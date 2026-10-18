-- Staggered satellites (2026-10-14, NEXT_PHASE_BRIEF 51; ot_satpace): per-town readiness, map-wide spacing, a seeded
-- draw among the ready towns, the saved mark across a reload, pod growth cadence, and the driver's glue (SATPACE).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local P = ug_require(F.DIR .. "ot_satpace.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")
local rng = ug_require(F.DIR .. "ot_rng.lua")

local FULL = os.getenv("TEST_FULL") ~= nil

-- the 16 towns of run 2026-10-14_1927_sqot (seed a, europe, Quick 40 years): buildings at the start -> after 40 years
local TOWNS = {
	{ 60255, 118, 949 }, { 60256, 287, 1413 }, { 60257, 145, 1121 }, { 60258, 104, 985 }, { 60259, 73, 435 },
	{ 60260, 126, 729 }, { 60261, 92, 1015 }, { 60262, 189, 1040 }, { 60263, 165, 664 }, { 60264, 77, 959 },
	{ 60265, 91, 429 }, { 60266, 57, 550 }, { 60267, 129, 505 }, { 60268, 101, 616 }, { 60269, 132, 685 },
	{ 60270, 104, 1097 },
}
-- the Simulate's build rounds: year 1, then every 4 simulated years (the calendar does not move)
local ROUNDS = { 1, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40 }

