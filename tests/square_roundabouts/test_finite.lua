-- Every number in an updateFn result is finite, and no edge is degenerate. A NaN in an edge
-- crashes the game outright ("Assertion `(angle)>=(.0f)' failed: -nan < 0").

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local K = geom.PARAM_KEYS

local function loadData(file)
	ug_require(DIR .. file)
	return data()
end
local script = loadData("square_roundabouts.script.lua")

local function finite(x) return x == x and x ~= math.huge and x ~= -math.huge end

local function scan(v, path, bad)
	if type(v) == "number" then
		if not finite(v) then bad[#bad + 1] = path end
	elseif type(v) == "table" then
		for k, c in pairs(v) do scan(c, path .. "." .. tostring(k), bad) end
	end
end

local function problems(res)
	local bad = {}
	scan(res, "res", bad)
	for li, el in ipairs(res.edgeLists or {}) do
		local e = el.edges
		for i = 1, #e, 2 do
			local p0, t0, p1, t1 = e[i][1], e[i][2], e[i + 1][1], e[i + 1][2]
			local d = math.sqrt((p1[1] - p0[1]) ^ 2 + (p1[2] - p0[2]) ^ 2 + (p1[3] - p0[3]) ^ 2)
			local l0 = math.sqrt(t0[1] ^ 2 + t0[2] ^ 2 + t0[3] ^ 2)
			local l1 = math.sqrt(t1[1] ^ 2 + t1[2] ^ 2 + t1[3] ^ 2)
			if not (d > 0.5) then bad[#bad + 1] = ("list %d edge %d length %s"):format(li, (i + 1) // 2, d) end
			if not (l0 > 1e-6 and l1 > 1e-6) then
				bad[#bad + 1] = ("list %d edge %d zero tangent"):format(li, (i + 1) // 2)
			end
		end
	end
	return bad
end

-- The full sweep is 28,080 builds per case (several minutes in all). By default every STRIDE-th
-- combination runs, from a different start per case; 7 is prime to every dimension's size, so
-- each value of each param still comes up. SQRB_FULL=1 runs every combination.
local STRIDE = (os.getenv and os.getenv("SQRB_FULL")) and 1 or 7

local function sweep(fixed, start)
	local fails = {}
	local n = 0
	for shape = 1, #geom.SHAPE_RATIOS do
	for lanes = 1, 3 do
	for radius = 1, #geom.RADII do
	for arms = 1, 6 do
	for splitter = 1, 2 do
	for armType = 1, 6 do
	for direction = 1, 2 do
		n = n + 1
		if (n - start) % STRIDE == 0 then
		local p = { [K.shape] = shape, [K.lanes] = lanes, [K.radius] = radius, [K.arms] = arms,
			[K.splitter] = splitter, [K.armType] = armType, [K.direction] = direction, [K.island] = 2 }
		for k, v in pairs(fixed) do p[K[k]] = v end
		local ok, res = pcall(script.updateFn, {}, p)
		local bad = ok and problems(res) or { "error: " .. tostring(res) }
		if #bad > 0 and #fails < 8 then
			fails[#fails + 1] = ("shape=%d lanes=%d radius=%d arms=%d splitter=%d armType=%d dir=%d: %s")
				:format(shape, lanes, radius, arms, splitter, armType, direction, bad[1])
		end
		end
	end end end end end end end
	return fails
end

for i, case in ipairs({
	{ "nothing through", { centre = 1 } },
	{ "road through", { centre = 2 } },
	{ "tram line through", { centre = 3 } },
	{ "tram line through + tram tracks", { centre = 3, tram = 2 } },
}) do
	test("finite, non-degenerate result: " .. case[1], function()
		local fails = sweep(case[2], i)
		eq(#fails, 0, table.concat(fails, "\n"))
	end)
end

-- Regression (in-game crash 2026-10-07, transition_util.cpp:128 CompCurveHandleDistance): a
-- tram_new edge must never end on a ring node; stubs of the tram arm road join the ring.
test("tram line: tram_new never touches a ring node", function()
	for arms = 1, 6 do
	for radius = 1, #geom.RADII do
	for armType = 1, 6 do
		local r = script.updateFn({}, { [K.centre] = 3, [K.arms] = arms, [K.radius] = radius, [K.armType] = armType })
		local sawTram = false
		for _, el in ipairs(r.edgeLists) do
			if el.params.type:find("tram/tram_new", 1, true) then
				sawTram = true
				for _, entry in ipairs(el.edges) do
					local tag = entry[3]
					ok(not (tag and tag:find("^sqrb_ring_")), ("arms=%d radius=%d armType=%d: tram_new on %s"):format(arms, radius, armType, tostring(tag)))
				end
			end
		end
		ok(sawTram or geom.RADII[radius] < 40, ("arms=%d radius=%d armType=%d: no tram-only middle"):format(arms, radius, armType))
	end end end
end)
