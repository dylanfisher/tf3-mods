# TF3 mod hub. All tools are stdlib/PEP 723 scripts run through uv.
UV := uv run --quiet

.PHONY: help docs docs-wiki docs-game subscribed new-mod link unlink validate check test teal covers shots state-towns state-mod state-mods names-browser flags test-tools

help:
	@echo "make docs        Re-sync all local docs (wiki + game files)"
	@echo "make docs-wiki   Mirror the TF3 wiki modding manual -> docs/wiki/"
	@echo "make docs-game   Extract game text resources -> .cache/game/ (+ docs/game/)"
	@echo "make subscribed  Copy your subscribed mod.io mods -> .cache/subscribed/ (reference only)"
	@echo "make new-mod ID=square_name NAME='Display Name' [ARGS='--script --tag \"Script Mod\"']"
	@echo "make link        Symlink mods/* into the game's staging_area"
	@echo "make unlink      Remove those symlinks"
	@echo "make validate    Check all mods (or MOD=mods/<id>) against wiki rules"
	@echo "make check       Teal type-check + Lua syntax-check all mods (or MOD=mods/<id>, PATHS='file/dir ...', ARGS=--allow-lua53)"
	@echo "make test        Run offline unit tests in tests/<modId>/ (all, or MOD=mods/<id>)"
	@echo "make covers      Render square-style covers -> mods/<id>/_metadata/0.png (all, or MOD=mods/<id>; ARGS=--no-text)"
	@echo "make shots       Render gallery slides from plans/<id>/shots/ -> mods/<id>/_metadata/1.png... (all, or MOD=mods/<id>)"
	@echo "make teal        Generate tlconfig.lua for VS Code Teal autocompletion"
	@echo "make state-towns STATE=us_washington [ARGS=--fetch]  Draft data/states/<key>/towns.tsv from Census files"
	@echo "make state-mod STATE=us_washington [ARGS=--check]    Generate mods/square_names_<key> + tests from data/states/<key>"
	@echo "make state-mods [ARGS=--check]                       Generate (or check) every state mod"
	@echo "make names-browser                                   Write plans/square_state_names/names_browser.html (all state names)"
	@echo "make test-tools                                      Unit tests for the state generator tools (tests/tools)"
	@echo "make flags [STATE=us_washington] [ARGS='--lookup \"Flag of Oregon.svg\" --key us_oregon']  Fetch + sanitize pinned state flags -> branding/flags/"

docs: docs-wiki docs-game

docs-wiki:
	$(UV) tools/sync_wiki.py

docs-game:
	$(UV) tools/sync_game.py

subscribed:
	$(UV) tools/sync_subscribed.py

new-mod:
	@test -n "$(ID)" -a -n "$(NAME)" || (echo "usage: make new-mod ID=square_name NAME='Display Name'"; exit 1)
	$(UV) tools/new_mod.py $(ID) --name "$(NAME)" $(ARGS)

link:
	$(UV) tools/link_mods.py

unlink:
	$(UV) tools/link_mods.py --unlink

validate:
	$(UV) tools/validate_mod.py $(MOD)

check:
	$(UV) tools/tl_check.py $(ARGS) $(MOD) $(PATHS)

test:
	$(UV) tests/run_tests.py $(ARGS) $(MOD)

teal:
	$(UV) tools/setup_teal.py

covers:
	$(UV) tools/render_covers.py $(ARGS) $(MOD)

flags:
	$(UV) tools/fetch_flags.py $(ARGS) $(STATE)

shots:
	$(UV) tools/render_shots.py $(MOD)

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

test-tools:
	uv run --quiet --with lupa python -m unittest discover -s tests/tools $(ARGS)
