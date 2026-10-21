-- Line Manager Plus: the Balance tooltip with the last year, 2 and 5 years (lmp_balance.lua), with fake react /
-- builtin / engine_react_util / line_react_util modules and a fake engine (game time, a per-line balance per year,
-- the wall clock).
-- Covers: install (wraps LineBalance once, shims ReplaceRecipe, a missing field installs nothing), the wrapper (a
-- plain params call renders our recipe, a call with meta or a ref goes to the base unchanged), the body (the base
-- recipe with the same params plus meta.tooltip, none while there is no text), the texts (three windows; clamped to
-- the game start and the identical longer windows left out), the cache (2 and 5 years recomputed at most once per
-- quarter month; the time going back), the per-second budget, the cache cap, and errors (no tooltip, logged once).

local react, builtin, eru, lru, bal, world, recipes, baseCalls

local YEAR = 4800 -- the fake default year (game ms); a quarter month = 100

local function setup(opts)
	opts = opts or {}
	reset_modules()
	clear_logs()
	world = {
		gameTime = opts.gameTime or 10 * YEAR,
		us = 0,
		rate = {}, -- [line] = balance per year
		broken = {},
		calls = 0,
	}
	set_global("api", {
		type = {
			ComponentType = { GAME_TIME = "time" },
			Clock = { new = function() return { getTime = function() return world.us end } end },
		},
		engine = {
			getComponent = function(_w, t)
				if t == "time" then return { gameTime = world.gameTime } end
			end,
			util = {
				getWorld = function() return 1 end,
				finance = { calculateBalance = function(entities, from, to, flag)
					assert(flag == true)
					assert(#entities == 1)
					local line = entities[1]
					world.calls = world.calls + 1
					if world.broken[line] then error("bad line " .. line) end
					return math.floor((to - from) / YEAR * (world.rate[line] or 0) + 0.5)
				end },
			},
		},
		util = {
			getDefaultYearDuration = function() return YEAR end,
			formatMoney = function(v) return "$" .. v end,
		},
	})
	recipes = {}
	react = { RegisterRecipe = function(name, fn)
		local r = function(p) return { kind = "Recipe", name = name, params = p, render = function() return fn(p) end } end
		recipes[name] = r
		return r
	end }
	builtin = {
		type = { Orientation = { Horizontal = "H", Vertical = "V" } },
		BoxLayout = function(p) return { kind = "BoxLayout", orientation = p.orientation, children = p.children } end,
	}
	eru = { useStepStateTimer = function(getter, interval)
		eq(interval, 1.0)
		local v = getter()
		return { old = function() return v end }
	end }
	baseCalls = 0
	lru = { LineBalance = function(...)
		baseCalls = baseCalls + 1
		return { kind = "LineBalance", args = table.pack(...) }
	end }
	stub_module("::/gui/main/react.lua", react)
	stub_module("::/gui/main/builtin.lua", builtin)
	stub_module("::/gui/main/engine_react_util.tl", eru)
	stub_module("::/gui/line_vehicle_mgmt/line_react_util.tl", lru)
	bal = ug_require "square_line_manager_plus::/line_manager_plus/lmp_balance.lua"
	if opts.install ~= false then ok(bal.install({})) end
end

local function warnings(text)
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if e.level == "warning" and (text == nil or e.msg:find(text, 1, true)) then n = n + 1 end
	end
	return n
end

-- the base node and the tooltip a caller's LineBalance{ entity, stepTimer } call renders
local function render(line, stepTimer)
	local node = lru.LineBalance{ entity = line, stepTimer = stepTimer }
	eq(node.kind, "Recipe")
	local out = node.render()
	eq(out.kind, "BoxLayout")
	eq(#out.children, 1)
	local base = out.children[1]
	eq(base.kind, "LineBalance")
	local p = base.args[1]
	return p.meta and p.meta.tooltip, p
end

-- install ------------------------------------------------------------------------------------------------------------

test("install: wraps LineBalance once and shims ReplaceRecipe", function()
	setup({ install = false })
	local base = lru.LineBalance
	local calls = {}
	local rapi = { ReplaceRecipe = function(orig, repl) calls[#calls + 1] = { orig = orig, repl = repl } end }
	ok(bal.install(rapi))
	ok(bal.install(rapi))
	ok(lru.LineBalance ~= base)
	ok(recipes.SquareLmpLineBalance ~= nil)
	rapi.ReplaceRecipe(lru.LineBalance, "x")
	ok(calls[1].orig == base)
	eq(warnings(), 0)
end)

test("install: a missing field installs nothing, logged once", function()
	setup({ install = false })
	lru.LineBalance = nil
	ok(not bal.install({}))
	ok(not bal.install({}))
	eq(lru.LineBalance, nil)
	eq(warnings("balance: install"), 1)
end)

test("wrapper: a call with meta or a ref goes to the base unchanged", function()
	setup()
	local p = { entity = 11, stepTimer = true, meta = { class = "x" } }
	local node = lru.LineBalance(p)
	eq(node.kind, "LineBalance")
	ok(node.args[1] == p)
	local ref = {}
	node = lru.LineBalance(ref, { entity = 11 })
	eq(node.kind, "LineBalance")
	ok(node.args[1] == ref)
	node = lru.LineBalance({ stepTimer = true }) -- no entity
	eq(node.kind, "LineBalance")
end)

-- body and texts -----------------------------------------------------------------------------------------------------

test("body: the base recipe with the same params and the tooltip; ten years in", function()
	setup()
	world.rate[11] = 1200
	local tip, p = render(11, true)
	eq(p.entity, 11)
	eq(p.stepTimer, true)
	eq(tip, "Last year: $1200\nLast 2 years: $2400\nLast 5 years: $6000")
	local _tip, p2 = render(11, false)
	eq(p2.stepTimer, false)
	eq(baseCalls, 2)
end)

test("texts: windows before the game start are clamped, the identical longer ones left out", function()
	setup({ gameTime = YEAR * 3 / 2 })
	world.rate[11] = 100
	eq((render(11)), "Last year: $100\nLast 2 years: $150 (since the game started)")
	setup({ gameTime = YEAR / 2 })
	world.rate[11] = -100
	eq((render(11)), "Last year: $-50 (since the game started)")
	setup({ gameTime = 2 * YEAR }) -- exactly two years: not clamped
	world.rate[11] = 10
	eq((render(11)), "Last year: $10\nLast 2 years: $20\nLast 5 years: $20 (since the game started)")
	for line in (render(11)):gmatch("[^\n]+") do ok(#line <= 70) end
end)

test("errors: a failing balance gives no tooltip, logged once; the base still renders", function()
	setup()
	world.broken[11] = true
	local tip, p = render(11, true)
	eq(tip, nil)
	eq(p.meta, nil)
	render(11, true)
	eq(warnings("balance: tooltip"), 1)
	api.engine.getComponent = function() return nil end -- no game time
	world.broken[11] = nil
	eq((render(11)), nil)
end)

-- cache and budget ---------------------------------------------------------------------------------------------------

test("cache: 2 and 5 years recomputed at most once per quarter month; the last year every time", function()
	setup()
	world.rate[11] = 480
	eq(bal.tooltip(11), "Last year: $480\nLast 2 years: $960\nLast 5 years: $2400")
	eq(world.calls, 3)
	bal.tooltip(11)
	eq(world.calls, 4)
	world.gameTime = world.gameTime + YEAR / 48 - 1
	world.rate[11] = 960
	eq(bal.tooltip(11), "Last year: $960\nLast 2 years: $960\nLast 5 years: $2400") -- cached until the quarter month
	eq(world.calls, 5)
	world.gameTime = world.gameTime + 1
	eq(bal.tooltip(11), "Last year: $960\nLast 2 years: $1920\nLast 5 years: $4800")
	eq(world.calls, 8)
	world.gameTime = world.gameTime - 1 -- time went back: recomputed
	bal.tooltip(11)
	eq(world.calls, 11)
end)

test("budget: at most BUDGET lines recomputed per wall second; the rest show the last year until then", function()
	setup()
	local n = bal.BUDGET + 10
	for line = 1, n do world.rate[line] = 48 end
	local full = 0
	for line = 1, n do
		if bal.tooltip(line):find("5 years", 1, true) then full = full + 1 end
	end
	eq(full, bal.BUDGET)
	eq(bal.tooltip(n), "Last year: $48")
	world.us = world.us + 1e6
	full = 0
	for line = 1, n do
		if bal.tooltip(line):find("5 years", 1, true) then full = full + 1 end
	end
	eq(full, n)
end)

test("cache: bounded by MAX_CACHE lines", function()
	setup()
	bal.MAX_CACHE = 5
	bal.BUDGET = 1000
	for line = 1, 12 do bal.tooltip(line) end
	world.calls = 0
	bal.tooltip(12) -- still cached after the restart at the 6th and 11th line
	eq(world.calls, 1)
	bal.tooltip(1) -- dropped at a restart: recomputed
	eq(world.calls, 4)
	bal.MAX_CACHE, bal.BUDGET = 5000, 40
end)
