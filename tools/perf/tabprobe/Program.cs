// Measures what a tab switch looks like on screen. Captures the target window with
// Windows.Graphics.Capture (every frame DWM composes, with its QPC timestamp),
// clicks tab chips through UI Automation, and reports per switch when the tab
// strip and the content area first changed and when the content settled.
//   TabProbe --pid <TerminalDeck.App pid> --sequence 1,0,2,0,3 [--rounds 3] [--settle 1200]
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Windows.Automation;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;
using Windows.Graphics.Imaging;

static string Arg(string[] a, string name, string fallback) { var i = Array.IndexOf(a, name); return i >= 0 && i + 1 < a.Length ? a[i + 1] : fallback; }
var pid = int.Parse(Arg(args, "--pid", "0"));
var sequence = Arg(args, "--sequence", "1,0").Split(',').Select(int.Parse).ToArray();
var rounds = int.Parse(Arg(args, "--rounds", "3"));
var settleMs = int.Parse(Arg(args, "--settle", "1200"));
var verbose = args.Contains("--verbose");

var process = Process.GetProcessById(pid);
var hwnd = process.MainWindowHandle;
if (hwnd == IntPtr.Zero) throw new InvalidOperationException("No main window");
Native.GetWindowRect(hwnd, out var rect);
int width = rect.Right - rect.Left, height = rect.Bottom - rect.Top;
Console.WriteLine($"window {width}x{height} at {rect.Left},{rect.Top}");

// Tabs: buttons in the top strip that are not window or strip controls, left to right.
var root = AutomationElement.FromHandle(hwnd);
string[] skip = ["Minimize", "Maximize", "Restore", "Close", "Toggle sidebar", "New terminal tab", "New browser tab"];
var tabs = root.FindAll(TreeScope.Descendants, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button)).Cast<AutomationElement>()
  .Select(e => (e, r: e.Current.BoundingRectangle, n: e.Current.Name))
  .Where(t => !t.r.IsEmpty && !double.IsInfinity(t.r.X) && t.r.Y - rect.Top < 40 && t.r.Height < 30 && !skip.Contains(t.n) && !t.n.StartsWith("Close ", StringComparison.Ordinal))
  .OrderBy(t => t.r.X).ToArray();
for (var i = 0; i < tabs.Length; i++) Console.WriteLine($"tab {i}: {tabs[i].n}");

// Regions in window pixels: the tab strip (top band right of the sidebar) and
// the content (below the strip). Sampled every 2nd pixel as luma.
var strip = new Region("strip", 280, 2, width - 560, 36);
var content = new Region("content", 280, 44, width - 300, height - 60);

