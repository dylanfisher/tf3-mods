# /// script
# requires-python = ">=3.11"
# ///
"""Translation report for the mods' strings.json files (docs/wiki/modding/general/moddefinition.md "strings.json").

A mod's strings.json maps language -> {key: text}. The game looks a key up in the player's language, then in
"en", then shows the key itself. House convention: the key IS the English text (`_("Filter")`), so "en" only
needs entries for keys that are ids (`_("SQUARE_OWR_..._NAME")`), and every other language needs every key.

Keys are collected from
  - every `_("...")`, `_('...')`, `_([[...]])` and `_ "..."` literal in content/**/*.tl|.lua (not content/sqperf/,
    not *.d.tl), decoded the way Lua decodes the literal (escapes, long brackets);
  - mod.json params: each "name", "tooltip" and "values" entry;
  - string literals on lines marked `-- i18n: keys` (for label tables translated later with `_(TABLE[k])`).
    `-- i18n: keys label text` takes only the literals after `label =` / `text =` on that line, and
    `-- i18n: keys begin [fields]` ... `-- i18n: keys end` marks a whole block.

Warnings (heuristics, never fail --check; `-- i18n: ignore` on a line silences that line):
  - non-literal calls: `_(var)`, `_(a .. b)`, `_(string.format(...))`: the key can't be extracted;
  - sentence building: a `..` chain that joins a `_()` result with another `_()` or with a literal that has letters;
  - untranslated literals: text-like string literals at GUI text sinks without `_()`: fields
    `text/tooltip/title/label/placeholder/...= "..."`, calls `text("...")`, `setText("...")`, `TextView.new("...")`,
    and `name/description = "..."` in .lua resource files (not *.script.lua or *.tree.lua). Ids, paths and
    style names are skipped (looks_like_text).

Per mod and language it reports missing keys, unused (extra) keys, placeholder mismatches (printf tokens
`%d %s %.1f` must keep their order; `{name}`, `%1%` and `%%` must all be there, in any order), empty
translations, and redundant "en" entries (text == key).

Usage: uv run tools/i18n.py [options] [mods/<id> ...]
  (default: every mod in mods/ except DEV/probe/fork mods, see EXCLUDE; an explicit path always works)
  --check           exit 1 on missing keys, placeholder mismatches or invalid strings.json (and, with
                    --lint-modinfo, modinfo problems); unused keys and heuristics stay warnings
  --json            machine-readable report
  --missing LANG    print a JSON object {key: English text} of the keys LANG lacks (one mod: flat;
                    several: {modId: {...}}), to hand to a translator
  --fix-format      rewrite existing strings.json files in the stable layout (LANGS order, keys in
                    extraction order with unused keys last, 4-space indent, UTF-8 without BOM)
  --lint-modinfo    check _metadata/modinfo.json "localization": an entry per language, name <= 32 chars,
                    summary <= 100 chars, single line
  -v, --verbose     list every missing / unused key instead of a count
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import re
import sys
from collections import Counter
from dataclasses import asdict, dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hubconfig import MODS_DIR  # noqa: E402

# The game's own locales (.cache/game/base/content/locale/*.lang.lua); "en" is the source and fallback.
LANGS = ("en", "ru", "de", "fr", "es", "it", "nl", "pl", "pt_BR", "ja", "ko", "zh_CN", "zh_TW")
TARGET_LANGS = LANGS[1:]

# DEV/probe and fork mods are skipped unless passed explicitly (they are never translated).
EXCLUDE = (
    "square_*_probe",
    "square_sqperf_*",
    "square_stress_test",
    "square_aat_perftest",
    "square_hitch_probe",
    "square_opt_*",
)
SKIP_DIRS = ("sqperf",)  # content/<dir>/ copied from tools/ (SQPERF), never user-facing

MAX_NAME, MAX_SUMMARY = 32, 100  # modinfo limits (tools/validate_mod.py)

# --- heuristics for untranslated literals (tune here) ---------------------------------------------
# Table fields whose string value the GUI shows.
FIELD_SINKS = {"text", "tooltip", "title", "label", "placeholder", "caption", "header", "virtualKeyboardTitle"}
# ...and in .lua resource files (constructions, streets, models), the menu name and description.
RESOURCE_FIELD_SINKS = {"name", "description"}
RESOURCE_SKIP = (".script.lua", ".tree.lua")  # not resources: GUI/game scripts, map generator node graphs
# Calls whose first argument is shown: f("..."), obj:f("...").
CALL_SINKS = {"text", "setText", "setTooltip", "setTitle"}
# Constructors X.new("...") whose first argument is shown.
CTOR_SINKS = {"TextView", "Window"}
ID_CHARS = re.compile(r"[._/\\:@#\-]")  # a word with one of these is an id, path, style class or format
IGNORE_MARK = "i18n: ignore"
KEYS_MARK = re.compile(r"i18n:\s*keys\b\s*(begin|end)?\s*([\w ,]*)")

PLACEHOLDER = re.compile(r"%%|%[-+#0]*\d*(?:\.\d+)?[diouxXeEfgGqsc]|%\d+%|\{[A-Za-z_]\w*\}")
LUA_KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local",
    "nil", "not", "or", "repeat", "return", "then", "true", "until", "while", "record", "enum", "global",
}  # fmt: skip


# ==================================================================================================
# Lua / Teal lexer
# ==================================================================================================


@dataclass(slots=True)
class Tok:
    kind: str  # "name" | "str" | "num" | "op"
    value: str  # name / operator text, or the decoded string value
    line: int
    start: int  # offsets into the source, for snippets
    end: int


NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
NUM_RE = re.compile(r"0[xX][0-9a-fA-F]*(?:\.[0-9a-fA-F]*)?(?:[pP][+-]?\d+)?|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?")
LONG_OPEN = re.compile(r"\[(=*)\[")
OPS = ("...", "..", "==", "~=", "<=", ">=", "//", "::", "<<", ">>")
SIMPLE_ESC = {"a": 7, "b": 8, "f": 12, "n": 10, "r": 13, "t": 9, "v": 11, "\\": 92, '"': 34, "'": 39}


class LexError(ValueError):
    pass


def _short_string(src: str, pos: int, line: int) -> tuple[str, int, int]:
    """Decode the quoted literal starting at src[pos]; return (value, end offset, end line)."""
    quote, i, n = src[pos], pos + 1, len(src)
    out = bytearray()
    while True:
        if i >= n or src[i] == "\n":
            raise LexError(f"line {line}: unfinished string")
        c = src[i]
        if c == quote:
            return out.decode("utf-8", errors="replace"), i + 1, line
        if c != "\\":
            out += c.encode("utf-8")
            i += 1
            continue
        e = src[i + 1] if i + 1 < n else ""
        if e in SIMPLE_ESC:
            out.append(SIMPLE_ESC[e])
            i += 2
        elif e in "\r\n":  # backslash-newline is a newline (\r\n counts once)
            out.append(10)
            line += 1
            i += 2
            if i < n and src[i] in "\r\n" and src[i] != e:
                i += 1
        elif e == "z":  # skip following whitespace
            i += 2
            while i < n and src[i] in " \t\r\n\f\v":
                line += src[i] == "\n"
                i += 1
        elif e == "x":
            out.append(int(src[i + 2 : i + 4], 16))
            i += 4
        elif e == "u":
            m = re.compile(r"\{([0-9a-fA-F]+)\}").match(src, i + 2)
            if not m:
                raise LexError(f"line {line}: bad \\u escape")
            out += chr(int(m.group(1), 16)).encode("utf-8")
            i = m.end()
        elif e.isdigit():
            m = re.compile(r"\d{1,3}").match(src, i + 1)
            out.append(int(m.group()) & 0xFF)
            i = m.end()
        else:
            raise LexError(f"line {line}: invalid escape \\{e}")


def _long_bracket(src: str, pos: int, level: int) -> tuple[str, int]:
    """Body and end offset of the [==[ ... ]==] starting at src[pos] (level = number of '=')."""
    open_end = pos + level + 2
    close = "]" + "=" * level + "]"
    end = src.find(close, open_end)
    if end < 0:
        raise LexError("unfinished long bracket")
    body = src[open_end:end]
    if body.startswith("\r\n"):  # Lua drops a newline right after the opening bracket
        body = body[2:]
    elif body.startswith("\n"):
        body = body[1:]
    return body, end + len(close)


def tokenize(src: str) -> tuple[list[Tok], dict[int, str]]:
    """Tokens (comments dropped) and {line: comment text} (a long comment is keyed by its first line)."""
    toks: list[Tok] = []
    comments: dict[int, str] = {}
    pos, line, n = 0, 1, len(src)
    while pos < n:
        c = src[pos]
        if c == "\n":
            line += 1
            pos += 1
        elif c in " \t\r\f\v":
            pos += 1
        elif src.startswith("--", pos):
            m = LONG_OPEN.match(src, pos + 2)
            if m:
                body, end = _long_bracket(src, pos + 2, len(m.group(1)))
            else:
                end = src.find("\n", pos)
                end = n if end < 0 else end
                body = src[pos + 2 : end]
            comments[line] = (comments.get(line, "") + " " + body).strip()
            line += src.count("\n", pos, end)
            pos = end
        elif c in "\"'":
            value, end, end_line = _short_string(src, pos, line)
            toks.append(Tok("str", value, line, pos, end))
            line, pos = end_line, end
        elif c == "[" and (m := LONG_OPEN.match(src, pos)):
            body, end = _long_bracket(src, pos, len(m.group(1)))
            toks.append(Tok("str", body, line, pos, end))
            line += src.count("\n", pos, end)
            pos = end
        elif (m := NAME_RE.match(src, pos)) is not None:
            toks.append(Tok("name", m.group(), line, pos, m.end()))
            pos = m.end()
        elif (c.isdigit() or (c == "." and src[pos + 1 : pos + 2].isdigit())) and (m := NUM_RE.match(src, pos)):
            toks.append(Tok("num", m.group(), line, pos, m.end()))
            pos = m.end()
        else:
            op = next((o for o in OPS if src.startswith(o, pos)), c)
            toks.append(Tok("op", op, line, pos, pos + len(op)))
            pos += len(op)
    return toks, comments


def match_brackets(toks: list[Tok]) -> dict[int, int]:
    """Index of each bracket token -> index of its partner (both directions); unbalanced ones are left out."""
    pairs, stack = {}, []
    for i, t in enumerate(toks):
        if t.kind != "op":
            continue
        if t.value in "([{":
            stack.append(i)
        elif t.value in ")]}" and stack:
            j = stack.pop()
            pairs[i], pairs[j] = j, i
    return pairs


def is_op(tok: Tok | None, *values: str) -> bool:
    return tok is not None and tok.kind == "op" and tok.value in values


# ==================================================================================================
# Extraction
# ==================================================================================================


@dataclass
class Hit:
    """One heuristic finding: where, and the source snippet."""

    file: str
    line: int
    text: str


@dataclass
class Scan:
    keys: dict[str, str] = field(default_factory=dict)  # key -> first "file:line" (insertion = extraction order)
    nonliteral: list[Hit] = field(default_factory=list)
    concat: list[Hit] = field(default_factory=list)
    untranslated: list[Hit] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)  # files that failed to lex

    def add_key(self, key: str, where: str) -> None:
        self.keys.setdefault(key, where)


def looks_like_text(s: str) -> bool:
    """Heuristic: would a player read this literal? False for ids, paths, style classes, formats."""
    s = s.strip()
    if len(s) < 2 or not re.search(r"[^\W\d_]", s):
        return False
    words = [w for w in re.split(r"[\s,]+", s) if w]
    return not all(ID_CHARS.search(w) or (w.islower() and re.search(r"\d", w)) for w in words)


def looks_like_id(key: str) -> bool:
    """A key that is an id (SQUARE_OWR_X_NAME, param_x_name) rather than English text needs an "en" entry."""
    return " " not in key and "_" in key and re.fullmatch(r"[A-Za-z0-9_.]+", key) is not None


def snippet(src: str, start: int, end: int, limit: int = 90) -> str:
    text = re.sub(r"\s+", " ", src[start:end]).strip()
    return text if len(text) <= limit else text[: limit - 3] + "..."


def _operand_fwd(toks: list[Tok], pairs: dict[int, int], i: int) -> int:
    """Index of the last token of the operand (prefix expression) starting at toks[i]."""
    n = len(toks)
    while i < n and (is_op(toks[i], "-", "#") or (toks[i].kind == "name" and toks[i].value == "not")):
        i += 1
    if i >= n:
        return n - 1
    t = toks[i]
    if t.kind in ("str", "num") or (t.kind == "name" and t.value in ("nil", "true", "false")) or is_op(t, "..."):
        return i
    if is_op(t, "{"):
        return pairs.get(i, i)
    if is_op(t, "("):
        i = pairs.get(i, i)
    elif t.kind != "name" or t.value in LUA_KEYWORDS:
        return i
    while i + 1 < n:
        nxt = toks[i + 1]
        if is_op(nxt, ".", ":") and i + 2 < n and toks[i + 2].kind == "name":
            i += 2
        elif is_op(nxt, "(", "[", "{") and (i + 1) in pairs:
            i = pairs[i + 1]
        elif nxt.kind == "str":
            i += 1
        else:
            break
    return i


def _operand_bwd(toks: list[Tok], pairs: dict[int, int], j: int) -> int:
    """Index of the first token of the operand that ends at toks[j]."""
    while j >= 0:
        t = toks[j]
        if is_op(t, ")", "]", "}") and j in pairs:
            o = pairs[j]
            prev = toks[o - 1] if o > 0 else None
            callee = prev is not None and (
                (prev.kind == "name" and prev.value not in LUA_KEYWORDS) or is_op(prev, ")", "]") or prev.kind == "str"
            )
            if not callee:
                return o  # parenthesised expression or table constructor
            j = o - 1
        elif t.kind == "name":
            if j >= 2 and is_op(toks[j - 1], ".", ":"):
                j -= 2
                continue
            return j
        else:
            return j
    return 0


def _is_tr_call(toks: list[Tok], pairs: dict[int, int], s: int, e: int) -> bool:
    """Is toks[s..e] exactly one `_(...)` / `_ "..."` call?"""
    t = toks[s]
    if t.kind != "name" or t.value != "_" or (s > 0 and is_op(toks[s - 1], ".", ":")):
        return False
    return (is_op(toks[s + 1], "(") and pairs.get(s + 1) == e) or (s + 1 == e and toks[e].kind == "str")


def _field_filter(spec: str) -> set[str] | None:
    names = {w for w in re.split(r"[\s,]+", spec) if w}
    return names or None


def scan_source(src: str, rel: str, scan: Scan, resource: bool = False) -> None:
    """Add the keys and heuristic hits of one .tl/.lua source to `scan` (rel: path shown in reports)."""
    try:
        toks, comments = tokenize(src)
    except (LexError, ValueError) as exc:
        scan.errors.append(f"{rel}: {exc}")
        return
    pairs = match_brackets(toks)
    ignored = {ln for ln, c in comments.items() if IGNORE_MARK in c}

    # Lines whose literals are keys: `-- i18n: keys [fields]`, or inside a begin/end block.
    key_lines: dict[int, set[str] | None] = {}
    block: tuple[int, set[str] | None] | None = None
    for ln in sorted(comments):
        m = KEYS_MARK.search(comments[ln])
        if not m:
            continue
        kind, fields = m.group(1), _field_filter(m.group(2))
        if kind == "begin":
            block = (ln, fields)
        elif kind == "end" and block is not None:
            for k in range(block[0], ln + 1):
                key_lines[k] = block[1]
            block = None
        else:
            key_lines[ln] = fields
    if key_lines:
        for i, t in enumerate(toks):
            if t.kind != "str" or t.line not in key_lines:
                continue
            fields = key_lines[t.line]
            if fields is not None:
                if not (
                    i >= 2 and is_op(toks[i - 1], "=") and toks[i - 2].kind == "name" and toks[i - 2].value in fields
                ):
                    continue
            elif i + 1 < len(toks) and is_op(toks[i + 1], "]") and i > 0 and is_op(toks[i - 1], "["):
                continue  # ["key"] = ... table keys are not texts
            scan.add_key(t.value, f"{rel}:{t.line}")

    n = len(toks)
    for i, t in enumerate(toks):
        nxt = toks[i + 1] if i + 1 < n else None
        prev = toks[i - 1] if i > 0 else None

        # _("...") and friends
        if t.kind == "name" and t.value == "_" and nxt is not None and not is_op(prev, ".", ":"):
            if prev is not None and prev.kind == "name" and prev.value == "function":
                continue  # function _(s) ... (a definition)
            if nxt.kind == "str":
                scan.add_key(nxt.value, f"{rel}:{t.line}")
            elif is_op(nxt, "("):
                close = pairs.get(i + 1)
                if close == i + 3 and toks[i + 2].kind == "str":
                    scan.add_key(toks[i + 2].value, f"{rel}:{t.line}")
                elif t.line not in ignored:
                    end = toks[close].end if close is not None else nxt.end
                    scan.nonliteral.append(Hit(rel, t.line, snippet(src, t.start, end)))
            continue

        if t.line in ignored or t.line in key_lines:
            continue
        # name = "..." sinks
        if t.kind == "name" and is_op(nxt, "=") and i + 2 < n and toks[i + 2].kind == "str":
            if t.value in FIELD_SINKS or (resource and t.value in RESOURCE_FIELD_SINKS):
                lit = toks[i + 2]
                if looks_like_text(lit.value) and not is_op(prev, "["):
                    scan.untranslated.append(Hit(rel, t.line, snippet(src, t.start, lit.end)))
            continue
        # f("...") and X.new("...") sinks
        if t.kind == "name" and is_op(nxt, "(") and i + 2 < n and toks[i + 2].kind == "str":
            lit = toks[i + 2]
            sink = t.value in CALL_SINKS and not (prev is not None and prev.kind == "name" and prev.value == "function")
            ctor = t.value == "new" and is_op(prev, ".") and i >= 2 and toks[i - 2].value in CTOR_SINKS
            if (sink or ctor) and looks_like_text(lit.value):
                start = toks[i - 2].start if ctor else t.start
                more = ")" if i + 3 < n and is_op(toks[i + 3], ")") else ", ...)"
                scan.untranslated.append(Hit(rel, t.line, snippet(src, start, lit.end) + more))

    # Sentence building: `..` chains that join a _() result with another _() or a literal with letters.
    cats = [i for i, t in enumerate(toks) if is_op(t, "..")]
    chains: list[list[tuple[int, int]]] = []
    last_right_end = -2
    for k in cats:
        left = (_operand_bwd(toks, pairs, k - 1), k - 1)
        right = (k + 1, _operand_fwd(toks, pairs, k + 1))
        if chains and left[1] == last_right_end:
            chains[-1].append(right)
        else:
            chains.append([left, right])
        last_right_end = right[1]
    for chain in chains:
        tr = [s for s, e in chain if s <= e and _is_tr_call(toks, pairs, s, e)]
        lits = [s for s, e in chain if s == e and toks[s].kind == "str" and re.search(r"[^\W\d_]", toks[s].value)]
        if tr and (len(tr) > 1 or lits):
            line = toks[tr[0]].line
            if line not in ignored and toks[chain[0][0]].line not in ignored:
                start, end = toks[chain[0][0]].start, toks[chain[-1][1]].end
                scan.concat.append(Hit(rel, line, snippet(src, start, end)))


def source_files(mod: Path) -> list[Path]:
    content = mod / "content"
    if not content.is_dir():
        return []
    files = []
    for path in sorted(content.rglob("*")):
        rel = path.relative_to(content)
        if not path.is_file() or path.suffix not in (".tl", ".lua") or path.name.endswith(".d.tl"):
            continue
        if rel.parts[0] in SKIP_DIRS or any(p.startswith(".") for p in rel.parts):
            continue
        files.append(path)
    return files


def param_keys(mod: Path, scan: Scan) -> int:
    """Add the mod.json params' name/tooltip/values; return how many keys that were."""
    path = mod / "mod.json"
    if not path.exists():
        return 0
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except ValueError as exc:
        scan.errors.append(f"mod.json: invalid JSON ({exc})")
        return 0
    before = len(scan.keys)
    for param in data.get("params") or []:
        if not isinstance(param, dict):
            continue
        where = f"mod.json:params.{param.get('key')}"
        for text in [param.get("name"), param.get("tooltip"), *(param.get("values") or [])]:
            if isinstance(text, str) and text:
                scan.add_key(text, where)
    return len(scan.keys) - before


