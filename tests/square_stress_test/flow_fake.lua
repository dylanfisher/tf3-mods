-- A fake api for the traffic log (gui/stress_flow_log.tl), shared by test_flow.lua and flow_e2e.lua (dofile'd
-- from the repo root). Not a test file itself (no test_ prefix).
--
-- World: persons 1..P; ids not divisible by 5 drive (MOVE_PATH, DRIVE), the others walk. Car i sits at CAR_POS[(i % 4) + 1]:
-- the centres of the zones g1a (0,0), g1b (1000,0), g2a (0,1000) and a spot outside every zone. Every 3rd
-- car stands (speed 0, timeStanding 6 if i % 9 == 0 else 2), the others drive at 10 m/s (or speedOf(i)).
-- Line 900 "SQST Bus 1" (vehicles 800, 801; stops at (-500,0) and (500,0): its midpoint is zone g1a), line
-- 901 "Other line". gameTime is F.gt (the test moves it); the Clock advances F.clockStep us per read and F.readUs
-- per component read (F.posUs per getPosition; F.posOf(i) overrides a car's spot).

local F = { gt = 1000000, clockStep = 1, readUs = 0, P = 400, reads = 0, persons = 0, sent = 0, exists = 0, smParams = true, saved = nil, zrun = nil,
	speedOf = nil, deps = { [800] = { 0, 0 }, [801] = { 0, 0 } }, last = { [800] = 0, [801] = 0 }, towns = 0 }

local WORLD = 9999
local CAR_POS = { { 3, 4 }, { 1003, -2 }, { -5, 998 }, { 5000, 5000 } }
F.WORLD = WORLD

local T = 0

function F.speed(i)
	if F.speedOf then return F.speedOf(i) end
	return i % 3 == 0 and 0 or 10
end

local function movePath(i)
	F.reads = F.reads + 1
	local sp = F.speed(i)
	-- F.pathOf(i) -> { entities of the path's edges }, its current index (0-based): the thru check's paths
	local edges, cur = {}, 0
	if F.pathOf then
		local list, c = F.pathOf(i)
		local real = {}
		for k, id in ipairs(list or {}) do
			-- F.pathLayout "first": the pair as { first = EdgeId, second = dir } (another binding layout)
			if F.pathLayout == "first" then real[k] = { first = { entity = id, index = 0 }, second = true }
			elseif F.pathLayout == "none" then real[k] = 0   -- nothing any reader can read
			else real[k] = { { entity = id, index = 0 }, true } end
		end
		-- every element read costs F.edgeUs on the fake clock (the game's userdata path)
		edges = setmetatable({}, { __index = function(_, k) T = T + (F.edgeUs or 0) return real[k] end, __len = function() return #real end })
		cur = c or 0
	end
	return { dyn = { speed = sp, timeStanding = sp < 0.5 and (i % 9 == 0 and 6 or 2) or 0, pathPos = { edgeIndex = cur } }, path = { edges = edges } }
end

local function savedState()
	return {
		find = function(_, key)
			if key == "zrun" then return F.zrun end
			if key == "zones" then
				if F.saved == nil then return nil end
				return { asTable = function() return F.saved end }
			end
			return nil
		end,
	}
end

function F.api()
	local fixed = {
		[800] = function() return { line = 900, lastLineStopDeparture = F.last[800], lineStopDepartures = F.deps[800], sectionTimes = F.sections or { 60, 70 } } end,
		[801] = function() return { line = 900, lastLineStopDeparture = F.last[801], lineStopDepartures = F.deps[801], sectionTimes = {} } end,
	}
	local stations = { [7001] = { 7101 }, [7002] = { 7102 } }
	local conPos = { [7201] = { x = -500, y = 0 }, [7202] = { x = 500, y = 0 } }
	local a = {
		type = {
			Clock = { new = function() return { getTime = function() T = T + F.clockStep return T end } end },
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
			ComponentType = setmetatable({}, { __index = function(_, k) return k end }),
			enum = { MoveMode = { WALK = 0, DRIVE = 1, LINES = 2 } },
		},
		cmd = { sendCommand = function() F.sent = F.sent + 1 end },
		gui = {},
		engine = {
			config = { getModParams = function() return F.smParams and { square_smart_lanes = {} } or {} end },
			entityExists = function(e)
				F.exists = F.exists + 1
				return (e >= 1 and e <= F.P) or e == WORLD or fixed[e] ~= nil or e == 900 or e == 901
			end,
			getComponent = function(e, ct)
				T = T + F.readUs
				if e == WORLD then
					if ct == "GAME_TIME" then return { gameTime = F.gt } end
					if ct == "GAME_SPEED" then return { speedup = 4 } end
					return nil
				end
				if e == 5000 and ct == "GAME_SCRIPT" then return { state_native = savedState() } end
				if fixed[e] and ct == "TRANSPORT_VEHICLE" then return fixed[e]() end
				if e == 900 and ct == "LINE" then return { stops = { { stationGroup = 7001 }, { stationGroup = 7002 } } } end
				if e == 901 and ct == "LINE" then return { stops = { { stationGroup = 7001 } } } end
				if stations[e] and ct == "STATION_GROUP" then return { stations = stations[e] } end
				if conPos[e] and ct == "CONSTRUCTION" then
					local p = conPos[e]
					return { transf = { getTransl = function() return { x = p.x, y = p.y, z = 0 } end } }
				end
				-- ring lane use: F.nodePos[e] = {x, y} (a path node), F.edgeEnds[e] = {node0, node1} (a street edge)
				if F.nodePos and ct == "BASE_NODE" and F.nodePos[e] then
					return { position = { x = F.nodePos[e][1], y = F.nodePos[e][2], z = 0 } }
				end
				if F.edgeEnds and ct == "BASE_EDGE" and F.edgeEnds[e] then return { node0 = F.edgeEnds[e][1], node1 = F.edgeEnds[e][2] } end
				-- the junction streets of F.junctionEdges: one end node at the zone's centre (thruSetOf reads them)
				if F.junctionEdges and (ct == "BASE_EDGE" or ct == "BASE_NODE") then
					for key, list in pairs(F.junctionEdges) do
						local cx, cy = key:match("^(%-?%d+),(%-?%d+)$")
						for _, id in ipairs(list) do
							if ct == "BASE_EDGE" and e == id then return { node0 = id * 10, node1 = id * 10 + 1 } end
							if ct == "BASE_NODE" and (e == id * 10 or e == id * 10 + 1) then
								local off = (e == id * 10) and 0 or 300   -- the far end 300 m out: a long arm
								return { position = { x = tonumber(cx) + off, y = tonumber(cy), z = 0 } }
							end
						end
					end
				end
								if type(e) == "number" and e >= 1 and e <= F.P then
					if ct == "SIM_PERSON" then F.persons = F.persons + 1 return { lastMoveMode = e % 5 ~= 0 and 1 or 0 } end
					if ct == "MOVE_PATH" and e % 5 ~= 0 then return movePath(e) end
				end
				return nil
			end,
			getEntitiesWithComponent = function(ct)
				if ct == "SIM_PERSON" then
					local l = {}
					for i = 1, F.P do l[i] = i end
					return l
				end
				if ct == "TOWN" then return { 1, 2, 3 } end
				return {}
			end,
			util = {
				getPlayer = function() return 7 end,
				getWorld = function() return WORLD end,
				getEntityName = function(e)
					if e == 900 then return "SQST Bus 1" end
					if e == 901 then return "Other line" end
					return "Town " .. tostring(e)
				end,
				finance = { getPlayersBalance = function() return 1 end },
				vehicle = { getPosition = function(e)
					T = T + (F.posUs or 0)
					local p = (F.posOf and F.posOf(e)) or CAR_POS[(e % 4) + 1]
					return { x = p[1], y = p[2], z = 0 }
				end },
				town = { computeTownsTrafficSpeedMap = function()
					F.towns = F.towns + 1
					return { [301] = { 0.8, { 5, 2, 1 } }, [302] = { 0.5, { 1, 1, 1 } } }
				end },
				line = { getMaxFrequency = function() return 0.01 end },
				-- F.junctionEdges[x .. "," .. y] -> the street edges at a zone centre (the thru sets)
				octree = { findEntitiesInCircle = function(c, r, ct)
					local key = string.format("%d,%d", math.floor(c.x + 0.5), math.floor(c.y + 0.5))
					return (F.junctionEdges or {})[key] or {}
				end },
			},
			system = {
				lineSystem = { getLinesForPlayer = function() return { 900, 901 } end },
				transportVehicleSystem = { getLineVehicles = function(l) return l == 900 and { 800, 801 } or {} end },
				gameScriptSystem = { getEntityForGameScript = function() return 5000 end },
				streetConnectorSystem = { getConstructionEntityForStation = function(s) return s + 100 end },
			},
		},
	}
	return a
end

--- The Showcase zones of one run as stress_junctions keeps them (g2b refused: not built; g3a built, no car).
function F.showcase()
	return {
		{ id = "g1a", pair = "g1", ab = "sl", kind = "rb", label = "Magic Roundabout", x = 0, y = 0, r = 100, towns = 4, built = true },
		{ id = "g1b", pair = "g1", ab = "game", kind = "rb", label = "Magic Roundabout", x = 1000, y = 0, r = 100, towns = 4, built = true },
		{ id = "g2a", pair = "g2", ab = "sl", kind = "plain", label = "Crossroads", x = 0, y = 1000, r = 60, towns = 4, built = true, reason = "town" },
		{ id = "g2b", pair = "g2", ab = "game", kind = "plain", label = "Crossroads", x = 1000, y = 1000, r = 60, towns = 4 },
		{ id = "g3a", pair = "g3", ab = "sl", kind = "ix", label = "Trumpet", x = 3000, y = -3000, r = 150, towns = 3, built = true },
	}
end

--- Loads the modules on the fake api; returns rt, the flow log, slzones, buslines, traffic.
function F.load()
	set_global("api", F.api())
	local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	rt.notificationsSent = true
	local fl = ug_require "square_stress_test::/stress/gui/stress_flow_log.tl"
	local slz = ug_require "square_stress_test::/stress/gui/stress_slzones.tl"
	local bl = ug_require "square_stress_test::/stress/gui/stress_buslines.tl"
	local tr = ug_require "square_stress_test::/stress/gui/stress_traffic.tl"
	return rt, fl, slz, bl, tr
end

--- Ticks n frames, moving gameTime by gtStep each; perTick(i) after each tick. Returns the [SQST] FLOW lines.
function F.run(rt, n, gtStep, perTick)
	for i = 1, n do
		F.gt = F.gt + (gtStep or 500)
		rt.tick()
		if perTick then perTick(i) end
	end
	local out = {}
	for _, e in ipairs(log_entries()) do
		if e.msg:find("[SQST] FLOW", 1, true) then out[#out + 1] = e.msg end
	end
	return out
end

function F.kv(line)
	local t = {}
	for k, v in line:gmatch("([%w_]+)=(%S*)") do t[k] = v end
	return t
end

function F.kind(line)
	return line:match("^%[SQST%] (FLOW_?%u*) ")
end

return F
