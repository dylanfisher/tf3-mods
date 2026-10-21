-- Better Auto Vehicle Renamer: bavr_register.lua (numbers, records, prune, gone matching, welcome answers, the Apply
-- pass order, state validation) and bavr_classify.lua (type letters). PLAN.md "Per-save state", "Types and letters".

local Reg = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_register.lua"
local Classify = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_classify.lua"
local Settings = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_settings.lua"
-- The render tests were written for the first layout (Model + number, automatic separators, no year): pin
-- those three settings unless a test sets them; the defaults test reads Settings.parse directly.
local function P(t, ...)
	local m = { ["bavr.format"] = 1, ["bavr.partSep"] = 1, ["bavr.year"] = 1 }
	for k, v in pairs(t or {}) do m[k] = v end
	return Settings.parse(m, ...)
end


local function copy(t)
	if type(t) ~= "table" then return t end
	local r = {}
	for k, v in pairs(t) do r[k] = copy(v) end
	return r
end

local cfg = P({})

---------------------------------------------------------------------------
-- Classify

test("classify: carrier enum to letters, bus vs truck by passengers, helicopter by metadata or path", function()
	eq(Classify.letter(0, true, false), "B")
	eq(Classify.letter(0, false, false), "T")
	eq(Classify.letter(1, false, false), "L")
	eq(Classify.letter(2, true, false), "R")
	eq(Classify.letter(3, true, false), "A")
	eq(Classify.letter(3, true, true), "H")
	eq(Classify.letter(4, true, false), "S")
	eq(Classify.letter(5, true, false), nil, "OTHER / unknown")
	eq(Classify.letter(nil), nil)
	eq(Classify.isHeliModel({ airVehicle = { isHelicopter = true } }, nil), true)
	eq(Classify.isHeliModel({ airVehicle = { isHelicopter = false } }, "vehicle/helicopter/x.mdl"), false,
		"the metadata wins over the path")
	eq(Classify.isHeliModel({}, "vehicle/helicopter/aw101.mdl"), true, "path fallback")
	eq(Classify.isHeliModel(nil, "vehicle/plane/dc3.mdl"), false)
end)

test("classify: passengers from the .mdl compartments layout", function()
	local function md(classes, cap)
		return { transportVehicle = { compartments = { { loadConfigs = { { cargoEntry = { capacity = cap,
			cargoTypeSet = { cargoClassesIncluded = classes } } } } } } } }
	end
	eq(Classify.hasPassengers(md({ "PASSENGERS" }, 60)), true)
	eq(Classify.hasPassengers(md({ "PASSENGERS" }, 0)), false, "no capacity")
	eq(Classify.hasPassengers(md({ "BULK" }, 20)), false)
	eq(Classify.hasPassengers({ transportVehicle = { compartments = { { loadConfigs = { { cargoEntry = {
		capacity = 4, cargoTypeSet = { cargoTypesIncluded = { "PASSENGERS" } } } } } } } } }), true, "by cargo type")
	eq(Classify.hasPassengers(nil), false)
	eq(Classify.hasPassengers({ transportVehicle = {} }), false)
end)

test("classify: lead part is the first powered one, else 1; the loop is capped", function()
	eq(Classify.lead(3, function(i) return i == 2 end), 2)
	eq(Classify.lead(3, function() return false end), 1)
	eq(Classify.lead(0, function() return true end), 1)
	local calls = 0
	eq(Classify.lead(1e9, function() calls = calls + 1; return false end), 1)
	eq(calls, Classify.MAX_PARTS, "capped")
end)

---------------------------------------------------------------------------
-- Numbers

test("numbers: per type, global and per model, only up; start raises a counter, never lowers it", function()
	local st = Reg.new()
	local a = Reg.create(st, cfg, 10, "B", "citaro", 1, 900)
	local b = Reg.create(st, cfg, 11, "B", "urbino", 2, 900)
	local c = Reg.create(st, cfg, 12, "T", "scania", 3, 0)
	eq({ a.t, a.a, a.m, b.t, b.a, b.m, c.t, c.a, c.m }, { 1, 1, 1, 2, 2, 1, 1, 3, 1 })
	eq(Reg.shown(b, cfg), 2)
	eq(Reg.shown(b, P({ ["bavr.counter"] = 2 })), 2)
	eq(Reg.shown(c, P({ ["bavr.counter"] = 2 })), 3)
	eq(Reg.shown(b, P({ ["bavr.counter"] = 3 })), 1)
	local c1000 = P({ ["bavr.start"] = 3 })
	local d = Reg.create(st, c1000, 13, "B", "citaro", 4, 900)
	eq({ d.t, d.a, d.m }, { 1000, 1000, 1000 })
	local e = Reg.create(st, cfg, 14, "B", "citaro", 5, 900)
	eq(e.t, 1001, "start 1 again: the counter stays where it is")
	-- a model change takes the next per-model number, keeps the others
	ok(Reg.setModel(st, a, "urbino", cfg))
	eq({ a.t, a.a, a.m, a.mk }, { 1, 1, 2, "urbino" })
	eq(Reg.setModel(st, a, "urbino", cfg), false)
end)

