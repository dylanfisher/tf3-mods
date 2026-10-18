# /// script
# requires-python = ">=3.11"
# dependencies = ["lupa"]
# ///
"""Run offline unit tests for mod scripts (Lua 5.4 + the game's Teal compiler).

Usage:
  uv run tests/run_tests.py [-k TEXT] [-f FILE] [-j N] [--full] [--no-cache] MOD ... | --all

MOD is a mod dir (mods/<id>) or a modId (--all: every mod that has a tests/<modId>/ folder;
one mod's work never needs it). Runs tests/<modId>/test_*.lua and test_*.tl in name order.

Result cache: each run records, per test file, every file it read (the test file, mod modules
through ug_require, loadfile / dofile / io.open / io.lines reads) with its hash, the env vars it
read (os.getenv) and its test names, in .cache/test_results.json. A file whose last run passed
and whose inputs are all unchanged (and this runner, tealrt, the mod's .d.tl files, tl.lua and
TEALRT_LUA) is not run again: it counts as passed and shows on the mod's "cached:" line.
--no-cache runs everything. A file that opens a file in the repo for writing is never cached (temp files outside it are fine). A -k run never
records a pass (only some tests ran), but skips files whose recorded names have no match.

Quick and full: sweeps over every parameter combination sample by default (e.g. every 7th case)
and check every case when TEST_FULL is set: `--full` (make gate) sets it. Tests read
`os.getenv("TEST_FULL")`. A pass recorded with --full also stands for a later quick run.
SQRB_FULL=1 (the exhaustive roundabouts sweep) implies TEST_FULL.

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
-k runs only tests whose name contains TEXT (plain substring of the test name, not the
file name: `-k short` also hits "... short edges" tests elsewhere); files with no match
are not listed, but every file still loads. -f TEXT keeps only test files whose name
contains TEXT (repeatable; e.g. `-f through -f ramps`), so the others never load.
-j N runs N worker processes (default: about one per 2 s of recorded CPU time, at most the
CPU count, since each worker spends ~0.8 s starting Teal; -j 1 runs everything in order in
one process). Output is printed per file in name order with the time of each test >= 1 s;
`print` inside a test is captured and shown under that test. Exit code 1 on any failure.

Sharding: each run records per-test CPU seconds in .cache/test_timings.json. Later runs
split a slow file into shards (each a process that loads the file and runs a subset of
its tests; tests not in the record run in the first shard), slowest first, so one long
file no longer sets the wall time. Tests must not depend on state left by an earlier
test in the same file; a file that does puts the text "run_tests: no-split" in it.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TESTS_DIR.parent / "tools"))
from hubconfig import CACHE_DIR, MODS_DIR, ROOT  # noqa: E402
from tealrt import Teal, def_modules, locate_game_teal  # noqa: E402

HARNESS = r"""
local compile, mod_id, note = ...
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

  -- files and env vars the test reads are noted, so the result cache knows what a pass depends on
  local function note_read(path) if type(path) == "string" then note("file", path) end end
  sb.loadfile = function(path, ...) note_read(path) return loadfile(path, ...) end
  sb.dofile = function(path) note_read(path) return dofile(path) end
  sb.io = setmetatable({
    open = function(path, mode, ...)
      if type(mode) == "string" and mode:find("[wa+]") then note("write", tostring(path)) else note_read(path) end
      return io.open(path, mode, ...)
    end,
    lines = function(path, ...) note_read(path) return io.lines(path, ...) end,
  }, { __index = io })
  sb.os = setmetatable({
    getenv = function(name)
      local value = os.getenv(name)
      note("env", tostring(name), value)
      return value
    end,
  }, { __index = os })

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

local function name_set(text)
  if not text then return nil end
  local set = {}
  for n in (text .. "\n"):gmatch("([^\n]*)\n") do set[n] = true end
  return set
end

