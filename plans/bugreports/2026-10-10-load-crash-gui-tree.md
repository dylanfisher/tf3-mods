# Crash on the first frame after loading a save with many GUI mods (Mac, build 40420)

**Build:** 40420 (commit 32c4e2d8), Steam, macOS 26.6.2, Apple M5 Max, MoltenVK (default driver)

**What happens:** Loading a save crashes on the first GUI frame after the game is ready. The log always ends with
`ScriptComponentRoot: Collect Lua Garbage: … KB -> … KB`, then the minidump callback within about 0–1 s, then
"Possible hang detected" / ShowErrorBox. The crash is intermittent: the same mod set sometimes loads fine.

**Stack (identical in every dump):** an uncaught C++ exception from a std::string constructor, inside a recursive tree walk:

```
#7  libc++abi __cxa_throw
#8  TransportFever3 +0x16a50  (throw helper)
#10 TransportFever3 +0x3d16c  (std::string init)
#11 TransportFever3 +0x2fbe0cc
#12 TransportFever3 +0x2fbdf68  ┐
#13 TransportFever3 +0x2f85bac  │ recursive walk
#14 TransportFever3 +0x3066244  │
#15 TransportFever3 +0x2fbdf68  ┘
```

(Offsets from the image base 0x100000000.)

**It depends on the total number of stylesheet rules from mods.** Counting every mod `.css.lua` rule
(comma-separated selectors count once per part; base ≈ 5,970), loads sort exactly by the mod rule total:

| Active mod set | Mod CSS rules | Result |
|---|---:|---|
| set A alone | 191 | loads |
| set A minus one or more CSS mods + zhenya_easy_terminal_assignment | 58 – 196 | loads |
| set A minus a 5-rule or 2-rule mod + easy_terminal | 208 / 211 | crashes |
| set A + easy_terminal (22 rules) / + auto_color_lines (26) | 213 / 217 | crashes |
| set A + a test mod with **only 40 inert rules and no scripts** | 231 | crashes |

Set A (15 mods, 191 rules): square_better_bus_overlay, square_line_revert, square_no_factory_passengers,
square_better_minimap, square_problem_radar, square_industry_flows, square_supply_gaps,
square_industry_production_label, square_roundabouts, square_one_way_roads, square_bigger_line_dots,
square_bulk_bulldozer, square_smart_lanes, square_passenger_destinations, square_full_refund.

So the limit is around 6,170 rules in total. The 2026-10-07 crash with **UI Overhaul as the only mod** (a new game,
dump 72ecd799) has the same stack. Not every load near the limit crashes, presumably because the freed memory
has to be reused first.

**Where (from disassembly of build 40420):** `Component::ComputeStyles` (0x102fbe0cc) inside a recursive
`Component::Validate` (0x102fbdf68) from `CCore::Step` (0x102fe3914). It copies the computed style's
`animationName` string (StyleSheet+0x1c8), which is a raw pointer into stylesheet rule storage
(`GetValueFromBestInstanceRule`, the rule vector at ruleSet+0x700). The length read is garbage
(e.g. 0x80a0e8fa52aa5acb), so the pointer is stale: the rule storage apparently reallocates once it passes a
capacity while components keep pointers computed before that.

**Save:** large map (map.size 5, sub-arctic), estimatedMb=8172, 1.41 M models, 90 lines, 187 vehicles.

**Uploaded crash reports (minidump IDs):**
1888A521-4FFC-445B-B36A-8C396C841205, 18FF5E94-E9E2-45E5-A275-2B3C764AFC9A, 2623D00D-EA75-46A9-B2B3-073D3986990F,
27AC7034-9940-4A35-8D27-4F674A93DA2B, 38C02F1A-1D36-4614-A7FF-45849FFDC6A3, 41528116-4AF6-431D-BE55-F490B76972DD,
464AC455-553F-4B87-A871-01488048F31C, 5CF998A0-1DD9-4172-BB01-8A656F98622A, 64C0E2B6-0153-4467-9558-87E49F1859AA,
6CBF80F0-48FC-49B4-B4F6-440D446EFF5D, 854C8F37-A657-4E4E-AE62-93898B7F3830, 86579A8F-954D-44F6-850A-F818920BAC14

**Standalone repro (2026-10-12):** `mods/square_css_rule_crash_repro` (zipped as
`plans/bugreports/square_css_rule_crash_repro.zip`, with a README for the developers): one stylesheet with 400
inert rules, no scripts. Verified 2026-10-12 as the only mod for the whole game session: a new game loaded, then
loading the large sub-arctic save crashed in `+0x2fbe0cc` (EXC_BAD_ACCESS, crash report 13ca8116, minidump
16DF9C65-6DB7-459E-A89D-C51482AC39B8). A first attempt (7c2b0ad4, minidump F3FA9424-…) crashed too, but after a
mod switch in the same session, so it doesn't count.
Reconfirmed after a full restart with the large save as the first load: the original string-exception stack
(frames 8/10/11), crash report c9a75c9c, minidump 1C6CB5B7-3952-4B7C-91DB-D0AC37A5CD67.
