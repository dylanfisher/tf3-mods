# /// script
# requires-python = ">=3.11"
# ///
"""Scaffold a new mod in mods/<modId>/ following the TF3 wiki mod definition.

Usage:
  uv run tools/new_mod.py <modId> --name "Display Name" [--summary "..."]
      [--tag "Script Mod" ...] [--script] [--cosmetic] [--author NAME]

<modId> must match [a-z0-9_]+, by convention square_<modname>. --script adds a
content/mod.script.tl stub wired to runScript. Author defaults to TF3_AUTHOR (else "square")
from .hub.env.
"""

from __future__ import annotations

import argparse
import datetime
import html
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR, _lookup  # noqa: E402

PRESENCE_STUB = """\
-- Presence marker: another mod tells whether {mod_id} is active in the current game with
--   pcall(ug_require, "{mod_id}::/{mod_id}_presence.lua")
-- (CLAUDE.md "Detecting another of our mods"). Keep it side-effect free.
return {{ modId = "{mod_id}" }}
"""

SCRIPT_STUB = """\
-- Script functions referenced from mod.json as "{mod_id}::mod.script@<function>".
-- See docs/wiki/modding/general/modscripts.md, but note captureParams comes first (the wiki omits it;
-- base base/base_mod.lua:8, docs/findings.md). Param values are 1-based option indices.

local mod = {{}}

mod.runFn = function(_captureParams : any, _settings : {{{{string, string}}}}, _allModParams : {{string : {{string : integer}}}})
\tlog.message("{mod_id} loaded")
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
    parser.add_argument("--author", default=_lookup("TF3_AUTHOR") or "square")
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
    # House-style description with a changelog (branding/README.md "Mod description").
    (mod / "_metadata" / "description.html").write_text(
        DESCRIPTION_STUB.format(summary=html.escape(args.summary or args.name), date=datetime.date.today().isoformat()),
        encoding="utf-8",
    )
    (mod / "content").mkdir(parents=True, exist_ok=True)
    (mod / "content" / f"{args.mod_id}_presence.lua").write_text(PRESENCE_STUB.format(mod_id=args.mod_id), encoding="utf-8")
    if args.script:
        (mod / "content" / "mod.script.tl").write_text(SCRIPT_STUB.format(mod_id=args.mod_id), encoding="utf-8")

    print(f"Created {mod.relative_to(MODS_DIR.parent)}")
    print("Next: add content, a 1920x1080 _metadata/0.png, then `make link` and `make validate`.")


DESCRIPTION_STUB = """<p>{summary}</p>
<h2>Features</h2>
<ul>
<li><strong>TODO</strong>: what it shows or does.</li>
</ul>
<h2>Notes</h2>
<ul>
<li>TODO: caveats and save compatibility.</li>
</ul>
<hr>
<h2>Changelog</h2>
<h3>Revision 1 ({date})</h3>
<ul>
<li>First release.</li>
</ul>
"""


if __name__ == "__main__":
    main()
