-- line_revert_detect.lua is a copy of Line Manager Plus's lmp_detect.lua (tested in
-- tests/square_line_manager_plus/test_detect.lua). Here: the copies are identical, and a smoke test of this copy.

local detect = ug_require "square_line_revert::/line_revert/line_revert_detect.lua"

local function read(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local s = f:read("a")
	f:close()
	return s
end

test("identical to mods/square_line_manager_plus/.../lmp_detect.lua", function()
	local mine = read("mods/square_line_revert/content/line_revert/line_revert_detect.lua")
	local theirs = read("mods/square_line_manager_plus/content/line_manager_plus/lmp_detect.lua")
	ok(mine ~= nil, "line_revert_detect.lua readable from the repo root")
	ok(theirs ~= nil, "lmp_detect.lua readable from the repo root")
	ok(mine == theirs, "the two detection helpers differ: copy lmp_detect.lua over line_revert_detect.lua")
end)

test("isActive finds square_line_manager_plus by its config's filePath; paramOn reads line_undo", function()
	local configs = {
		{ filePath = "square_line_revert::/line_revert/line_revert.script" },
		{ filePath = "square_line_manager_plus::/line_manager_plus/lmp.script" },
	}
	local api = {
		res = { genericRep = {
			getAllOfType = function() return { 1, 2 } end,
			get = function(id) return { data = configs[id] } end,
		} },
		engine = { config = { getModParams = function() return { square_line_manager_plus = { line_undo = 1 } } end } },
	}
	eq(detect.isActive(api, "square_line_manager_plus"), true)
	eq(detect.paramOn(detect.modParams(api, "square_line_manager_plus"), "line_undo"), false)
	configs[2] = nil
	api.res.genericRep.getAllOfType = function() return { 1 } end
	eq(detect.isActive(api, "square_line_manager_plus"), false)
end)