def scan_mod(mod: Path) -> tuple[Scan, int]:
    """Scan a mod: (scan, number of keys that came only from mod.json params)."""
    scan = Scan()
    for path in source_files(mod):
        rel = path.relative_to(mod).as_posix()
        resource = path.suffix == ".lua" and not path.name.endswith(RESOURCE_SKIP)
        try:
            src = path.read_text(encoding="utf-8-sig")
        except UnicodeDecodeError:
            scan.errors.append(f"{rel}: not valid UTF-8")
            continue
        scan_source(src, rel, scan, resource=resource)
    return scan, param_keys(mod, scan)


# ==================================================================================================
# strings.json
# ==================================================================================================


def placeholders(text: str) -> tuple[list[str], Counter]:
    """(printf tokens in order, multiset of the order-free tokens: {name}, %1%, %%)."""
    ordered, named = [], Counter()
    for tok in PLACEHOLDER.findall(text):
        if tok.startswith("{") or tok.endswith("%"):  # {name}, %1% and a literal %% may move
            named[tok] += 1
        else:
            ordered.append(tok)
    return ordered, named


def placeholder_problem(english: str, translated: str) -> str | None:
    eo, en = placeholders(english)
    to, tn = placeholders(translated)
    if eo == to and en == tn:
        return None
    want = eo + sorted(en.elements())
    got = to + sorted(tn.elements())
    return f"expected {' '.join(want) or '(none)'}, got {' '.join(got) or '(none)'}"


