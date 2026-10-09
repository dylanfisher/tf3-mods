-- Quota Run engine side effects (PLAN.md §4.3, §6 Phase 2). Sim thread only.
-- The interface (QuotaRunEffects in quota_types.d.tl) is frozen; this file holds the bodies.
-- No module-level run state: everything persistent lives in `state` (savedSpeed, fx).
--
-- Citation shorthand: API = .cache/game/api/tealdef, BT = .cache/game/base/tealdef,
-- BC = .cache/game/base/content, MOD = .cache/game/mods/release.

local config = ug_require "/quota/quota_config.tl" as QuotaRunConfig
local cards = ug_require "/quota/quota_cards.tl" as QuotaRunCards
local rules = ug_require "/quota/quota_rules.tl" as QuotaRunRules
local bosses = ug_require "/quota/quota_bosses.tl" as QuotaRunBosses
-- Same construction as the adapter (v2: rules/bosses injected); effects only use rngNext/dump.
local logic = (ug_require "/quota/quota_logic.tl" as QuotaRunLogicModule).new(config, cards, rules, bosses)
-- Base worker-boost math, so our productivity composes with it (PLAN §6 Phase 2).
-- src: BC/industries/industry_productivity_util.tl:1-76, BT/industries/industry_productivity_util.d.tl:3-13
-- (mods must prefix base modules with "::/", PLAN §4 path rules)
local productivity_util = ug_require "::/industries/industry_productivity_util.tl" as IndustryProductivityUtil

local PREFIX <const> = "[QuotaRun] "

--- Our single VehicleModifier source id: the base replaces an id's entry on each event
--- (BC/vehicle/vehicle_modifier.script.tl:107) and aggregates different ids as 1 + sum(v - 1) (:3-23).
local VEHICLE_MOD_ID <const> = "square_quota_run"
--- The notification system finds our .res by replacing ".script" with ".res"
--- (BC/game_mechanics/notifications/notification_util.tl:12-14); both files live in quota/notify/.
local NOTIFY_TYPE <const> = "square_quota_run::/quota/notify/quota_notification.script"
--- src: BC/game_mechanics/notifications/notification_util.tl:10 (defaultAutoDismissDurationMs)
local NOTIFY_DISMISS_MS <const> = 60000
--- |current - desired| above this re-sends an industry's productivity (PLAN §6 Phase 2).
local PRODUCTIVITY_EPS <const> = 0.001

-- src: BT/vehicle/vehicle_modifier.d.tl:4-9 (Modification keys)
local VEHICLE_KEYS : {VehicleModifierChanger.Modification} = { "TopSpeed", "Comfort", "Pollution", "Noise" }

local effects : QuotaRunEffects = {}

local function getGameSpeed() : integer
	-- src: BC/mission/guide_system/guide_system_react.tl:139-140 (GAME_SPEED on the world entity)
	-- src: API/api/engine.d.tl:415-422 (GameSpeed.speedup, 0 = paused)
	local gameSpeed : Engine.Component.GameSpeed = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED)
	return gameSpeed ~= nil and gameSpeed.speedup or nil
end

local function setGameSpeed(speedup : integer)
	-- src: BC/game_mechanics/company/company.script.tl:403 (makeGameSetSpeedCmd from a game script)
	-- src: API/api/cmd.d.tl:708
	api.cmd.sendCommand(api.cmd.makeGameSetSpeedCmd(speedup))
end

--- state.fx, created if a (pre-Phase-2 or damaged) state lacks it or any of its maps.
local function ensureFx(state : QuotaRunState) : QuotaRunFxState
	if state.fx == nil then state.fx = {} end
	local fx = state.fx
	if fx.vehicleMods == nil then fx.vehicleMods = {} end
	if fx.vehicleModsRev == nil then fx.vehicleModsRev = 0 end
	if fx.vehicleApplied == nil then fx.vehicleApplied = {} end
	if fx.industryMods == nil then fx.industryMods = {} end
	return fx
end

local function entityExists(e : integer) : boolean
	-- src: API/api/engine.d.tl:1723 (entityExists); base use: BC/vehicle/vehicle_modifier.script.tl:35
	return e ~= nil and e >= 0 and api.engine.entityExists(e)
end

---------------------------------------------------------------------------
-- Vehicles (PLAN §6 Phase 2): one ChangeModifier id, revision-tracked scan.

