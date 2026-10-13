-- Stress Test GUI runtime: the job queue, the [SQST] log, command sending and the balance top-up.
-- Shared by stress_hud.script.tl (window + HUD button) and stress_probes.tl through the require
-- cache of the GUI Lua state. Nothing here is saved; the queue empties on a reload.
--
-- THREADS: rt.tick runs from react.onStep of the always-mounted HUD button (Main Thread, docs/findings.md
-- "Timers and threads in GUI contexts"), so every command is sent from the GUI main thread, never from
-- onStepTimer (worker threads) or a build event. api.cmd from the GUI state runs the command in the
-- next simulation step and calls the callback a frame after it ran (api/tealdef/api/cmd.d.tl:1-10).

local logic = ug_require "square_stress_test::/stress/stress_logic.tl" as SquareStressLogic
local nc = ug_require "square_stress_test::/stress/gui/stress_nodecfg.tl" as SquareStressNodeCfg

local RECENT_MAX <const> = 8
local TOPUP_CHECK_US <const> = 2000000
-- A booked top-up only shows in the balance after a simulation step; while the game is paused the
-- balance doesn't move, so wait this long before booking again at the same balance.
local TOPUP_RETRY_US <const> = 20000000

local rt : SquareStressRuntime = {
	queue = nil,
	version = 0,
	recent = {},
	warnings = {},
	keepBalance = false,
	hideNotifications = true,
	notificationsSent = false,
	KEEP_BALANCE = 50000000,
	PER_FRAME = 4,
	tickHooks = {},
	queueClears = 0,
	lines = 0,
}
rt.queue = logic.newQueue(rt.PER_FRAME)

local clock : Clock = nil

function rt.nowUs() : integer
	-- api.type.Clock: microseconds since construction, safe in every GUI context (docs/findings.md).
	if clock == nil then clock = api.type.Clock.new() end
	return clock:getTime()
end

