# /// script
# requires-python = ">=3.11"
# dependencies = ["lupa"]
# ///
"""Run offline unit tests for mod scripts (Lua 5.4 + the game's Teal compiler).

Usage:
  uv run tests/run_tests.py [-k TEXT] [-f FILE] [-j N] [MOD ...]

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
-k runs only tests whose name contains TEXT (plain substring of the test name, not the
file name: `-k short` also hits "... short edges" tests elsewhere); files with no match
are not listed, but every file still loads. -f TEXT keeps only test files whose name
contains TEXT (repeatable; e.g. `-f through -f ramps`), so the others never load.
-j N runs N worker processes (default: CPU count; -j 1 runs everything in order in one
process). Output is printed per file in name order with the time of each test >= 1 s;
`print` inside a test is captured and shown under that test. Exit code 1 on any failure.

Sharding: each run records per-test CPU seconds in .cache/test_timings.json. Later runs
split a slow file into shards (each a process that loads the file and runs a subset of
its tests; tests not in the record run in the first shard), slowest first, so one long
file no longer sets the wall time. Tests must not depend on state left by an earlier
test in the same file; a file that does puts the text "run_tests: no-split" in it.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TESTS_DIR.parent / "tools"))
from hubconfig import CACHE_DIR, MODS_DIR, ROOT  # noqa: E402
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

    def run_file(self, tf: Path, filter_text: str | None, only: list[str] | None = None,
                 known: list[str] | None = None) -> dict:
        """Runs one test file (or the shard picked by only/known); returns plain data for the parent."""
        name = display(tf)
        started = time.perf_counter()
        src = tf.read_text(encoding="utf-8-sig")
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
                "results": results, "took": time.perf_counter() - started}


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


def load_timings() -> dict[str, dict[str, float]]:
    try:
        return json.loads(TIMINGS.read_text())
    except (OSError, ValueError):
        return {}


def plan(jobs: list[tuple[Path, Path]], timings: dict, workers: int, filter_text: str | None):
    """Returns [(mod, tf, only, known, estimate)], slow files split by recorded per-test times
    into shards no bigger than the slowest single test or half the even share per worker."""
    known = {}
    for _, tf in jobs:
        times = timings.get(display(tf))
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
        names = list(timings[display(tf)])
        for i, (est, only) in enumerate(b for b in bins if b[1]):
            out.append((mod, tf, only, names if i == 0 else None, est))
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mods", nargs="*")
    parser.add_argument("-k", dest="filter", help="only tests whose name contains this text")
    parser.add_argument("-f", dest="files", action="append",
                        help="only test files whose name contains this text (repeatable)")
    parser.add_argument("-j", dest="jobs", type=int, default=os.cpu_count() or 1,
                        help="worker processes (default: CPU count; 1 = serial, no sharding)")
    args = parser.parse_args()

    if args.mods:
        mods = [resolve_mod(m) for m in args.mods]
    else:
        mods = sorted(p.resolve() for p in MODS_DIR.iterdir() if (TESTS_DIR / p.name).is_dir())
    jobs = [(mod, tf) for mod in mods for tf in test_files(mod)
            if not args.files or any(f in tf.name for f in args.files)]
    for mod in mods:
        if not test_files(mod):
            print(f"[{mod.name}] no tests in {display(TESTS_DIR / mod.name)}")
    if not jobs:
        raise SystemExit(f"no test files match -f {args.files}")

    started = time.perf_counter()
    passed = failed = 0
    timings = load_timings()
    planned = plan(jobs, timings, args.jobs, args.filter)
    if args.jobs <= 1 or len(planned) <= 1:
        outputs = {tf: [run_file(mod, tf, args.filter)] for mod, tf in jobs}
    else:
        with ProcessPoolExecutor(max_workers=min(args.jobs, len(planned))) as pool:
            # slowest first, so the long shards don't start last
            futures = [(tf, pool.submit(run_file, mod, tf, args.filter, only, known))
                       for mod, tf, only, known, _ in sorted(planned, key=lambda p: -p[4])]
            outputs = {tf: [] for _, tf in jobs}
            for tf, fut in futures:
                outputs[tf].append(fut.result())

    current = None
    for mod, tf in jobs:
        shards = outputs[tf]
        p, f, text = format_file(display(tf), shards)
        passed += p
        failed += f
        if args.filter and not p + f:
            continue  # -k: files with no matching test stay quiet
        if mod != current:
            print(f"[{mod.name}]")
            current = mod
        print(text, flush=True)
        if not any(s.get("load_error") or s.get("compile_errors") for s in shards):
            # a full run replaces the file's record (drops renamed tests); a -k run updates it
            rec = timings.setdefault(display(tf), {}) if args.filter else timings.__setitem__(display(tf), {}) or timings[display(tf)]
            for r in (r for s in shards for r in s["results"]):
                rec[r["name"]] = round(r["secs"], 3)
    for key in [k for k in timings if not (ROOT / k).exists()]:
        del timings[key]  # deleted / renamed test files (e.g. a temporary test_zz_debug.lua)
    try:
        TIMINGS.parent.mkdir(parents=True, exist_ok=True)
        TIMINGS.write_text(json.dumps(timings, indent=0, sort_keys=True))
    except OSError:
        pass
    print(f"{passed} passed, {failed} failed ({time.perf_counter() - started:.1f} s)")
    sys.exit(1 if failed or not passed else 0)


if __name__ == "__main__":
    main()
