# TF3 mod hub. All tools are stdlib/PEP 723 scripts run through uv.
UV := uv run --quiet

.PHONY: help docs docs-wiki docs-game subscribed new-mod link unlink validate check test teal covers shots state-towns state-mod state-mods names-browser flags gate test-tools probe-report probe-split hx-dump fork-new fork-status fork-merge fork-finish fork-abort forks-save forks-push sqperf-sync perf audit flow bench logs logs-list logs-grep modio modio-status more-from i18n tooltips css-rules site-install site-dev site-media site-build site-deploy

help:
	@echo "make docs        Re-sync all local docs (wiki + game files)"
	@echo "make docs-wiki   Mirror the TF3 wiki modding manual -> docs/wiki/"
	@echo "make docs-game   Extract game text resources -> .cache/game/ (+ docs/game/)"
	@echo "make subscribed  Copy your subscribed mod.io mods -> .cache/subscribed/ (reference only)"
	@echo "make fork-new UP=<upstreamModId>  Local SQ Opt fork of a subscribed mod -> mods/square_opt_<id>/ (gitignored)"
	@echo "make fork-status                  Which forks have a newer upstream revision (after make subscribed)"
	@echo "make fork-merge FORK=<forkId> [ARGS='--from DIR']  Three-way merge newer upstream into the fork"
	@echo "make fork-finish FORK=<forkId>    After resolving conflicts: adopt the new upstream base"
	@echo "make fork-abort FORK=<forkId>     Restore the fork from its pre-merge backup"
	@echo "make forks-save [MSG='...']       Commit the fork paths to the private backup repo (.forks-git)"
	@echo "make forks-push                   Push the private backup repo"
	@echo "make new-mod ID=square_name NAME='Display Name' [ARGS='--script --tag \"Script Mod\"']"
	@echo "make link        Symlink mods/* into the game's staging_area"
	@echo "make unlink      Remove those symlinks"
	@echo "make validate    Check all mods (or MOD=mods/<id>) against wiki rules"
	@echo "make check       Teal type-check + Lua syntax-check all mods (or MOD=mods/<id>, PATHS='file/dir ...', ARGS=--allow-lua53)"
	@echo "make test MOD=mods/<id>  Offline unit tests in tests/<modId>/, quick mode, cached per file (ARGS="-f FILE -k TEXT --full --no-cache")"
	@echo "make gate MOD=mods/<id> [MOD2=mods/<id>]  check + validate + test --full, one summary line each (end-of-phase gate)"
	@echo "make covers      Render square-style covers -> mods/<id>/_metadata/0.png (all, or MOD=mods/<id>; ARGS=--no-text)"
	@echo "make shots       Render gallery slides from plans/<id>/shots/ -> mods/<id>/_metadata/1-<hash>.png... (all, or MOD=mods/<id>)"
	@echo "make modio [MOD=mods/<id>] [ARGS='--diff --apply --only gallery --force --prune-tags']  Dry-run/sync mod.io text, tags, logo, gallery"
	@echo "make modio-status [MOD=mods/<id>] [ARGS='--verbose --all']  Which mods changed since their live mod.io upload (need a Hub update; --all adds Towns & Streets + Blank Slate)"
	@echo "make more-from [MOD=mods/<id>] [ARGS=--published|--refresh|--check]  Write the More from square section (branding/more_from.json) into a description"
	@echo "make i18n [MOD=mods/<id>] [ARGS='--check --json --missing ru --fix-format --lint-modinfo -v']  strings.json translation report (keys, missing, placeholders)"
	@echo "make teal        Generate tlconfig.lua for VS Code Teal autocompletion"
	@echo "make sqperf-sync [MOD=mods/<id>] [ARGS=--check]  Copy tools/sqperf/ into mods using SQPERF (MOD: add it there)"
	@echo "make perf [LOG=path]  Per-mod [SQPERF] report from the latest stdout.txt (or LOG)"
	@echo "make audit [LOG=path] [ARGS='--last --src auto --top 5']  Smart Lanes junction audit report ([SQRL] AUDIT lines)"
	@echo "make flow [LOG=path] [ARGS='--last --warmup 180 --worse-pct 10 --min-samples 5 --retime-settle 60 --auto-settle 900']  Traffic flow A/B report: Showcase twins sl / sl_phases / sl_auto / ... vs game, light plans per shape and demand, auto timing as built/settled, whole-map auto re-time before/after, Re-time before/after ([SQST] FLOW_* lines)"
	@echo "make bench [LOG=session] [ARGS='--record --warmup 180']  Stress Test bench report: the last bench sheet's run (default LOG=last-bench) -> draft RESULTS.md entry in .cache/bench/; --record appends it"
	@echo "                 (perf/audit/flow archive the live log first; LOG= also takes a session name/alias: last, last-crash, last-<tag>, a seed)"
	@echo "make logs [ARGS='--tag NAME']  Archive the live stdout.txt and crash_dump logs -> .cache/logs/; print the newest sessions"
	@echo "make logs-list [ARGS='--tag SQRL --crash --grep TEXT --since 2026-10-01 --last 5 -v']  Archived/crash sessions (.cache/logs/INDEX.md)"
	@echo "make logs-grep PAT='regex' [ARGS='--tag X --since DATE --session last -C 2 --max 50 -i']  Search every archived/crash log"
	@echo "make state-towns STATE=us_washington [ARGS=--fetch]  Draft data/states/<key>/towns.tsv from Census files"
	@echo "make state-mod STATE=us_washington [ARGS=--check]    Generate mods/square_names_<key> + tests from data/states/<key>"
	@echo "make state-mods [ARGS=--check]                       Generate (or check) every state mod"
	@echo "make names-browser                                   Write plans/square_state_names/names_browser.html (all state names)"
	@echo "make probe-report [LOGS='plans/square_roundabouts/probe_x.log ...']  Parse probe logs (default: the Phase 7 logs present) + print a summary"
	@echo "make probe-split LOG=plans/square_roundabouts/probe_x.log [ARGS=--uncap]  Which build feature (reach, edge, grade) splits placed vs refused"
	@echo "make hx-dump KEY='h:1,3,2,2,1,1,1,1,2 ...' [DEV='sqrb_dev_x=1']  Highway Interchange edges (lengths, bridges) per probe key"
	@echo "make test-tools                                      Unit tests for the Python tools (tests/tools)"
	@echo "make flags [STATE=us_washington] [ARGS='--lookup \"Flag of Oregon.svg\" --key us_oregon']  Fetch + sanitize pinned state flags -> branding/flags/"
	@echo "make site-dev    Mod microsites (site/, tf3.dylanfisher.com): Astro dev server (installs deps on first run)"
	@echo "make site-media [ARGS='--force --mod <modId>']  Manifest images -> site/public/media/ WebP (thumb + full, hash-cached)"
	@echo "make site-build  site-media + astro build -> site/dist/ (pnpm run build)"
	@echo "make site-deploy Build and push site/dist/ to the public Pages repo (SITE_REMOTE, SITE_BRANCH; DRY_RUN=1 to skip the push)"