function rt.log(msg : string)
	rt.lines = rt.lines + 1
	log.message(msg)   -- full text (with any traceback) to stdout.txt
	rt.recent[#rt.recent + 1] = logic.oneLine(msg)   -- one line in the window
	while #rt.recent > RECENT_MAX do table.remove(rt.recent, 1) end
	rt.version = rt.version + 1
end

--- A node's BASE_NODE_CONFIG for a street proposal that replaces or removes some of its edges:
--- connections and crosswalks through `gone` edges dropped, edge ids in `newIds` (old -> new temp id)
--- re-pointed. Read connections are read-only, so they are rebuilt with api.type.LaneConnection.new()
--- (docs/findings.md "Junction lane connections"; plain tables when the constructor is missing). Send
--- it as nodeConfigsToRemove {node} + nodeConfigsToAdd {entry}, never the remove alone. Second
--- result: how many connections and crosswalks were dropped or re-pointed. nil without a config.
function rt.nodeConfigEntry(node : integer, newIds : {integer : integer}, gone : {integer : boolean}) : Proposal.BaseNodeLaneConnectionAndEntity, integer
	local cfg = api.engine.getComponent(node, api.type.ComponentType.BASE_NODE_CONFIG) as Engine.Component.BaseNodeConfig
	if cfg == nil then return nil, 0 end
	newIds = newIds or {}
	gone = gone or {}
	local LC = (api.type as {string : any})["LaneConnection"] as {string : function() : any}
	local conns : {any} = {}
	local changed = 0
	local dropped = false
	-- for the light phases (nc.relight): old index -> re-pointed connection, old crosswalk -> new position
	local oldMap : {integer : {integer}} = {}
	local plain : {{integer}} = {}
	local cwMap : {integer : integer} = {}
	local nOld = #(cfg.laneConnections or {})
	for i = 1, nOld do
		local old = cfg.laneConnections[i]
		if gone[old.segment0] or gone[old.segment1] then
			changed = changed + 1
			dropped = true
		else
			if newIds[old.segment0] ~= nil or newIds[old.segment1] ~= nil then changed = changed + 1 end
			local lc : {string : any} = LC ~= nil and LC.new ~= nil and LC.new() as {string : any} or {}
			lc.segment0 = newIds[old.segment0] or old.segment0
			lc.lane0 = old.lane0
			lc.segment1 = newIds[old.segment1] or old.segment1
			lc.lane1 = old.lane1
			lc.withRoad = old.withRoad
			lc.withTram = old.withTram
			conns[#conns + 1] = lc
			local pc = { lc.segment0 as integer, old.lane0, lc.segment1 as integer, old.lane1 }
			oldMap[i] = pc
			plain[#plain + 1] = pc
		end
	end
	local cws : {integer} = {}
	local nCwOld = #(cfg.crosswalks or {})
	for i = 1, nCwOld do
		local c = cfg.crosswalks[i]
		if gone[c] then
			changed = changed + 1
			dropped = true
		else
			if newIds[c] ~= nil then changed = changed + 1 end
			cws[#cws + 1] = newIds[c] or c
			cwMap[i] = #cws
		end
	end
	local entry = api.type.BaseNodeLaneConnectionAndEntity.new()
	entry.entity = node
	entry.comp = cfg
	entry.comp.laneConnections = conns as {LaneConnection}
	entry.comp.crosswalks = cws
	-- dropped connections or crosswalks shift the light phases' indices: re-point them (stale ones
	-- crash the simulation, docs/findings/roads.md "Traffic light phases index the lane connections")
	if dropped then nc.relight(entry, cfg, oldMap, nOld, plain, cwMap, nCwOld) end
	return entry, changed
end

--- A warning the window shows in a dialog (the HUD pops rt.warnings), also logged.
function rt.warn(title : string, body : string)
	rt.log("[SQST] " .. title .. ": " .. body)
	rt.warnings[#rt.warnings + 1] = { title = title, body = body }
end

function rt.detail(msg : string)
	rt.lines = rt.lines + 1
	log.message(msg)
end

function rt.probe(name : string, ok : boolean, details : string)
	rt.log(string.format("[SQST-PROBE] %s %s %s", name, ok and "ok" or "fail", details or ""))
end

function rt.enqueue(name : string, total : integer, step : function(i : integer, job : SquareStressJob), opts? : SquareStressJobOpts) : SquareStressJob
	local job : SquareStressJob = { name = name, total = total, step = step }
	if opts ~= nil then
		job.quiet = opts.quiet
		job.label = opts.label
		if opts.serial then
			job.serial = true
			job.waitTimeoutUs = math.floor((opts.timeoutMs or logic.SERIAL_TIMEOUT_MS) * 1000)
		end
		job.maxPerTick = opts.maxPerTick
		if opts.delayMs ~= nil and opts.delayMs > 0 then
			job.notBefore = rt.nowUs() + math.floor(opts.delayMs * 1000)
		end
	end
	logic.push(rt.queue, job)
	rt.version = rt.version + 1
	return job
end

--- One quiet, delayed step (follow-up reads of the probes). An error becomes a probe fail line.
function rt.later(name : string, delayMs : number, fn : function())
	rt.enqueue(name, 1, function(_i : integer)
		local ok, err : boolean, any = pcall(fn)
		if not ok then rt.probe(name, false, "error: " .. tostring(err)) end
	end, { delayMs = delayMs, quiet = true })
end

--- sendCommand with a protected callback. Logs a failed command as "[SQST] cmd <name> failed".
--- onDone also gets the resultEntities ({entity, revision} pairs, api/tealdef/api/cmd.d.tl:598-600).
function rt.send(name : string, cmd : any, onDone? : function(success : boolean, data : any, resultEntities : {{integer}}))
	api.cmd.sendCommand(cmd as Command<ICommandData>, function(data : ICommandData, success : boolean, resultEntities : {{Engine.Entity, Engine.Revision}})
		if not success then rt.log("[SQST] cmd " .. name .. " failed") end
		if onDone ~= nil then
			local ok, err : boolean, any = pcall(onDone, success, data, resultEntities as {{integer}})
			if not ok then rt.log("[SQST] callback " .. name .. " error: " .. tostring(err)) end
		end
	end)
end

--- The name of a queued or running job whose name starts with one of the prefixes, else nil (the
--- buttons refuse a second batch of the same kind instead of stacking it; 2026-10-10 three quick clicks
--- queued three bus-line batches).
-- Job-name prefixes of the test builds (Junction test, Crossing test, Showcase and their bus lines): the tests
-- refuse each other while one runs, and Remove all roads / Remove towns refuse while one runs (a removal queued
-- between a test's towns and its junctions would leave the test half linked).
rt.TEST_JOBS = { "junction_test", "junction_grid", "crossing_test", "crossing_towns", "bus_lines_junction_test",
	"bus_lines_crossing_test", "showcase", "bus_lines_showcase", "lights_showcase", "bus_lines_lights_showcase", "bench_" }

function rt.busyJob(prefixes : {string}) : string
	for _, job in ipairs(rt.queue.jobs) do
		for _, p in ipairs(prefixes) do
			if job.name ~= nil and string.sub(job.name, 1, #p) == p then return job.name end
		end
	end
	return nil
end

local function hasComp(e : integer, ct : Engine.ComponentType) : boolean
	if e == nil or e < 0 or ct == nil then return false end
	local okE, ex = pcall(api.engine.entityExists, e)
	if not okE or not ex then return false end
	local ok, c : boolean, any = pcall(api.engine.getComponent, e, ct)
	return ok and c ~= nil
end

--- Whether e still exists and still is a transport vehicle. Checked before every vehicle command: a
--- tracked id must never be acted on after the entity is gone or its id now names something else
--- (2026-10-10 crash: a TransportVehicle read on an entity that looked like a street stop).
function rt.isVehicle(e : integer) : boolean
	return hasComp(e, api.type.ComponentType.TRANSPORT_VEHICLE)
end

--- Whether e still exists and still is a line (checked before makeLineDestroyCmd).
function rt.isLine(e : integer) : boolean
	return hasComp(e, api.type.ComponentType.LINE)
end

--- Whether e belongs to the player: PLAYER_OWNED.player (api/tealdef/api/engine.d.tl:855-859) is
--- rt.player(); true when the component can't be read (not every entity type carries it).
function rt.ownedByPlayer(e : integer) : boolean
	local ct = api.type.ComponentType.PLAYER_OWNED
	if ct == nil then return true end
	local ok, po : boolean, any = pcall(api.engine.getComponent, e, ct)
	if not ok or po == nil then return true end
	local okP, p = pcall(function() : integer return (po as Engine.Component.PlayerOwned).player end)
	if not okP or p == nil then return true end
	return p == rt.player()
end

function rt.camera() : number, number
	-- GUI main thread only (api/tealdef/api/gui.d.tl:434): call from onClick or onStep.
	local d = api.gui.camera.getCameraData()
	return d.x, d.y
end

function rt.player() : integer
	return api.engine.util.getPlayer()
end

--- Player balance, nil when unknown (infinite money). src: base finance/loan.script.tl:47.
function rt.balance() : integer
	local ok, b = pcall(api.engine.util.finance.getPlayersBalance, api.engine.util.getPlayer())
	if not ok then return nil end
	return b as integer
end

--- Books money for the player as "Other" income. Pattern: mods/square_full_refund/content/refund/refund.script.tl
--- book() (api/tealdef/api/cmd.d.tl:747); amount is passed as is (callers split it with logic.bookingChunks).
function rt.book(amount : number)
	local entry = api.type.JournalEntry.new()
	entry.amount = math.floor(amount)
	entry.time = -1
	entry.category.type = api.type.JournalEntry.Type.OTHER
	rt.send("book", api.cmd.makeJournalBookAssetCmd(api.engine.util.getPlayer(), entry, api.type.Vec3f.new(0, 0, 0)))
end

local nextTopUpCheck = 0
local lastTopUpBalance : integer = nil
local lastTopUpAt = 0

local function topUpTick(now : integer)
	if not rt.keepBalance or now < nextTopUpCheck then return end
	nextTopUpCheck = now + TOPUP_CHECK_US
	local b = rt.balance()
	local amount = logic.topUpAmount(b, rt.KEEP_BALANCE, 10000000)
	if amount <= 0 then
		lastTopUpBalance = nil
		return
	end
	if lastTopUpBalance == b and now - lastTopUpAt < TOPUP_RETRY_US then return end
	lastTopUpBalance, lastTopUpAt = b, now
	local chunks = logic.bookingChunks(amount)
	rt.enqueue("top_up", #chunks, function(i : integer) rt.book(chunks[i]) end)
end

---------------------------------------------------------------------------
-- Hide all notifications: the base Notifications game script's "updateIgnoredTypes" event
-- (stress_logic.notificationPayload). The ignored set is saved with the game script state, so the
-- default (on) is sent once per session from the first tick (Main Thread, never at file load), and
-- again whenever the box changes.

--- Every notification type name with a label (base notification_util.getNotificationType2Label, the
--- notification log's own list, gui/notification_log.tl:7,227); nil when unavailable.
local function notificationTypeNames() : {string}
	local ok, names = pcall(function() : {string}
		local nu = ug_require "::/game_mechanics/notifications/notification_util.tl" as NotificationUtil
		local out : {string} = {}
		for name, _ in pairs(nu.getNotificationType2Label()) do out[#out + 1] = name end
		table.sort(out)
		return out
	end)
	if not ok then return nil end
	return names
end

local function sendNotifications()
	local on = rt.hideNotifications
	rt.notificationsSent = true
	local names : {string} = nil
	if on then names = notificationTypeNames() end
	local payload = logic.notificationPayload(on, names)
	rt.send("notifications", api.cmd.makeScriptingSendEventCmd("", "Notifications", "updateIgnoredTypes", payload),
		function(success : boolean, _d : any)
			rt.log(string.format("[SQST] notifications %s success=%s (gui types %s, type names %s)", on and "hidden" or "shown",
				tostring(success), on and table.concat(logic.NOTIFICATION_GUI_TYPES, ",") or "none",
				names ~= nil and tostring(#names) or "unavailable"))
		end)
end

function rt.setHideNotifications(on : boolean)
	if on == rt.hideNotifications and rt.notificationsSent then return end
	rt.hideNotifications = on
	rt.notificationsSent = false   -- the next tick sends it (Main Thread)
	rt.version = rt.version + 1
end

function rt.addTickHook(fn : function(nowUs : integer))
	rt.tickHooks[#rt.tickHooks + 1] = fn
end

function rt.clearQueue() : integer
	local n = logic.clear(rt.queue)
	rt.queueClears = rt.queueClears + 1
	rt.version = rt.version + 1
	return n
end

--- Called every frame from react.onStep: notifications, top-up check, tick hooks (Keep traffic cleared),
--- then at most PER_FRAME queued steps.
function rt.tick()
	local now = rt.nowUs()
	if not rt.notificationsSent then
		local okN, errN : boolean, any = pcall(sendNotifications)
		if not okN then rt.log("[SQST] notifications error: " .. tostring(errN)) end
	end
	local ok, err : boolean, any = pcall(topUpTick, now)
	if not ok then rt.log("[SQST] top-up error: " .. tostring(err)) end
	for _, hook in ipairs(rt.tickHooks) do
		local okH, errH : boolean, any = pcall(hook, now)
		if not okH then rt.log("[SQST] tick hook error: " .. tostring(errH)) end
	end
	if #rt.queue.jobs == 0 then return end
	local finished = logic.tick(rt.queue, rt.nowUs)
	rt.version = rt.version + 1
	for _, d in ipairs(finished) do
		if not d.quiet or d.errors > 0 then rt.log(logic.doneLine(d)) end
	end
end

return rt
