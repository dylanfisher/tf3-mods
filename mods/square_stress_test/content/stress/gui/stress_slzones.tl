-- Stress Test -> Smart Lanes zones channel (plans/square_stress_test/FLOW_PLAN.md "Revision 2026-10-12:
-- side-by-side twins", FLOW.md "[SQRL] ZONES"). The Showcase builds every junction as twins marked game / sl /
-- sl_phases; Smart Lanes (square_smart_lanes, optional: either mod works without the other, and neither
-- requires the other's code) leaves game zones at the game default and plans sl_phases zones with its light
-- phases.
--
-- Channel (GUI Lua state, Main Thread: rt.tick runs from react.onStep; never from a build event, where
-- sendCommand asserts, findings "game-scripts"):
--   api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "square_smart_lanes", "SmartLanes.zones", payload))
--   (api/tealdef/api/cmd.d.tl:788; square_problem_radar's GUI events use the same call). The engine broadcasts
--   it to every game script subscribed to "SmartLanes.zones": Smart Lanes' handleEvent validates it and stores
--   the zones in its saved game-script state with zrun = the payload's run id. Without Smart Lanes nobody is
--   subscribed and the event is dropped (harmless).
-- Acknowledgement: zrun read back from Smart Lanes' GAME_SCRIPT component (getEntityForGameScript
--   "square_smart_lanes::/smart_lanes/sl_lanes.gs", state_native:find("zrun"), as square_problem_radar's HUD and
--   the base game's industry window read game-script state on the GUI side; never get_native). Only tried when
--   Smart Lanes' mod params are listed (present()), so an unknown game script name is never asked for.
-- Race and its bound: commands run in the order they were sent, so a zones event sent before a build is
--   handled before that build's onPostBuildProposal; Smart Lanes' GUI reads the zones from the same state read
--   that hands it the build's job. The Showcase still waits for the acknowledgement (waitAck, at most
--   ACK_TIMEOUT_MS, after the towns, which take far longer) before its first junction, so an engine that
--   reordered commands could not get ahead either. A timeout (an older Smart Lanes without zones, a paused
--   game) only logs ack=timeout and builds anyway: the zones then may miss the first builds.
-- Traffic log (gui/stress_flow_log.tl): z.current keeps the session's last Showcase zone list (the same tables the
--   Showcase marks built as it reads them); z.savedZones reads Smart Lanes' stored zones back after a reload, with
--   the twin id / pair labels the payload carries (stress_logic.slZonesPayload; Smart Lanes keeps them).

local logic = ug_require "square_stress_test::/stress/stress_logic.tl" as SquareStressLogic
local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl" as SquareStressRuntime

local z : SquareStressSlZones = {
	EVENT_ID = "square_smart_lanes",
	EV_ZONES = "SmartLanes.zones",
	GS_NAME = "square_smart_lanes::/smart_lanes/sl_lanes.gs",
	ACK_TIMEOUT_MS = 5000,
	ACK_POLL_MS = 250,
	IDLE_GAP_MS = 2000,
}

local sends = 0

local function wallS() : integer
	local ok, t = pcall(os.time)
	return (ok and t ~= nil) and math.floor(t as number) or 0
end

function z.present() : boolean
	local ok, all = pcall(function() : any return api.engine.config.getModParams() end)
	return ok and type(all) == "table" and type((all as {string : any})["square_smart_lanes"]) == "table"
end

--- Sends one event; false when the command could not be made or sent (logged).
local function send(payload : {string : any}) : boolean
	local ok, err : boolean, any = pcall(function()
		local cmd = api.cmd.makeScriptingSendEventCmd("", z.EVENT_ID, z.EV_ZONES, payload)
		api.cmd.sendCommand(cmd as Command<ICommandData>)
	end)
	if not ok then rt.log("[SQST] showcase zones send failed: " .. tostring(err)) end
	return ok
end

function z.sendSet(zones : {SquareStressShowcaseZone}, seed : integer) : string
	sends = sends + 1
	local run = logic.slZoneRun(seed, wallS(), sends)
	local payload, dropped = logic.slZonesPayload(zones, run)
	local list = payload.zones as {{string : any}}
	local sl = z.present()
	local okS = send(payload)
	z.current = { run = okS and run or nil, zones = zones, seq = sends }
	rt.log(string.format("[SQST] showcase zones sent n=%d run=%s by_ab=%s smart_lanes=%s%s%s", #list, run, logic.slZonesByAb(list),
		sl and "yes" or "no", dropped > 0 and string.format(" dropped=%d", dropped) or "", okS and "" or " failed=yes"))
	if not okS then return nil end
	return run
end

