-- Organic Towns: forest lanes (pure; round R2, 2026-10-13). User (run 2026-10-13_1945_sqot-dev): "if a street is in
-- between a forest and close enough to trees, we block building for part of the road to ensure no houses take over (but
-- game should be able to extend past and continue the road). we should use that sparingly so there's still some houses
-- built in forests".
--
-- Where a planned street of an increment runs through forest with trees within lot depth on BOTH sides (ot_forest
-- corridor: centreline and both sides' lots wooded), that stretch is built with the era's base country template
-- (`country_old_small` before 1940, `country_new_small` from 1940), locked: country roads get no houses (verified,
-- docs/findings/roads.md "Country roads get no houses") and the lock keeps the town from rebuilding it. The street's
-- edges before and after the stretch stay town streets, so the town extends past it.
--
-- Sparingly: about 1 in 3 eligible crossings (seeded per town and street), more in forest-hugging towns, fewer in towns
-- that build through the forest and in later eras, never in a metropolis, at most MAX_PER_TOWN per town and session.
-- Only edges between two new nodes that each meet another new edge (a joined edge copies its dead end's town street;
-- never a tip, so the town street goes on beyond), never a bridge. Nothing saved; no new node (the crash rule: the
-- nodes get their configs as any other new node).
--
-- One-sided variant (a street along the forest edge): the base `barrier_a` / `barrier_b` edge decorations have
-- `preventParcels = true` and a side flag, but they are noise barriers; R1's placement (the edge premium one lot depth
-- off the trees, the dose on the open side) handles the edge, so it stays off (ONE_SIDED false, not built).

local FO = ug_require "square_organic_towns::/organic_towns/ot_forest.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"

local M = {}

