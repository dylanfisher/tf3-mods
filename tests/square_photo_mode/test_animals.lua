-- Round 16b / 17: Animals (gui/pm_animals.lua): groups by climate, the engine's suitability score where each may
-- stand, the spawn commands with their callbacks, the caps, removing only our own, the life checks.
-- Round 20: the Animals tab: every group (the climate's first), placement by screen rays (a pinhole camera fake
-- below: screen2World / world2Screen), Distance / Formation / Facing, never refused for the score.

local M, fk

-- A pinhole camera: eye E looking at C, vertical fov 60 degrees, a 1600 x 900 screen (the game's screen2World takes
-- pixels and a depth 0..1 between the near and far planes; world2Screen returns pixels).
local function camera(E, C)
	local W, H, tanH, NEAR, FAR = 1600, 900, math.tan(math.rad(30)), 1, 5000
	local function norm(x, y, z) local l = math.sqrt(x * x + y * y + z * z) return x / l, y / l, z / l end
	local fx, fy, fz = norm(C.x - E.x, C.y - E.y, C.z - E.z)
	local rx, ry, rz = norm(fy * 1 - fz * 0, fz * 0 - fx * 1, 0) -- f x up
	local ux, uy, uz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
	local aspect = W / H
	return {
		getSize = function() return { x = W, y = H } end,
		getEye = function() return { x = E.x, y = E.y, z = E.z } end,
		getCenter = function() return { x = C.x, y = C.y, z = C.z } end,
		screen2World = function(p)
			local nx, ny = (2 * p.x / W - 1) * tanH * aspect, (1 - 2 * p.y / H) * tanH
			local dx, dy, dz = norm(fx + rx * nx + ux * ny, fy + ry * nx + uy * ny, fz + rz * nx + uz * ny)
			local t = p.z == 0 and NEAR or FAR
			return { x = E.x + dx * t, y = E.y + dy * t, z = E.z + dz * t }
		end,
		world2Screen = function(p)
			local vx, vy, vz = p.x - E.x, p.y - E.y, p.z - E.z
			local z = vx * fx + vy * fy + vz * fz
			if z <= 1e-6 then return { x = -1e6, y = -1e6 } end
			local x = (vx * rx + vy * ry + vz * rz) / z / (tanH * aspect)
			local y = (vx * ux + vy * uy + vz * uz) / z / tanH
			return { x = (x + 1) / 2 * W, y = (1 - y) / 2 * H }
		end,
	}
end

