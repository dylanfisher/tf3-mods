-- DEV ONLY (never upload). Organic Towns dev tools: the task runner behind the HUD window. Logic only: the main
-- mod's driver module (D), its engine (E), saved-state (SV), graph (OG) and proposal (PR) modules, the hooks table
-- (H), the dev engine extras (X) and the undo planner (UN) are injected, so tests/square_organic_towns_dev drive it with fakes.
--
-- Where it runs: the dev game script's guiUpdate / guiHandleEvent (Main Thread). Only there do the main mod's
-- facts hold (plans/square_organic_towns/HANDOFF.md): runFn's region global (SQOT_CONFIG) is visible and
-- commands get callbacks. It is (very likely) the same Lua state as the main mod's game script, so the hooks
-- table and the main driver instance (H.main) are shared; the status shows whether they are (main=yes/no).
--
-- It reuses the main driver: a second Driver instance (log tag [SQOT_DEV]) runs single jobs through the main
-- stages (assess -> terrain -> snapshot -> plan -> send -> wait) with startJob/advance: forced (no needs-room
-- test), another style mode, or a dry run that stops after the pre-check. Forced growth is the main engine's
-- growTown (makeTownUpdateSizeCmd, updateAllBuildings) as the probe's Grow here: first pass x factor, then
-- passes at the reached size.
--
-- One task at a time. While a task is queued or runs, H.devBusy holds the main driver (no new checks, no testing
-- growth); a task starts only when the main driver has no job or command running. Single jobs (Grow now, Plan
-- only, Fast-forward) run on the dev driver, one command in flight.
--
-- Concurrent builds (Showcase v7+, buildBatch / poolStep): a showcase round's town jobs run side by side on a small
-- pool of driver instances (R.BUILD_INFLIGHT, one job slot each) that share the dev driver's per-town state
-- (towns: history, excludes, samplers, fill records; counts; config), so a town's job reads and writes the same
-- state as before. Each job keeps its own stages, callback and refusal handling (prune / halve / joint-rule
-- replan / fill) and reports through its own onDone; a town has at most one job per batch. The towns are 2.5 km
-- apart, so their proposals can't collide. Per tick: every job waiting for a callback is checked (cheap), CPU
-- stages (assess, snapshot, plan slices, pre-checks) run while R.TICK_BUDGET_US lasts (at least one per tick).
--
-- Simulate natural growth (otd_simgrow, deps.SG) is not a task: it ticks beside the task queue and sets H.devBusy
-- only during its build rounds, so the main driver keeps running normally (its needs-room trigger reacts to the houses the town
-- developer adds). It sends makeTownUpdateSizeCmd(town, sizeFactors, false), as the game's town growth does, and in
-- Fast fill years (updateAllBuildings = true) for towns whose houses lag. At each chunk's end (every fillEvery years,
-- before the fill) a build round (simRoundStart / simRoundTick, 2026-10-13) holds the main driver (H.devBusy) and runs
-- the main mod's normal check -> plan -> build on every grown town, concurrently on the "simPool" drivers that share the
-- main driver's state; with the round off, the old wait for the main driver's own checks. The main driver stays held
-- through the fill after a round (simHolds, 2026-10-14), and a town whose round part ended is filled while the round
-- goes on elsewhere (simRoundReady / simRoundFilling). Build out (SG.BUILDOUT): chunks of years, the main mod's upward /
-- level-weight gaps lowered for the run (simUpPace); optional game date (X.setYear). During a run the main
-- driver checks faster (D.CHECK_S, ot_assess COOLDOWN_S scaled; both restored at Stop) and the game runs at
-- SG.SIM_SPEED (the previous speed restored at Stop).

local R = {}

R.PREFIX = "[SQOT_DEV]"
R.LOG_MAX = 18
R.GROW_PASSES = 3        -- forced growth passes after each increment (probe Grow here: 4)
R.GROW_PASS_S = 0        -- no pause after a pass (UpdateSize adds the buildings at once; callbacks still awaited)
R.FAST_PASS_S = 0        -- fast-forward: no pause after a town's growth pass
R.GROW_CAP = 50          -- size factors never above this
R.CMD_TIMEOUT_S = 30
R.BATCH_TIMEOUT_S = 120  -- a batch (one command per town): v7's 35-town growth batches took 14-30 s and growing
R.MARKER_S = 30          -- plan markers stay this long
R.ALL_TOWNS_MAX = 40     -- "Tour all towns": the biggest towns of the map, at most this many (Real map test)
R.BUILD_INFLIGHT = 12    -- showcase: town jobs at once (builds / fills in flight; v6 ran them one by one, ~0.6 s each)
R.TICK_BUDGET_US = 12000 -- ... CPU stages of those jobs per tick (one at least; v7 logged 1.2-5 s of CPU per round)
R.POOL_MAX = 24          -- the simulation's build round: jobs at once at most (SG.ROUND_INFLIGHT capped to this; each
                         -- slot is one more driver instance, CPU stays within TICK_BUDGET_US per tick)

local Runner = {}
Runner.__index = Runner

