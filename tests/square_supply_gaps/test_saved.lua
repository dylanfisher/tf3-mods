-- Per-save state (PLAN "Per-save state"): sg_saved.tl rules (isOn, apply, the GUI load decision,
-- readOn / sendOn against a fake API) and the engine game script sg_state.script.tl (subscribe once per
-- load, validated event, no write when unchanged, nothing written by update, map editor inert).

local saved = ug_require "square_supply_gaps::/supply_gaps/sg_saved.tl"

local sent, mapEditor, gsEntity, gsComp

local function fakeApi()
	return {
		type = { ComponentType = { GAME_SCRIPT = "GAME_SCRIPT" } },
		engine = {
			config = { getModParams = function() return { [""] = { isMapEditor = mapEditor } } end },
			system = { gameScriptSystem = { getEntityForGameScript = function(name)
				eq(name, "square_supply_gaps::/supply_gaps/sg.gs")
				return gsEntity
			end } },
			getComponent = function(e, ct)
				eq(ct, "GAME_SCRIPT")
				return gsComp
			end,
		},
		cmd = {
			makeScriptingSendEventCmd = function(src, id, name, param) return { src = src, id = id, name = name, param = param } end,
			sendCommand = function(cmd) sent[#sent + 1] = cmd end,
		},
	}
end

--- Fake GameScriptState: counts writes and subscriptions.
local function fakeState(initial)
	local st = { value = initial, sets = 0, subs = nil, subCalls = 0 }
	function st:get() return self.value end
	function st:set(v) self.value = v; self.sets = self.sets + 1 end
	function st:hasEventSubscriptions() return self.subs ~= nil and next(self.subs) ~= nil end
	function st:subscribeToNoEvents() self.subs = {}; self.subCalls = self.subCalls + 1 end
	function st:subscribeToEvent(n) self.subs[n] = true end
	return st
end

local function loadScript()
	reset_modules()
	saved = ug_require "square_supply_gaps::/supply_gaps/sg_saved.tl"
	return ug_require "square_supply_gaps::/supply_gaps/sg_state.script.tl"
end

local function setOn(script, state, param)
	script.handleEvent({}, state, "", "SupplyGaps", "SupplyGaps.setOn", param)
end

before_each(function()
	sent, mapEditor, gsEntity, gsComp = {}, false, 42, nil
	set_global("api", fakeApi())
	clear_logs()
end)

test("isOn: absent / malformed state is off; only on == true is on", function()
	eq(saved.isOn(nil), false)
	eq(saved.isOn({}), false)
	eq(saved.isOn("on"), false)
	eq(saved.isOn({ v = 1, on = "true" }), false)
	eq(saved.isOn({ v = 1, on = false }), false)
	eq(saved.isOn({ v = 1, on = true }), true)
end)

test("apply: validates the param; changed only when the flag flips", function()
	local s, changed, rej = saved.apply(nil, { on = true })
	eq(s, { v = 1, on = true })
	ok(changed)
	eq(rej, nil)
	s, changed, rej = saved.apply({ v = 1, on = true }, { on = true })
	eq(s, { v = 1, on = true })
	ok(not changed, "unchanged: no write")
	eq(rej, nil)
	s, changed = saved.apply(nil, { on = false })
	eq(s, { v = 1, on = false })
	ok(not changed, "absent state is already off")
	s, changed = saved.apply({ v = 1, on = true }, { on = false })
	eq(s, { v = 1, on = false })
	ok(changed)
	for _, bad in ipairs({ {}, { on = 1 }, { on = "true" }, "x", true }) do
		local s2, ch, r = saved.apply({ v = 1, on = true }, bad)
		eq(s2, { v = 1, on = true })
		ok(not ch)
		ok(r ~= nil, "rejected")
	end
	local _, ch, r = saved.apply(nil, nil)
	ok(not ch)
	ok(r ~= nil)
end)

test("load decision: saved on -> on, saved off -> off, then done", function()
	local l = saved.newLoad()
	eq(saved.loadStep(l, true), "on")
	eq(saved.loadStep(l, true), "done")
	eq(saved.loadStep(l, false), "done")
	l = saved.newLoad()
	eq(saved.loadStep(l, false), "off")
	eq(saved.loadStep(l, true), "done", "a later read never switches on")
end)

test("load decision: unreadable state waits, then gives up as off after LOAD_TRIES", function()
	local l = saved.newLoad()
	for i = 1, saved.LOAD_TRIES - 1 do eq(saved.loadStep(l, nil), "wait", "try " .. i) end
	eq(saved.loadStep(l, nil), "off")
	eq(saved.loadStep(l, true), "done")
	l = saved.newLoad()
	eq(saved.loadStep(l, nil), "wait")
	eq(saved.loadStep(l, true), "on", "readable on the second try")
end)

test("load decision: the player's toggle (done) wins over a pending read", function()
	local l = saved.newLoad()
	eq(saved.loadStep(l, nil), "wait")
	l.done = true
	eq(saved.loadStep(l, true), "done")
end)

test("readOn: no game-script entity or component -> nil (not readable yet)", function()
	gsEntity = nil
	eq(saved.readOn(), nil)
	gsEntity = -1
	eq(saved.readOn(), nil)
	gsEntity, gsComp = 42, nil
	eq(saved.readOn(), nil)
end)

test("readOn: state_native field, absent field = off; falls back to the state copy", function()
	local native = { on = true }
	gsComp = { state_native = { find = function(_, k) return native[k] end } }
	eq(saved.readOn(), true)
	native.on = false
	eq(saved.readOn(), false)
	native.on = nil
	eq(saved.readOn(), false, "empty state (mod added to an old save)")
	gsComp = { state_native = nil, state = { v = 1, on = true } }
	eq(saved.readOn(), true)
	gsComp = { state_native = { find = function() error("userdata") end }, state = nil }
	eq(saved.readOn(), false)
end)

test("sendOn: one scripting event with a boolean param", function()
	saved.sendOn(true)
	saved.sendOn(nil)
	eq(sent, {
		{ src = "", id = "SupplyGaps", name = "SupplyGaps.setOn", param = { on = true } },
		{ src = "", id = "SupplyGaps", name = "SupplyGaps.setOn", param = { on = false } },
	})
end)

test("engine: update subscribes once per load to our event and never writes state", function()
	local script = loadScript()
	local st = fakeState(nil)
	for _ = 1, 5 do script.update({}, st, 0.2) end
	eq(st.subs, { ["SupplyGaps.setOn"] = true })
	eq(st.subCalls, 1)
	eq(st.sets, 0, "absent state stays absent")
	eq(st.value, nil)
	-- next load (fresh module) re-subscribes, e.g. a save from an older revision
	script = loadScript()
	script.update({}, st, 0.2)
	eq(st.subCalls, 2)
	eq(#log_entries(), 0)
end)

test("engine: setOn writes only a change; a repeat or an invalid param writes nothing", function()
	local script = loadScript()
	local st = fakeState(nil)
	setOn(script, st, { on = false })
	eq(st.sets, 0, "off on an absent state: no write")
	setOn(script, st, { on = true })
	eq(st.sets, 1)
	eq(st.value, { v = 1, on = true })
	setOn(script, st, { on = true })
	eq(st.sets, 1, "unchanged")
	setOn(script, st, { on = "yes" })
	eq(st.sets, 1, "invalid")
	setOn(script, st, { on = false })
	eq(st.sets, 2)
	eq(st.value, { v = 1, on = false })
end)

test("engine: other events and lifecycle events are ignored", function()
	local script = loadScript()
	local st = fakeState({ v = 1, on = true })
	script.handleEvent({}, st, "", "", "initNewGame", nil)
	script.handleEvent({}, st, "", "ProblemRadar", "SupplyGaps.setOn", { on = false })
	script.handleEvent({}, st, "", "SupplyGaps", "SupplyGaps.other", { on = false })
	eq(st.sets, 0)
end)

test("engine: map editor: no subscription, no write", function()
	mapEditor = true
	local script = loadScript()
	local st = fakeState(nil)
	script.update({}, st, 0.2)
	setOn(script, st, { on = true })
	eq(st.subs, nil)
	eq(st.sets, 0)
end)

test("engine: an error inside the handler is caught and logged once", function()
	local script = loadScript()
	local st = fakeState(nil)
	st.get = function() error("boom") end
	setOn(script, st, { on = true })
	setOn(script, st, { on = true })
	local n = 0
	for _, e in ipairs(log_entries()) do
		if e.msg:find("[SQSG] event 'SupplyGaps.setOn' failed", 1, true) then n = n + 1 end
	end
	eq(n, 1)
end)
