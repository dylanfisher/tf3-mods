-- stress_runtime.tl against a fake api: throttled sending from tick, journal bookings, the balance
-- top-up, and the [SQST] log lines.

local T = 0
local sent, balance

local function fakeApi()
	sent = {}
	balance = 100000000
	T = 0
	return {
		type = {
			Clock = { new = function() return { getTime = function() return T end } end },
			JournalEntry = {
				new = function() return { category = {} } end,
				Type = { OTHER = "OTHER" },
			},
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
		},
		cmd = {
			sendCommand = function(cmd, cb) sent[#sent + 1] = { cmd = cmd, cb = cb } end,
			makeScriptingSendEventCmd = function(src, id, name, param) return { kind = "event", src = src, id = id, name = name, param = param } end,
			makeJournalBookAssetCmd = function(player, entry, pos) return { kind = "book", player = player, amount = entry.amount, cat = entry.category.type } end,
		},
		engine = {
			util = {
				getPlayer = function() return 7 end,
				finance = { getPlayersBalance = function(_p) return balance end },
			},
		},
	}
end

local rt
before_each(function()
	reset_modules()
	set_global("api", fakeApi())
	clear_logs()
	rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	rt.notificationsSent = true -- only the notification tests below send it
end)

test("tick sends at most PER_FRAME commands per frame and logs one [SQST] line per job", function()
	local n = 0
	rt.enqueue("burst", 10, function(_i) n = n + 1 end)
	rt.tick()
	eq(n, rt.PER_FRAME)
	rt.tick()
	rt.tick()
	eq(n, 10)
	eq(#rt.queue.jobs, 0)
	local last = rt.recent[#rt.recent]
	ok(last:find("^%[SQST%] action=burst count=10") ~= nil, last)
end)

test("quiet jobs log nothing unless they fail; later() waits for its delay", function()
	local ran = false
	rt.later("probe:check", 2000, function() ran = true end)
	rt.tick()
	eq(ran, false)
	T = 2000 * 1000
	rt.tick()
	eq(ran, true)
	eq(#rt.recent, 0)
	rt.enqueue("q", 1, function() error("bad") end, { quiet = true })
	rt.tick()
	ok(rt.recent[#rt.recent]:find("errors=1") ~= nil)
end)

test("book sends one OTHER journal entry for the player", function()
	rt.book(10000000)
	eq(#sent, 1)
	eq(sent[1].cmd, { kind = "book", player = 7, amount = 10000000, cat = "OTHER" })
end)

test("send: failed command and callback errors are logged, not thrown", function()
	rt.send("x", { kind = "x" }, function() error("cb boom") end)
	sent[1].cb({}, false)
	ok(rt.recent[1]:find("cmd x failed") ~= nil)
	ok(rt.recent[2]:find("callback x error") ~= nil)
end)

test("probe lines have the [SQST-PROBE] name ok|fail format", function()
	rt.probe("speed_8", true, "speedup=8")
	rt.probe("speed_16", false, "speedup=4")
	eq(rt.recent, { "[SQST-PROBE] speed_8 ok speedup=8", "[SQST-PROBE] speed_16 fail speedup=4" })
end)

test("keep balance: tops up below 50M, once per balance until it changes", function()
	balance = 20000000
	rt.tick()
	eq(#sent, 0) -- toggle off
	rt.keepBalance = true
	rt.tick() -- check enqueues, then the same tick books
	eq(#sent, 1)
	eq(sent[1].cmd.amount, 40000000)
	T = T + 3000000
	rt.tick()
	eq(#sent, 1) -- same balance (booking not applied yet): no second booking
	T = T + 25000000
	rt.tick()
	eq(#sent, 2) -- retry after 20 s at an unchanged balance (e.g. paused game)
	balance = 60000000
	T = T + 3000000
	rt.tick()
	eq(#sent, 2)
end)

test("keep balance: nothing with unknown balance (infinite money)", function()
	balance = nil
	rt.keepBalance = true
	rt.tick()
	eq(#sent, 0)
end)

test("log keeps the last 8 lines", function()
	for i = 1, 12 do rt.log("line " .. i) end
	eq(#rt.recent, 8)
	eq(rt.recent[1], "line 5")
	eq(rt.recent[8], "line 12")
end)

test("log: the window gets one line (no traceback, at most 160 chars), stdout.txt the full text", function()
	local msg = "[SQST-PROBE] town_develop_1 fail error: stress_probes.tl:40: Cannot loop over this component type\n"
		.. "stack traceback:\n\t[C]: in function 'getEntitiesWithComponent'"
	rt.log(msg)
	eq(rt.recent[1], "[SQST-PROBE] town_develop_1 fail error: stress_probes.tl:40: Cannot loop over this component type...")
	local logs = log_entries()
	eq(logs[#logs].msg, msg)
	rt.log(string.rep("x", 300))
	eq(#rt.recent[2], 160)
end)

test("hide notifications: on by default, sent once from the first tick with the four gui types, fully", function()
	rt.notificationsSent = false -- as after loading
	eq(rt.hideNotifications, true)
	rt.tick()
	rt.tick()
	eq(#sent, 1)
	local c = sent[1].cmd
	eq({ c.kind, c.src, c.id, c.name }, { "event", "", "Notifications", "updateIgnoredTypes" })
	eq(c.param.ignoredGuiTypes, { "Info", "Caution", "Problem", "Opportunity" })
	eq(c.param.ignoreFully, true)
	eq(c.param.ignoredTypes, nil) -- notification_util not reachable here: gui types only
	sent[1].cb(c, true, {})
	ok(rt.recent[#rt.recent]:find("[SQST] notifications hidden success=true", 1, true), rt.recent[#rt.recent])
end)

test("hide notifications: every labelled type name as a set when notification_util is reachable", function()
	stub_module("::/game_mechanics/notifications/notification_util.tl", {
		getNotificationType2Label = function() return { ["b.script"] = "B", ["a.script"] = "A" } end,
	})
	rt.notificationsSent = false
	rt.tick()
	eq(sent[1].cmd.param.ignoredTypes, { ["a.script"] = true, ["b.script"] = true })
	eq(sent[1].cmd.param.ignoreFully, true)
end)

test("unchecking sends the off form on the next tick; re-checking sends on again", function()
	rt.setHideNotifications(false)
	eq(#sent, 0) -- never from the click itself
	rt.tick()
	eq(#sent, 1)
	eq(sent[1].cmd.param, { ignoredTypes = {}, ignoreFully = false })
	sent[1].cb(sent[1].cmd, true, {})
	ok(rt.recent[#rt.recent]:find("[SQST] notifications shown", 1, true), rt.recent[#rt.recent])
	rt.setHideNotifications(false) -- unchanged: nothing
	rt.tick()
	eq(#sent, 1)
	rt.setHideNotifications(true)
	rt.tick()
	eq(#sent, 2)
	eq(sent[2].cmd.param.ignoreFully, true)
end)

test("notificationPayload", function()
	local logic = ug_require "square_stress_test::/stress/stress_logic.tl"
	eq(logic.notificationPayload(false, { "x" }), { ignoredTypes = {}, ignoreFully = false })
	eq(logic.notificationPayload(true, {}), { ignoredGuiTypes = { "Info", "Caution", "Problem", "Opportunity" }, ignoreFully = true })
	eq(logic.notificationPayload(true, { "x" }).ignoredTypes, { x = true })
end)

test("tick hooks run every frame before the queue; an error is logged, not raised", function()
	local seen = {}
	rt.addTickHook(function(now) seen[#seen + 1] = now end)
	rt.addTickHook(function() error("boom") end)
	T = 5
	rt.tick()
	rt.tick()
	eq(seen, { 5, 5 })
	ok(table.concat(rt.recent, "\n"):find("tick hook error", 1, true))
end)

test("clearQueue drops the jobs and counts the clears", function()
	rt.enqueue("a", 3, function() end)
	rt.enqueue("b", 1, function() end)
	eq(rt.clearQueue(), 2)
	eq(#rt.queue.jobs, 0)
	eq(rt.queueClears, 1)
end)