var d3d = Native.CreateDevice();
var item = Native.CreateItemForWindow(hwnd);
Console.WriteLine($"capture item {item.Size.Width}x{item.Size.Height}");
var pool = Direct3D11CaptureFramePool.CreateFreeThreaded(d3d, DirectXPixelFormat.B8G8R8A8UIntNormalized, 3, item.Size);
var frames = new ConcurrentQueue<Frame>();
var arrived = 0; var failures = 0;
var idleMs = int.Parse(Arg(args, "--idle", "0"));
byte[]? previous = null; var idleLog = new ConcurrentQueue<string>();
pool.FrameArrived += (sender, _) =>
{
  Interlocked.Increment(ref arrived);
  try
  {
    using var frame = sender.TryGetNextFrame();
    if (frame is null) return;
    var at = frame.SystemRelativeTime.TotalMilliseconds;
    var (pixels, w, h) = Native.Read(frame.Surface);
    if (idleMs > 0)
    {
      // Which pixels changed since the previous frame, as a bounding box.
      if (previous is { } last && last.Length == pixels.Length)
      {
        int minX = w, minY = h, maxX = -1, maxY = -1, changedPixels = 0;
        for (var y = 0; y < h; y++)
          for (var x = 0; x < w; x++)
          {
            var i = (y * w + x) * 4;
            if (Math.Abs(pixels[i] - last[i]) + Math.Abs(pixels[i + 1] - last[i + 1]) + Math.Abs(pixels[i + 2] - last[i + 2]) <= 6) continue;
            changedPixels++; minX = Math.Min(minX, x); maxX = Math.Max(maxX, x); minY = Math.Min(minY, y); maxY = Math.Max(maxY, y);
          }
        idleLog.Enqueue(changedPixels == 0 ? $"{at:F1} identical" : $"{at:F1} changed {changedPixels} px in x {minX}-{maxX}, y {minY}-{maxY}");
      }
      previous = pixels;
      return;
    }
    frames.Enqueue(new Frame(at, strip.Sample(pixels, w, h), content.Sample(pixels, w, h)));
  }
  catch (Exception ex) { if (Interlocked.Increment(ref failures) <= 3) Console.WriteLine("frame failed: " + ex.GetType().Name + ": " + ex.Message); }
};
var session = pool.CreateCaptureSession(item);
session.StartCapture();
if (idleMs > 0)
{
  Thread.Sleep(idleMs);
  session.Dispose(); pool.Dispose();
  var lines = idleLog.ToArray();
  Console.WriteLine($"idle {idleMs} ms: {arrived} frames, {lines.Count(l => l.EndsWith("identical"))} identical to the one before");
  foreach (var group in lines.Where(l => !l.EndsWith("identical")).Select(l => l[(l.IndexOf(' ') + 1)..]).GroupBy(l => l).OrderByDescending(g => g.Count()).Take(12))
    Console.WriteLine($"  {group.Count(),4} x {group.Key}");
  return;
}
Thread.Sleep(800);
Console.WriteLine($"frames after start: arrived {arrived}, kept {frames.Count}");

static double Now() => Stopwatch.GetTimestamp() * 1000.0 / Stopwatch.Frequency;
var results = new List<Result>();
for (var round = 0; round < rounds; round++)
  foreach (var target in sequence)
  {
    if (target >= tabs.Length) throw new ArgumentException($"no tab {target}");
    Thread.Sleep(700);
    var t0 = Now();
    ((InvokePattern)tabs[target].e.GetCurrentPattern(InvokePattern.Pattern)).Invoke();
    var returned = Now() - t0;
    Thread.Sleep(settleMs);
    var all = frames.ToArray();
    var before = all.LastOrDefault(f => f.At < t0);
    var after = all.Where(f => f.At >= t0).ToArray();
    if (before is null || after.Length == 0) { Console.WriteLine($"-> tab {target}: no frames (before={before is not null}, after={after.Length})"); continue; }
    var final = after[^1];
    double? First(Func<Frame, byte[]> pick) => after.FirstOrDefault(f => Diff(pick(f), pick(before)) > 0.002)?.At - t0;
    double? Settle(Func<Frame, byte[]> pick)
    {
      if (Diff(pick(final), pick(before)) <= 0.002) return null;
      for (var i = 0; i < after.Length; i++) if (after.Skip(i).All(f => Diff(pick(f), pick(final)) <= 0.002)) return after[i].At - t0;
      return null;
    }
    var r = new Result(target, returned, First(f => f.Strip), First(f => f.Content), Settle(f => f.Content), after.Count(f => f.At - t0 < 500), Gaps(after.Where(f => f.At - t0 < 500).Select(f => f.At).Prepend(t0).ToArray()));
    results.Add(r);
    Console.WriteLine($"-> tab {target}: invoke {r.Invoke,5:F1} ms | strip {Fmt(r.Strip)} | content first {Fmt(r.ContentFirst)} settled {Fmt(r.ContentSettled)} | frames<500ms {r.Frames} | max gap {r.MaxGap,5:F1} ms");
    if (verbose)
      foreach (var f in after.Where(f => f.At - t0 < 600))
        Console.WriteLine($"     +{f.At - t0,6:F1}  strip vs before {Diff(f.Strip, before.Strip):P1}  content vs before {Diff(f.Content, before.Content):P1}  vs final {Diff(f.Content, final.Content):P1}");
    while (frames.Count > 400 && frames.TryDequeue(out _)) { }
  }
