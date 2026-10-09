-- Problem Radar settings schema (PLAN "Settings"). PURE: no api.*, no base modules, so the engine
-- script (validation of "ProblemRadar.setSetting" / "ProblemRadar.resetSettings") and the GUI model
-- (normalising what it reads) share one definition, and it is unit-tested offline
-- (tests/square_problem_radar/test_settings.lua).
-- Kinds of keys:
--   * string enums (ALLOWED, first value = default): hudMode
--   * integers in a range (NUMBERS)
--   * booleans (BOOLEANS): notifyPaused
--   * notify: a nested map alert kind -> "off" | "passive" | "notify" (NOTIFY_DEFAULTS). A
--     setSetting param may carry any subset of kinds: { notify = { veh_stuck = "off" } }.
-- Phase 5's Settings tab reads KEYS / NUMBERS / NOTIFY_KINDS to build its controls.

local settings : ProblemRadarSettingsModule = {}

-- Allowed values per key; the first one is the default.
local ALLOWED : {string : {string}} = {
	hudMode = { "badge", "compact" },
}

local BOOLEANS : {string : boolean} = {
	-- Phase 5: true = no radar notifications at all (alerts are still listed).
	notifyPaused = false,
}

-- Integer settings (Phase 3, Phase 4, Phase 5, Phase 7). Stuck thresholds are game-time minutes (the base stuck rule uses
-- 5 game-minutes for every carrier: notifications.script.tl:562, 1000 * 60 * 5 ms).
settings.NUMBERS = {
	stuckMinRoad = { default = 3, min = 1, max = 240, unit = "min" },
	stuckMinTram = { default = 3, min = 1, max = 240, unit = "min" },
	stuckMinRail = { default = 5, min = 1, max = 240, unit = "min" },
	stuckMinWater = { default = 10, min = 1, max = 240, unit = "min" },
	stuckMinAir = { default = 5, min = 1, max = 240, unit = "min" },
	idleDepotDays = { default = 30, min = 1, max = 3650, unit = "days" },
	-- Phase 5: fleet_worn at condition <= this percent. Base vehicle-condition notification: <= 0.2
	-- (notifications.script.tl:311). The alert clears above this + WORN_HYSTERESIS_PCT (base 0.3).
	wornPct = { default = 20, min = 1, max = 90, unit = "%" },
	-- Phase 4 line quality (PLAN "Phase 4"; conservative defaults so the radar stays quiet; tune in game).
	-- line_overloaded: waiting at the worst stop >= this many vehicle-loads (x capacity per trip)
	lineOverloadFactor = { default = 3, min = 1, max = 50, unit = "x" },
	-- line_underused: line utilisation (used / capacity, base "Utilization") below this percent
	lineUnderusedPct = { default = 10, min = 1, max = 90, unit = "%" },
	-- line_bunching: two vehicles depart a stop within this percent of the target interval (clump)
	lineClumpPct = { default = 20, min = 1, max = 90, unit = "%" },
	-- line_bunching: the largest gap exceeds this percent of the target interval (300 = 3x)
	lineGapPct = { default = 300, min = 120, max = 2000, unit = "%" },
	-- every line-quality condition must hold this long (game-time minutes) before it is listed
	lineSustainMin = { default = 10, min = 1, max = 240, unit = "min" },
	-- Smoothing for every alert kind (radar_checks.merge), in game seconds (GAME_TIME.gameTime / 1000):
	-- a new problem is listed only after it has been detected for this long (short misses within it
	-- don't restart it), and a listed one stays until it has been gone this long. 0 = off (list and
	-- clear on the next scan). Game time stands still while paused, so nothing appears or clears then.
	smoothSec = { default = 30, min = 0, max = 600, unit = "s" },
	-- Phase 7 economy. line_unprofitable (12-month loss, >= 3 of 4 quarters negative) is tiered by two
	-- era-independent ratios (radar_checks.judgeLoss): cost coverage (the line's income / its vehicle
	-- costs, running + maintenance: 1 point below econLossWarnPct %, 2 below econLossCritPct %) and the
	-- size of the loss (the loss / all lines' vehicle costs: 1 point at econLossSharePct %, 2 at 3x
	-- that). 0 points Info, 1-2 Warning, 3+ Critical. If Critical >= Warning, Critical simply wins (no
	-- cross-key rule to reject settings by).
	econLossWarnPct = { default = 75, min = 1, max = 99, unit = "%" },
	econLossCritPct = { default = 50, min = 1, max = 99, unit = "%" },
	econLossSharePct = { default = 2, min = 1, max = 50, unit = "%" },
	-- line_low_use: the yearly utilisation average below this %: Info; below half of it Warning, below
	-- a quarter Critical (defaults 20 / 10 / 5 %).
	econLowUsePct = { default = 20, min = 1, max = 90, unit = "%" },
	-- Snooze: a row's snooze button mutes its alert for this many game months (calendar months at the
	-- current calendar speed; radar.script.tl handleSnooze). The window offers radar_checks.SNOOZE_MONTHS.
	snoozeMonths = { default = 6, min = 1, max = 120, unit = "months" },
}