def load_strings(path: Path) -> tuple[dict[str, dict[str, str]] | None, list[str], list[str]]:
    """Parse strings.json: (data or None, errors, warnings)."""
    errors, warnings = [], []
    raw = path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        errors.append("strings.json has a UTF-8 BOM")
        raw = raw[3:]
    dups: list[str] = []

    def no_dups(pairs: list[tuple[str, object]]) -> dict:
        seen = Counter(k for k, _ in pairs)
        dups.extend(k for k, c in seen.items() if c > 1)
        return dict(pairs)

    try:
        data = json.loads(raw.decode("utf-8"), object_pairs_hook=no_dups)
    except (UnicodeDecodeError, ValueError) as exc:
        return None, [*errors, f"strings.json: invalid JSON ({exc})"], warnings
    if not isinstance(data, dict):
        return None, [*errors, "strings.json: top level must be an object"], warnings
    for key in dict.fromkeys(dups):
        warnings.append(f"strings.json: duplicate key {key!r} (the last one wins)")
    clean: dict[str, dict[str, str]] = {}
    for lang, table in data.items():
        if lang not in LANGS:
            warnings.append(f"strings.json: unknown language {lang!r} (game locales: {', '.join(LANGS)})")
        if not isinstance(table, dict):
            errors.append(f"strings.json: {lang!r} must be an object of key: text")
            continue
        bad = [k for k, v in table.items() if not isinstance(v, str)]
        if bad:
            errors.append(f"strings.json: {lang}: non-string values for {bad[:3]}")
        clean[lang] = {k: v for k, v in table.items() if isinstance(v, str)}
    return clean, errors, warnings


