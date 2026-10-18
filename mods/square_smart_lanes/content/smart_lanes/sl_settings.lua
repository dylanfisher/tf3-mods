-- Smart Lanes in-game settings (PLAN.md "In-game settings panel"): the light settings changed in game, per save,
-- overriding the mod.json value (which stays the default for new games and other saves). Pure apart from
-- M.readSaved / M.poll (any Lua state that can read the GAME_SCRIPT component); Lua 5.1 syntax.
--
-- Overridable here (mod.json key, 1-based value as in the mod params):
--   lights    sqrl_lights        No lights at roundabouts and ramps: 1 On / 2 Off
--   freeTurn  sqrl_free_turn     Free curb turn at traffic lights: 1 Off / 2 When safe / 3 Always
--   phases    sqrl_light_phases  Light phases: 1 Game default / 2 Smart Lanes
--   every     sqrl_auto_every    Keep timing adjusted: check interval: 1 x0.5 / 2 x1 / 3 x2 / 4 x4
-- "Automatic light timing" (sqrl_auto_lights) keeps its own per-save override, the game-script state's `amode`
-- (sl_allmode.lua; SmartLanes.auto op=mode): the panel shows and sets that one, so the welcome, the panel and the
-- mod setting never disagree. This module mirrors amode too (M.amodeNow), with the same pending logic.
--
-- Saved (game-script state, written from the first change only; sl_lanes.script.lua handleAuto, op=setting):
--   sset = { lights = i, freeTurn = i, phases = i, every = i }   only the settings changed in this save
--   sseq = n                                                    +1 per change (the mirrors re-read sset only then)
-- Size bound: 4 small numbers.
--
-- Channel: SmartLanes.auto { op = "setting", key = "<name>", value = i, src = "tool" | "crossing" } (sl_auto.lua
-- validates through M.validate); the game script logs SETTINGS op=set key= value= param= src= seq=.
--
-- Every reader of these mod params decodes them through M.effectiveRaw / M.merged: Rules.fromModParams of the merged
-- raw table (sl_lanes.script.lua settings(), sl_write.lua W.phasesMode / W.removeLights / W.freeTurn), and
-- Auto.everyFactorOf (sl_autoretime.lua, re-derived when M.mirror.version moves).
--
-- The mirror (one per Lua state): the saved sset / sseq / amode as last read, plus `pending` values this Lua state
-- sent and the game script has not stored yet (a click shows at once; the toolbar's stored values follow the
-- effective value every step, sl_settingsui.lua). A pending value is dropped once the saved state holds it, the saved
-- seq moved (someone stored something newer), or after PENDING_S.

local M = {}

M.GS_NAME = "square_smart_lanes::/smart_lanes/sl_lanes.gs" -- = sl_auto.lua M.GS_NAME
M.ITEMS = {
	{ name = "lights", key = "sqrl_lights", n = 2, default = 1 }, -- i18n: ignore
	{ name = "freeTurn", key = "sqrl_free_turn", n = 3, default = 3 }, -- i18n: ignore
	{ name = "phases", key = "sqrl_light_phases", n = 2, default = 1 }, -- i18n: ignore
	{ name = "every", key = "sqrl_auto_every", n = 4, default = 2 }, -- i18n: ignore
}
M.BY_NAME = {}
for _, it in ipairs(M.ITEMS) do M.BY_NAME[it.name] = it end
M.AMODES = { "pick", "all", "off" } -- sqrl_auto_lights values (= AllMode.MODES)
local AMODE_OK = {}
for _, a in ipairs(M.AMODES) do AMODE_OK[a] = true end
M.POLL_S = 0.5                -- s of M.clock between two reads of the saved state (M.poll)
M.PENDING_S = 5               -- s a sent value shows before the saved state must hold it

M.clock = os.clock

local function intIn(v, n)
	return type(v) == "number" and v == v and v == math.floor(v) and v >= 1 and v <= n
end

--- Whether value is a valid 1-based index of setting `name`.
function M.valid(name, value)
	local it = type(name) == "string" and M.BY_NAME[name] or nil
	return it ~= nil and intIn(value, it.n)
end

--- A saved sset cleaned: { name = i } with valid entries only; nil when none.
function M.clean(t)
	if type(t) ~= "table" then return nil end
	local out, any = {}, false
	for _, it in ipairs(M.ITEMS) do
		local v = tonumber(t[it.name])
		if M.valid(it.name, v) then
			out[it.name] = v
			any = true
		end
	end
	return any and out or nil
end

--- The event's setting: name, value; nil, reason for a bad payload ("key" | "value").
function M.validate(param)
	if type(param) ~= "table" then return nil, "not_table" end
	if type(param.key) ~= "string" or M.BY_NAME[param.key] == nil then return nil, "key" end
	if not M.valid(param.key, param.value) then return nil, "value" end
	return param.key, param.value
end

--- Stores a validated setting in a game-script state table s (in place): false when it holds that value already.
function M.apply(s, name, value)
	if not M.valid(name, value) then return false end
	local cur = M.clean(s.sset) or {}
	if cur[name] == value then return false end
	cur[name] = value
	s.sset = cur
	s.sseq = (tonumber(s.sseq) or 0) + 1
	return true
end

--- A copy of this mod's raw mod params (nil or a table of 1-based indices) with the overrides `over` ({ name = i })
-- in place of the mod.json values.
function M.merged(raw, over)
	local out = {}
	if type(raw) == "table" then
		for k, v in pairs(raw) do out[k] = v end
	end
	if type(over) == "table" then
		for _, it in ipairs(M.ITEMS) do
			local v = over[it.name]
			if M.valid(it.name, v) then out[it.key] = v end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- The mirror of this Lua state

