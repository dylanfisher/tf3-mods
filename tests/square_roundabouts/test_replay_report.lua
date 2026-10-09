-- DEV TOOL (skipped unless SQRB_REPLAY_OUT is set): rebuilds every layout the engine judged in
-- the probe runs (plans/square_roundabouts/probe_search_trials.csv: exact dev layouts;
-- probe_results.csv: the Phase 3b shipped geometry of the `all` sweep) and writes one CSV row
-- per engine call with the offline model's view of it: whether geom.plan / magic.layout accepted
-- the layout, the Phase 3b and the engine-fitted test models (checks.junctionRoom 4.5 / 6 m,
-- checks.engineModel), and the junction model's numbers (checks.junctions: smallest free length and
-- largest corner-behind per road role; the tram line's stub and middle). Used to retune the
-- offline thresholds against the engine (PLAN.md "Phase 4b notes"):
--
--   SQRB_REPLAY_OUT=/tmp/replay.csv uv run tests/run_tests.py -k "replay report" mods/square_roundabouts
--
-- The layouts are rebuilt as the probe built them: the neutral tuning table (dev overrides
-- replace any rule anyway) and the Phase 3b tram line rule (TRAM_MIDDLE_MIN = MIN_EDGE).
-- SQRB_REPLAY_LIMIT=n stops after n rows per file (quick checks).

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local magic = ug_require(DIR .. "square_roundabouts_magic.lua")

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local V = loadfile(here .. "verdicts.lua", "t", _ENV)()
local checks = loadfile(here .. "checks.lua", "t", _ENV)()
local PLANS = here .. "../../plans/square_roundabouts/"

local OUT = os.getenv and os.getenv("SQRB_REPLAY_OUT")
local LIMIT = tonumber(os.getenv and os.getenv("SQRB_REPLAY_LIMIT") or "")

local ROLES = { "ring", "arms", "legs", "neck", "through", "satellites", "links" }
local HEADER = { "src", "row", "kind", "ok", "offline", "entry", "effR", "minFree", "maxBehind" }
for _, r in ipairs(ROLES) do HEADER[#HEADER + 1] = "free_" .. r end
for _, r in ipairs(ROLES) do HEADER[#HEADER + 1] = "behind_" .. r end
for _, c in ipairs({ "tramStub", "tramMiddle", "model3b", "model4b", "key" }) do HEADER[#HEADER + 1] = c end

local function fmt(v)
	if v == nil or v == math.huge then return "" end
	if type(v) == "number" then return string.format("%.2f", v) end
	return tostring(v)
end

local function buildRow(r)
	local built, offline = V.probeLayout(geom, magic, r)
	return built, offline, V.parseKey(r.key) == "g" and "magic" or "main"
end

local function features(built)
	local xs = checks.junctions(built.lists)
	local f = { minFree = math.huge, maxBehind = 0 }
	for _, x in ipairs(xs) do
		f.minFree = math.min(f.minFree, x.free)
		f.maxBehind = math.max(f.maxBehind, x.behind or 0)
		local fk, bk = "free_" .. x.role, "behind_" .. x.role
		f[fk] = math.min(f[fk] or math.huge, x.free)
		f[bk] = math.max(f[bk] or 0, x.behind or 0)
	end
	for _, l in ipairs(built.lists) do
		if l.role == "through" then
			for _, e in ipairs(l.edges) do
				local len = checks.edgeLength(e)
				if l.template == geom.TRAM_THROUGH.template then f.tramMiddle = len
				elseif not e.tag0 or not e.tag1 or e.tag0:find("tram") or e.tag1:find("tram") then f.tramStub = len - built.halfWidth end
			end
		end
	end
	return f
end

test("replay report: offline model numbers for every engine verdict (dev tool, needs SQRB_REPLAY_OUT)", function()
	if not OUT then
		print("    (skipped: set SQRB_REPLAY_OUT=<csv> to write the report)")
		return
	end
	local out = assert(io.open(OUT, "w"))
	out:write(table.concat(HEADER, ","), "\n")
	local savedMiddle = geom.TRAM_MIDDLE_MIN
	geom.setTuning({ radius = {}, magic = {}, splitter = {} })
	geom.TRAM_MIDDLE_MIN = geom.MIN_EDGE
	local okRun, err = pcall(function()
		for _, src in ipairs({ { "trial", "probe_search_trials.csv" }, { "sweep", "probe_results.csv" } }) do
			local rows = V.readCsv(PLANS .. src[2]) or {}
			local n = 0
			for i, r in ipairs(rows) do
				if V.sent(r) and (src[1] == "sweep" or r.kind ~= "") then
					local built, offline, entry = buildRow(r)
					local f = features(built)
					local cells = {}
					local function push(v) cells[#cells + 1] = fmt(v) end
					for _, v in ipairs({ src[1], tostring(i), r.kind or "", r.ok, tostring(offline), entry }) do push(v) end
					push(built.radius or built.size)
					push(f.minFree)
					push(f.maxBehind)
					for _, role in ipairs(ROLES) do push(f["free_" .. role]) end
					for _, role in ipairs(ROLES) do push(f["behind_" .. role]) end
					push(f.tramStub)
					push(f.tramMiddle)
					-- the Phase 3b test model (free 4.5 m, behind 6 m) and the engine-fitted one
					push(tostring(#checks.junctionRoom(built.lists, 4.5, 6.0) == 0))
					push(tostring(#checks.engineModel(built.lists, built.halfWidth) == 0))
					cells[#cells + 1] = '"' .. r.key .. '"'
					out:write(table.concat(cells, ","), "\n")
					n = n + 1
					if LIMIT and n >= LIMIT then break end
				end
			end
			print(string.format("    %s: %d rows", src[2], n))
		end
	end)
	geom.TRAM_MIDDLE_MIN = savedMiddle
	geom.setTuning(nil)
	out:close()
	if not okRun then error(err, 0) end
end)
