# /// script
# requires-python = ">=3.11"
# dependencies = ["lupa"]
# ///
"""Run offline unit tests for mod scripts (Lua 5.4 + the game's Teal compiler).

Usage:
  uv run tests/run_tests.py [-k TEXT] [-j N] [MOD ...]

MOD is a mod dir (mods/<id>) or a modId; default: every mod that has a
tests/<modId>/ folder. Runs tests/<modId>/test_*.lua and test_*.tl in name order.

Test files run in a fresh sandbox each (globals the test or mod code sets stay
in that file). Available there, besides the Lua standard library:
  test(name, fn), before_each(fn)            register tests / a per-test hook
  eq(a, b, msg?), ok(v, msg?), near(a, b, eps?, msg?), raises(fn, text?)
  ug_require(path)                           loads a mod module, transpiled on demand:
      "/dir/x.tl", "<modId>::/dir/x.tl", or a path relative to the requiring file
      ("::/..." base modules and other mods' modules need stub_module first)
  stub_module(path, value), reset_modules()
  set_global(name, value)                    e.g. set_global("api", fakeApi); plain
                                             `api = ...` also works in .lua tests
  log                                        fake game log (verbose/message/warning/error)
  log_entries(), clear_logs()                inspect what was logged
  _(s), getCurrentModId(), getOwningModId()  game globals, faked
Mod .tl modules are type-checked with the mod's .d.tl definitions before they
run; a type error fails the test that required the module. Test .tl files can
use tests/harness.d.tl for the harness globals.
-k runs only tests whose name contains TEXT. -j N runs N test files at once, each in
its own process (default: CPU count; -j 1 runs them in order in one process). Output
is printed per file in name order; `print` inside a test is captured and shown under
that test. Exit code 1 on any failure.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TESTS_DIR.parent / "tools"))
from hubconfig import MODS_DIR, ROOT  # noqa: E402
from tealrt import Teal, def_modules  # noqa: E402

HARNESS = r"""
local compile, mod_id = ...
local runner = {}


