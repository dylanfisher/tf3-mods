-- Line Manager Plus, Send to Line info core: pure logic behind the extra lines of the "Send N vehicles to <line>." tooltip.
-- No GUI calls: everything game-specific comes in through `deps` (see core.new), so tests/square_line_manager_plus
-- can drive it with fakes. The recipe and the replacement live in stli.lua.
--
-- Numbers match the Line Manager footer (manager_window.tl:3940-4000, the LineDetails statistics row):
--   Capacity    statistics_react_util.calculateCargoColumnDataForLine(line).demand, lang_util.formatInt
--   Utilization statistics_react_util.calculateCargoColumnDataForLine(line).coverage,
--               api.util.toStringPercentPrecision(v, 0)
--   Frequency   line_util.calculateFrequencySeconds(line), api.util.formatMinutesSeconds
--   Rate        api.engine.util.line.calcLineStationThroughput(line), lang_util.formatInt
--               (gui_react_util.integer2TextLayout, gui_react_util.tl:334)
-- Vehicles: api.engine.system.transportVehicleSystem.getLineVehicles(line) (api/engine/system.d.tl:372); a vehicle's
-- model name is its multiple unit's name, else the first part's model description name, the same fields the vehicle
-- store shows (vehicle_store_util.tl:445-480; it formats desc.name into "{name} ({count})" at
-- vehicle_store_window.tl:906-911, so the name is already translated).
--
-- Before -> after estimate (PLAN.md feature 2, setting send_to_line_estimate): given the vehicles about to be sent,
-- the stats row shows "Frequency: 7 min 19 s → ~4 min 53 s" etc. n = vehicles on the line, k = selected vehicles
-- NOT already on it (TRANSPORT_VEHICLE.line ~= line), add = their capacity for the line's cargo (see core.vehicleCapacity):
--   Capacity   after = capacity + add (the footer's capacity is the sum of the line vehicles' load-config
--              capacities, cargo_util.tl:707-722 getLineCapacityUsages)
--   Frequency  after = interval * n / (n + k): k more vehicles on the same round trip, assuming similar speeds
--   Rate       after = rate * (capacity + add) / capacity: calcLineStationThroughput is linear in identical vehicles,
--              computed not measured (docs/findings.md "Line Rate, cloning onto a line": 1/2/3 ships -> 51/103/154);
--              throughput ~ capacity x trips, so for identical vehicles this is rate * (n + k) / n
--   Utilization no estimate: the footer's value is the cargo aboard right now / capacity (cargo_util.tl:707-722,
--              statistics_react_util.tl:194-224), a snapshot, not the waiting supply; how full the vehicles run
--              after the send depends on demand we can't see. The current value stays, without an arrow.
-- No estimate (plain value, no arrow) when k = 0 (all already on the line), for Frequency and Rate on a line without
-- vehicles (n = 0: no round-trip time, Rate 0; Capacity still gets "0 -> ~add"), for Rate with capacity 0, and when
-- an after value rounds to the before value.

local core = {}

core.CACHE_US = 1000000 -- stats of a line are reused for 1 s (Clock microseconds)
core.CACHE_MAX = 64 -- entries before the cache is cleared
core.TEXTS_MAX = 8 -- texts per line entry (one per selection) before they are cleared
core.MAX_GROUPS = 5 -- model rows shown; the rest are summed into one "other models" row
core.SEPARATOR = "  ·  " -- between the stats; the GUI font has "·" (docs/findings.md, HUD glyphs)

