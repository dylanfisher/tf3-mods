-- Stress Test pure logic: mod.json params -> baseConfig, the throttled job queue, and the money /
-- date / grid helpers. No engine calls (the caller passes the clock and the BaseConfig), so it is
-- unit-tested offline (tests/square_stress_test/). Types: stress_types.d.tl.

local logic : SquareStressLogic = {}

-- mod.json param keys (mod.json "params"; values arrive as 1-based option indices, docs/findings.md
-- "Script function signatures").
logic.PARAM_KEYS = { "no_costs", "sandbox", "vehicles_no_expire", "no_emissions", "sim_recompute", "town_develop",
	"show_probe_tab", "car_traffic", "town_capacity" }

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
		carTrafficMode = logic.carTrafficMode(p["car_traffic"]),
		townCapacityFactor = logic.CAPACITY_FACTORS[logic.optionIndex(p["town_capacity"], #logic.CAPACITY_FACTORS)],
	}
end

---------------------------------------------------------------------------
-- More car traffic (plans/square_stress_test/MORE_TRAFFIC.md, Phase 7a; load-time, NOT verified in game).
-- A private car is a SIM_PERSON driving (docs/findings.md "Stress Test probes", fourth run); no command
-- makes more of them, so the levers are the town buildings' personCapacity:
-- - Mode choice: a personCapacity may carry disallowedMoveModes (MoveMode WALK / DRIVE / LINES,
--   api/tealdef/api/type.d.tl:2364-2368), flat on the table as base industries set it
--   (industries/industryutil.lua:444-457: {"WALK", "DRIVE"}, i.e. workers come by line) and landmarks too
--   (landmarks/landmark_util_serialized.tl:200-221). The engine keeps it as PERSON_CAPACITY
--   .pathfindingPreference (api/tealdef/api/engine.d.tl:827-843); town buildings read {} in game (probe 9d).
-- - Capacity: town buildings set personCapacity.capacity = params.capacity
--   (buildings/townbuildingutil.lua:213-217), and the cargo rules after it are computed from
--   params.capacity (:219-230), so scaling only personCapacity.capacity leaves cargo demand alone.
-- mod.script.tl runFn wraps the updateFn of town building scripts (townbuildingutil.lua:98-99,
-- makeBuildingScript) through a loadScript modifier (base/mod.lua:111) and patches each result here.

--- "car_traffic" options. landUses: the personCapacity.type values (the landUseType strings of
--- townbuildingutil.makeBuildingStatic, :44) that get `disallow` added. Never DRIVE.
logic.CAR_TRAFFIC_MODES = {
	{ id = "default", landUses = {}, disallow = {} },
	{ id = "drive_destinations", landUses = { "COMMERCIAL", "INDUSTRIAL" }, disallow = { "WALK", "LINES" } },
	{ id = "drive_all", landUses = { "RESIDENTIAL", "COMMERCIAL", "INDUSTRIAL" }, disallow = { "WALK", "LINES" } },
}
--- "town_capacity" options: x1 (unchanged) / x2 / x4 of personCapacity.capacity.
logic.CAPACITY_FACTORS = { 1.0, 2.0, 4.0 }

--- The car_traffic option (nil for Default or anything unusable).
function logic.carTrafficMode(raw : any) : SquareStressCarTrafficMode
	local i = logic.optionIndex(raw, #logic.CAR_TRAFFIC_MODES)
	if i == 1 then return nil end
	return logic.CAR_TRAFFIC_MODES[i]
end

--- Whether the town building patch (and so the loadScript modifier) is needed at all.
function logic.wantsTownBuildingPatch(cfg : SquareStressConfig) : boolean
	if cfg == nil then return false end
	return cfg.carTrafficMode ~= nil or (cfg.townCapacityFactor ~= nil and cfg.townCapacityFactor ~= 1.0)
end

--- The "[SQST] config car_traffic=... town_capacity=..." fields of runFn's line.
function logic.townBuildingConfigText(cfg : SquareStressConfig) : string
	local mode = cfg ~= nil and cfg.carTrafficMode or nil
	local f = cfg ~= nil and cfg.townCapacityFactor or nil
	return string.format("car_traffic=%s town_capacity=x%g", mode ~= nil and mode.id or "default", f or 1.0)
end

--- A loadScript file name of a town building script: a ".script" file (plain, .lua or .tl) somewhere
--- below a "buildings" folder (base: buildings/<era>/<type>/<size>/<name>.script.lua, referenced by the
--- .con.lua as "<name>.script@updateFn", townbuildingutil.lua:89). Never a .con.lua, an industry or a
--- landmark (those live in industry/ and landmarks/). The exact form of the name the modifier gets is
--- not known yet (MORE_TRAFFIC.md U1), so separators and any prefix are accepted.
function logic.isTownBuildingScript(fileName : string) : boolean
	if type(fileName) ~= "string" then return false end
	local f = "/" .. fileName:gsub("\\", "/")
	if f:find("/buildings/", 1, true) == nil then return false end
	return f:match("%.script$") ~= nil or f:match("%.script%.lua$") ~= nil or f:match("%.script%.tl$") ~= nil
end

local function hasValue(list : {string}, v : string) : boolean
	for _, x in ipairs(list or {}) do
		if x == v then return true end
	end
	return false
end

--- Patches one town building updateFn result for the config; true when something changed. Only results
--- with townBuilding and personCapacity (town buildings, never industries, landmarks or stations).
--- Mode: adds the option's disallowed move modes for its land uses, keeping existing entries and never
--- adding DRIVE. Capacity: capacity * factor, rounded, for capacities > 0. Defaults change nothing.
function logic.patchTownBuildingResult(result : {string : any}, cfg : SquareStressConfig) : boolean
	if type(result) ~= "table" or cfg == nil then return false end
	local pc = result["personCapacity"]
	if result["townBuilding"] == nil or type(pc) ~= "table" then return false end
	local cap = pc as {string : any}
	local changed = false
	local mode = cfg.carTrafficMode
	if mode ~= nil and type(cap["type"]) == "string" and hasValue(mode.landUses, cap["type"] as string) then
		local old = cap["disallowedMoveModes"]
		local list : {string} = {}
		if type(old) == "table" then
			for _, m in ipairs(old as {string}) do list[#list + 1] = m end
		end
		local added = false
		for _, m in ipairs(mode.disallow) do
			if m ~= "DRIVE" and not hasValue(list, m) then
				list[#list + 1] = m
				added = true
			end
		end
		if added then
			cap["disallowedMoveModes"] = list
			changed = true
		end
	end
	local f = cfg.townCapacityFactor
	local n = cap["capacity"]
	if f ~= nil and f ~= 1.0 and type(n) == "number" and (n as number) > 0 then
		local new = math.floor((n as number) * f + 0.5)
		if new ~= n then
			cap["capacity"] = new
			changed = true
		end
	end
	return changed
end

--- The one "[SQST] town_building_patch" line (the first patched result of a Lua state).
function logic.townBuildingPatchLine(fileName : string, result : {string : any}, capBefore : any, wrapped : integer,
	seen : integer) : string
	local pc = (type(result) == "table" and type(result["personCapacity"]) == "table")
		and result["personCapacity"] as {string : any} or {}
	local modes = type(pc["disallowedMoveModes"]) == "table" and table.concat(pc["disallowedMoveModes"] as {string}, ",") or ""
	return string.format("[SQST] town_building_patch first=%s type=%s modes=%s capacity=%s->%s wrapped=%d seen=%d",
		tostring(fileName), tostring(pc["type"]), modes ~= "" and modes or "-", tostring(capBefore),
		tostring(pc["capacity"]), wrapped or 0, seen or 0)
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

--- The move-mode split of a scan by SIM_PERSON.lastMoveMode: "DRIVE 79 (11%) / WALK 614 (89%) /
--- LINES 0 (0%)" (shares of the three; persons with another value are not counted). nil for no scan.
function logic.moveSplitText(split : SquareStressMoveSplit) : string
	if split == nil then return nil end
	local d, w, l = split.drive or 0, split.walk or 0, split.lines or 0
	local total = d + w + l
	local function part(name : string, n : integer) : string
		if total <= 0 then return name .. " " .. logic.formatMoney(n) end
		return string.format("%s %s (%.0f%%)", name, logic.formatMoney(n), 100 * n / total)
	end
	return part("DRIVE", d) .. " / " .. part("WALK", w) .. " / " .. part("LINES", l)
end

--- The same split for an [SQST] line: "modes=DRIVE:79,WALK:614,LINES:0".
function logic.moveSplitLog(split : SquareStressMoveSplit) : string
	if split == nil then return "modes=-" end
	return string.format("modes=DRIVE:%d,WALK:%d,LINES:%d", split.drive or 0, split.walk or 0, split.lines or 0)
end

--- The Traffic tab readout: "Lines 4   Vehicles 37   Sim persons 12.3k   Driving now 63   Added 10",
--- and the last scan's move-mode split on a second line ("Last trip mode: DRIVE 79 (11%) / ...").
--- A nil count is left out (its API was unavailable; driving and modes: no scan yet).
function logic.trafficReadout(lines : integer, vehicles : integer, persons : integer, added : integer, driving? : integer,
	modes? : SquareStressMoveSplit) : string
	local parts : {string} = {}
	if lines ~= nil then parts[#parts + 1] = "Lines " .. tostring(lines) end
	if vehicles ~= nil then parts[#parts + 1] = "Vehicles " .. logic.formatMoney(vehicles) end
	if persons ~= nil then parts[#parts + 1] = "Sim persons " .. logic.formatMoney(persons) end
	if driving ~= nil then parts[#parts + 1] = "Driving now " .. logic.formatMoney(driving) end
	if added ~= nil and added > 0 then parts[#parts + 1] = "Added " .. tostring(added) end
	local split = modes ~= nil and ("Last trip mode: " .. logic.moveSplitText(modes)) or nil
	if #parts == 0 then return split or "Traffic: readout unavailable" end
	if split ~= nil then return table.concat(parts, "   ") .. "\n" .. split end
	return table.concat(parts, "   ")
end

---------------------------------------------------------------------------
-- Clear traffic (Traffic tab, PLAN.md Phase 3B). A private car is a SIM_PERSON driving (lastMoveMode
-- DRIVE, a MOVE_PATH, not seated in a vehicle); api.cmd.debug.makeSimPersonSetStateCmd(e, 2) ("jump
-- home") takes it off the road (docs/findings.md "Stress Test probes", fourth run).

logic.CLEAR_INTERVALS = { 2, 5, 10, 60, 120 }           -- Keep traffic cleared: seconds between cycles
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

-- Clear traffic "Where": everywhere, only cars in towns (traffic between towns keeps driving, e.g.
-- through the Junction test's junctions), or only cars outside towns.
logic.CLEAR_WHERE = { "Everywhere", "In towns", "Outside towns" }
-- A town's area: its buildings' centre and the farthest building from it, plus this margin (m).
logic.TOWN_AREA_MARGIN = 60.0

--- Centre (mean) and radius (farthest point + margin) of a town's building positions; nil for none.
function logic.townArea(points : {{number}}, margin : number) : SquareStressTownArea
	if points == nil or #points == 0 then return nil end
	local x, y = 0.0, 0.0
	for _, p in ipairs(points) do
		x = x + p[1] / #points
		y = y + p[2] / #points
	end
	local r = 0.0
	for _, p in ipairs(points) do
		local d = math.sqrt((p[1] - x) ^ 2 + (p[2] - y) ^ 2)
		if d > r then r = d end
	end
	return { x = x, y = y, r = r + (margin or 0) }
end

function logic.inTownArea(areas : {SquareStressTownArea}, x : number, y : number) : boolean
	for _, a in ipairs(areas or {}) do
		if (x - a.x) ^ 2 + (y - a.y) ^ 2 <= a.r * a.r then return true end
	end
	return false
end

--- Whether a driver at a known place is sent home for this Where choice.
function logic.clearWanted(where : integer, inTown : boolean) : boolean
	if where == 2 then return inTown end
	if where == 3 then return not inTown end
	return true
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

---------------------------------------------------------------------------
-- Test grid (Towns tab): identical towns at exact, equally spaced positions, for traffic tests
-- between towns on a flat map (Blank Slate).

logic.GRID_LAYOUTS = {
	{ label = "2 x 2", cols = 2, rows = 2 },
	{ label = "3 x 3", cols = 3, rows = 3 },
	{ label = "1 x 4", cols = 4, rows = 1 },
}
logic.GRID_SPACINGS = { 1000, 2000, 3000, 4000, 6000 }   -- metres between neighbouring town centres
logic.GRID_CONNECT = { "None", "Neighbours", "Neighbours + diagonals" }
-- One seed for every grid town, so towns of the same size grow from the same generator input.
logic.GRID_SEED = "sqst_grid"

--- The town centres of a cols x rows grid around (cx, cy), spacing metres apart, row by row from the
--- lowest y. Each entry: { x, y, name } with names "Grid A1" (row letter, column number).
function logic.gridPositions(cx : number, cy : number, cols : integer, rows : integer, spacing : number) : {SquareStressGridPoint}
	local out : {SquareStressGridPoint} = {}
	local x0 = cx - (cols - 1) * spacing / 2
	local y0 = cy - (rows - 1) * spacing / 2
	for r = 1, rows do
		for c = 1, cols do
			out[#out + 1] = {
				x = x0 + (c - 1) * spacing,
				y = y0 + (r - 1) * spacing,
				name = string.format("Grid %s%d", string.char(64 + r), c),
				row = r,
				col = c,
			}
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Crossing test (Towns tab; gui/stress_junctions.tl jn.buildCrossings): 4 towns and a 3 x 3 grid of
-- long roads between them, every junction a plain crossing of our own construction (stress_crossing):
--   rows (west -> east) at y = +D, 0, -D: 3, 2, 1 lanes each way; columns (south -> north) at
--   x = -D, 0, +D: 3, 2, 1 lanes. Their 9 crossings are every lane-count pair once.
--   A collector road (2 lanes) on each side, L beyond the outer row / column: T junctions where the
--   rows / columns end, the middle one a crossing whose outer arm goes to that side's town, G further.
-- So W <-> E traffic drives straight along the rows and every other trip turns somewhere.

logic.CROSSING_D = 1500.0          -- between neighbouring rows / columns
logic.CROSSING_L = 1000.0          -- outer row / column to the collector
logic.CROSSING_G = 1500.0          -- collector to the town centre
logic.CROSSING_LANES = { 3, 2, 1 } -- rows north -> south, columns west -> east (stress_crossing.ROADS 3, 2, 1)
logic.CROSSING_COLLECTOR = 2       -- town medium

local DIRS : {string : {number}} = { E = { 1, 0 }, N = { 0, 1 }, W = { -1, 0 }, S = { 0, -1 } }
logic.CROSSING_DIRS = DIRS

--- The layout around (cx, cy) at `scale` (1 = the distances above): junctions, links between their arms,
--- town points and the town links. Angles: the construction's local x (main road) direction in
--- radians; a T's side arm (local +y) points to the grid.
function logic.crossingLayout(cx : number, cy : number, scale : number) : SquareStressCrossingLayout
	local D, L, G = logic.CROSSING_D * scale, logic.CROSSING_L * scale, logic.CROSSING_G * scale
	local lanes = logic.CROSSING_LANES
	local out : SquareStressCrossingLayout = { junctions = {}, links = {}, towns = {} }
	local byId : {string : SquareStressCrossingJunction} = {}
	local function add(j : SquareStressCrossingJunction)
		j.x, j.y = cx + j.x, cy + j.y
		out.junctions[#out.junctions + 1] = j
		byId[j.id] = j
	end
	local rowY = { D, 0.0, -D }
	local colX = { -D, 0.0, D }
	for r = 1, 3 do
		for c = 1, 3 do
			add({ id = string.format("x%d%d", r, c), x = colX[c], y = rowY[r], angle = 0.0, shape = 1, main = lanes[r], side = lanes[c],
				label = string.format("Crossing %dx%d", lanes[r], lanes[c]) })
		end
	end
	-- collectors: side ("w", "e", "n", "s"), toward the grid, angle so local +y points there
	local sides = {
		{ key = "w", ux = 1.0, uy = 0.0, angle = -math.pi / 2, name = "W" },
		{ key = "e", ux = -1.0, uy = 0.0, angle = math.pi / 2, name = "E" },
		{ key = "n", ux = 0.0, uy = -1.0, angle = math.pi, name = "N" },
		{ key = "s", ux = 0.0, uy = 1.0, angle = 0.0, name = "S" },
	}
	for _, sd in ipairs(sides) do
		local horizontal = sd.ux ~= 0 -- w / e collectors run north-south and meet the rows
		for k = 1, 3 do
			local x, y : number, number
			local road : integer
			if horizontal then
				x, y = -sd.ux * (D + L), rowY[k]
				road = lanes[k]
			else
				x, y = colX[k], -sd.uy * (D + L)
				road = lanes[k]
			end
			local shape = k == 2 and 1 or 2
			add({ id = sd.key .. tostring(k), x = x, y = y, angle = sd.angle, shape = shape, main = logic.CROSSING_COLLECTOR, side = road,
				label = string.format("%s %d/%d", shape == 2 and "T" or "Crossing", logic.CROSSING_COLLECTOR, road) })
		end
		local tx, ty = -sd.ux * (D + L + G), -sd.uy * (D + L + G)
		out.towns[#out.towns + 1] = { name = "Grid " .. sd.name, x = cx + tx, y = cy + ty, from = sd.key .. "2",
			dir = horizontal and (sd.ux > 0 and "W" or "E") or (sd.uy > 0 and "S" or "N") }
	end
	local function link(a : string, aDir : string, b : string, bDir : string)
		out.links[#out.links + 1] = { a = a, aDir = aDir, b = b, bDir = bDir }
	end
	for r = 1, 3 do
		link("w" .. r, "E", "x" .. r .. "1", "W")
		link("x" .. r .. "1", "E", "x" .. r .. "2", "W")
		link("x" .. r .. "2", "E", "x" .. r .. "3", "W")
		link("x" .. r .. "3", "E", "e" .. r, "W")
	end
	for c = 1, 3 do
		link("n" .. c, "S", "x1" .. c, "N")
		link("x1" .. c, "S", "x2" .. c, "N")
		link("x2" .. c, "S", "x3" .. c, "N")
		link("x3" .. c, "S", "s" .. c, "N")
	end
	link("w1", "S", "w2", "N") link("w2", "S", "w3", "N")
	link("e1", "S", "e2", "N") link("e2", "S", "e3", "N")
	link("n1", "E", "n2", "W") link("n2", "E", "n3", "W")
	link("s1", "E", "s2", "W") link("s2", "E", "s3", "W")
	return out
end

--- How far the layout reaches from its centre at scale 1 (plus a town's own extent).
function logic.crossingReach(townR : number) : number
	return logic.CROSSING_D + logic.CROSSING_L + logic.CROSSING_G + townR
end

--- Road pairs between grid points (1-based indices into gridPositions' list): mode 1 none,
--- 2 horizontal and vertical neighbours, 3 also both diagonals of every cell.
function logic.gridPairs(cols : integer, rows : integer, mode : integer) : {{integer}}
	local out : {{integer}} = {}
	if mode == nil or mode <= 1 then return out end
	local function idx(r : integer, c : integer) : integer return (r - 1) * cols + c end
	for r = 1, rows do
		for c = 1, cols do
			if c < cols then out[#out + 1] = { idx(r, c), idx(r, c + 1) } end
			if r < rows then out[#out + 1] = { idx(r, c), idx(r + 1, c) } end
			if mode >= 3 and r < rows and c < cols then
				out[#out + 1] = { idx(r, c), idx(r + 1, c + 1) }
				out[#out + 1] = { idx(r, c + 1), idx(r + 1, c) }
			end
		end
	end
	return out
end

-- Streets choice of Test grid / Junction test: the town's own streets, or our wide street grid
-- (stress_grid_streets.lua) built first. GRID_STREET_HALF must match stress_grid_streets.HALF.
-- "Wide grid, locked": every grid street gets roadDevelopmentLocked ("prevent towns from updating or
-- extending this road", api engine.d.tl BaseEdge; the flag the game's Player owned road tool sets).
logic.GRID_STREETS = { "Town's own", "Wide grid", "Wide grid, locked" }
logic.GRID_STREET_HALF = { 200, 300, 400 }
logic.WIDE_GRID_NEW_FROM = 1940   -- town_new_large exists from this year; before it, town_old_large

--- Street grid half-size index for a town size (initial capacity per district).
function logic.gridStreetHalf(caps : integer) : integer
	if caps <= 100 then return 1 end
	if caps <= 400 then return 2 end
	return 3
end

--- "Create 2 x 2 grid, 2 km".
function logic.gridLabel(layoutLabel : string, spacing : number) : string
	return string.format("Create %s grid, %g km", layoutLabel, spacing / 1000)
end

---------------------------------------------------------------------------
-- Remove towns (Towns tab): makeTownDestroyCmd removes a town with its streets and buildings
-- (cmd.d.tl:832-836); the map editor sends one per town (map_editor.tl:758-778).

logic.REMOVE_TARGETS = { "Nearest to camera", "Grid towns", "All towns" }

--- Whether a town name is one of the test grid's ("Grid A1" ... "Grid C3"; Showcases before 2026-10-12: "Grid S35").
function logic.isGridTownName(name : string) : boolean
	return name ~= nil and tostring(name):match("^Grid %u%d+$") ~= nil
end

--- The twin mode words of Showcase town names (SHOWCASE_AB / LIGHTS_AB label).
-- "Full fan": the Lights showcase's fourth twin until 2026-10-13 (old saves); "Kerb locked" since.
-- "Keep lights": the bench's sl_keeplights twins (BENCH.md). "Classic phases": the light plans A/B's sl_classic twins
-- until 2026-10-16 (old saves; Smart Lanes dropped the classic patterns, its PLAN.md "No classic fallback").
-- "Auto timing": the light plans A/B's sl_auto twins.
logic.TEST_TOWN_MODES = { "Smart lanes", "Game default", "Smart phases", "Full fan", "Kerb locked", "Exit fan", "Keep lights",
	"Ring turbo", "Ring matched", "Ring outer exit", "Ring two exits", "Ring spiral", "Ring spread", "Ring split", "Ring mid",
	"Classic phases", "Auto timing", "Ring mid 2", "Ring turbo in" }
-- the light plans A/B's unbalanced towns: "<mode> <set> <side> <word>" ("Auto timing 2 S tiny"); the bench Sheet 5's mixes
-- ("Ring mid 2 3 N large")
logic.TEST_TOWN_WORDS = { busy = true, small = true, tiny = true, large = true }
-- the bench's twins on a mid-node ring next to plain-ring twins (Sheet 4 v5, stress_bench twinMode): "<mode> mid"
do
	local n = #logic.TEST_TOWN_MODES
	for i = 1, n do logic.TEST_TOWN_MODES[#logic.TEST_TOWN_MODES + 1] = logic.TEST_TOWN_MODES[i] .. " mid" end
end

--- Whether a town name is a test town's (Remove towns > Grid towns; towns.removePlan also takes the
--- session's own created towns by entity id): the test grid's "Grid A1" (and older Showcases' "Grid S35"),
--- the Crossing test's "Grid N" / "Grid E" / "Grid S" / "Grid W",
--- the Lights showcase's "<mode> <set> <side>" ("Smart lanes 1 N") and the Showcase's "<type> <set> <side>
--- (<mode>)" ("Parclo 3 NE (Game default)"); side a compass point (N, NE, ... NW).
function logic.isTestTownName(name : string) : boolean
	if name == nil then return false end
	local s = tostring(name)
	if logic.isGridTownName(s) then return true end
	if s:match("^Grid [NESW]$") ~= nil then return true end   -- the Crossing test's four towns
	for _, m in ipairs(logic.TEST_TOWN_MODES) do
		local side = s:match("^" .. m .. " %d+ (%u%u?)$")
		if side ~= nil and logic.compassIndex(side) ~= nil then return true end
		local side2, word = s:match("^" .. m .. " %d+ (%u%u?) (%l+)$")
		if side2 ~= nil and logic.compassIndex(side2) ~= nil and logic.TEST_TOWN_WORDS[word] then return true end
		side = s:match("^%S.* %d+ (%u%u?) %(" .. m .. "%)$")
		if side ~= nil and logic.compassIndex(side) ~= nil then return true end
	end
	return false
end

--- "Remove the nearest town", "Remove grid towns", "Remove all towns".
function logic.removeLabel(target : integer) : string
	if target == 2 then return "Remove grid towns" end
	if target == 3 then return "Remove all towns" end
	return "Remove the nearest town"
end

---------------------------------------------------------------------------
-- Junction test (Towns tab; gui/stress_junctions.tl, needs square_roundabouts): a test grid of
-- towns with one junction in the middle of every cell, turned 45 deg so its four arms point at
-- the cell's four corner towns, each arm linked to its town by a straight road. Between towns
-- there is no other road, so all town-to-town traffic drives through the junctions.

logic.JUNCTION_DIR = "infrastructure/street_construction/"
-- Every junction type of square_roundabouts' menu entries, at the entry's defaults except the
-- layout params listed (1-based indices: square_roundabouts_channel.lua LAYOUT_T / LAYOUT_X,
-- square_roundabouts_interchange.lua LAYOUT_TWO_BRIDGE / DUMBBELL / PEANUT).
-- Every road arm is "Country large" (index 6 of square_roundabouts' six arm roads, geometry.lua
-- ARM_TEMPLATES): link roads copy the arm's street, so the whole route between the towns is a large
-- country road. Highway arms stay the interchanges' highway (Medium), linked as two carriageways.
-- Param values are square_roundabouts' 1-based indices (docs/findings.md).
local ARM_COUNTRY_LARGE <const> = 6
logic.JUNCTION_CASES = {
	{ id = "ring", label = "Roundabout", file = "square_roundabouts.con",
		params = { sqrb_arm_type = ARM_COUNTRY_LARGE, sqrb_radius_size = 3 } },
	{ id = "magic", label = "Magic Roundabout", file = "square_roundabouts_magic.con", params = { sqrb_arm_type = ARM_COUNTRY_LARGE } },
	{ id = "channel_x", label = "Channelized X", file = "square_roundabouts_channel.con",
		params = { sqrb_ch_layout = 2, sqrb_ch_main = ARM_COUNTRY_LARGE, sqrb_ch_side = ARM_COUNTRY_LARGE } },
	{ id = "channel_t", label = "Channelized T", file = "square_roundabouts_channel.con",
		params = { sqrb_ch_layout = 1, sqrb_ch_main = ARM_COUNTRY_LARGE, sqrb_ch_side = ARM_COUNTRY_LARGE } },
	{ id = "ix_two_bridge", label = "Roundabout Interchange", file = "square_roundabouts_interchange.con",
		params = { sqrb_ix_layout = 1, sqrb_ix_cross = ARM_COUNTRY_LARGE } },
	{ id = "ix_dumbbell", label = "Dumbbell Interchange", file = "square_roundabouts_interchange.con",
		params = { sqrb_ix_layout = 2, sqrb_ix_cross = ARM_COUNTRY_LARGE } },
	{ id = "ix_peanut", label = "Peanut Interchange", file = "square_roundabouts_interchange.con",
		params = { sqrb_ix_layout = 3, sqrb_ix_cross = ARM_COUNTRY_LARGE } },
	{ id = "parclo", label = "Parclo", file = "square_roundabouts_highway_parclo.con", params = { sqrb_ix_cross = ARM_COUNTRY_LARGE } },
	{ id = "parclo2", label = "Parclo 2", file = "square_roundabouts_highway_parclo2.con", params = { sqrb_ix_cross = ARM_COUNTRY_LARGE } },
	{ id = "diamond", label = "Diamond", file = "square_roundabouts_highway_diamond.con", params = { sqrb_ix_cross = ARM_COUNTRY_LARGE } },
}
logic.JUNCTION_SETS = {
	{ label = "All types", ids = { "ring", "magic", "channel_x", "channel_t", "ix_two_bridge", "ix_dumbbell", "ix_peanut",
		"parclo", "parclo2", "diamond" } },
	{ label = "Roundabouts", ids = { "ring", "magic", "channel_x", "channel_t" } },
	{ label = "Interchanges", ids = { "ix_two_bridge", "ix_dumbbell", "ix_peanut", "parclo", "parclo2", "diamond" } },
}
-- Town spacing: a junction sits spacing x 0.71 from its towns and reaches up to ~485 m from its
-- centre (docs/findings.md "Highway street templates and interchange placement").
logic.JUNCTION_SPACINGS = { 2000, 3000, 4000, 6000, 8000 }

-- In-line junctions: extra junctions placed on each arm's link road between the cell's junction and
-- its town, every one a different layout, so traffic between two towns passes several in a row.
-- Every square_roundabouts layout has its through arms on the local x axis (the interchanges' highway
-- runs along x, square_roundabouts_highway.lua:8; ring arms at 0/90/180/270 deg, Channelized main road
-- east-west), so a stop is placed rotated to the link's direction. Road links get roundabout layouts,
-- highway links (two carriageways) interchanges; their other arms stay dead ends.
logic.JUNCTION_INLINE = { "Off", "As many as fit" }
-- Traffic lights at the junctions the test builds: the game's automatic ones, or none (the game's own
-- traffic light proposal with preference NO).
logic.JUNCTION_LIGHTS = { "Game decides", "Off" }
-- Crossing test lights: off by default (lanes alone decide), or the game's automatic ones.
logic.CROSSING_LIGHTS = { "Off", "Game decides" }
local A6 <const> = ARM_COUNTRY_LARGE
logic.INLINE_ROAD = {
	{ id = "ring1", label = "Roundabout 1 lane", file = "square_roundabouts.con", params = { sqrb_arm_type = A6, sqrb_lanes = 1, sqrb_radius_size = 3 } },
	{ id = "ring2", label = "Roundabout 2 lanes", file = "square_roundabouts.con", params = { sqrb_arm_type = A6, sqrb_lanes = 2, sqrb_radius_size = 3 } },
	{ id = "magic", label = "Magic Roundabout 2 lanes", file = "square_roundabouts_magic.con",
		params = { sqrb_arm_type = A6, sqrb_magic_size = 3, sqrb_magic_lanes = 2 } },
	{ id = "ring2s", label = "Roundabout 2 lanes, splitters", file = "square_roundabouts.con",
		params = { sqrb_arm_type = A6, sqrb_lanes = 2, sqrb_radius_size = 3, sqrb_splitter = 2 } },
	{ id = "channel_x", label = "Channelized X", file = "square_roundabouts_channel.con",
		params = { sqrb_ch_layout = 2, sqrb_ch_main = A6, sqrb_ch_side = A6 } },
	{ id = "ring4", label = "Roundabout 4 lanes", file = "square_roundabouts.con", params = { sqrb_arm_type = A6, sqrb_lanes = 3, sqrb_radius_size = 4 } },
	{ id = "oval", label = "Oval roundabout 2:1", file = "square_roundabouts.con",
		params = { sqrb_arm_type = A6, sqrb_shape = 5, sqrb_lanes = 2, sqrb_radius_size = 3 } },
	{ id = "channel_t", label = "Channelized T", file = "square_roundabouts_channel.con",
		params = { sqrb_ch_layout = 1, sqrb_ch_main = A6, sqrb_ch_side = A6 } },
	{ id = "ring_t", label = "T roundabout", file = "square_roundabouts.con", params = { sqrb_arm_type = A6, sqrb_arms = 1, sqrb_lanes = 2, sqrb_radius_size = 3 } },
	{ id = "channel_x_all", label = "Channelized X, all slips", file = "square_roundabouts_channel.con",
		params = { sqrb_ch_layout = 2, sqrb_ch_main = A6, sqrb_ch_side = A6, sqrb_ch_slips = 2, sqrb_ch_splitter = 2 } },
	{ id = "hamburger", label = "Hamburger roundabout", file = "square_roundabouts.con",
		params = { sqrb_arm_type = A6, sqrb_lanes = 2, sqrb_radius_size = 4, sqrb_centre = 2 } },
}
logic.INLINE_HIGHWAY = {
	{ id = "parclo_a", label = "Parclo A", file = "square_roundabouts_highway_parclo.con", params = { sqrb_ix_cross = A6, sqrb_hx_layout = 1 } },
	{ id = "diamond", label = "Diamond", file = "square_roundabouts_highway_diamond.con", params = { sqrb_ix_cross = A6 } },
	{ id = "ix_two_bridge", label = "Roundabout Interchange", file = "square_roundabouts_interchange.con",
		params = { sqrb_ix_layout = 1, sqrb_ix_cross = A6 } },
	{ id = "parclo_b", label = "Parclo B", file = "square_roundabouts_highway_parclo.con", params = { sqrb_ix_cross = A6, sqrb_hx_layout = 2 } },
	{ id = "ix_dumbbell", label = "Dumbbell Interchange", file = "square_roundabouts_interchange.con",
		params = { sqrb_ix_layout = 2, sqrb_ix_cross = A6 } },
	{ id = "parclo2_ab", label = "Parclo 2 AB", file = "square_roundabouts_highway_parclo2.con", params = { sqrb_ix_cross = A6, sqrb_hx_layout = 3 } },
	{ id = "ix_peanut", label = "Peanut Interchange", file = "square_roundabouts_interchange.con",
		params = { sqrb_ix_layout = 3, sqrb_ix_cross = A6 } },
}
-- Reach of a stop from its centre (arms included), the shortest link road between two junctions, and
-- how far a town reaches from its centre (x its size's spacing). Tightened 2026-10-11 for 3 km (the
-- largest spacing that fits a 16 km map with 10 junctions): 200 / 150 / 0.5 left room for one stop per
-- route with Large towns; a stop that hits the town tries spots further back (INLINE_SHIFTS).
logic.INLINE_ROAD_R = 150.0
logic.INLINE_HIGHWAY_R = 485.0
logic.INLINE_GAP = 100.0
logic.INLINE_TOWN_R = 0.35

--- Centres of the in-line junctions on the straight line a -> b ({x, y}): as many as fit, at least
--- `pitch` apart, the first at least clearA from a and the last at least clearB from b, spread evenly
--- over the free part of the line (one alone sits in its middle). At most maxN.
function logic.inlineStops(a : {number}, b : {number}, clearA : number, clearB : number, pitch : number, maxN : integer) : {{number}}
	local dx, dy = b[1] - a[1], b[2] - a[2]
	local len = math.sqrt(dx * dx + dy * dy)
	local free = len - clearA - clearB
	local out : {{number}} = {}
	if free < 0 or len <= 0 or maxN < 1 then return out end
	local n = math.min(maxN, math.floor(free / pitch) + 1)
	for k = 1, n do
		local d = n == 1 and clearA + free / 2 or clearA + free * (k - 1) / (n - 1)
		out[k] = { a[1] + dx * d / len, a[2] + dy * d / len }
	end
	return out
end

--- The cases of a set, in JUNCTION_CASES order.
function logic.junctionCases(set : SquareStressJunctionSet) : {SquareStressJunctionCase}
	local want : {string : boolean} = {}
	for _, id in ipairs(set.ids) do want[id] = true end
	local out : {SquareStressJunctionCase} = {}
	for _, c in ipairs(logic.JUNCTION_CASES) do
		if want[c.id] then out[#out + 1] = c end
	end
	return out
end

--- Town grid (cols, rows) with at least n cells: the shortest longer side first, so a wide spacing
--- still fits the map (2026-10-11: 10 junctions as 6 x 3 towns 4 km apart ran off a map's edge at
--- x = -10 km; 5 x 4 fits), then the fewest towns, then the wider.
function logic.junctionGrid(n : integer) : integer, integer
	local bestC, bestR, bestM, bestT = 1, 1, math.huge, math.huge
	n = math.max(1, n)
	for c = 1, n do
		local r = math.ceil(n / c)
		local t = (c + 1) * (r + 1)
		local m = math.max(c, r)
		if m < bestM or (m == bestM and (t < bestT or (t == bestT and c > bestC))) then
			bestC, bestR, bestM, bestT = c, r, m, t
		end
	end
	return bestC + 1, bestR + 1
end

--- The junction grid for n junctions `spacing` apart that fits a w x h map (each town centre at least
--- margin inside it): (cols, rows) of towns and the spacing used. Fitting layouts (cells c x r >= n)
--- go by the shortest longer side, then the fewest towns, then the wider. When none fits, the layout
--- that allows the widest spacing, with that spacing (whole 100 m, at least 500 m). Map size unknown
--- (w or h <= 0): junctionGrid and the spacing as asked.
function logic.fitJunctionGrid(n : integer, spacing : number, w : number, h : number, margin : number) : integer, integer, number
	n = math.max(1, n)
	if w == nil or h == nil or w <= 0 or h <= 0 then
		local c, r = logic.junctionGrid(n)
		return c, r, spacing
	end
	local W, H = w - 2 * margin, h - 2 * margin
	local bestC, bestR, bestM, bestT = 0, 0, math.huge, math.huge
	local altC, altR, altS = 1, 1, -1.0
	for c = 1, n do
		local r = math.ceil(n / c)
		-- either orientation: c cells across and r down, or the other way round
		for _, o in ipairs({ { c, r }, { r, c } }) do
			local cx, cy = o[1], o[2]
			local t = (cx + 1) * (cy + 1)
			local m = math.max(cx, cy)
			if cx * spacing <= W and cy * spacing <= H then
				if m < bestM or (m == bestM and (t < bestT or (t == bestT and cx > bestC))) then
					bestC, bestR, bestM, bestT = cx, cy, m, t
				end
			end
			local s = math.min(W / cx, H / cy)
			if s > altS then altC, altR, altS = cx, cy, s end
		end
	end
	if bestC > 0 then return bestC + 1, bestR + 1, spacing end
	return altC + 1, altR + 1, math.max(500.0, math.floor(altS / 100) * 100)
end

--- The cells of a cols x rows grid (points from gridPositions, row by row), row by row: centre and
--- corners SW, SE, NE, NW.
function logic.junctionCells(points : {SquareStressGridPoint}, cols : integer, rows : integer) : {SquareStressJunctionCell}
	local out : {SquareStressJunctionCell} = {}
	local function idx(r : integer, c : integer) : integer return (r - 1) * cols + c end
	for r = 1, rows - 1 do
		for c = 1, cols - 1 do
			local corners = { idx(r, c), idx(r, c + 1), idx(r + 1, c + 1), idx(r + 1, c) }
			local x, y = 0.0, 0.0
			for _, k in ipairs(corners) do
				x = x + points[k].x / 4
				y = y + points[k].y / 4
			end
			out[#out + 1] = { x = x, y = y, name = string.format("Cell %s%d", string.char(64 + r), c), corners = corners }
		end
	end
	return out
end

--- Text broken into lines of at most `width` characters at spaces (existing line breaks kept; a word
--- longer than the width stays whole). The game does not wrap tooltips (CLAUDE.md "Tooltips").
function logic.wrapText(text : string, width : integer) : string
	if text == nil then return nil end
	local out : {string} = {}
	for para in (text .. "\n"):gmatch("(.-)\n") do
		local line = ""
		for word in para:gmatch("%S+") do
			if line == "" then
				line = word
			elseif #line + 1 + #word <= width then
				line = line .. " " .. word
			else
				out[#out + 1] = line
				line = word
			end
		end
		out[#out + 1] = line
	end
	return table.concat(out, "\n")
end

--- "Build 10 junctions, 2 km".
function logic.junctionLabel(n : integer, spacing : number) : string
	return string.format("Build %d junction%s, %g km", n, n == 1 and "" or "s", spacing / 1000)
end

--- Groups points ({x, y}) closer than gap to another point of the group (single link), in input
--- order of their first member; each group with its centroid.
function logic.clusterEnds(ends : {{number}}, gap : number) : {SquareStressArmCluster}
	local group : {integer : integer} = {}
	local out : {SquareStressArmCluster} = {}
	for i = 1, #ends do
		if group[i] == nil then
			local cl : SquareStressArmCluster = { members = { i }, x = 0, y = 0 }
			out[#out + 1] = cl
			group[i] = #out
			local k = 1
			while k <= #cl.members do
				local a = ends[cl.members[k]]
				for j = 1, #ends do
					if group[j] == nil then
						local b = ends[j]
						if (a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 < gap * gap then
							group[j] = #out
							cl.members[#cl.members + 1] = j
						end
					end
				end
				k = k + 1
			end
			table.sort(cl.members)
			for _, m in ipairs(cl.members) do
				cl.x = cl.x + ends[m][1] / #cl.members
				cl.y = cl.y + ends[m][2] / #cl.members
			end
		end
	end
	return out
end

-- math.atan2 is in the game's Lua (base: scripts/vec3.tl:88); the offline tests run a Lua 5.3+
-- that only has the two-argument math.atan (as minimap_geom.tl).
local atan2 = math.atan2 or math.atan

local function angleDiff(a : number, b : number) : number
	local d = math.abs(a - b) % (2 * math.pi)
	if d > math.pi then d = 2 * math.pi - d end
	return d
end

--- The direction of an arm (cluster) in radians: its measured heading (cl.hx, cl.hy: the way its
--- road leaves the junction, read from the end edges) when known, else from (cx, cy) to it.
local function armAngle(cx : number, cy : number, cl : SquareStressArmCluster) : number
	if cl.hx ~= nil and cl.hy ~= nil and (cl.hx ~= 0 or cl.hy ~= 0) then return atan2(cl.hy, cl.hx) end
	return atan2(cl.y - cy, cl.x - cx)
end

--- The direction from an arm (its end when it has a measured heading, else the junction centre) to
--- a corner point.
local function cornerAngle(cx : number, cy : number, cl : SquareStressArmCluster, c : {number}) : number
	if cl.hx ~= nil and cl.hy ~= nil and (cl.hx ~= 0 or cl.hy ~= 0) then return atan2(c[2] - cl.y, c[1] - cl.x) end
	return atan2(c[2] - cy, c[1] - cx)
end

--- Arm (cluster) index -> corner index: the best matching direction first, each corner once, at
--- most maxDeg degrees apart. An arm with a measured heading (cl.hx, cl.hy) is matched by that
--- heading against the direction from its end to the corner (2026-10-12: an oval's arms leave the
--- ring up to 33 deg off their nominal direction); else by its direction seen from (cx, cy). Arms
--- left over stay unlinked.
function logic.assignArms(cx : number, cy : number, clusters : {SquareStressArmCluster}, corners : {{number}}, maxDeg : number) : {integer : integer}
	local pairs_ : {{number}} = {}
	for i, cl in ipairs(clusters) do
		local a = armAngle(cx, cy, cl)
		for k, c in ipairs(corners) do
			local d = angleDiff(a, cornerAngle(cx, cy, cl, c))
			if d <= math.rad(maxDeg) then pairs_[#pairs_ + 1] = { d, i, k } end
		end
	end
	table.sort(pairs_, function(p : {number}, q : {number}) : boolean
		if p[1] ~= q[1] then return p[1] < q[1] end
		if p[2] ~= q[2] then return p[2] < q[2] end
		return p[3] < q[3]
	end)
	local out : {integer : integer} = {}
	local used : {integer : boolean} = {}
	for _, p in ipairs(pairs_) do
		local i, k = math.floor(p[2]), math.floor(p[3])
		if out[i] == nil and not used[k] then
			out[i] = k
			used[k] = true
		end
	end
	return out
end

--- The corners assignArms left without an arm, each given the free arm nearest its direction (any
--- angle), best match first: {arm index, corner index, degrees off}. Adds them to `assigned`.
--- skip: corners that take no arm (Showcase: towns skipped for want of land).
function logic.assignLeftovers(cx : number, cy : number, clusters : {SquareStressArmCluster}, corners : {{number}},
		assigned : {integer : integer}, skip? : {integer : boolean}) : {{number}}
	local used : {integer : boolean} = {}
	for _, k in pairs(assigned) do used[k] = true end
	for k in pairs(skip or {}) do used[k] = true end
	local cand : {{number}} = {}
	for i, cl in ipairs(clusters) do
		if assigned[i] == nil then
			local a = armAngle(cx, cy, cl)
			for k, c in ipairs(corners) do
				if not used[k] then cand[#cand + 1] = { angleDiff(a, cornerAngle(cx, cy, cl, c)), i, k } end
			end
		end
	end
	table.sort(cand, function(p : {number}, q : {number}) : boolean
		if p[1] ~= q[1] then return p[1] < q[1] end
		if p[2] ~= q[2] then return p[2] < q[2] end
		return p[3] < q[3]
	end)
	local out : {{number}} = {}
	for _, p in ipairs(cand) do
		local i, k = math.floor(p[2]), math.floor(p[3])
		if assigned[i] == nil and not used[k] then
			assigned[i] = k
			used[k] = true
			out[#out + 1] = { i, k, math.deg(p[1]) }
		end
	end
	return out
end

--- Points from p0 to p1 (both included) on the straight line, at most maxSeg apart; 3D points keep
--- the interpolated z.
function logic.linePoints(p0 : {number}, p1 : {number}, maxSeg : number) : {{number}}
	local len = math.sqrt((p1[1] - p0[1]) ^ 2 + (p1[2] - p0[2]) ^ 2)
	local n = math.max(1, math.ceil(len / maxSeg))
	local out : {{number}} = {}
	for i = 0, n do
		local t = i / n
		out[#out + 1] = { p0[1] + (p1[1] - p0[1]) * t, p0[2] + (p1[2] - p0[2]) * t, (p0[3] or 0) + ((p1[3] or 0) - (p0[3] or 0)) * t }
	end
	out[1], out[#out] = p0, p1
	return out
end

--- 2D distance from p to the segment a-b.
function logic.distToSegment(p : {number}, a : {number}, b : {number}) : number
	local dx, dy = b[1] - a[1], b[2] - a[2]
	local l2 = dx * dx + dy * dy
	local t = 0.0
	if l2 > 0 then t = math.max(0, math.min(1, ((p[1] - a[1]) * dx + (p[2] - a[2]) * dy) / l2)) end
	local qx, qy = a[1] + t * dx, a[2] + t * dy
	return math.sqrt((p[1] - qx) ^ 2 + (p[2] - qy) ^ 2)
end

-- Only dead ends (one street edge): a link replaces the node it joins and every edge at it, and the
-- one crash (2026-10-11, sim thread "BaseNodeConfig" assert on a node being added) came with the first
-- link to a node with more than one edge (a wide grid corner); every dead-end link had worked.
local AVOID_ROAD <const> = 8.0

--- Whether a street template (BaseEdge.roadTemplate) is a large two-way town or country street
--- (town_new_large, country_old_large_bus, ...: 4 lanes), not a highway or a one-way street.
function logic.isLargeStreet(template : string) : boolean
	if type(template) ~= "string" then return false end
	local base = template:match("([^/:]+)$") or template
	if base:find("highway", 1, true) or base:find("one_way", 1, true) then return false end
	return base:match("^town_%a+_large[%w_]*%.street_template$") ~= nil
		or base:match("^country_%a+_large[%w_]*%.street_template$") ~= nil
end

-- Bus route lines (Showcase): stops and depot connections only on the route's own town streets.
-- 2026-10-12 (seed 488838, user screenshot): a depot of the 700-1200 m ring was built beside a Roundabout
-- Interchange next to its highway ramp (getClosestTown still named the town), with the red no-entry sign at
-- its gate, and findBestDepotForLine found no depot for the line.
logic.BUS_ZONE_MARGIN = 100.0   -- m beyond a junction zone's radius (its reach estimate) kept free
logic.BUS_TOWN_MARGIN = 15.0    -- m beyond the street grid's outer streets (their centre lines)

--- Why a street edge (template = BaseEdge.roadTemplate, p0/p1 its end positions) may not carry a bus stop
--- or a depot connection, nil when it may: "highway", "oneway" (either: a two-way stub can't join it the
--- right way), "not_town" (townOnly: not a town street template), "outside_town" (town.half set: an end
--- outside the town's square street grid + BUS_TOWN_MARGIN: link roads, junction arms), "zone" (within a
--- junction zone {x, y, r} + BUS_ZONE_MARGIN). An empty or nil template skips the template checks.
function logic.busEdgeReject(template : string, p0 : {number}, p1 : {number}, town : SquareStressTownPos, zones : {{number}},
		townOnly : boolean) : string
	if type(template) == "string" and template ~= "" then
		local base = template:match("([^/:]+)$") or template
		if base:find("highway", 1, true) then return "highway" end
		if base:find("one_way", 1, true) then return "oneway" end
		if townOnly and base:match("^town_") == nil then return "not_town" end
	end
	if town ~= nil and type(town.half) == "number" then
		local lim = town.half + logic.BUS_TOWN_MARGIN
		for _, p in ipairs({ p0, p1 }) do
			if math.abs(p[1] - town.x) > lim or math.abs(p[2] - town.y) > lim then return "outside_town" end
		end
	end
	for _, z in ipairs(zones or {}) do
		if logic.distToSegment({ z[1], z[2] }, p0, p1) < (z[3] or 0) + logic.BUS_ZONE_MARGIN then return "zone" end
	end
	return nil
end

--- Half-size (m) of the wide street grid of a town of TOWN_SIZES index `size` (nil: Small).
function logic.gridHalfOfSize(size : integer) : number
	local s = logic.TOWN_SIZES[size or 1] or logic.TOWN_SIZES[1]
	return logic.GRID_STREET_HALF[logic.gridStreetHalf(s.caps)]
end

-- A town node on a large street is taken before nearer ones on small streets up to this much further
-- from the arm (2026-10-11 Showcase: a highway's link joined the town on a small street, so all its
-- traffic squeezed through it; a node much further away would cross the town instead).
logic.LARGE_PREFER = 400.0

--- Town nodes an arm may be linked to, best first: within maxR of the town centre, dead ends (one
--- street edge), not on one of our earlier link roads (avoid: {{a, b}} segments); score = distance
--- to the arm. Nodes on a large street (cand.large) come first when at most LARGE_PREFER further
--- than the nearest node, unless noLarge (Showcase: after a link refused with a collision, the
--- nearest node, the shortest road through the fewest town streets).
function logic.rankTownNodes(cands : {SquareStressNodeCand}, arm : {number}, town : {number}, maxR : number,
		avoid : {{{number}}}, noLarge? : boolean) : {SquareStressNodeCand}
	local out : {SquareStressNodeCand} = {}
	for _, c in ipairs(cands) do
		local p = { c.x, c.y }
		local ok = c.deg == 1 and (c.x - town[1]) ^ 2 + (c.y - town[2]) ^ 2 <= maxR * maxR
		if ok then
			for _, seg in ipairs(avoid or {}) do
				if logic.distToSegment(p, seg[1], seg[2]) < AVOID_ROAD then ok = false break end
			end
		end
		if ok then
			c.score = math.sqrt((c.x - arm[1]) ^ 2 + (c.y - arm[2]) ^ 2)
			out[#out + 1] = c
		end
	end
	local best = math.huge
	for _, c in ipairs(out) do best = math.min(best, c.score) end
	local first : {SquareStressNodeCand : boolean} = {}
	for _, c in ipairs(out) do first[c] = not noLarge and c.large == true and c.score <= best + logic.LARGE_PREFER end
	table.sort(out, function(a : SquareStressNodeCand, b : SquareStressNodeCand) : boolean
		if first[a] ~= first[b] then return first[a] end
		if a.score ~= b.score then return a.score < b.score end
		return a.id < b.id
	end)
	return out
end

---------------------------------------------------------------------------
-- Remove roads (Towns tab; gui/stress_roads.tl): street edges in batches of a SimpleProposal's
-- edgesToRemove + the nodes they leave without edges, as square_bulk_bulldozer's bb_commit does.

logic.ROAD_BATCH = 100       -- street edges per removal proposal (a failed batch is split in half)

--- Every street edge once, sorted, from streetSystem.getNode2StreetEdgeMap() (each edge is listed
--- under both its nodes; docs/findings.md "Stress Test probes").
function logic.uniqueEdges(node2edges : {integer : {integer}}) : {integer}
	local seen : {integer : boolean} = {}
	local out : {integer} = {}
	for _, list in pairs(node2edges or {}) do
		for _, e in ipairs(list) do
			if not seen[e] then
				seen[e] = true
				out[#out + 1] = e
			end
		end
	end
	table.sort(out)
	return out
end

--- list split into consecutive chunks of at most n.
function logic.chunk(list : {integer}, n : integer) : {{integer}}
	local out : {{integer}} = {}
	for i, v in ipairs(list or {}) do
		local k = math.floor((i - 1) / n) + 1
		if out[k] == nil then out[k] = {} end
		local c = out[k]
		c[#c + 1] = v
	end
	return out
end

--- The nodes a removal leaves without any segment: every node whose segment count (degree, read
--- fresh) is covered by the removed edges' ends and that belongs to no construction (frozen).
--- Unknown degree = kept. Same rule as square_bulk_bulldozer bb_batch.orphanNodes.
function logic.orphanNodes(edgeEnds : {{integer}}, degree : {integer : integer}, frozen : {integer : boolean}) : {integer}
	local removed : {integer : integer} = {}
	for _, ends in ipairs(edgeEnds or {}) do
		for k = 1, 2 do
			local n = ends[k]
			if n ~= nil and n >= 0 then removed[n] = (removed[n] or 0) + 1 end
		end
	end
	local out : {integer} = {}
	for n, cnt in pairs(removed) do
		local d = degree ~= nil and degree[n] or nil
		if d ~= nil and cnt >= d and not (frozen ~= nil and frozen[n] == true) then out[#out + 1] = n end
	end
	table.sort(out)
	return out
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

---------------------------------------------------------------------------
-- Traffic through the Junction test and the Crossing test (PHASE7.md step 6 of square_smart_lanes): after
-- the build, one bus line between two test towns per route through the junctions (stress_buslines
-- addRouteLines), with the Auto bus lines "Buses" count per line.

logic.TEST_TRAFFIC = { "Off", "Bus lines" }
logic.TEST_ROUTES_MAX = 40                     -- bus lines per test run at most

--- Junction test routes: per cell its two diagonals (corners SW-NE and SE-NW, so both lines drive
--- straight through the cell's junction and cross each other there) whose arms both reached their towns.
--- linked: cell name -> set of corner positions (1..4, junctionCells' order) whose arm got its town link.
--- Returns {gridIndexA, gridIndexB, cell index} pairs in cell order, at most maxN.
function logic.cellRoutes(cells : {SquareStressJunctionCell}, linked : {string : {integer : boolean}}, maxN : integer) : {{integer}}
	local out : {{integer}} = {}
	for ci, cell in ipairs(cells or {}) do
		local set = linked and linked[cell.name] or nil
		if set ~= nil and cell.corners ~= nil then
			for _, d in ipairs({ { 1, 3 }, { 2, 4 } }) do
				if set[d[1]] and set[d[2]] and #out < maxN then
					out[#out + 1] = { cell.corners[d[1]], cell.corners[d[2]], ci }
				end
			end
		end
	end
	return out
end

--- Crossing test routes between its towns (crossingLayout order W, E, N, S): straight across the grid
--- (W-E, N-S), then turning (W-N, E-S); only towns whose link was built (linked: town index -> true).
function logic.crossingRoutes(linked : {integer : boolean}) : {{integer}}
	local out : {{integer}} = {}
	for _, pr in ipairs({ { 1, 2 }, { 3, 4 }, { 1, 3 }, { 2, 4 } }) do
		if linked ~= nil and linked[pr[1]] and linked[pr[2]] then out[#out + 1] = { pr[1], pr[2] } end
	end
	return out
end

--- The one-line in-game summary of a test run, e.g. "Junction test done: 12 of 12 junctions built,
--- 47 of 48 links; 24 bus lines queued." lines nil: Traffic Off (no clause); 0: no route to serve.
function logic.testSummary(title : string, built : integer, total : integer, what : string, linked : integer, links : integer,
		lines : integer) : string
	local s = string.format("%s done: %d of %d %s built, %d of %d links", title, built, total, what, linked, links)
	if lines ~= nil then
		if lines > 0 then
			s = s .. string.format("; %d bus line%s queued", lines, lines == 1 and "" or "s")
		else
			s = s .. "; no bus lines (no route with both towns linked)"
		end
	end
	return s .. "."
end

--- "Add 1 bus line to the nearest town", "Add 2 bus lines each to 5 towns", "... to all towns (max 25)".
function logic.busLinesLabel(choice : integer, lines : integer) : string
	local what = string.format("Add %d bus line%s", lines, lines == 1 and "" or "s")
	if choice == 1 then return what .. " to the nearest town" end
	if choice == 2 then return what .. string.format(" each to %d towns", logic.BUS_TOWN_COUNTS[2]) end
	return what .. string.format(" each to all towns (max %d)", logic.BUS_TOWN_COUNTS[3])
end

---------------------------------------------------------------------------
-- Showcase (Towns tab; gui/stress_junctions.tl jn.buildShowcase, needs square_roundabouts,
-- plans/square_stress_test/SHOWCASE.md "Showcase v2: groups only"): one button. Groups only: per group
-- one junction with a Medium town on every arm, close around it; groups are joined to nothing else.
-- The group types take turns by kind (interchange, roundabout, plain game crossing), each kind cycling
-- through its own types, with random params, rotation (and for plain crossings the lights) from a
-- seeded PRNG; as many groups as fit the map. Town size is fixed per spec (user 2026-10-12).

-- A small deterministic PRNG (Park-Miller "minimal standard", multiplier 48271): every product stays
-- below 2^53, so it is exact in the game's Lua 5.1 doubles and in the tests' Lua 5.4 integers. No
-- math.random: its state is shared with every other script of the GUI state.
local RNG_M <const> = 2147483647

--- A generator from any number (0 and negatives included); the same seed gives the same sequence.
function logic.newRng(seed : number) : SquareStressRng
	local s = math.floor(math.abs(seed or 0)) % (RNG_M - 1)
	if s == 0 then s = 1 end
	return { state = s }
end

--- The next raw value, 1 .. 2^31 - 2.
function logic.rngNext(rng : SquareStressRng) : integer
	rng.state = math.floor(rng.state * 48271 % RNG_M)
	return rng.state
end

--- A whole number 1 .. n.
function logic.rngInt(rng : SquareStressRng, n : integer) : integer
	if n <= 1 then return 1 end
	return math.floor((logic.rngNext(rng) - 1) / (RNG_M - 1) * n) + 1
end

--- The seed of a new run from a clock reading (seconds or microseconds): 1 .. 999999, so it is short
--- enough to note down from the log.
function logic.showcaseSeed(clock : number) : integer
	return math.floor(math.abs(clock or 0)) % 999999 + 1
end

logic.SHOWCASE_GAP = 100.0        -- a town's clearance beyond its streets (to the junction, to the group's other towns)
logic.SHOWCASE_IX_R = 505.0       -- the largest interchange reach showcaseReach gives (a Parclo at scale 3)
logic.SHOWCASE_RB_MAX = 315.0     -- the largest roundabout reach showcaseReach gives
logic.SHOWCASE_TOWN_R = 0.35      -- a town's streets reach its size's spacing x this (INLINE_TOWN_R)
-- One town size for every town of a spec, never drawn (user 2026-10-12: consistent towns; Medium keeps
-- more groups on the map). TOWN_SIZES index.
logic.SHOWCASE_SIZE = 2           -- TOWN_SIZES: Medium
logic.SHOWCASE_STEP = 100.0       -- the fit scan's row step (m)
logic.SHOWCASE_MAX_GROUPS = 80    -- safety cap (twins each counted; a set that would pass it is not added)
logic.SHOWCASE_MISSES = 3         -- a kind stops after this many draws in a row that fit nowhere
-- Kinds in turn (interchange, roundabout, plain), so a small map still gets every kind; the names
-- are the zone lines' kind= values and the summary's words.
logic.SHOWCASE_KINDS = { "ix", "rb", "plain" }
logic.SHOWCASE_KIND_NAMES = { ix = "interchange", rb = "roundabout", plain = "plain" }
-- Twins (user 2026-10-12): every group is built side by side once per A/B mode, with identical draws
-- (type, params, rotation; one town size; towns share GRID_SEED), so Smart Lanes vs the game default can
-- be compared on one map at the same time. ab: the mode tag of the zone lines, also sent to Smart Lanes
-- before the build (gui/stress_slzones.tl), which treats each zone by it; twin: the letter after the group number; litPlainOnly: only for a
-- group whose junction is a plain crossing with lights (the game's AUTO). Change the list here.
logic.SHOWCASE_AB = {
	{ ab = "sl", twin = "a", label = "Smart lanes", note = "Smart Lanes lanes, current light behaviour" },
	{ ab = "game", twin = "b", label = "Game default", note = "game default lanes and lights (Smart Lanes leaves it alone)" },
	{ ab = "sl_phases", twin = "c", label = "Smart phases", note = "Smart Lanes lanes and light phases", litPlainOnly = true },
} as {SquareStressShowcaseAb}

local function seq(a : integer, b : integer) : {integer}
	local out : {integer} = {}
	for v = a, b do out[#out + 1] = v end
	return out
end

-- Ranges are the constructions' own value lists (square_roundabouts .con.lua / highway_menu.lua params,
-- 1-based indices), all of them except: Direction / Traffic side (right-hand traffic only: a left-hand
-- layout in a right-hand game has its one-way roads the wrong way), Arms "None" (nothing to link), and
-- "Through the centre" only on the Hamburger type (with 3 (T), 4 or 6 arms: those have an opposite pair,
-- so no extra arm is added and the arm directions stay known). Interchanges keep their cross road a
-- large country road (armKey sqrb_ix_cross = 6: user 2026-10-12, the cross-road arms reach their
-- towns by a large country road; the link copies the arm's street).
local RING_COMMON : {SquareStressShowcaseRange} = {
	{ key = "sqrb_lanes", values = seq(1, 3) },
	{ key = "sqrb_radius_size", values = seq(1, 5) },
	{ key = "sqrb_arms", values = seq(1, 5) },
	{ key = "sqrb_splitter", values = seq(1, 2) },
	{ key = "sqrb_tram", values = seq(1, 2) },
	{ key = "sqrb_signals", values = seq(1, 2) },
	{ key = "sqrb_island", values = seq(1, 5) },
}
local function withRanges(first : {SquareStressShowcaseRange}, rest : {SquareStressShowcaseRange}) : {SquareStressShowcaseRange}
	local out : {SquareStressShowcaseRange} = {}
	for _, r in ipairs(first) do out[#out + 1] = r end
	for _, r in ipairs(rest) do out[#out + 1] = r end
	return out
end
local CHANNEL : {SquareStressShowcaseRange} = {
	{ key = "sqrb_ch_scale", values = seq(1, 5) },
	{ key = "sqrb_ch_side", values = seq(1, 6) },
	{ key = "sqrb_ch_slips", values = seq(1, 3) },
	{ key = "sqrb_ch_splitter", values = seq(1, 2) },
	{ key = "sqrb_ch_arm_length", values = seq(1, 4) },
	{ key = "sqrb_ch_island", values = seq(1, 3) },
}
local IX : {SquareStressShowcaseRange} = {
	{ key = "sqrb_ix_highway", values = seq(1, 3) },
	{ key = "sqrb_ix_level", values = seq(1, 2) },
	{ key = "sqrb_lanes", values = seq(1, 3) },
	{ key = "sqrb_ix_radius_size", values = seq(1, 4) },
	{ key = "sqrb_ix_slip_length", values = seq(1, 4) },
	{ key = "sqrb_ix_arm_length", values = seq(1, 4) },
	{ key = "sqrb_island", values = seq(1, 5) },
}
local HX : {SquareStressShowcaseRange} = {
	{ key = "sqrb_ix_highway", values = seq(1, 3) },
	{ key = "sqrb_hx_level", values = seq(1, 2) },
	{ key = "sqrb_hx_scale", values = seq(1, 3) },
	{ key = "sqrb_hx_ramp", values = seq(1, 3) },
	{ key = "sqrb_hx_arm_length", values = seq(1, 3) },
}
local IX_CROSS <const> = "sqrb_ix_cross"
logic.SHOWCASE_IX_CROSS = 6       -- the interchanges' cross road: Country large

--- Interchange types, in build order.
logic.SHOWCASE_IX_TYPES = {
	{ id = "ix_two_bridge", label = "Roundabout Interchange", file = "square_roundabouts_interchange.con", kind = "ix",
		armKey = IX_CROSS, fixed = { sqrb_ix_layout = 1 }, ranges = IX },
	{ id = "parclo", label = "Parclo", file = "square_roundabouts_highway_parclo.con", kind = "ix", armKey = IX_CROSS, fixed = {},
		ranges = withRanges({ { key = "sqrb_hx_layout", values = seq(1, 2) } }, HX) },
	{ id = "ix_dumbbell", label = "Dumbbell Interchange", file = "square_roundabouts_interchange.con", kind = "ix",
		armKey = IX_CROSS, fixed = { sqrb_ix_layout = 2 }, ranges = IX },
	{ id = "parclo2", label = "Parclo, two quadrants", file = "square_roundabouts_highway_parclo2.con", kind = "ix", armKey = IX_CROSS,
		fixed = {}, ranges = withRanges({ { key = "sqrb_hx_layout", values = seq(1, 3) } }, HX) },
	{ id = "ix_peanut", label = "Peanut Interchange", file = "square_roundabouts_interchange.con", kind = "ix",
		armKey = IX_CROSS, fixed = { sqrb_ix_layout = 3 }, ranges = IX },
	{ id = "diamond", label = "Diamond", file = "square_roundabouts_highway_diamond.con", kind = "ix", armKey = IX_CROSS, fixed = {},
		ranges = HX },
} as {SquareStressShowcaseType}

--- Roundabout types, in build order. armKey: the arm road param (drawn, 1-6).
logic.SHOWCASE_RB_TYPES = {
	{ id = "ring", label = "Roundabout", file = "square_roundabouts.con", kind = "rb", armKey = "sqrb_arm_type",
		fixed = { sqrb_shape = 1, sqrb_centre = 1 }, ranges = RING_COMMON },
	{ id = "magic", label = "Magic Roundabout", file = "square_roundabouts_magic.con", kind = "rb", armKey = "sqrb_arm_type",
		fixed = {}, ranges = {
			{ key = "sqrb_magic_size", values = seq(1, 5) },
			{ key = "sqrb_magic_lanes", values = seq(1, 2) },
			{ key = "sqrb_island", values = seq(1, 5) },
		} },
	{ id = "channel_t", label = "Channelized T", file = "square_roundabouts_channel.con", kind = "rb", armKey = "sqrb_ch_main",
		fixed = { sqrb_ch_layout = 1 }, ranges = CHANNEL },
	{ id = "oval", label = "Oval roundabout", file = "square_roundabouts.con", kind = "rb", armKey = "sqrb_arm_type",
		fixed = { sqrb_centre = 1 }, ranges = withRanges({ { key = "sqrb_shape", values = seq(2, 5) } }, RING_COMMON) },
	{ id = "channel_x", label = "Channelized X", file = "square_roundabouts_channel.con", kind = "rb", armKey = "sqrb_ch_main",
		fixed = { sqrb_ch_layout = 2 }, ranges = CHANNEL },
	{ id = "hamburger", label = "Hamburger roundabout", file = "square_roundabouts.con", kind = "rb", armKey = "sqrb_arm_type",
		fixed = {}, ranges = {
			{ key = "sqrb_shape", values = seq(1, 5) },
			{ key = "sqrb_lanes", values = seq(1, 3) },
			{ key = "sqrb_radius_size", values = seq(1, 5) },
			{ key = "sqrb_arms", values = { 1, 3, 5 } },
			{ key = "sqrb_splitter", values = seq(1, 2) },
			{ key = "sqrb_centre", values = { 2, 4 } },
			{ key = "sqrb_through_road", values = seq(1, 7) },
			{ key = "sqrb_tram", values = seq(1, 2) },
			{ key = "sqrb_signals", values = seq(1, 2) },
			{ key = "sqrb_island", values = seq(1, 5) },
		} },
} as {SquareStressShowcaseType}

-- Plain game crossings: the Crossing test's own construction (stress_crossing.lua: ROADS 1-6 two-way
-- town / country small / medium / large, 7-8 one-way; ANGLES; main2 / side2 1 = the first arm's road,
-- k + 1 = ROADS[k]). The side road is drawn one-way 1 time in 7 (X only: both side arms one way
-- through, sqst_x_side2 then the same road), so traffic can only cross it one way and its two towns
-- get no bus line. A T's side arm stays two-way (its town would be a dead end one way).
logic.SHOWCASE_PLAIN_FILE = "square_stress_test_crossing.con"
logic.SHOWCASE_PLAIN_ANGLES = { 90, 60, 75, 105, 120 }   -- stress_crossing.ANGLES (degrees; arms at least 60 apart)
local PLAIN_SIDE_X : {integer} = { 1, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5, 6, 7, 8 }
logic.SHOWCASE_PLAIN_TYPES = {
	{ id = "crossroads", label = "Crossroads", file = logic.SHOWCASE_PLAIN_FILE, kind = "plain", fixed = { sqst_x_shape = 1 }, ranges = {
		{ key = "sqst_x_angle", values = seq(1, 5) },
		{ key = "sqst_x_main", values = seq(1, 6) },
		{ key = "sqst_x_main2", values = seq(1, 7) },
		{ key = "sqst_x_side", values = PLAIN_SIDE_X },
		{ key = "sqst_x_side2", values = seq(1, 7) },
	} },
	{ id = "t_junction", label = "T-junction", file = logic.SHOWCASE_PLAIN_FILE, kind = "plain", fixed = { sqst_x_shape = 2 }, ranges = {
		{ key = "sqst_x_angle", values = seq(1, 5) },
		{ key = "sqst_x_main", values = seq(1, 6) },
		{ key = "sqst_x_main2", values = seq(1, 7) },
		{ key = "sqst_x_side", values = seq(1, 6) },
	} },
} as {SquareStressShowcaseType}
local PLAIN_ONE_WAY <const> = 7   -- stress_crossing.ROADS from here on are one-way

-- Short type words for town names (showcaseTownName; user 2026-10-12: names <= ~30 characters).
local SHOWCASE_SHORT : {string : string} = {
	ix_two_bridge = "Ring IX", parclo = "Parclo", ix_dumbbell = "Dumbbell", parclo2 = "Parclo 2Q", ix_peanut = "Peanut",
	diamond = "Diamond", ring = "Roundabout", magic = "Magic RB", channel_t = "Channel T", oval = "Oval RB",
	channel_x = "Channel X", hamburger = "Hamburger", crossroads = "Crossroads", t_junction = "T-junction",
}
for _, list in ipairs({ logic.SHOWCASE_IX_TYPES, logic.SHOWCASE_RB_TYPES, logic.SHOWCASE_PLAIN_TYPES }) do
	for _, t in ipairs(list) do t.short = SHOWCASE_SHORT[t.id] end
end

--- The type lists by kind.
function logic.showcaseTypes(kind : string) : {SquareStressShowcaseType}
	if kind == "ix" then return logic.SHOWCASE_IX_TYPES end
	if kind == "rb" then return logic.SHOWCASE_RB_TYPES end
	if kind == "plain" then return logic.SHOWCASE_PLAIN_TYPES end
	return {}
end

-- Lights showcase (user request 2026-10-12, SHOWCASE.md "Lights showcase"): only lit plain crossings, every
-- arm two-way, the light asked for at the centre node (sqst_x_lights 2 = Yes: the construction lists it in
-- trafficLightYes and trafficLightNodePreference, stress_crossing.lua). Exact square layout (SHOWCASE.md
-- "Square layout"): the side road at 90 deg (sqst_x_angle 1), never turned. Every arm a COUNTRY road
-- (country = true streets get no houses, wiki modding/infrastructure/tracksstreets.md "country"), so the
-- town never lines or branches off the junction's own arms.
-- ONE junction shape per press, the same in every set (user 2026-10-12, SHOWCASE.md "Faster, simpler
-- Lights showcase"); the shape cycles per press (jn.buildLightsShowcase's session counter). Lanes per
-- direction -> the crossing construction's roads (stress_crossing.ROADS): 2 = Country medium (5), 3 =
-- Country large (6); main2 / side2 1 = the same road on both arms. "3x2 X": main road 3 lanes each way,
-- side road 2. "T 2x2": shape 2 (side road towards +y only), both roads 2 lanes each way.
local function litShape(id : string, label : string, slot : string, shape : integer, main : integer, side : integer) : SquareStressShowcaseType
	local fixed : {string : number} = { sqst_x_shape = shape, sqst_x_lights = 2, sqst_x_angle = 1, sqst_x_main = main, sqst_x_main2 = 1,
		sqst_x_side = side }
	if shape ~= 2 then fixed.sqst_x_side2 = 1 end
	return { id = id, label = label, file = logic.SHOWCASE_PLAIN_FILE, kind = "plain", slot = slot, fixed = fixed, ranges = {} }
end
logic.LIGHTS_SHAPES = {
	litShape("lit_x22", "2x2 X", "x", 1, 5, 5),
	litShape("lit_x33", "3x3 X", "x", 1, 6, 6),
	litShape("lit_x32", "3x2 X", "x", 1, 6, 5),
	litShape("lit_t22", "T 2x2", "t", 2, 5, 5),
} as {SquareStressShowcaseType}
-- Its twins: every A/B mode, and Smart Lanes' kerb-locked mode (sl_lock: Smart Lanes lanes, the game's phases,
-- the kerb turn always locked; user 2026-10-13: replaces the full fan twin sl_fan, which the Lights showcase no
-- longer builds; sl_fan stays accepted everywhere else). sl_lock vs game measures the lane layout alone, sl vs
-- sl_lock the free kerb turn alone (tools/flow_report.py). Letter d as stress_flow's TWIN_LETTER. Built in letter
-- order a, b, c, d (the traffic log's fallback twin ids follow it).
logic.LIGHTS_AB = {
	{ ab = "sl", twin = "a", label = "Smart lanes", note = "Smart Lanes lanes, current light behaviour" },
	{ ab = "game", twin = "b", label = "Game default", note = "game default lanes and lights (Smart Lanes leaves it alone)" },
	{ ab = "sl_phases", twin = "c", label = "Smart phases", note = "Smart Lanes lanes and light phases", litPlainOnly = true },
	{ ab = "sl_lock", twin = "d", label = "Kerb locked", note = "Smart Lanes lanes, game phases, kerb turn always locked", litPlainOnly = true },
} as {SquareStressShowcaseAb}
-- Smart Lanes' exit-lane fan mode (sl_exitfan, 2026-10-13: its lanes, every turn fanned into the exit lanes it can
-- reach at a lit crossroads / T-junction, the game's phases; sl vs sl_exitfan = the fan alone). Letter e (d stays
-- sl_lock / sl_fan). The mixed Lights showcase's third twin.
logic.LIGHTS_EXITFAN_AB = { ab = "sl_exitfan", twin = "e", label = "Exit fan", note = "Smart Lanes lanes, turns fanned into the exit lanes, game phases",
	litPlainOnly = true } as SquareStressShowcaseAb
-- Medium too (user 2026-10-12: Medium 8 x 8 blocks; more people from density, not a bigger grid:
-- LIGHTS_GROW_FACTOR)
logic.LIGHTS_SIZE = 2             -- TOWN_SIZES: Medium, every town

---------------------------------------------------------------------------
-- Town growth locked into the grid (Showcase and Lights showcase; SHOWCASE.md "Town growth locked into
-- the grid"). Every street of a Showcase town is roadDevelopmentLocked (docs/findings/towns.md "Locked
-- town streets still get houses; the town stops branching off them"), its unused corner stubs removed,
-- its size factors raised and its building levels shifted up (makeTownCustomDistributionWeightsCmd,
-- api cmd.d.tl:845-850: per land use (residential, commercial, industrial) four level weights 0..1, as the
-- town editor's sliders, base town_eow.script.tl:660-812, which never lets all four be 0).

logic.LOCK_BATCH = 100           -- street edges per lock proposal (one in flight)
logic.LOCK_MAX_PASS = 400        -- at most this many edges per town per pass (the rest the next pass)
logic.LOCK_RETRY_MS = 3000       -- a refused lock batch is rebuilt from fresh reads and sent once more this much later
logic.LOCK_MARGIN = 20.0         -- a street is inside the grid up to this far beyond its outer streets
logic.HOUSE_MARGIN = 45.0        -- a house is inside up to this far beyond them (4 parcels of 8 m + half a street)
logic.LOCK_REACH = 300.0         -- a town's streets are looked for this far beyond its grid's corners
-- Around each Showcase junction (its zone: centre and measured reach) every street within this much more
-- is locked in every lock pass and leak check, whatever town is closest (the crossing's own arms and
-- anything a town hung on them; user 2026-10-12: a town grew a block of streets around a crossing off its
-- unlinked arm). Logged as zone_streets= (unlocked ones found).
logic.ZONE_LOCK_MARGIN = 150.0
logic.STUB_TOL = 3.0             -- a corner stub's inner end lies within this of a grid corner
logic.DENSE_GROW_FACTOR = 10.0   -- after the links every town grows x10 (GROW_FACTORS[3]) ...
logic.DENSE_GROW_PASSES = 3      -- ... in 3 build-out passes (GROW_PASSES[2])
logic.DENSE_WEIGHTS = { 0.0, 0.1, 0.5, 1.0 }   -- level 1..4 capacity weights, every land use
-- A town's population is its residential person capacity (the game's own: company_util.computeWorldPopulation
-- sums getTown2personCapacitiesMap()[town][1]; the town window's TownPopulationWidget shows the residential
-- capacity). A forced size command (makeTownUpdateSizeCmd(town, f, true)) aims at initialLandUseCapacities x f;
-- the town filled about GROW_FILL of the residential target within 5-30 s (probe 2026-10-10, log session
-- 2026-10-10_0544_grow-x100-crash: initCaps 100 x10 -> residential 836 and 836 at +5 s / +30 s; an older town on
-- a crowded map, Tacoma 233 x10 -> 1347, 58 %). Lights showcase x3, 96 Medium towns (initCaps 400; log sessions
-- 2026-10-13_0118_top-up-148916 and 2026-10-13_0205_top-up-61157): mean 939 of 1200 targeted = 0.78 (326-1198),
-- the same at the size command's answer and minutes later; and per town the population came out at its residents
-- at creation (createTowns personCaps, ~3.5 min before the command) x 3.1 (median; quartiles 3.0 / 3.2, 2.7-4.2;
-- before: 122-399, mean 301), capped at the initial capacity x 3 (20 towns at 1150-1200). That "x pop" reading was
-- wrong: session 2026-10-13_0356_top-up-779299 (90 towns, x1.0-x1.55 each from 400 / their population) ended at
-- initialLandUseCapacities[1] x factor (median 0.998, quartiles 0.997 / 1.0; 89 of 90 the same at the command's
-- answer as minutes later), whatever the population before (261-398), pop 398-1020, mean 569 for 400 wanted. So a
-- forced command fills its capacity target at once, fully at small factors (x1-x1.55) and about 0.78 at x3 (room
-- runs out): growFactorForCap sizes each town from its capacity target, not from its people.
logic.GROW_FILL = 0.78
--- The size factor that lands a town of residential initial capacity initRes near target people: target /
--- (GROW_FILL x initRes), rounded to the nearest 0.25, between 1 and MAX_SIZE_FACTOR (the fallback when a town's
--- population can't be read).
function logic.growFactorFor(target : number, initRes : number, fill? : number) : number
	local f = fill or logic.GROW_FILL
	if target == nil or initRes == nil or initRes <= 0 or f <= 0 then return 1.0 end
	local x = math.floor(target / (f * initRes) * 4 + 0.5) / 4
	return math.max(1.0, math.min(logic.MAX_SIZE_FACTOR, x))
end
--- One town's size factor for about target people from its residential capacity target now (its
--- initialLandUseCapacities[1] x sizeFactors[1]; a forced size command fills that x factor, see GROW_FILL): target /
--- capacity, rounded to 0.05, between 1 (a town whose target is that big already only gets the level weights) and
--- MAX_SIZE_FACTOR; nil when the capacity is unknown or not positive (the caller's fallback factor then).
function logic.growFactorForCap(target : number, capacity : number) : number
	if target == nil or capacity == nil or capacity ~= capacity or capacity <= 0 then return nil end
	local x = math.floor(target / capacity * 20 + 0.5) / 20
	return math.max(1.0, math.min(logic.MAX_SIZE_FACTOR, x))
end
-- Lights showcase: the weights and ONE size command after the links, no build-out passes (seed 718344: 3 passes
-- took 3-4 min for +0..+12 buildings per town and pass; the towns go on densifying while the game runs). Sized
-- for about LIGHTS_TARGET_POP people per town, each town from its capacity target (growFactorForCap; user
-- 2026-10-13: "keep towns smaller, maybe around 400 people"; was 1000 with x3 for all, 939 came out). Medium
-- towns (initial capacity 400, the same 8 x 8 grid): x1, the level weights only, and the town fills its 400 at once
-- (the x1 towns of session 2026-10-13_0356_top-up-779299 ended at 398-400). LIGHTS_GROW_FACTOR (x1, fill 1 at
-- small factors) where a capacity can't be read. The grid
-- is locked, so the town can only build up (taller, DENSE_WEIGHTS), never out. The grow lines log each town's
-- population (pop=, read at the size command's answer and again at the final check) and the summary min/mean/max.
logic.LIGHTS_TARGET_POP = 400
logic.LIGHTS_GROW_FACTOR = logic.growFactorFor(logic.LIGHTS_TARGET_POP, logic.TOWN_SIZES[logic.LIGHTS_SIZE].caps, 1.0)
logic.LIGHTS_GROW_PASSES = 1

--- Where a town building stands for the leak check (houses_outside / houses_perimeter), from its bounding box
--- {minX, minY, maxX, maxY} (nil: unread) and its construction's origin {x, y} (nil: unread). Seed 530609
--- (2026-10-12): 1842 houses "outside" over 64 towns while the user saw none outside any grid, with no house in
--- the 45 m band beyond the ring (houses_perimeter=0 everywhere) and the one town whose grid holds the map's
--- origin at 0: buildings without a real box (min = max at 0,0: a building still under construction after the
--- growth, its box not filled yet) were placed at the origin. Now: the box centre when the box is real (finite,
--- some extent, not a point at 0,0); else the construction's origin (finite, not exactly 0,0); else nil
--- (unread: not counted). Both read but over HOUSE_ODD_M apart: the construction's origin (where the engine
--- placed the building). Second result: "bbox" / "con" / nil; third: that odd case (log evidence).
logic.HOUSE_ODD_M = 150.0
local function realXY(x : number, y : number) : boolean
	return x ~= nil and y ~= nil and x == x and y == y and math.abs(x) < 1e7 and math.abs(y) < 1e7
end
function logic.housePos(box : {number}, con : {number}) : {number}, string, boolean
	local b : {number} = nil
	if box ~= nil and #box >= 4 then
		local x0, y0, x1, y1 = box[1], box[2], box[3], box[4]
		if realXY(x0, y0) and realXY(x1, y1) and x1 >= x0 and y1 >= y0 and (x1 - x0) + (y1 - y0) > 0.01 then
			b = { (x0 + x1) / 2, (y0 + y1) / 2 }
		end
	end
	local c : {number} = nil
	if con ~= nil and realXY(con[1], con[2]) and not (con[1] == 0 and con[2] == 0) then c = { con[1], con[2] } end
	if b ~= nil then
		-- a box far from where the engine placed the building's construction is not its footprint: the origin
		if c ~= nil and math.sqrt((b[1] - c[1]) ^ 2 + (b[2] - c[2]) ^ 2) > logic.HOUSE_ODD_M then return c, "con", true end
		return b, "bbox", false
	end
	if c ~= nil then return c, "con", false end
	return nil, nil, false
end

--- Whether (px, py) lies outside the grid square of `a` grown by margin.
function logic.outsideGrid(a : SquareStressLockArea, px : number, py : number, margin : number) : boolean
	local lim = a.half + (margin or 0)
	return math.abs(px - a.x) > lim or math.abs(py - a.y) > lim
end

--- Whether a street edge from p0 to p1 ({x, y}) leaves the grid square (+ margin) at either end.
function logic.edgeOutside(a : SquareStressLockArea, p0 : {number}, p1 : {number}, margin : number) : boolean
	return logic.outsideGrid(a, p0[1], p0[2], margin) or logic.outsideGrid(a, p1[1], p1[2], margin)
end

--- A grid corner stub (stress_grid_streets.lua STUB: diagonally out of each corner): 0 when p0 is its
--- outer end and p1 sits on a corner, 1 the other way round, nil when the edge is no such stub.
function logic.stubOuterEnd(a : SquareStressLockArea, p0 : {number}, p1 : {number}, tol? : number) : integer
	local t = tol or logic.STUB_TOL
	local function corner(p : {number}) : boolean
		return math.abs(math.abs(p[1] - a.x) - a.half) <= t and math.abs(math.abs(p[2] - a.y) - a.half) <= t
	end
	local function outer(p : {number}) : boolean
		return math.abs(p[1] - a.x) > a.half + t and math.abs(p[2] - a.y) > a.half + t
	end
	if outer(p0) and corner(p1) then return 0 end
	if outer(p1) and corner(p0) then return 1 end
	return nil
end

--- The weights table for makeTownCustomDistributionWeightsCmd: `w` (default DENSE_WEIGHTS) for each of
--- the three land uses, fresh tables, every value clamped to 0..1, all zero replaced by the default.
function logic.denseWeights(w? : {number}) : {{number}}
	local src = w or logic.DENSE_WEIGHTS
	local row : {number} = {}
	local sum = 0.0
	for i = 1, 4 do
		local v = tonumber(src[i]) or 0.0
		if v < 0 then v = 0.0 elseif v > 1 then v = 1.0 end
		row[i] = v
		sum = sum + v
	end
	if sum <= 0 then row = { logic.DENSE_WEIGHTS[1], logic.DENSE_WEIGHTS[2], logic.DENSE_WEIGHTS[3], logic.DENSE_WEIGHTS[4] } end
	local out : {{number}} = {}
	for k = 1, 3 do out[k] = { row[1], row[2], row[3], row[4] } end
	return out
end

--- Building counts per level 1..4 from a list of levels (anything else counted as level 1 or 4, clamped).
function logic.levelCounts(levels : {integer}) : {integer}
	local c = { 0, 0, 0, 0 }
	for _, l in ipairs(levels or {}) do
		local k = math.floor(tonumber(l) or 1)
		if k < 1 then k = 1 elseif k > 4 then k = 4 end
		c[k] = c[k] + 1
	end
	return c
end

--- "1:a 2:b 3:c 4:d".
function logic.levelText(c : {integer}) : string
	return string.format("1:%d 2:%d 3:%d 4:%d", c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 0)
end

--- The steps of a density job over n towns: per town its weights, then its growth passes; then every
--- town's final check (after all growth, so the first towns had the longest to build on).
function logic.denseSteps(n : integer, passes : integer) : {SquareStressDenseStep}
	local out : {SquareStressDenseStep} = {}
	local p = math.max(1, math.floor(passes or 1))
	for k = 1, n do
		out[#out + 1] = { kind = "weights", town = k, pass = 0 }
		for q = 1, p do out[#out + 1] = { kind = "grow", town = k, pass = q } end
	end
	for k = 1, n do out[#out + 1] = { kind = "final", town = k, pass = p } end
	return out
end

--- " pop min/mean/max=a/b/c (n towns)" over the read populations (nil entries skipped), " pop=unread" without any.
function logic.popText(pops : {integer : integer}, n : integer) : string
	local lo, hi, sum, k = nil as integer, nil as integer, 0, 0
	for i = 1, n or 0 do
		local p = pops[i]
		if p ~= nil then
			k = k + 1
			sum = sum + p
			if lo == nil or p < lo then lo = p end
			if hi == nil or p > hi then hi = p end
		end
	end
	if k == 0 then return " pop=unread" end
	return string.format(" pop min/mean/max=%d/%.0f/%d (%d of %d towns read)", lo, sum / k, hi, k, n)
end

--- Per growth target (the light plans A/B's 600 / 150 / 40 towns): " pop_by_target=40:38/40/41/18,150:..." = target:min/
--- mean/max/towns read, targets ascending; "" when no town has a target. pops / targets: town index -> people / target.
function logic.popByTargetText(pops : {integer : integer}, targets : {integer : number}, n : integer) : string
	local by : {integer : {integer}} = {}
	local keys : {integer} = {}
	for i = 1, n or 0 do
		local t, p = targets[i], pops[i]
		if t ~= nil then
			local key = math.floor(t)
			if by[key] == nil then
				by[key] = { 0, 0, 0, 0, 0 }   -- min, max, sum, read, towns
				keys[#keys + 1] = key
			end
			local b = by[key]
			b[5] = b[5] + 1
			if p ~= nil then
				if b[4] == 0 or p < b[1] then b[1] = p end
				if b[4] == 0 or p > b[2] then b[2] = p end
				b[3] = b[3] + p
				b[4] = b[4] + 1
			end
		end
	end
	if #keys == 0 then return "" end
	table.sort(keys)
	local parts : {string} = {}
	for _, key in ipairs(keys) do
		local b = by[key]
		if b[4] == 0 then
			parts[#parts + 1] = string.format("%d:unread/%d", key, b[5])
		else
			parts[#parts + 1] = string.format("%d:%d/%.0f/%d/%d", key, b[1], b[3] / b[4], b[2], b[4])
		end
	end
	return " pop_by_target=" .. table.concat(parts, ",")
end

--- The leak check line: "[SQST] <name> town <label> outside_streets=N houses_outside=M<extra>".
function logic.leakLine(name : string, label : string, outside : integer, houses : integer, extra? : string) : string
	return string.format("[SQST] %s town %s outside_streets=%d houses_outside=%d%s", name, label, outside or 0, houses or 0, extra or "")
end
logic.LIGHTS_LIT_FROM = 1950      -- the game's trafficLightYearFrom (traffic_light_config.res.lua)

-- The two variants of the shared Showcase code (layout, build, zones, summary). nil fields read the
-- Showcase's own tables at call time (SHOWCASE_KINDS, showcaseTypes, SHOWCASE_AB, SHOWCASE_SIZE, ...),
-- so changing one of those still changes the Showcase.
logic.SHOWCASE_SPEC = {
	id = "showcase", title = "Showcase",
	kindLog = { ix = "interchanges", rb = "roundabouts", plain = "plain" },
	kindWords = { ix = "interchanges", rb = "roundabouts", plain = "plain junctions" },
	growFactor = logic.DENSE_GROW_FACTOR,
	growPasses = logic.DENSE_GROW_PASSES,
	lockStreets = true,
	denseWeights = logic.DENSE_WEIGHTS,
} as SquareStressShowcaseSpec
--- The Lights showcase spec of shape k (1-based into LIGHTS_SHAPES, wrapped): one slot ("x" crossroads or
--- "t" T-junctions) with that one type, so every set is the same junction; no bus lines (seed 718344: every
--- depot spot collided with the built-up grids, and the traffic log measures the towns' own traffic).
-- Lights showcase links: the large country road (3 lanes each way; SHOWCASE.md "Town entries")
logic.ENTRY_LINK_LANES = 6
function logic.lightsSpec(k : integer) : SquareStressShowcaseSpec
	local n = #logic.LIGHTS_SHAPES
	local i = ((math.floor(k or 1) - 1) % n) + 1
	local t = logic.LIGHTS_SHAPES[i]
	local slot = t.slot or "x"
	return {
		id = "lights_showcase", title = "Lights showcase",
		kinds = { slot },
		types = { [slot] = { t } },
		kindLog = { x = "crossroads", t = "t_junctions" },
		kindWords = { x = "lit " .. t.label .. " crossroads", t = "lit " .. t.label .. " junctions" },
		modes = logic.LIGHTS_AB,
		size = logic.LIGHTS_SIZE,
		misses = 6,
		litOnly = true,
		growFactor = logic.LIGHTS_GROW_FACTOR,
		growTarget = logic.LIGHTS_TARGET_POP,
		growPasses = logic.LIGHTS_GROW_PASSES,
		lockStreets = true,
		denseWeights = logic.DENSE_WEIGHTS,
		square = true,
		noBusLines = true,
		modeNames = true,
		entries = true,
		linkLanes = logic.ENTRY_LINK_LANES,
		shape = i,
		shapeLabel = t.label,
	} as SquareStressShowcaseSpec
end
-- The mixed Lights showcase's twins: Smart Lanes (a), the game default (b) and Smart Lanes' exit-lane fan (e)
-- (user 2026-10-13: "A": every shape on one map, 3 sets each; then the exit fan as a third twin). sl_phases /
-- sl_lock / sl_fan stay modes of LIGHTS_AB and Smart Lanes, just not built here.
logic.LIGHTS_MIXED_AB = { logic.LIGHTS_AB[1], logic.LIGHTS_AB[2], logic.LIGHTS_EXITFAN_AB } as {SquareStressShowcaseAb}
logic.LIGHTS_PER_TYPE = 3

--- The Lights showcase (one press, no options): every LIGHTS_SHAPES shape, LIGHTS_PER_TYPE sets each (12), the game
--- and Smart Lanes twins of each (24 junctions), crossroads and T-junctions alternating, the crossroads' shapes
--- in turn (2x2 X, 3x3 X, 3x2 X). lightsSpec(k) builds one shape with four twins (earlier runs, tests).
function logic.lightsMixedSpec() : SquareStressShowcaseSpec
	local sp = logic.lightsSpec(1)
	local xs : {SquareStressShowcaseType} = {}
	local ts : {SquareStressShowcaseType} = {}
	for _, t in ipairs(logic.LIGHTS_SHAPES) do
		if (t.slot or "x") == "t" then ts[#ts + 1] = t else xs[#xs + 1] = t end
	end
	-- three crossroads sets, then a T set, in turn: the T sets spread over the whole map (the sets fill it row by row)
	sp.kinds = { "x", "x", "x", "t" }
	sp.types = { x = xs, t = ts }
	sp.kindWords = { x = "lit crossroads", t = "lit T-junctions" }
	sp.modes = logic.LIGHTS_MIXED_AB
	sp.perType = logic.LIGHTS_PER_TYPE
	sp.alternateTwins = true
	sp.shape, sp.shapeLabel = nil, nil
	return sp
end
logic.LIGHTS_SPEC = logic.lightsMixedSpec()

-- Light plans A/B (user 2026-10-14, SHOWCASE.md "Light plans A/B"): a lit crossroads with the game's default (game, b),
-- Smart Lanes' axis plan (sl_phases, c: Smart Lanes lanes + the axis phases since Smart Lanes rev 8) and the axis plan
-- with its timing kept adjusted (sl_auto, v). The classic patterns' twin (sl_classic, u) is gone (2026-10-16: Smart
-- Lanes dropped the classic patterns, its PLAN.md "No classic fallback"); letter u stays reserved (older saves).
-- Keep timing adjusted (user 2026-10-14, Smart Lanes rev 8 step B; its PLAN.md "Stress Test interface: Keep timing
-- adjusted"): sl_auto = sl_phases (lanes + the axis plan) with every lit junction in the zone enrolled in Smart Lanes'
-- automatic re-timing (~30 game s after its light). Letter v: a-u are taken (u: the dropped sl_classic).
logic.LIGHTS_AUTO_AB = { ab = "sl_auto", twin = "v", label = "Auto timing",
	note = "Smart Lanes lanes and axis plan, its timing kept adjusted (Keep timing adjusted)", litPlainOnly = true } as SquareStressShowcaseAb
-- built in stress_flow TWIN_ORDER (game, sl_phases, sl_auto), so a reload's fallback set split stays right. The classic
-- patterns are settled (session 2026-10-14, seed 488195: axis +23-26 % thru/min vs game, classic worse than game, 6/6
-- sets) and gone from Smart Lanes: the twins are game / axis / auto.
logic.LIGHTS_PLANS_AB = { logic.LIGHTS_AB[2], logic.LIGHTS_AB[3], logic.LIGHTS_AUTO_AB } as {SquareStressShowcaseAb}
-- busy junctions: 600 people a town (x1.5 by capacity, filled at once: docs/findings/towns.md); 400 left the 3x3 X's
-- Smart Lanes twins at ~20 % standing (session 2026-10-13_0447_top-up-726115), the micro bench's 800 neared a jam
-- (~52 % standing map-wide), 600 is the micro bench's choice since
logic.LIGHTS_PLANS_TARGET_POP = 600
logic.LIGHTS_PLANS_PER_TYPE = 3
-- Unbalanced demand (user 2026-10-14, SHOWCASE.md "Light plans A/B": "some sets get unbalanced demand to exercise the
-- timing"): in an unbalanced set the two towns on the E-W road stay busy (LIGHTS_PLANS_TARGET_POP), the north town is
-- small, the south town tiny. A town smaller than its size's initial capacity is created with that capacity (a forced
-- size command never sizes a town below x1, growFactorForCap; it fills its capacity target at once: docs/findings/
-- towns.md); its street grid stays the size's (the same layout as the balanced sets). Word: the town name's suffix.
logic.LIGHTS_PLANS_POPS = { busy = logic.LIGHTS_PLANS_TARGET_POP, small = 150, tiny = 40 }
logic.LIGHTS_PLANS_UNBALANCED = { E = "busy", W = "busy", N = "small", S = "tiny" }

--- A light plans set's demand: per shape (typeIndex: its place in the spec's types, 1-based) its k-th set; balanced and
--- unbalanced in turn, the shapes starting on opposite ones (2x2 X: balanced, unbalanced, balanced; 3x3 X: unbalanced,
--- balanced, unbalanced), so a 16 km map holds three of each and every twin sees both (the twins of a set share it).
function logic.lightsPlansDemand(typeIndex : integer, k : integer) : string
	return ((typeIndex or 1) + (k or 1)) % 2 == 1 and "unbalanced" or "balanced"
end

--- One town's people of a light plans set: (target, word) by its demand and its side's compass point; the word ("busy" /
--- "small" / "tiny") only in an unbalanced set (nil: balanced, every town LIGHTS_PLANS_TARGET_POP).
function logic.lightsPlansTownPop(demand : string, side : string) : number, string
	if demand ~= "unbalanced" then return logic.LIGHTS_PLANS_TARGET_POP, nil end
	local word = logic.LIGHTS_PLANS_UNBALANCED[side] or "busy"
	return logic.LIGHTS_PLANS_POPS[word], word
end

--- The light plans A/B (its own button): a 2-lane (2x2 X) and a 3-lane (3x3 X) lit crossroads in turn,
--- LIGHTS_PLANS_PER_TYPE sets of each (6 sets, 18 junctions: what a 16 km map holds with three twins), every set as
--- three twins game / sl_phases (axis plan) / sl_auto, each twin once in every position per shape (alternateTwins),
--- balanced and unbalanced sets in turn (demandMix, lightsPlansDemand), towns of about LIGHTS_PLANS_TARGET_POP people.
--- Otherwise the Lights showcase (square layout, entries, country links, locks, no bus lines, batched building).
--- (Its variant "classic", twins game / sl_phases / sl_classic, is gone with Smart Lanes' classic patterns, 2026-10-16.)
function logic.lightsPlansSpec() : SquareStressShowcaseSpec
	local sp = logic.lightsSpec(1)
	sp.title = "Light plans A/B"
	sp.kinds = { "x" }
	sp.types = { x = { logic.LIGHTS_SHAPES[1], logic.LIGHTS_SHAPES[2] } }
	sp.kindWords = { x = "lit crossroads" }
	sp.modes = logic.LIGHTS_PLANS_AB
	sp.perType = logic.LIGHTS_PLANS_PER_TYPE
	sp.alternateTwins = true
	sp.growTarget = logic.LIGHTS_PLANS_TARGET_POP
	sp.variant = "light_plans"
	sp.demandMix = true
	sp.shape, sp.shapeLabel = nil, nil
	return sp
end
logic.LIGHTS_PLANS_SPEC = logic.lightsPlansSpec()

local function specOf(spec : SquareStressShowcaseSpec) : SquareStressShowcaseSpec
	return spec or logic.SHOWCASE_SPEC
end

--- A spec's kinds (slots in turn), its types of one slot, its A/B modes, town size, town clearance factor.
function logic.specKinds(spec : SquareStressShowcaseSpec) : {string}
	return specOf(spec).kinds or logic.SHOWCASE_KINDS
end
function logic.specTypes(spec : SquareStressShowcaseSpec, slot : string) : {SquareStressShowcaseType}
	local sp = specOf(spec)
	if sp.types ~= nil then return sp.types[slot] or {} end
	return logic.showcaseTypes(slot)
end
function logic.specModes(spec : SquareStressShowcaseSpec) : {SquareStressShowcaseAb}
	return specOf(spec).modes or logic.SHOWCASE_AB
end
function logic.specSize(spec : SquareStressShowcaseSpec) : integer
	return specOf(spec).size or logic.SHOWCASE_SIZE
end
function logic.specTownR(spec : SquareStressShowcaseSpec) : number
	return specOf(spec).townR or logic.SHOWCASE_TOWN_R
end
--- "Medium": the label of a spec's town size.
function logic.specSizeText(spec : SquareStressShowcaseSpec) : string
	return (logic.TOWN_SIZES[logic.specSize(spec)] or { label = "?" }).label
end

--- One placement's construction case: the type's fixed params, then each range drawn in order;
--- armRoad (1-6) sets the arm road, nil draws it too. A one-way side road keeps one road on both arms.
function logic.showcaseDraw(rng : SquareStressRng, t : SquareStressShowcaseType, armRoad : integer) : SquareStressJunctionCase
	local params : {string : number} = {}
	for k, v in pairs(t.fixed) do params[k] = v end
	for _, r in ipairs(t.ranges) do params[r.key] = r.values[logic.rngInt(rng, #r.values)] end
	if t.armKey ~= nil then params[t.armKey] = armRoad or logic.rngInt(rng, 6) end
	if params.sqst_x_side ~= nil and params.sqst_x_side >= PLAIN_ONE_WAY and params.sqst_x_side2 ~= nil then params.sqst_x_side2 = 1 end
	return { id = t.id, label = t.label, file = t.file, params = params }
end

--- "key=v key=v ..." of a case's params, keys sorted (the log line).
function logic.showcaseParamText(case_ : SquareStressJunctionCase) : string
	local keys : {string} = {}
	for k in pairs(case_.params) do keys[#keys + 1] = k end
	table.sort(keys)
	local parts : {string} = {}
	for i, k in ipairs(keys) do parts[i] = string.format("%s=%g", k, case_.params[k]) end
	return table.concat(parts, " ")
end

-- square_roundabouts' Arms layouts (geometry.lua ARM_LAYOUTS), the Magic Roundabout's five arms
-- (magic.lua FIRST_DEG 90, every 72 deg), the Channelized Junction's (channel.lua ARMS, right-hand) and
-- the interchanges' (highway along local x, square_roundabouts_highway.lua:8; cross road along y).
local RING_ARMS : {{number}} = { { 0, 90, 180 }, { 90, 210, 330 }, { 0, 90, 180, 270 }, { 90, 162, 234, 306, 18 }, { 0, 60, 120, 180, 240, 300 } }
local MAGIC_ARMS : {number} = { 90, 162, 234, 306, 18 }
local IX_ARMS : {number} = { 0, 90, 180, 270 }

--- The side road angle of a plain crossing case (degrees).
local function plainAngle(p : {string : number}) : number
	local i = math.floor(p.sqst_x_angle or 1)
	return logic.SHOWCASE_PLAIN_ANGLES[i] or 90
end

--- The arm directions of a case in its local frame (degrees, ascending); nil for unknown files.
function logic.showcaseArms(case_ : SquareStressJunctionCase) : {number}
	local p = case_.params
	local list : {number} = nil
	if p.sqst_x_shape ~= nil then
		local a = plainAngle(p)
		if p.sqst_x_shape == 2 then list = { 0, a, 180 }
		elseif p.sqst_x_shape == 3 then list = { 0, 60, 180, 240 }
		elseif p.sqst_x_shape == 4 then list = { 0, 180 }   -- straight (the bench's lane drop)
		else list = { 0, a, 180, a + 180 } end
	elseif p.sqrb_ix_highway ~= nil then
		list = IX_ARMS
	elseif p.sqrb_ch_layout ~= nil then
		list = p.sqrb_ch_layout == 2 and { 0, 90, 180, 270 } or { 0, 90, 180 }
	elseif p.sqrb_magic_size ~= nil or case_.file == "square_roundabouts_magic.con" then
		list = MAGIC_ARMS
	elseif case_.file == "square_roundabouts.con" then
		list = RING_ARMS[math.floor(p.sqrb_arms or 3)]
	elseif case_.file == logic.ENTRY_FILE then
		list = { 0, 90, 180, 270 }
	end
	if list == nil then return nil end
	local out : {number} = {}
	for i, d in ipairs(list) do out[i] = d end
	table.sort(out)
	return out
end

--- The arms (positions in showcaseArms' order) whose road is one-way: a plain crossing's one-way
--- side road (its towns can be reached one way only, so they get no bus line).
function logic.showcaseOneWay(case_ : SquareStressJunctionCase) : {integer : boolean}
	local out : {integer : boolean} = {}
	local p = case_.params
	if p.sqst_x_shape == nil or (p.sqst_x_side or 1) < PLAIN_ONE_WAY then return out end
	local a = p.sqst_x_shape == 3 and 60 or plainAngle(p)
	for i, d in ipairs(logic.showcaseArms(case_) or {}) do
		if d == a or d == a + 180 then out[i] = true end
	end
	return out
end

-- Reach (metres from the centre to the outer road edge, arms included): measured offline on
-- square_roundabouts' own updateFn output (tests/square_stress_test/test_showcase.lua "showcaseReach
-- covers the real footprint": every edge sampled, plus its road's half width), the worst case over
-- the params that are not keys of the table (lanes, arms, arm road, tram, through road, slips, ...),
-- plus REACH_PAD. 2026-10-12 (in-game Showcase seed 204313: the old formula was up to 96 m short for
-- ovals with splitters, 60 m for Hamburgers, 46 m for small Magic Roundabouts, 12 m for Parclos;
-- splitters grow the ring to a floor whatever the radius, a road through the centre too).
-- Ring / oval / Hamburger: [splitter][shape][radius size]; RING_THROUGH with a road through the centre.
local RING_REACH : {{{number}}} = {
	{ { 91, 91, 91, 104, 134 }, { 95, 95, 95, 113, 144 }, { 101, 101, 101, 122, 159 }, { 108, 108, 108, 131, 174 }, { 146, 146, 146, 146, 189 } },
	{ { 155, 155, 155, 155, 161 }, { 175, 175, 175, 175, 176 }, { 229, 229, 229, 229, 229 }, { 263, 263, 263, 263, 263 }, { 225, 225, 225, 225, 225 } } }
local RING_THROUGH : {{{number}}} = {
	{ { 104, 104, 104, 104, 129 }, { 119, 119, 119, 119, 144 }, { 129, 129, 129, 129, 159 }, { 148, 148, 148, 148, 174 }, { 159, 159, 159, 159, 189 } },
	{ { 155, 155, 155, 155, 161 }, { 158, 158, 158, 158, 165 }, { 160, 160, 160, 160, 166 }, { 168, 168, 168, 168, 174 }, { 183, 183, 183, 183, 189 } } }
-- Magic Roundabout: [size][lanes]
local MAGIC_REACH : {{number}} = { { 152, 159 }, { 152, 159 }, { 152, 159 }, { 152, 159 }, { 212, 220 } }
-- Channelized T / X: [layout][scale][arm length]
local CHANNEL_REACH : {{{number}}} = {
	{ { 137, 147, 157, 167 }, { 159, 169, 179, 189 }, { 182, 192, 202, 212 }, { 227, 237, 247, 257 }, { 272, 282, 292, 302 } },
	{ { 124, 134, 144, 154 }, { 145, 155, 165, 175 }, { 165, 175, 185, 195 }, { 206, 216, 226, 236 }, { 247, 257, 267, 277 } } }
-- Roundabout / Dumbbell / Peanut Interchange: [arm length] (the radius changes it by under 15 m)
local IX_REACH : {number} = { 276, 288, 298, 308 }
-- Parclo (both) and Diamond: [scale][arm length]
local PARCLO_REACH : {{number}} = { { 288, 304, 319 }, { 401, 408, 431 }, { 493, 493, 493 } }
local DIAMOND_REACH : {{number}} = { { 222, 237, 252 }, { 294, 309, 324 }, { 402, 417, 432 } }
-- Plain crossing: its arms (stress_crossing.ARM 60 m) + the widest road's half width (16 m)
local PLAIN_REACH <const> = 76.0
local REACH_PAD <const> = 12.0

local function at(list : {number}, i : number) : number
	return list[math.max(1, math.min(#list, math.floor(i or 1)))]
end

function logic.showcaseReach(case_ : SquareStressJunctionCase) : number
	local p = case_.params
	local r : number
	if p.sqst_x_shape ~= nil then
		r = PLAIN_REACH
	elseif p.sqrb_hx_scale ~= nil then
		local t = (p.sqrb_hx_layout ~= nil or (case_.file or ""):find("parclo", 1, true) ~= nil) and PARCLO_REACH or DIAMOND_REACH
		r = at(t[math.max(1, math.min(#t, math.floor(p.sqrb_hx_scale)))], p.sqrb_hx_arm_length)
	elseif p.sqrb_ix_highway ~= nil then
		r = at(IX_REACH, p.sqrb_ix_arm_length)
	elseif p.sqrb_ch_layout ~= nil then
		r = at(CHANNEL_REACH[p.sqrb_ch_layout == 2 and 2 or 1][math.max(1, math.min(5, math.floor(p.sqrb_ch_scale or 1)))], p.sqrb_ch_arm_length)
	elseif p.sqrb_magic_size ~= nil then
		r = at(MAGIC_REACH[math.max(1, math.min(5, math.floor(p.sqrb_magic_size)))], p.sqrb_magic_lanes)
	else
		local t = (p.sqrb_centre == 2 or p.sqrb_centre == 4) and RING_THROUGH or RING_REACH
		r = at(t[p.sqrb_splitter == 2 and 2 or 1][math.max(1, math.min(5, math.floor(p.sqrb_shape or 1)))], p.sqrb_radius_size)
	end
	return math.floor(r + REACH_PAD + 0.5)
end

--- A group's town distances (one per arm, in arm order) from its junction: reach + the town's
--- clearance (its streets, size spacing x SHOWCASE_TOWN_R, + SHOWCASE_GAP); all pushed out by one
--- factor when two towns would come closer than their clearances together (arms 60 deg apart).
--- arms: directions (degrees); spacings: each town's size spacing.
function logic.showcaseTownDists(reach : number, arms : {number}, spacings : {number}, townR? : number) : {number}
	local R, GAP = townR or logic.SHOWCASE_TOWN_R, logic.SHOWCASE_GAP
	local d : {number} = {}
	for i = 1, #arms do d[i] = reach + spacings[i] * R + GAP end
	local f = 1.0
	for i = 1, #arms do
		for j = i + 1, #arms do
			local th = math.rad(arms[j] - arms[i])
			local chord = math.sqrt(math.max(0, d[i] * d[i] + d[j] * d[j] - 2 * d[i] * d[j] * math.cos(th)))
			local need = (spacings[i] + spacings[j]) * R + 2 * GAP
			if chord > 0 and chord < need then f = math.max(f, need / chord) end
		end
	end
	for i = 1, #d do d[i] = d[i] * f end
	return d
end

--- The unit vector of a direction that is a multiple of 90 degrees ({1, 0}, {0, 1}, {-1, 0}, {0, -1}),
--- exact (no 6e-17 from cos / sin); nil for any other direction.
function logic.axisUnit(deg : number) : {number}
	local k = math.floor(deg / 90 + 0.5)
	if math.abs(deg - k * 90) > 1e-6 then return nil end
	local units : {{number}} = { { 1.0, 0.0 }, { 0.0, 1.0 }, { -1.0, 0.0 }, { 0.0, -1.0 } }
	return units[k % 4 + 1]
end

-- Compass points of town names, clockwise from north (map +y is north, +x east).
logic.COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

--- The index into COMPASS of a compass point, nil for anything else.
function logic.compassIndex(side : string) : integer
	for i, c in ipairs(logic.COMPASS) do if c == side then return i end end
	return nil
end

--- The compass point (8 of them, 45 deg each) of a direction in degrees counter-clockwise from +x (east):
--- 90 -> "N", 0 -> "E", 225 -> "SW". Arms at least 60 deg apart never share one.
function logic.compassOf(deg : number) : string
	local bearing = (90 - deg) % 360
	local k = math.floor(bearing / 45 + 0.5) % 8
	return logic.COMPASS[k + 1]
end

--- A Showcase town's name (user 2026-10-12: the name says which test it belongs to). modeNames (Lights
--- showcase): "<mode> <set> <side>" ("Smart lanes 1 N"); else "<type> <set> <side> (<mode>)" ("Parclo 3 N
--- (Smart lanes)"), type = its short label. Kept short (<= ~30 characters).
function logic.showcaseTownName(t : SquareStressShowcaseType, m : SquareStressShowcaseAb, set : integer, side : string, modeNames : boolean,
		word? : string) : string
	local mode = m.label or m.ab
	-- word: the light plans A/B's unbalanced towns ("Auto timing 2 S tiny")
	if modeNames and word ~= nil then return string.format("%s %d %s %s", mode, set, side, word) end
	if modeNames then return string.format("%s %d %s", mode, set, side) end
	return string.format("%s %d %s (%s)", t.short or t.label, set, side, mode)
end

--- The middle of the side of a town's square grid (centre tx, ty, half its side) that faces the point
--- (jx, jy): the side across the larger offset (a junction straight east of the town: the east side's
--- middle, tx + half, ty). Square layout links end there, on the grid's central street.
function logic.sideCentre(tx : number, ty : number, half : number, jx : number, jy : number) : {number}
	local dx, dy = jx - tx, jy - ty
	if math.abs(dx) >= math.abs(dy) then
		return { tx + (dx >= 0 and half or -half) + 0.0, ty + 0.0 }
	end
	return { tx + 0.0, ty + (dy >= 0 and half or -half) + 0.0 }
end

--- The candidate nearest to pt within tol (m), nil when none is that close (a square layout's link
--- target: the grid's node at its side's middle).
function logic.nodeAt(cands : {SquareStressNodeCand}, pt : {number}, tol : number) : SquareStressNodeCand
	local best : SquareStressNodeCand = nil
	local bestD = tol * tol
	for _, c in ipairs(cands or {}) do
		local d = (c.x - pt[1]) ^ 2 + (c.y - pt[2]) ^ 2
		if (best == nil and d <= bestD) or (best ~= nil and (d < bestD or (d == bestD and c.id < best.id))) then
			best, bestD = c, d
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Town entries (Lights showcase; SHOWCASE.md "Town entries must not be the bottleneck", user screenshot
-- 2026-10-12, seed 530609: every link's inbound lanes queued solid back from the grid's side-middle crossroads,
-- so the measurement tested the town entry, not the junction). At the middle of each town's facing side the
-- node where the link, the perimeter ring (both ways) and the central street meet is replaced by a 2-lane
-- roundabout, our own construction (stress_entry_streets.lua): ONE proposal removes that node and its three grid
-- edges (the far nodes' configs pruned) and adds the construction centred on the node's spot, rotation exactly 0
-- (it is the same at 0/90/180/270 deg; its output has no -0, and the transform's zeros are +0). After the settle
-- its arm ends are read: the inward, left and right arms are joined to the three far grid nodes (short pieces,
-- one proposal), the outward arm is the junction link's target. No construction, before 1940, or the proposal
-- refused: the crossroads stays (kind=crossroads).
-- 2026-10-12 (log 2026-10-12_2343_top-up-563524): square_roundabouts' Roundabout (2 lanes, radius S, country large
-- arms) ends its arms 62 m out, inside the junction areas of the far grid nodes 75 m out (from ~59 m): all 96
-- entries "Collision (hits 12 other BASE_NODE)". Ours ends them at ENTRY_REACH, ENTRY_FAR_CLEAR + a join clear.
logic.ENTRY_FILE = "square_stress_test_entry.con"
logic.ENTRY_CASE = { id = "entry_rb", label = "Entry roundabout", file = logic.ENTRY_FILE, params = {} } as SquareStressJunctionCase
-- Its arm ends lie this far from its centre (stress_entry_streets.REACH; tested equal).
logic.ENTRY_REACH = 46.0
-- A far grid node's junction area reaches about this far towards the entry (half the widest grid street: the
-- 32 m large town street); an arm end and its join must stay outside it.
logic.ENTRY_FAR_CLEAR = 16.0
-- The inward arm's reaches tried in turn (stress_entry_streets.IN_REACHES; tested equal): 2026-10-13 (log session
-- 2026-10-13_0018_top-up-598153) all 96 entries at 46 m still hit the inward far node, a crossroads 75 m out
-- ("hits 2 other BASE_NODE (1 distinct) ... in far node"), while left / right (T-junctions) cleared.
logic.ENTRY_IN_REACHES = { 46.0, 42.0, 38.0, 36.0 }
-- The rings tried, biggest first (sqst_entry_ring: 2 = 3 lanes, 1 = 2 lanes; stress_entry_streets.RINGS, tested
-- equal): the pre-check ladder runs every inward reach on the 3-lane ring, then on the 2-lane one, then the
-- crossroads stays (user 2026-10-13: "3/4 lanes, whatever is biggest").
logic.ENTRY_RINGS = { 2, 1 }
logic.ENTRY_RING_LANES = { 2, 3 }   -- lanes by sqst_entry_ring
logic.ENTRY_RING_RADIUS = { 24.0, 22.0 }   -- ring centreline (m) by sqst_entry_ring (stress_entry_streets.RINGS; tested equal)
logic.ENTRY_MIN_JOIN = 5.0      -- each join piece keeps at least this much beyond ENTRY_FAR_CLEAR, else the block is too small
logic.ENTRY_FROM_YEAR = 1940    -- the construction's templates (one-way ring, country_new_large) exist from this year
logic.ENTRY_SCAN = 20.0         -- the roundabout's new arm ends are read within ENTRY_REACH + this
logic.ENTRY_ROLE_COS = 0.9      -- an arm (or far node) is "out" / "in" / "left" / "right" within ~25 deg of that axis

--- The map's driving side from one two-way street's road lanes (laneConfigs order without the sidewalks: left
--- to right looking from node0 into the segment) by their `forward` flags: "right" when every backward lane
--- comes before every forward one (traffic towards node0 keeps to its right, our left), "left" the other way
--- round; nil when it is not one clean two-way split (one-way, mixed, unreadable). The entry roundabout runs
--- anticlockwise for "right", clockwise for "left".
function logic.drivingSide(forwards : {boolean}) : string
	local n = #(forwards or {})
	if n < 2 then return nil end
	local first = forwards[1]
	local k = 1
	while k <= n and forwards[k] == first do k = k + 1 end
	if k > n then return nil end
	for j = k, n do
		if forwards[j] == first then return nil end
	end
	return first and "left" or "right"
end

--- The index (1..4: +x, +y, -x, -y, stress_entry_streets' AXES order) of an axis-aligned unit vector; nil otherwise.
function logic.axisIndex(v : {number}) : integer
	if v == nil then return nil end
	local x, y = v[1], v[2]
	if x == 1 and y == 0 then return 1 end
	if x == 0 and y == 1 then return 2 end
	if x == -1 and y == 0 then return 3 end
	if x == 0 and y == -1 then return 4 end
	return nil
end

--- The unit vector from a town's centre (tx, ty) to the middle of its side at (sx, sy), exactly on an axis
--- (components 0 / +-1, never -0): the outward direction of that side's entry.
function logic.entryOutward(tx : number, ty : number, sx : number, sy : number) : {number}
	local dx, dy = sx - tx, sy - ty
	if math.abs(dx) >= math.abs(dy) then return { dx >= 0 and 1.0 or -1.0, 0.0 } end
	return { 0.0, dy >= 0 and 1.0 or -1.0 }
end

--- The role of each point around an entry centred at (cx, cy) facing `out` (unit): "out" (away from the
--- town: the link), "in" (the central street), "left" / "right" (the perimeter ring, seen looking out).
--- Returns role -> index into pts, nil and why when a point fits no role or two share one.
function logic.entryRoles(cx : number, cy : number, out : {number}, pts : {{number}}) : {string : integer}, string
	local roles : {string : integer} = {}
	local lx, ly = -out[2], out[1]
	for i, p in ipairs(pts or {}) do
		local dx, dy = p[1] - cx, p[2] - cy
		local l = math.sqrt(dx * dx + dy * dy)
		if l <= 0 then return nil, string.format("point %d at the centre", i) end
		local a, b = (dx * out[1] + dy * out[2]) / l, (dx * lx + dy * ly) / l
		local c = logic.ENTRY_ROLE_COS
		local role : string = nil
		if a >= c then role = "out" elseif a <= -c then role = "in" elseif b >= c then role = "left" elseif b <= -c then role = "right" end
		if role == nil then return nil, string.format("point %d at %.0f,%.0f is off the axes", i, p[1], p[2]) end
		if roles[role] ~= nil then return nil, string.format("two points %s", role) end
		roles[role] = i
	end
	return roles, nil
end

--- "[SQST] lights_showcase entry Smart lanes 1 N kind=roundabout at -6661,7361 ..." (SHOWCASE.md "Town
--- entries"; tools/flow_report.py counts the kinds).
function logic.entryLine(id : string, town : string, kind : string, detail : string) : string
	return string.format("[SQST] %s entry %s kind=%s%s", id, tostring(town), kind, (detail ~= nil and detail ~= "") and (" " .. detail) or "")
end

--- Town link targets must be the arm's own town's (user 2026-10-12, seed 718344: Group 1a's north arm
--- was linked to a corner stub of the EAST town, whose grid corner lay nearer the arm than any node of
--- the north town, inside the north town's search circle): only the candidates within the town's own grid
--- square + OWN_TOWN_MARGIN (its corner stubs reach STUB x 0.71 = 42 m out). Never another town's node.
logic.OWN_TOWN_MARGIN = 50.0
function logic.ownTownNodes(cands : {SquareStressNodeCand}, area : SquareStressLockArea) : {SquareStressNodeCand}
	local out : {SquareStressNodeCand} = {}
	for _, c in ipairs(cands or {}) do
		if not logic.outsideGrid(area, c.x, c.y, logic.OWN_TOWN_MARGIN) then out[#out + 1] = c end
	end
	return out
end

--- One group drawn (not placed yet): its placement (centre 0, 0), town offsets and sizes, and the
--- room it needs: R (circle other groups keep clear of: the farthest town + its clearance, so towns
--- of neighbouring groups keep the same distance as two towns of one group: their streets + 2 x
--- SHOWCASE_GAP) and the box of its town centres and junction reach (map margins).
local record Draft
	place : SquareStressShowcasePlacement
	kind : string
	offsets : {{number}}
	sizes : {integer}
	oneWay : {integer : boolean}
	type_ : SquareStressShowcaseType
	sides : {string}
	R : number
	minX : number
	maxX : number
	minY : number
	maxY : number
end

local function drawGroup(rng : SquareStressRng, t : SquareStressShowcaseType, spec : SquareStressShowcaseSpec) : Draft
	local case_ = logic.showcaseDraw(rng, t, t.kind == "ix" and logic.SHOWCASE_IX_CROSS or nil)
	local reach = logic.showcaseReach(case_)
	local square = specOf(spec).square == true
	-- square layout: never turned (arms along the map axes)
	local rot = square and 0 or (logic.rngInt(rng, 24) - 1) * 15
	-- lights drawn per plain crossing (AUTO or off); a lit-only spec never draws them off
	local lightsOff = t.kind == "plain" and not specOf(spec).litOnly and logic.rngInt(rng, 2) == 2
	local arms = logic.showcaseArms(case_) or {}
	local sizes : {integer} = {}
	local spacings : {number} = {}
	-- one size for every town of the spec, never drawn (so no rng value is spent on it)
	local size = logic.specSize(spec)
	local townR = logic.specTownR(spec)
	for i = 1, #arms do
		sizes[i] = size
		spacings[i] = logic.TOWN_SIZES[size].spacing
	end
	local dists = logic.showcaseTownDists(reach, arms, spacings, townR)
	if square then
		-- every town at the same distance, the farthest one's (its grid's side faces the junction square on)
		local far = 0.0
		for _, d in ipairs(dists) do far = math.max(far, d) end
		for i = 1, #dists do dists[i] = math.ceil(far) + 0.0 end
	end
	local g : Draft = { kind = t.kind, type_ = t, sides = {}, offsets = {}, sizes = sizes, oneWay = logic.showcaseOneWay(case_), R = reach,
		minX = -reach, maxX = reach, minY = -reach, maxY = reach,
		place = { case_ = case_, x = 0, y = 0, angle = math.rad(rot), reach = reach, lightsOff = lightsOff } }
	for i, d in ipairs(arms) do
		local a = math.rad(rot + d)
		local ox, oy = dists[i] * math.cos(a), dists[i] * math.sin(a)
		if square then
			-- exactly on the axis (cos 90 deg is 6e-17, not 0), +0 never -0
			local u = logic.axisUnit(rot + d)
			ox, oy = dists[i] * u[1] + 0.0, dists[i] * u[2] + 0.0
		end
		g.offsets[i] = { ox, oy }
		g.sides[i] = logic.compassOf(rot + d)
		g.R = math.max(g.R, dists[i] + spacings[i] * townR + logic.SHOWCASE_GAP)
		g.minX, g.maxX = math.min(g.minX, ox), math.max(g.maxX, ox)
		g.minY, g.maxY = math.min(g.minY, oy), math.max(g.maxY, oy)
	end
	return g
end

--- The first spot (rows top to bottom, SHOWCASE_STEP apart, left to right) for n twins of group g side
--- by side (2 R apart along x, so their circles touch and no town of one comes near the other's)
--- where the boxes fit the bounds and every twin's circle R clears every placed one ({x, y, R}):
--- the first twin's centre, nil when there is none.
local function fitSet(g : Draft, n : integer, placed : {{number}}, left : number, right : number, bottom : number, top : number) : number, number
	local pitch = 2 * g.R
	local xMin, xMax = left - g.minX, right - g.maxX - (n - 1) * pitch
	local yMin = bottom - g.minY
	local y = top - g.maxY
	if xMin > xMax then return nil, nil end
	while y >= yMin do
		local x = xMin
		while x <= xMax do
			local skip : number = nil
			for t = 0, n - 1 do
				local tx = x + t * pitch
				for _, p in ipairs(placed) do
					local rr, dy = p[3] + g.R, y - p[2]
					if (tx - p[1]) ^ 2 + dy * dy < rr * rr then
						skip = p[1] + math.sqrt(math.max(0, rr * rr - dy * dy)) + 1 - t * pitch
						break
					end
				end
				if skip ~= nil then break end
			end
			if skip == nil then return x, y end
			x = math.max(x + 1, skip)
		end
		y = y - logic.SHOWCASE_STEP
	end
	return nil, nil
end

--- The A/B modes a group is built in (the spec's order, SHOWCASE_AB by default): all but the litPlainOnly
--- ones, which only a plain crossing with lights gets.
function logic.showcaseModes(kind : string, lightsOff : boolean, spec? : SquareStressShowcaseSpec) : {SquareStressShowcaseAb}
	local out : {SquareStressShowcaseAb} = {}
	for _, m in ipairs(logic.specModes(spec)) do
		if not m.litPlainOnly or (kind == "plain" and not lightsOff) then out[#out + 1] = m end
	end
	return out
end

--- The Showcase on a w x h map (positions are offsets from the map centre; town centres and junction
--- reaches at least `margin` inside the map): as many groups as fit, the kinds in turn (interchange,
--- roundabout, plain), each kind's types in turn; a kind stops after SHOWCASE_MISSES draws in a row that
--- fit nowhere (the next types may be smaller), the others go on filling the gaps. Every drawn group is placed once per A/B mode (showcaseModes),
--- the twins side by side and next in the list ("Group 3a", "Group 3b", ...: set 3), identical but
--- for their position. Towns are named by test, set, side and mode (showcaseTownName: "Parclo 3 N
--- (Smart lanes)", Lights showcase "Smart lanes 3 N"; Remove towns > Grid towns removes them: isTestTownName), each with the spec's one size (TOWN_SIZES index). spec (default SHOWCASE_SPEC): the kinds (slots in
--- turn: group.slot; group.kind is its type's kind), their types, the A/B modes, the town size and
--- clearance (Lights showcase: LIGHTS_SPEC).
function logic.showcaseLayout(w : number, h : number, margin : number, seed : integer, spec? : SquareStressShowcaseSpec) : SquareStressShowcaseLayout
	local rng = logic.newRng(seed)
	local out : SquareStressShowcaseLayout = { seed = seed, towns = {}, groups = {}, square = specOf(spec).square == true }
	local left, right = -w / 2 + margin, w / 2 - margin
	local bottom, top = -h / 2 + margin, h / 2 - margin
	if not (right > left and top > bottom) then return out end
	local kinds = logic.specKinds(spec)
	local maxMisses = specOf(spec).misses or logic.SHOWCASE_MISSES
	local nextType : {string : integer} = {}
	local full : {string : boolean} = {}
	local misses : {string : integer} = {}
	local nFull, k, set = 0, 0, 0
	local placed : {{number}} = {}
	-- perType (Lights showcase): at most that many sets of each type; a kind whose types are all done is full
	local perType = specOf(spec).perType
	local typeSets : {string : integer} = {}
	-- a kind may be listed more than once (its share of the turns): the loop ends when every distinct kind is full
	local distinct : {string : boolean} = {}
	local nKinds = 0
	for _, kd in ipairs(kinds) do
		if not distinct[kd] then
			distinct[kd] = true
			nKinds = nKinds + 1
		end
	end
	while nFull < nKinds and #out.groups < logic.SHOWCASE_MAX_GROUPS do
		local kind = kinds[k % #kinds + 1]
		k = k + 1
		local types = logic.specTypes(spec, kind)
		if not full[kind] and perType ~= nil then
			-- the kind's next type that still needs a set (in turn), else the kind is full
			local n0 = nextType[kind] or 0
			local found = false
			for d = 0, #types - 1 do
				local t = types[(n0 + d) % #types + 1]
				if (typeSets[t.id] or 0) < perType then
					nextType[kind] = n0 + d
					found = true
					break
				end
			end
			if not found then
				full[kind] = true
				nFull = nFull + 1
			end
		end
		-- a kind without types is full at once (never a division by zero below)
		if not full[kind] and #types == 0 then
			full[kind] = true
			nFull = nFull + 1
		end
		if not full[kind] then
			local n = nextType[kind] or 0
			local tp = types[n % #types + 1]
			local g = drawGroup(rng, tp, spec)
			local modes = logic.showcaseModes(g.kind, g.place.lightsOff, spec)
			-- a set comes whole or not at all: its twins must stay within the cap (else a miss); a set with no twin at
			-- all (every mode litPlainOnly for an unlit kind) is a miss too, never an empty set placed
			local x, y : number, number = nil, nil
			if #modes > 0 and #out.groups + #modes <= logic.SHOWCASE_MAX_GROUPS then
				x, y = fitSet(g, #modes, placed, left, right, bottom, top)
			end
			nextType[kind] = n + 1
			if x == nil then
				-- the kind's next types (or draws) may be smaller: it stops after SHOWCASE_MISSES misses in a row
				misses[kind] = (misses[kind] or 0) + 1
				if misses[kind] >= maxMisses then
					full[kind] = true
					nFull = nFull + 1
				end
			else
				misses[kind] = 0
				set = set + 1
				typeSets[tp.id] = (typeSets[tp.id] or 0) + 1
				-- demandMix (the light plans A/B): the set's demand by its shape and its count of that shape
				local demand : string = nil
				if specOf(spec).demandMix then demand = logic.lightsPlansDemand(n % #types + 1, typeSets[tp.id]) end
				for t, m in ipairs(modes) do
					-- alternateTwins: per type the twins' positions rotate by one with each of its sets (its k-th set puts
					-- twin t at position (t - 1 + k - 1) mod n + 1), so over n sets of a type every twin sits once in every
					-- position (two twins: every second set swapped; three: west / middle / east in turn)
					local slotT = t
					if specOf(spec).alternateTwins then slotT = (t - 1 + (typeSets[tp.id] or 1) - 1) % #modes + 1 end
					local tx = x + (slotT - 1) * 2 * g.R
					placed[#placed + 1] = { tx, y, g.R }
					-- + 0.0: a zero stays +0, never -0 (docs/findings.md "Negative zero in construction geometry")
					local pl : SquareStressShowcasePlacement = { case_ = g.place.case_, x = tx + 0.0, y = y + 0.0, angle = g.place.angle,
						reach = g.place.reach, lightsOff = g.place.lightsOff }
					local group : SquareStressShowcaseGroup = { name = string.format("Group %d%s", set, m.twin), kind = g.kind, slot = kind,
						place = pl, towns = {}, oneWay = g.oneWay, R = g.R, set = set, twin = m.twin, ab = m.ab, demand = demand }
					for i, o in ipairs(g.offsets) do
						local ti = #out.towns + 1
						local pop, word : number, string = nil, nil
						if demand ~= nil then pop, word = logic.lightsPlansTownPop(demand, g.sides[i]) end
						out.towns[ti] = { x = tx + o[1] + 0.0, y = y + o[2] + 0.0, row = 1, col = ti, size = g.sizes[i],
							name = logic.showcaseTownName(g.type_, m, set, g.sides[i], specOf(spec).modeNames == true, word), pop = pop }
						-- a town wanted below its size's initial capacity is created with that capacity (lightsPlansTownPop)
						local caps = (logic.TOWN_SIZES[g.sizes[i]] or {}).caps
						if pop ~= nil and caps ~= nil and pop < caps then out.towns[ti].townCaps = math.floor(pop) end
						group.towns[i] = ti
					end
					out.groups[#out.groups + 1] = group
				end
			end
		end
	end
	return out
end

--- Showcase build, after the check refused a placement with "Construction Not Possible": a fresh
--- draw of the same type (rng from `seed`) that keeps its arms (the arm count / layout, a plain
--- crossing's angle and side road, the arm road: the group's towns stay right) and fits in maxReach;
--- nil when 40 draws find none that differs from the refused one.
function logic.showcaseRedraw(case_ : SquareStressJunctionCase, maxReach : number, seed : integer, spec? : SquareStressShowcaseSpec) : SquareStressJunctionCase
	local t : SquareStressShowcaseType = nil
	for _, sp in ipairs({ specOf(spec), logic.SHOWCASE_SPEC }) do
		for _, kind in ipairs(logic.specKinds(sp)) do
			for _, x in ipairs(logic.specTypes(sp, kind)) do
				if t == nil and x.id == case_.id then t = x end
			end
		end
	end
	if t == nil then return nil end
	local rng = logic.newRng(seed)
	local was = logic.showcaseParamText(case_)
	local road : integer = nil
	if t.armKey ~= nil and case_.params[t.armKey] ~= nil then road = math.floor(case_.params[t.armKey]) end
	for _ = 1, 40 do
		local c = logic.showcaseDraw(rng, t, road)
		for _, key in ipairs({ "sqrb_arms", "sqst_x_angle", "sqst_x_side" }) do
			if case_.params[key] ~= nil then c.params[key] = case_.params[key] end
		end
		if c.params.sqst_x_side ~= nil and c.params.sqst_x_side >= PLAIN_ONE_WAY and c.params.sqst_x_side2 ~= nil then c.params.sqst_x_side2 = 1 end
		if logic.showcaseReach(c) <= maxReach and logic.showcaseParamText(c) ~= was then return c end
	end
	return nil
end

--- Counts of a layout: groups (twins each counted), towns, groups per kind (the spec's slots: ix, rb,
--- plain; Lights showcase x, t), groups per A/B mode.
function logic.showcaseCounts(layout : SquareStressShowcaseLayout, spec? : SquareStressShowcaseSpec) : integer, integer, {string : integer}, {string : integer}
	local by : {string : integer} = {}
	for _, k in ipairs(logic.specKinds(spec)) do by[k] = 0 end
	local ab : {string : integer} = {}
	for _, m in ipairs(logic.specModes(spec)) do ab[m.ab] = 0 end
	for _, g in ipairs(layout.groups) do
		local slot = g.slot or g.kind
		by[slot] = (by[slot] or 0) + 1
		if g.ab ~= nil then ab[g.ab] = (ab[g.ab] or 0) + 1 end
	end
	return #layout.groups, #layout.towns, by, ab
end

--- Every group's zone with its A/B mode, for the traffic log and the Smart Lanes channel
--- (slZonesPayload): id "g3a", pair "g3" (its set), ab, kind, type label, centre (layout offset + cx, cy), r (the
--- reach estimate), towns.
--- A square layout's approach length (m) of a group (BENCH.md, FLOW.md "thru"): from the junction out along its arms
--- to just before its towns' entry roundabouts (the nearest town's distance - its grid half - ENTRY_REACH - 20 m), the
--- straight link where every car on the inbound side is bound for the junction; nil outside a square layout.
function logic.groupApproach(layout : SquareStressShowcaseLayout, g : SquareStressShowcaseGroup) : number
	if not layout.square or g == nil or #(g.towns or {}) == 0 then return nil end
	local best : number = nil
	for _, ti in ipairs(g.towns) do
		local t = layout.towns[ti]
		if t ~= nil then
			local d = math.sqrt((t.x - g.place.x) ^ 2 + (t.y - g.place.y) ^ 2) - logic.gridHalfOfSize(t.size or 1) - logic.ENTRY_REACH - 20
			if best == nil or d < best then best = d end
		end
	end
	if best == nil or best <= (g.place.reach or 0) then return nil end
	return math.floor(best)
end

function logic.showcaseZones(layout : SquareStressShowcaseLayout, cx? : number, cy? : number) : {SquareStressShowcaseZone}
	local out : {SquareStressShowcaseZone} = {}
	for _, g in ipairs(layout.groups) do
		-- a bench sheet's ids carry its key ("s2g10a"): zone ids repeat across sheets run in one session (BENCH.md)
		local pre = layout.idPrefix or ""
		out[#out + 1] = { id = string.format("%sg%d%s", pre, g.set or 0, g.twin or ""), pair = string.format("%sg%d", pre, g.set or 0), ab = g.ab,
			kind = g.kind, label = g.place.case_.label, x = (cx or 0) + g.place.x, y = (cy or 0) + g.place.y, r = g.place.reach,
			towns = #g.towns, test = g.test, variant = g.variant, geom = g.geom, approach = logic.groupApproach(layout, g), demand = g.demand,
			mix = g.mix, ringMix = g.ringMix }
	end
	return out
end

-- The Stress Test -> Smart Lanes zones channel (plans/square_stress_test/FLOW.md "[SQRL] ZONES"; Smart Lanes
-- sl_zones.lua is the receiving side and validates the same bounds: keep them in step).
logic.SL_ZONES_MAX = 400          -- zones per event (Smart Lanes ignores a bigger event as a whole)
logic.SL_ZONE_R_MAX = 2000.0      -- m, largest radius Smart Lanes accepts
logic.SL_ZONE_PAD = 20.0          -- m added to the reach estimate: the junction's nodes all lie inside
logic.SL_ZONE_AB = { game = true, sl = true, sl_phases = true, sl_fan = true, sl_lock = true, sl_exitfan = true, sl_keeplights = true,
	sl_rturbo = true, sl_rmatch = true, sl_rout1 = true, sl_r2exit = true, sl_rspiral = true, sl_rspread = true, sl_rsplit = true, sl_rmid = true,
	sl_auto = true, sl_rmid2 = true, sl_rturbo_in = true }
logic.SL_ZONE_LABEL_MAX = 12      -- characters of a zone's id / pair label (Smart Lanes LABEL_MAX)

--- A twin id / pair label for the zones payload ("g3a", "g3"): Smart Lanes stores labels of 1..12 [%w_]
--- characters and drops others (sl_zones.lua validLabel), so anything else is left out here (nil).
function logic.slZoneLabel(v : string) : string
	if type(v) ~= "string" or #v == 0 or #v > logic.SL_ZONE_LABEL_MAX or v:match("^[%w_]+$") == nil then return nil end
	return v
end

--- The "SmartLanes.zones" set payload of a Showcase run: { op = "set", run, zones = {{x, y, r, ab, id, pair}} }
--- (id / pair: the twin labels, read back after a reload by the traffic log, gui/stress_flow_log.tl) with
--- r = reach + SL_ZONE_PAD (at most SL_ZONE_R_MAX), numbers rounded to 0.1 m; zones without a known ab or a
--- usable position are left out; at most SL_ZONES_MAX (the rest dropped). Second result: zones dropped.
function logic.slZonesPayload(zones : {SquareStressShowcaseZone}, run : string) : {string : any}, integer
	local list : {{string : any}} = {}
	local dropped = 0
	for _, z in ipairs(zones or {}) do
		local okXY = type(z.x) == "number" and type(z.y) == "number" and z.x == z.x and z.y == z.y
		if okXY and logic.SL_ZONE_AB[z.ab] and type(z.r) == "number" and z.r > 0 and #list < logic.SL_ZONES_MAX then
			local r = math.min(logic.SL_ZONE_R_MAX, z.r + logic.SL_ZONE_PAD)
			list[#list + 1] = { x = math.floor(z.x * 10 + 0.5) / 10, y = math.floor(z.y * 10 + 0.5) / 10,
				r = math.floor(r * 10 + 0.5) / 10, ab = z.ab, id = logic.slZoneLabel(z.id), pair = logic.slZoneLabel(z.pair) }
		else
			dropped = dropped + 1
		end
	end
	return { op = "set", run = run, zones = list }, dropped
end

--- A run id for the zones channel: "s<seed>-<time>-<n>" (seed of the Showcase, wall clock seconds, the
--- session's send counter), so an acknowledgement from an older run or save never matches. Only
--- [0-9a-z.-] characters, at most 40.
function logic.slZoneRun(seed : integer, wallS : integer, n : integer) : string
	return string.format("s%d-%d-%d", math.floor(seed or 0) % 1000000000, math.floor(wallS or 0) % 1000000000, math.floor(n or 0) % 100000)
end

--- "game:a,sl:b,sl_phases:c" of a payload's zones, then ",sl_fan:d", ",sl_lock:e" and ",sl_exitfan:f" each only when > 0 (the log
--- line; Smart Lanes logs the same on receipt, sl_zones.lua M.byAbText).
function logic.slZonesByAb(list : {{string : any}}) : string
	local c : {string : integer} = { game = 0, sl = 0, sl_phases = 0, sl_fan = 0, sl_lock = 0, sl_exitfan = 0, sl_keeplights = 0,
		sl_rturbo = 0, sl_rmatch = 0, sl_rout1 = 0, sl_r2exit = 0, sl_rspiral = 0, sl_rspread = 0, sl_rsplit = 0, sl_rmid = 0, sl_auto = 0,
		sl_rmid2 = 0, sl_rturbo_in = 0 }
	for _, z in ipairs(list or {}) do
		local ab = z.ab as string
		if c[ab] ~= nil then c[ab] = c[ab] + 1 end
	end
	local s = string.format("game:%d,sl:%d,sl_phases:%d", c.game, c.sl, c.sl_phases)
	if c.sl_fan > 0 then s = s .. string.format(",sl_fan:%d", c.sl_fan) end
	if c.sl_lock > 0 then s = s .. string.format(",sl_lock:%d", c.sl_lock) end
	if c.sl_exitfan > 0 then s = s .. string.format(",sl_exitfan:%d", c.sl_exitfan) end
	-- the bench's lights twin (BENCH.md "What Smart Lanes must add" SL-1: after sl_exitfan, only when > 0)
	if c.sl_keeplights > 0 then s = s .. string.format(",sl_keeplights:%d", c.sl_keeplights) end
	-- the ring layout modes (square_smart_lanes PLAN.md "Ring layout variants (bench)"), then the auto re-timing twin
	-- (sl_auto, the light plans A/B: Smart Lanes PLAN.md "Stress Test interface: Keep timing adjusted"), then the ring lane
	-- use modes (sl_rmid2, sl_rturbo_in after sl_auto: Smart Lanes PLAN.md "Ring lane use"), in Smart Lanes' byAbText order,
	-- each only when > 0 (sl_classic, Smart Lanes' classic patterns, is gone since 2026-10-16: no longer sent or counted)
	for _, m in ipairs({ "sl_rturbo", "sl_rmatch", "sl_rout1", "sl_r2exit", "sl_rspiral", "sl_rspread", "sl_rsplit", "sl_rmid", "sl_auto",
			"sl_rmid2", "sl_rturbo_in" }) do
		if c[m] > 0 then s = s .. string.format(",%s:%d", m, c[m]) end
	end
	return s
end

--- "Build showcase".
function logic.showcaseLabel() : string
	return "Build showcase"
end

--- "Build light plans A/B" (the Lights showcase's second button).
function logic.lightsPlansLabel() : string
	return "Build light plans A/B"
end

--- "Build lights showcase" or, with the next shape, "Build lights showcase (2x2 X)".
function logic.lightsShowcaseLabel(shape? : string) : string
	if shape ~= nil then return "Build lights showcase (" .. shape .. ")" end
	return "Build lights showcase"
end

--- Bus routes (town index pairs) of a Showcase run: per group the towns across its ring (k with
--- k + n/2 for n even, else k with k + (n-1)/2 for k = 1 .. (n+1)/2, so every town has a line), only
--- arm pairs linked in EVERY twin of its set (groupLinked: group index -> set of its town positions
--- 1..n), so the twins get identical routes; none to or from a town on a one-way road (g.oneWay). Every
--- set's first route (in all its twins) first, then every set's second, ...; a set's twins are added
--- together or not at all under the cap maxN. Each route is {town a, town b, group index} (the towns of
--- one group share a road network; the bus lines reuse depots only within it).
function logic.showcaseRoutes(layout : SquareStressShowcaseLayout, groupLinked : {integer : {integer : boolean}}, maxN : integer) : {{integer}}
	-- sets in order, each its twins' group indices
	local sets : {{integer}} = {}
	local setOf : {integer : integer} = {}
	for gi, g in ipairs(layout.groups) do
		local key = g.set or -gi
		if setOf[key] == nil then
			sets[#sets + 1] = {}
			setOf[key] = #sets
		end
		local list = sets[setOf[key]]
		list[#list + 1] = gi
	end
	local per : {{{integer}}} = {}   -- set -> its arm pairs linked in every twin
	local most = 0
	for si, twins in ipairs(sets) do
		local g = layout.groups[twins[1]]
		local n = #g.towns
		local pairs_ : {{integer}} = {}
		if n >= 2 then
			local half = math.floor(n / 2)
			local last = n % 2 == 0 and half or half + 1
			local oneWay = g.oneWay or {}
			for k = 1, last do
				local j = k + half
				if j > n then j = j - n end
				local all = not oneWay[k] and not oneWay[j]
				for _, gi in ipairs(twins) do
					local linked = groupLinked ~= nil and groupLinked[gi] or nil
					if linked == nil or not linked[k] or not linked[j] then all = false end
				end
				if all then pairs_[#pairs_ + 1] = { k, j } end
			end
		end
		per[si] = pairs_
		most = math.max(most, #pairs_)
	end
	local out : {{integer}} = {}
	for r = 1, most do
		for si, twins in ipairs(sets) do
			local pr = per[si][r]
			if pr ~= nil and #out + #twins <= maxN then
				for _, gi in ipairs(twins) do
					local g = layout.groups[gi]
					out[#out + 1] = { g.towns[pr[1]], g.towns[pr[2]], gi }
				end
			end
		end
	end
	return out
end

--- Whether the twins of one set still match as built (FLOW.md "Showcase zones" `match`): nil when
--- they do, else the reason(s), comma-separated: "town" (lostTown: a town of one of its twins was
--- skipped, so its arms and bus lines differ), "link" (lostLink: an arm of one of its twins was left
--- unlinked, its link refused or no node of its own town to end on: known only after the links, so it
--- comes on a `showcase zone_match` line, showcaseZoneMatchLine), "redrawn" (a twin was redrawn after "Construction Not
--- Possible" while another was not, the redraws differ, or a redrawn twin was not built; all twins
--- redrawn the same way and built still match).
function logic.showcaseMatch(twins : {SquareStressShowcaseTwin}, lostTown : boolean, lostLink? : boolean, lostEntry? : boolean) : string
	local reasons : {string} = {}
	if lostTown then reasons[#reasons + 1] = "town" end
	if lostLink then reasons[#reasons + 1] = "link" end
	-- Lights showcase: its towns' entries differ between twins (a roundabout refused, or not joined to its grid)
	if lostEntry then reasons[#reasons + 1] = "entry" end
	local any, same = false, true
	for _, t in ipairs(twins) do
		if t.redrawn then any = true end
		if not t.built or not t.redrawn or t.params ~= twins[1].params then same = false end
	end
	if any and not same then reasons[#reasons + 1] = "redrawn" end
	if #reasons == 0 then return nil end
	return table.concat(reasons, ",")
end

--- The zone line of a group for the traffic log (plans/square_stress_test/FLOW.md "Showcase zones"):
--- "[SQST] showcase zone id=g3a pair=g3 ab=sl kind=roundabout type=Magic_Roundabout x=1200 y=-3400 r=167
--- r_from=measured towns=5 match=yes" (z.reason set: "match=no reason=redrawn").
function logic.showcaseZoneLine(z : SquareStressShowcaseZone, measured : boolean) : string
	local typ = (z.label or "?"):gsub("[%s,]+", "_")
	local s = string.format("[SQST] showcase zone id=%s pair=%s ab=%s kind=%s type=%s x=%.0f y=%.0f r=%.0f r_from=%s towns=%d %s", z.id, z.pair,
		tostring(z.ab), logic.SHOWCASE_KIND_NAMES[z.kind] or "other", typ, z.x, z.y, z.r, measured and "measured" or "est", z.towns,
		z.reason ~= nil and ("match=no reason=" .. z.reason) or "match=yes")
	-- the bench (BENCH.md "Log contract additions"): its test and variant; keys only added
	if z.test ~= nil then s = s .. " test=" .. z.test .. " variant=" .. ((z.variant or "-"):gsub("[%s,]+", "_")) end
	-- a bench twin on a named ring geometry (Sheet 4 v5): tools/flow_report.py reads its mode as "<ab>@<geom>"
	if z.geom ~= nil then s = s .. " geom=" .. z.geom end
	if z.approach ~= nil then s = s .. string.format(" approach=%.0f", z.approach) end
	-- the light plans A/B's demand of the set (balanced / unbalanced; tools/flow_report.py splits its tables by it)
	if z.demand ~= nil then s = s .. " demand=" .. z.demand end
	-- the bench Sheet 5's traffic mix of the set (even / straight / adjacent; tools/flow_report.py "Ring lane use")
	if z.mix ~= nil then s = s .. " mix=" .. z.mix end
	return s
end

--- The late verdict of one twin's zone after the links (FLOW.md "Showcase zones"): "[SQST] showcase
--- zone_match id=g1b pair=g1 match=no reason=link". The zone line itself is written at the read, before
--- the links; tools/flow_report.py applies this line to the zone of that id in the current run.
function logic.showcaseZoneMatchLine(z : SquareStressShowcaseZone) : string
	return string.format("[SQST] showcase zone_match id=%s pair=%s %s", z.id, z.pair,
		z.reason ~= nil and ("match=no reason=" .. z.reason) or "match=yes")
end

--- The country street of a link road (SHOWCASE.md "Link roads are country roads"): the base
--- country_{new,old}_{small,medium,large} template whose road lanes match a two-way street's
--- (carLanes = road lanes both ways together: 2, 4, 6; base templates have 2 / 4 / 6 CAR lanes plus two
--- sidewalk lanes, as town_*_{small,medium,large}), new from WIDE_GRID_NEW_FROM (country_new yearFrom 1940,
--- country_old yearTo 1940). nil for any other count (one-way streets, highways keep their own type).
-- country = true: "no houses will spawn along streets of this type" (wiki modding/infrastructure/
-- tracksstreets.md:170, base country_*.street_template.lua `country = true`; town_* have no such field).
function logic.countryTemplate(carLanes : integer, year? : integer) : string
	local size = ({ [2] = "small", [4] = "medium", [6] = "large" } as {integer : string})[carLanes or 0]
	if size == nil then return nil end
	local era = (year ~= nil and year < logic.WIDE_GRID_NEW_FROM) and "old" or "new"
	return string.format("::/infrastructure/street/country/country_%s_%s.street_template", era, size)
end

---------------------------------------------------------------------------
-- Batched building (SHOWCASE.md "Faster, simpler Lights showcase + batched building"): several pieces
-- per command, each batch falling back to one by one on refusal.

logic.GRID_BATCH = 10            -- street grid constructions per proposal (createGrid batch)
logic.LINK_GROUP_MAX = 8         -- town links per proposal (Showcase links)
logic.LINK_GROUP_GAP = 200.0     -- links of one proposal stay this far apart beyond their footprints
logic.TOWN_MATCH_MAX = 600.0     -- a batch-created town is matched to the nearest asked point within this
logic.BATCH_TIMEOUT_MS = 600000  -- a batched step (all towns in one command, a refused batch one by one) may take this long

--- Shortest distance between segments a0-a1 and b0-b1 (2D; 0 when they cross).
function logic.segDist(a0 : {number}, a1 : {number}, b0 : {number}, b1 : {number}) : number
	local function orient(p : {number}, q : {number}, r : {number}) : number
		return (q[1] - p[1]) * (r[2] - p[2]) - (q[2] - p[2]) * (r[1] - p[1])
	end
	local d1, d2 = orient(a0, a1, b0), orient(a0, a1, b1)
	local d3, d4 = orient(b0, b1, a0), orient(b0, b1, a1)
	if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)) then return 0.0 end
	return math.min(logic.distToSegment(a0, b0, b1), logic.distToSegment(a1, b0, b1), logic.distToSegment(b0, a0, a1),
		logic.distToSegment(b1, a0, a1))
end

--- Groups of links that may share one proposal: items {x0, y0, x1, y1, r} (a link's footprint: the
--- segment from its arm end to its town's centre, widened by r), in order; each group starts at the first
--- ungrouped item and takes every later ungrouped one whose footprint stays `gap` clear of all its
--- members', up to maxN. Indices into items, every item in exactly one group, groups in order of their
--- first item.
function logic.groupLinks(items : {{number}}, gap : number, maxN : integer) : {{integer}}
	local out : {{integer}} = {}
	local taken : {integer : boolean} = {}
	local function apart(i : integer, j : integer) : boolean
		local a, b = items[i], items[j]
		local d = logic.segDist({ a[1], a[2] }, { a[3], a[4] }, { b[1], b[2] }, { b[3], b[4] })
		return d >= (a[5] or 0) + (b[5] or 0) + gap
	end
	for i = 1, #items do
		if not taken[i] then
			local g : {integer} = { i }
			taken[i] = true
			for j = i + 1, #items do
				if #g >= maxN then break end
				if not taken[j] then
					local ok = true
					for _, k in ipairs(g) do
						if not apart(k, j) then ok = false break end
					end
					if ok then
						g[#g + 1] = j
						taken[j] = true
					end
				end
			end
			out[#out + 1] = g
		end
	end
	return out
end

--- Matches points to found positions one to one, nearest pairs first, each pair within maxD: the
--- result maps point index -> found index (points without a match are missing). Ties by index.
function logic.matchNearest(points : {{number}}, found : {{number}}, maxD : number) : {integer : integer}
	local pairs_ : {{number}} = {}
	for i, p in ipairs(points) do
		for j, f in ipairs(found) do
			local d = math.sqrt((p[1] - f[1]) ^ 2 + (p[2] - f[2]) ^ 2)
			if d <= maxD then pairs_[#pairs_ + 1] = { d, i, j } end
		end
	end
	table.sort(pairs_, function(a : {number}, b : {number}) : boolean
		if a[1] ~= b[1] then return a[1] < b[1] end
		if a[2] ~= b[2] then return a[2] < b[2] end
		return a[3] < b[3]
	end)
	local out : {integer : integer} = {}
	local used : {integer : boolean} = {}
	for _, pr in ipairs(pairs_) do
		local i, j = math.floor(pr[2]), math.floor(pr[3])
		if out[i] == nil and not used[j] then
			out[i] = j
			used[j] = true
		end
	end
	return out
end

-- The phases of a Showcase run's timing line, in order (ms each; SHOWCASE.md "Timing").
logic.TIMING_PHASES = { "towns", "grids", "locks", "junctions", "links", "depots", "density" }

--- "[SQST] <id> timing towns=Nms grids=Nms ... total=Nms (X.X min)": every phase of TIMING_PHASES (0 when
--- it did not run), the total since the press.
function logic.timingLine(id : string, t : {string : number}, totalMs : number) : string
	local parts : {string} = {}
	for _, k in ipairs(logic.TIMING_PHASES) do parts[#parts + 1] = string.format("%s=%.0fms", k, (t or {})[k] or 0) end
	return string.format("[SQST] %s timing %s total=%.0fms (%s min)", id, table.concat(parts, " "), totalMs or 0, logic.minutesText(totalMs))
end

--- Milliseconds as minutes with one decimal ("2.3").
function logic.minutesText(ms : number) : string
	return string.format("%.1f", (ms or 0) / 60000)
end

--- The one-line summary of a run: "Showcase done: 4 of 4 interchanges, 4 of 4 roundabouts, 5 of 5
--- plain junctions built (sl 5/5, game 5/5, sl_phases 3/3), 40 of 41 links; 12 bus lines queued. Seed 777."
--- skipped: towns left out for want of land (", 2 towns skipped (no land)" after the links).
--- spec (default SHOWCASE_SPEC): its title, kinds (kindWords) and modes; with growFactor the towns'
--- growth follows the links ("; every town then grows x10 in 3 build-out passes, locked to its grid").
function logic.showcaseSummary(built : {string : integer}, planned : {string : integer}, builtAb : {string : integer},
		plannedAb : {string : integer}, linked : integer, links : integer, lines : integer, seed : integer, skipped? : integer,
		spec? : SquareStressShowcaseSpec) : string
	local sp = specOf(spec)
	local parts : {string} = {}
	for _, kind in ipairs(logic.specKinds(sp)) do
		parts[#parts + 1] = string.format("%d of %d %s", built[kind] or 0, planned[kind] or 0, (sp.kindWords or {})[kind] or kind)
	end
	local modes : {string} = {}
	for _, m in ipairs(logic.specModes(sp)) do
		modes[#modes + 1] = string.format("%s %d/%d", m.ab, builtAb[m.ab] or 0, plannedAb[m.ab] or 0)
	end
	local s = string.format("%s done: %s built (%s), %d of %d links", sp.title or "Showcase", table.concat(parts, ", "), table.concat(modes, ", "),
		linked, links)
	if skipped ~= nil and skipped > 0 then
		s = s .. string.format(", %d town%s skipped (no land)", skipped, skipped == 1 and "" or "s")
	end
	if sp.growFactor ~= nil and (sp.growPasses or 1) > 1 then
		s = s .. string.format("; every town then grows x%g in %d build-out passes%s", sp.growFactor, sp.growPasses or 1,
			sp.lockStreets and ", locked to its grid" or "")
	elseif sp.growTarget ~= nil and sp.demandMix then
		s = s .. string.format("; every town then grows to about %d people (one size command, no build-out passes)%s, but in the unbalanced sets the north town to about %d and the south town to about %d",
			math.floor(sp.growTarget), sp.lockStreets and ", locked to its grid" or "", math.floor(logic.LIGHTS_PLANS_POPS.small), math.floor(logic.LIGHTS_PLANS_POPS.tiny))
	elseif sp.growTarget ~= nil then
		s = s .. string.format("; every town then grows to about %d people (one size command, no build-out passes)%s", math.floor(sp.growTarget),
			sp.lockStreets and ", locked to its grid" or "")
	elseif sp.growFactor ~= nil then
		s = s .. string.format("; every town then grows x%g (one size command, no build-out passes)%s", sp.growFactor,
			sp.lockStreets and ", locked to its grid" or "")
	end
	if sp.noBusLines then
		s = s .. "; no bus lines (the towns' own traffic)"
	elseif lines > 0 then
		s = s .. string.format("; %d bus line%s queued", lines, lines == 1 and "" or "s")
	else
		s = s .. "; no bus lines (no route with both towns linked)"
	end
	return s .. string.format(". Seed %d.", seed)
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
