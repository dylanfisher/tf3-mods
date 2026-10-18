-- square_smart_lanes "Record traffic" (PLAN.md "Traffic rate at a junction"): the pure part, sl_record.lua (the 30 s
-- bucket ring, the rates, the saved records with their cap, the texts) and the event validation (sl_auto.lua op
-- "traffic"). The tool's recording (start / stop / one at a time / goes on / saved through the game script) is in
-- test_tool.lua "record traffic".

local Rec = ug_require "square_smart_lanes::/smart_lanes/sl_record.lua"
local Auto = ug_require "square_smart_lanes::/smart_lanes/sl_auto.lua"

test("bucket ring: counts land in the 30 s bucket of their game time; the last-3-minutes span is 180 .. 210 s", function()
	local b = Rec.newBuckets()
	eq(b.n, 40, "20 min of 30 s buckets")
	-- 2 vehicles every 5 s for 6 minutes (from 5 s on), then 1 every 5 s up to 600 s
	for e = 5, 600, 5 do ok(Rec.add(b, e, e <= 360 and 2 or 1)) end
	local r = Rec.result(b, 600)
	eq(r.v, 72 * 2 + 48, "the whole recording")
	-- at 600 s the current bucket is 20 (600 .. 630): buckets 14 .. 20, from 420 s on
	eq(r.d3, 180)
	eq(r.v3, 37, "1 per 5 s from 420 to 600 s (both inclusive)")
	local r2 = Rec.result(b, 625)
	eq(r2.d3, 205, "the current bucket only partly over: the span grows to 210 s")
	eq(Rec.result(b, 100).d3, 100, "shorter than 3 min: the span is the whole recording")
	-- invalid input is ignored
	ok(not Rec.add(b, -1, 1))
	ok(not Rec.add(b, 0 / 0, 1))
	ok(not Rec.add(b, 10, -2))
	eq(Rec.result(b, 600).v, 192, "unchanged")
	-- the ring reuses a slot whose index passed 40 buckets ago (a recording never gets there: MAX_S = 40 buckets)
	local w = Rec.newBuckets()
	Rec.add(w, 5, 7)
	Rec.add(w, 5 + 40 * 30, 3)
	eq(Rec.result(w, 5 + 40 * 30).v3, 3, "the old count left the ring")
	eq(Rec.result(w, 5 + 40 * 30).v, 10, "and stays in the total")
end)

test("rates: vehicles per minute, shown with one decimal under 10, whole from 10; minutes at least 1", function()
	eq(Rec.rate(30, 60), 30)
	eq(Rec.rate(1, 0), nil)
	eq(Rec.rateText(Rec.rate(7, 60)), "7.0")
	eq(Rec.rateText(4.25), "4.2")
	eq(Rec.rateText(9.96), "10")
	eq(Rec.rateText(155.6), "156")
	eq(Rec.rateText(nil), "-")
	eq(Rec.minutes(20), 1)
	eq(Rec.minutes(355), 6)
	eq(Rec.minutes(205), 3)
end)

test("texts: the running line, the rates (junction / roundabout entries, one rate while short), the saved record", function()
	eq(Rec.runningLine(0), "Recording traffic: 0 of 20 min")
	eq(Rec.runningLine(7 * 60 + 59), "Recording traffic: 7 of 20 min")
	eq(Rec.runningLine(5000), "Recording traffic: 20 of 20 min")
	eq(Rec.ratesLine("node", { d = 20, v = 4, d3 = 20, v3 = 4 }), nil, "nothing before the first bucket is over")
	eq(Rec.ratesLine("node", { d = 120, v = 60, d3 = 120, v3 = 60 }), "Vehicles per minute: 30 (2 min)")
	eq(Rec.ratesLine("ring", { d = 120, v = 6, d3 = 120, v3 = 6 }), "Vehicles entering per minute: 3.0 (2 min)")
	eq(Rec.ratesLine("node", { d = 600, v = 300, d3 = 180, v3 = 120 }), "Vehicles per minute: 40 (last 3 min), 30 (all 10 min)")
	eq(Rec.ratesLine("ring", { d = 600, v = 300, d3 = 180, v3 = 120 }),
		"Vehicles entering per minute: 40 (last 3 min), 30 (all 10 min)")
	local rec = Rec.record("node", 500, 1000, 1000, 4000, { d = 600, v = 300, d3 = 180, v3 = 120 })
	eq(rec, { 500, 1000, 1000, 4000, 1, 600, 300, 180, 120 })
	eq(Rec.savedLines(rec, "12 min ago"),
		{ "Traffic recorded 12 min ago (10 min)", "Vehicles per minute: 40 (last 3 min), 30 (all 10 min)" })
	eq(Rec.savedLines({ "x" }, "now"), nil)
	-- the previous recording's line (shown muted): the whole-recording rate, its minutes and when
	eq(Rec.prevLine("node", { t = 100, d = 1200, v = 240 }, "2 h ago"), "Previous recording: 12 vehicles per minute (20 min, 2 h ago)")
	eq(Rec.prevLine("ring", { t = 100, d = 300, v = 31 }, "12 min ago"),
		"Previous recording: 6.2 vehicles entering per minute (5 min, 12 min ago)")
	eq(Rec.prevLine("node", nil, "now"), nil, "no previous")
	eq(Rec.prevLine("node", { t = 1, d = 0, v = 3 }, "now"), nil, "no time recorded: no rate")
end)

