-- Stress Test pure logic: mod.json params -> baseConfig, the throttled job queue, and the money /
-- date / grid helpers. No engine calls (the caller passes the clock and the BaseConfig), so it is
-- unit-tested offline (tests/square_stress_test/). Types: stress_types.d.tl.

local logic : SquareStressLogic = {}

-- mod.json param keys (mod.json "params"; values arrive as 1-based option indices, docs/findings.md
-- "Script function signatures").
logic.PARAM_KEYS = { "no_costs", "sandbox", "vehicles_no_expire", "no_emissions", "sim_recompute", "town_develop",
	"show_probe_tab" }

-- "sim_recompute" options: x1 (unchanged) / x2 / x5 of simPersonDestinationRecomputationProbability
-- (base default 1.0, base/mod.script.tl:108; api/type.d.tl:3696).
logic.RECOMPUTE_FACTORS = { 1.0, 2.0, 5.0 }
-- "town_develop" options: unchanged (base 60, base/mod.script.tl:104) / 15 / 5.
logic.DEVELOP_INTERVALS = { 0, 15, 5 }

logic.SPEEDS = { 1, 2, 4, 8, 16 }
logic.LOG_LINE_MAX = 160   -- window log line length (stdout.txt keeps the full text)
logic.MIN_YEAR = 1850
logic.MAX_YEAR = 2150
-- Largest single journal booking: stays inside a signed 32-bit integer in case the engine stores the
-- amount that way (RESEARCH.md section 9, "Integer overflow limit of amount [?]").
logic.MAX_BOOKING = 1000000000

--- 1-based option index from a raw param value; anything unusable gives 1 (the default option).
function logic.optionIndex(raw : any, count : integer) : integer
	if raw == true then return 2 end
	local n = tonumber(raw)
	if n == nil then return 1 end
	local i = math.floor(n)
	if i ~= n or i < 1 or i > count then return 1 end
	return i
end

