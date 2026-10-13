# Stress Test: history

Superseded designs and finished notes, moved verbatim (newest first). See plans/README.md.

## Lights showcase growth x25 (SHOWCASE.md, 2026-10-12; superseded 2026-10-12 by x10, then 2026-10-13 by x3 for ~1000 people per town)

- **Density instead of area** (Lights showcase): `LIGHTS_GROW_FACTOR` x25 (GROW_FACTORS[4]; was x10 = the Showcase's
  DENSE_GROW_FACTOR), still one size command (`LIGHTS_GROW_PASSES` 1), DENSE_WEIGHTS {0, 0.1, 0.5, 1} (tall
  buildings), every street locked (the town can only build up, never out). Why x25: the engine keeps size factors
  unclamped (x100 on Tacoma read back 100, docs/findings/lines-vehicles.md "Big growth factors"); where the streets
  are full the building count plateaus while the people per building keep rising; our cap MAX_SIZE_FACTOR 1000.
  Not x100: ~100 Medium towns at once on one map, unmeasured sim load; raise after TESTING.md 6U step 3 if the game
  keeps up. The Showcase keeps x10 in 3 passes. More people per building without any growth: the load setting
  "Town building capacity" x2 / x4 (experimental; TESTING.md 6U).
