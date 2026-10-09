# New roundabout types: research (2026-10-07)

Constraints: base templates only, every node freed, pure updateFn. Checks may return only
"Enabled" or "Disabled", never "Hidden".

## Evidence
- Tags merge nodes across edgeLists and templates (base diverging diamond "sn-south",
  `street_constructions.script.lua:~795-900`). Edge direction sets the one-way direction.
- No minimum street edge length or curve radius is documented (`minCurveRadius` applies to tracks
  only, `tracksstreets.md:194`). Keep edges at least 10 m long and test.
- No base construction joins one-way and two-way edges at one tagged node. Our ring + arm merge
  already does this and works in game (phase 1 test).
- Tram:
  - `tram/tram_new` (tram-only, two-way, 11 m, from 1925).
  - `town_new_one_way_small_tram_electrified` (tram on lane offset +0.5), `town_new_small_tram_electrified`.
  - Or `params.tramTrackType = "ELECTRIC"` on an edgeList (`underground_station.script.lua:353`,
    `tram_depot.script.lua:183`).
- Traffic lights:
  - Field names: `trafficLightYes`/`trafficLightNo` (`{integer}`, `construction_util_serialized.d.tl:150-151`)
    vs the wiki's `trafficLightNodePreference = {{nodeIdx, "YES"}}` (`basics.md:690`). Nothing local
    uses either.
  - At runtime, lights are node data that only a proposal can set (`createTrafficLightProposal`,
    `api/engine/util.d.tl:965`).
  - Lights exist from 1950 (`traffic_light_config.res.lua`).
- `highway_new_small` drives at 27.8 m/s. For tight rings, `town_new_one_way_xsmall` (2×4 m, 14 m)
  is an option.

## Per type
| Type | Recipe | Spike | Value / effort |
| --- | --- | --- | --- |
| Splitter islands | Each arm: ring exit node at φ−δ, entry at φ+δ (CCW, mirrored for CW). One-way legs (`town_new_one_way_xsmall`) to a split node S at ringOuter + 15–20 m. The two-way arm runs from S. δ·r ≥ ~10 m. Optional triangle island. r ≥ 25 (4 arms), 30 (6). | 2 one-way + 1 two-way at S | high / low-med |
| Cut-through | Straight two-way edge between two opposite arm ring nodes (4 edges per node). Island becomes two half-moons (2 outlines, 2 colliders). r ≥ ~25. Only for layouts with an opposite pair (4, 6, T). | priority behaviour | med-high / low |
| Tram through centre | `tram_new` between opposite ring nodes. The ring and the arms on that axis use tram templates (or `tramTrackType`) so the tram can continue. Fallback: tunnel under the ring (`edgeType="TUNNEL"`, `tunnel_b_car.tunnel`). | tram_new ↔ ring junction | med / low |
| Tram ring | Tram-electrified one-way ring + tram arms | — | med / low |
| Magic (Swindon) | Central ring r ~22 (`town_new_one_way_small`, opposite direction). 5 satellite minis (`highway_new_small`, r ~11) at D ≥ 58 m. Each satellite: outward arm, two-way links to its neighbours (`town_new_xsmall`), one-way in/out pair to the centre ring. ~200 m across. Arms fixed at 5. | footprint overlap | high / med |
| Signalised | Set both candidate fields on different arms. If neither works, document using the traffic-light tool instead. Gate from 1950. | gates the type | high / low if it works |
| Turbo | Lane-split ring: at each entry a merge node splits into inner (continues) and outer (exits at next arm) single-lane edges, ≥ 9 m apart, no crossings. r ≥ 30, ≤ 5 arms. | AI behaviour | low / high (defer) |

Multi-lane (2/4) and single-lane (1) are already covered by the Lanes param.

## Proposed UI
- `sqrb_type`: Standard, Mini, Oval, Magic (+ Turbo later)
- `sqrb_splitter`: Off/On (not Magic)
- `sqrb_centre`: None / Road through / Tram through / Road + tram; through axis follows the layout
  (first opposite pair)
- `sqrb_tram_ring`: Off/On
- `sqrb_signals`: Off/Entries (spike first)
- Ranking: Splitter > Cut-through > Tram > Magic > Signals (spike early, cheap) > Turbo.
