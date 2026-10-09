> **Superseded (2026-10-08)** by `plans/square_state_names/PLAN.md` (US State Names series); kept for history.

# Town Street Names (`square_town_street_names`): plan (draft)

Towns whose name is in a street pack get **their own real street names** for new street stops. A stop in
"Seattle" becomes "Pike Street" or "Pine Street", and a stop in "Tacoma" becomes "Pacific Avenue". Every other town keeps the
default names from the selected name set. The first pack covers Washington cities, to go with the subscribed Washington Names
set (`arizonaranger_washington_names`).

**Status (2026-10-08):** offline research done (`research.md`). Probe built (`mods/square_town_street_names_probe`,
`PROBE.md`) and not yet run. The design below has open options (marked **D1..D7**) that the probe run decides.

## Why a game script

A name set can't do this: `streetNamesScript` gets only `{lang, num}` and never a town (research.md §1). So the mod
lets the engine name a new stop as usual, then **renames it right after it is built** with
`api.cmd.makeEntitySetNameCmd`. auto_line_namer_1 does the same for lines (research.md §4).

## Decisions (draft)

| Topic | Decision |
|---|---|
| What gets renamed | **New edge-object street stops only** ("Road Stop", "Two-Sided Road Stop" and their eras; any station whose station has an EDGE_OBJECT component). Construction stations (bus/tram station, train station) keep "{townName} Station"-style names. Maybe later as an option, see D6. |
| When | Only stops that appear within a few seconds of a **player-initiated** `onPostBuildProposal` (`param[4] == true`). Never existing stops and never anything on load. A save that already has stops is untouched. |
| Detection | `onPostBuildProposal` only sets a flag (no state writes, no commands; memory `gs-no-sendcommand-in-build-events`). The next `update` diffs `getEntitiesWithComponent(STATION_GROUP)` against the known set. Post-event ids are placeholders (`-400000000+n`), so the event can't name the entity (research.md §4). Baseline storage is D3. |
| Town | `stationSystem.getTown(station)`. Fallback `util.town.getClosestTown(pos)` within a radius (D4). No town → leave the default. Look up the town's **current** name at naming time, so a town renamed to "Seattle" gets Seattle streets from then on. |
| Rename target | The **station group** (what the player renames in the window, research.md §2), unless the probe shows the station NAME is what's displayed (D2). |
| Player-renamed stops | Never touched: only brand-new groups are renamed, once, within seconds of the build. Extra guard: rename only if the group's current name still equals the default name seen when it was detected. Also skip if the name changed between detection and send. |
| Repeats within a town | Collect the names in use in that town: `getTown2StationsMap()[town]` → station groups → `getEntityName`, compared without the engine's suffix. Pick the first unused name in the town's (shuffled) list. No saved state needed. When all names are used, reuse with a suffix (D5). |
| Shuffle | Per-town order = list shuffled with a seed from the town entity id, so two playthroughs differ and one save stays stable. Or plain list order (most famous first) as a param. |
| Name matching | Town key = name lower-cased, trimmed, inner whitespace collapsed, ASCII-folded for common accents (e.g. "Coeur d’Alene"). Packs may list extra spellings in `aliases`. Exact match only, never a substring match ("Port Seattle" isn't "Seattle"). |
| Saves | `severityAdd: None`, `severityRemove: None`, `cosmetic: true`. Names are plain NAME values. Removing the mod leaves them and stops renaming. Lazy subscription in `update`. No `init` events relied on. Saved state: none, or the known-group baseline (D3). Never in the map editor (`getModParams()[""].isMapEditor`, as refund.script.tl `isMapEditor`). |
| Params | `enabled` stays implicit (disable the mod). Possible params: "Order: shuffled / list order"; D6 "Also rename bus/tram stations: off / on". Numbers as doubles (`10.0`) (memory `modjson-param-numbers-doubles`). |

## Data format: street packs

One Lua module per pack under `content/town_streets/packs/`. Each returns a plain table, so packs are easy to review
and to contribute:

```lua
-- content/town_streets/packs/usa_washington.lua
return {
	id = "usa_washington",
	towns = {
		["Seattle"] = {
			aliases = {},
			streets = { "Pike Street", "Pine Street", "Union Street", "University Street", "Seneca Street",
				"Spring Street", "Madison Street", "Marion Street", "Columbia Street", "Cherry Street",
				"James Street", "Yesler Way", "Jackson Street", "Denny Way", "Mercer Street", "Broadway",
				"Westlake Avenue", "Eastlake Avenue", "Rainier Avenue", "Aurora Avenue", "Market Street",
				"Fremont Avenue", "Stone Way", "Roosevelt Way", "Beacon Avenue", "Delridge Way",
				"California Avenue", "Fauntleroy Way", "Queen Anne Avenue", "Leary Way", ... },
		},
		["Tacoma"] = { streets = { "Pacific Avenue", "Broadway", "Commerce Street", "Market Street",
			"Tacoma Avenue", "Division Avenue", "6th Avenue", "Puyallup Avenue", "Ruston Way", ... } },
		["Spokane"] = { streets = { "Riverside Avenue", "Sprague Avenue", "Division Street", "Monroe Street", ... } },
		-- Bellevue, Everett, Olympia, Yakima, Bellingham, Vancouver, ... (aim: the ~20 largest WA cities,
		-- 25-60 streets each, only well-known, verifiable street names)
	},
}
```

- `content/town_streets/packs.lua` lists the pack modules to load (`ug_require`). Later towns are merged into
  earlier ones by key, and lists are concatenated without duplicates.
- Later packs (other US states, UK, German cities) are just more files. Optional phase 4: let other mods register
  packs.
- Validation in tests: no empty lists, no duplicate streets per town, every name is a non-empty UTF-8 string of at
  most 40 bytes, and keys are unique after normalization.

## Naming algorithm (pure, unit-tested: `tsn_logic.lua`)

```
nameFor(townName, defaultName, namesInUse, pack, order) -> newName | nil
  list  = pack[normalize(townName)]            -- nil -> return nil (town keeps the name-set pool)
  base, suffix = splitSuffix(defaultName)      -- D1: keep " East"/" #2" style suffixes or not
  first unused name in list (order) not in namesInUse (compared on base names)
  all used -> reuse with suffix                -- D5
```

Two variants. D1 decides between them.
- **V1 "next unused"**: every new stop takes the next unused street. Simple, and gives the most variety.
- **V2 "consistent mapping"**: only if the probe shows that same-street stops share the default stem (e.g.
  "Probe Street 03", "Probe Street 03 East"). Map each default stem to one town street (stem → street in a small
  per-town table, rebuilt from the existing names), and keep the engine's suffix. Stops on one street then share
  one real name, which reads better on a line.

## Decision points the probe settles

| ID | Question | Probe evidence (PROBE.md) | Default if unclear |
|---|---|---|---|
| D1 | Default stop names are pool street names; do same-street stops share a stem with suffixes? | step 3 `NEW ... name=` | V1 next-unused |
| D2 | Which entity to rename (group / station stem / forceSameEntity), and is the result what the UI shows? | step 9-10 `rename #n verify` + UI | group |
| D3 | Baseline in saved state or memory only? Depends on how often the Lua state is recreated (`init Lua state` lines) and whether build event + update share a state (`via postBuild` vs `via poll`). | steps 2-9 | memory-only baseline + "recent player build" window. Re-baseline silently on a new Lua state. Missing a stop leaves a default name, which is harmless. |
| D4 | `getTown` valid right after the build? Value outside towns? Fallback radius? | steps 3, 5 `town:` | getTown, else no rename |
| D5 | Duplicate names: does the engine suffix them itself ("#2") or accept duplicates? | step 9 second "Pike Street" | reuse the list from the top and let the engine add its own suffix; if it accepts duplicates, append " #2" ourselves |
| D6 | Rename construction stations (bus/tram stations) too? They are "{town} Station"-style today. | step 6 | no |
| D7 | NAME component presence = custom name? If yes, use it as an extra player-rename guard. | step 7 `name change ... (NAME no) -> (NAME yes)` | not used |

## Architecture

```
mods/square_town_street_names/
  mod.json (cosmetic, severities None), _metadata/{modinfo.json, description.html, 0.png}
  content/town_streets/
    town_streets.gs.lua         updateScript + handleEventScript (no GUI scripts needed)
    town_streets.script.lua     game script: subscribe lazily, flag on player post-build, scan + rename in update;
                                exports via data() (memory script-lua-exports-via-data); pcall everywhere, log once
    tsn_logic.lua               pure: normalize, splitSuffix, nameFor, pack merge (offline-tested)
    packs.lua, packs/usa_washington.lua
tests/square_town_street_names/test_logic.lua, test_packs.lua, test_script.lua (fake world, like the probe test)
```

Plain Lua (pre-5.3: no `//`, `math.tointeger`, `utf8.*`; memory tf3-lua-runtime-pre53). The scan only runs when a
post-build flag is set and at most every 1 s, so there is no per-tick `state:get()`. One `getEntitiesWithComponent`
call per scan.

## Phases

### Phase 0: probe (done in code, needs a run)
Run PROBE.md, fill in "Results", and settle D1-D7 here.

### Phase 1: working mod
Logic module + tests, Washington pack (Seattle, Tacoma, Spokane, Bellevue, Everett, Olympia at least), game script
with detection and rename per D2/D3, skip the map editor. `make check/test/validate` clean. TESTING.md: new game
with the Washington Names set, build stops in Seattle/Tacoma/a generic town; add the mod to an existing save
(no existing stop renamed); remove it again (names stay, no warning beyond None).

### Phase 2: edge cases
Two-sided stops, stops joining an existing group (must not rename the old group), town renamed before and after a
build, stop outside towns, undo/bulldoze-rebuild, fast building of many stops (one scan, many renames, no repeats
within a scan: update `namesInUse` as names are assigned), name-set pools that already contain the town's
real street names.

### Phase 3: release
Pack review (spelling, only real streets), cover (`branding/mods.js`, distinct accent, e.g. a street sign
pictogram), description with Changelog, `revision` 1, upload.

### Phase 4 (optional)
More packs (other US states, UK, DE). A pack-registration hook for other mods. An option to also rename
construction stations "{Town} {Street} Station".
