-- Replays engine verdicts from the probe (plans/square_roundabouts/probe_search*.csv and
-- probe_results.csv, written by tools/parse_probe.py) against the shipped geometry. Loaded with
-- loadfile like checks.lua; used by test_engine_verdicts.lua. Every function returns a list of
-- problems (strings); empty = the geometry agrees with the engine.

local V = {}

--- Minimal CSV reader (header row, quoted fields with "" escapes). Returns rows or nil if missing.
function V.readCsv(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local text = f:read("a")
	f:close()
	local rows, header = {}, nil
	local pos, n = 1, #text
	local function record()
		local fields = {}
		while true do
			local c = text:sub(pos, pos)
			local value
			if c == '"' then
				local parts = {}
				pos = pos + 1
				while true do
					local q = text:find('"', pos, true)
					parts[#parts + 1] = text:sub(pos, q - 1)
					pos = q + 1
					if text:sub(pos, pos) == '"' then
						parts[#parts + 1] = '"'
						pos = pos + 1
					else
						break
					end
				end
				value = table.concat(parts)
			else
				local stop = text:find("[,\r\n]", pos) or n + 1
				value = text:sub(pos, stop - 1)
				pos = stop
			end
			fields[#fields + 1] = value
			local d = text:sub(pos, pos)
			if d == "," then
				pos = pos + 1
			else
				if d == "\r" then pos = pos + 1 end
				if text:sub(pos, pos) == "\n" then pos = pos + 1 end
				return fields
			end
		end
	end
	while pos <= n do
		local fields = record()
		if not header then
			header = fields
		elseif #fields > 1 or fields[1] ~= "" then
			local row = {}
			for i, k in ipairs(header) do row[k] = fields[i] or "" end
			rows[#rows + 1] = row
		end
	end
	return rows
end

--- "m:1,2,5,..." -> "m", {1, 2, 5, ...}
function V.parseKey(key)
	local tag, rest = tostring(key):match("^(%a+):(.*)$")
	local idx = {}
	for x in (rest or ""):gmatch("[^,]+") do idx[#idx + 1] = tonumber(x) end
	return tag, idx
end

-- "throughRoad" was appended to the probe's main axes in Phase 5e: 11-value keys = Same as arms.
local MAIN_ORDER = { "shape", "lanes", "radius", "arms", "splitter", "centre", "armType", "tram", "direction", "island", "signals", "throughRoad" }
-- "lanes" (Magic satellite ring lanes) was appended to the probe's axes later: keys logged
-- before it have 4 values ("g:size,arm,dir,island") and mean 1 lane (V.magicLanes).
local MAGIC_ORDER = { "size", "armType", "direction", "island", "lanes" }

--- Construction params of a probe replay key (no dev overrides). Values the key lacks are left
-- out (the construction's default).
function V.params(key, geomKeys, magicKeys)
	local tag, idx = V.parseKey(key)
	local order, keys = MAIN_ORDER, geomKeys
	if tag == "g" then order, keys = MAGIC_ORDER, magicKeys end
	local p = {}
	for i, name in ipairs(order) do
		if keys[name] ~= nil and idx[i] ~= nil then p[keys[name]] = idx[i] end
	end
	return p, tag
end

--- Satellite lanes of a Magic replay key (1 for the 4-value keys from before the lanes axis).
function V.magicLanes(key)
	local _, idx = V.parseKey(key)
	return idx[5] or 1
end

--- Tuning-row id of a Magic replay key, as magic.sizeFloor looks it up: "armType,direction" for
-- 1-lane satellites, "armType,direction,<lanes>" otherwise (that row, when probed, is the 2-lane
-- verdict; the 1-lane row is only a fallback for unprobed 2-lane combos).
function V.magicRowKey(key)
	local _, idx = V.parseKey(key)
	local lanes = idx[5] or 1
	return idx[2] .. "," .. idx[3] .. (lanes ~= 1 and ("," .. lanes) or "")
end

local function num(v) return tonumber(v) end

local function radiiOf(list)
	local out = {}
	for item in tostring(list or ""):gmatch("[^|]+") do
		local v = item:match("^radius=(.+)$")
		if v then out[tonumber(v)] = true end
	end
	return out
end

--- Deterministic text of a value (sorted keys, numbers to 1e-4), to compare layouts.
function V.text(v, out)
	out = out or {}
	if type(v) == "number" then
		local t = string.format("%.4f", v)
		out[#out + 1] = t == "-0.0000" and "0.0000" or t
	elseif type(v) ~= "table" then
		out[#out + 1] = tostring(v)
	else
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			if type(a) == type(b) then return a < b end
			return type(a) < type(b)
		end)
		out[#out + 1] = "{"
		for _, k in ipairs(keys) do
			out[#out + 1] = tostring(k) .. "="
			V.text(v[k], out)
			out[#out + 1] = ","
		end
		out[#out + 1] = "}"
	end
	return out
end

local function same(_, a, b)
	return table.concat(V.text(a)) == table.concat(V.text(b))
end

--- Known gaps: engine-rejected combos the shipped geometry cannot (yet) map to a layout the
-- engine accepted. Every gap a replay reports must have one of these categories (documented in
-- PLAN.md "Phase 4b notes"; the next probe runs close them).
V.GAPS = {
	none = "the engine accepted no radius up to the search maximum (120 m)",
	cw = "clockwise: not searched for this combo; the anticlockwise engine radius is its floor (288 of 288 searched clockwise minima equal the anticlockwise ones)",
	splitter = "splitter rule on a layout the splitter search did not probe (Y, 5 arms, ovals, through road or tram line, tram tracks, clockwise, sliders above the floor): search_radius_split pending",
	provisional = "splitter rule with a provisional floor (the engine accepted it at no probed radius: large arms, 5-6 arms, 1-2 lanes): search_radius_split pending",
	final = "rejected by the Phase 4b verification sweep (probe_results_4b.csv) and still shipped as swept: the next tuning round",
	channel = "Channelized Junction: no slip lane angle / template accepted yet for the layout, main road, side road and splitter; ships ch.FALLBACK (unverified; none since p5f_search, Phase 5g)",
	interchange = "Roundabout Interchange, two-bridge ring with 4 lanes: ships a radius no sweep or search accepted for the combo (alpha <= 45 deg since Phase 5g; probe p5g_verify)",
	through = "through road other than the arm road (Phase 5c) on a pattern p5_hamburger_radius did not search (splitter, ovals, tram tracks, other arm roads): the arm-road pattern's engine radius is only a floor and geom.plan decides",
}

--- Canonical main key as the tuning patterns see it: Road + traffic lights (centre 4) is Road
-- (centre 2), a 12-value key with Same as arms (through road 1) is the 11-value key, splitter on
-- with Arms None builds like splitter off (geom.patternKey).
function V.canonical(key)
	local tag, idx = V.parseKey(key)
	if tag == "m" then
		if idx[6] == 4 then idx[6] = 2 end
		if #idx == 12 and idx[12] == 1 then idx[12] = nil end
		if idx[4] == 6 then idx[5] = 1 end
	end
	return tag .. ":" .. table.concat(idx, ",")
end

--- geom.patternKey of a main replay key (Road + traffic lights = Road; another through road than
-- the arm road appends its arm road index).
function V.patternOf(key)
	local _, idx = V.parseKey(key)
	local splitter = idx[4] == 6 and 1 or idx[5]
	local centre = idx[6] == 4 and 2 or idx[6]
	local p = table.concat({ idx[1], idx[2], idx[4], splitter, centre, idx[7], idx[8], idx[9] }, ",")
	local through = idx[12]
	if centre == 2 and through and through ~= 1 and through - 1 ~= idx[7] then p = p .. "," .. (through - 1) end
	return p
end

--- Through-road patterns (geom.patternKey with a ninth field) the radius jobs searched.
function V.searchedPatterns(jobs)
	local out = {}
	for _, j in ipairs(jobs or {}) do
		if j.kind == "radius" and (j.fixed or "") == "" and (j.skipped or "") == "" then out[V.patternOf(j.key)] = true end
	end
	return out
end

--- Phase 5c "Through road": every pattern with engine data and a road through the centre
-- (Road; Road + traffic lights shares its key) also ships with the five other through roads.
-- Phase 5f: where p5_hamburger_radius searched the through-road pattern (jobs), its own cells
-- decide (V.radius / V.sweep replay them): not a gap. A clockwise pattern copied from a searched
-- anticlockwise one is a gap of category "cw"; every other one of category "through"
-- (geom.engineRadius returns the arm-road pattern's radius as a floor, source "through"; V.judge
-- leaves them to the offline model unless a sweep accepted the layout).
-- Returns problems (an unsearched through-road build that still claims an exact engine radius), gaps.
function V.through(geom, jobs)
	local problems, gaps = {}, {}
	local searched = V.searchedPatterns(jobs)
	local keys = {}
	for key in pairs(geom.tuning.radius or {}) do keys[#keys + 1] = key end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local idx = {}
		for x in key:gmatch("[^,]+") do idx[#idx + 1] = tonumber(x) end
		if #idx == 8 and idx[5] == geom.CENTRE_ROAD then
			for _, centre in ipairs({ geom.CENTRE_ROAD, geom.CENTRE_ROAD_LIGHTS }) do
				for tt = 1, #geom.ARM_TEMPLATES do
					if tt ~= idx[6] then
						local spec = geom.readParams({
							[geom.PARAM_KEYS.shape] = idx[1], [geom.PARAM_KEYS.lanes] = idx[2], [geom.PARAM_KEYS.arms] = idx[3],
							[geom.PARAM_KEYS.splitter] = idx[4], [geom.PARAM_KEYS.centre] = centre, [geom.PARAM_KEYS.armType] = idx[6],
							[geom.PARAM_KEYS.tram] = idx[7], [geom.PARAM_KEYS.direction] = idx[8],
							[geom.PARAM_KEYS.throughRoad] = tt + 1,
						})
						local own = key .. "," .. tt
						local cwOf = idx[8] == geom.DIRECTION_CW and (key:gsub(",2$", ",1") .. "," .. tt)
						if searched[own] then
							-- searched: replayed by V.radius / V.sweep
						elseif cwOf and searched[cwOf] then
							gaps[#gaps + 1] = { "cw", own .. " (centre " .. centre .. "): anticlockwise cells" }
						else
							local _, verified, source = geom.engineRadius(spec)
							if verified or (source ~= nil and source ~= "through" and source ~= "floor") then
								problems[#problems + 1] = key .. " through " .. tt .. ": engine source " .. tostring(source)
							end
							gaps[#gaps + 1] = { "through", key .. " (centre " .. centre .. ") through road " .. tt }
						end
					end
				end
			end
		end
	end
	return problems, gaps
end

--- The Phase 4b verification sweep (probe_results_4b.csv, the `all` subset of the tuned
-- geometry): every combo it rejected that still ships the swept radius (size) is a gap of
-- category "final" (listed, for the next round); a combo whose shipped radius changed since is
-- left to the next sweep. Returns problems (always empty), gaps.
function V.final(geom, magic, rows)
	local gaps = {}
	for _, r in ipairs(rows) do
		if r.ok ~= "true" then
			if r.entry == "magic" then
				local size = magic.build(magic.readParams((V.params(r.key, nil, magic.PARAM_KEYS)))).size
				if size == num(r.effSize) then gaps[#gaps + 1] = { "final", r.key .. ": size " .. size } end
			elseif r.entry == "main" then
				local built = geom.build(geom.readParams((V.params(r.key, geom.PARAM_KEYS, magic.PARAM_KEYS))))
				if built.radius == num(r.effR) then gaps[#gaps + 1] = { "final", r.key .. ": " .. built.radius .. " m (" .. tostring(r.msgs) .. ")" } end
			end
		end
	end
	return {}, gaps
end

--- Context for the replays: the probe's tram line rule (Phase 3b: a tram-only middle from
-- MIN_EDGE) and the tuning table as it was when the probe ran (neutral for search_radius / the
-- sweep; dev overrides replace any rule anyway), to rebuild the layouts the engine judged.
function V.legacy(geom, fn)
	local saved = geom.TRAM_MIDDLE_MIN
	geom.TRAM_MIDDLE_MIN = geom.MIN_EDGE
	local okRun, res = pcall(fn)
	geom.TRAM_MIDDLE_MIN = saved
	if not okRun then error(res, 0) end
	return res
end

--- Index of the radius jobs: key -> job.
function V.radiusJobs(jobs)
	local by = {}
	for _, j in ipairs(jobs) do
		if j.kind == "radius" and (j.fixed or "") == "" and (j.skipped or "") == "" then by[j.key] = j end
	end
	return by
end

local function devParams(V_, geom, magic, key, dev)
	local p = V_.params(key, geom.PARAM_KEYS, magic.PARAM_KEYS)
	for name, v in pairs(dev or {}) do p[geom.DEV_KEYS[name]] = v end
	return p
end

--- Radius jobs (S rows, kind radius, no fixed layout): what ships for the job's combo must be the
-- layout the engine accepted (the found radius, as the probe built it), or a larger radius than
-- the engine minimum (not shrunk; never one it rejected). Returns problems, gaps ({cat, text}).
function V.radius(geom, magic, jobs)
	local problems, gaps = {}, {}
	for _, j in ipairs(jobs) do
		if j.kind == "radius" and (j.fixed or "") == "" and (j.skipped or "") == "" then
			local spec = geom.readParams((V.params(j.key, geom.PARAM_KEYS, magic.PARAM_KEYS)))
			local built = geom.build(spec)
			local r = built.radius
			local best = j.found == "true" and num(j.devRadius) or nil
			if radiiOf(j.rejected)[r] then
				if best then
					problems[#problems + 1] = j.key .. ": ships " .. r .. " m, which the engine rejected (accepted " .. best .. " m)"
				else
					gaps[#gaps + 1] = { "none", j.key .. ": ships " .. r .. " m" }
				end
			elseif best and r < best - 1e-9 then
				problems[#problems + 1] = j.key .. ": ships " .. r .. " m, engine needs " .. best .. " m"
			elseif best and r == best then
				local probe = V.legacy(geom, function()
					return geom.build(geom.readParams(devParams(V, geom, magic, j.key, { radius = best })))
				end)
				if not same(geom, built.lists, probe.lists) then
					problems[#problems + 1] = j.key .. ": ships " .. r .. " m but not the layout the probe sent"
				end
			end
		end
	end
	return problems, gaps
end

--- Magic size jobs: the shipped size for each requested size must be one the engine accepted
-- (when any accepted size at or above it exists). The job's lanes come from its key (4-value
-- keys = 1 lane), so 2-lane jobs (search_magic2) judge the 2-lane build, whose floor
-- magic.sizeFloor takes from the "armType,direction,2" row (else the 1-lane row).
function V.magicSize(magic, jobs)
	local problems = {}
	for _, j in ipairs(jobs) do
		if j.kind == "magic_size" and (j.fixed or "") == "" then
			local accepted = {}
			for item in tostring(j.acceptedList or ""):gmatch("[^|]+") do
				local s = tonumber(item:match("^magicSize=(%d+)$"))
				if s then accepted[s] = true end
			end
			local p = V.params(j.key, nil, magic.PARAM_KEYS)
			for size = 1, #magic.SIZES do
				local any = false
				for s = size, #magic.SIZES do if accepted[s] then any = true end end
				if any then
					p[magic.PARAM_KEYS.size] = size
					local built = magic.build(magic.readParams(p)).size
					if not accepted[built] then
						problems[#problems + 1] = j.key .. ": size " .. size .. " ships " .. built .. ", not accepted by the engine"
					end
				end
			end
		end
	end
	return problems
end

local RULE_COLS = { split = "devSplit", fork = "devFork", spread = "devSpread", leg = "devLeg", neck = "devNeck", neckType = "devNeckType" }

local function ruleMatches(rule, t)
	for name, col in pairs(RULE_COLS) do
		local want, have = rule[name], num(t[col])
		if want ~= nil and want ~= 0 and have ~= want then return false end
		if want == 0 and have ~= nil and have ~= 0 then return false end
	end
	return true
end

--- Splitter trials with exactly a rule's parameters: (arm, lanes, layout, shape, radius) -> ok.
function V.splitterTrials(geom, trials)
	local by = {}
	for _, t in ipairs(trials) do
		if t.kind == "splitter" then
			local _, idx = V.parseKey(t.key)
			local rule = geom.tuning.splitter and geom.tuning.splitter[idx[7] .. "," .. idx[2]]
			if rule and ruleMatches(rule, t) then
				by[table.concat({ idx[7], idx[2], idx[4], idx[1], num(t.devRadius) }, ",")] = t.ok == "true"
			end
		end
	end
	return by
end

--- Splitter rules: for every layout the search probed, the engine accepted the rule at its floor
-- and at every probed radius above it; floors where it accepted nothing are gaps (provisional).
function V.splitter(geom, trials)
	local problems, gaps = {}, {}
	local by = V.splitterTrials(geom, trials)
	for ruleKey, rule in pairs(geom.tuning.splitter or {}) do
		local arm, lanes = tostring(ruleKey):match("^(%d+),(%d+)$")
		for layout, f in pairs(rule.floor or {}) do
			local probed, accepted = 0, false
			for k, okT in pairs(by) do
				local a, l, lay, shape, r = k:match("^(%d+),(%d+),(%d+),(%d+),(.+)$")
				if a == arm and l == lanes and tonumber(lay) == layout and shape == "1" then
					probed = probed + 1
					r = tonumber(r)
					if r >= f and not okT then
						problems[#problems + 1] = string.format("splitter rule %s layout %d: rejected at %g m (floor %g m)", ruleKey, layout, r, f)
					end
					if r == f and okT then accepted = true end
				end
			end
			if probed > 0 and not accepted then
				gaps[#gaps + 1] = { "provisional", string.format("splitter rule %s layout %d: floor %g m", ruleKey, layout, f) }
			end
		end
	end
	return problems, gaps
end

--- Tram line stub jobs (4 arms, exact radii): the shipped tram line at each probed radius is a
-- layout the engine accepted (one of the accepted stub candidates, as the probe built it).
function V.tram(geom, magic, trials)
	local problems = {}
	local jobs = {}
	for _, t in ipairs(trials) do
		if t.kind == "tram_stub" then
			local id = t.key .. "@" .. t.devRadius
			jobs[id] = jobs[id] or { key = t.key, radius = num(t.devRadius), accepted = {} }
			if t.ok == "true" then jobs[id].accepted[#jobs[id].accepted + 1] = num(t.devTramStub) end
		end
	end
	local function through(b)
		local out = {}
		for _, l in ipairs(b.lists) do if l.role == "through" then out[#out + 1] = l end end
		return out
	end
	for id, j in pairs(jobs) do
		local shipped = through(geom.build(geom.readParams(devParams(V, geom, magic, j.key, { radius = j.radius }))))
		local match = false
		for _, stub in ipairs(j.accepted) do
			local probe = V.legacy(geom, function()
				return through(geom.build(geom.readParams(devParams(V, geom, magic, j.key, { radius = j.radius, tramStub = stub }))))
			end)
			if same(geom, shipped, probe) then match = true end
		end
		if not match then problems[#problems + 1] = id .. ": the shipped tram line is none of the accepted stub layouts" end
	end
	return problems
end

--- Sweep rows (probe_results.csv, the Phase 3b shipped geometry): every combo the engine
-- rejected must now ship a layout the engine accepted in the search: the found radius of the
-- combo's radius job, or the splitter rule at a radius where its trial was accepted. Returns
-- problems, gaps ({cat, text}).
function V.sweep(geom, magic, rows, jobs, trials)
	local problems, gaps = {}, {}
	local byKey = V.radiusJobs(jobs)
	local split = V.splitterTrials(geom, trials or {})
	local provisional = V.provisionalFloors(geom, trials or {})
	local magicJobs = {}
	for _, j in ipairs(jobs) do
		if j.kind == "magic_size" and (j.fixed or "") == "" then
			local acc = {}
			for item in tostring(j.acceptedList or ""):gmatch("[^|]+") do
				local s = tonumber(item:match("^magicSize=(%d+)$"))
				if s then acc[s] = true end
			end
			magicJobs[V.magicRowKey(j.key)] = acc
		end
	end
	local canonical = V.canonical
	for _, r in ipairs(rows) do
		if r.ok ~= "true" and r.entry == "magic" then
			local p = V.params(r.key, nil, magic.PARAM_KEYS)
			local size = magic.build(magic.readParams(p)).size
			-- the job with the same satellite lanes (a 1-lane verdict says nothing about 2 lanes)
			local acc = magicJobs[V.magicRowKey(r.key)]
			if not (acc and acc[size]) then problems[#problems + 1] = r.key .. ": Magic ships size " .. size .. ", not accepted" end
		elseif r.ok ~= "true" and r.entry == "main" then
			local spec = geom.readParams((V.params(r.key, geom.PARAM_KEYS, magic.PARAM_KEYS)))
			local built = geom.build(spec)
			local _, idx = V.parseKey(r.key)
			local rule = spec.splitter == geom.SPLITTER_ON and spec.layout ~= #geom.ARM_LAYOUTS and geom.splitterRule(spec)
			local job = byKey[canonical(r.key)]
			local text = r.key .. " (rejected at " .. tostring(r.effR) .. " m): ships " .. built.radius .. " m"
			if job and job.found == "true" and num(job.devRadius) == built.radius then
				-- the combo's own radius job (search_radius / search_radius_split) accepted it
			elseif job and job.found ~= "true" then
				gaps[#gaps + 1] = { "none", text }
			elseif rule then
				local k = table.concat({ spec.armType, spec.lanes, spec.layout, spec.shape, built.radius }, ",")
				local probed = spec.centre == geom.CENTRE_NONE and spec.tram == geom.TRAM_OFF and spec.direction == geom.DIRECTION_CCW
				if probed and split[k] == true then
					-- the splitter search accepted the rule at exactly this radius
				elseif probed and split[k] == false then
					problems[#problems + 1] = text .. " with the splitter rule, which the engine rejected"
				elseif rule.floor and rule.floor[spec.layout] and built.radius >= rule.floor[spec.layout]
					and provisional[spec.armType .. "," .. spec.lanes .. "," .. spec.layout] then
					gaps[#gaps + 1] = { "provisional", text }
				else
					gaps[#gaps + 1] = { "splitter", text }
				end
			elseif not job and spec.direction == geom.DIRECTION_CW then
				local ccw = {}
				for i, v in ipairs(idx) do ccw[i] = v end
				ccw[9] = geom.DIRECTION_CCW
				local cj = byKey[canonical("m:" .. table.concat(ccw, ","))]
				if cj and cj.found == "true" and built.radius >= num(cj.devRadius) and not radiiOf(cj.rejected)[built.radius] then
					gaps[#gaps + 1] = { "cw", text }
				else
					problems[#problems + 1] = text .. ": clockwise, no matching anticlockwise engine radius"
				end
			else
				problems[#problems + 1] = text .. ": not a radius the engine accepted"
			end
		end
	end
	return problems, gaps
end

--- Provisional splitter floors ("arm,lanes,layout" -> true): probed layouts where the rule was
-- accepted at no probed radius, and the unprobed layouts that inherit their floor.
function V.provisionalFloors(geom, trials)
	local out = {}
	local _, gaps = V.splitter(geom, trials)
	for _, g in ipairs(gaps) do
		local rk, layout = g[2]:match("^splitter rule (%d+,%d+) layout (%d+)")
		if rk then out[rk .. "," .. layout] = true end
	end
	-- Y inherits T's floor, 5 arms the 6-arm floor (gen_roundabouts_tuning.py LAYOUT_FROM)
	local inherit = {}
	for k in pairs(out) do
		local rk, layout = k:match("^(%d+,%d+),(%d+)$")
		if layout == "1" then inherit[#inherit + 1] = rk .. ",2" end
		if layout == "5" then inherit[#inherit + 1] = rk .. ",4" end
	end
	for _, k in ipairs(inherit) do out[k] = true end
	return out
end

local DEV_COLS = {
	radius = "devRadius", magicSize = "devMagicSize", magicRadius = "devMagicRadius", magicDistance = "devMagicDistance",
	split = "devSplit", fork = "devFork", spread = "devSpread", leg = "devLeg", neck = "devNeck",
	neckType = "devNeckType", tramStub = "devTramStub",
}

--- The layout a probe row (T row of probe_search_trials.csv) asked the engine about, rebuilt
-- with its dev overrides; call inside V.legacy with the neutral tuning table. Returns the build
-- (main or Magic) and whether geom.plan / magic.layout accepted it.
function V.probeLayout(geom, magic, r)
	local p, tag = V.params(r.key, geom.PARAM_KEYS, magic.PARAM_KEYS)
	for name, col in pairs(DEV_COLS) do
		local v = tonumber(r[col] or "")
		if v then p[geom.DEV_KEYS[name]] = v end
	end
	if tag == "g" then
		local spec = magic.readParams(p)
		local offline = true
		if spec.dev then offline = magic.devLayout(spec).offline end
		return magic.build(spec), offline
	end
	local built = geom.build(geom.readParams(p))
	local offline = built.offline
	if offline == nil then offline = not built.forced end
	return built, offline
end

--- Whether a trial row is a real engine verdict (not degenerate geometry the probe never sent).
function V.sent(r)
	return r.sane ~= "false" and not tostring(r.msgs or ""):find("not sent", 1, true)
end

--- Returns judged(built): true when the engine (not the offline model) judges this shipped build:
-- an exact engine radius (built.engine "radius" / "splitter"), an engine floor the offline model
-- rejects at every radius ("floor" with offline = false: pending search_radius_split, a documented
-- gap), or a radius the engine accepted for the build's pattern (a radius trial, or a Phase 3b
-- sweep row whose layout is unchanged): the layout depends only on the pattern and the effective
-- radius (not on the slider), and no accepted tram layout had a middle the Phase 4b rule changes.
-- The engine-fitted model has false alarms there (e.g. 2.1 m arm corners on a 2:1 oval).
function V.judge(geom, trials, sweep)
	local accepted = {}
	local function pattern(key)
		local _, idx = V.parseKey(key)
		return V.patternOf(key), idx
	end
	for _, t in ipairs(trials or {}) do
		if t.kind == "radius" and t.ok == "true" then accepted[pattern(t.key) .. "@" .. tostring(num(t.devRadius))] = true end
	end
	for _, r in ipairs(sweep or {}) do
		if r.entry == "main" and r.ok == "true" then
			local pat, idx = pattern(r.key)
			-- the splitter rule replaced the Phase 3b splitter of medium/large arms
			local ruled = idx[5] == 2 and idx[4] ~= 6 and geom.tuning.splitter and geom.tuning.splitter[idx[7] .. "," .. idx[2]]
			if not ruled then accepted[pat .. "@" .. tostring(num(r.effR))] = true end
		end
	end
	return function(built)
		if built.engine == "radius" or built.engine == "splitter" then return true end
		if built.engine == "floor" and built.offline == false then return true end
		if not (built.spec and built.spec.radiusIndex) then return false end
		-- another through road than the arms: its own pattern (geom.patternKey, Phase 5f), so only
		-- the layouts p5_hamburger_radius / p5_all saw accepted count
		return accepted[geom.patternKey(built.spec) .. "@" .. tostring(built.radius)] == true
	end
end

-- Channelized Junction / Roundabout Interchange replays (Phase 5f) ----------------------------

local CH_ORDER = { "layout", "main", "side", "slips", "splitter", "armLength", "direction", "island" }
local IX_ORDER = { "layout", "highway", "level", "lanes", "radius", "cross", "slipLength", "armLength", "direction", "island" }

--- Params of a channel (c:) or interchange (x:) replay key, plus the dev overrides of a trial row
-- (its dev* columns). The interchange's 11th value is the year (1 = 1969, 2 = 2020).
function V.entryParams(geom, mod, key, row)
	local tag, idx = V.parseKey(key)
	local order = tag == "c" and CH_ORDER or IX_ORDER
	local p = {}
	for i, name in ipairs(order) do
		if idx[i] then p[mod.PARAM_KEYS[name]] = idx[i] end
	end
	if tag == "x" and idx[11] then p.year = idx[11] == 1 and 1969 or 2020 end
	for name, key2 in pairs(geom.DEV_KEYS) do
		local col = "dev" .. name:sub(1, 1):upper() .. name:sub(2)
		local v = row and tonumber(row[col] or "")
		if v then p[key2] = v end
	end
	return p
end

--- Channel: every combo the engine rejected (p5_all / p5f_all sweep rows, grid jobs whose shipped
-- candidate it rejected) ships a layout it accepted for the same layout, main road, side road and
-- splitter (the tuning row's angle / template, rebuilt as the probe built it: the table without
-- channel rows + dev values), or falls in gap "channel" (no accepted candidate: ch.FALLBACK). Sweep rows it accepted
-- still build the swept set-backs, or (Phase 5g: a search found a more compact layout) a layout an
-- accepted search trial built. Call with the shipped tuning table.
function V.channel(geom, ch, sweep, trials)
	local problems, gaps = {}, {}
	local accepted = {} -- "layout,main,side,splitter" -> list of params (dev values) the engine took
	for _, t in ipairs(trials or {}) do
		if t.entry == "channel" and t.ok == "true" and V.sent(t) then
			local _, idx = V.parseKey(t.key)
			local rk = idx[1] .. "," .. idx[2] .. "," .. idx[3] .. "," .. idx[5]
			accepted[rk] = accepted[rk] or {}
			accepted[rk][#accepted[rk] + 1] = t
		end
	end
	-- the table the probe ran with: the shipped one without the channel rows (the splitter rules
	-- still shape the side road's legs)
	local function neutral(fn)
		local saved = geom.tuning
		local t = {}
		for k, v in pairs(saved) do if k ~= "channel" then t[k] = v end end
		geom.setTuning(t)
		local okRun, res = pcall(fn)
		geom.setTuning(saved)
		if not okRun then error(res, 0) end
		return res
	end
	local function layoutText(b) return table.concat(V.text(b.lists)) end
	-- whether the shipped build b of sweep row r is a layout an accepted search trial built (the
	-- trial's dev values on this combo, as the probe built it)
	local function trialMatch(r, b)
		local _, idx = V.parseKey(r.key)
		local rk = idx[1] .. "," .. idx[2] .. "," .. idx[3] .. "," .. idx[5]
		local mine = layoutText(b)
		for _, t in ipairs(accepted[rk] or {}) do
			local q = V.entryParams(geom, ch, r.key, t)
			if not q[geom.DEV_KEYS.chSlip] then q[geom.DEV_KEYS.chSlip] = 1 end
			local probe = neutral(function() return ch.build(ch.readParams(q)) end)
			if layoutText(probe) == mine then return true end
		end
		return false
	end
	for _, r in ipairs(sweep or {}) do
		if r.entry == "channel" then
			local p = V.entryParams(geom, ch, r.key)
			local b = ch.build(ch.readParams(p))
			local sb = string.format("%.1f/%.1f", b.setback.main, b.setback.side)
			if r.ok == "true" and #b.slips > 0 then
				-- unchanged since the sweep, or replaced by an accepted search layout (Phase 5g:
				-- p5f_search's more compact slip lanes replace the p5f_all-verified ch.FALLBACK)
				if r.setback and r.setback ~= "" and r.setback ~= "-" and r.setback ~= sb
					and not (b.slipSource == "engine" and trialMatch(r, b)) then
					problems[#problems + 1] = r.key .. ": accepted with set-backs " .. r.setback .. ", ships " .. sb
				end
			elseif r.ok ~= "true" and #b.slips > 0 then
				local text = r.key .. " (rejected at " .. tostring(r.setback) .. "): ships " .. string.format("%g", b.slipAngle) .. " deg, " .. sb
				if b.slipSource == "fallback" then
					gaps[#gaps + 1] = { "channel", text }
				elseif b.slipSource == "engine" then
					if not trialMatch(r, b) then problems[#problems + 1] = text .. ": not a layout the engine accepted" end
				else
					problems[#problems + 1] = text .. ": still the rejected 40 deg layout"
				end
			end
		end
	end
	return problems, gaps
end

--- Interchange: every combo a sweep row covers ships a ring radius the engine accepted for it: the
-- swept one (accepted rows, unchanged), or one an accepted sweep row or search trial (dev value
-- ixAlphaMax only) of the same combo placed (the two-bridge ring's slip nodes follow from the radius: alpha = asin(clearance /
-- radius), the cap only sets the smallest radius). A rejected radius still shipped is a problem;
-- a radius no engine row accepted is gap "interchange" (unverified, e.g. after a cap change).
function V.interchange(geom, ix, sweep, trials)
	local problems, gaps = {}, {}
	local accepted = {} -- key -> {radius = true}
	local function take(r)
		if r.entry == "interchange" and r.ok == "true" and tonumber(r.effR) then
			accepted[r.key] = accepted[r.key] or {}
			accepted[r.key][tonumber(r.effR)] = true
		end
	end
	for _, r in ipairs(sweep or {}) do take(r) end
	-- trials only with ixAlphaMax as their dev value (ixClear / ixGamma / ... change the layout)
	local function onlyAlpha(t)
		for col, v in pairs(t) do
			if col:sub(1, 3) == "dev" and col ~= "devIxAlphaMax" and v ~= "" and v ~= "-" then return false end
		end
		return true
	end
	for _, t in ipairs(trials or {}) do if V.sent(t) and onlyAlpha(t) then take(t) end end
	for _, r in ipairs(sweep or {}) do
		if r.entry == "interchange" then
			local b = ix.build(ix.readParams(V.entryParams(geom, ix, r.key)))
			local swept = tonumber(r.effR)
			local verified = accepted[r.key] and accepted[r.key][b.radius]
			if r.ok ~= "true" and swept == b.radius then
				problems[#problems + 1] = r.key .. ": ships " .. b.radius .. " m, which the engine rejected"
			elseif not (r.ok == "true" and swept == b.radius) and not verified then
				gaps[#gaps + 1] = { "interchange", r.key .. ": " .. (r.ok == "true" and "accepted" or "rejected") .. " at "
					.. tostring(swept) .. " m, ships " .. b.radius .. " m" }
			end
		end
	end
	return problems, gaps
end

--- Every probe file the replays use, concatenated (missing files are skipped): the Phase 4
-- search / sweep (probe_search*.csv, probe_results.csv), the Phase 5e runs (probe_p5_*), the
-- Phase 5f runs (probe_p5f_*) and the Phase 5g verify sweep (probe_p5g_verify.csv, once it exists).
-- Returns {jobs, trials, sweep}.
V.FILES = {
	jobs = { "probe_search.csv", "probe_p5_search_jobs.csv", "probe_p5f_search_jobs.csv" },
	trials = { "probe_search_trials.csv", "probe_p5_search_trials.csv", "probe_p5f_search_trials.csv" },
	sweep = { "probe_results.csv", "probe_p5_all.csv", "probe_p5f_all.csv", "probe_p5g_verify.csv" },
}
function V.loadAll(plans)
	local out = {}
	for kind, names in pairs(V.FILES) do
		local rows = {}
		for _, name in ipairs(names) do
			for _, r in ipairs(V.readCsv(plans .. name) or {}) do rows[#rows + 1] = r end
		end
		out[kind] = rows
	end
	return out
end

--- Whether a tuning table holds no data.
function V.neutral(t)
	return next(t.radius or {}) == nil and next(t.magic or {}) == nil and next(t.splitter or {}) == nil
end

return V
