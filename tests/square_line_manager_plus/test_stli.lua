-- Line Manager Plus Send to Line info feature (stli.lua) with fake react / builtin / base modules and a fake api.
-- Covers: module exports, install (installs once, skips a missing or non-recipe VMSendToLine, survives a failing
-- ReplaceRecipe or require), the recipe (vanilla node first, untouched params, our text block with the vanilla
-- tooltip classes, BoxLayout root), and the fallbacks (non-line entity, stats errors, vanilla error, logged once).

local react, builtin, tooltips, script, replaced, origCalls, world, failVanilla
local VANILLA = { kind = "VanillaTooltip" }

local function format(s, vars)
	return (s:gsub("{(%w+)}", function(k) return tostring(vars[k]) end))
end

local function setup(opts)
	opts = opts or {}
	reset_modules()
	clear_logs()
	replaced, origCalls, failVanilla = {}, {}, false
	world = { lines = { [1] = { 11, 12 } }, vehicles = { [11] = 100, [12] = 200 } }
	set_global("api", {
		type = {
			ComponentType = { LINE = "LINE", TRANSPORT_VEHICLE = "TV" },
			Clock = { new = function() return { getTime = function() return 1e9 end } end },
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
		tooltips.VMSendToLine = react.RegisterRecipe("VMSendToLine", function() error("must not run directly") end)
	end
	if opts.plainFunction then tooltips.VMSendToLine = function() end end
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

	script = ug_require "square_line_manager_plus::/line_manager_plus/stli.lua"
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

test("exports install and the recipe; install replaces VMSendToLine once", function()
	setup()
	ok(type(script.install) == "function")
	ok(type(script.SendToLineInfo) == "function")
	script.install(replacementApi)
	eq(#replaced, 1)
	ok(replaced[1].orig == tooltips.VMSendToLine)
	ok(replaced[1].repl == script.SendToLineInfo)
	script.install(replacementApi)
	eq(#replaced, 1)
end)

test("install: a missing VMSendToLine replaces nothing and warns", function()
	setup({ vanilla = false })
	script.install(replacementApi)
	eq(#replaced, 0)
	eq(countWarnings(), 1)
end)

test("install: a plain function in VMSendToLine (not a recipe) replaces nothing", function()
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
	local params = { numVehicles = 3, lineOrDepotEntity = 1 }
	local node = script.SendToLineInfo(params)
	eq(node.kind, "BoxLayout")
	eq(node.orientation, "V")
	eq(#node.children, 2)
	ok(node.children[1] == VANILLA)
	ok(origCalls[1].recipe == tooltips.VMSendToLine)
	ok(origCalls[1].params == params)
	eq(params, { numVehicles = 3, lineOrDepotEntity = 1 })
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
	local node = script.SendToLineInfo({ numVehicles = 1, lineOrDepotEntity = 1 })
	eq(node.children[2].text, "No vehicles on this line.\nCapacity: 80  ·  Utilization: 25%  ·  Frequency: 1:30  ·  Rate: 4321")
end)

test("recipe: not a line (or bad params) shows the vanilla tooltip only, no warning", function()
	setup()
	script.install(replacementApi)
	for _i, p in ipairs({ { numVehicles = 1, lineOrDepotEntity = 77 }, {}, "x" }) do
		local node = script.SendToLineInfo(p)
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
		local node = script.SendToLineInfo({ numVehicles = 1, lineOrDepotEntity = 1 })
		eq(#node.children, 1)
		ok(node.children[1] == VANILLA)
	end
	eq(countWarnings(), 1)
end)

test("recipe: a missing base stats module costs the stats only", function()
	setup({ noStatsModule = true })
	script.install(replacementApi)
	for _i = 1, 3 do
		local node = script.SendToLineInfo({ numVehicles = 1, lineOrDepotEntity = 1 })
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
	local node = script.SendToLineInfo({ numVehicles = 1, lineOrDepotEntity = 1 })
	eq(node.kind, "BoxLayout")
	eq(#node.children, 1)
	eq(node.children[1].kind, "TextView")
	script.SendToLineInfo({ numVehicles = 1, lineOrDepotEntity = 1 })
	eq(countWarnings(), 1)
end)
