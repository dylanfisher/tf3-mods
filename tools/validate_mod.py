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
from i18n import summary_line as translation_summary  # noqa: E402
from sqperf_sync import check_mod as check_sqperf  # noqa: E402
from tooltips import check_mod as check_tooltips  # noqa: E402

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


def check_params(path: Path, data: dict, report: Report) -> None:
    # The game parses param "numbers" as doubles and skips the whole mod on an
    # integer literal ("Value is not a double"), so 60 must be written 60.0.
    raw = json.loads(path.read_text(encoding="utf-8-sig"), parse_int=lambda s: ("int", s))
    for param in raw.get("params") or []:
        if not isinstance(param, dict):
            continue
        ints = [v[1] for v in param.get("numbers") or [] if isinstance(v, tuple)]
        if ints:
            report.error(
                f"mod.json: param {param.get('key')!r} numbers {ints} must be written as decimals "
                "(e.g. 60.0); the game skips the mod with 'Value is not a double'"
            )
        values, numbers = param.get("values"), param.get("numbers")
        if values is not None and numbers is not None and len(values) != len(numbers):
            report.error(f"mod.json: param {param.get('key')!r} has {len(values)} values but {len(numbers)} numbers")


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
    check_params(path, data, report)
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
    if not (mod / "content" / f"{mod.name}_presence.lua").exists():
        report.warn(f"content/{mod.name}_presence.lua missing (presence marker, CLAUDE.md \"Detecting another of our mods\")")


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


# Tags the in-game mod browser renders (docs/wiki/modding/general/guidelines.md:189-196), plus blockquote and img (mod.io
# shows them, docs/findings/publishing.md; in game untested; img only in the More-from tiles); the house
# format for description.html is in branding/README.md "Mod description".
DESCRIPTION_TAGS = {"p", "h1", "h2", "h3", "h4", "strong", "b", "em", "i", "ul", "ol", "li", "hr", "br", "a", "blockquote", "img"}
# mod.io rejects a longer description with error 13009 at the Mod Hub upload (docs/findings/publishing.md
# "Description length", 2026-10-16; the swagger's 150,000 maxLength is not what the upload enforces).
MAX_DESCRIPTION_CHARS = 50_000
WARN_DESCRIPTION_CHARS = 40_000


def check_description(mod: Path, report: Report) -> None:
    path = mod / "_metadata" / "description.html"
    if not path.exists():
        report.warn("_metadata/description.html missing (house style: description with a Changelog, see branding/README.md)")
        return
    html = path.read_text(encoding="utf-8")
    if len(html) > MAX_DESCRIPTION_CHARS:
        report.error(f"description.html is {len(html)} characters, mod.io rejects more than {MAX_DESCRIPTION_CHARS} (error 13009)")
    elif len(html) > WARN_DESCRIPTION_CHARS:
        report.warn(f"description.html is {len(html)} characters, close to mod.io's {MAX_DESCRIPTION_CHARS} limit: trim it")
    for tag in sorted({t.lower() for t in re.findall(r"</?\s*([a-zA-Z][a-zA-Z0-9]*)", html)} - DESCRIPTION_TAGS):
        report.warn(f"description.html: <{tag}> is not rendered by the in-game browser")
    # Every piece of text sits in a block: <p>, a heading or a list item. Remove those blocks and the
    # remaining tags; whatever text is left was written loose.
    loose = re.sub(r"<(p|h[1-4]|li)\b[^>]*>.*?</\1\s*>", " ", html, flags=re.IGNORECASE | re.DOTALL)
    loose = re.sub(r"<[^>]+>", " ", loose)
    for text in re.findall(r"\S[^\n]*", loose):
        report.warn(f"description.html: text outside <p>, <h1>-<h4> or <li>: {text.strip()[:60]!r}")
    # House style: <h2> is reserved for the Changelog title; sections and revisions are <h4>.
    for title in re.findall(r"<h2[^>]*>(.*?)</h2\s*>", html, re.IGNORECASE | re.DOTALL):
        if title.strip().lower() != "changelog":
            report.warn(f"description.html: <h2> is only for the Changelog, use <h4> for {title.strip()[:40]!r}")
    if re.search(r"<h[13]\b", html, re.IGNORECASE):
        report.warn("description.html: use <h2> for the Changelog title and <h4> for every other heading")
    if not re.search(r"<h[1-3][^>]*>\s*Changelog\s*</h[1-3]>", html, re.IGNORECASE):
        report.warn("description.html: no Changelog heading")
        return
    mod_json = mod / "mod.json"
    revision = None
    if mod_json.exists():
        try:
            revision = json.loads(mod_json.read_text(encoding="utf-8")).get("revision")
        except ValueError:
            pass
    if isinstance(revision, int) and not re.search(rf"<h4[^>]*>\s*Revision {revision}\b", html, re.IGNORECASE):
        report.warn(f"description.html: Changelog has no 'Revision {revision}' entry (mod.json revision)")


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


# API calls the upload review rejects (docs/findings/publishing.md). Text match, comments included: the server
# check may match text too.
FORBIDDEN_API = {
    "saveAppConfig": "api.util.saveAppConfig is rejected by the upload review; store mod data with "
                     "api.gui.game.setGuiSaveData(modId, table)",
}


def check_forbidden_api(mod: Path, report: Report) -> None:
    # DEV/probe mods are never uploaded: a warning there
    dev = (mod / "NOT_FOR_UPLOAD.txt").exists() or mod.name.endswith(("_probe", "_dev"))
    flag = report.warn if dev else report.error
    for path in sorted(mod.rglob("*")):
        if path.suffix not in (".lua", ".tl") or not path.is_file():
            continue
        rel = path.relative_to(mod).as_posix()
        text = path.read_text(encoding="utf-8", errors="replace")
        for name, why in FORBIDDEN_API.items():
            for n, line in enumerate(text.splitlines(), 1):
                if name in line:
                    flag(f"{rel}:{n}: {why}")
        for n, line in enumerate(text.splitlines(), 1):
            if "mainMenuState" in line and "=" in line.split("mainMenuState", 1)[1][:4]:
                report.warn(f"{rel}:{n}: writes AppConfig.mainMenuState; mod data belongs in setGuiSaveData")


def validate(mod: Path, tags: set[str] | None) -> Report:
    report = Report(mod)
    check_mod_json(mod, report)
    check_modinfo(mod, report, tags)
    check_description(mod, report)
    strings = mod / "strings.json"
    if strings.exists():
        load_json(strings, report)
    check_files(mod, report)
    check_forbidden_api(mod, report)
    translations = translation_summary(mod)  # strings.json coverage (tools/i18n.py); skips DEV/probe/fork mods
    if translations:
        report.warn(translations)
    for problem in check_sqperf(mod):  # SQPERF copies match tools/sqperf/ (plans/sqperf/README.md)
        report.error(f"sqperf: {problem}")
    tips = check_tooltips(mod)  # tooltip lines short enough (tools/tooltips.py, CLAUDE.md "Tooltips")
    for problem in tips[:5]:
        report.warn(problem)
    if len(tips) > 5:
        report.warn(f"... {len(tips) - 5} more long tooltip lines (make tooltips MOD=mods/{mod.name})")
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
