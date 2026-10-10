-- Problem Radar HUD (ridge badge / compact panel) + the radar window (PLAN "Architecture";
-- Phase 1: skeleton + UI proof, Phase 2: alert rows from the engine's game-flag scans, Phase 5: the
-- full Settings tab, Phase 7: the Economy tab). GUI thread: read-only; settings go back to the engine script as
-- "ProblemRadar.setSetting" (only the changed key) / "ProblemRadar.resetSettings" events, which the
-- engine validates with radar_settings.tl. Never scans the world itself.
-- Modelled on .cache/game/base/content/gui/game_bar/game_bar_display_transported_plugin/
-- (.res.lua registers the plugin, .script.tl polls engine state, .css.lua styles R::<recipe>).
-- Widget types: .cache/game/base/tealdef/scripts/builtin.d.tl
--
-- MOUNT POINT "::MainModButtonAreaExtension" (radar_hud.res.lua): the visible mod slot in the
-- top-left button ridge (.cache/game/base/content/gui/main/main_mod_button_area.tl:13). The ridge
-- is a ScrollArea with verticalPolicy AlwaysOff (main_mod_button_area.tl:26-31): everything here
-- is ONE row high, anything taller is clipped. Lists live in the window.
--
-- ROWS: plain Button rows of TextViews, not DataTable. DataTable cells only get userParam when they
-- are created (builtin.d.tl:1161) and are keyed by integer rowKeys (statistic_vehicles.tl:409-414),
-- so live alert rows would need a ref read inside each cell. Phase 2 keeps the dense Button rows
-- (columns: tier · kind · type · entity · context · detail · metric, fixed widths in the .css.lua);
-- the list is capped by the engine (radar_checks.MAX_STORED_ALERTS), and the window renders only the
-- selected tab, at most hud_model.MAX_RENDERED_ROWS rows of it (Phase 6).
--
-- POLLING (Phase 6): each poll reads only the state fields it needs through the GAME_SCRIPT
-- component's state_native (NativeLuaTable:find / asTable, the base pattern of
-- industry.tl:56-64 and town_cargo_util.tl:64-72), so the timer maps and notify maps are never
-- copied into the GUI. The ridge HUD reads kindCounts + settings only (counts, no rows, no texts).

-- SQPERF (plans/sqperf/README.md): load time of this GUI Lua state, the first ridge render, slow
-- renders / clicks (> 16 ms, at most one line per section per minute), and with the "Debug:
-- performance log" mod setting a 30 s summary. The polls run in react onStepTimer callbacks (worker
-- threads "Main Pool N", engine_react_util.tl useStepStateTimer) and are timed too: api.type.Clock
-- is safe there (docs/findings.md "Timers and threads in GUI contexts"). Local counters only;
-- nothing is saved.
local sqperf = ug_require "square_problem_radar::/sqperf/square_problem_radar.lua" as SquareProblemRadarSqPerf
local perf = sqperf.new({ mod = "square_problem_radar", ctx = "gui", paramKey = "sqperf_log", first = { "hud_render" } })
local perfInit = perf:start()

local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local lang_util = ug_require "::/scripts/lang_util.tl" as LangUtil
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl" as MainModButtonArea
-- mod precedent for game_react_globals: .cache/game/mods/release/urbangames_campaign_mission_05/content/mission/perk_icons_replacement.script.tl:4
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl" as GameReactGlobals

local hud_model = ug_require "square_problem_radar::/radar/gui/radar_hud_model.tl" as ProblemRadarHudModel
local radar_settings = ug_require "square_problem_radar::/radar/radar_settings.tl" as ProblemRadarSettingsModule
local radar_checks = ug_require "square_problem_radar::/radar/radar_checks.tl" as ProblemRadarChecks

-- src: .cache/game/mods/release/urbangames_campaign_mission_08/content/mission/mission_story.tl:891 (mod gs name)
local GS_NAME <const> = "square_problem_radar::/radar/radar.gs"
local EVENT_ID <const> = "ProblemRadar"
local EV_SET_SETTING <const> = "ProblemRadar.setSetting"
local EV_RESET_SETTINGS <const> = "ProblemRadar.resetSettings"
local EV_SNOOZE <const> = "ProblemRadar.snooze"
local EV_UNSNOOZE <const> = "ProblemRadar.unsnooze"
local POLL_SECONDS <const> = 1.0
-- The window polls at the base default (engine_react_util 0.5 s): an idle poll reads one number
-- (state.seq) and stops there, so the faster rate costs little.
local WINDOW_POLL_SECONDS <const> = 0.5

-- Phase 7: the economy rows' money in the game's own format (api/util.d.tl:58; base use for a line's
-- 12-month balance: line_react_util.tl:637). The model itself stays pure.
hud_model.formatMoney = function(money : integer) : string
	return api.util.formatMoney(money)
end

local function sendEvent(name : string, param : table)
	-- src: .cache/game/api/tealdef/api/cmd.d.tl:788; GUI usage: .cache/game/base/content/game_mechanics/subventions/subventions_gui.tl:135
	api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", EVENT_ID, name, param))
end