@dataclass
class LangReport:
    missing: list[str] = field(default_factory=list)
    unused: list[str] = field(default_factory=list)
    placeholder: list[tuple[str, str]] = field(default_factory=list)  # (key, problem)
    empty: list[str] = field(default_factory=list)
    redundant: list[str] = field(default_factory=list)  # "en" only: text == key


@dataclass
class ModReport:
    mod: str
    path: str
    keys: list[str]
    param_keys: int
    has_strings: bool
    langs: dict[str, LangReport]
    nonliteral: list[Hit]
    concat: list[Hit]
    untranslated: list[Hit]
    errors: list[str]
    warnings: list[str]
    modinfo: list[str] | None = None  # --lint-modinfo problems (None: not linted)

    @property
    def failed(self) -> bool:
        return bool(self.errors or any(r.missing or r.placeholder for r in self.langs.values()) or (self.modinfo or []))


def compare(keys: list[str], strings: dict[str, dict[str, str]]) -> dict[str, LangReport]:
    """Per language: missing / unused / placeholder / empty (and, for "en", redundant entries)."""
    keyset = set(keys)
    en = strings.get("en", {})
    out: dict[str, LangReport] = {}
    for lang in [*LANGS, *sorted(set(strings) - set(LANGS))]:
        table = strings.get(lang, {})
        rep = LangReport()
        if lang == "en":
            rep.missing = [k for k in keys if looks_like_id(k) and k not in table]
            rep.redundant = [k for k, v in table.items() if v == k]
        else:
            rep.missing = [k for k in keys if k not in table]
        rep.unused = [k for k in table if k not in keyset]
        rep.empty = [k for k, v in table.items() if not v.strip()]
        for k, v in table.items():
            if k not in keyset or not v.strip():
                continue
            if lang == "en":
                if looks_like_id(k):
                    continue
                problem = placeholder_problem(k, v)
            else:
                problem = placeholder_problem(en.get(k, k), v)
            if problem:
                rep.placeholder.append((k, problem))
        out[lang] = rep
    return out