local function setup(climate, eye, centre)
	reset_modules()
	fk = { now = 0, sent = {}, busy = {}, animals = {}, nextId = 500 }
	set_global("api", {
		util = { powerToDecibel = function(p) return p end },
		type = {
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
			ComponentType = { ANIMAL = "ANIMAL", BASE_EDGE = "BASE_EDGE", CONSTRUCTION = "CONSTRUCTION", TOWN_BUILDING = "TOWN_BUILDING",
				ASSET_GROUP = "ASSET_GROUP" },
			EmissionGrid = { Type = { Noise = 0 } },
		},
		engine = {
			entityExists = function(e) return fk.animals[e] ~= nil end,
			getComponent = function(e, t)
				if fk.animals[e] == nil then error("Invalid entity") end
				if t == "ANIMAL" then return fk.animals[e] end
				return nil
			end,
			system = { emissionGridSystem = { getInterpolatedEmission = function() return fk.noise or 0 end } },
			util = { octree = { findEntitiesInCircle = function(p, r, t) return fk.busy[t] and { 1 } or {} end } },
		},
		cmd = {
			makeAnimalSpawnAtCmd = function(file, pos, look) return { spawn = file, pos = pos, look = look } end,
			makeCustomEntityDestroyCmd = function(e) return { destroy = e } end,
			sendCommand = function(c, cb)
				fk.sent[#fk.sent + 1] = c
				if c.spawn then
					fk.nextId = fk.nextId + 1
					fk.animals[fk.nextId] = { worldPosition = { x = c.pos.x, y = c.pos.y, z = 0 }, movementType = 1, movementSpeed = 0.5 }
					if cb then cb({ resultEntity = fk.nextId }, true) end
				elseif c.destroy then
					fk.animals[c.destroy] = nil
					if cb then cb({}, true) end
				end
			end,
		},
		gui = { camera = camera(eye or { x = 0, y = 0, z = 30 }, centre or { x = 200, y = 0, z = 0 }) },
	})
	local seed = 0
	stub_module("square_photo_mode::/photo_mode/gui/pm_world.lua", {
		nowMs = function() return fk.now end,
		rnd = function() seed = (seed * 16807 + 12345) % 2147483647 return seed / 2147483647 end,
		groundAt = function(x, y) return fk.ground and fk.ground(x, y) or 0 end,
		waterAt = function(x, y) return fk.waterAll == true or (fk.water ~= nil and fk.water(x, y)) end,
	})
	stub_module("square_photo_mode::/photo_mode/gui/pm_weather.lua", { climate = function() return climate end })
	M = ug_require "square_photo_mode::/photo_mode/gui/pm_animals.lua"
end

local function groupKeys()
	local keys = {}
	for __, g in ipairs(M.groups()) do keys[#keys + 1] = g.key end
	return table.concat(keys, ",")
end
local function sel(key)
	for i, g in ipairs(M.groups()) do if g.key == key then M.S.sel = i return end end
	error("no group " .. key)
end

test("round 17: groups follow the map's climate (the models' categoryList); no elk model: the herd is deer", function()
	setup("dry")
	-- round 20: every group, the climate's own first (horses and gulls live in every climate)
	ok(groupKeys():find("^cougar_lone,cougar_pair,horse_lone,horse_pair,horse_herd,eagle_lone,eagle_circling,gull_flock,"
		.. "gull_few,salmon_school,salmon_schools,deer_herd"), groupKeys())
	eq(#M.groups(), #M.GROUPS, "round 20: every group offered")
	setup("temperate")
	ok(groupKeys():find("deer_herd", 1, true))
	local other = false
	for __, g in ipairs(M.groups()) do
		local own = M.native(M.BY_KEY[g.sp], "temperate")
		ok(not (other and own), g.key .. ": the climate's own come first")
		if not own then other = true end
	end
	ok(other, "cougars, eagles and discus fish are another climate's")
	ok(not M.native(M.BY_KEY.cougar, "temperate"))
	ok(M.native(M.BY_KEY.horse, "dry") and M.native(M.BY_KEY.horse, "tropical"), "horses everywhere")
	for __, f in ipairs(M.BY_KEY.discus.files) do ok(f:find("^::/animal/cr_fish/cr_fish_0%d%.mdl$"), f) end
	setup(nil)
	eq(#M.groups(), #M.GROUPS, "unknown climate: all")
	for __, sp in ipairs(M.SPECIES) do ok(sp.file:find("^::/animal/.+%.mdl$"), sp.file) end
	for __, g in ipairs(M.GROUPS) do ok(M.BY_KEY[g.sp] ~= nil and g.min >= 1 and g.max >= g.min, g.key) end
	local r = function() return 0.999 end
	eq(M.groupSize(M.GROUPS[1], r), 12, "a herd of deer: up to 12")
	eq(M.groupSize(M.GROUPS[1], function() return 0 end), 6)
end)

test("round 17: the score is the engine's suitableAreas sum: the cougar dies on a 0.45 slope, lives on 0.2", function()
	setup("dry")
	local cougar = M.BY_KEY.cougar
	local probes = { ground = function() return 100 end, water = function() return false end, busy = function() return false end }
	local s, parts = M.score(cougar, 0, 0, probes)
	eq(s, 5, "bias 5 on flat open ground")
	eq(parts.slope, 0)
	probes.ground = function(x) return 100 + x * 0.45 end
	local s2, __, why = M.score(cougar, 0, 0, probes)
	ok(s2 < 0, "0.45: negative (round 16b let it stand there)")
	eq(why, "steep")
	eq(select(2, M.suits(cougar, 0, 0, probes)), "steep")
	probes.ground = function(x) return 100 + x * 0.2 end
	ok(M.suits(cougar, 0, 0, probes))
	-- the threshold: bias 5 / (1000 / 1.7) above 0.3
	probes.ground = function(x) return 100 + x * 0.305 end
	ok(M.suits(cougar, 0, 0, probes), "0.305 still >= 0")
	probes.ground = function(x) return 100 + x * 0.31 end
	ok(not M.suits(cougar, 0, 0, probes), "0.31 negative")
	-- civilisation, noise, height, water, shore
	probes.ground = function() return 100 end
	probes.busy = function(x, y, r, what) return what == "TOWN_BUILDING" end
	eq(select(2, M.suits(cougar, 0, 0, probes)), "roads or buildings")
	probes.busy = function() return false end
	probes.noise = function() return 70 end
	ok(not M.suits(cougar, 0, 0, probes), "70 dB: -111")
	probes.noise = nil
	probes.ground = function() return 600 end
	ok(not M.suits(cougar, 0, 0, probes), "600 m up: -125")
	probes.ground = function() return 100 end
	probes.water = function(x) return x > 10 end
	eq(select(2, M.suits(cougar, 0, 0, probes)), "shore")
	eq(select(2, M.suits(cougar, 20, 0, probes)), "water")
end)

test("round 17: fish need open water (the shore is -5000); deer stay away from our predators; birds anywhere", function()
	setup("temperate")
	local probes = { ground = function() return 0 end, water = function() return true end, busy = function() return false end }
	ok(M.suits(M.BY_KEY.salmon, 0, 0, probes))
	probes.water = function(x) return x < 10 end
	eq(select(2, M.suits(M.BY_KEY.salmon, 0, 0, probes)), "shore")
	probes.water = function() return false end
	eq(select(2, M.suits(M.BY_KEY.salmon, 0, 0, probes)), "not water")
	ok(M.suits(M.BY_KEY.gull, 0, 0, probes))
	ok(M.suits(M.BY_KEY.deer, 0, 0, probes))
	probes.predator = function() return true end
	eq(select(2, M.suits(M.BY_KEY.deer, 0, 0, probes)), "predator")
	ok(M.suits(M.BY_KEY.wolf, 0, 0, probes), "wolves don't mind")
	-- the module's own predator probe: our added wolves, not dead ones
	M.S.added = { { key = "wolf", entity = 7, x = 50, y = 0 } }
	eq(M.probes.predator(0, 0, 100), true)
	M.S.added[1].dead = true
	eq(M.probes.predator(0, 0, 100), false)
end)

test("round 17: a herd spawns close together in the view with the callback's entity tracked; remove only ours", function()
	setup("temperate")
	sel("deer_herd")
	M.S.face = 2 -- round 20: to the camera
	local n = M.add()
	ok(n >= 6 and n <= 12, "a herd: " .. n)
	local xs = {}
	local cam = api.gui.camera
	for __, c in ipairs(fk.sent) do
		if c.spawn then
			ok(c.look.x < 0, "facing the camera")
			xs[#xs + 1] = c.pos
			ok(c.pos.x > 0, "ahead of the eye")
			local sc = cam.world2Screen({ x = c.pos.x, y = c.pos.y, z = 0 })
			ok(sc.x >= 0 and sc.x <= 1600 and sc.y >= 0 and sc.y <= 900, "on the screen")
		end
	end
	eq(#xs, n)
	for i = 2, #xs do ok((xs[i].x - xs[1].x) ^ 2 + (xs[i].y - xs[1].y) ^ 2 <= 80 ^ 2, "a herd stays together") end
	for __, a in ipairs(M.S.added) do ok(a.entity ~= nil) end
	fk.now = M.VERIFY_MS + 1
	ok(M.busy())
	M.step()
	-- remove: only ours, and only those still there
	fk.animals[999] = { worldPosition = { x = 0, y = 0, z = 0 } } -- a game animal
	fk.animals[M.S.added[1].entity] = nil -- despawned by the game
	eq(M.removeAdded(), n - 1)
	ok(fk.animals[999] ~= nil, "a game animal stays")
	eq(#M.S.added, 0)
end)

test("round 20: the ray march finds the ground; a start under it or no ground is no hit", function()
	setup("dry")
	local flat = function() return 0 end
	-- from 30 m up, 45 degrees down: the ground 30 m ahead
	local d = math.sqrt(0.5)
	local x, y, t = M.march(0, 0, 30, d, 0, -d, 1000, flat, 0)
	near(x, 30, 0.5)
	near(y, 0, 1e-9)
	near(t, 30 * math.sqrt(2), 0.7)
	eq(M.march(0, 0, 30, 1, 0, 0, 1000, flat, 0), nil, "level: never down")
	eq(M.march(0, 0, -5, d, 0, -d, 1000, flat, 0), nil, "under the ground")
	eq(M.march(0, 0, 30, d, 0, -d, 1000, function() return nil end, 0), nil, "no ground")
	-- a hill in the way: the first hit
	local hill = function(hx) return (hx > 10 and hx < 14) and 40 or 0 end
	local hx = M.march(0, 0, 30, d, 0, -d, 1000, hill, 0)
	ok(hx >= 10 and hx < 14, "the hill: " .. tostring(hx))
end)

test("round 20: Distance: Close shows them bigger and nearer than Far; both on the screen near the middle", function()
	local function placeAt(dist)
		setup("temperate", { x = 0, y = 0, z = 4 }, { x = 200, y = 0, z = 0 }) -- low: close ground in the view
		sel("deer_lone")
		M.S.dist = dist
		eq(M.add(), 1)
		local c = fk.sent[1].pos
		return c.x, api.gui.camera.world2Screen({ x = c.x, y = c.y, z = 0 })
	end
	local xc, sc = placeAt(1)
	local xm = placeAt(2)
	local xf, sf = placeAt(3)
	ok(xc < xm and xm < xf, string.format("close %.0f < middle %.0f < far %.0f", xc, xm, xf))
	ok(sc.y > sf.y, "the close one lower on the screen")
	-- the on-screen height near the asked share (a deer is 2.2 m): within the grid's steps
	local ctx = M.camCtx()
	local res = M.place(M.BY_KEY.deer, 1, { dist = "middle", form = "group", face = "any" }, ctx, function() return 0.5 end, nil)
	ok(res.mid.frac > 0.04 and res.mid.frac < 0.09, "about 6 %: " .. res.mid.frac)
	-- from 30 m up the nearest ground is ~38 m out (a deer ~5 % high): Close can't be met, the nearest plays
	setup("temperate")
	sel("deer_lone")
	M.S.dist = 1
	eq(M.add(), 1)
	ok(fk.sent[1].pos.x < 60, "the nearest ground: " .. fk.sent[1].pos.x)
end)

test("round 20: formations: a line stands across the view, single file along it, spread over the width", function()
	local function spots(form)
		setup("temperate")
		sel("horse_herd")
		M.S.form = form
		M.S.dist = 3
		M.add()
		local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
		for __, c in ipairs(fk.sent) do
			if c.spawn then
				minX, maxX = math.min(minX, c.pos.x), math.max(maxX, c.pos.x)
				minY, maxY = math.min(minY, c.pos.y), math.max(maxY, c.pos.y)
			end
		end
		return maxX - minX, maxY - minY
	end
	local lx, ly = spots(2)
	ok(ly > 2 * lx, string.format("line across: %.0f wide, %.0f deep", ly, lx))
	local fx, fy = spots(3)
	ok(fx > 2 * fy, string.format("single file: %.0f deep, %.0f wide", fx, fy))
	local sx, sy = spots(4)
	ok(sy > ly, string.format("spread out wider than the line: %.0f > %.0f", sy, ly))
end)

test("round 20: never refused for the score: a cougar on noisy ground is added and the status says it may die", function()
	setup("dry")
	fk.noise = 70 -- the 2150 session: every cougar click refused with "noise 60"
	sel("cougar_pair")
	eq(M.add(), 2)
	ok(M.status:find("may die", 1, true), M.status)
	-- another climate's animal: added, with its note
	setup("dry")
	sel("deer_lone")
	eq(M.add(), 1)
	ok(M.status:find("climate", 1, true), M.status)
	-- a horse lives anywhere: nothing to say
	setup("dry")
	fk.noise = 70
	sel("horse_lone")
	eq(M.add(), 1)
	eq(M.status, nil)
end)

test("round 20: looking at the sky: no ground, nothing added, the status says why; birds show at their height", function()
	setup("temperate", { x = 0, y = 0, z = 30 }, { x = 100, y = 0, z = 200 })
	sel("deer_lone")
	eq(M.add(), 0)
	ok(M.status:find("No ground", 1, true), M.status)
	eq(#fk.sent, 0)
	-- fish: no water in the view
	setup("temperate")
	sel("salmon_school")
	eq(M.add(), 0)
	ok(M.status:find("water", 1, true), M.status)
	-- a gull flock from a level eye-level view: their flying height (50 m) on the screen
	setup("temperate", { x = 0, y = 0, z = 2 }, { x = 200, y = 0, z = 2 })
	sel("gull_few")
	ok(M.add() >= 1)
	for __, c in ipairs(fk.sent) do
		if c.spawn then
			local sc = api.gui.camera.world2Screen({ x = c.pos.x, y = c.pos.y, z = 50 })
			ok(sc.y >= 0 and sc.y <= 900, "the flying gull on the screen: " .. sc.y)
		end
	end
end)

test("round 17: the life checks log a death with its lifetime and an invalid tile once; no Invalid entity error", function()
	setup("dry")
	sel("cougar_pair")
	eq(M.add(), 2)
	local a, b = M.S.added[1], M.S.added[2]
	fk.animals[a.entity].invalidTileElapsed = 0.5
	fk.now = 1000
	M.step()
	fk.animals[b.entity] = nil -- gone: getComponent would raise "Invalid entity"
	fk.now = M.VERIFY_MS + 10
	M.step()
	fk.now = 5000
	M.step()
	ok(b.dead)
	ok(not a.dead)
	local gone, invalid, err = 0, 0, 0
	for __, e in ipairs(log_entries()) do
		local m = tostring(e.msg)
		if m:find("GONE after", 1, true) then gone = gone + 1 end
		if m:find("on an invalid tile", 1, true) then invalid = invalid + 1 end
		if m:find("ERROR", 1, true) then err = err + 1 end
	end
	eq(gone, 1)
	eq(invalid, 1, "once")
	eq(err, 0)
	-- an id taken by another animal far away counts as gone
	fk.animals[a.entity].worldPosition = { x = 99999, y = 0, z = 0 }
	fk.now = 7000
	M.step()
	ok(a.dead)
	ok(not M.busy(), "nothing left to watch")
end)

test("round 17: fish need water in the view; round 19: no total limit, per click at most PER_PRESS", function()
	setup("dry")
	sel("salmon_school")
	eq(M.add(), 0)
	ok(M.status ~= nil)
	fk.waterAll = true
	eq(M.add(), 1)
	setup("dry")
	sel("gull_flock")
	local total = 0
	for __ = 1, 20 do
		local n = M.add()
		ok(n >= 1 and n <= M.PER_PRESS, "per click: " .. n)
		total = total + n
	end
	eq(#M.S.added, total)
	ok(total > 64, "round 19: past round 17's 64: " .. total)
	eq(M.MAX_ADDED, nil, "no session cap")
	M.reset()
	eq(#M.S.added, 0)
end)

test("round 19: counts per species; Remove of one species leaves the others; life checks sliced", function()
	setup("dry")
	sel("gull_flock")
	local g = M.add()
	sel("cougar_pair")
	eq(M.add(), 2)
	local counts, total = M.counts()
	eq(total, g + 2)
	eq(#counts, 2)
	eq(counts[1].key, "cougar", "M.SPECIES order")
	eq(counts[1].n, 2)
	eq(counts[2].key, "gull")
	-- a death drops out of the count
	local first = M.S.added[1]
	fk.animals[first.entity] = nil
	for __ = 1, 10 do
		fk.now = fk.now + M.LIFE_MS
		M.step()
	end
	local __, t2 = M.counts()
	eq(t2, g + 1)
	-- remove only the cougars
	eq(M.removeAdded("cougar"), 2)
	local c3, t3 = M.counts()
	eq(#c3, 1)
	eq(c3[1].key, "gull")
	eq(t3, g - 1)
	-- the slice: never more than LIFE_PER_STEP checks a frame
	M.reset()
	for i = 1, 3 * M.LIFE_PER_STEP do
		M.S.added[i] = { key = "gull", entity = 5000 + i, x = 0, y = 0, t0 = 0 }
		fk.animals[5000 + i] = { worldPosition = { x = 0, y = 0, z = 0 } }
	end
	local calls = 0
	local get = api.engine.getComponent
	api.engine.getComponent = function(e, t) calls = calls + 1 return get(e, t) end
	fk.now = fk.now + M.LIFE_MS
	M.step()
	ok(calls <= M.LIFE_PER_STEP, "one slice: " .. calls)
	eq(M.S.lifeNext, M.LIFE_PER_STEP + 1)
	M.step()
	M.step()
	eq(M.S.lifeNext, 1, "through the list: a new round after LIFE_MS")
	api.engine.getComponent = get
end)

test("round 17: the Animals rows: one dropdown of the groups; round 20: Distance, Formation, Facing, Remove all, the note", function()
	setup("dry")
	local function mk(kind) return function(...) return { kind = kind, args = { ... } } end end
	local UI = { heading = mk("heading"), labelled = mk("labelled"), dropdown = mk("dropdown"), grid = mk("grid"),
		button = mk("button"), note = mk("note"), choiceGroup = mk("choice") }
	local rows = M.rows(UI)
	eq(#rows, 7, "heading, animals, distance, formation, facing, buttons, the dying note")
	eq(#rows[2].args[2].args[1], #M.GROUPS, "every group")
	eq(rows[3].args[2].kind, "choice")
	eq(#rows[3].args[2].args[1], #M.DISTANCES)
	eq(#rows[4].args[2].args[1], #M.FORMATIONS)
	eq(#rows[5].args[2].args[1], #M.FACINGS)
	eq(rows[6].args[1][2].args[1], "Remove all")
	eq(rows[7].kind, "note")
	ok(rows[7].args[1]:find("die within seconds", 1, true))
	-- a choice sets its field
	rows[4].args[2].args[4](3)
	eq(M.S.form, 3)
	M.S.form = 1
	-- round 19: the added ones listed per species, each with its Remove
	sel("gull_flock")
	M.add()
	sel("cougar_lone")
	M.add()
	rows = M.rows(UI)
	local labelledSpecies = {}
	for __, rr in ipairs(rows) do
		if rr.kind == "labelled" and rr.args[1] == "Cougars" then labelledSpecies[#labelledSpecies + 1] = rr end
	end
	eq(#labelledSpecies, 1)
	eq(labelledSpecies[1].args[2].args[1], "Remove 1")
	-- every group's tooltip within the width; another climate's says so
	for i, g in ipairs(M.groups()) do
		local tip = rows[2].args[2].args[2][i]
		for line in tip:gmatch("[^\n]+") do ok(#line <= 70, g.key .. ": " .. line) end
	end
end)
