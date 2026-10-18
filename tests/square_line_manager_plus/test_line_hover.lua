-- Line Manager Plus "Map: line info on hover" (line_hover.lua) with fake react / builtin / base modules and a fake api.
-- Covers: module exports, install (installs once, skips a missing or non-recipe SelectLine, survives a failing
-- ReplaceRecipe or require), the hover -> block path (the main mode's SelectLine params = LineSelectionDetails
-- { entity, stopNumber }: vanilla node first with untouched params, our text block with the vanilla tooltip classes,
-- BoxLayout root, no estimate), the 1 s stats cache, and the fallbacks (non-line entity, a vanilla nil for a gone
-- line, stats errors, vanilla error, logged once).

local react, builtin, tooltips, script, replaced, origCalls, world, failVanilla, nowUs, listCalls, vanillaNil
local VANILLA = { kind = "VanillaTooltip" }

local function format(s, vars)
	return (s:gsub("{(%w+)}", function(k) return tostring(vars[k]) end))
end

local function setup(opts)
	opts = opts or {}
	reset_modules()
	clear_logs()
	replaced, origCalls, failVanilla, nowUs, listCalls, vanillaNil = {}, {}, false, 1e9, 0, false
	world = { lines = { [1] = { 11, 12 } }, vehicles = { [11] = 100, [12] = 200 } }
	set_global("api", {
		type = {
			ComponentType = { LINE = "LINE", TRANSPORT_VEHICLE = "TV" },
			Clock = { new = function() return { getTime = function() return nowUs end } end },
		},
		engine = {
			entityExists = function(e) return world.lines[e] ~= nil end,
			getComponent = function(e, ct)
				if ct == "LINE" then return world.lines[e] and {} or nil end
				if ct == "TV" and world.vehicles[e] then
					return { transportVehicleConfig = { vehicles = { { part = { modelId = world.vehicles[e] } } } } }
				end
			end,
			system = { transportVehicleSystem = { getLineVehicles = function(line)
				if world.failList then error("list boom") end
				listCalls = listCalls + 1
				return world.lines[line]
			end } },
			util = { line = { calcLineStationThroughput = function() return 4321 end } },
		},
		res = { modelRep = { get = function(id)
			return { metadata = { description = { name = id == 100 and "Bus A" or "Bus B" } } }
		end } },
		util = {
			toStringPercentPrecision = function(v, d) eq(d, 0); return tostring(math.floor(v * 100)) .. "%" end,
			formatMinutesSeconds = function(s) return string.format("%d:%02d", s // 60, s % 60) end,
		},
	})

	local recipeIds = {}
	react = {
		-- a recipe call renders at once here: Recipe(params) = fn(params)
		RegisterRecipe = function(name, fn)
			local r = function(p) return fn(p) end
			recipeIds[r] = name
			return r
		end,
		GetRecipeId = function(fn) return recipeIds[fn] end,
		CallOriginalRecipe = function(recipe, params)
			origCalls[#origCalls + 1] = { recipe = recipe, params = params }
			if failVanilla then error("vanilla boom") end
			if vanillaNil then return nil end
			return VANILLA
		end,
	}
	builtin = {
		type = { Orientation = { Vertical = "V", Horizontal = "H" } },
		BoxLayout = function(p) return { kind = "BoxLayout", orientation = p.orientation, children = p.children } end,
		TextView = function(p) return { kind = "TextView", meta = p.meta, text = p.text } end,
	}
	tooltips = {}
	if opts.vanilla ~= false then
		tooltips.SelectLine = react.RegisterRecipe("SelectLine", function() error("must not run directly") end)
	end
	if opts.plainFunction then tooltips.SelectLine = function() end end
	stub_module("::/gui/main/react.lua", react)
	stub_module("::/gui/main/builtin.lua", builtin)
	-- stubs outlive reset_modules: nil makes ug_require fail like a missing base module
	stub_module("::/gui/line_vehicle_mgmt/manager_tooltips_util.tl", (not opts.noTooltipsModule) and tooltips or nil)
	stub_module("::/scripts/lang_util.tl", { format = format, formatInt = function(n) return tostring(n) end })
	if opts.noStatsModule then
		stub_module("::/gui/statistics/statistics_react_util.tl", nil)
	else
		stub_module("::/gui/statistics/statistics_react_util.tl", { calculateCargoColumnDataForLine = function()
			return { demand = 80, coverage = 0.25 }
		end })
	end
	stub_module("::/gui/line_vehicle_mgmt/line_util.tl", { calculateFrequencySeconds = function() return 90 end })

	script = ug_require "square_line_manager_plus::/line_manager_plus/line_hover.lua"
end

local replacementApi = {
	ReplaceRecipe = function(orig, repl) replaced[#replaced + 1] = { orig = orig, repl = repl } end,
}

local function countWarnings()
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if e.level == "warning" then n = n + 1 end
	end
	return n
end

test("exports install and the recipe; install replaces SelectLine once", function()
	setup()
	ok(type(script.install) == "function")
	ok(type(script.LineHoverInfo) == "function")
	script.install(replacementApi)
	eq(#replaced, 1)
	ok(replaced[1].orig == tooltips.SelectLine)
	ok(replaced[1].repl == script.LineHoverInfo)
	script.install(replacementApi)
	eq(#replaced, 1)
end)

test("install: a missing SelectLine replaces nothing and warns", function()
	setup({ vanilla = false })
	script.install(replacementApi)
	eq(#replaced, 0)
	eq(countWarnings(), 1)
end)

test("install: a plain function in SelectLine (not a recipe) replaces nothing", function()
	setup({ plainFunction = true })
	script.install(replacementApi)
	eq(#replaced, 0)
	eq(countWarnings(), 1)
end)

test("install: a failing ReplaceRecipe or a missing module is caught", function()
	setup()
	script.install({ ReplaceRecipe = function() error("replace boom") end })
	eq(countWarnings(), 1)
	setup({ noTooltipsModule = true })
	script.install(replacementApi)
	eq(#replaced, 0)
	eq(countWarnings(), 1)
end)

test("recipe: vanilla node first with untouched params, then our block in the tooltip classes", function()
	setup()
	script.install(replacementApi)
	local params = { entity = 1, stopNumber = 2 }
	local node = script.LineHoverInfo(params)
	eq(node.kind, "BoxLayout")
	eq(node.orientation, "V")
	eq(#node.children, 2)
	ok(node.children[1] == VANILLA)
	ok(origCalls[1].recipe == tooltips.SelectLine)
	ok(origCalls[1].params == params)
	eq(params, { entity = 1, stopNumber = 2 })
	local tv = node.children[2]
	eq(tv.kind, "TextView")
	eq(tv.meta.class, "lvm-selector-tooltip, font-scale-tooltip, default-tooltip-configuration, sq-lmp-stli")
	eq(tv.text, "Vehicles on this line: 2\n1× Bus A\n1× Bus B\n"
		.. "Capacity: 80  ·  Utilization: 25%  ·  Frequency: 1:30  ·  Rate: 4321")
	eq(countWarnings(), 0)
end)

test("recipe: a line without vehicles", function()
	setup()
	script.install(replacementApi)
	world.lines[1] = {}
	local node = script.LineHoverInfo({ entity = 1, stopNumber = 1 })
	eq(node.children[2].text, "No vehicles on this line.\nCapacity: 80  ·  Utilization: 25%  ·  Frequency: 1:30  ·  Rate: 4321")
end)

test("recipe: not a line (or bad params) shows the vanilla tooltip only, no warning", function()
	setup()
	script.install(replacementApi)
	for _i, p in ipairs({ { entity = 77, stopNumber = 1 }, {}, "x" }) do
		local node = script.LineHoverInfo(p)
		eq(node.kind, "BoxLayout")
		eq(#node.children, 1)
		ok(node.children[1] == VANILLA)
	end
	eq(countWarnings(), 0)
end)

test("recipe: stats errors keep the vanilla tooltip and log once", function()
	setup()
	script.install(replacementApi)
	world.failList = true
	for _i = 1, 5 do
		local node = script.LineHoverInfo({ entity = 1, stopNumber = 1 })
		eq(#node.children, 1)
		ok(node.children[1] == VANILLA)
	end
	eq(countWarnings(), 1)
end)

test("recipe: a missing base stats module costs the stats only", function()
	setup({ noStatsModule = true })
	script.install(replacementApi)
	for _i = 1, 3 do
		local node = script.LineHoverInfo({ entity = 1, stopNumber = 1 })
		eq(#node.children, 1)
		ok(node.children[1] == VANILLA)
	end
	-- one for the require, one for the first render
	eq(countWarnings(), 2)
end)

test("recipe: a failing vanilla recipe still returns a BoxLayout with our block", function()
	setup()
	script.install(replacementApi)
	failVanilla = true
	local node = script.LineHoverInfo({ entity = 1, stopNumber = 1 })
	eq(node.kind, "BoxLayout")
	eq(#node.children, 1)
	eq(node.children[1].kind, "TextView")
	script.LineHoverInfo({ entity = 1, stopNumber = 1 })
	eq(countWarnings(), 1)
end)

test("recipe: the main mode's hover of a line never shows the before -> after estimate", function()
	setup()
	script.install(replacementApi)
	local node = script.LineHoverInfo({ entity = 1, stopNumber = 1, apiStopIndex0 = 0 })
	ok(not node.children[2].text:find("→", 1, true))
	ok(not node.children[2].text:find("can't carry", 1, true))
end)

test("recipe: a line gone before the render (vanilla returns nil): an empty BoxLayout, no warning", function()
	setup()
	script.install(replacementApi)
	vanillaNil = true
	world.lines[1] = nil
	local node = script.LineHoverInfo({ entity = 1, stopNumber = 1 })
	eq(node.kind, "BoxLayout")
	eq(#node.children, 0)
	eq(countWarnings(), 0)
end)

test("recipe: hovering along a line re-renders from the 1 s cache; another line or after 1 s reads again", function()
	setup()
	script.install(replacementApi)
	world.lines[2] = { 12 }
	for stop = 1, 10 do script.LineHoverInfo({ entity = 1, stopNumber = stop }) end
	eq(listCalls, 1)
	local node = script.LineHoverInfo({ entity = 2, stopNumber = 1 })
	eq(listCalls, 2)
	eq(node.children[2].text, "Vehicles on this line: 1\n1× Bus B\n"
		.. "Capacity: 80  ·  Utilization: 25%  ·  Frequency: 1:30  ·  Rate: 4321")
	nowUs = nowUs + 999999
	script.LineHoverInfo({ entity = 1, stopNumber = 3 })
	eq(listCalls, 2)
	nowUs = nowUs + 2
	script.LineHoverInfo({ entity = 1, stopNumber = 3 })
	eq(listCalls, 3)
end)

test("recipe: before install the vanilla call fails safely (no original recipe): our block only, logged once", function()
	setup()
	failVanilla = true
	local node = script.LineHoverInfo({ entity = 1, stopNumber = 1 })
	eq(node.kind, "BoxLayout")
	eq(#node.children, 1)
	eq(node.children[1].kind, "TextView")
	eq(countWarnings(), 1)
end)
