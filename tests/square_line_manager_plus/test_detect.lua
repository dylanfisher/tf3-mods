-- lmp_detect.lua: active-mod detection through the react-replacement-config resources in api.res.genericRep, the
-- yieldsTo hand-shake, and the Off/On param reads. square_line_revert ships the same file (line_revert_detect.lua);
-- tests/square_line_revert/test_detect.lua checks the two copies are identical.

local detect = ug_require "square_line_manager_plus::/line_manager_plus/lmp_detect.lua"

-- configs: list of data tables (nil entries = a resource without data); params: the getModParams() result or
-- "error"; resError: getAllOfType throws
local function fakeApi(configs, params, resError)
	return {
		res = { genericRep = {
			getAllOfType = function(t, includeInvisible)
				if resError then error("no res here") end
				eq(t, "react-replacement-config")
				eq(includeInvisible, nil) -- same call as base bootstrap_game.tl:13
				local ids = {}
				for i = 1, #configs do ids[i] = 100 + i end
				return ids
			end,
			get = function(id) return { type = "react-replacement-config", data = configs[id - 100] } end,
		} },
		engine = { config = { getModParams = function()
			if params == "error" then error("no engine here") end
			return params
		end } },
	}
end

local LR = { filePath = "square_line_revert::/line_revert/line_revert.script", doReplaceFn = "doReplace", order = 200 }
local LR5 = { filePath = "square_line_revert::/line_revert/line_revert.script", doReplaceFn = "doReplace", order = 200,
	yieldsTo = "square_line_manager_plus" }
local LMP = { filePath = "square_line_manager_plus::/line_manager_plus/lmp.script", doReplaceFn = "doReplace", order = 250 }
local OTHER = { filePath = "::/gui/mission/hud_replace.script", doReplaceFn = "doReplace" }

test("configsOf: only configs whose filePath starts with '<modId>::'", function()
	local api = fakeApi({ OTHER, LR, LMP, { doReplaceFn = "x" }, { filePath = 7 } })
	local lr = detect.configsOf(api, "square_line_revert")
	eq(#lr, 1)
	ok(lr[1] == LR)
	eq(#detect.configsOf(api, "square_line_manager_plus"), 1)
	-- a modId that is only a prefix of another one doesn't match ("::" is part of the test)
	eq(#detect.configsOf(api, "square_line"), 0)
	eq(#detect.configsOf(fakeApi({}), "square_line_revert"), 0)
end)

test("configsOf: a resource without data is skipped", function()
	local api = fakeApi({ LR })
	api.res.genericRep.get = function() return { data = nil } end
	eq(#detect.configsOf(api, "square_line_revert"), 0)
	api.res.genericRep.get = function() return nil end
	eq(#detect.configsOf(api, "square_line_revert"), 0)
end)

test("isActive: true with the mod's config, false without", function()
	eq(detect.isActive(fakeApi({ OTHER, LR }), "square_line_revert"), true)
	eq(detect.isActive(fakeApi({ OTHER, LMP }), "square_line_revert"), false)
	eq(detect.isActive(fakeApi({ OTHER, LMP }), "square_line_manager_plus"), true)
end)

test("isActive / configsOf: repository errors propagate (callers choose the fallback)", function()
	raises(function() detect.isActive(fakeApi({ LR }, nil, true), "square_line_revert") end, "no res here")
end)

test("activeWithoutYield: an older Line Editor Undo (no marker) counts, rev 5+ (yieldsTo us) doesn't", function()
	eq(detect.activeWithoutYield(fakeApi({ LR }), "square_line_revert", "square_line_manager_plus"), true)
	eq(detect.activeWithoutYield(fakeApi({ LR5 }), "square_line_revert", "square_line_manager_plus"), false)
	eq(detect.activeWithoutYield(fakeApi({ OTHER }), "square_line_revert", "square_line_manager_plus"), false)
	-- a marker for someone else is no yield to us
	local lrOther = { filePath = LR.filePath, yieldsTo = "square_something_else" }
	eq(detect.activeWithoutYield(fakeApi({ lrOther }), "square_line_revert", "square_line_manager_plus"), true)
end)

test("modParams: the mod's table, nil when missing or unreadable (never errors)", function()
	local mine = { line_undo = 1 }
	ok(detect.modParams(fakeApi({}, { square_line_manager_plus = mine }), "square_line_manager_plus") == mine)
	eq(detect.modParams(fakeApi({}, { other = {} }), "square_line_manager_plus"), nil)
	eq(detect.modParams(fakeApi({}, "error"), "square_line_manager_plus"), nil)
	eq(detect.modParams(fakeApi({}, nil), "square_line_manager_plus"), nil)
	eq(detect.modParams({}, "square_line_manager_plus"), nil) -- no api.engine
end)

test("paramOn: Off only at index 1; missing table or key = the default On", function()
	eq(detect.paramOn({ k = 1 }, "k"), false)
	eq(detect.paramOn({ k = 2 }, "k"), true)
	eq(detect.paramOn({}, "k"), true)
	eq(detect.paramOn(nil, "k"), true)
end)