-- Base hysteresis of the vehicle-condition notification: on at <= 0.2, kept while <= 0.3.
settings.WORN_HYSTERESIS_PCT = 10

-- Flat keys (string, integer and boolean settings), in display order. "notify" is separate (NOTIFY_KINDS).
settings.KEYS = { "hudMode", "notifyPaused", "smoothSec", "stuckMinRoad", "stuckMinTram", "stuckMinRail", "stuckMinWater", "stuckMinAir",
	"idleDepotDays", "wornPct", "lineOverloadFactor", "lineUnderusedPct", "lineClumpPct", "lineGapPct", "lineSustainMin",
	"econLossWarnPct", "econLossCritPct", "econLossSharePct", "econLowUsePct", "snoozeMonths" }

-- Carrier names as the engine script maps TRANSPORT_VEHICLE.carrier (api.type.enum.Carrier).
-- OTHER has no threshold, so it never produces veh_stuck.
settings.STUCK_KEYS = {
	ROAD = "stuckMinRoad",
	TRAM = "stuckMinTram",
	RAIL = "stuckMinRail",
	WATER = "stuckMinWater",
	AIR = "stuckMinAir",
}

settings.HUD_MODES = ALLOWED.hudMode

-- Phase 5 per-alert notify level. "off": not detected / listed; "passive": listed only;
-- "notify": listed + a game notification when it first appears (radar_notify.tl).
settings.NOTIFY_LEVELS = { "off", "passive", "notify" }

-- Every alert kind (radar_checks.KINDS; the test checks they match), in the Settings tab's order.
settings.NOTIFY_KINDS = { "veh_blocked", "veh_nopath", "veh_stuck", "train_blocked_by",
	"line_broken", "line_no_vehicles", "line_cargo_issue", "line_cargo_not_unloaded", "line_overloaded", "line_underused", "line_bunching",
	"station_overcrowded", "station_useless", "fleet_worn", "fleet_old", "fleet_idle_depot",
	"line_unprofitable", "line_low_use" }

