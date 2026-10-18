# US State Names series: next states and rollout

Status: rollout done 2026-10-08 (all 12 states built; all 13 published, revision 6 in the repo since 2026-10-10).
No further state is planned. Kept here: the prerequisite, name-set conflicts, the repeatable per-state checklist (§5), the data-quality
gate (§7) and the user decisions (§9). The ranked shortlist, batches, per-state recipes, generator gaps table, phases
and open decisions moved to `HISTORY.md` ("moved from NEXT_STATES.md"). Still open from the gaps table: G4 (font
check for ñ, ġ, ʻ) and G8 (station suffix), see PLAN.md "Open work".

**Prerequisite for every new state:** finish Washington's in-game run (`TESTING.md` Phase 1 + 2). The station-suffix
answer (Phase 1 item 5) and a font check (gap G4, in `HISTORY.md` "4. Template and generator gaps") decide how the rail data and non-ASCII names are written.
Every new state depends on both, so no new state's data is final until they're answered.

## Conflicts with other name sets (from §1)

### Existing mod.io name sets (conflict check)

The slug survey (mod.io search and API need JS or a key, so slugs were probed) found a "**<State> Names**" mod for
**all 50 states**, all described as "<State> town and street names". This is almost certainly AZ-Ranger's batch, ids
6418624 (Alaska, "Alaskan Names") and 6424725–6430129. Only Washington's author and contents are confirmed: the local
copy has 635 towns and 84 streets, set name "Washington", at `content/names/washington/`. Utah has a second, curated
set ("Utah Names", 154 towns, 582 streets) by an unknown author.

What this means:
- No state is uncontested. What sets ours apart is everywhere: real streets per city, real stations, climate-aware towns.
  The description already leads with these. Keep that order.
- Paths: ours are `content/names/<modId>/…` and `content/<modId>/…`, so they never clash with `content/names/<state>/`.
- Picker labels: theirs show as bare "<State>", ours as "<State> (Towns & Streets)", so they're distinct.
- Add the WA-style note to every state (`notes` in `state.lua`): "Not affiliated with the "<State> Names" mod; all lists
  here are our own." Alaska's is "Alaskan Names".
- Never open or derive from their lists, same rule as research.md §5.3. Our sources are Census, OSM (check only) and
  official agency lists.

### Overlap between our own state mods

The owner rule (`sn_logic.isActive`):
- **The game uses a series set** (`nameList` starts with `square_names_us_`): only the mod that owns it renames.
  "Portland" on an Oregon map gets Oregon streets even with Maine active. **No conflict.**
- **The game uses a base or third-party set**: every active series mod renames towns found in its own `cities.lua`.
  For a shared key (Portland OR/ME, Springfield IL/MA/MO/OR, Aurora CO/IL, Glendale AZ/CA, Pasadena CA/TX,
  Arlington TX/VA, Jacksonville FL/NC, Lakewood CO/WA/OH, Richmond CA/VA, Albany NY/OR/GA, Salem OR/MA), both mods
  queue the same stop. The second usually skips because of the "renamed since the build" check. If both send in the
  same window, the last one lands. Either way the stop gets a real name, but **a town can end up mixing two cities'
  streets** (stop 1 Oregon, stop 2 Maine).
- Proposed fix (G9): the generator knows every state's `cities.lua`, so for each contested key it records the
  winner (the bigger city by Census population) in every mod involved. At runtime the losing mod skips that city
  when the winner's modId shows up in `getModParams()`. Older mods learn about new contests when they're regenerated
  (Phase 4 rule: a revision bump each time).
- Only `cities.lua` keys matter. Shared **town** names (Miami AZ, Duluth WA) are harmless.

## 5. Per-state checklist (repeatable)

Copy into `plans/square_state_names/states/<key>.md` and tick it off. `<key>` = `us_<state>`, modId =
`square_names_us_<state>`.

1. **Data: towns**
   - Write `data/states/<key>/towns_config.json` (FIPS, postal, region polygons and `countyTags`, CDP filters).
   - Run `make state-towns STATE=<key> ARGS=--fetch`, then `make state-towns STATE=<key>`.
   - Check `regions.geojson` on a map, review oddly named CDPs, iterate on the config (never on the TSV).
