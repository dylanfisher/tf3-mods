-- Line Manager Plus, feature "Vehicle list: current cargo" (setting vehicle_list_cargo): every row of the Line
-- Manager's vehicle list shows what the vehicle carries right now, between its name and its picture: the icon of
-- the cargo types aboard (fullest first, up to MAX_ICONS; " +N" for more) and "fill/capacity" for the whole vehicle (a greyed "0/25" when it
-- runs empty), every cargo type in the tooltip. Player request 2026-10-11: find the empty truck before removing
-- vehicles, see how many run empty. GUI only: reads the game state, writes nothing, saves nothing. Installed by
-- lmp.script.lua (doReplace).
--
-- Where the rows come from: VehicleList (base gui/line_vehicle_mgmt/vehicle_list_react_util.tl:525-605) renders
-- builtin.DataTable{ columns = { checkbox, VehicleLineSmall, VehicleName, VehicleIcon } }; the cell recipes are
-- file-local, so ReplaceRecipe can't reach them. VehicleName (:203-373) is 206 px wide (line_vehicle_mgmt.css.lua
-- :924-927): the name button, a filler button up to the picture and, while hovered, the Rename pen at its end.
--
-- Hook: as line_list_hover.lua, the MODULE FIELD builtin.ColumnDesc is wrapped. When it gets one table whose recipe
-- is VehicleName (react.GetRecipeName), it passes a copy whose recipe is a plain function (one per inner recipe, so
-- the column's recipe never changes between renders) that returns
--   SquareLmpVehicleNameCell<N>{ inner, cell } = BoxLayout{ inner(cell), SquareLmpVehicleCargo{ entity, userParam } }
-- The vanilla cell is called with its own params, untouched: selecting, renaming (the pen sits right of the name, so
-- now in front of the cargo), the hover highlight and the problem colour work as before. Our own ColumnDesc
-- wrapper, chained after line_list_hover's when both are On: each only touches its own column.
--
-- Width: the cell keeps the name column's width (lmp.css.lua NAME_W, 60 px wider than vanilla's 206, taken from the
-- picture column), so the row keeps its width and the picture its place.
-- The badge gets one of M.WIDTHS, the smallest that fits the line's icon slots (as many as the most cargo types a
-- vehicle of the line has capacity for, 1 to MAX_ICONS; a blank fills a missing icon) and "cap/cap" in digits of the
-- largest capacity on the vehicle's line (M.needWidth), so every row of a line has the same width class and its
-- numbers start at the same place; VehicleName gets the rest. The class is
-- the cell recipe's number N; lmp.css.lua has one rule pair per class (the same list; a stylesheet can't require
-- this module). In game 2026-10-11 a fixed 76 px badge let "28/130" run into the train's picture.
--
-- Look: the badge behaves as the rest of the row: the vanilla "highlight" / "selected" classes on its background
-- (line_vehicle_mgmt.css.lua:463-481, "R::VehicleManager !selected" etc.), hovering it marks the row hovered
-- (userParam.hoveredVehicleRef, as VehicleName :226-230). It keeps the shape that rendered in game (2026-10-11),
-- the same as VehicleName's own root (Component{ class, layout }); a version inside a Button (to select on click)
-- together with a wrapper Component rendered an empty strip, so no click.
--
-- Data, as the vanilla vehicle window (cargo_util.tl:683-705 with showEmpty, :941-972 unset capacities): set
-- compartments' capacity per cargo type from api.engine.util.vehicle.getVehicleCapacities (1-based by cargo id + 1;
-- config.capacities when missing), plus compartments not yet assigned to a cargo (getVehicleUnsetCapacities, one
-- list per compartment group, its largest entry counted once); the fill from
-- simEntityAtVehicleSystem.getVehicleSimEntitiesCountForCargoType. Read every INTERVAL s by
-- engine_react_util.useStepStateTimer (onStepTimer, a worker thread: engine reads only; deepEquals, so an unchanged
-- load re-renders nothing).
--
-- Failure handling: install, swap and cell each in pcall, a failure logged once ("[LineManagerPlus] vehicle cargo:
-- ..."); a failing swap or cell renders the vanilla cell; a vehicle that can't be read shows an empty badge.
-- SQPERF sections: "vehicle_cargo" one badge render (the first read included), "vehicle_cargo_read" one load read
-- (onStepTimer, worker thread; Clock is safe there), "vehicle_cargo_cell" one cell (its width, with a line scan on a
-- cache miss).

local PREFIX = "[LineManagerPlus] vehicle cargo: "

local warned = {}
local function warnOnce(key, err)
	if warned[key] then return end
	warned[key] = true
	local text = PREFIX .. key .. ": " .. tostring(err) .. " (further failures not logged)"
	if log and log.warning then log.warning(text) else print(text) end
end

local function say(msg)
	if log and log.message then log.message(PREFIX .. msg) else print(PREFIX .. msg) end
end

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local perf = (ug_require "square_line_manager_plus::/line_manager_plus/lmp_perf.lua").perf

local M = {}

M.ROW_RECIPE = "VehicleName"
M.BUILTIN = "::/gui/main/builtin.lua"
M.ENGINE_REACT_UTIL = "::/gui/main/engine_react_util.tl"
M.INTERVAL = 1.0 -- s between reads of one row's load
M.MAX_ICONS = 3 -- cargo icons in the badge (fullest first; more types aboard show " +N"); the tooltip lists every type.
-- Each line reserves only the slots its vehicles can fill (M.needWidth), so a single-cargo line keeps one slot (player
-- request 2026-10-11: condense the column; 2026-10-12: up to 3 icons instead of "+1" now the name column is flexible)
M.MAX_TOOLTIP_TYPES = 8 -- tooltip lines; more types end in "…"
-- badge widths (UI px), smallest first (inline sizes, see cellRender). Content estimate: M.needWidth, which is
-- PAD_W + slots * ICON_W + CHAR_W * chars = 17 + 20 * slots + 9 * chars for "c/c" of 1-4 digits (3/5/7/9 chars;
-- one slot: 64/82/100/118, each more slot +20), with " +N" 3 chars more. Classes rather than the exact need, so every
-- row of a line has the same width and its numbers start at the same place. The widest: three slots, 5 digits, " +N"
-- (17 + 60 + 14 * 9 = 203).
M.WIDTHS = { 64, 82, 100, 118, 136, 154, 172, 190, 208 }
-- CHAR_W: a body font digit (in game 2026-10-11 8 px left "10/20" cut at about 3.5 characters once the margins were
-- counted, so 9); ICON_W: the icon slot (no margin); PAD_W: what the badge takes off its class width besides the
-- content (2 * BADGE_PAD, BADGE_SLACK), the text's 2 px left margin and 2 px safety.
M.CHAR_W, M.ICON_W, M.PAD_W = 9, 20, 17

local function digits(n) return #tostring(math.floor(n)) end

--- The vehicle's capacities: { [cargoId] = capacity } of its set compartments (single-type unset groups added to
--- their type), the capacity not yet assigned among several types, how many cargo types it can carry at all and how
--- many it has capacity for (byId's size: the most types it can have aboard, as the fill is read per byId type).
--- nil when it isn't a transport vehicle. tv: its TRANSPORT_VEHICLE component when the caller has it (read here
--- otherwise; it is also the existence check before the util calls). Unassigned compartments count only cargo types
--- currently produced, as the vanilla vehicle window (cargo_util.tl:941-972). Engine reads only.
function M.capacities(vehicle, tv)
	if tv == nil then
		tv = M.liveVehicle(vehicle)
		if tv == nil then return nil end
	end
	local stock = api.engine.util.stock
	local isProduced = stock and stock.isCargoTypeCurrentlyProduced
	local function produced(id)
		if isProduced == nil then return true end
		local okP, yes = pcall(isProduced, id)
		return not okP or yes ~= false
	end
	local util = api.engine.util.vehicle
	local caps
	if util and util.getVehicleCapacities then caps = util.getVehicleCapacities(vehicle) end
	if caps == nil and tv.config then caps = tv.config.capacities end
	if caps == nil then return nil end
	local byId, possible, nPossible, nSet = {}, {}, 0, 0
	local function mark(id)
		if not possible[id] then possible[id] = true; nPossible = nPossible + 1 end
	end
	for i, cap in ipairs(caps) do
		if cap > 0 then byId[i - 1] = cap; nSet = nSet + 1; mark(i - 1) end
	end
	local unset = 0
	local groups = util and util.getVehicleUnsetCapacities and M.liveVehicle(vehicle)
		and util.getVehicleUnsetCapacities(vehicle) or {}
	for _g, group in ipairs(groups) do
		local maxCap, ids = 0, {}
		for i, cap in ipairs(group) do
			if cap > 0 and produced(i - 1) then
				ids[#ids + 1] = i - 1
				if cap > maxCap then maxCap = cap end
			end
		end
		for _k, id in ipairs(ids) do mark(id) end
		if #ids == 1 then
			if byId[ids[1]] == nil then nSet = nSet + 1 end
			byId[ids[1]] = (byId[ids[1]] or 0) + maxCap
		elseif #ids > 1 then
			unset = unset + maxCap
		end
	end
	return { byId = byId, unset = unset, possible = nPossible, set = nSet }
end

--- The load of `vehicle`, or nil (no transport vehicle, no capacity, a failed read):
--- { fill, capacity (whole vehicle), icons = { cargoId, ... } (loaded types, fullest first, at most MAX_ICONS; the
--- only possible type when empty), more (loaded types beyond the icons), empty, unset, types = { {id, fill, capacity}, ... } (loaded first, fullest
--- first, then by capacity, then by id) }. Engine reads only: safe on the onStepTimer worker thread.
function M.read(vehicle)
	local c = M.capacities(vehicle)
	if c == nil then return nil end
	local sys = api.engine.system.simEntityAtVehicleSystem
	if M.liveVehicle(vehicle) == nil then return nil end
	local types, total, filled = {}, c.unset, 0
	for id, cap in pairs(c.byId) do
		local fill = sys.getVehicleSimEntitiesCountForCargoType(vehicle, id) or 0
		types[#types + 1] = { id, fill, cap }
		total, filled = total + cap, filled + fill
	end
	if total <= 0 then return nil end
	table.sort(types, function(a, b)
		if a[2] ~= b[2] then return a[2] > b[2] end
		if a[3] ~= b[3] then return a[3] > b[3] end
		return a[1] < b[1]
	end)
	local icons, more = {}, 0
	for _k, t in ipairs(types) do
		if t[2] > 0 then
			if #icons < M.MAX_ICONS then icons[#icons + 1] = t[1] else more = more + 1 end
		end
	end
	if filled == 0 and c.possible == 1 and #types == 1 then icons[1] = types[1][1] end
	return { fill = filled, capacity = total, icons = icons, more = more, empty = filled == 0, unset = c.unset,
		types = types }
end

--- The vehicle's TRANSPORT_VEHICLE component, or nil when `vehicle` is no (longer a) transport vehicle: sold,
--- replaced, entity 0 (the world). Checked right before every native vehicle call below: a stale id there is a fatal
--- engine assert ("it != components.end()"), which pcall can't catch. The list's rows outlive their vehicles by up
--- to a refresh, and the reads run on a worker thread (onStepTimer).
function M.liveVehicle(vehicle)
	if type(vehicle) ~= "number" or vehicle <= 0 then return nil end
	local ok, tv = pcall(function()
		if not api.engine.entityExists(vehicle) then return nil end
		return api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
	end)
	if ok then return tv end
	return nil
end

--- The vehicle's whole capacity (set compartments plus unassigned ones), or nil when it can't be read.
--- Second result: how many cargo types it can have aboard at once (icon slots and "+N" room in M.needWidth).
function M.totalCapacity(vehicle, tv)
	local c = M.capacities(vehicle, tv)
	if c == nil then return nil end
	local total = c.unset
	for _id, cap in pairs(c.byId) do total = total + cap end
	return total, c.set
end

-- CPU s (os.clock counts all threads, so shorter in wall time) a line's capacities are kept: it only has to outlive
-- one render pass of the list (every row asks for its line)
M.LINE_CACHE_S = 2
local lineCap = {} -- line -> { t, capacity, totals = { [vehicle] = whole capacity }, kinds = most cargo types aboard }

-- the largest capacity of the vehicles on `line` (may be nil) and each one's capacity (cached)
local function lineCapacity(line)
	local hit, now = lineCap[line], os.clock()
	if hit and now - hit.t < M.LINE_CACHE_S then return hit.capacity, hit.totals, hit.kinds end
	local best, totals, most = nil, {}, 0
	local ok, vehicles = pcall(api.engine.system.transportVehicleSystem.getLineVehicles, line)
	if ok and vehicles then
		for _k, v in ipairs(vehicles) do
			local cap, kinds = M.totalCapacity(v)
			totals[v] = cap
			if cap and (best == nil or cap > best) then best = cap end
			if kinds and kinds > most then most = kinds end
		end
	end
	lineCap[line] = { t = now, capacity = best, totals = totals, kinds = most }
	return best, totals, most
end

--- UI px the badge needs at most for `vehicle`, or nil when it can't be read, and its icon slots: padding, one slot
--- per cargo type the line's vehicles can have aboard (the most of any vehicle, 1 to MAX_ICONS, reserved in every row
--- of the line, so their numbers line up) and "cap/cap" in digits of the largest capacity on the vehicle's
--- line (its own when it has no line), so every row of a line gets the same width class and a load change, or a
--- compartment getting a cargo assigned, never changes it (in game 2026-10-11: one ship of a line, its holds
--- assigned, got a smaller class than the others and its badge sat further left). A vehicle without capacity of its
--- own (a lone locomotive) takes its line's class too. Lines where a vehicle can have more types aboard than
--- MAX_ICONS get room for " +N" as well. The slots grow when a vehicle's compartments get a cargo assigned (rare;
--- the line's width class then changes once). One component read per row while the line cache holds.
function M.needWidth(vehicle)
	local tv = M.liveVehicle(vehicle)
	if tv == nil then return nil end
	local lc, totals, most
	if type(tv.line) == "number" and tv.line > 0 then lc, totals, most = lineCapacity(tv.line) end
	local own = totals and totals[vehicle]
	if own == nil then -- no line, or not (yet) in the line's list
		local ownKinds
		own, ownKinds = M.totalCapacity(vehicle, tv)
		if ownKinds and ownKinds > (most or 0) then most = ownKinds end
	end
	local cap = own or 0
	if lc and lc > cap then cap = lc end
	if cap <= 0 then return nil end
	local chars = 2 * digits(cap) + 1
	if (most or 0) > M.MAX_ICONS then chars = chars + 3 end -- room for " +N" on lines that can carry more types
	local slots = math.max(1, math.min(M.MAX_ICONS, most or 0))
	return M.PAD_W + slots * M.ICON_W + chars * M.CHAR_W, slots
end

--- The width class index into M.WIDTHS for a needed width (nil: the smallest; too wide: the largest).
function M.widthIndex(need)
	if need == nil then return 1 end
	for i, w in ipairs(M.WIDTHS) do
		if w >= need then return i end
	end
	return #M.WIDTHS
end

--- The badge text: "6/25", "21/90 +1" (one more cargo type aboard than icons shown; the tooltip lists it).
function M.badgeText(s)
	local text = string.format("%d/%d", s.fill, s.capacity)
	if (s.more or 0) > 0 then text = text .. " +" .. s.more end
	return text
end

--- The badge tooltip: a title and one "Cargo: fill/capacity" line per type (the game's cargo names, localized), and
--- the capacity not yet assigned to a cargo type.
function M.tooltip(s)
	local lines = { _("Current load") }
	for k, t in ipairs(s.types) do
		if k > M.MAX_TOOLTIP_TYPES then
			lines[#lines + 1] = "…"
			break
		end
		local okName, ct = pcall(api.res.cargoTypeRep.get, t[1])
		local name = okName and ct ~= nil and ct.name or tostring(t[1])
		lines[#lines + 1] = string.format(_("%s: %d/%d"), name, t[2], t[3])
	end
	if s.unset > 0 then
		lines[#lines + 1] = string.format(_("Not yet assigned to a cargo: %d"), s.unset)
	end
	return table.concat(lines, "\n")
end

-- the cargo's icon path, or nil
local function iconPath(id)
	if id == nil or id < 0 then return nil end
	local ok, ct = pcall(api.res.cargoTypeRep.get, id)
	if ok and ct ~= nil and type(ct.icon) == "string" and ct.icon ~= "" then return ct.icon end
	return nil
end

local engine_react_util -- required on first render (base GUI module, only there in the GUI state)

-- the row's vanilla userParam (vehicle_list_react_util.tl:579-590) or nil when it isn't one
local function rowParams(up)
	if type(up) ~= "table" then return nil end
	if up.hoveredVehicleRef == nil or up.managerRef == nil then return nil end
	return up
end

local timedRead = perf:wrap("vehicle_cargo_read", function(vehicle) return M.read(vehicle) end)
local tipCache = setmetatable({}, { __mode = "k" }) -- load state -> tooltip (a state is replaced, never changed)

local Badge = react.RegisterRecipe("SquareLmpVehicleCargo", perf:wrap("vehicle_cargo", function(p)
	engine_react_util = engine_react_util or ug_require(M.ENGINE_REACT_UTIL)
	local entity, up, slots = p.entity, rowParams(p.userParam), p.slots or 1
	local state = engine_react_util.useStepStateTimer(function()
		local ok, s = pcall(timedRead, entity)
		if ok then return s end
		warnOnce("read", s)
		return nil
	end, M.INTERVAL)
	-- the row's hover and selection, as VehicleName (hooks only for a vanilla userParam, the same every render)
	local hovered, selected = false, false
	if up then
		react.onMouseEvent(function(evt)
			if evt.type == api.gui.mouse.Event.Type.Entered then up.hoveredVehicleRef:set(entity) end
			return false
		end)
		hovered = react.useMirrorState(up.hoveredVehicleRef):old() == entity
		-- the manager api once per render, as VehicleName (vehicle_list_react_util.tl:206); the step only calls it
		local okSel, isSel = pcall(function() return up.managerRef:get():getApi().isVehicleSelected end)
		if not okSel then isSel = nil end
		selected = engine_react_util.useStepState(function()
			if isSel == nil then return false end
			local ok, sel = pcall(isSel, entity)
			return ok and sel == true
		end):old() == true
	end
	local s = state:old()
	local children = {}
	local tooltip, text, icons
	if s ~= nil then
		-- the texts in a pcall: M.cell's pcall doesn't cover this render (react runs it later) and an error here would
		-- break the window; no node is made inside it. On failure an empty badge, logged once.
		local okText, err = pcall(function()
			icons = {}
			for _k, id in ipairs(s.icons) do icons[#icons + 1] = iconPath(id) end
			text = M.badgeText(s)
			tooltip = tipCache[s]
			if tooltip == nil then
				tooltip = M.tooltip(s)
				tipCache[s] = tooltip
			end
		end)
		if not okText then
			warnOnce("badge", err)
			s, tooltip = nil, nil
		end
	end
	if s ~= nil then
		-- the line's icon slots, right-aligned to the text: a blank of the icon's size per missing icon, so the text
		-- starts at the same place in every row
		for _k = #icons + 1, slots do
			children[#children + 1] = builtin.Component{ meta = { class = "sq-lmp-vcargo-gap" } }
		end
		for _k, icon in ipairs(icons) do
			children[#children + 1] = builtin.ImageView{
				meta = { class = "text-icon-size-hack, sq-lmp-vcargo-icon" },
				path = icon,
			}
		end
		children[#children + 1] = builtin.TextView{
			meta = { class = "font-scale-body, sq-lmp-vcargo-text" .. (s.empty and ", sq-lmp-vcargo-empty" or "") },
			text = text,
		}
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Component{
				meta = {
					class = "sq-lmp-vcargo" .. (hovered and ", highlight" or "") .. (selected and ", selected" or ""),
					tooltip = tooltip,
				},
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Horizontal,
					children = children,
				},
			},
		},
	}
end))

-- the vanilla name cell and our badge side by side. The badge's width class is an INLINE size on the badge's recipe
-- node (meta.styleSheet on the recipe call; a StyleSheet size is the content size, so the background's left and right
-- padding, BADGE_PAD each, and BADGE_SLACK come off): no stylesheet rule per class (docs/findings.md "Load crash
-- above ~200 mod stylesheet rules"; rev 4 had 2 rules per class). The cell recipe stretches over its column
-- (lmp.css.lua, gravity) and VehicleName fills what the badge leaves (its own gravity), so the name grows with the
-- column: the name column has the table's weight (vehicle_columns.lua) and takes the room the pictures don't need.
M.BADGE_PAD = 4 -- the badge background's left and right padding (lmp.css.lua, Component!sq-lmp-vcargo)
M.BADGE_SLACK = 5 -- px more off the badge: in game 2026-10-11 the vanilla name cell took a little more than its size
local function cellRender(p)
	local st = api.gui.StyleSheet.new()
	st.size = api.type.Vec2f.new(p.width - 2 * M.BADGE_PAD - M.BADGE_SLACK, -1)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = { p.inner(p.cell), Badge{ entity = p.entity, userParam = p.userParam, slots = p.slots,
			meta = { styleSheet = st } } },
	}
end
M.CELL_RECIPE = "SquareLmpVehicleNameCell"
local Cell = react.RegisterRecipe(M.CELL_RECIPE, cellRender)

--- The cell node for `p` ({ inner, cell, entity, userParam }) with the badge in the width class and icon slots of its
--- vehicle's line.
M.cell = perf:wrap("vehicle_cargo_cell", function(p)
	local okW, need, slots = pcall(M.needWidth, p.entity)
	if not okW then
		warnOnce("width", need)
		need, slots = nil, nil
	end
	p.width = M.WIDTHS[M.widthIndex(need)]
	p.slots = slots or 1
	return Cell(p)
end)

--- For a cell param: the vehicle entity, or nil (leave the call as is). The DataTable's C++ side may pass a
--- userdata (line_list_hover.lua decorate); VehicleName reads rowKey and userParam (vehicle_list_react_util.tl:204-205).
function M.entityOf(cell)
	local kind = type(cell)
	if kind ~= "table" and kind ~= "userdata" then return nil end
	local entity = cell.rowKey
	if type(entity) ~= "number" then return nil end
	return entity
end

local cellFns = setmetatable({}, { __mode = "k" }) -- inner recipe -> our cell function (stable per inner)

--- Our cell function around the name recipe `inner` (the same function for the same inner).
function M.cellFn(inner)
	local fn = cellFns[inner]
	if fn then return fn end
	fn = function(cell, ...)
		if select("#", ...) == 0 then
			local ok, entity = pcall(M.entityOf, cell)
			if not ok then
				warnOnce("cell", entity)
			elseif entity ~= nil then
				local okNode, node = pcall(M.cell, { inner = inner, cell = cell, entity = entity, userParam = cell.userParam })
				if okNode then return node end
				warnOnce("cell", node)
			end
		end
		return inner(cell, ...)
	end
	cellFns[inner] = fn
	return fn
end

--- A copy of the ColumnDesc param `p` with our cell function, or nil when it isn't the vehicle list's name column.
function M.swap(p)
	if type(p) ~= "table" or type(p.recipe) ~= "function" then return nil end
	if react.GetRecipeName(p.recipe) ~= M.ROW_RECIPE then return nil end
	local copy = {}
	for k, v in pairs(p) do copy[k] = v end
	copy.recipe = M.cellFn(p.recipe)
	return copy
end

local prev -- the ColumnDesc we wrapped, set by install()
local wrapper -- our function in builtin.ColumnDesc

local function columnDesc(...)
	if select("#", ...) == 1 then
		local ok, copy = pcall(M.swap, ...)
		if not ok then
			warnOnce("column", copy)
		elseif copy ~= nil then
			local okNode, node = pcall(prev, copy)
			if okNode then return node end
			warnOnce("column", node)
		end
	end
	return prev(...)
end

-- a later ReplaceRecipe(<our wrapper>, x) gets the function we wrapped instead (as line_list_hover.lua)
local function shimReplacementApi(replacementApi)
	if type(replacementApi) ~= "table" then return end
	local replace = replacementApi.ReplaceRecipe
	if type(replace) ~= "function" then return end
	replacementApi.ReplaceRecipe = function(original, ...)
		if wrapper ~= nil and original == wrapper then original = prev end
		return replace(original, ...)
	end
end

--- Wraps builtin.ColumnDesc; true when installed (now or before). Never errors.
function M.install(replacementApi)
	if prev then return true end
	local ok, err = pcall(function()
		local fn = type(builtin) == "table" and builtin.ColumnDesc or nil
		if type(fn) ~= "function" then
			warnOnce("install", "builtin.ColumnDesc is " .. type(fn) .. "; vehicle list left as is")
			return
		end
		if type(react.GetRecipeName) ~= "function" then
			warnOnce("install", "react.GetRecipeName missing; vehicle list left as is")
			return
		end
		prev = fn
		wrapper = columnDesc
		builtin.ColumnDesc = wrapper
		shimReplacementApi(replacementApi)
		say("installed")
	end)
	if not ok then
		warnOnce("install", err)
	end
	return prev ~= nil
end

return M