def lint_modinfo(mod: Path) -> list[str]:
    """modinfo.json "localization": an entry per language with a valid name and summary."""
    path = mod / "_metadata" / "modinfo.json"
    if not path.exists():
        return ["_metadata/modinfo.json missing"]
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except ValueError as exc:
        return [f"modinfo.json: invalid JSON ({exc})"]
    loc = data.get("localization") or {}
    problems = []
    lacking = [lang for lang in TARGET_LANGS if lang not in loc]
    if lacking:
        problems.append(f"modinfo.json: localization lacks {len(lacking)} languages: {', '.join(lacking)}")
    blocks = [(lang, loc[lang]) for lang in loc]
    if "en" not in loc:
        blocks.insert(0, ("(top level)", data))
    for lang, block in blocks:
        if not isinstance(block, dict):
            problems.append(f"modinfo.json: localization.{lang} must be an object")
            continue
        for fld, limit in (("name", MAX_NAME), ("summary", MAX_SUMMARY)):
            value = block.get(fld)
            if not isinstance(value, str) or not value.strip():
                problems.append(f"modinfo.json: {lang}: {fld} missing")
            elif len(value) > limit or "\n" in value or "\r" in value:
                problems.append(f"modinfo.json: {lang}: {fld} must be <= {limit} chars, single line ({len(value)})")
    return problems


