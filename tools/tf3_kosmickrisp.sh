#!/bin/sh
# Steam launch wrapper: start TF3 with the bundled KosmicKrisp Vulkan driver instead of MoltenVK.
# macOS Steam can't take `VAR=value %command%` (OS Error 260), so set this as the launch option:
#   "/Users/dylanfisher/projects/tf3-mods/tools/tf3_kosmickrisp.sh" %command%
# Remove the launch option to go back to MoltenVK. The game log's "driver name:" line shows which one loaded.
GAME_DIR="$HOME/Library/Application Support/Steam/steamapps/common/Transport Fever 3"
export VK_DRIVER_FILES="$GAME_DIR/libkosmickrisp_icd.json"
echo "$(date '+%F %T') VK_DRIVER_FILES=$VK_DRIVER_FILES exec: $*" >> "${TMPDIR:-/tmp}/tf3_kosmickrisp.log"
exec "$@"
