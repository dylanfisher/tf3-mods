"""Offline Teal compiler runtime shared by tools/tl_check.py and tests/run_tests.py.

Loads the game's own tl.lua (Teal 0.24.1+dev) into a Lua 5.4 interpreter via
lupa and type-checks or transpiles .tl files against the game's API
definitions. Not a script; scripts that import it must declare
`dependencies = ["lupa"]` in their PEP 723 header.

Urban Games stubbed out Teal's module search in tl.lua (UG_BEGIN_PATCH), so
`tl.init_env` cannot load any definition module as shipped. We undo that with
two text replacements, in memory only; the file on disk is never touched. Each
replacement must match exactly once, so a game update that changes tl.lua fails
loudly instead of silently mis-checking.

Sources, in order of preference: the extracted copy in .cache/game/ (make
docs-game), then the game install (read only).
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Sequence

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import GAME_CACHE_DIR, game_install  # noqa: E402

try:
    # Explicitly 5.4: the default lupa runtime is 5.5, which is not what the game runs.
    from lupa.lua54 import LuaRuntime
except ImportError:  # pragma: no cover
    raise SystemExit("lupa with Lua 5.4 is required; run this script through `uv run`")

# (description, old, new). Undo the UG stubs in require_module and search_for.
PATCHES = [
    (
        "require_module: drop the early `return invalid` so modules are searched",
        """   if mod then
      return mod, env.module_filenames[module_name]
   else
      return a_type(w, "invalid", {}), false
   end
""",
        """   if mod then
      return mod, env.module_filenames[module_name]
   end
""",
    ),
    (
        "search_for: re-enable io.open on candidate files",
        """      -- local fd = io.open(tl_filename, "rb")
      -- if fd then
         -- return tl_filename, fd, tried
      -- end""",
        """      local fd = io.open(tl_filename, "rb")
      if fd then
         return tl_filename, fd, tried
      end""",
    ),
]

# Lua-side helpers. Receives the tl module; returns a table of functions.
HELPERS = r"""
local tl = ...
local H = {}

