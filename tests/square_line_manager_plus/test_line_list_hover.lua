-- Line Manager Plus line list hover block (line_list_hover.lua, through lmp_callout.lua) with fake react / builtin /
-- base modules and a fake api.
-- Covers: install (wraps builtin.ColumnDesc once, keeps the previous wrapper in the chain, skips a missing field or a
-- missing react.GetRecipeName, shims ReplaceRecipe), the column swap (only the LineAndDepotListEntry column: other
-- recipes, a ref argument, malformed params pass through untouched; every other field kept; the same cell function
-- on every render; an error passes through and is logged once; a failing ColumnDesc with our copy falls back to the
-- caller's param), the cell function (the vanilla row recipe called in place with a ref holder and meta.onMouseOver,
-- the row's params otherwise the same; a cell without commonParams, with its own meta or with extra arguments goes
-- through untouched; nothing built until hovered), and the block (opened once per hovered row with the line's name,
-- vehicles and stats and no estimate; right of the line list, top aligned with the row, left of it when the window is
-- in the right half; closed on unhover of that row only; moving rows in either event order; a depot/deleted line or
-- a stats error opens nothing; a missing callout overlay is logged once; the position keeps its last value when the
-- row can't be read; without the list ref the row's own edges).

local react, builtin, hover, recipeFns, world, prevCalls, RAPI_CALLS, baseRecipes, callouts, rowCalls

local function format(s, vars)
	return (s:gsub("{(%w+)}", function(k) return tostring(vars[k]) end))
end

