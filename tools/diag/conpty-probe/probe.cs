// Runs a child under the inbox ConPTY (kernel32) and prints what ConPTY sends to the terminal, with control characters spelled out.
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

var command = args.Length > 0 ? string.Join(' ', args) : "node child.js";
CreatePipe(out var inRead, out var inWrite, IntPtr.Zero, 0);
CreatePipe(out var outRead, out var outWrite, IntPtr.Zero, 0);
if (CreatePseudoConsole(new Coord { X = 40, Y = 40 }, inRead, outWrite, 0, out var hpc) != 0) throw new Exception("CreatePseudoConsole");
nuint size = 0; InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
var attrs = Marshal.AllocHGlobal((int)size); InitializeProcThreadAttributeList(attrs, 1, 0, ref size);
UpdateProcThreadAttribute(attrs, 0, (IntPtr)0x00020016, hpc, (nuint)IntPtr.Size, IntPtr.Zero, IntPtr.Zero);
var si = new StartupInfoEx { AttributeList = attrs }; si.StartupInfo.cb = Marshal.SizeOf<StartupInfoEx>(); si.StartupInfo.dwFlags = 0x100;
if (!CreateProcessW(null, new StringBuilder(command), IntPtr.Zero, IntPtr.Zero, false, 0x00080000, IntPtr.Zero, Environment.CurrentDirectory, ref si, out var pi)) throw new Exception("CreateProcess " + Marshal.GetLastWin32Error());
inRead.Dispose(); outWrite.Dispose();
var output = new FileStream(outRead, FileAccess.Read);
var reader = new Thread(() =>
{
  var buffer = new byte[8192]; var start = Environment.TickCount64;
  try
  {
    while (true)
    {
      var n = output.Read(buffer, 0, buffer.Length); if (n == 0) break;
      var text = Encoding.UTF8.GetString(buffer, 0, n); var b = new StringBuilder();
      foreach (var c in text) b.Append(c switch { (char)27 => "ESC", (char)8 => "<BS>", (char)13 => "<CR>", (char)10 => "<LF>", (char)7 => "<BEL>", _ => c < 32 ? $"<{(int)c:X2}>" : c.ToString() });
      Console.WriteLine($"+{Environment.TickCount64 - start,5} ms  {b}");
    }
  }
  catch (IOException) { }
}) { IsBackground = true };
reader.Start();
WaitForSingleObject(pi.hProcess, 15000);
Thread.Sleep(300);
ClosePseudoConsole(hpc);
reader.Join(2000);

[DllImport("kernel32.dll", SetLastError = true)] static extern bool CreatePipe(out SafeFileHandle r, out SafeFileHandle w, IntPtr a, uint s);
[DllImport("kernel32.dll")] static extern int CreatePseudoConsole(Coord size, SafeFileHandle i, SafeFileHandle o, uint f, out IntPtr h);
[DllImport("kernel32.dll")] static extern void ClosePseudoConsole(IntPtr h);
[DllImport("kernel32.dll", SetLastError = true)] static extern bool InitializeProcThreadAttributeList(IntPtr l, int c, uint f, ref nuint s);
[DllImport("kernel32.dll", SetLastError = true)] static extern bool UpdateProcThreadAttribute(IntPtr l, uint f, IntPtr a, IntPtr v, nuint s, IntPtr p, IntPtr r);
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool CreateProcessW(string? app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, ref StartupInfoEx si, out ProcessInformation pi);
[DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);

struct Coord { public short X, Y; }
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct StartupInfo { public int cb; public IntPtr r, d, t; public int x, y, xs, ys, xc, yc, fa, dwFlags; public short sw, cb2; public IntPtr r2, i, o, e; }
struct StartupInfoEx { public StartupInfo StartupInfo; public IntPtr AttributeList; }
struct ProcessInformation { public IntPtr hProcess, hThread; public int pid, tid; }
