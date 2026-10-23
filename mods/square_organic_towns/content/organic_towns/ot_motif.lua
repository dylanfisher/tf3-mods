-- Organic Towns: town motifs (pure). Phase M0 of the motifs plan (plans/square_organic_towns/MOTIFS_BRIEF.md,
-- 2026-10-13).
--
-- A motif is a small, recognisable street pattern placed where the land, the surroundings or the era call for it (a
-- crescent around a meadow, a hill road climbing a slope, later a harbour crescent, a village green, a station
-- quarter ...). Motifs are built through the normal planner (increments, housed front, own-empty budget, lead limit,
-- map edge margin, the crash rule): a motif only changes what the planner is offered or how it is steered, never how
-- an increment is sent.
--
-- The registry: MO.register(kind) with
--   id        string, [a-z_]; saved frames store its index in MO.IDS (append only)
--   derived   true: a look the town gets from its style / shape anyway (the pre-M0 behaviour migrated here: crescents,
--             the hillside hill road). Present whenever eligible, recomputed every session, never drawn, never saved,
--             no neighbour diversity. false / nil: a drawn motif (0-MAX per town, seeded, saved on the frame)
--   free      true (derived kinds only; 2026-10-13 final test): a style look that takes no motif slot either (the
--             crescents: EU organic towns all have them, so they took one of the two slots in 13 of 16 towns)
--   extra     true (derived kinds only; M4 2026-10-13): a quarter that comes from an event in the town's life (the player's
--             rail station, the town's river bridge), not from its site / style: it takes no motif slot, so a town's drawn
--             motifs never depend on it (before M4 a station near a fresh town took a slot: its ring road picks fell from
--             3 to 0 of 120). The site / style looks (crescent, hill_road) keep taking a slot: they are the town's own
--             character, at most MAX of them in all
--   eligible  fn(ctx) -> score (0 = not here; up to 1 = the site calls for it), why (short text for the logs).
--             ctx = { style (the resolved StyleParams, shape / form set), inputs (ot_inputs), feats (ot_site.features
--             or nil), terrain, year, era, tier, cap, form, shape, character }
--   group     string (optional, M1): at most one drawn motif of a group per town
--   inputs    fn(inputs, m) (optional; a forced motif only): adjust the inputs before the shape / form are picked
--   style     fn(p, m, env) (optional): steering: style fields (contour, lobes, premiums), reservations (style.greens),
--             env = { greenReserves = ot_style.greenReserves }
--   plan      fn(mp, style, m, env) (optional): candidate pieces: change the master plan in place (ot_core.masterPlan;
--             env = { green = ot_select.GREEN, extent, terrain (sampler), g (the snapshot graph) }). A derived kind's
--             plan hook runs for every style
--             (it checks its own condition, so the migrated behaviour stays exactly as it was)
--   measure   fn(env, m) -> { edges (this build), total (in the town), houses, text } or nil (optional; MOTIF build
--             lines). env = { g, inc, style, mp, pts, sampler, MT, SH }
--   dose      fn(m, edges, off, n) -> { {x, y} } (optional; M1): DevelopAt points for a build's edges (spec edges with
--             p0 / p1), the driver's fill (ot_driver fillKind / fillPoints, FILL why=motif)
--
-- The drawn kinds of M1 (terrain / water: hill_climb, valley_fishbone, harbour_crescent, fishing_village) live in
-- ot_motif_land.lua, those of M2 (roads / villages: ribbon_village, village_green, crossroads_hamlet) in ot_motif_road.lua;
-- those of M3 (town structure / era: ring_road, station_quarter (derived), workers_terraces, culdesac_pods) in
-- ot_motif_town.lua; those of M4 (more terrain: switchbacks, ridge_street, headland_street, bridgehead_quarter (derived,
-- extra)) in ot_motif_relief.lua; all are registered at the end of this file. MO.IDS order (save indices): crescent,
-- hill_road, hill_climb, valley_fishbone, harbour_crescent, fishing_village, ribbon_village, village_green,
-- crossroads_hamlet, ring_road, station_quarter, workers_terraces, culdesac_pods, switchbacks, ridge_street,
-- headland_street, bridgehead_quarter, peninsula_tip (final-test round, ot_motif_point).
--   lock      true (optional, M2): the build's edges of this motif (keys starting with its plan prefix, MO.lockPrefixes)
--             are locked like a shape's arms (ot_driver.lockKeys): the game hangs no side streets on them
--
-- A town's motifs (MO.pick, from ot_style.resolve): a saved frame keeps its saved motifs (old frames: none); a dev
-- forced kind comes first; a fresh town draws 0 to MAX minus its derived motifs (not the `extra` ones) from the eligible drawn kinds, seeded
-- per town, a kind its neighbours use weighing less (ot_diverse key "motif"). style.motifs holds the drawn / saved /
-- forced records; MO.list(style) adds the derived ones.

