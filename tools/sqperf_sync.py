# /// script
# requires-python = ">=3.11"
# ///
"""Copy the SQPERF instrumentation module into the mods that use it, or check the copies.

Canonical sources (edit only these):
  tools/sqperf/sqperf.lua          the module (plain Lua, pre-5.3)
  tools/sqperf/sqperf_types.d.tl   Teal types; __MODID__ / __PREFIX__ are filled in per mod

Per mod (content paths are shared by every loaded mod, so the file names carry the modId):
  content/sqperf/<modId>.lua             byte-for-byte copy of sqperf.lua
  content/sqperf/<modId>_types.d.tl      rendered types (records <Prefix>SqPerf, <Prefix>SqPerfInst, ...)
  tealdef/sqperf/<modId>_types.d.tl      editor copy, only when the mod has a tealdef/ dir
  tealdef/<modId>_def.d.tl               gets `require "sqperf.<modId>_types"` when it exists

Usage:
  uv run tools/sqperf_sync.py                 refresh every mod that already has content/sqperf/
  uv run tools/sqperf_sync.py mods/<id> ...   add SQPERF to these mods (or refresh them)
  uv run tools/sqperf_sync.py --check [MOD]   report stale or missing copies, exit 1 if any (a MOD without
                                              content/sqperf/ prints "not using sqperf", exit 0)
Docs: plans/sqperf/README.md.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR, ROOT  # noqa: E402

SRC_DIR = ROOT / "tools" / "sqperf"
SRC_LUA = SRC_DIR / "sqperf.lua"
SRC_TYPES = SRC_DIR / "sqperf_types.d.tl"


def prefix(mod_id: str) -> str:
    """square_problem_radar -> SquareProblemRadar (Teal global names are shared by all mods)."""
    return "".join(part[:1].upper() + part[1:] for part in mod_id.split("_") if part)


def expected(mod: Path) -> dict[Path, bytes]:
    """Every file SQPERF owns in this mod, with its expected content."""
    mod_id = mod.name
    types = SRC_TYPES.read_text(encoding="utf-8").replace("__MODID__", mod_id).replace("__PREFIX__", prefix(mod_id))
    out = {
        mod / "content" / "sqperf" / f"{mod_id}.lua": SRC_LUA.read_bytes(),
        mod / "content" / "sqperf" / f"{mod_id}_types.d.tl": types.encode("utf-8"),
    }
    if (mod / "tealdef").is_dir():
        out[mod / "tealdef" / "sqperf" / f"{mod_id}_types.d.tl"] = types.encode("utf-8")
    return out


def require_line(mod_id: str) -> str:
    return f'require "sqperf.{mod_id}_types"'


def uses_sqperf(mod: Path) -> bool:
    return (mod / "content" / "sqperf").is_dir()


def check_mod(mod: Path) -> list[str]:
    """Problems with this mod's SQPERF copies (empty when the mod doesn't use SQPERF or all match)."""
    if not uses_sqperf(mod):
        return []
    problems = []
    for path, data in expected(mod).items():
        rel = path.relative_to(mod).as_posix()
        if not path.is_file():
            problems.append(f"{rel}: missing (run `make sqperf-sync`)")
        elif path.read_bytes() != data:
            problems.append(f"{rel}: differs from tools/sqperf/ (run `make sqperf-sync`; edit only the canonical file)")
    sqdir = mod / "content" / "sqperf"
    known = set(expected(mod))
    for extra in sorted(sqdir.iterdir()):
        if extra not in known:
            problems.append(f"{extra.relative_to(mod).as_posix()}: unexpected file in content/sqperf/")
    def_file = mod / "tealdef" / f"{mod.name}_def.d.tl"
    if def_file.is_file() and require_line(mod.name) not in def_file.read_text(encoding="utf-8"):
        problems.append(f"{def_file.relative_to(mod).as_posix()}: lacks {require_line(mod.name)}")
    return problems


def sync_mod(mod: Path) -> list[str]:
    changed = []
    for path, data in expected(mod).items():
        if path.is_file() and path.read_bytes() == data:
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        changed.append(path.relative_to(mod).as_posix())
    def_file = mod / "tealdef" / f"{mod.name}_def.d.tl"
    if def_file.is_file():
        text = def_file.read_text(encoding="utf-8")
        line = require_line(mod.name)
        if line not in text:
            def_file.write_text(text.rstrip("\n") + "\n" + line + "\n", encoding="utf-8")
            changed.append(def_file.relative_to(mod).as_posix())
    return changed


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="only report stale / missing copies")
    ap.add_argument("mods", nargs="*", type=Path)
    args = ap.parse_args()
    if args.mods:
        mods = [m.resolve() for m in args.mods]
        for m in mods:
            if not (m / "mod.json").is_file():
                raise SystemExit(f"{m}: not a mod (no mod.json)")
    else:
        mods = sorted(p for p in MODS_DIR.iterdir() if p.is_dir() and uses_sqperf(p))
    if not mods:
        print("No mod uses SQPERF yet; add one with: make sqperf-sync MOD=mods/<id>")
        return
    bad = 0
    for mod in mods:
        if args.check:
            if not uses_sqperf(mod):
                # Intentionally left out (construction-only, data-only, stylesheet-only mods): nothing to check.
                print(f"{mod.name}: not using sqperf")
                continue
            problems = check_mod(mod)
            for p in problems:
                print(f"{mod.name}: {p}")
            bad += len(problems)
            if not problems:
                print(f"{mod.name}: sqperf ok")
        else:
            changed = sync_mod(mod)
            print(f"{mod.name}: " + (", ".join(changed) if changed else "up to date"))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