local function collect(out, list, kind, fallback)
  for _, e in ipairs(list or {}) do
    out[#out + 1] = { file = e.filename or fallback, y = e.y or 1, x = e.x or 1, msg = tostring(e.msg), kind = kind }
  end
end

function H.new_env(predefined, gen_compat, gen_target)
  local ok, env, err = pcall(tl.init_env, false, gen_compat, gen_target, predefined)
  if not ok then return nil, tostring(env) end
  if not env then return nil, tostring(err) end
  return env, false
end

-- Diagnostics for every module loaded into env so far (predefined .d.tl files).
function H.loaded_diags(env)
  local out = {}
  for _, name in ipairs(env.loaded_order) do
    local r = env.loaded[name]
    collect(out, r.syntax_errors, "error", name)
    collect(out, r.type_errors, "error", name)
  end
  return out
end

function H.check(env, src, name, warnings)
  local ok, r, err = pcall(tl.check_string, src, env, name)
  if not ok or not r then
    return { { file = name, y = 1, x = 1, msg = "teal crashed: " .. tostring(ok and err or r), kind = "error" } }
  end
  local out = {}
  collect(out, r.syntax_errors, "error", name)
  collect(out, r.type_errors, "error", name)
  if warnings then collect(out, r.warnings, "warning", name) end
  return out
end

function H.gen(env, src, name, warnings)
  local diags = H.check(env, src, name, warnings)
  for _, d in ipairs(diags) do
    if d.kind == "error" then return nil, diags end
  end
  local r = env.loaded[name]
  local code, gerr = tl.generate(r.ast, env.defaults.gen_target)
  if not code then
    return nil, { { file = name, y = 1, x = 1, msg = "codegen failed: " .. tostring(gerr), kind = "error" } }
  end
  return code, diags
end

function H.lua_syntax(src, name)
  local f, err = load(src, "=" .. name, "t", {})
  if f then return {} end
  local line, msg = tostring(err):match("^.-:(%d+): (.*)$")
  return { { file = name, y = tonumber(line) or 1, x = 1, msg = msg or tostring(err), kind = "error" } }
end

return H
"""


@dataclass(frozen=True)
class Diag:
    file: str
    line: int
    col: int
    msg: str
    kind: str = "error"

    def __str__(self) -> str:
        tag = "" if self.kind == "error" else f"{self.kind}: "
        return f"{self.file}:{self.line}:{self.col}: {tag}{self.msg}"


@dataclass
class GameTeal:
    tl_lua: Path
    include_dirs: list[Path]
    global_defs: list[str]


def locate_game_teal() -> GameTeal:
    """Find tl.lua and the API definition dirs, preferring the extracted cache."""
    roots = [GAME_CACHE_DIR]
    if not (GAME_CACHE_DIR / "base/content/base/tl.lua").exists():
        roots.append(game_install())

    def first(rel: str) -> Path | None:
        return next((r / rel for r in roots if (r / rel).exists()), None)

    tl_lua = first("base/content/base/tl.lua")
    if tl_lua is None:
        raise SystemExit("tl.lua not found; run `make docs-game` or set TF3_INSTALL in .hub.env")
    include_dirs = [d for d in (first("api/tealdef"), first("base/tealdef"), first("vscode-template")) if d]
    # all_def.tl is just `require "api_def"; require "content_def"`; fall back to
    # those two modules directly when the vscode-template copy is missing.
    has_all_def = any((d / "all_def.tl").exists() for d in include_dirs)
    return GameTeal(tl_lua, include_dirs, ["all_def"] if has_all_def else ["api_def", "content_def"])


def patch_tl(src: str) -> str:
    for desc, old, new in PATCHES:
        count = src.count(old)
        if count != 1:
            raise SystemExit(
                f"tl.lua patch '{desc}' matched {count} times (expected 1). "
                "The game's tl.lua changed; update PATCHES in tools/tealrt.py."
            )
        src = src.replace(old, new)
    return src


def def_modules(content_dir: Path) -> list[str]:
    """Dotted module names for every .d.tl under a mod's content dir."""
    names = []
    for p in sorted(content_dir.rglob("*.d.tl")):
        rel = p.relative_to(content_dir).as_posix()[: -len(".d.tl")]
        if "." in rel:
            print(f"warning: {p}: dots in the file name; Teal cannot load it as a module", file=sys.stderr)
            continue
        names.append(rel.replace("/", "."))
    return names


def find_mod_root(path: Path) -> Path | None:
    """Nearest ancestor (or self) that holds a mod.json."""
    path = path.resolve()
    for p in [path, *path.parents]:
        if (p / "mod.json").is_file():
            return p
    return None


class Teal:
    """One Lua 5.4 state with the patched Teal compiler loaded.

    `search_dirs` are extra roots for module search (`<dir>/?.lua` →
    `<dir>/?.d.tl`), e.g. a mod's content/ and tealdef/ dirs.
    """

    def __init__(self, search_dirs: Iterable[Path] = ()):
        game = locate_game_teal()
        self.global_defs = game.global_defs
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        # tl.lua calls log.error in its (patched) module search; the game provides log.
        self.lua.execute(
            "log = setmetatable({}, { __index = function() return function() end end })"
        )
        dirs = [*game.include_dirs, *(Path(d) for d in search_dirs)]
        g.package.path = ";".join(f"{d.resolve().as_posix()}/?.lua" for d in dirs)
        src = patch_tl(game.tl_lua.read_text(encoding="utf-8"))
        tl = self.lua.eval("load")(src, "=tl.lua")()
        self.tl = tl
        self._h = self.lua.eval("load")(HELPERS, "=tealrt")(tl)

    @staticmethod
    def _diags(table: Any) -> list[Diag]:
        if table is None:
            return []
        return [Diag(str(d.file), int(d.y), int(d.x), str(d.msg), str(d.kind)) for d in table.values()]

    def new_env(self, extra_defs: Sequence[str] = (), game_target: bool = False) -> tuple[Any, list[Diag]]:
        """Env with the game's global definitions plus `extra_defs` (dotted module names).

        By default code is generated for this Lua 5.4 host: tl.init_env picks target
        "5.3" from _VERSION, and compat is off. game_target=True instead generates what
        the game's pre-5.3 runtime gets from the same init_env defaults: target "5.1"
        (`//` -> math.floor, bitwise ops -> bit32.*) with gen_compat "optional"
        (math.maxinteger/mininteger polyfilled). That code needs bit32, which the game
        provides but Lua 5.4 does not, so it is for linting, not for running here.

        Returns (env, diagnostics from every loaded definition file). Callers
        usually filter the diagnostics to their own files.
        """
        compat, target = ("optional", "5.1") if game_target else (False, None)
        env, err = self._h.new_env(self.lua.table(*self.global_defs, *extra_defs), compat, target)
        if env is None:
            raise SystemExit(f"Teal env init failed: {err}")
        return env, self._diags(self._h.loaded_diags(env))

    def check(self, env: Any, src: str, name: str, warnings: bool = False) -> list[Diag]:
        return self._diags(self._h.check(env, src, name, warnings))

    def gen(self, env: Any, src: str, name: str, warnings: bool = False) -> tuple[str | None, list[Diag]]:
        """Type-check and transpile to Lua for env's target (see new_env).

        Code is None if there were errors. Teal keeps statement line numbers in the
        output (a compat prologue, if any, shares line 1).
        """
        code, diags = self._h.gen(env, src, name, warnings)
        return (str(code) if code is not None else None), self._diags(diags)

    def lua_syntax(self, src: str, name: str) -> list[Diag]:
        return self._diags(self._h.lua_syntax(src, name))