local function setup(opts)
	opts = opts or {}
	reset_modules()
	clear_logs()
	recipeFns, prevCalls, RAPI_CALLS, rowCalls = {}, {}, {}, {}
	callouts = { opened = {}, closed = {}, current = nil }
	world = {
		lines = { [1] = { 11, 12 }, [2] = { 21 } },
		vehicles = { [11] = 100, [12] = 200, [21] = 100 },
		vehicleLine = { [11] = 1, [12] = 1, [21] = 2 },
		names = { [1] = "Bus Line 1", [2] = "Bus Line 2" },
	}
	set_global("api", {
		type = {
			ComponentType = { LINE = "LINE", TRANSPORT_VEHICLE = "TV" },
			Clock = { new = function() return { getTime = function() return 1e9 end } end },
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			Vec4f = { new = function(a, b, c, d) return { a, b, c, d } end },
		},
		gui = { StyleSheet = { new = function() return {} end } },
		engine = {
			entityExists = function(e) return world.lines[e] ~= nil end,
			getComponent = function(e, ct)
				if ct == "LINE" then return world.lines[e] and {} or nil end
				if ct == "TV" and world.vehicles[e] then
					return {
						line = world.vehicleLine[e],
						config = { capacities = { 40 }, allCaps = { 40 } },
						transportVehicleConfig = { vehicles = { { part = { modelId = world.vehicles[e] } } } },
					}
				end
			end,
			system = { transportVehicleSystem = { getLineVehicles = function(line)
				world.listCalls = (world.listCalls or 0) + 1
				if world.failList then error("list boom") end
				return world.lines[line]
			end } },
			util = {
				getEntityName = function(e) return world.names[e] end,
				line = {
					calcLineStationThroughput = function() return 4321 end,
					getLineCapacityUsages = function() return { [1] = { capacity = 80 } } end,
				},
			},
		},
		res = { modelRep = { get = function(id)
			return { metadata = { description = { name = id == 100 and "Bus A" or "Bus B" } } }
		end } },
		util = {
			toStringPercentPrecision = function(v) return tostring(math.floor(v * 100)) .. "%" end,
			formatMinutesSeconds = function(s) return string.format("%d:%02d", s // 60, s % 60) end,
		},
	})
	local names = {}
	react = {
		RegisterRecipe = function(name, fn)
			recipeFns[name] = fn
			local r = function(p) return { recipe = name, p = p } end
			names[r] = name
			return r
		end,
		GetRecipeName = function(fn) return names[fn] end,
		ref = function(r) return { is_react_ref_info = true, data = r } end,
	}
	builtin = {
		type = { Orientation = { Vertical = "V", Horizontal = "H" } },
		BoxLayout = function(p) return { kind = "BoxLayout", orientation = p.orientation, children = p.children } end,
		TextView = function(p) return { kind = "TextView", class = p.meta and p.meta.class, text = p.text } end,
		Component = function(p) return { kind = "Component", meta = p.meta, layout = p.layout } end,
	}
	if opts.noField ~= true then
		builtin.ColumnDesc = function(...)
			prevCalls[#prevCalls + 1] = table.pack(...)
			if opts.failColumn and type((...)) == "table" and (...).recipe ~= baseRecipes.LineAndDepotListEntry then
				error("column boom")
			end
			return { kind = "ColumnDesc", args = table.pack(...) }
		end
	end
	-- the vanilla row recipe and another table's: calls are recorded, as the cell would make the node
	baseRecipes = {}
	for _i, n in ipairs({ "LineAndDepotListEntry", "VehicleRow" }) do
		local r = react.RegisterRecipe(n, function() return "row" end)
		baseRecipes[n] = function(...)
			rowCalls[#rowCalls + 1] = table.pack(...)
			return r(...)
		end
		names[baseRecipes[n]] = n
	end
	stub_module("::/gui/main/react.lua", react)
	stub_module("::/gui/main/builtin.lua", builtin)
	stub_module("::/scripts/lang_util.tl", { format = format, formatInt = function(n) return tostring(n) end })
	stub_module("::/gui/statistics/statistics_react_util.tl", { calculateCargoColumnDataForLine = function()
		return { demand = 80, coverage = 0.25 }
	end })
	stub_module("::/gui/line_vehicle_mgmt/line_util.tl", { calculateFrequencySeconds = function() return 90 end })
	hover = ug_require "square_line_manager_plus::/line_manager_plus/line_list_hover.lua"
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

local function messages(text)
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if e.level == "message" and e.msg:find(text, 1, true) then n = n + 1 end
	end
	return n
end

-- the line list's column param (manager_window.tl:2722-2736 shape)
local function column(recipe)
	return { name = "Name", recipe = recipe or baseRecipes.LineAndDepotListEntry, getCompareValue = function() end,
		weight = 1.0 }
end

-- the game's callout overlay, as callout_container.tl: one callout; close(parent) only closes the parent's own
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

-- a fake node: getPosition(gx, gy) over a box { x, y, w, h } in screen fractions
local function node(box)
	return { getPosition = function(_n, gx, gy)
		if box.fail then error("node gone") end
		return { x = box.x + gx * box.w, y = box.y + gy * box.h }
	end }
end

local LIST = { x = 0.1, y = 0.2, w = 0.25, h = 0.3 }

-- commonParams of the manager (with the overlay unless noCallouts)
local function commonParams(noCallouts, listBox)
	local listNode = node(listBox or LIST)
	local cp = { lineAndDepotListRef = { get = function() return listNode end, hasExpired = function() return false end } }
	if not noCallouts then cp.gameCtx = { calloutContainerRef = calloutRef() } end
	return cp
end

-- install, take the cell function of the list's column, call it for row `line` as builtin.DataTableCell does and
-- let react hand the holder the row node. Returns the meta's onMouseOver and the holder.
local function row(line, cp, rowBox)
	hover.install(rapi())
	local col = builtin.ColumnDesc(column())
	local fn = col.args[1].recipe
	local cell = { rowKey = line, colKey = 1, userParam = { commonParams = cp, lineAndDepotListApi = {} } }
	local out = fn(cell)
	local call = rowCalls[#rowCalls]
	local refInfo, param = call[1], call[2]
	ok(refInfo.is_react_ref_info == true)
	-- as react.lua:355-360 does: a table ref is a LIST of refs, each one gets :set(node)
	local refs = refInfo.data
	eq(type(refs), "table"); eq(#refs, 1)
	local rowNode = node(rowBox or { x = 0.11, y = 0.25 + 0.02 * line, w = 0.2, h = 0.02 })
	for _i, v in ipairs(refs) do v:set(rowNode) end
	local holder = refs[1]
	return param.meta.onMouseOver, holder, param, cell, out
end

local STATS = "Vehicles on this line: 2\n1× Bus A\n1× Bus B\n"
	.. "Capacity: 80  ·  Utilization: 25%  ·  Frequency: 1:30  ·  Rate: 4321"

-- install ------------------------------------------------------------------------------------------------------------

test("install: wraps builtin.ColumnDesc once and logs installed", function()
	setup()
	local orig = builtin.ColumnDesc
	ok(hover.install(rapi()))
	ok(builtin.ColumnDesc ~= orig)
	local w = builtin.ColumnDesc
	ok(hover.install(rapi()))
	ok(builtin.ColumnDesc == w)
	eq(messages("[LineManagerPlus] list hover: installed"), 1)
	eq(warnings(), 0)
end)

test("install: a missing ColumnDesc or react.GetRecipeName installs nothing and warns once", function()
	setup({ noField = true })
	eq(hover.install(rapi()), false)
	eq(builtin.ColumnDesc, nil)
	eq(warnings("[LineManagerPlus] list hover: install"), 1)
	setup()
	local orig = builtin.ColumnDesc
	react.GetRecipeName = nil
	eq(hover.install(rapi()), false)
	ok(builtin.ColumnDesc == orig)
	eq(warnings("install"), 1)
end)

test("install: keeps the previous wrapper in the chain; a later ReplaceRecipe of our wrapper gets the wrapped one", function()
	setup()
	local prev, chained = builtin.ColumnDesc, 0
	builtin.ColumnDesc = function(...) chained = chained + 1; return prev(...) end
	local before = builtin.ColumnDesc
	local api_ = rapi()
	hover.install(api_)
	builtin.ColumnDesc(column())
	eq(chained, 1)
	eq(#prevCalls, 1)
	local other = function() end
	api_.ReplaceRecipe(builtin.ColumnDesc, "R1")
	api_.ReplaceRecipe(other, "R2")
	ok(RAPI_CALLS[1].orig == before)
	ok(RAPI_CALLS[2].orig == other)
	setup()
	ok(hover.install(nil)) -- no replacement api: still installs
end)

-- column swap --------------------------------------------------------------------------------------------------------

test("column: other tables, a ref argument and malformed params go to the previous function untouched", function()
	setup()
	hover.install(rapi())
	local noFn = column()
	noFn.recipe = "notafunction"
	local cases = { { column(baseRecipes.VehicleRow) }, { noFn }, { "ref", column() }, { "x" }, { {} } }
	for i, args in ipairs(cases) do
		local n = builtin.ColumnDesc(table.unpack(args))
		eq(n.args.n, #args, "case " .. i)
		for j = 1, #args do ok(n.args[j] == args[j], "case " .. i) end
	end
	eq(warnings(), 0)
end)

test("column: the line list's column gets our cell function, the same on every render; other fields kept", function()
	setup()
	hover.install(rapi())
	local p = column()
	local q = builtin.ColumnDesc(p).args[1]
	ok(q ~= p)
	ok(type(q.recipe) == "function" and q.recipe ~= p.recipe)
	eq(q.name, "Name"); eq(q.weight, 1.0)
	ok(q.getCompareValue == p.getCompareValue)
	ok(p.recipe == baseRecipes.LineAndDepotListEntry) -- the caller's table unchanged
	local q2 = builtin.ColumnDesc(column()).args[1]
	ok(q2.recipe == q.recipe) -- stable: the table never sees a new column recipe
	eq(#prevCalls, 2)
end)

test("column: an error while deciding passes through and warns once; a failing ColumnDesc falls back", function()
	setup()
	hover.install(rapi())
	react.GetRecipeName = function() error("no names") end
	for _i = 1, 3 do
		local p = column()
		ok(builtin.ColumnDesc(p).args[1] == p)
	end
	eq(warnings("[LineManagerPlus] list hover: column"), 1)
	setup({ failColumn = true })
	hover.install(rapi())
	local p = column()
	ok(builtin.ColumnDesc(p).args[1] == p) -- our copy failed: the caller's param, unchanged
	eq(#prevCalls, 2)
	eq(warnings("[LineManagerPlus] list hover: column"), 1)
end)

-- cell function ------------------------------------------------------------------------------------------------------

test("cell: the vanilla row called in place with a ref holder and meta.onMouseOver; its params otherwise the same", function()
	setup()
	local cp = commonParams()
	local onMouseOver, holder, param, cell, out = row(1, cp)
	eq(#rowCalls, 1)
	eq(type(onMouseOver), "function")
	eq(param.rowKey, 1); eq(param.colKey, 1)
	ok(param.userParam == cell.userParam)
	eq(cell.meta, nil) -- the caller's cell unchanged
	eq(out.recipe, "LineAndDepotListEntry") -- the vanilla node itself, no wrapper node
	ok(holder:get() ~= nil)
	eq(holder:hasExpired(), false)
	eq(#callouts.opened, 0)
	eq(world.listCalls, nil) -- nothing built until hovered
end)

test("cell: a userdata cell (the game's DataTable, in game 2026-10-11) is decorated like a table one", function()
	setup()
	hover.install(rapi())
	local fn = builtin.ColumnDesc(column()).args[1].recipe
	local up = { commonParams = commonParams(), lineAndDepotListApi = {} }
	-- stands in for the C++ TableCellParam: fields readable by index, no pairs(), type() says userdata
	local cell = setmetatable({}, { __index = { rowKey = 3, colKey = 1, userParam = up },
		__pairs = function() error("pairs on userdata") end })
	local realType = type
	_G.type = function(v) if v == cell then return "userdata" end return realType(v) end
	local okCall, err = pcall(fn, cell)
	_G.type = realType
	ok(okCall, tostring(err))
	local call = rowCalls[#rowCalls]
	eq(call.n, 2)
	ok(call[1].is_react_ref_info == true)
	eq(call[2].rowKey, 3); eq(call[2].colKey, 1)
	ok(call[2].userParam == up)
	eq(type(call[2].meta.onMouseOver), "function")
	eq(warnings("[LineManagerPlus] list hover: row"), 0)
end)

test("cell: no commonParams, own meta, extra arguments or a broken cell go through untouched", function()
	setup()
	hover.install(rapi())
	local fn = builtin.ColumnDesc(column()).args[1].recipe
	local noCp = { rowKey = 1, colKey = 1, userParam = {} }
	local withMeta = { rowKey = 1, colKey = 1, userParam = { commonParams = {} }, meta = {} }
	local broken = setmetatable({}, { __index = function() error("cell boom") end })
	local cases = { { noCp }, { withMeta }, { noCp, "extra" }, { broken } }
	for i, args in ipairs(cases) do
		fn(table.unpack(args))
		local call = rowCalls[#rowCalls]
		eq(call.n, #args, "case " .. i)
		for j = 1, #args do ok(call[j] == args[j], "case " .. i) end
	end
	eq(warnings("[LineManagerPlus] list hover: row"), 1)
end)

-- block --------------------------------------------------------------------------------------------------------------

local function renderCallout(params)
	eq(react.GetRecipeName(params.recipe), "SquareLmpInfoCallout")
	local out = recipeFns.SquareLmpInfoCallout(params.recipeParam)
	eq(out.kind, "BoxLayout")
	local comp = out.children[1]
	eq(comp.kind, "Component")
	return comp.layout.children[1], comp.meta.styleSheet.padding
end

test("block: hovering a row opens it once right of the line list, top aligned with the row; unhover closes it", function()
	setup()
	local cp = commonParams()
	local onMouseOver, holder = row(1, cp)
	onMouseOver(true)
	onMouseOver(true)
	eq(#callouts.opened, 1)
	local c = callouts.opened[1]
	ok(c.parent == holder)
	eq(c.anchor.x, 0); eq(c.anchor.y, 0)
	eq(c.recipeParam.onRight, true)
	eq(c.recipeParam.gap, hover.GAP)
	local pos = c.getPositionFn()
	near(pos.x, LIST.x + LIST.w) -- the list's right edge
	near(pos.y, 0.27) -- the row's top
	local tv, pad = renderCallout(c)
	eq(tv.text, "Bus Line 1\n" .. STATS) -- no estimate
	ok(tv.class:find("sq-lmp-stli", 1, true) ~= nil)
	eq(pad[2], 0); eq(pad[4], hover.GAP)
	onMouseOver(false)
	eq(#callouts.closed, 1)
	ok(callouts.closed[1] == holder)
	eq(callouts.current, nil)
	onMouseOver(false)
	eq(#callouts.closed, 1)
	eq(warnings(), 0)
end)

test("block: a window in the right half of the screen gets the block on the list's left", function()
	setup()
	local cp = commonParams(false, { x = 0.7, y = 0.2, w = 0.25, h = 0.3 })
	local onMouseOver = row(1, cp)
	onMouseOver(true)
	local c = callouts.opened[1]
	eq(c.anchor.x, 1)
	eq(c.recipeParam.onRight, false)
	near(c.getPositionFn().x, 0.7)
	local _tv, pad = renderCallout(c)
	eq(pad[2], hover.GAP); eq(pad[4], 0)
end)

test("block: moving to the next row shows that line's, whichever of the two events comes first", function()
	setup()
	local cp = commonParams()
	local overA, holderA = row(1, cp)
	local overB, holderB = row(2, cp)
	overA(true)
	overB(true) -- entered B before leaving A
	overA(false) -- not A's block any more: stays
	eq(#callouts.opened, 2)
	ok(callouts.current.parent == holderB)
	ok(callouts.current.recipeParam.text:find("^Bus Line 2\n") ~= nil)
	overB(false) -- left B first, then entered A
	overA(true)
	ok(callouts.current.parent == holderA)
	eq(#callouts.opened, 3)
	eq(warnings(), 0)
end)

test("block: a depot or deleted line opens nothing; a stats error opens nothing and logs once", function()
	setup()
	local cp = commonParams()
	local over77 = row(77, cp)
	over77(true)
	eq(#callouts.opened, 0)
	eq(warnings(), 0)
	local over1 = row(1, cp)
	world.failList = true
	over1(true)
	over1(false)
	over1(true)
	eq(#callouts.opened, 0)
	eq(warnings("[LineManagerPlus] list hover: stats"), 1)
end)

test("block: no callout overlay logs once and nothing breaks", function()
	setup()
	local cp = commonParams(true)
	local over = row(1, cp)
	over(true)
	over(false)
	over(true)
	eq(warnings("[LineManagerPlus] list hover: callout"), 1)
	eq(warnings(), 1)
end)

test("block: the position keeps its last value when the row can't be read; without the list ref the row's edges", function()
	setup()
	local box = { x = 0.11, y = 0.4, w = 0.2, h = 0.02 }
	local cp = commonParams()
	local over = row(1, cp, box)
	over(true)
	local c = callouts.opened[1]
	local p1 = c.getPositionFn()
	box.fail = true
	local p2 = c.getPositionFn()
	eq(p2.x, p1.x); eq(p2.y, p1.y)
	eq(c.parent:hasExpired(), true) -- the row is gone: the container drops the block
	setup()
	local cp2 = commonParams()
	cp2.lineAndDepotListRef = nil
	local over2 = row(1, cp2, { x = 0.11, y = 0.4, w = 0.2, h = 0.02 })
	over2(true)
	near(callouts.opened[1].getPositionFn().x, 0.31)
	eq(warnings(), 0)
end)

test("block: a row whose node was never set logs once instead of opening", function()
	setup()
	local cp = commonParams()
	local over, holder = row(1, cp)
	holder:set(nil)
	eq(holder:hasExpired(), true)
	over(true)
	eq(#callouts.opened, 0)
	eq(warnings("[LineManagerPlus] list hover: callout"), 1)
end)

-- a row that goes while hovered gets no onMouseOver(false) (player report 2026-10-11: the block stayed, ~3 FPS) ------

test("holder: deleting the hovered row's line expires the block's parent, for good", function()
	setup()
	local over, holder = row(1, commonParams())
	over(true)
	local c = callouts.opened[1]
	ok(c.parent == holder)
	eq(holder:hasExpired(), false)
	world.lines[1] = nil -- deleted with the mouse still on its row
	eq(holder:hasExpired(), true)
	eq(holder:get(), nil) -- the dead node is never handed out again
	world.lines[1] = { 11 } -- an entity id reused later doesn't revive it
	eq(holder:hasExpired(), true)
	eq(warnings(), 0)
end)

test("holder: the line list's ref expiring (Line Manager closed) expires the block's parent", function()
	setup()
	local cp = commonParams()
	local expired = false
	cp.lineAndDepotListRef.hasExpired = function() return expired end
	local over, holder = row(1, cp)
	over(true)
	eq(holder:hasExpired(), false)
	expired = true
	eq(holder:hasExpired(), true)
end)

test("holder: an engine failure reading the line counts as gone", function()
	setup()
	local _over, holder = row(1, commonParams())
	api.engine.getComponent = function() error("engine boom") end
	eq(holder:hasExpired(), true)
end)
