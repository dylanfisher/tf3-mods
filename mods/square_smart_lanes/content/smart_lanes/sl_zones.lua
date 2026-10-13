-- Smart Lanes zones: map circles another mod (or a test) marks with an A/B mode, so Smart Lanes' automatic
-- pass treats the junctions inside them differently (plans/square_stress_test/FLOW_PLAN.md "Revision
-- 2026-10-12: side-by-side twins"; the Stress Test Showcase builds every junction as twins and sends them).
--
-- Modes (ab):
--   game       the automatic pass leaves every node inside alone (no lanes, no lights, no phases):
--              SKIP kind=zone reason=zone_game. The tool's Apply still works there (the player's choice),
--              its APPLY lines say zone=game.
--   sl         Smart Lanes as everywhere (the global settings).
--   sl_phases  Smart Lanes lanes + Smart Lanes light phases, whatever the global "Light phases" setting.
--   sl_fan     the full fan for measuring (PHASES_PLAN.md "Fan mode"): a lit crossroads / T-junction gets every
--              entry lane connected to every exit lane of every other arm (sl_cross X.fanConns) and a split
--              phase plan, one approach per phase (sl_phaseplan opts.fan), in one proposal. Unlit / unknown
--              nodes and other junction kinds there: as sl_phases. Never a default; a test mode for twins.
--   sl_lock    as sl (Smart Lanes lanes), but the kerb turn at crossroads / T-junctions is never freed, as if
--              "Free kerb turn at traffic lights" were Off, and the light phases stay the game's, whatever
--              the global settings ("Free kerb turn", "Light phases"). Its lane writes lock the kerb turns
--              back with their approach (as the tool's Reset: Lights.LOCK), so a turn freed earlier ends red
--              again. A test mode for twins: sl vs sl_lock measures the free kerb turn alone (with Light
--              phases = Game default; the MODE line tells).
--   sl_exitfan as sl (Smart Lanes lanes, "Free kerb turn" as set), but at a lit crossroads / T-junction every turn
--              fans into every exit lane it can reach without crossing a movement green in the same phase of
--              the game's axis phases (sl_cross X.phaseGroups / placeExitLit; a freed kerb turn only into the
--              exit's kerb lane), and the light phases stay the game's whatever "Light phases" says. Unlit /
--              unknown nodes and other junction kinds: as sl. A test mode for twins: sl vs sl_exitfan measures
--              the exit-lane fan alone (PLAN.md "Exit-lane fan (sl_exitfan zones)").
--   sl_keeplights as sl (lanes, free kerb turn and light phases as the settings), but no light is switched off in
--              the zone ("No lights at roundabouts and ramps" is not applied there: ring arm junctions, slip / ramp
--              nodes keep what the game made), in the automatic pass and the tool. One LIGHTS ... to=kept
--              zone=sl_keeplights line per node it would have switched off. A test mode for twins: sl vs
--              sl_keeplights measures the lights setting alone (plans/square_stress_test/BENCH.md test 2, SL-1).
-- Nodes outside every zone: unchanged. A node inside several zones takes the one whose centre is nearest
-- (relative to its radius).
--
-- Channel (another mod's GUI Lua state -> our saved game-script state):
--   api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "square_smart_lanes", "SmartLanes.zones",
--     { op = "set", run = "<id>", zones = { { x = .., y = .., r = .., ab = "game", id = "g3b", pair = "g3" }, ... } }))
--   api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "square_smart_lanes", "SmartLanes.zones",
--     { op = "clear", run = "<id>" }))
-- (api/tealdef/api/cmd.d.tl:788; the pattern of square_problem_radar's GUI events.) The engine-thread
-- handleEvent of sl_lanes.script.lua validates the payload (M.validate) and stores it in the saved state:
-- zones = the list, zrun = the run id (the sender's acknowledgement: it reads zrun back through the
-- GAME_SCRIPT component, M.readSaved), zseq = +1 per change (the GUI mirror re-reads the list only then).
-- id / pair are optional labels the sender reads back after a reload (the Stress Test's twin ids, its
-- traffic log: plans/square_stress_test/FLOW.md); Smart Lanes never uses them. A malformed label is dropped,
-- never the zone. A set replaces every zone; a clear removes them. Zones only affect writes after they arrived: nothing
-- written before is changed or undone.
--
-- Pure apart from M.readSaved (GUI thread). Lua 5.1 syntax (the game's Lua is pre-5.3).

local M = {}

M.EVENT_ID = "square_smart_lanes"
M.EV_ZONES = "SmartLanes.zones"
-- getEntityForGameScript name of sl_lanes.gs.lua (as square_problem_radar's "square_problem_radar::/radar/radar.gs")
M.GS_NAME = "square_smart_lanes::/smart_lanes/sl_lanes.gs"
M.MAX = 400          -- zones per set (more: the whole event is ignored)
M.R_MAX = 2000       -- m, largest radius
M.COORD_MAX = 1e6    -- m, |x| and |y| at most (no map is that large)
M.RUN_MAX = 40       -- characters of the run id
M.AB = { "game", "sl", "sl_phases", "sl_fan", "sl_lock", "sl_exitfan", "sl_keeplights" }
M.LABEL_MAX = 12     -- characters of an optional zone id / pair label ([%w_] only)
local AB_SET = { game = true, sl = true, sl_phases = true, sl_fan = true, sl_lock = true, sl_exitfan = true, sl_keeplights = true }
-- modes counted in byAbText only when present (the line stays as before for senders that know none of them)
local AB_OPTIONAL = { sl_fan = true, sl_lock = true, sl_exitfan = true, sl_keeplights = true }

local function finite(v, max)
	-- NaN fails every comparison, +-inf fails the bound
	return type(v) == "number" and v == v and math.abs(v) <= max
end

--- An optional label (id / pair): kept when 1..LABEL_MAX characters of [%w_], else nil (dropped).
local function validLabel(v)
	if type(v) ~= "string" or #v == 0 or #v > M.LABEL_MAX then return nil end
	if not v:match("^[%w_]+$") then return nil end
	return v
end

local function validRun(run)
	if type(run) == "number" then
		if not finite(run, 1e15) then return nil end
		return string.format("%d", math.floor(run))
	end
	if type(run) ~= "string" or #run == 0 or #run > M.RUN_MAX then return nil end
	if not run:match("^[%w%._%-]+$") then return nil end
	return run
end

--- A run id as validate keeps it (string), nil when it is none (SL-4 zerr.run of a refused payload).
M.runOf = validRun

--- Validates an event param. Returns op ("set" | "clear"), the zone list (fresh tables {x, y, r, ab} plus the
-- optional id / pair labels when well-formed; empty
-- for clear), the run id (string, "-" when none was given); or nil and the reason (never logs the payload).
function M.validate(param)
	if type(param) ~= "table" then return nil, "not_table" end
	local op = param.op
	if op ~= "set" and op ~= "clear" then return nil, "op" end
	local run = "-"
	if param.run ~= nil then
		run = validRun(param.run)
		if run == nil then return nil, "run" end
	end
	if op == "clear" then return op, {}, run end
	local list = param.zones
	if type(list) ~= "table" then return nil, "zones" end
	local n = #list
	if n > M.MAX then return nil, "too_many" end
	local out = {}
	for i = 1, n do
		local z = list[i]
		if type(z) ~= "table" then return nil, "zone" .. i end
		local x, y, r, ab = z.x, z.y, z.r, z.ab
		if not finite(x, M.COORD_MAX) or not finite(y, M.COORD_MAX) then return nil, "xy" .. i end
		if not finite(r, M.R_MAX) or r <= 0 then return nil, "r" .. i end
		if type(ab) ~= "string" or not AB_SET[ab] then return nil, "ab" .. i end
		out[i] = { x = x, y = y, r = r, ab = ab, id = validLabel(z.id), pair = validLabel(z.pair) }
	end
	return op, out, run
end

--- "game:a,sl:b,sl_phases:c" (fixed order, zero counts too), then ",sl_fan:d", ",sl_lock:e", ",sl_exitfan:f" and
-- ",sl_keeplights:g", each only when > 0 (the line stays as before for senders that know none of them: the
-- Stress Test logs the same text from its payload, stress_logic slZonesByAb).
function M.byAbText(list)
	local c = { game = 0, sl = 0, sl_phases = 0, sl_fan = 0, sl_lock = 0, sl_exitfan = 0, sl_keeplights = 0 }
	for _, z in ipairs(list or {}) do
		if c[z.ab] ~= nil then c[z.ab] = c[z.ab] + 1 end
	end
	local parts = {}
	for _, ab in ipairs(M.AB) do
		if not AB_OPTIONAL[ab] or c[ab] > 0 then parts[#parts + 1] = ab .. ":" .. c[ab] end
	end
	return table.concat(parts, ",")
end

--- The mode of the zone a point lies in (nearest centre relative to its radius when several), else nil.
-- Bounded: one pass over at most M.MAX zones. Nil-safe (no list, no point, broken entries).
function M.abAt(list, x, y)
	local z = M.zoneAt(list, x, y)
	return z and z.ab or nil
end

--- The zone a point lies in (the record: x, y, r, ab and the optional id / pair labels; nearest centre relative
-- to its radius when several, the first of equals), else nil. Same rule and bounds as M.abAt.
function M.zoneAt(list, x, y)
	if type(list) ~= "table" or type(x) ~= "number" or type(y) ~= "number" then return nil end
	local best, bestQ = nil, nil
	for _, z in ipairs(list) do
		if type(z) == "table" and type(z.x) == "number" and type(z.y) == "number" and type(z.r) == "number" and z.r > 0 then
			local dx, dy = x - z.x, y - z.y
			local d2 = dx * dx + dy * dy
			local r2 = z.r * z.r
			if d2 <= r2 then
				local q = d2 / r2
				if bestQ == nil or q < bestQ then best, bestQ = z, q end
			end
		end
	end
	return best
end

--- The zone id label (SL-3 zid=) of a zone record, nil without a valid one (labels are [%w_], at most
-- LABEL_MAX characters: validLabel).
function M.idOf(z)
	if type(z) ~= "table" then return nil end
	if type(z.id) ~= "string" or #z.id == 0 or #z.id > M.LABEL_MAX or not z.id:match("^[%w_]+$") then return nil end
	return z.id
end

--- The mode at a node of `world` (sl_write W.makeWorld: world.node(id) has x, y), else nil.
function M.nodeAb(list, world, n)
	if type(list) ~= "table" or #list == 0 or world == nil then return nil end
	local node = world.node(n)
	if node == nil then return nil end
	return M.abAt(list, node.x, node.y)
end

--- The zone list from the saved state of another Lua state (the tool's, GUI thread): the GAME_SCRIPT
-- component of our game script, as square_problem_radar's radar_hud readFields (state_native:find, else the
-- `state` copy; base: industry_productivity_util.tl:5-20). Never the engine-side get_native (findings
-- "Game-script get_native asserts"). Returns the list (possibly empty) or nil when unreadable. Never throws.
function M.readSaved(api)
	local ok, list = pcall(function()
		local entity = api.engine.system.gameScriptSystem.getEntityForGameScript(M.GS_NAME)
		if entity == nil or entity < 0 then return nil end
		local gs = api.engine.getComponent(entity, api.type.ComponentType.GAME_SCRIPT)
		if gs == nil then return nil end
		local okN, v = pcall(function()
			local native = gs.state_native
			if native == nil then error("no state_native") end
			local z = native:find("zones")
			if z == nil then return {} end
			return z:asTable()
		end)
		if okN then return v end
		local st = gs.state
		if type(st) ~= "table" then return nil end
		return st.zones or {}
	end)
	if not ok or type(list) ~= "table" then return nil end
	return list
end

return M
