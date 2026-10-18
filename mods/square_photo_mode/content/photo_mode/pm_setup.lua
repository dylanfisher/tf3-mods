-- Photo Mode: saved setups, the pure part (no api calls). Round 16 (user: "I want a way to save the settings as a
-- whole in case you press Escape by accident, like 'custom golden 1', 'my dark night' etc."). Shared by
-- gui/pm_setups.lua and the offline tests (tests/square_photo_mode/test_setups.lua). Plain Lua, pre-5.3.
-- PLAN: plans/square_photo_mode/PLAN.md "Round 16 settings".
--
-- A setup is the whole picture Photo Mode controls:
--   look     { sky, haze, water } layer keys (pm_looks; "legacy" is a whole look in the sky slot), nil = the
--            climate's own look
--   values   pm_light fields time, day, sun, cloud, cloudBase, cloudTop, cloudScattering (the light & weather
--            override's values), nil = the override was off (the "last setup" then leaves the override alone)
--   freeze   the game paused by Freeze time
--   hq, labels  High graphics mode / Hide labels and hover were on (loading only switches them on, never off:
--            High graphics mode stalls the game for about a second)
--
-- Two kinds:
--   library  named setups, kept in AppConfig.mainMenuState[KEY] (the game's settings.lua): the same setups in every
--            savegame, never in a save, so removing the mod can't touch a save. At most CAP, names cleaned like
--            the saved views' (at most NAME_MAX characters).
--   last     the most recent setup in which something of ours was on (override, look or freeze), captured at every
--            change and right before the pause menu (Esc) or an untick put the player's own values back: "Restore
--            last setup" undoes an accidental Esc. Kept in our GUI save data (field `last`, with the saved views),
--            so it also survives a save and reload.

local L = ug_require "square_photo_mode::/photo_mode/pm_light.lua"

local M = {}

-- The AppConfig.mainMenuState key of the library. Not "square_photo_mode": pm_button.script.lua writes and clears
-- the high graphics marker there (pm_core.withMarker), which would wipe the setups.
M.KEY = "square_photo_mode_setups"
M.CAP = 30
M.NAME_MAX = 40
M.VALUE_FIELDS = { "time", "day", "sun", "cloud", "cloudBase", "cloudTop", "cloudScattering" }
M.LAYERS = { "sky", "haze", "water" }

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

--- A setup name as typed (the saved views' rules, pm_cam.cleanName): ASCII control characters become spaces, runs
--- of spaces one, trimmed, cut to NAME_MAX characters on a UTF-8 character boundary. nil for an empty name or a
--- non-string. Byte by byte: %c / %s follow the C locale and may match UTF-8 continuation bytes.
function M.cleanName(s)
	if type(s) ~= "string" then return nil end
	local out, chars, pendingSpace = {}, 0, false
	for i = 1, #s do
		local b = s:byte(i)
		if b <= 32 or b == 127 then
			pendingSpace = #out > 0
		else
			local lead = b < 128 or b >= 192
			if lead then
				local need = pendingSpace and 2 or 1
				if chars + need > M.NAME_MAX then break end
				if pendingSpace then
					out[#out + 1] = " "
					chars = chars + 1
				end
				chars = chars + 1
				pendingSpace = false
			end
			out[#out + 1] = string.char(b)
		end
	end
	if #out == 0 then return nil end
	return table.concat(out)
end

local function lookKey(k)
	if type(k) == "string" and #k <= 40 and k:match("^[a-z_]+$") and k ~= "orig" then return k end
	return nil
end

--- A clean copy of a setup (anything malformed dropped), or nil when `s` isn't a table. Id and name are kept when
--- valid (library entries); a setup with nothing in it is still a setup (the climate's own look, nothing frozen).
function M.valid(s)
	if type(s) ~= "table" then return nil end
	local ok, out = pcall(function()
		local o = {}
		if finite(s.id) and s.id >= 1 and s.id < 1e9 then o.id = math.floor(s.id) end
		o.name = M.cleanName(s.name)
		if type(s.look) == "table" then
			local lk = {}
			for __, layer in ipairs(M.LAYERS) do lk[layer] = lookKey(s.look[layer]) end
			if lk.sky or lk.haze or lk.water then o.look = lk end
		end
		if type(s.values) == "table" then
			local v = L.validState(s.values)
			local vals = {}
			for __, k in ipairs(M.VALUE_FIELDS) do vals[k] = v[k] end
			if next(vals) ~= nil then o.values = vals end
		end
		o.freeze = s.freeze == true
		o.hq = s.hq == true
		o.labels = s.labels == true
		return o
	end)
	return ok and out or nil
end

--- A plain copy for storage (numbers, strings and booleans only).
function M.plain(s)
	s = M.valid(s)
	if s == nil then return nil end
	local out = { id = s.id, name = s.name, freeze = s.freeze, hq = s.hq, labels = s.labels }
	if s.look ~= nil then out.look = { sky = s.look.sky, haze = s.look.haze, water = s.look.water } end
	if s.values ~= nil then
		out.values = {}
		for k, v in pairs(s.values) do out.values[k] = v end
	end
	return out
end

--- The library read back from settings.lua (any shape may come back: another version, a hand-edited file): only
--- valid setups with an id and a name, no repeated ids, at most CAP.
function M.readLibrary(raw)
	local out, seen = {}, {}
	pcall(function()
		if type(raw) ~= "table" or type(raw.list) ~= "table" then return end
		for __, s in ipairs(raw.list) do
			if #out >= M.CAP then break end
			local v = M.valid(s)
			if v ~= nil and v.id ~= nil and v.name ~= nil and not seen[v.id] then
				seen[v.id] = true
				out[#out + 1] = v
			end
		end
	end)
	return out
end

--- What goes into AppConfig.mainMenuState[KEY].
function M.libraryData(list)
	local out = { v = 1, list = {} }
	for __, s in ipairs(list or {}) do
		local p = M.plain(s)
		if p ~= nil then out.list[#out.list + 1] = p end
	end
	return out
end

function M.find(list, id)
	for i, s in ipairs(list or {}) do
		if s.id == id then return s, i end
	end
	return nil
end

function M.nextId(list)
	local n = 0
	for __, s in ipairs(list or {}) do
		if type(s.id) == "number" and s.id > n then n = s.id end
	end
	return n + 1
end

local function copyList(list)
	local out = {}
	for i, s in ipairs(list or {}) do out[i] = s end
	return out
end

--- Adds `setup` under `name` (cleaned; nil -> no add). Returns the new list and the new setup's id, or the list
--- unchanged and nil when full or the name is empty.
function M.add(list, setup, name)
	list = list or {}
	if #list >= M.CAP then return list, nil end
	local s = M.valid(setup)
	local n = M.cleanName(name)
	if s == nil or n == nil then return list, nil end
	s.id, s.name = M.nextId(list), n
	local out = copyList(list)
	out[#out + 1] = s
	return out, s.id
end

--- Replaces setup `id`'s contents with `setup` (id and name kept). Returns the new list and true, or the list
--- unchanged and false.
function M.overwrite(list, id, setup)
	local cur, i = M.find(list, id)
	local s = M.valid(setup)
	if cur == nil or s == nil then return list, false end
	s.id, s.name = cur.id, cur.name
	local out = copyList(list)
	out[i] = s
	return out, true
end

--- Renames setup `id` (an empty name changes nothing).
function M.rename(list, id, name)
	local cur, i = M.find(list, id)
	local n = M.cleanName(name)
	if cur == nil or n == nil or n == cur.name then return list, false end
	local s = M.valid(cur)
	s.name = n
	local out = copyList(list)
	out[i] = s
	return out, true
end

function M.remove(list, id)
	local __, i = M.find(list, id)
	if i == nil then return list, false end
	local out = copyList(list)
	table.remove(out, i)
	return out, true
end

--- A copy of mainMenuState (nil or table-like, read with pairs) with `key` set to `value` (nil clears it); other
--- keys untouched. nil when it can't be copied completely: writing a partial copy back would wipe other mods'
--- prefs, so the caller must not write then (as pm_core.withMarker).
function M.withKey(mm, key, value)
	local t = {}
	if mm ~= nil then
		local ok = pcall(function() for k, v in pairs(mm) do t[k] = v end end)
		if not ok then return nil end
	end
	t[key] = value
	return t
end

--- True when something of ours shapes the picture (st: { override, look, freeze }): only then is a "last setup"
--- worth keeping.
function M.active(st)
	return type(st) == "table" and (st.override == true or st.look ~= nil or st.freeze == true)
end

--- A setup from the current state `st`: { override (bool), values (pm_light fields), look ({ sky, haze, water } or
--- nil), freeze, hq, labels }. withValues: keep the values even when the override is off (a named setup keeps the
--- picture's time and weather; the last setup only what the override set).
function M.capture(st, withValues)
	st = type(st) == "table" and st or {}
	local s = {
		look = st.look,
		freeze = st.freeze == true,
		hq = st.hq == true,
		labels = st.labels == true,
	}
	if st.values ~= nil and (withValues or st.override == true) then s.values = st.values end
	return M.valid(s)
end

--- True when two setups would show the same picture (ids and names aside): the last setup isn't rewritten then.
function M.same(a, b)
	a, b = M.plain(a), M.plain(b)
	if a == nil or b == nil then return a == b end
	if a.freeze ~= b.freeze or a.hq ~= b.hq or a.labels ~= b.labels then return false end
	local la, lb = a.look or {}, b.look or {}
	for __, k in ipairs(M.LAYERS) do if la[k] ~= lb[k] then return false end end
	local va, vb = a.values, b.values
	if (va == nil) ~= (vb == nil) then return false end
	if va ~= nil then
		for __, k in ipairs(M.VALUE_FIELDS) do
			local x, y = va[k], vb[k]
			if (x == nil) ~= (y == nil) then return false end
			if x ~= nil and math.abs(x - y) > 1e-6 then return false end
		end
	end
	return true
end

--- "look=a/b/c values=... freeze hq labels" (log lines).
function M.text(s)
	s = M.valid(s)
	if s == nil then return "-" end
	local parts = {}
	if s.look ~= nil then
		parts[#parts + 1] = "look=" .. tostring(s.look.sky or "-") .. "/" .. tostring(s.look.haze or "-") .. "/"
			.. tostring(s.look.water or "-")
	end
	if s.values ~= nil then parts[#parts + 1] = L.text(s.values) end
	if s.freeze then parts[#parts + 1] = "freeze" end
	if s.hq then parts[#parts + 1] = "hq" end
	if s.labels then parts[#parts + 1] = "labels" end
	return #parts > 0 and table.concat(parts, " ") or "-"
end

return M
