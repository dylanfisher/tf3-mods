// Node check of the JS port against Lua's golden runs (data.js `golden`, export_names.py):
//   node plans/square_organic_towns/names/check_port.js
// The page runs the same check (Port check tab).
global.window = globalThis;
require('./data.js');
const G = require('./gen.js');
const P = require('./port_check.js');
const r = P.run(window.NAMEDATA, G);
for (const l of r.langs) console.log(`${l.lang.padEnd(5)} ${l.ok}/${l.n}` + (l.bad.length ? '  first diff: ' + JSON.stringify(l.bad[0]) : ''));
console.log(`total ${r.ok}/${r.n} names match Lua` + (r.parse.length ? `; parse diffs ${r.parse.length}: ${JSON.stringify(r.parse.slice(0, 3))}` : '; parser matches Lua on every entry'));
process.exit(r.ok === r.n && r.parse.length === 0 ? 0 : 1);
