-- Smoke test for the DEV probe (content/tsnprobe/tsnprobe.script.lua and the name set script) against a
-- tiny fake world: it must not throw, must detect a new stop group, and must run the rename test from
-- update (never from the build event). Not a spec of the game, just a guard against typos.

local MOD = "square_town_street_names_probe"

local CT = {}
for _, k in ipairs({ "NAME", "TOWN", "STATION_GROUP", "STATION", "EDGE_OBJECT", "CONSTRUCTION", "BASE_EDGE",
	"BASE_EDGE_STREET", "BASE_NODE", "LINE", "TRANSPORT_VEHICLE", "VEHICLE_DEPOT", "INDUSTRY", "TOWN_BUILDING",
	"PLAYER", "GAME_SCRIPT", "SIM_PERSON", "BOUNDING_VOLUME" }) do CT[k] = k end

local function world()
	local w = { comps = {}, params = {}, sent = {}, time = 1000 }
	local function add(e, k, v) w.comps[e] = w.comps[e] or {}; w.comps[e][k] = v end
	w.add = add
	local function bv(x, y) return { bbox = { min = { x = x - 1, y = y - 1, z = 0 }, max = { x = x + 1, y = y + 1, z = 0 } } } end
	w.bv = bv
	add(1, "TOWN", {}); add(1, "NAME", { name = "Seattle" }); add(1, "BOUNDING_VOLUME", bv(0, 0))
	add(2, "TOWN", {}); add(2, "NAME", { name = "Tacoma" }); add(2, "BOUNDING_VOLUME", bv(5000, 0))
	-- existing stop: group 10, station 11 (edge object on edge 12)
	add(10, "STATION_GROUP", { stations = { 11 } }); add(10, "NAME", { name = "Probe Street 01" })
	add(11, "STATION", {}); add(11, "EDGE_OBJECT", { transf = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 100,0,0,1 }, edgeObjectConstruction = "station/street/small_new.con", param = 0.5 })
	add(12, "BASE_EDGE", { objects = { { 11, 0 } } }); add(12, "BASE_EDGE_STREET", {})
	w.api = {
		type = {
			ComponentType = CT,
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
		},
		engine = {
			getComponent = function(e, k) return w.comps[e] and w.comps[e][k] or nil end,
			entityExists = function(e) return w.comps[e] ~= nil end,
			getEntitiesWithComponent = function(k)
				local out = {}
				for e, c in pairs(w.comps) do if c[k] then out[#out + 1] = e end end
				table.sort(out)
				return out
			end,
			config = {
				getModParams = function() return { [MOD] = w.params, [""] = { isMapEditor = false } } end,
				getConfigDict = function() return { climate = "::/climates/dry/dry.clima", nameList = "x" } end,
			},
			util = {
				getEntityName = function(e) return w.comps[e] and w.comps[e].NAME and w.comps[e].NAME.name or nil end,
				getEntityNameStem = function(e) return { nil, nil } end,
				town = { getClosestTown = function(_p) return 1 end },
				octree = { findEntitiesInCircle = function(_c, _r, k)
					local out = {}
					for e, c in pairs(w.comps) do if c[k] then out[#out + 1] = e end end
					return out
				end },
			},
			system = {
				stationSystem = { getTown = function(_s) return 1 end, getTown2StationsMap = function() return { [1] = { 11 } } end },
				stationGroupSystem = { getStationGroup = function(s)
					for e, c in pairs(w.comps) do
						if c.STATION_GROUP then for _, x in ipairs(c.STATION_GROUP.stations) do if x == s then return e end end end
					end
					return -1
				end },
				streetConnectorSystem = { getConstructionEntityForStation = function(_s) return -1 end },
			},
		},
		cmd = {
			makeEntitySetNameCmd = function(e, n, f) return { e = e, n = n, f = f } end,
			sendCommand = function(cmd, cb)
				w.sent[#w.sent + 1] = cmd
				add(cmd.e, "NAME", { name = cmd.n })
				-- like the engine-state update in game: "Callbacks are currently disallowed"
				if cb then error("Callbacks are currently disallowed") end
			end,
		},
	}
	return w
end

local function fakeState()
	local st = { v = nil, subs = false }
	return {
		get = function(_) return st.v end,
		set = function(_, v) st.v = v end,
		hasEventSubscriptions = function(_) return st.subs end,
		subscribeToAllEvents = function(_) st.subs = true end,
		subscribeToNoEvents = function(_) st.subs = true end,
		subscribeToEvent = function(_, _n) end,
	}
end

local captured = {}
local function load(w)
	reset_modules()
	set_global("api", w.api)
	set_global("data", nil)
	captured = {}
	set_global("print", function(s) captured[#captured + 1] = tostring(s) end)
	ug_require(MOD .. "::/tsnprobe/tsnprobe.script.lua")
	return data()
end

local function has(text)
	for _, l in ipairs(captured) do if l:find(text, 1, true) then return true end end
	return false
end

local function noErrors()
	for _, l in ipairs(captured) do
		if l:find("ERROR", 1, true) then error("probe logged: " .. l) end
	end
end

test("dump, baseline, new stop via post build, rename from update", function()
	local w = world()
	w.params = { renameTest = 20.0, eventDiscovery = 100.0 }
	local script = load(w)
	local state = fakeState()
	script.update({}, state, 0.1)
	ok(has("dump towns: 2"), "towns dumped")
	ok(has("NAME on TOWN: 2"), "census")
	ok(has("baseline: 1 station groups"), "baseline")
	-- build a new stop: group 20, station 21
	w.add(20, "STATION_GROUP", { stations = { 21 } }); w.add(20, "NAME", { name = "Probe Street 02" })
	w.add(21, "STATION", {}); w.add(21, "EDGE_OBJECT", { transf = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 200,0,0,1 } })
	local proposal = { toAdd = {}, toRemove = {}, proposal = { edgeObjectsToAdd = { { category = 0, resultEntity = -400000000, left = true, modelInstance = { transf = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 200,0,0,1 } } } }, new2oldEdgeObjects = {}, addedSegments = {} } }
	script.handleEvent({}, state, "builder", "apply_command", "onPostBuildProposal", { proposal, {}, {}, true })
	eq(#w.sent, 0, "no command inside the build event")
	ok(has("build onPostBuildProposal"), "build logged")
	script.update({}, state, 0.1)
	ok(has("NEW (via postBuild"), "new group detected via post build")
	ok(has("rename queued #1 mode=group group 20"), "rename queued")
	-- next scan sends, the one after verifies
	w.api.engine.util.getEntityName(20)
	local t = os.time
	local now = t()
	set_global("os", setmetatable({ time = function() now = now + 3; return now end }, { __index = os }))
	script.update({}, state, 0.1)
	eq(#w.sent, 1, "rename sent from update")
	eq(w.sent[1].e, 20)
	ok(has("rename #1 sent=true"), "sent without callback")
	script.update({}, state, 0.1)
	ok(has("rename #1 verify"), "verified")
	ok(has("name change group 20"), "watcher saw the rename")
	set_global("os", os)
	noErrors()
end)

test("read-only by default", function()
	local w = world()
	local script = load(w)
	local state = fakeState()
	script.update({}, state, 0.1)
	w.add(20, "STATION_GROUP", { stations = { 21 } }); w.add(21, "STATION", {})
	script.handleEvent({}, state, "builder", "apply_command", "onPostBuildProposal", { { proposal = {} }, {}, {}, true })
	script.update({}, state, 0.1)
	ok(has("NEW (via postBuild"), "detected")
	ok(not has("rename queued"), "no rename when off")
	eq(#w.sent, 0)
	script.guiUpdate({}, nil, nil)
	script.guiHandleEvent({}, nil, nil, "x", "y", "builder.proposalApply", { proposal })
	noErrors()
end)

test("name set script logs and returns names", function()
	reset_modules()
	set_global("data", nil)
	captured = {}
	set_global("print", function(s) captured[#captured + 1] = tostring(s) end)
	stub_module("::/names/usa/en/towns.lua", { "Springfield" })
	ug_require(MOD .. "::/names/tsn_probe/tsn_probe_names.script.lua")
	local fns = data()
	local all = fns.streetsFn({}, { lang = "en", num = -1 })
	eq(#all, 80); eq(all[1], "Probe Street 01")
	eq(#fns.streetsFn({}, { lang = "en", num = 3 }), 3)
	local towns = fns.townsFn({}, { lang = "en", num = 2 })
	eq(towns[1], "Seattle"); eq(towns[2], "Tacoma")
	ok(has("names streets call=1"), "logged")
end)

test("climate probe: runFn global, name script context and person names", function()
	reset_modules()
	set_global("data", nil)
	set_global("SQTSN_PROBE_RUNFN", nil)
	captured = {}
	set_global("print", function(s) captured[#captured + 1] = tostring(s) end)
	ug_require(MOD .. "::/mod.script.lua")
	data().runFn({}, { climate = "::/climates/dry/dry.clima", nameList = "n" }, {})
	set_global("data", nil)
	stub_module("::/names/usa/en/towns.lua", { "Springfield" })
	-- The name script uses plain require (as base names.script.lua does); fake it for the base util.
	local util = { usa = { en = { firstNamesMale = { "Jacob" }, firstNamesFemale = { "Emily" }, lastNames = { "Smith" } } } }
	set_global("require", function(path)
		if path == "::/names/personnameutil.lua" then return util end
		error("not stubbed: " .. tostring(path))
	end)
	ug_require(MOD .. "::/names/tsn_probe/tsn_probe_names.script.lua")
	local fns = data()
	eq(#fns.townsFn({}, { lang = "en", num = 2 }), 2)
	eq(fns.personsFn({}, { lang = "en", isMale = true }), "Jacob Smith")
	eq(fns.personsFn({}, { lang = "en", isMale = false }), "Emily Smith")
	ok(has("runFnGlobal climate=::/climates/dry/dry.clima"), "runFn global seen")
	ok(has("names ctx persons"), "person context logged")
	ok(has("names persons call=1"), "person call logged")
end)
