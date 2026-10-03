# /// script
# requires-python = ">=3.11"
# ///
"""Scaffold a new mod in mods/<modId>/ following the TF3 wiki mod definition.

Usage:
  uv run tools/new_mod.py <modId> --name "Display Name" [--summary "..."]
      [--tag "Script Mod" ...] [--script] [--cosmetic] [--author NAME]

<modId> must match [a-z0-9_]+, ideally <author>_<modname>. --script adds a
content/mod.script.tl stub wired to runScript. Author defaults to TF3_AUTHOR
from .hub.env.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR, _lookup  # noqa: E402

SCRIPT_STUB = """\
-- Script functions referenced from mod.json as "{mod_id}::mod.script@<function>".
-- See docs/wiki/modding/general/modscripts.md

local mod = {{}}

mod.runFn = function(_configDict : {{{{string, string}}}}, _allModParams : {{string : {{string : integer}}}})
\tlog.info("{mod_id} loaded")
end

return mod
"""


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=4, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mod_id")
    parser.add_argument("--name", required=True, help="display name, max 32 chars")
    parser.add_argument("--summary", default="", help="tooltip summary, max 100 chars")
    parser.add_argument("--description", default="")
    parser.add_argument("--tag", action="append", default=[], help="official tag; repeatable")
    parser.add_argument("--author", default=_lookup("TF3_AUTHOR") or "")
    parser.add_argument("--script", action="store_true", help="add content/mod.script.tl wired to runScript")
    parser.add_argument("--cosmetic", action="store_true")
    args = parser.parse_args()

    if not re.match(r"^[a-z0-9_]+$", args.mod_id):
        raise SystemExit("modId may only contain a-z, 0-9 and _")
    if len(args.name) > 32:
        raise SystemExit("--name must be at most 32 characters")
    if len(args.summary) > 100:
        raise SystemExit("--summary must be at most 100 characters")
    mod = MODS_DIR / args.mod_id
    if mod.exists():
        raise SystemExit(f"{mod} already exists")

    severity = "None" if args.cosmetic else "Critical"
    mod_json: dict = {
        "modId": args.mod_id,
        "revision": 1,
        "severityAdd": severity,
        "severityRemove": severity,
        "visible": True,
        "cosmetic": args.cosmetic,
    }
    if args.script:
        mod_json["runScript"] = {"fileName": f"{args.mod_id}::mod.script@runFn"}
    write_json(mod / "mod.json", mod_json)

    write_json(
        mod / "_metadata" / "modinfo.json",
        {
            "name": args.name,
            "summary": args.summary,
            "description": args.description,
            "authors": [{"name": args.author, "role": "CREATOR"}] if args.author else [],
            "tags": args.tag,
            "dependencies": [],
            "url": "",
        },
    )
    (mod / "content").mkdir(parents=True, exist_ok=True)
    if args.script:
        (mod / "content" / "mod.script.tl").write_text(SCRIPT_STUB.format(mod_id=args.mod_id), encoding="utf-8")
    else:
        (mod / "content" / ".gitkeep").touch()

    print(f"Created {mod.relative_to(MODS_DIR.parent)}")
    print("Next: add content, a 1920x1080 _metadata/0.png, then `make link` and `make validate`.")


if __name__ == "__main__":
    main()