docs: docs-wiki docs-game

docs-wiki:
	$(UV) tools/sync_wiki.py

docs-game:
	$(UV) tools/sync_game.py

subscribed:
	$(UV) tools/sync_subscribed.py

fork-new:
	@test -n "$(UP)" || (echo "usage: make fork-new UP=<upstreamModId>"; exit 1)
	$(UV) tools/fork_mod.py new $(UP)

fork-status:
	$(UV) tools/fork_mod.py status

fork-merge:
	@test -n "$(FORK)" || (echo "usage: make fork-merge FORK=<forkId>"; exit 1)
	$(UV) tools/fork_mod.py merge $(FORK) $(ARGS)

fork-finish:
	@test -n "$(FORK)" || (echo "usage: make fork-finish FORK=<forkId>"; exit 1)
	$(UV) tools/fork_mod.py finish $(FORK)

fork-abort:
	@test -n "$(FORK)" || (echo "usage: make fork-abort FORK=<forkId>"; exit 1)
	$(UV) tools/fork_mod.py abort $(FORK)

# Private backup of the gitignored third-party paths: a second repo with git dir .forks-git/ and this working tree.
FORKS_GIT := git --git-dir=.forks-git
FORK_PATHS := ':(glob)mods/square_opt_*/**' mods/square_aat_perftest forks ':(glob)plans/*/original/**'

forks-save:
	@test -d .forks-git || (echo "no .forks-git/ (see CLAUDE.md, Forks)"; exit 1)
	$(FORKS_GIT) add -A -f -- $(FORK_PATHS)
	@if $(FORKS_GIT) diff --cached --quiet; then echo "forks: nothing to save"; \
	else $(FORKS_GIT) commit -q -m "$(or $(MSG),Fork backup $$(date +%Y-%m-%d))" && $(FORKS_GIT) log --oneline -1; fi

forks-push:
	$(FORKS_GIT) push

new-mod:
	@test -n "$(ID)" -a -n "$(NAME)" || (echo "usage: make new-mod ID=square_name NAME='Display Name'"; exit 1)
	$(UV) tools/new_mod.py $(ID) --name "$(NAME)" $(ARGS)

link:
	$(UV) tools/link_mods.py

unlink:
	$(UV) tools/link_mods.py --unlink

validate:
	$(UV) tools/validate_mod.py $(MOD)

i18n:
	$(UV) tools/i18n.py $(ARGS) $(MOD)

css-rules:
	$(UV) tools/css_rules.py $(MODS)

tooltips:
	$(UV) tools/tooltips.py $(ARGS) $(MOD)

check:
	$(UV) tools/tl_check.py $(ARGS) $(MOD) $(PATHS)

test:
	$(UV) tests/run_tests.py $(ARGS) $(MOD)

gate:
	@for m in $(MOD) $(MOD2); do echo "== $$m"; \
		$(UV) tools/tl_check.py $$m 2>&1 | tail -1; \
		$(UV) tools/validate_mod.py $$m 2>&1 | tail -1; \
		$(UV) tests/run_tests.py --full $$m 2>&1 | grep -E "^ *FAIL|passed" || exit 1; \
	done

