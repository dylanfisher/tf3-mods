-- DEV probe for Line Manager Plus feature 5 "Balance vehicles" (plans/square_line_manager_plus/PLAN.md "5." and
-- phase 6; steps: PROBE.md). Never upload. Every line it logs starts with "[LMPProbe]" (print -> stdout.txt).
--
-- Mount: same technique as square_line_rate_matcher_probe (proven in game, docs/findings.md "Line Rate, cloning"):
-- * line_util.makeLineActionDescriptor is wrapped to capture the manager's commonParams; the line shown in the
--   details panel is commonParams.lineState:old().entityAndRevision.entity (manager_window.tl:458-459).
-- * button_react_util.makeIconToggleButton is wrapped; when it builds the Auto-Rename "A+" icon inside the
--   LinePanelActionButtons recipe, our button row goes to its left. doReplace order 260 reads the current module
--   functions, so Line Manager Plus (250) and the RM probe (250) stay in the chain.
--
-- Buttons: "LMPP" toggles the row. "Snap" = read-only spacing sampler (probe questions 2 and 3). "Send:plan",
-- "Send:back", "Send:same" = re-send test (question 1): makeVehicleSetLineCmd on ONE vehicle of the same line.
-- Commands are sent only from click handlers (GUI thread); the callback only logs.
-- Samplers run in the row's useStepState getter (react.onStep, Main Thread per docs/findings.md "Timers and threads
-- in GUI contexts"), timed with api.type.Clock, so they only run while the row is mounted: keep the Line Manager open
-- on that line.
--
-- API sources (.cache/game):
--   TRANSPORT_VEHICLE fields       api/tealdef/api/engine.d.tl:1380-1530 (stopIndex, lineStopDepartures, sectionTimes,
--                                  loadState, timeUntilNextScheduledDeparture, timeUntilDeparture, autoDeparture)
--   LoadState enum                 api.type.TransportVehicle.LoadState (entity_window_util.tl:2279-2284)
--   GAME_TIME                      api/tealdef/api/engine.d.tl:425-431
--   cargo on board                 api/tealdef/api/engine/system.d.tl:209-214 simEntityAtVehicleSystem
--   position / speed               api/tealdef/api/engine/util.d.tl:437-445 api.engine.util.vehicle
--   set line                       api/tealdef/api/cmd.d.tl:916-922 (stop index is 0-based: findings "cloning")

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl"
local button_react_util = ug_require "::/gui/main/button_react_util.tl"
local line_util = ug_require "::/gui/line_vehicle_mgmt/line_util.tl"

local AUTO_RENAME_ICON = "::/gui/line_vehicle_mgmt/icons/symbol_autorename.tga"
local RECIPE_ACTION_BUTTONS = "LinePanelActionButtons"
local SNAP_CHECK_US = 1000000 -- check every 1 s: log changed vehicles and WaitForScheduledDeparture ones
local SNAP_FULL_US = 10000000 -- full snapshot every 10 s
local SNAP_TOTAL_US = 60000000 -- for 60 s
local TRACK_LOG_US = 2000000 -- re-sent vehicle: every 2 s
local TRACK_TOTAL_US = 60000000 -- for 60 s
local DEP_UNITS_PER_SEC = 1000 -- ASSUMPTION: gameTime / lineStopDepartures in ms; sectionTimes in s (checked in log)

-- Logging --------------------------------------------------------------------------------------------------------
local function say(...)
	local parts = { "[LMPProbe]" }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring(select(i, ...))
	end
	print(table.concat(parts, " "))
end

