-- Problem Radar notification decisions (PLAN Phase 5: per-alert off / passive / notify, toasts only
-- on newly appearing alerts). PURE: no api.*, no base modules; unit-tested offline
-- (tests/square_problem_radar/test_notify.lua). The engine script (radar.script.tl) applies the result:
-- it stores the new notified / cleared maps and sends one "Notifications"/"add" event per toast.
--
-- Rules (step):
--   * Only alerts whose kind is at level "notify" can toast. "off" kinds never reach the state
--     (filterOff); "passive" kinds are listed only.
--   * notified[id] = gameTime it was notified (or silently marked). While the id stays in the
--     alert list it never toasts again.
--   * When a notified id disappears it moves to cleared[id] = gameTime it cleared. If it comes back
--     within COOLDOWN_MS it is marked notified again WITHOUT a toast (flapping); after that it is a
--     new problem and toasts. Expired cooldowns are dropped.
--   * notifyPaused: new alerts are marked notified silently (no backlog when notifications resume).
--   * At most MAX_TOASTS toasts per call (the engine calls once per full scan cycle); the rest are
--     marked notified too and summed up in one "+N more problems" toast (`more`).
--   * MIN_AGE_MS: a kind may wait this long after its alert appeared before it toasts (still listed
--     at once). line_no_vehicles: a line that is still being set up has no vehicles yet.
--   * Smoothing (settings.smoothSec, radar_checks.merge): `alerts` holds only listed alerts, never the
--     pending ones, and firstSeen is the time an alert became listed. So a toast never precedes its
--     row, and MIN_AGE_MS counts on top of the smoothing window (line_no_vehicles: about 30 s + 2 min
--     after the line first lacks vehicles). A listed alert lingering after it was last detected is
--     still listed here, so it neither clears nor re-toasts while it lingers.
--   * silentAll / silentKinds (Phase 6): new alerts (of those kinds) are marked notified without a
--     toast. The engine sets them for the first full scan cycle after the mod is added to a save and
--     after a kind is switched to "notify", so the alerts already there never arrive as a burst.
--   * Budget (applyBudget, Phase 6): on top of the per-cycle cap, at most BUDGET_TOASTS toasts and
--     BUDGET_SUMMARIES summaries per BUDGET_WINDOW_MS of game time. The base notification history
--     keeps only 100 entries (notification_util.tl:7, 161-175), so radar toasts must never push the
--     base game's own notifications out. Toasts over the budget are carried into the next summary.
--   * Maps are capped (save size): notified at MAX_NOTIFIED (it only holds ids that are currently
--     listed, so it is bounded by radar_checks.MAX_STORED_ALERTS anyway), cleared at MAX_CLEARED
--     (the most recent clears are kept; a dropped one simply toasts again when it comes back).
-- `changed` is true only when a map changed, so the engine calls state:set only on a transition.

local radar_settings = ug_require "square_problem_radar::/radar/radar_settings.tl" as ProblemRadarSettingsModule

local notify : ProblemRadarNotifyModule = {}

notify.MAX_TOASTS = 3
notify.COOLDOWN_MS = 10 * 60 * 1000
notify.MAX_NOTIFIED = 300
notify.MAX_CLEARED = 100
notify.BUDGET_WINDOW_MS = 2 * 60 * 1000
notify.BUDGET_TOASTS = 3
notify.BUDGET_SUMMARIES = 1
notify.MIN_AGE_MS = {
	line_no_vehicles = 2 * 60 * 1000,
}

local function toInt(v : any) : integer
	if type(v) ~= "number" then return nil end
	return math.floor(v as number)
end

