// TEMPORARY local instrumentation (never commit): logs to %TEMP%\td-timing-<pid>.log
namespace TerminalDeck.App;

internal static class TdTiming
{
  private static readonly string path = Path.Combine(Path.GetTempPath(), $"td-timing-{Environment.ProcessId}.log");
  public static readonly System.Diagnostics.Stopwatch Clock = System.Diagnostics.Stopwatch.StartNew();
  public static double TitleBarMs; public static int TitleBarCalls;
  public static void Log(string message) { try { File.AppendAllText(path, $"{DateTime.Now:HH:mm:ss.fff} {message}\n"); } catch (IOException) { } }
  // Printable text becomes '.', so typed or shown words never reach the log; control
  // characters and escape sequences (cursor moves, erases) stay readable.
  public static string Mask(string text)
  {
    var b = new System.Text.StringBuilder(); var inEscape = false;
    foreach (var c in text)
    {
      if (c == (char)27) { b.Append("ESC"); inEscape = true; continue; }
      if (inEscape) { b.Append(c); if (char.IsLetter(c) || c == '~') inEscape = false; continue; }
      b.Append(c switch { (char)13 => "<CR>", (char)10 => "<LF>", (char)8 => "<BS>", (char)127 => "<DEL>", (char)9 => "<TAB>", ' ' => "_", _ => char.IsControl(c) ? $"<{(int)c:X2}>" : "." });
    }
    return b.ToString();
  }
  public static void Frames(string label, int count = 4)
  {
    var seen = 0; var start = Clock.Elapsed.TotalMilliseconds; TitleBarMs = 0; TitleBarCalls = 0;
    void Tick(object? s, object e)
    {
      seen++; Log($"  frame {seen} after {label}: +{Clock.Elapsed.TotalMilliseconds - start:F1} ms");
      if (seen >= count) Microsoft.UI.Xaml.Media.CompositionTarget.Rendering -= Tick;
    }
    Microsoft.UI.Xaml.Media.CompositionTarget.Rendering += Tick;
  }
}
