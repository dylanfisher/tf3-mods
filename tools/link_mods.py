# /// script
# requires-python = ">=3.11"
# ///
"""Symlink every mod in mods/ into the game's staging_area.

Edits in this repo are then picked up by the game and the Model Editor.
Never touches staging_area entries that are real folders or links pointing
elsewhere. Removes dangling links that point into this repo.

Usage: uv run tools/link_mods.py [--unlink] [--dry-run]
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR, ROOT, staging_area  # noqa: E402


def points_into_repo(link: Path) -> bool:
    target = Path(os.readlink(link))
    return ROOT in target.parents or target == ROOT


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--unlink", action="store_true", help="remove links this hub created")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    staging = staging_area()
    staging.mkdir(parents=True, exist_ok=True)
    act = (lambda msg, fn: print(f"[dry-run] {msg}")) if args.dry_run else (lambda msg, fn: (fn(), print(msg)))

    for entry in sorted(staging.iterdir()):
        if entry.is_symlink() and points_into_repo(entry) and (args.unlink or not entry.exists()):
            act(f"unlinked {entry.name}", entry.unlink)
    if args.unlink:
        return

    mods = sorted(p for p in MODS_DIR.iterdir() if p.is_dir() and (p / "mod.json").exists())
    for mod in mods:
        link = staging / mod.name
        if link.is_symlink():
            if Path(os.readlink(link)) == mod:
                print(f"ok      {mod.name}")
            else:
                print(f"SKIP    {mod.name}: staging_area link points to {os.readlink(link)}")
        elif link.exists():
            print(f"SKIP    {mod.name}: a real folder already exists in staging_area; move it into mods/ first")
        else:
            act(f"linked  {mod.name} -> {link}", lambda m=mod, l=link: l.symlink_to(m, target_is_directory=True))
    if not mods:
        print("No mods in mods/ yet (create one with `make new-mod`).")
    print(f"staging_area: {staging}")


if __name__ == "__main__":
    main()
