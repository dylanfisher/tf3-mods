-- Base interchange numbers (INTERCHANGES.md Phase 7a: "compute the base interchanges' loop /
-- terminal numbers offline into the notes"). Runs the base game's own updateFns
-- (.cache/game/base/content/infrastructure/street_construction/street_constructions.script.lua)
-- with a minimal vec3 / street_util_serialized port (the base .tl modules, types stripped) and
-- prints the cloverleaf loops' smallest plan radius, length, peak and average grade and the weave,
-- and the diamond's terminal and ramp numbers. Reference only: no shipped code depends on it.
-- Skipped when .cache/game is missing (fresh clone: make docs).

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local S = geom.shapes

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local SC = here .. "../../.cache/game/base/content/infrastructure/street_construction/street_constructions.script.lua"

-- vec3 (base scripts/vec3.tl): only what street_constructions.script.lua and the util use
local vec3 = {}
local mt = {}
function vec3.new(x, y, z) return setmetatable({ x = x, y = y, z = z }, mt) end
mt.__add = function(a, b) return vec3.new(a.x + b.x, a.y + b.y, a.z + b.z) end
mt.__sub = function(a, b) return vec3.new(a.x - b.x, a.y - b.y, a.z - b.z) end
mt.__mul = function(f, v) return vec3.new(f * v.x, f * v.y, f * v.z) end
function vec3.add(a, b) return a + b end
function vec3.sub(a, b) return a - b end
function vec3.mul(f, v) return f * v end
function vec3.dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
function vec3.length(v) return math.sqrt(vec3.dot(v, v)) end
function vec3.distance(a, b) return vec3.length(a - b) end
function vec3.normalize(v) return (1.0 / vec3.length(v)) * v end
function vec3.angleUnit(a, b)
	local p = vec3.dot(a, b)
	if p < -1 then p = -1 elseif p > 1 then p = 1 end
	return math.acos(p)
end
function vec3.toArray(v) return { v.x, v.y, v.z } end

-- street_util_serialized (base scripts/construction/street_util_serialized.tl:5-71); every edge
-- is also recorded as {p0, t0, p1, t1, auto} in `log` (auto: addEdgeAutoTangents)
local log = {}
local su = {}
function su.calcScale(dist, angle)
	if angle < 0.001 then return dist end
	local scale = 1.0
	if angle >= math.pi / 2 then scale = 1.0 + (math.sqrt(2) - 1.0) * ((angle - math.pi / 2) / (math.pi / 2)) end
	return 0.5 * dist / math.cos(0.5 * math.pi - 0.5 * angle) * angle * scale
end
local function put(edges, p0, t0, p1, t1, tag0, tag1, auto)
	edges[#edges + 1] = { vec3.toArray(p0), vec3.toArray(t0), tag0 }
	edges[#edges + 1] = { vec3.toArray(p1), vec3.toArray(t1), tag1 }
	log[#log + 1] = { p0 = vec3.toArray(p0), t0 = vec3.toArray(t0), p1 = vec3.toArray(p1), t1 = vec3.toArray(t1), tag0 = tag0, tag1 = tag1, auto = auto }
end
function su.addStraightEdge(edges, p0, p1, tag0, tag1) put(edges, p0, p1 - p0, p1, p1 - p0, tag0, tag1) end
function su.addRamp(edges, p0, p1, tag0, tag1)
	local q = vec3.distance(p0, p1) * vec3.normalize(vec3.new(p1.x - p0.x, p1.y - p0.y, 0))
	put(edges, p0, q, p1, q, tag0, tag1)
end
function su.addEdge(edges, p0, p1, t0, t1, tag0, tag1) put(edges, p0, t0, p1, t1, tag0, tag1) end
function su.addEdgeAutoTangents(edges, p0, p1, t0, t1, tag0, tag1)
	local q0, q1 = vec3.normalize(t0), vec3.normalize(t1)
	local scale = su.calcScale(vec3.distance(p0, p1), vec3.angleUnit(q0, q1))
	put(edges, p0, scale * q0, p1, scale * q1, tag0, tag1, true)
end
function su.freeAllNodes(edges) local t = {}; for i = 1, #edges do t[i] = i - 1 end; return t end

local function loadBase()
	local f = io.open(SC, "r")
	if not f then return nil end
	f:close()
	local env = setmetatable({
		require = function(name)
			if name:find("vec3") then return vec3 end
			return su
		end,
	}, { __index = _ENV })
	local chunk = assert(loadfile(SC, "t", env))
	chunk()
	return env.data()
end

--- Plan-curvature radius, length, grades of a chain of edges (sampled).
local function measure(edges)
	local N = 400
	local minR, length, plan, peak = math.huge, 0, 0, 0
	for _, e in ipairs(edges) do
		local prev
		for k = 0, N do
			local s = k / N
			local p, d = S.hermite(e, s)
			-- second derivative of the cubic Hermite
			local a = {}
			for i = 1, 3 do
				a[i] = (12 * s - 6) * e.p0[i] + (6 * s - 4) * e.t0[i] + (-12 * s + 6) * e.p1[i] + (6 * s - 2) * e.t1[i]
			end
			local v2 = d[1] * d[1] + d[2] * d[2]
			local cross = math.abs(d[1] * a[2] - d[2] * a[1])
			if cross > 1e-9 then minR = math.min(minR, v2 ^ 1.5 / cross) end
			if v2 > 1e-12 then peak = math.max(peak, math.abs(d[3]) / math.sqrt(v2)) end
			if prev then
				length = length + S.dist(prev, p)
				plan = plan + math.sqrt((p[1] - prev[1]) ^ 2 + (p[2] - prev[2]) ^ 2)
			end
			prev = p
		end
	end
	local dz = math.abs(edges[#edges].p1[3] - edges[1].p0[3])
	return { minR = minR, length = length, peak = peak, avg = dz / plan, dz = dz }
end

local base = loadBase()

test("base interchanges: cloverleaf loops and diamond terminals (reference numbers)", function()
	if not base then
		print("    skipped: " .. SC .. " missing (make docs)")
		return
	end
	local LANES = { "2-lane", "3-lane" }
	local SCALES = { "small", "medium", "large" }
	local rmin, rmax = math.huge, 0
	for st = 1, 2 do
		for sc = 1, 3 do
			for k in pairs(log) do log[k] = nil end
			base.updateFnCloverleafInterchange({}, { streetType = st, scale = sc, viaduct = 0 })
			-- loops = addCurvedRamp: consecutive pairs of auto-tangent edges
			local loops = {}
			for _, e in ipairs(log) do
				if e.auto then
					local l = loops[#loops]
					if l and #l == 1 then l[2] = e else loops[#loops + 1] = { e } end
				end
			end
			eq(#loops, 4, "cloverleaf loops")
			local worst = { minR = math.huge, length = 0, peak = 0, avg = 0 }
			for _, l in ipairs(loops) do
				local m = measure(l)
				worst.minR = math.min(worst.minR, m.minR)
				worst.length = math.max(worst.length, m.length)
				worst.peak = math.max(worst.peak, m.peak)
				worst.avg = math.max(worst.avg, m.avg)
			end
			-- weave on the eastbound carriageway: the loop on joins at "we-west", the loop off leaves at "we-east"
			local xOn, xOff
			for _, e in ipairs(log) do
				if e.tag1 == "we-west" and e.auto then xOn = e.p1[1] end
				if e.tag0 == "we-east" and e.auto then xOff = e.p0[1] end
			end
			local weave = xOff - xOn
			rmin, rmax = math.min(rmin, worst.minR), math.max(rmax, worst.minR)
			print(string.format("    cloverleaf %s %s: loop min radius %.1f m, length <= %.0f m, peak grade %.1f %%, avg %.1f %%; weave %.0f m",
				LANES[st], SCALES[sc], worst.minR, worst.length, 100 * worst.peak, 100 * worst.avg, weave))
			ok(worst.minR > 20 and worst.minR < 35, "loop radius out of the expected range")
		end
	end
	for st = 1, 2 do
		for sc = 1, 3 do
			for k in pairs(log) do log[k] = nil end
			base.updateFnDiamondInterchange({}, { streetType = st, scale = sc, viaduct = 0 })
			local term, ramps = nil, {}
			for _, e in ipairs(log) do
				if e.auto then ramps[#ramps + 1] = e end
				if e.tag1 == "sn-south" then term = e.p1 end
			end
			eq(#ramps, 4, "diamond ramps")
			local worst = { length = 0, peak = 0, avg = 0 }
			for _, r in ipairs(ramps) do
				local m = measure({ r })
				worst.length = math.max(worst.length, m.length)
				worst.peak = math.max(worst.peak, m.peak)
				worst.avg = math.max(worst.avg, m.avg)
			end
			local gore = ramps[1].p0
			print(string.format("    diamond %s %s: terminal at |y| %.0f m (cross road bridge %.0f m long), ramp node at |x| %.0f m, %.1f m beside its carriageway centre (13.5 m); ramps <= %.0f m, peak %.1f %%, avg %.1f %%",
				LANES[st], SCALES[sc], math.abs(term[2]), 2 * math.abs(term[2]), math.abs(gore[1]), math.abs(gore[2]) - 13.5, worst.length, 100 * worst.peak, 100 * worst.avg))
		end
	end
	print(string.format("    cloverleaf loop radius range %.1f-%.1f m", rmin, rmax))
end)