function logic.configFromParams(params : {string : any}) : SquareStressConfig
	local p : {string : any} = params or {}
	local function on(key : string) : boolean
		return logic.optionIndex(p[key], 2) == 2
	end
	local dev = logic.DEVELOP_INTERVALS[logic.optionIndex(p["town_develop"], #logic.DEVELOP_INTERVALS)]
	return {
		noCosts = on("no_costs"),
		sandboxMode = on("sandbox"),
		vehiclesNoExpire = on("vehicles_no_expire"),
		noEmissions = on("no_emissions"),
		recomputeFactor = logic.RECOMPUTE_FACTORS[logic.optionIndex(p["sim_recompute"], #logic.RECOMPUTE_FACTORS)],
		townDevelopInterval = dev > 0 and dev or nil,
	}
end

--- Writes the non-default settings into the BaseConfig (preRunFn) and returns one text per change.
--- Default settings write nothing at all, so another mod's (or the base game's) values stay.
function logic.applyToBaseConfig(cfg : SquareStressConfig, bc : BaseConfig) : {string}
	local changes : {string} = {}
	if cfg == nil or bc == nil then return changes end
	if cfg.noCosts then
		bc.noCosts = true
		changes[#changes + 1] = "noCosts=true"
	end
	if cfg.sandboxMode then
		bc.sandboxMode = true
		changes[#changes + 1] = "sandboxMode=true"
	end
	if cfg.noEmissions then
		-- The base emissions script returns at once when this factor is 0 (base
		-- game_mechanics/emission/emissions.script.tl:27-29), so it stops re-sending the emitter values of
		-- industries, stations, depots and warehouses (:115-131, :197-251). New industries start at 0
		-- (base industries/industryutil.lua:478-481); existing emitters keep their last value.
		-- Typedef: api/tealdef/api/type.d.tl:3482.
		if bc.advancedOptions ~= nil then
			bc.advancedOptions.missionEmissionsScriptFactor = 0
			changes[#changes + 1] = "missionEmissionsScriptFactor=0"
		end
		-- Noise no longer counts in the town ratings (api/tealdef/api/type.d.tl:3659-3661; read at base
		-- game_mechanics/towns/town_util.tl:1723-1735, gui/entity_window/town_building/town_building.tl:363).
		if bc.emission ~= nil then
			bc.emission.townNoiseResidentialAffected = false
			bc.emission.townNoiseCommercialAffected = false
			bc.emission.townNoiseIndustrialAffected = false
			changes[#changes + 1] = "townNoise*Affected=false"
		end
	end
	if cfg.recomputeFactor ~= nil and cfg.recomputeFactor ~= 1.0 then
		local old = tonumber(bc.simPersonDestinationRecomputationProbability) or 1.0
		bc.simPersonDestinationRecomputationProbability = old * cfg.recomputeFactor
		changes[#changes + 1] = string.format("simPersonDestinationRecomputationProbability=%g", old * cfg.recomputeFactor)
	end
	if cfg.townDevelopInterval ~= nil then
		bc.townDevelopInterval = cfg.townDevelopInterval
		changes[#changes + 1] = string.format("townDevelopInterval=%g", cfg.townDevelopInterval)
	end
	return changes
end

--- loadModel modifier body for "No noise and pollution" (mod.script.tl runFn). Vehicle emissions live in
--- metadata.emissions.{noise,pollution}.{score,idle,speed,power} (wiki modding/vehicles/basics.md
--- "Emissions"; e.g. base vehicle/car/fiesta/fiesta.mdl:429-442, vehicle/truck/gaz_3307/gaz_3307_box.mdl:391-398).
--- The base runFn fills idle/speed/power from the score (base base/base_mod.lua:84-85 ->
--- base/model_metadata_util.lua:358-376 addEmissionMetadata, :312-356 the score mapping) and adds
--- "unmaintained". Mod modifiers are registered after the base ones, so this runs on the filled values
--- and zeroes them all. Should it ever run first, score 0 maps to each carrier's minimum (0 for road,
--- rail, tram and water; :210-252) and idle/speed/power <= 0 are refilled from it, so the result is 0
--- apart from aircraft. Trees (negative pollution = they absorb it) and other models stay untouched.
--- Returns true when the model was changed.
function logic.zeroVehicleEmissions(data : table) : boolean
	local md = data ~= nil and data["metadata"] as {string : any} or nil
	if md == nil or (md["transportVehicle"] == nil and md["car"] == nil) then return false end
	local em = md["emissions"] as {string : {string : number}}
	if em == nil then
		em = {}
		md["emissions"] = em
	end
	for _, kind in ipairs({ "noise", "pollution" }) do
		local e = em[kind]
		if e == nil then
			e = {}
			em[kind] = e
		end
		e["score"] = 0
		e["idle"] = 0
		e["speed"] = 0
		e["power"] = 0
		e["unmaintained"] = 0
	end
	return true
end

-- postRunFn for "No noise and pollution": the default town rating sensitivity, as the base game sets it
-- from the advanced settings (base base/mod.script.tl:676-692, config_util.changeScriptConfig on
-- "::/game_mechanics/towns/town_ratings_sensitivity.res"). The value is a 1-based option index into
-- base/difficulty_util.tl:48-49 ({0, 1/4, ...}); index 1 = sensitivity 0, and a sensitivity <= 0 makes
-- the noise and pollution ratings 1.0, i.e. no penalty (game_mechanics/towns/town_util.tl:412-439).
-- Towns with their own sensitivity (town editor, or the Game tab's town ratings action) keep it.
logic.SENSITIVITY_OFF = { SensitivityNoise = 1, SensitivityPollution = 1 }

--- "Show probe tab (developers)" (mod.json show_probe_tab, {"Off", "On"}) from getModParams(); false
--- for anything unusable.
function logic.showProbeTab(allModParams : {string : any}) : boolean
	if type(allModParams) ~= "table" then return false end
	local mine = allModParams["square_stress_test"]
	if type(mine) ~= "table" then return false end
	return logic.optionIndex((mine as {string : any})["show_probe_tab"], 2) == 2
end

-- Town ratings (Game tab): the base town editor sends one "Towns" game-script event per rating
-- (gui/entity_window/town/town_eow.script.tl:896-903 setTownRatingSensitivity, :964-968
-- resetTownRatingSensitivity), handled by game_mechanics/towns/towns.script.tl:340-368 (subscribed at :49-50). The reset clears
-- every custom rating sensitivity of the town (all six), like the editor's reset button.
logic.RATING_KEYS = { "noise", "pollution" }

function logic.ratingSteps(townList : {integer}, ignore : boolean) : {SquareStressRatingStep}
	local out : {SquareStressRatingStep} = {}
	for _, t in ipairs(townList or {}) do
		if ignore then
			for _, k in ipairs(logic.RATING_KEYS) do
				out[#out + 1] = { town = t, event = "setTownRatingSensitivity",
					param = { townEntity = t, rating = k, sensitivity = 0 } }
			end
		else
			out[#out + 1] = { town = t, event = "resetTownRatingSensitivity", param = { townEntity = t } }
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Job queue

function logic.newQueue(perFrame : integer) : SquareStressQueue
	return { jobs = {}, perFrame = (perFrame ~= nil and perFrame > 0) and perFrame or 1 }
end

function logic.push(q : SquareStressQueue, job : SquareStressJob) : SquareStressJob
	job.total = math.max(0, math.floor(job.total or 1))
	job.done = 0
	job.errors = 0
	job.busyUs = 0
	job.startedUs = nil
	q.jobs[#q.jobs + 1] = job
	return job
end

local function finish(job : SquareStressJob, nowUs : integer) : SquareStressDone
	return {
		name = job.name,
		count = job.done,
		errors = job.errors,
		firstErr = job.firstErr,
		wallMs = (nowUs - (job.startedUs or nowUs)) / 1000,
		busyMs = job.busyUs / 1000,
		quiet = job.quiet,
	}
end

--- Runs up to q.perFrame steps over the runnable jobs, oldest first. A waiting job (notBefore in the
--- future) doesn't block the ones behind it. Serial jobs share one lane: only the first serial job in
--- the queue may run, and not while it waits for resume() (one serial command in flight at a time;
--- town creation raced when several were in flight, docs/findings.md "Stress Test probes").
--- A job with maxPerTick runs at most that many steps per call (one chunk per frame), then lets the
--- jobs behind it run. Returns the jobs that finished in this call.
function logic.tick(q : SquareStressQueue, now : function() : integer) : {SquareStressDone}
	local finished : {SquareStressDone} = {}
	local budget = q.perFrame
	local t = now()
	local ran : {SquareStressJob : integer} = {}   -- steps per job in this call (maxPerTick)
	-- A serial job whose callback never came: give up waiting, count it as an error.
	for _, job in ipairs(q.jobs) do
		if job.waiting and job.waitTimeoutUs ~= nil and t - (job.waitSinceUs or t) >= job.waitTimeoutUs then
			job.waiting = false
			job.errors = job.errors + 1
			if job.firstErr == nil then job.firstErr = string.format("no callback after %.0f s", job.waitTimeoutUs / 1e6) end
		end
	end
	while true do
		local idx : integer = nil
		local serialSeen = false
		for i, job in ipairs(q.jobs) do
			local blocked = false
			if job.serial then
				blocked = serialSeen or job.waiting
				serialSeen = true
			end
			if job.maxPerTick ~= nil and (ran[job] or 0) >= job.maxPerTick and job.done < job.total then
				blocked = true   -- yields the rest of this frame to the jobs behind it
			end
			if not blocked and (job.notBefore == nil or job.notBefore <= t) then
				idx = i
				break
			end
		end
		if idx == nil then break end
		local job = q.jobs[idx]
		if job.startedUs == nil then job.startedUs = t end
		if job.done >= job.total then
			table.remove(q.jobs, idx)
			finished[#finished + 1] = finish(job, t)
		else
			if budget <= 0 then break end
			budget = budget - 1
			ran[job] = (ran[job] or 0) + 1
			job.done = job.done + 1
			if job.serial then
				job.waiting = true
				job.waitSinceUs = t
			end
			local t0 = now()
			local ok, err : boolean, any = pcall(job.step, job.done, job)
			t = now()
			job.busyUs = job.busyUs + (t - t0)
			if not ok then
				job.waiting = false   -- a failed step sent nothing to wait for
				job.errors = job.errors + 1
				if job.firstErr == nil then job.firstErr = tostring(err) end
			end
			if job.done >= job.total and not job.waiting then
				table.remove(q.jobs, idx)
				finished[#finished + 1] = finish(job, t)
			end
		end
	end
	return finished
end

--- Lets a waiting serial job run its next step (call it from the command's callback, or right away
--- when a step sends nothing). Harmless on a job that was cleared from the queue.
function logic.resume(job : SquareStressJob)
	if job ~= nil then job.waiting = false end
end

--- Steps still to run, over all jobs.
function logic.pending(q : SquareStressQueue) : integer
	local n = 0
	for _, job in ipairs(q.jobs) do n = n + (job.total - job.done) end
	return n
end

--- One-line progress for the window: "Idle" or "<job> 3/10 (+2 jobs queued)".
function logic.progress(q : SquareStressQueue) : string
	local head = q.jobs[1]
	if head == nil then return "Idle" end
	local label = head.label or head.name
	local s = string.format("%s %d/%d", label, head.done, head.total)
	if head.done == 0 and head.notBefore ~= nil then s = label .. " (waiting)" end
	local more = #q.jobs - 1
	if more > 0 then s = s .. string.format(" (+%d job%s queued)", more, more == 1 and "" or "s") end
	return s
end

--- Drops every job; returns how many.
function logic.clear(q : SquareStressQueue) : integer
	local n = #q.jobs
	q.jobs = {}
	return n
end

--- The [SQST] log line of a finished job.
function logic.doneLine(d : SquareStressDone) : string
	local s = string.format("[SQST] action=%s count=%d ms=%.1f busyMs=%.2f", d.name, d.count, d.wallMs, d.busyMs)
	if d.errors > 0 then
		s = s .. string.format(" errors=%d firstErr=%s", d.errors, tostring(d.firstErr))
	end
	return s
end

--- A log message as one window line: the text before the first line break (an engine error's
--- "stack traceback:" follows on the next lines), tabs as spaces, cut to max characters with "...".
--- stdout.txt still gets the full message (stress_runtime.log).
function logic.oneLine(msg : string, max? : integer) : string
	max = max or logic.LOG_LINE_MAX
	local s = tostring(msg)
	local nl = s:find("[\r\n]")
	local cut = nl ~= nil
	if nl ~= nil then s = s:sub(1, nl - 1) end
	s = s:gsub("\t", " ")
	if #s > max then
		s = s:sub(1, max - 3)
		cut = true
	end
	if cut then s = s .. "..." end
	return s
end

---------------------------------------------------------------------------
-- Helpers

--- Year from the text field; nil + reason when it isn't a whole year in [MIN_YEAR, MAX_YEAR].
function logic.parseYear(s : string) : integer, string
	if s == nil then return nil, "empty" end
	local trimmed = s:match("^%s*(.-)%s*$")
	if trimmed == "" then return nil, "empty" end
	if not trimmed:match("^%d+$") then return nil, "not a number" end
	local y = math.floor(tonumber(trimmed))
	if y < logic.MIN_YEAR or y > logic.MAX_YEAR then
		return nil, string.format("outside %d-%d", logic.MIN_YEAR, logic.MAX_YEAR)
	end
	return y, nil
end

--- Splits a booking into integer pieces of at most maxChunk (default MAX_BOOKING). Non-positive or
--- unusable amounts give no pieces.
function logic.bookingChunks(amount : number, maxChunk? : integer) : {integer}
	local out : {integer} = {}
	local n = tonumber(amount)
	if n == nil or n ~= n or n < 1 then return out end
	local left = math.floor(n)
	local cap = (maxChunk ~= nil and maxChunk > 0) and maxChunk or logic.MAX_BOOKING
	while left > 0 do
		local c = math.min(left, cap)
		out[#out + 1] = c
		left = left - c
	end
	return out
end

--- How much to book so the balance gets back above the threshold (0 when it already is, or when
--- the balance is unknown, e.g. infinite money).
function logic.topUpAmount(balance : number, threshold : number, margin : number) : integer
	if balance == nil or threshold == nil then return 0 end
	if balance >= threshold then return 0 end
	return math.floor(threshold - balance + (margin or 0))
end

--- Short money text: 950, 12.5k, 10M, 1.5B (sign kept).
function logic.formatMoney(n : number) : string
	if n == nil then return "?" end
	local a = math.abs(n)
	local sign = n < 0 and "-" or ""
	local function fmt(v : number, suffix : string) : string
		local s = string.format("%.1f", v)
		s = s:gsub("%.0$", "")
		return sign .. s .. suffix
	end
	if a >= 1e9 then return fmt(a / 1e9, "B") end
	if a >= 1e6 then return fmt(a / 1e6, "M") end
	if a >= 1e3 then return fmt(a / 1e3, "k") end
	return sign .. string.format("%d", math.floor(a))
end

--- A town's size factors times factor (missing entries count as 1).
function logic.scaledFactors(current : {number}, factor : number) : {number}
	local out : {number} = {}
	for i = 1, 3 do
		local v = current ~= nil and tonumber(current[i]) or nil
		out[i] = (v or 1.0) * factor
	end
	return out
end

--- n points on a square grid centred on (cx, cy), spacing metres apart, row by row.
function logic.gridPoints(cx : number, cy : number, n : integer, spacing : number) : {{number}}
	local out : {{number}} = {}
	if n == nil or n < 1 then return out end
	local side = math.ceil(math.sqrt(n))
	local off = (side - 1) / 2
	for r = 0, side - 1 do
		for c = 0, side - 1 do
			if #out >= n then return out end
			out[#out + 1] = { cx + (c - off) * spacing, cy + (r - off) * spacing }
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Towns tab (PLAN.md Phase 2; in-game numbers: docs/findings.md "Stress Test probes")

logic.GROW_FACTORS = { 2, 5, 10, 25, 100 }
-- Safety cap on a town's size factor: x100 then x100 again would be 10000. The engine doesn't clamp
-- (x100 on Tacoma read back 100); more buildings come from re-sending (build-out passes), not the factor.
logic.MAX_SIZE_FACTOR = 1000
logic.SPAWN_COUNTS = { 1, 5, 10, 25 }
-- caps: initialLandUseCapacities per district. 1600 is the stock tool's maximum and was accepted in
-- game (580 buildings); Huge (3200) is untested and logged so it can be tuned. spacing: metres
-- between new towns and to existing ones (~1.5 km, more for the big ones).
logic.TOWN_SIZES = {
	{ label = "Small", caps = 100, spacing = 1200 },
	{ label = "Medium", caps = 400, spacing = 1500 },
	{ label = "Large", caps = 1600, spacing = 2000 },
	{ label = "Huge", caps = 3200, spacing = 2500 },
}
-- A serial command whose callback hasn't come after this long is given up (town_create_big took 4 s,
-- several at once 10-12 s; x100 growth 4 s).
logic.SERIAL_TIMEOUT_MS = 120000

--- Short text of a number or a list of numbers, for log lines: 12, 0.5, {1,2,3}.
function logic.listText(v : any) : string
	if type(v) == "table" then
		local parts : {string} = {}
		for i, x in ipairs(v as {any}) do
			if i > 8 then parts[#parts + 1] = "..." break end
			parts[#parts + 1] = logic.listText(x)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	if type(v) == "number" then
		local n = v as number
		if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%d", n) end
		return string.format("%.3g", n)
	end
	return tostring(v)
end

--- New size factors: current x factor per district, at most MAX_SIZE_FACTOR (second result: capped).
--- factor nil = reset to {1,1,1}.
function logic.grownFactors(current : {number}, factor : number) : {number}, boolean
	if factor == nil then return { 1.0, 1.0, 1.0 }, false end
	local out = logic.scaledFactors(current, factor)
	local capped = false
	for i = 1, 3 do
		if out[i] > logic.MAX_SIZE_FACTOR then
			out[i] = logic.MAX_SIZE_FACTOR
			capped = true
		end
	end
	return out, capped
end

--- The first count points of a square grid around (cx, cy), nearest first (the centre itself first),
--- spacing metres apart. Ties are ordered by row, then column, so the order is fixed.
function logic.spiralPoints(cx : number, cy : number, count : integer, spacing : number) : {{number}}
	local out : {{number}} = {}
	if count == nil or count < 1 then return out end
	local r = math.ceil(math.sqrt(count) / 2) + 1
	local cells : {{number}} = {}
	for i = -r, r do
		for j = -r, r do
			cells[#cells + 1] = { i, j, i * i + j * j }
		end
	end
	table.sort(cells, function(a : {number}, b : {number}) : boolean
		if a[3] ~= b[3] then return a[3] < b[3] end
		if a[2] ~= b[2] then return a[2] < b[2] end
		return a[1] < b[1]
	end)
	for k = 1, math.min(count, #cells) do
		out[k] = { cx + cells[k][1] * spacing, cy + cells[k][2] * spacing }
	end
	return out
end

--- Grid points spacing metres apart over the box shrunk by margin on every side, centred in it,
--- row by row. Empty when the shrunk box is empty.
function logic.mapGrid(minX : number, minY : number, maxX : number, maxY : number, spacing : number, margin : number) : {{number}}
	local out : {{number}} = {}
	local x0, y0, x1, y1 = minX + margin, minY + margin, maxX - margin, maxY - margin
	if x1 < x0 or y1 < y0 or spacing == nil or spacing <= 0 then return out end
	local nx = math.floor((x1 - x0) / spacing) + 1
	local ny = math.floor((y1 - y0) / spacing) + 1
	local ox = x0 + ((x1 - x0) - (nx - 1) * spacing) / 2
	local oy = y0 + ((y1 - y0) - (ny - 1) * spacing) / 2
	for r = 0, ny - 1 do
		for c = 0, nx - 1 do
			out[#out + 1] = { ox + c * spacing, oy + r * spacing }
		end
	end
	return out
end

--- Grid spacing for "spread over the map": about 2n cells over the shrunk box (room to skip water),
--- never below minSpacing.
function logic.spreadSpacing(minX : number, minY : number, maxX : number, maxY : number, n : integer, margin : number, minSpacing : number) : number
	local w = math.max(0, maxX - minX - 2 * margin)
	local h = math.max(0, maxY - minY - 2 * margin)
	local s = math.sqrt(w * h / (2 * math.max(1, n)))
	return math.max(s, minSpacing)
end

--- n points picked evenly from the list (all of them when there are no more than n), in list order.
function logic.spreadPick(points : {{number}}, n : integer) : {{number}}
	local out : {{number}} = {}
	if n == nil or n < 1 then return out end
	if #points <= n then
		for i, p in ipairs(points) do out[i] = p end
		return out
	end
	local step = #points / n
	for k = 0, n - 1 do
		out[#out + 1] = points[math.floor(k * step + step / 2) + 1]
	end
	return out
end

--- Up to n candidates that pass isOk(x, y) (terrain: on the map, not water) and lie at least minDist
--- from every existing town and every point accepted before them. Second result: how many were
--- skipped, by reason ("near" or isOk's reason).
function logic.placeTowns(candidates : {{number}}, existing : {{number}}, n : integer, minDist : number,
		isOk : function(x : number, y : number) : boolean, string) : {{number}}, {string : integer}
	local accepted : {{number}} = {}
	local skipped : {string : integer} = {}
	local d2 = minDist * minDist
	local function farEnough(x : number, y : number, list : {{number}}) : boolean
		for _, p in ipairs(list) do
			local dx, dy = p[1] - x, p[2] - y
			if dx * dx + dy * dy < d2 then return false end
		end
		return true
	end
	for _, c in ipairs(candidates) do
		if #accepted >= n then break end
		local x, y = c[1], c[2]
		if not farEnough(x, y, existing or {}) or not farEnough(x, y, accepted) then
			skipped["near"] = (skipped["near"] or 0) + 1
		else
			local ok, why = true, nil as string
			if isOk ~= nil then ok, why = isOk(x, y) end
			if ok then
				accepted[#accepted + 1] = { x, y }
			else
				local key = why or "terrain"
				skipped[key] = (skipped[key] or 0) + 1
			end
		end
	end
	return accepted, skipped
end

-- Placement relaxation (in game, docs/findings.md "Stress Test" third run: Huge near the camera found
-- 0 of 16 spots, and after ~16 towns the coarse spread grid had none left). When the strict pass
-- places fewer towns than asked, later steps try again with a smaller distance to other towns
-- (dist = fraction of the size's spacing, never below MIN_TOWN_DIST), more rings around the camera
-- (widen = candidate count multiplier) and, spread over the map, a grid as fine as that distance
-- instead of the coarse one. The terrain checks (map edge, water) never relax.
logic.MIN_TOWN_DIST = 800
logic.PLACE_STEPS = {
	{ label = "strict", dist = 1.0, widen = 1, fine = false },
	{ label = "wider", dist = 1.0, widen = 2, fine = true },
	{ label = "70%", dist = 0.7, widen = 3, fine = true },
	{ label = "50%", dist = 0.5, widen = 5, fine = true },
}

--- A placement step's minimum distance to other towns: spacing x step.dist, at least MIN_TOWN_DIST.
function logic.stepDistance(step : SquareStressPlaceStep, spacing : number) : number
	return math.max(logic.MIN_TOWN_DIST, spacing * step.dist)
end

--- "near=12 edge=4", or "none".
function logic.skippedText(skipped : {string : integer}) : string
	local parts : {string} = {}
	for _, k in ipairs({ "near", "water", "edge", "terrain", "error" }) do
		if skipped ~= nil and skipped[k] ~= nil then parts[#parts + 1] = string.format("%s=%d", k, skipped[k]) end
	end
	return #parts > 0 and table.concat(parts, " ") or "none"
end

--- Up to n positions, trying PLACE_STEPS in order until n are placed. candidates(step, minDist) gives
--- each step's candidate points; towns placed by an earlier step count as existing in the later ones.
--- spread = true: every valid candidate is collected, then need of them picked evenly (spreadPick);
--- otherwise the first valid ones in candidate order (nearest the camera first). Second result: one
--- record per step tried (the last one is the relaxation that was needed).
function logic.placeRelaxed(n : integer, existing : {{number}}, spacing : number,
		candidates : function(step : SquareStressPlaceStep, minDist : number) : {{number}},
		isOk : function(x : number, y : number) : boolean, string, spread : boolean) : {{number}}, {SquareStressPlaceTry}
	local placed : {{number}} = {}
	local tried : {SquareStressPlaceTry} = {}
	for _, step in ipairs(logic.PLACE_STEPS) do
		local need = (n or 0) - #placed
		if need <= 0 then break end
		local minDist = logic.stepDistance(step, spacing)
		local blockers : {{number}} = {}
		for _, p in ipairs(existing or {}) do blockers[#blockers + 1] = p end
		for _, p in ipairs(placed) do blockers[#blockers + 1] = p end
		local cands = candidates(step, minDist)
		local got, skipped : {{number}}, {string : integer}
		if spread then
			local valid : {{number}}
			valid, skipped = logic.placeTowns(cands, blockers, #cands, minDist, isOk)
			got = logic.spreadPick(valid, need)
		else
			got, skipped = logic.placeTowns(cands, blockers, need, minDist, isOk)
		end
		for _, p in ipairs(got) do placed[#placed + 1] = p end
		tried[#tried + 1] = { label = step.label, minDist = minDist, candidates = #cands, placed = #got, skipped = skipped }
	end
	return placed, tried
end

--- Log text of placeRelaxed's steps: "relaxation=70% | strict 2500m cands=16 placed=0 (near=12 edge=4) | ...".
function logic.placementText(tried : {SquareStressPlaceTry}) : string
	if tried == nil or #tried == 0 then return "relaxation=none" end
	local parts : {string} = { "relaxation=" .. (#tried == 1 and "none" or tried[#tried].label) }
	for _, t in ipairs(tried) do
		parts[#parts + 1] = string.format("%s %.0fm cands=%d placed=%d (%s)", t.label, t.minDist, t.candidates, t.placed,
			logic.skippedText(t.skipped))
	end
	return table.concat(parts, " | ")
end

---------------------------------------------------------------------------
-- Grow build-out passes (in game, third run: re-sending makeTownUpdateSizeCmd with the same, already
-- capped factor keeps adding ~250-350 buildings per call; Town 10 went 889 -> 2314 over 5 calls).

logic.GROW_PASSES = { 1, 3, 5, 10 }
-- A pass that adds fewer buildings than this ends that town's build-out.
logic.MIN_PASS_GAIN = 20

--- Step i of a grow job with passes per town: the town index and the pass (1-based), town by town.
function logic.passStep(i : integer, passes : integer) : integer, integer
	local p = math.max(1, math.floor(passes or 1))
	return math.floor((i - 1) / p) + 1, (i - 1) % p + 1
end

--- The size factors to send on a pass and a log note. Pass 1 multiplies (grownFactors); later passes
--- re-send the current factors (build-out). factor nil = reset to {1,1,1}.
function logic.growPlan(current : {number}, factor : number, pass : integer) : {number}, string
	if factor == nil then return { 1.0, 1.0, 1.0 }, "" end
	if pass ~= nil and pass > 1 then return logic.scaledFactors(current, 1), " (build-out pass)" end
	local out, capped = logic.grownFactors(current, factor)
	if not capped then return out, "" end
	local same = logic.scaledFactors(current, 1)
	for i = 1, 3 do
		if same[i] ~= out[i] then return out, string.format(" (capped at %g)", logic.MAX_SIZE_FACTOR) end
	end
	return out, " (at cap, build-out pass)"
end

--- Whether a town's build-out goes on after a pass took its building count from before to after.
function logic.passContinues(before : integer, after : integer) : boolean
	return (after or 0) - (before or 0) >= logic.MIN_PASS_GAIN
end

--- 1 + the highest N among names "SQST Town N" (1 when there are none), so a new batch never repeats
--- a name of an earlier session.
function logic.nextTownNumber(names : {string}) : integer
	local best = 0
	for _, name in ipairs(names or {}) do
		local n = tonumber(tostring(name):match("^SQST Town (%d+)$"))
		if n ~= nil and n > best then best = math.floor(n) end
	end
	return best + 1
end

--- One {newTown, nearestOtherTown} pair per new town (entity ids), without duplicates (A-B = B-A).
--- A new town with no other town gets no pair.
function logic.nearestPairs(newTowns : {SquareStressTownPos}, allTowns : {SquareStressTownPos}) : {{integer}}
	local out : {{integer}} = {}
	local seen : {string : boolean} = {}
	for _, a in ipairs(newTowns or {}) do
		local best : SquareStressTownPos = nil
		local bestD = math.huge
		for _, b in ipairs(allTowns or {}) do
			if b.id ~= a.id then
				local dx, dy = b.x - a.x, b.y - a.y
				local d = dx * dx + dy * dy
				if d < bestD then best, bestD = b, d end
			end
		end
		if best ~= nil then
			local lo, hi = math.min(a.id, best.id), math.max(a.id, best.id)
			local key = tostring(lo) .. "-" .. tostring(hi)
			if not seen[key] then
				seen[key] = true
				out[#out + 1] = { a.id, best.id }
			end
		end
	end
	return out
end

--- The Towns tab readout: "Towns 12 (2 frozen)   Capacity 19.2k   Buildings 3.4k".
function logic.townReadout(towns : {integer}, caps : {integer : {integer}}, buildings : {integer : {integer}}, frozen : integer) : string
	local cap : number = 0
	local nb = 0
	for _, t in ipairs(towns or {}) do
		local c = caps ~= nil and caps[t] or nil
		if c ~= nil then
			for _, v in ipairs(c) do cap = cap + (tonumber(v) or 0) end
		end
		local b = buildings ~= nil and buildings[t] or nil
		if b ~= nil then nb = nb + #b end
	end
	local s = string.format("Towns %d", #(towns or {}))
	if frozen ~= nil and frozen > 0 then s = s .. string.format(" (%d frozen)", frozen) end
	return s .. string.format("   Capacity %s   Buildings %s", logic.formatMoney(cap), logic.formatMoney(nb))
end

---------------------------------------------------------------------------
-- Traffic tab (PLAN.md Phase 3)

logic.VEHICLES_PER_LINE = { 1, 5, 10, 25 }
-- Stop a buy batch after this many failures in a row (no money, no depot, refused config).
logic.MAX_BUY_FAILURES = 3
-- A buy or SetLine callback normally comes a frame after the command ran; give up waiting after this.
logic.VEHICLE_TIMEOUT_MS = 20000

--- Ends a job early: no more steps run, and the queue reports it done (with the steps so far) at the
--- next tick. Harmless on a job that was cleared from the queue.
function logic.stop(job : SquareStressJob)
	if job == nil then return end
	job.total = job.done
	job.waiting = false
end

--- The purchases for "N per line": round robin over the lines that have a template vehicle (k-th
--- vehicle of every line before the k+1-th of any), so a batch stopped early still spread over all
--- lines. Second result: the lines skipped because they have no vehicle to copy.
function logic.buyPlan(lines : {SquareStressLineVehicle}, n : integer) : {SquareStressLineVehicle}, {integer}
	local plan : {SquareStressLineVehicle} = {}
	local skipped : {integer} = {}
	local usable : {SquareStressLineVehicle} = {}
	for _, l in ipairs(lines or {}) do
		if l.vehicle ~= nil and l.vehicle >= 0 then usable[#usable + 1] = l else skipped[#skipped + 1] = l.line end
	end
	for _ = 1, math.max(0, n or 0) do
		for _, l in ipairs(usable) do plan[#plan + 1] = { line = l.line, vehicle = l.vehicle } end
	end
	return plan, skipped
end

--- Sum of the part prices; nil when any part price is unknown.
function logic.configPrice(prices : {number}) : number
	if prices == nil then return nil end
	local sum : number = 0
	for _, p in ipairs(prices) do
		if p == nil or p ~= p then return nil end
		sum = sum + p
	end
	return sum
end

--- Whether the balance can pay for a vehicle. Unknown balance (infinite money) or unknown price: yes.
function logic.canAfford(balance : number, price : number) : boolean
	if balance == nil or price == nil then return true end
	return balance >= price
end

--- The Traffic tab readout: "Lines 4   Vehicles 37   Sim persons 12.3k   Driving now 63   Added 10".
--- A nil count is left out (its API was unavailable; driving: no clear scan yet).
function logic.trafficReadout(lines : integer, vehicles : integer, persons : integer, added : integer, driving? : integer) : string
	local parts : {string} = {}
	if lines ~= nil then parts[#parts + 1] = "Lines " .. tostring(lines) end
	if vehicles ~= nil then parts[#parts + 1] = "Vehicles " .. logic.formatMoney(vehicles) end
	if persons ~= nil then parts[#parts + 1] = "Sim persons " .. logic.formatMoney(persons) end
	if driving ~= nil then parts[#parts + 1] = "Driving now " .. logic.formatMoney(driving) end
	if added ~= nil and added > 0 then parts[#parts + 1] = "Added " .. tostring(added) end
	if #parts == 0 then return "Traffic: readout unavailable" end
	return table.concat(parts, "   ")
end

---------------------------------------------------------------------------
-- Clear traffic (Traffic tab, PLAN.md Phase 3B). A private car is a SIM_PERSON driving (lastMoveMode
-- DRIVE, a MOVE_PATH, not seated in a vehicle); api.cmd.debug.makeSimPersonSetStateCmd(e, 2) ("jump
-- home") takes it off the road (docs/findings.md "Stress Test probes", fourth run).

logic.CLEAR_INTERVALS = { 2, 5, 10 }             -- Keep traffic cleared: seconds between cycles
logic.CLEAR_SCAN_PER_FRAME = 5000                -- persons read per frame
logic.CLEAR_SEND_PER_FRAME = 200                 -- set-state commands sent per frame
logic.CLEAR_STATE_JUMP_HOME = 2
logic.CLEAR_SUMMARY_US = 30000000                -- Keep cleared: at most one window log line per 30 s
logic.CLEAR_CALLBACK_TIMEOUT_US = 10000000       -- a cycle ends this long after its last send at the latest

--- Whether a person is driving a car right now: DRIVE, a MOVE_PATH, not at (in) a vehicle, and never a
--- transport vehicle (the player's buses, trains, ...).
function logic.isDriver(driveMode : boolean, hasPath : boolean, atVehicle : boolean, isTransportVehicle : boolean) : boolean
	return driveMode == true and hasPath == true and not atVehicle and not isTransportVehicle
end

--- The last index of the chunk of at most `size` items that starts at `first` in a list of n.
function logic.chunkLast(first : integer, n : integer, size : integer) : integer
	return math.min(n, first + math.max(1, size) - 1)
end

--- Frames (queue steps) a clear cycle still needs: scan chunks left, then send chunks left.
function logic.clearStepsLeft(scanLeft : integer, sendLeft : integer, scanPer : integer, sendPer : integer) : integer
	local function chunks(left : integer, per : integer) : integer
		if left == nil or left <= 0 then return 0 end
		return math.ceil(left / math.max(1, per))
	end
	return chunks(scanLeft, scanPer) + chunks(sendLeft, sendPer)
end

--- The [SQST] line of one clear cycle.
function logic.clearLine(name : string, scanned : integer, drivers : integer, sent : integer, ok : integer,
	answered : integer, ms : number, note? : string) : string
	local s = string.format("[SQST] %s scanned=%d drivers=%d sent=%d ok=%d ms=%.0f", name, scanned, drivers, sent, ok, ms)
	if answered < sent then s = s .. string.format(" answered=%d", answered) end
	if note ~= nil then s = s .. " " .. note end
	return s
end

---------------------------------------------------------------------------
-- Action button labels (each tab section is a form: options, then one button that says what it does)

--- "Grow all towns x10", "Grow nearest town x10, 3 passes", "Reset all towns to x1" (factor nil =
--- reset, which always runs one pass).
function logic.growLabel(nearest : boolean, factor : number, passes? : integer) : string
	local what = nearest and "nearest town" or "all towns"
	if factor == nil then return "Reset " .. what .. " to x1" end
	local s = string.format("Grow %s x%g", what, factor)
	if passes ~= nil and passes > 1 then s = s .. string.format(", %d passes", passes) end
	return s
end

--- "Spawn 1 medium town", "Spawn 5 large towns".
function logic.spawnLabel(n : integer, sizeLabel : string) : string
	return string.format("Spawn %d %s town%s", n, tostring(sizeLabel):lower(), n == 1 and "" or "s")
end

--- "Add 1 vehicle per line", "Add 5 vehicles per line".
function logic.addVehiclesLabel(n : integer) : string
	return string.format("Add %d vehicle%s per line", n, n == 1 and "" or "s")
end

---------------------------------------------------------------------------
-- Auto bus lines (Traffic tab, PLAN.md Phase 3C; gui/stress_buslines.tl)

logic.BUS_TOWN_CHOICES = { "Nearest to camera", "5 nearest", "All towns" }
logic.BUS_TOWN_COUNTS = { 1, 5, 25 }             -- towns per choice ("All towns" capped at 25)
logic.BUS_LINES_PER_TOWN = { 1, 2, 4 }
logic.BUSES_PER_LINE = { 2, 5, 10 }

--- The towns for a bus line batch: nearest to (cx, cy) first, BUS_TOWN_COUNTS[choice] of them.
function logic.busTownPick(positions : {SquareStressTownPos}, cx : number, cy : number, choice : integer) : {SquareStressTownPos}
	local sorted : {SquareStressTownPos} = {}
	local d : {SquareStressTownPos : number} = {}
	for i, t in ipairs(positions or {}) do
		sorted[i] = t
		d[t] = (t.x - cx) * (t.x - cx) + (t.y - cy) * (t.y - cy)
	end
	table.sort(sorted, function(a : SquareStressTownPos, b : SquareStressTownPos) : boolean
		if d[a] ~= d[b] then return d[a] < d[b] end
		return a.id < b.id
	end)
	local n = logic.BUS_TOWN_COUNTS[choice] or 1
	local out : {SquareStressTownPos} = {}
	for i = 1, math.min(n, #sorted) do out[i] = sorted[i] end
	return out
end

--- "Add 1 bus line to the nearest town", "Add 2 bus lines each to 5 towns", "... to all towns (max 25)".
function logic.busLinesLabel(choice : integer, lines : integer) : string
	local what = string.format("Add %d bus line%s", lines, lines == 1 and "" or "s")
	if choice == 1 then return what .. " to the nearest town" end
	if choice == 2 then return what .. string.format(" each to %d towns", logic.BUS_TOWN_COUNTS[2]) end
	return what .. string.format(" each to all towns (max %d)", logic.BUS_TOWN_COUNTS[3])
end

---------------------------------------------------------------------------
-- Hide all notifications (Game tab). The base Notifications game script's "updateIgnoredTypes" event
-- (base game_mechanics/notifications/notifications.script.tl:741-764) replaces the whole ignored set:
-- ignoredTypes is a SET {typeName = true}, ignoredGuiTypes a LIST of gui types (each expands to every
-- notification type of that gui type, notification_util.tl:87-100), ignoreFully = true means no entry
-- is created at all (notifications.d.tl:95-107; the missions use it, mission_sim.script.tl:789-807).

logic.NOTIFICATION_GUI_TYPES = { "Info", "Caution", "Problem", "Opportunity" }

--- The event payload: on = ignore every type fully (the four gui types plus, when known, every type
--- name, which also covers types without a gui type); off = ignore nothing (this also clears the
--- player's own notification-log filter, which lives in the same set).
function logic.notificationPayload(on : boolean, typeNames : {string}) : {string : any}
	if not on then return { ignoredTypes = {}, ignoreFully = false } end
	local guiTypes : {string} = {}
	for i, t in ipairs(logic.NOTIFICATION_GUI_TYPES) do guiTypes[i] = t end
	local p : {string : any} = { ignoredGuiTypes = guiTypes, ignoreFully = true }
	if typeNames ~= nil and #typeNames > 0 then
		local set : {string : boolean} = {}
		for _, n in ipairs(typeNames) do set[n] = true end
		p["ignoredTypes"] = set
	end
	return p
end

return logic