session.Dispose(); pool.Dispose();

var changed = results.Where(r => r.ContentSettled is not null).ToArray();
if (changed.Length > 0)
{
  double P(IEnumerable<double> xs, double q) { var s = xs.OrderBy(x => x).ToArray(); return s[(int)Math.Min(s.Length - 1, Math.Floor(q * s.Length))]; }
  Console.WriteLine($"summary over {changed.Length} switches with a content change:");
  Console.WriteLine($"  content settled  median {P(changed.Select(r => r.ContentSettled!.Value), 0.5),6:F1} ms   p90 {P(changed.Select(r => r.ContentSettled!.Value), 0.9),6:F1} ms   max {changed.Max(r => r.ContentSettled!.Value),6:F1} ms");
  Console.WriteLine($"  content first    median {P(changed.Select(r => r.ContentFirst ?? 0), 0.5),6:F1} ms");
  Console.WriteLine($"  strip first      median {P(changed.Select(r => r.Strip ?? 0), 0.5),6:F1} ms");
  Console.WriteLine($"  UIA invoke call  median {P(changed.Select(r => r.Invoke), 0.5),6:F1} ms");
}

static string Fmt(double? v) => v is { } x ? $"{x,6:F1} ms" : "     -   ";
static double Gaps(double[] times) { var g = 0.0; for (var i = 1; i < times.Length; i++) g = Math.Max(g, times[i] - times[i - 1]); return g; }
static double Diff(byte[] a, byte[] b)
{
  if (a.Length != b.Length) return 1;
  var n = 0; for (var i = 0; i < a.Length; i++) if (Math.Abs(a[i] - b[i]) > 10) n++;
  return (double)n / a.Length;
}

record Frame(double At, byte[] Strip, byte[] Content);
record Result(int Target, double Invoke, double? Strip, double? ContentFirst, double? ContentSettled, int Frames, double MaxGap);
record Region(string Name, int X, int Y, int W, int H)
{
  public byte[] Sample(byte[] bgra, int width, int height)
  {
    var cols = W / 2; var rows = H / 2; var output = new byte[cols * rows];
    for (var r = 0; r < rows; r++)
      for (var c = 0; c < cols; c++)
      {
        int x = X + c * 2, y = Y + r * 2;
        if (x >= width || y >= height) continue;
        var i = (y * width + x) * 4;
        output[r * cols + c] = (byte)((bgra[i] * 29 + bgra[i + 1] * 150 + bgra[i + 2] * 77) >> 8);
      }
    return output;
  }
}

