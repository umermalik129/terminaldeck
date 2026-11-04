// Mimics Claude Code's input line after a pause: "ab " is typed, the app goes idle,
// its redraw sends ESC[?2004h plus SI, then the next letter is drawn where the SI went.
// A terminal in step with ConPTY ends with "ab c"; one column off ends with "abc".
const w = (s) => process.stdout.write(s);
const step = (ms, s) => new Promise((r) => setTimeout(() => { w(s); r(); }, ms));
(async () => {
  await step(200, 'CELLTEST ab ');
  await step(500, '\x1b[?2004h\x0f');
  await step(500, '\bc');
  await step(300, ' END\r\n');
})();
