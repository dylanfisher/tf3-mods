-- Photo Mode: saved setups and the last setup (round 16; GUI thread only: window clicks, the plugin's onStep and its
-- openPauseMenu event, the game start). Pure part: ../pm_setup.lua. PLAN: plans/square_photo_mode/PLAN.md "Round 16
-- settings".
--
--   library  named setups of this savegame, in our GUI save data (field `setups`): read at every game start
--            (G.start) from api.gui.game.getGuiSaveData(modId), written at once on every change through G.persist,
--            set by pm_window.lua to its one writer of our save data (setGuiSaveData replaces the whole modId
--            table, so the views, the hud / light markers, `last` and `setups` always go out together). Each save
--            has its own setups; they are kept in the savegame the next time the player saves the game.
--   last     captured whenever the picture changes by a click (pm_sky.noteChange: a value, a look, the freeze) and
--            right before the pause menu or an untick put the player's own values back; kept in our GUI save data
--            (pm_window.lua's save, field `last`), read back at the game start. "Restore last setup" applies it.
--   apply    the look first (one environment switch; pm_weather carries the live values over), then the values
--            (pm_sky.set: the override begins, one log line, the marker saved), the freeze both ways, High graphics
--            mode and hidden labels only on (never off: the switch stalls the game for about a second).
-- Removing the mod: the library and `last` sit in our GUI save data next to the saved views (findings: GUI save
-- data per mod id); the game's settings are never written for them. Every api call in pcall. Logs "[PhotoMode] setup ...".

local core = ug_require "square_photo_mode::/photo_mode/pm_core.lua"
local P = ug_require "square_photo_mode::/photo_mode/pm_setup.lua"
local sky = ug_require "square_photo_mode::/photo_mode/gui/pm_sky.lua"
local hud = ug_require "square_photo_mode::/photo_mode/gui/pm_hud.lua"

local G = {}

-- Set by pm_button.script.lua: whether High graphics mode is on (or switching on), and a request to switch it on.
G.hqOn = function() return false end
G.hqSwitchOn = function() end
-- Set by pm_window.lua: writes our whole GUI save data (views, markers, last, setups) now.
G.persist = function() end

local S = {
	lib = nil,       -- the library (pm_setup.readLibrary) of this game, read on first use and at every game start
	last = nil,      -- the last setup (pm_setup.valid) or nil
	version = 0,     -- grows on every change the window shows
	selected = nil,  -- the setup id the window's dropdown shows
	editing = nil,   -- the setup id being renamed
	restoring = false, -- a setup is being applied: its own changes don't rewrite the last setup mid-way
}
G.S = S

local function try(what, fn)
	local ok, err = pcall(fn)
	if not ok then core.log("setup " .. what .. " ERROR " .. tostring(err)) end
	return ok
end

local function bump() S.version = S.version + 1 end

--- A number that grows whenever the window should render again (pm_window version()).
function G.version() return S.version end

---------------------------------------------------------------------------
-- The current state

--- What the picture is now: { override, values, look, freeze, hq, labels } (pm_setup.capture's input).
function G.state()
	local st = {}
	pcall(function()
		st.override = sky.active()
		st.values = sky.shown()
	end)
	pcall(function()
		local ls = sky.status() or {}
		if ls.sky ~= nil or ls.haze ~= nil or ls.water ~= nil then
			st.look = { sky = ls.sky, haze = ls.haze, water = ls.water }
		end
	end)
	pcall(function() st.freeze = sky.frozen() end)
	pcall(function() st.hq = G.hqOn() == true end)
	pcall(function() st.labels = hud.labelsHidden() == true end)
	return st
end

---------------------------------------------------------------------------
-- The last setup

--- Keeps the current picture as the last setup when something of ours shapes it (override, look, freeze); else the
--- last one stays. Returns true when it was kept.
function G.capture(why)
	if S.restoring then return false end
	local st = G.state()
	if not P.active(st) then return false end
	local s = P.capture(st, false)
	if s == nil then return false end
	if S.last ~= nil and P.same(S.last, s) then return true end
	S.last = s
	bump()
	core.log("setup last (" .. tostring(why) .. "): " .. P.text(s))
	return true
end

function G.last() return S.last end

--- The last setup for our GUI save data (pm_window.lua's save), or nil.
function G.lastData() return S.last ~= nil and P.plain(S.last) or nil end

---------------------------------------------------------------------------
-- The library (our GUI save data, field `setups`)

--- Our GUI save data's `setups` field, read with any shape tolerated (pm_setup.readLibrary keeps valid setups).
local function readSaved()
	local raw = nil
	pcall(function()
		local mine = api.gui.game.getGuiSaveData(core.MOD_ID)
		if type(mine) == "table" then raw = mine.setups end
	end)
	return P.readLibrary(raw)
end

function G.library()
	if S.lib == nil then
		S.lib = readSaved()
		core.log("setups loaded n=" .. #S.lib)
	end
	return S.lib
end

--- The library for our GUI save data (pm_window.lua's save, field `setups`).
function G.libraryData() return P.libraryData(G.library()) end

local function setLibrary(list, what)
	S.lib = list
	bump()
	core.log("setup " .. what .. " (n=" .. #list .. ")")
	try("write", G.persist)
end

function G.selected()
	local list = G.library()
	if S.selected ~= nil and P.find(list, S.selected) ~= nil then return S.selected end
	return list[1] and list[1].id or nil
end

function G.select(id)
	if P.find(G.library(), id) ~= nil then S.selected = id; bump() end
end

function G.editing() return S.editing end

--- Saves the current picture as a new setup named `name`; the new one is selected and its name field opens.
--- Returns the new id, or nil (full, or an empty name).
function G.saveNew(name)
	local s = P.capture(G.state(), true)
	local list, id = P.add(G.library(), s, name)
	if id == nil then return nil end
	S.selected, S.editing = id, id
	setLibrary(list, "save id=" .. id .. " " .. P.text(s))
	return id
end

--- Overwrites setup `id` with the current picture.
function G.overwrite(id)
	local s = P.capture(G.state(), true)
	local list, ok = P.overwrite(G.library(), id, s)
	if ok then setLibrary(list, "overwrite id=" .. tostring(id) .. " " .. P.text(s)) end
	return ok
end

function G.editName(id)
	if P.find(G.library(), id) ~= nil then S.editing = id; bump() end
end

function G.rename(id, name)
	S.editing = nil
	local list, ok = P.rename(G.library(), id, name)
	if ok then setLibrary(list, "rename id=" .. tostring(id)) else bump() end
	return ok
end

function G.cancelRename()
	S.editing = nil
	bump()
end

function G.remove(id)
	if S.editing == id then S.editing = nil end
	local list, ok = P.remove(G.library(), id)
	if ok then
		if S.selected == id then S.selected = nil end
		setLibrary(list, "delete id=" .. tostring(id))
	end
	return ok
end

---------------------------------------------------------------------------
-- Applying a setup

--- Puts setup `s` on: the look, the values, the freeze, High graphics mode and hidden labels (only on).
function G.apply(s, why)
	s = P.valid(s)
	if s == nil then return false end
	S.restoring = true
	try("apply " .. tostring(why), function()
		local ls = sky.status() or {}
		local lk = s.look
		if lk ~= nil then
			if ls.looks ~= nil then
				sky.look(lk.sky, lk.haze, lk.water, why)
			else
				core.log("setup " .. tostring(why) .. ": this climate has no looks, the look is left out")
			end
		elseif ls.look ~= nil then
			sky.look(nil, nil, nil, why)
		end
		if s.values ~= nil then
			local v = {}
			for k, x in pairs(s.values) do v[k] = x end
			sky.set(v, why)
		end
		if s.freeze ~= sky.frozen() then sky.setFreeze(s.freeze, why) end
		if s.hq and not G.hqOn() then G.hqSwitchOn() end
		if s.labels and not hud.labelsHidden() then hud.setLabels(true, why) end
	end)
	S.restoring = false
	core.log("setup " .. tostring(why) .. ": " .. P.text(s))
	G.capture(why)
	bump()
	return true
end

--- Loads setup `id` of the library.
function G.load(id)
	local s = P.find(G.library(), id)
	if s == nil then return false end
	return G.apply(s, "setup " .. tostring(id))
end

--- "Restore last setup".
function G.restoreLast()
	if S.last == nil then return false end
	return G.apply(S.last, "restore last")
end

---------------------------------------------------------------------------
-- Game start and hooks

--- First frame of a game (pm_button.script.lua start): the library and the last setup from this save's GUI save
--- data (our data's `setups` and `last` fields; nothing of `last` when it holds no look, no values and no freeze).
function G.start()
	S.lib = readSaved()
	S.selected = nil
	core.log("setups loaded n=" .. #S.lib)
	local raw = nil
	pcall(function()
		local mine = api.gui.game.getGuiSaveData(core.MOD_ID)
		if type(mine) == "table" then raw = mine.last end
	end)
	S.last = raw ~= nil and P.valid(raw) or nil
	if S.last ~= nil and S.last.look == nil and S.last.values == nil and not S.last.freeze then S.last = nil end
	S.editing, S.restoring = nil, false
	if S.last ~= nil then core.log("setup last from this save: " .. P.text(S.last)) end
	bump()
end

sky.noteChange = function() G.capture("change") end
sky.beforeRestore = function() G.capture("untick") end

return G
