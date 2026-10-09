-- Problem Radar checks (PLAN "Architecture": radar_checks.tl; Phase 2 "game-flag alerts",
-- Phase 3 "inferred alerts": veh_stuck, train_blocked_by, fleet_old, fleet_idle_depot;
-- Phase 4 "line quality": line_overloaded, line_underused, line_bunching; Phase 7 "economy":
-- line_unprofitable, line_low_use and the utilisation averages behind the latter).
-- PURE: no api.*, no base modules. Every function takes plain tables that the engine script's
-- gather layer (radar.script.tl) already fetched from the API, and returns {ProblemRadarAlert}.
-- Unit-tested offline: tests/square_problem_radar/test_checks.lua.
--
-- Alerts are language-neutral (codes + game names); radar_hud_model.tl translates them.
-- Ownership: only the player's entities produce alerts (base notifications.script.tl filters
-- vehicles/lines by PLAYER_OWNED, station groups by "a player line stops here", l.588-637).

local radar_settings = ug_require "square_problem_radar::/radar/radar_settings.tl" as ProblemRadarSettingsModule

local checks : ProblemRadarChecks = {}

checks.STATE_VERSION = 6
checks.MAX_STORED_ALERTS = 300
-- Timer caps (save size: a few KB). Over the cap the oldest timers are kept, because they are the
-- ones closest to alerting; a vehicle left out simply starts its timer later (fewer alerts, never
-- false ones).
checks.MAX_STOPPED_TIMERS = 500
checks.MAX_BLOCKED_TIMERS = 200
checks.MAX_LINE_TIMERS = 300
-- Smoothing (settings.smoothSec): at most this many not-yet-listed (pending) alerts are stored; over
-- the cap the oldest are kept, a newer one just starts its window later (never a false alert).
checks.MAX_PENDING_ALERTS = 200
-- line_overloaded: below this many waiting a stop never counts (a 10-seat bus with 31 waiting is
-- not a network problem worth a row).
checks.MIN_OVERLOAD_WAITING = 50
-- Hysteresis for the Phase 4 timers: a condition starts at its threshold and, once its timer runs,
-- holds while the value stays within this fraction of it (overload: ratio >= 0.75 x factor;
-- underuse: pct < pct / 0.75; clump: headway < clump / 0.75; gap: gap >= 0.75 x gap threshold).
-- One noisy sample near the threshold then does not restart the sustain timer.
checks.HOLD_FRACTION = 0.75
-- Base vehicle-condition notification: <= 0.2, kept while <= 0.3
-- (.cache/game/base/content/game_mechanics/notifications/notifications.script.tl:311).
-- Defaults only: Phase 5 makes the threshold a setting (radar_settings wornPct, wornThresholds).
checks.WORN_THRESHOLD = 0.2
checks.WORN_CLEAR_THRESHOLD = 0.3
-- Phase 7 economy. line_unprofitable: "consistently" = the 12-month balance is negative AND at least
-- this many of its 4 quarters are.
checks.ECON_MIN_NEG_QUARTERS = 3
-- line_unprofitable (2026-10-07 perf review): a line's money is re-checked at most this many times per
-- game year (a game month apart). It is a trailing 12-month figure, so a month moves it little; the
-- rotating cursor only brings due lines (checks.dueRotation).
checks.ECON_RECHECKS_PER_YEAR = 12
-- line_low_use: at most this many lines carry a utilisation average (save size: 3 integers each);
-- over the cap the longest-tracked are kept and a new line is simply not tracked yet.
checks.MAX_USE_TRACKED = 1000
-- A line is judged once its average covers this fraction of a game year (half a year: waiting a full
-- year would show nothing for a year after the mod is added; the average is bias-corrected, so half a
-- year of samples is already a fair mean, just a less smoothed one).
checks.USE_MIN_TRACK_FRACTION = 0.5
-- Snooze (state.snoozed): at most this many snoozed alerts (save size); over the cap the ones ending
-- last are kept. The window's snooze length presets, in game months.
checks.MAX_SNOOZED = 200
checks.SNOOZE_MONTHS = { 1, 6, 12, 60 }

-- Catalogue (PLAN "Alert catalogue"). Critical = 1, Warning = 2, Info = 3. Phase 7 economy kinds set
-- each row's tier by the size of the problem (Info .. maxTier); `tier` is their mildest tier.
checks.KINDS = {
	veh_blocked = { tab = "vehicles", tier = 1, group = "vehicles" },
	veh_nopath = { tab = "vehicles", tier = 1, group = "vehicles" },
	line_broken = { tab = "lines", tier = 1, group = "lines" },
	line_no_vehicles = { tab = "lines", tier = 1, group = "lines" },
	line_cargo_issue = { tab = "lines", tier = 2, group = "lines" },
	line_cargo_not_unloaded = { tab = "lines", tier = 2, group = "lines" },
	station_overcrowded = { tab = "stations", tier = 2, group = "stations" },
	station_useless = { tab = "stations", tier = 3, group = "stations" },
	fleet_worn = { tab = "fleet", tier = 3, group = "fleet" },
	veh_stuck = { tab = "vehicles", tier = 1, group = "vehicles" },
	train_blocked_by = { tab = "vehicles", tier = 2, group = "vehicles" },
	fleet_old = { tab = "fleet", tier = 3, group = "fleet" },
	fleet_idle_depot = { tab = "fleet", tier = 3, group = "fleet" },
	line_overloaded = { tab = "lines", tier = 2, group = "lines" },
	line_underused = { tab = "lines", tier = 3, group = "lines" },
	line_bunching = { tab = "lines", tier = 2, group = "lines" },
	line_unprofitable = { tab = "economy", tier = 3, maxTier = 1, group = "lines" },
	line_low_use = { tab = "economy", tier = 3, maxTier = 1, group = "lines" },
}

checks.GROUPS = { "lines", "stations", "vehicles", "fleet" }

checks.GROUP_KINDS = {
	lines = { "line_broken", "line_no_vehicles", "line_cargo_issue", "line_cargo_not_unloaded", "line_overloaded", "line_underused", "line_bunching",
		"line_unprofitable", "line_low_use" },
	stations = { "station_overcrowded", "station_useless" },
	vehicles = { "veh_blocked", "veh_nopath", "veh_stuck", "train_blocked_by" },
	fleet = { "fleet_worn", "fleet_old", "fleet_idle_depot" },
}

---------------------------------------------------------------------------
-- State

function checks.freshMemory() : ProblemRadarMemory
	return { stoppedSince = {}, blockedSince = {}, blockedBy = {}, overloadSince = {}, underusedSince = {}, bunchingSince = {}, useAvg = {} }
end

function checks.patchMemory(memory : ProblemRadarMemory, patch : ProblemRadarMemory) : ProblemRadarMemory
	local out = checks.freshMemory()
	local o = out as {string : any}
	if type(memory) == "table" then
		for k, v in pairs(memory as {string : any}) do o[k] = v end
	end
	if type(patch) == "table" then
		for k, v in pairs(patch as {string : any}) do o[k] = v end
	end
	return out
end

function checks.freshState() : ProblemRadarState
	return { version = checks.STATE_VERSION, settings = radar_settings.defaults(), alerts = {}, total = 0, kindCounts = {},
		memory = checks.freshMemory(), notified = {}, notifyCleared = {}, tierCounts = { 0, 0, 0 } }
end

local function toInt(v : any) : integer
	if type(v) ~= "number" then return nil end
	return math.floor(v as number)
end

local function optString(v : any) : string
	return type(v) == "string" and v as string or ""
end

-- Whole numbers (pre-5.3 Lua: no math.type; a save may hand back floats). Module level: validSnooze
-- runs for every snooze on every upgradeState (twice per scan slot), so no closure per entry.
local function whole(x : any) : boolean return type(x) == "number" and x as number == math.floor(x as number) end

local function validSnooze(k : any, v : any) : boolean
	if type(k) ~= "string" or type(v) ~= "table" then return false end
	local z = v as {string : any}
	return whole(z.untilMs) and type(z.kind) == "string" and type(z.label) == "string"
		and type(z.etype) == "string" and type(z.context) == "string" and (z.entity == nil or whole(z.entity))
end