def analyze(mod: Path, lint_info: bool = False) -> ModReport:
    scan, n_params = scan_mod(mod)
    keys = list(scan.keys)
    errors, warnings = list(scan.errors), []
    path = mod / "strings.json"
    strings: dict[str, dict[str, str]] = {}
    if path.exists():
        data, errs, warns = load_strings(path)
        errors += errs
        warnings += warns
        strings = data or {}
    langs = compare(keys, strings) if keys or strings else {}
    return ModReport(
        mod=mod.name,
        path=str(mod),
        keys=keys,
        param_keys=n_params,
        has_strings=path.exists(),
        langs=langs,
        nonliteral=scan.nonliteral,
        concat=scan.concat,
        untranslated=scan.untranslated,
        errors=errors,
        warnings=warnings,
        modinfo=lint_modinfo(mod) if lint_info else None,
    )


def excluded(mod: Path) -> bool:
    return any(fnmatch.fnmatchcase(mod.name, pat) for pat in EXCLUDE)


def default_mods() -> list[Path]:
    return sorted(p for p in MODS_DIR.iterdir() if p.is_dir() and (p / "mod.json").exists() and not excluded(p))


def _count(n: int, noun: str) -> str:
    return f"{n} {noun}{'' if n == 1 else 's'}"


def summary_line(mod: Path) -> str | None:
    """One-line warning for tools/validate_mod.py, or None when translations are complete (or the mod is excluded)."""
    if excluded(mod):
        return None
    rep = analyze(mod)
    if not rep.keys:
        return None
    hint = f"make i18n MOD=mods/{mod.name}"
    if not rep.has_strings:
        return f"translations: no strings.json for {_count(len(rep.keys), 'key')} ({hint})"
    parts = []
    if rep.errors:
        parts.append(rep.errors[0])
    missing = {lang: len(r.missing) for lang, r in rep.langs.items() if r.missing}
    if missing:
        counts = set(missing.values())
        if len(counts) == 1:
            langs = f"all {len(missing)} languages" if set(missing) == set(TARGET_LANGS) else ", ".join(missing)
            parts.append(f"{_count(counts.pop(), 'key')} missing in {langs}")
        else:
            parts.append("keys missing in " + ", ".join(f"{lang} ({n})" for lang, n in missing.items()))
    bad = sum(len(r.placeholder) for r in rep.langs.values())
    if bad:
        parts.append(f"{bad} placeholder mismatches")
    return f"translations: {'; '.join(parts)} ({hint})" if parts else None