static class Native
{
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("d3d11.dll")] static extern int D3D11CreateDevice(IntPtr adapter, int driverType, IntPtr software, uint flags, IntPtr levels, uint count, uint sdk, out IntPtr device, out int level, out IntPtr context);
  [DllImport("d3d11.dll")] static extern int CreateDirect3D11DeviceFromDXGIDevice(IntPtr dxgiDevice, out IntPtr graphicsDevice);
  [ComImport, Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IGraphicsCaptureItemInterop
  {
    IntPtr CreateForWindow([In] IntPtr window, [In] ref Guid iid);
    IntPtr CreateForMonitor([In] IntPtr monitor, [In] ref Guid iid);
  }
  static IntPtr device, context, staging; static int stagingW, stagingH;
  static readonly object gate = new();
  public static IDirect3DDevice CreateDevice()
  {
    Marshal.ThrowExceptionForHR(D3D11CreateDevice(IntPtr.Zero, 1, IntPtr.Zero, 0x20, IntPtr.Zero, 0, 7, out device, out _, out context));
    var iid = new Guid("54ec77fa-1377-44e6-8c32-88fd5f44c84c");
    Marshal.ThrowExceptionForHR(Marshal.QueryInterface(device, ref iid, out var dxgi));
    Marshal.ThrowExceptionForHR(CreateDirect3D11DeviceFromDXGIDevice(dxgi, out var inspectable));
    Marshal.Release(dxgi);
    var result = WinRT.MarshalInterface<IDirect3DDevice>.FromAbi(inspectable); Marshal.Release(inspectable); return result;
  }
  [ComImport, Guid("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IDirect3DDxgiInterfaceAccess { IntPtr GetInterface([In] ref Guid iid); }
  [StructLayout(LayoutKind.Sequential)] struct TextureDesc { public uint Width, Height, MipLevels, ArraySize, Format, SampleCount, SampleQuality, Usage, BindFlags, CpuAccessFlags, MiscFlags; }
  [StructLayout(LayoutKind.Sequential)] struct Mapped { public IntPtr Data; public uint RowPitch, DepthPitch; }
  // ID3D11Texture2D::GetDesc = 10, ID3D11Device::CreateTexture2D = 5,
  // ID3D11DeviceContext::Map = 14, Unmap = 15, CopyResource = 47.
  public static unsafe (byte[] Pixels, int Width, int Height) Read(IDirect3DSurface surface)
  {
    var access = WinRT.CastExtensions.As<IDirect3DDxgiInterfaceAccess>(surface);
    var textureIid = new Guid("6f15aaf2-d208-4e89-9ab4-489535d34f9c");
    var texture = access.GetInterface(ref textureIid);
    try
    {
      lock (gate)
      {
        TextureDesc desc;
        ((delegate* unmanaged[Stdcall]<IntPtr, TextureDesc*, void>)(*(IntPtr**)texture)[10])(texture, &desc);
        if (staging == IntPtr.Zero || stagingW != desc.Width || stagingH != desc.Height)
        {
          if (staging != IntPtr.Zero) Marshal.Release(staging);
          var copy = desc; copy.Usage = 3; copy.BindFlags = 0; copy.CpuAccessFlags = 0x20000; copy.MiscFlags = 0; copy.MipLevels = 1; copy.ArraySize = 1; copy.SampleCount = 1; copy.SampleQuality = 0;
          IntPtr created;
          Marshal.ThrowExceptionForHR(((delegate* unmanaged[Stdcall]<IntPtr, TextureDesc*, IntPtr, IntPtr*, int>)(*(IntPtr**)device)[5])(device, &copy, IntPtr.Zero, &created));
          staging = created; stagingW = (int)desc.Width; stagingH = (int)desc.Height;
        }
        ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, IntPtr, void>)(*(IntPtr**)context)[47])(context, staging, texture);
        Mapped mapped;
        Marshal.ThrowExceptionForHR(((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, uint, int, uint, Mapped*, int>)(*(IntPtr**)context)[14])(context, staging, 0, 1, 0, &mapped));
        var pixels = new byte[stagingW * stagingH * 4];
        for (var y = 0; y < stagingH; y++) Marshal.Copy(mapped.Data + (int)(y * mapped.RowPitch), pixels, y * stagingW * 4, stagingW * 4);
        ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, uint, void>)(*(IntPtr**)context)[15])(context, staging, 0);
        return (pixels, stagingW, stagingH);
      }
    }
    finally { Marshal.Release(texture); }
  }
  public static GraphicsCaptureItem CreateItemForWindow(IntPtr hwnd)
  {
    var factory = WinRT.ActivationFactory.Get("Windows.Graphics.Capture.GraphicsCaptureItem");
    var interop = factory.AsInterface<IGraphicsCaptureItemInterop>();
    var iid = new Guid("79C3F95B-31F7-4EC2-A464-632EF5D30760");
    var pointer = interop.CreateForWindow(hwnd, ref iid);
    var item = GraphicsCaptureItem.FromAbi(pointer); Marshal.Release(pointer); return item;
  }
}
