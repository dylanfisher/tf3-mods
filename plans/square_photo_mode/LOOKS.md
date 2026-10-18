# Photo Mode: looks, weather over time, time-lapse, seasons, sun placement

Status: engine built in code 2026-10-13; window integrated the same day (sections in the Light tab, see
"Integration"); every look switched fine in `2026-10-14_0055_session` (findings environment.md). Round 11
(2026-10-14, untested: TESTING.md K14-K19): looks in layers on a new Weather tab, every look pushed further, Wild
water, the depth-of-field research. Round 12 (2026-10-14, untested: TESTING.md K21-K25): a third layer, **haze**,
split off the sky; Soft background retuned; Misty valley's scale height fixed; soft foreground researched (not
possible). Round 15 (2026-10-14, untested: TESTING.md LS1-LS8): four more skies, a haze and a water look (1076 files),
`<` / `>` beside each look dropdown, sliders for time, season and sun ("Round 15" below). TESTING.md "Phase 4:
Looks" K1-K13 still apply. Belongs to PLAN.md "Rev 2" phase 4 (move the finished
parts into PLAN.md / HISTORY.md per plans/README.md once tested).

Files (all new except the two extended ones):

| File | What |
|---|---|
| `tools/gen_photo_looks.py` | generator: base climate env files + per-layer deltas -> 1076 env files (round 15; 396 in round 12, 156 after Soft background, 136 in round 11, 32 before); `--check` for drift |
| `mods/square_photo_mode/content/environments/sqpm_<climate>_<sky>_<haze>_<water>.env.lua` | 1076 generated look environments (4 climates x (9 skies x 6 hazes x 5 waters - 1), `orig` = the climate's own layer; 4541 KB, the headers list the changes, the intent stays in the generator) |
| `content/photo_mode/pm_looks.lua` | pure: climates, looks, ResNames, climate detection, easing, weather / time-lapse plans, solar geometry, sun placement, start plan |
| `content/photo_mode/gui/pm_weather.lua` | GUI: look switch / restore, animations, time-lapse, seasons, sun placement, pause menu, game start |
| `content/photo_mode/gui/pm_sky.lua` (extended) | requires pm_weather, forwards step / pause menu / start / marker; `K.apply` (quiet sets), facade `looks / look / weather / lapse / season / placeSun / status` |
| `content/photo_mode/pm_light.lua` (extended) | fields `cloudBase`, `cloudTop` in the override (snapshot, restore, marker); marker field `look` |
| `tests/square_photo_mode/test_looks.lua` | 23 offline tests (pure + fake api through pm_sky; round 15: the new looks, stepLook, the slider scales and throttle, quiet live sets) |
| `content/photo_mode/gui/pm_slider.lua` (round 15) | the Light tab's slider row recipe: own state, throttled quiet live writes, a final set at release / settle |

Regenerate the looks after a game update changed a base climate: `uv run tools/gen_photo_looks.py` (`--check`
reports drift; listed in CLAUDE.md "Commands").

## Verified facts (probe session `2026-10-13_1924_sqpq`, Dry map)

Moved to `docs/findings/environment.md` (index: `docs/findings.md` "Environment, weather, light and cutscenes"):
live environment edits (T6), a mod's env file listed and switched rendering-only (T7; a switch resets the live
atmosphere values to the file's), `isToolEnvironment`, the 0..1 cloud scale (the weather script's means are
sunny 0.5, cloudy 0.5, rainy 1.0; an earlier draft here said sunny 0.0), and the T9 cutscene facts.

## Layers (round 11, three since round 12)

User (round 11): "Can the looks be mixed and matched? e.g. hazy morning and mirror water". An env file is switched
as a whole and only the six atmosphere fields are live (findings environment.md), so a mix is its own file. Clouds,
day and sun are live and stay as the player set them (carried over every switch), so they need no layer.

Round 12 (user: "Is it possible to mix Dramatic sky and a new selector for haze?"): three layers, each owning its
own fields (the generator fails when two layers change the same field):

- **Sky**: `atmosphere` sun / moon fields (disc size, bloom, intensity, illuminance, sunset boost), Rayleigh
  (`rayScatteringCoeff` / `Scale`) and ozone (`absorptionScale`), and the `light` block (exposure, contrast,
  ambient tint) except the two overcast-only fields.
- **Haze**: every mie field (`mieScatteringScale` / `Coeff` / `Overcast`, `mieAbsorptionScale` / `Overcast`,
  `mieScaleHeight`, `miePhaseG` / `Overcast`) and the aerial perspective (`fogScaleLow` / `High`).