--- deps = { D, E, SV, OG, PR, H, X, UN } + for the showcase { ST, I, MT (main mod), S, L, SC (dev) } + for the
--- roundabout probe { RB (otd_roundabout), rbGeom (square_roundabouts' geometry module or nil), rbWhy }.
function R.new(deps)
	local r = setmetatable({
		D = deps.D, E = deps.E, SV = deps.SV, OG = deps.OG, PR = deps.PR, H = deps.H, X = deps.X, UN = deps.UN,
		ST = deps.ST, I = deps.I, MT = deps.MT, S = deps.S, L = deps.L, SC = deps.SC, show = nil,
		NM = deps.NM, RB = deps.RB, rbGeom = deps.rbGeom, rbWhy = deps.rbWhy, ND = deps.ND, SG = deps.SG, A = deps.A, sim = nil,
		UP = deps.UP,
		lines = {}, version = 0, tasks = {}, task = nil, selected = nil, info = nil, plan = nil, configured = false,
		taskSeq = 0, needInspect = false, styleMode = "main", motif = nil,
		-- showcase options (set before a run; the run keeps the values it started with)
		-- ringMode "oneway" (the engine's one-way ring lane pattern, docs/findings/roads.md) by default, "town" the
		-- two-way town street ring (also the fallback when every one-way size is refused)
		showOpts = { fill = false, freeze = false, ringMode = "oneway", offset = nil, shapes = true,
			density = true, settle = "passes", settleCap = 10, settleForce = true, tourAfter = true },
	}, Runner)
	if deps.S then
		r.showOpts.settle = deps.S.SETTLE_DEFAULT or r.showOpts.settle
		r.showOpts.settleCap = deps.S.SETTLE_CAP_DEFAULT or r.showOpts.settleCap
	end
	local Ew = setmetatable({ log = function(l) r:push(l) end }, { __index = deps.E })
	r.driver = deps.D.new(Ew, R.PREFIX)
	r.driver.phase = "manual"
	r.driver.verbose = true   -- every stage of a dev job is logged ([SQOT_DEV] CHECK / PLAN / SEND ...)
	-- per-edge diagnosis after a Construction_Not_Possible pre-check and on every Plan only (DIAG / DIAGSUM;
	-- the main driver too while the dev mod is loaded: same hooks table)
	r.H.diagnose = true
	return r
end

---------------------------------------------------------------------------
-- log + status

function Runner:push(line)
	if self.X and self.X.log then self.X.log(line) elseif self.E.log then self.E.log(line) end
	self.lines[#self.lines + 1] = line
	while #self.lines > R.LOG_MAX do table.remove(self.lines, 1) end
	self.version = self.version + 1
end

function Runner:log(what, fields)
	local l = self.D.line(what, fields, R.PREFIX)
	self:push(l)
	return l
end

function Runner:changed()
	self.version = self.version + 1
end

--- The main game script's driver, when it lives in this Lua state (else nil).
function Runner:main()
	local m = self.H.main
	if m ~= nil and m ~= self.driver then return m end
	return nil
end

--- The main mod's saved state (via its driver), or nil when not visible.
function Runner:saved()
	local m = self:main()
	return m and m.saved or nil
end

--- Saved state for dev jobs: the main mod's, or one where every town counts as new.
function Runner:savedForJobs()
	return self:saved() or { v = self.SV.VERSION, known = {}, frames = {} }
end

function Runner:ensureConfig()
	if self.configured then return end
	self.driver:loadConfig()
	self.configured = true
	-- (the dev driver's new-map gate and list folder: the main driver's, when it runs in this state)
	local m = self:main()
	if m then
		if self.driver.newMap == nil then self.driver.newMap = m.newMap end
		self.driver.listDir = self.driver.listDir or m.listDir
	end
end

local function taskText(t)
	if t == nil then return "" end
	local s = t.label or t.kind
	if t.kind == "grow" then s = string.format("%s %d/%d (%s)", s, t.k or 0, t.n, t.phase or "-")
	elseif t.kind == "fast" then s = string.format("%s round %d/%d town %d/%d (%s)", s, t.round or 0, t.rounds,
		t.idx or 0, t.towns and #t.towns or 0, t.phase or "-")
	elseif t.kind == "showcase" then s = string.format("%s N=%d (%s%s)", s, t.n, t.phase or "-",
		t.pool and string.format(", builds %d/%d", t.pool.done, #t.pool.items) or "") end
	return s
end

--- Plain status table for the HUD (fireReactEvent / guiHandleEvent return).
function Runner:status()
	local m, H = self:main(), self.H
	local st = {
		v = self.version,
		main = m ~= nil,
		mainPhase = m and m.phase or "-",
		mainOff = m and m.offReason or "",
		mainCounts = m and string.format("checks %d, builds %d, fails %d, refused %d", m.counts.checks, m.counts.builds,
			m.counts.fails, m.counts.refused) or "",
		paused = H.paused == true,
		ownJoins = self.driver.allowNoConfig == true,
		motif = self.motif or "main",
		player = H.player == true,
		debug = H.debug == nil and "param" or (H.debug and "on" or "off"),
		busy = taskText(self.task),
		queue = #self.tasks,
		log = {},
		town = "",
		townLines = {},
		plan = "",
		show = (self.SC and self.show) and self.SC.status(self, self.show) or nil,
		showOpts = { fill = self.showOpts.fill, freeze = self.showOpts.freeze, ringMode = self.showOpts.ringMode,
			shapes = self.showOpts.shapes ~= false,
			density = self.showOpts.density ~= false, settle = self.showOpts.settle or "off",
			settleCap = self.showOpts.settleCap, settleForce = self.showOpts.settleForce == true,
			tourAfter = self.showOpts.tourAfter == true,
			offset = self.showOpts.offset and string.format("%d,%d", self.showOpts.offset[1], self.showOpts.offset[2]) or nil },
		allTowns = self.allTownList,
		rb = self.rbGeom ~= nil,
		rbWhy = self.rbWhy,
		rbProbe = self.rbProbe and self.rbProbe.text or nil,
		sim = self.sim and self.sim:status() or nil,
		-- (2026-10-14: Quick / Build out wait for the main mod's head start, HEAD done)
		mainHead = m ~= nil and m.head ~= nil,
	}
	for i, l in ipairs(self.lines) do st.log[i] = l end
	if self.info then
		st.town = self.info.name
		for i, l in ipairs(self.info.lines) do st.townLines[i] = l end
	end
	if self.plan then
		st.plan = string.format("%s: %d edges, style %s, %s", self.plan.name, #self.plan.edges, self.plan.style, self.plan.summary)
	end
	return st
end

---------------------------------------------------------------------------
-- Tour all towns (Real map test, v8 round): every town of any map, biggest first

--- The main driver's style table for town t (any cached mode), or nil.
local function mainStyle(m, t)
	local s = m and m.towns and m.towns[t]
	if s == nil or s.styles == nil then return nil end
	for _, st in pairs(s.styles) do return st end
	return nil
end

--- Street measures of a driver.measure result: { len (m of town street), emptyLen / emptyEdges (edges without a
--- built lot of this town), deadEnds (nodes with one edge) } (2026-10-14). With ctx = { any = { [edge] = houses of
--- every town }, mod = { [edge] = true } } also (NEXT_PHASE_BRIEF 52.3: a created town's snapshot holds its parent's
--- streets, whose houses are the parent's, so emptyLen read 31.9 km for a 40-building Works): bareLen (no house of any
--- town), foreignLen (only other towns' houses), modLen (mod streets: locked or built this session by the main mod).
function R.streetMeasures(m, ctx)
	local out = { len = 0, emptyLen = 0, emptyEdges = 0, deadEnds = 0, bareLen = 0, foreignLen = 0, modLen = 0 }
	local deg = {}
	local any, mod = ctx and ctx.any or nil, ctx and ctx.mod or nil
	for _, ed in ipairs(m and m.edges or {}) do
		local L = math.sqrt((ed.p1[1] - ed.p0[1]) ^ 2 + (ed.p1[2] - ed.p0[2]) ^ 2)
		out.len = out.len + L
		if ((m.builtBy and m.builtBy[ed.id]) or 0) == 0 then
			out.emptyLen = out.emptyLen + L
			out.emptyEdges = out.emptyEdges + 1
			if any ~= nil then
				if (any[ed.id] or 0) > 0 then out.foreignLen = out.foreignLen + L else out.bareLen = out.bareLen + L end
			end
		end
		if ed.locked == true or (mod ~= nil and mod[ed.id]) then out.modLen = out.modLen + L end
		if ed.n0 then deg[ed.n0] = (deg[ed.n0] or 0) + 1 end
		if ed.n1 then deg[ed.n1] = (deg[ed.n1] or 0) + 1 end
	end
	for _, d in pairs(deg) do if d == 1 then out.deadEnds = out.deadEnds + 1 end end
	return out
end

--- Measures every town (driver.measure), keeps the R.ALL_TOWNS_MAX biggest, logs one ALLTOWN line each (size,
--- extent, street orientation, density, the main mod's style / form / shape / metropolis when it has planned there)
--- and puts them in the status (allTowns) for the HUD's "Tour all towns".
function Runner:allTowns(now)
	local E, d, MT = self.E, self.driver, self.MT
	local list = {}
	for _, t in ipairs(E.towns() or {}) do
		local okM, m = pcall(d.measure, d, t)
		if okM and m then list[#list + 1] = { t = t, m = m } end
	end
	table.sort(list, function(a, b)
		if a.m.buildings ~= b.m.buildings then return a.m.buildings > b.m.buildings end
		return a.t < b.t
	end)
	local main = self:main()
	local out = {}
	-- (NEXT_PHASE_BRIEF 52.3: the houses of every measured town per edge, and the main mod's session streets, for the
	-- bareLen / foreignLen / modLen fields)
	local sctx = { any = {}, mod = {} }
	for _, it in ipairs(list) do
		for id, c in pairs(it.m.builtBy or {}) do sctx.any[id] = (sctx.any[id] or 0) + (tonumber(c) or 0) end
	end
	for _, st in pairs(main and main.towns or {}) do
		if type(st) == "table" and type(st.own) == "table" then for id in pairs(st.own) do sctx.mod[id] = true end end
	end
	-- (2026-10-14 late: industries in each town and how many it encloses, `ind=`; its building levels, `lvl=`; both
	-- with the main mod off: the driver's engine reads them)
	local DE = d.E or E
	local indAll = nil
	if DE.industries then
		local okI, all = pcall(DE.industries)
		if okI then indAll = all end
	end
	for i = 1, math.min(#list, R.ALL_TOWNS_MAX) do
		local t, m = list[i].t, list[i].m
		local cx, cy
		if E.boxCentre then cx, cy = E.boxCentre(t) end
		if cx == nil or cy == nil then cx, cy = m.ext.cx, m.ext.cy end
		local segs = {}
		for _, ed in ipairs(m.edges or {}) do segs[#segs + 1] = { ed.p0[1], ed.p0[2], ed.p1[1], ed.p1[2] } end
		local o = (MT and MT.orientationSegs) and MT.orientationSegs(segs, cx, cy) or nil
		local st = mainStyle(main, t)
		local dens = (m.ext.r or 0) > 0 and m.buildings / (math.pi * m.ext.r * m.ext.r / 10000) or 0
		local sm = R.streetMeasures(m, sctx)
		self:log("ALLTOWN", { { "n", i }, { "town", t }, { "name", E.name(t) }, { "buildings", m.buildings },
			{ "edges", #segs }, { "r", m.ext.r }, { "capacity", m.caps and m.caps.actual or 0 },
			{ "orient", (MT and MT.orientText) and MT.orientText(o) or "-" }, { "dens", string.format("%.1f", dens) },
			{ "style", st and st.id or "-" }, { "form", st and st.form and st.form.id or "-" },
			{ "shape", st and st.shape and st.shape.id or "-" }, { "metro", st and st.metro and st.metro.variant or "-" },
			-- (2026-10-13, main mod round 5) land spread: ratio / % beyond 1.5 x the equal-area disc / lobes
			{ "spread", (MT and MT.landSpread) and MT.spreadText(MT.landSpread(m.pts, cx, cy)) or "-" },
			-- (2026-10-13, main mod M0) the town's motifs (ot_motif: id:score:source)
			{ "motifs", (st and self.D.motifText) and self.D.motifText(st) or "-" },
			-- (2026-10-13, main mod phase F) forest share around the town and its mode (ot_forest: share:hug|clear|none)
			{ "forest", (st and self.D.forestText) and self.D.forestText(st) or "-" },
			-- (2026-10-13, main mod later-ideas phase) upward doses / persons per building, meadow rule, frames, tree-lined
			-- entry edges (D.laterText)
			{ "later", self.D.laterText and self.D.laterText(main and main.towns and main.towns[t], st, m) or "-" },
			-- (2026-10-14, the vanilla comparison: also with the main mod off) street length, unhoused street length /
			-- edges, dead ends, persons per building, free lots share
			{ "streetLen", string.format("%.0f", sm.len) }, { "emptyLen", string.format("%.0f", sm.emptyLen) },
			{ "emptyEdges", sm.emptyEdges }, { "deadEnds", sm.deadEnds },
			{ "bareLen", string.format("%.0f", sm.bareLen) }, { "foreignLen", string.format("%.0f", sm.foreignLen) },
			{ "modLen", string.format("%.0f", sm.modLen) },
			{ "pb", m.buildings > 0 and m.caps and string.format("%.2f", (m.caps.actual or 0) / m.buildings) or "-" },
			{ "freeLots", m.lots and string.format("%d/%d", m.lots.free or 0, (m.lots.free or 0) + (m.lots.built or 0)) or "-" },
			{ "ind", (indAll and self.D.industryEnclosure) and select(3, self.D.industryEnclosure(indAll, cx, cy, m.ext.r,
				m.pts, segs)) or "-" },
			{ "lvl", (DE.levelInfo and self.D.levelText) and self.D.levelText(select(2, pcall(DE.levelInfo, t))) or "-" },
			-- (2026-10-14, main mod strong characters: the kind / densify, the one-way rings built)
			{ "char", (main and main.charTownText) and (select(1, main:charTownText(t))) or "-" },
			{ "roundabouts", (main and main.charTownText) and (select(2, main:charTownText(t))) or "-" },
			-- (§66: the town's R/C/I target shares, its usage as the base game reads it, the aim and lean, and the main
			-- driver's weighting state: smoothed usage, steps, last reason)
			{ "rci", self.D.rciReadout and self.D.rciReadout(DE, t, main) or "-" },
			{ "x", cx }, { "y", cy } })
		out[#out + 1] = { key = "ALL_" .. t, label = E.name(t), x = cx, y = cy, town = t, kind = "all" }
	end
	self.allTownList = out
	self:log("ALLTOWNS", { { "towns", #list }, { "tour", #out } })
end

---------------------------------------------------------------------------
-- inspector

local function pct(a, b)
	if not b or b <= 0 then return "?" end
	return string.format("%.0f %%", 100 * a / b)
end

--- History records of a town, newest last: { rec, owner (driver) } from the main driver and ours.
function Runner:records(t)
	local out = {}
	local owners = { self.driver }
	if self:main() then owners[2] = self:main() end
	for _, d in ipairs(owners) do
		local s = d and d.towns and d.towns[t]
		if s and s.history then
			for _, rec in ipairs(s.history) do out[#out + 1] = { rec = rec, owner = d } end
		end
	end
	table.sort(out, function(a, b) return (a.rec.us or 0) < (b.rec.us or 0) end)
	return out
end

function Runner:styleText(st)
	local outer = st.outer and string.format(", outer %s from %.0f m", st.outer.id, st.outer.from or 0) or ""
	return string.format("%s%s, axis %.1f deg (%s), templates %s, streets %s; style from %s%s", st.id, outer,
		math.deg(st.axis or 0), tostring(st.axisSource), st.newTemplates and "new" or "old", tostring(st.hierarchy or "-"),
		tostring(st.styleSource or "-"), (st.styleSource == "site" and st.styleWhy) and (" (" .. st.styleWhy .. ")") or "")
end

--- Inspector lines for the selected town (one-shot: measure, terrain once, snapshot, styles).
function Runner:inspect(now)
	local t = self.selected
	if t == nil then return end
	self:ensureConfig()
	local d, E, SV = self.driver, self.E, self.SV
	local name = E.name(t)
	local lines = { string.format("%s (town %d)", name, t) }
	local m, reason, n = d:measure(t)
	local fields = { { "town", t }, { "name", name } }
	if m == nil then
		lines[#lines + 1] = string.format("Too few buildings for an extent (%s: %s)", tostring(reason), tostring(n))
	else
		local l, c = m.lots, m.caps
		lines[#lines + 1] = string.format("Buildings %d, extent r %.0f m, street edges %d (%d with lots, %d not adopted yet)",
			m.buildings, m.ext.r, l.edges, l.withParcels, l.unparcelled)
		lines[#lines + 1] = string.format("Lots: %d built, %d free (%d in gaps); open frontage %.1f (%d edges + %d virtual)",
			l.built, l.free, l.gaps, l.open, l.openEdges, l.virtual)
		if c then
			lines[#lines + 1] = string.format("Capacity %.0f / %.0f (%s), sizeFactors %s", c.actual, c.target, pct(c.actual, c.target),
				table.concat((function()
					local o = {}
					for i, f in ipairs(c.sizeFactors or {}) do o[i] = string.format("%.2f", f) end
					return o
				end)(), "/"))
		end
		local why = {
			low = string.format("YES: open frontage %.1f < need %.1f", l.open, m.threshold),
			open = string.format("no: open frontage %.1f >= need %.1f", l.open, m.threshold),
			over = "no: well over its capacity target (shrinking)",
			demand = string.format("YES: growth demand %.1f edges, own open frontage %s < lead %.1f",
				m.dem and m.dem.edges or 0, tostring(l.ownOpen), m.dem and m.dem.lead or 0),
			ahead = string.format("no: growth demand %.1f edges, but own open frontage %s >= lead %.1f",
				m.dem and m.dem.edges or 0, tostring(l.ownOpen), m.dem and m.dem.lead or 0),
		}
		lines[#lines + 1] = "Needs room: " .. (why[m.why] or tostring(m.why))
		-- (§66: R/C/I target shares, the base game's usage, the weighting's aim and lean, the main driver's state)
		if self.D.rciReadout then
			lines[#lines + 1] = "R/C/I by deliveries: " .. self.D.rciReadout(d.E or E, t, self:main())
			fields[#fields + 1] = { "rci", self.D.rciReadout(d.E or E, t, self:main()) }
		end
		local job = { town = t, ext = m.ext, edges = m.edges, caps = c, styleMode = "main" }
		local s = d:townState(t)
		if not s.stats then d:terrain(job) end
		local g, _, joinable, noJoin = d:snapshotGraph(job)
		local saved = self:saved()
		local style = d:styleFor(job, g, saved)
		lines[#lines + 1] = "Main mod style: " .. self:styleText(style)
		lines[#lines + 1] = "Motifs: " .. ((self.D.motifText and self.D.motifText(style)) or "-")
			.. (self.motif and (" (Grow now / Plan only force " .. self.motif .. ")") or "")
		if self.styleMode ~= "main" then
			local sel = d:styleFor({ town = t, ext = m.ext, edges = m.edges, caps = c, styleMode = self.styleMode }, g, saved)
			lines[#lines + 1] = "Picked style (" .. self.styleMode .. "): " .. self:styleText(sel)
		end
		local de = #self.OG.deadEnds(g)
		lines[#lines + 1] = string.format("Dead ends: %d joinable of %d (%s)", joinable, de, noJoin ~= "" and noJoin or "-")
		fields[#fields + 1] = { "buildings", m.buildings }
		fields[#fields + 1] = { "open", l.open }
		fields[#fields + 1] = { "need", m.threshold }
		fields[#fields + 1] = { "needsRoom", m.needs }
		fields[#fields + 1] = { "why", m.why }
		fields[#fields + 1] = { "style", style.id }
		fields[#fields + 1] = { "joinable", joinable }
	end
	local saved = self:saved()
	if self:main() == nil then
		lines[#lines + 1] = "Saved grid frame: unknown (main driver not visible in this Lua state)"
	else
		local fr = SV.frame(saved, t)
		lines[#lines + 1] = fr and string.format("Saved grid frame: axis %.2f deg, origin %.0f, %.0f", math.deg(fr.axis),
			fr.origin[1], fr.origin[2]) or "Saved grid frame: none yet (set by the first build)"
		local known = SV.knownSet(saved)
		if d.opts and d.opts.actOn == "new" then
			lines[#lines + 1] = known == nil and "New towns only: not initialised yet"
				or (known[t] and "Existing town: New towns only leaves it alone" or "New town: the main mod acts on it")
		end
	end
	local recs = self:records(t)
	local mainS = self:main() and self:main().towns[t]
	local devS = d.towns[t]
	lines[#lines + 1] = string.format("Increments this session: main %d, dev %d; undoable %d",
		mainS and mainS.builds or 0, devS and devS.builds or 0, #recs)
	local cfg = d.cfg or {}
	lines[#lines + 1] = string.format("Map: region %s, profile %s, nameList %s, climate %s; main driver %s%s",
		tostring(d.region), tostring(d.profile), tostring(cfg.nameList or "nil"), tostring(cfg.climate or "nil"),
		self:main() and self:main().phase or "not visible",
		(self:main() and self:main().offReason) and (" (" .. self:main().offReason .. ")") or "")
	self.info = { town = t, name = name, lines = lines }
	self:log("INSPECT", fields)
	self:changed()
end

---------------------------------------------------------------------------
-- task steps

function Runner:startJob(t, town, now, o)
	t.jobOutcome, t.job = nil, nil
	o.onDone = function(job, outcome)
		t.job, t.jobOutcome = job, outcome
	end
	local job = self.driver:startJob(town, now, o)
	if job == nil then return false end
	t.waitJob = true
	return true
end

--- Pool driver i: a Driver sharing the dev driver's per-town state and config (one job slot each). owner (the
--- simulation's build round: the main driver) shares its state, log prefix and engine instead; set names the pool
--- ("pool" for tasks, "simPool" for the build round, so the two never share a slot).
function Runner:poolDriver(i, owner, set)
	set = set or "pool"
	self[set] = self[set] or {}
	local m = owner or self.driver
	local d = self[set][i]
	if d == nil then
		-- (the build round's drivers log under the main driver's prefix: nil = "[SQOT]"; run 2026-10-13_2240_sqot-dev
		-- logged the main mod's own round builds as [SQOT_DEV] because `owner.prefix or R.PREFIX` fell through)
		local prefix = R.PREFIX
		if owner then prefix = owner.prefix end
		d = self.D.new(owner and owner.E or self.driver.E, prefix)
		self[set][i] = d
		if owner then self:simWrapMeasure(d) end
	end
	d.phase, d.verbose = "manual", owner == nil or owner.verbose == true
	d.towns, d.counts, d.sched = m.towns, m.counts, m.sched
	d.opts, d.cfg, d.region, d.profile = m.opts, m.cfg, m.region, m.profile
	d.allowNoConfig = m.allowNoConfig
	-- the map's session facts the main driver learnt at its start (run 2026-10-13_2240_sqot-dev: the round drivers had
	-- no newMap, so every Works said notNewMap on a fresh map and marked the shared town state done, the main driver's
	-- own demand builds then skipped them silently): the new-map gate and the name list folder
	local src = self:main() or m
	d.newMap = m.newMap
	if d.newMap == nil then d.newMap = src.newMap end
	d.listDir = m.listDir or src.listDir
	return d
end

--- Concurrent town jobs (showcase rounds): items = { { town, opts (startJob options), key } }, at most cap
--- (R.BUILD_INFLIGHT) at once on the pool drivers. onResult(item) runs once per item as soon as its job ended
--- (item.outcome, item.job). The task waits until every started job ended (t.pool is nil again). Stop: no new
--- jobs start, the running ones finish.
--- owner / set: Runner:poolDriver (the simulation's build round: the main driver, "simPool"); items may be appended
--- while the batch runs (onResult: a town's next job).
function Runner:buildBatch(t, items, onResult, cap, owner, set)
	if owner == nil then self:ensureConfig() end
	t.pool = { items = items, next = 1, slots = {}, cap = math.max(1, cap or R.BUILD_INFLIGHT), onResult = onResult,
		peak = 0, rot = 0, done = 0, cpuMax = 0, owner = owner, set = set }
	self.lastPool = nil
end

local function copyOpts(o)
	local c = {}
	for k, v in pairs(o or {}) do c[k] = v end
	return c
end

--- One tick of the job pool: start jobs on free slots, check the waiting ones, CPU stages within the budget.
function Runner:poolStep(t, now)
	local P = t.pool
	local saved = self:savedForJobs()
	if t.abort then P.next = #P.items + 1 end
	for i = 1, P.cap do
		if P.slots[i] == nil and P.next <= #P.items and P.canStart then
			-- (the build round: the first waiting item that may start now goes next; none: wait for a slot to end)
			local k = P.next
			while k <= #P.items and not P.canStart(P.items[k], P.slots) do k = k + 1 end
			if k > #P.items then break end
			P.items[P.next], P.items[k] = P.items[k], P.items[P.next]
		end
		if P.slots[i] == nil and P.next <= #P.items then
			local it = P.items[P.next]
			P.next = P.next + 1
			local d = self:poolDriver(i, P.owner, P.set)
			local o = copyOpts(it.opts)
			o.onDone = function(job, outcome) it.job, it.outcome = job, outcome end
			if d:startJob(it.town, now, o) == nil then
				it.outcome, it.why = "fail", "poolBusy"
				P.done = P.done + 1
				pcall(P.onResult, it)
			else
				P.slots[i] = { d = d, it = it }
			end
		end
	end
	local running = 0
	for i = 1, P.cap do if P.slots[i] then running = running + 1 end end
	P.peak = math.max(P.peak, running)
	local E = self.E
	local clock = E.nowUs or function() return now end
	local t0 = clock()
	local cpu = 0
	P.rot = P.rot % P.cap + 1
	for k = 0, P.cap - 1 do
		local i = (P.rot + k - 1) % P.cap + 1
		local s = P.slots[i]
		if s then
			local job = s.d.job
			-- (a build whose callback came counts as CPU: BUILT / recordBuilt / the fill plan run in that advance)
			local waiting = job ~= nil and ((job.stage == "wait" and job.result == nil) or job.stage == "fill")
			if job == nil or waiting or cpu == 0 or clock() - t0 < R.TICK_BUDGET_US then
				if job ~= nil and not waiting then cpu = cpu + 1 end
				if job ~= nil then s.d:advance(now, saved) end
			end
			if s.it.outcome ~= nil or s.d.job == nil then
				P.slots[i] = nil
				if s.it.outcome == nil then s.it.outcome, s.it.why = "fail", "noOutcome" end
				P.done = P.done + 1
				local ok, err = pcall(P.onResult, s.it)
				if not ok then self:log("ERROR", { { "stage", "poolResult" }, { "town", s.it.town }, { "err", err } }) end
			end
		end
	end
	P.cpuMax = math.max(P.cpuMax, cpu)
	if P.next > #P.items and next(P.slots) == nil then
		if P.owner == nil then self.lastPool = { peak = P.peak, cap = P.cap, done = P.done, cpuMax = P.cpuMax } end
		t.lastPool = { peak = P.peak, cap = P.cap, done = P.done, cpuMax = P.cpuMax }
		t.pool = nil
	end
end

--- One forced growth pass of a town: size factors x mult (1 = again at the reached size).
function Runner:growPass(t, town, mult, sleepS)
	local caps = self.E.townCaps(town)
	if caps == nil or caps.sizeFactors == nil or caps.sizeFactors[1] == nil then
		self:log("GROW", { { "town", town }, { "ok", false }, { "why", "noTown" } })
		return false
	end
	local f = {}
	for i = 1, 3 do f[i] = math.min(R.GROW_CAP, (caps.sizeFactors[i] or 1) * mult) end
	self:log("GROW", { { "town", town }, { "name", self.E.name(town) }, { "x", mult }, { "sizeFactors", caps.sizeFactors },
		{ "to", f }, { "cap", string.format("%.0f/%.0f", caps.actual or 0, caps.target or 0) } })
	t.cmdDone, t.waitCmd, t.cmdUs, t.sleepAfter = nil, true, self.nowUs, sleepS
	self.E.growTown(town, f, function(success)
		t.cmdDone = success == true
		if not success then self:log("GROW", { { "town", town }, { "ok", false } }) end
	end)
	return true
end

--- One forced growth pass to absolute size factors max(current, target) (showcase: the same schedule for all).
function Runner:growTo(t, town, target, sleepS)
	local caps = self.E.townCaps(town)
	if caps == nil or caps.sizeFactors == nil or caps.sizeFactors[1] == nil then
		self:log("GROW", { { "town", town }, { "ok", false }, { "why", "noTown" } })
		return false
	end
	local f = {}
	for i = 1, 3 do f[i] = math.min(R.GROW_CAP, math.max(caps.sizeFactors[i] or 1, target)) end
	self:log("GROW", { { "town", town }, { "name", self.E.name(town) }, { "sizeFactors", caps.sizeFactors }, { "to", f },
		{ "cap", string.format("%.0f/%.0f", caps.actual or 0, caps.target or 0) } })
	t.cmdDone, t.waitCmd, t.cmdUs, t.sleepAfter = nil, true, self.nowUs, sleepS
	self.E.growTown(town, f, function(success)
		t.cmdDone = success == true
		if not success then self:log("GROW", { { "town", town }, { "ok", false } }) end
	end)
	return true
end

--- Growth batch (showcase rounds): one pass for each { town, target, key } to sizeFactors max(current, target),
--- all commands sent back to back (one per town in flight); the task waits until every callback came (or the
--- command timeout). Returns the keys of towns that no longer exist.
function Runner:growBatch(t, list, sleepS)
	local todo, gone = {}, {}
	for _, it in ipairs(list) do
		local caps = self.E.townCaps(it.town)
		if caps == nil or caps.sizeFactors == nil or caps.sizeFactors[1] == nil then
			self:log("GROW", { { "town", it.town }, { "ok", false }, { "why", "noTown" } })
			gone[#gone + 1] = it.key
		else
			local f = {}
			for i = 1, 3 do f[i] = math.min(R.GROW_CAP, math.max(caps.sizeFactors[i] or 1, it.target)) end
			self:log("GROW", { { "town", it.town }, { "name", self.E.name(it.town) }, { "sizeFactors", caps.sizeFactors },
				{ "to", f }, { "cap", string.format("%.0f/%.0f", caps.actual or 0, caps.target or 0) }, { "batch", #list } })
			todo[#todo + 1] = { town = it.town, f = f }
		end
	end
	self:sendBatch(t, todo, function(it, cb) self.E.growTown(it.town, it.f, cb) end, sleepS, "GROW")
	return gone
end

--- Sends one command per item back to back (send(item, cb)); t waits until all callbacks came (or
--- R.BATCH_TIMEOUT_S). Each batch has its own id: a callback of an earlier batch that timed out (Showcase v7 round 7:
--- a 35-town growth batch ran past the old 30 s timeout) is logged as LATE and no longer counts for the next batch.
function Runner:sendBatch(t, items, send, sleepS, what)
	t.cmdDone, t.cmdUs, t.sleepAfter = nil, self.nowUs, sleepS or 0
	t.waitCmd = #items > 0
	t.cmdTimeoutS = R.BATCH_TIMEOUT_S
	t.batchLeft, t.batchFail = #items, 0
	self.batchSeq = (self.batchSeq or 0) + 1
	local id, sentUs = self.batchSeq, self.nowUs or 0
	t.batchId = id
	for _, it in ipairs(items) do
		send(it, function(success)
			if t.batchId ~= id then
				self:log("LATE", { { "what", what or "BATCH" }, { "town", it.town or "-" }, { "ok", success == true },
					{ "s", string.format("%.1f", ((self.nowUs or 0) - sentUs) / 1e6) } })
				return
			end
			if not success then
				t.batchFail = t.batchFail + 1
				self:log(what or "BATCH", { { "ok", false }, { "town", it.town or "-" } })
			end
			t.batchLeft = t.batchLeft - 1
			if t.batchLeft <= 0 then t.cmdDone = t.batchFail == 0 end
		end)
	end
end

--- Showcase "Fill mod streets": makeTownDevelopAtCmd(point, no streets, no upgrade) at each { x, y }, as a batch.
function Runner:developBatch(t, pts)
	self:sendBatch(t, pts, function(p, cb) self.X.developAt(p[1], p[2], false, false, cb) end, 0, "FILL")
end

--- Adoption of street edges `ids` (the mod's): { alive (still exist), withParcels (the town cut lots along them),
--- parcels, built (lots with a house) } from the whole parcel map and the town's buildings.
function Runner:adoption(town, ids)
	local E = self.E
	local a = { alive = 0, withParcels = 0, parcels = 0, built = 0 }
	if ids == nil or #ids == 0 then return a end
	local pmap = E.parcelMap() or {}
	local _, builtBy = E.townBuildings(town, E.town2buildings())
	builtBy = builtBy or {}
	for _, id in ipairs(ids) do
		local alive = true
		if self.X.edgeGeom then alive = self.X.edgeGeom(id) ~= nil end
		if alive then
			a.alive = a.alive + 1
			local pd = pmap[id]
			local n = pd ~= nil and E.parcelCount(pd) or 0
			if n > 0 then
				a.withParcels = a.withParcels + 1
				a.parcels = a.parcels + n
			end
			a.built = a.built + (builtBy[id] or 0)
		end
	end
	return a
end

--- Street-lock probe (Showcase v5) over the mod's edges `ids`: { alive, locked (read back roadDevelopmentLocked),
--- attached (other street edges at their nodes that are not in `base`) }. record = true adds every other street
--- edge at those nodes to `base` instead (the baseline right after a build: the joints to the existing town).
function Runner:lockProbe(ids, base, record)
	local X, E = self.X, self.E
	local out = { alive = 0, locked = 0, attached = 0 }
	if ids == nil or X.edge == nil then return out end
	local mod, nodes = {}, {}
	for _, id in ipairs(ids) do mod[id] = true end
	for _, id in ipairs(ids) do
		local e = X.edge(id)
		if e then
			out.alive = out.alive + 1
			if e.locked then out.locked = out.locked + 1 end
			if e.n0 then nodes[#nodes + 1] = e.n0 end
			if e.n1 then nodes[#nodes + 1] = e.n1 end
		end
	end
	local seen = {}
	for _, n in ipairs(nodes) do
		for _, eid in ipairs(E.nodeStreetEdges(n) or {}) do
			if not mod[eid] and not seen[eid] then
				seen[eid] = true
				if record then base[eid] = true
				elseif not base[eid] then out.attached = out.attached + 1 end
			end
		end
	end
	return out
end

--- Roundabout probe: a 4-arm roundabout of plain streets at a joinable dead end of `town` (otd_roundabout with
--- square_roundabouts' geometry), the first of the sizes XS / S / M whose pre-check passes, built with one
--- proposal (context with the player). o = { mode = "camera" (dead end nearest o.x, o.y) | "frontier",
--- ringMode = "oneway" (default; falls back to the two-way "town" ring, RB FALLBACK, when every size is refused) |
--- "town",
--- tag = log tag, onResult = fn({ edges, ring, arms, centre, size, cost }) }.
--- Logs <tag> PLAN per size, SEND before the build, BUILT / FAILED after. Returns true when sent (t waits).
function Runner:roundabout(t, town, o)
	local RB, geom, E = self.RB, self.rbGeom, self.E
	local tag = o.tag or "RB"
	self.rbLast = {}
	local function fail(why)
		self.rbLast = { why = why }
		self:log(tag, { { "town", town }, { "ok", false }, { "why", why } })
		return false
	end
	if RB == nil or geom == nil then return fail("noRoundaboutMod:" .. tostring(self.rbWhy)) end
	self:ensureConfig()
	local d = self.driver
	local m = d:measure(town)
	if m == nil then return fail("noTown") end
	local job = { town = town, ext = m.ext, edges = m.edges, caps = m.caps }
	local g, joinInfo = d:snapshotGraph(job)
	local cx, cy = E.boxCentre(town)
	if cx == nil then cx, cy = m.ext.cx, m.ext.cy end
	local byId = {}
	for _, ed in ipairs(m.edges) do byId[ed.id] = ed end
	local cands = {}
	for n, ji in pairs(joinInfo) do
		local node, ed = g.nodeById[n], byId[ji.src]
		if node and ed then
			local other = ed.n0 == n and ed.p1 or ed.p0
			local dx, dy = node.x - other[1], node.y - other[2]
			local l = math.sqrt(dx * dx + dy * dy)
			if l > 1 then
				local t0 = ji.template or ""
				local cls = t0:find("large", 1, true) and "main" or (t0:find("medium", 1, true) and "medium" or "small")
				cands[#cands + 1] = { node = n, x = node.x, y = node.y, z = node.z or 0, dx = dx / l, dy = dy / l, ji = ji, cls = cls,
					d = math.sqrt((node.x - cx) ^ 2 + (node.y - cy) ^ 2),
					near = o.x and math.sqrt((node.x - o.x) ^ 2 + (node.y - o.y) ^ 2) or nil }
			end
		end
	end
	-- one-way ring by default (Showcase v7: the engine's own one-way ring lane pattern, ot_proposal.junctionConnsDir);
	-- the two-way town street ring only as a logged fallback when every one-way size is refused
	local ringMode = o.ringMode or "oneway"
	local modes = ringMode == "oneway" and { "oneway", "town" } or { "town" }
	local c = RB.pick(cands, o.mode or "camera")
	if c == nil then return fail("noJoinableDeadEnd") end
	local ctx = E.context(self.H.player == true)
	local water = self.X.isWater
	local fallbackWhy = nil
	for mi, mode in ipairs(modes) do
	ringMode = mode
	if mi > 1 then
		self:log(tag .. " FALLBACK", { { "town", town }, { "from", modes[1] }, { "to", mode }, { "why", fallbackWhy or "-" } })
	end
	for i, size in ipairs(RB.SIZES) do
		local lp, err = RB.localPlan(geom, size)
		if lp == nil then return fail("geometry:" .. tostring(err)) end
		local wp = RB.place(lp, c.x, c.y, c.z, c.dx, c.dy)
		local wet = false
		if water then
			for _, p in pairs(wp.nodes) do if water(p[1], p[2]) then wet = true end end
		end
		local spec, why = RB.spec(wp, { deadEnd = c.node, deadEdge = c.ji.src, lanes = c.ji.lanes, hasConfig = c.ji.hasConfig,
			src = c.ji.src, template = c.ji.template, ringMode = ringMode,
			ringLanes = (E.templateLanes and E.templateLanes(RB.ONEWAY)) or 4, junctionConns = self.PR.junctionConns,
			junctionConnsDir = self.PR.junctionConnsDir })
		if spec == nil then return fail("spec:" .. tostring(why)) end
		local pre = { ok = false, msgs = { "water" }, collisions = 0 }
		local proposal
		if not wet then
			local okP, p = pcall(E.proposal, spec)
			if not okP then return fail("proposal:" .. tostring(p)) end
			proposal = p
			pre = E.precheck(proposal, ctx)
		end
		self:log(tag .. " PLAN", { { "town", town }, { "size", RB.SIZE_NAMES[i] }, { "radius", lp.radius }, { "ringR", lp.R },
			{ "deadEnd", c.node }, { "street", c.cls }, { "centre", string.format("%.0f,%.0f", wp.centre[1], wp.centre[2]) },
			{ "ring", ringMode }, { "ok", pre.ok }, { "msgs", pre.msgs }, { "collisions", pre.collisions },
			{ "partners", pre.partners and d:partnerText(job, pre.partners) or "-" }, { "preCost", pre.cost or "-" } })
		if pre.ok then
			local bal0 = E.balance()
			self:log(tag .. " SEND", { { "town", town }, { "spec", self.PR.summary(spec) }, { "size", RB.SIZE_NAMES[i] },
				{ "player", self.H.player == true and "on" or "off" },
					{ "newNodeConfigs", string.format("%d/%d", spec.newConfigs or 0, #spec.nodes) }, { "ring", ringMode },
					{ "fallback", mi > 1 },
					{ "balance", bal0 } })
			t.cmdDone, t.waitCmd, t.cmdUs, t.sleepAfter = nil, true, self.nowUs, 0
			local reach = lp.reach
			E.sendBuild(proposal, ctx, function(success, info)
				info = info or {}
				local res = { centre = wp.centre, size = RB.SIZE_NAMES[i], cost = info.cost, ring = {}, arms = {}, edges = {},
					ringMode = mode }
				if success then
					local found = E.streets(wp.centre[1], wp.centre[2], reach + 15)
					local old = {}
					for _, ed in ipairs(m.edges) do old[ed.id] = true end
					local function near(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) <= 1.5 end
					for _, e in ipairs(spec.edges) do
						for _, ed in ipairs(found) do
							if not old[ed.id] and ((near(ed.p0, e.p0) and near(ed.p1, e.p1)) or (near(ed.p0, e.p1) and near(ed.p1, e.p0))) then
								res.edges[#res.edges + 1] = ed.id
								local list = spec.roles[e.entity] == "ring" and res.ring or res.arms
								list[#list + 1] = ed.id
								old[ed.id] = true
								break
							end
						end
					end
				end
				self:log(success and (tag .. " BUILT") or (tag .. " FAILED"), { { "town", town }, { "ok", success },
					{ "cost", info.cost or "-" }, { "msgs", info.msgs or {} }, { "ring", #res.ring }, { "arms", #res.arms },
					{ "balance", string.format("%s->%s", tostring(bal0), tostring(E.balance())) } })
				if not success then res = { failed = true, why = "buildFailed" } end
				if o.onResult then pcall(o.onResult, res) end
				t.cmdDone = success == true
			end)
			return true
		end
	end
	fallbackWhy = "allSizesRefused:" .. mode
	end
	return fail("allSizesRefused")
end

--- Node dump (read-only, runs at once): the street nodes nearest (x, y) with their edges, every lane
--- connection annotated (otd_nodedump: edge end, edge lane, forward flag, in / out) and our derived pattern for
--- the same node (ot_proposal.junctionConnsDir) to compare. NODEDUMP / NODECONN / NODEOURS lines.
function Runner:nodeDump(x, y)
	local ND, X = self.ND, self.X
	if ND == nil or X.nodesNear == nil then
		self:log("NODEDUMP", { { "ok", false }, { "why", "nodeDumpNotLoaded" } })
		return
	end
	local list = X.nodesNear(x, y, ND.RADIUS, ND.MAX_NODES)
	if #list == 0 then
		self:log("NODEDUMP", { { "ok", false }, { "why", "noNodeWithin" .. ND.RADIUS .. "m" }, { "x", x }, { "y", y } })
		return
	end
	for _, node in ipairs(list) do
		X.nodeRead(node)
		local head, conns = ND.fields(node)
		self:log("NODEDUMP", head)
		for _, f in ipairs(conns) do self:log("NODECONN", f) end
		if self.PR and self.PR.junctionConnsDir then
			local ours = ND.ours(node, self.PR.junctionConnsDir)
			local engine, same = {}, 0
			for _, c in ipairs(node.conns or {}) do engine[string.format("%d.%d>%d.%d", c[1], c[2], c[3], c[4])] = true end
			for _, c in ipairs(ours) do if engine[c] then same = same + 1 end end
			self:log("NODEOURS", { { "node", node.id }, { "ours", table.concat(ours, ",") }, { "match", same },
				{ "engine", #(node.conns or {}) }, { "oursN", #ours },
				{ "equal", same == #ours and same == #(node.conns or {}) } })
		end
	end
end

function Runner:endTask(t, result)
	if t.kind == "showcase" and result ~= "done" and self.show ~= nil then
		-- stopped / failed: the numbers so far (the showcase state stays: Showcase again resumes)
		local ok, err = pcall(self.SC.report, self, self.show, self.nowUs)
		if not ok then self:log("ERROR", { { "stage", "showcaseReport" }, { "err", err } }) end
	end
	self:log("DONE", { { "task", t.label or t.kind }, { "id", t.id }, { "result", result },
		{ "s", string.format("%.1f", ((self.nowUs or 0) - (t.startUs or 0)) / 1e6) } })
	self.task = nil
	self.H.devBusy = #self.tasks > 0 or self.simRound ~= nil
	if t.town ~= nil and t.town == self.selected then self.needInspect = true end
	self:changed()
end

local K = {}

--- Grow now: n x (forced increment in the picked style + forced growth passes).
function K.grow(r, t, now)
	if t.phase == nil then t.phase, t.k = "build", 1 end
	if t.phase == "build" then
		if t.jobOutcome ~= nil then
			local o = t.jobOutcome
			t.jobOutcome = nil
			r:log("STEP", { { "task", "grow" }, { "town", t.town }, { "increment", string.format("%d/%d", t.k, t.n) },
				{ "outcome", o }, { "style", t.job and t.job.style and t.job.style.id or "-" } })
			if o ~= "built" then return r:endTask(t, "stopped:" .. tostring(o)) end
			t.phase, t.pass = "grow", 1
			return
		end
		r:startJob(t, t.town, now, { force = true, styleMode = t.styleMode, motif = t.motif })
		return
	end
	if t.pass > R.GROW_PASSES then
		t.k = t.k + 1
		if t.k > t.n then return r:endTask(t, "done") end
		t.phase = "build"
		return
	end
	local mult = t.pass == 1 and t.factor or 1
	t.pass = t.pass + 1
	if not r:growPass(t, t.town, mult, R.GROW_PASS_S) then return r:endTask(t, "noTown") end
end

--- Plan only: forced dry run (plan + pre-check, never sent), the plan logged edge by edge and marked.
function K.dry(r, t, now)
	if t.jobOutcome ~= nil then
		local o, job = t.jobOutcome, t.job
		if o == "dry" and job and job.spec then
			r:showPlan(t.town, job)
		else
			r:log("STEP", { { "task", "dry" }, { "town", t.town }, { "outcome", o } })
		end
		return r:endTask(t, o)
	end
	r:startJob(t, t.town, now, { force = true, dry = true, styleMode = t.styleMode, motif = t.motif })
end

--- Forest-lane test (round R2, 2026-10-13): a forced increment of the picked town (best by a forest) planned through
--- the forest with every eligible stretch a lane (job.forestLane "force": ot_lane, no cap), GROW_PASSES growth
--- passes, a second forced increment (does the town build on past the lane?), more growth, then LANETEST: the houses
--- within LANE_NEAR_M of the lane edges (want 0) vs of the first increment's town edges, and the second increment's
--- edges beyond the lane.
R.LANE_NEAR_M = 30
local function segDist(px, py, a, b)
	local dx, dy = b[1] - a[1], b[2] - a[2]
	local l2 = dx * dx + dy * dy
	local f = l2 > 0 and math.max(0, math.min(1, ((px - a[1]) * dx + (py - a[2]) * dy) / l2)) or 0
	local x, y = a[1] + dx * f, a[2] + dy * f
	return math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
end
R.segDist = segDist

--- Houses (pts {x, y}) within near m of any of the segments ({p0, p1}).
function R.housesNear(pts, segs, near)
	local n = 0
	for _, p in ipairs(pts or {}) do
		for _, sg in ipairs(segs) do
			if segDist(p[1], p[2], sg[1], sg[2]) <= near then n = n + 1; break end
		end
	end
	return n
end

-- (round after the names run, 2026-10-13: every LANETEST said noLane: the picked towns' forced plans crossed no forest
-- wooded on both sides (one of them the new industrial satellite). Now the test finds its site: a dry run of the
-- picked town first, then of the other towns by forest share (the dev driver's tree reads), at most LANE_PICK_MAX; the
-- first whose plan has a lane is built. LANETEST pick lines.)
R.LANE_PICK_MAX = 8

--- Candidate towns for the forest-lane test: the picked one first, then the rest by forest share (known reads first).
function R.laneCandidates(picked, ids, shareOf)
	local out, rest = {}, {}
	if picked then out[1] = picked end
	for _, id in ipairs(ids or {}) do if id ~= picked then rest[#rest + 1] = id end end
	table.sort(rest, function(a, b)
		local sa, sb = shareOf(a) or -1, shareOf(b) or -1
		if sa ~= sb then return sa > sb end
		return a < b
	end)
	for _, id in ipairs(rest) do
		if #out >= R.LANE_PICK_MAX then break end
		out[#out + 1] = id
	end
	return out
end

function K.forestLane(r, t, now)
	if t.phase == nil then
		t.phase = "pick"
		local d = r.driver
		t.cands = R.laneCandidates(t.town, r.E.towns and r.E.towns() or {}, function(id)
			local st = d.towns and d.towns[id]
			return st and st.forest and st.forest.share or nil
		end)
		t.ci = 0
	end
	if t.phase == "pick" then
		if t.jobOutcome ~= nil then
			local o, job = t.jobOutcome, t.job
			t.jobOutcome = nil
			local n = 0
			for _, e in ipairs(job and job.spec and job.spec.edges or {}) do if e.forestLane then n = n + 1 end end
			local cand = t.cands[t.ci]
			r:log("LANETEST", { { "pick", cand }, { "name", r.E.name(cand) }, { "dry", o }, { "lanes", n },
				{ "tried", t.ci }, { "of", #t.cands } })
			if n > 0 then
				t.town, t.phase, t.k = cand, "build", 1
				return
			end
		end
		t.ci = t.ci + 1
		local cand = t.cands[t.ci]
		if cand == nil then
			r:log("LANETEST", { { "town", t.town or "-" }, { "ok", false }, { "why", "noForestCrossing" }, { "tried", t.ci - 1 } })
			return r:endTask(t, "noLane")
		end
		r:startJob(t, cand, now, { force = true, dry = true, styleMode = t.styleMode, forestLane = "force" })
		return
	end
	if t.phase == "build" then
		if t.jobOutcome ~= nil then
			local o, job = t.jobOutcome, t.job
			t.jobOutcome = nil
			local lanes, town = {}, {}
			for _, e in ipairs(job and job.spec and job.spec.edges or {}) do
				if e.forestLane then lanes[#lanes + 1] = { e.p0, e.p1 } else town[#town + 1] = { e.p0, e.p1 } end
			end
			r:log("LANETEST", { { "town", t.town }, { "increment", t.k }, { "outcome", o }, { "lanes", #lanes },
				{ "townEdges", #town } })
			if o ~= "built" then return r:endTask(t, "stopped:" .. tostring(o)) end
			if t.k == 1 then
				if #lanes == 0 then
					r:log("LANETEST", { { "town", t.town }, { "ok", false },
						{ "why", "noLane (the plan crossed no forest wooded on both sides: pick a town next to a forest)" } })
					return r:endTask(t, "noLane")
				end
				t.lanes, t.town1 = lanes, town
			else
				t.town2 = town
			end
			t.phase, t.pass = "grow", 1
			return
		end
		r:startJob(t, t.town, now, { force = true, styleMode = t.styleMode, forestLane = t.k == 1 and "force" or nil })
		return
	end
	if t.pass > R.GROW_PASSES then
		if t.k == 1 then
			t.k, t.phase = 2, "build"
			return
		end
		local part = r.driver:measureReads(t.town)
		local pts = part and part.pts or {}
		local onLane = R.housesNear(pts, t.lanes, R.LANE_NEAR_M)
		local onTown = R.housesNear(pts, t.town1 or {}, R.LANE_NEAR_M)
		local len = 0
		for _, sg in ipairs(t.lanes) do len = len + math.sqrt((sg[2][1] - sg[1][1]) ^ 2 + (sg[2][2] - sg[1][2]) ^ 2) end
		-- the second increment's edges beyond the lane: their midpoint farther from the town centre than the lane's
		local cx, cy = part and part.ext and part.ext.cx or 0, part and part.ext and part.ext.cy or 0
		local laneR = 0
		for _, sg in ipairs(t.lanes) do
			laneR = math.max(laneR, math.sqrt((((sg[1][1] + sg[2][1]) / 2) - cx) ^ 2 + (((sg[1][2] + sg[2][2]) / 2) - cy) ^ 2))
		end
		local beyond = 0
		for _, sg in ipairs(t.town2 or {}) do
			local mr = math.sqrt((((sg[1][1] + sg[2][1]) / 2) - cx) ^ 2 + (((sg[1][2] + sg[2][2]) / 2) - cy) ^ 2)
			if mr > laneR then beyond = beyond + 1 end
		end
		r:log("LANETEST", { { "town", t.town }, { "name", r.E.name(t.town) }, { "lanes", #t.lanes }, { "laneLen", string.format("%.0f", len) },
			{ "housesOnLane", onLane }, { "housesOnTownEdges", onTown }, { "townEdges1", #(t.town1 or {}) },
			{ "edges2", #(t.town2 or {}) }, { "beyond", beyond }, { "ok", onLane == 0 } })
		r.X.markers(t.lanes and (function()
			local out = {}
			for _, sg in ipairs(t.lanes) do out[#out + 1] = { p0 = sg[1], p1 = sg[2] } end
			return out
		end)() or {}, R.MARKER_S)
		return r:endTask(t, "done")
	end
	local mult = t.pass == 1 and (t.factor or 1.5) or 1
	t.pass = t.pass + 1
	if not r:growPass(t, t.town, mult, R.GROW_PASS_S) then return r:endTask(t, "noTown") end
end

--- Industrial satellite probe (round R7, 2026-10-13): the API has town-wide capacities only, no per-area zoning. Does a
--- separate town created with industrial-heavy initial capacities (SATIND_CAPS, makeTownCreateCmd) build only industry?
--- Site: SATIND_D m from the picked town, preferring a site across water (a river between: "across a bridge"), dry,
--- SATIND_NEAR m from every other town; the new town gets SATIND_PASSES forced growth passes (x SATIND_FACTOR), then
--- SATIND logs its capacities per district and its buildings. (No bridge is built: the probe answers the zoning
--- question; the main mod's bridge links it later, if ever.)
R.SATIND_CAPS = { 10, 10, 200 }
R.SATIND_D = { 900, 1200, 1500 }
R.SATIND_NEAR = 700
R.SATIND_PASSES = 3
R.SATIND_FACTOR = 2

--- The site for the probe: { x, y, across (bool), d, heading } or nil. wet(x, y), towns { {x, y} } (the others).
function R.satIndSite(cx, cy, wet, towns)
	local best = nil
	for _, d in ipairs(R.SATIND_D) do
		for k = 0, 15 do
			local a = k / 16 * 2 * math.pi
			local x, y = cx + math.cos(a) * d, cy + math.sin(a) * d
			local okSite = not wet(x, y)
			for _, tw in ipairs(towns or {}) do
				if okSite and math.sqrt((tw[1] - x) ^ 2 + (tw[2] - y) ^ 2) < R.SATIND_NEAR then okSite = false end
			end
			if okSite then
				local across = false
				for f = 0.1, 0.9, 0.05 do
					if wet(cx + (x - cx) * f, cy + (y - cy) * f) then across = true break end
				end
				local score = (across and 0 or 1000) + d + k
				if best == nil or score < best.score then best = { x = x, y = y, across = across, d = d, heading = a, score = score } end
			end
		end
	end
	return best
end

function K.satInd(r, t, now)
	local E, X = r.E, r.X
	if t.phase == nil then
		local cx, cy = E.boxCentre(t.town)
		if cx == nil then return r:endTask(t, "noTown") end
		local others = {}
		for _, id in ipairs(E.towns() or {}) do
			if id ~= t.town then
				local x, y = E.boxCentre(id)
				if x then others[#others + 1] = { x, y } end
			end
		end
		local sampler = r.driver.E.sampler and r.driver.E.sampler() or nil
		local wet = function(x, y)
			if sampler == nil then return false end
			local okW, w = pcall(function()
				if sampler.water then return sampler.water(x, y) and true or false end
				return sampler.height(x, y) < (sampler.waterLevel or 0)
			end)
			return okW and w == true
		end
		local site = R.satIndSite(cx, cy, wet, others)
		if site == nil then
			r:log("SATIND", { { "town", t.town }, { "ok", false }, { "why", "noSite" } })
			return r:endTask(t, "noSite")
		end
		t.site, t.before = site, {}
		for _, id in ipairs(E.towns() or {}) do t.before[id] = true end
		t.name = string.format("%s Works", E.name(t.town))
		local okSend, info = X.createTown({ x = site.x, y = site.y, name = t.name, capsList = R.SATIND_CAPS, caps = 100 },
			function(success) t.created = success end)
		r:log("SATIND", { { "town", t.town }, { "name", E.name(t.town) }, { "event", "create" }, { "site", string.format("%.0f:%.0f", site.x, site.y) },
			{ "d", site.d }, { "across", site.across }, { "caps", string.format("%d/%d/%d", R.SATIND_CAPS[1], R.SATIND_CAPS[2], R.SATIND_CAPS[3]) },
			{ "sent", okSend }, { "err", info and info.err or "-" } })
		if not okSend then return r:endTask(t, "createFailed") end
		t.phase = "wait"
		return
	end
	if t.phase == "wait" then
		if t.created == nil then return end
		if not t.created then return r:endTask(t, "createRefused") end
		for _, id in ipairs(E.towns() or {}) do
			if not t.before[id] then t.newTown = id end
		end
		if t.newTown == nil then return r:endTask(t, "newTownNotFound") end
		t.phase, t.pass = "grow", 1
		return
	end
	if t.phase == "grow" then
		if t.pass > R.SATIND_PASSES then
			local lu = X.landUse and X.landUse(t.newTown) or nil
			local g = X.townGrowth and X.townGrowth(t.newTown) or nil
			local counts = X.buildingCounts and X.buildingCounts() or {}
			local tot = lu and (lu[1] + lu[2] + lu[3]) or 0
			r:log("SATIND", { { "town", t.town }, { "satellite", t.newTown }, { "name", t.name }, { "event", "result" },
				{ "initial", g and string.format("%d/%d/%d", g.initials[1], g.initials[2], g.initials[3]) or "-" },
				{ "landUse", lu and string.format("%d/%d/%d", lu[1], lu[2], lu[3]) or "-" },
				{ "indShare", tot > 0 and string.format("%.2f", lu[3] / tot) or "-" },
				{ "buildings", counts[t.newTown] or 0 }, { "across", t.site.across }, { "onlyIndustry", tot > 0 and lu[3] >= 0.9 * tot } })
			return r:endTask(t, "done")
		end
		local mult = t.pass == 1 and R.SATIND_FACTOR or 1
		t.pass = t.pass + 1
		if not r:growPass(t, t.newTown, mult, R.GROW_PASS_S) then return r:endTask(t, "noTown") end
	end
end

function Runner:showPlan(town, job)
	local spec = job.spec
	local edges = {}
	for i, e in ipairs(spec.edges) do
		edges[i] = { p0 = e.p0, p1 = e.p1 }
		self:log("PLANEDGE", { { "i", i }, { "from", string.format("%.1f,%.1f,%.1f", e.p0[1], e.p0[2], e.p0[3]) },
			{ "to", string.format("%.1f,%.1f,%.1f", e.p1[1], e.p1[2], e.p1[3]) }, { "class", e.class or "-" },
			{ "template", (e.override or e.template or "-"):match("([^/]+)%.street_template$") or "-" },
			{ "join", (e.node0 > 0 and e.node0) or (e.node1 > 0 and e.node1) or "-" } })
	end
	self.plan = { town = town, name = self.E.name(town), style = job.style and job.style.id or "-", edges = edges,
		summary = self.PR.summary(spec), preCost = job.pre and job.pre.cost }
	local n = self.X.markers(edges, R.MARKER_S)
	self:log("MARKERS", { { "town", town }, { "icons", n }, { "seconds", R.MARKER_S } })
end

--- Undo last increment of the town (the newest record of the main driver or ours).
function K.undo(r, t, now)
	if t.sent then
		if not t.cmdDone then
			r:log("UNDO", { { "town", t.town }, { "ok", false }, { "msgs", t.cmdInfo and t.cmdInfo.msgs or {} } })
			return r:endTask(t, "failed")
		end
		local s = t.owner.towns[t.town]
		for i = #s.history, 1, -1 do
			if s.history[i] == t.rec then table.remove(s.history, i) end
		end
		r:log("UNDONE", { { "town", t.town }, { "edges", #t.plan.edges }, { "nodes", #t.plan.nodesRemove },
			{ "cost", t.cmdInfo and t.cmdInfo.cost } })
		return r:endTask(t, "done")
	end
	local recs = r:records(t.town)
	local last = recs[#recs]
	if last == nil then
		r:log("UNDO", { { "town", t.town }, { "ok", false }, { "why", "nothing built this session" } })
		return r:endTask(t, "nothing")
	end
	local E, X = r.E, r.X
	local plan, why = r.UN.plan(last.rec, { edge = X.edge, nodeEdges = E.nodeStreetEdges, hasConfig = E.hasConfig,
		hasLights = X.hasLights, inConstruction = E.nodeInConstruction })
	if plan == nil then
		r:log("UNDO", { { "town", t.town }, { "ok", false }, { "why", why } })
		return r:endTask(t, "refused")
	end
	local _, builtBy = E.townBuildings(t.town, E.town2buildings())
	local lots = r.UN.houses(plan, builtBy)
	local proposal, nCfg = X.removalProposal(plan)
	local ctx = E.context()
	local pre = E.precheck(proposal, ctx)
	-- logged BEFORE sending (crash forensics)
	r:log("UNDO", { { "town", t.town }, { "edges", plan.edges }, { "missing", plan.missing }, { "nodesRemove", plan.nodesRemove },
		{ "cfgPrune", plan.cfgPrune }, { "cfgWritten", nCfg }, { "builtLots", lots }, { "preCost", pre.cost },
		{ "preMsgs", pre.msgs }, { "warn", lots > 0 and "removing streets with houses demolishes them (HANDOFF D4)" or "-" } })
	if pre.critical then return r:endTask(t, "precheck") end
	t.sent, t.rec, t.owner, t.plan = true, last.rec, last.owner, plan
	t.cmdDone, t.waitCmd, t.cmdUs, t.sleepAfter = nil, true, now, 0
	X.send(proposal, ctx, function(ok, info)
		t.cmdInfo = info
		t.cmdDone = ok
	end)
end

--- Towns the main mod acts on (New towns only: the ones not known at first sight; all when unknown).
function Runner:actedTowns()
	local ids = self.E.towns()
	local known = nil
	if self.driver.opts and self.driver.opts.actOn == "new" then known = self.SV.knownSet(self:saved()) end
	if known == nil then return ids end
	local out = {}
	for _, id in ipairs(ids) do if not known[id] then out[#out + 1] = id end end
	return out
end

--- Fast-forward: rounds x (every acted-on town: one forced growth pass, then a normal check with the trigger).
---------------------------------------------------------------------------
-- Place test stops (named) (2026-10-13): for each town, one kerbside Road Stop per stop theme its streets offer
-- (ot_names.stopThemes on each plain town street edge's middle, read by the main driver's stopSite: hill, shore, river,
-- valley, forest, station, centre, outskirts), built with otd_engine.stopProposal (no new node; the end nodes' configs
-- re-pointed), then handed to the main driver's stop naming (Driver:addDevStops: script builds never pass the build
-- event's player filter), which logs its STOPNAME line. TESTSTOP per stop; at most TESTSTOP_PER_TOWN per town and
-- TESTSTOP_MAX per click; edges shorter than TESTSTOP_MIN_LEN (the stop keeps 10 m from crossings) are skipped.
R.TESTSTOP_TOWNS = 6
R.TESTSTOP_PER_TOWN = 8
R.TESTSTOP_MAX = 24
R.TESTSTOP_MIN_LEN = 32
R.TESTSTOP_SCAN = 40        -- edges read per tick
R.TESTSTOP_EDGES = 600      -- edges looked at per town at most
R.TESTSTOP_SETTLE_S = 0.6   -- after the build's callback, before the new group is looked for

function K.testStops(r, t, now)
	local E, X, NM = r.E, r.X, r.NM
	local main = r:main()
	local namer = main or r.driver
	if NM == nil or namer.stopSite == nil then
		r:log("TESTSTOP", { { "ok", false }, { "why", "main mod without stop names" } })
		return r:endTask(t, "refused")
	end
	-- 1. scan: one candidate edge per theme and town
	if t.items == nil then
		t.items, t.ti, t.ei, t.byTheme = {}, 1, 0, {}
		r:log("TESTSTOP", { { "start", true }, { "towns", #t.towns }, { "main", main ~= nil } })
	end
	if not t.scanned then
		local town = t.towns[t.ti]
		if town == nil then
			t.scanned, t.k = true, 0
			r:log("TESTSTOP", { { "planned", #t.items } })
			return
		end
		if t.edges == nil then
			local m = r.driver:measure(town, { noNet = true })
			t.edges = m and m.edges or {}
			t.ei, t.byTheme = 0, {}
			if m == nil then r:log("TESTSTOP", { { "town", town }, { "ok", false }, { "why", "noTown" } }) end
		end
		local per = 0
		for _ in pairs(t.byTheme) do per = per + 1 end
		for _ = 1, R.TESTSTOP_SCAN do
			t.ei = t.ei + 1
			local ed = t.edges[t.ei]
			if ed == nil or t.ei > R.TESTSTOP_EDGES or per >= R.TESTSTOP_PER_TOWN or #t.items >= R.TESTSTOP_MAX then
				t.ti, t.edges = t.ti + 1, nil
				if #t.items >= R.TESTSTOP_MAX then t.ti = #t.towns + 1 end
				return
			end
			local len = math.sqrt((ed.p1[1] - ed.p0[1]) ^ 2 + (ed.p1[2] - ed.p0[2]) ^ 2)
			if r.D.plainTownEdge(ed) and len >= R.TESTSTOP_MIN_LEN then
				local x, y = (ed.p0[1] + ed.p1[1]) / 2, (ed.p0[2] + ed.p1[2]) / 2
				local okS, site = pcall(namer.stopSite, namer, town, x, y, now)
				local themes = okS and NM.stopThemes(site) or {}
				local th = themes[1]
				if th and not t.byTheme[th] then
					t.byTheme[th] = true
					per = per + 1
					t.items[#t.items + 1] = { town = town, edge = ed.id, tag = th, x = x, y = y, tags = table.concat(themes, ",") }
				end
			end
		end
		return
	end
	-- 2. build one at a time, then hand the new stop to the main driver's naming
	local it = t.cur
	if it and it.sent then
		if it.cmdOk then
			local after = X.stationGroups()
			local g = nil
			for id in pairs(after) do if not it.before[id] then g = id break end end
			local st = g and E.groupStations(g)[1] or nil
			local name = g and E.name(g) or "-"
			local handed = 0
			if st and main and main.addDevStops then
				handed = main:addDevStops({ { st = st, g = g, n = name, x = it.x, y = it.y } })
			end
			r:log("TESTSTOP", { { "town", it.town }, { "edge", it.edge }, { "tag", it.tag }, { "tags", it.tags },
				{ "stop", g or -1 }, { "station", st or -1 }, { "name", name }, { "named", handed > 0 and "main" or "no" } })
		else
			r:log("TESTSTOP", { { "town", it.town }, { "edge", it.edge }, { "tag", it.tag }, { "ok", false },
				{ "msgs", it.info and it.info.msgs or {} } })
		end
		t.cur = nil
		return
	end
	t.k = t.k + 1
	it = t.items[t.k]
	if it == nil then
		r:log("TESTSTOP", { { "done", true }, { "stops", t.k - 1 } })
		return r:endTask(t, "done")
	end
	local proposal, why = X.stopProposal(it.edge, X.stopModel(), "SQOT test stop")
	if proposal == nil then
		r:log("TESTSTOP", { { "town", it.town }, { "edge", it.edge }, { "tag", it.tag }, { "ok", false }, { "why", why } })
		return
	end
	it.before, it.sent = X.stationGroups(), true
	t.cur = it
	t.cmdDone, t.waitCmd, t.cmdUs, t.sleepAfter = nil, true, now, R.TESTSTOP_SETTLE_S
	X.send(proposal, nil, function(ok, info)
		it.cmdOk, it.info = ok, info
		t.cmdDone = ok
	end)
end

function K.fast(r, t, now)
	if t.phase == nil then
		t.round, t.idx, t.phase, t.towns = 1, 1, "grow", r:actedTowns()
		t.built = 0
		r:log("FAST", { { "rounds", t.rounds }, { "towns", #t.towns }, { "x", t.factor } })
	end
	if t.idx > #t.towns then
		r:log("ROUND", { { "round", t.round }, { "of", t.rounds }, { "built", t.built } })
		t.round, t.idx, t.phase = t.round + 1, 1, "grow"
		if t.round > t.rounds then return r:endTask(t, "built=" .. t.built) end
		t.towns = r:actedTowns()
		return
	end
	local town = t.towns[t.idx]
	if t.phase == "grow" then
		t.phase = "check"
		if not r:growPass(t, town, t.factor, R.FAST_PASS_S) then t.phase = "next" end
		return
	end
	if t.phase == "check" then
		if t.jobOutcome ~= nil then
			if t.jobOutcome == "built" then t.built = t.built + 1 end
			t.jobOutcome = nil
			t.phase = "next"
			return
		end
		r:startJob(t, town, now, { force = false, styleMode = "main" })
		return
	end
	t.idx, t.phase = t.idx + 1, "grow"
end

--- Roundabout here: a roundabout at the dead end nearest the camera of the town nearest the camera.
function K.rb(r, t, _now)
	if t.sent then return r:endTask(t, t.cmdDone and "built" or "failed") end
	t.sent = true
	local sent = r:roundabout(t, t.town, { mode = "camera", x = t.x, y = t.y, ringMode = r.showOpts.ringMode, tag = "RB",
		onResult = function(res)
			if res.edges then
				r.rbProbe = { town = t.town, ring = res.ring, arms = res.arms, centre = res.centre,
					text = string.format("%s: %s ring, %d ring + %d arm edges at %.0f, %.0f", r.E.name(t.town), res.size, #res.ring,
						#res.arms, res.centre[1], res.centre[2]) }
			end
		end })
	if not sent then return r:endTask(t, "refused") end
end

--- Reset showcase: destroys the showcase towns one by one (makeTownDestroyCmd) and logs what stays (street
--- edges within 1.2 km of each town's centre before / after). Streets left -> the next layout moves by an offset.
function K.destroy(r, t, _now)
	local E, X = r.E, r.X
	if t.list == nil then
		t.list, t.i, t.left = {}, 0, 0
		local byName = {}
		for _, id in ipairs(E.towns()) do byName[E.name(id)] = id end
		local items = r.L.items(r.SC.styles(r.S, r.ST), { era = true, roundabout = true })
		for _, it in ipairs(items) do
			local tw = r.show and r.show.towns[it.key] or nil
			local id = (tw and tw.town) or byName[it.label]
			if id then t.list[#t.list + 1] = { town = id, label = it.label } end
		end
		r:log("SHOWCASE DESTROY", { { "towns", #t.list } })
	end
	local cur = t.cur
	if cur then
		local after = #E.streets(cur.x, cur.y, 1200)
		local still = false
		for _, id in ipairs(E.towns()) do if id == cur.town then still = true end end
		t.left = t.left + after
		r:log("SHOWCASE DESTROYED", { { "town", cur.town }, { "label", cur.label }, { "ok", t.cmdDone == true },
			{ "townExists", still }, { "edgesBefore", cur.before }, { "edgesAfter", after } })
		t.cur = nil
	end
	t.i = t.i + 1
	local it = t.list[t.i]
	if it == nil then
		r.show = nil
		if t.left > 0 then
			local off = r.showOpts.offset
			r.showOpts.offset = (off == nil) and { 1250, 1250 } or nil
		end
		r:log("SHOWCASE RESET", { { "destroyed", #t.list }, { "edgesLeft", t.left },
			{ "nextOffset", r.showOpts.offset and string.format("%d,%d", r.showOpts.offset[1], r.showOpts.offset[2]) or "-" } })
		return r:endTask(t, "done")
	end
	local x, y = E.boxCentre(it.town)
	x, y = x or 0, y or 0
	t.cur = { town = it.town, label = it.label, x = x, y = y, before = #E.streets(x, y, 1200) }
	t.cmdDone, t.waitCmd, t.cmdUs, t.sleepAfter = nil, true, r.nowUs, 0
	X.destroyTown(it.town, function(ok) t.cmdDone = ok == true end)
end

--- Showcase: build all (otd_showcase): layout -> create -> grow round-robin -> report. Resumes a stopped one.
function K.showcase(r, t, now)
	local SC = r.SC
	if t.phase == nil then
		t.phase = "run"
		local resume = r.show ~= nil
		if r.show == nil then
			local o = r.showOpts
			r.show = SC.new(t.n, { fill = o.fill, freeze = o.freeze, ringMode = o.ringMode, offset = o.offset,
				shapes = o.shapes ~= false, density = o.density ~= false })
		end
		local sh = r.show
		sh.n = t.n
		if sh.phase == "done" then sh.phase = "grow" end
		sh.startUs = sh.startUs or now
		-- the main driver would grow the new towns as NA grids: held now and after (Resume button)
		r.H.paused = true
		r:log("SHOWCASE START", { { "n", sh.n }, { "resume", resume }, { "phase", sh.phase }, { "mainPaused", true },
			{ "ownJoins", r.driver.allowNoConfig == true }, { "player", r.H.player == true }, { "fill", sh.opts.fill == true },
			{ "freeze", sh.opts.freeze == true }, { "ring", sh.opts.ringMode or "oneway" }, { "shapeRow", sh.opts.shapes ~= false },
			{ "densityRow", sh.opts.density ~= false }, { "settle", r.showOpts.settle or "off" },
			{ "settleCapMin", r.showOpts.settleCap or "-" }, { "settleForce", r.showOpts.settleForce == true },
			{ "diagnose", r.H.diagnose == true } })
		return
	end
	local sh = r.show
	local nextPhase
	if sh.phase == "layout" then nextPhase = SC.layout(r, sh)
	elseif sh.phase == "create" then nextPhase = SC.create(r, t, sh, now)
	elseif sh.phase == "grow" then nextPhase = SC.grow(r, t, sh, now)
	elseif sh.phase == "settle" then nextPhase = SC.settle(r, t, sh, now)
	elseif sh.phase == "report" then
		SC.report(r, sh, now)
		sh.phase = "done"
		return r:endTask(t, "done")
	else
		nextPhase = "failed"
	end
	if nextPhase == "failed" then
		r.show = nil   -- a fresh layout next time
		return r:endTask(t, "failed")
	end
	if nextPhase then
		sh.phase = nextPhase
		r:log("SHOWCASE PHASE", { { "phase", nextPhase } })
	end
end

--- Grow towns: the selected town (all passes) or every acted-on town (one pass each), no streets.
function K.growTowns(r, t, _now)
	if t.idx == nil then t.idx, t.pass = 1, 1 end
	local town = t.towns[t.idx]
	if town == nil then return r:endTask(t, "done") end
	if t.pass > t.passes then
		t.idx, t.pass = t.idx + 1, 1
		return
	end
	local mult = t.pass == 1 and t.factor or 1
	t.pass = t.pass + 1
	r:growPass(t, town, mult, t.passes > 1 and R.GROW_PASS_S or R.FAST_PASS_S)
end

---------------------------------------------------------------------------
-- Simulate natural growth (otd_simgrow)

--- The simulation's engine: towns, names, centres, growth inputs, the game's UpdateSize command (no forced
--- building update), building counts, game speed, the min district weight, SIMGROW log lines.
function Runner:simEnv()
	local E, X = self.E, self.X
	return {
		towns = E.towns, name = E.name, centre = E.boxCentre, town = X.townGrowth, updateSize = X.updateSize, year = E.year,
		caps = E.townCaps and function(t)
			local c = E.townCaps(t)
			if c == nil then return nil end
			return { actual = c.actual, target = c.target }
		end or nil,
		buildings = X.buildingCounts, speed = X.gameSpeed, minWeight = X.minDistrictWeight,
		mainMark = function(towns, now) return self:simMainMark(towns, now) end,
		mainSeen = function(mark, now) return self:simMainSeen(mark, now) end,
		roundStart = function(towns, now, o) return self:simRoundStart(towns, now, o) end,
		roundTick = function(rd, now) return self:simRoundTick(rd, now) end,
		roundReady = function(rd) return self:simRoundReady(rd) end,
		roundFilling = function(rd, t, on) return self:simRoundFilling(rd, t, on) end,
		setYear = X.setYear,
		reactivate = X.setDevelopmentActive and function(t, cb) X.setDevelopmentActive(t, true, cb) end or nil,
		log = function(what, fields) self:log(what, fields) end,
		-- (2026-10-14: the main driver's frame builds and gap holds, per SIMGROW year)
		mainCounts = function()
			local m = self:main()
			return m and m.counts or nil
		end,
	}
end

---------------------------------------------------------------------------
-- The simulation's build round (2026-10-13): the main mod's own turn on every town that grew in a chunk. The main
-- driver's scheduler is held (H.devBusy, as a dev task holds it) once its running job ended; the towns' jobs run on the
-- "simPool" drivers (R.BUILD_INFLIGHT at once, one job per town at a time), which share the main driver's per-town
-- state (demand ledger, own streets, history, samplers), scheduler, counts, config, log prefix and engine: each job is
-- the main mod's normal check -> plan -> build (force = false: its trigger decides), so the ledger, the "served"
-- demand and the cooldowns move exactly as in a normal check. After a build the town is checked again (its trigger
-- decides once more), until a check doesn't build, SG.ROUND_BUILDS builds or SG.ROUND_MAX_S (running jobs finish).

--- The round's owner: the main driver (visible, configured, not off or paused), or nil and why.
function Runner:simRoundOwner()
	local m = self:main()
	if m == nil then return nil, "noMain" end
	if m.phase == "off" then return nil, "mainOff" end
	if m.opts == nil then return nil, "mainInit" end
	if self.H.paused == true then return nil, "mainPaused" end
	return m
end

--- Pool drivers of the round record each check's verdict (why, demand) for the round summary (a wrapper of the
--- instance's measure; the main mod is unchanged).
function Runner:simWrapMeasure(d)
	local base = d.measure
	if type(base) ~= "function" then return end
	local r = self
	d.measure = function(dd, t)
		local m, a, b = base(dd, t)
		local rd = r.simRound
		if rd and type(m) == "table" then rd.measured[t] = { why = m.why, demand = m.dem and m.dem.edges or nil } end
		return m, a, b
	end
end

--- Starts a round for `towns` (most growth first): holds the main driver at once. o = { builds, maxS } or nil (the
--- round's limits; nil: SG.ROUND_BUILDS / ROUND_MAX_S). Returns the round, or nil and why.
function Runner:simRoundStart(towns, now, o)
	local m, why = self:simRoundOwner()
	if m == nil then return nil, why end
	if self.simRound ~= nil then return nil, "busy" end
	o = o or {}
	local rd = { towns = towns, startUs = now, owner = m, stage = "hold", per = {}, measured = {}, checks = 0, builds = 0,
		edges = 0, maxBuilds = o.builds or self.SG.ROUND_BUILDS, maxS = o.maxS or self.SG.ROUND_MAX_S, filling = {},
		handed = {} }
	for _, t in ipairs(towns) do rd.per[t] = { checks = 0, builds = 0, edges = 0 } end
	self.simRound = rd
	self.H.devBusy = true
	-- (2026-10-14, ot_satpace: the main mod founds at most one offshoot per round; SATPACE `simYear=`)
	self.simRoundN = (self.simRoundN or 0) + 1
	self.H.simRound = self.simRoundN
	self.H.simYears = self.sim and self.sim.years or nil
	-- (2026-10-14, run 2026-10-14_0502_sqot year 8: the main mod's dose / upward fills inside the round timed out; the
	-- Fast fill after the round covers them)
	self.H.simNoFills = true
	return rd
end

--- One job of the round ended: the town's tally; built -> checked again (unless capped or out of time).
function Runner:simRoundResult(rd, it)
	local SG = self.SG
	local pt = rd.per[it.town]
	if pt == nil then return end
	pt.checks = pt.checks + 1
	rd.checks = rd.checks + 1
	local mz = rd.measured[it.town]
	rd.measured[it.town] = nil
	pt.why = mz and mz.why or it.outcome or "-"
	pt.demand = mz and mz.demand or pt.demand
	if it.outcome == "built" then
		local n = (it.job and it.job.spec and it.job.spec.edges) and #it.job.spec.edges or 0
		pt.builds, pt.edges = pt.builds + 1, pt.edges + n
		rd.builds, rd.edges = rd.builds + 1, rd.edges + n
		if pt.demand then pt.demand = math.max(0, pt.demand - n) end
		if pt.builds >= (rd.maxBuilds or SG.ROUND_BUILDS) then
			pt.capped = true
		elseif rd.abort then
			pt.cut = true
		else
			local P = rd.pool
			if P then P.items[#P.items + 1] = { town = it.town, opts = {}, key = it.town } end
		end
	else
		pt.served = true
	end
	-- (no further job for the town in this round: its fill may go out now, simRoundReady)
	pt.done = pt.served or pt.capped or pt.cut or nil
end

--- A town's building extent for the neighbour rule: the radius of the main driver's last check of it (townState
--- extR), else SG.ROUND_R_DEFAULT.
function Runner:simTownR(t)
	local m = self.simRound and self.simRound.owner or self:main()
	local s = m and m.towns and m.towns[t]
	local r = s and tonumber(s.extR)
	if r == nil or r <= 0 then r = self.SG.ROUND_R_DEFAULT end
	return r
end

--- May the plans of towns a and b meet? Centres closer than rA + rB + 2 x SG.ROUND_REACH_M (each plan stays within its
--- town's extent + ROUND_REACH_M; the SG constants' note). Unknown centres: no.
function Runner:simNear(a, b)
	local centre = self.E.boxCentre
	if centre == nil or a == b then return false end
	local x, y = centre(a)
	local ux, uy = centre(b)
	if x == nil or ux == nil then return false end
	local d = self:simTownR(a) + self:simTownR(b) + 2 * self.SG.ROUND_REACH_M
	return (ux - x) ^ 2 + (uy - y) ^ 2 < d * d
end

--- May town t's job start beside the running ones? Not when its plan extent may meet a running job's town's (real
--- maps have neighbour towns closer than the showcase's 2.5 km grid: their proposals could meet at the rims) or a town
--- whose fill is in flight (its forced houses and the game's own streets for them).
function Runner:simRoundClear(t, slots)
	for _, sl in pairs(slots) do
		local u = sl.it and sl.it.town
		if u ~= nil and u ~= t and self:simNear(t, u) then return false end
	end
	local rd = self.simRound
	for u in pairs(rd and rd.filling or {}) do
		if u ~= t and self:simNear(t, u) then return false end
	end
	return true
end

--- Towns of the round whose part ended (served, capped or cut: no further job) and that no running job's town may
--- reach, each handed out once: the simulation fills them while the round goes on elsewhere (Sim:earlyFill).
function Runner:simRoundReady(rd)
	local out = {}
	if rd == nil or rd ~= self.simRound or rd.pool == nil then return out end
	for _, t in ipairs(rd.towns) do
		local pt = rd.per[t]
		if pt and pt.done and not rd.handed[t] then
			local clear = true
			for _, sl in pairs(rd.pool.slots) do
				local u = sl.it and sl.it.town
				if u == t or (u ~= nil and self:simNear(t, u)) then clear = false break end
			end
			if clear then
				rd.handed[t] = true
				out[#out + 1] = t
			end
		end
	end
	return out
end

--- A town's fill went out (on) or came back (off) during the round: no neighbour job starts meanwhile.
function Runner:simRoundFilling(rd, t, on)
	if rd == nil or rd.filling == nil then return end
	rd.filling[t] = on and true or nil
end

--- The round's end: releases the main driver, returns the summary for SIMGROW round.
function Runner:simRoundEnd(rd, now, why)
	local served, capped, left, known = 0, 0, 0, false
	local rows = {}
	for _, t in ipairs(rd.towns) do
		local pt = rd.per[t]
		if pt.served then served = served + 1 end
		if pt.capped then capped = capped + 1 end
		if pt.demand then left, known = left + pt.demand, true end
		rows[#rows + 1] = string.format("%s:%d/%d:%s%s", (tostring(self.E.name(t)):gsub("[%s=,:]", "_")), pt.builds,
			pt.checks, tostring(pt.why or "-"), pt.demand and string.format(":%.0f", pt.demand) or "")
	end
	if self.simRound == rd then self.simRound = nil end
	self.H.simNoFills = false
	-- (2026-10-14: the level-weight probe per round: when does the engine set a town's custom weights? LEVELS read)
	local mo = rd.owner
	if mo ~= nil and type(mo.levelsProbe) == "function" then
		pcall(mo.levelsProbe, mo, "simgrow:year=" .. tostring(self.sim and self.sim.years or "?"))
	end
	self.H.devBusy = self.task ~= nil or #self.tasks > 0 or self:simHolds()
	local lp = rd.lastPool
	return { towns = #rd.towns, checks = rd.checks, builds = rd.builds, edges = rd.edges, served = served, capped = capped,
		demandLeft = known and left or nil, s = (now - rd.startUs) / 1e6, peak = lp and lp.peak or 0, why = why or "done",
		per = table.concat(rows, ",") }
end

--- The build round's jobs at once: SG.ROUND_INFLIGHT, at most R.POOL_MAX.
function R.roundInflight(SG)
	return math.max(1, math.min(R.POOL_MAX, (SG and SG.ROUND_INFLIGHT) or R.BUILD_INFLIGHT))
end

--- One tick of the round: waits for the main driver's running job (at most SG.ROUND_START_S), then the pool.
--- Returns nil while running, else the summary.
function Runner:simRoundTick(rd, now)
	local SG = self.SG
	if rd == nil or rd ~= self.simRound then return { why = "lost" } end
	self.H.devBusy = true
	if rd.stage == "hold" then
		local m = rd.owner
		if m.job ~= nil or m.inflight or self.task ~= nil then
			if now - rd.startUs > SG.ROUND_START_S * 1e6 then return self:simRoundEnd(rd, now, "mainBusy") end
			return nil
		end
		rd.stage, rd.buildUs = "build", now
		local items = {}
		for _, t in ipairs(rd.towns) do items[#items + 1] = { town = t, opts = {}, key = t } end
		self:buildBatch(rd, items, function(it) self:simRoundResult(rd, it) end, R.roundInflight(SG), rd.owner, "simPool")
		rd.pool.canStart = function(it, slots) return self:simRoundClear(it.town, slots) end
	end
	if rd.pool then
		if not rd.abort and now - (rd.buildUs or now) > (rd.maxS or SG.ROUND_MAX_S) * 1e6 then rd.abort, rd.timeout = true, true end
		self:poolStep(rd, now)
		if rd.pool then return nil end
	end
	return self:simRoundEnd(rd, now, rd.timeout and "time" or nil)
end

--- A round left behind by Stop or an error: no new jobs, the running ones finish, then the main driver is free.
function Runner:simRoundDrain(now)
	local rd = self.simRound
	if rd == nil then return end
	rd.abort = true
	if rd.pool then self:poolStep(rd, now) end
	if rd.pool == nil then self:simRoundEnd(rd, now, "stopped") end
end

--- The main driver to wait for (visible, running, not paused, not held by a dev task), or nil.
function Runner:simMainDriver()
	local m = self:main()
	if m == nil or m.phase == "off" or self.H.paused == true or self.H.devBusy == true then return nil end
	return m
end

--- Wait mark after a Fast fill: the main driver's check / build counts and each town's scheduler cooldown end
--- (ot_assess sched.towns[t].nextUs, set when a check of the town ends). nil = no main driver to wait for.
function Runner:simMainMark(towns, now)
	local m = self:simMainDriver()
	if m == nil then return nil end
	local counts = m.counts or {}
	local mark = { usAt = now, towns = {}, checks = counts.checks or 0, builds = counts.builds or 0 }
	local sched = m.sched and m.sched.towns
	for _, t in ipairs(towns) do
		local s = sched and sched[t]
		mark.towns[#mark.towns + 1] = { t = t, next = s and s.nextUs or false }
	end
	return mark
end

--- Progress of the wait: { seen (towns checked since the mark, or on a cooldown past the wait), total, busy (a
--- job or command of the main driver running), checks, builds (since the mark) }, or nil (stop waiting).
function Runner:simMainSeen(mark, now)
	local m = self:simMainDriver()
	if m == nil or mark == nil then return nil end
	local counts = m.counts or {}
	local checks = (counts.checks or 0) - mark.checks
	local sched = m.sched and m.sched.towns
	local seen = 0
	local limitUs = mark.usAt + self.SG.WAIT_MAX_S * 1e6
	if sched == nil then
		seen = math.max(0, math.min(#mark.towns, checks))   -- no scheduler visible: count checks
	else
		for _, it in ipairs(mark.towns) do
			local nx = sched[it.t] and sched[it.t].nextUs
			if nx ~= nil and (nx ~= it.next or nx > limitUs) then seen = seen + 1 end
		end
	end
	return { seen = seen, total = #mark.towns, busy = m.job ~= nil or m.inflight == true, checks = checks,
		builds = (counts.builds or 0) - mark.builds }
end

--- The main driver's check pace during a run (waitMain): D.CHECK_S -> SG.MAIN_CHECK_S, ot_assess COOLDOWN_S x
--- SG.MAIN_COOLDOWN_MULT; on = false restores the saved values. Returns a log text.
function Runner:simMainPace(on)
	local D, A, SG = self.D, self.A, self.SG
	if on then
		if self.simPaceSaved ~= nil or D == nil or type(D.CHECK_S) ~= "number" then return "-" end
		local saved = { check = D.CHECK_S, cool = {} }
		D.CHECK_S = math.min(D.CHECK_S, SG.MAIN_CHECK_S)
		if A ~= nil and type(A.COOLDOWN_S) == "table" then
			for k, v in pairs(A.COOLDOWN_S) do
				if type(v) == "number" then
					saved.cool[k] = v
					A.COOLDOWN_S[k] = v * SG.MAIN_COOLDOWN_MULT
				end
			end
		end
		self.simPaceSaved = saved
		return string.format("check%.2fs_cooldownx%.2f", D.CHECK_S, SG.MAIN_COOLDOWN_MULT)
	end
	local saved = self.simPaceSaved
	if saved == nil then return "-" end
	D.CHECK_S = saved.check
	if A ~= nil and type(A.COOLDOWN_S) == "table" then
		for k, v in pairs(saved.cool) do A.COOLDOWN_S[k] = v end
	end
	self.simPaceSaved = nil
	return "restored"
end

--- Game speed during a run: SG.SIM_SPEED (when the game runs slower; a paused game is left alone); off restores
--- the previous speed if it is still SG.SIM_SPEED (a speed the player picked meanwhile stays).
function Runner:simGameSpeed(on)
	local X, SG = self.X, self.SG
	if X.gameSpeed == nil or X.setGameSpeed == nil then return "-" end
	local cur = X.gameSpeed()
	if on then
		if self.simSpeedPrev ~= nil or cur == nil or cur <= 0 or cur >= SG.SIM_SPEED then return tostring(cur or "-") end
		self.simSpeedPrev = cur
		X.setGameSpeed(SG.SIM_SPEED, function(ok) self:log("SIMGROW speed", { { "speed", SG.SIM_SPEED }, { "ok", ok }, { "was", cur } }) end)
		return string.format("%s->%d", tostring(cur), SG.SIM_SPEED)
	end
	local prev = self.simSpeedPrev
	if prev == nil then return "-" end
	self.simSpeedPrev = nil
	if cur ~= SG.SIM_SPEED then return string.format("kept%s", tostring(cur)) end
	X.setGameSpeed(prev, function(ok) self:log("SIMGROW speed", { { "speed", prev }, { "ok", ok }, { "restored", true } }) end)
	return string.format("%s->%s", tostring(cur), tostring(prev))
end

--- Does the simulation hold the main driver now? Its fill after a build round (2026-10-14: run 2026-10-14_0302's
--- main driver built right after each round, its proposal queued with the 16 forced updates, BUILT ms=8717 / 16859, and
--- the fill waited for it: fillS up to 20.7 s instead of 4-10). The round itself holds through self.simRound.
function Runner:simHolds()
	local sim = self.sim
	return sim ~= nil and sim.running == true and sim.buildRound == true and sim.phase == "fill"
end

--- Build out's gaps of the main mod's upward doses and level weights (ot_upward GAP_S / LV_GAP_S, real seconds) during
--- the run: SG.BUILDOUT.upGapS, so a town can get each about once per chunk (in normal play a chunk's 10 years take
--- hours). on = false restores them. Returns a log text.
function Runner:simUpPace(on)
	local UP, SG = self.UP, self.SG
	if on then
		if self.simUpSaved ~= nil or UP == nil or type(UP.GAP_S) ~= "number" then return "-" end
		local g = SG.BUILDOUT.upGapS
		self.simUpSaved = { gap = UP.GAP_S, lv = UP.LV_GAP_S }
		UP.GAP_S = math.min(UP.GAP_S, g)
		if type(UP.LV_GAP_S) == "number" then UP.LV_GAP_S = math.min(UP.LV_GAP_S, g) end
		return string.format("gap%ss", tostring(g))
	end
	local saved = self.simUpSaved
	if saved == nil or UP == nil then return "-" end
	UP.GAP_S, UP.LV_GAP_S = saved.gap, saved.lv
	self.simUpSaved = nil
	return "restored"
end

--- Start (or resume: same seed, stopped) the simulation. p = { pace, seed, limit, fillEvery (1-based indices into
--- SG.PACES / SEEDS / LIMITS / FILL_EVERY), scope ("near" | "all"), x, y (camera), bias, tourWhenDone, fastFill,
--- waitMain, speedUp, moveDate (the game date follows the years) (false = off; nil = on), mode ("quick" | "buildout"
--- | nil) }. Build out (SG.BUILDOUT) always starts fresh from the towns' current size: YEARS more years in CHUNKS
--- steps, every town grows, the tour at the end, as fast as possible.
function Runner:simStart(p, now)
	local SG = self.SG
	if SG == nil then
		self:log("REFUSED", { { "action", "simStart" }, { "why", "simgrow module not loaded" } })
		return
	end
	if self.sim and self.sim.running then
		self:log("REFUSED", { { "action", "simStart" }, { "why", "already running (Stop first)" } })
		return
	end
	local buildOut = p.mode == "buildout"
	-- (2026-10-14, run 2026-10-14_0502_sqot: Quick started before HEAD done and head rounds ran between the simulated
	-- years. Then Quick waited for HEAD done (several minutes, too long for the user); now any start ends the head
	-- start at once (HEAD done cut=simgrow) and the first simulated year gets a build round instead)
	local mh = self:main()
	local headCut = 0
	if mh ~= nil and mh.head ~= nil and mh.headEnd then headCut = mh:headEnd("simgrow") end
	local opts = {
		pace = SG.PACES[tonumber(p.pace) or 0] or SG.PACES[SG.PACE_DEFAULT],
		seed = SG.SEEDS[tonumber(p.seed) or 0] or SG.SEEDS[1],
		limit = SG.LIMITS[tonumber(p.limit) or 0] or 0,
		near = (p.scope == "near" and tonumber(p.x) and tonumber(p.y)) and { tonumber(p.x), tonumber(p.y) } or nil,
		bias = p.bias ~= false, even = p.even == true, tourWhenDone = p.tourWhenDone == true,
		fastFill = p.fastFill ~= false, waitMain = p.waitMain ~= false, buildRound = p.buildRound ~= false,
		fillEvery = SG.FILL_EVERY[tonumber(p.fillEvery) or 0] or SG.FILL_EVERY[SG.FILL_EVERY_DEFAULT],
		moveDate = p.moveDate ~= false, mode = p.mode or "custom",   -- (§68: nil = on)
		firstRound = headCut > 0,
	}
	if buildOut then
		local B = SG.BUILDOUT
		opts.pace, opts.limit, opts.chunk = 0, B.years, B.years / B.chunks
		opts.even, opts.tourWhenDone, opts.fastFill, opts.buildRound, opts.waitMain = true, true, true, true, true
		opts.roundBuilds, opts.roundMaxS = B.roundBuilds, B.roundMaxS
	end
	local resume = not buildOut and self.sim ~= nil and self.sim.seed == opts.seed and self.sim.chunk == nil
	if resume then self.sim:configure(opts) else self.sim = SG.new(self:simEnv(), opts) end
	local picked, c = self.sim:start(now, resume)
	-- (2026-10-14, session 2026-10-14_2237_sqot-dev: Quick on the Blank Slate showcase map with no towns ran 40 empty
	-- years at once, moved the calendar 2028 -> 2060 and toured nothing; now refused)
	if #picked == 0 then
		self.sim:stop("noTowns")
		self:log("REFUSED", { { "action", "simStart" }, { "mode", opts.mode },
			{ "why", opts.near and "no towns near the camera" or "no towns on this map" } })
		return
	end
	local m = self:main()
	local mainPace = (opts.waitMain or opts.buildRound) and self:simMainPace(true) or "-"
	local upPace = buildOut and self:simUpPace(true) or "-"
	local speed = p.speedUp ~= false and self:simGameSpeed(true) or tostring(self.X.gameSpeed and self.X.gameSpeed() or "-")
	self.sim.speedUp = p.speedUp ~= false
	self:log("SIMGROW start", { { "mode", opts.mode }, { "chunks", buildOut and SG.BUILDOUT.chunks or "-" },
		{ "years", buildOut and SG.BUILDOUT.years or opts.limit }, { "moveDate", opts.moveDate },
		{ "startYear", self.sim.startYear or "-" }, { "upGap", upPace },
		{ "seed", opts.seed }, { "pace", opts.pace }, { "scope", opts.near and "near" or "all" },
		{ "near", opts.near and string.format("%.0f,%.0f,r%d", opts.near[1], opts.near[2], SG.NEAR_M) or "-" },
		{ "limit", opts.limit }, { "bias", opts.bias }, { "even", opts.even }, { "tourWhenDone", opts.tourWhenDone }, { "resume", resume },
		{ "years", self.sim.years }, { "towns", #picked }, { "none", c.none }, { "slow", c.slow }, { "medium", c.medium },
		{ "fast", c.fast }, { "minWeight", self.sim.minW }, { "stepsPerYear", SG.STEPS_PER_YEAR },
		{ "cmdSteps", SG.cmdSteps(opts.pace) }, { "fastFill", opts.fastFill }, { "fillEvery", opts.fillEvery },
		{ "fillRatio", SG.FILL_RATIO }, { "waitMain", opts.waitMain }, { "waitMaxS", SG.WAIT_MAX_S },
		{ "buildRound", opts.buildRound }, { "roundBuilds", opts.roundBuilds or SG.ROUND_BUILDS },
		{ "roundMaxS", opts.roundMaxS or SG.ROUND_MAX_S },
		{ "inflight", R.roundInflight(SG) }, { "reachM", SG.ROUND_REACH_M },
		{ "mainPace", mainPace }, { "speed", speed }, { "mainVisible", m ~= nil },
		{ "mainPaused", self.H.paused == true }, { "buildings", self.sim.buildingsTotal or 0 } })
end

--- Stop: SIMGROW stop + one SIMGROW final line per town; the tour of all towns when asked for.
function Runner:simStop(reason, now)
	local sim = self.sim
	if sim == nil or not sim:stop(reason) then return false end
	if self.simRound then self.simRound.abort = true end   -- running jobs finish (Runner:tick drains the round)
	local builds = (self.X.buildingCounts and self.X.buildingCounts()) or {}
	local total = 0
	for _, t in ipairs(sim.order) do
		local st = sim.towns[t]
		local b = builds[t] or 0
		total = total + b
		self:log("SIMGROW final", { { "town", t }, { "name", self.E.name(t) }, { "rate", string.format("%.2f", st.rate) },
			{ "class", st.class }, { "factor", string.format("%.2f->%.2f", st.startFactor or 1, st.factor or st.startFactor or 1) },
			{ "buildings", string.format("%d->%d", st.startBuildings or 0, b) }, { "steps", st.applied or 0 } })
	end
	sim.buildingsTotal = total
	local secs = sim.startUs and now and (now - sim.startUs) / 1e6 or nil
	local mainPace = self:simMainPace(false)
	local upPace = self:simUpPace(false)
	local speed = self:simGameSpeed(false)
	self:log("SIMGROW stop", { { "reason", reason }, { "years", sim.years }, { "towns", #sim.order }, { "steps", sim.applied },
		{ "fills", sim.fills }, { "fails", sim.fails }, { "rounds", sim.rounds }, { "roundBuilds", sim.roundBuilds }, { "buildings", string.format("%d->%d", sim.buildingsStart or 0, total) },
		{ "s", secs and string.format("%.0f", secs) or "-" },
		{ "sPerYear", (secs and sim.years > 0) and string.format("%.1f", secs / sim.years) or "-" },
		{ "mainPace", mainPace }, { "upGap", upPace }, { "speed", speed }, { "tour", sim.tourWhenDone },
		{ "mode", sim.mode or "-" }, { "fillEarly", sim.earlyFills or 0 } })
	-- (the main mod's offshoot pacing over the run: SATPACE summary, foundings per decade of simulated years)
	self.H.simYears = sim.years
	self.H.simRound = nil
	local mm = self:main()
	if mm and mm.satPaceSummary then
		local okS, errS = pcall(mm.satPaceSummary, mm, "simStop", now)
		if not okS then self:log("SIMGROW warn", { { "satpace", tostring(errS) } }) end
	end
	if sim.tourWhenDone then
		-- (2026-10-14 late: run 2026-10-14_0119_sqot measured and toured while district creations were in flight, so
		-- two new towns got no ALLTOWN line and no shot; the measure now waits for the main driver's town creation)
		local m = self:main()
		if m ~= nil and m.createInFlight ~= nil and now ~= nil then
			sim.tourPending = { sinceUs = now }
			self:log("SIMGROW tour", { { "wait", "create" }, { "town", m.createInFlight.town or "-" } })
		else
			self:simTourNow(now, "now", 0)
		end
	end
	self:changed()
	return true
end

R.TOUR_AFTER_CREATE_S = 10   -- real s after the last town creation came back before the measure (its first fill)
R.TOUR_WAIT_MAX_S = 150      -- ... and at most this long in all

--- The tour's measure (allTowns) and the HUD's auto tour (sim.autoTour).
function Runner:simTourNow(now, why, waited)
	local sim = self.sim
	if why ~= "now" then
		self:log("SIMGROW tour", { { "wait", "done" }, { "why", why }, { "s", string.format("%.0f", waited or 0) } })
	end
	local ok, err = pcall(self.allTowns, self, now)
	if ok then sim.autoTour = sim.autoTour + 1 else self:log("ERROR", { { "stage", "simTour" }, { "err", err } }) end
	self:changed()
end

--- A tour waiting for the main driver's town creation (Works / district): measured once nothing is in flight for
--- TOUR_AFTER_CREATE_S, or after TOUR_WAIT_MAX_S.
function Runner:simTourPending(now)
	local sim = self.sim
	local tp = sim and sim.tourPending
	if tp == nil or now == nil then return end
	local m = self:main()
	local busy = m ~= nil and m.createInFlight ~= nil
	if busy then tp.lastBusyUs = now end
	local waited = (now - tp.sinceUs) / 1e6
	local quiet = (now - (tp.lastBusyUs or tp.sinceUs)) / 1e6
	if waited >= R.TOUR_WAIT_MAX_S then
		sim.tourPending = nil
		return self:simTourNow(now, "timeout", waited)
	end
	if not busy and quiet >= R.TOUR_AFTER_CREATE_S then
		sim.tourPending = nil
		return self:simTourNow(now, "created", waited)
	end
end

--- One simulation tick (every guiUpdate, beside the tasks).
function Runner:simTick(now)
	local sim = self.sim
	if sim == nil or not sim.running then return end
	local applied = sim.applied
	local r = sim:tick(now)
	if r == "limit" then self:simStop("limit", now) end
	if sim.applied ~= applied then self:changed() end
	-- (held through the fill too, Runner:simHolds; set here, right after the phase changed, before the main driver ticks)
	self.H.devBusy = self.task ~= nil or #self.tasks > 0 or self.simRound ~= nil or self:simHolds()
end

---------------------------------------------------------------------------
-- commands (from the HUD via guiHandleEvent) and the tick

local function pick(list, i, default)
	local v = list[tonumber(i) or 0]
	if v == nil then return default end
	return v
end

--- Handles one HUD command. p = { action, town | x, y, style, n, m, factor (1-based picker indices from
--- otd_shared lists), on, mode }. S = otd_shared. Returns the status table.
function Runner:command(p, now, S)
	self.nowUs = now
	if type(p) ~= "table" then return self:status() end
	local a = p.action
	self:ensureConfig()
	if p.style ~= nil then
		local st = pick(S.STYLES, p.style, nil)
		if st then self.styleMode = st.id end
	end
	if p.motif ~= nil and S.MOTIFS then
		-- (dev: a motif kind forced on the picked town's Grow now / Plan only; "main" = the main mod's own)
		local mo = pick(S.MOTIFS, p.motif, nil)
		if mo then self.motif = mo.id ~= "main" and mo.id or nil end
	end
	local function queue(t)
		self.taskSeq = self.taskSeq + 1
		t.id, t.startUs = self.taskSeq, now
		self.tasks[#self.tasks + 1] = t
		self:log("QUEUE", { { "task", t.label or t.kind }, { "id", t.id }, { "town", t.town or "-" },
			{ "style", t.styleMode or "-" }, { "motif", t.motif or "-" }, { "queued", #self.tasks } })
	end
	local function needTown()
		if self.selected == nil then
			self:log("REFUSED", { { "action", a }, { "why", "pick a town first" } })
			return false
		end
		return true
	end
	if a == "allTowns" then
		self:allTowns(now)
	elseif a == "select" then
		local t = tonumber(p.town)
		if t == nil and p.x ~= nil then t = self.E.closestTown(tonumber(p.x) or 0, tonumber(p.y) or 0) end
		if t == nil then
			self:log("SELECT", { { "ok", false }, { "why", "no town near the camera" } })
		else
			self.selected = t
			self:log("SELECT", { { "town", t }, { "name", self.E.name(t) } })
			self:inspect(now)
		end
	elseif a == "inspect" then
		if needTown() then self:inspect(now) end
	elseif a == "grow" then
		if needTown() then
			queue({ kind = "grow", label = "Grow now", town = self.selected, n = pick(S.N, p.n, 1), styleMode = self.styleMode,
				motif = self.motif,
				factor = pick(S.FACTORS, p.factor, 1.5) })
		end
	elseif a == "dry" then
		if needTown() then
			queue({ kind = "dry", label = "Plan only", town = self.selected, styleMode = self.styleMode, motif = self.motif })
		end
	elseif a == "undo" then
		if needTown() then queue({ kind = "undo", label = "Undo", town = self.selected }) end
	elseif a == "testStops" then
		-- (Place test stops (named): the picked town, or every acted-on town up to TESTSTOP_TOWNS)
		if p.all then
			local towns = {}
			for _, tw in ipairs(self:actedTowns()) do
				if #towns >= R.TESTSTOP_TOWNS then break end
				towns[#towns + 1] = tw
			end
			queue({ kind = "testStops", label = "Test stops (all towns)", towns = towns })
		elseif needTown() then
			queue({ kind = "testStops", label = "Test stops", town = self.selected, towns = { self.selected } })
		end
	elseif a == "district" then
		-- (main mod districts, 2026-10-14: found one on the picked town; pressed again once created: link it now)
		if needTown() then
			local m = self:main()
			if m and m.devDistrict then
				local action, started = m:devDistrict(self.selected, now)
				self:log("DISTRICTDEV", { { "town", self.selected }, { "action", action }, { "started", started } })
			else
				self:log("DISTRICTDEV", { { "town", self.selected }, { "ok", false }, { "why", "noMainDriver" } })
			end
		end
	elseif a == "satInd" then
		if needTown() then queue({ kind = "satInd", label = "Industrial satellite probe", town = self.selected }) end
	elseif a == "forceChar" then
		-- (main mod strong characters, 2026-10-14: the picked town plans as the kind on the main driver and the dev drivers)
		if needTown() then
			local done = {}
			for _, d in ipairs({ self.driver, self:main() }) do
				if d and d.devCharacter then done[#done + 1] = tostring(d:devCharacter(self.selected, p.kind)) end
			end
			self:log("CHARDEV", { { "town", self.selected }, { "name", self.E.name(self.selected) }, { "kind", p.kind or "-" },
				{ "now", #done > 0 and done[1] or "-" }, { "drivers", #done }, { "ok", #done > 0 } })
		end
	elseif a == "deepForest" then
		-- (main mod deep forest towns, 2026-10-14: the picked town plans deep on the main driver and the dev drivers)
		if needTown() then
			local done = {}
			for _, d in ipairs({ self.driver, self:main() }) do
				if d and d.devDeep then done[#done + 1] = tostring(d:devDeep(self.selected)) end
			end
			self:log("DEEPDEV", { { "town", self.selected }, { "name", self.E.name(self.selected) },
				{ "drivers", #done }, { "ok", #done > 0 } })
		end
	elseif a == "forestLane" then
		-- (no town picked: the test finds one, K.forestLane's pick phase)
		queue({ kind = "forestLane", label = "Forest lane test", town = self.selected, styleMode = self.styleMode,
			factor = pick(S.FACTORS, p.factor, 1.5) })
	elseif a == "fast" then
		queue({ kind = "fast", label = "Fast-forward", rounds = pick(S.M, p.m, 1), factor = pick(S.FACTORS, p.factor, 1.5) })
	elseif a == "growTown" then
		if needTown() then
			queue({ kind = "growTowns", label = "Grow town", town = self.selected, towns = { self.selected },
				passes = R.GROW_PASSES, factor = pick(S.FACTORS, p.factor, 1.5) })
		end
	elseif a == "growAll" then
		queue({ kind = "growTowns", label = "Grow all towns", towns = self:actedTowns(), passes = 1,
			factor = pick(S.FACTORS, p.factor, 1.5) })
	elseif a == "markers" then
		if self.plan then
			local n = self.X.markers(self.plan.edges, R.MARKER_S)
			self:log("MARKERS", { { "town", self.plan.town }, { "icons", n }, { "seconds", R.MARKER_S } })
		else
			self:log("MARKERS", { { "ok", false }, { "why", "no plan yet (Plan only first)" } })
		end
	elseif a == "pause" then
		self.H.paused = p.on == true
		self:log("PAUSE", { { "paused", self.H.paused }, { "mainVisible", self:main() ~= nil } })
	elseif a == "debug" then
		if p.mode == "on" then self.H.debug = true elseif p.mode == "off" then self.H.debug = false else self.H.debug = nil end
		self:log("DEBUG", { { "mode", p.mode or "param" } })
	elseif a == "ownJoins" then
		-- dev driver only: join dead ends without a BASE_NODE_CONFIG (our own unadopted streets). Unverified in
		-- game: the config is only added there (never removed, which crashes), see ot_proposal.
		self.driver.allowNoConfig = p.on == true
		self:log("OWNJOINS", { { "on", self.driver.allowNoConfig }, { "warn", "unverified: config added to script nodes" } })
	elseif a == "player" then
		-- every build (main and dev) with or without ctx.player (ot_hooks.player; nil = off, the default)
		self.H.player = p.on == true
		self:log("PLAYER", { { "on", self.H.player }, { "warn", self.H.player and "charged_then_refunded" or "-" } })
	elseif a == "stop" then
		local n = #self.tasks
		self.tasks = {}
		if self.task then self.task.abort = true else self.H.devBusy = self.simRound ~= nil or self:simHolds() end
		self:log("STOP", { { "dropped", n }, { "running", self.task and (self.task.label or self.task.kind) or "-" } })
	elseif a == "showcase" then
		if self.SC == nil then
			self:log("REFUSED", { { "action", a }, { "why", "showcase modules not loaded" } })
		else
			queue({ kind = "showcase", label = "Showcase", n = pick(self.SC.NS, p.sn, self.SC.NS[1]) })
		end
	elseif a == "showFocus" then
		if self.show and p.key then
			local ok, err = pcall(self.SC.focus, self, self.show, p.key)
			if not ok then self:log("ERROR", { { "stage", "showFocus" }, { "err", err } }) end
		end
	elseif a == "roundabout" then
		local t = tonumber(p.town)
		if t == nil and p.x ~= nil then t = self.E.closestTown(tonumber(p.x) or 0, tonumber(p.y) or 0) end
		if t == nil then
			self:log("REFUSED", { { "action", a }, { "why", "no town near the camera" } })
		else
			queue({ kind = "rb", label = "Roundabout here", town = t, x = tonumber(p.x), y = tonumber(p.y) })
		end
	elseif a == "nodeDump" then
		self:nodeDump(tonumber(p.x) or 0, tonumber(p.y) or 0)
	elseif a == "rbAdopt" then
		local pr = self.rbProbe
		if pr == nil then
			self:log("RB ADOPT", { { "ok", false }, { "why", "no roundabout built this session" } })
		else
			local ra, aa = self:adoption(pr.town, pr.ring), self:adoption(pr.town, pr.arms)
			self:log("RB ADOPT", { { "town", pr.town }, { "ring", string.format("%d/%d_edges_with_parcels_%d_lots_%d_built",
				ra.withParcels, ra.alive, ra.parcels, ra.built) }, { "arms", string.format("%d/%d_edges_with_parcels_%d_lots_%d_built",
				aa.withParcels, aa.alive, aa.parcels, aa.built) } })
		end
	elseif a == "showOpt" then
		local o = self.showOpts
		if p.opt == "fill" then o.fill = not o.fill
		elseif p.opt == "freeze" then o.freeze = not o.freeze
		elseif p.opt == "ring" then o.ringMode = o.ringMode == "town" and "oneway" or "town"
		elseif p.opt == "shapes" then o.shapes = not (o.shapes ~= false)
		elseif p.opt == "density" then o.density = not (o.density ~= false)
		elseif p.opt == "tourAfter" then o.tourAfter = not o.tourAfter
		elseif p.opt == "settle" then
			local v = S.SETTLE and S.SETTLE[tonumber(p.value) or 0]
			if v ~= nil then o.settle = v.id end
		elseif p.opt == "settleCap" then
			local v = S.SETTLE_CAP and S.SETTLE_CAP[tonumber(p.value) or 0]
			if v ~= nil then o.settleCap = v end
		elseif p.opt == "settleForce" then o.settleForce = not o.settleForce
		end
		self:log("SHOWCASE OPTS", { { "fill", o.fill }, { "freeze", o.freeze }, { "ring", o.ringMode }, { "shapeRow", o.shapes ~= false }, { "densityRow", o.density ~= false },
			{ "settle", o.settle or "off" }, { "settleCapMin", o.settleCap or "-" }, { "settleForce", o.settleForce == true },
			{ "tourAfterSettle", o.tourAfter == true },
			{ "note", "applies to the next new showcase (Reset or Forget first)" } })
	elseif a == "showDestroy" then
		if self.task and self.task.kind == "showcase" then
			self:log("REFUSED", { { "action", a }, { "why", "stop the showcase first" } })
		else
			queue({ kind = "destroy", label = "Reset showcase" })
		end
	elseif a == "showReset" then
		if self.task and self.task.kind == "showcase" then
			self:log("REFUSED", { { "action", a }, { "why", "stop the showcase first" } })
		else
			self.show = nil
			self:log("SHOWCASE RESET", { { "note", "next run lays out again; towns named like items are reused" } })
		end
	elseif a == "simStart" then
		self:simStart(p, now)
	elseif a == "simStop" then
		if not self:simStop("button", now) then self:log("SIMGROW stop", { { "ok", false }, { "why", "not running" } }) end
	elseif a == "simPace" then
		local v = self.SG and self.SG.PACES[tonumber(p.pace) or 0]
		if v and self.sim then
			self.sim.pace = v
			self:log("SIMGROW pace", { { "pace", v } })
		end
	elseif a == "simOpt" then
		-- a running (or stopped, for the resume) simulation's Fast fill options; the next Start sends them too
		local sim = self.sim
		if sim then
			if p.fastFill ~= nil then sim.fastFill = p.fastFill == true end
			if p.waitMain ~= nil then sim.waitMain = p.waitMain == true end
			if p.buildRound ~= nil then sim.buildRound = p.buildRound == true end
			if p.moveDate ~= nil then sim.moveDate = p.moveDate == true end
			if sim.running and (p.waitMain ~= nil or p.buildRound ~= nil) then self:simMainPace(sim.waitMain or sim.buildRound) end
			local fe = self.SG and self.SG.FILL_EVERY[tonumber(p.fillEvery) or 0]
			if fe then sim.fillEvery = fe end
			self:log("SIMGROW opts", { { "fastFill", sim.fastFill }, { "fillEvery", sim.fillEvery }, { "waitMain", sim.waitMain },
				{ "buildRound", sim.buildRound }, { "moveDate", sim.moveDate } })
		end
	elseif a == "simSpeed" then
		local v = tonumber(p.speed) or 4
		self.X.setGameSpeed(v, function(ok) self:log("SIMGROW speed", { { "speed", v }, { "ok", ok } }) end)
	elseif a == "poll" or a == "style" then
		-- status only (style: the picked style changes the inspector's second style line)
		if a == "style" and self.selected then self:inspect(now) end
	else
		self:log("REFUSED", { { "action", tostring(a) }, { "why", "unknown action" } })
	end
	self:changed()
	return self:status()
end

--- One tick (guiUpdate). Runs at most one task transition.
function Runner:tick(now)
	self.nowUs = now
	-- once, a few seconds in (both game scripts have ticked): is the main driver in this Lua state?
	if self.firstUs == nil then self.firstUs = now end
	if not self.mainLogged and now - self.firstUs > 3e6 then
		self.mainLogged = true
		local m = self:main()
		self:log("MAIN", { { "visible", m ~= nil }, { "phase", m and m.phase or "-" }, { "off", m and m.offReason or "-" } })
	end
	self.H.devBusy = self.task ~= nil or #self.tasks > 0 or self.simRound ~= nil or self:simHolds()
	if self.sim and self.sim.running then
		local okS, errS = pcall(self.simTick, self, now)
		if not okS then
			self:log("ERROR", { { "stage", "simgrow" }, { "err", errS } })
			self.sim:stop("error")
			pcall(self.simMainPace, self, false)
			pcall(self.simUpPace, self, false)
			pcall(self.simGameSpeed, self, false)
		end
	end
	-- (2026-10-14 late: a tour waiting for a town creation, after the simulation stopped)
	if self.sim and not self.sim.running and self.sim.tourPending ~= nil then
		local okP, errP = pcall(self.simTourPending, self, now)
		if not okP then
			self:log("ERROR", { { "stage", "simTour" }, { "err", errP } })
			self.sim.tourPending = nil
		end
	end
	if self.simRound and not (self.sim and self.sim.running) then
		local okR, errR = pcall(self.simRoundDrain, self, now)
		if not okR then
			self:log("ERROR", { { "stage", "simRound" }, { "err", errR } })
			self.simRound = nil
			self.H.simNoFills = false
		end
		self.H.devBusy = self.task ~= nil or #self.tasks > 0 or self.simRound ~= nil
	end
	if self.task == nil then
		if self.needInspect then
			self.needInspect = false
			local ok, err = pcall(self.inspect, self, now)
			if not ok then self:log("ERROR", { { "stage", "inspect" }, { "err", err } }) end
		end
		if #self.tasks == 0 then return end
		local m = self:main()
		if m ~= nil and (m.job ~= nil or m.inflight) then return end   -- let the main driver finish its job
		if self.simRound ~= nil then return end   -- the simulation's build round first (it shares the main state)
		self.task = table.remove(self.tasks, 1)
		self.task.startUs = now
		self:log("START", { { "task", self.task.label or self.task.kind }, { "id", self.task.id } })
	end
	local t = self.task
	if t.pool then
		self:poolStep(t, now)
		if t.pool then return end
	end
	if t.waitJob then
		self.driver:advance(now, self:savedForJobs())
		if t.jobOutcome == nil then return end
		t.waitJob = false
	end
	if t.waitCmd then
		if t.cmdDone == nil then
			if now - (t.cmdUs or now) <= (t.cmdTimeoutS or R.CMD_TIMEOUT_S) * 1e6 then return end
			t.cmdDone = false
			self:log("TIMEOUT", { { "task", t.label or t.kind }, { "s", t.cmdTimeoutS or R.CMD_TIMEOUT_S },
				{ "left", t.batchLeft or "-" } })
		end
		t.waitCmd, t.cmdTimeoutS, t.batchId = false, nil, nil
		t.sleepUntil = now + (t.sleepAfter or 0) * 1e6
	end
	if t.sleepUntil ~= nil and now < t.sleepUntil then return end
	if t.abort then return self:endTask(t, "stopped") end
	local ok, err = pcall(K[t.kind], self, t, now)
	if not ok then
		self:log("ERROR", { { "task", t.label or t.kind }, { "err", err } })
		if self.task == t then self:endTask(t, "error") end
	end
end

return R