test("prune: gone ids are dropped and their numbers retired; newer-than-list records stay; gone list capped", function()
	local st = Reg.new()
	for i = 1, 5 do Reg.create(st, cfg, 100 + i, "B", "citaro", 1000 + i, 900) end
	local present = { [101] = true, [103] = true, [105] = true }
	local rec6 = Reg.create(st, cfg, 106, "B", "citaro", 9000, 900) -- bought after the list
	eq(Reg.prune(st, present, 5000, 5000), 2)
	eq(Reg.get(st, 102), nil)
	ok(Reg.get(st, 106) == rec6, "newer than the list: kept")
	eq(#st.gone, 2)
	local n = Reg.create(st, cfg, 107, "B", "citaro", 9001, 900)
	eq(n.t, 7, "numbers 2 and 4 stay retired")
	-- gone matching: same line and letter, oldest first, expires
	local g = Reg.takeGone(st, 900, "B", 5001)
	eq(g[3], 2)
	eq(Reg.takeGone(st, 900, "T", 5001), nil, "other type")
	eq(Reg.takeGone(st, 901, "B", 5001), nil, "other line")
	eq(Reg.takeGone(st, 900, "B", 5000 + Reg.GONE_MS + 1), nil, "expired")
	eq(Reg.takeGone(st, 0, "B", 5001), nil, "no line: never matched")
	-- cap
	local st2 = Reg.new()
	for i = 1, Reg.MAX_GONE + 10 do Reg.create(st2, cfg, i, "B", nil, 1, 900) end
	Reg.prune(st2, {}, 10, 10)
	eq(#st2.gone, Reg.MAX_GONE)
end)

test("prune: the record walk is capped", function()
	local st = Reg.new()
	for i = 1, 30 do Reg.create(st, cfg, i, "B", nil, 1, 0) end
	local old = Reg.MAX_RECORDS
	Reg.MAX_RECORDS = 10
	local n = Reg.prune(st, {}, 10, 10)
	Reg.MAX_RECORDS = old
	ok(n <= 10, "pruned " .. n)
	eq(Reg.size(st), 30 - n)
end)

---------------------------------------------------------------------------
-- Welcome, pass

test("welcome: first only with vehicles, renumber after Not now with the setting, never while standing down", function()
	local st = Reg.new()
	local yes = P({ ["bavr.renumberNext"] = 2 })
	eq(Reg.welcomeDue(st, cfg, 0), nil)
	eq(Reg.welcomeDue(st, cfg, 3), "first")
	Reg.answer(st, "later", 500)
	eq({ st.welcome, st.cutoff, st.pass }, { "later", 500, nil })
	eq(Reg.welcomeDue(st, cfg, 3), nil)
	eq(Reg.welcomeDue(st, yes, 3), "renumber")
	Reg.answer(st, "apply", 900)
	eq({ st.welcome, st.cutoff, st.pass.cutoff }, { "apply", nil, 900 })
	eq(Reg.welcomeDue(st, yes, 3), nil, "the pass is due")
	st.standDown = "destination_displays"
	eq(Reg.welcomeDue(Reg.new(), cfg, 3), "first")
	local sd = Reg.new()
	sd.standDown = "x"
	eq(Reg.welcomeDue(sd, cfg, 3), nil)
end)

test("pass: oldest first by purchase time then id, duplicates and existing records skipped, capped", function()
	local st = Reg.new()
	Reg.create(st, cfg, 50, "B", "citaro", 1, 900) -- already numbered
	local q = {}
	local function add(id, pt, k) for _, v in ipairs({ id, pt, k, "citaro", 900 }) do q[#q + 1] = v end end
	add(30, 300, "B"); add(10, 100, "B"); add(20, 100, "B"); add(10, 100, "B"); add(50, 1, "B"); add(40, 50, "T")
	st.pass = { at = 1, cutoff = 1000 }
	eq(Reg.assignPass(st, cfg, q, #q / Reg.PASS_FIELDS), 4)
	eq({ Reg.get(st, 10).t, Reg.get(st, 20).t, Reg.get(st, 30).t, Reg.get(st, 40).t }, { 2, 3, 4, 1 })
	eq({ st.pass, st.cutoff }, { nil, nil })
	local old = Reg.MAX_PASS
	Reg.MAX_PASS = 2
	local st2 = Reg.new()
	eq(Reg.assignPass(st2, cfg, q, #q / Reg.PASS_FIELDS), 2, "capped")
	Reg.MAX_PASS = old
end)

---------------------------------------------------------------------------
-- State

test("state: round trip through a copy, repair of garbage, unknown versions start fresh", function()
	local st = Reg.new()
	Reg.create(st, cfg, 212817, "B", "vehicle/bus/citaro.mdl", 168703000, 900).last = "Citaro B-0001"
	Reg.answer(st, "apply", 5)
	local back, how = Reg.validate(copy(st))
	eq(how, "ok")
	eq(back, st)
	eq(Reg.get(back, 212817).last, "Citaro B-0001")
	local new, how2 = Reg.validate(nil)
	eq(how2, "new")
	eq(new, Reg.new())
	eq(select(2, Reg.validate({ ver = 99, v = { ["1"] = { k = "B", t = 1 } } })), "new")
	local raw = copy(st)
	raw.v["7"] = { k = "X", t = 1 }
	raw.v["8"] = "junk"
	raw.v["9"] = { k = "B" }
	raw.v["10"] = { k = "B", t = 3.0, user = true }
	raw.nt.Q = 3
	raw.welcome = "maybe"
	raw.gone = 5
	local fixed, how3 = Reg.validate(raw)
	eq(how3, "repaired")
	eq({ fixed.v["7"], fixed.v["8"], fixed.v["9"] }, { nil, nil, nil })
	eq(fixed.v["10"], { k = "B", t = 3 }, "a non-1 user flag is dropped")
	eq({ fixed.nt.Q, fixed.welcome, fixed.gone }, { nil, nil, {} })
	eq(Reg.get(fixed, 212817).t, 1)
end)

test("state: only plain numbers, strings and string-keyed tables are stored", function()
	local st = Reg.new()
	for i = 1, 20 do
		local r = Reg.create(st, cfg, 5000 + i, i % 2 == 0 and "B" or "L", "m" .. i, i, 900)
		r.last, r.orig, r.ts, r.user = "n" .. i, "Road Vehicle " .. i, 77, i % 3 == 0 and 1 or nil
	end
	st.gone[1] = { 900, "B", 1, 2, 0, "", 5 }
	Reg.answer(st, "later", 9)
	local function walk(t, path)
		for k, v in pairs(t) do
			local tk = type(k)
			local isArray = tk == "number" and k >= 1 and k == math.floor(k) and k <= #t
			ok(tk == "string" or isArray, "key " .. path .. "." .. tostring(k))
			local tv = type(v)
			ok(tv == "string" or tv == "number" or tv == "table", "value " .. path .. "." .. tostring(k) .. " " .. tv)
			if tv == "table" then walk(v, path .. "." .. tostring(k)) end
		end
	end
	walk(st, "st")
end)

test("key: ids become strings, memo is capped", function()
	eq(Reg.key(212817), "212817")
	eq(Reg.key(212817.0), "212817")
	local old = Reg.MAX_RECORDS
	Reg.MAX_RECORDS = 2
	for i = 1, 20 do eq(Reg.key(i), tostring(i)) end
	Reg.MAX_RECORDS = old
end)

---------------------------------------------------------------------------
-- Counting "Per line" (Reg.linePositions; PLAN.md "Per line counting")

local function lineState(specs)
	-- specs: { id, li, lj, pt } per record (lj set by hand; the join sequence then goes on from 1000)
	local st = Reg.new()
	for _, sp in ipairs(specs) do
		local rec = Reg.create(st, cfg, sp[1], "B", nil, sp[4] or sp[3], sp[2])
		rec.lj = sp[3]
	end
	st.nj = 1000
	return st
end

test("line positions: join order (then purchase time, then id); a leaver closes the gap; a joiner comes last", function()
	local st = lineState({ { 10, 900, 500, 500 }, { 11, 900, 100, 100 }, { 12, 900, 300, 50 }, { 13, 901, 50, 50 },
		{ 14, 900, 300, 40 }, { 15, 0, 1, 1 } })
	local out = {}
	local n = Reg.linePositions(st, nil, out)
	eq(n, 5, "every record on a line got a position")
	eq({ Reg.get(st, 11).lp, Reg.get(st, 14).lp, Reg.get(st, 12).lp, Reg.get(st, 10).lp }, { 1, 2, 3, 4 },
		"lj, then purchase time (14 before 12 at the same join time)")
	eq(Reg.get(st, 13).lp, 1, "lines count on their own")
	eq(Reg.get(st, 15).lp, nil, "no line: no position")
	eq(Reg.linePositions(st, nil, {}), 0, "stable: nothing moves on a second run")
	-- 14 is sold: only the ones after it move up
	st.v[Reg.key(14)] = nil
	out = {}
	n = Reg.linePositions(st, { [900] = true }, out)
	eq(n, 2)
	table.sort(out)
	eq(out, { 10, 12 })
	eq({ Reg.get(st, 11).lp, Reg.get(st, 12).lp, Reg.get(st, 10).lp }, { 1, 2, 3 })
	-- a joiner (latest join time) moves nobody
	local j = Reg.create(st, cfg, 16, "B", nil, 900, 900)
	eq({ j.lj, st.nj }, { 1000, 1001 }, "the next join number: unique, never a tie")
	out = {}
	eq(Reg.linePositions(st, { [900] = true }, out), 1)
	eq(out, { 16 })
	eq(j.lp, 4)
	-- only the lines asked for
	Reg.get(st, 13).lp = 7
	eq(Reg.linePositions(st, { [900] = true }, {}), 0, "line 901 not asked for")
	eq(Reg.get(st, 13).lp, 7)
end)

test("line positions: the same result whatever the record order (pairs) and the Lua state", function()
	local specs = {}
	for i = 1, 60 do specs[i] = { 100 + (i * 37) % 60, 900 + i % 3, 1000 + (i * 13) % 7, 500 + i } end
	local a = lineState(specs)
	local rev = {}
	for i = #specs, 1, -1 do rev[#rev + 1] = specs[i] end
	local b = lineState(rev)
	Reg.linePositions(a, nil, {})
	Reg.linePositions(b, nil, {})
	for k, rec in pairs(a.v) do eq(rec.lp, b.v[k].lp, "record " .. k) end
end)

test("line positions: the record walk is capped at MAX_RECORDS", function()
	local st = lineState({ { 1, 900, 1 }, { 2, 900, 2 }, { 3, 900, 3 }, { 4, 900, 4 } })
	local old = Reg.MAX_RECORDS
	Reg.MAX_RECORDS = 2
	local n = Reg.linePositions(st, nil, {})
	Reg.MAX_RECORDS = old
	eq(n, 2, "stops after MAX_RECORDS records")
end)

test("shown: per line shows the position for a vehicle on a line, else the per-type number; validate keeps lp / lj", function()
	local c = P({ ["bavr.counter"] = 4 })
	eq(c.counter, "line")
	local rec = { k = "B", t = 205, a = 9, li = 900, lp = 3, lj = 5 }
	eq({ Reg.shown(rec, c) }, { 3, true })
	eq({ Reg.shown({ k = "B", t = 205, li = 0 }, c) }, { 205, false }, "no line: the per-type number")
	eq({ Reg.shown({ k = "B", t = 205, li = 900 }, c) }, { 205, false }, "no position yet")
	eq({ Reg.shown(rec, cfg) }, { 205, false }, "per type: the permanent number")
	local st = Reg.new()
	st.v["7"] = { k = "B", t = 1, li = 900, lp = 2, lj = 44 }
	local v = Reg.validate(copy(st))
	eq({ v.v["7"].lp, v.v["7"].lj }, { 2, 44 })
	st.v["7"].lp = -1
	eq(Reg.validate(copy(st)).v["7"].lp, nil, "a bad position is dropped")
end)

test("prune: the lines of pruned records go into the lines set; gone entries keep the join time", function()
	local st = lineState({ { 1, 900, 10 }, { 2, 901, 20 }, { 3, 0, 30 } })
	local lines = {}
	eq(Reg.prune(st, {}, 1000, 1000, lines), 3)
	eq(lines, { [900] = true, [901] = true })
	eq(st.gone[1][8], 10, "join time kept for Replace matching")
end)

test("words: the old marker word O is optional and part of the key", function()
	local w = { B = "Bus", T = "Lkw", R = "Tram", L = "Zug", S = "Schiff", A = "Flugzeug", H = "Hubschrauber" }
	local c = Reg.cleanWords(w)
	eq(c.O, nil)
	w.O = "(alt)"
	eq(Reg.cleanWords(w).O, "(alt)")
	ok(Reg.wordsKey(Reg.cleanWords(w)) ~= Reg.wordsKey(c), "the key moves with O")
	w.O = string.rep("x", Reg.MAX_WORD_BYTES + 1)
	eq(Reg.cleanWords(w).O, nil, "too long: dropped, the letters stay")
end)
