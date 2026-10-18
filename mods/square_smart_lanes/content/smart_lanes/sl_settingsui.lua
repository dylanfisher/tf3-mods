-- Smart Lanes in-game settings panel (PLAN.md "In-game settings panel"): the light settings as construction-toolbar
-- params, one shared builder for the Smart Lanes road tool (sl_tool.script.lua getDefinition: shown with nothing
-- selected) and the base Crossing Tool (ACTION_LANE_MODIFIER_TOOL: always shown; inserted by a wrapper of
-- construction_react_util.forEachDefinition, M.wrapForEach). Lua 5.1 syntax; api, the GUI helpers and _() are passed
-- in or global at call time (tests: tests/square_smart_lanes/test_settings.lua).
--
-- The panel: one group (U.GROUP; labelled params in one group stack vertically, construction.tl:2023-2072, one
-- separator line above), each param with its label above its control (displayMode Vertical: the 314 px bar fits the
-- long German / Russian labels that way):
--   No lights at roundabouts and ramps   On | Off            (the base toggle; our content so a long value is not
--                                                             clipped by the bar's 50 px text rule)
--   Free curb turn at traffic lights     ComboBox Off / When safe / Always
--   Light phases                         ComboBox Game default / Smart Lanes
--   Automatic light timing               ComboBox Junctions I choose / All lights / Off   (the save's amode,
--                                                             sl_allmode.lua)
--   Keep timing adjusted: check interval x0.5 | x1 | x2 | x4
-- Values are the mod.json indices. A change goes to the game script as SmartLanes.auto op=setting (sl_settings.lua) or
-- op=mode (Automatic light timing: All lights = the old "Adjust all lights", Junctions I choose = "Stop for all
-- lights", which from All lights also unenrolls every junction, Off pauses every junction and keeps the list), and
-- shows at once (Settings.setPending).
--
-- What the bar shows: a param's shown value is the menu's stored value, else its default, both read every step
-- (construction.tl:1044-1051, 1081-1084); getParam returns our own param table (definition.params[i], 1978-1987;
-- shallowCopy keeps it). So checkEnabledFn, called every step (updateDisabledParams), sets param.defaultIndex to the
-- value in force before any click, and after the first click (whose onChangeFn hands over the params api) writes
-- the stored value (preserveValueInAllCategories: category -1, shared by both tools) whenever it differs. Unverified in
-- game (TESTING.md "SP"). Our params are not constructionParam: no construction or tool action ever reads them.

local Settings = ug_require "square_smart_lanes::/smart_lanes/sl_settings.lua"
local AllMode = ug_require "square_smart_lanes::/smart_lanes/sl_allmode.lua"

local M = {}

M.GROUP = "sqrl-settings" -- dashes: a group id is a CSS class (no rule targets it)
M.ORDER = { "lights", "freeTurn", "phases", "amode", "every" }
M.KEYS = { lights = "sqrl_set_lights", freeTurn = "sqrl_set_free_turn", phases = "sqrl_set_light_phases",
	amode = "sqrl_set_auto_lights", every = "sqrl_set_auto_every" }
M.PARAM_OF = { lights = "sqrl_lights", freeTurn = "sqrl_free_turn", phases = "sqrl_light_phases",
	amode = "sqrl_auto_lights", every = "sqrl_auto_every" }
M.N = { lights = 2, freeTurn = 3, phases = 2, amode = 3, every = 4 }
M.CROSSING_ACTION = "ACTION_LANE_MODIFIER_TOOL"
M.UNDERGROUND = "undergroundMode"
M.EVENT_ID = "square_smart_lanes"
M.EV_AUTO = "SmartLanes.auto"
M.STORED_CATEGORY = -1 -- preserveValueInAllCategories (construction.tl:1041, 1874-1876)

-- Per Lua state: the menu's params api (from the first onChangeFn), this mod's raw mod params (fixed for a session)
M.state = { paramsApi = nil, raw = nil, rawRead = false }

--- The texts of a setting (translated at call time, GUI Lua state). mod.json's own name and tooltip (the same keys),
-- plus a line on the per-save scope.
function M.texts(name)
	local note = _("Set here, it applies to this game only and is saved with it.\nThe mod setting stays the default for new games.")
	local t
	if name == "lights" then
		t = { name = _("No lights at roundabouts and ramps"),
			tip = _("On: turns off the game's automatic traffic lights at roundabouts\nand where a slip lane or ramp leaves or joins a road, right\nafter you build them and when you use the Smart Lanes tool.\nCrossroads and T-junctions keep the game's own choice.\nOff: the game decides everywhere."),
			values = { _("On"), _("Off") } }
	elseif name == "freeTurn" then
		t = { name = _("Free curb turn at traffic lights"),
			tip = _("When safe: at crossroads and T-junctions with traffic lights,\nthe turn toward the curb (right in right-hand traffic, left in\nleft-hand traffic) also goes in light phases where nothing\ncrosses its path: no green traffic into a lane nearer the curb,\nno green crosswalk on the two roads it drives over. It may\nmerge with green traffic that enters the same lane.\nAlways: free in every phase, even across green traffic and\ncrosswalks (turning vehicles do not give way).\nBoth free a curb turn only where its lane turns and nothing\nelse: where that lane also goes straight (on roads with one or\ntwo lanes each way), the turn waits with it, as the car in front\nwould block it anyway.\nSet when Smart Lanes handles the junction, after you build it\nor with the Smart Lanes tool; the tool's Reset locks it again.\nOff: the game's phases (the turn waits with its road)."),
			values = { _("Off"), _("When safe"), _("Always") } }
	elseif name == "phases" then
		t = { name = _("Light phases"),
			tip = _("Game default: crossroads and T-junctions with traffic lights\nkeep the game's own light phases.\nSmart Lanes: Smart Lanes plans their phases from its lanes.\nEach road gets one long green for both of its directions, with\nevery lane at once (turns included, as in the game's phases),\nthen a short phase for pedestrians only clears the junction\nbefore the cross road gets its green. A curb turn on a lane of\nits own also goes where it only merges into green traffic (as\nFree curb turn When safe).\nSet when Smart Lanes handles the junction, after you build it\nor with the Smart Lanes tool; the tool's Reset restores the\ngame's phases. Free curb turn is not applied on top.\nA light you switch on later gets them too, while \"Apply\nautomatically to new roads\" is On."),
			values = { _("Game default"), _("Smart Lanes") } }
	elseif name == "amode" then
		t = { name = _("Automatic light timing"),
			tip = _("Junctions I choose: Keep timing adjusted runs only where you\nchoose Yes in the Smart Lanes tool.\nAll lights: every junction with traffic lights, also ones built\nlater. Choose No at a junction to leave it out. Lights you timed\nby hand stay as they are until you choose Yes there.\nOff: no junction is adjusted and no waiting cars are counted.\nYour Yes choices are kept for when you switch it back on.\nAt most 1000 junctions. A game can also choose its own in the\nSmart Lanes tool or the Crossing Tool.") -- i18n: ignore
				.. "\n" .. _("Choosing Junctions I choose here also stops it at every\njunction where it runs now: then choose Yes at the ones you want."), -- i18n: ignore (two paragraphs, each a whole text)
			values = { _("Junctions I choose"), _("All lights"), _("Off") } }
	elseif name == "every" then
		t = { name = _("Keep timing adjusted: check interval"),
			tip = _("Multiplies the time between two checks of a junction with\nKeep timing adjusted (x1: 10 to 60 game minutes). Shorter\nreacts sooner but changes the lights more often; longer\nmakes fewer changes. The counts of waiting cars (every 2 game\nminutes) and their 20-minute average are not affected."),
			values = { _("x0.5"), _("x1"), _("x2"), _("x4") } }
	else
		return nil
	end
	t.tip = t.tip .. "\n\n" .. note
	return t
end

--- This mod's raw mod params (read once per Lua state; nil when unreadable).
local function rawParams(api)
	local st = M.state
	if not st.rawRead then
		local ok, all = pcall(function() return api.engine.config.getModParams() end)
		st.raw = ok and type(all) == "table" and all["square_smart_lanes"] or nil
		st.rawRead = ok
	end
	return st.raw
end

--- The 1-based value of a panel setting in force (the save's override, a value sent from here, else mod.json).
function M.current(api, name)
	local raw = rawParams(api)
	if name == "amode" then
		local mode = AllMode.effective(AllMode.settingOf(raw), Settings.amodeNow())
		for i, m in ipairs(Settings.AMODES) do
			if m == mode then return i end
		end
		return 1
	end
	return Settings.index(name, raw)
end

--- Sends a SmartLanes.auto event (never throws). Returns whether it went out.
function M.send(api, payload)
	local ok = pcall(function()
		api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", M.EVENT_ID, M.EV_AUTO, payload))
	end)
	return ok
end

--- A click on a panel setting (onChangeFn): the clicked value is the intent; the value in force changes nothing.
-- opts: src ("tool" | "crossing"), setLightMode(mode) (the tool's controller: its mirror and result line follow at
-- once), emit(kind, fields) (log). Returns "sent" | "same" | "bad".
function M.change(api, name, value, paramsApi, opts)
	opts = opts or {}
	if paramsApi ~= nil then M.state.paramsApi = paramsApi end
	local n = M.N[name]
	if n == nil or type(value) ~= "number" or value ~= math.floor(value) or value < 1 or value > n then return "bad" end
	if value == M.current(api, name) then return "same" end
	local src = opts.src == "crossing" and "crossing" or "tool"
	local sent
	if name == "amode" then
		local mode = Settings.AMODES[value]
		if opts.setLightMode ~= nil then
			sent = pcall(opts.setLightMode, mode)
		else
			sent = M.send(api, { op = "mode", mode = mode, src = src })
		end
		Settings.setPending("amode", mode)
	else
		sent = M.send(api, { op = "setting", key = name, value = value, src = src })
		Settings.setPending(name, value)
	end
	if opts.emit ~= nil then
		pcall(opts.emit, "SETTINGS", { { "op", "click" }, { "key", name }, { "value", value }, { "src", src },
			{ "sent", sent and 1 or 0 } })
	end
	return "sent"
end

--- Every step (checkEnabledFn): the shown value follows the value in force (param.defaultIndex; the stored value
-- once one exists), then "Enabled" or, when opts.shown() says no, "Hidden".
function M.check(api, param, name, opts)
	pcall(Settings.poll, api, false)
	local okC, cur = pcall(M.current, api, name)
	if okC and type(cur) == "number" then
		param.defaultIndex = cur
		local pa = M.state.paramsApi
		if pa ~= nil then
			pcall(function()
				local stored = pa.getStoredValues(M.STORED_CATEGORY)
				if type(stored) == "table" and stored[param.key] ~= nil and stored[param.key] ~= cur then
					stored[param.key] = cur
				end
			end)
		end
	end
	if opts ~= nil and opts.shown ~= nil then
		local okS, shown = pcall(opts.shown)
		if okS and shown == false then return "Hidden" end
	end
	return "Enabled"
end

--- The panel's params, a fresh list (each param table is mutated by M.check). opts: src ("tool" | "crossing"),
-- shown() -> bool (nil: always), setLightMode(mode) or nil, emit(kind, fields) or nil, content(label) -> recipe for a
-- toggle value's button content (nil: the base text).
function M.params(api, opts)
	opts = opts or {}
	local E = api.type.enum
	local list = {}
	for _, name in ipairs(M.ORDER) do
		local t = M.texts(name)
		local toggle = name == "lights" or name == "every"
		local tips = {}
		for i = 1, #t.values do tips[i] = t.tip end
		local okC, cur = pcall(M.current, api, name)
		local p = {
			key = M.KEYS[name],
			name = t.name,
			tooltip = t.tip,
			tooltips = tips,
			values = t.values,
			defaultIndex = okC and cur or 1,
			group = M.GROUP,
			uiType = toggle and E.ScriptParamType.Button or E.ScriptParamType.ComboBox,
			displayMode = E.ScriptParamDisplayMode and E.ScriptParamDisplayMode.Vertical or nil,
			yearFrom = 0,
			yearTo = 0,
			location = E.ScriptParamLocation.Toolbar,
			preserveValueInAllCategories = true,
		}
		if toggle and name == "lights" and opts.content ~= nil then
			local labels = t.values
			p.makeCompactButtonFn = function(value)
				return opts.content(labels[value] or tostring(value), t.tip)
			end
		end
		p.onChangeFn = function(newValue, paramsApi, _oldValue)
			M.change(api, name, newValue, paramsApi, opts)
		end
		p.checkEnabledFn = function(_params)
			return M.check(api, p, name, opts)
		end
		list[#list + 1] = p
	end
	return list
end

---------------------------------------------------------------------------
-- The Crossing Tool

local function items(list)
	local out = {}
	if list == nil then return out end
	for i = 1, 200 do
		local okI, v = pcall(function() return list[i] end)
		if not okI or v == nil then break end
		out[#out + 1] = v
	end
	return out
end

--- Inserts the panel's params (makeParams() -> list) into a Crossing Tool definition, before Underground (else at the
-- end); a fresh list (the old one may be shared). Nothing for another action, or when ours are there already.
-- Returns "inserted" | "present" | "other".
function M.insertInto(definition, makeParams)
	if type(definition) ~= "table" or definition.action ~= M.CROSSING_ACTION then return "other" end
	local old = items(definition.params)
	for _, p in ipairs(old) do
		if type(p) == "table" and p.key == M.KEYS.lights then return "present" end
	end
	local ours = makeParams()
	local out, placed = {}, false
	for _, p in ipairs(old) do
		if not placed and type(p) == "table" and p.key == M.UNDERGROUND then
			for _, o in ipairs(ours) do out[#out + 1] = o end
			placed = true
		end
		out[#out + 1] = p
	end
	if not placed then
		for _, o in ipairs(ours) do out[#out + 1] = o end
	end
	definition.params = out
	return "inserted"
end

--- Wraps cru.forEachDefinition (the module table the construction menu calls, construction.tl:4279-4287) once per
-- module table: every definition passes M.insertInto before the menu's callback. The function in place at install is
-- kept in the chain (Better Bus Overlay wraps it too, either order). An error in ours never reaches the menu.
-- onInsert(result) after each Crossing Tool insert (log). Returns "installed" | "already" | "missing".
function M.wrapForEach(cru, makeParams, onInsert)
	if type(cru) ~= "table" or type(cru.forEachDefinition) ~= "function" then return "missing" end
	if cru.__sqrlSettingsPatched then return "already" end
	cru.__sqrlSettingsPatched = true
	local base = cru.forEachDefinition
	cru.forEachDefinition = function(fn, repository, ...)
		return base(function(definition, ...)
			local okI, res = pcall(M.insertInto, definition, makeParams)
			if onInsert ~= nil and (not okI or res ~= "other") then pcall(onInsert, okI and res or ("error:" .. tostring(res))) end
			return fn(definition, ...)
		end, repository, ...)
	end
	return "installed"
end

return M
