-- Photo Mode round 13, DEV prototype: an orbit played as a game cutscene ATTACHED to an entity (user, round 12:
-- "Tours still are jerky over terrain and don't use the free camera ... Is there any way to fix?"). PLAN:
-- plans/square_photo_mode/PLAN.md "Round 13", TESTING.md CB2.
--
-- Why a cutscene: api.gui.mission.playCutscene plays a keyframe file from a mod, hides the UI root, places the
-- camera by eye position and look angles (no camera model, no terrain under a look-at point) and the engine
-- interpolates between the keys (docs/findings/environment.md "Cutscenes from a mod"; session
-- 2026-10-14_0606_session: 1361 frames, d2 max 0.72 m, rms 0.05 m: smooth). The keyframe file's data() runs in
-- a Lua state without api or the GUI state's globals, so it can't know where the subject is. The campaign's way
-- around that: keys with `attachment = { entity = <id in the file>, group = 0, lockPitch, lockRoll, lockYaw }`
-- are relative to that entity, and playCutscene's third argument maps the file's ids to live entities:
-- { [idInFile] = liveEntity } (api/tealdef/api/gui.d.tl:753-754). The live entity is always an entity with a
-- transform of its own: a vehicle's carriage (urbangames_campaign_mission_01 mission_story.tl:86-97: the Mardi
-- Gras floats, ROAD vehicles bought in a road depot, mapped to CARRIAGE_LIST.carriages[1]) or a spawned custom
-- model (urbangames_campaign_mission_08 mission_story.tl:890-897: the rocket, custom_entity_util.spawn, whose
-- transform is MODEL_INSTANCE_LIST.fatInstances[1].transf). A transport vehicle's own entity is not one: the
-- 2026-10-14_0606 run mapped road vehicle 95565 itself and the engine logged "Invalid entity for attachment"
-- (CameraAction.cpp GetTransform) every frame while the keys played at their raw offsets around the map origin.
--
-- The round 12 keys-file channel (the GUI writing a flight's keys to a file the keyframe file reads) is retired:
-- the GUI state has no io (and no dofile) in that same session.
--
-- Only with the DEV companion mod square_photo_mode_dev active (its presence marker; never uploaded): Orbit right
-- after a jump plays the attached orbit and logs "[PhotoMode] cutscene ..." lines. Nothing here runs for players.

local C = {}

C.DEV_PRESENCE = "square_photo_mode_dev::/square_photo_mode_dev_presence.lua"
C.ORBIT_FILE = "square_photo_mode::/mission/keyframes/sqpm_orbit.lua"
-- a 0.1 s still frame, played over an orbit that turned out not to be attached (C.abort; does a second
-- playCutscene replace the first? CB2 logs it)
C.STOP_FILE = "square_photo_mode::/mission/keyframes/sqpm_stop.lua"
-- the placeholder entity id the orbit file's keys are attached to (mapped to the subject at each play). Like the
-- campaign's ids (33846, 167181) a plain integer key; far above any save's entity ids (so an unmapped key never
-- lands on a real entity) and exact as a float32 (< 2^24).
C.ANCHOR = 9999999
-- the orbit the file flies (keep equal to the file's ORBIT table): radius and height (m) around the anchor, one
-- turn in `seconds`, a key every `stepS`. Round 20 (user: "orbit on subject should be slower"; 2026-10-14_2150
-- orbited a bus at 18.6-120 m/s, mean 44): 24 -> 48 s a turn (15.7 m/s around a standing subject)
C.ORBIT = { radius = 120, height = 50, seconds = 48, stepS = 1 }

local dev = nil
--- True while the DEV companion mod is active (cached per Lua state).
function C.devOn()
	if dev == nil then
		local ok, m = pcall(ug_require, C.DEV_PRESENCE)
		dev = ok and type(m) == "table"
	end
	return dev
end

--- The orbit's eye-anchor distance (m).
function C.orbitDistance()
	return math.sqrt(C.ORBIT.radius ^ 2 + C.ORBIT.height ^ 2)
end

-- Components are userdata in the game (never type-check them as tables): read fields in pcall.
local function read(comp, e, name)
	local ok, v = pcall(comp, e, name)
	if ok then return v end
	return nil
end
local function field(v, key)
	if v == nil then return nil end
	local ok, f = pcall(function() return v[key] end)
	if ok then return f end
	return nil
end
local function count(list)
	if list == nil then return 0 end
	local ok, n = pcall(function() return #list end)
	return ok and type(n) == "number" and n or 0
end
local function entityAt(list, i)
	local v = field(list, i)
	if type(v) == "number" and v >= 0 then return v end
	return nil
end

--- The entity a subject's keys attach to, or nil and why. comp(entity, componentName) returns that component
--- (api.engine.getComponent with api.type.ComponentType[name]; a userdata in the game) or nil; conOf(station)
--- optionally returns a station's construction entity. Valid anchors carry a transform of their own:
---   1. a vehicle (CARRIAGE_LIST): its middle carriage (the campaign maps carriages[1]; any carriage is one);
---   2. a carriage itself (CARRIAGE);
---   3. a model entity (MODEL_INSTANCE_LIST with a fat instance, as the campaign's rocket); for a station group
---      also its first station and that station's construction are tried (untested in game: CB2 logs it).
--- Returns anchor, how (text for the log).
function C.anchorFor(entity, comp, conOf)
	if type(entity) ~= "number" or entity < 0 then return nil, "no entity" end
	local cl = read(comp, entity, "CARRIAGE_LIST")
	local cars = field(cl, "carriages")
	local n = count(cars)
	if n > 0 then
		local i = math.floor((n + 1) / 2)
		local car = entityAt(cars, i) or entityAt(cars, 1)
		if car ~= nil then return car, string.format("carriage %d of %d", i, n) end
	end
	if read(comp, entity, "CARRIAGE") ~= nil then return entity, "a carriage" end
	local tried = { entity }
	local sg = read(comp, entity, "STATION_GROUP")
	local st = entityAt(field(sg, "stations"), 1)
	if st ~= nil then
		tried[#tried + 1] = st
		if type(conOf) == "function" then
			local okC, con = pcall(conOf, st)
			if okC and type(con) == "number" and con >= 0 then tried[#tried + 1] = con end
		end
	end
	for __, e in ipairs(tried) do
		local mil = read(comp, e, "MODEL_INSTANCE_LIST")
		local fat = count(field(mil, "fatInstances"))
		if fat > 0 then
			return e, string.format("model entity %d (%d instances)%s", e, fat, e ~= entity and " of the station" or "")
		end
	end
	return nil, string.format("no carriage or model transform (CARRIAGE_LIST %s, tried %s)",
		cl == nil and "none" or ("with " .. n .. " carriages"), table.concat(tried, ","))
end

--- The entity map playCutscene takes: the file's placeholder id -> the live anchor.
function C.entityMap(anchor)
	return { [C.ANCHOR] = anchor }
end

--- Whether a played orbit is attached, from the eye-anchor distance d (m): "attached" near the orbit's own
--- distance, "detached" far beyond it (the keys at their raw offsets around the map origin), else "unsure".
function C.attachVerdict(d)
	if type(d) ~= "number" or d ~= d then return "unsure" end
	local want = C.orbitDistance()
	if d <= want * 1.5 + 20 then return "attached" end
	if d >= want * 3 + 100 then return "detached" end
	return "unsure"
end

--- Plays the attached orbit around `anchor` (a live entity with a transform). Returns ok, text.
function C.playOrbit(anchor)
	if type(anchor) ~= "number" then return false, "no anchor" end
	pcall(function() api.gui.fireReactEvent("disableToolActions", true) end)
	local ok, err = pcall(function() api.gui.mission.playCutscene(C.ORBIT_FILE, true, C.entityMap(anchor)) end)
	if not ok then
		pcall(function() api.gui.fireReactEvent("disableToolActions", false) end)
		return false, "playCutscene: " .. tostring(err)
	end
	return true, "anchor " .. tostring(anchor)
end

--- Plays the 0.1 s stop file over a running cutscene (no api stops one). Returns ok, text.
function C.abort()
	local ok, err = pcall(function() api.gui.mission.playCutscene(C.STOP_FILE, true, nil) end)
	return ok, ok and "stop file played" or ("playCutscene: " .. tostring(err))
end

--- Tool actions back after the cutscene.
function C.finish()
	pcall(function() api.gui.fireReactEvent("disableToolActions", false) end)
end

function C.playing()
	local ok, v = pcall(function() return api.gui.mission.isCutscenePlaying() end)
	return ok and v == true
end

--- The cutscene's own clock (s), nil when unreadable.
function C.elapsed()
	local ok, v = pcall(function() return api.gui.mission.getCutsceneElapsedTime() end)
	if ok and type(v) == "number" and v == v then return v end
	return nil
end

---------------------------------------------------------------------------
-- Round 15 DEV: the cutscene aerial (user: "Is there no way to move the camera programmatically while in free
-- camera mode?" -> no (PLAN.md "Round 15" item 3); the one smooth, terrain-free camera a mod can drive is a
-- cutscene). A keyframe file is static and the GUI can't write one (no io), so the entity map is the data
-- channel: the file's K keys are each attached to their OWN placeholder id (FLY.anchorBase + i) at a fixed offset
-- (FLY.height straight up: the same in any entity frame), and the GUI maps each placeholder to a real entity near
-- the i-th waypoint of a straight line across the map. So the keys land where the GUI chose, and the engine's
-- spline flies between them. The file can't know the line's heading, so there is one file per heading
-- (FLY.headings, 45 degrees apart; round 16: and per turn, sqpm_fly_<h>_<t>.lua in the DEV mod, identical
-- but for their first line), and it can't know the legs' lengths, so its keys' speed is FLY.leg / FLY.legS and the
-- GUI picks every anchor one leg (+- FLY.searchR) on from the last one. Open in game (TESTING.md CD4): whether
-- keys attached to DIFFERENT entities interpolate smoothly (the campaign only cuts between them), whether trees /
-- buildings / station parts resolve (`Invalid entity for attachment`), whether a second playCutscene replaces a
-- running one (the chain), and the pace when real legs differ from FLY.leg.
-- Round 16 (the user's round 15 run: "Aerials always shows the same place", a screenshot at the map edge looking
-- out over the void; PLAN.md "Round 16 camera"): a flight can turn (one file per heading AND turn, the keys'
-- heading going from h to h + t x 45 degrees, the legs along it), every anchor keeps its picture on the map
-- (C.viewInside: the ground FLY.reach m out across the frame's width), the first flight goes over a place of
-- interest not shown lately (C.chooseStart), the next ones go on from the last anchor turning away from the edge
-- and towards places not shown lately (C.chooseNext), and when no turn fits the chain cuts to a new area.

C.FLY = { keys = 6, leg = 600, legS = 15, height = 250, pitch = -0.35, headings = 8, anchorBase = 9999900,
	searchR = 150, chain = 4, leadS = 0.5,
	-- round 16: turn t (-turns .. turns, in 45-degree steps over one flight; + = counter-clockwise) and the view's
	-- reach past the eye kept inside the map (C.viewInside)
	turns = 2, reach = 2500, reachShare = 0.3, edgeM = 300, fanHalf = 0.7, startTries = 10, planTries = 6 }
-- Round 16: one file per heading h and turn t: sqpm_fly_<h>_<t + turns>.lua (0 .. 4: two left .. two right).
C.FLY_FILE = "square_photo_mode_dev::/mission/keyframes/sqpm_fly_%d_%d.lua"

local TWO_PI = 2 * math.pi
local STEP = TWO_PI / C.FLY.headings

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

--- The world heading (rad, +x = 0, counter-clockwise: the keys' `angle`) of heading index h.
function C.flyHeading(h)
	return (h % C.FLY.headings) * STEP
end

--- The heading index nearest to a look heading (rad).
function C.flyIndex(angle)
	if not finite(angle) then return 0 end
	return math.floor(angle / STEP + 0.5) % C.FLY.headings
end

local function turnOf(t)
	t = math.floor(tonumber(t) or 0)
	return math.max(-C.FLY.turns, math.min(C.FLY.turns, t))
end

--- The file of heading h turning t (0: straight).
function C.flyFile(h, t)
	return string.format(C.FLY_FILE, h % C.FLY.headings, turnOf(t) + C.FLY.turns)
end

--- Round 16: key i's look heading (rad, unwrapped) in the file of heading h turning t: from h to h + t (45-degree
--- steps) evenly over the keys, so a chained flight starts on the last one's end heading.
function C.keyAngle(h, t, i)
	return ((h % C.FLY.headings) + turnOf(t) * (i - 1) / (C.FLY.keys - 1)) * STEP
end

--- Round 16: the direction of leg i (anchor i -> i + 1): the mean of its two keys' headings.
function C.legAngle(h, t, i)
	return ((h % C.FLY.headings) + turnOf(t) * (i - 0.5) / (C.FLY.keys - 1)) * STEP
end

--- The heading index a flight ends on.
function C.endHeading(h, t)
	return (h + turnOf(t)) % C.FLY.headings
end

--- Seconds one flight file plays.
function C.flyDuration()
	return (C.FLY.keys - 1) * C.FLY.legS
end

--- Round 16: how far past the eye (m) the picture is kept inside the map: FLY.reach, at most reachShare of the
--- map's smaller side (a small map keeps room to fly).
function C.reachFor(bounds)
	if bounds == nil then return C.FLY.reach end
	local side = math.min(bounds[3] - bounds[1], bounds[4] - bounds[2])
	return math.max(0, math.min(C.FLY.reach, C.FLY.reachShare * side))
end

local function inside(bounds, x, y, margin)
	if bounds == nil then return true end
	return x >= bounds[1] + margin and x <= bounds[3] - margin and y >= bounds[2] + margin and y <= bounds[4] - margin
end

--- Round 16 (user screenshot: the camera at the map edge looking out over the void): true when an eye at (x, y)
--- looking along heading a keeps its picture on the map: the eye FLY.edgeM inside, and the ground `reach` m out
--- along five rays across the frame's width (+- FLY.fanHalf, about the half width of fovY 0.8 at 16:9) inside.
--- The keys look 20 degrees down, the frame's top near the horizon: what lies past `reach` is far in the haze.
function C.viewInside(bounds, x, y, a, reach)
	if bounds == nil then return true end
	if not (finite(x) and finite(y) and finite(a)) then return false end
	if not inside(bounds, x, y, C.FLY.edgeM) then return false end
	local R = tonumber(reach) or C.FLY.reach
	for k = -2, 2 do
		local r = a + k * C.FLY.fanHalf / 2
		if not inside(bounds, x + math.cos(r) * R, y + math.sin(r) * R, 0) then return false end
	end
	return true
end

--- Round 16: the ideal waypoints (no anchors yet) of a flight from (x0, y0), heading h turning t: { {x, y}, ... }.
function C.flyRoute(x0, y0, h, t)
	local out = { { x = x0, y = y0 } }
	for i = 1, C.FLY.keys - 1 do
		local a = C.legAngle(h, t, i)
		local p = out[i]
		out[i + 1] = { x = p.x + math.cos(a) * C.FLY.leg, y = p.y + math.sin(a) * C.FLY.leg }
	end
	return out
end

--- Round 16: true when every waypoint of that route keeps its view on the map, with room for an anchor up to
--- FLY.searchR off it (a cheap check before any octree search). The first key that fails, else nil.
function C.routeInside(bounds, x0, y0, h, t, reach)
	if bounds == nil then return true end
	for i, p in ipairs(C.flyRoute(x0, y0, h, t)) do
		if not C.viewInside(bounds, p.x, p.y, C.keyAngle(h, t, i), (reach or C.FLY.reach) + C.FLY.searchR) then
			return false, i
		end
	end
	return true
end

--- Plans one flight from (x0, y0) along heading index h turning t (round 16; nil: straight): anchor i is the
--- candidate nearest to one leg on from anchor i - 1 along leg i - 1's direction (the first: nearest to the
--- start), no entity twice, and every anchor keeps its view on the map (C.viewInside with `reach`, nil:
--- C.reachFor(bounds)). find(x, y, r) returns candidates { entity, x, y, z } within r (already valid anchors).
--- bounds = { minX, minY, maxX, maxY } (pm_world mapBounds; nil: none).
--- Returns plan { h, t, angle, anchors, legs, off } or nil, why. legs[i]: the xy distance anchor i -> i + 1;
--- off[i]: how far anchor i lies from its waypoint.
function C.planFly(x0, y0, h, find, bounds, t, reach)
	local F = C.FLY
	t = turnOf(t)
	reach = reach or C.reachFor(bounds)
	local anchors, legs, off, used = {}, {}, {}, {}
	local px, py = x0, y0
	for i = 1, F.keys do
		if i > 1 then
			local last = anchors[i - 1]
			local a = C.legAngle(h, t, i - 1)
			px, py = last.x + math.cos(a) * F.leg, last.y + math.sin(a) * F.leg
		end
		if not C.viewInside(bounds, px, py, C.keyAngle(h, t, i), reach) then
			return nil, string.format("waypoint %d off the map (or its view: %.0f m)", i, reach)
		end
		local okF, cands = pcall(find, px, py, F.searchR)
		if not okF or type(cands) ~= "table" then return nil, "search failed: " .. tostring(cands) end
		local best, bestD = nil, math.huge
		for __, c in ipairs(cands) do
			if type(c) == "table" and type(c.x) == "number" and type(c.y) == "number" and not used[c.entity]
				and C.viewInside(bounds, c.x, c.y, C.keyAngle(h, t, i), reach) then
				local d = (c.x - px) ^ 2 + (c.y - py) ^ 2
				if d < bestD then best, bestD = c, d end
			end
		end
		if best == nil then return nil, string.format("no anchor near waypoint %d (%.0f,%.0f)", i, px, py) end
		used[best.entity] = true
		anchors[i] = best
		off[i] = math.sqrt(bestD)
		if i > 1 then
			local b = anchors[i - 1]
			legs[i - 1] = math.sqrt((best.x - b.x) ^ 2 + (best.y - b.y) ^ 2)
		end
	end
	return { h = h % F.headings, t = t, angle = C.flyHeading(h), anchors = anchors, legs = legs, off = off }
end

--- The middle of a planned flight (between its middle anchors).
function C.flyMiddle(plan)
	local n = #plan.anchors
	local a, b = plan.anchors[math.floor((n + 1) / 2)], plan.anchors[math.floor(n / 2) + 1]
	return (a.x + b.x) / 2, (a.y + b.y) / 2
end

-- a random order of 1..n (rnd 0..1)
local function shuffled(n, rnd)
	local o = {}
	for i = 1, n do o[i] = i end
	for i = n, 2, -1 do
		local j = math.min(i, math.floor(rnd() * i) + 1)
		o[i], o[j] = o[j], o[i]
	end
	return o
end

--- Round 16 (user: "Now Aerials always shows the same place"): a flight over a place of interest. interests:
--- { { x, y, w, why }, ... } (pm_world flightCandidates: towns, stations, industries, rivers, water, hills, rail);
--- recent(x, y): true for an area shown lately (pm_flight nearRecent; skipped while others are left). Tries up to
--- FLY.startTries interests in a random order weighted by w, each with the 8 headings in a random order and a
--- random turn of -1 / 0 / 1, the interest in the flight's middle; the route's view checked first (no search),
--- at most FLY.planTries plans searched. Without interests: random points of the map.
--- Returns plan (with plan.interest) or nil, why; tried: "n interests, m routes, k plans".
function C.chooseStart(interests, find, bounds, rnd, recent, reach)
	rnd = rnd or math.random
	reach = reach or C.reachFor(bounds)
	local pool, fresh = {}, {}
	for __, c in ipairs(interests or {}) do
		if type(c) == "table" and finite(c.x) and finite(c.y) then
			pool[#pool + 1] = c
			if not (recent and recent(c.x, c.y)) then fresh[#fresh + 1] = c end
		end
	end
	if #fresh > 0 then pool = fresh end
	if #pool == 0 and bounds ~= nil then
		for __ = 1, C.FLY.startTries do
			pool[#pool + 1] = { x = bounds[1] + (bounds[3] - bounds[1]) * (0.2 + 0.6 * rnd()),
				y = bounds[2] + (bounds[4] - bounds[2]) * (0.2 + 0.6 * rnd()), w = 1, why = "random point" }
		end
	end
	-- weighted random order: w x (0.5 .. 1.5)
	local keyed = {}
	for i, c in ipairs(pool) do keyed[i] = { c = c, k = (tonumber(c.w) or 1) * (0.5 + rnd()) } end
	table.sort(keyed, function(a, b) return a.k > b.k end)
	local routes, plans, last = 0, 0, "no place of interest"
	for n = 1, math.min(#keyed, C.FLY.startTries) do
		local c = keyed[n].c
		local h0 = math.floor(rnd() * C.FLY.headings)
		local t = math.floor(rnd() * 3) - 1
		for k = 0, C.FLY.headings - 1 do
			local h = (h0 + k) % C.FLY.headings
			-- the start so that the interest lies in the flight's middle
			local r = C.flyRoute(0, 0, h, t)
			local mid = math.floor((#r + 1) / 2)
			local mx, my = (r[mid].x + r[mid + 1].x) / 2, (r[mid].y + r[mid + 1].y) / 2
			local x0, y0 = c.x - mx, c.y - my
			routes = routes + 1
			if C.routeInside(bounds, x0, y0, h, t, reach) then
				plans = plans + 1
				local plan, why = C.planFly(x0, y0, h, find, bounds, t, reach)
				if plan ~= nil then
					plan.interest = c
					return plan, string.format("%d interests, %d routes, %d plans", n, routes, plans)
				end
				last = why
				if plans >= C.FLY.planTries then
					return nil, string.format("%s (%d interests, %d routes, %d plans)", tostring(last), n, routes, plans)
				end
			else
				last = "every route's view leaves the map"
			end
		end
	end
	return nil, string.format("%s (%d routes, %d plans)", tostring(last), routes, plans)
end

--- Round 16: the next flight of a chain, from the last anchor on the last flight's end heading (no turn at the
--- hand-over: the next file's first key is the last one's end), turning t' = 0, +-1, +-2: the turns whose route
--- keeps its view on the map, scored by a place of interest near the route's end or middle that wasn't shown
--- lately, a little randomness and a gentler turn. nil, why when none fits (the map edge ahead and on both
--- sides, or no anchors): the caller cuts to a new area.
function C.chooseNext(prev, interests, find, bounds, rnd, recent, reach)
	rnd = rnd or math.random
	reach = reach or C.reachFor(bounds)
	local last = prev.anchors[#prev.anchors]
	local h = C.endHeading(prev.h, prev.t or 0)
	local opts = {}
	for t = -C.FLY.turns, C.FLY.turns do
		if C.routeInside(bounds, last.x, last.y, h, t, reach) then
			local r = C.flyRoute(last.x, last.y, h, t)
			local ex, ey = r[#r].x, r[#r].y
			local mx, my = r[3].x, r[3].y
			local bonus = 0
			for __, c in ipairs(interests or {}) do
				if type(c) == "table" and finite(c.x) and finite(c.y) and not (recent and recent(c.x, c.y)) then
					local d = math.min((c.x - ex) ^ 2 + (c.y - ey) ^ 2, (c.x - mx) ^ 2 + (c.y - my) ^ 2)
					if d < 1200 * 1200 then bonus = math.max(bonus, 1.5 * (tonumber(c.w) or 1) / 2) end
				end
			end
			local score = bonus + rnd() - 0.3 * math.abs(t) - ((recent and recent(ex, ey)) and 1 or 0)
			opts[#opts + 1] = { t = t, score = score }
		end
	end
	if #opts == 0 then return nil, "the map edge ahead: no turn keeps the view on the map" end
	table.sort(opts, function(a, b) return a.score > b.score end)
	local why
	for i = 1, math.min(#opts, C.FLY.planTries) do
		local plan, w = C.planFly(last.x, last.y, h, find, bounds, opts[i].t, reach)
		if plan ~= nil then return plan end
		why = w
	end
	return nil, tostring(why)
end

--- The entity map of a planned flight: { [anchorBase + i - 1] = anchor i's entity }.
function C.flyMap(plan)
	local m = {}
	for i, an in ipairs(plan.anchors) do m[C.FLY.anchorBase + i - 1] = an.entity end
	return m
end

--- Where the eye should be at time t (s) of a flight: straight above the anchors, linear between them (the
--- engine's spline rounds this off; for the log's "off the plan" only).
function C.flyEyeAt(plan, t)
	local F = C.FLY
	local n = #plan.anchors
	local u = math.max(0, math.min(t / F.legS, n - 1))
	local i = math.min(math.floor(u) + 1, n - 1)
	local f = u - (i - 1)
	local a, b = plan.anchors[i], plan.anchors[i + 1]
	return a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, (a.z or 0) + ((b.z or 0) - (a.z or 0)) * f + F.height
end

--- "legs a-b m (the file's L), anchors off their waypoints up to c m"
function C.flyText(plan)
	local lo, hi, offMax = math.huge, 0, 0
	for __, l in ipairs(plan.legs) do lo, hi = math.min(lo, l), math.max(hi, l) end
	for __, o in ipairs(plan.off) do offMax = math.max(offMax, o) end
	return string.format("legs %.0f-%.0f m (the file's %d m, pace %.0f-%.0f m/s against its %.0f), anchors up to %.0f m "
		.. "off their waypoints", lo, hi, C.FLY.leg, lo / C.FLY.legS, hi / C.FLY.legS, C.FLY.leg / C.FLY.legS, offMax)
end

--- Plays flight `plan` (no tool actions switch: Photo Mode's world lock covers the map, round 15). ok, text.
function C.playFly(plan)
	local file = C.flyFile(plan.h, plan.t or 0)
	local ok, err = pcall(function() api.gui.mission.playCutscene(file, true, C.flyMap(plan)) end)
	if not ok then return false, "playCutscene: " .. tostring(err) end
	return true, file
end

return C
