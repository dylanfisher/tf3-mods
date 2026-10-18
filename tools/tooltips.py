# /// script
# requires-python = ">=3.11"
# ///
"""Tooltip line widths: the game does not wrap tooltips, so a long one becomes one wide line.

Every tooltip line (split at "\\n") must fit LIMIT_EN display columns in English and LIMIT_TR in a
translation (CJK full-width characters count as 2). Checked:
  - mod.json params' "tooltip";
  - literal tooltips in content/**/*.lua|.tl: `tooltip = "..."`, `tooltip = _("...")`, `setTooltip("...")`,
    `setTooltip(_("..."))` (one-line literals; tooltips built at runtime from variables are not seen:
    wrap those in code, e.g. square_stress_test's stress_logic.wrapText);
  - strings.json translations of those keys.
CLAUDE.md "Tooltips" has the rule. Run by tools/validate_mod.py (warnings), or alone:

Usage: uv run tools/tooltips.py [--fix] [mods/<id> ...]   (default: every mod in mods/)
  --fix  re-wraps mod.json param tooltips that are too wide (WRAP columns per line) and their
         strings.json translations, re-keyed to the new English text. Tooltips in code are only
         reported: break those by hand (or wrap them at runtime).
"""

from __future__ import annotations

import json
import re
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR  # noqa: E402

LIMIT_EN = 70
LIMIT_TR = 90
WRAP = 60
# Characters a CJK line may break after any one of (Hangul uses spaces, so it is not listed).
_CJK = r"\u3000-\u30ff\u3400-\u9fff\uff00-\uffef"
_NO_LINE_START = set("、。，．・：；！？）」』】〕〉》ー々ゃゅょっぁぃぅぇぉャュョッァィゥェォ,.;:!?)]")
_TOKEN = re.compile(rf"[{_CJK}]\s*|[^\s{_CJK}]+\s*|\s+")

_STR = r'"((?:[^"\\]|\\.)*)"'
SOURCE_RES = [
    re.compile(r"\btooltip\s*=\s*_\(\s*" + _STR),
    re.compile(r"\btooltip\s*=\s*" + _STR),
    re.compile(r"\bsetTooltip\(\s*_\(\s*" + _STR),
    re.compile(r"\bsetTooltip\(\s*" + _STR),
]
ESCAPES = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}


def unescape(s: str) -> str:
    return re.sub(r"\\(.)", lambda m: ESCAPES.get(m.group(1), m.group(1)), s)


def width(line: str) -> int:
    return sum(2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1 for ch in line)


def widest(text: str) -> tuple[int, str]:
    best = (0, "")
    for line in text.split("\n"):
        w = width(line)
        if w > best[0]:
            best = (w, line)
    return best


def wrap(text: str, cols: int = WRAP) -> str:
    """Greedy wrap to `cols` display columns: at spaces, and between CJK characters; existing line
    breaks kept; a token wider than cols stays whole."""
    out: list[str] = []
    for para in text.split("\n"):
        line = ""
        for tok in _TOKEN.findall(para):
            if not line.strip():
                line = tok.lstrip()
                continue
            # closing punctuation never starts a line (Japanese/Chinese kinsoku): it stays on this one
            if width((line + tok).rstrip()) <= cols or tok[0] in _NO_LINE_START:
                line += tok
            else:
                out.append(line.rstrip())
                line = tok.lstrip()
        out.append(line.rstrip())
    return "\n".join(out)