local function show(v, depth)
  depth = depth or 0
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" or depth > 3 then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = (type(k) == "string" and k or "[" .. tostring(k) .. "]") .. " = " .. show(v[k], depth + 1)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function deep_eq(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then
    if math.type(a) and math.type(b) then return a == b end
    return false
  end
  for k, v in pairs(a) do if not deep_eq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function normalize(path)
  local out = {}
  for seg in path:gmatch("[^/]+") do
    if seg == ".." then
      if #out == 0 then return nil end
      out[#out] = nil
    elseif seg ~= "." then
      out[#out + 1] = seg
    end
  end
  return table.concat(out, "/")
end

function runner.new_sandbox()
  local sb = setmetatable({}, { __index = _G })
  sb._G = sb
  local stubs, loaded, tests, hooks, logs = {}, {}, {}, {}, {}

  local function fail(msg, user)
    error((user and (user .. ": ") or "") .. msg, 3)
  end

  sb.test = function(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
  sb.before_each = function(fn) hooks[#hooks + 1] = fn end
  sb.eq = function(a, b, msg)
    if not deep_eq(a, b) then fail("expected " .. show(b) .. ", got " .. show(a), msg) end
  end
  sb.ok = function(v, msg) if not v then fail("expected truthy, got " .. show(v), msg) end end
  sb.near = function(a, b, eps, msg)
    eps = eps or 1e-9
    if type(a) ~= "number" or math.abs(a - b) > eps then
      fail("expected " .. tostring(b) .. " +/- " .. tostring(eps) .. ", got " .. show(a), msg)
    end
  end
  sb.raises = function(fn, text)
    local okc, err = pcall(fn)
    if okc then fail("expected an error, none raised") end
    if text and not tostring(err):find(text, 1, true) then
      fail("error " .. show(tostring(err)) .. " does not contain " .. show(text))
    end
  end
  sb.stub_module = function(path, value) stubs[path] = value end
  sb.reset_modules = function() for k in pairs(loaded) do loaded[k] = nil end end
  sb.set_global = function(name, value) rawset(sb, name, value) end
  -- print is captured (shown under the test that printed), so parallel runs don't interleave
  local printed = {}
  sb.print = function(...)
    local parts = table.pack(...)
    for i = 1, parts.n do parts[i] = tostring(parts[i]) end
    printed[#printed + 1] = table.concat(parts, "\t", 1, parts.n)
  end
  sb.take_printed = function()
    local text = table.concat(printed, "\n")
    for i = #printed, 1, -1 do printed[i] = nil end
    return text
  end

  local function logger(level)
    return function(msg, detail)
      logs[#logs + 1] = { level = level, msg = detail and (tostring(msg) .. " " .. tostring(detail)) or tostring(msg) }
    end
  end
  sb.log = { verbose = logger("verbose"), message = logger("message"), warning = logger("warning"), error = logger("error") }
  sb.log_entries = function() return logs end
  sb.clear_logs = function() for i = #logs, 1, -1 do logs[i] = nil end end
  sb._ = function(s) return s end
  sb.getCurrentModId = function() return mod_id end
  sb.getOwningModId = function() return mod_id end

  local own_prefix = mod_id .. "::"
  local function make_require(from_dir)
    return function(path)
      if type(path) ~= "string" then error("ug_require: expected a string path", 2) end
      if stubs[path] ~= nil then return stubs[path] end
      local p = path
      if p:sub(1, #own_prefix) == own_prefix then p = p:sub(#own_prefix + 1) end
      if p:find("::", 1, true) then
        error("ug_require '" .. path .. "': not a module of " .. mod_id .. "; call stub_module(path, value) first", 2)
      end
      local rel = normalize(p:sub(1, 1) == "/" and p or (from_dir .. p))
      if not rel then error("ug_require '" .. path .. "': path escapes the content dir", 2) end
      if stubs["/" .. rel] ~= nil then return stubs["/" .. rel] end
      if loaded[rel] ~= nil then return loaded[rel] end
      local code, chunkname, err = compile(rel)
      if not code then error("ug_require '" .. path .. "':\n" .. tostring(err), 2) end
      local env = setmetatable({ ug_require = make_require(rel:match("^(.*/)") or "") },
        { __index = sb, __newindex = sb })
      local chunk, lerr = load(code, "@" .. chunkname, "t", env)
      if not chunk then error(lerr, 2) end
      local result = chunk()
      if result == nil then result = true end
      loaded[rel] = result
      return result
    end
  end
  sb.ug_require = make_require("")
  return sb, tests, hooks
end

-- Runs one test file's code. Returns {load_error=?, results={{name, ok, err}}}.
function runner.run_file(code, chunkname, filter)
  local sb, tests, hooks = runner.new_sandbox()
  local out = { results = {} }
  local chunk, err = load(code, "@" .. chunkname, "t", sb)
  if not chunk then out.load_error = err return out end
  local okl, lerr = xpcall(chunk, debug.traceback)
  out.printed = sb.take_printed()
  if not okl then out.load_error = lerr return out end
  for _, t in ipairs(tests) do
    if not filter or t.name:find(filter, 1, true) then
      local okt, terr = xpcall(function()
        for _, h in ipairs(hooks) do h() end
        t.fn()
      end, debug.traceback)
      out.results[#out.results + 1] = { name = t.name, ok = okt, err = okt and "" or tostring(terr),
        printed = sb.take_printed() }
    end
  end
  return out
end

return runner
"""


def display(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def resolve_mod(arg: str) -> Path:
    path = Path(arg)
    if not (path / "mod.json").is_file():
        path = MODS_DIR / arg
    if not (path / "mod.json").is_file():
        raise SystemExit(f"{arg}: not a mod dir or modId")
    return path.resolve()


def trim_traceback(text: str) -> str:
    """Drop harness frames so tracebacks point at test and mod code."""
    keep = [ln for ln in text.splitlines() if "[C]: in" not in ln and "run_tests" not in ln]
    while keep and keep[-1].strip() in ("stack traceback:", "(...tail calls...)"):
        keep.pop()
    return "\n".join(keep)


class ModRunner:
    """One mod's Teal env and harness in this process; runs its test files one at a time."""

    def __init__(self, mod: Path):
        self.mod_id = mod.name
        content = mod / "content"
        search = [d for d in (content, mod / "tealdef", TESTS_DIR) if d.is_dir()]
        self.teal = Teal(search)
        self.env, def_diags = self.teal.new_env([*def_modules(content), "harness"])
        own_errors = [d for d in def_diags if Path(d.file).resolve().is_relative_to(mod) or "harness" in d.file]
        if own_errors:
            raise SystemExit("\n".join(map(str, own_errors))
                             + f"\n[{self.mod_id}] definition files have errors; run `make check MOD={display(mod)}`")
        cache: dict[str, tuple] = {}

        def compile_module(rel: str):
            """Lua callback: content-relative path -> (code, chunkname, error)."""
            if rel in cache:
                return cache[rel]
            path = content / rel
            name = display(path)
            if not path.is_file():
                result = (None, name, f"no such file {name}")
            elif path.suffix == ".tl":
                code, diags = self.teal.gen(self.env, path.read_text(encoding="utf-8-sig"), name)
                result = (code, name, "\n".join(map(str, diags)) or None)
            else:
                result = (path.read_text(encoding="utf-8-sig"), name, None)
            cache[rel] = result
            return result

        self.runner = self.teal.lua.eval("load")(HARNESS, "=run_tests")(compile_module, self.mod_id)

    def run_file(self, tf: Path, filter_text: str | None) -> tuple[int, int, str]:
        """Runs one test file; returns (passed, failed, report text)."""
        name = display(tf)
        started = time.perf_counter()
        lines: list[str] = []
        passed = failed = 0

        def indent(text: str, prefix: str) -> str:
            return prefix + text.replace("\n", "\n" + prefix)

        src = tf.read_text(encoding="utf-8-sig")
        if tf.suffix == ".tl":
            code, diags = self.teal.gen(self.env, src, name)
            if code is None:
                lines.append("    FAIL  (compile)")
                lines.extend(f"      {d}" for d in diags)
                return 0, 1, "\n".join([f"  {name}", *lines])
            src = code
        out = self.runner.run_file(src, name, filter_text)
        if out.printed:
            lines.append(indent(str(out.printed), "      "))
        if out.load_error is not None:
            failed += 1
            lines.append("    FAIL  (loading file)")
            lines.append(indent(trim_traceback(str(out.load_error)), "      "))
        else:
            for r in out.results.values():
                if r.ok:
                    passed += 1
                    lines.append(f"    ok    {r.name}")
                else:
                    failed += 1
                    lines.append(f"    FAIL  {r.name}")
                    lines.append(indent(trim_traceback(str(r.err)), "      "))
                if r.printed:
                    lines.append(indent(str(r.printed), "      "))
        took = time.perf_counter() - started
        header = f"  {name}" + (f"  ({took:.1f} s)" if took >= 1 else "")
        return passed, failed, "\n".join([header, *lines])


_RUNNERS: dict[Path, ModRunner] = {}


def run_file(mod: Path, tf: Path, filter_text: str | None) -> tuple[int, int, str]:
    """Worker entry: one test file, reusing this process's runner for the mod."""
    if mod not in _RUNNERS:
        _RUNNERS[mod] = ModRunner(mod)
    return _RUNNERS[mod].run_file(tf, filter_text)


def test_files(mod: Path) -> list[Path]:
    return sorted(p for p in (TESTS_DIR / mod.name).glob("test_*") if p.suffix in (".lua", ".tl"))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mods", nargs="*")
    parser.add_argument("-k", dest="filter", help="only tests whose name contains this text")
    parser.add_argument("-j", dest="jobs", type=int, default=os.cpu_count() or 1,
                        help="test files run in parallel (default: CPU count; 1 = serial)")
    args = parser.parse_args()

    if args.mods:
        mods = [resolve_mod(m) for m in args.mods]
    else:
        mods = sorted(p.resolve() for p in MODS_DIR.iterdir() if (TESTS_DIR / p.name).is_dir())
    jobs = [(mod, tf) for mod in mods for tf in test_files(mod)]
    for mod in mods:
        if not test_files(mod):
            print(f"[{mod.name}] no tests in {display(TESTS_DIR / mod.name)}")

    started = time.perf_counter()
    passed = failed = 0
    current = None

    def report(mod: Path, result: tuple[int, int, str]) -> None:
        nonlocal passed, failed, current
        if mod != current:
            print(f"[{mod.name}]")
            current = mod
        passed += result[0]
        failed += result[1]
        print(result[2], flush=True)

    if args.jobs <= 1 or len(jobs) <= 1:
        for mod, tf in jobs:
            report(mod, run_file(mod, tf, args.filter))
    else:
        with ProcessPoolExecutor(max_workers=min(args.jobs, len(jobs))) as pool:
            futures = [pool.submit(run_file, mod, tf, args.filter) for mod, tf in jobs]
            for (mod, _), fut in zip(jobs, futures):  # print in name order as results arrive
                report(mod, fut.result())
    print(f"{passed} passed, {failed} failed ({time.perf_counter() - started:.1f} s)")
    sys.exit(1 if failed or not passed else 0)


if __name__ == "__main__":
    main()
