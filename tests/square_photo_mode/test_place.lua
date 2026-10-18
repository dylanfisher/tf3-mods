-- pm_place.lua (Photo Mode, pure): the "This place" tour's shots: inside the area, around the whole circle,
-- pitch inside the range rows, nearby subjects as targets.

local P, cam

before_each(function()
	reset_modules()
	cam = ug_require "square_photo_mode::/photo_mode/pm_cam.lua"
	P = ug_require "square_photo_mode::/photo_mode/pm_place.lua"
end)

local function rng(seed) return cam.newRng(seed) end

test("area choices: Small / Medium / Large radius, bad choices give the default", function()
	eq(P.radius(1), 80); eq(P.radius(2), 250); eq(P.radius(3), 600)
	eq(P.radius(0), 250); eq(P.radius(9), 250); eq(P.radius(nil), 250); eq(P.radius(0 / 0), 250)
	eq(P.newPlan(0 / 0, 0, 100, rng(1)), nil)
	eq(P.newPlan(0, 0, 0, rng(1)), nil)
end)

test("every round of SECTORS shots covers the whole circle once, in a shuffled order", function()
	local rnd = rng(7)
	local plan = P.newPlan(1000, -500, 250, rnd)
	local range = cam.tourRange(cam.preset("place"))
	local orders = {}
	for round = 1, 5 do
		local seen, order = {}, {}
		for __ = 1, P.SECTORS do
			local v = P.shot(plan, range, rnd, nil)
			local slice = cam.TWO_PI / P.SECTORS
			local a = v.a < 0 and v.a + cam.TWO_PI or v.a
			local sector = math.floor(a / slice) + 1
			eq(sector, plan.last, "the angle lies inside its slice")
			ok(not seen[sector], "no slice twice in a round")
			seen[sector] = true
			order[#order + 1] = sector
		end
		orders[round] = table.concat(order, ",")
	end
	ok(orders[1] ~= orders[2] or orders[2] ~= orders[3], "the order changes between rounds")
end)

test("a new round never starts on the last slice or its neighbours", function()
	for seed = 1, 40 do
		local rnd = rng(seed)
		local plan = P.newPlan(0, 0, 80, rnd)
		for __ = 1, 6 * P.SECTORS do
			local before = plan.last
			local startsRound = plan.i >= #plan.order
			local s = P.nextSector(plan, rnd)
			if startsRound and before ~= nil then
				local d = math.abs(s - before) % P.SECTORS
				ok(d > 1 and d < P.SECTORS - 1, "seed " .. seed .. ": " .. before .. " -> " .. s)
			end
		end
	end
end)

test("place points stay within the area, distances by the area size, pitch inside the range rows", function()
	for _, choice in ipairs({ 1, 2, 3 }) do
		local r = P.radius(choice)
		local rnd = rng(100 + choice)
		local plan = P.newPlan(5000, 5000, r, rnd)
		local sel = cam.preset("place")
		local range = cam.tourRange(sel)
		eq(range.pMin, cam.RANGE.pitchFrom[1], "eye level")
		eq(range.pMax, cam.RANGE.pitchTo[2], "drone")
		local dMin, dMax = P.distRange(r, false)
		local lowBand, highBand = 0, 0
		for __ = 1, 300 do
			local v, target = P.shot(plan, range, rnd, nil)
			eq(target, nil)
			ok(P.inside(plan, v.x, v.y, P.PLACE_SPREAD + 1e-9), "centre inside the area")
			ok(v.d >= dMin - 1e-9 and v.d <= dMax + 1e-9, "distance " .. v.d)
			ok(v.p >= range.pMin - 1e-9 and v.p <= range.pMax + 1e-9, "pitch " .. v.p)
			ok(cam.safeView(v) ~= nil, "finite")
			local third = (range.pMax - range.pMin) / 3
			if v.p < range.pMin + third then lowBand = lowBand + 1 end
			if v.p > range.pMax - third then highBand = highBand + 1 end
			-- the eye stays near the place: centre within 0.6 r, ground distance at most 1.2 r
			local ex, ey = cam.eyeXY(v, 0)
			ok(math.sqrt((ex - 5000) ^ 2 + (ey - 5000) ^ 2) <= (P.PLACE_SPREAD + 1.2) * r + 1e-6, "eye near")
		end
		ok(lowBand >= 80 and highBand >= 80, "eye level to drone, both ends used: " .. lowBand .. "/" .. highBand)
	end
end)

test("the range rows are honoured (a narrow range keeps every pitch in it)", function()
	local rnd = rng(3)
	local plan = P.newPlan(0, 0, 250, rnd)
	local range = cam.tourRange({ pf = 2, pt = 1, df = 1, dt = 1 }) -- 0.12 .. 0.20
	for __ = 1, 100 do
		local v = P.shot(plan, range, rnd, nil)
		ok(v.p >= 0.12 - 1e-9 and v.p <= 0.20 + 1e-9)
	end
end)

test("nearby subjects: about half the shots, each before any repeats, only those inside the area", function()
	local rnd = rng(11)
	local plan = P.newPlan(0, 0, 250, rnd)
	local subjects = {
		{ entity = 1, x = 50, y = 0, kind = "building" },
		{ entity = 2, x = 0, y = -120, kind = "train", moving = true },
		{ entity = 3, x = 900, y = 900, kind = "person", moving = true }, -- outside: never a target
		{ entity = 4, x = -200, y = 100, kind = "building" },
	}
	local hits, byEntity = 0, {}
	local N = 400
	for __ = 1, N do
		local s = P.pickSubject(plan, subjects, rnd)
		if s ~= nil then
			hits = hits + 1
			byEntity[s.entity] = (byEntity[s.entity] or 0) + 1
			local v, target = P.shot(plan, cam.tourRange(cam.preset("place")), rnd, s)
			eq(target, s)
			eq(v.x, s.x); eq(v.y, s.y)
			local dMin, dMax = P.distRange(250, true)
			ok(v.d >= dMin - 1e-9 and v.d <= dMax + 1e-9, "a subject is framed closer")
		end
	end
	ok(hits > N * 0.35 and hits < N * 0.65, "about half: " .. hits)
	eq(byEntity[3], nil, "outside the area")
	ok((byEntity[1] or 0) > 20 and (byEntity[2] or 0) > 20 and (byEntity[4] or 0) > 20, "all inside ones used")
	eq(P.pickSubject(plan, {}, rnd), nil)
	eq(P.pickSubject(plan, nil, rnd), nil)
end)

test("a subject that isn't finite becomes a place point", function()
	local rnd = rng(5)
	local plan = P.newPlan(0, 0, 80, rnd)
	local v, target = P.shot(plan, nil, rnd, { x = 0 / 0, y = 1 })
	eq(target, nil)
	ok(cam.safeView(v) ~= nil)
	ok(P.inside(plan, v.x, v.y))
end)
