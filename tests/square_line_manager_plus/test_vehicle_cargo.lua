-- Line Manager Plus vehicle list cargo badge (vehicle_cargo.lua) with fake react / builtin / engine_react_util and a
-- fake api.
-- Covers: install (wraps builtin.ColumnDesc once, keeps the previous wrapper in the chain, skips a missing field,
-- shims ReplaceRecipe), the column swap (only the VehicleName column; other recipes and malformed params pass
-- through; every other field kept; the same cell function on every render; a failing ColumnDesc with our copy falls
-- back), the cell (the vanilla cell called with its own params, then our badge for the row's vehicle; extra
-- arguments or a cell without a numeric rowKey go through untouched; a failing cell renders the vanilla one), the
-- read (loaded / empty / several types / unset compartments / no capacity / no vehicle), the width class and the
-- badge (icons, text, empty class, tooltip, the row's hover/selected classes, hover).

local react, builtin, vc, world, prevCalls, RAPI_CALLS, baseRecipes, recipeFns, innerCalls, timers

local function setup(opts)
	opts = opts or {}
	reset_modules()
	clear_logs()
	prevCalls, RAPI_CALLS, recipeFns, innerCalls, timers = {}, {}, {}, {}, {}
	world = {
		-- vehicle -> set capacities (1-based by cargo id + 1), unset groups, fills by cargo id
		caps = { [23] = { 30, 30, 30, 30 }, [22] = { 30, 30, 30 }, [11] = { 0, 25 }, [12] = { 0, 25 }, [13] = { 40, 20, 20 }, [14] = { 0, 0 }, [15] = { 0, 0 },
			[16] = { 0, 1000, 0 } },
		unset = { [15] = { { 0, 21, 21 }, { 0, 21 } }, [16] = { { 0, 0, 200 } } },
		fills = { [23] = { [0] = 4, [1] = 9, [2] = 2, [3] = 1 }, [22] = { [0] = 4, [1] = 9, [2] = 2 }, [11] = { [1] = 6 }, [12] = {}, [13] = { [1] = 3, [2] = 9 }, [14] = {}, [15] = {}, [16] = {} },
		cargo = { [0] = { name = "Passengers", icon = "pax.tga" }, [1] = { name = "Fuel", icon = "fuel.tga" },
			[2] = { name = "Goods", icon = "goods.tga" }, [3] = { name = "Coal", icon = "coal.tga" } },
		selected = {},
		line = {},
		unproduced = {},
	}
	set_global("api", {
		type = {
			ComponentType = { TRANSPORT_VEHICLE = "TV" },
			Clock = { new = function() return { getTime = function() return 1e9 end } end },
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
		},
		gui = {
			StyleSheet = { new = function() return {} end },
			mouse = { Event = { Type = { Entered = "E", Exited = "X" } } },
			camera = { followEntity = function(e) world.followed = e end },
		},
		engine = {
			entityExists = function(e) return world.caps[e] ~= nil end,
			getComponent = function(e, ct)
				world.tvCalls = (world.tvCalls or 0) + 1
				if ct == "TV" and world.caps[e] then
					return { line = world.line[e] or -1, config = { capacities = world.caps[e] } }
				end
			end,
			util = { stock = { isCargoTypeCurrentlyProduced = function(id) return not world.unproduced[id] end },
				vehicle = {
				getVehicleCapacities = function(e) return world.caps[e] end,
				getVehicleUnsetCapacities = function(e) return world.unset[e] or {} end,
			} },
			system = { transportVehicleSystem = { getLineVehicles = function(l)
				world.lineCalls = (world.lineCalls or 0) + 1
				local out = {}
				for v, x in pairs(world.line) do if x == l then out[#out + 1] = v end end
				return out
			end }, simEntityAtVehicleSystem = { getVehicleSimEntitiesCountForCargoType = function(e, id)
				return world.fills[e][id] or 0
			end } },
		},
		res = { cargoTypeRep = { get = function(id) return world.cargo[id] end } },
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
		onMouseEvent = function(fn) world.mouseFn = fn end,
		useMirrorState = function(ref) return { old = function() return ref:get() end } end,
	}
	builtin = {
		type = { Orientation = { Vertical = "V", Horizontal = "H" } },
		BoxLayout = function(p) return { kind = "BoxLayout", children = p.children } end,
		TextView = function(p) return { kind = "TextView", class = p.meta and p.meta.class, text = p.text } end,
		ImageView = function(p) return { kind = "ImageView", class = p.meta and p.meta.class, path = p.path } end,
		Component = function(p) return { kind = "Component", meta = p.meta, layout = p.layout } end,
		Button = function(p) return { kind = "Button", meta = p.meta, content = p.content, onClick = p.onClick,
			onDoubleClick = p.onDoubleClick } end,
	}
	if opts.noField ~= true then
		builtin.ColumnDesc = function(...)
			prevCalls[#prevCalls + 1] = table.pack(...)
			if opts.failColumn and type((...)) == "table" and (...).recipe ~= baseRecipes.VehicleName then
				error("column boom")
			end
			return { kind = "ColumnDesc", args = table.pack(...) }
		end
	end
	baseRecipes = {}
	for _i, n in ipairs({ "VehicleName", "VehicleIcon" }) do
		local r = react.RegisterRecipe(n, function() return "cell" end)
		baseRecipes[n] = function(...)
			innerCalls[#innerCalls + 1] = table.pack(...)
			return r(...)
		end
		names[baseRecipes[n]] = n
	end
	stub_module("::/gui/main/react.lua", react)
	stub_module("::/gui/main/builtin.lua", builtin)
	stub_module("::/gui/main/engine_react_util.tl", { useStepStateTimer = function(fn, interval)
		timers[#timers + 1] = { fn = fn, interval = interval }
		local v = world.frozen or fn() -- frozen: the timer keeps the same state table, as an unchanged load does
		return { old = function() return v end }
	end, useStepState = function(fn)
		local v = fn()
		return { old = function() return v end }
	end })
	vc = ug_require "square_line_manager_plus::/line_manager_plus/vehicle_cargo.lua"
end

local function rapi()
	return { ReplaceRecipe = function(orig, repl) RAPI_CALLS[#RAPI_CALLS + 1] = { orig = orig, repl = repl } end }
end

local function count(level, text)
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if e.level == level and (text == nil or e.msg:find(text, 1, true)) then n = n + 1 end
	end
	return n
end

local function column(recipe)
	return { name = " ", recipe = recipe or baseRecipes.VehicleName, getCompareValue = function() end }
end

-- the cell function of the name column after install
local function cellFn()
	vc.install(rapi())
	return builtin.ColumnDesc(column()).args[1].recipe
end

-- the vanilla userParam of the vehicle list (hover ref, manager api, select callback)
local function userParam()
	local hovered = { v = nil }
	return {
		hoveredVehicleRef = { get = function() return hovered.v end, set = function(_r, v) hovered.v = v end },
		managerRef = { get = function() return { getApi = function()
			return { isVehicleSelected = function(e) return world.selected[e] == true end }
		end } end },
		onClickSelectVehicle = function(e) world.clicked = e end,
	}
end

-- render our cell for `vehicle` down to the badge: the badge's root, its background Component, its children, the
-- cell node (recipe SquareLmpVehicleNameCell; p.width: the badge class width)
local function badge(vehicle, up)
	local cellNode = cellFn()({ rowKey = vehicle, colKey = 3, userParam = up or userParam() })
	eq(cellNode.recipe, "SquareLmpVehicleNameCell")
	local kids = recipeFns[cellNode.recipe](cellNode.p).children
	eq(#kids, 2)
	eq(kids[1].recipe, "VehicleName")
	local b = kids[2]
	eq(b.recipe, "SquareLmpVehicleCargo")
	eq(b.p.entity, vehicle)
	local root = recipeFns.SquareLmpVehicleCargo(b.p)
	local comp = root.children[1]
	return comp, comp, comp.layout.children, cellNode
end

-- install ------------------------------------------------------------------------------------------------------------

test("install: wraps builtin.ColumnDesc once and logs installed", function()
	setup()
	local orig = builtin.ColumnDesc
	ok(vc.install(rapi()))
	ok(builtin.ColumnDesc ~= orig)
	local w = builtin.ColumnDesc
	ok(vc.install(rapi()))
	ok(builtin.ColumnDesc == w)
	eq(count("message", "[LineManagerPlus] vehicle cargo: installed"), 1)
	eq(count("warning"), 0)
end)

test("install: a missing ColumnDesc installs nothing and warns once", function()
	setup({ noField = true })
	eq(vc.install(rapi()), false)
	eq(vc.install(rapi()), false)
	eq(builtin.ColumnDesc, nil)
	eq(count("warning", "[LineManagerPlus] vehicle cargo: install"), 1)
end)

test("install: keeps the previous wrapper in the chain; ReplaceRecipe of our wrapper gets the wrapped one", function()
	setup()
	local prev, chained = builtin.ColumnDesc, 0
	builtin.ColumnDesc = function(...) chained = chained + 1; return prev(...) end
	local before = builtin.ColumnDesc
	local api_ = rapi()
	vc.install(api_)
	builtin.ColumnDesc(column())
	eq(chained, 1)
	api_.ReplaceRecipe(builtin.ColumnDesc, "R1")
	api_.ReplaceRecipe("other", "R2")
	ok(RAPI_CALLS[1].orig == before)
	eq(RAPI_CALLS[2].orig, "other")
end)

-- swap ---------------------------------------------------------------------------------------------------------------

test("swap: only the VehicleName column; other fields kept; same cell function every render", function()
	setup()
	vc.install(rapi())
	local p = column()
	local q = builtin.ColumnDesc(p).args[1]
	ok(q ~= p)
	ok(q.recipe ~= baseRecipes.VehicleName)
	eq(q.name, " "); ok(q.getCompareValue == p.getCompareValue)
	ok(p.recipe == baseRecipes.VehicleName) -- caller's table untouched
	local q2 = builtin.ColumnDesc(column()).args[1]
	ok(q2.recipe == q.recipe)
	local other = column(baseRecipes.VehicleIcon)
	ok(builtin.ColumnDesc(other).args[1] == other)
	ok(builtin.ColumnDesc("x").args[1] == "x")
	local two = builtin.ColumnDesc(p, 2).args
	ok(two[1] == p); eq(two.n, 2)
end)

test("swap: a failing ColumnDesc with our copy falls back to the caller's param, logged once", function()
	setup({ failColumn = true })
	vc.install(rapi())
	local p = column()
	ok(builtin.ColumnDesc(p).args[1] == p) -- our copy failed: the vanilla param, unchanged
	ok(builtin.ColumnDesc(p).args[1] == p)
	eq(count("warning", "[LineManagerPlus] vehicle cargo: column"), 1)
end)

-- cell ---------------------------------------------------------------------------------------------------------------

test("cell: the vanilla cell gets its own params; our badge is beside it", function()
	setup()
	local fn = cellFn()
	local cell = { rowKey = 11, colKey = 3, userParam = { x = 1 } }
	local node = fn(cell)
	eq(node.recipe, "SquareLmpVehicleNameCell")
	eq(#innerCalls, 0) -- nothing rendered until react runs our recipe
	recipeFns[node.recipe](node.p)
	eq(#innerCalls, 1)
	ok(node.p.userParam == cell.userParam)
	ok(innerCalls[1][1] == cell); eq(innerCalls[1].n, 1)
end)

test("cell: extra arguments or no numeric rowKey go through untouched", function()
	setup()
	local fn = cellFn()
	local ref = {}
	local cell = { rowKey = 11 }
	eq(fn(ref, cell).recipe, "VehicleName")
	ok(innerCalls[1][1] == ref and innerCalls[1][2] == cell)
	eq(fn({ rowKey = "x" }).recipe, "VehicleName")
	eq(fn(nil).recipe, "VehicleName")
	eq(count("warning"), 0)
end)

-- read ---------------------------------------------------------------------------------------------------------------

test("read: loaded, empty, several types, unset compartments, no capacity, no vehicle", function()
	setup()
	local s = vc.read(11)
	eq(s.fill, 6); eq(s.capacity, 25); eq(s.icons, { 1 }); eq(s.empty, false)
	s = vc.read(12)
	eq(s.fill, 0); eq(s.capacity, 25); eq(s.icons, { 1 }); eq(s.empty, true)
	s = vc.read(13) -- whole vehicle: 12 of 80; icons goods (9), fuel (3); passengers listed last
	eq(s.fill, 12); eq(s.capacity, 80); eq(s.icons, { 2, 1 }); eq(s.more, 0)
	eq(s.types[1][1], 2); eq(s.types[2][1], 1); eq(s.types[3][1], 0)
	world.fills[13] = {}
	s = vc.read(13) -- empty with several types: no icon
	eq(s.icons, {}); eq(s.capacity, 80); eq(s.empty, true)
	s = vc.read(15) -- two unassigned groups: one of fuel/goods (21), one fuel only (21, counted as fuel)
	eq(s.capacity, 42); eq(s.unset, 21); eq(s.types, { { 1, 0, 21 } }); eq(s.icons, {})
	s = vc.read(16) -- a single-type unset group adds to its type
	eq(s.capacity, 1200); eq(s.types, { { 1, 0, 1000 }, { 2, 0, 200 } })
	eq(vc.read(14), nil)
	eq(vc.read(99), nil)
end)

test("read: a vehicle sold between the reads is never passed to a native vehicle call", function()
	setup()
	local passed = {}
	local util, sys = api.engine.util.vehicle, api.engine.system.simEntityAtVehicleSystem
	local caps, unset = util.getVehicleCapacities, util.getVehicleUnsetCapacities
	util.getVehicleCapacities = function(e)
		local got = caps(e)
		world.caps[e] = nil -- sold right after the capacity read
		return got
	end
	util.getVehicleUnsetCapacities = function(e) passed[#passed + 1] = e; return unset(e) end
	sys.getVehicleSimEntitiesCountForCargoType = function(e) passed[#passed + 1] = e; return 0 end
	eq(vc.read(11), nil)
	eq(passed, {})
	eq(vc.read(0), nil)
	eq(vc.needWidth(0), nil)
end)

test("width: icon slots for the line's cargo types, cap/cap of the line's largest vehicle; stable while loads change", function()
	setup()
	local w11 = vc.needWidth(11) -- "25/25", no line
	eq(w11, vc.PAD_W + vc.ICON_W + 5 * vc.CHAR_W)
	ok(vc.WIDTHS[vc.widthIndex(w11)] >= w11)
	world.fills[11] = {}
	eq(vc.needWidth(11), w11)
	eq(vc.needWidth(16), vc.PAD_W + 2 * vc.ICON_W + 9 * vc.CHAR_W) -- "1200/1200": two types, two slots
	eq(vc.needWidth(14), nil)
	-- on one line, the small vehicle takes the big one's width (cached per line)
	world.line[11], world.line[16] = 7, 7
	eq(vc.needWidth(11), vc.needWidth(16))
	local calls = world.lineCalls
	vc.needWidth(11)
	eq(world.lineCalls, calls)
	eq(vc.widthIndex(nil), 1)
	eq(vc.widthIndex(1), 1)
	eq(vc.widthIndex(10000), #vc.WIDTHS)
	local _b, _c, _k, cellNode = badge(16)
	eq(cellNode.p.width, vc.WIDTHS[vc.widthIndex(vc.needWidth(16))])
	-- the badge's width class as an inline size on its recipe node (content size: padding and slack off)
	local kids16 = recipeFns.SquareLmpVehicleNameCell(cellNode.p).children
	eq(kids16[2].p.meta.styleSheet.size.x, cellNode.p.width - 2 * vc.BADGE_PAD - vc.BADGE_SLACK)
	eq(kids16[2].p.meta.styleSheet.size.y, -1)
	local _b2, _c2, _k2, cell14 = badge(14) -- unreadable: the smallest class
	eq(cell14.p.width, vc.WIDTHS[1])
end)

-- badge --------------------------------------------------------------------------------------------------------------

test("badge: icon, fill/capacity and tooltip; refreshed by a 1 s step timer", function()
	setup()
	local button, _comp, kids = badge(11)
	eq(kids[1].kind, "ImageView"); eq(kids[1].path, "fuel.tga")
	eq(kids[2].text, "6/25")
	ok(not kids[2].class:find("sq-lmp-vcargo-empty", 1, true))
	eq(button.meta.tooltip, "Current load\nFuel: 6/25")
	eq(timers[1].interval, 1.0)
end)

test("badge: an empty vehicle is greyed; several types show their icons, every type in the tooltip", function()
	setup()
	local _b, _c, kids = badge(12)
	eq(kids[2].text, "0/25")
	ok(kids[2].class:find("sq-lmp-vcargo-empty", 1, true))
	local button, _c2, kids2 = badge(13) -- three slots: a blank, then the fullest first
	eq(#kids2, 4); eq(kids2[1].meta.class, "sq-lmp-vcargo-gap")
	eq(kids2[2].path, "goods.tga"); eq(kids2[3].path, "fuel.tga"); eq(kids2[4].text, "12/80")
	eq(button.meta.tooltip, "Current load\nGoods: 9/20\nFuel: 3/20\nPassengers: 0/40")
	world.fills[13] = {}
	local _b3, _c3, kids3 = badge(13)
	eq(#kids3, 4); eq(kids3[1].meta.class, "sq-lmp-vcargo-gap"); eq(kids3[3].meta.class, "sq-lmp-vcargo-gap")
	eq(kids3[4].text, "0/80") -- no icon when it would have to guess the type
	local b15 = badge(15)
	eq(b15.meta.tooltip, "Current load\nFuel: 0/21\nNot yet assigned to a cargo: 21")
end)

test("badge: the row's hover and selection colours; hovering it marks the row hovered", function()
	setup()
	local up = userParam()
	local _b, comp = badge(11, up)
	eq(comp.meta.class, "sq-lmp-vcargo")
	world.mouseFn({ type = "E" })
	eq(up.hoveredVehicleRef:get(), 11)
	world.selected[11] = true
	local _b2, comp2 = badge(11, up)
	eq(comp2.meta.class, "sq-lmp-vcargo, highlight, selected")
	local _b3, comp3 = badge(11, { other = true }) -- not a vanilla userParam: no row hooks, still a badge
	eq(comp3.meta.class, "sq-lmp-vcargo")
end)

test("badge: a vehicle without capacity shows an empty badge; a failing read is logged once", function()
	setup()
	local button, _c, kids = badge(14)
	eq(#kids, 0); eq(button.meta.tooltip, nil)
	api.engine.system.simEntityAtVehicleSystem.getVehicleSimEntitiesCountForCargoType = function() error("boom") end
	badge(11); badge(11)
	eq(count("warning", "[LineManagerPlus] vehicle cargo: read"), 1)
end)

test("badge: a failing badge text renders an empty badge, logged once", function()
	setup()
	vc.badgeText = function() error("text boom") end
	local button, _c, kids = badge(11)
	eq(#kids, 0); eq(button.meta.tooltip, nil)
	badge(11)
	eq(count("warning", "[LineManagerPlus] vehicle cargo: badge"), 1)
end)

test("badge: the tooltip is built once per load state", function()
	setup()
	local n, orig = 0, vc.tooltip
	vc.tooltip = function(s) n = n + 1; return orig(s) end
	world.frozen = vc.read(11)
	local b1 = badge(11)
	local b2 = badge(11)
	eq(n, 1)
	eq(b1.meta.tooltip, b2.meta.tooltip)
end)

test("width: a vehicle without capacity on a line takes the line's width class", function()
	setup()
	world.caps[20] = { 0, 0 }; world.fills[20] = {}
	world.line[16], world.line[20] = 7, 7
	eq(vc.needWidth(20), vc.needWidth(16))
	world.line[20] = nil
	eq(vc.needWidth(20), nil)
end)

test("width: with the line cached a row costs one component read", function()
	setup()
	world.line[11], world.line[16] = 7, 7
	vc.needWidth(11)
	local before = world.tvCalls
	vc.needWidth(11)
	eq(world.tvCalls - before, 1)
end)

test("width: capacities of 10000+ with every slot and +N fit the widest class", function()
	setup()
	world.caps[21] = { 12000, 12000, 12000, 12000 }; world.fills[21] = {}
	local need = vc.needWidth(21)
	ok(vc.WIDTHS[#vc.WIDTHS] >= need)
	eq(vc.widthIndex(need), #vc.WIDTHS)
end)

test("read: unassigned compartments count only produced cargo types, as the vehicle window", function()
	setup()
	world.unproduced[2] = true -- goods not produced: vehicle 15's fuel/goods group becomes fuel only
	local s = vc.read(15)
	eq(s.unset, 0); eq(s.types, { { 1, 0, 42 } }); eq(s.icons, { 1 })
	world.unproduced[1] = true -- nothing it can carry is produced
	eq(vc.read(15), nil)
end)

test("badge: up to MAX_ICONS icons, fullest first; the line reserves the slots its vehicles can fill", function()
	setup()
	local s = vc.read(22) -- fuel 9, passengers 4, goods 2
	eq(s.icons, { 1, 0, 2 }); eq(s.more, 0)
	local _b, _c, kids = badge(22)
	eq(#kids, 4)
	eq(kids[1].path, "fuel.tga"); eq(kids[2].path, "pax.tga"); eq(kids[3].path, "goods.tga"); eq(kids[4].text, "15/90")
	eq(vc.needWidth(22), vc.PAD_W + 3 * vc.ICON_W + 5 * vc.CHAR_W)
	eq(vc.needWidth(11), vc.PAD_W + vc.ICON_W + 5 * vc.CHAR_W) -- one type: one slot
	world.line[11], world.line[22] = 7, 7 -- on one line: the single-type vehicle gets the slots too
	eq(vc.needWidth(11), vc.needWidth(22))
	local _b2, _c2, kids11 = badge(11)
	eq(#kids11, 4); eq(kids11[1].meta.class, "sq-lmp-vcargo-gap"); eq(kids11[2].meta.class, "sq-lmp-vcargo-gap")
	eq(kids11[3].path, "fuel.tga"); eq(kids11[4].text, "6/25")
end)

test("badge: cargo types beyond MAX_ICONS show +N after the number; the line gets room for it", function()
	setup()
	local s = vc.read(23) -- fuel 9, passengers 4, goods 2, coal 1
	eq(s.icons, { 1, 0, 2 }); eq(s.more, 1)
	local button, _c, kids = badge(23)
	eq(kids[4].text, "16/120 +1")
	ok(button.meta.tooltip:find("Coal: 1/30", 1, true) ~= nil)
	eq(vc.needWidth(23), vc.PAD_W + 3 * vc.ICON_W + (7 + 3) * vc.CHAR_W)
	eq(vc.badgeText({ fill = 3, capacity = 9, more = 0 }), "3/9")
end)
