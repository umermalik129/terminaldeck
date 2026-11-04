// One line per C0 control (plus DEL): "NN x<ctl>y". Shows which ones the console stores as a cell.
const codes = [];
for (let c = 1; c < 32; c++) if (![8, 9, 10, 13, 27].includes(c)) codes.push(c);
codes.push(127);
let text = '';
codes.forEach((c, i) => { text += `\x1b[${i + 1};1H${c.toString(16).padStart(2, '0')} x${String.fromCharCode(c)}y`; });
setTimeout(() => process.stdout.write(text), 300);
setTimeout(() => {}, 1200);