-- Runs one test file's code. Returns {load_error=?, results={{idx, name, ok, err, printed, secs}}}.
-- only / known (names joined by "\n", or nil) pick a shard of the file: run the tests named in
-- only, plus any test not named in known (new since the timings were recorded).
function runner.run_file(code, chunkname, filter, only, known)
  local sb, tests, hooks = runner.new_sandbox()
  local out = { results = {} }
  local chunk, err = load(code, "@" .. chunkname, "t", sb)
  if not chunk then out.load_error = err return out end
  local okl, lerr = xpcall(chunk, debug.traceback)
  out.printed = sb.take_printed()
  if not okl then out.load_error = lerr return out end
  out.names = {}
  for i, t in ipairs(tests) do out.names[i] = t.name end
  local onlySet, knownSet = name_set(only), name_set(known)
  for idx, t in ipairs(tests) do
    local picked = not onlySet or onlySet[t.name] or (knownSet and not knownSet[t.name])
    if picked and (not filter or t.name:find(filter, 1, true)) then
      local t0 = os.clock()
      local okt, terr = xpcall(function()
        for _, h in ipairs(hooks) do h() end
        t.fn()
      end, debug.traceback)
      out.results[#out.results + 1] = { idx = idx, name = t.name, ok = okt, err = okt and "" or tostring(terr),
        printed = sb.take_printed(), secs = os.clock() - t0 }
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


@dataclass
class Deps:
    """What one test file run read: files (repo path -> hash, None if missing), env vars, any write."""
    files: dict[str, str | None] = field(default_factory=dict)
    env: dict[str, str | None] = field(default_factory=dict)
    writes: bool = False  # opened a file in the repo for writing: never cached
    scratch: set[str] = field(default_factory=set)  # files written outside the repo


def file_hash(data: bytes) -> str:
    return hashlib.blake2b(data, digest_size=12).hexdigest()


def path_hash(path: Path) -> str | None:
    try:
        return file_hash(path.read_bytes())
    except OSError:
        return None


def base_stamp(mod: Path) -> str:
    """Hash of what every test of the mod depends on besides the files it reads: this runner,
    tealrt, the mod's Teal definitions, the game's tl.lua and the Lua version."""
    parts = [path_hash(Path(__file__)), path_hash(TESTS_DIR.parent / "tools" / "tealrt.py"),
             path_hash(TESTS_DIR / "harness.d.tl"), os.environ.get("TEALRT_LUA", "54")]
    defs = [*(mod / "content").rglob("*.d.tl"), *((mod / "tealdef").rglob("*") if (mod / "tealdef").is_dir() else [])]
    parts += [f"{display(p)}={path_hash(p)}" for p in sorted(defs) if p.is_file()]
    tl_lua = locate_game_teal().tl_lua
    st = tl_lua.stat()
    parts.append(f"{tl_lua}:{st.st_size}:{st.st_mtime_ns}")
    return file_hash("\n".join(map(str, parts)).encode())


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
        self.deps: Deps = Deps()

        def compile_module(rel: str):
            """Lua callback: content-relative path -> (code, chunkname, error)."""
            path = content / rel
            name = display(path)
            if rel in cache:
                self.deps.files[name] = cache[rel][1]
                return cache[rel][0]
            if not path.is_file():
                digest, result = None, (None, name, f"no such file {name}")
            else:
                raw = path.read_bytes()
                digest, text = file_hash(raw), raw.decode("utf-8-sig")
                if path.suffix == ".tl":
                    code, diags = self.teal.gen(self.env, text, name)
                    result = (code, name, "\n".join(map(str, diags)) or None)
                else:
                    result = (text, name, None)
            cache[rel] = (result, digest)
            self.deps.files[name] = digest
            return result

        def note(kind: str, value: str, extra=None):
            """Lua callback: the test read a file or an env var, or opened a file for writing."""
            if kind == "env":
                self.deps.env[value] = None if extra is None else str(extra)
            elif kind == "write":
                # a scratch file outside the repo (os.tmpname) doesn't stop caching; its read-back isn't an input
                path = Path(value).resolve()
                if path.is_relative_to(ROOT):
                    self.deps.writes = True
                else:
                    self.deps.scratch.add(str(path))
            elif str(Path(value).resolve()) not in self.deps.scratch:
                name = display(Path(value))
                if name not in self.deps.files:
                    self.deps.files[name] = path_hash(Path(value))

        self.runner = self.teal.lua.eval("load")(HARNESS, "=run_tests")(compile_module, self.mod_id, note)

    def run_file(self, tf: Path, filter_text: str | None, only: list[str] | None = None,
                 known: list[str] | None = None) -> dict:
        """Runs one test file (or the shard picked by only/known); returns plain data for the parent."""
        name = display(tf)
        started = time.perf_counter()
        raw = tf.read_bytes()
        self.deps = Deps(files={name: file_hash(raw)})
        src = raw.decode("utf-8-sig")
        if tf.suffix == ".tl":
            code, diags = self.teal.gen(self.env, src, name)
            if code is None:
                return {"compile_errors": [str(d) for d in diags], "results": [], "took": 0.0}
            src = code
        join = (lambda names: "\n".join(names) if names is not None else None)
        out = self.runner.run_file(src, name, filter_text, join(only), join(known))
        results = [] if out.results is None else [
            {"idx": int(r.idx), "name": str(r.name), "ok": bool(r.ok), "err": str(r.err),
             "printed": str(r.printed or ""), "secs": float(r.secs)} for r in out.results.values()]
        return {"printed": str(out.printed or ""),
                "load_error": None if out.load_error is None else str(out.load_error),
                "results": results, "took": time.perf_counter() - started,
                "names": None if out.names is None else [str(n) for n in out.names.values()],
                "deps": self.deps.files, "env": self.deps.env, "writes": self.deps.writes}


