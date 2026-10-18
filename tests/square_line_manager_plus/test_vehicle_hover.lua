-- Line Manager Plus vehicle list hover block (vehicle_hover.lua, through lmp_callout.lua) with fake react / builtin /
-- base modules and a fake api.
-- Covers: install (wraps builtin.ColumnDesc once, keeps the previous wrapper, shims ReplaceRecipe), the column swap
-- (only the VehicleIcon column; others untouched), the cell (the vanilla picture cell called in place with a ref
-- holder and meta.onMouseOver; a cell without commonParams or with extra arguments goes through untouched), the parts
-- lines (runs of equal models), the block text (a train: line, parts, speed / power / weight, age / condition, running
-- costs / value / last year; depot states; a failing value left out and logged once; a sold vehicle: no block), the
-- block (opened once beside the line list, top aligned with the row; unhover closes it) and the holder (expires once
-- the vehicle is gone).

local react, builtin, hover, world, prevCalls, RAPI_CALLS, baseRecipes, callouts, cellCalls

local function format(s, vars)
	return (s:gsub("{(%w+)}", function(k) return tostring(vars[k]) end))
end

local function setup(opts)
	opts = opts or {}
	reset_modules()
	clear_logs()
	prevCalls, RAPI_CALLS, cellCalls = {}, {}, {}
	callouts = { opened = {}, closed = {}, current = nil }
	world = {
		-- vehicle -> parts (model ids), state, line
		vehicles = {
			[50] = { parts = { 1, 2, 3, 3, 3 }, state = "EN_ROUTE", line = 7 },
			[51] = { parts = { 4 }, state = "IN_DEPOT", line = -1 },
			[52] = { parts = { 4 }, state = "GOING_TO_DEPOT", line = -1 },
		},
		names = { [50] = "R0006", [51] = "Bus 1", [52] = "Bus 2", [7] = "TP Line" },
		models = {
			[1] = { description = { name = "Big Boy" }, landVehicle = { topSpeed = 30, weightEmpty = 100000, engines = { { power = 2000 } } } },
			[2] = { description = { name = "Tender" }, landVehicle = { topSpeed = 40, weightEmpty = 50000, engines = {} } },
			[3] = { description = { name = "Boxcar" }, landVehicle = { topSpeed = 25, weightEmpty = 20000 } },
			[4] = { description = { name = "Bus A" }, landVehicle = { topSpeed = 20, weightEmpty = 8000, engines = { { power = 150 } } } },
		},
	}
	set_global("api", {
		type = {
			ComponentType = { TRANSPORT_VEHICLE = "TV", GAME_TIME = "GT" },
			enum = { TransportVehicleState = { IN_DEPOT = "IN_DEPOT", EN_ROUTE = "EN_ROUTE", AT_TERMINAL = "AT_TERMINAL",
				GOING_TO_DEPOT = "GOING_TO_DEPOT" } },
			Clock = { new = function() return { getTime = function() return 1e9 end } end },
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			Vec4f = { new = function(a, b, c, d) return { a, b, c, d } end },
		},
		gui = { StyleSheet = { new = function() return {} end } },
		engine = {
			entityExists = function(e) return world.vehicles[e] ~= nil or world.names[e] ~= nil end,
			getComponent = function(e, ct)
				if ct == "GT" then return { gameTime = 5000000 } end
				local v = world.vehicles[e]
				if ct == "TV" and v then
					local parts = {}
					for i, id in ipairs(v.parts) do
						parts[i] = { part = { modelId = id }, purchaseTime = 1000000 + i, maintenanceState = 0.8 }
					end
					return { state = v.state, line = v.line, transportVehicleConfig = { vehicles = parts } }
				end
			end,
			util = {
				getWorld = function() return 0 end,
				getEntityName = function(e) return world.names[e] end,
				formatAge = function(t0, t1) return string.format("age %d-%d", t0, t1) end,
				vehicle = {
					getRunningCost = function() return 45000.4 end,
					getDepreciatedValue = function()
						if world.failValue then error("value boom") end
						return 120000
					end,
				},
				finance = { calculateBalance = function(es, from, to, mi)
					world.balanceArgs = { es = es, from = from, to = to, mi = mi }
					return -1234
				end },
			},
		},
		res = { modelRep = { get = function(id) return { metadata = world.models[id] } end } },
		util = {
			toStringPercentPrecision = function(v) return tostring(math.floor(v * 100 + 0.5)) .. "%" end,
			formatSpeed = function(s) return string.format("%d km/h", math.floor(s * 3.6 + 0.5)) end,
			formatPower = function(p) return string.format("%d kW", p) end,
			formatWeight = function(w) return string.format("%d t", w) end,
			formatMoney = function(m) return "$" .. tostring(m) end,
			getDefaultYearDuration = function() return 2000000 end,
		},
	})
	local names = {}
	react = {
		RegisterRecipe = function(name, fn)
			local r = function(p) return { recipe = name, p = p } end
			names[r] = name
			return r
		end,
		GetRecipeName = function(fn) return names[fn] end,
		ref = function(r) return { is_react_ref_info = true, data = r } end,
	}
	builtin = {
		type = { Orientation = { Vertical = "V", Horizontal = "H" } },
		BoxLayout = function(p) return { kind = "BoxLayout", children = p.children } end,
		TextView = function(p) return { kind = "TextView", class = p.meta and p.meta.class, text = p.text } end,
		Component = function(p) return { kind = "Component", meta = p.meta, layout = p.layout } end,
		ColumnDesc = function(...)
			prevCalls[#prevCalls + 1] = table.pack(...)
			return { kind = "ColumnDesc", args = table.pack(...) }
		end,
	}
	baseRecipes = {}
	for _i, n in ipairs({ "VehicleIcon", "VehicleName" }) do
		local r = react.RegisterRecipe(n, function() return "cell" end)
		baseRecipes[n] = function(...)
			cellCalls[#cellCalls + 1] = table.pack(...)
			return r(...)
		end
		names[baseRecipes[n]] = n
	end
	stub_module("::/gui/main/react.lua", react)
	stub_module("::/gui/main/builtin.lua", builtin)
	stub_module("::/scripts/lang_util.tl", { format = format, formatInt = function(n) return tostring(n) end })
	stub_module("::/gui/line_vehicle_mgmt/vehicle_util.tl", { getConditionText = function(s)
		return s > 0.6 and "Good" or "Bad"
	end })
	stub_module("square_line_manager_plus::/line_manager_plus/lmp_stats.lua", { lines = function() return nil end })
	hover = ug_require "square_line_manager_plus::/line_manager_plus/vehicle_hover.lua"
end

local function rapi()
	return { ReplaceRecipe = function(orig, repl) RAPI_CALLS[#RAPI_CALLS + 1] = { orig = orig, repl = repl } end }
end

local function warnings(text)
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if e.level == "warning" and (text == nil or e.msg:find(text, 1, true)) then n = n + 1 end
	end
	return n
end

local function column(recipe)
	return { name = " ", recipe = recipe or baseRecipes.VehicleIcon, getCompareValue = function() end }
end

local function calloutRef()
	local capi = {
		open = function(params)
			callouts.opened[#callouts.opened + 1] = params
			callouts.current = params
		end,
		close = function(parent)
			callouts.closed[#callouts.closed + 1] = parent
			if callouts.current and callouts.current.parent == parent then callouts.current = nil end
		end,
	}
	return { get = function() return { getApi = function() return capi end } end }
end

local function node(box)
	return { getPosition = function(_n, gx, gy)
		if box.fail then error("node gone") end
		return { x = box.x + gx * box.w, y = box.y + gy * box.h }
	end }
end

local LIST = { x = 0.1, y = 0.2, w = 0.25, h = 0.3 }

local function commonParams()
	local listNode = node(LIST)
	return {
		lineAndDepotListRef = { get = function() return listNode end, hasExpired = function() return false end },
		gameCtx = { calloutContainerRef = calloutRef() },
	}
end

-- install, call the picture column's cell for `vehicle` and hand the holder its node
local function cell(vehicle, cp)
	hover.install(rapi())
	local fn = builtin.ColumnDesc(column()).args[1].recipe
	local c = { rowKey = vehicle, colKey = 4, userParam = { commonParams = cp } }
	local out = fn(c)
	local call = cellCalls[#cellCalls]
	local refInfo, param = call[1], call[2]
	ok(refInfo.is_react_ref_info == true)
	local holder = refInfo.data[1]
	holder:set(node({ x = 0.2, y = 0.6, w = 0.1, h = 0.02 }))
	return param.meta.onMouseOver, holder, param, c, out
end

local TRAIN = "R0006\nTP Line\nBig Boy\nTender\n3× Boxcar\n"
	.. "Top Speed: 90 km/h  ·  Power: 2000 kW  ·  Weight: 210 t\n"
	.. "Age: age 1000001-5000000  ·  Condition: Good (80%)\n"
	.. "Running Costs: $45000/year  ·  Value: $120000  ·  Last Year: $-1234"

-- install / column ---------------------------------------------------------------------------------------------------

test("install: wraps builtin.ColumnDesc once; a later ReplaceRecipe of our wrapper gets the wrapped one", function()
	setup()
	local before = builtin.ColumnDesc
	ok(hover.install(rapi()))
	local ours = builtin.ColumnDesc
	ok(ours ~= before)
	ok(hover.install(rapi()))
	ok(builtin.ColumnDesc == ours)
	local r = rapi()
	setup()
	before = builtin.ColumnDesc
	hover.install(r)
	r.ReplaceRecipe(builtin.ColumnDesc, "x")
	ok(RAPI_CALLS[1].orig == before)
end)

test("column: only the picture column gets our cell function, the same on every render", function()
	setup()
	hover.install(rapi())
	local name = column(baseRecipes.VehicleName)
	builtin.ColumnDesc(name)
	ok(prevCalls[1][1] == name)
	local a = builtin.ColumnDesc(column()).args[1]
	local b = builtin.ColumnDesc(column()).args[1]
	ok(a.recipe ~= baseRecipes.VehicleIcon)
	ok(a.recipe == b.recipe)
	eq(a.name, " ")
end)

test("cell: the vanilla picture cell called in place with a ref holder and meta.onMouseOver", function()
	setup()
	local onMouseOver, holder, param, c, out = cell(50, commonParams())
	eq(type(onMouseOver), "function")
	eq(param.rowKey, 50); eq(param.colKey, 4)
	ok(param.userParam == c.userParam)
	eq(c.meta, nil)
	eq(out.recipe, "VehicleIcon")
	eq(holder:hasExpired(), false)
	eq(#callouts.opened, 0) -- nothing built until hovered
end)

test("cell: no commonParams or extra arguments go through untouched", function()
	setup()
	hover.install(rapi())
	local fn = builtin.ColumnDesc(column()).args[1].recipe
	local c = { rowKey = 50, colKey = 4, userParam = {} }
	fn(c)
	ok(cellCalls[1][1] == c)
	fn(c, "extra")
	ok(cellCalls[2][1] == c); eq(cellCalls[2][2], "extra")
end)

-- text ---------------------------------------------------------------------------------------------------------------

test("parts: runs of equal models collapse to count× name; single parts stay plain", function()
	setup()
	eq(hover.partLines({ "A", "B", "B", "A" }), { "A", "2× B", "A" })
	eq(hover.partLines({}), {})
end)

test("text: a train's line, parts by run, slowest speed, summed power and weight, age, condition, money", function()
	setup()
	eq(hover.panelText(50), TRAIN)
	eq(world.balanceArgs.from, 3000000); eq(world.balanceArgs.to, 5000000); eq(world.balanceArgs.mi, true)
	eq(world.balanceArgs.es, { 50 })
end)

test("text: depot states; a failing value is left out and logged once; a sold vehicle has no block", function()
	setup()
	ok(hover.panelText(51):find("^Bus 1\nIn Depot\nBus A\n") ~= nil)
	ok(hover.panelText(52):find("^Bus 2\nGoing to Depot\n") ~= nil)
	world.failValue = true
	local t = hover.panelText(51)
	ok(t:find("Value", 1, true) == nil)
	ok(t:find("Running Costs: $45000/year  ·  Last Year: $-1234", 1, true) ~= nil)
	hover.panelText(51)
	eq(warnings("value boom"), 1)
	eq(hover.panelText(99), nil)
end)

-- block --------------------------------------------------------------------------------------------------------------

test("block: hovering opens it once beside the line list, top aligned with the row; unhover closes it", function()
	setup()
	local onMouseOver, holder = cell(50, commonParams())
	onMouseOver(true)
	onMouseOver(true)
	eq(#callouts.opened, 1)
	local c = callouts.opened[1]
	ok(c.parent == holder)
	eq(c.recipeParam.text, TRAIN)
	eq(c.recipeParam.onRight, true)
	local pos = c.getPositionFn()
	near(pos.x, LIST.x + LIST.w)
	near(pos.y, 0.6)
	onMouseOver(false)
	eq(#callouts.closed, 1)
	eq(callouts.current, nil)
	eq(warnings(), 0)
end)

test("holder: selling the hovered vehicle expires the block's parent", function()
	setup()
	local _o, holder = cell(50, commonParams())
	eq(holder:hasExpired(), false)
	world.vehicles[50] = nil
	world.names[50] = nil
	eq(holder:hasExpired(), true)
	world.vehicles[50] = { parts = { 4 }, state = "IN_DEPOT", line = -1 }
	eq(holder:hasExpired(), true) -- for good
end)