- **Water**: the `water` block, plus `light.hdrContrastOvercast` / `hdrExposureOvercast` (Wild water's hard overcast
  picture, from round 11's Stormy sea; no sky look touches them).

Files: 4 climates x (5 skies x 5 hazes x 4 waters - 1) = **396**, ~4.7 KB each, 1858 KB in all (156 / 677 KB
before; orig x3 is the climate itself). The base game loads ~18,000 text files, so 396 more is ~2 % (K22 checks the
load time). The straight split of round 11's looks (7 skies x 5 hazes x 5 waters) would have been 4 x 174 = 696:
reduced by folding the skies that only made sense with their haze (Hazy morning's warm grade, Misty valley's cool
grade: into the new Soft light sky and the haze looks), Crisp & clear's deep blue into Dramatic, and Stormy sea into
Wild water (both rough, foamy, murky; Wild is the stronger and the one for rivers). Every combination exists, so the
dropdowns need no rules. Dropping combinations instead (e.g. Moonlit night only with the Original or Misty haze)
would have saved 12 per climate and needed disabled dropdown items: not done. Window: three ComboBox rows (Sky,
Haze, Water) with "Original" first (`pm_window.layerRow`, docs/ui-guide.md "one of many");
`pm_sky.layer(layer, key)` keeps the other two layers.

## Looks (round 12)

One env file per base climate and combination, each the climate's own env file with the changes below, so textures
(sun cube map, water depth colours), latitude and the climate's character stay. Values inside the wiki's ranges and
our sanity bounds (the generator fails otherwise). Base values for scale: temperate mieScatteringScale 0.0069 (dry
0.014, tropical 0.012), mieScaleHeight 1.2 km (dry and subarctic 0.8, tropical 2.4), fogScaleLow / High 3 (dry
4.4), miePhaseG 0.8 (0.7-0.875), the `*Overcast` mie scales 0.12-0.24 / absorption 0.06-0.12 and miePhaseGOvercast
0.5, sunBloom 350, sunSizeAngle 0.9, hdrContrastDay[1] 1.3, ambientDayColor 0.047 grey, moonIlluminance 0.21,
water normalScale 0.4 (dry 0.3, tropical 0.6), extinctionCoeff 0.05 (dry 0.1), roughness 0.5 (dry 0, tropical 1).

Sky looks (relative = x, absolute = "="):

| Look | Intent | Changes |
|---|---|---|
| Soft light (new) | soft, bright light; pairs with a haze | sunBloom = 150, sunBloomScale x1.5, sunIntensity x0.8 (the disc); ambientDayColor = {0.08, 0.08, 0.082}, hdrExposureDay x1.15, hdrContrastDay[1] -0.35. From round 11's Misty valley and Soft background grades |
| Dramatic | huge sun, hard contrast, deep blue | sunBloom = 80, sunBloomScale x2.5, sunSizeAngle x1.8, sunsetBoostScale x2, sunIntensity x1.25, rayScatteringScale x1.3 and absorptionScale (ozone) x1.6 (new: Crisp & clear's deep blue); ambientDayColor = {0.025, 0.025, 0.03}, hdrContrastDay[1] +0.6, hdrContrastNight = 1.4. Round 11's mieScatteringScale x2 and miePhaseG 0.93 went (haze fields) |
| Storybook | pastel picture book | rayScatteringCoeff = {0.26, 0.42, 0.70}, rayScatteringScale x0.85, sunsetBoostScale x1.8; ambientDayColor = {0.12, 0.10, 0.09}, hdrExposureDay x1.3, hdrContrastDay[1] -0.35. Round 11's rosy mie (x2, {0.64, 0.55, 0.54}) went |
| Moonlit night | full moon | moonIlluminance x8, moonIntensity x3; ambientNightColor = {0.02, 0.03, 0.06}, hdrExposureNight x1.6, hdrContrastNight = 1.2 |

Haze looks:

| Look | Intent | Changes |
|---|---|---|
| Crisp & clear | long, sharp views | mieScatteringScale x0.15, mieAbsorptionScale x0.2, fogScaleLow / High x0.25. Round 11's deep blue moved to Dramatic, its contrast +0.25 and cool ambient dropped |
| Hazy morning | golden haze, bright halo | mieScatteringScale x6, mieScatteringCoeff = warm {0.68, 0.57, 0.46}, miePhaseG = 0.9, mieScaleHeight x2, fogScaleLow x2.5, fogScaleHigh x1.8. Round 11's sunset boost, warm ambient and grade went (sky fields) |
| Misty valley (fixed) | thick white mist lying low | fogScaleLow = 24, fogScaleHigh = 1.5, mieScatteringScale = 0.9 and Overcast = 0.9, mieAbsorptionScale = 0 and Overcast = 0, mieScatteringCoeff = {0.56, 0.58, 0.60}, mieScaleHeight = 0.3, miePhaseG = 0.35 and Overcast = 0.35. Round 11: mie x10, mieScaleHeight x0.35, miePhaseG 0.6, plus a grade (now Soft light) |
| Soft background (retuned) | close-ups: a bright veil over the distance, the sky kept | mieScatteringScale = 0.27 and Overcast = 0.27, mieAbsorptionScale = 0 and Overcast = 0, mieScaleHeight = 0.4, miePhaseG = 0.1 and Overcast = 0.1, fogScaleLow = 25. Why: "Round 12" below |

Water looks:

| Look | Intent | Changes |
|---|---|---|
| Mirror water | dead still | normalScale = 0 (the wiki: 0 = still water), preferLowFreq = true, roughness = 0, waveFoamTex = "" |
| Crystal clear | see the bottom | extinctionCoeff = 0.008 (a sixth to a twelfth of the base), normalScale x0.5, preferLowFreq = true, roughness = 0.1 |
| Wild water | rapids, a boiling sea | normalScale = 6, preferLowFreq = false, roughness = 0.6, waveFoamTex = shared foam, extinctionCoeff x8; light: hdrContrastOvercast = 1.4, hdrExposureOvercast = 0.75 (round 11's Stormy sea, merged in round 12; Stormy's normalScale 2.5, roughness 1, extinction x4 went) |

## Round 12: Soft background retuned, Misty valley fixed, no soft foreground

User (Dry map, a canyon from ~100 m up, low trees in front; session `2026-10-14_0229_sqrl-sqst`: Soft background
on at 12:00 with the live cloud cover 0.78, later at 05:42 with Overcast 0.7, sun ~10 degrees): with Soft
background "the whole scene beyond ~50 m is a heavy grey-brown murk, the sky a dull grey-mauve overcast, far cliffs
barely visible"; Crisp & clear at the same place showed a pink sky, a river and cliffs.

How the shaders make haze (`.cache/game/base/content/rendering/programs/shaders/`):

- `atmosphere/common.glsl` `sampleMediumRGB`: mie density `exp(mieDensityExpScale x viewHeight)`, viewHeight =
  altitude above sea level + `heightOffset` (0.5 km in all four climates); scattering = density x
  `mieScattering` (inferred: `mieScatteringCoeff` x `mieScatteringScale`, per km; the coefficient vectors have unit
  length), extinction = mie scattering + mie absorption + Rayleigh + ozone. The engine computes
  `mieDensityExpScale` from `mieScaleHeight` (not in the files; inferred `-1 / mieScaleHeight`, as in the
  reference implementation this shader follows).
- `integrateScatteredLuminance`: single scattering (no multiple-scattering term); per step `S = sunsetBoost x
  earthShadow x transmittanceToSun x (mie scattering x Cornette-Shanks phase + Rayleigh x Rayleigh phase)`,
  integrated as `S x (1 - T) / extinction`. For geometry (`aerial_perspective_LUT.fs`, `applyFogFactor` true) the
  step length is multiplied by the fog factor `mix(fogScaleHigh, fogScaleLow, fz^2)`, `(1 - |dz| / distance)^2`
  with `mirrorSky`. For the sky (`sky_view_LUT.fs`, `applyFogFactor` false) it is not: **the sky sees the whole
  mie column, the land sees the fog-scaled one**. `transmittanceToSun` comes from `transmittance_LUT.fs` through
  the whole column too.
- `util/fog.fs` `applyFog`: below the cloud base the fog colour is multiplied by `sunIlluminance x
  getCloudCoverageFactor(cloudCoverage)` = 1 - 0.75 x cover (`cloud.h.glsl`): at 0.78 the veil gets 42 % of the sun.

What went wrong in round 11 (model below: the shader's integral in Python, Dry climate, camera 100 m above sea
level, level view; the session's camera altitude above sea level is unknown):

1. **The sky itself was haze.** mie 0.25 x coeff 0.58 with a 2 km scale height: zenith optical depth ~0.23,
   ~16 along the horizon (the climate: ~0.01 / ~0.3). The sky 20 degrees up, away from the sun, had blue/red 1.6
   (climate 4.6): grey-mauve.
2. **The sun was dimmed and browned through that column.** At 10 degrees the sun kept 24 % / 18 % / 17 % (R/G/B;
   climate 79 / 50 / 35 %), so the veil, lit only by that sun, was dim.
3. **Phase g 0.45 is dull away from the sun.** Single scattering only: the far veil's radiance is sun x phase
   (no absorption). g 0.45 gives 0.033 per sr sideways and 0.028 away (isotropic 0.080); the veil sideways to a
   10-degree sun came out at 0.37 x a sunlit surface (albedo 0.3): darker than the land it covers, so the frame
   turned into a dark veil the auto exposure lifted to grey.
4. **Too strong**: ~3 per km at the ground: 13 % veil at 50 m, 25 % at 100 m, 76 % at 500 m.
5. Under clouds (0.78) the veil gets 42 % of the sun (`getCloudCoverageFactor`), as does the land: no fix in an env
   file, but a veil that was already darker than the land got darker still.

The fix: the land's veil comes from the fog factor (which the sky never sees), the aerosol is packed near the ground
(so the sky's column stays thin), the phase is near-isotropic. Since `mieScatteringScale` stops at 1 (wiki), the
scale height can't go very low (at 0.5 km offset a 0.2 km height leaves 8 % at sea level): 0.4 km and 0.27 give
~0.044 per km mie at sea level, x25 fog = ~1.1 per km plus the climate's Rayleigh x25 (bluish distance).

| Model (Dry, camera 100 m above sea level) | climate | round 11 | round 12 |
|---|---|---|---|
| veil at 50 / 100 / 200 / 500 / 1000 m | 0 / 1 / 1 / 3 / 6 % | 13 / 25 / 43 / 76 / 94 % | 6 / 11 / 21 / 44 / 68 % |
| same, camera 300 m above sea level | 0 / 1 / 1 / 3 / 6 % | 10 / 19 / 34 / 65 / 88 % | 3 / 7 / 13 / 29 / 49 % |
| from 1 km / 2 km up, 30 degrees down | 3 / 5 % | 31 / 8 % | 12 / 8 % |
| sun at 10 degrees, transmittance R/G/B | 79 / 50 / 35 % | 24 / 18 / 17 % | 74 / 47 / 33 % |
| sky 5 / 20 / 60 degrees up, away from the sun, blue/red | 2.6 / 4.6 / 5.4 | 1.1 / 1.6 / 1.8 | 1.7 / 3.2 / 3.8 |
| far veil vs a sunlit surface, 10-degree sun: sideways / away / towards | 0.24 / 0.41 / 1.65 | 0.37 / 0.34 / 4.2 | 1.31 / 1.96 / 3.2 |
| same, 40-degree sun, sideways | 0.14 | 0.41 | 0.75 |

So a subject 20-80 m away keeps 91-97 %, the background is about half veiled at 500-600 m, the veil is as bright as
the land or brighter (warm at a low sun) and the sky stays blue above ~10 degrees. Caveats (K23): the model is
single scattering with my reading of the uniforms (density scale, the `*Overcast` blend, inferred); the LUT's depth
slices are linear between near and far, so the veil near the camera is interpolated; a map on high ground gets less
(the aerosol is packed low: half as much at 300 m above sea level), the price of keeping it out of the sky. Grade
(lifted fill, exposure, low contrast, soft sun) is now the Soft light sky, to pick with it or not.

**Misty valley**: round 11's mie x10 with `mieScaleHeight` x0.35 (0.28-0.84 km) left 17-55 % of it at sea level:
2 / 5 / 9 / 22 / 38 % veil (Dry). Now absolute (one mist everywhere): 0.9 with 0.3 km, no absorption, the same
under clouds, phase 0.35: 9 / 18 / 32 / 62 / 86 %, the sky 20 degrees up blue/red 3.4.

### Soft foreground: not possible with an env file (research, not built)

User: "Let's also try a soft foreground." Checked against the shaders:

- **Any haze veils what is behind it.** `integrateScatteredLuminance` multiplies the transmittance step by step
  from the camera outward (`throughput *= sampleTransmittance`) and only adds scattered light, so the veil in front
  of a near object is also in front of everything behind it: a far subject is always at least as veiled as the
  foreground on the same ray. A foreground on another ray (the bottom of the frame looking down) has a shorter,
  steeper path, which the `mirrorSky` factor `(1 - |dz| / distance)^2` veils even less. There is no near-only term.
- **A density that rises with height** (camera above, air near it denser than near the ground) would need a
  positive `mieDensityExpScale`, i.e. a negative `mieScaleHeight`: outside the wiki's 0-100, no base or campaign
  file uses one, and the engine's conversion (and any clamp) is not in the files. Even if it passed, the density
  `exp(+h / |H|)` grows up to the atmosphere's top (`atmosphereHeight` 100 km): a small |H| overflows (a black or NaN
  sky, no sunlight through the transmittance LUT), a large one is nearly uniform, which fills the sky column (the
  round 11 failure, worse). And by the point above, the dense air near the camera would veil the ground below it
  just as much: a uniform haze, not a soft foreground. Not tried in game (a broken env file risks the sky).
- **A cloud layer at the camera's height** (live `cloudBase` / `cloudTop`): `applyFog` case "camera inside the
  layer" marches the cloud from the camera, again veiling everything behind; above it, the cloud sits between
  camera and ground. Neither leaves the subject clear.

So a soft foreground needs a real depth of field (the DoF probe, "Depth of field and shaders" below), not a look.

## Soft background, round 11 version (superseded by "Round 12" above)

User: "push the soft background look really extreme for close up photos of a subject with bokeh background". There
is no depth of field (below, and findings environment.md), so the look fakes one with the aerial perspective: haze
only grows with distance along the view ray, which is exactly what a close subject in front of a far background
needs. The aim: a subject 20-80 m from a low camera stays nearly clear while everything from a few hundred metres on
dissolves into a bright, soft veil.

How the shaders set the numbers (`.cache/game/base/content/rendering/programs/shaders/`):

- **How fast the veil grows.** `atmosphere/common.glsl` `integrateScatteredLuminance` marches camera -> pixel,
  transmittance `exp(-extinction x dt x dtScale)` with `extinction = density x (mie scattering + mie absorption) +
  Rayleigh + ozone` (`sampleMediumRGB`, per km). For a ray towards geometry `dtScale` is the fog factor
  `mix(fogScaleHigh, fogScaleLow, fz^2)`, `fz = 1 - clamp((camera z in km - 0.1) / 2)` (camera z = game height
  above sea level: full Low up to 100 m, full High from 2.1 km), times `(1 - |dz| / distance)^2` with
  `mirrorSky = true` (all four base climates): a near-horizontal ray gets the whole factor. The result is baked per
  frame into `aerialPerspectiveLUT` (`aerial_perspective_LUT.fs`, depth slices from near to far) and applied in
  `util/fog.fs` `applyFog`. Mie density is `exp(-height / mieScaleHeight)` with height above sea level plus
  `heightOffset` 0.5 km. Model, camera 50 m up, horizontal view (temperate; dry the same within 2 %): extinction
  about 3.0 per km, so the veil is ~8 % at 30 m, ~16 % at 60 m, ~26 % at 100 m, half at 200 m, ~77 % at 500 m,
  ~95 % at 1 km. Hazy morning is ~0.24 per km (5 % at 200 m), Misty valley ~0.6 (11 % at 200 m; its small scale
  height lowers the density at the ground, see below). Values: `mieScatteringScale` 0.25 (x18 dry to x36
  temperate), `fogScaleLow` 25 (the wiki's maximum), `mieScaleHeight` 2.0 (so maps on high ground keep most of it:
  at 1 km up the density is 0.47 instead of 0.29 with 1.2).
- **Bright, not grey.** The veil's colour far away tends to `sun x transmittance to the sun x (mie scattering x
  mie phase + Rayleigh x Rayleigh phase) / extinction` (the `sint` step), so absorption only darkens it:
  `mieAbsorptionScale` 0 (as subarctic's own). `mieScatteringCoeff` near-white, a touch warm; Rayleigh x0.6 so the
  veil isn't blue (with fog 25 the Rayleigh share alone would be ~0.7 per km in blue) and the sky turns paler.
- **Glow towards the sun.** The shader is single scattering only (no multiple-scattering term), so the veil's
  brightness follows the Cornette-Shanks phase (`cornetteShanksMiePhaseFunction`): with g 0.45 it is 0.52 looking
  at the sun, 0.15 at 45 degrees, 0.03 sideways and away (isotropic 0.08); g 0.8 would give 4.1 / 0.07 / 0.008: a
  hot spot round the sun and a dull grey veil everywhere else. 0.45 is the lowest a base env file uses (a broad
  glow, brightest towards the sun: Backlight). Away from the sun the veil is about as bright as sunlit ground, so
  lifted exposure and lower contrast make it read milky rather than grey.
- **Overcast.** The base files carry `mieScatteringScaleOvercast` 0.12-0.24 and `mieAbsorptionScaleOvercast`
  0.06-0.12 (not in the wiki; most likely blended in by cloud cover, inferred): set to 0.25 and 0 so the veil
  stays the same and bright under clouds.
- **From high up** `fogScaleHigh` 1 (the real distance): at 2 km the map is hazy but readable, not a white-out.
  The look is meant for close-ups.
- **Glowing highlights.** Image bloom has no env field: `hdr/compose.fs` adds the blurred frame when the engine's
  `applyBloom` is on (no strength, no threshold in the files). The env controls only the sun's own glow in the sky
  (`getSunLuminance`: `sunBloom` smaller = wider): 150 and `sunBloomScale` x1.5 for a soft sun when it is in frame.
  The rest is `light`: ambient fill lifted (softer shadows on the subject), exposure x1.2, contrast -0.35.

Ranges: everything inside the wiki's ranges and the generator's RANGES. Outside what the base and campaign env
files use: `mieScatteringScale` 0.25 (they go to 0.107, overcast to 0.24), `fogScaleLow` 25 (they go to 23.8),
`fogScaleHigh` 1.0 (they use 3.0 at least). One strength only: a milder one overlaps Hazy morning and Misty valley,
and the request was for the extreme; 20 more files.

Caveats (inferred from the files, K20 settles them): the LUT's depth slices are set by the engine (count and far
plane not in the files) and interpolated linearly, so the veil may come later at 100-300 m than the model's
exponential (the subject at 30-60 m stays clearer too); the auto exposure (`hdr/histogram.fs`, `hdrTarget`) may
darken the subject when the bright veil fills the frame (then raise `hdrExposureDay`). Framing: the shot presets
Eye level (25 m, 2 degrees down) and Low angle (60 m) and the subject framings (person 22 m, road vehicle 40 m, vehicle
60 m) already put a subject at the right distance; no new "portrait" preset is needed.

Side find: Misty valley's `mieScaleHeight` x0.35 (0.42 km temperate) leaves only ~27 % of the mie density at the
ground (height above sea level + 0.5 km offset), so its ground mist is weaker than its x10 mie and fog 24 suggest
(~0.6 per km). If K15 finds it too weak, raise its scale height rather than the mie.

## Rapids: what the water can and can't do (round 11)

User: "A way to make a river look more extreme, rapids etc.? Stormy sea gets us a little way." From the shaders
(findings environment.md "Water: one block for sea and rivers, no flow"): one `water` block for sea, lakes and
rivers; the normal map scrolls with the clock in six fixed directions (no flow speed or direction field, so no
downstream motion); wave strength is `normalScale` times `0.5 log2((depth + 5) / 4)`, about 0.16 at 0 m and 0.5
at 3 m: a river's shallow water gets a third or less of the sea's chop at the same value, which is why Stormy sea
(1.5) did little on rivers. Wild water sets 6: a river at 1 m gets ~1.75 (more than Stormy's sea); the sea gets
chaotic, glittering water (the normal saturates; `water.fs` then draws the shallow colour, a whitish churn).
Roughness 0.6 keeps some glitter, extinction x8 makes it opaque and stirred up, foam on shores. Further steps if
K14 says it's not enough: a custom normal map (`water.normalTex`, a DDS of our own with sharper, denser waves),
a lighter `depthColorTex` (whiter water); both need DDS authoring (mipmaps).

## Depth of field and shaders (round 11, research; not built)

User: "Can the way looks are applied be leveraged for depth of field? Or can we add shaders?" Findings
(environment.md "What an env file controls; no depth of field or blur anywhere", "Shaders: mods may ship them on
PC, never on consoles"):

- No DoF, focus, tilt-shift or blur parameter exists in env files, the scripting api or cutscene keyframes
  (cameras there have fovY only). So no supported path: an env switch can't blur.
- Shaders: a mod may ship GLSL files (wiki shaders page, resource types), but the guidelines forbid custom shaders
  on consoles, and Photo Mode supports consoles (PS5 window fields). A shader would also replace a base file for
  every frame of every game, always on.
- The only workable design: a separate **PC-only companion mod** ("Photo Mode: Tilt-shift") overriding
  `rendering/programs/shaders/hdr/compose.fs` (the last pass; ~60 lines): mix `texBlurred` (the bloom chain's
  full-frame blur, no threshold) into the frame by the pixel's distance from a horizontal band (a tilt-shift
  miniature look, no depth buffer there), switched on per look through a value only our env files set (e.g. a
  sentinel in a `light` field that reaches the compose uniforms: `hdrMax` / `hdrShoulder` / `hdrMidIn` /
  `hdrMidOut` are in its uniform block). Risks: an untested override mechanism in TF3, a base shader update
  breaking it, every player's frame going through our shader. **Needs the user's go-ahead** before any work.
- **Update 2026-10-14 (DoF probe)**: a mod most likely can't override a base shader at all (namespaced
  resources; Realistic Environment Pro makes players copy its shaders into the install), so the companion-mod idea
  above becomes "manual install, PC only". The `ssr_apply` pass has depth + a blurred mip chain, so real depth of
  field is possible there, switched per look by `light.latitude + 2 pi * mode` (not REP's cloud / day bits, which
  Photo Mode also writes live: possible REP conflict). Probe: `plans/square_photo_dof_probe/` (PLAN, TESTING).
- A GUI alternative: CSS `blurRadius` (a backdrop blur, base main menu) on top / bottom bands of a full-screen
  overlay; needs class rules (budget) and would never be in Photo Mode's screenshots (the capture leaves the UI
  out). Not recommended.

Generation: `tools/gen_photo_looks.py` runs each base env file in Lua (lupa), applies the deltas, writes a
sorted table with a header comment (intent and changes). Why a generator and not an env file that loads the
base one: base and campaign env files are plain `function data() return {...} end` (no `require` anywhere in
`*.env.lua`), the env loader's Lua environment is undocumented (whether `require` / `dofile` / `ug_require`
exist there and how a base path would resolve is unknown), and a failing env file at load would cost the whole
mod. The generator keeps the deltas in one place and `--check` catches a game update that changed a climate.

Since round 12 every file is a sky + haze + water combination (`apply_looks`: each layer's changes in turn) and
names all three in its header. Each file: `isToolEnvironment = true` (as the base `*_old` and model-editor envs: hidden from the calendar
editor's Environment list, which the probe's `false` would have shown, and never a climate for a new game
anyway, fact 4); `name = "Photo Mode look: <Sky> + <Haze> + <Water> (<Climate>)"` ("Original" for a layer left alone) (an id, never shown: our window names the
looks; Photo Mode recognises its own rendering env by this prefix); textures absolute (`sun.dds` ->
`::/climates/<c>/sun.dds`, `/climates/shared/x` -> `::/climates/shared/x`; the probe's absolute form loaded
without a texture error).

### Unknown climates (decided)

The climate comes from the game's ResName (`pm_looks.climateOf`): the four base climates exactly; then
keywords for mod and campaign climates (`subarctic`, `arctic`, `nordic`, `norway` -> subarctic; `tropic` ->
tropical; `desert`, `arid`, `dry` -> dry; `temperate`); anything else (e.g. campaign `mission2.env`, a mod's
"mars.env") gets **no looks**: the Looks row shows a one-line note instead. Reason: a look file of another
climate brings that climate's sky cube map and water colours, which on a mod climate would look wrong and could
clash with its textures; weather, time-lapse, seasons and sun placement still work there (they only touch the
live fields), with the temperate latitude for sun maths.

## Switching and restore

- **Switch** (`pm_weather.setLook`): read the live six fields; `environmentRep.find(look ResName)`;
  `rendering.setEnvironment(rep.get(id))`; copy of the new env with the live fields put back; set again.
  Never `api.gui.game.setEnvironment` (the save would point at our env, and need the mod; Crash-safety and
  "mods must not impact saves"). A look needs no override: it changes nothing the game simulates.
- **Layers** (round 12, `pm_weather.setLook(sky, haze, water)` / `setLayer(layer, key)`): the combination's file
  (`P.lookResName(climate, sky, haze, water)`, nil for all three originals = Back). `S.look = { key, sky, haze,
  water, ... }`; the key (`P.lookKey`: `<sky|orig>_<haze|orig>_<water|orig>`, at most 36 characters, the marker
  takes 40) is the marker's `look` and the log's `look <key> on`. `P.parseOurs` compares every combination (keys
  are unique across layers and contain underscores, so no pattern split).
- **Back** (all three dropdowns on "Original", the pause menu, the game start): the same switch to the game's ResName
  (`P.originalResName`: never back to one of ours), live fields carried.
- **Pause menu order** (`pm_sky.pauseMenu`): animations and time-lapse stop -> look back -> the override's
  values (`pm_light.recoverPlan`) -> freeze. Untick "Light & weather override" stops animations but keeps the
  look (separate control). Window close keeps both (as High graphics mode).
- **Game start** (`pm_weather.start` from `pm_sky.start`, before the override repair): state cleared; when the
  rendering environment's name is ours (the GUI Lua state outlived a load) or our save marker had `look`, switch
  to the game's ResName (`P.startPlan`). The marker (`light.look` in our GUI save data, `pm_light.marker`) is
  written on every look change; a rendering-only switch never reaches the save, so this is a safety net only.
- Logs: `look <key> on (button, climate dry by base): <ResName>, live cloud=.. base=.. top=.. day=.. sun=..`,
  `look <key> off (<why>): back to <ResName> ok=..`, `look <key>: unknown climate (environment ..), no looks`,
  `look: game start (rendering|marker, ...): back to .. ok=..`, `look ... ERROR ...`.

## Weather over time, time-lapse, seasons

All of these set values through `pm_sky.apply` (the override starts first if needed), so the existing snapshot
and `recoverPlan` restore them (new override fields `cloudBase` / `cloudTop`, tolerance 5 m). A click that sets
the same field (preset, step button, season) stops the animation / time-lapse (`pm_weather.interrupt`); the
same button again stops it (toggle). Cost: `setEnvironment` at most every 50 ms (20 Hz), the sim's cloud cover
command once a second and at the end, the marker every 3 s; each animation logs `setEnvironment avg / max ms`
at its end, a single step over 8 ms logs `step slow`.

| Control | What (pm_looks) |
|---|---|
| Storm rolls in | cloud from min(current, 0.1) to 1.0 over 40 s, smoothstep |
| Clearing | cloud from max(current, 0.9) to 0 over 40 s |
| Low clouds | cloudBase 1500 -> 500 m, cloudTop 3600 -> 1800 m, cloud at least 0.6, over 8 s (plausibility: K7) |
| Sunrise | clock from civil dawn (sun 6 degrees below) to the sun 12 degrees up, 45 s, linear; polar fallback 05:00-08:00 |
| Sunset | clock from the sun 14 degrees up (golden) to civil dusk, 45 s; fallback 18:00-21:00 |
| Run the clock | 600 game s per real s (a day in 2.4 min) until stopped; runs on during a tour |
| Winter sun / Summer sun | dayOfYear 355 / 172 (northern hemisphere: every base climate) |

Time-lapse sends `makeGameSetTimeOfDayCmd` whenever the whole second changes (every frame at 600x), with the
time cycle on Constant (the override). The sun maths now use the current climate's latitude (`pm_sky.preset`
passes `pm_weather.latitude()`; before: always temperate 0.7068).

## Sun placement (Backlight, Side light, Front light)

`pm_weather.placeSun`: look heading = `atan2` of getEye -> getCenter (fallback getCameraData angle + pi,
findings map-camera.md); the sun's azimuth `az` (from north, clockwise) and altitude from textbook solar
geometry (`P.solarPosition`: the clock as solar time, noon 12:00; declination from the day of year; the
climate's latitude); then `sunRotation = sign * (look + offset - north + az)` with offset back 0 (the sun in
front of the camera, the subject against the light), side +-pi/2 (alternates per click), front pi.
Calibration `P.SUN_CAL = { north = pi/2 (world +y), sign = +1 }` is an ASSUMPTION; K10 settles it. Log:
`sun back: look heading=.. rad (.. deg, from eye) sun azimuth=.. deg from north altitude=.. deg (day .., hh:mm,
lat ..) -> sunRotation=.. (.. deg), cal north=.. sign=..; expected sun heading .. deg`.

How K10's answers fix the calibration (offline maths, test "sun placement"): with the right sign the error is a
constant offset (the sun lands at the same place relative to the camera whatever the view): set `north` += that
offset. With the wrong sign the sun's place moves the other way when the camera turns: flip `sign`.

## In-game tests (K1-K25)

Moved to TESTING.md "Phase 4: Looks, weather over time, time-lapse, sun (K1-K13)", "Round 11 looks" (K14-K20) and
"Round 12 looks" (K21-K25).

## Integration (done 2026-10-13; round 11: Weather tab)

Round 11 (user: "photo mode is too long, we need more tabs, one for the light, one for weather"): the looks (now two
ComboBox rows, Sky and Water), the cloud presets (Clear, Overcast, Storm), Weather over time and the Clouds steps
moved to a new **Weather tab**; the Light tab keeps the time presets, Time-lapse, Season and sun and the time /
season / sun steps; the override checkbox heads both. The tab row is icons with tooltips (PLAN.md "Round 11 looks":
measured with Lato at the indicator's 16-21 px plus 36 px padding, six text labels need 503-593 px in English and
up to 701 px in nl; **the five text labels before already needed 405-475 px in English and 454-613 px in de / nl /
pl**, so the "near the 440 px" estimate below was low: the window most likely grew wider than 440 px in those
languages, inferred from font metrics, not seen in game). The text below is the round-4 state.

Built as sections of the **Light tab** between "Presets" and "Adjust" (`pm_window.looksRows`), not a sixth tab:
the five tab labels already come near the 440 px content width in de / nl (TabWidget::Indicator padding 18 + 18 per
tab, font-scale-tab-widget-indicator 16-21 px; nl "Onderwerpen Camera Beelden Rondleiding Licht" ~40 characters,
de ~34), and the indicator row doesn't wrap, so a sixth label ("Stimmungen", "Атмосферы", "Ambiances") would widen
the window. The Light tab is now tall (L9 / K-layout check in TESTING.md). Changes from the sketch below: "Low
clouds" says "Click again to stop" (it toggles like the others), "Storm rolls in" no longer promises rain ("to a
full storm cover": where rain starts is K6). Tests: `test_window.lua` "phase 4" (sections, cells, tooltips, calls,
unknown climate) and the cell count (27 on the Light tab with a base climate).

The original integration notes follow.


### Where

Recommended: a new **"Looks" tab** after "Light" (TABS in pm_window: `{ key = "looks", label = _("Looks"),
build = looksTab }`) holding the sections below, so the Light tab stays as it is. If six tab indicators don't fit
the 440 px window in de / ru (check L9-style), put the sections into the Light tab between "Presets" and
"Adjust" instead. Both need no new CSS rules: headings, `grid`, `button(..., true, true)` cells and `toggle`
cells exist (`pm_window.lua` ~265-297).

### Controls, English strings, tooltips (max 60-70 columns per line, translations into all 13 languages)

Section heading `_("Looks")`, one cell per look (`toggle`, on = `sky.status().look == key`), then an action cell:

| Key / call | Label | Tooltip |
|---|---|---|
| hazy_morning | `Hazy morning` | `Soft, warm haze with a glow round the sun.\nBest with a low morning or evening sun.` |
| crisp_clear | `Crisp & clear` | `Clear air and long views, a deeper blue sky\nand a little more contrast.` |
| misty_valley | `Misty valley` | `Mist lying in the low ground.\nBest at eye level in the morning.` |
| mirror_water | `Mirror water` | `Still water that mirrors the scene.` |
| stormy_sea | `Stormy sea` | `Rough water with foam under a dark, hard sky.\nTry it with Storm rolls in.` |
| moonlit_night | `Moonlit night` | `A bright moon and a cool blue night.\nOnly shows at night.` |
| dramatic | `Dramatic` | `Strong contrast and a big, glowing sun.` |
| storybook | `Storybook` | `A soft pastel sky and warm light,\nlike a picture book or a model railway.` |
| `sky.look(nil)` (button cell, enabled while a look is on) | `Original look` | `Your climate's own look again.` |

Under the grid, dim annotation (`font-scale-annotation, sqpm-wrap`, as the Light tab's note):
`A look changes only the picture, never your save. It ends when you open the menu.`
When `#sky.looks() == 0` instead of the grid: `This map's climate has no looks: they are made for the four base climates.`

Section heading `_("Weather over time")` (`toggle` cells, on = `sky.status().weather == kind`; `sky.weather(kind)`):

| kind | Label | Tooltip |
|---|---|---|
| storm | `Storm rolls in` | `Clouds gather from a clear sky until it rains,\nover about 40 seconds. Click again to stop.` |
| clearing | `Clearing` | `The clouds thin out to a clear sky\nover about 40 seconds. Click again to stop.` |
| lowclouds | `Low clouds` | `Brings the cloud deck down low and thick.` |

Section heading `_("Time-lapse")` (`toggle` cells, on = `sky.status().lapse == kind`; `sky.lapse(kind)`):

| kind | Label | Tooltip |
|---|---|---|
| sunrise | `Sunrise` | `Runs the clock from dawn until the sun is up,\nover 45 seconds. Click again to stop.` |
| sunset | `Sunset` | `Runs the clock from the golden hour into dusk,\nover 45 seconds. Click again to stop.` |
| run | `Run the clock` | `The day passes at 10 minutes a second\nuntil you click again. Keeps running in a tour.` |

Section heading `_("Season and sun")` (action `button` cells):

| Call | Label | Tooltip |
|---|---|---|
| `sky.season("winter")` | `Winter sun` | `Midwinter: a low sun and long shadows all day.` |
| `sky.season("summer")` | `Summer sun` | `Midsummer: a high sun and short shadows.` |
| `sky.placeSun("back")` | `Backlight` | `Turns the sun to face the camera:\nthe scene stands against the light.` |
| `sky.placeSun("side")` | `Side light` | `Turns the sun to the side for long shadows across\nthe view. Click again for the other side.` |
| `sky.placeSun("front")` | `Front light` | `Turns the sun behind the camera:\nthe scene in full light.` |

Status after a sun button when the returned altitude < 0 (the window's status line):
`The sun is below the horizon now: set a time of day first.`

All weather / time-lapse / season / sun controls start the override (as the presets do); its checkbox tooltip
already says how it ends. Shown values (Time, Clouds) update at the start and end of an animation (the window
refreshes on `sky.changed`); a live readout would need `changed()` about once a second from `pm_weather` steps
(one line in `animStep` / `lapseStep`; costs a window render a second while it runs).

### pm_window diff (sketch)

```lua
-- after lightTab()
local LOOK_TEXT = { -- i18n: keys begin
	hazy_morning = { _("Hazy morning"), _("Soft, warm haze with a glow round the sun.\nBest with a low morning or evening sun.") },
	-- ... the table above, one entry per key
} -- i18n: keys end

local function looksTab()
	local st = sky.status()
	local out = { heading(_("Looks")) }
	if #st.looks == 0 then
		out[#out + 1] = text(_("This map's climate has no looks: they are made for the four base climates."), "font-scale-body, sqpm-wrap", styles().dim)
	else
		local cells = {}
		for __, key in ipairs(st.looks) do
			local t = LOOK_TEXT[key]
			cells[#cells + 1] = toggle(t[1], t[2], st.look == key, function() if st.look == key then sky.look(nil) else sky.look(key) end end)
		end
		cells[#cells + 1] = button(_("Original look"), _("Your climate's own look again."), function() sky.look(nil) end, st.look ~= nil, true)
		out[#out + 1] = grid(cells)
		out[#out + 1] = text(_("A look changes only the picture, never your save. It ends when you open the menu."), "font-scale-annotation, sqpm-wrap", styles().dim)
	end
	out[#out + 1] = heading(_("Weather over time"))
	-- toggle cells: sky.weather(kind), on = st.weather == kind (storm, clearing, lowclouds)
	out[#out + 1] = heading(_("Time-lapse"))
	-- toggle cells: sky.lapse(kind), on = st.lapse == kind (sunrise, sunset, run)
	out[#out + 1] = heading(_("Season and sun"))
	-- button cells: sky.season("winter" | "summer"), sky.placeSun("back" | "side" | "front") (status line when it returns < 0)
	return out
end
```

`test_window.lua`'s tooltip audit then covers the new cells. Translations: every label, tooltip, heading and
note above into `strings.json` for the 12 languages; `make i18n MOD=mods/square_photo_mode ARGS='--check
--lint-modinfo'`, `make tooltips MOD=mods/square_photo_mode`. description.html: a Looks paragraph and the
Changelog (rev 1 is unreleased: fold into the rev 1 entry).

### Docs the main session should bring in line (found while building)

- PLAN.md "Rev 2" item 4 says looks switch with `api.gui.game.setEnvironment(resName)` +
  `api.gui.rendering.setEnvironment`: the built design is rendering only (game.setEnvironment persists into the
  save); item 4's preset names changed (this file).
- PLAN.md "Phase 3: Light & weather": "the six values" is now eight (cloudBase, cloudTop); the sun times use the
  current climate's latitude (no longer always temperate 0.7068); `pm_sky` forwards to `pm_weather` (step,
  pause menu, start, marker field `look`).
- docs/findings: the facts in "Verified facts" above (T6, T7, isToolEnvironment, the 0..1 cloud scale vs the
  wiki's 0..0.5).
- TESTING.md: K1-K12 (this file) into the Photo Mode checklist; regression: K3, K4, K5.
- CLAUDE.md "Commands": `uv run tools/gen_photo_looks.py [--check]` (or a make target).

## Round 15: more looks, arrows, sliders (built 2026-10-14, untested: TESTING.md LS1-LS8)

User: "Is it possible to add more looks, and have them changeable with arrows < > and also a picker? Can season, time
of day, and sun direction be sliders?"

### What an env file can do for a "look" (shaders, findings environment.md "No colour grade in an env file")

There is no colour-grade field: `hdr/compose.fs` is exposure, bloom and the AMD tone mapper. Its saturation follows
its contrast (`amdTonemapperOpt`: the colour ratio raised to `0.75 c + 0.25`), so `hdrContrastDay[1]` is also the
picture's saturation, and colour comes from the light: the ozone layer's `absorptionCoeff` / `absorptionScale` (in
every transmittance to the sun: blue-absorbing ozone warms the sunlight, green-absorbing turns twilight magenta,
red-absorbing cools it), the Rayleigh colour, the ambient fill, the sunset boost; water colour is the
`depthColorTex` gradient. So, of the ideas:

| Idea | Verdict |
|---|---|
| Golden hour glow | built: **Golden glow** (sky) |
| Cold blue | built: **Cold blue** (sky) |
| Noir / desaturated | not possible: no grade; the lowest contrast in range (0.5) still leaves ~60 % of the colour. Faded film goes part of the way |
| Sepia / vintage | built: **Faded film** (sky): low contrast = faded colour, warm light and fill |
| Neon dusk | built: **Neon dusk** (sky) |
| Overcast moody | not built as a sky: the clouds are live (the Overcast / Storm presets) and a moody grade overlaps Cold blue + Faded film; it would have cost 120 files |
| Dust storm (dry) | built: **Dust storm** (haze) |
| Sea mist | not built: Misty valley lighter and higher; too close to it for 180 more files |
| Smog | not built: a thinner Dust storm (yellow-brown absorbing aerosol); can replace Dust storm or come later |
| Tropical turquoise | built: **Tropical turquoise** (water: tropical's depth colours) |
| Dark / deep, Muddy | not built (each water look adds 216 files): Dark = extinction ~0.4, roughness 0.2, normals x0.6; Muddy = a brown `depthColorTex` of our own (DDS authoring) or dry's teal-green with extinction ~0.6 |

### The new looks (generator SKY / HAZE / WATER; every value inside RANGES; `sunsetBoostParam` 0.05-2 added)

| Look | Layer | Changes |
|---|---|---|
| Golden glow | sky | absorptionCoeff = {0.04, 0.30, 0.95} (ozone absorbing blue), absorptionScale = 0.012 (3-12x the climates'); sunsetBoostScale = 5, sunsetBoostParam = 0.5 (the glow lasts higher: boost 2.0 at a 30-degree sun vs the climate's 1.3); sunBloom = 200, sunBloomScale x1.8; ambientDayColor = {0.10, 0.075, 0.045}, hdrExposureDay x1.05 |
| Cold blue | sky | absorptionCoeff = {0.62, 0.78, 0.06} (ozone absorbing red / green), absorptionScale = 0.008; rayScatteringScale x1.15, sunsetBoostScale x0.5; ambientDayColor = {0.03, 0.042, 0.07}, ambientNightColor = {0.005, 0.01, 0.025}, hdrExposureDay x0.95, hdrContrastDay[1] +0.15 |
| Faded film | sky | hdrContrastDay[1] -0.5 (0.8-0.9: saturation ratio ^ ~0.85), hdrContrastNight = 0.8; ambientDayColor = {0.12, 0.10, 0.07} (lifted warm shadows); absorptionCoeff = {0.04, 0.30, 0.95}, absorptionScale = 0.008; rayScatteringScale x0.8; hdrExposureDay x1.1 |
| Neon dusk | sky | absorptionCoeff = {0.20, 0.97, 0.10} (ozone absorbing green: magenta twilight), absorptionScale = 0.012; rayScatteringCoeff = {0.12, 0.33, 0.94}; sunsetBoostScale = 7; ambientDayColor = {0.06, 0.035, 0.07}, ambientNightColor = {0.04, 0.012, 0.06}, hdrExposureNight x1.4, hdrContrastNight = 1.4, hdrContrastDay[1] +0.3 |
| Dust storm | haze | mieScatteringScale = 0.2 (and Overcast), mieScatteringCoeff = {0.66, 0.58, 0.48}, mieAbsorptionScale = 0.06 (and Overcast) with mieAbsorptionCoeff = {0.25, 0.45, 0.86} (dust absorbing blue: orange-brown), mieScaleHeight = 1.2 (fills the sky's column on purpose: round 11's "murk"), miePhaseG = 0.75 / Overcast 0.6, fogScaleLow = 6, fogScaleHigh = 3 |
| Tropical turquoise | water | depthColorTex = `::/climates/tropical/depthColor.dds` (cyan #7beef6 to deep blue #081c29 instead of teal-green #6ad6b4 to #183029; on the Tropical map its own colour), extinctionCoeff = 0.02, roughness = 0.3 |

Two new fields enter the layers: `absorptionCoeff` and `sunsetBoostParam` (sky), `mieAbsorptionCoeff` (haze); the
generator's disjoint-field check still passes. Every value is inferred from the shaders; how strong each reads in
game is LS1.

### File count and load time

4 x (9 x 6 x 5 - 1) = **1076 files, 4541 KB** (396 / 1858 KB in round 12). The headers now list only the changes
(the intent paragraphs stay in the generator): without that cut, 5184 KB. Load time (findings environment.md
"Hundreds of mod env files cost no measurable load time"): the same map loaded with 0 and 396 files showed no
difference (enter game 6.7-7.4 s vs 6.7-8.5 s, main menu at 4-5 s both; the run-to-run spread is larger), so 2.7x
the files is expected to stay within the noise (inferred, LS2 measures). Budget: ~1,000 files / ~5 MB (user). Every
further look costs: a sky 120 files, a haze 180, a water 216. Choices if 1076 is too many: drop Neon dusk or Cold
blue (956), or Tropical turquoise (860).

### Arrows and pickers (Weather tab)

Each look row: `<`, the dropdown, `>` (compact outlined buttons, tooltips "Previous look." / "Next look."), in a
horizontal BoxLayout in the row's control box. `pm_looks.stepLook(layer, current, dir)`: Original first, wrapping
round at both ends; each click is a normal `sky.layer` switch (one env switch, logged).

### Sliders (Light tab "Adjust")

Time of day (0..1439 minutes, keys step 10, page 60), Season (day of year 1..365, page 15) and Sun direction
(sunRotation 0..359 whole degrees, absolute; 0 = the climate's own direction; the Light angle buttons still place it
relative to the camera) as base `builtin.Slider`s (findings gui.md "builtin.Slider"), each between `<` / `>` step
buttons (10 minutes, 15 days, 15 degrees; round 4's `<<` / `>>` hour steps dropped: the slider does coarse) with the
value text after it (hh:mm, a date "21 Jun" through translated month names and a `{day} {month}` pattern, degrees).
`gui/pm_slider.lua`: a recipe per row holding the dragged value in its own state (only the row re-renders), live
writes through `pm_light.throttleInput` / `throttleStep` (at most every 80 ms, the value stopped on as a trailing
write) as `pm_sky.setLive` (quiet: no log, no marker write, no window refresh; stops a time-lapse / animation moving
the same field, as a click), and the gesture's final value through `pm_sky.set` (log, marker, window refresh) at the
mouse release (`react.onMouseEvent`, as the base construction slider) or 400 ms after the last move (keys, gamepad,
a release off the row). The compass direction of the sun is not shown: `SUN_CAL` (which world heading is north,
which way sunRotation turns) is still unverified (K10), so a compass label could be wrong; the value is the
rotation in degrees.

## Round 16: strength sliders, other looks (research 2026-10-14; built: Legacy, night lights, cloud sliders)

User: "Is it possible for looks to have sliders to adjust the fade, or do they have to be preset?" and "Are there
any other look styles we could leverage?" PLAN.md "Round 16 settings".

### A look's strength: only as more files

Only `Environment.AthmostphereParams` is live (cloudCoverage, cloudBase, cloudTop, cloudScattering, dayOfYear,
sunRotation; `api/tealdef/api/type.d.tl` 5326-5343, findings environment.md "Live environment edits"); every look
field is in the env file, switched as a whole. So a strength slider = a file per step and combination. Per climate
the count is S x H x W - 1 (S, H, W: options per layer, Original included); x 4 climates, ~4.2 KB a file:

| Design | Per climate | Files | Size |
|---|---|---|---|
| Now (9 skies, 6 hazes, 5 waters) | 269 | **1076** | 4.5 MB |
| Haze strength Light / Full (each of the 5 hazes at 50 % and 100 %) | 494 | 1976 | 8.2 MB |
| Haze strength 1/3, 2/3, Full | 719 | 2876 | 11.9 MB |
| Haze strength 25 / 50 / 75 / 100 % | 944 | 3776 | 15.6 MB |
| Sky strength 3 steps (8 skies) | 749 | 2996 | 12.4 MB |
| Every layer 3 steps | 5199 | 20796 | 86 MB |
| Haze Light / Full, the Light ones only with the climate's water (a dropdown rule) | 314 | 1256 | 5.2 MB |
| Soft background alone at 3 strengths | 359 | 1436 | 5.9 MB |

A step would blend each changed field from the climate's value to the look's (a `mul` factor f^s, a `set` value
linearly), so the generator could make them. Load-time evidence (findings environment.md "Hundreds of mod env
files"): 0, 396 and 1076 files load the same map in the same time (5.6-8.5 s, one run with 1076), and nothing is
known past that; the user's budget (round 15) is ~1,000 files / ~5 MB, already reached. **Not built.** If the
budget may grow: Haze Light / Full (1976) is the one that matches "the fade" (haze is what fades the distance).

Live instead (built, Weather tab "Adjust"): Clouds 0-100 %, Cloud height 100-4000 m, Cloud density 10-400 % (the
cloud march's scattering coefficient). The cloud cover also fades the haze a little: below the cloud base the veil
is x (1 - 0.75 x cover) and the `*Overcast` mie values most likely blend in with it (findings environment.md "Haze:
the sky sees the whole mie column").

### Other looks

| Look | What | Cost | Verdict |
|---|---|---|---|
| **Legacy** | the base game's `<climate>_old.env` "(Legacy)" atmospheres: 10 km height offset, thin Rayleigh spread 100 km high (a paler sky), 3x aerial perspective, exposure 1.72 (findings environment.md "The base game's other environments") | 0 files: switched to as they are, a whole look in the Sky menu (brings its own haze and water) | **built** (TESTING.md RS8) |
| **Night lights** | `light.globalEmissiveScale` x2 (Moonlit night) / x2.5 (Neon dusk): lit windows and lamps glow brighter (`physical.fs:455`, `emissive.fs:45`) | 0 new files (240 rewritten) | **built** (RS9) |
| Rain | the live cloud cover from 0.8 rains (`rain.fs`); Storm (1.0) and the Clouds slider already do it | 0 | nothing to add (RS6) |
| Long twilight | `sunsetOffset` (0.08) lifts the sun direction the sky and haze scattering use (`atmosphere/common.glsl:268`, in `integrateScatteredLuminance`): a larger one keeps the sky lit after sunset, a longer twilight (inferred) | a sky: +120 | candidate |
| Starry night | brighter stars: the skyBox `starsTex` / `starsTexMask` (a mask texture of our own) | a sky: +120 + a DDS | candidate |
| Overcast moody, Sea mist, Smog, Dark / deep water, Muddy water | round 15's list (LOOKS.md "Round 15") | +120 / +180 / +180 / +216 / +216 | not built (budget) |
| Studio | the model editor envs (studio light, `useSkyBoxOverwrite`) | 0 (whole look) | not added: Legacy-like atmospheres made for a void |
| Subarctic "(Test)" | `subarctic2.env`: a tone-map test (`hdrTarget` 0, `hdrMax` 16) | 0 | not added: a test file |
| Campaign atmospheres | the campaign's env files are the base climates (mission 7: clearer water) | - | none exist |
| Snow, wetness, wind, lightning, a bigger moon | no field in any shader (`dayOfYear` reaches no shader; the moon has no size field) | - | not possible |

## Open questions for the user

1. Does a look switch visibly change the picture (T7 left it open), and do the eight read as intended (K2)?
2. Where does rain start on the 0..1 scale (K6)? Storm rolls in ends at 1.0 (the base "rainy" mean). Round 16: the rain shader shows it from 0.8, fully at 1.0 (findings environment.md "Rain"; RS6).
3. Sun calibration (K10): where does Backlight put the sun at two headings?
4. Does dayOfYear change snow / foliage, or only the sun (K9)?
5. Unknown climates get no looks (decided above); prefer the closest base climate's looks instead?
6. ~~A separate "Looks" tab, or the sections inside the Light tab?~~ Round 11: a Weather tab (user).
7. Round 11: do the pushed looks read as dramatic and distinct (K15), is Wild water rapids on a river (K14)?
8. Depth of field: build the PC-only tilt-shift companion mod (a base shader override, "Depth of field and shaders")?