# ==================================================================================================
# Output
# ==================================================================================================


def fix_format(mod: Path, rep: ModReport) -> bool:
    """Rewrite strings.json in the stable layout; return whether the file changed."""
    path = mod / "strings.json"
    data = load_strings(path)[0]
    if data is None:
        return False
    order = {k: i for i, k in enumerate(rep.keys)}
    out = {}
    for lang in [*LANGS, *sorted(set(data) - set(LANGS))]:
        if lang not in data:
            continue
        table = data[lang]
        known = sorted((k for k in table if k in order), key=order.__getitem__)
        out[lang] = {k: table[k] for k in known + [k for k in table if k not in order]}
    text = json.dumps(out, indent=4, ensure_ascii=False) + "\n"
    old = path.read_bytes()
    if old == text.encode("utf-8"):
        return False
    path.write_bytes(text.encode("utf-8"))
    return True


def missing_for(rep: ModReport, lang: str, strings: dict[str, dict[str, str]]) -> dict[str, str]:
    en = strings.get("en", {})
    lr = rep.langs.get(lang)
    return {k: en.get(k, k) for k in (lr.missing if lr else [])}


def _list(items: list[str], verbose: bool, limit: int = 3) -> str:
    shown = items if verbose else items[:limit]
    more = "" if len(shown) == len(items) else f", ... (+{len(items) - len(shown)})"
    return ", ".join(repr(k) for k in shown) + more


