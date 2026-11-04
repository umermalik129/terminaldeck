// Writes like a TUI does: a prompt, then (after a pause) a mode switch plus SI, then a redraw at the same cell.
// argv[2] = "tty" (libuv console writes) or "fs" (raw byte writes to the handle, as some runtimes do).
const fs = require('fs');
const mode = process.argv[2] || 'tty';
process.stdout; // creating the TTY stream turns on VT processing for the console
const w = mode === 'fs' ? (s) => fs.writeSync(1, Buffer.from(s, 'utf8')) : (s) => process.stdout.write(s);
const step = (ms, s) => new Promise((r) => setTimeout(() => { w(s); r(); }, ms));
(async () => {
  await step(300, 'ab ');                          // cursor at column 4
  await step(400, '\x1b[?2004h\x0f');               // what the log showed after the pause
  await step(400, '\x1b[1;4Hc');                    // the app draws the next letter at column 4
  await step(400, 'd');
  await step(600, '');
})();
