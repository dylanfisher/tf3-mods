-- Photo Mode: variety for repeated jumps (round 17, user: "The interesting buttons should always be able to
-- click through and get a new view each time, even if it's just a different perspective of the same
-- interesting thing."). Pure (no api calls). Offline tests: tests/square_photo_mode/test_variety.lua.
-- Plain Lua, pre-5.3.
--
-- Two parts:
--   bags   one per pick kind (pm_world.lua): the subjects (entity ids, saved view ids, skyline directions...)
--          taken in the current cycle. The scans prefer a subject not taken yet in the cycle (isFresh); after
--          POOL_MAX different subjects, or when only taken ones are found, a new cycle starts. take() records
--          a pick and returns its place in the cycle, the pool size and the view variant: how often that
--          subject was taken before (0 = the shot's own framing). choose() is a shuffle bag over a list
--          (saved views): every item once, in random order, before any repeats, never the last one first.
--   views  vary() turns a view { x, y, d, a, p } into variant k of it: the same centre, the heading turned k
--          golden-angle steps (never the same heading twice), the distance and pitch of a shot style taken in
--          turn (eye level, high, low) with a small distance jitter. distinct() steps the variant on until the
--          view differs from the last one jumped to, so two clicks in a row never give the identical view.
--
-- PLAN: plans/square_photo_mode/PLAN.md "Round 17: interesting views vary".

local V = {}

-- Different subjects of a kind per cycle; after that the best ones come back from new angles.
V.POOL_MAX = 6
-- Subject ids remembered per kind (pool size, taken counts); past this the kind's memory starts afresh.
V.MEMORY_MAX = 256
-- The golden angle (radians): k steps of it never land on the same heading.
V.GOLDEN = math.pi * (3 - math.sqrt(5))
-- Shot styles of the variants, in turn: distance scale and pitch (radians down from the horizon).
V.STYLES = { "eye", "high", "low" }
V.STYLE = {
	eye = { dScale = 0.75, p = 0.05 },               -- close, nearly level
	high = { dScale = 1.35, pAdd = 0.35, pMax = 0.85 }, -- further out, looking down
	low = { dScale = 0.95, pScale = 0.5, pMin = 0.02 }, -- the framing's distance, half its pitch
}
V.JITTER = 0.3 -- distance jitter: x (1 - JITTER/2 .. 1 + JITTER/2), golden-ratio sequence
V.D_MIN, V.D_MAX = 15, 3000
-- Two views closer than this are "the same view".
V.SAME_TOL = { xy = 1, dRel = 0.01, a = 0.02, p = 0.01 }
V.DISTINCT_TRIES = 8

-- The Interesting buttons and the saved views: their jumps log "interesting pick".
V.INTERESTING = {
	bridge = true, water = true, passing = true, tunnel = true, approach = true, rush = true, skyline = true,
	viewpoint = true, departure = true, oldest = true, fastest = true, longest = true, saved = true,
}

local PI, TWO_PI = math.pi, 2 * math.pi

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function clamp(v, lo, hi)
	if v ~= v then return lo end
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function wrap(a)
	if not finite(a) then return 0 end
	local r = math.fmod(a + PI, TWO_PI)
	if r <= 0 then r = r + TWO_PI end
	return r - PI
end

---------------------------------------------------------------------------
-- Bags

--- A new bag. poolMax: different subjects per cycle (default POOL_MAX; math.huge for a list such as the saved
--- views, where choose() decides).
function V.newBag(poolMax)
	return { used = {}, usedN = 0, seen = {}, seenN = 0, taken = {}, last = nil, cycle = 1,
		poolMax = poolMax or V.POOL_MAX }
end

local function newCycle(bag)
	bag.used, bag.usedN = {}, 0
	bag.cycle = bag.cycle + 1
end

--- True when the subject `id` is not taken yet in the bag's cycle and the cycle has room for one more.
function V.isFresh(bag, id)
	if bag == nil or id == nil then return true end
	return not bag.used[id] and bag.usedN < bag.poolMax
end

--- Records a pick of subject `id`. A subject already taken in this cycle (or a full cycle) starts a new cycle
--- with it. Returns n (its place in the cycle), m (the pool size: poolSize when given, else the subjects found so far,
--- at most poolMax) and k, the view variant (how often `id` was taken before).
function V.take(bag, id, poolSize)
	if bag == nil or id == nil then return 1, 1, 0 end
	if not bag.seen[id] then
		if bag.seenN >= V.MEMORY_MAX then
			bag.seen, bag.seenN, bag.taken = {}, 0, {}
			newCycle(bag)
		end
		bag.seen[id] = true
		bag.seenN = bag.seenN + 1
	end
	if bag.used[id] or bag.usedN >= bag.poolMax then newCycle(bag) end
	bag.used[id] = true
	bag.usedN = bag.usedN + 1
	local k = bag.taken[id] or 0
	bag.taken[id] = k + 1
	bag.last = id
	local m = tonumber(poolSize) or math.min(bag.seenN, bag.poolMax)
	return bag.usedN, math.max(bag.usedN, m), k
end

--- Shuffle bag over `ids` (a list): a random id not taken in this cycle; when all are taken, a new cycle starts
--- and the last one taken waits (unless it is the only one). rnd: 0..1. nil for an empty list.
function V.choose(bag, ids, rnd)
	local n = ids and #ids or 0
	if n == 0 then return nil end
	local fresh = {}
	for i = 1, n do
		if not bag.used[ids[i]] then fresh[#fresh + 1] = ids[i] end
	end
	if #fresh == 0 then
		newCycle(bag)
		for i = 1, n do
			if ids[i] ~= bag.last or n == 1 then fresh[#fresh + 1] = ids[i] end
		end
	end
	local r = clamp(tonumber(rnd and rnd()) or 0, 0, 0.999999)
	return fresh[math.floor(r * #fresh) + 1]
end

---------------------------------------------------------------------------
-- Views

--- Variant k of view v ({ x, y, d, a, p }): k = 0 (or a non-view) the view itself (a copy); else the heading
--- turned k golden-angle steps, the style STYLES[k] (in turn) and a distance jitter. Returns the view and the
--- style ("frame" for k = 0).
function V.vary(v, k)
	if v == nil then return nil, "frame" end
	local out = { x = v.x, y = v.y, d = v.d, a = v.a, p = v.p }
	k = math.floor(tonumber(k) or 0)
	if k <= 0 or not (finite(v.d) and finite(v.a) and finite(v.p)) then return out, "frame" end
	local style = V.STYLES[(k - 1) % #V.STYLES + 1]
	local st = V.STYLE[style]
	local g = (k * 0.6180339887) % 1
	local d = v.d * st.dScale * (1 - V.JITTER / 2 + V.JITTER * g)
	out.d = clamp(d, V.D_MIN, V.D_MAX)
	if st.p ~= nil then
		out.p = st.p
	elseif st.pAdd ~= nil then
		out.p = math.min(v.p + st.pAdd, st.pMax)
	else
		out.p = math.max(v.p * st.pScale, st.pMin)
	end
	out.a = wrap(v.a + k * V.GOLDEN)
	return out, style
end

--- True when views a and b are the same view (within SAME_TOL); false when either is missing.
function V.same(a, b)
	if a == nil or b == nil then return false end
	local t = V.SAME_TOL
	if not (finite(a.x) and finite(b.x) and finite(a.d) and finite(b.d)) then return false end
	if math.abs(a.x - b.x) > t.xy or math.abs(a.y - b.y) > t.xy then return false end
	if math.abs(a.d - b.d) > t.dRel * math.max(1, math.abs(b.d)) then return false end
	if math.abs(wrap((b.a or 0) - (a.a or 0))) > t.a then return false end
	return math.abs((a.p or 0) - (b.p or 0)) <= t.p
end

--- Variant k of `base`, or a later one when it would repeat `last` (the view of the previous jump), at most
--- DISTINCT_TRIES steps on. Returns the view, the variant used and its style.
function V.distinct(base, k, last)
	k = math.max(0, math.floor(tonumber(k) or 0))
	local v, style = V.vary(base, k)
	for __ = 1, V.DISTINCT_TRIES do
		if not V.same(v, last) then return v, k, style end
		k = k + 1
		v, style = V.vary(base, k)
	end
	return v, k, style
end

return V
