# CSS rule crash repro (Transport Fever 3, build 40420, macOS)

A minimal mod that reproduces a crash on the first GUI frame after loading a game. It contains a single
stylesheet (`content/css_rule_crash_repro/css_rule_crash_repro.css.lua`) with 400 rules whose selectors
(`TextView!sqcssrepro-none-N`) match no component. It has no scripts, models or other content, so it changes
nothing visible in the game.

## Steps

1. Copy the `square_css_rule_crash_repro` folder into the staging area (`.../Transport Fever 3/staging_area/`).
2. Start the game and enable **CSS rule crash repro** as the only mod.
3. Load a large save (ours: map size 5, sub-arctic, ~1.07 M assets, 206 vehicles, estimatedMb=8233).
4. The game crashes on the first GUI frame: the log ends with `ScriptComponentRoot: Collect Lua Garbage: … KB -> … KB`,
   then the minidump callback (stack below).

Verified 2026-10-12 on build 40420, this mod as the only mod for the whole game session:

| Crash report (session) | Minidump | What happened |
|---|---|---|
| `c9a75c9c-be81-4c72-8091-8338ceb7fcd9` | `1C6CB5B7-3952-4B7C-91DB-D0AC37A5CD67` | fresh start, large save as the first load: string exception in +0x2fbe0cc |
| `13ca8116-e0b6-40e5-b68d-60c9d00ec795` | `16DF9C65-6DB7-459E-A89D-C51482AC39B8` | a small new game loaded, then the large save: EXC_BAD_ACCESS in +0x2fbe0cc |

Control: the same save, fresh start, with only Urban Games' No Costs mod (no stylesheets) loads fine (session
`99052c78`). It also loads repeatedly with mod sets under ~200 stylesheet rules. A small new game alone can survive:
the crash is intermittent because the freed memory has to be reused first. When you compare mod sets, restart the
game in between: after loading a large rule set, switching to a small one in the same session can still crash.

## The threshold

Change `local RULES = 400` at the top of the stylesheet:

| Mod rules (all active mods together) | Result in our tests |
|---:|---|
| up to ~200 | loads |
| ~205 and above | crashes (208, 211, 213, 217, 231 seen) |

Every comma-separated selector part counts as one rule. The base game has about 5,970, so the limit is near
6,170 in total. Real mods hit it: the Timetables mod alone has 187 rules, and UI Overhaul alone crashed a new
game with the same stack.

## Stack (identical in every dump)

Uncaught C++ exception from a std::string constructor (garbage length, e.g. 0x80a0e8fa52aa5acb), inside a
recursive component tree walk. Offsets from the image base 0x100000000:

```
#7  libc++abi __cxa_throw
#8  TransportFever3 +0x16a50   (throw helper)
#10 TransportFever3 +0x3d16c   (std::string init)
#11 TransportFever3 +0x2fbe0cc  Component::ComputeStyles
#12 TransportFever3 +0x2fbdf68  Component::Validate (recursive)
#13 TransportFever3 +0x2f85bac
#14 TransportFever3 +0x3066244
#15 TransportFever3 +0x2fbdf68
...                             CCore::Step (+0x2fe3914)
```

Sometimes instead the crash is EXC_BAD_ACCESS at frame #0 inside +0x2fbe0cc (+1152, reading a garbage address
such as 0xffffffffd243d24f), with the same recursive walk below it. The verified repro above crashed this way.

**Likely cause (from disassembly):** `ComputeStyles` copies the computed style's `animationName` string
(StyleSheet+0x1c8), which is a raw pointer into the stylesheet rule storage (`GetValueFromBestInstanceRule`,
the rule vector at ruleSet+0x700). Once the rules pass a capacity, the storage reallocates, while components
keep pointers computed before that.
