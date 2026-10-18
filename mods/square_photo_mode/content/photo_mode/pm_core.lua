-- Photo Mode: the pure part (no api calls), shared by the GUI plugin (gui/pm_button.script.lua) and the offline
-- tests (tests/square_photo_mode/). Plain Lua, pre-5.3.
--
-- Design and proven mechanics: plans/square_photo_mode/PLAN.md, docs/findings/map-camera.md "Graphics settings
-- from a mod: api.util.setAppConfig".

local M = {}

M.MOD_ID = "square_photo_mode"
M.PREFIX = "[PhotoMode] "

-- The AppConfig graphics keys photo mode changes (and so snapshots and restores). Set by name: they are not in
-- the AppConfig record of api/tealdef/api/type.d.tl; the settings page writes them the same way
-- (base/content/gui/menu/settings_page.tl:866-990). vsync and cameraTool are not touched, so not snapshotted.
-- shadowQuality is never changed: it crashed the renderer 4 times (MoltenVK, after "Could not invert matrix");
-- old markers that still hold it are accepted, but it is neither snapshotted, restored nor recovered (not in KEYS).
-- geometryQuality / terrainQuality / grassQuality crashed once when switched together in one call (fatal assert
-- StaticBuffer.cpp:743, 2026-10-13_0558_session-crash) and passed one key at a time (round 18,
-- 2026-10-14_2019_r18-test-risky): each has a stage of its own. docs/findings/map-camera.md "Changing
-- render-buffer settings at runtime crashes".
M.KEYS = {
	"textureQuality", "terrainTextureQuality", "numMSAASamples", "useSsao", "ssrQuality", "resolutionScale",
	"geometryQuality", "terrainQuality", "grassQuality",
}

-- The highest value of every key: the "Very High" preset's values of these keys
-- (base/content/gui/menu/graphics_presets_util.tl:90-100) plus full resolution scale. numMSAASamples is replaced by
-- the highest supported count (maxMsaa).
M.BOOST = {
	textureQuality = 2,
	terrainTextureQuality = 2,
	numMSAASamples = 4,
	useSsao = true,
	ssrQuality = 2,
	resolutionScale = 1.0,
	geometryQuality = 2,
	terrainQuality = 2,
	grassQuality = 2,
}
M.MSAA_FALLBACK = 4