--- Fresh modifications table for the current aggregate; keys at 1.0 are omitted.
--- An empty table means "remove our entry" (BC/vehicle/vehicle_modifier.script.tl:84-101).
local function vehicleModifications(fx : QuotaRunFxState) : {VehicleModifierChanger.Modification : number}
	local mods : {VehicleModifierChanger.Modification : number} = {}
	for _, key in ipairs(VEHICLE_KEYS) do
		local v = fx.vehicleMods[key]
		if v ~= nil and math.abs(v - 1.0) > 1e-9 then
			mods[key] = v
		end
	end
	return mods
end

local function sendVehicleChange(entity : integer, mods : {VehicleModifierChanger.Modification : number})
	-- Param shape: BT/vehicle/vehicle_modifier.d.tl:3-13. The base vehicle_modifier game script
	-- subscribes to ChangeModifier itself (BC/vehicle/vehicle_modifier.script.tl:60-64) and only
	-- handles id "VehicleModifier", name "ChangeModifier" (:66-70).
	local changer : VehicleModifierChanger = { entity = entity, id = VEHICLE_MOD_ID, modifications = mods }
	-- src: BC/landmarks/landmarks.script.tl:236 (same call); API/api/cmd.d.tl:788 (makeScriptingSendEventCmd)
	api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "VehicleModifier", "ChangeModifier", changer))
end

--- Max ChangeModifier events per call (Phase 4 perf fix). The base handler does a full
--- state:get()/set() of its per-vehicle map on every event
--- (BC/vehicle/vehicle_modifier.script.tl:72-120), so sending one event per vehicle in one
--- frame is O(N^2). Capped work continues on a later frame (fx.nextScanTime made due).
local function sendCap() : integer
	local cap = config.VEHICLE_SENDS_PER_FRAME
	if cap == nil or cap < 1 then return 2147483647 end	-- no math.maxinteger in the game's pre-5.3 Lua
	return cap
end

--- Remove our modifier from up to sendCap() vehicles we touched and forget them.
--- Returns the events sent and whether entries remain (capped).
local function clearVehicles(fx : QuotaRunFxState) : integer, boolean
	local n = 0
	local cap = sendCap()
	for e, _ in pairs(fx.vehicleApplied) do
		if n >= cap then
			return n, true
		end
		if entityExists(e) then
			sendVehicleChange(e, {})
			n = n + 1
		end
		fx.vehicleApplied[e] = nil -- clearing a field during pairs() is allowed in Lua
	end
	return n, false
end

--- Drop dead entities from vehicleApplied, then send ChangeModifier to every player vehicle
--- whose vehicleApplied rev differs from vehicleModsRev, at most sendCap() per call.
--- Returns the number of events sent and whether vehicles were left for a later call.
local function scanVehicles(state : QuotaRunState) : integer, boolean
	local fx = ensureFx(state)
	-- The base drops its own entries for deleted vehicles (BC/vehicle/vehicle_modifier.script.tl:34-51).
	for e, _ in pairs(fx.vehicleApplied) do
		if not entityExists(e) then fx.vehicleApplied[e] = nil end
	end
	local mods = vehicleModifications(fx)
	if next(mods) == nil then
		-- Neutral aggregate: only vehicles that carry our entry need the removal event; untouched
		-- vehicles would be a no-op in the base (deepEquals(nil, nil), :89-91), so skip the enumeration.
		return clearVehicles(fx)
	end
	local rev = fx.vehicleModsRev
	local sent = 0
	local cap = sendCap()
	-- New vehicles are not discovered by the base, so enumerate the player's fleet.
	-- src: API/api/engine.d.tl:1692-1713 (getEntitiesWithComponent + requireOwnedByPlayer);
	-- API/api/engine/util.d.tl:1023 (getPlayer); API/api/engine.d.tl:1657 (TRANSPORT_VEHICLE)
	local vehicles = api.engine.getEntitiesWithComponent(api.type.ComponentType.TRANSPORT_VEHICLE,
		{ requireOwnedByPlayer = api.engine.util.getPlayer() })
	for _, e in ipairs(vehicles or {}) do
		if fx.vehicleApplied[e] ~= rev then
			if sent >= cap then
				return sent, true
			end
			sendVehicleChange(e, vehicleModifications(fx))
			fx.vehicleApplied[e] = rev
			sent = sent + 1
		end
	end
	return sent, false
end

