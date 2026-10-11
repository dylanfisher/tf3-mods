-- ASCII preview.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_showcase/"
local H = loadfile(here .. "helpers.lua", "t", _ENV)()
local preview = ug_require "/showcase/sc_preview.lua"

test("symbols, mirrors in lowercase, the centre, the size limit", function()
	local ps = {
		{ item = { symbol = "R" }, fp = H.fakeFp(100, 100), x = -500, y = 0, rot = 0 },
		{ item = { symbol = "P" }, fp = H.fakeFp(400, 200), x = 500, y = 300, rot = 90, mirrored = true },
	}
	local lines = preview.render(ps, 0, 0, 40, 20)
	local body = table.concat(lines, "\n", 1, #lines - 1)
	ok(body:find("R", 1, true))
	ok(body:find("p", 1, true))
	ok(not body:find("P", 1, true))
	ok(body:find("+", 1, true))
	for i = 1, #lines - 1 do ok(#lines[i] <= 40) end
	ok(#lines - 1 <= 20)
	eq(preview.render({}, 0, 0), { "(nothing placed)" })
end)
