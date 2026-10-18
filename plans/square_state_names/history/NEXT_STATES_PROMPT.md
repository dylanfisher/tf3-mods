# Prompt: pick the next states and plan the rollout

Status: done 2026-10-08 (produced NEXT_STATES.md; the rollout it planned is finished).

Paste into a new session. Output: `plans/square_state_names/NEXT_STATES.md`.

```
Read CLAUDE.md, docs/findings.md ("Street names and Road Stops"), the memory note
state-names-series.md, and plans/square_state_names/{PLAN.md,research.md,TESTING.md,data_review.md}.
Washington (mods/square_names_us_washington) is the finished template for a series of US state
name mods: shared runtime in templates/state_names/, per-state data in data/states/us_<state>/,
generated with tools/gen_state_mod.py, towns drafted from Census data with tools/state_towns.py,
flag-sticker covers via Square.stateCover + tools/fetch_flags.py, slides via branding/shots.js.

Goal: recommend which states to do next and write an execution plan. Don't build any state yet.

1. Shortlist 8-12 states and rank them. Score each on:
   - player appeal: recognisable cities, rail and transit history, TF3 player base (US and international)
   - data feasibility: enough Census places (300+ towns), well-known real streets for 10+ cities,
     real rail stations, airports and harbours to name
   - climate fit: how well the state's regions map to TF3's climates (temperate, dry,
     subarctic, tropical) through the region tags in state.lua (e.g. Arizona/New Mexico for dry,
     Alaska for subarctic, Florida/Hawaii for tropical, Washington-style west/east splits)
   - flag: public-domain SVG on Wikimedia Commons, and how it reads as a sticker at thumbnail size
   - overlap with other state mods: shared city names such as Portland (OR/ME) or Springfield.
     Say how the existing isActive/ownership rule handles it.
   Also check mod.io (game transportfever3) for existing name-set mods per state and note conflicts.
2. Pick a first batch of 3 and say why: one each that exercises a different climate.
3. Write plans/square_state_names/NEXT_STATES.md with:
   - the ranked table and the batch choice
   - per-state data recipe: Census FIPS, how to draw the region/climate boundary in towns_config.json
     (the equivalent of Washington's Cascade crest), which cities get street, neighbourhood,
     rail, airport and harbour lists, and where facts get verified (OpenStreetMap spot checks,
     official transit agency station lists)
   - template gaps a new state would expose, with the fix in templates/ or the generator
     (e.g. climates Washington never needed, states with no passenger rail, non-ASCII names
     like Hawaiian ʻokina, very long names)
   - a repeatable per-state checklist: data → make state-towns → make state-mod →
     make check/test/validate → flag → cover → in-game test (TESTING.md) → slides → release date
   - phases, run one subagent per state (main session orchestrates, per memory phases-in-subagents),
     with done criteria for each
   - a data-quality gate: only real, verifiable names; uncertain entries go to that state's
     data_review section instead of shipping
4. List the decisions I need to make (batch, naming, release cadence) as a short question list at the end.

Report: the ranked shortlist, the recommended first batch, and the path to NEXT_STATES.md.
```
