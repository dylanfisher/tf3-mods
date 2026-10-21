-- Line Manager Plus: the one writer of the mod's GUI save data (api.gui.game.getGuiSaveData / setGuiSaveData(KEY,
-- table), gui.d.tl:773-781; docs/findings/publishing.md). setGuiSaveData replaces the whole table of the key, so every
-- feature that keeps data in the savegame goes through here: each owns one top-level part, and every write carries all
-- parts, the other features' and any unknown ones (a newer revision's) unchanged.
--   * "lineManager" (lmp_visible.lua): boolean, the Line Manager's "Show Only Visible Lines".
--   * "util" (lmp_util_avg.lua): the average utilization history, its own versioned format (see there).
-- The table is read once per load, on the first get or set (the GUI scripts reload with each game load, so another
-- save's data is never mixed in). If that read fails, nothing is ever written in this load: a write would replace the
-- parts we could not read. Callers validate what a part holds (old revisions, edited saves). Never errors.
-- Removing the mod leaves this table unused in the save (Photo Mode TESTING P11: the save loads without a warning).

local M = {}

M.KEY = "square_line_manager_plus"

local data = nil -- the top-level parts, nil until read
local readErr = nil -- why the read failed (then nothing is written)

local function load()
	if data ~= nil then return end
	data = {}
	local ok, err = pcall(function()
		local raw = api.gui.game.getGuiSaveData(M.KEY)
		if type(raw) ~= "table" then return end -- nil in a new game or a save without our data
		local n = 0
		for k, v in pairs(raw) do
			n = n + 1
			if n > 64 then break end -- our table has a handful of parts: anything beyond is not ours
			if type(k) == "string" then data[k] = v end
		end
	end)
	if not ok then readErr = tostring(err) end
end

--- The part `name` as stored (any type: the caller validates), nil when absent. Never errors.
function M.get(name)
	load()
	return data[name]
end

--- The error of this load's read, or nil when it worked.
function M.readError()
	load()
	return readErr
end

--- Stores `value` as the part `name` (nil removes it) and writes the whole table. true, or false and the reason.
--- Never errors.
function M.set(name, value)
	load()
	if readErr ~= nil then
		data[name] = value -- remembered for this load
		return false, "save data unreadable (" .. readErr .. "), not written"
	end
	data[name] = value
	local out = {}
	for k, v in pairs(data) do out[k] = v end
	local ok, err = pcall(function() api.gui.game.setGuiSaveData(M.KEY, out) end)
	if not ok then return false, tostring(err) end
	return true
end

--- For tests: forget what was read.
function M.reset()
	data, readErr = nil, nil
end

return M