def fix_mod(mod: Path) -> int:
    """Re-wraps too-wide mod.json param tooltips and their translations. Returns how many."""
    mj = mod / "mod.json"
    if not mj.exists():
        return 0
    raw = mj.read_text(encoding="utf-8")
    data = json.loads(raw)
    changes: dict[str, str] = {}
    for p in data.get("params") or []:
        t = p.get("tooltip") if isinstance(p, dict) else None
        if isinstance(t, str) and widest(t)[0] > LIMIT_EN:
            new = wrap(t)
            changes[t] = new
    if not changes:
        return 0
    # mod.json: replace the JSON-encoded strings in place, keeping the file's own layout
    for old, new in changes.items():
        enc_old, enc_new = json.dumps(old, ensure_ascii=False), json.dumps(new, ensure_ascii=False)
        if enc_old not in raw:
            raise SystemExit(f"{mj}: tooltip not found verbatim: {old[:40]!r}")
        raw = raw.replace(enc_old, enc_new)
    json.loads(raw)
    mj.write_text(raw, encoding="utf-8")
    strings = mod / "strings.json"
    if strings.exists():
        tr = json.loads(strings.read_text(encoding="utf-8"))
        for lang, table in tr.items():
            if not isinstance(table, dict):
                continue
            for old, new in changes.items():
                if old in table:
                    value = table.pop(old)
                    table[new] = wrap(value) if isinstance(value, str) else value
        strings.write_text(json.dumps(tr, ensure_ascii=False, indent=4) + "\n", encoding="utf-8")
    return len(changes)


def tooltips(mod: Path) -> list[tuple[str, str]]:
    """(where, English tooltip) for every tooltip found in the mod."""
    out: list[tuple[str, str]] = []
    mj = mod / "mod.json"
    if mj.exists():
        try:
            data = json.loads(mj.read_text(encoding="utf-8"))
        except ValueError:
            data = {}
        for p in data.get("params") or []:
            if isinstance(p, dict) and isinstance(p.get("tooltip"), str):
                out.append((f"mod.json param {p.get('key')}", p["tooltip"]))
    content = mod / "content"
    if content.exists():
        for path in sorted(content.rglob("*")):
            if path.suffix not in (".lua", ".tl") or not path.is_file():
                continue
            rel = path.relative_to(mod)
            for no, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
                if line.lstrip().startswith("--"):
                    continue
                seen: set[int] = set()
                for rx in SOURCE_RES:
                    for m in rx.finditer(line):
                        if m.start() in seen:
                            continue
                        seen.add(m.start())
                        out.append((f"{rel}:{no}", unescape(m.group(1))))
    return out


def check_mod(mod: Path) -> list[str]:
    """Warning lines for tooltips with a line wider than the limits."""
    warnings: list[str] = []
    found = tooltips(mod)
    seen_text: set[str] = set()
    for where, text in found:
        w, line = widest(text)
        if w > LIMIT_EN and (where, text) not in seen_text:
            seen_text.add((where, text))
            warnings.append(f"tooltip line {w} > {LIMIT_EN} columns ({where}): {line[:60]!r}... (break it with \\n)")
    strings = mod / "strings.json"
    if strings.exists() and found:
        try:
            tr = json.loads(strings.read_text(encoding="utf-8"))
        except ValueError:
            tr = {}
        keys = {text: where for where, text in found}
        for lang, table in sorted(tr.items()):
            if lang == "en" or not isinstance(table, dict):
                continue
            for key, where in keys.items():
                value = table.get(key)
                if not isinstance(value, str):
                    continue
                w, line = widest(value)
                if w > LIMIT_TR:
                    warnings.append(f"tooltip translation {lang} line {w} > {LIMIT_TR} columns ({where}): {line[:40]!r}...")
    return warnings


def main() -> None:
    args = sys.argv[1:]
    fix = "--fix" in args
    args = [a for a in args if a != "--fix"]
    mods = [Path(a) for a in args] or sorted(p for p in MODS_DIR.iterdir() if (p / "mod.json").exists())
    total = 0
    for mod in mods:
        if fix:
            n = fix_mod(mod)
            if n:
                print(f"[FIXED] {mod.name}: {n} mod.json tooltip(s) re-wrapped (with their translations)")
        w = check_mod(mod)
        total += len(w)
        print(f"[{'WARN' if w else 'OK'}] {mod.name}" + (f" ({len(w)})" if w else ""))
        for line in w:
            print(f"  warn:  {line}")
    print(f"\n{len(mods)} mod(s), {total} long tooltip line(s)")


if __name__ == "__main__":
    main()