def format_file(name: str, shards: list[dict]) -> tuple[int, int, str]:
    """Merges a file's shard outputs (in test order); returns (passed, failed, report text)."""

    def indent(text: str, prefix: str) -> str:
        return prefix + text.replace("\n", "\n" + prefix)

    lines: list[str] = []
    passed = failed = 0
    first = shards[0]
    took = max(s["took"] for s in shards)
    if first.get("compile_errors"):
        return 0, 1, "\n".join([f"  {name}", "    FAIL  (compile)", *(f"      {d}" for d in first["compile_errors"])])
    if first.get("printed"):
        lines.append(indent(first["printed"], "      "))
    load_error = next((s["load_error"] for s in shards if s.get("load_error")), None)
    if load_error is not None:
        failed += 1
        lines.append("    FAIL  (loading file)")
        lines.append(indent(trim_traceback(load_error), "      "))
    else:
        for r in sorted((r for s in shards for r in s["results"]), key=lambda r: r["idx"]):
            secs = f"  ({r['secs']:.1f} s)" if r["secs"] >= 1 else ""
            if r["ok"]:
                passed += 1
                lines.append(f"    ok    {r['name']}{secs}")
            else:
                failed += 1
                lines.append(f"    FAIL  {r['name']}{secs}")
                lines.append(indent(trim_traceback(r["err"]), "      "))
            if r["printed"]:
                lines.append(indent(r["printed"], "      "))
    split = f", {len(shards)} shards" if len(shards) > 1 else ""
    header = f"  {name}" + (f"  ({took:.1f} s{split})" if took >= 1 else "")
    return passed, failed, "\n".join([header, *lines])


_RUNNERS: dict[Path, ModRunner] = {}


def run_file(mod: Path, tf: Path, filter_text: str | None, only=None, known=None) -> dict:
    """Worker entry: one test file or shard, reusing this process's runner for the mod."""
    if mod not in _RUNNERS:
        _RUNNERS[mod] = ModRunner(mod)
    return _RUNNERS[mod].run_file(tf, filter_text, only, known)


def test_files(mod: Path) -> list[Path]:
    return sorted(p for p in (TESTS_DIR / mod.name).glob("test_*") if p.suffix in (".lua", ".tl"))


# Per-test CPU seconds from earlier runs (gitignored); used to split slow files into shards.
TIMINGS = CACHE_DIR / "test_timings.json"
NO_SPLIT = "run_tests: no-split"  # put this in a test file whose tests depend on each other's state
# Per test file: what its last run read (file hashes, env vars), its test names and whether it all
# passed (gitignored). A file whose last pass still holds is reported as cached instead of run.
RESULTS = CACHE_DIR / "test_results.json"
FULL_ENV = "TEST_FULL"  # set by --full: sweeps that sample in the default quick mode check every case


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def save_json(path: Path, update: dict, drop: set[str]) -> None:
    """Merges into the file as it is now (another session may have written it since) and
    replaces it atomically."""
    data = load_json(path)
    data.update(update)
    for key in drop:
        data.pop(key, None)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
        tmp.write_text(json.dumps(data, indent=0, sort_keys=True))
        os.replace(tmp, path)
    except OSError:
        pass


class InputCheck:
    """Tells whether the files and env vars a recorded run read are unchanged (hashes memoized)."""

    def __init__(self):
        self.memo: dict[str, str | None] = {}

    def current(self, name: str) -> str | None:
        if name not in self.memo:
            path = Path(name)
            self.memo[name] = path_hash(path if path.is_absolute() else ROOT / path)
        return self.memo[name]

    def same(self, rec: dict | None, base: str, exact_env: bool) -> bool:
        """exact_env=False lets a record made with --full stand for a quick run (a superset)."""
        if not rec or rec.get("base") != base:
            return False
        for name, value in rec.get("env", {}).items():
            now = os.environ.get(name)
            if now != value and (exact_env or name != FULL_ENV or now is not None):
                return False
        return all(self.current(n) == h for n, h in rec.get("deps", {}).items())


