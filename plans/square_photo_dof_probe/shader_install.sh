#!/bin/sh
# DEV DoF probe: copy the probe shader into the game install, or put the base file back.
#   sh plans/square_photo_dof_probe/shader_install.sh status|install|restore
# Quit the game first. A mod can't replace a base shader (docs/findings/environment.md "Shaders"), so this edits
# <game>/base/content/rendering/programs/shaders/misc/ssr_apply.fs directly. The original goes to
# .cache/sqdof_backup/ssr_apply.fs; restore copies it back (Steam "Verify integrity of game files" does too).
# Both remove the compiled ssr_apply pipeline from the shader cache so the game recompiles it at the next start.
set -eu
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GAME="${TF3_GAME_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/Transport Fever 3}"
REL="base/content/rendering/programs/shaders/misc/ssr_apply.fs"
DST="$GAME/$REL"
SRC="$REPO/mods/square_photo_dof_probe/shader_files/$REL"
BAK="$REPO/.cache/sqdof_backup/ssr_apply.fs"
BASE_SHA="3d5a2ed8cff5a3d338c8b1457ac9b36a3b81526997bf8a48985af5bc5a196a5b"  # build 40420

clear_cache() {
	n=0
	for c in "$HOME/Library/Application Support/Steam/userdata"/*/3493540/local/shader_cache; do
		[ -d "$c" ] || continue
		for f in "$c"/rendering_programs_ssr_apply.prog_*; do
			[ -e "$f" ] || continue
			rm -f "$f"; n=$((n + 1))
		done
	done
	echo "shader cache: removed $n ssr_apply file(s) (if the change doesn't show: delete the whole shader_cache folder)"
}

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

[ -f "$DST" ] || { echo "not found: $DST (set TF3_GAME_DIR)"; exit 1; }
case "${1:-status}" in
status)
	s="$(sha "$DST")"
	if [ "$s" = "$BASE_SHA" ]; then echo "game file: base (build 40420)";
	elif grep -q 'sqdof:' "$DST"; then echo "game file: PROBE installed";
	else echo "game file: unknown version ($s): game update or another mod (e.g. Realistic Environment Pro)"; fi
	[ -f "$BAK" ] && echo "backup: $BAK ($(sha "$BAK"))" || echo "backup: none"
	;;
install)
	if grep -q 'sqdof:' "$DST"; then echo "probe already installed; copying the current probe file again";
	else
		s="$(sha "$DST")"
		[ "$s" = "$BASE_SHA" ] || { echo "game file is not the build 40420 base ($s): stop (game update or another shader mod). Compare it with the probe's base first."; exit 1; }
		mkdir -p "$(dirname "$BAK")"; cp "$DST" "$BAK"; echo "backup -> $BAK"
	fi
	cp "$SRC" "$DST"; echo "installed -> $DST"
	clear_cache
	;;
restore)
	[ -f "$BAK" ] || { echo "no backup: use Steam > Transport Fever 3 > Properties > Installed Files > Verify integrity"; exit 1; }
	cp "$BAK" "$DST"; echo "restored base -> $DST ($(sha "$DST"))"
	clear_cache
	;;
*) echo "usage: $0 status|install|restore"; exit 2 ;;
esac
