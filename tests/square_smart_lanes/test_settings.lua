-- square_smart_lanes in-game settings panel (PLAN.md "In-game settings panel"): sl_settings.lua (the per-save
-- overrides: decode, event validation, the mirror with its pending values, the saved-state reader), the game script's
-- op=setting handler and the GUI pass re-deriving its settings (sl_lanes.script.lua), the runtime's re-derived check
-- interval (sl_autoretime.lua), and sl_settingsui.lua (the toolbar params, their shown value, the clicks, the Crossing
-- Tool insertion and the forEachDefinition wrapper, also through sl_tool.script.lua). The tool's end-to-end path
-- (a click -> the saved state -> the write path's settings) is in test_tool.lua "settings panel".

local Settings = ug_require "square_smart_lanes::/smart_lanes/sl_settings.lua"
local UI = ug_require "square_smart_lanes::/smart_lanes/sl_settingsui.lua"
local Auto = ug_require "square_smart_lanes::/smart_lanes/sl_auto.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local AllMode = ug_require "square_smart_lanes::/smart_lanes/sl_allmode.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local makeGame = assert(loadfile(here .. "fakegame.lua", "t", _ENV))()
local MOD_DIR = here .. "../../mods/square_smart_lanes/"

local function has(line, text) return line ~= nil and line:find(text, 1, true) ~= nil end

-- a fake clock for the mirror's poll and pending times
local T = { now = 100 }
before_each(function()
	clear_logs()
	T.now = 100
	Settings.clock = function() return T.now end
	Settings.resetMirror()
	UI.state = { paramsApi = nil, raw = nil, rawRead = false }
end)

--- mod.json's params by key (name, tooltip, values, defaultIndex 0-based).
local function modJson()
	local f = assert(io.open(MOD_DIR .. "mod.json", "r"))
	local text = f:read("*a")
	f:close()
	local out = {}
	-- each param object: "key": "...", then its "tooltip": "..." (escaped \n kept as in the file)
	for key, body in text:gmatch('"key":%s*"([%w_]+)"(.-)"defaultIndex"') do
		local tip = body:match('"tooltip":%s*"(.-[^\\])"')
		out[key] = { tooltip = tip and tip:gsub("\\n", "\n"):gsub('\\"', '"') or nil,
			default = tonumber(text:match('"key":%s*"' .. key .. '".-"defaultIndex":%s*(%d+)')) }
	end
	return out
end

---------------------------------------------------------------------------
-- sl_settings.lua: decode, validation, apply

test("settings: the items match mod.json and Rules / Auto (keys, value counts, defaults)", function()
	local mj = modJson()
	for _, it in ipairs(Settings.ITEMS) do
		ok(mj[it.key] ~= nil, it.key .. " in mod.json")
		eq(mj[it.key].default + 1, it.default, it.key .. " default")
	end
	eq(Settings.BY_NAME.lights.key, Rules.KEYS.lights)
	eq(Settings.BY_NAME.freeTurn.key, Rules.KEYS.freeTurn)
	eq(Settings.BY_NAME.phases.key, Rules.KEYS.phases)
	eq(Settings.BY_NAME.every.key, Auto.PARAM_EVERY)
	eq({ Settings.BY_NAME.lights.n, Settings.BY_NAME.freeTurn.n, Settings.BY_NAME.phases.n, Settings.BY_NAME.every.n },
		{ #Rules.VALUES.lights, #Rules.VALUES.freeTurn, #Rules.VALUES.phases, #Auto.EVERY_FACTORS })
	eq({ Settings.BY_NAME.lights.default, Settings.BY_NAME.freeTurn.default, Settings.BY_NAME.phases.default },
		{ Rules.DEFAULTS.lights, Rules.DEFAULTS.freeTurn, Rules.DEFAULTS.phases })
	eq(Settings.BY_NAME.every.default, Auto.EVERY_DEFAULT)
	eq(Settings.AMODES, AllMode.MODES)
	eq(Settings.GS_NAME, Auto.GS_NAME)
end)

test("settings: merged raw -> one decode (Rules.fromModParams, Auto.everyFactorOf); bad overrides ignored", function()
	local raw = { sqrl_lights = 1, sqrl_free_turn = 3, sqrl_light_phases = 1, sqrl_auto_every = 2, sqrl_auto = 1 }
	local m = Settings.merged(raw, { phases = 2, freeTurn = 1, lights = 2, every = 4 })
	local cfg = Rules.fromModParams(m)
	eq({ cfg.phases, cfg.freeTurn, cfg.lights, cfg.auto }, { "sl", "off", false, true })
	eq(Auto.everyFactorOf(m), 4)
	eq(raw.sqrl_light_phases, 1, "the mod params are never changed")
	-- garbage overrides change nothing; nil raw: the defaults with the overrides
	eq(Settings.merged(raw, { phases = 3, freeTurn = 1.5, lights = "2", bogus = 1 }), raw)
	eq(Rules.fromModParams(Settings.merged(nil, { phases = 2 })).phases, "sl")
	eq(Rules.fromModParams(Settings.merged(nil, nil)), Rules.fromModParams(nil))
	-- index: the override, else mod.json, else the default
	eq(Settings.index("freeTurn", nil), 3)
	eq(Settings.index("freeTurn", { sqrl_free_turn = 2 }), 2)
	Settings.setMirror(1, { freeTurn = 1 }, nil)
	eq(Settings.index("freeTurn", { sqrl_free_turn = 2 }), 1)
	eq(Settings.index("nope", nil), nil)
end)

test("settings: event validation (op=setting through Auto.validate) and apply (sset / sseq, nothing for no change)", function()
	eq({ Settings.validate({ key = "phases", value = 2 }) }, { "phases", 2 })
	eq({ Settings.validate({ key = "every", value = 4 }) }, { "every", 4 })
	eq({ Settings.validate({ key = "amode", value = 1 }) }, { nil, "key" }, "Automatic light timing goes as op=mode")
	eq({ Settings.validate({ key = "phases", value = 3 }) }, { nil, "value" })
	eq({ Settings.validate({ key = "phases", value = 1.5 }) }, { nil, "value" })
	eq({ Settings.validate({ key = "phases", value = 0 / 0 }) }, { nil, "value" })
	eq({ Settings.validate({ key = "phases" }) }, { nil, "value" })
	eq({ Settings.validate("x") }, { nil, "not_table" })
	local op, nodes, src, _run, extra = Auto.validate({ op = "setting", key = "lights", value = 2, src = "crossing" })
	eq({ op, #nodes, src, extra }, { "setting", 0, "crossing", { key = "lights", value = 2 } })
	op, nodes, src = Auto.validate({ op = "setting", key = "lights", value = 2 })
	eq({ op, src }, { "setting", "tool" }, "default src")
	eq({ Auto.validate({ op = "setting", key = "lights", value = 2, src = "stress" }) }, { nil, "src" })
	eq({ Auto.validate({ op = "setting", key = "x", value = 2 }) }, { nil, "key" })
	eq({ Auto.validate({ op = "setting", key = "lights", value = 9 }) }, { nil, "value" })
	eq(Auto.validate({ op = "mode", mode = "all", src = "crossing" }), "mode", "the Crossing Tool's Automatic light timing")
	local s = {}
	eq(Settings.apply(s, "phases", 2), true)
	eq({ s.sset, s.sseq }, { { phases = 2 }, 1 })
	eq(Settings.apply(s, "phases", 2), false, "no change: nothing written")
	eq(s.sseq, 1)
	eq(Settings.apply(s, "every", 1), true)
	eq({ s.sset, s.sseq }, { { phases = 2, every = 1 }, 2 })
	eq(Settings.apply(s, "every", 7), false)
	-- a malformed saved sset is cleaned on the next write
	local t = { sset = { phases = "x", lights = 2, junk = 1 }, sseq = 4 }
	eq(Settings.apply(t, "freeTurn", 2), true)
	eq({ t.sset, t.sseq }, { { lights = 2, freeTurn = 2 }, 5 })
	eq(Settings.clean({ phases = 9 }), nil)
end)

---------------------------------------------------------------------------
-- The mirror

test("mirror: a sent value shows at once; dropped when saved, replaced by a newer seq, or after PENDING_S", function()
	Settings.setMirror(nil, nil, nil)
	local v0 = Settings.mirror.version
	Settings.setPending("phases", 2)
	eq(Settings.overNow(), { phases = 2 })
	ok(Settings.mirror.version > v0, "version moved")
	-- the game script has not stored it yet (same seq): still pending
	eq(Settings.setMirror(nil, nil, nil), false)
	eq(Settings.overNow(), { phases = 2 })
	-- stored: the saved value, pending dropped, nothing changed in force
	eq(Settings.setMirror(1, { phases = 2 }, nil), false)
	eq(Settings.mirror.pending, {})
	eq(Settings.overNow(), { phases = 2 })
	-- a newer seq holding another value replaces a pending one
	Settings.setPending("phases", 1)
	eq(Settings.overNow(), { phases = 1 })
	eq(Settings.setMirror(2, { phases = 2, every = 3 }, nil), true)
	eq(Settings.overNow(), { phases = 2, every = 3 })
	-- a lost event: after PENDING_S the saved value is back
	Settings.setPending("lights", 2)
	eq(Settings.overNow().lights, 2)
	T.now = T.now + Settings.PENDING_S + 1
	eq(Settings.overNow().lights, nil)
	-- amode: pending until the saved amode holds it or moves
	Settings.setPending("amode", "all")
	eq(Settings.amodeNow(), "all")
	Settings.setMirror(2, { phases = 2, every = 3 }, nil)
	eq(Settings.amodeNow(), "all", "not saved yet")
	Settings.setMirror(2, { phases = 2, every = 3 }, "all")
	eq({ Settings.amodeNow(), Settings.mirror.pending.amode }, { "all", nil })
	Settings.setPending("amode", "pick")
	Settings.setMirror(2, { phases = 2, every = 3 }, "garbage")
	eq(Settings.amodeNow(), nil, "the saved amode moved (to none): the pending one goes")
end)

local function gsApi(comp)
	return { type = { ComponentType = { GAME_SCRIPT = "GS" } }, engine = {
		system = { gameScriptSystem = { getEntityForGameScript = function() return comp and 5 or -1 end } },
		getComponent = function() return comp end,
		config = { getModParams = function() return { square_smart_lanes = { sqrl_light_phases = 1, sqrl_auto_every = 2 } } end },
	} }
end

test("readSaved / poll: state_native (sset only when sseq moved), the state copy, unreadable keeps the mirror; at most every POLL_S", function()
	local finds = {}
	local saved = { sseq = 3, sset = { phases = 2 }, amode = "all" }
	local native = { find = function(_, k)
		finds[#finds + 1] = k
		local v = saved[k]
		if type(v) == "table" then return { asTable = function() return v end } end
		return v
	end }
	local api = gsApi({ state_native = native })
	eq({ Settings.readSaved(api, nil) }, { true, 3, { phases = 2 }, "all" })
	finds = {}
	eq({ Settings.readSaved(api, 3) }, { true, 3, "same", "all" })
	eq(finds, { "sseq", "amode" }, "sset not read while sseq is unchanged")
	-- the state copy when state_native fails
	local copy = gsApi({ state_native = { find = function() error("native") end }, state = { sseq = 1, sset = { lights = 2 } } })
	eq({ Settings.readSaved(copy, nil) }, { true, 1, { lights = 2 }, nil })
	eq({ Settings.readSaved(gsApi({ state = nil }), nil) }, { true, nil, nil, nil }, "nothing saved yet")
	eq(Settings.readSaved(gsApi(nil), nil), false, "no game script")
	eq(Settings.readSaved({}, nil), false, "no api")
	-- poll: reads, then at most every POLL_S; force reads now
	eq(Settings.poll(api, false), true)
	eq({ Settings.overNow(), Settings.amodeNow() }, { { phases = 2 }, "all" })
	saved.sseq, saved.sset = 4, { phases = 1 }
	eq(Settings.poll(api, false), false, "within POLL_S")
	eq(Settings.overNow(), { phases = 2 })
	T.now = T.now + Settings.POLL_S
	eq(Settings.poll(api, false), true)
	eq(Settings.overNow(), { phases = 1 })
	-- unchanged sseq: the mirror keeps its sset
	T.now = T.now + Settings.POLL_S
	eq(Settings.poll(api, false), false)
	eq(Settings.overNow(), { phases = 1 })
	-- unreadable: kept
	eq(Settings.poll(gsApi(nil), true), false)
	eq(Settings.overNow(), { phases = 1 })
	-- effectiveRaw: the mod params with the overrides (the write path's decode)
	eq(Settings.effectiveRaw(api).sqrl_light_phases, 1)
	saved.sseq, saved.sset = 5, { phases = 2, every = 4 }
	T.now = T.now + Settings.POLL_S
	local eff = Settings.effectiveRaw(api)
	eq({ eff.sqrl_light_phases, eff.sqrl_auto_every }, { 2, 4 })
	eq(Rules.fromModParams(eff).phases, "sl")
end)

---------------------------------------------------------------------------
-- The game script: op=setting, the GUI pass re-deriving

local function autoEvent(G, payload)
	return G.gs.handleEvent({}, G.state, "", Auto.EVENT_ID, Auto.EV_AUTO, payload)
end

test("handler: op=setting stores sset / sseq once per change (SETTINGS op=set); bad payloads ignored; saved only from the first change", function()
	local G = makeGame(nil)
	G.gs.update({}, G.state, 0.1)
	eq(G.state:get(), nil, "nothing saved before a change")
	autoEvent(G, { op = "setting", key = "phases", value = 2, src = "crossing" })
	local s = G.state:get()
	eq({ s.sset, s.sseq }, { { phases = 2 }, 1 })
	local l = G.kinds("SETTINGS")
	eq(#l, 1)
	ok(has(l[1], "op=set key=phases value=2 param=sqrl_light_phases src=crossing seq=1"), l[1])
	autoEvent(G, { op = "setting", key = "phases", value = 2, src = "tool" })
	eq(#G.kinds("SETTINGS"), 1, "the same value: nothing")
	eq(G.state:get().sseq, 1)
	autoEvent(G, { op = "setting", key = "freeTurn", value = 4 })
	autoEvent(G, { op = "setting", key = "amode", value = 1 })
	local ign = G.kinds("AUTORETIME")
	ok(has(ign[#ign - 1], "op=ignored reason=value"), ign[#ign - 1])
	ok(has(ign[#ign], "op=ignored reason=key"), ign[#ign])
	eq(G.state:get().sset, { phases = 2 })
	-- Automatic light timing from the Crossing Tool: the existing op=mode (the save's amode)
	autoEvent(G, { op = "mode", mode = "all", src = "crossing" })
	eq(G.state:get().amode, "all")
	ok(has(G.kinds("AUTORETIME")[#G.kinds("AUTORETIME")], "op=mode mode=all src=crossing"))
	eq(#G.kinds("ERROR"), 0)
end)

test("GUI pass: the settings follow the save (MODE ... src=save once per change); the next job uses them", function()
	local G = makeGame({ sqrl_light_phases = 1, sqrl_free_turn = 3 })
	G.gs.update({}, G.state, 0.1)
	G.frames(3)
	local modes = G.kinds("MODE")
	eq(#modes, 1)
	ok(has(modes[1], "phases=game free_turn=always lights=on"), modes[1])
	autoEvent(G, { op = "setting", key = "phases", value = 2 })
	autoEvent(G, { op = "setting", key = "freeTurn", value = 2 })
	autoEvent(G, { op = "setting", key = "lights", value = 2 })
	G.frames(200)
	modes = G.kinds("MODE")
	eq(#modes, 2, "one more MODE line")
	ok(has(modes[2], "phases=sl free_turn=safe lights=off src=save"), modes[2])
	G.frames(200)
	eq(#G.kinds("MODE"), 2, "no change: no line")
	-- a load of this save: the overrides from its first frame
	local H = makeGame({ sqrl_light_phases = 1 })
	H.state:set({ sseq = 3, sset = { phases = 2 } })
	H.gs.update({}, H.state, 0.1)
	H.frames(1)
	ok(has(H.kinds("MODE")[1], "phases=sl"), H.kinds("MODE")[1])
	eq(#G.kinds("ERROR") + #H.kinds("ERROR"), 0)
end)

test("GUI pass: a save that switches back to the mod values (an older sseq read as none) re-derives too", function()
	local G = makeGame({ sqrl_light_phases = 2 })
	G.state:set({ sseq = 1, sset = { phases = 1 } })
	G.gs.update({}, G.state, 0.1)
	G.frames(2)
	ok(has(G.kinds("MODE")[1], "phases=game"), G.kinds("MODE")[1])
	G.state:set({})
	G.frames(200)
	local modes = G.kinds("MODE")
	ok(has(modes[#modes], "phases=sl") and has(modes[#modes], "src=save"), modes[#modes])
end)

test("runtime: the check interval and Light phases re-derived when the save's settings change (op=config src=save)", function()
	local AutoRetime = ug_require "square_smart_lanes::/smart_lanes/sl_autoretime.lua"
	local lines = {}
	local api = { type = { ComponentType = {} }, engine = {
		config = { getModParams = function() return { square_smart_lanes = { sqrl_auto_every = 2 } } end } } }
	local R = AutoRetime.new(api, function(kind, fields) lines[#lines + 1] = Rules.line(kind, fields) end, nil, {})
	eq({ R.everyFactor, Auto.everyFactor, R.slPhases }, { 1, 1, false })
	ok(has(lines[1], "op=config every_factor=1") and not has(lines[1], "src=save"), lines[1])
	R.step()
	local n = #lines
	Settings.setMirror(1, { every = 4, phases = 2 }, nil)
	R.step()
	eq({ R.everyFactor, Auto.everyFactor, R.slPhases }, { 4, 4, true })
	local cfg = {}
	for _, l in ipairs(lines) do if has(l, "op=config") then cfg[#cfg + 1] = l end end
	ok(has(cfg[#cfg], "every_factor=4") and has(cfg[#cfg], "src=save"), cfg[#cfg])
	R.step()
	eq(#lines, n + 1, "no change: no line")
	Auto.setEveryFactor(1)
end)

---------------------------------------------------------------------------
-- sl_settingsui.lua: the toolbar params

local function uiApi(saved, sent)
	local api = gsApi({ state = saved })
	api.type.enum = {
		ScriptParamType = { Button = "Button", ComboBox = "ComboBox", CheckBox = "CheckBox" },
		ScriptParamLocation = { Toolbar = "Toolbar" },
		ScriptParamDisplayMode = { Vertical = "Vertical" },
	}
	api.engine.config.getModParams = function()
		return { square_smart_lanes = { sqrl_lights = 1, sqrl_free_turn = 3, sqrl_light_phases = 1, sqrl_auto_lights = 1,
			sqrl_auto_every = 2 } }
	end
	api.cmd = {
		makeScriptingSendEventCmd = function(_, id, name, param) return { id = id, name = name, param = param } end,
		sendCommand = function(cmd) sent[#sent + 1] = cmd end,
	}
	return api
end

test("panel params: five settings in one labelled group, mod.json names and tooltips plus the per-save note, values in mod.json order", function()
	local api = uiApi({}, {})
	local mj = modJson()
	local list = UI.params(api, { src = "crossing" })
	local keys, names = {}, {}
	for i, p in ipairs(list) do
		keys[i], names[i] = p.key, p.name
		eq(p.group, "sqrl-settings")
		ok(not p.group:find("[^%w%-]"), "a CSS class: letters, digits and dashes only")
		ok(not p.hideLabel, "labelled: the panel's params stack vertically in their group")
		eq({ p.location, p.displayMode, p.yearFrom, p.yearTo }, { "Toolbar", "Vertical", 0, 0 })
		eq(p.preserveValueInAllCategories, true, "one stored value for both tools")
		eq(p.constructionParam, nil, "never passed to a construction")
		local name = UI.ORDER[i]
		local tip = mj[UI.PARAM_OF[name]].tooltip
		ok(p.tooltip:sub(1, #tip) == tip, name .. ": starts with the mod.json tooltip")
		ok(has(p.tooltip, "this game only"), name .. ": the per-save note")
		eq(#p.values, UI.N[name])
		eq(#p.tooltips, #p.values, "each value has a tooltip")
		eq(p.uiType, (name == "lights" or name == "every") and "Button" or "ComboBox")
	end
	eq(keys, { "sqrl_set_lights", "sqrl_set_free_turn", "sqrl_set_light_phases", "sqrl_set_auto_lights", "sqrl_set_auto_every" })
	eq(names, { "No lights at roundabouts and ramps", "Free curb turn at traffic lights", "Light phases",
		"Automatic light timing", "Keep timing adjusted: check interval" })
	eq(list[1].values, { "On", "Off" })
	eq(list[2].values, { "Off", "When safe", "Always" })
	eq(list[4].values, { "Junctions I choose", "All lights", "Off" })
	eq(list[5].values, { "x0.5", "x1", "x2", "x4" })
	ok(has(list[4].tooltip, "stops it at every"), "Junctions I choose here unenrolls: said")
	-- defaults: the values in force (mod.json here)
	eq({ list[1].defaultIndex, list[2].defaultIndex, list[3].defaultIndex, list[4].defaultIndex, list[5].defaultIndex },
		{ 1, 3, 1, 1, 2 })
	-- the lights toggle's content (long values not clipped by the bar's 50 px text rule), when given
	local withContent = UI.params(api, { content = function(label, tip) return { label = label, tip = tip } end })
	eq(withContent[1].makeCompactButtonFn(2), { label = "Off", tip = withContent[1].tooltip })
	eq(withContent[5].makeCompactButtonFn, nil, "x0.5 .. x4 fit the base text")
end)

test("panel shown value: checkEnabledFn sets defaultIndex to the value in force, then the stored value once a click handed the api", function()
	local saved = {}
	local sent = {}
	local api = uiApi(saved, sent)
	local list = UI.params(api, { src = "tool", shown = function() return true end })
	local phases = list[3]
	eq(phases.checkEnabledFn({}), "Enabled")
	eq(phases.defaultIndex, 1)
	-- the save changed (elsewhere): the next step shows it
	saved.sseq, saved.sset = 1, { phases = 2 }
	T.now = T.now + Settings.POLL_S
	phases.checkEnabledFn({})
	eq(phases.defaultIndex, 2)
	-- a click hands the params api; the stored value then follows the value in force every step
	local stored = { [-1] = {} }
	local pa = { getStoredValues = function(cat) return stored[cat] end, getCategory = function() return 3 end }
	phases.onChangeFn(1, pa, 2)
	eq(sent[#sent].param, { op = "setting", key = "phases", value = 1, src = "tool" })
	eq(UI.state.paramsApi, pa)
	stored[-1][phases.key] = 1 -- the menu stored the click
	phases.checkEnabledFn({})
	eq({ phases.defaultIndex, stored[-1][phases.key] }, { 1, 1 }, "pending: the clicked value")
	-- the game script never stored it (lost): after PENDING_S the saved value is back, the stored value follows
	T.now = T.now + Settings.PENDING_S + 1
	phases.checkEnabledFn({})
	eq({ phases.defaultIndex, stored[-1][phases.key] }, { 2, 2 })
	-- a key the menu never stored is left alone (no click on it yet)
	list[5].checkEnabledFn({})
	eq(stored[-1][list[5].key], nil)
	-- the Smart Lanes tool: hidden with a selection
	local hidden = UI.params(api, { shown = function() return false end })
	eq(hidden[1].checkEnabledFn({}), "Hidden")
	-- an api that throws never breaks the step
	local bad = { getStoredValues = function() error("boom") end }
	phases.onChangeFn(2, bad, 1)
	eq(phases.checkEnabledFn({}), "Enabled")
end)

test("panel clicks: op=setting / op=mode with src, the value in force changes nothing, Automatic light timing through the tool", function()
	local sent = {}
	local api = uiApi({}, sent)
	local logs = {}
	local opts = { src = "crossing", emit = function(kind, f) logs[#logs + 1] = Rules.line(kind, f) end }
	eq(UI.change(api, "every", 2, nil, opts), "same", "x1 is in force")
	eq(#sent, 0)
	eq(UI.change(api, "every", 4, nil, opts), "sent")
	eq(sent[1], { id = "square_smart_lanes", name = "SmartLanes.auto", param = { op = "setting", key = "every", value = 4, src = "crossing" } })
	eq(Settings.overNow().every, 4, "shown at once")
	ok(has(logs[1], "SETTINGS op=click key=every value=4 src=crossing sent=1"), logs[1])
	eq(UI.change(api, "every", 4, nil, opts), "same", "now in force (pending)")
	eq(UI.change(api, "every", 5, nil, opts), "bad")
	eq(UI.change(api, "lights", 1.5, nil, opts), "bad")
	eq(UI.change(api, "nope", 1, nil, opts), "bad")
	-- Automatic light timing: op=mode (the save's amode)
	eq(UI.current(api, "amode"), 1)
	eq(UI.change(api, "amode", 2, nil, opts), "sent")
	eq(sent[#sent].param, { op = "mode", mode = "all", src = "crossing" })
	eq(UI.current(api, "amode"), 2)
	-- in the Smart Lanes tool through its controller (its mirror and result line follow)
	local calls = {}
	eq(UI.change(api, "amode", 1, nil, { src = "tool", setLightMode = function(m) calls[#calls + 1] = m end }), "sent")
	eq(calls, { "pick" })
	eq(#sent, 2, "the controller sends it")
	eq(UI.current(api, "amode"), 1)
	-- the save's amode wins over mod.json in the shown value
	Settings.resetMirror()
	Settings.setMirror(nil, nil, "all")
	eq(UI.current(api, "amode"), 2)
	-- a send that fails is logged as sent=0, never thrown
	api.cmd.sendCommand = function() error("no") end
	eq(UI.change(api, "phases", 2, nil, opts), "sent")
	ok(has(logs[#logs], "sent=0"), logs[#logs])
end)

---------------------------------------------------------------------------
-- The Crossing Tool

local function crossingDef()
	return { action = "ACTION_LANE_MODIFIER_TOOL", params = { { key = "tramMode" }, { key = "sqbbo_lines_other" },
		{ key = "undergroundMode" } } }
end

local function keysOf(def)
	local out = {}
	for i, p in ipairs(def.params) do out[i] = p.key end
	return out
end

test("Crossing Tool: our params before Underground (after other mods' params), a fresh list, idempotent, other tools untouched", function()
	local api = uiApi({}, {})
	local make = function() return UI.params(api, { src = "crossing" }) end
	local def = crossingDef()
	local oldList = def.params
	eq(UI.insertInto(def, make), "inserted")
	eq(keysOf(def), { "tramMode", "sqbbo_lines_other", "sqrl_set_lights", "sqrl_set_free_turn", "sqrl_set_light_phases",
		"sqrl_set_auto_lights", "sqrl_set_auto_every", "undergroundMode" })
	eq(#oldList, 3, "the old list is not changed in place")
	eq(UI.insertInto(def, make), "present")
	eq(#def.params, 8)
	-- no Underground: at the end
	local d2 = { action = "ACTION_LANE_MODIFIER_TOOL", params = { { key = "tramMode" } } }
	UI.insertInto(d2, make)
	eq(keysOf(d2)[2], "sqrl_set_lights")
	eq(#d2.params, 6)
	local d3 = { action = "ACTION_LANE_MODIFIER_TOOL" }
	eq(UI.insertInto(d3, make), "inserted")
	eq(#d3.params, 5)
	-- other actions (our own tool included) untouched
	local other = { action = "ACTION_CUSTOM", params = { { key = "x" } } }
	eq(UI.insertInto(other, make), "other")
	eq(keysOf(other), { "x" })
	eq(UI.insertInto(nil, make), "other")
	-- the Crossing Tool's own action reads only tramMode / undergroundMode (construction_react_util.tl:3323-3330):
	-- the panel is always shown there
	eq(def.params[3].checkEnabledFn({}), "Enabled")
end)

test("forEachDefinition wrapper: installed once per module table, chain-safe in either order with another wrapper, errors contained", function()
	local api = uiApi({}, {})
	local make = function() return UI.params(api, { src = "crossing" }) end
	local defs = { crossingDef(), { action = "ACTION_BULLDOZER", params = {} } }
	local function base(fn, _repo)
		for _, d in ipairs(defs) do fn(d) end
	end
	-- another mod's wrapper (Better Bus Overlay's shape: reads the current function at install)
	local function otherWrap(cru)
		local orig = cru.forEachDefinition
		cru.forEachDefinition = function(fn, repo)
			return orig(function(d)
				d.seenByOther = (d.seenByOther or 0) + 1
				return fn(d)
			end, repo)
		end
	end
	-- ours first, then the other mod
	local cru = { forEachDefinition = base }
	local inserts = {}
	eq(UI.wrapForEach(cru, make, function(r) inserts[#inserts + 1] = r end), "installed")
	eq(UI.wrapForEach(cru, make), "already")
	otherWrap(cru)
	local got = {}
	cru.forEachDefinition(function(d) got[#got + 1] = d end, nil)
	eq(#got, 2)
	eq(#got[1].params, 8)
	eq({ got[1].seenByOther, got[2].seenByOther }, { 1, 1 })
	eq(inserts, { "inserted" })
	-- a second menu mount: present, not doubled
	cru.forEachDefinition(function() end, nil)
	eq(#defs[1].params, 8)
	eq(inserts, { "inserted", "present" })
	-- the other mod first, then ours
	defs = { crossingDef() }
	local cru2 = { forEachDefinition = base }
	otherWrap(cru2)
	UI.wrapForEach(cru2, make)
	cru2.forEachDefinition(function() end, nil)
	eq({ #defs[1].params, defs[1].seenByOther }, { 8, 1 })
	-- an error in ours never reaches the menu's callback
	defs = { crossingDef() }
	local cru3 = { forEachDefinition = base }
	local logged = {}
	UI.wrapForEach(cru3, function() error("boom") end, function(r) logged[#logged + 1] = r end)
	local n = 0
	cru3.forEachDefinition(function() n = n + 1 end, nil)
	eq(n, 1)
	eq(#defs[1].params, 3)
	ok(has(logged[1], "error:"), tostring(logged[1]))
	eq(UI.wrapForEach({}, make), "missing")
	eq(UI.wrapForEach(nil, make), "missing")
end)

test("sl_tool.script.lua: wraps forEachDefinition at load (once), doReplace too; the Crossing Tool gets the panel; SETTINGS op=menu once", function()
	stub_module("::/gui/main/react.lua", { RegisterRecipe = function(name, _fn)
		return function(p) return { recipe = name, param = p } end
	end })
	stub_module("::/gui/main/builtin.lua", {
		type = { Orientation = { Vertical = "Vertical", Horizontal = "Horizontal" } },
		BoxLayout = function(p) return p end,
		TextView = function(p) return p end,
	})
	local defs = { crossingDef() }
	local cru = { forEachDefinition = function(fn, _repo) for _, d in ipairs(defs) do fn(d) end end }
	stub_module("::/gui/construction/construction_react_util.tl", cru)
	local sent = {}
	local api = uiApi({}, sent)
	api.gui = { fireReactEvent = function() end }
	local function load()
		local env = setmetatable({ api = api, ug_require = ug_require, log = log, resolve = function(p) return p end }, { __index = _ENV })
		assert(loadfile(MOD_DIR .. "content/smart_lanes/sl_tool.script.lua", "t", env))()
		return env.data()
	end
	local M = load()
	local wrapped = cru.forEachDefinition
	load() -- a second load of the script must not wrap twice
	eq(cru.forEachDefinition, wrapped)
	ok(type(M.doReplace) == "function", "the react-replacement-config's function")
	M.doReplace({})
	eq(cru.forEachDefinition, wrapped, "doReplace after the load: already installed")
	cru.forEachDefinition(function() end, nil)
	cru.forEachDefinition(function() end, nil)
	eq(keysOf(defs[1])[3], "sqrl_set_lights")
	eq(#defs[1].params, 8)
	local menu = {}
	for _, e in ipairs(log_entries()) do
		if has(e.msg, "SETTINGS op=menu") then menu[#menu + 1] = e.msg end
	end
	eq(#menu, 2, "inserted once, present once")
	ok(has(menu[1], "where=crossing_tool result=inserted"), menu[1])
	-- a click there goes to the game script with src=crossing
	defs[1].params[5].onChangeFn(2, nil, 1) -- Light phases (after tramMode, the other mod's toggle, lights, free turn)
	eq(sent[#sent].param, { op = "setting", key = "phases", value = 2, src = "crossing" })
	-- the Smart Lanes tool's own panel: hidden with a selection, shown with none
	local def = M.getDefinition("smart_lanes/sl_tool.res", nil, nil)
	local g = ug_require "square_smart_lanes::/smart_lanes/sl_toolstate.lua"
	local savedCore = g.core
	g.core = { sel = { kind = "node" } }
	eq(def.params[7].checkEnabledFn({}), "Hidden")
	g.core = { sel = nil, setLightMode = function() end }
	eq(def.params[7].checkEnabledFn({}), "Enabled")
	g.core = savedCore
	-- its replacement config resource names this script's doReplace
	local f = assert(io.open(MOD_DIR .. "content/smart_lanes/sl_settings_replace.res.lua", "r"))
	local res = f:read("*a")
	f:close()
	ok(has(res, '"square_smart_lanes::/smart_lanes/sl_tool.script"') and has(res, '"doReplace"')
		and has(res, '"react-replacement-config"'), "react-replacement-config -> sl_tool.script@doReplace")
end)

test("mod.json Automatic light timing no longer names the removed rows; texts for every setting", function()
	local mj = modJson()
	ok(not has(mj.sqrl_auto_lights.tooltip, "Adjust all lights"), mj.sqrl_auto_lights.tooltip)
	ok(has(mj.sqrl_auto_lights.tooltip, "Crossing Tool"))
	for _, name in ipairs(UI.ORDER) do ok(UI.texts(name) ~= nil, name) end
	eq(UI.texts("x"), nil)
end)
