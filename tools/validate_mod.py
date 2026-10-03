# /// script
# requires-python = ">=3.11"
# ///
"""Check mods against the TF3 wiki's mod definition and guidelines.

Rules come from docs/wiki/modding/general/{moddefinition,guidelines,modtags}.md.
The official tag list is read from the synced modtags.md, so it stays current.
This is a pre-flight check; the game's own upload validation is authoritative.

Usage: uv run tools/validate_mod.py [mods/<id> ...]   (default: every mod in mods/)
Exit code 1 if any mod has errors.
"""

from __future__ import annotations

import json
import re
import struct
import sys
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR, WIKI_DIR, is_text_resource  # noqa: E402

MAX_MOD_BYTES = 500 * 1024 * 1024
MAX_COVER_BYTES = 8 * 1024 * 1024
SEVERITIES = {"None", "Warning", "Critical"}
MOD_ID_RE = re.compile(r"^[a-z0-9_]+$")
PATH_RE = re.compile(r"^[A-Za-z0-9_.\-@]+$")  # "@" appears in game icon names like icon@2x.tga
SCRIPT_KEYS = ("preRunScript", "runScript", "postRunScript")


class Report:
    def __init__(self, mod: Path):
        self.mod = mod
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    def print(self) -> None:
        status = "FAIL" if self.errors else ("WARN" if self.warnings else "OK")
        print(f"[{status}] {self.mod.name}")
        for msg in self.errors:
            print(f"  error: {msg}")
        for msg in self.warnings:
            print(f"  warn:  {msg}")


def official_tags() -> set[str] | None:
    page = WIKI_DIR / "modding/general/modtags.md"
    if not page.exists():
        return None
    return set(re.findall(r"^- `([^`]+)`", page.read_text(), flags=re.M))


def load_json(path: Path, report: Report) -> dict | None:
    raw = path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        report.error(f"{path.name}: has a UTF-8 BOM")
        raw = raw[3:]
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        report.error(f"{path.relative_to(report.mod)}: invalid JSON ({exc})")
        return None
    if not isinstance(data, dict):
        report.error(f"{path.relative_to(report.mod)}: top level must be an object")
        return None
    return data


def check_mod_json(mod: Path, report: Report) -> None:
    path = mod / "mod.json"
    if not path.exists():
        report.error("mod.json missing")
        return
    data = load_json(path, report)
    if data is None:
        return
    mod_id = data.get("modId")
    if not isinstance(mod_id, str) or not MOD_ID_RE.match(mod_id):
        report.error(f"mod.json: modId {mod_id!r} must match [a-z0-9_]+")
    elif mod_id != mod.name:
        report.warn(f"mod.json: modId '{mod_id}' differs from folder name '{mod.name}' (wiki recommends keeping them in sync)")
    elif re.search(r"_\d+$", mod_id):
        report.warn(f"mod.json: modId '{mod_id}' ends in a version suffix; TF3 no longer uses _N major versions")
    if not isinstance(data.get("revision"), int):
        report.error("mod.json: revision must be an integer")
    for key in ("severityAdd", "severityRemove"):
        if key in data and data[key] not in SEVERITIES:
            report.error(f"mod.json: {key} must be one of {sorted(SEVERITIES)}")
        elif key not in data:
            report.warn(f"mod.json: {key} unset (defaults: severityAdd=None, severityRemove=Warning)")
    for key in ("visible", "cosmetic"):
        if key in data and not isinstance(data[key], bool):
            report.error(f"mod.json: {key} must be true/false")
    for key in SCRIPT_KEYS:
        ref = (data.get(key) or {}).get("fileName") if isinstance(data.get(key), dict) else None
        if not ref:
            continue
        match = re.match(r"^([a-z0-9_]+)::/?([^@]+)@(\w+)$", ref)
        if not match:
            report.error(f"mod.json: {key}.fileName {ref!r} must look like '<modId>::<file>@<function>'")
            continue
        ref_mod, file_stem, _fn = match.groups()
        if ref_mod != mod_id:
            report.warn(f"mod.json: {key} references mod '{ref_mod}', not this mod's id '{mod_id}'")
        elif not any((mod / "content" / f"{file_stem}{ext}").exists() for ext in (".tl", ".lua")):
            report.error(f"mod.json: {key} script content/{file_stem}.tl|.lua not found")