--- A model of the dev Simulate over the 16 towns: growth lands at the rounds (the sim's Fast fill), each round checks
--- every town (most growth first) and a ready town of size >= 250 with offshoots left (1-3, seeded) asks P.decide;
--- a seeded share of the foundings fails at the site (refund). o = { salt, reloadAt (year: a fresh session state from
--- the saved param before that round), towns, rounds, failShare }. Returns the founding years, the state, decisions.
local function model(o)
	o = o or {}
	local towns = o.towns or TOWNS
	local salt = o.salt or 1
	local st = P.new(nil)
	local size, kOf, cap, seen = {}, {}, {}, {}
	for _, tw in ipairs(towns) do
		size[tw[1]] = tw[2]
		kOf[tw[1]] = 0
		cap[tw[1]] = 1 + math.floor(rng.unit(salt, tw[1], "cap") * 3)
	end
	local base = 0
	for _, tw in ipairs(towns) do base = base + 0.8 * tw[2] end
	local years, decisions, now = {}, {}, 0
	for _, Y in ipairs(o.rounds or ROUNDS) do
		if o.reloadAt and Y == o.reloadAt then
			st = P.new({ sp = P.param(st) })
			seen = {}
		end
		local order = {}
		for _, tw in ipairs(towns) do order[#order + 1] = tw end
		table.sort(order, function(a, b) return (a[3] - a[2]) > (b[3] - b[2]) end)
		for _, tw in ipairs(order) do
			local t = tw[1]
			now = now + 2e6
			size[t] = tw[2] + (tw[3] - tw[2]) * Y / 40
			seen[t] = true
			local sum, nSeen = 0, 0
			-- (the driver's map size: persons / 4, ~0.8 x the buildings in that run)
			for id, v in pairs(size) do if seen[id] then nSeen = nSeen + 1 end; sum = sum + 0.8 * v end
			P.observe(st, sum, Y)
			if size[t] >= 250 and kOf[t] < cap[t] then
				local out, why = P.decide(st, { t = t, kind = "seed", size = size[t], start = tw[2], k = kOf[t],
					seed = rng.hash(salt, t), now = now, sum = sum, base = base, year = 1900, nTowns = #towns,
					salt = salt, elapsed = Y, epoch = Y })
				decisions[#decisions + 1] = { y = Y, t = t, out = out, why = why }
				if out == "found" then
					if rng.unit(salt, t, Y, "fail") < (o.failShare or 0.15) then
						P.refund(st, t)
					else
						kOf[t] = kOf[t] + 1
						years[#years + 1] = Y
					end
				end
			end
		end
	end
	return years, st, decisions
end

local function per(years, Y) local n = 0; for _, y in ipairs(years) do if y == Y then n = n + 1 end end; return n end

-- (§64, 2026-10-15: SPACE_B 520 -> 850, the slots for at most ~4 offshoot towns per 16 towns instead of 6-10 street
-- satellites and towns: 6-10 -> 3-8 foundings in this uncapped model)
test("satpace model: a 40-year Simulate of 16 towns founds 3-8, one per round at most, spread over the decades", function()
	local SALTS = FULL and 60 or 12
	local totals = {}
	for salt = 1, SALTS do
		local years = model({ salt = salt })
		totals[#totals + 1] = #years
		ok(#years >= 3 and #years <= 8, "salt " .. salt .. ": " .. #years .. " foundings " .. table.concat(years, ","))
		for _, Y in ipairs(ROUNDS) do ok(per(years, Y) <= 1, "salt " .. salt .. ": one per round, year " .. Y) end
		ok(per(years, 1) == 0, "salt " .. salt .. ": nothing in the head start round")
		-- the decades: no decade holds more than half of them, and the last two decades get some
		local dec = {}
		for _, y in ipairs(years) do local d = math.min(3, math.floor((y - 1) / 10)); dec[d] = (dec[d] or 0) + 1 end
		for d = 0, 3 do ok((dec[d] or 0) <= math.ceil(#years / 2), "salt " .. salt .. ": decade " .. d) end
		ok((dec[2] or 0) + (dec[3] or 0) >= 2, "salt " .. salt .. ": later decades " .. table.concat(years, ","))
		if salt == 1 then print("salt 1 foundings at years " .. table.concat(years, ",")) end
	end
	-- seed a's map salt (the driver's: the smallest town id); the towns' own seeds differ in game
	local ya = model({ salt = rng.hash("satpace", 60255) })
	print("seed a (model): foundings at simulated years " .. table.concat(ya, ","))
	table.sort(totals)
	print("foundings: min " .. totals[1] .. " median " .. totals[math.ceil(#totals / 2)] .. " max " .. totals[#totals])
end)


test("satpace model: no founding before the map grew by the slot's need, the head start round never", function()
	for salt = 1, FULL and 40 or 8 do
		local years, _, decisions = model({ salt = salt })
		ok(years[1] >= 8, "salt " .. salt .. ": first at " .. tostring(years[1]))
		for _, d in ipairs(decisions) do
			if d.y == 1 then ok(d.out ~= "found", "salt " .. salt .. ": head start round") end
		end
	end
	-- the first slot counts from the towns' starting sizes: a map that hasn't grown gets none, however big its towns
	local st = P.new(nil)
	local out, why = P.decide(st, { t = 1, kind = "seed", size = 900, start = 300, k = 0, seed = 5, now = 0,
		sum = 4000, base = 4000, year = 1900, nTowns = 16, salt = 1 })
	eq(out, "wait"); eq(why, "spacing")
	eq(st.n, 0)
end)

test("satpace model: a reload in the middle keeps the gap (the saved mark), no burst after it", function()
	for salt = 1, FULL and 40 or 8 do
		local plain = model({ salt = salt })
		for _, at in ipairs({ 16, 20, 28 }) do
			local years = model({ salt = salt, reloadAt = at })
			ok(#years >= 3 and #years <= 8, "salt " .. salt .. " reload " .. at .. ": " .. #years)
			for _, Y in ipairs(ROUNDS) do ok(per(years, Y) <= 1, "salt " .. salt .. " reload " .. at .. ": year " .. Y) end
			-- after the reload no more foundings than without it
			local a, b = 0, 0
			for _, y in ipairs(years) do if y >= at then a = a + 1 end end
			for _, y in ipairs(plain) do if y >= at then b = b + 1 end end
			ok(a <= b + 1, "salt " .. salt .. " reload " .. at .. ": " .. a .. " after vs " .. b)
		end
	end
	-- the saved record round-trips through ot_saved (normalize keeps it; old saves have none)
	local _, st = model({ salt = 3 })
	local raw = SV.normalize({ v = SV.VERSION, known = {} })
	eq(raw.sp, nil, "a save from before: no pacing record")
	eq(P.new(raw).n, 0)
	local s2, changed = SV.applyPace(raw, P.param(st))
	ok(changed)
	local s3, changed2 = SV.applyPace(s2, P.param(st))
	ok(not changed2, "idempotent")
	local back = P.new(SV.normalize(s3))
	eq(back.n, st.n); near(back.mark, st.mark, 1)
	eq(#back.hist, #st.hist)
	-- a later event keeps it (other events normalize the state)
	local s4 = SV.applyBridge(s3, { town = 1 })
	eq(s4.sp.n, st.n)
end)

test("satpace model: deterministic per seed, another seed staggers differently", function()
	local a1 = table.concat(model({ salt = 7 }), ",")
	local a2 = table.concat(model({ salt = 7 }), ",")
	eq(a1, a2)
	local differ = 0
	for salt = 1, 10 do if table.concat(model({ salt = salt }), ",") ~= a1 then differ = differ + 1 end end
	ok(differ >= 6, "other salts " .. differ)
end)

test("satpace: a Simulate build round with several ready towns founds one; the draw is not always the biggest", function()
	local wins = {}
	for salt = 1, FULL and 200 or 40 do
		local st = P.new({ sp = { m = 1000, n = 2, y = 190000 } })
		local res = {}
		-- round 6: the five are ready, the slot still closed (they wait: candidates of the next draw)
		for i = 1, 5 do
			local out = P.decide(st, { t = 100 + i, kind = "seed", size = 300 + 100 * i, start = 100, k = 0, seed = 10 + i,
				now = i * 1e5, sum = 1100, year = 1900, nTowns = 16, salt = salt, epoch = 6 })
			eq(out, "wait")
		end
		-- round 7: five ready towns, sizes 400..800; the slot open (the map grew 900)
		for i = 1, 5 do
			local o = { t = 100 + i, kind = "seed", size = 300 + 100 * i, start = 100, k = 0, seed = 10 + i, now = i * 1e6,
				sum = 1900 + i, year = 1900, nTowns = 16, salt = salt, epoch = 7 }
			res[i] = P.decide(st, o)
		end
		-- a second pass in the same round: still one
		for i = 1, 5 do
			local o = { t = 100 + i, kind = "seed", size = 300 + 100 * i, start = 100, k = 0, seed = 10 + i, now = 10e6 + i * 1e6,
				sum = 2500, year = 1900, nTowns = 16, salt = salt, epoch = 7 }
			local out = P.decide(st, o)
			if out == "found" then res[#res + 1] = out end
		end
		local found = 0
		for i, out in ipairs(res) do
			if out == "found" then found = found + 1; wins[100 + i] = (wins[100 + i] or 0) + 1 end
		end
		ok(found <= 1, "salt " .. salt .. ": " .. found .. " in one round")
		-- the next round: the mark settled at the founding round's last sum (2500), so 2500 + a little is no slot
		if found == 1 then
			local out, why = P.decide(st, { t = 999, kind = "seed", size = 900, start = 100, k = 0, seed = 3, now = 30e6,
				sum = 2550, year = 1900, nTowns = 16, salt = salt, epoch = 8 })
			eq(out, "wait", "salt " .. salt); eq(why, "spacing")
			near(st.mark, 2500, 1e-6)
		end
	end
	local winners = 0
	for _ in pairs(wins) do winners = winners + 1 end
	ok(winners >= 3, "variety: " .. winners .. " different winners")
	ok((wins[105] or 0) < (FULL and 200 or 40) * 0.8, "the biggest doesn't always win")
end)

test("satpace: a failed founding gives the slot back, the town sits it out", function()
	local st = P.new({ sp = { m = 1000, n = 0 } })
	local o = { t = 5, kind = "seed", size = 600, start = 100, k = 0, seed = 1, now = 0, sum = 3000, year = 1900,
		nTowns = 16, salt = 1 }
	eq(P.decide(st, o), "found")
	eq(st.n, 1); eq(st.mark, 3000)
	ok(not P.refund(st, 6), "another town: nothing")
	ok(P.refund(st, 5))
	eq(st.n, 0); eq(st.mark, 1000); eq(#st.hist, 0)
	local out, why = P.decide(st, o)
	eq(out, "wait"); eq(why, "satOut")
	o.t, o.seed = 6, 2
	eq(P.decide(st, o), "found", "the next ready town takes the slot")
end)

test("satpace: readiness milestones are seeded per town, later ones further out", function()
	local first = {}
	for seed = 1, 200 do
		local _, _, t0 = P.readiness({ size = 0, start = 150, k = 0, seed = seed })
		local _, _, t1 = P.readiness({ size = 0, start = 150, k = 1, seed = seed })
		local _, _, t2 = P.readiness({ size = 0, start = 150, k = 2, seed = seed })
		ok(t1 > t0 and t2 > t1, "later milestones further out")
		ok(t0 >= P.READY_MIN[1] - 1e-9 and t0 <= math.max(150 * P.READY[2], P.READY_MIN[2]) + 1e-9, "range " .. t0)
		first[#first + 1] = t0
	end
	table.sort(first)
	ok(first[#first] - first[1] > 120, "a wide jitter: " .. first[1] .. ".." .. first[#first])
	-- relative to the start: a big starting town needs more
	local _, _, small = P.readiness({ size = 0, start = 100, k = 0, seed = 9 })
	local _, _, big = P.readiness({ size = 0, start = 600, k = 0, seed = 9 })
	ok(big >= 600 * P.READY[1] and big > small)
end)

test("satpace: zero growth, NaN and missing inputs, the capped scan", function()
	local nan = 0 / 0
	local st = P.new({ sp = { m = nan, n = nan, y = 1 / 0, h = { nan, 3, "x" } } })
	eq(st.mark, nil); eq(st.n, 0); eq(st.markYear, nil); eq(#st.hist, 1)
	-- zero growth: the mark is the sum
	local st2 = P.new({ sp = { m = 2000, n = 1 } })
	local out, why = P.decide(st2, { t = 1, kind = "seed", size = 900, start = 100, k = 0, seed = 1, now = 0, sum = 2000,
		nTowns = 16, salt = 1 })
	eq(out, "wait"); eq(why, "spacing")
	-- NaN everywhere: no error, no founding
	out = P.decide(st2, { t = 2, kind = "seed", size = nan, start = nan, k = nan, seed = nan, now = nan, sum = nan,
		year = nan, nTowns = nan, salt = nan })
	ok(out == "wait", tostring(out))
	-- a falling map (towns lost): negative growth is no progress
	local open, growth = P.slot(st2, { sum = 1500, need = 500 })
	ok(not open); eq(growth, -500)
	-- need: finite and positive whatever comes in
	for _, n in ipairs({ 0, -5, nan, 1 / 0, 1, 16, 400 }) do
		local v = P.need(n, 3, 1)
		ok(v == v and v > 0 and v < 1e7, "need " .. tostring(n) .. " = " .. tostring(v))
	end
	ok(P.need(64, 0, 1) > P.need(16, 0, 1), "a bigger map: a longer slot (but less per town)")
	-- growDue: NaN-safe, cadence
	local due = P.growDue({ seed = nan, n = nan, size = nan, podMark = nan, sum = nan, growMark = nan, need = nan })
	ok(due == true or due == false)
	-- the candidate scan is capped
	local st3 = P.new({ sp = { m = 0, n = 0 } })
	for i = 1, P.MAX_CANDS + 50 do st3.cands[i] = { us = 0, w = 1 } end
	out = P.decide(st3, { t = 1, kind = "seed", size = 900, start = 100, k = 0, seed = 1, now = 0, sum = 1e6, nTowns = 16,
		salt = 1 })
	ok(out == "found" or out == "deferred")
	-- the summary helpers
	eq(P.decades({}), "-"); eq(P.decades({ 3, 12, 15, 38 }), "0-9:1,10-19:2,20-29:0,30-39:1")
	eq(P.minGap({ 4 }), nil); eq(P.minGap({ 4, 12, 16 }), 4)
end)

test("satpace: satellite pods grow on their own cadence, not all in the same round", function()
	local pods = {}
	for i = 1, 12 do pods[i] = { seed = rng.hash("pod", i), n = 0, mark = 300, size = 300 } end
	local growMark, sum = 0, 0
	local maxRound, total = 0, 0
	for round = 1, 10 do
		local grown = 0
		for _, pd in ipairs(pods) do
			pd.size = pd.size + 40
			sum = sum + 40
			for _ = 1, 2 do   -- two demand builds per round
				pd.n = pd.n + 1
				local due = P.growDue({ seed = pd.seed, n = pd.n, size = pd.size, podMark = pd.mark, sum = sum,
					growMark = growMark, need = 520 })
				if due then pd.mark, growMark, grown = pd.size, sum, grown + 1 end
			end
		end
		total = total + grown
		if grown > maxRound then maxRound = grown end
	end
	ok(maxRound <= 8, "at most 8 of 12 pods in one round: " .. maxRound)
	ok(total >= 12, "they do grow: " .. total)
end)

test("satpace driver glue: SATPACE lines, the saved record, a refund, one founding per round", function()
	local logs, events = {}, {}
	local caps = {}
	local towns = { 11, 12, 13, 14 }
	for _, t in ipairs(towns) do caps[t] = 1200 end
	local E = { t = 0 }
	function E.nowUs() return E.t end
	function E.log(l) logs[#logs + 1] = l end
	function E.sendEvent(_, name, p) events[#events + 1] = { name = name, p = p } end
	function E.towns() return towns end
	function E.name(t) return "T" .. t end
	function E.townCaps(t) return { actual = caps[t], target = caps[t] } end
	function E.yearF() return 1900.5 end
	local d = D.new(E)
	local saved = { v = SV.VERSION, known = {}, frames = {
		["11"] = { a = 0, x = 0, y = 0, ic = 1200, b0 = 300 }, ["12"] = { a = 0, x = 0, y = 0, ic = 1200, b0 = 300 } } }
	local H = ug_require(F.DIR .. "ot_hooks.lua")
	H.simRound, H.simYears = 3, 12
	local function job(t, n)
		return { town = t, pts = setmetatable({}, { __len = function() return n end }), caps = { actual = n * 3 },
			style = { seed = t * 7 } }
	end
	-- the map hasn't grown since the start (base = the frames' ic / 4 + first sights): wait
	eq(d:paceGate(job(11, 900), "seed", 0, saved), "wait")
	-- the map grows (persons x 3): the slot opens; one founding in round 3 at most
	for _, t in ipairs(towns) do caps[t] = 6000 end
	E.t = 10e6
	local outs = {}
	for i, t in ipairs(towns) do outs[i] = d:paceGate(job(t, 900), "seed", E.t + i, saved) end
	local found = 0
	for _, o in ipairs(outs) do if o == "found" then found = found + 1 end end
	eq(found, 1, table.concat(outs, ","))
	local pe = nil
	for _, e in ipairs(events) do if e.name == SV.EV_PACE then pe = e end end
	ok(pe ~= nil and pe.p.n == 1, "EV_PACE sent")
	local line = nil
	for _, l in ipairs(logs) do if l:find("SATPACE", 1, true) and l:find("outcome=found", 1, true) then line = l end end
	ok(line ~= nil and line:find("simYear=12", 1, true) ~= nil, tostring(line))
	-- the founding failed: refund (the slot back, the town out of this slot)
	local winner = nil
	for i, o in ipairs(outs) do if o == "found" then winner = towns[i] end end
	d:paceRefund(winner, "seed:noSite")
	eq(d:root().satPace.n, 0)
	ok(logs[#logs]:find("outcome=refund", 1, true) ~= nil)
	eq(events[#events].p.n, 0)
	H.simRound, H.simYears = nil, nil
end)