--- Some top-level fields of our game-script state, as plain tables (nil when there is no state).
--- src: .cache/game/base/content/mission/mission_framework/mission_framework_react.tl:49-51 (GUI reads
--- GAME_SCRIPT state); field-level reads via state_native: industry.tl:56-64, town_cargo_util.tl:64-72.
--- Falls back to the full `state` copy if state_native is missing or fails.
local function readFields(keys : {string}) : ProblemRadarState
	local entity = api.engine.system.gameScriptSystem.getEntityForGameScript(GS_NAME)
	if entity == nil or entity < 0 then return nil end
	local gs = api.engine.getComponent(entity, api.type.ComponentType.GAME_SCRIPT) as Engine.Component.GameScript<ProblemRadarState>
	if gs == nil then return nil end
	local ok, out = pcall(function() : {string : any}
		local native = gs.state_native
		if native == nil then return nil end
		local t : {string : any} = {}
		for __, k in ipairs(keys) do
			local v = native:find(k) as any
			local tv = type(v)
			if v ~= nil and tv ~= "string" and tv ~= "number" and tv ~= "boolean" then
				t[k] = (v as NativeLuaTable):asTable()
			else
				t[k] = v
			end
		end
		return t
	end)
	if ok and out ~= nil then return out as ProblemRadarState end
	local st = gs.state as {string : any}
	if type(st) ~= "table" then return nil end
	local t : {string : any} = {}
	for __, k in ipairs(keys) do t[k] = st[k] end
	return t as ProblemRadarState
end

local HUD_FIELDS : {string} = { "kindCounts", "settings", "tierCounts" }
-- settings: the snooze length (button tooltips, the length picker).
local WINDOW_FIELDS : {string} = { "alerts", "kindCounts", "snoozed", "settings" }
local SETTINGS_FIELDS : {string} = { "settings" }

--- Creation revision of an entity (entity_util.makeEntityAndRevision0 reads num[1]); nil if gone.
local function revOf(e : integer) : integer
	if e == nil or e < 0 or not api.engine.entityExists(e) then return nil end
	local r = api.engine.getRevision(e)
	return r ~= nil and r.num ~= nil and r.num[1] as integer or nil
end

-- Alert id -> creation revision of its entity, recorded when the window first lists it, so a click
-- on a row whose entity id was reused does not open the wrong entity (Phase 6). GUI-local, pruned
-- to the listed ids every poll.
local rowRevs : {string : integer} = {}

--- Ridge HUD poll: counts only (never nil; a missing state gives zero counts, so the badge still
--- shows and proves the ridge renders).
local function getCountsFromEngine() : ProblemRadarHudCounts
	local t = perf:start() -- onStepTimer (worker thread): Clock is safe there
	local s = readFields(HUD_FIELDS)
	local settings = s ~= nil and type(s.settings) == "table" and s.settings or nil
	local counts = hud_model.counts(s ~= nil and s.kindCounts or nil, settings ~= nil and settings.hudMode or nil,
		s ~= nil and s.tierCounts or nil)
	perf:stop("poll_hud", t)
	return counts
end

local SEQ_FIELDS : {string} = { "seq" }

-- Snooze clicks the engine has not confirmed yet (hud_model.applyPending): id -> estimated end /
-- id -> true, and id -> os.time() of the click. A click on a pending id is ignored (no repeated
-- events while the engine catches up). Dropped once a poll shows the engine's result, or after
-- PENDING_TIMEOUT_S (the engine refused it, e.g. the alert just cleared). os.time, not
-- getApplicationTime: plain Lua, safe on any thread.
local pendingSnooze : {string : integer} = {}
local pendingWake : {string : boolean} = {}
local pendingAt : {string : integer} = {}
local PENDING_TIMEOUT_S <const> = 5

local function reconcilePending(raw : ProblemRadarHudView)
	if next(pendingAt) == nil then return end
	local snoozedIds : {string : boolean} = {}
	for __, r in ipairs(raw.snoozedRows) do snoozedIds[r.id] = true end
	local now = os.time()
	for id, at in pairs(pendingAt) do
		local done = now - at > PENDING_TIMEOUT_S
			or (pendingSnooze[id] ~= nil and snoozedIds[id])
			or (pendingWake[id] and not snoozedIds[id])
		if done then
			pendingAt[id], pendingSnooze[id], pendingWake[id] = nil, nil, nil
		end
	end
end

-- The last full read and the state.seq it was made at: an unchanged seq means an unchanged state.
local lastSeq : integer = nil
local lastRaw : ProblemRadarHudView = nil

