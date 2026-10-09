# Performance review: square_bigger_line_dots (2026-10-08)

**Verdict: nothing worth changing.** No shipped code was modified, and the revision was not bumped.

## What the mod runs

| File | When it runs | Cost |
|---|---|---|
| `content/bigger_line_dots/gui/bigger_line_dots.css.lua` | Once, when the stylesheet loads | Two `ssu.makeAdder` rules, constant tables only |
| `content/square_bigger_line_dots_presence.lua` | Only when another mod `ug_require`s it | Returns a constant table |

The mod has no update or GUI script, no HUD script, no event handlers, no world queries and no timers, so it does no work per frame, per tick or per event.

## Examined and deliberately not changed
- **Selector specificity.** Each rule adds one descendant level to the base `line_vehicle_mgmt.css.lua` selector, so the override wins whatever the load order. The extra cost of matching one more level is negligible, and dropping it would bring back the load-order bug.

## In-game check list
- None needed (nothing changed).