-- The staged switch to the highest graphics (plans/square_photo_mode/PLAN.md "Highest graphics: the staged
-- switch"): one setAppConfig per stage, STAGE_DELAY_FRAMES frames apart, instead of one call with every key, to
-- spread the renderer's reload. The log names each stage, so a crash shows which one: crashes came right after
-- the shadow stage (2026-10-13_0522, _0524), so shadows are never switched, and once after the combined geometry /
-- terrain / grass stage (2026-10-13_0558), so those three now switch one key per stage, last. Every key of M.KEYS
-- is in exactly one stage (tests/square_photo_mode/test_core.lua).
M.STAGES = {
	{ "textureQuality", "terrainTextureQuality" },
	{ "useSsao", "ssrQuality" },
	{ "numMSAASamples", "resolutionScale" },
	{ "geometryQuality" },
	{ "terrainQuality" },
	{ "grassQuality" },
}
-- The staged restore (toggle off): the same stages in reverse order (anti-aliasing and resolution scale first,
-- textures last), STAGE_DELAY_FRAMES apart; the marker is cleared and saved with the last one. The pause-menu
-- restore stays one call (a quit may follow at once).
M.RESTORE_STAGES = {}
for i = #M.STAGES, 1, -1 do M.RESTORE_STAGES[#M.RESTORE_STAGES + 1] = M.STAGES[i] end

--- The keys of restore stage i whose current value differs from the player's value in `orig`, as key -> value,
--- and their names in stage order (for the log).
function M.restoreChanges(i, current, orig)
	local changes, names = {}, {}
	for __, key in ipairs(M.RESTORE_STAGES[i] or {}) do
		local o = orig[key]
		if o ~= nil and not M.same(current[key], o) then
			changes[key] = o
			names[#names + 1] = key
		end
	end
	return changes, names
end

-- Frames from the click to stage 1 and between stages (at least 2: the pressed toggle is drawn first, and
-- every stage gets frames of its own).
M.STAGE_DELAY_FRAMES = 3

--- The keys of stage i whose current value differs from the boost value, as key -> boost value (plain table,
--- possibly empty), and their names in stage order (for the log).
function M.stageChanges(i, current, boost)
	local changes, names = {}, {}
	for __, key in ipairs(M.STAGES[i] or {}) do
		local b = boost[key]
		if b ~= nil and not M.same(current[key], b) then
			changes[key] = b
			names[#names + 1] = key
		end
	end
	return changes, names
end

function M.log(msg)
	if log ~= nil and log.message ~= nil then log.message(M.PREFIX .. msg) else print(M.PREFIX .. msg) end
end

--- Equal values; numbers within 1e-6 (resolutionScale is a float and may come back from settings.lua rounded).
function M.same(a, b)
	if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-6 end
	return a == b
end

--- Highest number in a list of MSAA sample counts (app.getSupportedMSAASampleCounts()), else the fallback.
--- `list` is anything indexable 1..#list (a Lua table or an engine vector).
function M.maxOf(list, fallback)
	local best = nil
	if list ~= nil then
		local ok = pcall(function()
			for i = 1, #list do
				local v = tonumber(list[i])
				if v ~= nil and (best == nil or v > best) then best = v end
			end
		end)
		if not ok then best = nil end
	end
	return best or fallback
end

--- The boost values with the given MSAA count.
function M.boostValues(msaa)
	local t = {}
	for k, v in pairs(M.BOOST) do t[k] = v end
	if msaa ~= nil then t.numMSAASamples = msaa end
	return t
end

--- Plain table of the graphics keys of a config: get(key) returns the value (it may raise; such keys are left out).
--- Plain so it can be stored in mainMenuState and never holds a reference to the engine config.
function M.snapshot(get)
	local t = {}
	for __, key in ipairs(M.KEYS) do
		local ok, v = pcall(get, key)
		if ok and v ~= nil then t[key] = v end
	end
	return t
end

--- A copy of mainMenuState (nil or table-like, read with pairs) with our key set to marker (nil clears it).
--- Other mods' keys are kept untouched. nil when mainMenuState can't be copied completely (not a table, or
--- pairs fails): writing a partial copy back would wipe other mods' prefs, so the caller must not save then.
function M.withMarker(mm, marker)
	local t = {}
	if mm ~= nil then
		local ok = pcall(function() for k, v in pairs(mm) do t[k] = v end end)
		if not ok then return nil end
	end
	t[M.MOD_ID] = marker
	return t
end

-- Valid values per graphics key of M.KEYS (base/content/gui/menu/settings_page.tl:866-990): the 0-2 quality levels,
-- MSAA sample counts, SSAO on / off, resolution scale 0.5-1.0.
local LEVEL_KEYS = { textureQuality = true, terrainTextureQuality = true, ssrQuality = true, geometryQuality = true,
	terrainQuality = true, grassQuality = true }
local MSAA_COUNTS = { [1] = true, [2] = true, [4] = true, [8] = true, [16] = true }

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
M.finite = finite

--- The value a graphics key may be set to, normalised (whole numbers for levels and MSAA), or nil when `v` is
--- no valid value of that key (wrong type, NaN, out of range). Used on marker data read back from settings.lua,
--- which another mod, an older version or a hand edit may have left in any shape: a wrong value or type given
--- to setAppConfig could fail or worse.
function M.validValue(key, v)
	if LEVEL_KEYS[key] then
		if not finite(v) or v ~= math.floor(v) or v < 0 or v > 2 then return nil end
		return math.floor(v)
	end
	if key == "numMSAASamples" then
		if not finite(v) or not MSAA_COUNTS[v] then return nil end
		return math.floor(v)
	end
	if key == "useSsao" then
		if type(v) ~= "boolean" then return nil end
		return v
	end
	if key == "resolutionScale" then
		if not finite(v) or v < 0.5 - 1e-6 or v > 1 + 1e-6 then return nil end
		return math.max(0.5, math.min(1, v))
	end
	return nil
end

--- The original values from a safety-net marker ({ boosted = true, orig = { key = value } }), as a plain table
--- of valid values only (M.validValue; invalid ones are left out, so those keys are not restored); nil when
--- there is no usable marker (not a table, not boosted, no orig table).
function M.markerOrig(marker)
	if type(marker) ~= "table" then return nil end
	local ok, orig = pcall(function()
		if marker.boosted ~= true then return nil end
		return marker.orig
	end)
	if not ok or type(orig) ~= "table" then return nil end
	local t = {}
	for key, v in pairs(M.snapshot(function(key) return orig[key] end)) do
		local valid = M.validValue(key, v)
		if valid ~= nil then t[key] = valid end
	end
	return t
end

--- Safety net after a session that ended boosted: which keys to put back. A key is restored only when it still
--- has its boosted value (and the original was different); a key the player changed since is kept.
--- Returns put (key -> original value) and kept (list of key names, in M.KEYS order).
function M.recoverKeys(orig, current, boost)
	local put, kept = {}, {}
	for __, key in ipairs(M.KEYS) do
		local o, b = orig[key], boost[key]
		if o ~= nil and b ~= nil and not M.same(o, b) then
			if M.same(current[key], b) then put[key] = o else kept[#kept + 1] = key end
		end
	end
	return put, kept
end

--- "key=value key=value" in M.KEYS order (log lines).
function M.text(t)
	local parts = {}
	for __, key in ipairs(M.KEYS) do
		if t ~= nil and t[key] ~= nil then parts[#parts + 1] = key .. "=" .. tostring(t[key]) end
	end
	return #parts > 0 and table.concat(parts, " ") or "-"
end

--- Re-entrancy gate of the graphics switch (one stage or the restore). setAppConfig stalls up to ~1.2 s; should
--- the engine run a GUI callback (pause menu, a click) inside that call, a second switch would interleave with
--- the first (a stage applied after the restore, snapshot lost). gateEnter refuses while a switch runs; an "off" refused that way is kept
--- in gate.pendingOff and run by the caller right after the running switch (gateLeave returns it).
function M.newGate()
	return { busy = false, pendingOff = nil }
end

function M.gateEnter(g)
	if g.busy then return false end
	g.busy = true
	return true
end

--- Ends a switch; returns the pending "off" reason (cleared) or nil.
function M.gateLeave(g)
	g.busy = false
	local why = g.pendingOff
	g.pendingOff = nil
	return why
end

--- string.format that never raises: a translated pattern whose placeholders don't match the arguments (a player's
--- correction in strings.json, say) would otherwise throw inside a react render and take the UI down. On a
--- failure the pattern's placeholders are dropped and the arguments appended.
function M.fmt(pattern, ...)
	local ok, s = pcall(string.format, pattern, ...)
	if ok then return s end
	local parts = { (tostring(pattern):gsub("%%%-?%d*%.?%d*[%a%%]", "")) }
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- "Hide labels": the base HUD filter (base GUI save data key "", field hudFilter: BaseGUISaveData in
-- base/content/gui/main/game_context.d.tl:83-97, written by base gui/layers/layer_hud_filter.tl). Hidden = every
-- toggle of the base HUD filter window off: the building icons (stations, industries, warehouses, towns,
-- landmarks), every vehicle carrier, costs, income, event icons, cargo flow. BASE_NODE stays: the base window
-- can't switch it back, so a failed restore must never leave it hidden.

--- A deep copy of a plain table (pairs; depth-limited), or the value itself when it is not a table.
function M.deepCopy(t, depth)
	if type(t) ~= "table" then return t end
	depth = depth or 8
	if depth <= 0 then return nil end
	local out = {}
	for k, v in pairs(t) do out[k] = M.deepCopy(v, depth - 1) end
	return out
end

--- The hidden HUD filter: types = the component type values, carriers = the Carrier values to hide.
function M.hiddenHudFilter(types, carriers)
	local pre, car = {}, {}
	for __, t in ipairs(types or {}) do pre[t] = "Hidden" end
	for __, c in ipairs(carriers or {}) do car[c] = "Hidden" end
	return { preFilters = pre, preFilterTvCarriers = car, showCosts = false, showIncome = false,
		showEventIcons = false, showCargoFlow = false }
end

--- True when the HUD filter f still hides everything hiddenHudFilter hides (the player changed nothing since).
function M.isHiddenHudFilter(f, types, carriers)
	if type(f) ~= "table" then return false end
	local ok, r = pcall(function()
		if f.showCosts ~= false or f.showIncome ~= false or f.showEventIcons ~= false or f.showCargoFlow ~= false then
			return false
		end
		for __, t in ipairs(types or {}) do if f.preFilters[t] ~= "Hidden" then return false end end
		for __, c in ipairs(carriers or {}) do if f.preFilterTvCarriers[c] ~= "Hidden" then return false end end
		return true
	end)
	return ok and r == true
end

--- Round 11: the HUD icon config's filter from the HUD filter f (base GUI save data hudFilter, nil = none), as the
--- base default selector builds it (gui/main/selector_react_util.tl makePreFilter, a local there): the shown
--- component types of `types` (the base defaultHudIconFilter) and carriers of `carriers`; every carrier hidden
--- hides vehicleType too (nil carriers then). Returns { preFilter, preFilterTvCarriers, showCosts, showIncome }.
function M.hudPreFilter(f, types, carriers, vehicleType)
	if type(f) ~= "table" then
		return { preFilter = types, preFilterTvCarriers = nil, showCosts = true, showIncome = true }
	end
	local pre, tv = {}, nil
	local hidden = type(f.preFilters) == "table" and f.preFilters or {}
	local hideVehicles = false
	if type(f.preFilterTvCarriers) == "table" then
		local allHidden = true
		tv = {}
		for __, c in ipairs(carriers or {}) do
			if f.preFilterTvCarriers[c] ~= "Hidden" then
				tv[#tv + 1] = c
				allHidden = false
			end
		end
		if allHidden then tv, hideVehicles = nil, true end
	end
	for __, t in ipairs(types or {}) do
		if hidden[t] ~= "Hidden" and not (hideVehicles and t == vehicleType) then pre[#pre + 1] = t end
	end
	return { preFilter = pre, preFilterTvCarriers = tv, showCosts = f.showCosts, showIncome = f.showIncome }
end

return M