FULL_TAG = " [full]"


def timing_key(tf: Path) -> str:
    """Quick and full runs of a file record their times apart: full sweeps run many more cases."""
    return display(tf) + (FULL_TAG if os.environ.get(FULL_ENV) else "")


def recorded_times(timings: dict, tf: Path) -> dict | None:
    """This mode's times, else the other mode's (better than none for planning)."""
    return timings.get(timing_key(tf)) or timings.get(display(tf)) or timings.get(display(tf) + FULL_TAG)


def estimate(jobs: list[tuple[Path, Path]], timings: dict, filter_text: str | None) -> float:
    """Recorded CPU seconds of the jobs (1 s for a file with no record)."""
    total = 0.0
    for _, tf in jobs:
        times = recorded_times(timings, tf) or {}
        if filter_text:
            times = {n: t for n, t in times.items() if filter_text in n}
        total += sum(times.values()) or 1.0
    return total


def plan(jobs: list[tuple[Path, Path]], timings: dict, workers: int, filter_text: str | None):
    """Returns [(mod, tf, only, known, estimate)], slow files split by recorded per-test times
    into shards no bigger than the slowest single test or half the even share per worker."""
    known = {}
    for _, tf in jobs:
        times = recorded_times(timings, tf)
        if times and filter_text:
            times = {n: t for n, t in times.items() if filter_text in n}
        known[display(tf)] = times or None
    totals = [sum(t.values()) for t in known.values() if t]
    singles = [max(t.values()) for t in known.values() if t]
    # half the even share: this Mac's cores differ in speed (6 fast + 12 slower) and the pool hands
    # out shards as workers free up, so smaller shards balance better than one per worker
    target = max(max(singles, default=0), sum(totals) / max(2 * workers, 1))
    out = []
    for mod, tf in jobs:
        times = known[display(tf)]
        total = sum(times.values()) if times else 0.0
        if not times or total <= target or workers <= 1 or NO_SPLIT in tf.read_text(encoding="utf-8-sig"):
            out.append((mod, tf, None, None, total or target))
            continue
        # 1.5x the minimum shard count leaves LPT room to keep the slowest test's shard alone
        bins: list[list] = [[0.0, []] for _ in range(min(workers, len(times), math.ceil(1.5 * total / target)))]
        for n, secs in sorted(times.items(), key=lambda kv: -kv[1]):
            b = min(bins, key=lambda b: b[0])
            b[0] += secs
            b[1].append(n)
        names = list(recorded_times(timings, tf))
        for i, (est, only) in enumerate(b for b in bins if b[1]):
            out.append((mod, tf, only, names if i == 0 else None, est))
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mods", nargs="*")
    parser.add_argument("-k", dest="filter", help="only tests whose name contains this text")
    parser.add_argument("-f", dest="files", action="append",
                        help="only test files whose name contains this text (repeatable)")
    parser.add_argument("-j", dest="jobs", type=int,
                        help="worker processes (default: sized to the recorded work, at most the CPU count; "
                             "1 = serial, no sharding)")
    parser.add_argument("--all", action="store_true", help="every mod that has tests (~30 mods; rarely needed)")
    parser.add_argument("--full", action="store_true",
                        help=f"full coverage: sets {FULL_ENV}=1, so sweeps that sample by default check every case")
    parser.add_argument("--no-cache", action="store_true", help="run every file, even those whose last pass still holds")
    args = parser.parse_args()

    if args.full or os.environ.get("SQRB_FULL"):
        os.environ[FULL_ENV] = "1"  # the exhaustive SQRB_FULL sweep includes full coverage; workers inherit it
    if args.mods:
        mods = [resolve_mod(m) for m in args.mods]
    elif args.all:
        mods = sorted(p.resolve() for p in MODS_DIR.iterdir() if (TESTS_DIR / p.name).is_dir())
    else:
        raise SystemExit("name the mod you work on: make test MOD=mods/<id> (run_tests.py <modId>); "
                         "--all runs every mod's tests, which one mod's work never needs (CLAUDE.md \"Tests\")")
    jobs = [(mod, tf) for mod in mods for tf in test_files(mod)
            if not args.files or any(f in tf.name for f in args.files)]
    for mod in mods:
        if not test_files(mod):
            print(f"[{mod.name}] no tests in {display(TESTS_DIR / mod.name)}")
    if not jobs:
        raise SystemExit(f"no test files match -f {args.files}")

    started = time.perf_counter()
    passed = failed = 0
    timings, results = load_json(TIMINGS), load_json(RESULTS)
    bases = {mod: base_stamp(mod) for mod in mods}
    inputs = InputCheck()
    cached: dict[Path, int] = {}  # test file -> tests passed (matching -k)
    run_jobs = []
    for mod, tf in jobs:
        rec = results.get(display(tf))
        matching = None if not rec or rec.get("names") is None else [
            n for n in rec["names"] if not args.filter or args.filter in n]
        if not args.no_cache and rec and rec.get("pass") and not rec.get("writes") \
                and inputs.same(rec, bases[mod], exact_env=False):
            if matching:
                cached[tf] = len(matching)
            continue
        if args.filter and matching == [] and inputs.same(rec, bases[mod], exact_env=True):
            continue  # -k: no test of this file matches, and its names can't have changed
        run_jobs.append((mod, tf))

    # each worker spends ~0.8 s starting Teal, so small runs get few workers
    workers = args.jobs or max(1, min(os.cpu_count() or 1, math.ceil(estimate(run_jobs, timings, args.filter) / 2.0)))
    planned = plan(run_jobs, timings, workers, args.filter)
    if workers <= 1 or len(planned) <= 1:
        outputs = {tf: [run_file(mod, tf, args.filter)] for mod, tf in run_jobs}
    else:
        with ProcessPoolExecutor(max_workers=min(workers, len(planned))) as pool:
            # slowest first, so the long shards don't start last
            futures = [(tf, pool.submit(run_file, mod, tf, args.filter, only, known))
                       for mod, tf, only, known, _ in sorted(planned, key=lambda p: -p[4])]
            outputs = {tf: [] for _, tf in run_jobs}
            for tf, fut in futures:
                outputs[tf].append(fut.result())

    timing_updates: dict[str, dict] = {}
    result_updates: dict[str, dict] = {}
    current = None
    for mod in mods:
        mod_cached = [tf for m, tf in jobs if m == mod and tf in cached]
        for m, tf in run_jobs:
            if m != mod:
                continue
            shards = outputs[tf]
            p, f, text = format_file(display(tf), shards)
            passed += p
            failed += f
            if not (args.filter and not p + f):  # -k: files with no matching test stay quiet
                if mod != current:
                    print(f"[{mod.name}]")
                    current = mod
                print(text, flush=True)
            broken = any(s.get("load_error") or s.get("compile_errors") for s in shards)
            if not broken:
                # a full run replaces the file's record (drops renamed tests); a -k run updates it
                rec = dict(timings.get(timing_key(tf), {})) if args.filter else {}
                for r in (r for s in shards for r in s["results"]):
                    rec[r["name"]] = round(r["secs"], 3)
                timing_updates[timing_key(tf)] = rec
            if shards[0].get("names") is not None:
                deps, env = {}, {}
                for s in shards:
                    deps.update(s["deps"])
                    env.update(s["env"])
                result_updates[display(tf)] = {
                    "base": bases[mod], "deps": deps, "env": env, "names": shards[0]["names"],
                    "writes": any(s["writes"] for s in shards), "passed": p,
                    "pass": not args.filter and not broken and f == 0 and p > 0}
        if mod_cached:
            if mod != current:
                print(f"[{mod.name}]")
                current = mod
            n = sum(cached[tf] for tf in mod_cached)
            passed += n
            print(f"  cached: {len(mod_cached)} files, {n} tests passed earlier and read nothing that changed since"
                  " (--no-cache runs them)")
    gone = {k for k in {*timings, *results} if not (ROOT / k.removesuffix(FULL_TAG)).exists()}  # deleted / renamed test files
    save_json(TIMINGS, timing_updates, gone)
    save_json(RESULTS, result_updates, gone)
    n_cached = sum(cached.values())
    print(f"{passed} passed{f' ({n_cached} cached)' if n_cached else ''}, {failed} failed"
          f" ({time.perf_counter() - started:.1f} s)")
    sys.exit(1 if failed or not passed else 0)


if __name__ == "__main__":
    main()
