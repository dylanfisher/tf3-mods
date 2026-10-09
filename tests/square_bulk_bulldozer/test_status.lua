-- bb_status: the toolbar status chip text (user request 2026-10-07).

local status = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_status.tl"

local function input(t)
	local v = { phase = "none", count = 0, kindCounts = {}, objects = 0, cost = nil, capped = false, cap = 400, result = nil }
	for k, x in pairs(t) do v[k] = x end
	return v
end

test("kindSummary: display order, singular/plural, signals", function()
	eq(status.kindSummary({}, 0), "")
	eq(status.kindSummary({ track = 3, road = 1 }, 0), "1 road · 3 tracks")
	eq(status.kindSummary({ asset = 2 }, 1), "2 assets · 1 signal/stop")
	eq(status.kindSummary({ town_building = 1, station = 2 }, 0), "2 stations · 1 building")
end)

test("kindSummary: more than MAX_KIND_PARTS parts ends with ...", function()
	eq(status.kindSummary({ road = 2, track = 4, asset = 1, station = 1 }, 5),
		"2 roads · 4 tracks · 1 station ...")
	eq(status.kindSummary({ road = 2, track = 4, asset = 1 }, 0), "2 roads · 4 tracks · 1 asset")
end)

test("kindSummary: unknown kinds (industry/other never kept) are ignored", function()
	eq(status.kindSummary({ industry = 3, other = 1, road = 1 }, 0), "1 road")
end)

test("clip: short unchanged, long cut with ..., never inside a UTF-8 sequence", function()
	eq(status.clip("abc", 10), "abc")
	eq(status.clip("abcdefghij", 8), "abcde...")
	eq(status.clip(nil, 8), "")
	-- "·" is 2 bytes (C2 B7): a cut that would split it backs off before it.
	local s = "1234·6789"   -- bytes: 1234 C2 B7 6789
	eq(status.clip(s, 8), "1234...")
	eq(status.clip("ab", 2), "ab")
end)

test("lines: nothing selected", function()
	eq(status.lines(input({})), { head = "Nothing selected", detail = "Paint with the left mouse button" })
	eq(status.lines(input({ phase = "painting", count = 0 })).head, "Nothing selected")
end)

test("lines: hover preview shows what the brush would take", function()
	eq(status.lines(input({ phase = "idle", count = 4, kindCounts = { road = 3, track = 1 } })),
		{ head = "Nothing selected", detail = "Brush: 3 roads · 1 track" })
end)

test("lines: selection with cost and kinds", function()
	eq(status.lines(input({ phase = "selected", count = 12, cost = "$34,500", kindCounts = { road = 8, track = 3, asset = 1 } })),
		{ head = "12 selected · $34,500", detail = "8 roads · 3 tracks · 1 asset" })
	eq(status.lines(input({ phase = "painting", count = 2, kindCounts = { road = 2 } })),
		{ head = "2 selected", detail = "2 roads" })
	eq(status.lines(input({ phase = "selected", count = 400, capped = true, cost = "$1", kindCounts = { road = 400 } })).head,
		"400 selected (max) · $1")
end)

test("lines: committing", function()
	eq(status.lines(input({ phase = "committing", count = 5, kindCounts = { track = 5 } })),
		{ head = "Bulldozing 5...", detail = "5 tracks" })
end)

test("lines: a result replaces 'Nothing selected' but not a live selection", function()
	local r = { head = "Bulldozed 3", detail = "Paint with the left mouse button" }
	eq(status.lines(input({ phase = "idle", count = 2, kindCounts = { road = 2 }, result = r })), r)
	eq(status.lines(input({ result = r })), r)
	eq(status.lines(input({ phase = "painting", count = 1, kindCounts = { road = 1 }, result = r })).head, "1 selected")
end)

test("lines: every line fits MAX_CHARS", function()
	local t = status.lines(input({ phase = "selected", count = 399, cost = "$123,456,789,012,345,678",
		kindCounts = { road = 200, track = 100, asset = 99 }, objects = 50, capped = true }))
	ok(#t.head <= status.MAX_CHARS, t.head)
	ok(#t.detail <= status.MAX_CHARS, t.detail)
end)

test("resultLines: refused, clean, skipped with top reasons", function()
	eq(status.resultLines({ requested = 4, removed = 0, skipped = 4, reasons = {}, commands = 0, refused = "not enough money" }),
		{ head = "Nothing bulldozed", detail = "not enough money" })
	eq(status.resultLines({ requested = 4, removed = 4, skipped = 0, reasons = {}, commands = 1 }),
		{ head = "Bulldozed 4", detail = "Paint with the left mouse button" })
	eq(status.resultLines({ requested = 10, removed = 6, skipped = 4, commands = 5,
		reasons = { ["vehicle in the way"] = 1, locked = 3, other = 1 } }),
		{ head = "Bulldozed 6 · 4 skipped", detail = "locked, other" })
	eq(status.resultLines({ requested = 2, removed = 1, skipped = 1, reasons = {}, commands = 2 }).detail, "See the game log")
end)

test("oneLine", function()
	eq(status.oneLine({ head = "a", detail = "b" }), "a / b")
	eq(status.oneLine(nil), "")
end)
