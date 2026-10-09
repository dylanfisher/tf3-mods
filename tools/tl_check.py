# /// script
# requires-python = ">=3.11"
# dependencies = ["lupa"]
# ///
"""Type-check Teal (.tl) and syntax-check Lua (.lua) files offline with the
game's own Teal compiler (see tools/tealrt.py) and API definitions.

Usage:
  uv run tools/tl_check.py [-W] [--allow-lua53] [PATH ...]

PATH may be a mod dir (anything with a mod.json: checks every file under its
content/), or any .tl/.lua file or directory. Files inside a mod are checked
with that mod's .d.tl definitions loaded (every content/**/*.d.tl, as dotted
module names), and that mod's content/ and tealdef/ dirs on the module path.
With no PATH, every mod in mods/ is checked. A tealdef/ copy of a content/ .d.tl
(official mod layout) must match its original byte for byte.

.tl files (not .d.tl) get a full type check; .d.tl files are checked when they
load as definitions; .lua files get a load() syntax check only.
-W also prints Teal warnings (unused variables etc.); they never fail the check.

Pre-5.3 lint: TF3's in-game Lua is older than 5.3 (math.tointeger is nil there; no
base-game .lua uses `//` or bitwise operators; base code uses bit32), while this
checker runs Lua 5.4. Every plain .lua file is tokenized and scanned for 5.3+-only
constructs: math.tointeger, math.type, math.maxinteger, math.mininteger, math.ult,
utf8.*, string.pack/unpack/packsize, table.move, `//`, the bitwise operators
`& | ~ << >>` (binary and unary ~), and <const>/<close> attributes.
.tl files are transpiled the way the game's runtime would get them from tl.init_env's
defaults (target 5.1, gen_compat optional; see tealrt.Teal.new_env), and that Lua is
scanned. Teal rewrites `//` and bitwise operators (math.floor, bit32.*), polyfills
math.maxinteger/mininteger and strips <const>, so those are fine in .tl source (the
base game's new_game_or_map_settings_page.tl uses `1 << levels`); the library calls
Teal leaves alone are not. Teal keeps statement lines, so findings point at the .tl
source. If type errors block codegen, the .tl source is scanned for those library
calls instead. Findings are errors (`path:line:col: pre-5.3 Lua: <construct>`);
--allow-lua53 skips the lint (and transpiles for 5.4) for files that never run in
the game.

Output: `path:line:col: message`. Exit code 1 if anything has errors.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR, ROOT  # noqa: E402
from tealrt import Diag, Teal, def_modules, find_mod_root  # noqa: E402


def display(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def collect(path: Path) -> list[Path]:
    if path.is_file():
        return [path]
    files = [p for p in path.rglob("*") if p.is_file() and p.suffix in (".tl", ".lua") and not p.name.endswith(".d.tl")]
    return sorted(files)


def stale_tealdef(mod_root: Path) -> list[Diag]:
    """tealdef/ holds editor-only copies of content/ .d.tl files (official mod layout, e.g.
    urbangames_campaign_mission_08/tealdef). Only content/ is loaded for checking, so the copies
    never cause duplicate declarations; flag a copy that drifted from its content/ original."""
    tealdef, content = mod_root / "tealdef", mod_root / "content"
    out: list[Diag] = []
    if not tealdef.is_dir():
        return out
    for copy in sorted(tealdef.rglob("*.d.tl")):
        orig = content / copy.relative_to(tealdef)
        if orig.is_file() and orig.read_bytes() != copy.read_bytes():
            out.append(Diag(str(copy), 1, 1, f"stale copy: differs from {display(orig)} (copy it again)", "error"))
    return out


# Matches a plain `require "a.b"` / `require("a.b")` (not ug_require, which loads real modules).
REQUIRE_RE = re.compile(r"""(?<![\w.])require\s*\(?\s*["']([\w.]+)["']""")


def def_only_requires(name: str, src: str, content: Path | None) -> list[Diag]:
    """A runtime `require` of a module that exists only as a .d.tl fails in game ("module ... not
    found": types-only files are never shipped as code). The checker loads content/**/*.d.tl as
    modules, so it would resolve fine offline. Put the require in tealdef/<modId>_def.d.tl instead
    (see square_problem_radar)."""
    if content is None or not content.is_dir():
        return []
    out = []
    for lineno, line in enumerate(src.splitlines(), 1):
        for m in REQUIRE_RE.finditer(line.split("--", 1)[0]):
            rel = m.group(1).replace(".", "/")
            if (content / f"{rel}.d.tl").is_file() and not any(
                (content / f"{rel}{ext}").is_file() for ext in (".tl", ".lua")
            ):
                out.append(Diag(name, lineno, m.start() + 1,
                                f'require "{m.group(1)}" names a .d.tl-only module: it fails at runtime; '
                                "require it from tealdef/<modId>_def.d.tl instead", "error"))
    return out


# --- pre-5.3 Lua lint -------------------------------------------------------------------

LINT_PREFIX = "pre-5.3 Lua: "
KEYWORDS = frozenset(
    "and break do else elseif end false for function goto if in local nil not or repeat "
    "return then true until while".split()
)
# Multi-char operators, longest first, so `//` wins over `/` and `~=` over `~`.
OPERATORS = ("...", "..", "==", "~=", "<=", ">=", "<<", ">>", "//", "::")
SINGLE_OPS = frozenset("+-*/%^#&~|<>=(){}[];:,.")
LIB_53 = frozenset(
    {
        ("math", "tointeger"), ("math", "type"), ("math", "maxinteger"), ("math", "mininteger"),
        ("math", "ult"), ("string", "pack"), ("string", "unpack"), ("string", "packsize"),
        ("table", "move"),
    }
)


@dataclass(frozen=True)
class Tok:
    kind: str  # name | kw | num | str | op | eof
    text: str
    line: int
    col: int


def _long_bracket(src: str, i: int) -> int:
    """Level of a long bracket opening `[=*[` at i, or -1."""
    j = i + 1
    while j < len(src) and src[j] == "=":
        j += 1
    return j - i - 1 if j < len(src) and src[j] == "[" else -1


def lua_tokens(src: str) -> list[Tok]:
    """Tokenize Lua 5.1-5.4 (good enough for Teal too). Strings and comments are consumed
    whole, so nothing inside them is ever seen as code. Lenient on malformed input; the
    syntax check reports that."""
    toks: list[Tok] = []
    n, i, line, bol = len(src), 0, 1, 0
    if src.startswith("#"):  # shebang line
        while i < n and src[i] not in "\r\n":
            i += 1

    def newline(k: int) -> int:
        nonlocal line, bol
        k += 2 if src[k : k + 2] in ("\r\n", "\n\r") else 1
        line, bol = line + 1, k
        return k

    def skip_long(k: int, level: int) -> int:
        """k at the opening `[`; returns the index past the matching close."""
        close = "]" + "=" * level + "]"
        k += level + 2
        while k < n:
            if src[k] in "\r\n":
                k = newline(k)
            elif src.startswith(close, k):
                return k + len(close)
            else:
                k += 1
        return n

    while i < n:
        c = src[i]
        if c in "\r\n":
            i = newline(i)
            continue
        if c in " \t\f\v":
            i += 1
            continue
        tline, tcol = line, i - bol + 1
        if src.startswith("--", i):
            if (lvl := _long_bracket(src, i + 2) if src.startswith("[", i + 2) else -1) >= 0:
                i = skip_long(i + 2, lvl)
            else:
                while i < n and src[i] not in "\r\n":
                    i += 1
            continue
        if c == "[" and (lvl := _long_bracket(src, i)) >= 0:
            start = i
            i = skip_long(i, lvl)
            toks.append(Tok("str", src[start:i], tline, tcol))
            continue
        if c in "\"'":
            start = i
            i += 1
            while i < n and src[i] != c:
                if src[i] in "\r\n":
                    break  # unterminated
                if src[i] == "\\" and i + 1 < n:
                    i += 1
                    if src[i] in "\r\n":  # escaped newline
                        i = newline(i)
                        continue
                    if src[i] == "z":  # \z skips the following whitespace, newlines included
                        i += 1
                        while i < n and src[i] in " \t\f\v\r\n":
                            i = newline(i) if src[i] in "\r\n" else i + 1
                        continue
                i += 1
            i = min(i + 1, n)
            toks.append(Tok("str", src[start:i], tline, tcol))
            continue
        if c.isdigit() or (c == "." and i + 1 < n and src[i + 1].isdigit()):
            # Same greedy rule as llex.c read_numeral.
            start = i
            expo = "Pp" if src.startswith(("0x", "0X"), i) else "Ee"
            if expo == "Pp":
                i += 2
            while i < n:
                if src[i] in expo:
                    i += 2 if i + 1 < n and src[i + 1] in "+-" else 1
                elif src[i].isalnum() or src[i] in "._":
                    i += 1
                else:
                    break
            toks.append(Tok("num", src[start:i], tline, tcol))
            continue
        if c.isalpha() or c == "_":
            start = i
            while i < n and (src[i].isalnum() or src[i] == "_"):
                i += 1
            word = src[start:i]
            toks.append(Tok("kw" if word in KEYWORDS else "name", word, tline, tcol))
            continue
        op = next((o for o in OPERATORS if src.startswith(o, i)), c if c in SINGLE_OPS else None)
        if op is None:  # stray character; the syntax check reports it
            i += 1
            continue
        toks.append(Tok("op", op, tline, tcol))
        i += len(op)
    toks.append(Tok("eof", "", line, i - bol + 1))
    return toks


def _ends_operand(t: Tok | None) -> bool:
    """Can an expression end with t (so a following `~` is binary xor, not unary not)?"""
    if t is None:
        return False
    return t.kind in ("name", "num", "str") or t.text in (")", "]", "}", "...", "nil", "true", "false", "end")


def _in_local_names(toks: list[Tok], j: int) -> bool:
    """toks[j] is the name before a `<attr>`: is it in a `local a <x>, b <y>` name list?"""
    while j > 0:
        if toks[j].kind != "name":
            return False
        j -= 1
        if toks[j].text == "local":
            return True
        if toks[j].text != ",":
            return False
        j -= 1
        if toks[j].text == ">" and j >= 2 and toks[j - 2].text == "<":
            j -= 3
    return False


def lua53_findings(src: str) -> list[tuple[int, int, str]]:
    """(line, col, construct) for every Lua 5.3+-only construct in Lua source."""
    toks = lua_tokens(src)
    out: list[tuple[int, int, str]] = []
    for k, t in enumerate(toks[:-1]):
        prev = toks[k - 1] if k else None
        nxt = toks[k + 1]
        if t.kind == "name":
            if prev is not None and prev.text in (".", ":"):
                continue  # a field such as foo.math.type, not the library
            nn = toks[k + 2] if k + 2 < len(toks) else nxt
            if t.text == "utf8" and nxt.text in (".", ":", "["):
                out.append((t.line, t.col, "utf8 library"))
            elif nxt.text == "." and nn.kind == "name" and (t.text, nn.text) in LIB_53:
                out.append((t.line, t.col, f"{t.text}.{nn.text}"))
        elif t.kind == "op":
            if t.text == "//":
                out.append((t.line, t.col, "integer division '//'"))
            elif t.text in ("&", "|", "<<", ">>"):
                out.append((t.line, t.col, f"bitwise operator '{t.text}'"))
            elif t.text == "~":
                out.append((t.line, t.col, f"bitwise {'xor' if _ends_operand(prev) else 'not'} '~'"))
            elif (
                t.text == "<"
                and nxt.text in ("const", "close")
                and k + 2 < len(toks)
                and toks[k + 2].text == ">"
                and _in_local_names(toks, k - 1)
            ):
                out.append((t.line, t.col, f"<{nxt.text}> attribute"))
    return out


# Constructs (as lua53_findings labels them) that Teal's game-target codegen takes care of.
TEAL_POLYFILLED = frozenset({"math.maxinteger", "math.mininteger"})
TEAL_REWRITTEN = TEAL_POLYFILLED | {
    "integer division '//'", "bitwise xor '~'", "bitwise not '~'", "<const> attribute",
    "<close> attribute",  # a Teal type error for target 5.1
    *(f"bitwise operator '{op}'" for op in ("&", "|", "<<", ">>")),
}


def lint_lua53(
    name: str, lua_src: str, tl_src: str | None = None, skip: frozenset[str] = frozenset()
) -> list[Diag]:
    """Errors for 5.3+-only constructs in lua_src, minus the `skip` labels. When lua_src was
    generated from tl_src, Teal has kept statement lines, so each finding is matched to the
    same construct on the same .tl line for its column. One that only exists in the
    generated code (none known) keeps its generated position and says so."""
    src_cols: dict[tuple[int, str], list[int]] = {}
    if tl_src is not None:
        for line, col, what in lua53_findings(tl_src):
            src_cols.setdefault((line, what), []).append(col)
    out = []
    for line, col, what in lua53_findings(lua_src):
        if what in skip:
            continue
        msg = LINT_PREFIX + what
        if tl_src is not None:
            if cols := src_cols.get((line, what)):
                col = cols.pop(0)
            else:
                msg += " (position in the generated Lua)"
        out.append(Diag(name, line, col, msg, "error"))
    return out


def check_group(
    mod_root: Path | None, files: list[Path], warnings: bool, lint53: bool = True
) -> tuple[list[Diag], int]:
    """Check files that share one mod (or none). Returns (diags, files checked)."""
    search_dirs: list[Path] = []
    defs: list[str] = []
    if mod_root:
        content = mod_root / "content"
        search_dirs = [d for d in (content, mod_root / "tealdef") if d.is_dir()]
        if content.is_dir():
            defs = def_modules(content)
    teal = Teal(search_dirs)
    env, def_diags = teal.new_env(defs, game_target=lint53)
    diags: list[Diag] = []
    if mod_root:
        root = mod_root.resolve()
        diags += [d for d in def_diags if Path(d.file).resolve().is_relative_to(root)]

    if mod_root:
        diags += stale_tealdef(mod_root)

    checked = 0
    for f in files:
        name = display(f)
        src = f.read_text(encoding="utf-8-sig")  # BOMs are validate_mod.py's concern
        if not f.name.endswith(".d.tl"):
            diags += def_only_requires(name, src, mod_root / "content" if mod_root else None)
        if f.name.endswith(".d.tl"):
            # Explicitly requested definition file outside the predefined set.
            diags += teal.check(env, src, str(f.resolve()), warnings)
        elif f.suffix == ".tl":
            if lint53:
                code, tl_diags = teal.gen(env, src, name, warnings)
                diags += tl_diags
                if code is not None:
                    # math.maxinteger/mininteger in game-target output only appear in
                    # Teal's compat polyfill (`math.maxinteger or math.pow(2, 53)`).
                    diags += lint_lua53(name, code, src, skip=TEAL_POLYFILLED)
                else:
                    # Type errors block codegen; scan the .tl source so the lint never
                    # drops out silently. Skip what Teal rewrites, and `|`/`>>`, which
                    # are also Teal type syntax (unions, nested generics).
                    diags += lint_lua53(name, src, skip=TEAL_REWRITTEN)
            else:
                diags += teal.check(env, src, name, warnings)
        else:
            syntax = teal.lua_syntax(src, name)
            diags += syntax
            if lint53 and not syntax:
                diags += lint_lua53(name, src)
        checked += 1
    return [Diag(display(Path(d.file)), d.line, d.col, d.msg, d.kind) for d in diags], checked


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="*", type=Path)
    parser.add_argument("-W", "--warnings", action="store_true", help="also print Teal warnings")
    parser.add_argument(
        "--allow-lua53",
        action="store_true",
        help="skip the pre-5.3 Lua lint (only for files that never run in the game)",
    )
    args = parser.parse_args()

    paths = args.paths or sorted(p for p in MODS_DIR.iterdir() if (p / "mod.json").is_file())
    groups: dict[Path | None, list[Path]] = {}
    for path in paths:
        if not path.exists():
            raise SystemExit(f"{path}: not found")
        root = find_mod_root(path)
        target = root / "content" if root and path.resolve() == root else path
        groups.setdefault(root, [])
        if target.exists():
            groups[root] += collect(target)

    total_errors = total_files = lint_errors = 0
    for root, files in groups.items():
        diags, checked = check_group(root, sorted(set(files)), args.warnings, not args.allow_lua53)
        total_files += checked
        for d in diags:
            print(d)
        total_errors += sum(d.kind == "error" for d in diags)
        lint_errors += sum(d.msg.startswith(LINT_PREFIX) for d in diags)

    if lint_errors:
        print(
            f"tl_check: {lint_errors} pre-5.3 construct(s); the game's Lua is older than 5.3 "
            "(--allow-lua53 skips this lint, only for files that never run in the game)"
        )

    print(f"tl_check: {total_files} file(s), {total_errors} error(s)")
    sys.exit(1 if total_errors else 0)


if __name__ == "__main__":
    main()