function z.sendClear(by : string) : string
	sends = sends + 1
	local run = logic.slZoneRun(0, wallS(), sends)
	local okS = send({ op = "clear", run = run })
	z.current = nil
	rt.log(string.format("[SQST] showcase zones cleared by=%s run=%s smart_lanes=%s%s", by, run, z.present() and "yes" or "no",
		okS and "" or " failed=yes"))
	return okS and run or nil
end

--- One value of Smart Lanes' saved state (state_native:find, else the state copy), nil when unreadable.
local function savedField(key : string, asTable : boolean) : any
	if not z.present() then return nil end
	local ok, v = pcall(function() : any
		local entity = api.engine.system.gameScriptSystem.getEntityForGameScript(z.GS_NAME)
		if entity == nil or entity < 0 then return nil end
		local gs = api.engine.getComponent(entity, api.type.ComponentType.GAME_SCRIPT) as Engine.Component.GameScript<{string : any}>
		if gs == nil then return nil end
		local okN, r = pcall(function() : any
			local native = gs.state_native
			if native == nil then error("no state_native") end
			local f = native:find(key) as any
			if f == nil or not asTable then return f end
			return (f as {string : function(any) : any})["asTable"](f)
		end)
		if okN then return r end
		local st = gs.state
		if type(st) ~= "table" then return nil end
		return st[key]
	end)
	if not ok then return nil end
	return v
end

function z.ackRun() : string
	local v = savedField("zrun", false)
	if type(v) ~= "string" then return nil end
	return v as string
end

function z.savedZones() : {{string : any}}, string
	if not z.present() then return nil, nil end
	local list = savedField("zones", true)
	local run = savedField("zrun", false)
	local out : {{string : any}} = {}
	if type(list) == "table" then
		for _, e in ipairs(list as {any}) do
			if type(e) == "table" then
				local t = e as {string : any}
				out[#out + 1] = { x = t.x, y = t.y, r = t.r, ab = t.ab, id = t.id, pair = t.pair }
			end
		end
	end
	return out, type(run) == "string" and run as string or nil
end

--- Smart Lanes' accepted zone modes (its saved `zmodes`, BENCH.md SL-4): nil when it has none (a Smart Lanes
--- without SL-4, or no zones event since the load).
function z.modes() : {string}
	local v = savedField("zmodes", true)
	if type(v) ~= "table" then return nil end
	local out : {string} = {}
	for _, m in ipairs(v as {any}) do
		if type(m) == "string" then out[#out + 1] = m as string end
	end
	return out
end

--- The last refused payload (saved `zerr`: {run, reason}); nil, nil when none.
function z.refused() : string, string
	local v = savedField("zerr", true)
	if type(v) ~= "table" then return nil, nil end
	local t = v as {string : any}
	return type(t.run) == "string" and t.run as string or nil, type(t.reason) == "string" and t.reason as string or nil
end

--- Smart Lanes' queue length (saved `qlen`, BENCH.md SL-5; reported only while zones are set), nil when unreadable.
function z.qlen() : integer
	local v = savedField("qlen", false)
	if type(v) ~= "number" then return nil end
	return math.floor(v as number)
end

--- Calls onDone("yes" | "timeout" | "absent" | "unread", ms) once Smart Lanes' queue is empty twice IDLE_GAP_MS apart
--- (qlen 0), at most maxMs after the call ("unread": no qlen at all, an older Smart Lanes: after IDLE_GAP_MS).
function z.waitIdle(name : string, maxMs : number, onDone : function(result : string, ms : number))
	if not z.present() then onDone("absent", 0) return end
	local t0 = rt.nowUs()
	local zeroAt : number = nil
	local seen = false
	local function poll()
		local ms = (rt.nowUs() - t0) / 1000
		local q = z.qlen()
		if q ~= nil then seen = true end
		if q == 0 then
			if zeroAt == nil then zeroAt = ms end
			if ms - zeroAt >= z.IDLE_GAP_MS then onDone("yes", ms) return end
		else
			zeroAt = nil
		end
		if not seen and ms >= z.IDLE_GAP_MS then onDone("unread", ms) return end
		if ms >= maxMs then onDone("timeout", ms) return end
		rt.later(name, z.ACK_POLL_MS, poll)
	end
	poll()
end

function z.waitAck(run : string, onDone : function(result : string, ms : number))
	if run == nil then onDone("unsent", 0) return end
	if not z.present() then onDone("absent", 0) return end
	local t0 = rt.nowUs()
	local function poll()
		local ms = (rt.nowUs() - t0) / 1000
		if z.ackRun() == run then onDone("yes", ms) return end
		-- refused as a whole (an unknown mode, too many zones): SL-4's zerr names this run
		local rr, why = z.refused()
		if rr == run then onDone("refused:" .. tostring(why), ms) return end
		if ms >= z.ACK_TIMEOUT_MS then onDone("timeout", ms) return end
		rt.later("showcase:zones_ack", z.ACK_POLL_MS, poll)
	end
	poll()
end

return z
