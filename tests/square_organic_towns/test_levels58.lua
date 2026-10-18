-- LEVELS by maturity (2026-10-15; NEXT_PHASE_BRIEF 58): run 2026-10-14_2347_sqot-dev load 3 (seed a, europe, start 1950,
-- calendar not moved, Quick 40 years). The weights that held its grown towns at level 1 were the engine's own write
-- after the mod's FILL restores ("fill", never sent by LEVELS); LEVELS now replaces them by the town's phase (young /
-- blend / mature / densify), up to the era's top level, and never touches a player's.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local UP = ug_require(F.DIR .. "ot_upward.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local A = ug_require(F.DIR .. "ot_assess.lua")
local CH = ug_require(F.DIR .. "ot_character.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")

-- persons per building of a town's level-l buildings, fitted to the run's 16 ALLTOWN rows (1 / pb = sum a_l / S_l over
-- the actual capacity shares a; level 4 none in that run, a guess)
local S = { 2.73, 4.22, 24.2, 40 }

local function rows3(r) return { { r[1], r[2], r[3], r[4] }, { r[1], r[2], r[3], r[4] }, { r[1], r[2], r[3], r[4] } } end

--- The capacity shares the game builds: its unweighted target u x the custom row c (nil: none), normalised; a level
--- above the era's top is built at the top (the run: u 34/27/22/17 -> a 38/24/38/0 without weights).
local function shares(u, c, top)
	local w, sum = {}, 0
	for l = 1, 4 do
		w[l] = u[l] * (c and c[l] or 1)
	end
	for l = top + 1, 4 do w[top], w[l] = w[top] + w[l], 0 end
	for l = 1, 4 do sum = sum + w[l] end
	for l = 1, 4 do w[l] = sum > 0 and w[l] / sum or 0 end
	return w
end

local function pbOf(a)
	local x = 0
	for l = 1, 4 do x = x + a[l] / S[l] end
	return x > 0 and 1 / x or 0
end

-- the run at year 40 (ALLTOWN): name, buildings, persons (capacity), u (unweighted %), custom row (residential; nil none),
-- actual shares %, strong character / secluded (excluded from densify)
local TOWNS = {
	{ "Mytham", 1388, 4709, { 34, 27, 22, 17 }, { 0.453303, 0.255125, 0.100228, 0 }, { 62, 27, 10, 0 } },
	{ "Dart Head", 1241, 3661, { 34, 27, 22, 17 }, { 0.30965, 0.0572641, 0, 0 }, { 86, 14, 0, 0 } },
	{ "Lower Aberarun", 1058, 3231, { 34, 27, 22, 17 }, { 0.0775304, 0.0161943, 0.0107287, 0 }, { 77, 13, 9, 0 } },
	{ "Abercoed", 859, 2391, { 34, 27, 22, 17 }, { 0.0690605, 0.017357, 0, 0 }, { 80, 20, 0, 0 } },
	{ "Oakhaven", 761, 2807, { 34, 27, 22, 17 }, { 0.0531101, 0.0319281, 0.0212854, 0 }, { 55, 26, 19, 0 } },
	{ "Edton", 699, 1921, { 37, 30, 24, 10 }, { 0.419192, 0, 0, 0 }, { 100, 0, 0, 0 } },
	{ "Padfield", 682, 2303, { 35, 28, 22, 16 }, { 0.567901, 0.255144, 0, 0 }, { 73, 27, 0, 0 } },
	{ "Trefach", 679, 1894, { 37, 29, 24, 10 }, { 0.299822, 0.00533808, 0, 0 }, { 99, 1, 0, 0 } },
	{ "Wemmead", 483, 2165, { 36, 29, 23, 13 }, { 0.111839, 0.0667759, 0.0729209, 0 }, { 48, 24, 28, 0 } },
	-- (the towns without weights: c:-)
	{ "Milton-under-Edge", 878, 4128, { 34, 27, 22, 17 }, nil, { 38, 24, 38, 0 } },
	{ "Hornness", 721, 3254, { 34, 27, 22, 17 }, nil, { 39, 24, 38, 0 } },
	{ "Winmere", 530, 2134, { 36, 29, 23, 13 }, nil, { 42, 25, 33, 0 } },
	{ "Shaw", 300, 1501, { 39, 31, 30, 0 }, nil, { 43, 28, 29, 0 } },
	{ "Kelington", 295, 1278, { 40, 32, 27, 0 }, nil, { 47, 28, 25, 0 } },
}

local function decide(o)
	local x = { on = true, nowUs = 1e12, town = 1, ours = 0 }
	for k, v in pairs(o) do x[k] = v end
	return UP.levelDecide(x)
end

test("the run's weights are the engine's fill write: owner fill, not the player's; editor rows stay the player's", function()
	for _, t in ipairs(TOWNS) do
		if t[5] then
			local rows = rows3(t[5])
			eq(UP.levelOwner(UP.levelSig(rows), "-", 0, rows, nil), "fill", t[1])
		end
	end
	-- the town editor: "Enable" writes the weighted target normalised to its largest (1); a slider writes value / 100
	local def = { { 0.61, 0.83, 1, 0.42 }, { 1, 0.7, 0.3, 0.1 }, { 1, 0.5, 0.2, 0 } }
	eq(UP.levelOwner(UP.levelSig(def), "-", 0, def, nil), "player")
	local slid = { { 0.6123, 0.37, 0.4561, 0.3456 }, { 0.71, 0.66, 0.43, 0.2 }, { 0.92, 0.51, 0.22, 0.11 } }
	slid[2] = { 0.7123, 0.6612, 0.4318, 0.2021 }
	slid[3] = { 0.9123, 0.5112, 0.2218, 0.1121 }
	eq(UP.levelOwner(UP.levelSig(slid), "-", 0, slid, nil), "player", "one slider step (0.37): the player's")
	ok(UP.editorLike(def) and UP.editorLike(slid))
	-- ours: by the sig sent (the era makes one tilt's rows differ), or the old formula's strength
	local w = UP.levelWeights(-0.5, 3)
	eq(UP.levelOwner(UP.levelSig(w), "-", 0, w, UP.levelSig(w)), "ours")
	eq(UP.levelOwner(UP.levelSig(UP.levelWeights(0.5)), "-", 0.5, UP.levelWeights(0.5), nil), "ours")
	-- unknown rows (an old caller): the old rule
	eq(UP.levelOwner(UP.levelSig(rows3(TOWNS[1][5])), "-", 0), "player")
end)

test("replay of the 2347 run: target weights no longer all level 1, pb rises toward 4-5 for grown towns", function()
	local top = UP.eraTop(1950)
	eq(top, 3)
	local lines = {}
	local grownPb, n600 = {}, 0
	for _, t in ipairs(TOWNS) do
		local name, b, persons, u, c, act0 = t[1], t[2], t[3], t[4], t[5], t[6]
		local pb = persons / b
		-- (the model reproduces the run's pb from its actual shares)
		local a0 = { act0[1] / 100, act0[2] / 100, act0[3] / 100, act0[4] / 100 }
		local pbFit = pbOf(a0)
		ok(math.abs(pbFit - pb) / pb < 0.2, string.format("%s: the model's pb %.2f vs the run's %.2f", name, pbFit, pb))
		local rows = c and rows3(c) or nil
		local owner = UP.levelOwner(UP.levelSig(rows), "-", 0, rows, nil)
		local wNow = shares(u, c, 4)
		local act, k, why, phase = decide({ buildings = b, pb = pb, mat = A.maturity(persons), custom = rows ~= nil, owner = owner,
			top = top, u = u, w = wNow })
		local newC = c
		if act == "set" then newC = UP.levelWeights(k, top)[1] elseif act == "clear" then newC = nil end
		local a1 = shares(u, newC, top)
		local pb1 = pbOf(a1)
		lines[#lines + 1] = string.format("%-18s b=%4d pb %.2f -> %.2f  %-7s %-5s tilt=%5.2f  lvl %2.0f/%2.0f/%2.0f/%2.0f",
			name, b, pb, pb1, phase or "-", act or "-", k or 0, 100 * a1[1], 100 * a1[2], 100 * a1[3], 100 * a1[4])
		if b >= 600 then
			n600 = n600 + 1
			ok(a1[1] < 0.95, name .. ": a town of 600+ buildings is never held at level 1 alone")
			ok(phase ~= "young", name .. ": half grown at least")
		end
		if phase == "mature" then grownPb[#grownPb + 1] = pb1 end
		-- (the same town drawn densify: above the engine's weights once half grown)
		if phase ~= "young" then
			local aD, kD = decide({ buildings = b, pb = pb, mat = A.maturity(persons), custom = rows ~= nil, owner = owner,
				top = top, u = u, w = wNow, densify = true })
			local cD = aD == "set" and UP.levelWeights(kD, top)[1] or (aD == "clear" and nil or c)
			local pbD = pbOf(shares(u, cD, top))
			lines[#lines] = lines[#lines] .. string.format("  | densify tilt=%.2f pb %.2f", aD == "set" and kD or 0, pbD)
			ok(pbD >= pb1 - 1e-6, name .. ": densify at or above the plain town")
			if UP.levelMat(A.maturity(persons), b) >= UP.DZ_RAMP_MAT then ok(pbD > 5.2, name .. ": a grown densify town builds up") end
		end
		if c == nil then eq(act, nil, name .. ": no weights (the engine's own): never a hold, unchanged") end
		ok(pb1 >= pbOf(shares(u, c, top)) - 1e-6, name .. ": never lower than its current weights")
	end
	print("\n" .. table.concat(lines, "\n"))
	ok(n600 >= 8)
	ok(#grownPb >= 3, "the run's grown towns read mature")
	for _, p in ipairs(grownPb) do ok(p >= 4.0 and p <= 5.5, string.format("a grown town's pb %.2f in 4-5", p)) end
end)

test("young towns are unchanged; the blend eases back; grown at or above the engine's", function()
	-- young: nothing sent, the engine's fill weights stay (the young hold), weights of ours stay too
	local fill = rows3({ 0.766, 0, 0, 0 })
	for _, o in ipairs({ { buildings = 250, mat = 0.1 }, { buildings = 450, mat = 0.2 }, { buildings = 480, mat = 0.45 } }) do
		local act, _, why = decide({ buildings = o.buildings, pb = 3, mat = o.mat, custom = true, owner = "fill" })
		eq(act, nil)
		eq(why, "young")
		eq(select(1, decide({ buildings = o.buildings, pb = 3, mat = o.mat })), nil, "no weights: none")
		eq(select(1, decide({ buildings = o.buildings, pb = 3, mat = o.mat, custom = true, owner = "ours", ours = 0.5 })), nil)
	end
	ok(UP.levelOwner(UP.levelSig(fill), "-", 0, fill, nil) == "fill")
	-- the phases in order as a town grows, the tilt never falls
	local last, order, sends = -2, {}, 0
	local ours = 0
	for b = 150, 1500, 25 do
		local persons = b * 3.2
		local act, k, _, phase = decide({ buildings = b, pb = 3.2, mat = A.maturity(persons), owner = ours ~= 0 and "ours" or "none",
			ours = ours, custom = ours ~= 0 })
		if act == "set" then ours, sends = k, sends + 1 elseif act == "clear" then ours, sends = 0, sends + 1 end
		if phase and order[#order] ~= phase then order[#order + 1] = phase end
		if phase ~= "young" and phase ~= nil then
			ok(ours >= last - 1e-9, string.format("b=%d: the tilt %.2f never falls (was %.2f)", b, ours, last))
			last = ours
		end
	end
	eq(table.concat(order, ","), "young,blend,mature")
	ok(sends <= 6, "a few sends over the whole growth: " .. sends)
	eq(ours, 0, "a grown plain town from 1950 ends at the engine's own weights (none of ours)")
	local _, kTop2 = decide({ buildings = 1500, pb = 3.2, mat = 1, top = 2 })
	ok(kTop2 > 0, "before 1950 (levels 1-2 only) a grown town at pb 3.2 goes above them")
	-- mature at pb 5: the engine's weights (fill weights cleared, ours from the blend cleared)
	eq(select(1, decide({ buildings = 1200, pb = 5, mat = 1, custom = true, owner = "fill" })), "clear")
	eq(select(3, decide({ buildings = 1200, pb = 5, mat = 1, custom = true, owner = "ours", ours = -0.25 })), "eased")
	eq(select(1, decide({ buildings = 1200, pb = 5, mat = 1 })), nil, "no weights: none needed")
end)

test("player weights are never touched, in any phase", function()
	local slid = { { 0.37, 0.4, 0.2, 0 }, { 1, 0.5, 0.2, 0 }, { 1, 0.5, 0.2, 0 } }
	local owner = UP.levelOwner(UP.levelSig(slid), "-", 0, slid, nil)
	eq(owner, "player")
	for _, o in ipairs({ { 250, 0.1 }, { 600, 0.2 }, { 800, 0.7 }, { 1500, 1 } }) do
		for _, dz in ipairs({ false, true }) do
			local act, _, why = decide({ buildings = o[1], pb = 2.8, mat = o[2], custom = true, owner = owner, densify = dz })
			eq(act, nil)
			eq(why, "player")
		end
	end
	-- the player changed ours: theirs now
	local ours = UP.levelWeights(-0.5, 3)
	eq(UP.levelOwner(UP.levelSig(slid), "-", -0.5, slid, UP.levelSig(ours)), "player")
end)

test("era gate: no tilt toward levels the game can't build yet", function()
	eq(UP.eraTop(1900), 2)
	eq(UP.eraTop(1949), 2)
	eq(UP.eraTop(1950), 3)
	eq(UP.eraTop(1989), 3)
	eq(UP.eraTop(1990), 4)
	eq(UP.eraTop(nil), 4)
	local w2 = UP.levelWeights(0.75, 2)[1]
	eq(w2[2], 1)
	eq(w2[3], w2[2], "level 3 not above level 2 before 1950")
	eq(w2[4], w2[2])
	local w3 = UP.levelWeights(0.75, 3)[1]
	eq(w3[3], 1)
	eq(w3[4], w3[3], "level 4 not above level 3 before 1990")
	ok(w3[1] < w3[2] and w3[2] < w3[3])
	-- top 4: the old formula exactly (saved `lw` strengths of old saves read as ours)
	local w4, old = UP.levelWeights(0.5, 4)[1], UP.levelWeights(0.5)[1]
	for l = 1, 4 do eq(w4[l], old[l]) end
	-- the hold row ignores the era (it only lowers)
	local h = UP.levelWeights(-1, 2)[1]
	eq(h[1], 1)
	ok(h[2] < 0.45 and h[3] < h[2] and h[4] < h[3])
	-- a 1900 densify town: the weighted target asks no more of levels 3-4 than of level 2
	local a = shares({ 34, 27, 22, 17 }, UP.levelWeights(1, 2)[1], 2)
	eq(a[3] + a[4], 0)
	ok(a[2] > 0.6, "its share goes to level 2, the top it can build")
end)

test("densify: drawn from half grown, ramping in, above the engine's weights", function()
	-- the draw point by the level maturity: 500 buildings or 2700 persons
	ok(UP.levelMat(A.maturity(1900), 500) >= CH.DZ_MAT)
	ok(UP.levelMat(A.maturity(2700), 300) >= CH.DZ_MAT)
	ok(UP.levelMat(A.maturity(1900), 450) < CH.DZ_MAT)
	-- the ramp: 0 at the draw, full from DZ_RAMP_MAT; the tilt follows
	eq(CH.dzRamp(CH.DZ_MAT), 0)
	eq(CH.dzRamp(CH.DZ_RAMP_MAT), 1)
	eq(CH.DZ_RAMP_MAT, UP.DZ_RAMP_MAT)
	local ks = {}
	for _, b in ipairs({ 500, 600, 660, 800 }) do
		local act, k, _, phase = decide({ buildings = b, pb = 3, mat = 0, densify = true })
		eq(phase, "densify")
		ks[#ks + 1] = act == "set" and k or 0
	end
	ok(ks[1] == 0 and ks[2] > 0 and ks[4] >= UP.DZ_K_MIN, table.concat(ks, ","))
	for i = 2, #ks do ok(ks[i] >= ks[i - 1]) end
	-- the driver's hold ramps in too
	local d = D.new({ nowUs = function() return 0 end, log = function() end }, "[T]")
	d.opts = { strongCharacters = true }
	local s = d:townState(5)
	s.dz, s.mat = 1, CH.DZ_MAT
	local h0 = d:densifyDemand(5)
	s.mat = CH.DZ_RAMP_MAT
	local h1 = d:densifyDemand(5)
	ok(h0 and h1, "active from the draw")
	ok(math.abs(h0.holdFree - A.MATURE_HOLD_FREE) < 1e-9 and math.abs(h1.holdFree - CH.DZ_HOLD_FREE) < 1e-9)
end)

-- (the draw keeps about a third of the drawn towns, CH.DZ_P; this map is linear-heavy (linear x 0.3) and only 8 of its 13
-- ordinary towns are half grown by year 28: ~16 % on by year 28, ~22 % by 40, against none in the run, whose dev
-- Simulate pool drivers never drew)
test("densify share: the run's ordinary towns drawn from half grown, a fifth to a third on by the end", function()
	-- (the 13 ordinary towns of the run: buildings / persons at years 20, 28, 40 (SIMGROW town lines), form (ALLTOWN))
	local T = {
		{ "linear", { 854, 2764 }, { 1080, 3483 }, { 1388, 4669 } }, -- Mytham
		{ "linear", { 650, 2046 }, { 902, 2677 }, { 1241, 3706 } }, -- Dart Head
		{ "shore", { 508, 1691 }, { 627, 2215 }, { 1058, 3226 } }, -- Lower Aberarun
		{ "clustered", { 450, 1400 }, { 645, 1827 }, { 859, 2629 } }, -- Abercoed
		{ "shore", { 341, 1436 }, { 519, 1948 }, { 761, 2829 } }, -- Oakhaven
		{ "shore", { 448, 1917 }, { 550, 2394 }, { 721, 3188 } }, -- Hornness
		{ "linear", { 330, 1023 }, { 469, 1349 }, { 699, 1887 } }, -- Edton
		{ "wide", { 442, 1425 }, { 540, 1751 }, { 682, 2264 } }, -- Padfield
		{ "fingers", { 409, 1097 }, { 526, 1396 }, { 679, 1875 } }, -- Trefach
		{ "clustered", { 353, 1289 }, { 401, 1597 }, { 530, 2098 } }, -- Winmere
		{ "sprawling", { 309, 1362 }, { 368, 1613 }, { 483, 2129 } }, -- Wemmead
		{ "shore", { 201, 859 }, { 238, 1092 }, { 300, 1471 } }, -- Shaw
		{ "linear", { 209, 791 }, { 242, 971 }, { 295, 1256 } }, -- Kelington
	}
	local out = {}
	for yi, y in ipairs({ 20, 28, 40 }) do
		local drawn, on = 0, 0
		for _, t in ipairs(T) do
			local b, p = t[yi + 1][1], t[yi + 1][2]
			if UP.levelMat(A.maturity(p), b) >= CH.DZ_MAT then
				drawn = drawn + 1
				local sizeRank = math.max(0, math.min(1, math.log(math.max(1, p) / A.MAT_LO) / math.log(8)))
				local _, _, pr = CH.densifyDraw({ seed = 1, form = t[1], sizeRank = sizeRank, central = 0.5 })
				on = on + pr
			end
		end
		out[#out + 1] = string.format("year %d: %d of %d drawn, %.1f expected on (%.0f %%)", y, drawn, #T, on, 100 * on / #T)
		if y == 28 then ok(drawn >= 6 and on / #T >= 0.12, out[#out]) end
		if y == 40 then ok(drawn >= 8 and on / #T >= 0.2, out[#out]) end
	end
	print("\n" .. table.concat(out, "\n"))
end)

---------------------------------------------------------------------------
-- the driver: phases in the LEVELS line, the fill weights replaced, the refill after a restore, pool drivers

local function fakeE(custom, year)
	local E = { t = 1e9, logs = {}, events = {}, custom = custom, sent = {} }
	function E.nowUs() return E.t end
	function E.name(t) return "T" .. t end
	function E.log(l) E.logs[#E.logs + 1] = l end
	function E.year() return year or 1960 end
	function E.levelInfo(_t)
		return { custom = E.custom, actual = { { 80, 20, 0, 0 }, { 1, 0, 0, 0 }, { 1, 0, 0, 0 } } }
	end
	function E.setLevelWeights(t, w, cb)
		E.sent[#E.sent + 1] = { t = t, w = w }
		E.custom = w
		cb(true)
	end
	function E.sendEvent(_id, name, p) E.events[#E.events + 1] = { name = name, param = p } end
	return E
end

local function m(b, persons) return { buildings = b, caps = { actual = persons, target = persons }, dem = { mat = A.maturity(persons) } } end

local function logged(E, pat)
	for _, l in ipairs(E.logs) do if l:find(pat, 1, true) then return l end end
	return nil
end

test("driver: a grown town's fill weights go, LEVELS logs phase, tilt and weights from -> to; saved with its sig", function()
	local E = fakeE(rows3({ 0.419192, 0, 0, 0 }), 1960)
	local d = D.new(E, "[T]")
	d.opts = { debug = true, strongCharacters = false }
	d.newMap = true
	d.lvBase = { [7] = "-" }
	d:levelsCheck(7, m(699, 1921), E.t)
	eq(#E.sent, 1)
	local l = logged(E, "LEVELS town=7")
	ok(l and l:find("action=set", 1, true) and l:find("phase=blend", 1, true) and l:find("owner=fill", 1, true), tostring(l))
	ok(l:find("from=0.419/0/0/0", 1, true) and l:find("to=1/", 1, true) and l:find("era=3", 1, true), l)
	ok(E.sent[1].w[1][2] > 0.3, "level 2 back")
	local ev = E.events[#E.events]
	ok(ev.name == SV.EV_LEVELS and ev.param.k4 < 0 and ev.param.sig == UP.levelSig(E.sent[1].w), "saved: tilt and sig")
	-- the frame keeps both; ours by sig after a reload
	local s0 = SV.applyFrame(nil, { town = 7, a = 0, x = 0, y = 0 })
	local s1 = SV.applyLevels(s0, ev.param)
	local fr = SV.frame(SV.normalize(s1), 7)
	eq(fr.levels, ev.param.k4 / 4)
	eq(fr.levelSig, ev.param.sig)
	local s2 = SV.applyLevels(s1, { town = 7, k4 = 0 })
	eq(SV.frame(s2, 7).levelSig, nil, "cleared")
	-- a young town with fill weights: nothing
	local E2 = fakeE(rows3({ 0.766, 0, 0, 0 }), 1960)
	local d2 = D.new(E2, "[T]")
	d2.opts, d2.newMap, d2.lvBase = { debug = true, strongCharacters = false }, true, { [7] = "-" }
	d2:levelsCheck(7, m(300, 900), E2.t)
	eq(#E2.sent, 0, "young: unchanged")
	-- a player's weights: nothing, in any phase
	local E3 = fakeE({ { 1, 0.5, 0.2, 0 }, { 1, 0.5, 0.2, 0 }, { 1, 0.5, 0.2, 0 } }, 1960)
	local d3 = D.new(E3, "[T]")
	d3.opts, d3.newMap, d3.lvBase = { debug = true, strongCharacters = false }, true, { [7] = "-" }
	d3:levelsCheck(7, m(1300, 3000), E3.t)
	eq(#E3.sent, 0, "the player's")
end)

test("driver: after a FILL restore rewrote them, a managed town gets the mod's weights back (refill); young / player not", function()
	local E = fakeE(rows3({ 0.419192, 0, 0, 0 }), 1960)
	local d = D.new(E, "[T]")
	d.opts, d.newMap, d.lvBase = { debug = true, strongCharacters = false }, true, { [7] = "-" }
	d:levelsCheck(7, m(699, 1921), E.t)
	local ours = E.custom
	-- the engine's write on the restore
	E.custom = rows3({ 0.30965, 0.0572641, 0, 0 })
	d:levelsAfterRestore(7)
	eq(#E.sent, 2)
	eq(UP.levelSig(E.custom), UP.levelSig(ours))
	ok(logged(E, "LEVELS town=7 name=T7 event=refill phase=blend"), "refill line")
	-- unchanged: nothing
	d:levelsAfterRestore(7)
	eq(#E.sent, 2)
	-- the player's now: left
	E.custom = { { 1, 0.5, 0.2, 0 }, { 1, 0.5, 0.2, 0 }, { 1, 0.5, 0.2, 0 } }
	d:levelsAfterRestore(7)
	eq(#E.sent, 2)
	-- a young town: no refill (no weights of ours)
	local E2 = fakeE(rows3({ 0.766, 0, 0, 0 }), 1960)
	local d2 = D.new(E2, "[T]")
	d2.opts, d2.newMap, d2.lvBase = { debug = true, strongCharacters = false }, true, { [7] = "-" }
	d2:levelsCheck(7, m(300, 900), E2.t)
	E2.custom = rows3({ 0.5, 0, 0, 0 })
	d2:levelsAfterRestore(7)
	eq(#E2.sent, 0)
end)

test("driver: a pool driver (shared towns, no saved / baseline of its own) reads the root's", function()
	local H = ug_require(F.DIR .. "ot_hooks.lua")
	local E = fakeE(rows3({ 0.453303, 0.255125, 0.100228, 0 }), 1960)
	local root = D.new(E, "[T]")
	root.opts, root.newMap, root.lvBase = { debug = true, strongCharacters = true }, true, { [7] = "-" }
	root.saved = SV.normalize(SV.applyDense(SV.applyFrame(nil, { town = 7, a = 0, x = 0, y = 0 }), { town = 7, v = 1 }))
	local pool = D.new(E, "[T]")
	pool.towns, pool.opts, pool.newMap = root.towns, root.opts, true
	local was = H.main
	H.main = root
	eq(pool:levelBaseOf()[7], "-")
	ok(pool:densifyDrawn(7), "the saved draw read through the root")
	H.main = was
end)