test("records: the previous result kept (12 numbers); an old 9-number record reads without one; a partial previous dropped", function()
	-- an old rev 8 record (9 numbers): read as before, no previous
	local old = { 5, 1, 2, 10, 1, 60, 30, 60, 30 }
	eq(Rec.entryOf(old), old)
	eq(Rec.parts(old).prev, nil)
	eq(Rec.prevOf(old), { t = 10, d = 60, v = 30 }, "a new recording keeps it as its previous")
	eq(Rec.prevOf(nil), nil)
	-- a record with its previous
	local rec = Rec.record("node", 5, 1, 2, 4000, { d = 600, v = 300, d3 = 180, v3 = 120 }, Rec.prevOf(old))
	eq(rec, { 5, 1, 2, 4000, 1, 600, 300, 180, 120, 10, 60, 30 })
	eq(Rec.parts(rec).prev, { t = 10, d = 60, v = 30 })
	eq(Rec.entryOf({ 5, 1, 2, 10, 1, 60, 30, 60, 30, 3.4, 59.6, 7 }), { 5, 1, 2, 10, 1, 60, 30, 60, 30, 3, 60, 7 }, "rounded")
	-- a malformed or partial previous: dropped, the record kept
	for _, bad in ipairs({ { 1, 60 }, { 1, 60, 1.5 }, { -1, 60, 3 }, { 1, 0, 3 }, { 1, 5000, 3 }, { 0 / 0, 60, 3 }, { 1, 60, "x" } }) do
		eq(Rec.entryOf({ 5, 1, 2, 10, 1, 60, 30, 60, 30, bad[1], bad[2], bad[3] }), old, tostring(bad[1]) .. "/" .. tostring(bad[2]))
	end
	-- replacing: the new record's previous replaces the old one's (a 9-number record clears it)
	local list = Rec.apply(nil, { old })
	list = Rec.apply(list, { rec })
	eq(list[1], rec)
	local list2, st = Rec.apply(list, { rec })
	eq(st.changed, false, "the same record with the same previous: nothing to write")
	list2, st = Rec.apply(list2, { { 5, 1, 2, 5000, 1, 60, 30, 60, 30 } })
	eq({ st.replaced, list2[1][10], list2[1][12] }, { 1, nil, nil }, "no previous in the new one: none kept")
	-- the saved lines plus the previous
	local p = Rec.parts(rec)
	eq(Rec.prevLine(p.kind, p.prev, "1 h ago"), "Previous recording: 30 vehicles per minute (1 min, 1 h ago)")
	-- the event takes 12-number records
	local op, nodes = Auto.validate({ op = "traffic", nodes = { rec } })
	eq({ op, nodes[1] }, { "traffic", rec })
end)

