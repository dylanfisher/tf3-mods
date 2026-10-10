-- Offline perf bench for the overlay tick (plans/square_supply_gaps/PERF_REVIEW.md). Skipped unless
-- SQSG_BENCH=1:  SQSG_BENCH=1 make test MOD=mods/square_supply_gaps ARGS="-k bench"
-- Real gather / cache / model / scope / markers / areas against a fake engine shaped like the spike map
-- (scale 1: 30 towns, ~3775 buildings, ~44 % with needs, 71 stations, 40 lines) and 5x that.
-- Prints Lua ms per tick (Lua 5.4 here, not the game's runtime) and engine calls per tick by kind; the
-- engine calls themselves cost nothing here, so the call counts are the number to compare.

local overlay = ug_require "square_supply_gaps::/supply_gaps/sg_overlay.tl"
local scope = ug_require "square_supply_gaps::/supply_gaps/sg_scope.tl"

local PASS = 0
local CARGOS = { 3, 4, 7, 9, 12 }
local NCARGO = 20

local function world(k)
	local rnd = 12345
	local function r(n)
		rnd = (rnd * 1103515245 + 12345) % 2147483648
		return rnd % n
	end
	local comps, town2b, stock, catch, lineStops = {}, {}, {}, {}, {}
	local nextId = 100000
	local function id() nextId = nextId + 1 return nextId end
	local towns = {}
	local T = 30 * k
	for t = 1, T do
		local te = id()
		towns[t] = te
		comps[te] = { NAME = { name = "Town " .. t } }
		local tx, ty = (t % 10) * 2000, math.floor(t / 10) * 2000
		local list = {}
		for i = 1, 126 do
			local b = id()
			list[#list + 1] = b
			local x, y = tx + r(600) - 300, ty + r(600) - 300
			local sl, pc = id(), id()
			local stocks = {}
			if r(100) < 44 then
				local n = 1 + r(2)
				for j = 1, n do
					stocks[#stocks + 1] = { type = 0, cargoType = CARGOS[1 + r(#CARGOS)] }
				end
			end
			stocks[#stocks + 1] = { type = 1, cargoType = PASS }
			comps[b] = {
				TOWN_BUILDING = { stockList = sl, personCapacity = pc, town = te },
				BOUNDING_VOLUME = { bbox = { min = { x = x - 5, y = y - 5, z = 0 }, max = { x = x + 5, y = y + 5, z = 10 } } },
			}
			comps[sl] = { STOCK_LIST = { stocks = stocks } }
			comps[pc] = { PERSON_CAPACITY = { type = r(3) } }
			stock[sl] = r(3)
		end
		town2b[te] = list
	end
	-- 71 stations per scale, each its own group, catching ~150 buildings of one town
	local groups = {}
	for s = 1, 71 * k do
		local st, g = id(), id()
		local te = towns[1 + r(T)]
		local list = {}
		local tl = town2b[te]
		local start = r(#tl)
		for i = 1, 150 do list[i] = tl[(start + i) % #tl + 1] end
		catch[st] = list
		comps[st] = { STATION = { terminals = { { cargoUnload = true }, { cargoUnload = r(4) > 0 } } } }
		comps[g] = { STATION_GROUP = { stations = { st } } }
		groups[#groups + 1] = g
	end
	for l = 1, 40 * k do
		local le = id()
		local stops = {}
		for i = 1, 3 do
			local load = {}
			for c = 1, NCARGO do load[c] = false end
			load[CARGOS[1 + r(#CARGOS)] + 1] = true
			local g = groups[1 + r(#groups)]
			stops[i] = { stationGroup = g, station = 0, terminal = r(2), stopConfig = { load = load } }
			lineStops[g] = lineStops[g] or {}
			table.insert(lineStops[g], { le, i - 1 })
		end
		comps[le] = { LINE = { stops = stops } }
	end
	return comps, town2b, stock, catch, lineStops, towns
end

local function fakeApi(comps, town2b, stock, catch, lineStops, calls)
	local function n(kind) calls[kind] = (calls[kind] or 0) + 1 end
	local function copyMap(m)
		local out = {}
		for key, list in pairs(m) do
			local l = {}
			for i = 1, #list do l[i] = list[i] end
			out[key] = l
		end
		return out
	end
	return {
		gui = {
			mission = {
				setMarkerAtEntity = function() n("setMarker") end,
				removeMarker = function() n("removeMarker") end,
			},
		},
		res = { cargoTypeRep = {
			getPassengerCargoTypeId = function() return PASS end,
			get = function(c) return { name = "C" .. c, icon = "ui/c" .. c .. ".tga" } end,
		} },
		type = {
			ComponentType = setmetatable({}, { __index = function(_, key) return key end }),
			enum = { StockListType = { InputStock = 0, OutputStock = 1 } },
		},
		engine = {
			getComponent = function(e, ct)
				n(ct)
				return (comps[e] or {})[ct]
			end,
			system = {
				lineSystem = { getStationGroup2LineStopsMap = function() n("lineStopsMap") return copyMap(lineStops) end },
				townBuildingSystem = { getTown2BuildingMap = function() n("town2BuildingMap") return copyMap(town2b) end },
				simEntityAtStockSystem = { getStockCount = function(sl) n("getStockCount") return stock[sl] or 0 end },
				catchmentAreaSystem = { getStationCatchables = function(st)
					n("getStationCatchables")
					local l = catch[st] or {}
					local out = {}
					for i = 1, #l do out[i] = l[i] end
					return out
				end },
			},
		},
	}
end

local function fmtCalls(calls, ticks)
	local keys = {}
	for key in pairs(calls) do keys[#keys + 1] = key end
	table.sort(keys)
	local parts = {}
	for _, key in ipairs(keys) do parts[#parts + 1] = key .. "=" .. string.format("%.0f", calls[key] / ticks) end
	return table.concat(parts, " ")
end

local function run(k, scoped, label)
	local comps, town2b, stock, catch, lineStops, towns = world(k)
	local calls = {}
	set_global("api", fakeApi(comps, town2b, stock, catch, lineStops, calls))
	overlay.shutdown()
	overlay.session.scoped = scoped
	-- camera over town 12's area (a few towns in view)
	local cx, cy = 4000, 2000
	overlay.readCamera = function()
		return { cx = cx, cy = cy, distance = 1500, poly = scope.square(cx, cy, 1500), hits = 4, fallback = false }
	end
	local t0 = os.clock()
	overlay.tick("timer")
	local first = (os.clock() - t0) * 1000
	local firstCalls = fmtCalls(calls, 1)
	for key in pairs(calls) do calls[key] = nil end
	local N = 60
	local sum, max = 0, 0
	for i = 1, N do
		local a = os.clock()
		overlay.tick("timer")
		local ms = (os.clock() - a) * 1000
		sum = sum + ms
		if ms > max then max = ms end
	end
	local steadyCalls = fmtCalls(calls, N)
	for key in pairs(calls) do calls[key] = nil end
	-- panning: the camera moves 40 m a tick
	local psum, pmax = 0, 0
	for i = 1, N do
		cx = cx + 40
		local a = os.clock()
		overlay.tick("timer")
		local ms = (os.clock() - a) * 1000
		psum = psum + ms
		if ms > pmax then pmax = ms end
	end
	print(string.format("%s x%d %s: first %.1f ms | steady avg %.2f max %.2f ms | panning avg %.2f max %.2f ms | gaps %d",
		label, k, scoped and "scoped" or "map", first, sum / N, max, psum / N, pmax, overlay.view and overlay.view.total or -1))
	print("   first-tick calls: " .. firstCalls)
	print("   steady calls/tick: " .. steadyCalls)
	print("   panning calls/tick: " .. fmtCalls(calls, N))
	for _, e in ipairs(log_entries()) do if e.msg:find("PERF", 1, true) then print("   " .. e.msg) end end
	clear_logs()
end

test("bench (SQSG_BENCH=1 to run)", function()
	if os.getenv("SQSG_BENCH") ~= "1" then return end
	overlay.clock = function() return os.clock() end
	for _, k in ipairs({ 1, 5 }) do
		run(k, true, "bench")
		run(k, false, "bench")
	end
	overlay.shutdown()
end)