local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local DV = ug_require "square_organic_towns::/organic_towns/ot_diverse.lua"
local CR = ug_require "square_organic_towns::/organic_towns/ot_crescent.lua"

local MO = {}

MO.ON = true
MO.MAX = 2                   -- motifs per town at most (derived ones count, but not the `extra` event quarters nor the
                             -- `free` style looks: crescents)
-- chance of a drawn motif in the 1st / 2nd free slot, x the best eligible score / P_FULL (<= 1). (2026-10-13 final test,
-- session 2026-10-13_0856_sqot-dev: 0.6 / 0.3 x the score, the crescent taking a slot: 2 drawn picks in 16 towns; the
-- user: "the more we can push cities that build with the environment, the better")
MO.SLOT_P = { 0.9, 0.4 }
MO.P_FULL = 0.4              -- a best score of at least this draws at the full SLOT_P
MO.MIN_SCORE = 0.1           -- drawn kinds scoring less are not eligible (MOTIF elig: "low:")
MO.SAVE_BASE = 64            -- saved frames: mo = i1 + SAVE_BASE x i2 (indices into MO.IDS)
-- fallback (round R5, 2026-10-13; run 2026-10-13_1945_sqot-dev: hill_climb picked 6 times, 5 came out none:flat/short;
-- switchbacks 3 of 4 noBend): a drawn or saved kind whose plan hook lays no geometry (m.geo nil with a planWhy) gives
-- its slot to the next eligible kind (highest score first, not in use, no group clash) whose plan does; at most
-- FALLBACK_MAX tries per plan. The record replaces the old one in style.motifs (the frame saves the new id).
MO.FALLBACK = true
MO.FALLBACK_MAX = 3

-- save index: id -> position. Append only (saved frames hold the positions).
MO.IDS = { "crescent", "hill_road", "hill_climb", "valley_fishbone", "harbour_crescent", "fishing_village",
	"ribbon_village", "village_green", "crossroads_hamlet", "ring_road", "station_quarter", "workers_terraces",
	"culdesac_pods", "switchbacks", "ridge_street", "headland_street", "bridgehead_quarter", "peninsula_tip" }
MO.INDEX = {}
for i, id in ipairs(MO.IDS) do MO.INDEX[id] = i end