function notify.filterOff(alerts : {ProblemRadarAlert}, s : ProblemRadarSettings) : {ProblemRadarAlert}
	local out : {ProblemRadarAlert} = {}
	for __, a in ipairs(alerts or {}) do
		if type(a) == "table" and radar_settings.level(s, a.kind) ~= "off" then out[#out + 1] = a end
	end
	return out
end

function notify.isOn(s : ProblemRadarSettings, kind : string) : boolean
	return radar_settings.level(s, kind) ~= "off"
end

--- Sanitised copy of a saved id -> time map (string keys, integer values; garbage dropped).
local function cleanMap(m : any) : {string : integer}
	local out : {string : integer} = {}
	if type(m) ~= "table" then return out end
	for k, v in pairs(m as {any : any}) do
		local t = toInt(v)
		if type(k) == "string" and t ~= nil then out[k as string] = t end
	end
	return out
end

--- Keep the `cap` entries with the largest time (ties by id).
local function capNewest(m : {string : integer}, cap : integer) : {string : integer}
	local ids : {string} = {}
	for k in pairs(m) do ids[#ids + 1] = k end
	if #ids <= cap then return m end
	table.sort(ids, function(a : string, b : string) : boolean
		if m[a] ~= m[b] then return m[a] > m[b] end
		return a < b
	end)
	local out : {string : integer} = {}
	for i = 1, cap do out[ids[i]] = m[ids[i]] end
	return out
end

local function sameMap(a : {string : integer}, b : any) : boolean
	if type(b) ~= "table" then return false end
	local t = b as {any : any}
	local n = 0
	for k, v in pairs(a) do
		n = n + 1
		if toInt(t[k]) ~= v then return false end
	end
	for __ in pairs(t) do n = n - 1 end
	return n == 0
end

local function toastBefore(a : ProblemRadarAlert, b : ProblemRadarAlert) : boolean
	local ta, tb = toInt(a.tier) or 9, toInt(b.tier) or 9
	if ta ~= tb then return ta < tb end
	local fa, fb = toInt(a.firstSeen) or 0, toInt(b.firstSeen) or 0
	if fa ~= fb then return fa < fb end
	return tostring(a.id) < tostring(b.id)
end
notify.toastBefore = toastBefore

function notify.step(input : ProblemRadarNotifyInput) : ProblemRadarNotifyResult
	local now = input.now or 0
	local s = input.settings
	local paused = s ~= nil and s.notifyPaused == true
	local silentAll = input.silentAll == true
	local silentKinds = input.silentKinds or {}
	local cooldown = notify.COOLDOWN_MS
	local maxToasts = input.maxToasts or notify.MAX_TOASTS

	local present : {string : ProblemRadarAlert} = {}
	for __, a in ipairs(input.alerts or {}) do
		if type(a) == "table" and type(a.id) == "string" then present[a.id] = a end
	end

	local notified : {string : integer} = {}
	local cleared : {string : integer} = {}
	for id, t in pairs(cleanMap(input.cleared)) do
		-- keep only running cooldowns (a time in the future counts as "now")
		if now - math.min(t, now) < cooldown then cleared[id] = math.min(t, now) end
	end
	for id, t in pairs(cleanMap(input.notified)) do
		if present[id] ~= nil then
			notified[id] = t
		else
			cleared[id] = now -- it just cleared: the cooldown starts
		end
	end

	local candidates : {ProblemRadarAlert} = {}
	for id, a in pairs(present) do
		if notified[id] == nil and radar_settings.level(s, a.kind) == "notify" then
			local minAge = notify.MIN_AGE_MS[a.kind]
			local age = now - (toInt(a.firstSeen) or now)
			if cleared[id] ~= nil then
				-- back within the cooldown: the same problem flapping, no toast
				notified[id] = now
				cleared[id] = nil
			elseif paused or silentAll or silentKinds[a.kind] then
				-- paused, or primed (alerts already there when the mod was added / the kind switched on)
				notified[id] = now
			elseif minAge == nil or age >= minAge then
				candidates[#candidates + 1] = a
			end
		end
	end
	table.sort(candidates, toastBefore)

	local toasts : {ProblemRadarAlert} = {}
	for i, a in ipairs(candidates) do
		notified[a.id] = now
		if i <= maxToasts then toasts[#toasts + 1] = a end
	end
	local more = #candidates - #toasts

	notified = capNewest(notified, notify.MAX_NOTIFIED)
	cleared = capNewest(cleared, notify.MAX_CLEARED)
	local changed = not (sameMap(notified, input.notified) and sameMap(cleared, input.cleared))
	return { toasts = toasts, more = more, notified = notified, cleared = cleared, changed = changed }
end

function notify.applyBudget(budget : ProblemRadarNotifyBudget, now : integer, toasts : {ProblemRadarAlert}, more : integer,
		paused? : boolean) : {ProblemRadarAlert}, integer, ProblemRadarNotifyBudget
	local b : ProblemRadarNotifyBudget = { windowStart = now, toasts = 0, summaries = 0, pending = 0 }
	if budget ~= nil then
		local start = toInt(budget.windowStart)
		b.pending = math.max(0, toInt(budget.pending) or 0)
		if start ~= nil and start <= now and now - start < notify.BUDGET_WINDOW_MS then
			b.windowStart = start
			b.toasts = math.max(0, toInt(budget.toasts) or 0)
			b.summaries = math.max(0, toInt(budget.summaries) or 0)
		end
	end
	local send : {ProblemRadarAlert} = {}
	if paused then
		b.pending = 0
		return send, 0, b
	end
	for __, a in ipairs(toasts or {}) do
		if b.toasts < notify.BUDGET_TOASTS then
			send[#send + 1] = a
			b.toasts = b.toasts + 1
		else
			b.pending = b.pending + 1
		end
	end
	b.pending = b.pending + math.max(0, toInt(more) or 0)
	local summary = 0
	if b.pending > 0 and b.summaries < notify.BUDGET_SUMMARIES then
		summary = b.pending
		b.pending = 0
		b.summaries = b.summaries + 1
	end
	return send, summary, b
end

function notify.newlyNotify(old : ProblemRadarSettings, new : ProblemRadarSettings) : {string : boolean}
	local out : {string : boolean} = nil
	for __, kind in ipairs(radar_settings.NOTIFY_KINDS) do
		if radar_settings.level(new, kind) == "notify" and radar_settings.level(old, kind) ~= "notify" then
			out = out or {}
			out[kind] = true
		end
	end
	return out
end

function notify.params(a : ProblemRadarAlert) : ProblemRadarNotificationParams
	local p : ProblemRadarNotificationParams = {
		kind = a.kind,
		tier = toInt(a.tier),
		etype = a.etype,
		label = a.label,
		context = a.context,
		code = a.code,
		arg = a.arg,
		metric = a.metric,
		entity = toInt(a.entity),
	}
	if type(a.pos) == "table" and #a.pos == 3 then p.pos = { a.pos[1], a.pos[2], a.pos[3] } end
	return p
end

return notify
