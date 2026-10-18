// Node check of the Name lab's TypeScript port (site/src/mods/square_organic_towns/namelab/gen.ts) against Lua's
// golden runs (data.json `golden`, written by export_names.py):
//   node plans/square_organic_towns/names/check_port.mjs
// Node 23.6+ runs the .ts modules directly (type stripping). The page runs the same check (Port check tab).
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const LAB = path.resolve(HERE, "../../../site/src/mods/square_organic_towns/namelab");
const G = await import(path.join(LAB, "gen.ts"));
const P = await import(path.join(LAB, "port-check.ts"));
const D = JSON.parse(fs.readFileSync(path.join(HERE, "data.json"), "utf8"));
const r = P.run(D, G);
for (const l of r.langs) console.log(`${l.lang.padEnd(5)} ${l.ok}/${l.n}` + (l.bad.length ? "  first diff: " + JSON.stringify(l.bad[0]) : ""));
console.log(`total ${r.ok}/${r.n} names match Lua` + (r.parse.length ? `; parse diffs ${r.parse.length}: ${JSON.stringify(r.parse.slice(0, 3))}` : "; parser matches Lua on every entry"));
process.exit(r.ok === r.n && r.parse.length === 0 ? 0 : 1);