MO.KINDS = {}                -- registration order (the draw's order)
MO.BY_ID = {}

--- Registers (or replaces) a motif kind. Unknown ids are appended to MO.IDS.
function MO.register(kind)
	assert(type(kind) == "table" and type(kind.id) == "string" and kind.id:match("^[a-z_]+$"), "motif kind id")
	assert(type(kind.eligible) == "function", "motif kind eligible()")
	if MO.INDEX[kind.id] == nil then
		MO.IDS[#MO.IDS + 1] = kind.id
		MO.INDEX[kind.id] = #MO.IDS
	end
	if MO.BY_ID[kind.id] == nil then MO.KINDS[#MO.KINDS + 1] = kind
	else
		for i, k in ipairs(MO.KINDS) do if k.id == kind.id then MO.KINDS[i] = kind end end
	end
	MO.BY_ID[kind.id] = kind
	return kind
end

--- Removes a kind from the registry (tests); its save index stays reserved.
function MO.unregister(id)
	if MO.BY_ID[id] == nil then return end
	MO.BY_ID[id] = nil
	for i = #MO.KINDS, 1, -1 do if MO.KINDS[i].id == id then table.remove(MO.KINDS, i) end end
end

local function safeEligible(kind, ctx)
	local ok, s, why = pcall(kind.eligible, ctx)
	if not ok then return 0, "error" end
	s = tonumber(s) or 0
	if s < 0 then s = 0 end
	if s > 1 then s = 1 end
	-- (a trace of eligibility is none: a 2 % coast reading as a hill, final-test round)
	if s > 0 and s < MO.MIN_SCORE and not kind.derived then return 0, string.format("low:%.2f:%s", s, tostring(why)) end
	return s, why
end

--- The derived motifs a style has now: { { id, score, why, derived = true } } (style order of MO.KINDS).
function MO.derived(style, ctx)
	local out = {}
	if not MO.ON or style == nil then return out end
	ctx = ctx or { style = style }
	for _, k in ipairs(MO.KINDS) do
		if k.derived then
			local s, why = safeEligible(k, ctx)
			if s > 0 then out[#out + 1] = { id = k.id, score = s, why = why or "-", derived = true } end
		end
	end
	return out
end

--- The number of motif slots the derived motifs of a style take (the `extra` event quarters take none).
function MO.slotsTaken(style, ctx)
	local n = 0
	for _, m in ipairs(MO.derived(style, ctx)) do
		local k = MO.BY_ID[m.id]
		if not (k and (k.extra or k.free)) then n = n + 1 end
	end
	return n
end

--- Every motif of a style: the drawn / saved / forced records (style.motifs) first, then the derived ones not
--- already among them.
function MO.list(style)
	local out, seen = {}, {}
	if style == nil then return out end
	for _, m in ipairs(style.motifs or {}) do
		if MO.BY_ID[m.id] and not seen[m.id] then out[#out + 1] = m; seen[m.id] = true end
	end
	for _, m in ipairs(MO.derived(style)) do
		if not seen[m.id] then out[#out + 1] = m; seen[m.id] = true end
	end
	return out
end

--- The town's drawn / saved / forced motifs (the records for style.motifs). See the header.
function MO.pick(ctx)
	local out = {}
	if not MO.ON or type(ctx) ~= "table" or ctx.style == nil then return out end
	local inputs = ctx.inputs or {}
	local have = {}
	local forced = inputs.motif and MO.BY_ID[inputs.motif] or nil
	if forced then
		out[1] = { id = forced.id, score = 1, why = "forced(dev)", forced = true }
		have[forced.id] = true
		return out   -- (dev: only the forced one, plus the derived ones MO.list adds)
	end
	local cands = {}
	local elig = {}
	-- (a strong character's motif taste, ot_character 2026-10-14: forbidden kinds never drawn, preferred ones weigh more
	-- and fill the first slot when eligible)
	local cm = inputs.charMotifs
	local forbid, prefer = {}, {}
	for _, id in ipairs(cm and cm.forbid or {}) do forbid[id] = true end
	for _, id in ipairs(cm and cm.prefer or {}) do prefer[id] = true end
	for _, k in ipairs(MO.KINDS) do
		if not k.derived and not forbid[k.id] then
			local s, why = safeEligible(k, ctx)
			if s > 0 then cands[#cands + 1] = { kind = k, w = s, score = s, why = why or "-" } end
			elig[#elig + 1] = string.format("%s:%.2f:%s", k.id, s, tostring(why or "-"))
		end
	end
	-- (every kind's score and why, for the driver's debug line `MOTIF event=elig`)
	ctx.style._motifElig = table.concat(elig, ",")
	-- (R5: the eligible kinds, best first, for the plan's fallback, MO.applyPlan)
	local fb = {}
	for _, c in ipairs(cands) do fb[#fb + 1] = { id = c.kind.id, score = c.score, why = c.why, group = c.kind.group } end
	table.sort(fb, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return a.id < b.id
	end)
	ctx.style._motifCands = fb
	local frame = inputs.frame
	if frame then
		-- a framed town never draws again; frames from before motifs carry none
		for _, id in ipairs(frame.motifs or {}) do
			if MO.BY_ID[id] and not have[id] and #out < MO.MAX then
				out[#out + 1] = { id = id, score = 1, why = "saved", saved = true }
				have[id] = true
			end
		end
		return out
	end
	local free = MO.MAX - MO.slotsTaken(ctx.style, ctx)
	ctx.style._motifFree = free
	if #cands == 0 or free <= 0 then return out end
	-- neighbour diversity: a motif the towns nearby use weighs less
	local dv = DV.factors(inputs.nbrPicks, "motif")
	if next(dv) ~= nil then
		local used = {}
		for _, c in ipairs(cands) do
			local f = dv[c.kind.id]
			if f then c.w = c.w * f; used[c.kind.id] = f end
		end
		DV.note(inputs, "motif", used)
	end
	local seed = ctx.style.seed or 1
	local preferHit = false
	if cm then
		for _, c in ipairs(cands) do
			if prefer[c.kind.id] then c.w, preferHit = c.w * (cm.preferW or 4), true end
		end
	end
	for slot = 1, math.min(free, #MO.SLOT_P) do
		if #cands == 0 then break end
		local best, total = 0, 0
		for _, c in ipairs(cands) do
			if c.w > best then best = c.w end
			total = total + c.w
		end
		if total <= 0 then break end
		if not (slot == 1 and preferHit) and rng.decide(ctx.style.drawV, seed, "motif", slot) >= MO.SLOT_P[slot] * math.min(1, best / MO.P_FULL) then break end
		local r = rng.decide(ctx.style.drawV, seed, "motifPick", slot) * total
		local pi = #cands
		for i, c in ipairs(cands) do
			r = r - c.w
			if r <= 0 then pi = i; break end
		end
		local c = table.remove(cands, pi)
		out[#out + 1] = { id = c.kind.id, score = c.w, why = c.why }
		-- (one motif per group: e.g. the hill climb and the valley fishbone both lay the main street)
		if c.kind.group then
			for i = #cands, 1, -1 do if cands[i].kind.group == c.kind.group then table.remove(cands, i) end end
		end
	end
	return out
end

--- Runs the forced kind's inputs hook (ot_style.resolve, before the shape / form are picked).
function MO.applyInputs(inputs)
	local k = MO.ON and type(inputs) == "table" and inputs.motif and MO.BY_ID[inputs.motif] or nil
	if k and k.inputs then k.inputs(inputs, { id = k.id, forced = true }) end
end

--- Runs the style hooks of style.motifs (steering, reservations).
function MO.applyStyle(p, env)
	if p then p._motifStyleEnv = env end   -- (R5: a fallback kind's style hook runs with the same env)
	for _, m in ipairs(p and p.motifs or {}) do
		local k = MO.BY_ID[m.id]
		if k and k.style then k.style(p, m, env or {}) end
	end
end

--- Runs the plan hooks on master plan mp: every derived kind's (each checks its own condition) and those of
--- style.motifs. Returns the number of hooks run.
function MO.applyPlan(mp, style, env)
	env = env or {}
	local yield = env.yield or function() end
	MO.LAND.yieldFn = env.yield   -- (the overlays may end the driver's slice too, ot_motif_land sliceYield)
	local n, done = 0, {}
	for _, k in ipairs(MO.KINDS) do
		if k.derived and k.plan then
			-- (2026-10-22: the derived kinds' hooks ran without a pause between them, TICKCOST 133 ms in a motif plan)
			yield()
			k.plan(mp, style, { id = k.id, derived = true }, env)
			done[k.id], n = true, n + 1
		end
	end
	for i, m in ipairs(style and style.motifs or {}) do
		local k = MO.BY_ID[m.id]
		if k and k.plan and not done[k.id] then
			-- (env.yield: the driver's plan slice may end between the motifs' plan hooks, ot_core.masterPlan)
			yield()
			k.plan(mp, style, m, env)
			done[k.id], n = true, n + 1
			if MO.FALLBACK and m.geo == nil and m.planWhy ~= nil and not m.forced and not m.derived then
				local m2 = MO.fallback(mp, style, m, env, done)
				if m2 then style.motifs[i] = m2 end
			end
		end
	end
	MO.LAND.yieldFn = nil
	return n
end

--- R5: the next eligible kind for a motif record m whose plan laid nothing (see MO.FALLBACK): runs its style and plan
--- hooks; returns the new record (fallbackFrom = "<old id>:<planWhy>") or nil. Every try is noted on
--- style._motifFallbacks ({ from, to, why, ok }) for the driver's MOTIF event=fallback line.
function MO.fallback(mp, style, m, env, done)
	local inUse, groups = {}, {}
	for _, o in ipairs(style.motifs or {}) do
		inUse[o.id] = true
		local k = MO.BY_ID[o.id]
		if o ~= m and k and k.group then groups[k.group] = true end
	end
	style._motifFallbacks = style._motifFallbacks or {}
	local tries = 0
	for _, c in ipairs(style._motifCands or {}) do
		if tries >= MO.FALLBACK_MAX then break end
		local k2 = MO.BY_ID[c.id]
		if k2 and not inUse[c.id] and not done[c.id] and not (c.group and groups[c.group]) and (k2.plan or k2.style) then
			tries = tries + 1
			local m2 = { id = c.id, score = c.score, why = c.why, saved = m.saved, fallbackFrom = m.id .. ":" .. tostring(m.planWhy) }
			if k2.style then pcall(k2.style, style, m2, style._motifStyleEnv or {}) end
			if k2.plan then
				local okP = pcall(k2.plan, mp, style, m2, env)
				if not okP then m2.geo, m2.planWhy = nil, "error" end
				done[c.id] = true
			end
			local got = k2.plan == nil or m2.geo ~= nil
			local log = style._motifFallbacks
			log[#log + 1] = { from = m.id, to = c.id, why = tostring(m.planWhy), ok = got, toWhy = m2.planWhy }
			if got then return m2 end
		end
	end
	return nil
end

--- DevelopAt points from the dose hooks of style's motifs for a build's edges (at most n, off m beside the streets), and
--- the kind that gave them; empty list when none.
function MO.dose(style, edges, off, n)
	for _, m in ipairs(style and style.motifs or {}) do
		local k = MO.BY_ID[m.id]
		if k and k.dose then
			local ok, pts = pcall(k.dose, m, edges, off, n)
			if ok and type(pts) == "table" and #pts > 0 then return pts, m.id end
		end
	end
	return {}, nil
end

-- plan key prefixes of the kinds with `lock` (their pieces' keys start with these; ot_motif_road)
MO.LOCK_PREFIX = { ribbon_village = "mrb", village_green = "mvg", ring_road = "mrr", station_quarter = "msq",
	culdesac_pods = "mcp", bridgehead_quarter = "mbh" }

--- Key prefixes of the build edges to lock for style's motifs (kinds with `lock`, derived ones too: the station
--- quarter, M3): list (may be empty).
function MO.lockPrefixes(style)
	local out = {}
	if style == nil then return out end
	for _, m in ipairs(MO.list(style)) do
		local k = MO.BY_ID[m.id]
		if k and k.lock and MO.LOCK_PREFIX[m.id] then out[#out + 1] = MO.LOCK_PREFIX[m.id] end
	end
	return out
end

--- The kind's measure for the MOTIF build line, or nil.
function MO.measure(m, env)
	local k = MO.BY_ID[m.id]
	if k == nil or k.measure == nil then return nil end
	local ok, r = pcall(k.measure, env, m)
	if ok then return r end
	return nil
end

--- The source of a motif record: forced / saved / derived / drawn.
function MO.source(m)
	return m.forced and "forced" or (m.saved and "saved" or (m.derived and "derived" or "drawn"))
end

--- `motifs=` text: "id:score:source,..." or "-".
function MO.text(list)
	if type(list) ~= "table" or #list == 0 then return "-" end
	local parts = {}
	for _, m in ipairs(list) do parts[#parts + 1] = string.format("%s:%.2f:%s", m.id, m.score or 0, MO.source(m)) end
	return table.concat(parts, ",")
end

--- The terrain numbers the eligibility reads (MOTIF event=elig line): "grade=,range=,slope=,dr=valley|ridge|-:sa/sb/level,
--- water=kind:dist,cliff=h@d,spit=tip/neck/width,wide=range" ("-" parts when absent).
function MO.terrainText(t, wide)
	if t == nil then return "-" end
	local dr = t.dirRelief
	local w = t.water
	local c = t.cliff
	local sp = t.spit
	return string.format("grade=%.3f,range=%.0f,slope=%.3f,dr=%s,water=%s,cliff=%s,spit=%s,wide=%s",
		t.relief and t.relief.grade or 0, (t.highZ or 0) - (t.lowZ or 0), t.meanSlope or 0,
		dr and string.format("%s:%.0f/%.0f/%.1f", dr.valley and "valley" or (dr.ridge and "ridge" or "-"), dr.sideA or 0,
			dr.sideB or 0, dr.level or 0) or "-",
		w and string.format("%s:%.0f", tostring(w.kind), w.distance or -1) or "-",
		c and string.format("%.0f@%.0f", c.h or 0, c.d or 0) or "-",
		sp and string.format("%.0f/%.0f/%.0f", sp.tip or 0, sp.neck or 0, sp.width or 0) or "-",
		wide and wide.range and string.format("%.0f", wide.range) or "-")
end

--- The ids of the motifs a town's neighbours count (drawn / saved ones: derived looks follow the land anyway).
function MO.ids(list)
	local out = {}
	for _, m in ipairs(list or {}) do
		if not m.derived and not m.forced then out[#out + 1] = m.id end
	end
	return out
end

--- Saved frame field `mo` for the drawn / saved motifs of a style (forced and derived ones are not saved), or nil.
function MO.encode(list)
	local v, mul, n = 0, 1, 0
	for _, m in ipairs(list or {}) do
		local i = MO.INDEX[m.id]
		if i and not m.forced and not m.derived and n < MO.MAX then
			v = v + i * mul
			mul, n = mul * MO.SAVE_BASE, n + 1
		end
	end
	if n == 0 then return nil end
	return v
end

--- The motif ids of a saved `mo` value (unknown indices skipped), or nil for none / an invalid value.
function MO.decode(v)
	v = tonumber(v)
	if v == nil or v <= 0 or v ~= math.floor(v) then return nil end
	local out = {}
	for _ = 1, MO.MAX do
		if v <= 0 then break end
		local i = math.floor(v % MO.SAVE_BASE)
		v = math.floor(v / MO.SAVE_BASE)
		if MO.IDS[i] then out[#out + 1] = MO.IDS[i] end
	end
	return #out > 0 and out or nil
end

---------------------------------------------------------------------------
-- migrated kinds (derived: their behaviour exactly as before M0)

local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- Crescents around a green (ot_crescent, Showcase v9 round): the first style.crescents green reserves get a long
-- smooth arc around them. Derived from the style (EU organic 2, EU extension / MED hill / NA suburb 1, metropolis
-- parks 1). Forced (dev): a style without crescents gets one (its first reserve becomes a crescent meadow).
MO.register({
	id = "crescent",
	derived = true,
	free = true,
	eligible = function(ctx)
		local p = ctx.style
		if (p.crescents or 0) <= 0 then return 0 end
		local n = 0
		for _, gr in ipairs(p.greens or {}) do if gr[4] then n = n + 1 end end
		if n == 0 then return 0 end
		return 1, "style:crescents=" .. n
	end,
	style = function(p, m, env)
		if (p.crescents or 0) > 0 or not env.greenReserves then return end
		p.crescents = 1
		p.greens = env.greenReserves(p, math.max(1, #(p.greens or {})))
	end,
	plan = function(mp, style, m, env)
		-- (exactly the pre-M0 ot_core.masterPlan rule)
		if env.green and (style.crescents or 0) > 0 then CR.apply(mp, style) end
	end,
	measure = function(env, m)
		local cs = env.mp and env.mp.crescents
		if cs == nil or #cs == 0 then return nil end
		local edges, total, houses = 0, 0, 0
		for _, e in ipairs(env.inc and env.inc.edges or {}) do
			if type(e.key) == "string" and e.key:match("^arc%d") then edges = edges + 1 end
		end
		local g = env.g
		for _, e in ipairs(g and g.edges or {}) do
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			if a and b then
				local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
				for _, c in ipairs(cs) do
					if math.abs(dist(mx, my, c[1], c[2]) - c[3]) < 15 then total = total + 1; break end
				end
			end
		end
		for _, p in ipairs(env.pts or {}) do
			for _, c in ipairs(cs) do
				local d = dist(p[1], p[2], c[1], c[2])
				if d >= c[3] and d <= c[3] + 60 then houses = houses + 1; break end
			end
		end
		return { edges = edges, total = total + edges, houses = houses, text = #cs .. " meadows" }
	end,
})

-- Hill road (round 5, 2026-10-13; the user on Middlewich: "the one street up into the hills is very cool"): a hillside
-- town drawn linear along its contour (ot_shape HILLSIDE_GAIN), whose arm climbs where the contour bends; measured by
-- ot_metrics.hillRoad (SHAPE hillRoad=). Derived from the shape. Forced (dev): the shape linear (its strongest
-- candidate: the contour on a slope). The deliberate climb is the drawn kind hill_climb (M1, ot_motif_land).
MO.register({
	id = "hill_road",
	derived = true,
	eligible = function(ctx)
		local sh = ctx.style.shape
		if sh == nil or sh.id ~= "linear" or not tostring(sh.reason or ""):find("hillside: along the contour", 1, true) then
			return 0
		end
		return 1, "shape:hillside_contour"
	end,
	inputs = function(inputs, m)
		if inputs.shape == nil then inputs.shape = "linear" end
	end,
	measure = function(env, m)
		if env.MT == nil or env.SH == nil then return nil end
		local sh = env.style and env.style.shape
		local h = env.MT.hillRoad(env.g, sh, env.pts, env.sampler)
		if h == nil then return nil end
		local edges = 0
		for _, e in ipairs(env.inc and env.inc.edges or {}) do
			if e.p0 and e.p1 and h.arm then
				local i = env.SH.armAt(sh, (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2)
				if i == h.arm then edges = edges + 1 end
			end
		end
		return { edges = edges, total = h.edges, houses = h.houses, text = env.MT.hillText(h) }
	end,
})

-- M1 (2026-10-13): the terrain / water kinds (drawn): hill_climb, valley_fishbone, harbour_crescent, fishing_village
local LAND = ug_require "square_organic_towns::/organic_towns/ot_motif_land.lua"
LAND.registerAll(MO)
MO.LAND = LAND
-- M2 (2026-10-13): the road / village kinds (drawn): ribbon_village, village_green, crossroads_hamlet
local ROAD = ug_require "square_organic_towns::/organic_towns/ot_motif_road.lua"
ROAD.registerAll(MO)
-- M3 (2026-10-13): the town-structure / era kinds: ring_road, station_quarter (derived), workers_terraces, culdesac_pods
local TOWN = ug_require "square_organic_towns::/organic_towns/ot_motif_town.lua"
TOWN.registerAll(MO)
-- M4 (2026-10-13): more terrain kinds: switchbacks, ridge_street, headland_street (drawn), bridgehead_quarter (derived,
-- extra)
local RELIEF = ug_require "square_organic_towns::/organic_towns/ot_motif_relief.lua"
RELIEF.registerAll(MO)
-- final-test round (2026-10-13): peninsula_tip (drawn, group point; ot_motif_point)
local POINT = ug_require "square_organic_towns::/organic_towns/ot_motif_point.lua"
POINT.registerAll(MO)

return MO
