# /// script
# requires-python = ">=3.11"
# dependencies = ["lupa"]
# ///
"""Mod stylesheet rule count: the game crashes on load once all active mods add more than ~205 rules
(docs/findings.md "Load crash above ~200 mod stylesheet rules"; every comma-separated selector part counts).

Runs each `*.css.lua` `data()` of the given mods in Lua 5.4 with a counting `stylesheetutil.makeAdder` and
everything else stubbed. The given mods form the active set: shared leader-marker blocks (the layer window
offset `square_ridge/marker.gres`, the tool info style `square_tool_info/marker.gres`) see only those mods'
markers, so each shared block counts once, as in game.

Usage: uv run tools/css_rules.py [MOD ...]   (mod ids or paths; looked up in mods/ and .cache/subscribed/;
default: every mod in mods/). `make css-rules MODS='a b c'`.
"""
import glob
import os
import sys

from lupa.lua54 import LuaRuntime

ROOTS = ["mods", ".cache/subscribed"]
LIMIT = 205

LUA = r'''
local path, active = ...
local count = 0
local function stub()
  return setmetatable({}, { __index = function() return stub() end, __call = function() return stub() end })
end
local MARKER = { square_ridge = "squareRidge", square_tool_info = "squareToolInfo" }
local found = {}
api = { gui = { genericRep = {
  find = function(p)
    local owner, dir = tostring(p):match("^([%w_]+)::/([%w_]+)/marker%.gres$")
    if owner and MARKER[dir] then
      if active[owner] then found[#found + 1] = MARKER[dir] return #found end
      return -1
    end
    return 0
  end,
  get = function(id)
    if type(id) == "number" and id > 0 and found[id] then return { data = { [found[id]] = true } } end
    return { data = stub() }
  end,
} }, type = stub() }
log = stub()
local ssu = { makeAdder = function(result) return function(sel)
  for part in tostring(sel):gmatch("[^,]+") do if part:match("%S") then count = count + 1 end end
  result[#result + 1] = sel
end end }
require = function(n) if tostring(n):find("stylesheetutil") then return ssu end return stub() end
local chunk, err = loadfile(path)
if not chunk then return -1, err end
local ok, perr = pcall(chunk)
if not ok then return -1, perr end
ok, perr = pcall(data)
if not ok then return count, perr end
return count, nil
'''


def resolve(arg):
    if os.path.isdir(arg):
        return os.path.basename(os.path.normpath(arg)), arg
    for r in ROOTS:
        d = os.path.join(r, arg)
        if os.path.isdir(d):
            return arg, d
    return arg, None


def main(argv):
    args = argv or sorted(os.path.basename(d) for d in glob.glob("mods/*") if os.path.isdir(d))
    mods = [resolve(a) for a in args]
    active_ids = {m: True for m, d in mods if d}
    total, warnings = 0, []
    for mod_id, d in mods:
        if d is None:
            print(f"{mod_id:45s} (not found)")
            continue
        n_mod = 0
        for f in sorted(glob.glob(d + "/**/*.css.lua", recursive=True)):
            lua = LuaRuntime()
            run = lua.execute("return function(...) " + LUA + " end")
            n, err = run(f, lua.table_from(active_ids))
            if err:
                warnings.append(f"{f}: {err}")
            n_mod += max(n, 0)
        if n_mod:
            print(f"{mod_id:45s} {n_mod:4d}")
        total += n_mod
    print(f"{'TOTAL':45s} {total:4d}  (crash above ~{LIMIT})")
    for w in warnings:
        print("warning:", w)
    return 1 if total > LIMIT else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
