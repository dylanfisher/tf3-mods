-- DEV ONLY (never upload). Pure helpers for the OT Dev window (otd_hud.script.lua): the tab list, the status /
-- queue lines at the top of the window and the parameters of the commands that need more than a click. No api,
-- no GUI: tested in tests/square_organic_towns_dev/test_hudview.lua. Plain Lua, pre-5.3.
--
-- Window layout (2026-10-12, modelled on the Stress Test window, square_stress_test stress_hud.script.tl): status
-- lines and the queue with Stop at the top, always visible; one TabWidget below (V.TABS, the selected tab is
-- remembered for the session); each tab is a list of sections whose heading row carries the section's action
-- (green = "go"), with the options (pickers, check boxes) below; the log in a fixed area under the tabs.

local V = {}

V.TABS = {
	{ key = "sim", label = "Simulate" },
	{ key = "showcase", label = "Showcase" },
	{ key = "town", label = "Town" },
	{ key = "main", label = "Main mod" },
	{ key = "camera", label = "Camera & tour" },
}
V.DEFAULT_TAB = "sim"

--- A known tab key, else the default tab.
function V.tabKey(key)
	for _, t in ipairs(V.TABS) do
		if t.key == key then return key end
	end
	return V.DEFAULT_TAB
end

--- First status line: the link to the dev game script. err = the last send error, ageS = the status age in s.
function V.linkText(st, err, ageS)
	if err then return "Link: sending failed: " .. tostring(err) end
	if st == nil then
		return "Link: no reply from the dev game script yet. Is Organic Towns enabled? Check stdout.txt for [SQOT_DEV] LOAD."
	end
	if st.loadError then return "Link: the dev game script could not load the main mod: " .. tostring(st.loadError) end
	return string.format("Link: ok (status %.0f s old)", ageS or 0)
end

--- Second status line: the main mod's driver (nil while there is no status).
function V.mainText(st)
	if st == nil or st.loadError then return nil end
	if not st.main then
		return "Main driver: NOT visible (other Lua state: Pause and main undo unavailable)"
	end
	return string.format("Main driver: %s%s%s%s", st.paused and "PAUSED, " or "", tostring(st.mainPhase),
		(st.mainOff and st.mainOff ~= "") and (" (" .. st.mainOff .. ")") or "",
		(st.mainCounts and st.mainCounts ~= "") and (", " .. st.mainCounts) or "")
end

--- The queue line: the running dev task and how many wait.
function V.taskText(st)
	local busy = st and st.busy or ""
	local q = st and tonumber(st.queue) or 0
	return string.format("Task: %s%s", busy ~= "" and busy or "nothing", q > 0 and string.format(" (+%d queued)", q) or "")
end

--- The tour line, or nil when no tour runs or waits. tour = the HUD's tour state ({ i = town index }).
function V.tourText(tour, waiting, total, source, label)
	if tour == nil then
		return waiting and "Tour: waits for the showcase settle to end" or nil
	end
	return string.format("Tour (%s): town %d/%d%s", source == "all" and "all towns" or "showcase", tour.i or 0, total or 0,
		label and (": " .. tostring(label)) or "")
end

--- Progress lines under the queue: the simulation, the showcase, the tour (each only when there is one).
function V.progressLines(st, tourLine)
	local out = {}
	local sim = st and st.sim
	if sim and sim.head then out[#out + 1] = "Simulation: " .. sim.head end
	local sh = st and st.show
	if sh and sh.head then out[#out + 1] = sh.head end
	if tourLine then out[#out + 1] = tourLine end
	return out
end

--- simStart parameters from the window's pickers (o: the HUD store), the camera position and the mode ("quick" |
--- "buildout" | nil: the pickers as set).
function V.simStartParams(o, x, y, mode)
	return { pace = o.simPace, seed = o.simSeed, limit = o.simLimit, scope = o.simNear and "near" or "all", x = x, y = y,
		bias = o.simBias, even = o.simEven ~= false, tourWhenDone = o.simTour, fastFill = o.simFill ~= false, fillEvery = o.simFillEvery,
		waitMain = o.simWait ~= false, buildRound = o.simRound ~= false, speedUp = o.simSpeedUp ~= false,
		moveDate = o.simMoveDate ~= false, mode = mode }
end

--- Labels of the Real s per year picker: 0 is "as fast as possible".
function V.paceLabels(paces)
	local out = {}
	for i, v in ipairs(paces) do out[i] = v <= 0 and "0 (as fast as possible)" or string.format("%d", v) end
	return out
end

--- Tooltips of the Fill every picker (one per option of SG.FILL_EVERY; quick = SG.QUICK.fillEvery).
function V.fillEveryTips(list, quick)
	local out = {}
	for i, n in ipairs(list) do
		local t
		if n == 1 then
			t = "Every year: the main mod and the fill every year (slowest, closest to normal play)"
		elseif n < (quick or 4) then
			t = string.format("Every %d years: finer than Quick, slower", n)
		elseif n == quick then
			t = string.format("Every %d years: the Quick preset", n)
		else
			local k = math.floor(n / quick + 0.5)
			t = string.format("Every %d years: about %s as fast as every %d, but coarser: the main mod reacts %s as "
				.. "often (its build round and the fill come every %d years)", n, k == 2 and "twice" or (k .. " times"),
				quick, k == 2 and "half" or ("1/" .. k), n)
		end
		out[i] = t
	end
	return out
end

--- The "Quick" preset (SG.QUICK) into the HUD store: pace, year limit, Fast fill every N years (picker indices),
--- Fast fill, the build round, wait for the main mod (its fallback) and the game speed on. SG: otd_simgrow.
function V.applyQuick(o, SG)
	o.simPace = SG.indexOf(SG.PACES, SG.QUICK.pace) or o.simPace
	o.simLimit = SG.indexOf(SG.LIMITS, SG.QUICK.limit) or o.simLimit
	o.simFillEvery = SG.indexOf(SG.FILL_EVERY, SG.QUICK.fillEvery) or o.simFillEvery
	o.simFill, o.simWait, o.simSpeedUp, o.simRound = true, true, true, true
	return o
end

--- Ring picker: 1 = one-way (the runner's default "oneway"), 2 = the two-way town street.
V.RING_LABELS = { "One-way (default)", "Two-way town street" }
function V.ringIndex(mode)
	return mode == "oneway" and 1 or 2
end

--- true when picking ring choice i has to send the runner's ring toggle (showOpt ring).
function V.ringToggle(i, mode)
	return (i == 1 or i == 2) and V.ringIndex(mode) ~= i
end

--- Debug log picker: the runner's debug modes in picker order.
V.DEBUG_MODES = { "param", "on", "off" }
V.DEBUG_LABELS = { "Mod setting", "On", "Off" }
function V.debugIndex(mode)
	for i, m in ipairs(V.DEBUG_MODES) do
		if m == mode then return i end
	end
	return 1
end

return V
