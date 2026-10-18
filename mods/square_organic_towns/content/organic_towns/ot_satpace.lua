-- Organic Towns: map-wide pacing of the offshoots (pure; 2026-10-14, NEXT_PHASE_BRIEF 51 "Staggered satellites").
--
-- User (run 2026-10-14_1927_sqot, seed a, Quick 40 years): "make sure satellites don't get built during the same
-- period ... we want satellites to happen naturally at interesting staggered periods". That run founded 3 satellites
-- before simulated year 1 and the rest in bursts (year 11: 3 seeds, a Works and a district): every town decided on its
-- own, with no map-wide pacing. Now every founding (satellite seed, Works, district) goes through M.decide:
--   * per-town readiness (M.readiness): a town's first, second and later offshoots unlock at seeded milestones, its
--     size (ot_driver offshootSize: buildings or persons / 4) at least its starting size x READY (later ones x
--     READY_STEP more) and at least a maturity size READY_MIN, both seeded per town: towns get there at different times,
--     and none during the head start;
--   * map-wide spacing (M.slot): at most one founding per slot. A slot opens when the map grew by `need` (M.need: the
--     summed sizes of the map's towns since the last founding; SPACE_B on a 16-town map, x (towns / 16)^SPACE_EXP, x a
--     seeded JITTER per slot) or, when the calendar moves, after YEARS game years (both add: growth / need + years /
--     YEARS >= 1). The dev Simulate moves the calendar by default since §68 (both terms, as in play; unticked: growth
--     alone). The first slot counts from
--     the towns' summed starting sizes;
--   * order with variety: of the ready towns (candidates seen within CAND_TTL_S) the one with the highest seeded key
--     (weighted draw, Efraimidis-Spirakis u^(1/w): w = readiness x site quality) founds, the others are deferred. A
--     founding that fails (no site, refused) gives the slot back (M.refund) and that town sits it out;
--   * the map's size is read whole at each decision (the driver sums every town's persons / 4, not only the towns
--     measured this session), so a reload (session state lost, only the saved mark kept) never releases a backlog: the
--     saved mark is the map's size at the last founding;
--   * the dev Simulate's build rounds (o.epoch: ot_hooks simRound): the towns' growth lands during a round (each town's
--     fill once its jobs end), so at most one founding per round, and the mark settles at the map's size at the
--     founding round's last check (M.observe): the growth of the founding's own round doesn't count toward the next
--     slot, the next round's all does. The draw of a round takes only the towns still to decide in it (a town that
--     decided before the slot opened comes back only next round), so the slot goes to one of them in that round.
--   * grows (M.growDue): a satellite pod's later growth comes every EVERY_K demand builds of its town (seeded per pod,
--     with a seeded phase) and only once its town grew GROW_TOWN_F since the pod's last growth and the map
--     GROW_MAP_F x need since the last growth of any pod: pods don't all grow in the same round.
-- Saved (ot_saved `sp`, EV_PACE): { m = the mark, y = its game year x 100, n = foundings, y0 = the first game year x 100,
-- h = the foundings' elapsed years }. Lines: SATPACE (one per decision), SATPACE summary (foundings per decade).

local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"

local M = {}

M.ON = true
-- (2026-10-15, §64: 520 -> 850. The slots now go to at most ~4 named offshoot towns per 16 towns (ot_driver OFF_PER16)
-- instead of 6-10 foundings with the streets-only satellites; wider slots spread them over the decades: a 300-map
-- model's last founding at simulated year 28 (median) instead of 24)
M.SPACE_B = 850            -- size units (persons / 4) of map growth between two foundings on a SPACE_TOWNS-town map ...
M.SPACE_TOWNS = 16
M.SPACE_EXP = 0.5          -- ... x (towns / SPACE_TOWNS)^SPACE_EXP (a bigger map founds more, but less per town)
M.SPACE_MIN = 250
M.JITTER = { 0.6, 1.7 }    -- seeded per slot
M.YEARS = 10               -- game years since the last founding open a slot alone (calendar moving)
M.READY = { 1.3, 2.3 }     -- first offshoot: size >= the town's starting size x this (seeded per town) ...
M.READY_MIN = { 260, 480 } -- ... and >= this (maturity; seeded per town)
M.READY_STEP = { 1.35, 1.9 } -- every later one: both milestones x this (seeded per town and step)
M.READY_W_MAX = 2.5        -- readiness weighs at most this in the draw
M.CAND_TTL_S = 900         -- real s: a ready town seen this recently is a candidate of the draw
M.HIST_CAP = 64
M.MAX_CANDS = 4000         -- loop cap of the candidate scan
-- grows (a pod's later growth)
M.EVERY_K = { 3, 5 }       -- every this many demand builds of the town (seeded per pod) ...
M.GROW_TOWN_F = 0.08       -- ... once the town grew this share since the pod's last growth ...
M.GROW_TOWN_MIN = 25
M.GROW_MAP_F = 0.12        -- ... and the map this x need since the last growth of any pod

local function num(v)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then return nil end
	return v
end

local function lerp(r, u) return r[1] + (r[2] - r[1]) * u end

--- A new session state, from the saved `sp` (or nil): { mark, markYear, n, y0, hist, cands = {}, out = {} }.
function M.new(saved)
	local st = { cands = {}, out = {}, hist = {}, n = 0, grows = 0 }
	local sp = type(saved) == "table" and saved.sp or nil
	if type(sp) == "table" then
		st.mark = num(sp.m)
		st.markYear = num(sp.y) and num(sp.y) / 100 or nil
		st.n = math.max(0, math.floor(num(sp.n) or 0))
		st.y0 = num(sp.y0) and num(sp.y0) / 100 or nil
		if type(sp.h) == "table" then
			for i = 1, math.min(#sp.h, M.HIST_CAP) do
				local v = num(sp.h[i])
				if v then st.hist[#st.hist + 1] = v end
			end
		end
		st.restored = st.mark ~= nil
	end
	return st
end

--- The saved param (EV_PACE) of a state.
function M.param(st)
	local h = {}
	for i = math.max(1, #st.hist - M.HIST_CAP + 1), #st.hist do h[#h + 1] = math.floor(st.hist[i] * 10 + 0.5) / 10 end
	return { m = st.mark and math.floor(st.mark + 0.5) or nil, y = st.markYear and math.floor(st.markYear * 100 + 0.5) or nil,
		n = st.n, y0 = st.y0 and math.floor(st.y0 * 100 + 0.5) or nil, h = h }
end


--- Map growth between two foundings for a map of nTowns towns, slot idx (0-based founding index), salt (map seed).
function M.need(nTowns, idx, salt)
	local n = math.max(1, num(nTowns) or 1)
	local base = math.max(M.SPACE_MIN, M.SPACE_B * (n / M.SPACE_TOWNS) ^ M.SPACE_EXP)
	-- (§64: rng.draw: consecutive slots got near-linear jitters from rng.unit, an even 4-year beat on seed a)
	return base * lerp(M.JITTER, rng.draw(num(salt) or 1, num(idx) or 0, "satpace:gap"))
end

--- Readiness of a town for its next offshoot. o = { size, start, k (offshoots it has), seed }. Returns ready (bool),
--- ratio (size / target; >= 1 ready), target.
function M.readiness(o)
	local size = math.max(0, num(o.size) or 0)
	local start = math.max(1, num(o.start) or size)
	local k = math.max(0, math.min(8, math.floor(num(o.k) or 0)))
	local seed = num(o.seed) or 1
	local r = lerp(M.READY, rng.decide(o.dv, seed, "satpace:ready"))
	local mn = lerp(M.READY_MIN, rng.decide(o.dv, seed, "satpace:min"))
	for i = 1, k do
		local f = lerp(M.READY_STEP, rng.decide(o.dv, seed, i, "satpace:step"))
		r, mn = r * f, mn * f
	end
	local target = math.max(start * r, mn)
	local ratio = size / target
	return ratio >= 1, ratio, target
end

--- Is a slot open? o = { sum, mark, year, markYear, need }. Returns open, growth (since the mark), years, progress.
function M.slot(st, o)
	local need = num(o.need)
	if need == nil or need <= 0 then need = M.SPACE_MIN end
	local sum, mark = num(o.sum) or 0, num(st.mark) or num(o.sum) or 0
	local growth = sum - mark
	local years = 0
	local y, my = num(o.year), num(st.markYear)
	if y and my then years = math.max(0, y - my) end
	local progress = math.max(0, growth) / need + years / M.YEARS
	return progress >= 1, growth, years, progress
end

--- The draw key of town t for slot idx (higher wins): u^(1/w).
function M.key(salt, idx, t, w)
	-- (§64: rng.draw: neighboring town ids gave near-linear keys from rng.unit)
	local u = rng.draw(num(salt) or 1, num(idx) or 0, num(t) or 0, "satpace:key")
	w = math.max(0.05, num(w) or 1)
	return u ^ (1 / w)
end

--- The decision for a town about to found an offshoot. o = { t, kind, size, start, k, seed, quality (0..1, site
--- quality; 1 unknown), now (us), sum (the map's summed sizes), base (the towns' summed starting sizes: the mark
--- before the first founding), year (game year, fractional), nTowns, salt, epoch (the Simulate's round or nil),
--- elapsed (years, for the history) }. Returns outcome ("found" | "wait" | "deferred"), why, info { ratio, target, growth, need, years, cands,
--- winner }. A "found" moves the mark (M.refund gives it back).
function M.decide(st, o)
	local info = {}
	if not M.ON then return "found", "off", info end
	local t = o.t
	local ready, ratio, target = M.readiness(o)
	info.ratio, info.target = ratio, target
	local idx = st.n
	info.need = M.need(o.nTowns, idx, o.salt)
	if st.mark == nil and num(o.base) then st.mark = num(o.base) end
	local open, growth, years = M.slot(st, { sum = o.sum, year = o.year, need = info.need })
	info.growth, info.years = growth, years
	if not ready then
		st.cands[t] = nil
		return "wait", "notReady", info
	end
	local w = math.min(M.READY_W_MAX, ratio) * math.max(0.1, math.min(1, num(o.quality) or 1))
	st.cands[t] = { us = num(o.now) or 0, w = w, kind = o.kind, epoch = o.epoch }
	if st.out[idx] and st.out[idx][t] then return "wait", "satOut", info end
	if st.epoch ~= nil then
		if o.epoch == st.epoch then
			M.observe(st, o.sum, o.epoch)
			st.cands[t] = { us = num(o.now) or 0, w = 0, kind = o.kind, epoch = o.epoch }
			return "wait", "sameRound", info
		end
		M.observe(st, o.sum, o.epoch)
		open, growth, years = M.slot(st, { sum = o.sum, year = o.year, need = info.need })
		info.growth, info.years = growth, years
	end
	if not open then return "wait", "spacing", info end
	-- the draw among the candidates seen recently
	local now = num(o.now) or 0
	local best, bestKey, n = nil, -1, 0
	local ids = {}
	for id in pairs(st.cands) do
		n = n + 1
		if n > M.MAX_CANDS then break end
		ids[#ids + 1] = id
	end
	table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
	local live = 0
	for _, id in ipairs(ids) do
		local c = st.cands[id]
		if now - (c.us or 0) > M.CAND_TTL_S * 1e6 then
			st.cands[id] = nil
		elseif not (st.out[idx] and st.out[idx][id]) and c.w > 0
			and (o.epoch == nil or id == t or c.epoch ~= o.epoch) then
			live = live + 1
			local kk = M.key(o.salt, idx, id, c.w)
			if kk > bestKey or (kk == bestKey and tostring(id) < tostring(best)) then best, bestKey = id, kk end
		end
	end
	info.cands, info.winner = live, best
	if best ~= t then return "deferred", "draw", info end
	st.prev = { mark = st.mark, markYear = st.markYear, n = st.n, t = t, kind = o.kind, histN = #st.hist, epoch = st.epoch }
	st.mark, st.markYear, st.n = num(o.sum) or st.mark, num(o.year) or st.markYear, st.n + 1
	if st.y0 == nil then st.y0 = num(o.year) end
	st.hist[#st.hist + 1] = num(o.elapsed) or 0
	while #st.hist > M.HIST_CAP do table.remove(st.hist, 1) end
	st.cands[t] = nil
	st.epoch, st.pendMark = o.epoch, num(o.sum)
	return "found", "slot", info
end

--- A town was measured during the Simulate round of the last founding (epoch: ot_hooks simRound): the map's size then
--- is the mark to be; at the first sight of another round (or none) the mark settles at it. Returns true when the mark
--- settled now (the caller saves it).
function M.observe(st, sum, epoch)
	if st.epoch == nil then return false end
	if epoch == st.epoch then
		st.pendMark = num(sum) or st.pendMark
		return false
	end
	st.mark = st.pendMark or num(sum) or st.mark
	st.epoch, st.pendMark, st.dirty = nil, nil, true
	return true
end

--- The founding of town t failed (no site, refused, not sent): the slot goes back (mark, count) and t sits it out.
--- Returns true when something was given back.
function M.refund(st, t)
	local p = st.prev
	if p == nil or p.t ~= t then return false end
	st.mark, st.markYear, st.n, st.epoch = p.mark, p.markYear, p.n, p.epoch
	st.pendMark = nil
	while #st.hist > p.histN do table.remove(st.hist) end
	st.out[p.n] = st.out[p.n] or {}
	st.out[p.n][t] = true
	st.prev = nil
	return true
end

--- Is a satellite pod due to grow? o = { seed (the pod's), n (the town's demand build count, this one included),
--- size, podMark (town size at the pod's last growth), sum, growMark (map sum at the last growth of any pod), need }.
--- Returns due, why ("cadence" | "town" | "map" | "due").
function M.growDue(o)
	if not M.ON then return true, "off" end
	local seed = num(o.seed) or 1
	local every = M.EVERY_K[1] + math.floor(rng.decide(o.dv, seed, "satpace:every") * (M.EVERY_K[2] - M.EVERY_K[1] + 1))
	every = math.max(1, math.min(M.EVERY_K[2], every))
	local phase = math.floor(rng.decide(o.dv, seed, "satpace:phase") * every)
	local n = math.floor(num(o.n) or 0)
	if (n + phase) % every ~= 0 then return false, "cadence" end
	local size = num(o.size) or 0
	local pm = num(o.podMark)
	if pm and size - pm < math.max(M.GROW_TOWN_MIN, size * M.GROW_TOWN_F) then return false, "town" end
	local gm, need = num(o.growMark), num(o.need) or M.SPACE_B
	if gm and (num(o.sum) or 0) - gm < need * M.GROW_MAP_F then return false, "map" end
	return true, "due"
end

--- Foundings per decade of elapsed years: "0-9:2,10-19:1,..." ("-" none).
function M.decades(hist)
	local per, maxD = {}, -1
	for _, y in ipairs(hist or {}) do
		local d = math.max(0, math.floor((num(y) or 0) / 10))
		per[d] = (per[d] or 0) + 1
		if d > maxD then maxD = d end
	end
	if maxD < 0 then return "-" end
	local out = {}
	for d = 0, math.min(maxD, 50) do out[#out + 1] = string.format("%d-%d:%d", d * 10, d * 10 + 9, per[d] or 0) end
	return table.concat(out, ",")
end

--- The smallest gap (elapsed years) between two foundings, or nil with fewer than two.
function M.minGap(hist)
	local g = nil
	for i = 2, #(hist or {}) do
		local d = (num(hist[i]) or 0) - (num(hist[i - 1]) or 0)
		if g == nil or d < g then g = d end
	end
	return g
end

return M