-- Defaults (PLAN "Alert catalogue": kinds the base game already reports are passive, so the radar
-- does not duplicate it; other Critical kinds notify; the rest passive).
-- * Base-reported (passive): veh_blocked / veh_nopath (vehicle_warning), line_broken (line_warning),
--   line_cargo_issue (line_warning's line issues), line_cargo_not_unloaded (cargo_rtc_warning, per
--   vehicle there, initiallyIgnoredType = true), station_overcrowded (overcrowding), station_useless
--   (line_station_warning), fleet_worn (vehiclecondition). The base still shows them as HUD / line
--   manager icons even where its popup type is initially ignored (types/*.res.lua initiallyIgnoredType,
--   notifications.d.tl Ignored: "still showing up in EOWs, LVM and as HUD icons").
-- * veh_stuck: notify. The base stuck_vehicle type is initiallyIgnoredType = true
--   (types/stuck_vehicle.res.lua), so a default game shows no popup for it, only a HUD icon, and it
--   uses one 5-minute rule for every carrier without the radar's station / harbour-queue exclusions.
-- * line_no_vehicles: notify (Critical, base only "partly"); radar_notify waits MIN_AGE_MS so a line
--   that is still being set up does not toast.
-- * Phase 7 line_unprofitable / line_low_use: passive. They change over game months, so a toast adds
--   little; the Economy tab is where they are read.
settings.NOTIFY_DEFAULTS = {
	veh_blocked = "passive",
	veh_nopath = "passive",
	veh_stuck = "notify",
	train_blocked_by = "passive",
	line_broken = "passive",
	line_no_vehicles = "notify",
	line_cargo_issue = "passive",
	line_cargo_not_unloaded = "passive",
	line_overloaded = "passive",
	line_underused = "passive",
	line_bunching = "passive",
	station_overcrowded = "passive",
	station_useless = "passive",
	fleet_worn = "passive",
	fleet_old = "passive",
	fleet_idle_depot = "passive",
	line_unprofitable = "passive",
	line_low_use = "passive",
}

local function isLevel(v : any) : boolean
	if type(v) ~= "string" then return false end
	for __, l in ipairs(settings.NOTIFY_LEVELS) do
		if l == v then return true end
	end
	return false
end

local function allowed(key : string, value : any) : boolean
	local num = settings.NUMBERS[key]
	if num ~= nil then
		if type(value) ~= "number" then return false end
		local n = value as number
		-- integers only (a save may hand back 3.0, which is fine); NaN fails every comparison
		return n == math.floor(n) and n >= num.min and n <= num.max
	end
	if BOOLEANS[key] ~= nil then
		return type(value) == "boolean"
	end
	local values = ALLOWED[key]
	if values == nil or type(value) ~= "string" then return false end
	for __, v in ipairs(values) do
		if v == value then return true end
	end
	return false
end

local function defaultNotify() : {string : string}
	local out : {string : string} = {}
	for kind, level in pairs(settings.NOTIFY_DEFAULTS) do out[kind] = level end
	return out
end

function settings.defaults() : ProblemRadarSettings
	local out : ProblemRadarSettings = { hudMode = ALLOWED.hudMode[1], notify = defaultNotify() }
	local o = out as {string : any}
	for key, num in pairs(settings.NUMBERS) do o[key] = num.default end
	for key, b in pairs(BOOLEANS) do o[key] = b end
	return out
end

function settings.normalize(s : any) : ProblemRadarSettings
	local out = settings.defaults()
	if type(s) ~= "table" then return out end
	local t = s as {string : any}
	local o = out as {string : any}
	for __, key in ipairs(settings.KEYS) do
		local v = t[key]
		if allowed(key, v) then
			o[key] = type(v) == "number" and math.floor(v as number) or v
		end
	end
	if type(t.notify) == "table" then
		local n = t.notify as {any : any}
		for __, kind in ipairs(settings.NOTIFY_KINDS) do
			local v = n[kind]
			if isLevel(v) then out.notify[kind] = v as string end
		end
	end
	return out
end

function settings.same(raw : any, normalized : ProblemRadarSettings) : boolean
	if type(raw) ~= "table" then return false end
	local r = raw as {string : any}
	local n = normalized as {string : any}
	for __, key in ipairs(settings.KEYS) do
		if r[key] ~= n[key] then return false end
	end
	if type(r.notify) ~= "table" then return false end
	local rn = r.notify as {any : any}
	local count = 0
	for __, kind in ipairs(settings.NOTIFY_KINDS) do
		if rn[kind] ~= normalized.notify[kind] then return false end
		count = count + 1
	end
	for __ in pairs(rn) do count = count - 1 end
	return count == 0 -- no extra (unknown) kinds
end

function settings.apply(current : ProblemRadarSettings, param : any) : ProblemRadarSettings, boolean, {string}
	local out = settings.normalize(current)
	if type(param) ~= "table" then return out, false, { "<param>" } end
	local rejected : {string} = {}
	local changed = false
	local o = out as {string : any}
	for k, v in pairs(param as {any : any}) do
		local key = type(k) == "string" and k as string or nil
		if key == "notify" then
			if type(v) ~= "table" then
				rejected[#rejected + 1] = "notify"
			else
				for kind, level in pairs(v as {any : any}) do
					local kname = type(kind) == "string" and kind as string or nil
					if kname ~= nil and settings.NOTIFY_DEFAULTS[kname] ~= nil and isLevel(level) then
						if out.notify[kname] ~= level then
							out.notify[kname] = level as string
							changed = true
						end
					else
						rejected[#rejected + 1] = "notify." .. tostring(kind)
					end
				end
			end
		elseif key ~= nil and allowed(key, v) then
			local value = type(v) == "number" and math.floor(v as number) or v
			if o[key] ~= value then
				o[key] = value
				changed = true
			end
		else
			rejected[#rejected + 1] = tostring(k)
		end
	end
	table.sort(rejected)
	return out, changed, rejected
end

function settings.reset(current : ProblemRadarSettings, param : any) : ProblemRadarSettings, boolean, {string}
	local cur = settings.normalize(current)
	-- The GUI sends {}; anything that is not a table (or nil) is not a reset request.
	if param ~= nil and type(param) ~= "table" then return cur, false, { "<param>" } end
	local out = settings.defaults()
	return out, not settings.same(cur, out), {}
end

function settings.level(s : ProblemRadarSettings, kind : string) : string
	local n = type(s) == "table" and type(s.notify) == "table" and s.notify[kind] or nil
	if isLevel(n) then return n end
	return settings.NOTIFY_DEFAULTS[kind] or "passive"
end

function settings.stuckThresholdsMs(s : ProblemRadarSettings) : {string : integer}
	local n = settings.normalize(s) as {string : integer}
	local out : {string : integer} = {}
	for carrier, key in pairs(settings.STUCK_KEYS) do
		out[carrier] = n[key] * 60 * 1000
	end
	return out
end

function settings.wornThresholds(s : ProblemRadarSettings) : number, number
	local pct = settings.normalize(s).wornPct
	local clear = math.min(100, pct + settings.WORN_HYSTERESIS_PCT)
	return pct / 100, clear / 100
end

return settings
