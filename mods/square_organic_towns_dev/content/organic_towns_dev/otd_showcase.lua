-- DEV ONLY (never upload). Organic Towns showcase: "Showcase: build all" in the dev window. Logic only; runs as a
-- task of otd_runner (dev game script guiUpdate, Main Thread) with the runner's injected modules, so
-- tests/square_organic_towns_dev drives it with fakes. Briefs: plans/square_organic_towns/SHOWCASE_BRIEF.md,
-- NEXT_PHASE_BRIEF.md (v2: speed, era row, roundabout, adoption, results).
--
--   layout  terrain box -> island extent (isOnWater scan) -> grid positions (otd_layout), every spot checked
--           for water; towns already named like an item are reused (resume after a reload)
--   create  one town at a time: createTowns + makeTownCreateCmd (findings "Stress Test probes": toRemove lists
--           every town, ignored; resultEntities empty, the new town is found by diffing the town list, rechecked
--           up to 3 x 1 s), capacities CAPS each, TownInfo angles per item; renamed to the item label when the
--           game named it otherwise (makeEntitySetNameCmd). Freeze option: style towns set inactive.
--   grow    rounds. Each round: every active style town gets a forced increment in its style, all towns' jobs
--           concurrently (v7+: r:buildBatch, R.BUILD_INFLIGHT at once on pool drivers sharing the dev driver's
--           town state; a job is plan + pre-checks + one build command + its fill; v6 ran them one by one, ~14 s of
--           waiting for build callbacks per round), then two growth passes
--           to sizeFactors 1 + step x STEP_ADD for EVERY active town sent back to back as one batch (one command
--           per town in flight, no idle between towns; v1 waited for each town's callbacks in turn), then the
--           extras: "Fill mod streets" (makeTownDevelopAtCmd on this round's new mod streets), the roundabout of
--           the roundabout town at step RB_STEP, then one STEP line per town and a ROUND line with its seconds
--           (v7+: build= / grow= / other= seconds, builds= jobs, inflight= cap, peak= most jobs at once).
--   report  per town: buildings, street edges, mod edges and their adoption (edges with parcels, houses on
--           them), shape metrics (ot_metrics); results lines for the window; a SUMMARY line
--   settle  v6 default "passes": a few forced growth batches back to back (each target one STEP_ADD further,
--           PASS_WAIT_S after each, a sample after each), no game time to wait for (v5's 2 game years took 16 real
--           minutes). Game-time modes (v4): game time runs at speed SETTLE_SPEED (makeGameSetSpeedCmd, the previous speed restored after)
--           until the mode ends it (showOpts.settle = otd_shared.SETTLE id): "1y"/"2y"/"5y" = that many game
--           months passed; "plateau" = the showcase towns' total buildings grew less than PLATEAU_FRAC and less
--           than PLATEAU_PER_TOWN per town over the last PLATEAU_SAMPLES samples, after PLATEAU_MIN_MONTHS. Any
--           mode ends at the real-time cap (showOpts.settleCap minutes; reason=cap, timedOut=true). Samples of
--           the buildings (total and per town) every game month (every SAMPLE_REAL_S without a calendar; then a
--           month counts as MONTH_REAL_S). Forced passes (showOpts.settleForce, default ON since v5: towns without
--           transport barely grow by themselves, v4 added 22 buildings in 5 months): every FORCE_MONTHS a
--           growth batch (r:growBatch, each town's target 1 + steps x STEP_ADD, one command per town in
--           flight). Sizes before / after and mod-street adoption logged (SETTLE lines); then the Auto tour can
--           start by itself (status.show.autoTour, HUD)
-- v3 rows (otd_layout): a shape row (one town per shape archetype, `shape` passed to startJob; ot_shape in the
-- main mod) and a density row (one lever per town: level weights, DevelopAt upgrade at the centre, medium
-- streets, a control). Style towns log their shape (job.style.shape) in STEP / TOWN lines.
-- v4 density lever "upgrade": ONCE per town (v3 fired it every round and the town exploded: 4655 buildings vs
-- ~650), as a downtown densifier: DevelopAt(centre, no streets, upgrade buildings) in the round of step
-- UPGRADE_STEP (3, as the roundabout: the town has a core by then), after that round's growth passes. Its
-- buildings / capacity right before are compared at the town's next STEP line (DENSITY effect).
-- A town stops after K_FAIL consecutive refused builds or K_EMPTY consecutive empty plans, with the reason logged.
-- Stop ends the task after its current step; the showcase state stays in the runner, so "Showcase: build all"
-- again resumes (also with a larger N). The main driver is paused (ot_hooks.paused) and stays paused.
-- Every line starts with "[SQOT_DEV] SHOWCASE".

local SC = {}

SC.CAPS = 250            -- initialLandUseCapacities per land use (vanilla default 100: ~58 buildings; 250: ~150)
SC.STEP_ADD = 0.25       -- forced growth: sizeFactors 1 + step x STEP_ADD
SC.PASS_S = 0            -- no pause after a growth batch (user: build fast, 2026-10-11)
SC.K_FAIL = 3
SC.K_EMPTY = 4
SC.FIND_TRIES = 3
SC.FIND_S = 1
SC.NS = { 10, 20, 40 }   -- increments per town (picker)
SC.SEED = "sqotdev"
SC.RB_STEP = 3           -- the roundabout town gets its roundabout after this many steps (a frontier exists)
SC.FILL_MAX = 12         -- Fill mod streets: DevelopAt points per town and round
SC.FILL_OFFSET = 20      -- ... this far either side of a new mod street's midpoint
SC.SETTLE_SPEED = 8      -- settle: twice the base bar's fastest button (makeGameSetSpeedCmd 8 sticks, findings lines-vehicles)
SC.MONTH_REAL_S = 40     -- settle without a readable calendar: real seconds per game month (v3: 2 months, 80 s)
SC.SAMPLE_REAL_S = 20    -- ... and a sample every this many real seconds (with a calendar: every game month)
SC.SAMPLE_MONTHS = 1
SC.PLATEAU_SAMPLES = 3   -- plateau: growth over the last 3 samples ...
SC.PLATEAU_FRAC = 0.01   -- ... below 1 % of the total ...
SC.PLATEAU_PER_TOWN = 2  -- ... and below 2 buildings per town ...
SC.PLATEAU_MIN_MONTHS = 6   -- ... after at least 6 game months
SC.FORCE_MONTHS = 2      -- forced growth passes during the settle: every 2 game months
SC.PASS_WAIT_S = 6       -- settle "passes": real seconds after each pass (UpdateSize builds within ~5 s, findings)
SC.SETTLE_MOD = true     -- v9: the main mod's normal check (needs-room trigger) on every style town after each pass
SC.UPGRADE_STEP = 3      -- density lever "upgrade": once, in the round of this step
SC.MEDIUM = { main = "medium", medium = "medium", small = "medium" }   -- density lever "medium streets"

local function fmtMoney(v)
	if type(v) ~= "number" then return "-" end
	return string.format("%.1fM", v / 1e6)
end

--- The style list for otd_layout.items: S.STYLES profile entries with their profile's angleRange (degrees).
function SC.styles(S, ST)
	local out = {}
	for _, st in ipairs(S.STYLES) do
		local p = ST.profile(st.id)
		if p ~= nil then out[#out + 1] = { id = st.id, label = st.label, angle = p.angleRange or 0 } end
	end
	return out
end

--- opts = { fill, freeze, ringMode = "oneway"|"town", offset = {dx, dy} } (runner's showOpts at the start)
function SC.new(n, opts)
	return { n = n, phase = "layout", towns = {}, order = {}, startUs = nil, turns = 0, rounds = 0, roundS = {},
		opts = opts or {}, counts = { prune = 0, tiny = 0 } }
end

local function log(r, fields, what)
	return r:log("SHOWCASE " .. (what or ""), fields)
end

---------------------------------------------------------------------------
-- layout

function SC.layout(r, sh)
	local X, E, L = r.X, r.E, r.L
	local box = X.terrainBox()
	if box == nil then
		log(r, { { "ok", false }, { "why", "noTerrainBox" } }, "LAYOUT")
		return "failed"
	end
	local land = L.island(box, X.isWater)
	if land == nil then
		log(r, { { "ok", false }, { "why", "mapCentreIsWater" }, { "box", { box.minX, box.minY, box.maxX, box.maxY } } }, "LAYOUT")
		return "failed"
	end
	log(r, { { "box", { box.minX, box.minY, box.maxX, box.maxY } }, { "land", { land.minX, land.minY, land.maxX, land.maxY } },
		{ "width", land.maxX - land.minX }, { "height", land.maxY - land.minY } }, "ISLAND")
	local year = E.year()
	local newT = r.I.newTemplates(year)
	local rbOk = r.rbGeom ~= nil
	local items = L.items(SC.styles(r.S, r.ST), { era = newT, roundabout = rbOk, shapes = sh.opts.shapes ~= false,
		density = sh.opts.density ~= false, forms = sh.opts.shapes ~= false })
	local res = L.layout(items, land, X.isWater, { offset = sh.opts.offset })
	log(r, { { "towns", #res.placed }, { "of", #items }, { "dropped", #res.dropped }, { "spacing", res.spacing or 0 },
		{ "cols", res.cols or 0 }, { "rows", res.rows or 0 }, { "year", year }, { "era", newT and "new" or "old" },
		{ "box", { res.box.minX, res.box.minY, res.box.maxX, res.box.maxY } },
		{ "offset", sh.opts.offset and string.format("%d,%d", sh.opts.offset[1], sh.opts.offset[2]) or "-" },
		{ "fill", sh.opts.fill == true }, { "freeze", sh.opts.freeze == true }, { "roundabouts", rbOk and "yes" or (r.rbWhy or "no") },
		{ "ring", sh.opts.ringMode or "oneway" } }, "LAYOUT")
	if not newT then log(r, { { "item", "ERA_*" }, { "why", "year<1940: only old templates, no era row" } }, "SKIP") end
	if not rbOk then log(r, { { "item", "RB_EU" }, { "why", "square_roundabouts not loaded: " .. tostring(r.rbWhy) } }, "SKIP") end
	local byName = {}
	for _, t in ipairs(E.towns()) do byName[E.name(t)] = t end
	for _, p in ipairs(res.placed) do
		local it = p.item
		local tw = { key = it.key, label = it.label, kind = it.kind, style = it.style, angle = it.angle,
			newTemplates = it.newTemplates, year = it.year, roundabout = it.roundabout, shape = it.shape, lever = it.lever,
			probe = it.probe, twinOf = it.twinOf, lock = it.lock, freeze = it.freeze, fillKind = it.fillKind,
			fillStreets = it.fillStreets, fillUpgrade = it.fillUpgrade, metro = it.metro, metroCentres = it.metroCentres,
			charKind = it.charKind,
			form = it.form, x = p.x, y = p.y, row = p.row, itemRow = it.row,
			col = p.col, town = byName[it.label], steps = 0, built = 0, fails = 0, empties = 0, consecFail = 0,
			consecEmpty = 0, cost = 0, modEdges = {}, newEdges = {} }
		sh.towns[it.key] = tw
		sh.order[#sh.order + 1] = it.key
		log(r, { { "key", it.key }, { "label", it.label }, { "kind", it.kind }, { "style", it.style or "-" },
			{ "x", p.x }, { "y", p.y }, { "row", p.row }, { "col", p.col }, { "angle", it.angle or "default" },
			{ "era", SC.eraText(it, year) }, { "shape", it.shape or "-" },
			{ "lever", it.lever or "-" }, { "probe", it.probe or "-" }, { "twinOf", it.twinOf or "-" },
			{ "metro", it.metro or "-" }, { "form", it.form or "-" }, { "coast", p.coast and string.format("%.0fm_%s", p.coast, p.coastDir or "") or "-" },
			{ "swapped", p.swapped or "-" }, { "moved", p.moved == true }, { "existing", tw.town or "-" } }, "PLACE")
		if it.coast and p.coast == nil then
			log(r, { { "key", it.key }, { "why", "noShoreFound" } }, "COAST")
		end
	end
	for _, d in ipairs(res.dropped) do
		log(r, { { "key", d.item.key }, { "label", d.item.label }, { "why", d.why } }, "DROP")
	end
	-- probe twins: the shape-row town a probe town is compared with logs the same probe lines (LOCK; FREEZE effect
	-- for a freeze probe)
	for _, key in ipairs(sh.order) do
		local tw = sh.towns[key]
		local base = tw.twinOf and sh.towns[tw.twinOf]
		if base and tw.probe then
			base.probeTwin = base.probeTwin or {}
			base.probeTwin[tw.probe == "freeze" and "freeze" or "lock"] = true
		end
	end
	return #res.placed > 0 and "create" or "failed"
end

--- "1900:old" / "2020:new" / "vanilla" (the year the style is resolved for and its template era).
function SC.eraText(it, mapYear)
	if it.kind ~= "style" then return "vanilla:" .. tostring(mapYear) end
	local y = it.year or mapYear
	local newT = it.newTemplates
	if newT == nil then newT = y >= 1940 end
	return string.format("%d:%s", y, newT and "new" or "old")
end

---------------------------------------------------------------------------
-- create

function SC.create(r, t, sh, now)
	local E, X = r.E, r.X
	local c = t.create
	if c ~= nil then
		local tw = sh.towns[c.key]
		if c.stage == "sent" then
			if not t.cmdDone then
				log(r, { { "key", c.key }, { "ok", false }, { "why", "createFailed" } }, "CREATE")
				tw.stopped, tw.why = true, "createFailed"
				t.create = nil
				return
			end
			local new = nil
			for _, id in ipairs(E.towns()) do
				if not c.before[id] then new = id break end
			end
			if new == nil then
				c.tries = c.tries + 1
				if c.tries >= SC.FIND_TRIES then
					log(r, { { "key", c.key }, { "ok", false }, { "why", "newTownNotFound" } }, "CREATE")
					tw.stopped, tw.why = true, "newTownNotFound"
					t.create = nil
					return
				end
				t.sleepUntil = now + SC.FIND_S * 1e6
				return
			end
			tw.town = new
			local name = E.name(new)
			log(r, { { "key", c.key }, { "town", new }, { "name", name }, { "ok", true }, { "ms", (now - c.us) / 1000 },
				{ "tries", c.tries } }, "CREATED")
			if name ~= tw.label then
				c.stage = "rename"
				t.cmdDone, t.waitCmd, t.cmdUs, t.sleepAfter = nil, true, now, 0
				X.rename(new, tw.label, function(ok) t.cmdDone = ok == true end)
				return
			end
			c.stage = "freeze"
			return
		end
		if c.stage == "rename" then
			log(r, { { "key", c.key }, { "town", tw.town }, { "ok", t.cmdDone == true }, { "name", E.name(tw.town) } }, "RENAME")
			c.stage = "freeze"
			return
		end
		if c.stage == "freeze" then
			c.stage = "density"
			if ((sh.opts.freeze and tw.kind == "style") or tw.freeze) and X.setDevelopmentActive then
				t.cmdDone, t.waitCmd, t.cmdUs, t.sleepAfter = nil, true, now, 0
				X.setDevelopmentActive(tw.town, false, function(ok)
					t.cmdDone = ok == true
					log(r, { { "key", tw.key }, { "town", tw.town }, { "active", false }, { "ok", ok == true } }, "FREEZE")
				end)
			end
			return
		end
		if c.stage == "density" then
			t.create = nil
			if tw.lever == "weights" then SC.sendWeights(r, t, tw, now) end
			return
		end
	end
	-- next town to create (a town already named like the item is reused: resume after a stop or reload)
	local tw, byName = nil, nil
	for _, key in ipairs(sh.order) do
		local x = sh.towns[key]
		if x.town == nil and not x.stopped then
			if byName == nil then
				byName = {}
				for _, id in ipairs(E.towns()) do byName[E.name(id)] = id end
			end
			if byName[x.label] then
				x.town = byName[x.label]
				log(r, { { "key", x.key }, { "town", x.town }, { "why", "existing town with this name" } }, "REUSE")
			else
				tw = x
				break
			end
		end
	end
	if tw == nil then
		local n = 0
		for _, key in ipairs(sh.order) do if sh.towns[key].town then n = n + 1 end end
		log(r, { { "towns", n }, { "of", #sh.order } }, "CREATED_ALL")
		return "grow"
	end
	local before = {}
	for _, id in ipairs(E.towns()) do before[id] = true end
	t.cmdDone, t.waitCmd, t.cmdUs, t.sleepAfter = nil, true, now, 0
	local okSend, info = X.createTown({ x = tw.x, y = tw.y, name = tw.label, caps = SC.CAPS, angle = tw.angle,
		seed = SC.SEED .. tw.key }, function(ok) t.cmdDone = ok == true end)
	info = info or {}
	log(r, { { "key", tw.key }, { "label", tw.label }, { "x", tw.x }, { "y", tw.y }, { "caps", SC.CAPS },
		{ "angle", tw.angle or "default" }, { "angleSet", info.angleSet == nil and "-" or info.angleSet },
		{ "givenAngle", info.angle0 or "?" }, { "givenInitAngle", info.initAngle0 or "?" }, { "givenCaps", info.caps0 or "?" },
		{ "ok", okSend ~= false }, { "err", info.err or "-" } }, "CREATE")
	if okSend == false then
		t.waitCmd = false
		tw.stopped, tw.why = true, "create:" .. tostring(info.err)
		return
	end
	t.create = { key = tw.key, stage = "sent", before = before, us = now, tries = 0 }
end

---------------------------------------------------------------------------
-- grow (rounds)

local function active(tw, n)
	return tw.town ~= nil and not tw.stopped and tw.steps < n
end

--- Level weights for the density lever "weights": the style profile's `weights` (ot_style: res, optionally
--- core) as the command's three land uses x four levels (residential = res, commercial = core or res,
--- industrial = res). Plain numbers (floats).
function SC.densityWeights(profile)
	local w = (profile and profile.weights) or {}
	local function four(v)
		v = v or { 1, 1, 1, 1 }
		return { (v[1] or 1) + 0.0, (v[2] or 1) + 0.0, (v[3] or 1) + 0.0, (v[4] or 1) + 0.0 }
	end
	local res = four(w.res)
	return { res, four(w.core or w.res), four(w.res) }
end

local function weightsText(w)
	local parts = {}
	for i, l in ipairs(w) do parts[i] = string.format("%g/%g/%g/%g", l[1], l[2], l[3], l[4]) end
	return table.concat(parts, "|")
end

--- Density lever "weights": makeTownCustomDistributionWeightsCmd once, right after the town was created.
function SC.sendWeights(r, t, tw, now)
	local w = SC.densityWeights(r.ST and r.ST.profile(tw.style) or nil)
	if r.X.townWeights == nil then
		log(r, { { "key", tw.key }, { "town", tw.town }, { "lever", "weights" }, { "ok", false }, { "why", "noCommand" } }, "DENSITY")
		return
	end
	t.cmdDone, t.waitCmd, t.cmdUs, t.sleepAfter = nil, true, now, 0
	r.X.townWeights(tw.town, w, function(ok)
		t.cmdDone = ok == true
		log(r, { { "key", tw.key }, { "town", tw.town }, { "lever", "weights" }, { "weights", weightsText(w) }, { "ok", ok == true } },
			"DENSITY")
	end)
end

--- startJob options for a town (style, era, shape, density lever "medium").
function SC.jobOpts(tw)
	local o = { force = true, styleMode = tw.style, pure = true, newTemplates = tw.newTemplates, year = tw.year }
	if tw.shape then o.shape = tw.shape end
	if tw.lever == "medium" then o.override = { templates = SC.MEDIUM } end
	-- v6 probe row: the driver's lock / fill options (ot_driver.lockMode / fillKind); nil = the main mod's defaults
	if tw.lock ~= nil then o.lock = tw.lock end
	if tw.fillKind ~= nil then o.fill = tw.fillKind end
	if tw.fillStreets then o.fillStreets = true end
	if tw.fillUpgrade then o.fillUpgrade = true end
	-- v7 metropolis row: a forced ot_metro variant (polycentric with its centres from the first build)
	if tw.metro then o.metro = tw.metro end
	if tw.metroCentres then o.metroCentres = true end
	-- v8 form row: a forced town form (ot_form)
	if tw.form then o.form = tw.form end
	-- (2026-10-14: a strong character kind of the main mod, ot_character: the roundabout town's one-way rings)
	if tw.charKind then o.charKind = tw.charKind end
	return o
end

--- Records one increment outcome; stops the town after K_FAIL / K_EMPTY in a row.
function SC.record(r, sh, tw, outcome, job)
	local why = job and job.why or nil
	local shp = job and job.style and job.style.shape
	if type(shp) == "table" and shp.id then tw.shapeId, tw.shapeWhy = shp.id, shp.reason end
	local fm = job and job.style and job.style.form
	if type(fm) == "table" and fm.id then tw.formId, tw.formWhy = fm.id, fm.why end
	if job and job.style and type(job.style.axis) == "number" then tw.axis = job.style.axis end
	local cs = job and job.mp and job.mp.crescents
	if type(cs) == "table" and #cs > 0 then
		local n = 0
		for _, c in ipairs(cs) do if (c.arcs or 0) > 0 then n = n + 1 end end
		tw.crescents = string.format("%d/%d", n, #cs)
	end
	local mt = job and job.style and job.style.metro
	if mt then tw.metroVariant = mt.variant .. (#mt.centres > 0 and ("_" .. #mt.centres .. "centres") or "") end
	if job and (job.pruneRounds or 0) > 0 then sh.counts.prune = sh.counts.prune + job.pruneRounds end
	if why and tostring(why):find("^tiny") then sh.counts.tiny = sh.counts.tiny + 1 end
	-- (§65: the lock the main driver used for the town's build, ot_driver.lockMode: "mod" / "shape" / "off" / "all";
	-- only a built job has resolved its town's lock)
	if outcome ~= "built" then
		-- (nothing)
	elseif job and r.D and r.D.lockMode then
		local okL, lm = pcall(r.D.lockMode, job)
		if okL and lm then tw.lockUsed = lm end
	elseif job and job.lockModeUsed then tw.lockUsed = job.lockModeUsed end
	if outcome == "built" then
		tw.built = tw.built + 1
		tw.consecFail, tw.consecEmpty = 0, 0
		tw.cost = tw.cost + (type(job and job.cost) == "number" and job.cost or 0)
		local rec = job and job.rec
		if rec then
			for _, id in ipairs(rec.edges or {}) do
				tw.modEdges[#tw.modEdges + 1] = id
				tw.newEdges[#tw.newEdges + 1] = id
			end
			-- lock probe: the streets at this build's nodes right after it (its joints to the existing town) are the
			-- baseline; later ones there are side streets the town attached to ours (a side street attached earlier
			-- at an old tip this build joins counts as baseline from now: a small undercount)
			if SC.lockLines(tw) and r.lockProbe then
				tw.attachBase = tw.attachBase or {}
				r:lockProbe(rec.edges or {}, tw.attachBase, true)
			end
		end
	elseif outcome == "empty" or outcome == "skip" or outcome == "room" then
		tw.empties = tw.empties + 1
		tw.consecEmpty = tw.consecEmpty + 1
		tw.lastWhy = why or outcome
	else
		tw.fails = tw.fails + 1
		tw.consecFail = tw.consecFail + 1
		tw.lastWhy = why or outcome
	end
	if tw.consecFail >= SC.K_FAIL or tw.consecEmpty >= SC.K_EMPTY then
		tw.stopped = true
		tw.why = string.format("%s x%d: %s", tw.consecFail >= SC.K_FAIL and "refused" or "empty",
			math.max(tw.consecFail, tw.consecEmpty), tostring(tw.lastWhy))
		log(r, { { "key", tw.key }, { "town", tw.town }, { "label", tw.label }, { "step", tw.steps }, { "why", tw.why } }, "STOP")
	end
end

--- DevelopAt points for this round's new mod streets of a town: both sides of each midpoint, at most FILL_MAX.
function SC.fillPoints(r, tw)
	local pts = {}
	for _, id in ipairs(tw.newEdges) do
		local e = r.X.edgeGeom and r.X.edgeGeom(id) or nil
		if e then
			local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
			local dx, dy = e.p1[1] - e.p0[1], e.p1[2] - e.p0[2]
			local l = math.sqrt(dx * dx + dy * dy)
			if l > 1 then
				local nx, ny = -dy / l * SC.FILL_OFFSET, dx / l * SC.FILL_OFFSET
				pts[#pts + 1] = { mx + nx, my + ny }
				pts[#pts + 1] = { mx - nx, my - ny }
			end
		end
		if #pts >= SC.FILL_MAX then break end
	end
	while #pts > SC.FILL_MAX do table.remove(pts) end
	return pts
end

--- true when a town logs LOCK probe lines: a probe-row town (not a freeze probe) or the shape-row town one is
--- compared with.
function SC.lockLines(tw)
	return (tw.probe ~= nil and tw.probe ~= "freeze") or (tw.probeTwin ~= nil and tw.probeTwin.lock == true)
end

--- v5 probe lines for one town (`when` = "step" | "report"): LOCK for lock-probe towns and the plain shape-row twin
--- they are compared with (mod edges alive, read back locked, houses on them, side streets the town attached to
--- them since their build, vanilla edges this round), FREEZE effect for frozen towns and their twin (vanilla edges
--- this round, buildings, houses on mod edges). m = driver:measure(town) or nil; vanilla = this round's non-mod
--- edge change or nil.
function SC.probeLines(r, sh, tw, m, vanilla, when)
	local isLock = SC.lockLines(tw)
	local isFreeze = tw.probe == "freeze" or (tw.probeTwin and tw.probeTwin.freeze)
	if not isLock and not isFreeze then return end
	local ad = (#tw.modEdges > 0) and r:adoption(tw.town, tw.modEdges) or { alive = 0, withParcels = 0, parcels = 0, built = 0 }
	local role = tw.probe or "twin"
	if isLock then
		local lp = r.lockProbe and r:lockProbe(tw.modEdges, tw.attachBase or {}, false) or nil
		local edges = m and m.lots and m.lots.edges or nil
		local caps = m and m.caps or nil
		local game, share = nil, nil
		if edges and tw.edges0 then
			game = math.max(0, edges - (ad.alive or 0) - tw.edges0)
			if game + (ad.alive or 0) > 0 then share = game / (game + (ad.alive or 0)) end
		end
		log(r, { { "key", tw.key }, { "town", tw.town }, { "role", role }, { "twinOf", tw.twinOf or "-" }, { "when", when },
			{ "lockMode", tw.lock or "default" }, { "fill", tw.fillKind or "default" },
			{ "step", tw.steps }, { "modEdges", #tw.modEdges }, { "alive", ad.alive }, { "locked", lp and lp.locked or "?" },
			{ "withParcels", ad.withParcels }, { "lots", ad.parcels }, { "houses", ad.built },
			{ "attached", lp and lp.attached or "?" }, { "vanilla", vanilla or "?" },
			{ "buildings", m and m.buildings or "?" },
			-- (§65 lock A/B: the lock the driver used, the town's street edges built by the game since its first step
			-- (edges - live mod edges - its edges then), their share of the new streets, cap / target)
			{ "lockUsed", tw.lockUsed or "-" }, { "edges", edges or "?" }, { "gameEdges", game or "?" },
			{ "gameShare", share and string.format("%.2f", share) or "-" },
			{ "cap", caps and string.format("%.0f/%.0f", caps.actual or 0, caps.target or 0) or "?" },
			{ "capRatio", (caps and (caps.target or 0) > 0) and string.format("%.3f", caps.actual / caps.target) or "?" } }, "LOCK")
	end
	if isFreeze then
		log(r, { { "key", tw.key }, { "town", tw.town }, { "role", role }, { "twinOf", tw.twinOf or "-" }, { "when", when },
			{ "step", tw.steps }, { "frozen", tw.freeze == true or (sh.opts.freeze == true and tw.kind == "style") },
			{ "vanilla", vanilla or "?" }, { "edges", m and m.lots and m.lots.edges or "?" },
			{ "buildings", m and m.buildings or "?" }, { "modEdges", #tw.modEdges }, { "modHouses", ad.built },
			{ "withParcels", ad.withParcels } }, "FREEZE effect")
	end
end

--- This round's build items (r:buildBatch): style towns without an outcome yet, metropolis towns first (their
--- fill sends 12 DevelopAt one after another: the longest jobs start first).
function SC.buildItems(sh, rd)
	local first, rest = {}, {}
	for _, key in ipairs(rd.keys) do
		local tw = sh.towns[key]
		if tw.kind == "style" and tw.town ~= nil and rd.out[key] == nil then
			local it = { town = tw.town, key = key, opts = SC.jobOpts(tw) }
			if tw.metro then first[#first + 1] = it else rest[#rest + 1] = it end
		end
	end
	for _, it in ipairs(rest) do first[#first + 1] = it end
	if rd.nBuild == nil then rd.nBuild = #first end
	return first
end

--- One round: builds (style towns, concurrently) -> growth batch x2 (all towns) -> fill -> roundabout ->
--- STEP lines + ROUND line.
function SC.grow(r, t, sh, now)
	local rd = sh.rd
	if rd == nil then
		local keys = {}
		for _, key in ipairs(sh.order) do
			if active(sh.towns[key], sh.n) then keys[#keys + 1] = key end
		end
		if #keys == 0 then return "settle" end
		sh.rounds = sh.rounds + 1
		rd = { keys = keys, i = 0, stage = "build", us = now, out = {} }
		sh.rd = rd
		for _, key in ipairs(keys) do
			local tw = sh.towns[key]
			tw.steps = tw.steps + 1
			tw.newEdges = {}
		end
		sh.turns = sh.turns + #keys
		return
	end
	if rd.stage == "build" then
		-- every style town's increment of this round, concurrently (r:buildBatch, R.BUILD_INFLIGHT at once); each
		-- town's outcome is recorded by its own job's callback. Comes back here when the batch ended: towns without
		-- an outcome yet (a stopped task, resumed) go into a new batch, else on to the growth passes.
		local lp = r.lastPool
		if lp and rd.buildUs then
			rd.peak, rd.cap = math.max(rd.peak or 0, lp.peak), lp.cap
			rd.buildS = (rd.buildS or 0) + (now - rd.buildUs) / 1e6
			rd.buildUs = nil
		end
		local items = SC.buildItems(sh, rd)
		if #items == 0 then
			rd.stage = "grow1"
			return
		end
		rd.buildUs = now
		r:buildBatch(t, items, function(it)
			local tw = sh.towns[it.key]
			rd.out[it.key] = it.outcome
			SC.record(r, sh, tw, it.outcome, it.job)
		end)
		return
	end
	if rd.stage == "grow1" or rd.stage == "grow2" then
		if rd.stage == "grow1" then rd.growUs = now end
		local list = {}
		for _, key in ipairs(rd.keys) do
			local tw = sh.towns[key]
			if tw.town ~= nil then list[#list + 1] = { town = tw.town, target = 1 + tw.steps * SC.STEP_ADD, key = key } end
		end
		rd.stage = rd.stage == "grow1" and "grow2" or "fill"
		local gone = r:growBatch(t, list, SC.PASS_S)
		for _, key in ipairs(gone or {}) do
			local tw = sh.towns[key]
			tw.stopped, tw.why = true, "townGone"
		end
		return
	end
	if rd.stage == "fill" then
		rd.growS = rd.growUs and (now - rd.growUs) / 1e6 or 0
		rd.stage = "density"
		if r.X.developAt == nil then return end
		local cmds = {}
		for _, key in ipairs(rd.keys) do
			local tw = sh.towns[key]
			-- the window's global "Fill mod streets" (v5); the probe row's fills run in the driver (startJob fill)
			if tw.kind == "style" and #tw.newEdges > 0 and sh.opts.fill then
				local pts = SC.fillPoints(r, tw)
				for _, p in ipairs(pts) do cmds[#cmds + 1] = p end
				log(r, { { "key", key }, { "town", tw.town }, { "points", #pts }, { "edges", #tw.newEdges } }, "FILL")
			end
		end
		if #cmds > 0 then r:developBatch(t, cmds) end
		return
	end
	if rd.stage == "density" then
		-- density lever "upgrade": DevelopAt(centre, no streets, upgrade buildings) ONCE, at step UPGRADE_STEP
		rd.stage = "rb"
		if r.X.developAt == nil then return end
		local cmds = {}
		for _, key in ipairs(rd.keys) do
			local tw = sh.towns[key]
			if tw.lever == "upgrade" and tw.town ~= nil and tw.upgrade == nil and tw.steps >= SC.UPGRADE_STEP then
				local x, y = r.E.boxCentre(tw.town)
				if x ~= nil then
					local m = r.driver:measure(tw.town)
					local caps = r.E.townCaps(tw.town)
					tw.upgrade = { step = tw.steps, x = x, y = y, pending = true, buildings = m and m.buildings or 0,
						capacity = caps and caps.actual or 0, edges = m and m.lots and m.lots.edges or 0 }
					cmds[#cmds + 1] = { x, y, key = key, tw = tw }
				end
			end
		end
		if #cmds > 0 then
			r:sendBatch(t, cmds, function(p, cb)
				r.X.developAt(p[1], p[2], false, true, function(ok)
					p.tw.upgrade.ok = ok == true
					log(r, { { "key", p.key }, { "town", p.tw.town }, { "lever", "upgrade" }, { "once", true },
						{ "step", p.tw.upgrade.step }, { "x", p[1] }, { "y", p[2] }, { "ok", ok == true } }, "DENSITY")
					cb(ok)
				end)
			end, 0, "DENSITY")
		end
		return
	end
	if rd.stage == "rb" then
		rd.stage = "log"
		for _, key in ipairs(rd.keys) do
			local tw = sh.towns[key]
			if tw.roundabout and tw.rb == nil and tw.steps >= SC.RB_STEP and tw.town ~= nil then
				tw.rb = { pending = true, step = tw.steps }
				-- the one-way ring (default; the runner falls back to the two-way ring when it is refused)
				local ring = sh.opts.ringMode or "oneway"
				local sent = r:roundabout(t, tw.town, { mode = "frontier", ringMode = ring,
					tag = "SHOWCASE RB",
					onResult = function(res)
						res.step = tw.steps
						tw.rb = res
					end })
				if not sent then tw.rb = { failed = true, step = tw.steps, why = r.rbLast and r.rbLast.why or "notSent" } end
				rd.stage = "rb"   -- one roundabout per tick; come back for the others
				return
			end
		end
		return
	end
	-- log: one STEP line per town (edges now vs last round: mod / vanilla), a ROUND line
	for _, key in ipairs(rd.keys) do
		local tw = sh.towns[key]
		local m = r.driver:measure(tw.town)
		local edges = m and m.lots and m.lots.edges or nil
		local d = (edges and tw.lastEdges) and (edges - tw.lastEdges) or nil
		local modNew = #tw.newEdges
		local o = rd.out[key]
		log(r, { { "key", tw.key }, { "town", tw.town }, { "label", tw.label }, { "step", string.format("%d/%d", tw.steps, sh.n) },
			{ "outcome", o or "growth" }, { "built", tw.built }, { "refused", tw.fails }, { "empty", tw.empties },
			{ "cost", fmtMoney(tw.cost) }, { "edges", edges or "?" }, { "mod", modNew },
			{ "vanilla", d and (d - modNew) or "?" }, { "buildings", m and m.buildings or "?" },
			{ "why", o ~= nil and o ~= "built" and tw.lastWhy or "-" }, { "shape", tw.shapeId or tw.shape or "-" },
			{ "shapeWhy", tw.shapeWhy or "-" }, { "lever", tw.lever or "-" } }, "STEP")
		tw.lastEdges = edges or tw.lastEdges
		-- (§65: the town's edges that were not ours at its first step; round 1's vanilla growth counts as core)
		if tw.edges0 == nil and edges then tw.edges0 = math.max(0, edges - modNew) end
		local up = tw.upgrade
		-- v4: nothing within the round of the lever (306->306 buildings), the town doubled the round after
		-- (306->670, edges 127->250): logged at the lever's round (when=same) and once more a round later (when=next)
		if up and (up.pending or (up.next == nil and tw.steps > up.step)) then
			local when = up.pending and "same" or "next"
			if up.pending then up.pending = false else up.next = true end
			local caps = r.E.townCaps(tw.town)
			local b1, c1 = m and m.buildings or 0, caps and caps.actual or 0
			if when == "same" then up.after = { buildings = b1, capacity = c1, step = tw.steps } end
			log(r, { { "key", tw.key }, { "town", tw.town }, { "step", tw.steps }, { "upgradeStep", up.step },
				{ "when", when }, { "buildings", string.format("%d->%d", up.buildings, b1) },
				{ "capacity", string.format("%.0f->%.0f", up.capacity, c1) },
				{ "edges", string.format("%d->%s", up.edges or 0, tostring(edges or "?")) }, { "ok", up.ok == true } },
				"DENSITY effect")
		end
		SC.probeLines(r, sh, tw, m, d and (d - modNew) or nil, "step")
		if tw.rb and tw.rb.edges then
			local a = r:adoption(tw.town, tw.rb.ring)
			local b = r:adoption(tw.town, tw.rb.arms)
			log(r, { { "key", tw.key }, { "town", tw.town }, { "step", tw.steps }, { "since", tw.steps - (tw.rb.step or 0) },
				{ "ring", string.format("%d/%d_edges_with_parcels_%d_lots_%d_built", a.withParcels, a.alive, a.parcels, a.built) },
				{ "arms", string.format("%d/%d_edges_with_parcels_%d_lots_%d_built", b.withParcels, b.alive, b.parcels, b.built) } },
				"RB ADOPT")
		end
	end
	local s = (now - rd.us) / 1e6
	sh.roundS[#sh.roundS + 1] = s
	local b, g = rd.buildS or 0, rd.growS or 0
	-- build = the concurrent town jobs (plan + build + fill), grow = the two growth batches, other = fill mod
	-- streets / density / roundabout / logs; inflight = jobs allowed at once, peak = most that ran at once
	log(r, { { "round", sh.rounds }, { "towns", #rd.keys }, { "s", string.format("%.1f", s) },
		{ "build", string.format("%.1f", b) }, { "grow", string.format("%.1f", g) },
		{ "other", string.format("%.1f", math.max(0, s - b - g)) }, { "builds", rd.nBuild or 0 },
		{ "inflight", rd.cap or 0 }, { "peak", rd.peak or 0 } }, "ROUND")
	sh.rd = nil
end

---------------------------------------------------------------------------
-- settle (v4): let game time pass (years, or until the buildings stop growing; real-time cap), then compare

local function sizes(r, sh)
	local out = {}
	for _, key in ipairs(sh.order) do
		local tw = sh.towns[key]
		if tw.town ~= nil then
			local m = r.driver:measure(tw.town)
			local caps = r.E.townCaps(tw.town)
			out[key] = { buildings = m and m.buildings or 0, edges = m and m.lots and m.lots.edges or 0,
				capacity = caps and caps.actual or 0 }
		end
	end
	return out
end

--- Buildings of every created showcase town: total, per town ({ key = n }) and the number of towns.
function SC.buildingCounts(r, sh)
	local total, per, n = 0, {}, 0
	for _, key in ipairs(sh.order) do
		local tw = sh.towns[key]
		if tw.town ~= nil then
			local m = r.driver:measure(tw.town)
			local b = m and m.buildings or 0
			per[key] = b
			total = total + b
			n = n + 1
		end
	end
	return total, per, n
end

--- The settle mode for an otd_shared.SETTLE id: "off" | "passes" (with the pass count) | "years" (with target
--- months) | "plateau".
function SC.settleMode(S, id)
	if id == nil or id == "off" or id == 0 then return "off", nil end
	for _, e in ipairs(S and S.SETTLE or {}) do
		if e.id == id then
			if e.id == "off" then return "off", nil end
			if e.passes then return "passes", e.passes end
			if e.months then return "years", e.months end
			return "plateau", nil
		end
	end
	if type(id) == "number" and id > 0 then return "years", id end   -- a plain number of months (older option)
	return "off", nil
end

--- Plateau test over a list of sample totals: true when the last PLATEAU_SAMPLES samples added less than
--- PLATEAU_FRAC of the total and less than PLATEAU_PER_TOWN per town. Also returns the growth over that window.
function SC.plateau(totals, towns)
	local k = SC.PLATEAU_SAMPLES
	if #totals < k + 1 then return false, nil end
	local a, b = totals[#totals - k], totals[#totals]
	local d = b - a
	local ok = d < SC.PLATEAU_FRAC * math.max(a, 1) and d < SC.PLATEAU_PER_TOWN * math.max(towns or 1, 1)
	return ok, d
end

--- Game months passed since the settle started (calendar, or real time / MONTH_REAL_S without one).
local function passedMonths(st, m, now)
	if st.m0 ~= nil and m ~= nil then return m - st.m0 end
	return (now - st.startUs) / 1e6 / SC.MONTH_REAL_S
end

local function fmtCal(m)
	return m and string.format("%.2f", m) or "-"
end

--- One sample: buildings total and per town, SETTLE sample line; plateau check data.
local function sample(r, sh, st, m, now)
	local total, per, n = SC.buildingCounts(r, sh)
	local prev = st.totals[#st.totals]
	st.totals[#st.totals + 1] = total
	st.samples = st.samples + 1
	st.lastSampleUs, st.lastSampleM = now, m
	local grew, top, topD = 0, nil, 0
	for key, b in pairs(per) do
		local p = st.per[key]
		if p ~= nil and b > p then
			grew = grew + 1
			if b - p > topD or (b - p == topD and top ~= nil and key < top) then top, topD = key, b - p end
		end
	end
	st.per = per
	st.towns = n
	log(r, { { "n", st.samples }, { "calendar", fmtCal(m) },
		{ "passed", string.format("%.2f", passedMonths(st, m, now)) },
		{ "buildings", string.format("%d(%+d)", total, prev and (total - prev) or 0) }, { "towns", n }, { "grew", grew },
		{ "top", top and string.format("%s(+%d)", top, topD) or "-" }, { "passes", st.passes },
		{ "s", string.format("%.1f", (now - st.startUs) / 1e6) } }, "SETTLE sample")
end

--- Forced growth pass during the settle: one growth batch over every created town (target 1 + (steps + extra) x
--- STEP_ADD; extra = 0 in the game-time modes, the pass number in "passes": v5's passes at the reached target
--- grew no town but the fill twin).
local function forcePass(r, t, sh, st, m, now, extra, sleepS)
	local list = {}
	for _, key in ipairs(sh.order) do
		local tw = sh.towns[key]
		if tw.town ~= nil and tw.why ~= "townGone" then
			list[#list + 1] = { town = tw.town, target = 1 + (tw.steps + (extra or 0)) * SC.STEP_ADD, key = key }
		end
	end
	st.passes = st.passes + 1
	st.lastPassM, st.lastPassUs = m, now
	log(r, { { "n", st.passes }, { "towns", #list }, { "calendar", fmtCal(m) },
		{ "passed", string.format("%.2f", passedMonths(st, m, now)) }, { "extra", extra or 0 } }, "SETTLE pass")
	if #list == 0 then return end
	local gone = r:growBatch(t, list, sleepS or 0)
	for _, key in ipairs(gone or {}) do
		local tw = sh.towns[key]
		tw.stopped, tw.why = true, "townGone"
	end
end

--- v9 settle checks: one normal main-mod check (startJob force = false) per active style town, as the round's job
--- options otherwise (style, shape, form, metropolis ...). Returns build items for r:buildBatch.
function SC.settleItems(sh)
	local out = {}
	for _, key in ipairs(sh.order) do
		local tw = sh.towns[key]
		if tw.kind == "style" and tw.town ~= nil and tw.why ~= "townGone" then
			local o = SC.jobOpts(tw)
			o.force = false
			out[#out + 1] = { town = tw.town, key = key, opts = o }
		end
	end
	return out
end

--- One settle step: start (sizes, first sample, speed up), wait (samples, forced passes) until the mode ends it
--- (target months, plateau) or the real-time cap, restore the speed, log sizes before / after and the mod
--- streets' adoption, signal the auto tour. Returns "report" when done or off.
function SC.settle(r, t, sh, now)
	local X = r.X
	local st = sh.settle
	if st == nil then
		local o = r.showOpts or {}
		local mode, target = SC.settleMode(r.S, o.settle)
		if mode == "off" then return "report" end
		local capMin = tonumber(o.settleCap) or (r.S and r.S.SETTLE_CAP_DEFAULT) or 10
		local m0 = X.calendarMonths and X.calendarMonths() or nil
		st = { mode = mode, target = target, capMin = capMin, force = o.settleForce == true, m0 = m0,
			clock = m0 and "calendar" or "real", startUs = now, capUs = now + capMin * 60e6,
			speed0 = X.gameSpeed and X.gameSpeed() or nil, before = sizes(r, sh), stage = "speed",
			totals = {}, per = {}, samples = 0, passes = 0, towns = 0 }
		sh.settle = st
		if mode == "passes" then st.stage = "passes" end
		log(r, { { "mode", mode }, { "target", mode == "passes" and string.format("%dpasses", target)
			or (target and string.format("%dmonths", target) or "plateau") },
			{ "capMin", capMin }, { "forcePasses", st.force }, { "clock", st.clock }, { "calendar", fmtCal(m0) },
			{ "speedBefore", st.speed0 or "?" }, { "speed", SC.SETTLE_SPEED }, { "towns", #sh.order } }, "SETTLE start")
		st.lastPassM, st.lastPassUs = m0, now
		sample(r, sh, st, m0, now)   -- sample 1: the baseline
		return
	end
	if st.stage == "passes" then
		-- v6 default: forced passes back to back (each one STEP_ADD further), PASS_WAIT_S after each, at the
		-- current game speed; no waiting for game time
		-- (the task comes back once the batch's callbacks came and PASS_WAIT_S passed: sample, next pass)
		-- v9: after each pass the main mod's normal check runs on every style town (force = false: it builds only when
		-- its needs-room trigger fires), as in normal play. Showcase v8: the settle's three passes grew the towns by
		-- ~20 % with the game's own streets and no mod increment at all, and that rounded every shaped town (Shape:
		-- linear houses elong 1.62 at its last build -> 1.12 after the settle). showOpts.settleMod = false: v8's settle.
		local m = X.calendarMonths and X.calendarMonths() or nil
		local o = r.showOpts or {}
		if st.passes > 0 and (st.checked or 0) < st.passes and o.settleMod ~= false and SC.SETTLE_MOD then
			st.checked = st.passes
			local items = SC.settleItems(sh)
			if #items > 0 then
				r:buildBatch(t, items, function(it)
					local tw = sh.towns[it.key]
					st.modChecks = (st.modChecks or 0) + 1
					if it.outcome == "built" and tw then
						st.modBuilds = (st.modBuilds or 0) + 1
						tw.settleBuilds = (tw.settleBuilds or 0) + 1
						local rec = it.job and it.job.rec
						for _, id in ipairs(rec and rec.edges or {}) do tw.modEdges[#tw.modEdges + 1] = id end
					end
				end)
				return
			end
		end
		if st.passes > 0 then sample(r, sh, st, m, now) end
		if st.passes < st.target and now < st.capUs then
			forcePass(r, t, sh, st, m, now, st.passes + 1, SC.PASS_WAIT_S)
			return
		end
		st.stage = "restore"
		st.reason = st.passes >= st.target and "passes" or "cap"
		st.timedOut = st.reason == "cap"
		st.m1 = m
		st.passed = passedMonths(st, m, now)
		st.waitS = (now - st.startUs) / 1e6
		return
	end
	if st.stage == "speed" then
		st.stage = "wait"
		if X.setGameSpeed then
			t.cmdDone, t.waitCmd, t.cmdUs, t.sleepAfter = nil, true, now, 0
			X.setGameSpeed(SC.SETTLE_SPEED, function(ok) t.cmdDone = ok == true end)
		end
		return
	end
	if st.stage == "wait" then
		local m = X.calendarMonths and X.calendarMonths() or nil
		if st.m0 == nil then m = nil end   -- started without a calendar: stay on real time
		local passed = passedMonths(st, m, now)
		local reason = nil
		-- sample due?
		local due
		if m ~= nil then due = m - (st.lastSampleM or st.m0) >= SC.SAMPLE_MONTHS
		else due = now - st.lastSampleUs >= SC.SAMPLE_REAL_S * 1e6 end
		if due then
			sample(r, sh, st, m, now)
			if st.mode == "plateau" and passed >= SC.PLATEAU_MIN_MONTHS then
				local flat, d = SC.plateau(st.totals, st.towns)
				if flat then reason, st.plateauD = "plateau", d end
			end
		end
		if st.mode == "years" and passed >= st.target then reason = "target" end
		if reason == nil and now >= st.capUs then reason = "cap" end
		if reason == nil then
			-- forced growth pass every FORCE_MONTHS (one batch at a time: the task waits for its callbacks)
			if st.force then
				local since
				if m ~= nil then since = m - (st.lastPassM or st.m0)
				else since = (now - st.lastPassUs) / 1e6 / SC.MONTH_REAL_S end
				if since >= SC.FORCE_MONTHS then forcePass(r, t, sh, st, m, now) end
			end
			return
		end
		st.stage = "restore"
		st.reason = reason
		st.timedOut = reason == "cap"
		st.m1 = m
		st.passed = passed
		st.waitS = (now - st.startUs) / 1e6
		if X.setGameSpeed and st.speed0 ~= nil then
			t.cmdDone, t.waitCmd, t.cmdUs, t.sleepAfter = nil, true, now, 0
			X.setGameSpeed(st.speed0, function(ok) t.cmdDone = ok == true end)
		end
		return
	end
	-- after: sizes and adoption, one line per town
	local after = sizes(r, sh)
	local tb, ta = 0, 0
	for _, key in ipairs(sh.order) do
		local tw = sh.towns[key]
		local b, a = st.before[key], after[key]
		if a then
			tb, ta = tb + (b and b.buildings or 0), ta + a.buildings
			local ad = (tw.modEdges and #tw.modEdges > 0) and r:adoption(tw.town, tw.modEdges) or nil
			log(r, { { "key", key }, { "town", tw.town }, { "label", tw.label }, { "kind", tw.kind },
				{ "buildings", string.format("%d->%d", b and b.buildings or 0, a.buildings) },
				{ "capacity", string.format("%.0f->%.0f", b and b.capacity or 0, a.capacity) },
				{ "edges", string.format("%d->%d", b and b.edges or 0, a.edges) },
				{ "modEdges", tw.modEdges and #tw.modEdges or 0 },
				{ "adoption", ad and string.format("%d/%d_edges_with_parcels_%d_lots_%d_built", ad.withParcels, ad.alive, ad.parcels,
					ad.built) or "-" }, { "shape", tw.shapeId or tw.shape or "-" }, { "lever", tw.lever or "-" } }, "SETTLE town")
		end
	end
	local tour = r.showOpts and r.showOpts.tourAfter == true
	if tour then sh.autoTour = (sh.autoTour or 0) + 1 end
	log(r, { { "mode", st.mode }, { "target", st.mode == "passes" and string.format("%dpasses", st.target)
		or (st.target and string.format("%dmonths", st.target) or "plateau") }, { "reason", st.reason or "-" }, { "clock", st.clock }, { "calendar", fmtCal(st.m1) },
		{ "passed", string.format("%.2f", st.passed or 0) }, { "s", string.format("%.1f", st.waitS or 0) },
		{ "samples", st.samples }, { "passes", st.passes }, { "buildings", string.format("%d->%d", tb, ta) },
		{ "capMin", st.capMin }, { "timedOut", st.timedOut == true }, { "speedRestored", st.speed0 or "-" },
		{ "modChecks", st.modChecks or 0 }, { "modBuilds", st.modBuilds or 0 },
		{ "tour", tour } }, "SETTLE end")
	sh.settle = nil
	sh.settled = (sh.settled or 0) + 1
	return "report"
end

---------------------------------------------------------------------------
-- report / focus / results

--- One town's numbers now: { buildings, edges, r, metrics, cap, adoption } (driver.measure + ot_metrics over its
--- streets; adoption of the mod's edges: alive, withParcels, parcels, built).
function SC.measure(r, tw)
	if tw.town == nil then return nil end
	local m = r.driver:measure(tw.town)
	if m == nil then return { buildings = 0, edges = 0, r = 0 } end
	local cx, cy = r.E.boxCentre(tw.town)
	if cx == nil then cx, cy = m.ext.cx, m.ext.cy end
	-- v5: the whole town network (driver.measure follows the town's streets beyond the building extent, so the
	-- shape's arms count; v4 cut the streets at 1.25 x the building extent and every shape town read round).
	-- Town streets only (country roads between towns would stretch it); an older driver without m.net: the old cut
	local townR = m.net ~= nil and math.huge or (m.ext.r * 1.25 + 50)
	local segs = {}
	-- v9: unhoused street length (town streets without a building on their parcels: user "too many empty streets")
	local emptyLen, emptyN = 0, 0
	for _, ed in ipairs(m.edges) do
		local mx, my = (ed.p0[1] + ed.p1[1]) / 2, (ed.p0[2] + ed.p1[2]) / 2
		local town = type(ed.template) ~= "string" or ed.template:find("town_", 1, true) ~= nil
		if town and (mx - m.ext.cx) ^ 2 + (my - m.ext.cy) ^ 2 <= townR * townR then
			segs[#segs + 1] = { ed.p0[1], ed.p0[2], ed.p1[1], ed.p1[2] }
			if m.builtBy and ed.id ~= nil and (m.builtBy[ed.id] or 0) <= 0 then
				emptyLen = emptyLen + math.sqrt((ed.p1[1] - ed.p0[1]) ^ 2 + (ed.p1[2] - ed.p0[2]) ^ 2)
				emptyN = emptyN + 1
			end
		end
	end
	local out = { buildings = m.buildings, edges = #segs, r = m.ext.r, metrics = r.MT.segments(segs, cx, cy),
		cap = m.caps and m.caps.actual or 0, net = m.net, emptyLen = m.builtBy and emptyLen or nil, emptyN = emptyN }
	-- v9: the mod's own streets on the town's grid axes (ot_metrics.axisShare vs the style axis the town's jobs used)
	if tw.axis ~= nil and r.MT.axisShare and tw.modEdges and #tw.modEdges > 0 and r.X.edgeGeom then
		local ms = {}
		for _, id in ipairs(tw.modEdges) do
			local e = r.X.edgeGeom(id)
			if e then ms[#ms + 1] = { e.p0[1], e.p0[2], e.p1[1], e.p1[2] } end
		end
		if #ms > 0 then out.modGrid = (r.MT.axisShare(ms, tw.axis)) end
	end
	if r.MT.points and m.pts and #m.pts > 0 then out.houses = r.MT.points(m.pts, cx, cy) end
	if tw.modEdges and #tw.modEdges > 0 then out.adoption = r:adoption(tw.town, tw.modEdges) end
	-- v8: street orientation (grid share / spokes / rings, ot_metrics.orientationSegs) and density (buildings per ha
	-- within the 90 % building radius): do the metropolis variants and town forms keep their character?
	if r.MT.orientationSegs then
		local okO, o = pcall(r.MT.orientationSegs, segs, cx, cy)
		if okO then out.orient, out.orientText = o, r.MT.orientText(o) end
	end
	if (m.ext and m.ext.r or 0) > 0 then out.dens = m.buildings / (math.pi * m.ext.r * m.ext.r / 10000) end
	-- v7: green gaps (enclosed open land without buildings, ot_metrics.greenGapsSegs; user: the Density: control twin)
	if r.MT.greenGapsSegs then
		local okG, gg = pcall(r.MT.greenGapsSegs, segs, m.pts)
		if okG then out.green, out.greenText = gg, r.MT.greenText(gg) end
	end
	return out
end

local function shapeText(m)
	return string.format("drift=%.2f_spread=%.2f_cv=%.2f_elong=%.2f_arms=%.1f_side=%.2f_waist=%.2f", m.drift, m.spread,
		m.cv, m.elong, m.arms or 0, m.side or 0.5, m.waist or 1)
end

--- Building positions' metrics for TOWN / FOCUS lines: "elong_arms_side_waist" (ot_metrics.points).
local function housesText(h)
	if h == nil then return "-" end
	return string.format("%.2f_%.1f_%.2f_%.2f", h.elong, h.arms or 0, h.side or 0.5, h.waist or 1)
end

local function adoptText(a)
	if a == nil then return "-" end
	return string.format("%d/%d_edges_with_parcels_%d_lots_%d_built", a.withParcels, a.alive, a.parcels, a.built)
end

local function townFields(tw, mm, mapYear)
	local f = { { "key", tw.key }, { "town", tw.town or "-" }, { "label", tw.label }, { "kind", tw.kind },
		{ "style", tw.style or "-" }, { "era", SC.eraText(tw, mapYear or 0) }, { "angle", tw.angle or "default" },
		{ "x", tw.x }, { "y", tw.y }, { "steps", tw.steps }, { "built", tw.built }, { "refused", tw.fails },
		{ "empty", tw.empties }, { "cost", fmtMoney(tw.cost) }, { "stopped", tw.why or "-" },
		{ "shape", tw.shapeId or tw.shape or "-" }, { "shapeAsked", tw.shape or "-" }, { "shapeWhy", tw.shapeWhy or "-" },
		{ "lever", tw.lever or "-" }, { "probe", tw.probe or "-" } }
	if mm then
		f[#f + 1] = { "buildings", mm.buildings }
		f[#f + 1] = { "edges", mm.edges }
		f[#f + 1] = { "modEdges", tw.modEdges and #tw.modEdges or 0 }
		f[#f + 1] = { "adoption", adoptText(mm.adoption) }
		f[#f + 1] = { "r", mm.r }
		f[#f + 1] = { "capacity", mm.cap or 0 }
		if mm.metrics then f[#f + 1] = { "metrics", shapeText(mm.metrics) } end
		f[#f + 1] = { "houses", housesText(mm.houses) }
		f[#f + 1] = { "net", mm.net or "-" }
		f[#f + 1] = { "green", mm.greenText or "-" }
		f[#f + 1] = { "orient", mm.orientText or "-" }
		f[#f + 1] = { "own", (mm.edges or 0) > 0 and string.format("%.2f", (tw.modEdges and #tw.modEdges or 0) / mm.edges) or "-" }
		f[#f + 1] = { "dens", mm.dens and string.format("%.1f", mm.dens) or "-" }
		f[#f + 1] = { "emptyLen", mm.emptyLen and string.format("%.0f/%d", mm.emptyLen, mm.emptyN or 0) or "-" }
		f[#f + 1] = { "modGrid", mm.modGrid and string.format("%.2f", mm.modGrid) or "-" }
		f[#f + 1] = { "crescents", tw.crescents or "-" }
	end
	f[#f + 1] = { "form", tw.formId or tw.form or "-" }
	f[#f + 1] = { "metro", tw.metroVariant or tw.metro or "-" }
	if tw.rb then f[#f + 1] = { "roundabout", tw.rb.edges and ("built_step_" .. tostring(tw.rb.step) .. "_ring_"
		.. tostring(tw.rb.ringMode or "?")) or ("no:" .. tostring(tw.rb.why or "pending")) } end
	return f
end

--- Results lines for the window (one per town, controls last) from the TOWN measurements.
function SC.resultLines(sh, rows)
	local lines = { "Town | steps | built/refused/empty | edges (mod, adopted) | buildings (on mod) | drift spread elong" }
	local function line(tw, mm)
		local a = mm and mm.adoption
		return string.format("%s | %d | %d/%d/%d | %s (%d, %s) | %s (%s) | %s%s", tw.label, tw.steps, tw.built, tw.fails,
			tw.empties, mm and tostring(mm.edges) or "?", tw.modEdges and #tw.modEdges or 0,
			a and string.format("%d with lots", a.withParcels) or "-", mm and tostring(mm.buildings) or "?",
			a and tostring(a.built) or "-",
			(mm and mm.metrics) and string.format("%.2f %.2f %.2f", mm.metrics.drift, mm.metrics.spread, mm.metrics.elong) or "-",
			(tw.why and (" | stopped: " .. tw.why) or "") .. (tw.shapeId and (" | shape " .. tw.shapeId) or "")
			.. (tw.lever and (" | lever " .. tw.lever) or ""))
	end
	local later = {}
	for _, row in ipairs(rows) do
		if row.tw.kind == "vanilla" then later[#later + 1] = row else lines[#lines + 1] = line(row.tw, row.mm) end
	end
	lines[#lines + 1] = "Vanilla towns (same growth schedule, no mod streets):"
	for _, row in ipairs(later) do lines[#lines + 1] = line(row.tw, row.mm) end
	return lines
end

function SC.report(r, sh, now)
	local tot = { steps = 0, built = 0, fails = 0, empties = 0, stopped = 0, cost = 0, towns = 0, mod = 0, adopted = 0,
		houses = 0 }
	local rows = {}
	local mapYear = r.E.year()
	for _, key in ipairs(sh.order) do
		local tw = sh.towns[key]
		local ok, mm = pcall(SC.measure, r, tw)
		if not ok then mm = nil end
		log(r, townFields(tw, mm, mapYear), "TOWN")
		if tw.town then
			local okM, m = pcall(function() return r.driver:measure(tw.town) end)
			pcall(SC.probeLines, r, sh, tw, okM and m or nil, nil, "report")
		end
		rows[#rows + 1] = { tw = tw, mm = mm }
		if tw.town then tot.towns = tot.towns + 1 end
		tot.steps, tot.built, tot.fails, tot.empties = tot.steps + tw.steps, tot.built + tw.built, tot.fails + tw.fails,
			tot.empties + tw.empties
		tot.cost = tot.cost + tw.cost
		if tw.stopped then tot.stopped = tot.stopped + 1 end
		if mm and mm.adoption then
			tot.mod, tot.adopted, tot.houses = tot.mod + mm.adoption.alive, tot.adopted + mm.adoption.withParcels,
				tot.houses + mm.adoption.built
		end
	end
	sh.results = SC.resultLines(sh, rows)
	local avg = 0
	for _, s in ipairs(sh.roundS) do avg = avg + s end
	avg = #sh.roundS > 0 and avg / #sh.roundS or 0
	log(r, { { "towns", tot.towns }, { "n", sh.n }, { "rounds", sh.rounds }, { "turns", sh.turns }, { "steps", tot.steps },
		{ "built", tot.built }, { "refused", tot.fails }, { "empty", tot.empties }, { "stopped", tot.stopped },
		{ "cost", fmtMoney(tot.cost) }, { "modEdges", tot.mod }, { "adopted", tot.adopted }, { "modHouses", tot.houses },
		{ "prunes", sh.counts.prune }, { "tiny", sh.counts.tiny }, { "roundS", string.format("%.1f", avg) },
		{ "notPossibleNoCollision", r.driver.counts.notPossible or 0 },
		{ "laneAssert", "grep_lane_config_util_in_stdout" },
		{ "minutes", sh.startUs and string.format("%.1f", ((now or 0) - sh.startUs) / 6e7) or "-" } }, "SUMMARY")
end

--- Inspector lines for one showcase town (Next / Previous town in the window).
function SC.focus(r, sh, key)
	local tw = sh.towns[key]
	if tw == nil then return nil end
	local ok, mm = pcall(SC.measure, r, tw)
	if not ok then mm = nil end
	log(r, townFields(tw, mm, r.E.year()), "FOCUS")
	local lines = {
		string.format("%s (%s%s), town %s", tw.label, tw.kind == "style" and tw.style or "vanilla",
			tw.angle and string.format(", angle %s", tostring(tw.angle)) or "", tostring(tw.town or "not created")),
		string.format("Steps %d/%d: built %d, refused %d, empty %d, cost %s%s", tw.steps, sh.n, tw.built, tw.fails,
			tw.empties, fmtMoney(tw.cost), tw.why and (", STOPPED: " .. tw.why) or ""),
	}
	if mm then
		lines[#lines + 1] = string.format("Buildings %d, street edges %d, extent r %.0f m, capacity %.0f", mm.buildings,
			mm.edges, mm.r or 0, mm.cap or 0)
		if mm.adoption then
			lines[#lines + 1] = string.format("Mod streets: %d edges, %d with lots (%d lots), %d houses on them",
				mm.adoption.alive, mm.adoption.withParcels, mm.adoption.parcels, mm.adoption.built)
		end
		if mm.metrics then lines[#lines + 1] = "Shape: " .. r.MT.text(mm.metrics) end
		if mm.houses then lines[#lines + 1] = "Houses: " .. r.MT.text(mm.houses) end
	end
	if tw.rb then lines[#lines + 1] = "Roundabout: " .. (tw.rb.edges and ("built at step " .. tostring(tw.rb.step))
		or ("not built: " .. tostring(tw.rb.why or "pending"))) end
	if tw.shapeId or tw.shape then
		lines[#lines + 1] = string.format("Shape archetype: %s%s%s", tostring(tw.shapeId or tw.shape),
			tw.shape and (" (asked " .. tw.shape .. ")") or "", tw.shapeWhy and (", " .. tostring(tw.shapeWhy)) or "")
	end
	if tw.lever then lines[#lines + 1] = "Density lever: " .. tw.lever end
	if tw.probe then lines[#lines + 1] = string.format("Probe: %s (twin of %s)", tw.probe, tostring(tw.twinOf)) end
	if tw.lastWhy then lines[#lines + 1] = "Last refusal / empty plan: " .. tostring(tw.lastWhy) end
	sh.focus = { key = key, lines = lines }
	return lines
end

--- Status for the window: phase, progress, one line per town, the town list for the camera buttons, results.
function SC.status(r, sh)
	if sh == nil then return nil end
	local out = { phase = sh.phase, n = sh.n, lines = {}, towns = {}, focus = sh.focus and sh.focus.lines or {},
		focusKey = sh.focus and sh.focus.key or nil, results = sh.results, autoTour = sh.autoTour or 0 }
	local created, built, act = 0, 0, 0
	for _, key in ipairs(sh.order) do
		local tw = sh.towns[key]
		if tw.town then created = created + 1 end
		built = built + tw.built
		if tw.town and not tw.stopped and tw.steps < sh.n then act = act + 1 end
		local x, y = tw.x, tw.y
		if tw.town then
			local cx, cy = r.E.boxCentre(tw.town)
			if cx then x, y = cx, cy end
		end
		-- per-town info for the HUD camera (shape-row towns: wider and top-down, otd_shared.view)
		out.towns[#out.towns + 1] = { key = key, label = tw.label, x = x, y = y, town = tw.town, kind = tw.kind,
			shape = tw.shape, lever = tw.lever, row = tw.itemRow, probe = tw.probe, form = tw.form, metro = tw.metro }
		out.lines[#out.lines + 1] = string.format("%s: %s step %d/%d, built %d, refused %d, empty %d%s", tw.label,
			tw.town and "" or "(not created)", tw.steps, sh.n, tw.built, tw.fails, tw.empties,
			tw.why and (" - stopped: " .. tw.why) or "")
	end
	local last = sh.roundS[#sh.roundS]
	out.head = string.format("Showcase %s: %d/%d towns, %d increments built, %d towns still growing, round %d%s", sh.phase,
		created, #sh.order, built, act, sh.rounds, last and string.format(" (last %.0f s)", last) or "")
	return out
end

return SC