def format_report(rep: ModReport, verbose: bool = False) -> str:
    lines = []
    status = (
        "FAIL" if rep.failed else ("WARN" if rep.warnings or rep.nonliteral or rep.concat or rep.untranslated else "OK")
    )
    src = _count(len(rep.keys), "key") + (f" ({rep.param_keys} from mod.json params)" if rep.param_keys else "")
    lines.append(f"[{status}] {rep.mod}: {src}, strings.json {'present' if rep.has_strings else 'missing'}")
    for msg in rep.errors:
        lines.append(f"  error: {msg}")
    for msg in rep.modinfo or []:
        lines.append(f"  error: {msg}")
    for msg in rep.warnings:
        lines.append(f"  warn:  {msg}")
    if rep.keys and not rep.has_strings:
        lines.append("  error: every key missing in every language (no strings.json)")
    elif rep.langs:
        for lang, lr in rep.langs.items():
            bits = []
            if lr.missing:
                bits.append(
                    f"{len(lr.missing)} missing"
                    + (f" [{_list(lr.missing, verbose)}]" if verbose or len(lr.missing) <= 3 else "")
                )
            if lr.placeholder:
                bits.append(f"{len(lr.placeholder)} placeholder mismatches")
            if lr.empty:
                bits.append(f"{len(lr.empty)} empty [{_list(lr.empty, verbose)}]")
            if lr.unused:
                bits.append(f"{len(lr.unused)} unused [{_list(lr.unused, verbose)}]")
            if lr.redundant:
                bits.append(f"{len(lr.redundant)} redundant (text == key) [{_list(lr.redundant, verbose)}]")
            if bits:
                kind = "error:" if lr.missing or lr.placeholder else "warn: "
                lines.append(f"  {kind} {lang}: {'; '.join(bits)}")
            for key, problem in lr.placeholder:
                lines.append(f"           {lang} {key!r}: {problem}")
    for title, hits in (
        ("non-literal _() call", rep.nonliteral),
        ("sentence building (.. around _())", rep.concat),
        ("untranslated literal", rep.untranslated),
    ):
        for hit in hits:
            lines.append(f"  warn:  {title}: {hit.file}:{hit.line}  {hit.text}")
    return "\n".join(lines)


def to_json(rep: ModReport) -> dict:
    out = asdict(rep)
    out["failed"] = rep.failed
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0], formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("mods", nargs="*", type=Path, help="mod folders (default: every non-DEV mod in mods/)")
    ap.add_argument("--check", action="store_true", help="exit 1 on missing keys, placeholder mismatches, invalid JSON")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument("--missing", metavar="LANG", help="print the keys LANG lacks as JSON {key: English text}")
    ap.add_argument("--fix-format", action="store_true", help="rewrite strings.json in the stable layout")
    ap.add_argument("--lint-modinfo", action="store_true", help="check modinfo.json localization entries")
    ap.add_argument("-v", "--verbose", action="store_true", help="list every missing / unused key")
    args = ap.parse_args(argv)

    mods = [p.resolve() for p in args.mods] or default_mods()
    for mod in mods:
        if not (mod / "mod.json").exists():
            ap.error(f"{mod}: not a mod folder (no mod.json)")
    if args.missing and args.missing not in LANGS:
        ap.error(f"--missing: unknown language {args.missing!r} (one of {', '.join(LANGS)})")

    reports = [analyze(mod, args.lint_modinfo) for mod in mods]

    if args.fix_format:
        for mod, rep in zip(mods, reports):
            if rep.has_strings and fix_format(mod, rep):
                print(f"reformatted {mod.name}/strings.json", file=sys.stderr)

    if args.missing:
        per_mod = {}
        for mod, rep in zip(mods, reports):
            strings = (load_strings(mod / "strings.json")[0] or {}) if rep.has_strings else {}
            miss = missing_for(rep, args.missing, strings)
            if miss:
                per_mod[rep.mod] = miss
        out = per_mod.get(reports[0].mod, {}) if len(reports) == 1 else per_mod
        print(json.dumps(out, indent=4, ensure_ascii=False))
    elif args.json:
        print(json.dumps([to_json(r) for r in reports], indent=2, ensure_ascii=False))
    elif not args.fix_format or args.check:
        for rep in reports:
            print(format_report(rep, args.verbose))
        failed = sum(r.failed for r in reports)
        total = sum(len(r.keys) for r in reports)
        print(f"\n{_count(len(reports), 'mod')}, {failed} with errors, {_count(total, 'key')}")

    return 1 if args.check and any(r.failed for r in reports) else 0


if __name__ == "__main__":
    sys.exit(main())