def check_modinfo(mod: Path, report: Report, tags: set[str] | None) -> None:
    path = mod / "_metadata" / "modinfo.json"
    if not path.exists():
        report.error("_metadata/modinfo.json missing")
        return
    data = load_json(path, report)
    if data is None:
        return
    texts = [("", data)] + [(f"localization.{lang}.", v) for lang, v in (data.get("localization") or {}).items()]
    if "en" not in (data.get("localization") or {}) and not data.get("name"):
        report.error("modinfo.json: English name required (name or localization.en.name)")
    for prefix, block in texts:
        name, summary = block.get("name"), block.get("summary")
        if isinstance(name, str) and (len(name) > 32 or "\n" in name):
            report.error(f"modinfo.json: {prefix}name must be ≤32 chars, single line ({len(name)})")
        if isinstance(summary, str) and (len(summary) > 100 or "\n" in summary):
            report.error(f"modinfo.json: {prefix}summary must be ≤100 chars, single line ({len(summary)})")
    authors = data.get("authors")
    if not isinstance(authors, list) or not authors:
        report.warn("modinfo.json: no authors listed")
    mod_tags = data.get("tags") or []
    if not mod_tags:
        report.warn("modinfo.json: no tags (needed for Mod Hub filtering)")
    if tags is not None:
        for tag in mod_tags:
            if tag not in tags:
                report.warn(f"modinfo.json: tag {tag!r} is not an official tag (see docs/wiki/modding/general/modtags.md)")
    cover = mod / "_metadata" / "0.png"
    if not cover.exists():
        report.warn("_metadata/0.png cover image missing (1920x1080 recommended)")
    else:
        size = png_size(cover)
        if size and size != (1920, 1080):
            report.warn(f"_metadata/0.png is {size[0]}x{size[1]}, expected 1920x1080")
        if cover.stat().st_size > MAX_COVER_BYTES:
            report.error("_metadata/0.png exceeds 8 MB")


def png_size(path: Path) -> tuple[int, int] | None:
    head = path.read_bytes()[:24]
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])


def check_dds(path: Path, rel: str, report: Report) -> None:
    head = path.read_bytes()[:128]
    if head[:4] != b"DDS ":
        report.error(f"{rel}: not a valid DDS file")
        return
    height, width = struct.unpack("<II", head[12:20])
    mipmaps = struct.unpack("<I", head[28:32])[0]
    if width & (width - 1) or height & (height - 1):
        report.error(f"{rel}: dimensions {width}x{height} are not powers of two")
    if mipmaps <= 1 and max(width, height) > 1:
        report.error(f"{rel}: has no mipmaps")


def check_wav(path: Path, rel: str, report: Report) -> None:
    try:
        with wave.open(str(path)) as wav:
            if wav.getsampwidth() != 2 or wav.getframerate() != 48000:
                report.error(f"{rel}: must be 16-bit / 48000 Hz (is {wav.getsampwidth() * 8}-bit / {wav.getframerate()} Hz)")
    except wave.Error as exc:
        report.error(f"{rel}: unreadable WAV ({exc})")


def check_files(mod: Path, report: Report) -> None:
    total = 0
    for path in sorted(mod.rglob("*")):
        rel = path.relative_to(mod).as_posix()
        if any(part.startswith(".") for part in path.relative_to(mod).parts):
            continue  # .git, .DS_Store, editor files: not part of the upload
        if not PATH_RE.match(path.name):
            report.error(f"{rel}: avoid whitespace and special characters in names")
        elif path.name != path.name.lower():
            report.warn(f"{rel}: guidelines ask for lowercase file and folder names")
        if path.is_dir():
            continue
        total += path.stat().st_size
        suffix = path.suffix.lower()
        if is_text_resource(path.name):
            raw = path.read_bytes()
            if raw.startswith(b"\xef\xbb\xbf"):
                report.error(f"{rel}: has a UTF-8 BOM")
            try:
                raw.decode("utf-8")
            except UnicodeDecodeError:
                report.error(f"{rel}: not valid UTF-8")
        if suffix == ".dds":
            check_dds(path, rel, report)
        elif suffix == ".wav":
            check_wav(path, rel, report)
        elif suffix in (".glsl", ".fs", ".vs", ".gs"):
            report.warn(f"{rel}: custom shaders are not allowed on consoles")
    if total > MAX_MOD_BYTES:
        report.error(f"mod is {total / 1e6:.0f} MB unpacked; limit is 500 MB")


def validate(mod: Path, tags: set[str] | None) -> Report:
    report = Report(mod)
    check_mod_json(mod, report)
    check_modinfo(mod, report, tags)
    strings = mod / "strings.json"
    if strings.exists():
        load_json(strings, report)
    check_files(mod, report)
    return report


def main() -> None:
    targets = [Path(a).resolve() for a in sys.argv[1:]] or sorted(
        p for p in MODS_DIR.iterdir() if p.is_dir() and (p / "mod.json").exists()
    )
    if not targets:
        print("No mods found in mods/")
        return
    tags = official_tags()
    if tags is None:
        print("note: docs/wiki not synced; skipping tag validation (run `make docs-wiki`)")
    reports = [validate(mod, tags) for mod in targets]
    for report in reports:
        report.print()
    sys.exit(1 if any(r.errors for r in reports) else 0)


if __name__ == "__main__":
    main()