--- Window poll: rows without translated texts (only the rendered rows get them), with the pending
--- snooze clicks applied. `old` == nil: the window just opened, so always a full read.
local function getFromEngine(old? : ProblemRadarHudView) : ProblemRadarHudView
	local t = perf:start() -- onStepTimer (worker thread): Clock is safe there
	local q = readFields(SEQ_FIELDS)
	local seq = q ~= nil and q.seq or nil
	if old == nil or lastRaw == nil or seq == nil or seq ~= lastSeq then
		local tFull = perf:start()
		lastRaw = hud_model.buildRaw(readFields(WINDOW_FIELDS))
		lastSeq = seq
		local all : {ProblemRadarHudRow} = {}
		for __, r in ipairs(lastRaw.rows) do all[#all + 1] = r end
		for __, r in ipairs(lastRaw.snoozedRows) do all[#all + 1] = r end
		rowRevs = hud_model.trackRevisions(rowRevs, all, revOf)
		perf:stop("poll_window_full", tFull)
	end
	reconcilePending(lastRaw)
	local view = hud_model.applyPending(lastRaw, pendingSnooze, pendingWake)
	perf:stop("poll_window", t)
	return view
end

--- Poll for the Settings tab: the normalised settings only, so alert updates do not re-render it
--- (useStepStateTimer compares with deepEquals, engine_react_util.tl:126-145).
local function getSettingsFromEngine() : ProblemRadarSettings
	local t = perf:start() -- onStepTimer (worker thread): Clock is safe there
	local s = readFields(SETTINGS_FIELDS)
	local settings = radar_settings.normalize(s ~= nil and s.settings or nil)
	perf:stop("poll_settings", t)
	return settings
end

local function text(str : string, class? : string) : TreeNodeId
	return builtin.TextView{
		meta = { class = class or "font-scale-body" },
		text = str,
	}
end

-- Every layout of ours carries "radar-box", so the .css.lua spacing rule targets only our own
-- BoxLayouts, never the ones inside base widgets (DoubleSpinBox, ToggleButtonGroup, ...).
local function boxClass(class : string) : string
	return class and (class .. ", radar-box") or "radar-box"
end

local function hbox(children : {TreeNodeId}, class? : string) : TreeNodeId
	return builtin.BoxLayout{
		meta = { class = boxClass(class) },
		orientation = builtin.type.Orientation.Horizontal,
		children = children,
	}
end

local function vbox(children : {TreeNodeId}, class? : string) : TreeNodeId
	return builtin.BoxLayout{
		meta = { class = boxClass(class) },
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end

--- "●" coloured by tier (radar_hud.css.lua: !radar-tier-0..3; 0 = no alerts, green).
local function dot(tier : integer) : TreeNodeId
	return text("●", "font-scale-body, radar-dot, radar-tier-" .. tostring(tier))
end

local function tierName(tier : integer) : string
	return hud_model.tierLabel(tier)
end

---------------------------------------------------------------------------
-- Row click: jump camera + open the game's own entity window (PLAN "Row action").
-- src: .cache/game/base/content/game_mechanics/notifications/notification_util.tl:442-455
--      (entityExists guard, camera.focusEntity, fireReactEvent "selectEntity" {entity, stack});
--      .cache/game/base/content/gui/statistics/statistic_vehicles.tl:39-41 (selectEntity, stack = true)
-- Path problems: focusPosition at the break location instead
-- (.cache/game/base/content/game_mechanics/notifications/types/line_warning.script.tl:194, distance 15).
-- API: .cache/game/api/tealdef/api/gui.d.tl:49 (fireReactEvent), :446-451 (camera)

local function focusRow(row : ProblemRadarHudRow)
	local entity = row.entity
	-- Same guard as the notification click (radar_notification.script.tl liveEntity): the entity must
	-- exist and still have the creation revision it had when the row was first listed.
	local exists = entity ~= nil and api.engine.entityExists(entity) and hud_model.sameRevision(rowRevs[row.id], revOf(entity))
	if row.pos ~= nil then
		api.gui.camera.focusPosition(api.type.Vec3f.new(row.pos[1], row.pos[2], row.pos[3]), 15)
	elseif exists then
		api.gui.camera.focusEntity(entity)
	end
	if exists then
		api.gui.fireReactEvent("selectEntity", { entity = entity, stack = true })
	end
end

--- Second click target: the other train (veh_blocked) or the blocker (train_blocked_by).
local function focusEntity2(row : ProblemRadarHudRow)
	local e = row.entity2
	if e == nil or not api.engine.entityExists(e) then return end
	api.gui.camera.focusEntity(e)
	api.gui.fireReactEvent("selectEntity", { entity = e, stack = true })
end

local SECOND_TARGET_KINDS : {string : boolean} = { veh_blocked = true, train_blocked_by = true }

-- Stable click handlers keyed by alert id (Phase 6): a refresh re-uses the same function for the
-- same row instead of a new closure per row per render; the handler looks the row up when clicked.
-- Pruned to the rendered ids on every render.
local shownRows : {string : ProblemRadarHudRow} = {}
local rowHandlers : {string : function()} = {}
local altHandlers : {string : function()} = {}
local snoozeHandlers : {string : function()} = {}

local function rowHandler(id : string) : function()
	local h = rowHandlers[id]
	if h == nil then
		h = function()
			local r = shownRows[id]
			if r ~= nil then focusRow(r) end
		end
		rowHandlers[id] = h
	end
	return h
end

local function altHandler(id : string) : function()
	local h = altHandlers[id]
	if h == nil then
		h = function()
			local r = shownRows[id]
			if r ~= nil then focusEntity2(r) end
		end
		altHandlers[id] = h
	end
	return h
end

-- The snooze length for the buttons' tooltips and the optimistic end: set by ProblemRadarContent
-- from the polled settings.
local snoozeMonths = radar_settings.NUMBERS.snoozeMonths.default

-- The window's state and commit fn (engine_react_util.useStepStateTimerWithCommit), set on every
-- render of ProblemRadarContent; nil while the window is closed.
local windowState : ReactStateT<ProblemRadarHudView> = nil
local windowCommit : function(ProblemRadarHudView, Command<ICommandData>) = nil

--- The snooze's end as the engine will compute it (radar.script.tl monthsMs), for the optimistic row;
--- the poll replaces it with the engine's own value.
local function estimateUntil() : integer
	local ok, v = pcall(function() : integer
		local world = api.engine.util.getWorld()
		local gt = api.engine.getComponent(world, api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
		local gs = api.engine.getComponent(world, api.type.ComponentType.GAME_SPEED) as Engine.Component.GameSpeed
		local mpd = gs ~= nil and gs.millisPerDay or 0
		local month = mpd ~= nil and mpd > 0 and api.util.getMonthDuration(mpd) or api.util.getDefaultMonthDuration()
		return math.floor(gt.gameTime + snoozeMonths * month)
	end)
	return ok and v or 0
end

--- Snooze button (alert tabs) / unsnooze button (Snoozed tab): the engine stores it (radar_checks.snooze).
--- The row moves at once: the click is recorded as pending and the window commits the view with it
--- applied, like the base notification dismiss (notification_popups.tl, useStepStateTimerWithCommit).
local function snoozeHandler(id : string) : function()
	local h = snoozeHandlers[id]
	if h == nil then
		h = function()
			local r = shownRows[id]
			if r == nil or pendingAt[id] ~= nil then return end
			local wake = r.snoozedUntil ~= nil
			if wake then pendingWake[id] = true else pendingSnooze[id] = estimateUntil() end
			pendingAt[id] = os.time()
			local cmd = api.cmd.makeScriptingSendEventCmd("", EVENT_ID, wake and EV_UNSNOOZE or EV_SNOOZE, { id = id })
			if windowState ~= nil and windowCommit ~= nil and windowState:old() ~= nil then
				windowCommit(hud_model.applyPending(windowState:old(), pendingSnooze, pendingWake), cmd as Command<ICommandData>)
			else
				api.cmd.sendCommand(cmd)
			end
		end
		snoozeHandlers[id] = h
	end
	return h
end

local SNOOZE_LABELS : {integer : string} = { [1] = "1 month", [6] = "6 months", [12] = "1 year", [60] = "5 years" }

local function monthsText(months : integer) : string
	local preset = SNOOZE_LABELS[months]
	if preset ~= nil then return _(preset) end
	return lang_util.format(_("{n} months"), { n = tostring(months) })
end

-- Per render (alertList): the calendar speed, read once, and the snooze buttons' tooltips (the same
-- for every row). untilTexts caches the formatted end dates by "<ms>:<millisPerDay>".
local renderMpd : integer = 0
local snoozeTipText = ""
local wakeTipText = ""
local untilTexts : {string : string} = {}
local untilTextCount = 0

--- A snooze's end as a calendar date (as base scripts/util.tl formatTimePoint); the game time when the
--- calendar is frozen (millisPerDay 0).
local function untilText(ms : integer) : string
	local key = tostring(ms) .. ":" .. tostring(renderMpd)
	local cached = untilTexts[key]
	if cached ~= nil then return cached end
	local ok, txt = pcall(function() : string
		if renderMpd == 0 then return api.util.formatGameTime(ms) end
		return api.util.formatDate(api.engine.util.getCalendarDate(ms), api.type.enum.DateFormat.MEDIUM)
	end)
	local out = lang_util.format(_("until {date}"), { date = ok and txt or "" })
	if untilTextCount >= 400 then untilTexts, untilTextCount = {}, 0 end
	untilTexts[key] = out
	untilTextCount = untilTextCount + 1
	return out
end

local function alertRow(row : ProblemRadarHudRow) : TreeNodeId
	local tip = row.tip
	if tip == nil then
		tip = row.detail
		if row.metric ~= "" then tip = tip .. " (" .. row.metric .. ")" end
	end
	local snoozed = row.snoozedUntil ~= nil
	local metric = snoozed and untilText(row.snoozedUntil) or row.metric
	local button = builtin.Button{
		meta = { class = "radar-row", tooltip = tip },
		content = hbox({
			dot(row.tier),
			text(tierName(row.tier), "font-scale-annotation, radar-cell-tier, radar-tier-" .. tostring(row.tier)),
			text(row.kindLabel, "font-scale-annotation, radar-cell-kind"),
			text(row.typeLabel, "font-scale-annotation, radar-cell-type"),
			text(row.label, "font-scale-body, radar-cell-label"),
			text(row.context, "font-scale-annotation, radar-cell-context"),
			text(row.detail, "font-scale-annotation, radar-cell-detail"),
			text(metric, "font-scale-annotation, radar-cell-metric"),
		}),
		onClick = rowHandler(row.id),
	}
	-- Sibling buttons (not nested inside the row button), so each has its own click. The snooze
	-- button leads the row, so it lines up in one column whether or not the row has a second target.
	local children : {TreeNodeId} = {
		builtin.Button{
			meta = { class = "radar-row-snooze", tooltip = snoozed and wakeTipText or snoozeTipText },
			content = text(snoozed and "×" or "Zz", "font-scale-annotation"),
			onClick = snoozeHandler(row.id),
		},
		button,
	}
	if row.entity2 ~= nil and SECOND_TARGET_KINDS[row.kind] then
		children[#children + 1] = builtin.Button{
			meta = { class = "radar-row-alt", tooltip = _("Show the other train") },
			content = text("→", "font-scale-annotation"),
			onClick = altHandler(row.id),
		}
	end
	-- Keyed by alert id (base precedent: notification_popups.tl, meta.localKey per notification), so a
	-- row that leaves the list doesn't hand new props to every row after it.
	return builtin.BoxLayout{
		meta = { class = boxClass(nil), localKey = row.id },
		orientation = builtin.type.Orientation.Horizontal,
		children = children,
	}
end

local function alertList(view : ProblemRadarHudView, tab : string) : TreeNodeId
	local rows, more = hud_model.visibleRows(view, tab)
	local shown : {string : ProblemRadarHudRow} = {}
	for __, r in ipairs(rows) do shown[r.id] = r end
	shownRows = shown
	local keepRow : {string : function()} = {}
	local keepAlt : {string : function()} = {}
	local keepSnooze : {string : function()} = {}
	for id in pairs(shown) do
		keepRow[id] = rowHandlers[id]
		keepAlt[id] = altHandlers[id]
		keepSnooze[id] = snoozeHandlers[id]
	end
	rowHandlers, altHandlers, snoozeHandlers = keepRow, keepAlt, keepSnooze

	local mpdOk, mpd = pcall(function() : integer
		local gs = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED) as Engine.Component.GameSpeed
		return gs ~= nil and gs.millisPerDay or 0
	end)
	renderMpd = mpdOk and mpd or 0
	snoozeTipText = lang_util.format(_("Snooze: hide this alert and its notifications for {time}"), { time = monthsText(snoozeMonths) })
	wakeTipText = _("Unsnooze: list and count this alert again")

	if #rows == 0 and more == 0 then
		local empty = tab == hud_model.SNOOZED_TAB and _("Nothing snoozed. Zz on a row hides it for a while.") or _("No problems detected")
		return vbox({ text(empty, "font-scale-body, radar-empty") }, "radar-list")
	end
	local children : {TreeNodeId} = {}
	for i, row in ipairs(rows) do children[i] = alertRow(row) end
	if more > 0 then
		-- Rows over the render cap (hud_model.MAX_RENDERED_ROWS) and alerts over the stored cap
		-- (radar_checks.MAX_STORED_ALERTS): counted, not listed.
		children[#children + 1] = text(lang_util.format(_("+{n} more (not listed)"), { n = tostring(more) }),
			"font-scale-annotation, radar-more")
	end
	-- ScrollArea pattern: .cache/game/base/content/gui/main/main_mod_button_area.tl:26-36
	return builtin.ScrollArea{
		meta = { class = "radar-list" },
		horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
		verticalPolicy = builtin.type.ScrollBarPolicy.AsNeeded,
		content = builtin.Component{
			layout = vbox(children),
		},
	}
end

---------------------------------------------------------------------------
-- Settings tab (Phase 5). Controls:
--   * ToggleButtonGroup: 1-based index, -1 = nothing selected (builtin.d.tl:878-894; base use
--     game_bar_widgets.tl:204-240, script_param_util.tl:441-451). HUD mode and the per-kind notify
--     level (3-way). Verified in game for the HUD mode (Phase 1).
--   * CheckBox: value 0/1, onValueChange(integer) (builtin.d.tl:1024-1031; base use
--     town_eow.script.tl:1041-1050). Pause notifications.
--   * DoubleSpinBox: min/max/step/value + onValueChange(number), the base's numeric input with
--     -/+ buttons and typing (builtin.d.tl:917-933; base use for integers: game_bar_widgets.tl:709-719
--     day/month/year with step 1.0, town_eow.script.tl:1065-1074 with math.floor). Integer thresholds.
-- Every change sends only the changed key; the engine validates it (radar_settings.apply / reset).

local HUD_MODE_LABELS : {string : string} = { badge = "Badge", compact = "Compact panel" }
local LEVEL_LABELS : {string : string} = { off = "Off", passive = "List", notify = "Notify" }

local NUMBER_GROUPS : {{string}} = {
	-- { group title, key, label, key, label, ... }
	-- Smoothing applies to every alert kind (radar_checks.merge); 0 = list / clear on the next scan.
	{ "Timing",
		"smoothSec", "Smoothing: problems must persist / linger (game seconds)",
		"snoozeMonths", "Snooze length: Zz on a row hides its alert for (game months)" },
	{ "Stuck vehicles (game minutes standing)",
		"stuckMinRoad", "Road vehicles", "stuckMinTram", "Trams", "stuckMinRail", "Trains (also waiting behind a train)",
		"stuckMinWater", "Ships", "stuckMinAir", "Aircraft" },
	{ "Lines",
		"lineOverloadFactor", "Over capacity: waiting at a stop, in vehicle loads",
		"lineUnderusedPct", "Underused: utilisation below",
		"lineClumpPct", "Bunching: vehicles closer than, of the interval",
		"lineGapPct", "Bunching: a gap longer than, of the interval",
		"lineSustainMin", "Line problems must last (game minutes)" },
	{ "Fleet",
		"wornPct", "Worn: condition at or below",
		"idleDepotDays", "Idle in depot for at least (days)" },
	-- Phase 7: line_unprofitable tiers by cost coverage + size of the loss, line_low_use by its yearly average.
	{ "Economy",
		"econLossWarnPct", "Losing money: poor when income covers less than, of vehicle costs",
		"econLossCritPct", "Losing money: very poor when income covers less than",
		"econLossSharePct", "Losing money: a big loss is at least, of all lines' vehicle costs (3× = very big)",
		"econLowUsePct", "Low use: yearly average utilisation below (Warning at half, Critical at a quarter)" },
}

-- A hint under a group's heading, where the numbers only make sense together.
local GROUP_HINTS : {string : string} = {
	Economy = "Losing money is a Warning when its coverage is poor or the loss is big, and Critical when both count: a very poor coverage with a big loss, or a poor coverage with a very big loss. Within a severity, bigger losses come first.",
}

local UNIT_LABELS : {string : string} = { min = "min", days = "days", ["%"] = "%", x = "×", s = "s", months = "months" }

local function rangeText(num : ProblemRadarNumberSetting) : string
	local unit = _(UNIT_LABELS[num.unit] or num.unit)
	return lang_util.format(_("{min}-{max} {unit} (default {default})"),
		{ min = tostring(num.min), max = tostring(num.max), unit = unit, default = tostring(num.default) })
end

local function numberRow(settings : ProblemRadarSettings, key : string, label : string) : TreeNodeId
	local num = radar_settings.NUMBERS[key]
	local current = (settings as {string : integer})[key] or num.default
	return hbox({
		text(_(label), "font-scale-annotation, radar-set-label"),
		builtin.DoubleSpinBox{
			meta = { class = "radar-set-spin" },
			min = num.min,
			max = num.max,
			step = 1.0,
			value = current,
			onValueChange = function(value : number)
				if type(value) ~= "number" then return end
				local v = math.floor(value + 0.5)
				if v < num.min then v = num.min end
				if v > num.max then v = num.max end
				if v ~= current then
					sendEvent(EV_SET_SETTING, { [key] = v })
				end
			end,
			virtualKeyboardTitle = _(label),
			virtualKeyboardDescription = rangeText(num),
		},
		text(rangeText(num), "font-scale-annotation, radar-set-range"),
	}, "radar-set-row")
end

local function levelRow(settings : ProblemRadarSettings, kind : string) : TreeNodeId
	local info = radar_checks.KINDS[kind]
	-- Phase 7 economy kinds scale from Info to their maxTier: coloured by the most severe one.
	local tier = info ~= nil and (info.maxTier or info.tier) or 3
	local level = settings.notify[kind] or radar_settings.NOTIFY_DEFAULTS[kind]
	local buttons : {Builtin.ToggleButtonGroupChildParam} = {}
	local selected = -1
	for i, l in ipairs(radar_settings.NOTIFY_LEVELS) do
		buttons[i] = { content = text(_(LEVEL_LABELS[l] or l), "font-scale-annotation") }
		if l == level then selected = i end
	end
	return hbox({
		text(hud_model.kindLabel(kind), "font-scale-annotation, radar-set-kind"),
		text(hud_model.kindTierLabel(kind), "font-scale-annotation, radar-set-tier, radar-tier-" .. tostring(tier)),
		builtin.ToggleButtonGroup{
			meta = { class = "radar-set-level" },
			buttons = buttons,
			selected = selected,
			onValueChange = function(index : integer)
				local l = radar_settings.NOTIFY_LEVELS[index]
				if l ~= nil and l ~= level then
					sendEvent(EV_SET_SETTING, { notify = { [kind] = l } })
				end
			end,
		},
	}, "radar-set-row")
end

local function generalSection(settings : ProblemRadarSettings) : {TreeNodeId}
	local buttons : {Builtin.ToggleButtonGroupChildParam} = {}
	local selected = -1
	for i, mode in ipairs(radar_settings.HUD_MODES) do
		buttons[i] = { content = text(_(HUD_MODE_LABELS[mode] or mode), "font-scale-annotation") }
		if mode == settings.hudMode then selected = i end
	end
	return {
		text(_("General"), "font-scale-body, radar-section"),
		hbox({
			text(_("HUD mode"), "font-scale-annotation, radar-set-kind"),
			builtin.ToggleButtonGroup{
				buttons = buttons,
				selected = selected,
				onValueChange = function(index : integer)
					local mode = radar_settings.HUD_MODES[index]
					if mode ~= nil and mode ~= settings.hudMode then
						sendEvent(EV_SET_SETTING, { hudMode = mode })
					end
				end,
			},
		}, "radar-set-row"),
		builtin.CheckBox{
			value = settings.notifyPaused and 1 or 0,
			onValueChange = function(v : integer)
				local paused = v == 1
				if paused ~= settings.notifyPaused then
					sendEvent(EV_SET_SETTING, { notifyPaused = paused })
				end
			end,
			label = _("Pause all radar notifications (alerts are still listed)"),
		},
	}
end

local ProblemRadarSettingsPage = react.RegisterRecipe("ProblemRadarSettingsPage", perf:wrap("settings_render", function() : TreeNodeId
	local state = engine_react_util.useStepStateTimer(getSettingsFromEngine, POLL_SECONDS)
	local settings = state:old() or radar_settings.defaults()

	local left : {TreeNodeId} = generalSection(settings)
	left[#left + 1] = text(_("Alerts"), "font-scale-body, radar-section")
	left[#left + 1] = text(_("Off: not checked or listed. List: shown in the radar only. Notify: also a game notification when the problem first appears."),
		"font-scale-annotation, radar-hint")
	left[#left + 1] = hbox({
		text(_("Alert"), "font-scale-annotation, radar-set-kind, radar-set-head"),
		text(_("Severity"), "font-scale-annotation, radar-set-tier, radar-set-head"),
		text(_("Level"), "font-scale-annotation, radar-set-head"),
	}, "radar-set-row")
	for __, kind in ipairs(radar_settings.NOTIFY_KINDS) do
		left[#left + 1] = levelRow(settings, kind)
	end

	local right : {TreeNodeId} = {}
	for __, group in ipairs(NUMBER_GROUPS) do
		right[#right + 1] = text(_(group[1]), "font-scale-body, radar-section")
		if GROUP_HINTS[group[1]] ~= nil then
			right[#right + 1] = text(_(GROUP_HINTS[group[1]]), "font-scale-annotation, radar-hint")
		end
		for i = 2, #group - 1, 2 do
			right[#right + 1] = numberRow(settings, group[i], group[i + 1])
		end
	end
	right[#right + 1] = text(_("Settings are saved with this savegame. You can also mute \"Problem Radar\" in the game's notification log filter."),
		"font-scale-annotation, radar-hint")
	right[#right + 1] = builtin.Button{
		meta = { class = "radar-reset", tooltip = _("Every radar setting back to its default, including the HUD mode") },
		content = text(_("Reset to defaults"), "font-scale-annotation"),
		onClick = function() sendEvent(EV_RESET_SETTINGS, {}) end,
	}

	-- ScrollArea pattern: .cache/game/base/content/gui/main/main_mod_button_area.tl:26-36
	-- The recipe sits in a BoxLayout (tabChild), so it must return a layout, not a component:
	-- the engine rejects a component here with "Recipe child must be a layout".
	return vbox({
		builtin.ScrollArea{
			meta = { class = "radar-list, radar-settings" },
			horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
			verticalPolicy = builtin.type.ScrollBarPolicy.AsNeeded,
			content = builtin.Component{
				layout = hbox({
					vbox(left, "radar-set-col"),
					vbox(right, "radar-set-col"),
				}),
			},
		},
	})
end))

---------------------------------------------------------------------------
-- Window. Pattern: a wrapper recipe around builtin.Window, like
-- .cache/game/base/content/gui/menu/main_page.tl:44-63 (closable, onClose removes it), opened with
-- addSingletonWindow (.cache/game/base/tealdef/scripts/builtin.d.tl:1216-1232). Tabs: TabWidget/TabWidgetChild
-- (builtin.d.tl:1086-1110), uncontrolled with initialValue like
-- .cache/game/base/content/gui/entity_window/town/town.tl:1295-1310, indicator class from
-- .cache/game/base/content/mission/mission_framework/mission_framework_react.tl:759.

local TAB_LABELS : {string : string} = {
	all = "All ({n})",
	vehicles = "Vehicles ({n})",
	lines = "Lines ({n})",
	stations = "Stations ({n})",
	fleet = "Fleet ({n})",
	economy = "Economy ({n})",
	snoozed = "Snoozed ({n})",
}

local function tabChild(key : string, label : string, item : TreeNodeId, footer? : TreeNodeId) : TreeNodeId
	return builtin.TabWidgetChild{
		localKey = "radar_tab_" .. key,
		value = key,
		indicator = text(label, "font-scale-tab-widget-indicator"),
		item = builtin.Component{
			layout = vbox(footer ~= nil and { item, footer } or { item }),
		},
	}
end

--- Under the alert lists: the snooze length picker (settings.snoozeMonths, presets
--- radar_checks.SNOOZE_MONTHS; a custom value from the Settings tab selects none).
local function snoozeFooter(settings : ProblemRadarSettings) : TreeNodeId
	local buttons : {Builtin.ToggleButtonGroupChildParam} = {}
	local selected = -1
	for i, m in ipairs(radar_checks.SNOOZE_MONTHS) do
		buttons[i] = { content = text(monthsText(m), "font-scale-annotation") }
		if m == settings.snoozeMonths then selected = i end
	end
	return hbox({
		text(_("Zz snoozes an alert for"), "font-scale-annotation, radar-footer-label"),
		builtin.ToggleButtonGroup{
			buttons = buttons,
			selected = selected,
			onValueChange = function(index : integer)
				local m = radar_checks.SNOOZE_MONTHS[index]
				if m ~= nil and m ~= settings.snoozeMonths then
					sendEvent(EV_SET_SETTING, { snoozeMonths = m })
				end
			end,
		},
	}, "radar-footer")
end

--- Under the Snoozed list: wake everything at once.
local function snoozedFooter(count : integer) : TreeNodeId
	if count == 0 then return nil end
	return hbox({
		text(_("Snoozed alerts are not counted or notified. When a snooze ends, a problem that is still there notifies again."),
			"font-scale-annotation, radar-footer-label"),
		builtin.Button{
			meta = { class = "radar-reset" },
			content = text(_("Unsnooze all"), "font-scale-annotation"),
			onClick = function() sendEvent(EV_UNSNOOZE, {}) end,
		},
	}, "radar-footer")
end

local ProblemRadarContent = react.RegisterRecipe("ProblemRadarContent", perf:wrap("window_render", function() : TreeNodeId
	-- The window polls on its own (same hook as the HUD), so it stays live while open.
	-- With commit: a snooze click shows at once (snoozeHandler), polls pause until the event is done.
	local state, commit = engine_react_util.useStepStateTimerWithCommit(getFromEngine, WINDOW_POLL_SECONDS)
	windowState, windowCommit = state, commit as function(ProblemRadarHudView, Command<ICommandData>)
	-- Controlled tab (value + onValueChange, like .cache/game/base/content/gui/menu/mod_manager_page.tl:286-300),
	-- so the selected tab survives every data refresh (the tabs' labels and items change each poll).
	local tabState = react.useState("all") as ReactStateT<string>
	local view = state:old() or hud_model.buildRaw(nil)
	local selected = tabState:old() or "all"
	-- Phase 6: only the selected tab builds its content (one list of at most MAX_RENDERED_ROWS rows,
	-- or the Settings page with its own poll); every other tab gets an empty placeholder until it
	-- is selected.
	snoozeMonths = view.settings.snoozeMonths
	local tabs : {TreeNodeId} = {}
	for __, key in ipairs(hud_model.TABS) do
		local label = lang_util.format(_(TAB_LABELS[key]), { n = tostring(view.tabCounts[key] or 0) })
		local on = key == selected
		tabs[#tabs + 1] = tabChild(key, label, on and alertList(view, key) or vbox({}), on and snoozeFooter(view.settings) or nil)
	end
	local sz = hud_model.SNOOZED_TAB
	local szOn = selected == sz
	tabs[#tabs + 1] = tabChild(sz, lang_util.format(_(TAB_LABELS[sz]), { n = tostring(view.tabCounts[sz] or 0) }),
		szOn and alertList(view, sz) or vbox({}), szOn and snoozedFooter(view.tabCounts[sz] or 0) or nil)
	tabs[#tabs + 1] = tabChild("settings", _("Settings"), selected == "settings" and ProblemRadarSettingsPage() or vbox({}))
	return vbox({
		builtin.TabWidget{
			orientation = builtin.type.TabOrientation.North,
			deselectAllowed = false,
			value = tabState:old(),
			onValueChange = function(newTab : string)
				if newTab ~= nil then tabState:set(newTab) end
			end,
			tabs = tabs,
		},
	}, "radar-content")
end))

local record ProblemRadarWindowParam
	onClose : function()
end

-- Window id: the .css.lua centres it with gravity + anchorPoint on "#" .. WINDOW_ID, exactly like the
-- base finance/company windows (.cache/game/base/content/game_mechanics/finance/finances.css.lua:54-57,
-- game_mechanics/company/company.css.lua:47-50; their Windows pass an id and no initialX/initialY,
-- finance/account.tl:140-155). Phase 1's initialX/initialY = 0.5/0.4 placed the window's top-left
-- corner there (anchorPoint defaults to the top-left), so it opened offset to the bottom right.
local WINDOW_ID <const> = "squareproblemradar.window"

local ProblemRadarWindow = react.RegisterWrapperRecipe("ProblemRadarWindow", builtin.Window, function(params : ProblemRadarWindowParam) : TreeNodeId
	-- WindowParam: builtin.d.tl:1186-1210
	return builtin.Window{
		id = WINDOW_ID,
		title = _("Problem Radar"),
		closable = true,
		movable = true,
		onClose = params.onClose,
		content = ProblemRadarContent(),
	}
end)

local function closeWindow()
	windowState, windowCommit = nil, nil
	local wa = game_react_globals.getDefaultWindowApi()
	if wa ~= nil then
		wa.removeAllWindows(ProblemRadarWindow)
	end
end

local function openWindow()
	-- getDefaultWindowApi may return nil (.cache/game/base/content/gui/main/game_react_globals.tl:14-20)
	local wa = game_react_globals.getDefaultWindowApi()
	if wa == nil then
		log.warning("[ProblemRadar] no window container; cannot open the radar window")
		return
	end
	wa.addSingletonWindow(ProblemRadarWindow, { onClose = closeWindow })
	wa.moveSingletonWindowToFront(ProblemRadarWindow)
end

--- Whether the radar window is open: its content recipe is mounted. The WindowAPI has no query
--- (builtin.d.tl:1216-1233), so this uses the content's poll state, set on every render and expired
--- by react once the window is gone (however it was closed).
local function windowOpen() : boolean
	return windowState ~= nil and not windowState:hasExpired()
end

--- Ridge button: open the window, or close it when it is already open (like the Industry Flows button).
--- SQPERF section "click_toggle" (onClick: GUI thread).
local toggleWindow = perf:wrap("click_toggle", function()
	if windowOpen() then
		closeWindow()
	else
		openWindow()
	end
end)

---------------------------------------------------------------------------
-- Ridge HUD.

--- hudMode "badge": "Radar ● 3", dot coloured by the worst tier; click opens the window.
local function badge(counts : ProblemRadarHudCounts) : TreeNodeId
	return builtin.Button{
		meta = { class = "radar-badge", tooltip = hud_model.compactText(counts.tierCounts) },
		content = hbox({
			text(_("Radar")),
			dot(counts.worstTier),
			text(tostring(counts.total)),
		}),
		onClick = toggleWindow,
	}
end

--- hudMode "compact": one always-on row "Radar ● 3 crit · 2 warn · 5 info"; the whole panel is a
--- button (like the badge) that opens the window.
local function compactPanel(counts : ProblemRadarHudCounts) : TreeNodeId
	return builtin.Button{
		meta = { class = "radar-panel, radar-compact", tooltip = _("Open or close Problem Radar") },
		content = hbox({
			text(_("Radar")),
			dot(counts.worstTier),
			text(hud_model.compactText(counts.tierCounts)),
		}),
		onClick = toggleWindow,
	}
end

--- A plugin recipe's root must be a layout: MainModButtonArea mounts plugins as BoxLayout children,
--- and a Component root fails with "Recipe child must be a layout".
--- Same shape as the base plugin
--- (.cache/game/base/content/gui/game_bar/game_bar_display_transported_plugin/game_bar_display_transported.tl:28).
local function pluginRoot(child : TreeNodeId) : TreeNodeId
	return builtin.BoxLayout{
		meta = { class = "radar-box" },
		orientation = builtin.type.Orientation.Horizontal,
		children = { child },
	}
end

-- SQPERF section "hud_render" (its first call includes the first poll, via useStateLazy).
local ProblemRadarHudPlugin = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension, "ProblemRadarHudPlugin", perf:wrap("hud_render", function() : TreeNodeId
	-- Hooks first, unconditionally (same order as the base transported plugin).
	local isMapEditorRef : ReactRefT<boolean> = react.useRefLazy(function() : boolean return api.gui.game.isMapEditor() end)
	-- src: .cache/game/base/content/gui/main/engine_react_util.tl:126-145 (deepEquals on the fresh view)
	local state = engine_react_util.useStepStateTimer(getCountsFromEngine, POLL_SECONDS)

	if isMapEditorRef:get() then
		return nil
	end
	local counts = state:old()
	if counts == nil then
		return nil
	end
	if counts.hudMode == "compact" then
		return pluginRoot(compactPanel(counts))
	end
	return pluginRoot(badge(counts))
end))

local result = {
	ProblemRadarHudPlugin = ProblemRadarHudPlugin,
}

perf:phase("init", perfInit)

return result
