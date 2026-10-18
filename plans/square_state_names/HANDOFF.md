# State rollout handoff notes

Each state subagent appends a short section (newest last): what it changed in templates/tools, pitfalls, sources that worked, time sinks to avoid.

## Phase 0 (generator)

2026-10-08. G1, G2, G2b, G4, G5, G6, G9 and G10 are done; G7 is dropped (no API key, user decision). Washington was
regenerated: `towns.tsv` is unchanged. The generated mod changed in four places: the description (new climate bullet,
"ferry terminals" wording), the new `data/contested.lua`, the `state.lua` copy, and the runtime (contested check,
wider `normalize`). Tests: `make test MOD=mods/square_names_us_washington` (74 Lua tests) and `make test-tools`
(18 Python tests for `state_towns.py` and `gen_state_mod.py`, in `tests/tools/`).

### New `towns_config.json` keys (tools/state_towns.py)

- `regions`: an ordered list of polygons with vertices in `[lat, lon]` order. The first match wins.
  `"regions": [{"tag": "high", "polygon": [[37.0, -114.1], [37.0, -109.05], [33.6, -109.05], [34.55, -112.9]]}]`
- `defaultTag`: the tag for towns that fall outside every polygon. `"defaultTag": "desert"`
- How regions combine with `crest`: without `crest`, the region tag is the town's first tag ("side"), so rules can
  test it with `"side"`. With `crest`, the crest side comes first and the region tag is added second.
- `rules` now also take `latLt` and `lonGe`: `{"tag": "south", "latLt": 27.0, "side": "central"}`. Every condition
  in a rule must hold.
- `countyTags`: tags by county. A county name works with or without its suffix (" County", " Borough",
  " Census Area", …). `"countyTags": {"keys": ["Monroe"]}`
- `bigIncludesCdp`: CDPs can also get the "big" tag. `"bigIncludesCdp": true`
- `rename` also accepts a name that has an unknown LSAD suffix: map it to itself to silence the warning.
  `"rename": {"Athens-Clarke County": "Athens", "Urban Honolulu": "Honolulu"}`
- With `regions` set, the tool also writes `data/states/<key>/regions.geojson` (polygons plus town points coloured
  by first tag). Paste it into geojson.io to check the boundaries. GeoJSON stores points as `[lon, lat]`; the tool
  converts for you.

### New `state.lua` fields (tools/gen_state_mod.py)

- `asciiFallback = true`: set it in every new state (user decision). The generator transliterates every shipped
  name (Cañon City → Canon City, Utqiaġvik → Utqiagvik, okina dropped). The data files keep the official spelling.
- `minTowns = 250, minPool = 100, minStreetCities = 8`: lint floors. The defaults are 400 / 150 / 15, which
  Washington still uses. Add a comment explaining why. `minStreetCities` is new; add it whenever there are fewer
  than 15 street cities, since the user's target is 6–12.
- `regionLabels = { desert = "the low desert", high = "the high country" }`: names the regions in the
  description's climate sentence. A tag without a label prints as the raw tag, so label every weighted tag.
- `harborWord = "ports"`: the harbour noun (default "harbours"). The harbour sentence is dropped when there are no
  harbours.
- `streetFlavour = "saguaros, mesquite, mountain ranges and canals"`: the text in brackets after the generic street
  count. Leave it out to drop the brackets.
- `townFlavour = "small desert and mining towns"`: completes "from big cities to …" (default "small towns").
- The station and neighbourhood bullets and the intro list only the kinds that have data. Climates without
  positive weights are listed as "use the whole state".

### Per-state workflow

```
# 1. towns
make state-towns STATE=us_<state> ARGS=--fetch    # first time: Census files (+ county files when countyTags is set)
make state-towns STATE=us_<state>                 # iterate on towns_config.json; check warnings + regions.geojson
uv run tools/state_towns.py us_<state> --config /path/draft.json   # optional dry run, prints only
# 2. write streets.lua, cities.lua, state.lua (asciiFallback = true, minTowns/minPool/minStreetCities, wording fields)
make state-mod STATE=us_<state>
make state-mods                                   # regenerates EVERY state: contested.lua can change in older mods
make state-mods ARGS=--check
make check MOD=mods/square_names_us_<state>
make test MOD=mods/square_names_us_<state>
make validate MOD=mods/square_names_us_<state>
make test MOD=mods/square_names_us_washington     # WA again if its contested.lua changed
```

### Pitfalls

- **Run `make state-mods` (all states), not just `state-mod`.** Contested city keys are computed across every
  `data/states/*/cities.lua`, so a new state can change `contested.lua` in older mods (Washington included) and
  `--check` then reports them stale. While Washington is unreleased this needs no revision bump. Once a mod is
  released, any change to its generated files needs a `revision` bump and a changelog entry.
- The popest remote file has no leading zero for single-digit FIPS (`sub-est2023_2.csv` for Alaska), and its PLACE
  column isn't zero-padded either. Both are handled now. Before the fix, every Alaska city had population 0.
- The Census does not publish a 2020 place-to-county relationship file (`rel2020/place/` only has place20 to
  place10). Counties come from the 2020 block assignment file instead: each place goes to the county holding most of
  its blocks. That is a block count, not land area. A place created after 2020 has no county; the tool lists those
  places in one warning.
- An unknown LSAD suffix now prints `warn: unknown LSAD suffix …`. Fix it with a `rename` (to the short name, or to
  itself). " (balance)" is stripped first. Montana's "Butte-Silver Bow (balance)" counts as a known form;
  "Anaconda-Deer Lodge County" still warns, so give it a rename.
- A throwaway Alaska config (regions, a rule, `countyTags` for Kodiak/Aleutians, `cdpMinPop` 50) drafted 294 towns
  with no warnings. Juneau, Anchorage, Sitka and Wrangell came out clean, and Utqiaġvik keeps its ġ in the TSV
  (`asciiFallback` handles it at generation).
- `sn_logic.normalize` now strips quote marks before folding and uses ASCII classes (`[^0-9a-z#]`). `string.lower`
  and `%w` follow the C locale, and under lupa they treated bytes ≥ 128 as letters ("Hawaiʻi" came out as
  "hawai\234i"). Don't go back to `%w` there.
- `tests/run_tests.py` crashes with a `UnicodeDecodeError` (no test report) when a failing assertion message holds
  invalid UTF-8. Run with `-k` to find the test.
- Cover titles fit up to "New Hampshire" (the widest line 1 measured, 237 px clear of the diagonal). "Towns &
  Streets" on line 2 is the tightest line and the same on every state. `cover.js` is unchanged.

## Per-state notes (moved)

The per-state sections (Arizona to Hawaii, all 2026-10-08) moved verbatim to `HISTORY.md` ("moved from HANDOFF.md").
Read the relevant ones before adding a state: they hold the town-filter choices, region tricks and data sources
(GTFS feeds, ArcGIS neighbourhood layers, FAA NASR, the resumable Overpass `dump.py` recipe) and their pitfalls.
Lessons that apply to every new state:

- Overpass: dump every named highway once per city boundary (Alaska, New York, New Mexico notes), resumable, with
  relation ids from Nominatim; expect 429/504 and retry.
- Check every station and neighbourhood name against `towns.tsv` (Colorado, California notes); the lint misses it.
- A background subagent can verify rail, airports (FAA NASR) and ferries while the street dumps run.
- New `towns_config.json` keys added during the rollout: `incMinPop`, `keepTown` (Texas), per-region `cdpMinPop`
  (New York), `renameGeoid` (Hawaii); new `state.lua` field `introTowns` (Hawaii); `{{A_STATE_NAME}}` (Arizona).
