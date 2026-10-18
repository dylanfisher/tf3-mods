-- gui/pm_cutscene.lua (Photo Mode round 13 DEV prototype): the orbit keyframe file (keys attached to a placeholder
-- entity), the anchor a subject maps to (a carriage or a model entity, components read as userdata), the
-- entityToEntityMap handed to playCutscene, the attachment verdict and the stop file.

local C

before_each(function()
	reset_modules()
	C = ug_require "square_photo_mode::/photo_mode/gui/pm_cutscene.lua"
end)

-- Round 13 DEV: the orbit attached to an entity (no file channel)

local function loadOrbit(env)
	local f = assert(io.open("mods/square_photo_mode/content/mission/keyframes/en/sqpm_orbit.lua", "r"))
	local text = f:read("*a")
	f:close()
	local chunk = assert(load(text, "@sqpm_orbit.lua", "t", env))
	return chunk(), text
end

test("round 13: the orbit file: keys attached to the placeholder entity, a circle around it, looking at it", function()
	local said = {}
	local data, text = loadOrbit(setmetatable({ print = function(m) said[#said + 1] = m end }, { __index = _G }))
	local r = data()
	local O = C.ORBIT
	eq(#r.camera, O.seconds / O.stepS + 1)
	local want = math.sqrt(O.radius ^ 2 + O.height ^ 2)
	for i, k in ipairs(r.camera) do
		eq(k.attachment.entity, C.ANCHOR, "attached to the anchor the GUI maps")
		eq(k.attachment.group, 0)
		local x, y, z = k.position[1], k.position[2], k.position[3]
		near(math.sqrt(x * x + y * y + z * z), want, 1e-6, "on the orbit")
		-- the look (angle along +x at 0, pitch negative = down) points at the anchor
		local lx, ly = math.cos(k.angle) * math.cos(k.pitch), math.sin(k.angle) * math.cos(k.pitch)
		local lz = math.sin(k.pitch)
		local dot = (lx * -x + ly * -y + lz * -z) / want
		near(dot, 1, 1e-6, "looks at the anchor (key " .. i .. ")")
		eq(k.time, (i - 1) * O.stepS)
	end
	ok(said[1]:find("(math)", 1, true), said[1])
	-- the file's ORBIT and ANCHOR are the GUI's
	ok(text:find(string.format("local ORBIT = { radius = %d, height = %d, seconds = %d, stepS = %d }", O.radius,
		O.height, O.seconds, O.stepS), 1, true), "keep ORBIT equal to C.ORBIT")
	ok(text:find("local ANCHOR = " .. C.ANCHOR, 1, true))
	local g = assert(io.open("mods/square_photo_mode/content/mission/keyframes/sqpm_orbit.lua", "r"))
	eq(g:read("*a"), text, "keep both copies identical")
	g:close()
	-- a state without math: the fixed square, never raises
	local data2 = loadOrbit(setmetatable({ print = function() end, math = false }, { __index = _G }))
	eq(#data2().camera, 5)
end)

-- Round 14: the pulse (session 2026-10-14_0633_session). The engine moves the camera along its spline at the
-- keys' `speed` (m/s); a segment of length L in T s whose ends say v0, v1 runs, as a cubic in distance (the
-- simplest model with those end speeds), at s'(u) = 6 L u (1 - u) / T + v0 (1 - 4u + 3u^2) + v1 (3u^2 - 2u).
local function segSpeeds(L, T, v0, v1)
	local lo, hi = math.huge, 0
	for i = 0, 100 do
		local u = i / 100
		local v = 6 * L * u * (1 - u) / T + v0 * (1 - 4 * u + 3 * u * u) + v1 * (3 * u * u - 2 * u)
		lo, hi = math.min(lo, v), math.max(hi, v)
	end
	return lo, hi
end

test("round 14: the orbit's key speeds are the game's Auto Set Speed: even along the orbit (no pulse); locked to the anchor", function()
	local data = loadOrbit(setmetatable({ print = function() end }, { __index = _G }))
	local keys = data().camera
	local O = C.ORBIT
	local chord = 2 * O.radius * math.sin(math.pi * O.stepS / O.seconds)
	for i, k in ipairs(keys) do
		near(k.speed, chord / O.stepS, 1e-9, "key " .. i .. ": chord over time (round 20: 15.7 m/s)")
		eq(k.attachment.lockYaw, false, "round 17: the look turns with the anchor"); eq(k.attachment.lockPitch, true); eq(k.attachment.lockRoll, true)
	end
	-- the segment's speed stays within 1 % of its mean with these keys; round 13's speed 1 everywhere swung
	-- between a crawl and ~1.5 x the mean every second
	local lo, hi = segSpeeds(chord, O.stepS, keys[1].speed, keys[2].speed)
	ok(hi / lo < 1.01, string.format("even: %.2f-%.2f m/s", lo, hi))
	local lo13, hi13 = segSpeeds(chord, O.stepS, 1, 1)
	ok(lo13 <= 1.0001 and hi13 > 1.4 * chord / O.stepS, string.format("round 13: %.2f-%.2f m/s", lo13, hi13))
end)

test("round 14: Auto Set Speed matches the campaign's keys (first / last: their segment, between: the mean, a cut: its side)", function()
	-- the file's rule on keys shaped like MISSION_07_CUTSCENE_BONUS_COMPLETE (39.531, 38.787, 38.042) and
	-- MISSION_01_CUTSCENE_OUTRO_A (a 15 s segment then a cut)
	local f = assert(io.open("mods/square_photo_mode/content/mission/keyframes/en/sqpm_orbit.lua", "r"))
	local text = f:read("*a")
	f:close()
	local src = text:match("(local function autoSpeed%(keys%).-\nend)\n")
	ok(src ~= nil, "autoSpeed in the file")
	local autoSpeed = assert(load(src .. "\nreturn autoSpeed", "autoSpeed", "t", _G))()
	local function k(t, x) return { time = t, position = { x, 0, 0 } } end
	local ks = autoSpeed({ k(0, 0), k(1, 39.531), k(2, 39.531 + 38.042) })
	near(ks[1].speed, 39.531, 1e-9); near(ks[2].speed, (39.531 + 38.042) / 2, 1e-9); near(ks[3].speed, 38.042, 1e-9)
	ks = autoSpeed({ k(0, 0), k(15, 14.034655), k(15, 500), k(25, 504.15) })
	near(ks[1].speed, 0.935644, 1e-6); near(ks[2].speed, 0.935644, 1e-6, "the end of a segment before a cut")
	near(ks[3].speed, 0.415, 1e-9); near(ks[4].speed, 0.415, 1e-9)
end)

-- A component as the game hands it: not a plain table to the code (fields through metamethods only).
local function ud(fields)
	return setmetatable({}, { __index = fields, __len = function() return #fields end })
end
local function udList(list)
	return setmetatable({}, { __index = function(_, i) return list[i] end, __len = function() return #list end })
end
local function comps(byEntity)
	return function(e, name)
		local c = byEntity[e]
		return c and c[name] or nil
	end
end

test("round 13: the anchor: a vehicle's middle carriage, a carriage, a model entity; never the vehicle itself", function()
	-- a road vehicle (one carriage) as the 2026-10-14_0606 run had it: the carriage, not 95565
	local get = comps({ [95565] = { CARRIAGE_LIST = ud({ carriages = udList({ 95570 }) }), TRANSPORT_VEHICLE = ud({}) } })
	local a, how = C.anchorFor(95565, get)
	eq(a, 95570, how)
	ok(how:find("carriage 1 of 1", 1, true), how)
	-- a train: the middle carriage
	eq(C.anchorFor(7, comps({ [7] = { CARRIAGE_LIST = ud({ carriages = udList({ 71, 72, 73, 74, 75 }) }) } })), 73)
	eq(C.anchorFor(7, comps({ [7] = { CARRIAGE_LIST = { carriages = { 71, 72 } } } })), 71)
	-- a carriage itself
	eq(C.anchorFor(72, comps({ [72] = { CARRIAGE = ud({ reversed = false }) } })), 72)
	-- a model entity (the campaign's rocket: MODEL_INSTANCE_LIST.fatInstances)
	eq(C.anchorFor(300, comps({ [300] = { MODEL_INSTANCE_LIST = ud({ fatInstances = udList({ {} }) }) } })), 300)
	-- a station group: its station's construction when that has the transform
	local st = comps({ [40] = { STATION_GROUP = ud({ stations = udList({ 41 }) }) },
		[42] = { MODEL_INSTANCE_LIST = ud({ fatInstances = udList({ {}, {} }) }) } })
	local sa, shi = C.anchorFor(40, st, function(s) return s == 41 and 42 or -1 end)
	eq(sa, 42, shi)
	-- nothing with a transform: nil and why (the driver plays the normal orbit)
	local na, why = C.anchorFor(95565, comps({ [95565] = { TRANSPORT_VEHICLE = ud({}) } }))
	eq(na, nil)
	ok(why:find("no carriage or model transform", 1, true), why)
	eq(C.anchorFor(5, comps({ [5] = { CARRIAGE_LIST = ud({ carriages = udList({}) }) } })), nil, "an empty list")
	eq(C.anchorFor(77, function() error("no component") end), nil)
	eq(C.anchorFor(nil, function() end), nil)
	eq(C.anchorFor(-1, function() end), nil)
end)

test("round 13: the entityToEntityMap: { [the file's placeholder id] = the live anchor }, integer keys", function()
	local m = C.entityMap(95570)
	local n = 0
	for k, v in pairs(m) do
		n = n + 1
		eq(k, C.ANCHOR); eq(v, 95570)
		eq(k, math.floor(k), "an integer id like the campaign's (33846, 167181)")
	end
	eq(n, 1)
	ok(C.ANCHOR > 1 and C.ANCHOR < 2 ^ 24, "not a list index, far above save ids, exact as a float32")
	local played, events = nil, {}
	set_global("api", { gui = {
		mission = { playCutscene = function(file, lang, map) played = { file = file, lang = lang, map = map } end },
		fireReactEvent = function(name, v) events[#events + 1] = name .. "=" .. tostring(v) end,
	} })
	local okP = C.playOrbit(95570)
	eq(okP, true)
	eq(played.file, C.ORBIT_FILE); eq(played.lang, true)
	eq(played.map[C.ANCHOR], 95570)
	eq(played.map[1], nil, "never a list")
	eq(events[1], "disableToolActions=true")
	C.finish()
	eq(events[2], "disableToolActions=false")
	-- the stop file over it, no map
	local okA = C.abort()
	eq(okA, true)
	eq(played.file, C.STOP_FILE); eq(played.map, nil)
end)

test("round 13: the attachment verdict from the eye-subject distance", function()
	local want = C.orbitDistance()
	near(want, 130, 1e-9)
	eq(C.attachVerdict(want), "attached")
	eq(C.attachVerdict(want * 1.2), "attached")
	eq(C.attachVerdict(912.4), "detached", "the 2026-10-14_0606 run's first frame")
	eq(C.attachVerdict(300), "unsure")
	eq(C.attachVerdict(0 / 0), "unsure")
	eq(C.attachVerdict(nil), "unsure")
end)

test("round 13: the stop file: a 0.1 s still frame, unattached; both copies equal", function()
	local f = assert(io.open("mods/square_photo_mode/content/mission/keyframes/en/sqpm_stop.lua", "r"))
	local text = f:read("*a")
	f:close()
	local data = assert(load(text, "@sqpm_stop.lua", "t", setmetatable({}, { __index = _G })))()
	local r = data()
	eq(#r.camera, 2)
	eq(r.camera[2].time, 0.1)
	for __, k in ipairs(r.camera) do eq(k.attachment, nil) end
	local g = assert(io.open("mods/square_photo_mode/content/mission/keyframes/sqpm_stop.lua", "r"))
	eq(g:read("*a"), text, "keep both copies identical")
	g:close()
end)

---------------------------------------------------------------------------
-- Round 15 DEV: the cutscene aerial (keys attached to one placeholder each, one file per heading, in the DEV mod)

local FLY_DIR = "mods/square_photo_mode_dev/content/mission/keyframes/"

local function readFile(path)
	local f = assert(io.open(path, "r"))
	local t = f:read("*a")
	f:close()
	return t
end

test("round 15 / 16: the fly files: one per heading and turn, identical but for line 1, both copies equal; the keys each attached to their own placeholder above it, turning evenly", function()
	local F = C.FLY
	local body
	for h = 0, F.headings - 1 do
		for t = -F.turns, F.turns do
			local name = "sqpm_fly_" .. h .. "_" .. (t + F.turns) .. ".lua"
			local text = readFile(FLY_DIR .. "en/" .. name)
			eq(readFile(FLY_DIR .. name), text, "keep both copies identical (" .. name .. ")")
			local first, rest = text:match("^([^\n]*)\n(.*)$")
			eq(first, "local HEADING, TURN = " .. h .. ", " .. t)
			if body == nil then body = rest else eq(rest, body, "the same body for every file") end
			ok(text:find(string.format("local FLY = { keys = %d, leg = %d, legS = %d, height = %d, pitch = %s, headings = %d, anchorBase = %d }",
				F.keys, F.leg, F.legS, F.height, tostring(F.pitch), F.headings, F.anchorBase), 1, true), "keep FLY equal to C.FLY")
			local said = {}
			local env = setmetatable({ print = function(m) said[#said + 1] = m end, math = false }, { __index = _G })
			local data = assert(load(text, "@" .. name, "t", env))()
			local r = data()
			eq(#r.camera, F.keys)
			for i, k in ipairs(r.camera) do
				eq(k.attachment.entity, F.anchorBase + i - 1, "key " .. i .. ": its own placeholder")
				eq(k.attachment.lockYaw, true)
				eq(k.position, { 0, 0, F.height }, "straight above it (the same in any entity frame)")
				near(k.angle, C.keyAngle(h, t, i), 1e-6, "the key's heading")
				eq(k.pitch, F.pitch)
				near(k.speed, F.leg / F.legS, 1e-9)
				eq(k.time, (i - 1) * F.legS)
			end
			near(r.camera[1].angle, C.flyHeading(h), 1e-6, "starts on the file's heading")
			near(r.camera[F.keys].angle, (h + t) * math.pi / 4, 1e-6, "ends turned by t x 45 degrees (unwrapped)")
			ok(said[1]:find("heading " .. h .. " turn " .. t, 1, true), said[1])
			eq(C.flyFile(h, t), "square_photo_mode_dev::/mission/keyframes/" .. name:gsub("%.lua$", "") .. ".lua")
		end
	end
	near(C.flyDuration(), (F.keys - 1) * F.legS, 1e-9)
end)

test("round 15: the heading index: nearest of 8, wrapped, NaN safe", function()
	eq(C.flyIndex(0), 0)
	eq(C.flyIndex(math.pi / 4 + 0.3), 1)
	eq(C.flyIndex(math.pi), 4)
	eq(C.flyIndex(-math.pi / 2), 6)
	eq(C.flyIndex(2 * math.pi - 0.1), 0)
	eq(C.flyIndex(0 / 0), 0)
	near(C.flyHeading(10), math.pi / 2, 1e-9, "wrapped")
end)

-- a grid of candidate anchors every `step` m (entity id from the position)
local function grid(step, skip)
	return function(x, y, r)
		local out = {}
		for gx = math.floor((x - r) / step) * step, x + r, step do
			for gy = math.floor((y - r) / step) * step, y + r, step do
				if (gx - x) ^ 2 + (gy - y) ^ 2 <= r * r and not (skip and skip(gx, gy)) then
					out[#out + 1] = { entity = math.floor(gx * 1000 + gy + 5e6), x = gx, y = gy, z = 10 }
				end
			end
		end
		return out
	end
end

test("round 15: planFly: anchors one leg apart along the heading, the nearest candidate each, never one twice; the map", function()
	local F = C.FLY
	local plan = C.planFly(0, 0, 0, grid(50), { -10000, -10000, 10000, 10000 })
	ok(plan ~= nil)
	eq(#plan.anchors, F.keys)
	for i, a in ipairs(plan.anchors) do
		near(a.x, (i - 1) * F.leg, 1e-9, "on the line")
		near(a.y, 0, 1e-9)
	end
	for __, l in ipairs(plan.legs) do near(l, F.leg, 1e-9) end
	local m = C.flyMap(plan)
	for i, a in ipairs(plan.anchors) do eq(m[F.anchorBase + i - 1], a.entity) end
	ok(C.flyText(plan):find("legs 600-600 m", 1, true), C.flyText(plan))
	-- north-east: anchors near the diagonal, each leg from the last ANCHOR (no drift)
	local p2 = C.planFly(0, 0, 1, grid(170), nil)
	for __, l in ipairs(p2.legs) do ok(math.abs(l - F.leg) <= 2 * F.searchR, "leg " .. l) end
	for __, o in ipairs(p2.off) do ok(o <= F.searchR, "near its waypoint " .. o) end
	-- the eye plan: above the anchors, linear between
	local x, y, z = C.flyEyeAt(plan, F.legS * 1.5)
	near(x, 1.5 * F.leg, 1e-9); near(y, 0, 1e-9); near(z, 10 + F.height, 1e-9)
end)

test("round 15: planFly refuses: a waypoint off the map, no anchor near one, a failing search", function()
	local plan, why = C.planFly(0, 0, 0, grid(50), { -1000, -1000, 1000, 1000 })
	eq(plan, nil)
	ok(why:find("off the map", 1, true), why)
	plan, why = C.planFly(0, 0, 0, grid(50, function(gx) return gx > 1000 and gx < 1400 end), nil)
	eq(plan, nil)
	ok(why:find("no anchor near waypoint 3", 1, true), why)
	plan, why = C.planFly(0, 0, 0, function() error("octree") end, nil)
	eq(plan, nil)
	ok(why:find("search failed", 1, true), why)
	-- one candidate only: never used twice
	plan, why = C.planFly(0, 0, 0, function() return { { entity = 1, x = 0, y = 0, z = 0 } } end, nil)
	eq(plan, nil)
	ok(why:find("waypoint 2", 1, true), why)
end)

---------------------------------------------------------------------------
-- Round 16 DEV: the cutscene aerial stays on the map (user screenshot: the camera at the map edge looking out over
-- the void), turns away from the edge, and goes somewhere new each time ("Now Aerials always shows the same place")

local function lcg(seed)
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

local MAP = { -5000, -5000, 5000, 5000 }

test("round 16: the view check: the eye inside, the ground `reach` m out across the frame's width on the map", function()
	local F = C.FLY
	eq(C.reachFor(nil), F.reach)
	eq(C.reachFor(MAP), F.reach, "a 10 km map: the full reach")
	near(C.reachFor({ 0, 0, 4000, 6000 }), 0.3 * 4000, 1e-9, "a small map: a share of its smaller side")
	ok(C.viewInside(MAP, 0, 0, 0, 2500), "the middle, any heading")
	ok(not C.viewInside(MAP, 3000, 0, 0, 2500), "2 km from the east edge looking east: the void in the picture")
	ok(C.viewInside(MAP, 3000, 0, math.pi, 2500), "... looking west: fine")
	ok(not C.viewInside(MAP, 0, 4000, 0, 2500), "1 km from the north edge looking east: the frame's left side leaves")
	ok(not C.viewInside(MAP, 4800, 0, math.pi, 2500), "the eye itself too close to the edge")
	ok(not C.viewInside(MAP, 0 / 0, 0, 0, 2500), "NaN")
	ok(C.viewInside(nil, 1e9, 0, 0, 2500), "no bounds known: nothing to keep")
end)

test("round 16: a turning flight: keys turn evenly from h to h + t, legs along the mean of their keys, no view off the map", function()
	local F = C.FLY
	for t = -F.turns, F.turns do
		local plan = C.planFly(-2000, 0, 0, grid(50), MAP, t)
		ok(plan ~= nil, "t " .. t)
		eq(plan.t, t)
		near(C.keyAngle(0, t, 1), 0, 1e-12)
		near(C.keyAngle(0, t, F.keys), t * math.pi / 4, 1e-12)
		for i = 1, F.keys - 1 do
			local a, b = plan.anchors[i], plan.anchors[i + 1]
			local dir = math.atan(b.y - a.y, b.x - a.x)
			ok(math.abs(dir - C.legAngle(0, t, i)) < 0.2, string.format("leg %d along %.2f (%.2f)", i, C.legAngle(0, t, i), dir))
		end
		for i, a in ipairs(plan.anchors) do ok(C.viewInside(MAP, a.x, a.y, C.keyAngle(0, t, i), C.reachFor(MAP)), "anchor " .. i) end
	end
	eq(C.endHeading(7, 2), 1, "wrapped")
	eq(C.endHeading(0, -1), 7)
	-- straight east from the middle would end 2 km from the edge looking at it: refused ...
	local plan, why = C.planFly(0, 0, 0, grid(50), MAP, 0)
	eq(plan, nil)
	ok(why:find("off the map (or its view", 1, true), why)
	-- ... a left turn from the south-west gets by
	ok(C.routeInside(MAP, -2500, -3000, 0, 2), "a left turn keeps the view on the map")
end)

test("round 16: chooseStart: a place of interest in the flight's middle, a random heading, places shown lately skipped", function()
	local F = C.FLY
	local interests = {
		{ x = -2500, y = -2500, w = 2, why = "town" }, { x = 2000, y = 1500, w = 1, why = "station" },
		{ x = 0, y = 2500, w = 1.5, why = "water" }, { x = -1500, y = 2000, w = 2, why = "river" },
	}
	local seenHeadings, seenPlaces = {}, {}
	for seed = 1, 40 do
		local plan, info = C.chooseStart(interests, grid(50), MAP, lcg(seed * 7919), nil)
		ok(plan ~= nil, "seed " .. seed .. ": " .. tostring(info))
		seenHeadings[plan.h] = true
		seenPlaces[plan.interest.why] = true
		local mx, my = C.flyMiddle(plan)
		ok((mx - plan.interest.x) ^ 2 + (my - plan.interest.y) ^ 2 < 400 ^ 2, "the interest in the middle")
		for i, a in ipairs(plan.anchors) do
			ok(C.viewInside(MAP, a.x, a.y, C.keyAngle(plan.h, plan.t, i), C.reachFor(MAP)), "seed " .. seed .. " anchor " .. i)
		end
	end
	local nh, np = 0, 0
	for __ in pairs(seenHeadings) do nh = nh + 1 end
	for __ in pairs(seenPlaces) do np = np + 1 end
	ok(nh >= 4, "varied headings: " .. nh)
	ok(np >= 3, "the places vary (weighted by kind): " .. np)
	-- the places shown lately are skipped while others are left
	local recent = function(x, y) return x <= 0 end
	for seed = 1, 20 do
		local plan = C.chooseStart(interests, grid(50), MAP, lcg(seed), recent)
		ok(plan.interest.x > 0, "a fresh place: " .. plan.interest.why)
	end
	-- all shown lately: still a flight
	ok(C.chooseStart(interests, grid(50), MAP, lcg(3), function() return true end) ~= nil)
	-- none at all: random points of the map
	local plan, info = C.chooseStart({}, grid(50), MAP, lcg(5), nil)
	ok(plan ~= nil, tostring(info))
	eq(plan.interest.why, "random point")
	-- no anchors anywhere: nil and why, the searches capped
	local searches = 0
	plan, info = C.chooseStart(interests, function() searches = searches + 1 return {} end, MAP, lcg(1), nil)
	eq(plan, nil)
	ok(searches <= F.planTries, "at most planTries plans searched: " .. searches)
	ok(info:find("no anchor", 1, true), info)
end)

test("round 16: chooseNext: on from the last anchor on its end heading; at the edge it turns; boxed in: nil (a cut)", function()
	local F = C.FLY
	-- heading east, ending in the middle: any turn fits; the next starts on the last anchor's end heading
	local p1 = C.planFly(-4000, 0, 0, grid(50), MAP, 0)
	ok(p1 ~= nil)
	local p2 = C.chooseNext(p1, {}, grid(50), MAP, lcg(2), nil)
	ok(p2 ~= nil)
	eq(p2.h, 0, "the next file starts on the last one's end heading")
	near(p2.anchors[1].x, p1.anchors[F.keys].x, 50.1, "from the last anchor")
	-- a flight whose end heading points at the edge: the next one turns away (never straight on into the void)
	local nearEdge = { h = 0, t = 0, anchors = { { entity = 1, x = 0, y = -2600, z = 0 } } }
	for seed = 1, 20 do
		local p = C.chooseNext(nearEdge, {}, grid(50), MAP, lcg(seed), nil)
		ok(p ~= nil, "seed " .. seed)
		ok(p.t > 0, "turns left, away from the south edge's corner ... t=" .. p.t)
		for i, a in ipairs(p.anchors) do ok(C.viewInside(MAP, a.x, a.y, C.keyAngle(p.h, p.t, i), C.reachFor(MAP))) end
	end
	-- boxed in a corner looking out: no turn fits
	local corner = { h = 1, t = 0, anchors = { { entity = 1, x = 2000, y = 2000, z = 0 } } }
	local p, why = C.chooseNext(corner, {}, grid(50), MAP, lcg(1), nil)
	eq(p, nil)
	ok(why:find("map edge", 1, true), why)
	-- an interest ahead on the left pulls the turn there
	local pulled = C.chooseNext(p1, { { x = 600, y = 2300, w = 2, why = "town" } }, grid(50), MAP, function() return 0.5 end, nil)
	eq(pulled.t, 2, "towards the town")
	-- ... unless it was shown lately
	local fresh = C.chooseNext(p1, { { x = 600, y = 2300, w = 2, why = "town" } }, grid(50), MAP, function() return 0.5 end,
		function(x, y) return x == 600 end)
	eq(fresh.t, 0, "no pull from a place shown lately")
end)

test("round 16: 300 random chains on a 10 km map: no anchor's view ever leaves the map; the chain mostly goes on", function()
	local F = C.FLY
	local rnd = lcg(42)
	local flights, cuts = 0, 0
	for __ = 1, 300 do
		local plan = C.chooseStart({ { x = (rnd() - 0.5) * 8000, y = (rnd() - 0.5) * 8000, w = 1, why = "x" } }, grid(100), MAP, rnd, nil)
			or C.chooseStart({}, grid(100), MAP, rnd, nil) -- a place too near the edge for any flight: a random one
		for __ = 1, F.chain - 1 do
			if plan == nil then break end
			for i, a in ipairs(plan.anchors) do
				ok(C.viewInside(MAP, a.x, a.y, C.keyAngle(plan.h, plan.t, i), C.reachFor(MAP)), "inside")
			end
			flights = flights + 1
			local nxt = C.chooseNext(plan, {}, grid(100), MAP, rnd, nil)
			if nxt == nil then
				cuts = cuts + 1
				nxt = C.chooseStart({}, grid(100), MAP, rnd, nil)
			end
			plan = nxt
		end
	end
	ok(flights >= 850, "flights " .. flights)
	-- a 10 km map leaves a small middle once 2.5 km of view are kept: about one hand-over in three cuts to a new area
	ok(cuts < flights * 0.45, string.format("cuts %d of %d", cuts, flights))
end)
