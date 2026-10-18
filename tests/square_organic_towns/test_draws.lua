-- Decision draws (2026-10-15, NEXT_PHASE_BRIEF 68): ot_rng.hash is affine mod 2^31 - 1, so rng.unit(seed, a) and
-- rng.unit(seed, b) for labels of the same length differ by a constant mod 1 (forestMode = forestDeep + 0.861). The
-- coupled decisions draw with rng.decide (rng.draw) now; each group keeps at most one member on rng.unit (shape,
-- siteStyle, characterForm, form, characterIsland). Covers: before / after independence on 20000 seeds (full mode;
-- 4000 quick), the gates' joint odds, rng.decide's versions, the frame's `dv` (new frames 2, old frames keep
-- rng.unit), and that saved decisions (deep `fd`, character `ck`, skeleton `sk`, shape / style / form) are read back,
-- never drawn again on load.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local rng = ug_require(F.DIR .. "ot_rng.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local FO = ug_require(F.DIR .. "ot_forest.lua")
local EN = ug_require(F.DIR .. "ot_entry.lua")
local LD = ug_require(F.DIR .. "ot_lead.lua")
local BR = ug_require(F.DIR .. "ot_bridge.lua")
local SP = ug_require(F.DIR .. "ot_satpace.lua")
local CH = ug_require(F.DIR .. "ot_character.lua")

local FULL = os.getenv("TEST_FULL") ~= nil
local N = FULL and 20000 or 4000

local function townSeed(i)
	return rng.seed(60000 + (i * 7919) % 3000, (i * 104729) % 16000 - 8000, (i * 1299709) % 16000 - 8000)
end

--- Resultant length of the circular difference a - b (1 = one draw shifted by a constant, ~1/sqrt(n) independent)
--- and the mean shift.
local function shiftR(a, b)
	local c, s = 0, 0
	for i = 1, #a do
		local d = (a[i] - b[i]) * 2 * math.pi
		c, s = c + math.cos(d), s + math.sin(d)
	end
	return math.sqrt(c * c + s * s) / #a, (math.atan(s, c) / (2 * math.pi)) % 1
end

--- Pearson correlation.
local function corr(a, b)
	local n, ma, mb = #a, 0, 0
	for i = 1, n do ma, mb = ma + a[i], mb + b[i] end
	ma, mb = ma / n, mb / n
	local sab, saa, sbb = 0, 0, 0
	for i = 1, n do
		local x, y = a[i] - ma, b[i] - mb
		sab, saa, sbb = sab + x * y, saa + x * x, sbb + y * y
	end
	return sab / math.sqrt(saa * sbb)
end

--- chi-square over a 10 x 10 table (81 degrees of freedom: 0.1 % critical ~124).
local function chi2(a, b)
	local k, c, n = 10, {}, #a
	for i = 1, k * k do c[i] = 0 end
	for i = 1, n do
		local x, y = math.floor(a[i] * k), math.floor(b[i] * k)
		c[x * k + y + 1] = c[x * k + y + 1] + 1
	end
	local e, s = n / (k * k), 0
	for i = 1, k * k do s = s + (c[i] - e) ^ 2 / e end
	return s
end

-- the coupled pairs: { label a (+ extra args), label b, a's kind after §68, b's kind after §68 } ("d" rng.decide,
-- "u" rng.unit: an anchor)
local PAIRS = {
	{ { "forestMode" }, { "forestDeep" }, "d", "d" },
	{ { "forestMode" }, { "entryTrees" }, "d", "d" },
	{ { "forestDeep" }, { "entryTrees" }, "d", "d" },
	{ { "arms3" }, { "shape" }, "d", "u" },
	{ { "metro" }, { "shape" }, "d", "u" },
	{ { "metro" }, { "arms3" }, "d", "d" },
	{ { "shoreForm" }, { "satellite" }, "d", "d" },
	{ { "satellite" }, { "siteStyle" }, "d", "u" },
	{ { "densify" }, { "leadEnd" }, "d", "d" },
	{ { "fingers" }, { "leadEnd" }, "d", "d" },
	{ { "satpace:ready" }, { "characterForm" }, "d", "u" },
	{ { "satpace:every" }, { "satpace:phase" }, "d", "d" },
	{ { "motif", 1 }, { "motif", 2 }, "d", "d" },
	{ { "motifPick", 1 }, { "motifPick", 2 }, "d", "d" },
}

local function u(kind, seed, args)
	if kind == "u" then return rng.unit(seed, table.unpack(args)) end
	return rng.decide(2, seed, table.unpack(args))
end

test("before / after: equal-length decision labels were one draw shifted; rng.decide makes them independent", function()
	for _, pr in ipairs(PAIRS) do
		local oa, ob, na, nb = {}, {}, {}, {}
		for i = 1, N do
			local s = townSeed(i)
			oa[i], ob[i] = rng.unit(s, table.unpack(pr[1])), rng.unit(s, table.unpack(pr[2]))
			na[i], nb[i] = u(pr[3], s, pr[1]), u(pr[4], s, pr[2])
		end
		local R0, sh0 = shiftR(oa, ob)
		local R1 = shiftR(na, nb)
		local r1, c1 = corr(na, nb), chi2(na, nb)
		local label = tostring(pr[1][1]) .. (pr[1][2] and pr[1][2] or "") .. "/" .. tostring(pr[2][1]) .. (pr[2][2] and pr[2][2] or "")
		print(string.format("%-28s before R=%.3f shift=%.3f | after R=%.3f r=%+.3f chi2=%.0f (N %d)", label, R0, sh0, R1, r1, c1, N))
		ok(R0 > 0.999, label .. ": the old draws are one shifted draw")
		ok(R1 < 0.05, label .. ": after, no constant shift: " .. R1)
		ok(math.abs(r1) < 0.05, label .. ": after, uncorrelated: " .. r1)
		ok(c1 < 135, label .. ": after, independent (chi2 " .. c1 .. ")")
	end
end)

test("joint gates: hug, deep and tree-lined entries no longer pick each other; the cross's 3 arms not its shape's", function()
	-- before: forestMode = forestDeep + 0.861, so a town whose deep draw fell in [0.14, 0.3) (a deep candidate at p 0.3
	-- that the forest's share or the quota turned down) always drew u_mode below 0.161: a hug at any odds above it
	local pD, pM = 0.3, 0.45
	local old, nOld, new, nNew, both = 0, 0, 0, 0, 0
	for i = 1, N do
		local s = townSeed(i)
		local ud = rng.unit(s, "forestDeep")
		if ud >= 0.14 and ud < pD then
			nOld = nOld + 1
			if rng.unit(s, "forestMode") < pM then old = old + 1 end
		end
		local nd = rng.decide(2, s, "forestDeep")
		if nd >= 0.14 and nd < pD then
			nNew = nNew + 1
			if rng.decide(2, s, "forestMode") < pM then new = new + 1 end
		end
		if nd < pD and rng.decide(2, s, "forestMode") < pM then both = both + 1 end
	end
	print(string.format("hug among deep candidates turned down: before %.3f, after %.3f (p %.2f); deep x hug %.3f (%.3f)",
		old / nOld, new / nNew, pM, both / N, pD * pM))
	eq(old, nOld, "before: every one hugged")
	near(new / nNew, pM, 0.06, "after: the hug odds")
	near(both / N, pD * pM, 0.03, "after: deep x hug independent")
	-- ... and the cross's 3 arms (arms3 < 0.35) followed its shape draw (arms3 = shape + 0.028)
	local lo, hi, nLo, nHi = 0, 0, 0, 0
	for i = 1, N do
		local s = townSeed(i)
		local us = rng.unit(s, "shape")
		local a3 = rng.decide(2, s, "arms3") < 0.35
		if us < 0.5 then nLo = nLo + 1; if a3 then lo = lo + 1 end else nHi = nHi + 1; if a3 then hi = hi + 1 end end
	end
	near(lo / nLo, 0.35, 0.04, "3 arms whatever the shape draw (low half)")
	near(hi / nHi, 0.35, 0.04, "3 arms whatever the shape draw (high half)")
end)

test("rng.decide: version 1 is rng.unit, anything else rng.draw; deterministic, in [0, 1)", function()
	for i = 1, 200 do
		local s = townSeed(i)
		eq(rng.decide(1, s, "forestMode"), rng.unit(s, "forestMode"))
		eq(rng.decide(2, s, "forestMode"), rng.draw(s, "forestMode"))
		eq(rng.decide(nil, s, "forestMode"), rng.draw(s, "forestMode"))
		local v = rng.decide(2, s, "satpace:step", 3)
		ok(v >= 0 and v < 1)
	end
end)

test("frames: a new frame saves dv = 2, an old one has none and keeps rng.unit; frameless towns draw with rng.decide", function()
	local style = { id = "EU_ORGANIC", axis = 0.3, centre = { 10, 20 }, drawV = 2 }
	local fp = SV.frameParam(77, style, nil, nil, nil, nil)
	eq(fp.dv, 2)
	local st = SV.applyFrame(SV.normalize(nil), fp)
	eq(SV.frame(st, 77).drawV, 2)
	-- a saved state round trip (normalize keeps it)
	eq(SV.frame(SV.normalize(st), 77).drawV, 2)
	style.drawV = 1
	eq(SV.frameParam(78, style, nil, nil, nil, nil).dv, nil, "a legacy town never gets dv")
	local old = SV.normalize({ v = SV.VERSION, frames = { ["9"] = { a = 0.1, x = 1, y = 2 } } })
	eq(SV.frame(old, 9).drawV, nil)
	-- ot_style: an old frame -> 1, a §68 frame -> 2, no frame -> 2
	local function resolved(frame) return (F.style({ townId = 9, frame = frame })) end
	eq(resolved(SV.frame(old, 9)).drawV, 1, "old frame: rng.unit")
	eq(resolved(SV.frame(st, 77)).drawV, 2, "§68 frame")
	eq(resolved(nil).drawV, 2, "no frame yet")
end)

test("legacy towns keep their re-derived picks: forest mode, entries, lead, bridge, readiness as with rng.unit", function()
	local same, diff = 0, 0
	for i = 1, 400 do
		local s = townSeed(i)
		local style = { id = "EU_ORGANIC", seed = s, year = 1900, tier = 2, drawV = 1 }
		local fo = FO.forStyle({ done = true, share = 0.5 }, style)
		local mode = rng.unit(s, "forestMode") < select(1, FO.chance(style)) and "hug" or "clear"
		eq(fo.mode, mode, "forest mode " .. i)
		local en = select(1, EN.on(style))
		eq(en, rng.unit(s, "entryTrees") < select(2, EN.on(style)), "entries " .. i)
		local o = { seed = s, dv = 1, buildings = (LD.MIN_BUILDINGS + LD.MAX_BUILDINGS) / 2 }
		local l1 = LD.eligible(o)
		eq(l1 == true, rng.unit(s, "leadLane") < LD.CHANCE, "lead " .. i)
		local b1 = BR.eligible({ seed = s, dv = 1, buildings = BR.MIN_BUILDINGS + 1, river = true })
		eq(b1 == true, rng.unit(s, "bridge") < BR.CHANCE, "bridge " .. i)
		local r1 = select(3, SP.readiness({ size = 100, start = 100, k = 0, seed = s, dv = 1 }))
		local want = math.max(100 * (SP.READY[1] + (SP.READY[2] - SP.READY[1]) * rng.unit(s, "satpace:ready")),
			SP.READY_MIN[1] + (SP.READY_MIN[2] - SP.READY_MIN[1]) * rng.unit(s, "satpace:min"))
		near(r1, want, 1e-6, "readiness " .. i)
		-- a §68 town draws otherwise (now and then)
		style.drawV = 2
		if FO.forStyle({ done = true, share = 0.5 }, style).mode == fo.mode then same = same + 1 else diff = diff + 1 end
	end
	ok(diff > 40, "new towns' forest modes differ from the old draw for some towns: " .. diff)
	print(string.format("forest mode, legacy vs §68 draw: %d same, %d different of 400", same, diff))
end)

test("saved decisions are read back, never drawn again: deep fd, character ck, skeleton sk, shape / style / form", function()
	local raw = SV.normalize({ v = SV.VERSION, frames = { ["5"] = { a = 0.2, x = 0, y = 0, fd = 1, ck = 3, sk = "900:120:400",
		s = 2, st = 3, f = 1 } } })
	local fr = SV.frame(raw, 5)
	eq(fr.deep, true)
	eq(fr.charKind, 3)
	eq(fr.skel, "900:120:400")
	eq(fr.style, SV.STYLE_IDS[3])
	eq(fr.drawV, nil, "an old frame: its re-derived picks keep rng.unit")
	-- a deep frame stays deep whatever the draw says (the forest's mode is "deep", never drawn)
	local style = { id = "EU_ORGANIC", seed = 12345, year = 1900, deep = { why = "saved" }, drawV = 1 }
	eq(FO.forStyle({ done = true, share = 0.5 }, style).mode, "deep")
	-- the resolved style takes the saved style and form, whichever draw version
	local st = F.style({ townId = 5, frame = fr })
	eq(st.id, SV.STYLE_IDS[3])
	eq(st.drawV, 1)
	-- the strong character's kind comes from the frame / the map's saved picks (CH.byIndex), not from a draw
	ok(CH.byIndex(3) ~= nil, "kind 3")
end)
