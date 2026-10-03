# TF3 mod hub. All tools are stdlib/PEP 723 scripts run through uv.
UV := uv run --quiet

.PHONY: help docs docs-wiki docs-game new-mod link unlink validate teal

help:
	@echo "make docs        Re-sync all local docs (wiki + game files)"
	@echo "make docs-wiki   Mirror the TF3 wiki modding manual -> docs/wiki/"
	@echo "make docs-game   Extract game text resources -> .cache/game/ (+ docs/game/)"
	@echo "make new-mod ID=author_name NAME='Display Name' [ARGS='--script --tag \"Script Mod\"']"
	@echo "make link        Symlink mods/* into the game's staging_area"
	@echo "make unlink      Remove those symlinks"
	@echo "make validate    Check all mods (or MOD=mods/<id>) against wiki rules"
	@echo "make teal        Generate tlconfig.lua for VS Code Teal autocompletion"

docs: docs-wiki docs-game

docs-wiki:
	$(UV) tools/sync_wiki.py

docs-game:
	$(UV) tools/sync_game.py

new-mod:
	@test -n "$(ID)" -a -n "$(NAME)" || (echo "usage: make new-mod ID=author_name NAME='Display Name'"; exit 1)
	$(UV) tools/new_mod.py $(ID) --name "$(NAME)" $(ARGS)

link:
	$(UV) tools/link_mods.py

unlink:
	$(UV) tools/link_mods.py --unlink

validate:
	$(UV) tools/validate_mod.py $(MOD)

teal:
	$(UV) tools/setup_teal.py