--- pcall that logs the error and returns nil on failure.
local function try(label, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
	say("ERROR", label, a)
	return nil
end

local function fmt(x)
	if type(x) == "number" then
		if x == math.floor(x) and math.abs(x) < 1e15 then return string.format("%.0f", x) end
		return string.format("%.2f", x)
	end
	return tostring(x)
end

--- "[a,b,c]" of a list (userdata lists from the engine iterate with ipairs).
local function list(t)
	if t == nil then return "nil" end
	local out = {}
	local ok = pcall(function()
		for _i, v in ipairs(t) do out[#out + 1] = fmt(v) end
	end)
	return "[" .. table.concat(out, ",") .. "]" .. (ok and "" or "?")
end

-- Clock (safe on every thread, docs/findings.md) ---------------------------------------------------------------------
local clock
local function nowUs()
	if not clock then clock = api.type.Clock.new() end
	return clock:getTime()
end

-- State ------------------------------------------------------------------------------------------------------------
local managerParams -- latest commonParams seen by makeLineActionDescriptor
local status = "idle"
local snap -- { line, t0, nextCheck, nextFull, untilUs, last = { [v] = key } }
local track -- { v, line, label, t0, nextLog, untilUs, lastX, lastY }

local function setStatus(text)
	status = tostring(text)
	say("status", status)
end

local function lineOf(params)
	local ls = params and params.lineState and params.lineState:old()
	local e = ls and ls.entityAndRevision and ls.entityAndRevision.entity or nil
	if e and e >= 0 then return e end
	local st = params and params.lineManagerStateRef and params.lineManagerStateRef:get()
	local sel = st and st.lineListEntitiesSelected
	if sel and #sel == 1 then
		local s = sel[1]
		if type(s) == "number" then return s end
		if type(s) == "table" or type(s) == "userdata" then return s.entity end
	end
	return nil
end

local function isLine(e)
	return type(e) == "number" and e >= 0 and api.engine.entityExists(e)
		and api.engine.getComponent(e, api.type.ComponentType.LINE) ~= nil
end

local function nameOf(e)
	local ok, n = pcall(function()
		local c = api.engine.getComponent(e, api.type.ComponentType.NAME)
		return c and c.name
	end)
	return ok and n or nil
end

local function cargoName(id)
	local ok, n = pcall(function() return api.res.cargoTypeRep.get(id).name end)
	return (ok and n) and (n .. "#" .. tostring(id)) or ("cargo#" .. tostring(id))
end

local function gameTime()
	local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
	return gt and gt.gameTime or -1
end

local STATE_NAMES
local function stateName(s)
	if not STATE_NAMES then
		STATE_NAMES = {}
		local e = api.type["enum"].TransportVehicleState
		for _i, k in ipairs({ "IN_DEPOT", "EN_ROUTE", "AT_TERMINAL", "GOING_TO_DEPOT" }) do
			local ok, v = pcall(function() return e[k] end)
			if ok and v ~= nil then STATE_NAMES[v] = k end
		end
	end
	return STATE_NAMES[s] or ("state" .. tostring(s))
end

local LOAD_NAMES
local LOAD_KEYS = { "None", "Arrived", "Unloading", "Loading", "WaitForScheduledDeparture", "Departing" }
local function loadName(s)
	if not LOAD_NAMES then
		LOAD_NAMES = {}
		for _i, k in ipairs(LOAD_KEYS) do
			local ok, v = pcall(function() return api.type.TransportVehicle.LoadState[k] end)
			if ok and v ~= nil then LOAD_NAMES[#LOAD_NAMES + 1] = { v, k } end
		end
	end
	for _i, p in ipairs(LOAD_NAMES) do
		local ok, same = pcall(function() return p[1] == s end)
		if ok and same then return p[2] end
	end
	return "load" .. tostring(s)
end

local function isWaitScheduled(s)
	local ok, same = pcall(function() return s == api.type.TransportVehicle.LoadState.WaitForScheduledDeparture end)
	return ok and same
end

local function tvOf(v)
	return api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE)
end

local function lineVehicles(line)
	return api.engine.system.transportVehicleSystem.getLineVehicles(line) or {}
end

local function lineStopCount(line)
	local comp = api.engine.getComponent(line, api.type.ComponentType.LINE)
	return comp and comp.stops and #comp.stops or 0
end

--- "Passengers#0=12/40 total=12" for the cargo on board (capacities indexed by cargo id + 1).
local function cargoText(v, tv)
	local parts = {}
	pcall(function()
		local sys = api.engine.system.simEntityAtVehicleSystem
		for k, c in ipairs(tv.config.capacities) do
			if c and c > 0 then
				local n = sys.getVehicleSimEntitiesCountForCargoType(v, k - 1)
				parts[#parts + 1] = cargoName(k - 1) .. "=" .. tostring(n) .. "/" .. tostring(c)
			end
		end
	end)
	local total = try("cargo total", function() return api.engine.system.simEntityAtVehicleSystem.getVehicleSimEntitiesCount(v) end)
	return table.concat(parts, " ") .. " total=" .. tostring(total)
end

local function posOf(v)
	local ok, x, y = pcall(function()
		local p = api.engine.util.vehicle.getPosition(v)
		return p.x, p.y
	end)
	if ok then return x, y end
	return nil, nil
end

local function speedOf(v)
	local ok, s = pcall(function() return api.engine.util.vehicle.getSpeed(v) end)
	return ok and s or nil
end

-- Progress model (PLAN "5." Option A) ------------------------------------------------------------------------------
-- Per vehicle: last departed stop = the lineStopDepartures entry with the latest timestamp ("byDep"); also the one
-- implied by stopIndex (0-based next/current stop -> 1-based previous) as a cross-check ("byIdx").
-- Section times: line average per section index over the vehicles that have a value > 0 (ASSUMPTION: section i runs
-- from stop i to stop i+1; the depDiffs logged per vehicle show whether that holds).
-- progress = cum[last] + (gameTime - dep[last]) / DEP_UNITS_PER_SEC, cum[i] = sum of avg sections 1..i-1.
-- Round trip T = sum of avg sections; headway H = T / n (n = vehicles with a progress).

local function lastDeparted(tv)
	local best, bestT = nil, nil
	for i, t in ipairs(tv.lineStopDepartures) do
		if t and t > 0 and (bestT == nil or t > bestT) then best, bestT = i, t end
	end
	return best, bestT
end

local function model(line, vehicles)
	local S = lineStopCount(line)
	local now = gameTime()
	local sum, cnt = {}, {}
	local rows = {}
	for _i, v in ipairs(vehicles) do
		local tv = tvOf(v)
		if tv then
			local row = { v = v, tv = tv }
			pcall(function()
				for i, s in ipairs(tv.sectionTimes) do
					if s and s > 0 then
						sum[i] = (sum[i] or 0) + s
						cnt[i] = (cnt[i] or 0) + 1
					end
				end
			end)
			rows[#rows + 1] = row
		end
	end
	local avg, T, complete = {}, 0, S > 0
	for i = 1, S do
		avg[i] = cnt[i] and (sum[i] / cnt[i]) or 0
		if avg[i] <= 0 then complete = false end
		T = T + avg[i]
	end
	local cum = {}
	local acc = 0
	for i = 1, S do
		cum[i] = acc
		acc = acc + avg[i]
	end
	local active = {}
	for _i, row in ipairs(rows) do
		local tv = row.tv
		local st = stateName(tv.state)
		row.byDep, row.depT = lastDeparted(tv)
		row.byIdx = (S > 0 and tv.stopIndex ~= nil and tv.stopIndex >= 0) and ((tv.stopIndex - 1) % S) + 1 or nil
		if (st == "EN_ROUTE" or st == "AT_TERMINAL") and row.byDep and T > 0 then
			row.since = (now - row.depT) / DEP_UNITS_PER_SEC
			row.progress = (cum[row.byDep] or 0) + row.since
			if row.progress >= T then row.progress = row.progress % T end
			active[#active + 1] = row
		end
	end
	table.sort(active, function(a, b) return a.progress < b.progress end)
	local n = #active
	local H = n > 0 and T / n or 0
	for i, row in ipairs(active) do
		local ahead = active[(i % n) + 1]
		row.ahead = ahead.v
		row.gapAhead = n > 1 and ((ahead.progress - row.progress) % T) or T
	end
	return { S = S, now = now, avg = avg, cum = cum, T = T, H = H, n = n, active = active, rows = rows, complete = complete }
end

--- 0-based stop index whose cum (departure time from that stop, in loop seconds) is closest to x (circular).
local function stopNear(m, x)
	local best, bestD = nil, nil
	for i = 1, m.S do
		local d = math.abs(m.cum[i] - x)
		if m.T > 0 then d = math.min(d, m.T - d) end
		if bestD == nil or d < bestD then best, bestD = i - 1, d end
	end
	return best
end

--- Option A preview: the most bunched vehicle (smallest gap ahead) and the stop in the middle of the largest gap.
local function plan(m)
	if m.n < 2 then return nil end
	local bunched, largest = nil, nil
	for _i, row in ipairs(m.active) do
		if not bunched or row.gapAhead < bunched.gapAhead then bunched = row end
		if not largest or row.gapAhead > largest.gapAhead then largest = row end
	end
	local target = (largest.progress + largest.gapAhead / 2) % m.T
	return {
		vehicle = bunched.v, gapAhead = bunched.gapAhead, wouldResend = bunched.gapAhead < 0.5 * m.H,
		largestBehind = largest.v, largestGap = largest.gapAhead, targetProgress = target, stop0 = stopNear(m, target),
	}
end

-- Logging a vehicle ------------------------------------------------------------------------------------------------
local function vehicleKey(tv)
	return stateName(tv.state) .. "|" .. loadName(tv.loadState) .. "|" .. tostring(tv.stopIndex)
end

local function depDiffs(tv)
	local d = {}
	pcall(function()
		local deps = {}
		for i, t in ipairs(tv.lineStopDepartures) do deps[i] = t end
		for i = 1, #deps do
			local a, b = deps[i], deps[(i % #deps) + 1]
			d[i] = (a and b and a > 0 and b > 0) and ((b - a) / DEP_UNITS_PER_SEC) or "-"
		end
	end)
	return list(d)
end

local function logVehicle(prefix, row, m)
	local v, tv = row.v, row.tv
	local x, y = posOf(v)
	say(string.format("%s v=%s name=%s state=%s load=%s stopIndex=%s lastDep(byDep/byIdx)=%s/%s since=%s progress=%s gapAhead=%s(ahead %s) "
		.. "gap/H=%s tUntilDep=%s tUntilSched=%s tUntilDoors=%s autoDep=%s userStopped=%s daysAtTerminal=%s noPath=%s "
		.. "lastLineStopDeparture=%s deps=%s depDiffs(s)=%s sectionTimes=%s visited=%s cargo[%s] pos=%s,%s speed=%s",
		prefix, tostring(v), tostring(nameOf(v)), stateName(tv.state), loadName(tv.loadState), tostring(tv.stopIndex),
		tostring(row.byDep), tostring(row.byIdx), fmt(row.since), fmt(row.progress), fmt(row.gapAhead), tostring(row.ahead),
		(row.gapAhead and m and m.H > 0) and fmt(row.gapAhead / m.H) or "-",
		fmt(tv.timeUntilDeparture), fmt(tv.timeUntilNextScheduledDeparture), fmt(tv.timeUntilCloseDoors),
		tostring(tv.autoDeparture), tostring(tv.userStopped), tostring(tv.daysAtTerminal), tostring(tv.noPath),
		fmt(tv.lastLineStopDeparture), list(tv.lineStopDepartures), depDiffs(tv), list(tv.sectionTimes),
		list(tv.visitedStops), cargoText(v, tv), fmt(x), fmt(y), fmt(speedOf(v))))
end

local function fullSnapshot(line, label)
	local vehicles = lineVehicles(line)
	local m = model(line, vehicles)
	say(string.format("==== snapshot %s line=%s name=%s gameTime=%s stops=%d vehicles=%d active=%d T(s)=%s H(s)=%s "
		.. "sectionsComplete=%s avgSections=%s cum=%s frequencySec=%s",
		label, tostring(line), tostring(nameOf(line)), fmt(m.now), m.S, #vehicles, m.n, fmt(m.T), fmt(m.H),
		tostring(m.complete), list(m.avg), list(m.cum),
		tostring(try("frequency", function() return line_util.calculateFrequencySeconds(line) end))))
	local order = {}
	for _i, row in ipairs(m.active) do order[#order + 1] = tostring(row.v) .. "@" .. fmt(row.progress) end
	say("  order by progress:", table.concat(order, " "))
	for i, row in ipairs(m.rows) do try("vehicle", logVehicle, "  vehicle " .. i, row, m) end
	local p = plan(m)
	if p then
		say(string.format("  plan: most bunched v=%s gapAhead=%s (%.2f H) wouldResend=%s | largest gap %s behind v=%s -> "
			.. "target progress %s = stop index (0-based) %s", tostring(p.vehicle), fmt(p.gapAhead), m.H > 0 and p.gapAhead / m.H or 0,
			tostring(p.wouldResend), fmt(p.largestGap), tostring(p.largestBehind), fmt(p.targetProgress), tostring(p.stop0)))
	else
		say("  plan: fewer than 2 active vehicles with a progress")
	end
	say("==== end snapshot", label)
	return m, p
end

-- Snapshot sampler (questions 2, 3) ----------------------------------------------------------------------------------
local function startSnap(line)
	local t = nowUs()
	snap = { line = line, t0 = t, nextCheck = t, nextFull = t, untilUs = t + SNAP_TOTAL_US, last = {} }
	say("snap start line", line, "for", SNAP_TOTAL_US / 1000000, "s")
end

local function snapTick()
	local s = snap
	if not s then return end
	local t = nowUs()
	if t < s.nextCheck then return end
	s.nextCheck = t + SNAP_CHECK_US
	if t > s.untilUs or not isLine(s.line) then
		say("snap end line", s.line)
		snap = nil
		return
	end
	local label = string.format("t=+%.0fs", (t - s.t0) / 1000000)
	if t >= s.nextFull then
		s.nextFull = t + SNAP_FULL_US
		local m = fullSnapshot(s.line, label)
		for _i, row in ipairs(m.rows) do s.last[row.v] = vehicleKey(row.tv) end
		status = string.format("snap %s n%d H%s", label, m.n, fmt(m.H))
		return
	end
	-- between full snapshots: vehicles whose state/loadState/stopIndex changed, and every WaitForScheduledDeparture
	local m = nil
	for _i, v in ipairs(lineVehicles(s.line)) do
		local tv = tvOf(v)
		if tv then
			local key = vehicleKey(tv)
			local waiting = isWaitScheduled(tv.loadState)
			if key ~= s.last[v] or waiting then
				m = m or model(s.line, lineVehicles(s.line))
				local row
				for _j, r in ipairs(m.rows) do
					if r.v == v then row = r end
				end
				local why = (key ~= s.last[v]) and ("CHANGED from " .. tostring(s.last[v])) or "WAIT"
				try("vehicle", logVehicle, "  " .. label .. " " .. why, row or { v = v, tv = tv }, m)
				s.last[v] = key
			end
		end
	end
end

-- Re-send test (question 1) ------------------------------------------------------------------------------------------
local function trackLog(label)
	local k = track
	if not k then return end
	if not api.engine.entityExists(k.v) then
		say("track", label, "vehicle", k.v, "gone")
		return
	end
	local tv = tvOf(k.v)
	local x, y = posOf(k.v)
	local moved = (x and k.lastX) and math.sqrt((x - k.lastX) ^ 2 + (y - k.lastY) ^ 2) or nil
	local dHome = (x and k.x0) and math.sqrt((x - k.x0) ^ 2 + (y - k.y0) ^ 2) or nil
	local dTarget = (x and k.tx) and math.sqrt((x - k.tx) ^ 2 + (y - k.ty) ^ 2) or nil
	say(string.format("track %s v=%s line=%s state=%s load=%s stopIndex=%s (sent to %s) cargo[%s] pos=%s,%s speed=%s "
		.. "moved=%s fromStart=%s toTargetStation=%s tUntilDep=%s",
		label, tostring(k.v), tostring(tv.line), stateName(tv.state), loadName(tv.loadState), tostring(tv.stopIndex),
		tostring(k.stop0), cargoText(k.v, tv), fmt(x), fmt(y), fmt(speedOf(k.v)), fmt(moved), fmt(dHome), fmt(dTarget),
		fmt(tv.timeUntilDeparture)))
	k.lastX, k.lastY = x, y
end

local function trackTick()
	local k = track
	if not k then return end
	local t = nowUs()
	if t < k.nextLog then return end
	k.nextLog = t + TRACK_LOG_US
	if t > k.untilUs then
		trackLog("final")
		say("track end v", k.v)
		track = nil
		if isLine(k.line) then fullSnapshot(k.line, "after-send:" .. k.label) end
		return
	end
	trackLog(string.format("t=+%.0fs", (t - k.t0) / 1000000))
end

--- World position of a line stop's station (for "toTargetStation" distances); nil if unreadable.
local function stopPos(line, stop0)
	local ok, x, y = pcall(function()
		local comp = api.engine.getComponent(line, api.type.ComponentType.LINE)
		local s = comp.stops[stop0 + 1]
		local sg = api.engine.getComponent(s.stationGroup, api.type.ComponentType.STATION_GROUP)
		-- Stop.station is assumed 0-based within the group (fallback: as is)
		local station = sg.stations[s.station + 1] or sg.stations[s.station]
		-- STATION has no position; use its construction's transform
		local con = api.engine.system.streetConnectorSystem.getConstructionEntityForStation(station)
		local c = api.engine.getComponent(con, api.type.ComponentType.CONSTRUCTION)
		local p = c.transf:getTransl()
		return p.x, p.y
	end)
	if ok then return x, y end
	return nil, nil
end

local function resend(line, mode)
	local vehicles = lineVehicles(line)
	local m, p = fullSnapshot(line, "before-send:" .. mode)
	local v = p and p.vehicle or (m.active[1] and m.active[1].v) or nil
	if not v then
		setStatus("send: no EN_ROUTE/AT_TERMINAL vehicle with a departure on this line (" .. #vehicles .. " vehicles)")
		return
	end
	local tv = tvOf(v)
	local S = m.S
	local stop0
	if mode == "plan" then
		stop0 = p and p.stop0 or ((tv.stopIndex + math.floor(S / 2)) % S)
	elseif mode == "back" then
		stop0 = (tv.stopIndex - 1) % S -- the stop it just left (or the one before): does it turn around?
	else
		stop0 = tv.stopIndex -- the stop it is already heading to / at: no-op or reset?
	end
	local x0, y0 = posOf(v)
	local tx, ty = stopPos(line, stop0)
	say(string.format("SEND %s: vehicle=%s state=%s load=%s stopIndex=%s -> makeVehicleSetLineCmd(%s, %s, %s) cargo[%s] pos=%s,%s "
		.. "targetStationPos=%s,%s", mode, tostring(v), stateName(tv.state), loadName(tv.loadState), tostring(tv.stopIndex),
		tostring(v), tostring(line), tostring(stop0), cargoText(v, tv), fmt(x0), fmt(y0), fmt(tx), fmt(ty)))
	local t = nowUs()
	track = { v = v, line = line, label = mode, stop0 = stop0, t0 = t, nextLog = t + TRACK_LOG_US, untilUs = t + TRACK_TOTAL_US,
		x0 = x0, y0 = y0, lastX = x0, lastY = y0, tx = tx, ty = ty }
	api.cmd.sendCommand(api.cmd.makeVehicleSetLineCmd(v, line, stop0), function(_cmd, success)
		local ok, err = pcall(function()
			say(string.format("SEND %s callback success=%s after %.2fs", mode, tostring(success), (nowUs() - t) / 1000000))
			trackLog("callback")
		end)
		if not ok then say("ERROR send callback", err) end
	end)
	setStatus("send:" .. mode .. " v" .. tostring(v) .. " -> stop " .. tostring(stop0))
end

-- Button row ---------------------------------------------------------------------------------------------------------
local function act(label, fn)
	local line = lineOf(managerParams)
	if not isLine(line) then
		setStatus(label .. ": no line selected")
		return
	end
	say("CLICK", label, "line", line, "name", nameOf(line), "n", #lineVehicles(line), "gameTime", gameTime())
	try(label, fn, line)
end

local function textButton(text, tooltip, onClick)
	-- same shape as the RMPROBE buttons, proven in this toolbar
	return builtin.Button{
		meta = { class = "vehicle-button, secondary", tooltip = tooltip },
		content = builtin.TextView{ text = text },
		onClick = function()
			local ok, err = pcall(onClick)
			if not ok then say("ERROR click", text, err) end
		end,
	}
end

local function stepView()
	local ok, err = pcall(snapTick)
	if not ok then
		say("ERROR snap", err)
		snap = nil
	end
	ok, err = pcall(trackTick)
	if not ok then
		say("ERROR track", err)
		track = nil
	end
	return status
end

local LmpProbeRow = react.RegisterRecipe("SquareLmpProbeRow", function(_p)
	local open = react.useState(false)
	local view = engine_react_util.useStepState(function()
		return stepView()
	end, nil, function(a, b) return a == b end)
	local text = view:old() or status
	local children = {
		textButton(open:old() and "LMPP<" or "LMPP", "LMP Balance probe: " .. text .. " (click to show/hide actions)", function()
			open:set(not open:old())
		end),
	}
	if open:old() then
		children[#children + 1] = textButton("Snap", "READ ONLY: log the line's spacing data now and for 60 s", function()
			act("snap", startSnap)
		end)
		children[#children + 1] = textButton("Send:plan", "CHANGES THE GAME: re-send the most bunched vehicle to the stop in the "
			.. "middle of the largest gap (makeVehicleSetLineCmd, same line); track it for 60 s", function()
			act("send-plan", function(line) resend(line, "plan") end)
		end)
		children[#children + 1] = textButton("Send:back", "CHANGES THE GAME: re-send the most bunched vehicle to the stop BEFORE "
			.. "its current stop index (does it turn around?); track it for 60 s", function()
			act("send-back", function(line) resend(line, "back") end)
		end)
		children[#children + 1] = textButton("Send:same", "CHANGES THE GAME: re-send the most bunched vehicle to its CURRENT "
			.. "stop index (no-op, or reset?); track it for 60 s", function()
			act("send-same", function(line) resend(line, "same") end)
		end)
		children[#children + 1] = builtin.TextView{ text = text }
	end
	-- a recipe returns a layout (memory: react-recipe-must-return-layout)
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = children }
end)

-- Wrappers -----------------------------------------------------------------------------------------------------------
local origDescriptor
local function lineActionDescriptor(commonParams, ...)
	local ok, err = pcall(function()
		if type(commonParams) == "table" and commonParams.lineManagerStateRef then
			if managerParams ~= commonParams then say("captured commonParams") end
			managerParams = commonParams
		end
	end)
	if not ok then say("ERROR descriptor", err) end
	return origDescriptor(commonParams, ...)
end

local origToggle
local loggedMount = false
local function iconToggleButton(className, path, ...)
	local node = origToggle(className, path, ...)
	if path ~= AUTO_RENAME_ICON then return node end
	local ok, wrapped = pcall(function()
		if react.getCurrentRecipeName() ~= RECIPE_ACTION_BUTTONS or not managerParams then return nil end
		if not loggedMount then
			loggedMount = true
			say("mounted row left of A+ in", RECIPE_ACTION_BUTTONS)
		end
		return builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = { LmpProbeRow{}, node }, -- the recipe is the item itself, never a Component layout
		}
	end)
	if not ok then
		say("ERROR mount", wrapped)
		return node
	end
	return wrapped or node
end

local function doReplace(_replacementApi)
	if origToggle or origDescriptor then return end
	-- read the current functions now, so wrappers installed earlier (LMP 250, RM probe 250) stay in the chain
	local toggle, descriptor = button_react_util.makeIconToggleButton, line_util.makeLineActionDescriptor
	if type(toggle) ~= "function" or type(descriptor) ~= "function" then
		say("install FAILED", type(toggle), type(descriptor))
		return
	end
	origToggle, origDescriptor = toggle, descriptor
	button_react_util.makeIconToggleButton = iconToggleButton
	line_util.makeLineActionDescriptor = lineActionDescriptor
	say("installed (order 260)")
end

say("loaded")

-- .script.lua resources export through data() (memory: script-lua-exports-via-data)
function data()
	return {
		doReplace = doReplace,
		LmpProbeRow = LmpProbeRow,
	}
end