test("records: malformed ones refused; one per junction and kind (by id or within 2 m); the oldest dropped beyond the cap", function()
	eq(Rec.entryOf({ 5, 1.04, 2, 10.4, 1, 60.4, 30, 60, 30 }), { 5, 1, 2, 10, 1, 60, 30, 60, 30 })
	for _, bad in ipairs({ { -1, 0, 0, 1, 1, 60, 1, 60, 1 }, { 5, 0, 0, 1, 3, 60, 1, 60, 1 }, { 5, 0, 0, 1, 1, 60, 1.5, 60, 1 },
		{ 5, 0, 0, 1, 1, 60, 1, 90, 1 }, { 5, 0, 0, 1, 1, 60, 1, 60, 2 }, { 5, 0 / 0, 0, 1, 1, 60, 1, 60, 1 }, "x",
		{ 5, 0, 0, 1, 1, 5000, 1, 60, 1 } }) do
		eq(Rec.entryOf(bad), nil, tostring(bad[2]) .. "/" .. tostring(bad[5]))
	end
	local list, st = Rec.apply(nil, { { 5, 10, 10, 100, 1, 60, 30, 60, 30 } })
	eq({ #list, st.added, st.changed }, { 1, 1, true })
	-- a roundabout whose ring key is the same id: its own record
	list, st = Rec.apply(list, { { 5, 40, 40, 100, 2, 60, 12, 60, 12 } })
	eq({ #list, st.added }, { 2, 1 })
	-- the junction re-created 1 m away under another id: replaced (re-keyed)
	list, st = Rec.apply(list, { { 9, 11, 10, 200, 1, 120, 40, 120, 40 } })
	eq({ #list, st.replaced, st.added }, { 2, 1, 0 })
	local idx = Rec.index(list)
	eq(Rec.match(idx, "node", 9)[7], 40)
	eq(Rec.match(idx, "node", 5), nil, "the old id is gone")
	eq(Rec.match(idx, "ring", 5)[7], 12)
	eq(Rec.match(idx, "node", nil, 10.5, 10)[1], 9, "by position")
	eq(Rec.match(idx, "ring", nil, 10.5, 10), nil, "never across kinds")
	_, st = Rec.apply(list, { { 9, 11, 10, 200, 1, 120, 40, 120, 40 } })
	eq(st.changed, false, "the same record: nothing to write")
	-- the cap
	local big = nil
	for i = 1, 1200 do
		big = Rec.apply(big, { Rec.record(i % 3 == 0 and "ring" or "node", 100000 + i, (i % 50) * 100.37, math.floor(i / 50) * 99.91,
			1234567 + i, { d = 1200, v = 9999, d3 = 205, v3 = 1700 }) })
	end
	eq(#big, Rec.MAX)
	eq(big[1][4], 1234567 + 201, "the oldest records dropped")
	-- the event: op traffic, src tool only, at most EVENT_MAX records, each validated
	local op, nodes, src = Auto.validate({ op = "traffic", nodes = { { 5, 10, 10, 100, 1, 60, 30, 60, 30 } } })
	eq({ op, src, #nodes }, { "traffic", "tool", 1 })
	eq(select(2, Auto.validate({ op = "traffic", src = "auto", nodes = { { 5, 10, 10, 100, 1, 60, 30, 60, 30 } } })), "src")
	eq(select(2, Auto.validate({ op = "traffic", nodes = { { 5, 10, 10, 100, 7, 60, 30, 60, 30 } } })), "node1")
	local many = {}
	for i = 1, Auto.EVENT_MAX + 1 do many[i] = { i, 0, 0, 1, 1, 60, 1, 60, 1 } end
	eq(select(2, Auto.validate({ op = "traffic", nodes = many })), "too_many")
end)

test("save safety: trec with the cap reached, each with its previous, stays under 120 kB serialized (verbose serialization, as test_auto.lua)", function()
	local list = nil
	for i = 1, 1100 do
		list = Rec.apply(list, { Rec.record("node", 1000000 + i, 12345.6 + 3 * i, -12345.6 - 3 * i, 123456789 + i,
			{ d = 1200, v = 99999, d3 = 205, v3 = 19999 }, { t = 123450000 + i, d = 1200, v = 99999 }) })
	end
	eq(#list[1], Rec.FIELDS, "each with its previous")
	local function ser(v)
		if type(v) == "table" then
			local parts = {}
			for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. ser(x) end
			return "{" .. table.concat(parts, ",") .. "}"
		end
		return tostring(v)
	end
	eq(#list, Rec.MAX)
	local size = #ser({ trec = list, tseq = 123456 })
	print("trec with the cap reached: " .. size .. " bytes")
	ok(size < 120000, "bounded: " .. size)
end)