function checks.cleanSnoozed(m : any) : {string : ProblemRadarSnooze}
	if type(m) ~= "table" then return nil end
	-- Already clean and within the cap (every scan and event sees the saved map): no copy.
	local n, clean = 0, true
	for k, v in pairs(m as {any : any}) do
		n = n + 1
		if not validSnooze(k, v) then clean = false break end
	end
	if clean and n > 0 and n <= checks.MAX_SNOOZED then return m as {string : ProblemRadarSnooze} end
	local out : {string : ProblemRadarSnooze} = {}
	local ids : {string} = {}
	for k, v in pairs(m as {any : any}) do
		local z = type(v) == "table" and v as ProblemRadarSnooze or nil
		local untilMs = z ~= nil and toInt(z.untilMs) or nil
		if type(k) == "string" and untilMs ~= nil and type(z.kind) == "string" then
			out[k as string] = { untilMs = untilMs, kind = z.kind, label = optString(z.label), etype = optString(z.etype),
				context = optString(z.context), entity = toInt(z.entity) }
			ids[#ids + 1] = k as string
		end
	end
	if #ids == 0 then return nil end
	if #ids <= checks.MAX_SNOOZED then return out end
	table.sort(ids, function(a : string, b : string) : boolean
		if out[a].untilMs ~= out[b].untilMs then return out[a].untilMs > out[b].untilMs end
		return a < b
	end)
	local capped : {string : ProblemRadarSnooze} = {}
	for i = 1, checks.MAX_SNOOZED do capped[ids[i]] = out[ids[i]] end
	return capped
end

--- The alerts that count (not snoozed).
local function unsnoozed(alerts : {ProblemRadarAlert}, snoozed : {string : ProblemRadarSnooze}) : {ProblemRadarAlert}
	if snoozed == nil then return alerts end
	local out : {ProblemRadarAlert} = {}
	for __, a in ipairs(alerts) do
		if type(a) ~= "table" or snoozed[a.id] == nil then out[#out + 1] = a end
	end
	return out
end

-- v3 memory: the vehicle timers only.
local function validV3Memory(m : any) : boolean
	if type(m) ~= "table" then return false end
	local t = m as ProblemRadarMemory
	return type(t.stoppedSince) == "table" and type(t.blockedSince) == "table" and type(t.blockedBy) == "table"
end

-- v4 / v5 memory: + the line timers (v4 also had lineCursor, dropped in v5). v6 adds useAvg.
local function validV4Memory(m : any) : boolean
	if not validV3Memory(m) then return false end
	local t = m as ProblemRadarMemory
	return type(t.overloadSince) == "table" and type(t.underusedSince) == "table"
		and type(t.bunchingSince) == "table"
end

local MEMORY_KEYS <const> = { "stoppedSince", "blockedSince", "blockedBy", "overloadSince", "underusedSince", "bunchingSince", "useAvg" }

-- v6 memory: exactly the six timer maps and the utilisation averages (no leftover v4 lineCursor).
local function validMemory(m : any) : boolean
	if not validV4Memory(m) or type((m as ProblemRadarMemory).useAvg) ~= "table" then return false end
	local n = 0
	for __ in pairs(m as {any : any}) do n = n + 1 end
	return n == #MEMORY_KEYS
end

--- The maps of a v3/v4/v5 memory (missing ones fresh, e.g. v6's useAvg); drops v4's lineCursor.
local function timersOf(m : ProblemRadarMemory) : ProblemRadarMemory
	local out = checks.freshMemory()
	local o = out as {string : any}
	local t = m as {string : any}
	for __, k in ipairs(MEMORY_KEYS) do
		if type(t[k]) == "table" then o[k] = t[k] end
	end
	return out
end

function checks.upgradeState(s : any) : ProblemRadarState, boolean
	if type(s) ~= "table" then return checks.freshState(), true end
	local t = s as ProblemRadarState
	local version = toInt(t.version)
	local n = checks.freshState()
	n.settings = radar_settings.normalize(t.settings)
	local changed = version ~= checks.STATE_VERSION or not radar_settings.same(t.settings, n.settings)
	local current = version == checks.STATE_VERSION
	if current or version == 5 or version == 4 or version == 3 or version == 2 then
		-- v2..v6 share the alert schema: keep the alert data as is (the GUI model sanitises
		-- each alert). v2 -> v6 adds memory (fresh: the stuck timers start now); v3 -> v6 keeps the
		-- vehicle timers and adds empty line timers; v4 -> v6 keeps every timer and drops lineCursor.
		-- v5 added the notify maps (empty: alerts already listed may toast once, capped). v5 -> v6
		-- keeps everything and adds the empty utilisation averages and the tier counts.
		if type(t.alerts) == "table" then n.alerts = t.alerts else changed = true end
		if type(t.kindCounts) == "table" then n.kindCounts = t.kindCounts else changed = true end
		n.total = toInt(t.total)
		if n.total == nil then
			n.total = #n.alerts
			changed = true
		end
		if current and validMemory(t.memory) then
			-- Kept as is (no per-scan copy); updateStopped/updateBlocked/reconcileUseAvg sanitise every
			-- entry they read.
			n.memory = t.memory
		elseif ((version == 3 or version == 4) and validV3Memory(t.memory))
			or ((version == 5 or current) and validV4Memory(t.memory)) then
			-- v3/v4: the timer maps it has (missing line maps fresh); v5: the six timer maps + empty
			-- useAvg; v6 with extra keys (a leftover lineCursor) or no useAvg: the known maps only.
			n.memory = timersOf(t.memory)
			changed = true
		elseif current then
			changed = true
		end
		if current or version == 5 then
			-- Kept as is; radar_notify sanitises every entry it reads.
			if type(t.notified) == "table" then n.notified = t.notified else changed = true end
			if type(t.notifyCleared) == "table" then n.notifyCleared = t.notifyCleared else changed = true end
			-- Smoothing (optional, lazy): not-yet-listed alerts. Missing (older v5 saves, or nothing
			-- pending) is valid and not a change; merge sanitises every entry it reads. Alerts
			-- already listed in the save stay listed: they are in `alerts`, never pending.
			if type(t.pending) == "table" then n.pending = t.pending end
			-- Snooze (optional, lazy like pending): sanitised; missing is valid and not a change.
			n.snoozed = checks.cleanSnoozed(t.snoozed)
			n.seq = toInt(t.seq)
		end
		-- v6 tier counts: kept when valid, else rebuilt from the alerts and kind counts.
		local tc = t.tierCounts as {any}
		if current and type(tc) == "table" and type(tc[1]) == "number" and type(tc[2]) == "number" and type(tc[3]) == "number" then
			n.tierCounts = t.tierCounts
		else
			n.tierCounts = checks.tierCounts(unsnoozed(n.alerts, n.snoozed), n.kindCounts)
			changed = true
		end
	end
	-- v1 (Phase 1) and unknown versions: settings kept, alerts dropped (v1 never stored any;
	-- the alert schema changed). The next scans rebuild them.
	return n, changed
end

---------------------------------------------------------------------------
-- Helpers

local function str(v : string) : string
	return v or ""
end

local function posOf(p : {number}) : {number}
	if p == nil or type(p[1]) ~= "number" or type(p[2]) ~= "number" or type(p[3]) ~= "number" then return nil end
	if p[1] == 0 and p[2] == 0 and p[3] == 0 then return nil end -- no location
	return { p[1], p[2], p[3] }
end

local function newAlert(kind : string, id : string, entity : integer) : ProblemRadarAlert
	local k = checks.KINDS[kind]
	return {
		id = kind .. ":" .. id,
		kind = kind,
		tab = k.tab,
		tier = k.tier,
		entity = entity,
		etype = "",
		label = "",
		context = "",
		code = "",
		firstSeen = 0,
	}
end

local function sortedKeys(m : {integer : any}) : {integer}
	local keys : {integer} = {}
	for k in pairs(m) do keys[#keys + 1] = k end
	table.sort(keys)
	return keys
end

---------------------------------------------------------------------------
-- Relaxation (which network piece is missing on a path problem).
-- Same rules as base line_util.getRelaxationType
-- (.cache/game/base/content/gui/line_vehicle_mgmt/line_util.tl:1966-2014), on TransportMode names.

local function any(set : {string : boolean}, names : {string}) : boolean
	for __, n in ipairs(names) do
		if set[n] then return true end
	end
	return false
end

local TRAM <const> = { "ELECTRIC_TRAM", "TRAM" }
local TRAIN <const> = { "ELECTRIC_TRAIN", "TRAIN" }
local TRAM_TRACK <const> = { "ELECTRIC_TRAM_TRACK", "TRAM_TRACK" }
local ROAD <const> = { "CAR", "BUS", "TRUCK" }
local CATENARY <const> = { "ELECTRIC_TRAM", "ELECTRIC_TRAIN", "ELECTRIC_TRAM_TRACK" }

function checks.relaxationType(ok : {string : boolean}, relaxed : {string : boolean}, allowed : {string : boolean}) : string
	if ok == nil or relaxed == nil or allowed == nil then return nil end
	local wasTram, wasTrain, wasTramTrack, wasRoad = any(ok, TRAM), any(ok, TRAIN), any(ok, TRAM_TRACK), any(ok, ROAD)
	local asTram, asTrain, asTramTrack, asRoad = any(relaxed, TRAM), any(relaxed, TRAIN), any(relaxed, TRAM_TRACK), any(relaxed, ROAD)
	local allowedTram = any(allowed, TRAM)
	local asAllowed = (asTram and allowedTram) or (asTrain and any(allowed, TRAIN))
		or (asTramTrack and any(allowed, TRAM_TRACK)) or (asRoad and any(allowed, ROAD))
	if not asAllowed then
		if wasTram and not asTram then return "TramLanes" end
		if wasTrain and not asTrain then return "Train" end
		if wasTramTrack and not asTramTrack then return allowedTram and "TramLanes" or "TramTrack" end
		if wasRoad and not asRoad then return "Road" end
	end
	if any(ok, CATENARY) and not any(relaxed, CATENARY) then return "Catenary" end
	return nil
end

---------------------------------------------------------------------------
-- Lines: line_broken, line_no_vehicles, line_cargo_issue, line_cargo_not_unloaded

local RELAXED_PROBLEMS <const> : {string : boolean} = { NO_PATH = true, BAD_ALTERNATIVE_TERMINAL = true }

function checks.lines(input : ProblemRadarLinesInput) : {ProblemRadarAlert}
	local out : {ProblemRadarAlert} = {}
	local lines = input.lines or {}
	local broken : {integer : boolean} = {}

	for __, p in ipairs(input.problems or {}) do
		local info = lines[p.line]
		if info ~= nil and info.owned and p.code ~= nil and p.code ~= "NOTHING" and not broken[p.line] then
			broken[p.line] = true -- first problem per line (base lists one per line too)
			local a = newAlert("line_broken", tostring(p.line), p.line)
			a.etype = "Line"
			a.label = str(info.name)
			a.code = p.code
			if RELAXED_PROBLEMS[p.code] then
				a.arg = checks.relaxationType(p.okModes, p.relaxedModes, p.allowedModes)
			end
			a.pos = posOf(p.pos)
			out[#out + 1] = a
		end
	end

	local noVehicles : {integer : boolean} = {}
	for __, line in ipairs(sortedKeys(lines)) do
		local info = lines[line]
		-- A broken line can't take vehicles anyway: line_broken already says what to fix.
		if info.owned and (info.stops or 0) >= 2 and (info.vehicles or 0) == 0 and not broken[line] then
			noVehicles[line] = true
			local a = newAlert("line_no_vehicles", tostring(line), line)
			a.etype = "Line"
			a.label = str(info.name)
			a.code = "NoVehicles"
			a.arg = tostring(info.stops)
			out[#out + 1] = a
		end
	end

	local issues = input.issues or {}
	for __, line in ipairs(sortedKeys(issues)) do
		local list = issues[line]
		local info = lines[line]
		if noVehicles[line] then
			-- "No vehicle can transport the configured cargo" on a line without any vehicle says the
			-- same as its line_no_vehicles row: drop that issue (other issues of the line stay).
			local rest : {ProblemRadarLineIssue} = {}
			for __, issue in ipairs(list) do
				if issue.code ~= "NoVehicleToLoadCargo" then rest[#rest + 1] = issue end
			end
			list = rest
		end
		if info ~= nil and info.owned and #list > 0 then
			local a = newAlert("line_cargo_issue", tostring(line), line)
			a.etype = "Line"
			a.label = str(info.name)
			a.code = str(list[1].code)
			a.arg = list[1].cargo
			if #list > 1 then a.metric = "+" .. tostring(#list - 1) end
			out[#out + 1] = a
		end
	end

	-- line_cargo_not_unloaded: the base cargo_rtc_warning raises one notification per vehicle in
	-- getVehiclesWithRoundTripCount() (notifications.script.tl:277-290); here one row per owned line,
	-- counting its vehicles and their cargo. Vehicles without a known (owned) line are skipped.
	local roundTrips = input.roundTrips or {}
	local vehicleLines = input.vehicleLines or {}
	local perLine : {integer : {integer}} = {} -- line -> { vehicles, cargo }
	for v, count in pairs(roundTrips) do
		local line = vehicleLines[v]
		local info = line ~= nil and lines[line] or nil
		local n = toInt(count)
		if info ~= nil and info.owned and n ~= nil and n > 0 then
			local p = perLine[line]
			if p == nil then
				p = { 0, 0 }
				perLine[line] = p
			end
			p[1] = p[1] + 1
			p[2] = p[2] + n
		end
	end
	for __, line in ipairs(sortedKeys(perLine)) do
		local p = perLine[line]
		local a = newAlert("line_cargo_not_unloaded", tostring(line), line)
		a.etype = "Line"
		a.label = str(lines[line].name)
		a.code = "RoundTrip"
		a.arg = tostring(p[1]) .. "|" .. tostring(p[2]) -- "<vehicles>|<cargo>"
		a.metric = tostring(p[1]) .. " veh · " .. tostring(p[2])
		out[#out + 1] = a
	end
	return out
end

---------------------------------------------------------------------------
-- Stations: station_overcrowded, station_useless

function checks.stations(input : ProblemRadarStationsInput) : {ProblemRadarAlert}
	local out : {ProblemRadarAlert} = {}
	local groups = input.groups or {}
	local lines = input.lines or {}

	for __, sg in ipairs(sortedKeys(groups)) do
		local g = groups[sg]
		if g.owned and g.overflow then
			local a = newAlert("station_overcrowded", tostring(sg), sg)
			a.etype = "Station"
			a.label = str(g.name)
			a.code = "Overcrowded"
			if g.used ~= nil and g.capacity ~= nil then
				a.metric = tostring(math.floor(g.used)) .. "/" .. tostring(math.floor(g.capacity))
			end
			out[#out + 1] = a
		end
	end

	local seen : {string : boolean} = {}
	for __, p in ipairs(input.lineStationProblems or {}) do
		local line = lines[p.line]
		if line ~= nil and line.owned and p.code ~= nil then
			local a = newAlert("station_useless", tostring(p.stationGroup) .. ":" .. tostring(p.line) .. ":" .. p.code, p.stationGroup)
			if not seen[a.id] then
				seen[a.id] = true
				local g = groups[p.stationGroup]
				a.entity2 = p.line
				a.etype = "Station"
				a.label = g ~= nil and str(g.name) or ""
				a.context = str(line.name)
				a.code = p.code
				out[#out + 1] = a
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Vehicles: veh_blocked, veh_nopath

local function vehicleAlert(kind : string, id : string, v : integer, info : ProblemRadarVehicleInfo) : ProblemRadarAlert
	local a = newAlert(kind, id, v)
	a.etype = str(info.etype)
	a.label = str(info.name)
	a.context = str(info.lineName)
	return a
end

function checks.vehicles(input : ProblemRadarVehiclesInput) : {ProblemRadarAlert}
	local out : {ProblemRadarAlert} = {}
	local vehicles = input.vehicles or {}
	local failures = input.failures or {}
	local nopath : {integer : boolean} = {}

	local function owned(v : integer) : boolean
		local info = vehicles[v]
		return info ~= nil and info.owned
	end

	local function addNoPath(v : integer, code : string)
		if nopath[v] or not owned(v) then return end
		nopath[v] = true
		local a = vehicleAlert("veh_nopath", tostring(v), v, vehicles[v])
		a.code = code
		local f = failures[v]
		if f ~= nil then
			a.arg = f.reason
			a.pos = posOf(f.pos)
		end
		out[#out + 1] = a
	end

	local blockedSeen : {string : boolean} = {}
	for __, p in ipairs(input.problems or {}) do
		local vs : {integer} = {}
		for __, v in ipairs(p.vehicles or {}) do vs[#vs + 1] = v end
		table.sort(vs)
		if p.code == "Blocked" then
			-- One alert per blocking pair; the first owned train is the row's entity.
			local first : integer = nil
			for __, v in ipairs(vs) do
				if owned(v) then first = v break end
			end
			if first ~= nil then
				local other : integer = nil
				for __, v in ipairs(vs) do
					if v ~= first then other = v break end
				end
				local key = tostring(vs[1]) .. (vs[2] ~= nil and (":" .. tostring(vs[2])) or "")
				if not blockedSeen[key] then
					blockedSeen[key] = true
					local a = vehicleAlert("veh_blocked", key, first, vehicles[first])
					a.code = "Blocked"
					if other ~= nil then
						a.entity2 = other
						local o = vehicles[other]
						a.arg = o ~= nil and o.name or nil
					end
					out[#out + 1] = a
				end
			end
		elseif p.code ~= nil then
			for __, v in ipairs(vs) do addNoPath(v, p.code) end
		end
	end

	local np : {integer} = {}
	for __, v in ipairs(input.noPath or {}) do np[#np + 1] = v end
	table.sort(np)
	for __, v in ipairs(np) do addNoPath(v, "NoPath") end
	return out
end

---------------------------------------------------------------------------
-- Fleet: fleet_worn, fleet_old, fleet_idle_depot

-- Default calendar year in game ms if the engine gave none: lifespan units are quarter days at
-- normal calendar speed (docs/wiki/modding/general/resourcetypes/mdl.md:293) and getLifespan
-- multiplies them by 1000 (vehicle_util.tl:31-34), so a year is 365 * 4 * 1000 ms.
local DEFAULT_YEAR_MS <const> = 365 * 4 * 1000

local function copyAlert(a : ProblemRadarAlert) : ProblemRadarAlert
	local c : ProblemRadarAlert = {}
	for k, v in pairs(a as {string : any}) do (c as {string : any})[k] = v end
	return c
end

function checks.fleet(input : ProblemRadarFleetInput) : {ProblemRadarAlert}
	local out : {ProblemRadarAlert} = {}
	local vehicles = input.vehicles or {}
	local prev = input.prevIds or {}
	local yearMs = (input.yearMs ~= nil and input.yearMs > 0) and input.yearMs or DEFAULT_YEAR_MS
	local idleDays = input.idleDays or radar_settings.NUMBERS.idleDepotDays.default
	local wornAt = input.wornThreshold or checks.WORN_THRESHOLD
	local wornClear = input.wornClear or checks.WORN_CLEAR_THRESHOLD
	local oldDone : {integer : boolean} = {}
	for __, v in ipairs(sortedKeys(vehicles)) do
		local info = vehicles[v]
		local c = info.condition
		if info.owned and c ~= nil then
			local id = "fleet_worn:" .. tostring(v)
			if c <= wornAt or (prev[id] and c <= wornClear) then
				local a = vehicleAlert("fleet_worn", tostring(v), v, info)
				a.code = "Worn"
				a.metric = tostring(math.floor(c * 100 + 0.5)) .. "%"
				out[#out + 1] = a
			end
		end
		-- vehicle_util.getAge (vehicle_util.tl:297-315): age of the oldest part vs that part's
		-- lifespan. Lifespan 0 means "no lifespan" (never old).
		local age, life = info.ageMs, info.lifespanMs
		if info.owned and age ~= nil and life ~= nil then
			oldDone[v] = true
			if life > 0 and age > life then
				local a = vehicleAlert("fleet_old", tostring(v), v, info)
				a.code = "Old"
				a.arg = tostring(math.floor(age / yearMs)) .. "/" .. tostring(math.floor(life / yearMs + 0.5))
				a.metric = tostring(math.floor(age / life * 100 + 0.5)) .. "%"
				out[#out + 1] = a
			end
		end
		local days = info.daysInDepot
		if info.owned and days ~= nil and days >= idleDays then
			local a = vehicleAlert("fleet_idle_depot", tostring(v), v, info)
			a.code = "InDepot"
			a.context = str(info.depotName)
			a.arg = tostring(math.floor(days))
			a.metric = tostring(math.floor(days)) .. "d"
			out[#out + 1] = a
		end
	end
	-- Ages are read for a slice of the fleet per pass; earlier fleet_old alerts of vehicles not read
	-- this pass stay (age only grows; renewal/selling is caught when their slice comes round).
	for __, a in ipairs(input.keepOld or {}) do
		local v = toInt(a.entity)
		if a.kind == "fleet_old" and v ~= nil and not oldDone[v] then
			oldDone[v] = true
			local c = copyAlert(a)
			c.carried = true -- not re-checked this pass (smoothing: no news)
			out[#out + 1] = c
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Timers (state.memory): veh_stuck and train_blocked_by need "since when", across save/load.

function checks.formatMinutes(ms : integer) : string
	local m = math.floor((ms or 0) / 60000)
	if m < 60 then return tostring(m) .. "m" end
	return string.format("%dh%02dm", m // 60, m % 60)
end

--- Keep the `cap` oldest entries of a since-map (ties by id).
local function capMap(m : {integer : integer}, n : integer, cap : integer) : {integer : integer}, {integer : boolean}
	if n <= cap then return m, nil end
	local ids : {integer} = {}
	for k in pairs(m) do ids[#ids + 1] = k end
	table.sort(ids, function(a : integer, b : integer) : boolean
		if m[a] ~= m[b] then return m[a] < m[b] end
		return a < b
	end)
	local out : {integer : integer} = {}
	local kept : {integer : boolean} = {}
	for i = 1, cap do
		out[ids[i]] = m[ids[i]]
		kept[ids[i]] = true
	end
	return out, kept
end

local function sameMap(a : {integer : integer}, b : any) : boolean
	if type(b) ~= "table" then return false end
	local t = b as {any : any}
	local n = 0
	for k, v in pairs(a) do
		n = n + 1
		if toInt(t[k]) ~= v then return false end
	end
	for __ in pairs(t) do n = n - 1 end
	return n == 0
end

function checks.updateStopped(prev : {integer : integer}, standing : {integer : any}, now : integer, cap? : integer) : {integer : integer}, boolean
	local p = type(prev) == "table" and prev or {}
	local out : {integer : integer} = {}
	local n = 0
	for v in pairs(standing or {}) do
		local since = toInt(p[v])
		if since == nil or since > now then since = now end
		out[v] = since
		n = n + 1
	end
	out = capMap(out, n, cap or checks.MAX_STOPPED_TIMERS)
	return out, not sameMap(out, prev)
end

function checks.updateBlocked(prevSince : {integer : integer}, prevBy : {integer : integer}, pairs_ : {{integer}}, now : integer, cap? : integer) : {integer : integer}, {integer : integer}, boolean
	local ps = type(prevSince) == "table" and prevSince or {}
	local pb = type(prevBy) == "table" and prevBy or {}
	local since : {integer : integer} = {}
	local by : {integer : integer} = {}
	local n = 0
	for __, pair in ipairs(pairs_ or {}) do
		local blocked, blocker = toInt(pair[1]), toInt(pair[2])
		-- One blocker per train: the lowest id, so the choice is stable between scans.
		if blocked ~= nil and blocker ~= nil and blocked ~= blocker and (by[blocked] == nil or blocker < by[blocked]) then
			if by[blocked] == nil then n = n + 1 end
			by[blocked] = blocker
		end
	end
	for blocked, blocker in pairs(by) do
		local s = toInt(ps[blocked])
		if s == nil or s > now or toInt(pb[blocked]) ~= blocker then s = now end
		since[blocked] = s
	end
	local kept : {integer : boolean}
	since, kept = capMap(since, n, cap or checks.MAX_BLOCKED_TIMERS)
	if kept ~= nil then
		local b2 : {integer : integer} = {}
		for k in pairs(kept) do b2[k] = by[k] end
		by = b2
	end
	return since, by, not (sameMap(since, prevSince) and sameMap(by, prevBy))
end

checks.sameTimerMap = sameMap

-- Save churn (state:set serialises the whole state): on a busy network vehicles stop at junctions,
-- signals and in short jams all the time, so the full stopped / blocked maps change on nearly every
-- vehicles pass. Only timers at least this old are saved in state.memory; younger ones live in the
-- engine script's module-local copy. After a load a vehicle that had stood less than this simply
-- starts its timer again (at most this much later; the smallest stuck threshold is 1 minute).
checks.PERSIST_TIMER_AFTER_MS = 30 * 1000

function checks.agedTimers(since : {integer : integer}, now : integer, minAge : integer, by? : {integer : integer}) : {integer : integer}, {integer : integer}
	local out : {integer : integer} = {}
	local outBy : {integer : integer} = by ~= nil and {} or nil
	for k, t in pairs(since or {}) do
		if now - t >= minAge then
			out[k] = t
			if outBy ~= nil then outBy[k] = by[k] end
		end
	end
	return out, outBy
end

function checks.withYoungTimers(saved : {integer : integer}, savedBy : {integer : integer}, live : {integer : integer},
		liveBy : {integer : integer}, liveAt : integer, now : integer, minAge : integer) : {integer : integer}, {integer : integer}
	local out : {integer : integer} = {}
	local outBy : {integer : integer} = {}
	for k, t in pairs(type(saved) == "table" and saved or {}) do out[k] = t end
	for k, b in pairs(type(savedBy) == "table" and savedBy or {}) do outBy[k] = b end
	-- Live maps from a later game time than now: another (older) save was loaded; ignore them.
	if liveAt == nil or liveAt > now then return out, outBy end
	local lb = liveBy or {}
	for k, t in pairs(live or {}) do
		-- Only the entries that were too young to be saved when the live maps were made (an older one
		-- missing from the state was dropped there, e.g. kinds switched off, and must not come back).
		if out[k] == nil and t <= liveAt and liveAt - t < minAge then
			out[k] = t
			if lb[k] ~= nil then outBy[k] = lb[k] end
		end
	end
	return out, outBy
end

function checks.chainRoot(by : {integer : integer}, train : integer) : integer
	local seen : {integer : integer} = {}
	local order : {integer} = {}
	local cur = train
	while cur ~= nil do
		if seen[cur] ~= nil then
			-- cycle: the lowest id among the trains on it
			local root = cur
			for i = seen[cur], #order do
				if order[i] < root then root = order[i] end
			end
			return root
		end
		order[#order + 1] = cur
		seen[cur] = #order
		local nxt = by[cur]
		if nxt == nil then return cur end
		cur = nxt
	end
	return train
end

---------------------------------------------------------------------------
-- Vehicles (Phase 3): veh_stuck, train_blocked_by

function checks.stuck(input : ProblemRadarStuckInput) : {ProblemRadarAlert}
	local out : {ProblemRadarAlert} = {}
	local now = input.now or 0
	local thresholds = input.thresholds or {}
	local vehicles = input.vehicles or {}
	local excluded = input.excluded or {}
	local stoppedSince = input.stoppedSince or {}
	local blockedSince = input.blockedSince or {}
	local by = input.blockedBy or {}
	local railMs = thresholds.RAIL

	local function owned(v : integer) : boolean
		local info = vehicles[v]
		return info ~= nil and info.owned
	end

	-- veh_stuck: standing en route for at least the carrier's threshold. Trains in a blocked pair
	-- and trains waiting for a free path go to train_blocked_by instead.
	local waiting : {integer} = {}
	local standing = input.standing or {}
	for __, v in ipairs(sortedKeys(standing)) do
		local sv = standing[v]
		local since = toInt(stoppedSince[v])
		local limit = thresholds[sv.carrier]
		if since ~= nil and limit ~= nil and now - since >= limit and owned(v)
			and not excluded[v] and by[v] == nil and not sv.queueing then
			if sv.waitingForPath then
				waiting[#waiting + 1] = v
			else
				local a = vehicleAlert("veh_stuck", tostring(v), v, vehicles[v])
				a.code = sv.carrier
				a.arg = sv.nextStop ~= "" and sv.nextStop or nil
				a.metric = checks.formatMinutes(now - since)
				out[#out + 1] = a
			end
		end
	end

	if railMs == nil then return out end

	-- train_blocked_by: getBlockedTrains pairs blocked for at least the rail threshold, one alert
	-- per chain root (A behind B behind C -> one row: B waits for C, "+1" more queued).
	local groups : {integer : {integer}} = {}
	for __, b in ipairs(sortedKeys(by)) do
		local since = toInt(blockedSince[b])
		if since ~= nil and now - since >= railMs and owned(b) and not excluded[b] then
			local root = checks.chainRoot(by, b)
			local g = groups[root]
			if g == nil then
				g = {}
				groups[root] = g
			end
			g[#g + 1] = b
		end
	end
	for __, root in ipairs(sortedKeys(groups)) do
		local members = groups[root]
		-- Row entity: the eligible train directly behind the root that has waited longest; else the
		-- longest-waiting eligible train; in a cycle where only the root qualifies, the root itself.
		local best : integer = nil
		local bestDirect = false
		for __, m in ipairs(members) do
			if m ~= root then
				local direct = by[m] == root
				local better = best == nil
					or (direct and not bestDirect)
					or (direct == bestDirect and (toInt(blockedSince[m]) < toInt(blockedSince[best])
						or (toInt(blockedSince[m]) == toInt(blockedSince[best]) and m < best)))
				if better then
					best = m
					bestDirect = direct
				end
			end
		end
		local blocker = root
		if best == nil then
			best = root
			blocker = by[root]
		end
		local a = vehicleAlert("train_blocked_by", tostring(root), best, vehicles[best])
		a.code = "BlockedBy"
		a.entity2 = blocker
		local bi = vehicles[blocker]
		a.arg = bi ~= nil and bi.name ~= "" and bi.name or nil
		local metric = checks.formatMinutes(now - toInt(blockedSince[best]))
		if #members > 1 then metric = metric .. " +" .. tostring(#members - 1) end
		a.metric = metric
		out[#out + 1] = a
	end

	-- Trains waiting for a free path with no known blocker (signal waits that never clear).
	for __, v in ipairs(waiting) do
		local a = vehicleAlert("train_blocked_by", "w" .. tostring(v), v, vehicles[v])
		a.code = "WaitingForPath"
		local sv = standing[v]
		a.arg = sv.nextStop ~= "" and sv.nextStop or nil
		a.metric = checks.formatMinutes(now - toInt(stoppedSince[v]))
		out[#out + 1] = a
	end
	return out
end

---------------------------------------------------------------------------
-- Lines (Phase 4): line_overloaded, line_underused, line_bunching. See PLAN "Phase 4" for the
-- metric definitions; every threshold needs in-game tuning.

function checks.formatSeconds(sec : integer) : string
	local t = math.max(0, math.floor((sec or 0) + 0.5))
	if t >= 3600 then
		return string.format("%d:%02d:%02d", t // 3600, (t % 3600) // 60, t % 60)
	end
	return string.format("%d:%02d", t // 60, t % 60)
end

function checks.lineRotation(ids : {integer}, cursor : integer) : {integer}
	local sorted : {integer} = {}
	for __, id in ipairs(ids or {}) do sorted[#sorted + 1] = id end
	table.sort(sorted)
	local c = toInt(cursor) or -1
	local out : {integer} = {}
	for __, id in ipairs(sorted) do
		if id > c then out[#out + 1] = id end
	end
	for __, id in ipairs(sorted) do
		if id <= c then out[#out + 1] = id end
	end
	return out
end

local function median(xs : {integer}) : integer
	table.sort(xs)
	return xs[(#xs + 1) // 2]
end

function checks.headways(departures : {{integer}}, now : integer, intervalMs : integer, clumpMs : integer) : ProblemRadarHeadways
	local n = departures ~= nil and #departures or 0
	if n < 2 or intervalMs == nil or intervalMs <= 0 then return nil end
	-- A departure older than three round trips (n x interval) is not this cycle's: skip that stop.
	local stale = intervalMs * n * 3
	local stops = 0
	for __, d in ipairs(departures) do
		if type(d) == "table" and #d > stops then stops = #d end
	end
	local results : {{integer}} = {}   -- {minGap, maxGap, clump, span} per valid stop
	for s = 1, stops do
		local times : {integer} = {}
		local valid = true
		for __, d in ipairs(departures) do
			local t = type(d) == "table" and toInt(d[s]) or nil
			if t == nil or t <= 0 or t > now or now - t > stale then
				valid = false
				break
			end
			times[#times + 1] = t
		end
		if valid then
			table.sort(times)
			local minGap = times[2] - times[1]
			local maxGap = now - times[n] -- the gap still open since the last departure
			local bestClump, bestSpan = 1, 0
			local runStart = 1
			for i = 1, n - 1 do
				local h = times[i + 1] - times[i]
				if h < minGap then minGap = h end
				if h > maxGap then maxGap = h end
				if h >= clumpMs then runStart = i + 1 end
				local size = i + 1 - runStart + 1
				if size > bestClump then
					bestClump = size
					bestSpan = times[i + 1] - times[runStart]
				end
			end
			results[#results + 1] = { minGap, maxGap, bestClump, bestSpan }
		end
	end
	if #results == 0 then return nil end
	-- Median stop by smallest headway (its clump is reported), median of the largest gaps.
	table.sort(results, function(a : {integer}, b : {integer}) : boolean
		if a[1] ~= b[1] then return a[1] < b[1] end
		return a[3] > b[3]
	end)
	local mid = results[(#results + 1) // 2]
	local gaps : {integer} = {}
	for i, r in ipairs(results) do gaps[i] = r[2] end
	return {
		stopsUsed = #results,
		minGapMs = mid[1],
		maxGapMs = median(gaps),
		clump = mid[3],
		clumpSpanMs = mid[4],
	}
end

local function factorText(r : number) : string
	return string.format("%.1f×", r)
end

local QUALITY_KINDS <const> : {string : boolean} = { line_overloaded = true, line_underused = true, line_bunching = true }

--- The start time of a running timer, sanitised (nil if none; a future time clamps to now).
local function since(m : {integer : integer}, line : integer, now : integer) : integer
	local t = toInt(m[line])
	if t ~= nil and t > now then t = now end
	return t
end

function checks.lineQuality(input : ProblemRadarLineQualityInput) : {ProblemRadarAlert}, ProblemRadarMemory, boolean
	local out : {ProblemRadarAlert} = {}
	local now = input.now or 0
	local set = radar_settings.normalize(input.settings)
	local sustain = set.lineSustainMin * 60 * 1000
	local hold = checks.HOLD_FRACTION
	local mem = type(input.memory) == "table" and input.memory or checks.freshMemory()
	local prevO = type(mem.overloadSince) == "table" and mem.overloadSince or {}
	local prevU = type(mem.underusedSince) == "table" and mem.underusedSince or {}
	local prevB = type(mem.bunchingSince) == "table" and mem.bunchingSince or {}
	local eligible = input.eligible or {}
	local lines = input.lines or {}
	local newO : {integer : integer} = {}
	local newU : {integer : integer} = {}
	local newB : {integer : integer} = {}
	local nO, nU, nB = 0, 0, 0

	local function lineAlert(kind : string, line : integer, q : ProblemRadarLineQuality) : ProblemRadarAlert
		local a = newAlert(kind, tostring(line), line)
		a.etype = "Line"
		a.label = str(q.name)
		return a
	end

	for __, line in ipairs(sortedKeys(lines)) do
		local q = lines[line]
		if eligible[line] then
			-- line_overloaded: the stop/cargo with the most vehicle-loads waiting.
			local worst : ProblemRadarStopLoad = nil
			local worstRatio = 0.0
			for __, st in ipairs(q.stops or {}) do
				local w = toInt(st.waiting) or 0
				if w >= checks.MIN_OVERLOAD_WAITING and st.perTrip ~= nil and st.perTrip > 0 then
					local r = w / st.perTrip
					if r > worstRatio then
						worst = st
						worstRatio = r
					end
				end
			end
			local runO = since(prevO, line, now)
			local factor = set.lineOverloadFactor
			if worst ~= nil and (worstRatio >= factor or (runO ~= nil and worstRatio >= factor * hold)) then
				local t = runO or now
				newO[line] = t
				nO = nO + 1
				if now - t >= sustain then
					local a = lineAlert("line_overloaded", line, q)
					a.code = "Overloaded"
					-- "<stop number>|<waiting>|<stop name>" (stop number 1-based like the base GUI)
					a.arg = tostring(math.floor(worst.stop) + 1) .. "|" .. tostring(math.floor(worst.waiting)) .. "|" .. str(worst.name)
					a.metric = factorText(worstRatio)
					out[#out + 1] = a
				end
			end

			-- line_underused: base "Utilization" (used / capacity), lines with >= 2 vehicles only.
			local vehicles = toInt(q.vehicles) or 0
			local runU = since(prevU, line, now)
			if vehicles >= 2 and q.capacity ~= nil and q.capacity > 0 then
				local pct = (q.used or 0) / q.capacity * 100
				local limit = set.lineUnderusedPct
				if pct < limit or (runU ~= nil and pct < limit / hold) then
					local t = runU or now
					newU[line] = t
					nU = nU + 1
					if now - t >= sustain then
						local a = lineAlert("line_underused", line, q)
						a.code = "Underused"
						a.arg = tostring(vehicles)
						a.metric = tostring(math.floor(pct + 0.5)) .. "%"
						out[#out + 1] = a
					end
				end
			end

			-- line_bunching: headways at the stops vs the target interval; >= 3 vehicles, not full-load.
			local deps = q.departures or {}
			local interval = toInt(q.intervalMs) or 0
			local runB = since(prevB, line, now)
			if #deps >= 3 and interval > 0 and not q.fullLoad then
				local clumpMs = interval * set.lineClumpPct // 100
				local gapMs = interval * set.lineGapPct // 100
				local h = checks.headways(deps, now, interval, clumpMs)
				if h ~= nil then
					local clumped = h.minGapMs < clumpMs or (runB ~= nil and h.minGapMs < clumpMs / hold)
					local gapped = h.maxGapMs >= gapMs or (runB ~= nil and h.maxGapMs >= gapMs * hold)
					if clumped or gapped then
						local t = runB or now
						newB[line] = t
						nB = nB + 1
						if now - t >= sustain then
							local a = lineAlert("line_bunching", line, q)
							local intervalSec = tostring(interval // 1000)
							if clumped then
								local size, span = h.clump, h.clumpSpanMs
								if size < 2 then size, span = 2, h.minGapMs end
								a.code = "Clump"
								-- "<vehicles in the clump>|<vehicles>|<clump span s>|<target s>"
								a.arg = tostring(size) .. "|" .. tostring(#deps) .. "|" .. tostring(span // 1000) .. "|" .. intervalSec
								a.metric = tostring(size) .. "/" .. tostring(#deps)
							else
								a.code = "Gap"
								-- "<largest gap s>|<target s>"
								a.arg = tostring(h.maxGapMs // 1000) .. "|" .. intervalSec
								a.metric = factorText(h.maxGapMs / interval)
							end
							out[#out + 1] = a
						end
					end
				end
			end
		end
	end

	-- Eligible lines not measured this pass (rotating cursor): timers and alerts carry over until
	-- their turn comes. Lines no longer eligible (gone, sold, broken, no vehicles) are pruned.
	for line, t in pairs(prevO) do
		local l = toInt(line)
		if l ~= nil and lines[l] == nil and eligible[l] and toInt(t) ~= nil then newO[l] = since(prevO, l, now) nO = nO + 1 end
	end
	for line, t in pairs(prevU) do
		local l = toInt(line)
		if l ~= nil and lines[l] == nil and eligible[l] and toInt(t) ~= nil then newU[l] = since(prevU, l, now) nU = nU + 1 end
	end
	for line, t in pairs(prevB) do
		local l = toInt(line)
		if l ~= nil and lines[l] == nil and eligible[l] and toInt(t) ~= nil then newB[l] = since(prevB, l, now) nB = nB + 1 end
	end
	local kept : {string : boolean} = {}
	for __, a in ipairs(input.keep or {}) do
		local l = toInt(a.entity)
		if QUALITY_KINDS[a.kind] and l ~= nil and lines[l] == nil and eligible[l] and not kept[a.id] then
			kept[a.id] = true
			local c = copyAlert(a)
			c.carried = true -- not measured this pass (smoothing: no news)
			out[#out + 1] = c
		end
	end

	local cap = checks.MAX_LINE_TIMERS
	newO = capMap(newO, nO, cap)
	newU = capMap(newU, nU, cap)
	newB = capMap(newB, nB, cap)
	local changed = not (sameMap(newO, mem.overloadSince) and sameMap(newU, mem.underusedSince) and sameMap(newB, mem.bunchingSince))
	return out, checks.patchMemory(mem, { overloadSince = newO, underusedSince = newU, bunchingSince = newB }), changed
end

---------------------------------------------------------------------------
-- Economy (Phase 7): line_unprofitable, line_low_use. See PLAN "Phase 7".

function checks.dueRotation(ids : {integer}, cursor : integer, checkedAt : {integer : integer}, now : integer,
		everyMs : integer, max : integer, soon? : {integer : boolean}, soonMs? : integer) : {integer}
	local out : {integer} = {}
	local at = checkedAt or {}
	local early = soon or {}
	for __, line in ipairs(checks.lineRotation(ids, cursor)) do
		if #out >= max then break end
		local t = toInt(at[line])
		local wait = (early[line] and soonMs ~= nil) and math.min(soonMs, everyMs) or everyMs
		-- t > now: a load to an earlier game time; the check is due again.
		if t == nil or t > now or now - t >= wait then out[#out + 1] = line end
	end
	return out
end

function checks.lineMoney(balance : function(integer, integer, any) : number, now : integer, yearMs : integer,
		vehicleType : any, maintType : any) : ProblemRadarLineMoney
	local from = now - yearMs
	local m : ProblemRadarLineMoney = { year = balance(from, now, nil) as integer, quarters = {} }
	-- Each early return leaves out exactly the numbers judgeLoss would not look at (same verdict).
	local year = toInt(m.year)
	if year == nil or year >= 0 then return m end
	local quarter = yearMs // 4
	local notNeg = 0
	for i = 1, 4 do
		local a = from + (i - 1) * quarter
		local b = i == 4 and now or from + i * quarter
		local q = balance(a, b, nil) as integer
		m.quarters[i] = q
		local qi = toInt(q)
		-- The oldest quarter empty: too young to judge.
		if i == 1 and (qi == nil or qi == 0) then return m end
		if qi == nil or qi >= 0 then
			notNeg = notNeg + 1
			if notNeg > 4 - checks.ECON_MIN_NEG_QUARTERS then return m end
		end
	end
	if vehicleType ~= nil and maintType ~= nil then
		m.vehicleCost = balance(from, now, vehicleType) as integer
		m.maintCost = balance(from, now, maintType) as integer
	end
	return m
end

function checks.roundSig2(n : integer) : integer
	local v = toInt(n) or 0
	if v == 0 then return 0 end
	local sign = v < 0 and -1 or 1
	local a = math.abs(v)
	local mag = 1
	while a >= 100 * mag do mag = mag * 10 end
	return sign * math.floor(a / mag + 0.5) * mag
end

function checks.judgeLoss(m : ProblemRadarLineMoney, settings : ProblemRadarSettings, networkCost? : integer) : ProblemRadarLoss
	if type(m) ~= "table" or type(m.quarters) ~= "table" then return nil end
	local year = toInt(m.year)
	if year == nil or year >= 0 then return nil end
	-- The oldest quarter has no journal entries at all: the line (or its history) is younger than a
	-- year, so "the last year" can't be judged yet.
	local oldest = toInt(m.quarters[1])
	if oldest == nil or oldest == 0 then return nil end
	local neg = 0
	for i = 1, 4 do
		local q = toInt(m.quarters[i])
		if q ~= nil and q < 0 then neg = neg + 1 end
	end
	if neg < checks.ECON_MIN_NEG_QUARTERS then return nil end
	-- Cost coverage: costs = -(vehicle running costs + vehicle maintenance), income = balance - those
	-- (the rest of a line's maintenance/income balance). Only when the split is plausible (costs > 0,
	-- income >= 0).
	local coverage : number = nil
	local vc, mc = toInt(m.vehicleCost), toInt(m.maintCost)
	if vc ~= nil and mc ~= nil then
		local costs = -(vc + mc)
		local income = year + costs
		if costs > 0 and income >= 0 then coverage = income / costs * 100 end
	end
	-- Size: the loss as a share of all lines' yearly vehicle costs, so a big loss counts the same in
	-- 1850 and 2000, and in a small or a large network.
	local share : number = nil
	local net = toInt(networkCost)
	if net ~= nil and net > 0 then share = -year / net * 100 end
	local set = radar_settings.normalize(settings)
	-- Points: coverage 0-2 (unknown split: 1) + size 0-2 (unknown network costs: 0).
	-- 0 Info, 1-2 Warning, 3+ Critical; so a line that earns back little but loses a small amount is a
	-- Warning, and it takes a poor coverage and a big loss (or a very big loss) for Critical.
	local points = 1
	if coverage ~= nil then
		points = coverage < set.econLossCritPct and 2 or coverage < set.econLossWarnPct and 1 or 0
	end
	if share ~= nil then
		points = points + (share >= 3 * set.econLossSharePct and 2 or share >= set.econLossSharePct and 1 or 0)
	end
	local tier = points >= 3 and 1 or points >= 1 and 2 or 3
	-- Without the network costs the size can't count: the tier is the coverage's alone, as before
	-- (Critical below econLossCritPct).
	if share == nil and coverage ~= nil and coverage < set.econLossCritPct then tier = 1 end
	return { tier = tier, balance = year, negQuarters = neg, coveragePct = coverage, sharePct = share }
end

function checks.unprofitable(input : ProblemRadarUnprofitableInput) : {ProblemRadarAlert}
	local out : {ProblemRadarAlert} = {}
	local lines = input.lines or {}
	local eligible = input.eligible or {}
	local money = input.money or {}
	for __, line in ipairs(sortedKeys(money)) do
		local info = lines[line]
		local loss = info ~= nil and info.owned and eligible[line] and checks.judgeLoss(money[line], input.settings, input.networkCost) or nil
		if loss ~= nil then
			local a = newAlert("line_unprofitable", tostring(line), line)
			a.tier = loss.tier
			a.etype = "Line"
			a.label = str(info.name)
			-- Save churn: a re-checked row changes the state only when its text changes, so the balance
			-- is kept to two significant digits and the coverage to 5-point steps (floored, so the shown
			-- value never claims more coverage than the tier was decided on).
			local balance = checks.roundSig2(loss.balance)
			local cov = ""
			if loss.coveragePct ~= nil then
				a.code = "Loss"
				cov = tostring(math.floor(loss.coveragePct / 5) * 5)
			else
				a.code = "LossNoSplit"
			end
			-- The share as a whole % (floored; 0 = under 1 %), same churn reason.
			local share = loss.sharePct ~= nil and tostring(math.floor(loss.sharePct)) or ""
			-- "<12-month balance>|<negative quarters>|<coverage % or ''>|<share % or ''>"; metric = the
			-- balance (the GUI formats both with api.util.formatMoney; the engine stores raw integers only).
			a.arg = tostring(balance) .. "|" .. tostring(loss.negQuarters) .. "|" .. cov .. "|" .. share
			a.metric = tostring(balance)
			out[#out + 1] = a
		end
	end
	-- Eligible lines not checked this pass (rotating cursor): their rows carry over until their turn.
	local kept : {string : boolean} = {}
	for __, a in ipairs(input.keep or {}) do
		local l = toInt(a.entity)
		if a.kind == "line_unprofitable" and l ~= nil and money[l] == nil and eligible[l] and not kept[a.id] then
			kept[a.id] = true
			local c = copyAlert(a)
			c.carried = true -- not re-checked this pass (smoothing: no news)
			out[#out + 1] = c
		end
	end
	return out
end

function checks.lowUse(input : ProblemRadarLowUseInput) : {ProblemRadarAlert}
	local out : {ProblemRadarAlert} = {}
	local now = input.now or 0
	local yearMs = (input.yearMs ~= nil and input.yearMs > 0) and input.yearMs or DEFAULT_YEAR_MS
	local limit = radar_settings.normalize(input.settings).econLowUsePct
	local minTrack = math.floor(yearMs * checks.USE_MIN_TRACK_FRACTION)
	local lines = input.lines or {}
	local eligible = input.eligible or {}
	local avgs = input.useAvg or {}
	-- Runs every lines pass over every tracked line (up to MAX_USE_TRACKED): only the few low lines
	-- are sorted (output order), not all averages.
	local low : {integer : boolean} = {}
	for line, u in pairs(avgs) do
		if eligible[line] and type(u) == "table" and type(u.avg) == "number" and u.avg * 100 < limit then low[line] = true end
	end
	for __, line in ipairs(sortedKeys(low)) do
		local u = avgs[line]
		local info = lines[line]
		local start = toInt(u.start)
		if info ~= nil and info.owned and start ~= nil and now - start >= minTrack then
			local pct = u.avg * 100
			local a = newAlert("line_low_use", tostring(line), line)
			a.tier = pct < limit / 4 and 1 or (pct < limit / 2 and 2 or 3)
			a.etype = "Line"
			a.label = str(info.name)
			a.code = "LowUse"
			-- Floored, so the shown % is never at or above the threshold of a listed row (the epsilon
			-- keeps float noise such as 0.99999 from showing as 0 %).
			local shown = math.floor(pct + 1e-6)
			local months = math.min(12, (now - start) * 12 // yearMs)
			-- "<average %>|<months tracked, at most 12>"
			a.arg = tostring(shown) .. "|" .. tostring(months)
			a.metric = tostring(shown) .. "%"
			out[#out + 1] = a
		end
	end
	return out
end

function checks.updateUseAvg(prev : ProblemRadarUseAvg, sample : number, now : integer, yearMs : integer) : ProblemRadarUseAvg
	local x = math.max(0.0, math.min(1.0, sample or 0.0))
	local year = (yearMs ~= nil and yearMs > 0) and yearMs or DEFAULT_YEAR_MS
	local start = prev ~= nil and toInt(prev.start) or nil
	local last = prev ~= nil and toInt(prev.last) or nil
	if start == nil or last == nil or type(prev.avg) ~= "number" or last > now or start > last then
		return { avg = x, start = now, last = now }
	end
	local dt = now - last
	if dt <= 0 then return prev end
	-- Each sample stands for the time since the previous one (weight 1 - e), older weight decays by e;
	-- dividing by the total weight so far (1 - exp(-(now - start) / year)) removes the bias toward the
	-- first sample, which itself stands for no time (weight 0) and is fully replaced by the second.
	local e = math.exp(-dt / year)
	local wPrev = 1 - math.exp(-(last - start) / year)
	local w = wPrev * e + (1 - e)
	return { avg = (prev.avg * wPrev * e + x * (1 - e)) / w, start = start, last = now }
end

function checks.sampleUseAvg(live : {integer : ProblemRadarUseAvg}, samples : {integer : number}, keep : {integer : boolean},
		now : integer, yearMs : integer, cap? : integer) : {integer : ProblemRadarUseAvg}
	local out : {integer : ProblemRadarUseAvg} = {}
	local n = 0
	local k = keep or {}
	for line, u in pairs(live or {}) do
		if k[line] then
			out[line] = u
			n = n + 1
		end
	end
	local limit = cap or checks.MAX_USE_TRACKED
	local s = samples or {}
	for __, line in ipairs(sortedKeys(s)) do
		if k[line] and type(s[line]) == "number" and (out[line] ~= nil or n < limit) then
			if out[line] == nil then n = n + 1 end
			out[line] = checks.updateUseAvg(out[line], s[line], now, yearMs)
		end
	end
	return out
end

local function bpOf(avg : number) : integer
	return math.floor(avg * 10000 + 0.5)
end

--- A saved { bp, start, last } entry as three integers, or nil when malformed.
local function savedEntry(v : any) : integer, integer, integer
	if type(v) ~= "table" then return nil, nil, nil end
	local t = v as {any}
	local bp, start, last = toInt(t[1]), toInt(t[2]), toInt(t[3])
	if bp == nil or start == nil or last == nil then return nil, nil, nil end
	return bp, start, last
end

function checks.reconcileUseAvg(saved : any, live : {integer : ProblemRadarUseAvg}, liveAt : integer, now : integer) : {integer : ProblemRadarUseAvg}
	local function fromSaved() : {integer : ProblemRadarUseAvg}
		local out : {integer : ProblemRadarUseAvg} = {}
		if type(saved) ~= "table" then return out end
		for k, v in pairs(saved as {any : any}) do
			local line = toInt(k)
			local bp, start, last = savedEntry(v)
			if line ~= nil and bp ~= nil and start <= last and last <= now then
				out[line] = { avg = math.max(0, math.min(10000, bp)) / 10000, start = start, last = last }
			end
		end
		return out
	end
	if live == nil or liveAt == nil or liveAt > now or type(saved) ~= "table" then return fromSaved() end
	-- The averages themselves are not compared: between two writes the live ones drift freely (the
	-- save keeps the last written values, at most a game month old). Lines, starts and sample times
	-- tell whether the live copy grew out of this save (persistUseAvg writes whenever they change).
	local n = 0
	for k, v in pairs(saved as {any : any}) do
		n = n + 1
		local line = toInt(k)
		local bp, start, last = savedEntry(v)
		local l = line ~= nil and live[line] or nil
		if l == nil or bp == nil or l.start ~= start or l.last < last then
			return fromSaved()
		end
	end
	for __ in pairs(live) do n = n - 1 end
	if n ~= 0 then return fromSaved() end
	return live
end

function checks.persistUseAvg(live : {integer : ProblemRadarUseAvg}, saved : any, everyMs : integer) : {integer : {integer}}, boolean
	local need = type(saved) ~= "table"
	local old = type(saved) == "table" and saved as {integer : {integer}} or {}
	-- The newest saved sample time stands for the last write (every write saves every entry, and the
	-- pass that writes has just sampled); the newest live sample for now.
	local n = 0
	local savedAt, liveLast = nil as integer, nil as integer
	for line, l in pairs(live or {}) do
		n = n + 1
		local bp, start, last = savedEntry(old[line])
		if bp == nil or start ~= l.start then
			need = true
		elseif savedAt == nil or last > savedAt then
			savedAt = last
		end
		if liveLast == nil or l.last > liveLast then liveLast = l.last end
	end
	for __ in pairs(old) do n = n - 1 end
	if n ~= 0 then need = true end
	-- Cadence: once a game month for all entries together. Not per entry: with a line re-sampled less
	-- often than monthly (about 250+ lines), every sample would rewrite the whole state.
	if not need and savedAt ~= nil and liveLast ~= nil and liveLast - savedAt >= everyMs then need = true end
	if not need then return old, false end
	-- Every entry is written (so all saved "last" times are fresh together).
	local out : {integer : {integer}} = {}
	for line, l in pairs(live or {}) do out[line] = { bpOf(l.avg), l.start, l.last } end
	return out, true
end

---------------------------------------------------------------------------
-- Failure isolation (Phase 6). A scan (or a sub-scan such as the stuck or line-quality part) that
-- throws keeps its previous rows, so one bad API answer does not blank the list; after
-- FAIL_DROP_AFTER consecutive failures those rows are dropped, so frozen rows never stay forever.

checks.FAIL_DROP_AFTER = 10

function checks.carryOver(prev : {ProblemRadarAlert}, kinds : {string : boolean}, failures : integer, limit? : integer) : {ProblemRadarAlert}
	local out : {ProblemRadarAlert} = {}
	if (toInt(failures) or 0) >= (limit or checks.FAIL_DROP_AFTER) or type(prev) ~= "table" then return out end
	for __, a in ipairs(prev) do
		if type(a) == "table" and kinds[a.kind] then
			local c = copyAlert(a)
			c.carried = true -- not re-checked (smoothing: no news; a lingering row still clears)
			out[#out + 1] = c
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Deferred component reads for veh_stuck (Phase 6). The stopped timers run on getSpeed alone; the
-- engine reads PLAYER_OWNED / TRANSPORT_VEHICLE only for vehicles standing at least the smallest
-- threshold, and caches each vehicle's carrier.

function checks.standingDue(stoppedSince : {integer : integer}, now : integer, carriers : {integer : string},
		thresholds : {string : integer}) : {integer}, {integer}
	local minMs : integer = nil
	for __, ms in pairs(thresholds or {}) do
		if minMs == nil or ms < minMs then minMs = ms end
	end
	local classify : {integer} = {}
	local due : {integer} = {}
	if minMs == nil then return classify, due end
	local known = carriers or {}
	for __, v in ipairs(sortedKeys(stoppedSince or {})) do
		local since = toInt(stoppedSince[v])
		if since ~= nil and now - since >= minMs then
			local carrier = known[v]
			if carrier == nil then
				classify[#classify + 1] = v
			else
				local limit = thresholds[carrier]
				if limit ~= nil and now - since >= limit then due[#due + 1] = v end
			end
		end
	end
	return classify, due
end

function checks.expireMarks(marks : {integer : integer}, now : integer, ttl : integer, present : {integer : boolean}) : {integer : integer}
	local out : {integer : integer} = {}
	for v, t in pairs(marks or {}) do
		local at = toInt(t)
		if at ~= nil and present ~= nil and present[v] and now - at < ttl and at <= now then out[v] = at end
	end
	return out
end

function checks.keepSameEntity(alerts : {ProblemRadarAlert}, saved : {integer : integer}, current : {integer : integer}) : {ProblemRadarAlert}, {integer : integer}
	local out : {ProblemRadarAlert} = {}
	local revs : {integer : integer} = {}
	local cur = current or {}
	local old = saved or {}
	for __, a in ipairs(alerts or {}) do
		local e = toInt(a.entity)
		local rev = e ~= nil and toInt(cur[e]) or nil
		if rev ~= nil and (old[e] == nil or toInt(old[e]) == rev) then
			out[#out + 1] = a
			revs[e] = rev
		end
	end
	return out, revs
end

---------------------------------------------------------------------------
-- Merge one scan group's fresh alerts into the state.

function checks.tierCounts(alerts : {ProblemRadarAlert}, kindCounts : any) : {integer}
	local out : {integer} = { 0, 0, 0 }
	local rows : {string : integer} = {}
	for __, a in ipairs(type(alerts) == "table" and alerts or {}) do
		local t = type(a) == "table" and toInt(a.tier) or nil
		if t ~= nil and t >= 1 and t <= 3 then
			out[t] = out[t] + 1
			if type(a.kind) == "string" then rows[a.kind] = (rows[a.kind] or 0) + 1 end
		end
	end
	if type(kindCounts) == "table" then
		for k, n in pairs(kindCounts as {any : any}) do
			local info = type(k) == "string" and checks.KINDS[k as string] or nil
			local c = toInt(n)
			if info ~= nil and c ~= nil then
				local extra = c - (rows[k as string] or 0)
				if extra > 0 then out[info.tier] = out[info.tier] + extra end
			end
		end
	end
	return out
end

function checks.index(alerts : {ProblemRadarAlert}) : {string : ProblemRadarAlert}
	local m : {string : ProblemRadarAlert} = {}
	if type(alerts) ~= "table" then return m end
	for __, a in ipairs(alerts) do
		if type(a) == "table" and type(a.id) == "string" then m[a.id] = a end
	end
	return m
end

--- Sort order of the stored alerts. Robust to bad data from a save (a string tier, a numeric id):
--- table.sort must never see a comparison error, so every field is coerced first.
function checks.alertBefore(a : ProblemRadarAlert, b : ProblemRadarAlert) : boolean
	local ta, tb = toInt(a.tier) or 9, toInt(b.tier) or 9
	if ta ~= tb then return ta < tb end
	local fa, fb = toInt(a.firstSeen) or 0, toInt(b.firstSeen) or 0
	if fa ~= fb then return fa < fb end
	return tostring(a.id or "") < tostring(b.id or "")
end
local alertBefore = checks.alertBefore

local function samePos(a : {number}, b : {number}) : boolean
	if a == nil or b == nil then return a == b end
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

local function sameAlert(a : ProblemRadarAlert, b : ProblemRadarAlert) : boolean
	return a.id == b.id and a.kind == b.kind and a.tab == b.tab and a.tier == b.tier
		and a.entity == b.entity and a.entity2 == b.entity2 and a.etype == b.etype
		and a.label == b.label and a.context == b.context and a.code == b.code
		and a.arg == b.arg and a.metric == b.metric and a.firstSeen == b.firstSeen
		and a.missedAt == b.missedAt and samePos(a.pos, b.pos)
end

--- Smoothing (radar_settings smoothSec): `pending` entries in the order they are stored (oldest
--- first detection first, then id), so the stored list is stable and capped deterministically.
local function pendingBefore(a : ProblemRadarAlert, b : ProblemRadarAlert) : boolean
	local fa, fb = toInt(a.firstSeen) or 0, toInt(b.firstSeen) or 0
	if fa ~= fb then return fa < fb end
	return tostring(a.id or "") < tostring(b.id or "")
end

local function samePending(a : {ProblemRadarAlert}, b : {ProblemRadarAlert}) : boolean
	if #a ~= #b then return false end
	for i, x in ipairs(a) do
		local y = b[i]
		if x.id ~= y.id or toInt(x.firstSeen) ~= toInt(y.firstSeen) or toInt(x.missedAt) ~= toInt(y.missedAt) then return false end
	end
	return true
end

--- A shallow copy of `a` with missedAt set (nil clears it) and the transient `carried` flag removed.
local function withMissed(a : ProblemRadarAlert, missedAt : integer) : ProblemRadarAlert
	if a.missedAt == missedAt and a.carried == nil then return a end
	local c = copyAlert(a)
	c.missedAt = missedAt
	c.carried = nil
	return c
end

function checks.merge(state : ProblemRadarState, group : string, fresh : {ProblemRadarAlert}, now : integer, cap? : integer, memory? : ProblemRadarMemory, instant? : boolean) : ProblemRadarState, boolean
	local s = checks.upgradeState(state)
	cap = cap or checks.MAX_STORED_ALERTS
	local groupKinds : {string : boolean} = {}
	for __, k in ipairs(checks.GROUP_KINDS[group] or {}) do groupKinds[k] = true end
	-- Kinds switched "off" vanish at once (no lingering, no pending).
	local function live(kind : string) : boolean
		return checks.KINDS[kind] ~= nil and radar_settings.level(s.settings, kind) ~= "off"
	end
	-- Smoothing window in game ms (0 = off: the pre-smoothing behaviour).
	local windowMs = math.max(0, toInt(s.settings.smoothSec) or 0) * 1000
	local appearNow = windowMs <= 0 or instant == true

	local prevAlerts : {ProblemRadarAlert} = {}
	for __, a in ipairs(s.alerts) do
		if type(a) == "table" then prevAlerts[#prevAlerts + 1] = a end
	end
	local prev = checks.index(prevAlerts)
	local prevPendingList : {ProblemRadarAlert} = {}
	for __, a in ipairs(s.pending or {}) do
		if type(a) == "table" and type(a.id) == "string" and not prev[a.id] then prevPendingList[#prevPendingList + 1] = a end
	end
	local prevPending = checks.index(prevPendingList)

	-- Snoozes of this group's kinds (or of unknown kinds) end here once their time has passed; the
	-- other groups' are left to their own merge, so their counts change together with their rows.
	local snoozed : {string : ProblemRadarSnooze} = {}
	local snoozeChanged = false
	for id, z in pairs(s.snoozed or {}) do
		if z.untilMs <= now and (groupKinds[z.kind] or checks.KINDS[z.kind] == nil) then
			snoozeChanged = true
		else
			snoozed[id] = z
		end
	end

	-- Kinds with alerts over the stored cap (counted but not stored): their unseen ids may be
	-- listed ones, so they appear at once instead of going pending (no count flicker).
	local stored : {string : integer} = {}
	for __, a in ipairs(prevAlerts) do
		if type(a.kind) == "string" and (s.snoozed == nil or s.snoozed[a.id] == nil) then
			stored[a.kind] = (stored[a.kind] or 0) + 1
		end
	end
	local overCap : {string : boolean} = {}
	for k, n in pairs(s.kindCounts) do
		if type(k) == "string" and groupKinds[k] and type(n) == "number" and n > (stored[k] or 0) then overCap[k] = true end
	end

	-- Other groups' alerts and counts stay; kinds no longer in the catalogue are dropped.
	local combined : {ProblemRadarAlert} = {}
	for __, a in ipairs(prevAlerts) do
		if checks.KINDS[a.kind] ~= nil and not groupKinds[a.kind] then combined[#combined + 1] = a end
	end
	local counts : {string : integer} = {}
	for k, n in pairs(s.kindCounts) do
		if checks.KINDS[k] ~= nil and not groupKinds[k] and type(n) == "number" and n > 0 then counts[k] = math.floor(n) end
	end
	local pendingOut : {ProblemRadarAlert} = {}
	for __, p in ipairs(prevPendingList) do
		if live(p.kind) and not groupKinds[p.kind] then pendingOut[#pendingOut + 1] = p end
	end

	-- A snoozed alert is stored (so it keeps its firstSeen and smoothing) but not counted.
	local function show(a : ProblemRadarAlert)
		combined[#combined + 1] = a
		if snoozed[a.id] == nil then counts[a.kind] = (counts[a.kind] or 0) + 1 end
	end
	-- Missed for longer than the window (missedAt nil: not missed).
	local function expired(missedAt : integer) : boolean
		return missedAt ~= nil and now - missedAt > windowMs
	end

	local added : {string : boolean} = {}
	for __, a in ipairs(fresh or {}) do
		if type(a) == "table" and groupKinds[a.kind] and type(a.id) == "string" and not added[a.id] and live(a.kind) then
			added[a.id] = true
			-- carried: a row the scan kept without re-checking it (line-quality keep, fleet_old
			-- keepOld, failure carryOver). It is no news: timers neither start nor stop.
			local carried = a.carried == true
			a.carried = nil
			local old = prev[a.id]
			local p = prevPending[a.id]
			if old ~= nil then
				-- Listed: firstSeen kept. Detected again: no longer missing. Carried: a lingering
				-- row keeps its missedAt and still clears once the window has passed.
				a.firstSeen = toInt(old.firstSeen) or now
				local missedAt : integer = nil
				if carried and old.missedAt ~= nil then missedAt = math.min(toInt(old.missedAt) or now, now) end
				a.missedAt = missedAt
				if not expired(missedAt) then show(a) end
			elseif p ~= nil then
				local since = toInt(p.firstSeen) or now
				if carried then
					local m = toInt(p.missedAt)
					if not expired(m) and windowMs > 0 then pendingOut[#pendingOut + 1] = p end
				elseif appearNow or now - since >= windowMs then
					-- Detected for the whole window: listed now; firstSeen = when it is listed, so
					-- radar_notify's MIN_AGE_MS and the row's age count from the moment it shows.
					a.firstSeen = now
					a.missedAt = nil
					show(a)
				else
					pendingOut[#pendingOut + 1] = withMissed(p, nil)
				end
			elseif appearNow or overCap[a.kind] then
				a.firstSeen = now
				a.missedAt = nil
				show(a)
			else
				-- New: pending (not listed, not counted, not notified) from now on.
				a.firstSeen = now
				a.missedAt = nil
				pendingOut[#pendingOut + 1] = a
			end
		end
	end
	if windowMs > 0 then
		-- Listed rows of this group not detected: they linger with their last data until missed for
		-- longer than the window.
		for __, a in ipairs(prevAlerts) do
			if groupKinds[a.kind] and not added[a.id] and type(a.id) == "string" and live(a.kind) then
				local m = math.min(toInt(a.missedAt) or now, now)
				if not expired(m) then show(withMissed(a, m)) end
			end
		end
		-- Pending ids of this group not detected: dropped once missed for longer than the window.
		for __, p in ipairs(prevPendingList) do
			if groupKinds[p.kind] and not added[p.id] and live(p.kind) then
				local m = math.min(toInt(p.missedAt) or now, now)
				if not expired(m) then pendingOut[#pendingOut + 1] = withMissed(p, m) end
			end
		end
	end

	table.sort(combined, alertBefore)
	local alerts : {ProblemRadarAlert} = {}
	for i = 1, math.min(#combined, cap) do alerts[i] = combined[i] end

	-- Pending entries: the oldest MAX_PENDING_ALERTS kept (closest to being listed); a newer one left
	-- out simply starts its window later.
	table.sort(pendingOut, pendingBefore)
	local pendingCapped : {ProblemRadarAlert} = {}
	for i = 1, math.min(#pendingOut, checks.MAX_PENDING_ALERTS) do pendingCapped[i] = pendingOut[i] end

	local total = 0
	for __, n in pairs(counts) do total = total + n end

	local changed = snoozeChanged or #alerts ~= #prevAlerts or total ~= s.total
	if not changed then
		for i, a in ipairs(alerts) do
			if not sameAlert(a, prevAlerts[i]) then
				changed = true
				break
			end
		end
	end
	if not changed then
		for k, n in pairs(counts) do
			if s.kindCounts[k] ~= n then changed = true break end
		end
		for k, n in pairs(s.kindCounts) do
			if counts[k] ~= n then changed = true break end
		end
	end
	local tierCounts = checks.tierCounts(unsnoozed(alerts, snoozed), counts)
	if not changed then
		local tc = s.tierCounts or {}
		changed = tc[1] ~= tierCounts[1] or tc[2] ~= tierCounts[2] or tc[3] ~= tierCounts[3]
	end
	if not changed then
		local before : {ProblemRadarAlert} = {}
		for __, p in ipairs(s.pending or {}) do
			if type(p) == "table" then before[#before + 1] = p end
		end
		changed = not samePending(pendingCapped, before)
	end

	return {
		version = checks.STATE_VERSION,
		settings = s.settings,
		alerts = alerts,
		total = total,
		kindCounts = counts,
		memory = memory or s.memory,
		notified = s.notified,
		notifyCleared = s.notifyCleared,
		-- nil when empty (smoothing off, or nothing pending): the state shape of older saves.
		pending = #pendingCapped > 0 and pendingCapped or nil,
		tierCounts = tierCounts,
		snoozed = next(snoozed) ~= nil and snoozed or nil,
		seq = s.seq,
	}, changed
end

---------------------------------------------------------------------------
-- Snooze (GUI events "ProblemRadar.snooze" / "ProblemRadar.unsnooze", radar.script.tl)

local function copyCounts(m : {string : integer}) : {string : integer}
	local out : {string : integer} = {}
	for k, v in pairs(m or {}) do out[k] = v end
	return out
end

function checks.snooze(state : ProblemRadarState, id : string, untilMs : integer) : ProblemRadarState, boolean
	local s = checks.upgradeState(state)
	local a = type(id) == "string" and checks.index(s.alerts)[id] or nil
	if a == nil or type(untilMs) ~= "number" or checks.KINDS[a.kind] == nil then return s, false end
	local snoozed : {string : ProblemRadarSnooze} = {}
	for k, z in pairs(s.snoozed or {}) do snoozed[k] = z end
	-- Already snoozed (a repeated click before the window caught up): nothing to save. The Snoozed
	-- tab's button unsnoozes, so a new length is set by unsnoozing first.
	if snoozed[id] ~= nil then return s, false end
	local was = false
	snoozed[id] = { untilMs = math.floor(untilMs), kind = a.kind, label = optString(a.label), etype = optString(a.etype),
		context = optString(a.context), entity = toInt(a.entity) }
	s.snoozed = checks.cleanSnoozed(snoozed)
	if not was then
		local counts = copyCounts(s.kindCounts)
		local n = (counts[a.kind] or 0) - 1
		counts[a.kind] = n > 0 and n or nil
		s.kindCounts = counts
		s.total = math.max(0, (s.total or 0) - 1)
	end
	s.tierCounts = checks.tierCounts(unsnoozed(s.alerts, s.snoozed), s.kindCounts)
	return s, true
end

function checks.unsnooze(state : ProblemRadarState, id : string) : ProblemRadarState, boolean
	local s = checks.upgradeState(state)
	if s.snoozed == nil then return s, false end
	local listed = checks.index(s.alerts)
	local counts = copyCounts(s.kindCounts)
	local kept : {string : ProblemRadarSnooze} = {}
	local changed = false
	for k, z in pairs(s.snoozed) do
		if id == nil or k == id then
			changed = true
			local a = listed[k]
			if a ~= nil and checks.KINDS[a.kind] ~= nil then
				counts[a.kind] = (counts[a.kind] or 0) + 1
				s.total = (s.total or 0) + 1
			end
		else
			kept[k] = z
		end
	end
	if not changed then return s, false end
	s.snoozed = next(kept) ~= nil and kept or nil
	s.kindCounts = counts
	s.tierCounts = checks.tierCounts(unsnoozed(s.alerts, s.snoozed), s.kindCounts)
	return s, true
end

return checks