-- Round after the names run (2026-10-13, run 2026-10-13_2113_sqot-dev): the three lanes built all came from the dev
-- SIMGROW's plans (logged `[SQOT_DEV] FORESTLANE`, so a grep for `[SQOT] FORESTLANE` found none); Henley-in-Arden's was
-- 6 edges / 474 m of a grid of back-row streets (`bk1:2:L1#3`, mode clear) and read in the shots as "random country
-- roads mixed in" at the town's edge. The old rule (both nodes new, each meeting another new edge) let a lane run over
-- every connected wooded edge, around a block. Now a lane is one stretch of one plan line (M.lineOf: the piece key
-- before "#"), never on block-interior lines (M.NO_LINES: back rows, secondary radials, grid blocks, connectors), its
-- inner nodes carry no side street, both its ends meet another edge of the increment (the town street goes on), and it
-- is MIN_M..MAX_M long. And hug towns (most forest towns: 226 of 285 plans in that run) held exactly the pieces a lane
-- needs (wooded on both sides), so they never got one: a held piece at least FREE_M long that closes a gap between two
-- reached parts of the town may now come as a lane (M.free, ot_select forestOk; seeded per piece, the town's quota).

M.ON = true
M.ONE_SIDED = false   -- barrier decorations on the forest side (not built: see above)
M.P = 0.34            -- base chance per eligible crossing
M.MODE_F = { hug = 1.5, clear = 0.5 }   -- hug towns more, towns that build through the forest fewer (none: no lanes)
M.MAX_PER_TOWN = 4    -- lanes per town and session
-- deep forest towns (ot_forest deep, 2026-10-14): 2 of 3 eligible crossings whatever the era, more per town. (Single-sided
-- lanes on edge streets: not built for them either; a country street has no houses on either side, and the barrier
-- decorations stay unverified, ONE_SIDED above. A deep town's edge streets are locked instead, ot_forest.facesForest.)
M.DEEP_P = 0.67
M.DEEP_MAX_PER_TOWN = 8

--- The lane cap per town for a style: DEEP_MAX_PER_TOWN for a deep forest town when the caller asks the default.
function M.maxFor(style, max)
	local fo = style and style.forest
	if fo ~= nil and fo.mode == "deep" and (max == nil or max == M.MAX_PER_TOWN) then return M.DEEP_MAX_PER_TOWN end
	return max or M.MAX_PER_TOWN
end
M.MIN_M = 60          -- m: the stretch at least this long ...
M.MIN_EDGES = 2       -- ... and this many edges (one edge between two junctions is a block side: no lane)
M.CENTRE = 0.5        -- the centreline's cover at least this
M.SIDE = 0.5          -- each side's lots (ot_forest LOT_OFFSETS) at least this cover
M.MAX_REFUSED = 2     -- refused pre-checks with lanes (re-sent without them) before lanes are off for the session
M.MAX_M = 400         -- m: a longer wooded stretch is no lane (it stays a town street through the forest)
M.FREE_M = 220        -- m: a held hug piece this long (>= 3 edges at the 100 m split: inner edges between new nodes)
-- block-interior plan lines get no lane (ot_grow_organic back rows "bk" / secondary radials "sr", grid blocks "q",
-- lattice pieces "h" / "v", connectors "conn"): lanes go on through lines (spokes, rings, arms, motif lines)
M.NO_LINES = { "bk", "sr", "q", "conn" }

--- The plan line of an edge's piece key ("bk1:2:L1#3" -> "bk1:2:L1"; a grid lattice piece "h3:4" -> its row "h3"; a key
--- without "#<n>" is its own line).
function M.lineOf(key)
	if type(key) ~= "string" then return nil end
	local lat = key:match("^([hv]%-?%d+):%-?%d+$")
	if lat then return lat end
	return key:match("^(.-)#%d+$") or key
end

--- May a piece / edge key carry a lane? (not on the block-interior lines)
function M.lineOk(key)
	if type(key) ~= "string" then return false end
	for _, p in ipairs(M.NO_LINES) do
		if key:sub(1, #p) == p then return false end
	end
	return true
end

--- ot_select (hug towns): may the held wooded piece pc (corridor co) come as a lane? Seeded per piece against the
--- town's chance, its lane quota (used / max), the line rule, the corridor wooded on the centreline and both sides,
--- FREE_M..MAX_M long. The select only asks when both of the piece's ends are reached (it closes a gap in the town).
function M.free(style, pc, co, used, max)
	if not M.ON or pc == nil or co == nil or pc.motif then return false end
	if (used or 0) >= M.maxFor(style, max) then return false end
	if not M.lineOk(pc.key) then return false end
	if co.len < M.FREE_M or co.len > M.MAX_M then return false end
	if co.c < M.CENTRE or co.l < M.SIDE or co.r < M.SIDE then return false end
	local p = M.chance(style)
	if p <= 0 then return false end
	return rng.unit((style and style.seed) or 1, "laneFree", pc.key) < p
end
M.TEMPLATE = { old = "::/infrastructure/street/country/country_old_small.street_template",
	new = "::/infrastructure/street/country/country_new_small.street_template" }

--- The era's country template for a style (style.newTemplates: the town templates' era).
function M.templateFor(style)
	return (style and style.newTemplates) and M.TEMPLATE.new or M.TEMPLATE.old
end

--- True for a country template path.
function M.isCountry(path)
	return type(path) == "string" and path:find("/country/", 1, true) ~= nil
end

--- The chance per eligible crossing for a style (0 without forest info, mode none or a metropolis), and the why text.
function M.chance(style)
	local fo = style and style.forest
	if fo == nil or fo.grid == nil then return 0, "noGrid" end
	if style.metro then return 0, "metro" end
	if fo.mode == "deep" then return M.DEEP_P, string.format("deep:p=%.2f", M.DEEP_P) end
	local mf = M.MODE_F[fo.mode or "none"]
	if mf == nil then return 0, "mode:" .. tostring(fo.mode) end
	-- (the forest era factor without its early boost, §59: lanes keep their odds in early years)
	local era = math.min(1, FO.eraF(style.year))
	local p = math.min(0.9, M.P * mf * era)
	return p, string.format("%s:p=%.2f", fo.mode, p)
end

--- The eligible runs of an increment: { { street, line, first (inc.edges index), len, edges = { indices } } }. An edge
--- is eligible when its corridor is wooded on the centreline and both sides, both its nodes are new (never a joined
--- edge: it copies its dead end's town street), it is no bridge and its line may carry a lane (M.lineOk). A run is a
--- chain of eligible edges of ONE plan line through nodes without a side street (exactly two increment edges); both its
--- end nodes meet another edge of the increment (the town street goes on past it, never a tip), MIN_M..MAX_M long.
--- freed = { [piece key] = true } (ot_select via M.free: held hug pieces let through as lanes): their edges count as
--- wooded (the piece passed as a whole). minEdges: MIN_EDGES by default.
function M.runs(fo, inc, freed, minEdges)
	minEdges = minEdges or M.MIN_EDGES
	local out = {}
	-- (why the wooded edges made no lane, for the FORESTLANE check line: wooded = edges wooded on both sides, joined =
	-- of those touching an existing node, line = on a block-interior line, tip / short / long = runs dropped)
	local stats = { wooded = 0, joined = 0, line = 0, tip = 0, short = 0, long = 0, runs = 0 }
	if fo == nil or fo.grid == nil or inc == nil then return out, stats end
	local edges = inc.edges or {}
	local at = {}
	for i, e in ipairs(edges) do
		for _, n in ipairs({ e.node0, e.node1 }) do
			if n ~= nil then
				at[n] = at[n] or {}
				local l = at[n]
				l[#l + 1] = i
			end
		end
	end
	local elig, len, line = {}, {}, {}
	for i, e in ipairs(edges) do
		local n0, n1 = e.node0 or 0, e.node1 or 0
		if not e.bridge and e.p0 ~= nil and e.p1 ~= nil then
			local co = FO.corridor(fo, { e.p0, e.p1 })
			local free = freed ~= nil and e.key ~= nil and freed[e.key] == true
			if co.len > 0 and (free or (co.c >= M.CENTRE and co.l >= M.SIDE and co.r >= M.SIDE)) then
				stats.wooded = stats.wooded + 1
				if not (n0 < 0 and n1 < 0) then stats.joined = stats.joined + 1
				elseif not M.lineOk(e.key) then
					stats.line = stats.line + 1
					stats.lineKey = stats.lineKey or e.key
				else elig[i], len[i], line[i] = true, co.len, M.lineOf(e.key) end
			end
		end
	end
	-- chains along one line (every edge visited once: the walks are bounded by the edge count)
	local seen = {}
	local function nextOf(k, n)
		local l = at[n] or {}
		if #l ~= 2 then return nil end   -- (an end, or a node with a side street: the chain stops)
		local j = l[1] == k and l[2] or l[1]
		if j ~= k and elig[j] and not seen[j] and line[j] == line[k] then return j end
		return nil
	end
	local function otherNode(j, n) return (edges[j].node0 == n) and edges[j].node1 or edges[j].node0 end
	for i = 1, #edges do
		if elig[i] and not seen[i] then
			seen[i] = true
			-- the ordered chain through edge i: walk both ways (side 0 from node0, side 1 from node1)
			local sides, ends = { {}, {} }, {}
			for side = 1, 2 do
				local k = i
				local n = side == 1 and edges[i].node0 or edges[i].node1
				local steps = 0
				while steps <= #edges do
					steps = steps + 1
					local j = nextOf(k, n)
					if j == nil then break end
					seen[j] = true
					local l = sides[side]
					l[#l + 1] = j
					n = otherNode(j, n)
					k = j
				end
				ends[side] = n
			end
			local seq = {}
			for q = #sides[1], 1, -1 do seq[#seq + 1] = sides[1][q] end
			seq[#seq + 1] = i
			for _, j in ipairs(sides[2]) do seq[#seq + 1] = j end
			-- a dead end (no other increment edge at the chain's end node): its edge stays a town street, so the town
			-- can go on from it (never a lane at a tip)
			local nA, nB = ends[1], ends[2]
			local function alone(n, j) return #(at[n] or {}) == 1 and at[n][1] == j end
			if #seq > 0 and alone(nA, seq[1]) then nA = otherNode(seq[1], nA); table.remove(seq, 1) end
			if #seq > 0 and alone(nB, seq[#seq]) then nB = otherNode(seq[#seq], nB); table.remove(seq) end
			if #seq == 0 then
				stats.tip = stats.tip + 1
			else
				local run = { street = edges[i].street or edges[i].key or i, line = line[i], len = 0, edges = {} }
				for _, j in ipairs(seq) do
					run.edges[#run.edges + 1] = j
					run.len = run.len + len[j]
				end
				table.sort(run.edges)
				run.first = run.edges[1]
				if run.len < M.MIN_M or #run.edges < minEdges then stats.short = stats.short + 1
				elseif run.len > M.MAX_M then stats.long = stats.long + 1
				else out[#out + 1] = run end
			end
		end
	end
	stats.runs = #out
	return out, stats
end

--- Marks the increment's forest lanes (e.forestLane = the country template path). ctx = { seed, used (lanes this town
--- has), max (per town), ok = function(path) (template exists) }. Returns the marked runs { {street, len, edges, why} } and
--- the skipped ones (why = draw / cap / template).
function M.mark(inc, style, ctx)
	ctx = ctx or {}
	local marked, skipped = {}, {}
	if inc == nil then return marked, skipped end
	inc.lanes, inc.laneRuns = nil, nil
	for _, e in ipairs(inc.edges or {}) do e.forestLane = nil end
	if not M.ON then return marked, skipped end
	local p, why = M.chance(style)
	-- (dev forest-lane test, ctx.force: every eligible run, no cap, any forest mode with a grid)
	if ctx.force and style and style.forest and style.forest.grid then p, why = 1.01, "force" end
	if p <= 0 then return marked, skipped end
	local path = M.templateFor(style)
	local used, max = ctx.used or 0, M.maxFor(style, ctx.max)
	-- (the dev forest-lane test, ctx.force: a single edge may be a lane too)
	local runs, stats = M.runs(style.forest, inc, ctx.freed, ctx.force and 1 or nil)
	inc.laneStats = stats
	for _, run in ipairs(runs) do
		local u = rng.unit(ctx.seed or style.seed or 1, "forestLane:" .. tostring(run.street) .. ":" .. tostring(inc.edges[run.first].key))
		-- (a piece the select let through as a lane was drawn there already)
		local freed = ctx.freed ~= nil and ctx.freed[inc.edges[run.first].key] == true
		run.why = string.format("%s,u=%.2f%s", why, u, freed and ",freed" or "")
		if used >= max and not ctx.force then
			run.skip = "cap"
		elseif u >= p and not freed then
			run.skip = "draw"
		elseif ctx.ok and not ctx.ok(path) then
			run.skip = "template"
		end
		if run.skip then
			skipped[#skipped + 1] = run
		else
			for _, i in ipairs(run.edges) do inc.edges[i].forestLane = path end
			run.template = path
			marked[#marked + 1] = run
			used = used + 1
		end
	end
	if #marked > 0 then
		local n = 0
		for _, r in ipairs(marked) do n = n + #r.edges end
		inc.lanes, inc.laneRuns = n, #marked
	end
	return marked, skipped
end

--- Clears every lane flag of inc (a refused pre-check is re-sent without them). Returns how many edges had one.
function M.strip(inc)
	local n = 0
	for _, e in ipairs(inc and inc.edges or {}) do
		if e.forestLane then e.forestLane = nil; n = n + 1 end
	end
	if inc then inc.lanes, inc.laneRuns = nil, nil end
	return n
end

return M