-- names: list of model names (one per vehicle). Returns { {name=, count=}, ... }, most vehicles first, then by name.
function core.groupModels(names)
	local counts, order = {}, {}
	for _i, name in ipairs(names or {}) do
		local key = (type(name) == "string" and name ~= "") and name or "?"
		if not counts[key] then
			counts[key] = 0
			order[#order + 1] = key
		end
		counts[key] = counts[key] + 1
	end
	local groups = {}
	for _i, name in ipairs(order) do groups[#groups + 1] = { name = name, count = counts[name] } end
	table.sort(groups, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.name < b.name
	end)
	return groups
end

-- After-values for the stats row (integers; nil = no estimate for that stat). Pure.
-- info: { n = vehicles on the line, capacity = int?, frequency = int seconds?, rate = int? }
-- sel:  { k = selected vehicles not on the line, add = their capacity for the line's cargo } or nil
function core.estimate(info, sel)
	local after = {}
	if type(sel) ~= "table" or type(sel.k) ~= "number" or sel.k <= 0 then return after end
	local n, k, add = info.n or 0, sel.k, sel.add or 0
	local function round(x) return math.floor(x + 0.5) end
	if type(info.capacity) == "number" and add > 0 then after.capacity = info.capacity + add end
	if type(info.frequency) == "number" and info.frequency > 0 and n > 0 then
		after.frequency = round(info.frequency * n / (n + k))
	end
	if type(info.rate) == "number" and info.rate > 0 and type(info.capacity) == "number" and info.capacity > 0
		and add > 0 then
		after.rate = round(info.rate * (info.capacity + add) / info.capacity)
	end
	for _i, key in ipairs({ "capacity", "frequency", "rate" }) do
		if after[key] == info[key] then after[key] = nil end
	end
	return after
end

-- Text lines for the tooltip. Texts go through the global _ (GUI scripts translate at once, docs/findings.md
-- "Translations"); the label/value pairs are one format string each.
-- info:  { names = {model name per vehicle}, capacity = int?, utilization = number?, frequency = int seconds?,
--          rate = int? }; a nil stat is left out (its call failed).
-- fmt:   { format = lang_util.format, int = lang_util.formatInt, percent = fn(number) -> string,
--          minutes = fn(seconds) -> string }
-- after: optional, core.estimate's result. A stat with an after-value reads "{label}: {before} → ~{after}"; with any
--        after-value the stats take two rows (Capacity, Utilization / Frequency, Rate) so the tooltip stays narrow.
--        after.cantCarry > 0 adds a last line counting the selected vehicles that can't carry the line's cargo.
function core.formatLines(info, fmt, after)
	local format, int = fmt.format, fmt.int
	after = after or {}
	local lines = {}
	local names = info.names or {}
	if #names == 0 then
		lines[1] = _("No vehicles on this line.")
	else
		lines[1] = format(_("Vehicles on this line: {count}"), { count = int(#names) })
		local groups = core.groupModels(names)
		local other = 0
		for i, g in ipairs(groups) do
			if i <= core.MAX_GROUPS or #groups == core.MAX_GROUPS + 1 then
				lines[#lines + 1] = format(_("{count}× {name}"), { count = int(g.count), name = g.name })
			else
				other = other + g.count
			end
		end
		if other > 0 then
			lines[#lines + 1] = format(_("{count}× other models"), { count = int(other) })
		end
	end
	local split = (after.capacity or after.frequency or after.rate) ~= nil
	local rows = { {}, {} }
	local function add(row, label, value, afterValue)
		if value == nil then return end
		local r = rows[split and row or 1]
		if afterValue ~= nil then
			r[#r + 1] = format(_("{label}: {before} → ~{after}"), { label = label, before = value, after = afterValue })
		else
			r[#r + 1] = format(_("{label}: {value}"), { label = label, value = value })
		end
	end
	add(1, _("Capacity"), info.capacity and int(info.capacity), after.capacity and int(after.capacity))
	add(1, _("Utilization"), info.utilization and fmt.percent(info.utilization))
	add(2, _("Frequency"), info.frequency and fmt.minutes(info.frequency),
		after.frequency and fmt.minutes(after.frequency))
	add(2, _("Rate"), info.rate and int(info.rate), after.rate and int(after.rate))
	for _i, r in ipairs(rows) do
		if #r > 0 then lines[#lines + 1] = table.concat(r, core.SEPARATOR) end
	end
	if type(after.cantCarry) == "number" and after.cantCarry > 0 then
		lines[#lines + 1] = format(_("Selected vehicles that can't carry this line's cargo: {count}"),
			{ count = int(after.cantCarry) })
	end
	return lines
end

-- A vehicle's capacity for a line's cargo. caps / allCaps: Lua lists indexed by cargo type id + 1
-- (TRANSPORT_VEHICLE.config.capacities = its current load config, .allCaps = every cargo it can load;
-- api/engine.d.tl:1416-1418; docs/findings.md "capacities are indexed by cargo type id + 1").
-- cargo: set {[cargo id + 1] = true} of the cargo the line carries, or nil when unknown (a line without capacity):
-- then the vehicle's whole load config counts. With a known set: the load-config capacity for those cargos; if that
-- is 0, the largest allCaps entry among them (it loads one of them after a reconfiguration); 0 = it can't carry the
-- line's cargo. Pure.
function core.vehicleCapacity(caps, allCaps, cargo)
	local sum = 0
	if cargo == nil then
		for _i, c in ipairs(caps or {}) do
			if type(c) == "number" and c > 0 then sum = sum + c end
		end
		return sum
	end
	for idx in pairs(cargo) do
		local c = caps and caps[idx]
		if type(c) == "number" and c > 0 then sum = sum + c end
	end
	if sum > 0 then return sum end
	local best = 0
	for idx in pairs(cargo) do
		local c = allCaps and allCaps[idx]
		if type(c) == "number" and c > best then best = c end
	end
	return best
end

-- deps:
--   api                    the game api (engine, type, res, util)
--   stats                  statistics_react_util (calculateCargoColumnDataForLine)
--   lineUtil               line_util (calculateFrequencySeconds)
--   fmt                    as for core.formatLines
--                          (the estimate also reads api.engine.util.line.getLineCapacityUsages and
--                          TRANSPORT_VEHICLE.line / .config)
--   now                    fn() -> microseconds (api.type.Clock; safe on every thread, docs/findings.md)
--   warn                   fn(key, err): log once per key
function core.new(deps)
	local self = { cache = {}, size = 0 }
	local api = deps.api

	-- true if `entity` still is a line (the hovered entity can be gone by the time the tooltip renders)
	function self.isLine(entity)
		if type(entity) ~= "number" or entity < 0 then return false end
		if not api.engine.entityExists(entity) then return false end
		return api.engine.getComponent(entity, api.type.ComponentType.LINE) ~= nil
	end

	function self.modelName(vehicle)
		local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
		if not tv then return nil end
		local config = tv.transportVehicleConfig
		local mus = config.muFileNames
		if mus and mus[1] then
			local ok, name = pcall(function()
				local id = api.res.multipleUnitRep.find(mus[1])
				if id and id >= 0 then return api.res.multipleUnitRep.get(id).name end
			end)
			if ok and type(name) == "string" and name ~= "" then return name end
		end
		local part = config.vehicles[1]
		if not part then return nil end
		local desc = api.res.modelRep.get(part.part.modelId).metadata.description
		return desc and desc.name or nil
	end

	-- one value, or nil (logged once) if its call fails
	local function try(key, fn)
		local ok, v = pcall(fn)
		if ok then return v end
		deps.warn(key, v)
		return nil
	end

	function self.collect(line)
		local names = {}
		local vehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line) or {}
		for _i, v in ipairs(vehicles) do
			names[#names + 1] = try("model", function() return self.modelName(v) end) or "?"
		end
		local column = try("cargo", function() return deps.stats.calculateCargoColumnDataForLine(line) end)
		return {
			names = names,
			n = #names,
			capacity = column and column.demand,
			utilization = column and column.coverage,
			frequency = try("frequency", function() return deps.lineUtil.calculateFrequencySeconds(line) end),
			rate = try("rate", function() return api.engine.util.line.calcLineStationThroughput(line) end),
		}
	end

	-- The cargo the line carries: {[cargo id + 1] = true} from getLineCapacityUsages(line, false) (the footer's
	-- source, cargo_util.tl:895-907, keys = cargo id + 1), or nil when it lists no capacity (no vehicles yet).
	function self.cargoSet(line)
		local usages = api.engine.util.line.getLineCapacityUsages(line, false)
		local set, any = {}, false
		for idx, u in pairs(usages or {}) do
			if type(idx) == "number" and u and type(u.capacity) == "number" and u.capacity > 0 then
				set[idx], any = true, true
			end
		end
		return any and set or nil
	end

	local function list(v)
		local out = {}
		if v ~= nil then
			for _i, c in ipairs(v) do out[#out + 1] = c end
		end
		return out
	end

	-- { k, add, cantCarry } for sending `vehicles` (entities) to `line`; cargo as for core.vehicleCapacity.
	-- A vehicle already on the line, or gone, doesn't count; cantCarry only with a known cargo set.
	function self.selection(line, vehicles, cargo)
		local k, add, cantCarry = 0, 0, 0
		for _i, v in ipairs(vehicles) do
			local tv = api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE)
			if tv and tv.line ~= line then
				k = k + 1
				local cfg = tv.config
				local cap = core.vehicleCapacity(cfg and list(cfg.capacities), cfg and list(cfg.allCaps), cargo)
				add = add + cap
				if cap == 0 and cargo ~= nil then cantCarry = cantCarry + 1 end
			end
		end
		return { k = k, add = add, cantCarry = cantCarry }
	end

	-- after-values for `vehicles`, or {} when anything fails (no arrows; logged once per kind)
	local function afterFor(entry, line, vehicles)
		if entry.cargo == nil then
			entry.cargo = try("cargo set", function() return self.cargoSet(line) end) or false
		end
		local sel = try("selection", function() return self.selection(line, vehicles, entry.cargo or nil) end)
		if not sel then return {} end
		local after = try("estimate", function() return core.estimate(entry.info, sel) end) or {}
		after.cantCarry = sel.cantCarry
		return after
	end

	-- Text lines for `line`, or nil if it isn't a line (caller then shows the vanilla tooltip only).
	-- vehicles (optional): entities about to be sent there; adds the before -> after estimate (core.estimate).
	-- The line's stats are cached for 1 s; within that, the text per selection (key = the entity list).
	-- Errors reading the line's stats propagate (the caller pcalls); estimate errors only drop the arrows.
	function self.lines(line, vehicles)
		local t = deps.now()
		local key = ""
		if type(vehicles) == "table" and #vehicles > 0 then key = table.concat(vehicles, ",") end
		local hit = self.cache[line]
		if not (hit and t - hit.t >= 0 and t - hit.t < core.CACHE_US) then
			if not self.isLine(line) then return nil end
			if not hit then
				if self.size >= core.CACHE_MAX then
					self.cache, self.size = {}, 0
				end
				self.size = self.size + 1
			end
			hit = { t = t, info = self.collect(line), texts = {}, ntexts = 0 }
			self.cache[line] = hit
		end
		local text = hit.texts[key]
		if text then return text end
		local after = nil
		if key ~= "" then after = afterFor(hit, line, vehicles) end
		text = core.formatLines(hit.info, deps.fmt, after)
		if hit.ntexts >= core.TEXTS_MAX then hit.texts, hit.ntexts = {}, 0 end
		hit.texts[key] = text
		hit.ntexts = hit.ntexts + 1
		return text
	end

	return self
end

return core