---------------------------------------------------------------------------
-- Industries (PLAN §6 Phase 2): desired = (base boost or 1.0) * ours, re-asserted every scan.
--
-- There is no composition hook. The base worker script sets productivity to the boost factor or
-- 1.0, and only when an industry's visitor list changes and its view of "boosted"
-- (productivity > 1.0) disagrees with the worker count (BC/industries/industry_workers.script.tl:6-14).
-- Trade-off: when it resets an unboosted industry of ours to 1.0, our multiplier is missing until
-- the next scan (<= SCAN_INTERVAL_FRACTION of a month). Our multipliers are always >= 1.0
-- (PLAN §3.2), so the base's "> 1.0 = boosted" test never sees a curse.

--- The productivity the base would want: its worker boost, or 1.0.
local function baseProductivity(e : integer) : number
	-- src: BC/industries/industry_productivity_util.tl:35-48 (isIndustryWorkersBoosted), :58-72
	-- (getPersonCapacityPotentialBoost); same expression as BC/industries/industry_workers.script.tl:10
	if productivity_util.isIndustryWorkersBoosted(e) then
		return productivity_util.getPersonCapacityPotentialBoost(e)
	end
	return 1.0
end

local function getStockList(e : integer) : Engine.Component.StockList
	if not entityExists(e) then return nil end
	-- src: API/api/engine.d.tl:1690 (getComponent), :1655 (STOCK_LIST), :1191-1196 (Modifiers.productivity);
	-- base read: BC/industries/industry_productivity_util.tl:50-56
	return api.engine.getComponent(e, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList
end

--- Send productivity `desired` to stock list `e` if it differs from the current value.
local function assertProductivity(e : integer, stockList : Engine.Component.StockList, desired : number) : boolean
	local current = stockList.modifiers ~= nil and stockList.modifiers.productivity or nil
	if current ~= nil and math.abs(current - desired) <= PRODUCTIVITY_EPS then
		return false
	end
	-- src: BC/industries/industry_workers.script.tl:11-13 (same construction and command);
	-- API/api/type.d.tl:3854 (api.type.StockList), API/api/cmd.d.tl:810 (makeStockListSetModifiersCmd)
	local mods = api.type.StockList.Modifiers.new()
	mods.productivity = desired
	api.cmd.sendCommand(api.cmd.makeStockListSetModifiersCmd(e, mods))
	return true
end

--- Re-assert desired productivity on every industry we boost; drop dead/invalid entries.
local function scanIndustries(state : QuotaRunState) : integer
	local fx = ensureFx(state)
	local sent = 0
	for e, ours in pairs(fx.industryMods) do
		local stockList = getStockList(e)
		if stockList == nil then
			fx.industryMods[e] = nil
		elseif assertProductivity(e, stockList, baseProductivity(e) * ours) then
			sent = sent + 1
		end
	end
	return sent
end

--- All industry stock-list entities, deduplicated and sorted (deterministic draw order).
--- Note (MVP, accepted): "all industries" cards (industrial_policy) snapshot the industries that
--- exist when the card is picked; industries spawned later are not boosted.
local function industryStockLists() : {integer}
	local seen : {integer : boolean} = {}
	local out : {integer} = {}
	-- src: API/api/engine.d.tl:1713 (getEntitiesWithComponent), :1654 (INDUSTRY), :441-445 (Industry.stockList);
	-- base pattern INDUSTRY -> industry.stockList -> STOCK_LIST: BC/gui/main/industry_util.tl:513-514
	local industries = api.engine.getEntitiesWithComponent(api.type.ComponentType.INDUSTRY)
	for _, e in ipairs(industries or {}) do
		local industry = api.engine.getComponent(e, api.type.ComponentType.INDUSTRY) as Engine.Component.Industry
		local sl = industry ~= nil and industry.stockList or nil
		if sl ~= nil and not seen[sl] and getStockList(sl) ~= nil then
			seen[sl] = true
			out[#out + 1] = sl
		end
	end
	table.sort(out)
	return out
end

--- Pick `count` distinct entries of `list` with the state LCG (partial Fisher-Yates, like
--- logic.drawOffer). nil or count >= #list = all. Mutates `list`.
local function pickIndustries(state : QuotaRunState, list : {integer}, count : integer) : {integer}
	if count == nil or count >= #list then return list end
	local out : {integer} = {}
	for i = 1, math.max(0, count) do
		local j = i - 1 + logic.rngNext(state, #list - i + 1)
		list[i], list[j] = list[j], list[i]
		out[i] = list[i]
	end
	return out
end

---------------------------------------------------------------------------
-- Intent handlers

function effects.log(_state : QuotaRunState, intent : QuotaRunIntent)
	-- src: BT/scripts/log.d.tl:3-8 (log.message / log.warning)
	if intent.level == "warning" then
		log.warning(PREFIX .. tostring(intent.message))
	else
		log.message(PREFIX .. tostring(intent.message))
	end
end

function effects.cash(_state : QuotaRunState, intent : QuotaRunIntent)
	if intent.amount == nil or intent.amount == 0 then return end
	-- src: BC/game_mechanics/subventions/subvention_util.tl:127-134 (journal booking, negative deducts)
	-- src: MOD/urbangames_campaign_mission_08/content/mission/mission_story.tl:1015-1019 (type OTHER)
	local entry = api.type.JournalEntry.new()
	entry.amount = intent.amount
	entry.time = -1
	entry.category.type = api.type.JournalEntry.Type.OTHER
	-- src: API/api/cmd.d.tl:747 (makeJournalBookAssetCmd); API/api/engine/util.d.tl:1023 (getPlayer)
	api.cmd.sendCommand(api.cmd.makeJournalBookAssetCmd(api.engine.util.getPlayer(), entry, api.type.Vec3f.new(0, 0, 0)))
	log.message(PREFIX .. "cash " .. intent.amount)
end

function effects.pause(state : QuotaRunState, _intent : QuotaRunIntent)
	-- Pattern: store speed, then set 0 (src: BC/mission/guide_system/guide_system_react.tl:149-150).
	-- If the game is already paused keep the speed saved by an earlier pause (0 => restore as 1).
	local speed = getGameSpeed()
	if speed ~= nil and speed > 0 then
		state.savedSpeed = speed
	elseif state.savedSpeed == nil then
		state.savedSpeed = 0
	end
	setGameSpeed(0)
	log.message(PREFIX .. "paused (savedSpeed=" .. tostring(state.savedSpeed) .. ")")
end

function effects.resume(state : QuotaRunState, _intent : QuotaRunIntent)
	-- Only if still paused: if the player already unpaused, leave their speed alone (PLAN §4.4).
	local speed = getGameSpeed()
	if speed == 0 then
		local restore = (state.savedSpeed ~= nil and state.savedSpeed > 0) and state.savedSpeed or 1
		setGameSpeed(restore)
		log.message(PREFIX .. "resumed at speed " .. restore)
	else
		log.message(PREFIX .. "resume skipped: game already running at speed " .. tostring(speed))
	end
	state.savedSpeed = 0
end

function effects.notify(_state : QuotaRunState, intent : QuotaRunIntent)
	-- Plain data only; the text is built on the GUI thread in notify/quota_notification.script.tl.
	local params : {string : any} = {}
	for k, v in pairs(intent.params or {}) do params[k] = v end
	params.key = intent.key
	local notification : Notification = {
		type = NOTIFY_TYPE,
		params = params as table,
		autoDismissDuration = NOTIFY_DISMISS_MS,
	}
	-- src: BC/game_mechanics/company/company_growth.script.tl:100-105 (Notification + "Notifications"/"add");
	-- mod type string: MOD/urbangames_campaign_mission_05/content/mission/mission_story.tl:1348-1351;
	-- handler: BC/game_mechanics/notifications/notifications.script.tl:710-718; API/api/cmd.d.tl:788
	api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "Notifications", "add", notification))
	log.message(PREFIX .. "notify " .. tostring(intent.key) .. " " .. logic.dump(intent.params))
end

function effects.vehicleMods(state : QuotaRunState, _intent : QuotaRunIntent)
	-- The logic already updated fx.vehicleMods and bumped vehicleModsRev; apply now.
	local fx = ensureFx(state)
	local sent, capped = scanVehicles(state)
	if capped then
		fx.nextScanTime = 0 -- due on the next unpaused onUpdate (<= any gameTime)
	end
	log.message(PREFIX .. "vehicleMods rev=" .. tostring(fx.vehicleModsRev) .. " " .. logic.dump(fx.vehicleMods)
		.. " sent=" .. sent .. (capped and " (capped, continuing next frames)" or ""))
end

function effects.industryMods(state : QuotaRunState, intent : QuotaRunIntent)
	local fx = ensureFx(state)
	local mult = intent.mult or 1.0
	local chosen = pickIndustries(state, industryStockLists(), intent.industryCount)
	-- Several cards on one industry multiply (PLAN §3.2).
	for _, e in ipairs(chosen) do
		fx.industryMods[e] = (fx.industryMods[e] or 1.0) * mult
	end
	local sent = scanIndustries(state)
	-- Playtest diagnostic (Phase 4): composition with the base worker boost only works if the
	-- stock-list entity is the one carrying PERSON_CAPACITY (BC/industries/industry_productivity_util.tl:42,
	-- BC/industries/industry_workers.script.tl:38). API/api/engine.d.tl:1666 (PERSON_CAPACITY).
	if chosen[1] ~= nil then
		local pc = api.engine.getComponent(chosen[1], api.type.ComponentType.PERSON_CAPACITY) as Engine.Component.PersonCapacity
		log.message(PREFIX .. "industryMods probe: stockList " .. tostring(chosen[1]) .. " PERSON_CAPACITY="
			.. tostring(pc ~= nil) .. " baseBoosted=" .. tostring(productivity_util.isIndustryWorkersBoosted(chosen[1])))
	end
	local ids : {string} = {}
	for i, e in ipairs(chosen) do ids[i] = tostring(e) end
	log.message(PREFIX .. "industryMods count=" .. (intent.industryCount ~= nil and tostring(intent.industryCount) or "all")
		.. " mult=" .. tostring(mult) .. " chosen=" .. #chosen .. " [" .. table.concat(ids, ",") .. "] sent=" .. sent)
end

function effects.clearEffects(state : QuotaRunState, _intent : QuotaRunIntent)
	local fx = ensureFx(state)
	-- Neutral aggregate + rev bump: any later scan (capped continuation) only removes our entry.
	fx.vehicleMods = {}
	fx.vehicleModsRev = (fx.vehicleModsRev or 0) + 1
	local vehicles, capped = clearVehicles(fx)
	if capped then
		-- Continued by onUpdate on later unpaused frames, also in "ended"/"sandbox"
		-- (quota.script.tl update calls effects.onUpdate while fx.vehicleApplied is non-empty).
		fx.nextScanTime = 0
	end
	-- Industries are reset in one go: one direct makeStockListSetModifiersCmd each (no O(N^2)
	-- event fan-out), and the count is bounded by the map's industries.
	local industries = 0
	for e, _ in pairs(fx.industryMods) do
		local stockList = getStockList(e)
		if stockList ~= nil and assertProductivity(e, stockList, baseProductivity(e)) then
			industries = industries + 1
		end
	end
	fx.industryMods = {}
	log.message(PREFIX .. "clearEffects: vehicles=" .. vehicles .. " industries=" .. industries
		.. (capped and " (capped, continuing next frames)" or ""))
end

function effects.onUpdate(state : QuotaRunState, gameTime : integer) : boolean
	local fx = ensureFx(state)
	if fx.nextScanTime ~= nil and gameTime < fx.nextScanTime then
		return false
	end
	-- Idle (no vehicle or industry effect yet): nothing to scan, and no state write per scan.
	-- The first effect intent applies itself immediately; scans start after it.
	if next(fx.vehicleMods) == nil and next(fx.vehicleApplied) == nil and next(fx.industryMods) == nil then
		return false
	end
	-- src: API/api/util.d.tl:114-116 (getDefaultMonthDuration; fallback only, the logic stores monthDuration)
	local month = state.monthDuration or api.util.getDefaultMonthDuration()
	local interval = math.max(1, math.floor(month * config.SCAN_INTERVAL_FRACTION))
	local _sent, capped = scanVehicles(state)
	scanIndustries(state)
	-- Capped: continue next frame; otherwise the regular interval.
	fx.nextScanTime = capped and gameTime or gameTime + interval
	return true
end

function effects.run(state : QuotaRunState, intents : {QuotaRunIntent})
	for _, intent in ipairs(intents or {}) do
		local kind = intent.kind
		if kind == "log" then effects.log(state, intent)
		elseif kind == "cash" then effects.cash(state, intent)
		elseif kind == "pause" then effects.pause(state, intent)
		elseif kind == "resume" then effects.resume(state, intent)
		elseif kind == "notify" then effects.notify(state, intent)
		elseif kind == "vehicleMods" then effects.vehicleMods(state, intent)
		elseif kind == "industryMods" then effects.industryMods(state, intent)
		elseif kind == "clearEffects" then effects.clearEffects(state, intent)
		else log.warning(PREFIX .. "unknown intent kind " .. tostring(kind))
		end
	end
end

return effects