teal:
	$(UV) tools/setup_teal.py

sqperf-sync:
	$(UV) tools/sqperf_sync.py $(ARGS) $(MOD)

# Log reports archive the live stdout.txt first (never fatal), and LOG= takes a file or an archived session
# name/alias (game_logs.py path). Every new log report target does the same.
LOG_SAVE = $(UV) tools/game_logs.py save --quiet || true
LOG_FILES = $(if $(LOG),logs="$$($(UV) tools/game_logs.py path $(LOG))" || exit 1;,logs="";)

perf:
	@$(LOG_SAVE)
	@$(LOG_FILES) $(UV) tools/perf_report.py $(ARGS) $$logs

audit:
	@$(LOG_SAVE)
	@$(LOG_FILES) $(UV) tools/sqrl_audit.py $(ARGS) $$logs

flow:
	@$(LOG_SAVE)
	@$(LOG_FILES) $(UV) tools/flow_report.py $(ARGS) $$logs

bench:
	@$(LOG_SAVE)
	@logs="$$($(UV) tools/game_logs.py path $(or $(LOG),last-bench))" || exit 1; $(UV) tools/bench_report.py $(ARGS) $$logs

logs:
	@$(UV) tools/game_logs.py save --show 5 $(ARGS)

logs-list:
	@$(UV) tools/game_logs.py list $(ARGS)

logs-grep:
	@test -n "$(PAT)" || (echo "usage: make logs-grep PAT='regex' [ARGS='--tag X --since DATE --session NAME -C 2 --max N -i']"; exit 1)
	@$(UV) tools/game_logs.py grep '$(PAT)' $(ARGS)

covers:
	$(UV) tools/render_covers.py $(ARGS) $(MOD)

flags:
	$(UV) tools/fetch_flags.py $(ARGS) $(STATE)

shots:
	$(UV) tools/render_shots.py $(MOD)

modio:
	$(UV) tools/modio_sync.py $(ARGS) $(MOD)

more-from:
	$(UV) tools/more_from.py $(ARGS) $(MOD)

modio-status:
	$(UV) tools/modio_sync.py --release $(ARGS) $(MOD)

state-towns:
	@test -n "$(STATE)" || (echo "usage: make state-towns STATE=us_washington [ARGS=--fetch]"; exit 1)
	$(UV) tools/state_towns.py $(STATE) $(ARGS)

state-mod:
	@test -n "$(STATE)" || (echo "usage: make state-mod STATE=us_washington [ARGS=--check]"; exit 1)
	$(UV) tools/gen_state_mod.py $(STATE) $(ARGS)

names-browser:
	$(UV) tools/render_names_browser.py

state-mods:
	$(UV) tools/gen_state_mod.py --all $(ARGS)

PROBE_LOGS := $(wildcard plans/square_roundabouts/probe_p7_hx_all.log plans/square_roundabouts/probe_p7_hx_search.log plans/square_roundabouts/probe_p7_verify.log plans/square_roundabouts/probe_p7_hx_scale.log plans/square_roundabouts/probe_p7_presets.log plans/square_roundabouts/probe_p7_hx_scale_verify.log)
probe-report:
	@for f in $(or $(LOGS),$(PROBE_LOGS)); do \
		case $$f in *search*) fr=--fresh;; *) fr=;; esac; \
		echo "== $$f"; $(UV) tools/parse_probe.py --summary $$fr --stdout $$f $(ARGS) || exit 1; \
	done

probe-split:
	@test -n "$(LOG)" || (echo "usage: make probe-split LOG=plans/square_roundabouts/probe_<run>.log [ARGS='--uncap --near xmax']"; exit 1)
	@uv run --quiet --with lupa python tools/probe_split.py $(LOG) $(ARGS)

hx-dump:
	@SQRB_HX_KEY='$(KEY)' SQRB_HX_DEV='$(DEV)' uv run --quiet --with lupa python -c "import sys; sys.path.insert(0, 'tests'); \
	import run_tests as r; from pathlib import Path; \
	o = r.ModRunner(Path('mods/square_roundabouts')).run_file(Path('tools/dump_square_roundabouts_highway.lua'), None); \
	[print(x['printed'] if x['ok'] else x['err'], end='') for x in o['results']]; sys.exit(bool(o['load_error'] or not all(x['ok'] for x in o['results'])))"

test-tools:
	uv run --quiet --with lupa python -m unittest discover -s tests/tools $(ARGS)

# ---- Mod microsites (site/: Astro + pnpm; plans/site/PLAN.md) ----
SITE_PNPM := cd site && pnpm

site-install:
	@test -d site/node_modules || ($(SITE_PNPM) install --frozen-lockfile)

site-dev: site-install
	$(SITE_PNPM) exec astro dev

site-media: site-install
	$(SITE_PNPM) exec node scripts/media.mjs $(ARGS)

site-build: site-install
	$(SITE_PNPM) run build

site-deploy: site-install
	cd site && scripts/deploy.sh
