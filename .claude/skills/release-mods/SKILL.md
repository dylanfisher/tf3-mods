---
name: release-mods
description: Release checklist for publishing mod updates to mod.io (make modio-status, Hub upload, Changelog line, make modio sync). Use when the user wants to upload, publish or release a mod update, or sync a mod's mod.io profile.
---

# Releasing updates

The user runs every `make modio*` command (1Password prompt); Claude asks for the pasted output.

**Always start from `make modio-status` output, before any revision bump or changelog text.** Uncommitted
work can already be live (the Hub uploads from the staging area, not from git), so a revision that git shows
as new may be published. A fix made after the live revision goes into a new revision, never into the live one's
entry. Without that output, ask for it; don't guess.

0. **Full tests:** `make gate-full MOD=mods/<id>` for every mod about to be uploaded whose files changed since
   its last full pass (cached files are instant). Phases only run the quick `make gate`, so this is the first time
   the slow tests and full sweeps see the work. Fix any failure before the upload.
1. **Before:** `make modio-status` lists which mods differ from their live upload (Towns & Streets and Blank Slate only with `MOD=` or `ARGS=--all`). "Needs a Hub update": ready.
   "Changed, revision not bumped": bump `revision` in `mod.json` and add a Changelog entry to `description.html` first.
   REVISION is the **live** one. A "newer upload not live: rev N ... rejected / waiting" line under a row means rev N
   was uploaded but never went live (e.g. rejected by the review): re-upload as rev N with the fix and its entry
   amended, don't bump past it and don't treat rev N as published.
2. **Upload** (restart the game first if `make shots` ran since it started: the Hub uploads the slide list it read at
   start and fails "File not found" on renamed slides): those mods in game: Mod Hub → My Mods. The upload dialog has a one-line **Changelog** field: for every
   mod about to be uploaded, give the user a ready-to-paste line (plain text, about 150 characters at most, no
   markup) summarising every Changelog entry in `description.html` newer than the live revision (`make modio-status`
   shows it). The line always starts with "Revision N: " (the new revision; several entries: the newest), e.g.
   "Revision 3: the vehicle list shows each vehicle's current cargo and load."
3. **After:** `make modio ARGS=--diff` should say "in sync" (`--verify` also compares the slide bytes). The Hub
   sends the description and keeps slides named `N-<hash>.png` intact (at most 9: a 10-slide gallery came out of
   order, which `make modio MOD=mods/<id> ARGS='--apply --only gallery'` repairs), but an older stale description or
   `N.png` slides need `make modio ARGS=--apply`. `make modio-status` should now say "Up to date". A fresh upload shows as
   "Uploaded, waiting for mod.io" until mod.io's scan makes it live. See `docs/findings.md` "Mod Hub uploads and the
   mod.io gallery".

Changes to slides, the cover or the description alone need no Hub upload: just `make modio ARGS=--apply`.