function M.resetMirror()
	M.mirror = { read = false, seq = nil, over = nil, amode = nil, at = nil, pending = {}, version = 0 }
end
M.resetMirror()

local function overKey(over, amode)
	local parts = {}
	for _, it in ipairs(M.ITEMS) do parts[#parts + 1] = tostring(over and over[it.name] or "-") end
	parts[#parts + 1] = tostring(amode or "-")
	return table.concat(parts, ",")
end

--- The overrides in force here: the saved ones with this Lua state's pending values on top ({ name = i } or {}).
function M.overNow()
	local m, now = M.mirror, M.clock()
	local out = {}
	for k, v in pairs(m.over or {}) do out[k] = v end
	for k, p in pairs(m.pending) do
		if k ~= "amode" and now - p.at <= M.PENDING_S then out[k] = p.v end
	end
	return out
end

--- The per-save "Automatic light timing" override in force here ("all" | "pick" | "off" | nil: the mod setting).
function M.amodeNow()
	local m = M.mirror
	local p = m.pending.amode
	if p ~= nil and M.clock() - p.at <= M.PENDING_S then return p.v end
	return m.amode
end

local function bumpIfChanged(before)
	local m = M.mirror
	if overKey(M.overNow(), M.amodeNow()) ~= before then m.version = m.version + 1 end
end

--- The saved state as read (seq, sset table or nil, amode string or nil) into the mirror; pending values the saved
-- state now holds (or that a newer saved seq / amode replaced) are dropped. Returns whether the values in force here
-- changed (M.mirror.version moved).
function M.setMirror(seq, sset, amode)
	local m = M.mirror
	local before = overKey(M.overNow(), M.amodeNow())
	local over = M.clean(sset)
	if not AMODE_OK[amode] then amode = nil end
	local seqMoved = m.read and seq ~= m.seq
	local amodeMoved = m.read and amode ~= m.amode
	m.read, m.seq, m.over, m.amode = true, seq, over, amode
	local now = M.clock()
	for k, p in pairs(m.pending) do
		local saved = (k == "amode") and amode or (over and over[k])
		if saved == p.v or now - p.at > M.PENDING_S or (k == "amode" and amodeMoved) or (k ~= "amode" and seqMoved) then
			m.pending[k] = nil
		end
	end
	local v0 = m.version
	bumpIfChanged(before)
	return m.version ~= v0
end

--- A value this Lua state just sent (name = a setting or "amode"): in force here at once (M.overNow / M.amodeNow).
function M.setPending(name, value)
	local m = M.mirror
	local before = overKey(M.overNow(), M.amodeNow())
	m.pending[name] = { v = value, at = M.clock() }
	bumpIfChanged(before)
end

--- The saved sseq, sset and amode from another Lua state (the GAME_SCRIPT component, as sl_auto M.readSaved).
-- lastSeq: the caller's sseq; when unchanged, sset is not read (returned as "same"). Returns ok, seq, sset ("same",
-- a table or nil), amode; ok false when unreadable. Never throws.
function M.readSaved(api, lastSeq)
	local ok, r1, r2, r3, r4 = pcall(function()
		local entity = api.engine.system.gameScriptSystem.getEntityForGameScript(M.GS_NAME)
		if entity == nil or entity < 0 then return false end
		local gs = api.engine.getComponent(entity, api.type.ComponentType.GAME_SCRIPT)
		if gs == nil then return false end
		local okN, q, t, a = pcall(function()
			local native = gs.state_native
			if native == nil then error("no state_native") end
			local q = native:find("sseq")
			local a = native:find("amode")
			if type(q) == "number" and q == lastSeq then return q, "same", a end
			local v = native:find("sset")
			if type(v) == "userdata" or (type(v) == "table" and type(v.asTable) == "function") then v = v:asTable() end
			return q, v, a
		end)
		if okN then return true, q, t, a end
		local st = gs.state
		if st == nil then return true, nil, nil, nil end
		if type(st) ~= "table" then return false end
		if type(st.sseq) == "number" and st.sseq == lastSeq then return true, st.sseq, "same", st.amode end
		return true, st.sseq, st.sset, st.amode
	end)
	if not ok or r1 ~= true then return false end
	local seq = type(r2) == "number" and r2 or nil
	local amode = type(r4) == "string" and r4 or nil
	return true, seq, r3, amode
end

--- Reads the saved state into the mirror at most every POLL_S (force: now). Returns whether the values in force here
-- changed. Unreadable: the mirror stays as it was. Never throws.
function M.poll(api, force)
	local m = M.mirror
	local now = M.clock()
	if not force and m.at ~= nil and now - m.at < M.POLL_S and now >= m.at then return false end
	m.at = now
	local ok, seq, sset, amode = M.readSaved(api, m.read and m.seq or nil)
	if not ok then return false end
	if sset == "same" then sset = m.over end
	local okS, changed = pcall(M.setMirror, seq, sset, amode)
	return okS and changed == true
end

--- This mod's raw mod params (getModParams, read each call) merged with the overrides in force here, after a poll
-- (at most every POLL_S). The one decode every reader of these settings goes through.
function M.effectiveRaw(api)
	pcall(M.poll, api, false)
	local ok, all = pcall(function() return api.engine.config.getModParams() end)
	local raw = ok and type(all) == "table" and all["square_smart_lanes"] or nil
	return M.merged(raw, M.overNow())
end

--- The 1-based value of setting `name` in force here (the override, else the mod.json value, else the default).
function M.index(name, raw)
	local it = M.BY_NAME[name]
	if it == nil then return nil end
	local over = M.overNow()
	if M.valid(name, over[name]) then return over[name] end
	local v = type(raw) == "table" and tonumber(raw[it.key]) or nil
	if M.valid(name, v) then return v end
	return it.default
end

return M
