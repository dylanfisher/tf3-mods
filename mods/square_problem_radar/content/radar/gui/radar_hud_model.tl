-- Problem Radar HUD/window view model (PLAN "Architecture": radar_hud_model.tl). PURE: no api.*,
-- no base modules, so it is unit-tested offline (tests/square_problem_radar/test_hud_model.lua).
-- build(state) returns a small, fresh table for useStepStateTimer's deepEquals
-- (.cache/game/base/content/gui/main/engine_react_util.tl:126-145): counts per tab and tier,
-- the worst tier, the sorted rows and the badge/compact texts. Malformed alerts (bad tier, not a
-- table) are skipped, never an error: the state comes from a save.
-- The engine stores language-neutral codes; every player-facing text is made here through _()
-- (the harness fakes it). Wording follows the base notification types
-- (.cache/game/base/content/game_mechanics/notifications/types/*.script.tl, short variants).
-- Placeholders are filled with plain gsub so the module needs no base lang_util.

local radar_settings = ug_require "square_problem_radar::/radar/radar_settings.tl" as ProblemRadarSettingsModule
local radar_checks = ug_require "square_problem_radar::/radar/radar_checks.tl" as ProblemRadarChecks

local model : ProblemRadarHudModel = {}

model.TABS = { "all", "vehicles", "lines", "stations", "fleet", "economy" }
-- Snoozed alerts (state.snoozed) are only in this tab and its count, never in TABS' rows or counts.
model.SNOOZED_TAB = "snoozed"
-- The window renders at most this many rows of the selected tab (Phase 6); the rest is one
-- "+N more" line, so a long list never builds thousands of widgets.
model.MAX_RENDERED_ROWS = 100

local ALERT_TABS : {string : boolean} = { vehicles = true, lines = true, stations = true, fleet = true, economy = true }

local function toInt(v : any) : integer
	if type(v) ~= "number" then return nil end
	return math.floor(v as number)
end

local function toStr(v : any) : string
	if type(v) == "string" then return v as string end
	return ""
end

local function optStr(v : any) : string
	if type(v) == "string" and v ~= "" then return v as string end
	return nil
end

local function toPos(v : any) : {number}
	if type(v) ~= "table" then return nil end
	local t = v as {number}
	if type(t[1]) ~= "number" or type(t[2]) ~= "number" or type(t[3]) ~= "number" then return nil end
	return { t[1], t[2], t[3] }
end

--- Phase 7: money for the economy rows. The engine stores raw integers (it formats nothing); the
--- GUI scripts replace this with api.util.formatMoney (currency and the game's number format). The
--- default keeps the module pure for the offline tests: "-1,200,000".
function model.formatMoney(money : integer) : string
	local n = math.floor(money or 0)
	local digits = tostring(math.abs(n))
	local out = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return (n < 0 and "-" or "") .. out
end

--- "{n} crit" style fill: every {key} is replaced by the value (plain text, no patterns).
local function fill(template : string, values : {string : string}) : string
	return (template:gsub("{(%w+)}", function(key : string) : string
		return values[key] or ("{" .. key .. "}")
	end))
end

---------------------------------------------------------------------------
-- Texts. Each table maps a code to an untranslated string; _() is applied when used, so the
-- base game's own translations apply wherever the wording is identical. The `-- i18n: keys` blocks
-- let tools/i18n.py extract the table texts as strings.json keys.

-- i18n: keys begin
local KIND_LABELS : {string : string} = {
	veh_blocked = "Blocked",
	veh_nopath = "No path",
	line_broken = "Line broken",
	line_no_vehicles = "No vehicles",
	line_cargo_issue = "Cargo issue",
	line_cargo_not_unloaded = "Not unloaded",
	station_overcrowded = "Overcrowded",
	station_useless = "Stop unusable",
	fleet_worn = "Worn",
	veh_stuck = "Stuck",
	train_blocked_by = "Waiting",
	fleet_old = "Old",
	fleet_idle_depot = "Idle",
	line_overloaded = "Over capacity",
	line_underused = "Underused",
	line_bunching = "Bunching",
	line_unprofitable = "Losing money",
	line_low_use = "Low use",
}
-- i18n: keys end

-- i18n: keys begin
local TYPE_LABELS : {string : string} = {
	Train = "Train", Tram = "Tram", Bus = "Bus", Truck = "Truck", Ship = "Ship",
	Airplane = "Airplane", Helicopter = "Helicopter", Line = "Line", Station = "Station",
}
-- i18n: keys end

-- vehicle_warning.script.tl short texts
-- i18n: keys begin
local VEHICLE_PROBLEMS : {string : string} = {
	NoPathElectric = "No Electrified Path",
	NoPathShip = "No Path for Big Ships",
	NoPathAircraft = "No Path for Big Aircraft",
	NoPathGeneric = "No Path at All",
	NoPath = "No path",
}
-- i18n: keys end

-- Failure.Reason (manager_window.tl:5409-5421 texts; NoRail/NoRoad from line_util.getRelaxationText)
-- i18n: keys begin
local FAILURE_REASONS : {string : string} = {
	NoElectric = "Missing electric tracks.",
	NoTram = "Missing tram tracks.",
	NoTramButTramTrack = "Incompatible tracks.",
	NoTramTrackButRail = "Missing tram support on tracks.",
	NoSmallAircraft = "No path for big airplanes.",
	NoSmallShip = "No path for big ships.",
	NoRail = "Missing train tracks",
	NoRoad = "Missing road",
}
-- i18n: keys end

-- line_warning.script.tl short texts
-- i18n: keys begin
local LINE_PROBLEMS : {string : string} = {
	ZERO_OR_ONE_STATION = "Line Contains Too Few Stations",
	DOUBLE_STATIONS = "A Station Appears Consecutively Twice",
	INCOMPATIBLE_STATIONS = "Stations Are Incompatible Due to Conflicting Stops",
	NO_PATH = "Could Not Connect Stations",
	BAD_ALTERNATIVE_TERMINAL = "Could Not Connect Alternative Terminals",
}
-- i18n: keys end

-- line_util.getRelaxationText
-- i18n: keys begin
local RELAXATIONS : {string : string} = {
	Catenary = "Missing catenaries",
	TramLanes = "Missing tram lane",
	TramTrack = "Missing tram tracks",
	Train = "Missing train tracks",
	Road = "Missing road",
}
-- i18n: keys end

-- i18n: keys begin
local LINE_ISSUES : {string : string} = {
	NowhereToLoad = "Cargo cannot be loaded anywhere",
	NowhereToUnload = "Cargo cannot be unloaded anywhere",
	NoVehicleToLoadCargo = "No vehicle can transport the configured cargo",
	VehicleUseless = "Some vehicles cannot transport the configured cargo",
	LineCargoConfig = "The line isn't configured to load any cargo.",
}
-- i18n: keys end

-- line_station_warning.script.tl short texts
-- i18n: keys begin
local STATION_PROBLEMS : {string : string} = {
	StopUseless = "Stop Not Compatible With Current Vehicles",
	PassengerStopUseless = "Passenger Stop Incompatible With Cargo Vehicles",
	AllPassengerStopUseless = "All Passenger Stops Incompatible With Cargo Vehicles",
	CargoStopUseless = "Cargo Stop Incompatible With Passenger Vehicles",
	CargoTypeUnloadUseless = "Configured Cargo Type Cannot Be Unloaded at Stop",
	CargoTypeLoadUseless = "Configured Cargo Type Cannot Be Loaded at Stop",
}
-- i18n: keys end

local function tr(map : {string : string}, code : string, fallback : string) : string
	local s = map[code]
	return _(s or fallback) -- i18n: ignore (keys: the tables above + the literal fallbacks)
end

local function withReason(text : string, reason : string) : string
	if reason == nil then return text end
	return fill(_("{text}: {reason}"), { text = text, reason = reason })
end

-- veh_stuck codes are carrier names; the text is the same for all (the type column names the vehicle).
local function withNextStop(text : string, stop : string) : string
	if stop == nil then return text end
	return fill(_("{text}, next stop {stop}"), { text = text, stop = stop })
end

--- The engine's metric texts carry English unit letters ("12m", "1h05m +2", "31d", "3 veh · 42"; they
--- are saved and compared, so they stay as they are): shown through _() templates, the stored
--- value is untouched. Anything else (numbers, "%", "×", "/") is returned unchanged.
function model.metricText(kind : string, metric : string) : string
	if metric == nil or metric == "" then return metric end
	if kind == "veh_stuck" or kind == "train_blocked_by" then
		local h, m, rest = metric:match("^(%d+)h(%d+)m(.*)$")
		if h ~= nil then
			return fill(_("{h}h{m}m"), { h = h, m = m }) .. rest
		end
		local mm, rest2 = metric:match("^(%d+)m(.*)$")
		if mm ~= nil then
			return fill(_("{m}m"), { m = mm }) .. rest2
		end
	elseif kind == "fleet_idle_depot" then
		local d = metric:match("^(%d+)d$")
		if d ~= nil then return fill(_("{n}d"), { n = d }) end
	elseif kind == "line_cargo_not_unloaded" then
		local n, c = metric:match("^(%d+) veh · (%d+)$")
		if n ~= nil then return fill(_("{n} veh · {cargo}"), { n = n, cargo = c }) end
	end
	return metric
end

--- Split a Phase 4 packed arg ("3|420|Central") into at most `n` parts; the last part keeps any
--- further "|" (a stop name may contain one).
local function split(arg : string, n : integer) : {string}
	local out : {string} = {}
	local rest = arg
	while #out < n - 1 do
		local i = rest:find("|", 1, true)
		if i == nil then break end
		out[#out + 1] = rest:sub(1, i - 1)
		rest = rest:sub(i + 1)
	end
	out[#out + 1] = rest
	return out
end

--- line_unprofitable arg "<12-month balance>|<negative quarters>|<coverage % or ''>|<share % or ''>"
--- (saves before the size rule have no 4th part) -> its parts; nil if malformed. share is shown as
--- "<1%" for 0 (the engine floors it).
local record UnprofitableParts
	balance : number
	q : string
	cov : string
	share : string
end

local function unprofitableParts(extra : string) : UnprofitableParts
	local p = extra ~= nil and split(extra, 4) or {}
	local balance = #p >= 3 and tonumber(p[1]) or nil
	if balance == nil or tonumber(p[2]) == nil then return nil end
	local share : string = nil
	local sh = tonumber(p[4] or "")
	if sh ~= nil then share = sh < 1 and "<1%" or (tostring(math.floor(sh)) .. "%") end
	return { balance = balance, q = p[2], cov = tonumber(p[3]) ~= nil and p[3] or nil, share = share }
end

--- Seconds string -> "2:30" (nil if not a number).
local function secs(v : string) : string
	local n = tonumber(v)
	if n == nil then return nil end
	return radar_checks.formatSeconds(math.floor(n))
end

function model.detailText(kind : string, code : string, extra : string, metric? : string) : string
	if kind == "veh_blocked" then
		if extra ~= nil then
			return fill(_("Blocking each other with {vehicle}"), { vehicle = extra })
		end
		return _("Trains Are Blocking Each Other")
	elseif kind == "veh_nopath" then
		local reason = FAILURE_REASONS[extra]
		return withReason(tr(VEHICLE_PROBLEMS, code, "No path"), reason and _(reason) or nil) -- i18n: keys; i18n: ignore
	elseif kind == "line_broken" then
		local reason = RELAXATIONS[extra]
		return withReason(tr(LINE_PROBLEMS, code, "Unknown Line Issue Occured"), reason and _(reason) or nil) -- i18n: keys; i18n: ignore
	elseif kind == "line_no_vehicles" then
		if extra ~= nil then
			return fill(_("No vehicles on this line ({n} stops)"), { n = extra })
		end
		return _("No vehicles on this line")
	elseif kind == "line_cargo_issue" then
		return withReason(tr(LINE_ISSUES, code, "Line Is Misconfigured"), extra) -- i18n: keys
	elseif kind == "line_cargo_not_unloaded" then
		-- arg "<vehicles>|<cargo>" (metric "3 veh · 42"); base types/cargo_rtc_warning.script.tl wording
		local p = extra ~= nil and split(extra, 2) or {}
		if #p == 2 and tonumber(p[1]) ~= nil and tonumber(p[2]) ~= nil then
			if p[1] == "1" then
				return fill(_("{cargo} cargo of 1 vehicle rode a full round trip without being unloaded"), { cargo = p[2] })
			end
			return fill(_("{cargo} cargo of {n} vehicles rode a full round trip without being unloaded"), { cargo = p[2], n = p[1] })
		end
		return _("Cargo rides a full round trip without being unloaded")
	elseif kind == "station_overcrowded" then
		return _("Overcrowded, passengers will be leaving")
	elseif kind == "station_useless" then
		return tr(STATION_PROBLEMS, code, "Unkown Station Stop Issue Occured") -- i18n: keys
	elseif kind == "fleet_worn" then
		return _("Vehicle Condition Is Not Good")
	elseif kind == "veh_stuck" then
		-- metric "12m" (radar_checks.formatMinutes); arg = next stop name
		local base = metric ~= nil and fill(_("Standing {time}"), { time = model.metricText(kind, metric) }) or _("Vehicle Has Been Stuck for a While")
		return withNextStop(base, extra)
	elseif kind == "train_blocked_by" then
		if code == "WaitingForPath" then
			return withNextStop(_("Waiting for Free Path"), extra)
		end
		if extra ~= nil then
			return fill(_("Waiting behind {vehicle}"), { vehicle = extra })
		end
		return _("Waiting behind another train")
	elseif kind == "fleet_old" then
		-- arg "23/20": age / lifespan in years (vehicle_util.getAge)
		if extra ~= nil then
			return fill(_("Age {age} y, past its lifespan"), { age = extra })
		end
		return _("Past its lifespan")
	elseif kind == "line_overloaded" then
		-- arg "<stop number>|<waiting>|<stop name>", metric "2.8×" (waiting / capacity per trip)
		local p = extra ~= nil and split(extra, 3) or {}
		if #p == 3 and metric ~= nil then
			return fill(_("Stop {n} '{stop}': {waiting} waiting, ~{factor} capacity per trip"),
				{ n = p[1], stop = p[3], waiting = p[2], factor = metric })
		end
		return _("More waiting than the line can carry")
	elseif kind == "line_underused" then
		-- metric "8%" (utilisation), arg = vehicle count
		if metric ~= nil and extra ~= nil then
			return fill(_("{n} vehicles running mostly empty ({pct} used)"), { n = extra, pct = metric })
		end
		return _("Vehicles running mostly empty")
	elseif kind == "line_bunching" then
		local p = extra ~= nil and split(extra, 4) or {}
		if code == "Clump" and #p == 4 and secs(p[3]) ~= nil and secs(p[4]) ~= nil then
			-- arg "<in clump>|<vehicles>|<span s>|<target s>"
			return fill(_("{k} of {n} within {span} · target {target}"),
				{ k = p[1], n = p[2], span = secs(p[3]), target = secs(p[4]) })
		elseif code == "Gap" and #p == 2 and secs(p[1]) ~= nil and secs(p[2]) ~= nil then
			-- arg "<gap s>|<target s>"
			return fill(_("Gap {gap} vs target {target}"), { gap = secs(p[1]), target = secs(p[2]) })
		end
		return _("Vehicles bunched or unevenly spaced")
	elseif kind == "line_unprofitable" then
		-- Short (the detail column fits about 45 characters): the loss itself is the metric column and
		-- the full sentence is the row tooltip (model.tipText).
		local p = unprofitableParts(extra)
		if p ~= nil then
			if p.cov ~= nil and p.share ~= nil then
				return fill(_("Earns {cov}% of costs · {share} of all line costs"), { cov = p.cov, share = p.share })
			elseif p.cov ~= nil then
				return fill(_("Earns {cov}% of its costs · {q}/4 quarters lost"), { cov = p.cov, q = p.q })
			elseif p.share ~= nil then
				return fill(_("Loss {share} of all line costs · {q}/4 quarters"), { share = p.share, q = p.q })
			end
			return fill(_("Lost money in {q}/4 quarters"), { q = p.q })
		end
		return _("Lost money over the last 12 months")
	elseif kind == "line_low_use" then
		-- arg "<average %>|<months tracked, at most 12>"
		local p = extra ~= nil and split(extra, 2) or {}
		local months = #p == 2 and tonumber(p[2]) or nil
		if months ~= nil and tonumber(p[1]) ~= nil then
			if months >= 12 then
				return fill(_("{pct}% used on average over the last year"), { pct = p[1] })
			end
			return fill(_("{pct}% used on average over {n} months"), { pct = p[1], n = p[2] })
		end
		return _("Vehicles mostly empty over a long time")
	elseif kind == "fleet_idle_depot" then
		if extra ~= nil then
			return fill(_("In depot for {n} days"), { n = extra })
		end
		return _("In Depot")
	end
	return code or ""
end

---------------------------------------------------------------------------
-- Labels + notification texts (Phase 5: the Settings tab and notify/radar_notification.script.tl).

local TIER_NAMES : {integer : string} = { [1] = "Critical", [2] = "Warning", [3] = "Info" } -- i18n: keys

function model.kindLabel(kind : string) : string
	local l = KIND_LABELS[kind]
	return l ~= nil and _(l) or (kind or "") -- i18n: ignore
end

function model.tierLabel(tier : integer) : string
	return _(TIER_NAMES[tier] or "Info") -- i18n: ignore
end

function model.kindTierLabel(kind : string) : string
	local info = radar_checks.KINDS[kind]
	if info == nil then return model.tierLabel(3) end
	if info.maxTier ~= nil and info.maxTier ~= info.tier then
		return fill(_("{low} to {high}"), { low = model.tierLabel(info.tier), high = model.tierLabel(info.maxTier) })
	end
	return model.tierLabel(info.tier)
end

-- Base notification icons, by kind; each file is referenced by a base notification type
-- (.cache/game/base/content/game_mechanics/notifications/types/*.script.tl), so it exists in every
-- install. Vehicle kinds use the per-vehicle-type variant like vehicle_warning / vehiclecondition
-- ("relation_<type>_minus" / "_repair"). Unknown kinds fall back by tier.
local ICON_DIR <const> = "::/game_mechanics/notifications/gui/icons/"
local VEHICLE_ICON_TYPES : {string : string} = {
	Train = "train", Tram = "tram", Bus = "bus", Truck = "truck", Ship = "ship",
	Airplane = "airplane", Helicopter = "helicopter",
}
local KIND_ICONS : {string : string} = {
	veh_stuck = "stuck_vehicle",              -- types/stuck_vehicle.script.tl
	line_broken = "line_minus_x",             -- types/line_warning.script.tl
	line_no_vehicles = "line_minus",
	line_cargo_issue = "line_cargo_minus_unload", -- types/cargo_rtc_warning.script.tl
	line_cargo_not_unloaded = "line_cargo_minus_unload",
	line_overloaded = "line_minus",
	line_underused = "line_minus",
	line_bunching = "line_minus",
	station_overcrowded = "terminal_full",    -- types/overcrowding.script.tl
	station_useless = "line_station_incompatible", -- types/line_station_warning.script.tl
	fleet_idle_depot = "stuck_vehicle",
	-- Phase 7. No base notification type is about money; the coin stack is the base finance icon
	-- (finances_loan_gui.tl:334, 418), given as a full path.
	line_unprofitable = "::/game_mechanics/finance/icons/symbol_coin_stack.tga",
	line_low_use = "line_minus",
}
-- "minus" (problem) vs "repair" (condition) per-vehicle-type icons.
local VEHICLE_ICON_KINDS : {string : string} = {
	veh_blocked = "minus", veh_nopath = "minus", train_blocked_by = "minus",
	fleet_worn = "repair", fleet_old = "repair",
}
local TIER_ICONS : {integer : string} = { [1] = "line_minus_x", [2] = "line_minus", [3] = "notification_placeholder" }

local function iconFor(kind : string, etype : string, tier : integer) : string
	local suffix = VEHICLE_ICON_KINDS[kind]
	if suffix ~= nil then
		local vt = VEHICLE_ICON_TYPES[etype] or (kind == "train_blocked_by" or kind == "veh_blocked") and "train" or "bus"
		return ICON_DIR .. "relation_" .. vt .. "_" .. suffix .. ".tga"
	end
	local icon = KIND_ICONS[kind]
	if icon ~= nil and icon:sub(1, 3) == "::/" then return icon end
	return ICON_DIR .. (icon or TIER_ICONS[tier] or TIER_ICONS[3]) .. ".tga"
end

function model.notificationText(p : any) : string, string, string
	local t = type(p) == "table" and p as {string : any} or {}
	local more = toInt(t.more)
	local kind = toStr(t.kind)
	if more ~= nil or kind == "" then
		local n = more ~= nil and more or 0
		return _("Problem Radar"),
			fill(_("+{n} more new problems. Open the radar from the button ridge to see them."), { n = tostring(n) }),
			ICON_DIR .. TIER_ICONS[1] .. ".tga"
	end
	local tier = toInt(t.tier)
	if tier == nil or tier < 1 or tier > 3 then tier = 3 end
	local label = toStr(t.label)
	local entity = toInt(t.entity)
	if label == "" and entity ~= nil then label = "#" .. tostring(entity) end
	local title = model.kindLabel(kind)
	if label ~= "" then title = fill(_("{kind}: {name}"), { kind = title, name = label }) end
	local description = model.tipText(kind, optStr(t.arg)) or model.detailText(kind, optStr(t.code), optStr(t.arg), optStr(t.metric))
	local context = toStr(t.context)
	if context ~= "" then description = fill(_("{text} ({context})"), { text = description, context = context }) end
	return title, description, iconFor(kind, toStr(t.etype), tier)
end

--- The full sentence behind a short detail text (row tooltip, notification description); nil when
--- the detail says it all.
function model.tipText(kind : string, arg : string) : string
	if kind ~= "line_unprofitable" then return nil end
	local p = unprofitableParts(arg)
	if p == nil then return nil end
	local text = fill(_("Lost {money} in 12 months ({q}/4 quarters negative)."),
		{ money = model.formatMoney(math.floor(-p.balance)), q = p.q })
	if p.cov ~= nil then
		text = text .. " " .. fill(_("Income covers about {pct}% of its vehicle costs."), { pct = p.cov })
	end
	if p.share ~= nil then
		text = text .. " " .. fill(_("The loss is {share} of all lines' vehicle costs."), { share = p.share })
	end
	return text
end

---------------------------------------------------------------------------

--- A sanitised row without its translated texts (kindLabel / typeLabel / detail are filled by
--- model.decorate, only for the rows that are rendered).
local function toRow(a : any) : ProblemRadarHudRow
	if type(a) ~= "table" then return nil end
	local t = a as {string : any}
	local tier = toInt(t.tier)
	if tier == nil or tier < 1 or tier > 3 then return nil end
	local kind = toStr(t.kind)
	local entity = toInt(t.entity)
	local label = toStr(t.label)
	if label == "" and entity ~= nil then label = "#" .. tostring(entity) end
	return {
		id = toStr(t.id),
		kind = kind,
		tab = toStr(t.tab),
		tier = tier,
		entity = entity,
		entity2 = toInt(t.entity2),
		label = label,
		context = toStr(t.context),
		etype = toStr(t.etype),
		code = optStr(t.code),
		arg = optStr(t.arg),
		kindLabel = "",
		typeLabel = "",
		detail = "",
		metric = toStr(t.metric),
		firstSeen = toInt(t.firstSeen) or 0,
		pos = toPos(t.pos),
	}
end

function model.decorate(row : ProblemRadarHudRow) : ProblemRadarHudRow
	local etype = row.etype or ""
	row.kindLabel = model.kindLabel(row.kind)
	row.typeLabel = TYPE_LABELS[etype] ~= nil and _(TYPE_LABELS[etype]) or etype -- i18n: ignore
	if row.gone then
		-- A snooze whose problem is not detected right now: only the snapshot is known.
		row.detail = _("Not detected right now")
		return row
	end
	row.detail = model.detailText(row.kind, row.code, row.arg, optStr(row.metric))
	row.tip = model.tipText(row.kind, row.arg)
	-- line_unprofitable: the engine's metric is the raw 12-month balance; shown as money.
	local balance = row.kind == "line_unprofitable" and tonumber(row.metric) or nil
	if balance ~= nil then
		row.metric = model.formatMoney(math.floor(balance))
	else
		row.metric = model.metricText(row.kind, row.metric)
	end
	return row
end

local function rowBefore(a : ProblemRadarHudRow, b : ProblemRadarHudRow) : boolean
	if a.tier ~= b.tier then return a.tier < b.tier end
	-- Within a tier, the bigger loss first (raw balance metric: rows are sorted before decorate).
	if a.kind == "line_unprofitable" and b.kind == "line_unprofitable" then
		local x, y = tonumber(a.metric), tonumber(b.metric)
		if x ~= nil and y ~= nil and x ~= y then return x < y end
	end
	if a.firstSeen ~= b.firstSeen then return a.firstSeen < b.firstSeen end
	return a.id < b.id
end

--- Tier counts and the worst tier from state.kindCounts (+ v6 state.tierCounts) alone (the ridge
--- HUD's 1 s poll). The economy kinds' tier varies per row, so their tiers come from tierCounts; it is
--- used only when it adds up to the kind counts' total (else, e.g. an older state, each kind counts
--- at its catalogue tier).
function model.counts(kindCounts : any, hudMode : any, savedTiers? : any) : ProblemRadarHudCounts
	local tierCounts : {integer} = { 0, 0, 0 }
	local total, worst = 0, 0
	if type(kindCounts) == "table" then
		for kind, n in pairs(kindCounts as {any : any}) do
			local info = type(kind) == "string" and radar_checks.KINDS[kind as string] or nil
			local count = toInt(n)
			if info ~= nil and count ~= nil and count > 0 then
				tierCounts[info.tier] = tierCounts[info.tier] + count
				total = total + count
				if worst == 0 or info.tier < worst then worst = info.tier end
			end
		end
	end
	if type(savedTiers) == "table" then
		local t = savedTiers as {any}
		local c1, c2, c3 = toInt(t[1]), toInt(t[2]), toInt(t[3])
		if c1 ~= nil and c2 ~= nil and c3 ~= nil and c1 >= 0 and c2 >= 0 and c3 >= 0 and c1 + c2 + c3 == total then
			tierCounts = { c1, c2, c3 }
			worst = c1 > 0 and 1 or (c2 > 0 and 2 or (c3 > 0 and 3 or 0))
		end
	end
	local mode = radar_settings.normalize({ hudMode = hudMode }).hudMode
	return { hudMode = mode, total = total, tierCounts = tierCounts, worstTier = worst }
end

function model.compactText(tierCounts : {integer}) : string
	local t = tierCounts or {}
	return fill(_("{crit} crit · {warn} warn · {info} info"), {
		crit = tostring(t[1] or 0),
		warn = tostring(t[2] or 0),
		info = tostring(t[3] or 0),
	})
end

function model.build(s : ProblemRadarState) : ProblemRadarHudView
	local view = model.buildRaw(s)
	for __, r in ipairs(view.rows) do model.decorate(r) end
	view.badgeLabel = _("Radar")
	view.badgeText = view.badgeLabel .. " ● " .. tostring(view.total)
	view.compactText = model.compactText(view.tierCounts)
	return view
end

--- A snoozed alert that is not stored right now (its problem cleared): a row from the snapshot.
local function snapshotRow(id : string, z : ProblemRadarSnooze) : ProblemRadarHudRow
	local info = radar_checks.KINDS[z.kind]
	if info == nil then return nil end
	local label = z.label
	if label == "" and z.entity ~= nil then label = "#" .. tostring(z.entity) end
	return {
		id = id, kind = z.kind, tab = info.tab, tier = info.tier, entity = z.entity, label = label,
		context = z.context, etype = z.etype, kindLabel = "", typeLabel = "", detail = "", metric = "",
		firstSeen = 0, snoozedUntil = z.untilMs, gone = true,
	}
end

local function snoozeBefore(a : ProblemRadarHudRow, b : ProblemRadarHudRow) : boolean
	if a.snoozedUntil ~= b.snoozedUntil then return a.snoozedUntil < b.snoozedUntil end
	return a.id < b.id
end

function model.buildRaw(s : ProblemRadarState) : ProblemRadarHudView
	local st = type(s) == "table" and s or {} as ProblemRadarState
	local snoozed = radar_checks.cleanSnoozed(st.snoozed) or {}
	local rows : {ProblemRadarHudRow} = {}
	local snoozedRows : {ProblemRadarHudRow} = {}
	local stored : {string : boolean} = {}
	if type(st.alerts) == "table" then
		for __, a in ipairs(st.alerts) do
			local row = toRow(a)
			if row ~= nil then
				local z = snoozed[row.id]
				if z ~= nil then
					row.snoozedUntil = z.untilMs
					snoozedRows[#snoozedRows + 1] = row
					stored[row.id] = true
				else
					rows[#rows + 1] = row
				end
			end
		end
	end
	for id, z in pairs(snoozed) do
		if not stored[id] then
			local row = snapshotRow(id, z)
			if row ~= nil then snoozedRows[#snoozedRows + 1] = row end
		end
	end
	table.sort(rows, rowBefore)
	table.sort(snoozedRows, snoozeBefore)

	local tierCounts : {integer} = { 0, 0, 0 }
	local tabCounts : {string : integer} = { all = #rows, vehicles = 0, lines = 0, stations = 0, fleet = 0, economy = 0,
		snoozed = #snoozedRows }
	local hiddenByTab : {string : integer} = { all = 0, vehicles = 0, lines = 0, stations = 0, fleet = 0, economy = 0, snoozed = 0 }
	local rowsPerKind : {string : integer} = {}
	local worst = 0
	for __, r in ipairs(rows) do
		tierCounts[r.tier] = tierCounts[r.tier] + 1
		if ALERT_TABS[r.tab] then tabCounts[r.tab] = tabCounts[r.tab] + 1 end
		rowsPerKind[r.kind] = (rowsPerKind[r.kind] or 0) + 1
		if worst == 0 or r.tier < worst then worst = r.tier end
	end

	-- Alerts over the stored cap: counted per kind by the engine (state.kindCounts), not listed.
	local hidden = 0
	if type(st.kindCounts) == "table" then
		for kind, n in pairs(st.kindCounts as {any : any}) do
			local info = type(kind) == "string" and radar_checks.KINDS[kind as string] or nil
			local count = toInt(n)
			if info ~= nil and count ~= nil then
				local extra = count - (rowsPerKind[kind as string] or 0)
				if extra > 0 then
					hidden = hidden + extra
					tierCounts[info.tier] = tierCounts[info.tier] + extra
					tabCounts[info.tab] = tabCounts[info.tab] + extra
					tabCounts.all = tabCounts.all + extra
					hiddenByTab[info.tab] = hiddenByTab[info.tab] + extra
					hiddenByTab.all = hiddenByTab.all + extra
					if worst == 0 or info.tier < worst then worst = info.tier end
				end
			end
		end
	end
	local total = #rows + hidden

	local settings = radar_settings.normalize(st.settings)
	return {
		hudMode = settings.hudMode,
		settings = settings,
		total = total,
		hidden = hidden,
		hiddenByTab = hiddenByTab,
		tierCounts = tierCounts,
		tabCounts = tabCounts,
		worstTier = worst,
		badgeLabel = "",
		badgeText = "",
		compactText = "",
		rows = rows,
		snoozedRows = snoozedRows,
	}
end

function model.rowsForTab(view : ProblemRadarHudView, tab : string) : {ProblemRadarHudRow}
	local out : {ProblemRadarHudRow} = {}
	if view == nil or view.rows == nil then return out end
	for __, r in ipairs(view.rows) do
		if tab == "all" or r.tab == tab then out[#out + 1] = r end
	end
	return out
end

local function copyRow(r : ProblemRadarHudRow) : ProblemRadarHudRow
	local c : ProblemRadarHudRow = {}
	for k, v in pairs(r as {string : any}) do (c as {string : any})[k] = v end
	return c
end

--- The rows the window renders for a tab: at most `cap` (default MAX_RENDERED_ROWS), decorated, and
--- how many more the tab has (rows not rendered + alerts over the stored cap).
--- Decorated COPIES: the view is the useStepStateTimer state, which compares the next poll's fresh
--- (undecorated) view with it by deepEquals (engine_react_util.tl:126-145). Decorating the view's own
--- rows made every poll look like a change, so the open window rebuilt its rows every second.
function model.visibleRows(view : ProblemRadarHudView, tab : string, cap? : integer) : {ProblemRadarHudRow}, integer
	local limit = cap or model.MAX_RENDERED_ROWS
	local out : {ProblemRadarHudRow} = {}
	local matching = 0
	local snoozedTab = tab == model.SNOOZED_TAB
	local source = view ~= nil and (snoozedTab and view.snoozedRows or view.rows) or nil
	if source ~= nil then
		for __, r in ipairs(source) do
			if tab == "all" or snoozedTab or r.tab == tab then
				matching = matching + 1
				if #out < limit then
					out[#out + 1] = r.kindLabel == "" and model.decorate(copyRow(r)) or r
				end
			end
		end
	end
	local hidden = view ~= nil and view.hiddenByTab ~= nil and view.hiddenByTab[tab] or 0
	return out, matching - #out + hidden
end

--- Snooze clicks the engine has not confirmed yet, applied on top of a polled view so the row moves
--- at once (the window commits this view, base engine_react_util.useStepStateTimerWithCommit) and stays
--- moved until a poll shows the engine's own result. `snooze`: id -> estimated end (gameTime ms);
--- `wake`: ids to unsnooze. Returns the view itself when nothing applies, else a new view (the rows'
--- tables are shared; counts, rows and snoozedRows are fresh).
function model.applyPending(view : ProblemRadarHudView, snooze : {string : integer}, wake : {string : boolean}) : ProblemRadarHudView
	-- Nothing pending (every idle window poll): no walk over the rows.
	if view == nil or (next(snooze) == nil and next(wake) == nil) then return view end
	local any = false
	for __, r in ipairs(view.rows) do
		if snooze[r.id] ~= nil then any = true break end
	end
	if not any then
		for __, r in ipairs(view.snoozedRows) do
			if wake[r.id] then any = true break end
		end
	end
	if not any then return view end

	local out : ProblemRadarHudView = {}
	for k, v in pairs(view as {string : any}) do (out as {string : any})[k] = v end
	local tabCounts : {string : integer} = {}
	for k, v in pairs(view.tabCounts) do tabCounts[k] = v end
	local tierCounts : {integer} = { view.tierCounts[1], view.tierCounts[2], view.tierCounts[3] }
	local total = view.total
	local rows : {ProblemRadarHudRow} = {}
	local snoozedRows : {ProblemRadarHudRow} = {}
	local function count(r : ProblemRadarHudRow, d : integer)
		tierCounts[r.tier] = tierCounts[r.tier] + d
		tabCounts.all = tabCounts.all + d
		if tabCounts[r.tab] ~= nil and r.tab ~= "all" then tabCounts[r.tab] = tabCounts[r.tab] + d end
		total = total + d
	end
	for __, r in ipairs(view.rows) do
		local untilMs = snooze[r.id]
		if untilMs ~= nil then
			local c = copyRow(r)
			c.snoozedUntil = untilMs
			snoozedRows[#snoozedRows + 1] = c
			count(r, -1)
		else
			rows[#rows + 1] = r
		end
	end
	for __, r in ipairs(view.snoozedRows) do
		if wake[r.id] then
			if not r.gone then
				local c = copyRow(r)
				c.snoozedUntil = nil
				rows[#rows + 1] = c
				count(c, 1)
			end
		else
			snoozedRows[#snoozedRows + 1] = r
		end
	end
	table.sort(rows, rowBefore)
	table.sort(snoozedRows, snoozeBefore)
	tabCounts.snoozed = #snoozedRows
	out.rows = rows
	out.snoozedRows = snoozedRows
	out.tabCounts = tabCounts
	out.tierCounts = tierCounts
	out.total = total
	out.worstTier = tierCounts[1] > 0 and 1 or (tierCounts[2] > 0 and 2 or (tierCounts[3] > 0 and 3 or 0))
	return out
end

--- Rev 6: rows the GUI already knows are fixed (fleet rows of vehicles just replaced from the fleet
--- window, until the engine's recheck has dropped them) left out of a view, counts adjusted like
--- applyPending. Snoozed rows with those ids leave the Snoozed tab too. Returns the view itself when
--- nothing applies (the common idle poll: no copy).
function model.hideRows(view : ProblemRadarHudView, hide : {string : boolean}) : ProblemRadarHudView
	if view == nil or hide == nil or next(hide) == nil then return view end
	local any = false
	for __, r in ipairs(view.rows) do
		if hide[r.id] then any = true break end
	end
	if not any then
		for __, r in ipairs(view.snoozedRows) do
			if hide[r.id] then any = true break end
		end
	end
	if not any then return view end

	local out : ProblemRadarHudView = {}
	for k, v in pairs(view as {string : any}) do (out as {string : any})[k] = v end
	local tabCounts : {string : integer} = {}
	for k, v in pairs(view.tabCounts) do tabCounts[k] = v end
	local tierCounts : {integer} = { view.tierCounts[1], view.tierCounts[2], view.tierCounts[3] }
	local total = view.total
	local rows : {ProblemRadarHudRow} = {}
	for __, r in ipairs(view.rows) do
		if hide[r.id] then
			tierCounts[r.tier] = math.max(0, tierCounts[r.tier] - 1)
			tabCounts.all = math.max(0, tabCounts.all - 1)
			if tabCounts[r.tab] ~= nil and r.tab ~= "all" then tabCounts[r.tab] = math.max(0, tabCounts[r.tab] - 1) end
			total = math.max(0, total - 1)
		else
			rows[#rows + 1] = r
		end
	end
	local snoozedRows : {ProblemRadarHudRow} = {}
	for __, r in ipairs(view.snoozedRows) do
		if not hide[r.id] then snoozedRows[#snoozedRows + 1] = r end
	end
	tabCounts.snoozed = #snoozedRows
	out.rows = rows
	out.snoozedRows = snoozedRows
	out.tabCounts = tabCounts
	out.tierCounts = tierCounts
	out.total = total
	out.worstTier = tierCounts[1] > 0 and 1 or (tierCounts[2] > 0 and 2 or (tierCounts[3] > 0 and 3 or 0))
	return out
end

--- Creation revisions per alert id, so a click can tell a reused entity id from the entity the
--- alert was about (like the notification click, entity_util.entityChanged0). Revisions already
--- known are kept, new ids are looked up with `revOf` (nil when the entity is gone), ids no longer
--- listed are dropped.
function model.trackRevisions(prev : {string : integer}, rows : {ProblemRadarHudRow}, revOf : function(integer) : integer) : {string : integer}
	local out : {string : integer} = {}
	local old = prev or {}
	for __, r in ipairs(rows or {}) do
		if r.entity ~= nil and r.id ~= "" then
			local rev = old[r.id]
			if rev == nil then rev = revOf(r.entity) end
			out[r.id] = rev
		end
	end
	return out
end

--- Whether an entity still is the one an alert referred to: unknown revisions count as the same.
function model.sameRevision(saved : integer, current : integer) : boolean
	if saved == nil or current == nil then return true end
	return current <= saved
end

--- Window position (radar_hud.script.tl "WINDOW POSITION"), screen fractions. The content rect
--- (l, t)-(r, b) is moved fully on screen (its top at least minTop, below the ridge), then shifted by
--- the frame offset (dx, dy) = window anchor minus content top-left. nil for a rect that is not a
--- laid-out on-screen window (NaN, 0,0-0,0 before layout, far off screen).
function model.windowAnchor(l : number, t : number, r : number, b : number, dx : number, dy : number, minTop : number) : number, number
	local function ok(v : number) : boolean return v ~= nil and v == v and v > -0.5 and v < 1.5 end
	if not (ok(l) and ok(t) and ok(r) and ok(b) and ok(dx) and ok(dy)) then return nil, nil end
	local w, h = r - l, b - t
	if w <= 0.001 or h <= 0.001 or w > 1 or h > 1 then return nil, nil end
	local x = math.max(0, math.min(l, 1 - w))
	local y = math.max(minTop, math.min(t, 1 - h))
	return x + dx, y + dy
end

--- The remembered window anchor from the game settings ({ x, y } in 0..1); nil, nil when missing or malformed.
function model.readWindowPos(raw : any) : number, number
	if type(raw) ~= "table" then return nil, nil end
	local t = raw as {string : any}
	local function frac(v : any) : number
		if type(v) ~= "number" then return nil end
		local n = v as number
		if n ~= n or n < 0 or n > 1 then return nil end
		return n
	end
	local x, y = frac(t.x), frac(t.y)
	if x == nil or y == nil then return nil, nil end
	return x, y
end

return model