2. **Data: streets and cities**
   - Write `streets.lua` (generic, ≥ 120) and `cities.lua` (≥ 10 cities with streets unless the state is waived,
     stations for the major ones).
   - Give every entry a source: an Overpass hit for streets, an operator list for stations.
   - Unsure entries go to the state's `data_review.md` section, not into the data.
3. **Meta:** write `state.lua` (names, climates, notes incl. "<State> Names" non-affiliation, accent, `minTowns` if
   waived, revision 1, changelog "unreleased").
4. **Generate:** `make state-mod STATE=<key>`, then `make state-mods ARGS=--check` (clean, WA unchanged).
5. **Checks:** `make check MOD=mods/square_names_us_<state>`, `make test MOD=…`, `make validate MOD=…` (the cover
   warning is OK until step 7).
6. **Flag:**
   - `make flags ARGS='--lookup "Flag of <State>.svg" --key <key>'`, pin it in `SOURCES.json` (PD/CC0 only), then
     `make flags STATE=<key>`.
   - Check the sanitizer output (element counts).
7. **Cover:** add a `Square.stateCover({...})` entry in `branding/mods.js` (aspect from SOURCES.json), check it in
   `branding/index.html`, run `make covers MOD=mods/square_names_us_<state>`, add the README palette row.
8. **In-game test** (user): `make link`, then the `TESTING.md` Phase 1 items with the state's set and cities:
   - one new game per mapped climate
   - stops in two big cities
   - one station per kind that has data
   - the non-ASCII check (G4) if the state has such names
   - the two-state check (Phase 2 #12) with Washington active.
9. **Slides:** captures into `plans/square_names_us_<state>/shots/`, add a `Square.slides(...)` entry in
   `branding/shots.js`, run `make shots MOD=…`.
10. **Release:** set the changelog date in `state.lua`, regenerate, run `make validate` with no warnings. The user
    uploads via Mod Hub → My Mods.

## 7. Data-quality gate (applies to every state, enforced in review)

- **Towns:** Census places only. Renames only to the form people actually use ("Urban Honolulu" → "Honolulu"), each
  with a comment in `towns_config.json`. No invented places, no military bases or tribal-community CDP names
  (follow WA's `excludeCdp` pattern; tribal *towns* that are ordinary Census places stay).
- **Streets, neighbourhoods and stations:** each entry must be real and current, with a source: an Overpass hit inside
  the city, the operator's or agency's station list, the FAA name, or the city's neighbourhood map. Prefer the signed
  form. Leave directional prefixes out unless they're part of how the street is known (WA rule). No slash names, no
  trademarks or sponsor names.
- **Uncertain entries go to the state's section of `data_review.md`** with the reason. Never ship "probably". Examples:
  a stop not open yet, a name with an unclear official form, a facility outside the city players expect.
- **Generic street pools** must be clearly generic (trees, terrain, numbered streets) and need no per-name fact check,
  but no real person's name unless it's a common street name (Washington, Lincoln, MLK).
- **Before release:** a second pass by a fresh subagent that only checks sources (spot-check 20 % of entries, all
  stations). Any miss sends the whole list back for checking.

## 9. User decisions (2026-10-08)

- **All 12 states now**, sequentially, one subagent per state, in rank order: Arizona, Florida, Colorado, California,
  Texas, Alaska, New York, Minnesota, New Mexico, Oregon, Pennsylvania, Hawaii. A Phase 0 subagent (generator
  fixes) runs first. Each subagent appends what it learned to `HANDOFF.md` for the next one.
- **Keep data reasonable**: just enough names to feel real. Towns: roughly 250–500 per state (fewer for small states,
  lint floors per state). Cities: ~6–12 with streets (15–30 streets each), stations for the major ones. No Census API
  key; 2010 CDP counts + `keepCdp` are fine. Thin states (Alaska, Hawaii, New Mexico) are OK if the description is honest.
- **Accents: plain ASCII** for now (`asciiFallback` on for every state; Cañon City → Canon City). Revisit after the
  font check.
- **Rail lists: mainline/commuter first, then light rail.**
- **Shared city keys: the bigger city wins** (G9, built in Phase 0; Washington regenerated too).
- **Scope per state: data + generated mod + checks + flag + cover.** In-game tests, slides and upload stay with the user.
