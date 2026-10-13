-- End-to-end: the traffic log's real lines for tools/flow_report.py. Not run by `make test` (no test_ prefix):
-- tests/tools/test_flow_report.py (make test-tools) runs it through tests/run_tests.py's ModRunner, writes the
-- printed lines to a stdout.txt and parses it with flow_report.parse / render.
--
-- Scenario (flow_fake.lua): a Showcase run's zone lines (stress_logic.showcaseZoneLine, as stress_junctions writes
-- them) for g1a (sl) / g1b (game) Magic Roundabout, g2a (sl) Crossroads with match=no, g3a (sl) Trumpet; the
-- traffic log at 10 game s for 400 game s. Cars in g1b (the game twin) drive 4 m/s, the rest 10 m/s, every 3rd
-- stands. SQST Bus 1 serves g1a (session map).

test("flow e2e log", function()
	local F = assert(loadfile("tests/square_stress_test/flow_fake.lua", "t", _ENV))()
	F.speedOf = function(i)
		if i % 3 == 0 then return 0 end
		return i % 4 == 1 and 4 or 10
	end
	local rt, fl, slz, bl = F.load()
	local logic = ug_require "square_stress_test::/stress/stress_logic.tl"
	local zones = F.showcase()
	-- g1a's arms as the read measures them (v3: measured out along them, q_arm); the others: circles
	zones[1].arms = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
	clear_logs()
	log.message("[SQST] showcase zones sent n=5 run=s1-2-3 by_ab=game:2,sl:3,sl_phases:0 smart_lanes=yes")
	for _, z in ipairs(zones) do
		if z.built then log.message(logic.showcaseZoneLine(z, true)) end
	end
	slz.current = { run = "s1-2-3", seq = 1, zones = zones }
	bl.lineTwins[900] = { twin = "g1a", pair = "g1", ab = "sl" }
	fl.setInterval(1)
	fl.setOn(true)
	-- the bus departs stop 1 every 120 game s
	F.run(rt, 800, 500, function(i)
		local t = F.gt
		if i % 240 == 0 then F.deps[800] = { t, t - 50000 } F.last[800] = t end
	end)
	fl.setOn(false)
	rt.tick()
	for _, e in ipairs(log_entries()) do
		if e.msg:find("^%[SQ") then print(e.msg) end
	end
end)
