-- DEV ONLY (never upload). Organic Towns dev tools: HUD button + window. Plain Lua, pre-5.3. Wiring as the probe
-- (mods/square_organic_towns_probe/content/organic_towns_probe/otp_hud.script.lua): otd_hud.res.lua mounts
-- OtdHudPlugin at "::MainModButtonAreaExtension"; the window is a RegisterWrapperRecipe around builtin.Window.
--
-- This GUI plugin state can't run the tools itself (no region global from runFn here, and a different Lua state
-- than the main mod's driver: docs/findings.md "Organic Towns probe"). It only shows the window:
--   * commands go to the dev game script with api.gui.fireGuiScriptEvent(GUI_ID, EV_CMD, param) (its
--     guiHandleEvent returns the status, used when it comes back as a table);
--   * the game script pushes its status every 0.5 s with api.gui.fireReactEvent(EV_STATUS, status), heard here
--     with react.onEvent (a mod plugin hears react events: plans/square_line_revert/PROBE.md D).
-- Recipe rules (memory): every custom recipe returns a BoxLayout at its root; a ScrollArea's content is a
-- Component around a layout; a recipe is never a Component's layout; react states are checked with hasExpired()
-- before :old(). Undo arms on the first click and runs on a second click within 8 s.
--
-- LAYOUT (2026-10-12, as the Stress Test window, square_stress_test stress_hud.script.tl): status lines, the queue
-- with Stop / Pause and the simulation / showcase / tour progress at the top (always visible); a TabWidget below
-- (otd_hudview.lua V.TABS: Simulate, Showcase, Town, Main mod, Camera & tour; the selected tab is remembered for
-- the session in store.tab), each tab one fixed-size ScrollArea of sections whose heading row carries the
-- section's action (green sqotd-go) with pickers and the game's check boxes below; the log under the tabs.

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl"
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl"

local S = ug_require "square_organic_towns_dev::/organic_towns_dev/otd_shared.lua"
local SG = ug_require "square_organic_towns_dev::/organic_towns_dev/otd_simgrow.lua"   -- pure: picker lists only
local V = ug_require "square_organic_towns_dev::/organic_towns_dev/otd_hudview.lua"    -- pure: tabs, status lines

local WINDOW_ID = "sqotdev.window"
local RENDER_US = 250000
local POLL_US = 2000000
local ARM_US = 8000000

local store = {
	status = nil, version = 0, lastUs = nil, pollUs = 0, err = nil,
	style = 1, motif = 1, n = 1, m = 1, factor = 2, debug = "param", armedUs = nil, charKind = 1,
	sn = 2, showCursor = 0, topDown = false, cam = nil, camCheck = nil,
	destroyArmedUs = nil,
	-- auto tour: dwell picker index, screenshots on/off, both views (oblique + top-down) per town
	tourDwell = 1, tourShots = true, tourBoth = false, tour = nil, tourLabel = nil,
	autoTourSeen = nil,   -- status.show.autoTour already handled (the first status only records it)
	-- showcase camera (v4): overview distance (S.CAM_DIST index), shape-row towns top-down one step wider
	camDist = S.CAM_DIST_DEFAULT, shapeTop = true,
	-- Simulate natural growth: pickers (indices into SG.PACES / SEEDS / LIMITS), scope, size bias, tour when stopped
	simPace = SG.PACE_DEFAULT, simSeed = 1, simLimit = SG.LIMIT_DEFAULT, simNear = false, simBias = true, simEven = true, simTour = true,
	simFill = true, simFillEvery = SG.FILL_EVERY_DEFAULT, simWait = true, simRound = true, simSpeedUp = true,   -- Fast fill, main wait, speed
	-- the game date follows the simulated years (off: the calendar stands still). (§68, 2026-10-15: on by default: the
	-- Quick runs had all logged moveDate=false, a 1900 calendar for 40 simulated years, so the era rules never moved)
	simMoveDate = true,
	simTourSeen = nil,   -- status.sim.autoTour already handled
	tab = V.DEFAULT_TAB,   -- the selected window tab (session)
}

-- Auto tour (showcase): flies to each showcase town in turn and holds TOUR_DWELL[i] seconds per view, showing the
-- town's label large in the window. With screenshots on, api.gui.camera.takeScreenshot(1) runs once the camera
-- has settled (v3: the first tour lost its first shot to a camera still easing at 70 % of the dwell): the
-- camera read-back must match the target (x/y within SETTLE_M, the view's distance within SETTLE_DIST) on SETTLE_POLLS
-- consecutive steps, or SHOT_FALLBACK_US / FALLBACK_FRAC of the dwell passed. The tour never moves on before the
-- current view's shot. The base free-camera menu calls the same function (free_cam_options.tl:21); the game names
-- and stores the file itself (userdata folder), so each shot is logged ([SQOT_DEV] SHOT n=k town=label view=...
-- settleMs=... fallback=...) in order. The showcase's settle phase can start the tour (status.show.autoTour).
local TOUR_DWELL = { 3, 5, 10, 20 }   -- min 3 s: the game writes one screenshot per ~2 s and drops requests while busy (1 s lost half the shots)
local SETTLE_M = 2
local SETTLE_DIST = 0.02
local SETTLE_POLLS = 2
local SHOT_FALLBACK_US = 1500000
local REAIM_M = 60              -- a fallback shot with the camera this far off the target is aimed again first
local REAIM_MAX = 2
local FALLBACK_FRAC = 0.9
-- v9 (Showcase v8, session 2026-10-12_2129_top-up-530609: the first two shots of every tour came out without a file):
-- the tour starts right when the settle ends, while the game script writes the 32 TOWN report lines (a ~3 s Main
-- Thread stall); shot 1 fired at the end of that stall (settleMs=2661) and shot 2 0.3 s after it (its camera jump is
-- instant), and the game wrote neither ("Screenshot: wrote" only from shot 3, which came 3 s later). The game writes
-- about one screenshot per 2 s and drops requests while busy. So: the first shot waits TOUR_WARMUP_US after the
-- tour start, every shot waits until the frames have been steady for STEADY_US (no step gap over STALL_US), and two
-- shots are at least SHOT_GAP_US apart.
local TOUR_WARMUP_US = 2500000
local STEADY_US = 1000000
local STALL_US = 250000
local SHOT_GAP_US = 2500000
local SHOT_WAIT_MAX_US = 12000000   -- a shot never waits longer than this for steady frames (logged steady=false)
-- v10 (real map run 2026-10-13_0018_top-up-598153): shot 1 was dropped again although it waited 2.5 s with steady
-- frames (settleMs=2499 steady=true); every later shot wrote a file. In v8 and v9 it was always the first screenshot
-- request of the game session too, so the first request seems to be lost whatever the timing (inferred, two runs).
-- So a tour with shots sends a primer request first when this session hasn't asked for a screenshot yet (SHOT
-- primer=true, a throwaway file; tools/ot_shots.py ignores it), and the first real shot waits SHOT_GAP_US after it.
-- Every SHOT line carries sessionShot= (the request's number in this session) to prove it.
local frames = { lastUs = nil, steadySince = nil }
local lastShotUs = nil
local sessionShots = 0

-- Showcase camera (Next / Previous town): api.gui.camera.setCameraData(Vec5f{x, y, distance, angle, pitch})
-- from the button's onClick (GUI thread). Angle and pitch are taken from the camera at the first jump and kept
-- for every town (consistent screenshots); Top-down replaces the pitch with S.TOPDOWN_PITCH. v4: the distance is
-- a picker (S.CAM_DIST, default 1800 m; v3's 1000 m made the shape-row towns read round) and shape-row towns
-- (status town key SHAPE_* / shape) are seen top-down one picker step wider ("Shape row: top-down", default ON;
-- otd_shared.view). The camera eases toward its own target distance (findings "Camera zoom limit"), so a
-- [SQOT_DEV] CAMERA line 1.5 s later logs what was asked and what the camera reads back.
local CAM_CHECK_US = 1500000

local clock = nil
local function nowUs()
	if clock == nil then clock = api.type.Clock.new() end
	return clock:getTime()
end

local startTour   -- defined with the tour below

local function accept(st)
	if type(st) ~= "table" then return end
	store.status = st
	store.lastUs = nowUs()
	store.version = store.version + 1
	-- the showcase's settle phase asks for the auto tour once per settle (a sequence number); the first status
	-- after a load only records the number
	local seq = st.show and tonumber(st.show.autoTour) or nil
	-- a tour asked for during the showcase's settle waits for it to end (v4: the user started the tour mid-settle,
	-- the towns were still filling); the settle's own auto tour (Tour after settle) also releases it
	if store.tourWait and store.tour == nil and S.tourMayStart(st.show) then
		store.tourWait = nil
		if startTour then
			store.tourSource = nil
			log.message(string.format("%s TOUR start after=settle phase=%s", S.PREFIX, tostring(st.show and st.show.phase)))
			startTour()
		end
	end
	-- Simulate natural growth asks for "Tour all towns" when it stops (Tour when stopped; the runner measured the towns)
	local simSeq = st.sim and tonumber(st.sim.autoTour) or nil
	if simSeq ~= nil then
		if store.simTourSeen == nil or simSeq < store.simTourSeen then
			store.simTourSeen = simSeq
		elseif simSeq > store.simTourSeen then
			store.simTourSeen = simSeq
			if store.tour == nil and startTour then
				store.tourSource = "all"
				log.message(string.format("%s TOUR auto source=simgrow seq=%d", S.PREFIX, simSeq))
				if not startTour() then store.tourSource = nil end
			end
		end
	end
	if seq ~= nil then
		if store.autoTourSeen == nil then
			store.autoTourSeen = seq
		elseif seq > store.autoTourSeen then
			store.autoTourSeen = seq
			if store.tour == nil and startTour then
				store.tourSource = nil
				log.message(string.format("%s TOUR auto seq=%d", S.PREFIX, seq))
				startTour()
			end
		end
	end
end

local function send(action, extra)
	local p = { action = action, style = store.style, motif = store.motif, n = store.n, m = store.m, factor = store.factor }
	for k, v in pairs(extra or {}) do p[k] = v end
	local ok, res = pcall(api.gui.fireGuiScriptEvent, S.GUI_ID, S.EV_CMD, p)
	if not ok then
		store.err = tostring(res)
		log.warning(S.PREFIX .. " HUD send " .. tostring(action) .. " failed: " .. store.err)
	else
		store.err = nil
		accept(res)
	end
	store.version = store.version + 1
end

local function camText(d)
	return string.format("%.0f,%.0f,%.0f,%.3f,%.3f", d.x, d.y, d.z, d.w, d.q)
end

--- Flies the camera to a showcase town (the view's distance and pitch: otd_shared.view; the first jump's angle).
--- Returns ok (false when the camera API is missing: then the coordinates are only logged) and the view
--- { dist, top, pitch, why }.
local function flyTo(t, forceTopDown)
	local dist, top, why = S.view(t, { distIdx = store.camDist, shapeTop = store.shapeTop, topDown = store.topDown,
		forceTop = forceTopDown })
	local view = { dist = dist, top = top, why = why, pitch = nil }
	local ok, err = pcall(function()
		local cur = api.gui.camera.getCameraData()
		if store.cam == nil then store.cam = { angle = cur.w, pitch = cur.q } end
		local pitch = top and S.TOPDOWN_PITCH or store.cam.pitch
		view.pitch = pitch
		local v = api.type.Vec5f.new(t.x, t.y, dist, store.cam.angle, pitch)
		api.gui.camera.setCameraData(v)
		store.camCheck = { us = nowUs() + CAM_CHECK_US, label = t.label, key = t.key, view = view,
			asked = string.format("%.0f,%.0f,%.0f,%.3f,%.3f", t.x, t.y, dist, store.cam.angle, pitch), before = camText(cur) }
	end)
	if not ok then
		store.err = "camera: " .. tostring(err)
		log.message(string.format("%s CAMERA fallback town=%s x=%.0f y=%.0f dist=%.0f topdown=%s err=%s", S.PREFIX,
			tostring(t.label), t.x, t.y, dist, tostring(top), tostring(err)))
	end
	return ok, view
end

local function camera()
	local ok, d = pcall(function() return api.gui.camera.getCameraData() end)
	if ok and d ~= nil then return d.x, d.y end
	return nil
end

---------------------------------------------------------------------------
-- Widgets (idioms of the Stress Test window, square_stress_test stress_hud.script.tl: head() rows with the
-- section's action on the right, choice rows with a fixed-width label, check boxes for on/off options)

local function text(str, class)
	return builtin.TextView{ meta = { class = class or "font-scale-body" }, text = tostring(str) }
end

local function wrap(str)
	return text(str, "font-scale-annotation, sqotd-wrap")
end

local function box(children, horizontal, class)
	return builtin.BoxLayout{
		meta = { class = class and (class .. ", sqotd-box") or "sqotd-box" },
		orientation = horizontal and builtin.type.Orientation.Horizontal or builtin.type.Orientation.Vertical,
		children = children,
	}
end

local function flow(children)
	return builtin.FlowLayout{ children = children }
end

--- Tooltip text broken into lines of at most ~60 characters (the game never wraps a tooltip).
local function wrapTip(str)
	if str == nil then return nil end
	local lines, line = {}, ""
	for word in tostring(str):gmatch("%S+") do
		if line ~= "" and #line + 1 + #word > 60 then
			lines[#lines + 1] = line
			line = word
		else
			line = line == "" and word or (line .. " " .. word)
		end
	end
	if line ~= "" then lines[#lines + 1] = line end
	return table.concat(lines, "\n")
end

--- Button classes (otd_hud.css.lua): sqotd-button neutral, sqotd-go green (the action a section exists for:
--- Simulate natural growth, Showcase: build all, Grow now, Fast-forward all, the tours), sqotd-armed red (Stop
--- buttons of a running simulation / tour, armed confirms), sqotd-risky amber (destructive or unverified).
local function button(label, tooltip, fn, class)
	return builtin.Button{
		meta = { class = class or "sqotd-button", tooltip = wrapTip(tooltip) },
		content = text(label, "font-scale-annotation"),
		onClick = function()
			local ok, err = pcall(fn)
			if not ok then log.warning(S.PREFIX .. " HUD " .. label .. ": " .. tostring(err)) end
		end,
	}
end

local function primary(label, tooltip, fn)
	return button(label, tooltip, fn, "sqotd-go")
end

local function section(str)
	return text(str, "font-scale-body, sqotd-section")
end

--- A section heading: a blank line (the gap above every section), then the title with the section's buttons
--- at the right edge (fixed-width row + an expanding spacer), as the Stress Test's head().
local function head(title, buttons)
	local children = { section(title), text("", "sqotd-spacer") }
	for _, b in ipairs(buttons or {}) do children[#children + 1] = b end
	return box({ text(" "), box(children, true, "sqotd-head") })
end

--- An on/off option as the game's own check box; onChange(on) runs on a click.
local function check(label, on, onChange, tooltip)
	return builtin.CheckBox{
		meta = tooltip and { tooltip = wrapTip(tooltip) } or nil,
		value = on and 1 or 0,
		label = label,
		onValueChange = function(v)
			local ok, err = pcall(onChange, v == 1)
			if not ok then log.warning(S.PREFIX .. " HUD " .. label .. ": " .. tostring(err)) end
			store.version = store.version + 1
		end,
	}
end

--- A 1-based ToggleButtonGroup; tips (optional) one tooltip per button; flowLayout wraps a long list.
local function choice(labels, selected, onPick, tips, flowLayout)
	local buttons = {}
	for i, l in ipairs(labels) do
		buttons[i] = { content = text(l, "font-scale-annotation"),
			meta = (tips and tips[i]) and { tooltip = wrapTip(tips[i]) } or nil }
	end
	return builtin.ToggleButtonGroup{
		buttons = buttons,
		selected = selected,
		layout = flowLayout and "Flow" or nil,
		onValueChange = function(i)
			if i ~= nil and i >= 1 and i <= #labels then
				onPick(i)
				store.version = store.version + 1
			end
		end,
	}
end

--- A picker row: fixed-width label, then the choice.
local function row(label, node)
	return box({ text(label, "font-scale-annotation, sqotd-label"), node }, true)
end

local function labels(list, fmt)
	local out = {}
	for i, v in ipairs(list) do out[i] = string.format(fmt, v) end
	return out
end

local function scroll(class, item)
	return builtin.ScrollArea{
		meta = { class = class },
		horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
		verticalPolicy = builtin.type.ScrollBarPolicy.AsNeeded,
		content = builtin.Component{ layout = box({ item }) },
	}
end

local function bump()
	store.version = store.version + 1
end

local function needCamera(fn)
	return function()
		local x, y = camera()
		if x == nil then store.err = "no camera position" return end
		fn(x, y)
	end
end

local tourShotN = 0

local function tourTowns()
	-- "Tour all towns" (Real map test): every town of the map, biggest first (runner allTowns)
	if store.tourSource == "all" then return (store.status and store.status.allTowns) or {} end
	local sh = store.status and store.status.show
	return sh and sh.towns or {}
end

--- Starts the auto tour (false when there are no showcase towns).
startTour = function()
	local towns = tourTowns()
	if #towns == 0 then
		store.err = store.tourSource == "all" and "no towns measured" or "no showcase towns yet"
		return false
	end
	local now = nowUs()
	store.tour = { i = 0, view = 0, nextUs = 0, pending = false, startUs = now }
	store.tourWait = nil
	local primer = store.tourShots == true and sessionShots == 0
	log.message(string.format("%s TOUR start towns=%d dwell=%d shots=%s both=%s dist=%d shapeTopDown=%s topDown=%s primer=%s",
		S.PREFIX, #towns, TOUR_DWELL[store.tourDwell], tostring(store.tourShots), tostring(store.tourBoth),
		S.CAM_DIST[store.camDist] or 0, tostring(store.shapeTop), tostring(store.topDown), tostring(primer)))
	if primer then
		local ok, err = pcall(function() api.gui.camera.takeScreenshot(1) end)
		sessionShots = sessionShots + 1
		lastShotUs = now
		log.message(string.format("%s SHOT primer=true ok=%s err=%s sessionShot=%d", S.PREFIX, tostring(ok),
			tostring(ok and "-" or err), sessionShots))
	end
	store.version = store.version + 1
	return true
end

--- Starts / stops the auto tour.
local function toggleTour()
	store.tourSource = nil
	if store.tour then
		log.message(string.format("%s TOUR stop at=%d", S.PREFIX, store.tour.i))
		store.tour, store.tourLabel = nil, nil
		store.version = store.version + 1
		return
	end
	if store.tourWait then
		store.tourWait = nil
		log.message(string.format("%s TOUR deferred=cancelled", S.PREFIX))
		store.version = store.version + 1
		return
	end
	local sh = store.status and store.status.show
	if not S.tourMayStart(sh) then
		store.tourWait = true
		log.message(string.format("%s TOUR deferred phase=%s (starts when the settle ends)", S.PREFIX, tostring(sh and sh.phase)))
		store.version = store.version + 1
		return
	end
	startTour()
end

--- true when the camera reads back the tour's target (x, y within SETTLE_M, the view's distance within SETTLE_DIST).
local function cameraAt(tr)
	local ok, d = pcall(function() return api.gui.camera.getCameraData() end)
	if not ok or d == nil or tr.target == nil then return false, nil end
	local t = tr.target
	local good = math.abs(d.x - t.x) <= SETTLE_M and math.abs(d.y - t.y) <= SETTLE_M
		and math.abs(d.z - t.dist) <= t.dist * SETTLE_DIST
	return good, d
end

--- One tour step per call from onStep (GUI thread): with screenshots on, wait for the camera to settle on the
--- target (or the fallback time), shoot, and only then let the view's dwell end; then the next view / town.
local function tourStep(now)
	local tr = store.tour
	if tr == nil then return end
	-- steady frames (v9): a step gap over STALL_US (a Main Thread stall) restarts the steady clock
	if frames.lastUs ~= nil and now - frames.lastUs > STALL_US then frames.steadySince = now end
	if frames.steadySince == nil then frames.steadySince = now end
	frames.lastUs = now
	if tr.pending then
		local good, d = cameraAt(tr)
		tr.good = good and (tr.good or 0) + 1 or 0
		local fallback = now - tr.flyUs >= tr.fallbackUs
		local steady = now - frames.steadySince >= STEADY_US
		local ready = now - (tr.startUs or 0) >= TOUR_WARMUP_US and (lastShotUs == nil or now - lastShotUs >= SHOT_GAP_US)
		if (not steady or not ready) and now - tr.flyUs < SHOT_WAIT_MAX_US then
			if tr.nextUs < now + 200000 then tr.nextUs = now + 200000 end
			return
		end
		-- (2026-10-14, run 2026-10-14_0613_sqot: shot 1 took the fallback with the camera 925 m off the town (the first
		-- fly of the tour never arrived): a fallback with the camera more than REAIM_M off is aimed again, at most
		-- REAIM_MAX times per view, before the shot)
		if fallback and tr.good < SETTLE_POLLS and d ~= nil and tr.target ~= nil and (tr.reaims or 0) < REAIM_MAX
			and math.sqrt((d.x - tr.target.x) ^ 2 + (d.y - tr.target.y) ^ 2) > REAIM_M then
			tr.reaims = (tr.reaims or 0) + 1
			local off = math.sqrt((d.x - tr.target.x) ^ 2 + (d.y - tr.target.y) ^ 2)
			pcall(function()
				local v = api.type.Vec5f.new(tr.target.x, tr.target.y, tr.target.dist, store.cam and store.cam.angle or d.w,
					tr.target.pitch or d.q)
				api.gui.camera.setCameraData(v)
			end)
			log.message(string.format("%s SHOT reaim town=%s off=%.0f try=%d", S.PREFIX, tostring(store.tourLabel), off, tr.reaims))
			tr.flyUs, tr.good = now, 0
			if tr.nextUs < now + tr.fallbackUs + 200000 then tr.nextUs = now + tr.fallbackUs + 200000 end
			return
		end
		if tr.good >= SETTLE_POLLS or fallback then
			tr.pending = false
			local ok, err = pcall(function() api.gui.camera.takeScreenshot(1) end)
			lastShotUs = now
			tourShotN = tourShotN + 1
			sessionShots = sessionShots + 1
			local tg = tr.target or {}
			log.message(string.format("%s SHOT n=%d town=%s key=%s view=%s dist=%.0f pitch=%s why=%s ok=%s err=%s settleMs=%.0f "
				.. "fallback=%s steady=%s camera=%s sessionShot=%d", S.PREFIX, tourShotN, tostring(store.tourLabel), tostring(tg.key),
				tr.top and "topdown" or "overview", tg.dist or 0, tg.pitch and string.format("%.3f", tg.pitch) or "?",
				tostring(tg.why), tostring(ok), tostring(ok and "-" or err), (now - tr.flyUs) / 1000,
				tostring(fallback and tr.good < SETTLE_POLLS), tostring(steady), d and camText(d) or "?", sessionShots))
			-- the view's dwell counts from the fly; a late shot holds the view a moment longer
			if tr.nextUs < now + 200000 then tr.nextUs = now + 200000 end
		end
		return
	end
	if now < tr.nextUs then return end
	local towns = tourTowns()
	local views = store.tourBoth and 2 or 1
	tr.view = tr.view + 1
	if tr.i == 0 or tr.view > views then
		tr.i, tr.view = tr.i + 1, 1
	end
	local t = towns[tr.i]
	if t == nil then
		log.message(string.format("%s TOUR done towns=%d shots=%d", S.PREFIX, #towns, tourShotN))
		store.tour, store.tourLabel = nil, nil
		store.version = store.version + 1
		return
	end
	-- two views: oblique then top-down; one view: the town's own view (Top-down, shape row top-down)
	local force = nil
	if views == 2 then force = tr.view == 2 end
	local _, view = flyTo(t, force)
	tr.top = view.top
	store.tourLabel = t.label
	local dwell = TOUR_DWELL[store.tourDwell] * 1e6
	tr.nextUs = now + dwell
	tr.flyUs, tr.good, tr.reaims = now, 0, 0
	tr.target = { x = t.x, y = t.y, dist = view.dist, pitch = view.pitch, why = view.why, key = t.key }
	tr.fallbackUs = math.max(SHOT_FALLBACK_US, dwell * FALLBACK_FRAC)
	tr.pending = store.tourShots == true
	if tr.view == 1 and store.tourSource ~= "all" then send("showFocus", { key = t.key }) end
	store.version = store.version + 1
end

local function focusStep(d)
	local sh = store.status and store.status.show
	local towns = sh and sh.towns or {}
	local showcase = #towns > 0
	if not showcase then
		-- any map (Real map test): step through the map's biggest towns (runner allTowns, as Tour all towns)
		towns = (store.status and store.status.allTowns) or {}
		if #towns == 0 then
			send("allTowns")
			store.err = "measuring the map's towns: press again in a moment"
			bump()
			return
		end
	end
	store.showCursor = (store.showCursor - 1 + d) % #towns + 1
	local t = towns[store.showCursor]
	flyTo(t)
	if showcase then send("showFocus", { key = t.key }) end
	store.tourLabel = not showcase and t.label or store.tourLabel
	bump()
end

---------------------------------------------------------------------------
-- Shared buttons (used in more than one tab)

local TOUR_ALL_MAX = 40   -- the runner's allTowns list (the biggest towns)

local function tourAllClick()
	if store.tour then
		store.tour, store.tourLabel, store.tourSource = nil, nil, nil
		bump()
		return
	end
	send("allTowns")
	store.tourSource = "all"
	if not startTour() then store.tourSource = nil end
end

local function autoTourButton()
	return button(store.tour and "Stop tour" or (store.tourWait and "Tour waits for the settle (cancel)" or "Auto tour"),
		"Flies to every showcase town in turn (picked distance, same angle), holding each view for the picked seconds; "
		.. "the town's label shows large at the top of the window", toggleTour,
		(store.tour or store.tourWait) and "sqotd-armed" or "sqotd-go")
end

local function tourAllButton()
	return button(store.tour and "Stop tour" or "Tour all towns", "Any map (Real map test): measures every town (ALLTOWN "
		.. "log lines: size, street orientation, density, the main mod's style / form / shape) and flies to the "
		.. tostring(TOUR_ALL_MAX) .. " biggest in turn, with screenshots when on", tourAllClick,
		store.tour and "sqotd-armed" or "sqotd-go")
end

local function prevTownButton()
	return button("Previous town", "Camera to the previous showcase town (on any other map: the map's biggest towns), picked distance, same angle",
		function() focusStep(-1) end)
end

local function nextTownButton()
	return button("Next town", "Camera to the next showcase town (on any other map: the map's biggest towns), picked distance, same angle; its numbers in the "
		.. "Showcase tab", function() focusStep(1) end)
end

local function stopTasksButton()
	return button("Stop dev tasks", "Drops queued dev tasks; the running one (also the showcase) stops after its current "
		.. "step and logs the numbers so far", function() send("stop") end, "sqotd-risky")
end

local function pauseButton(st)
	local paused = st and st.paused
	return button(paused and "Resume main driver" or "Pause main driver",
		"Pause: the main mod starts no new town check and no testing growth (a running build finishes). Session only",
		function() send("pause", { on = not paused }) end, paused and "sqotd-armed" or "sqotd-button")
end

local function simRunning(st)
	return st and st.sim and st.sim.running
end

local function simClick(mode)
	local st = store.status
	if simRunning(st) then
		send("simStop")
		return
	end
	local x, y = camera()
	if store.simNear and x == nil then store.err = "no camera position" return end
	send("simStart", V.simStartParams(store, x, y, mode))
end

local function simButton(st)
	local running = simRunning(st)
	return button(running and "Stop simulation" or "Simulate natural growth",
		running and "Stops after the current step; logs SIMGROW final per town and SIMGROW stop; restores the game "
			.. "speed and the main mod's check pace"
			or "Starts the simulation (or resumes it with the same seed) with the options below",
		simClick, running and "sqotd-armed" or "sqotd-go")
end

local function quickButton(st)
	local label = "Quick: " .. SG.QUICK.limit .. " years"
	return primary(label, "Starts " .. SG.QUICK.limit .. " simulated years as fast "
		.. "as possible with Fast fill every " .. SG.QUICK.fillEvery .. " years, a build round (the main mod's turn on "
		.. "every grown town, at most " .. SG.ROUND_BUILDS .. " builds each) before each fill and game speed "
		.. SG.SIM_SPEED .. "x (about 0.7 s per quiet year + 1 s per 90 buildings added; SIMGROW round / year lines). "
		.. "Sets the pickers below", function()
		V.applyQuick(store, SG)
		simClick("quick")
	end)
end

local function buildOutButton(st)
	local B = SG.BUILDOUT
	local label = "Build out: " .. B.years .. " years"
	return primary(label, "For judging mature towns, not the early branching: grows "
		.. "every town " .. B.years .. " more years in " .. B.chunks .. " big steps of " .. math.floor(B.years / B.chunks)
		.. " years (each one size step, a build round of up to " .. B.roundBuilds .. " builds per town and a fill), "
		.. "then the Tour all towns (screenshots as set in Camera & tour). About 3-4 minutes for 16 towns. Seed and "
		.. "Move the game date apply; the other options are set by the button", function() simClick("buildout") end)
end

---------------------------------------------------------------------------
-- Top: status, queue, progress (always visible, above the tabs)

local function topPart(st)
	local age = store.lastUs and (nowUs() - store.lastUs) / 1e6 or 0
	local items = { text(V.linkText(st, store.err, age), "font-scale-annotation, sqotd-wrap, sqotd-status") }
	local main = V.mainText(st)
	if main then items[#items + 1] = wrap(main) end
	local buttons = { text(V.taskText(st), "font-scale-body, sqotd-queue"), stopTasksButton(), pauseButton(st) }
	if simRunning(st) then buttons[#buttons + 1] = simButton(st) end
	if store.tour or store.tourWait then
		buttons[#buttons + 1] = button(store.tour and "Stop tour" or "Cancel tour", "Stops the running tour (or the one "
			.. "waiting for the settle)", store.tourSource == "all" and tourAllClick or toggleTour, "sqotd-armed")
	end
	items[#items + 1] = flow(buttons)
	local tourLine = V.tourText(store.tour, store.tourWait, #tourTowns(), store.tourSource, nil)
	for _, l in ipairs(V.progressLines(st, tourLine)) do items[#items + 1] = wrap(l) end
	if store.tourLabel then items[#items + 1] = text(store.tourLabel, "font-scale-title-1") end
	return items
end

---------------------------------------------------------------------------
-- Simulate tab

--- One tooltip per pace (SG.PACES).
local function paceTips()
	local out = {}
	for i, v in ipairs(SG.PACES) do
		if v <= 0 then
			out[i] = "As fast as possible: no minimum real time per simulated year; a quiet year passes as soon as its "
				.. "size commands came back (only while the game runs)"
		elseif v <= SG.FAST_PACE then
			out[i] = string.format("%d s: one size step per town per year", v)
		else
			out[i] = string.format("%d s: four size steps per year", v)
		end
	end
	return out
end

local function simTab(st)
	local running = simRunning(st)
	local limitLabels = {}
	for i, v in ipairs(SG.LIMITS) do limitLabels[i] = v == 0 and "never" or tostring(v) end
	local function simOpt(fields)
		if st and st.sim then send("simOpt", fields) end
	end
	return {
		head("Simulate natural growth", running and { simButton(st) } or { quickButton(st), simButton(st) }),
		wrap("Any map, no transport needed. Grows every town as the game would if it were connected: a simulated "
			.. "connectedness per town (seed), the game's experience curve, its target size and district split, applied "
			.. "with the game's own size command. The main mod runs normally. Changes the towns for good: use a throwaway "
			.. "save. State is per session; Start again continues from the towns' current size. Progress: the Simulation "
			.. "line at the top."),
		row("Real s per year", choice(V.paceLabels(SG.PACES), store.simPace, function(i)
			store.simPace = i
			if running then send("simPace", { pace = i }) end
		end, paceTips(), true)),
		check("Fast fill: houses catch up at once", store.simFill, function(on)
			store.simFill = on
			simOpt({ fastFill = on })
		end, "ON: every N simulated years the towns whose built capacity is under " .. math.floor(SG.FILL_RATIO * 100)
			.. " % of their size get the size command with all buildings updated (the dev tools' forced growth), so "
			.. "the houses don't lag. Less like natural pacing (the engine may add its own streets when a town has no "
			.. "room). OFF: houses come at the town developer's pace (needs 30 s or more per year)"),
		row("Fill every, years", choice(labels(SG.FILL_EVERY, "%d"), store.simFillEvery, function(i)
			store.simFillEvery = i
			simOpt({ fillEvery = i })
		end, V.fillEveryTips(SG.FILL_EVERY, SG.QUICK.fillEvery))),
		check("Build round: the main mod's turn on every grown town", store.simRound, function(on)
			store.simRound = on
			simOpt({ buildRound = on })
		end, "ON: every N years (the Fill every picker, with or without Fast fill), after the sizes and before the fill, "
			.. "the main mod's scheduler is held and every town that grew gets its normal check, plan and build ("
			.. "its demand trigger decides), " .. SG.ROUND_INFLIGHT .. " jobs at once, again after each build until a check builds "
			.. "nothing or " .. SG.ROUND_BUILDS .. " builds (at most " .. SG.ROUND_MAX_S .. " s). As in normal play, "
			.. "where it checks each town hundreds of times in 40 years. SIMGROW round lines. OFF: the wait below"),
		check("Wait for the main mod in each fill year (when the build round is off)", store.simWait, function(on)
			store.simWait = on
			simOpt({ waitMain = on })
		end, "ON: a fill year applies the sizes, then waits (at most " .. SG.WAIT_MAX_S .. " s) until the main mod has "
			.. "checked the " .. SG.WAIT_TOWNS .. " towns that grew most, so its streets come before the forced houses, "
			.. "then fills and waits again briefly (at most " .. SG.WAIT_FILL_S .. " s); the main mod's checks run every "
			.. SG.MAIN_CHECK_S .. " s during the run (restored at Stop). The wait shows in the Simulation line"),
		check("Game speed " .. SG.SIM_SPEED .. "x while running", store.simSpeedUp, function(on) store.simSpeedUp = on end,
			"ON: Start sets game speed " .. SG.SIM_SPEED .. "x; Stop restores the previous speed (if still "
			.. SG.SIM_SPEED .. "x). Applies at the next Start"),
		row("Seed", choice(labels(SG.SEEDS, "%d"), store.simSeed, function(i) store.simSeed = i end)),
		row("Stop after, years", choice(limitLabels, store.simLimit, function(i) store.simLimit = i end)),
		check("Only towns near the camera (within " .. SG.NEAR_M .. " m at Start; off: every town of the map)",
			store.simNear, function(on) store.simNear = on end),
		check("Every town grows (to judge the looks)", store.simEven, function(on) store.simEven = on end,
			"ON: every town grows about 4-7x in 40 years (none left small).\nOFF: realistic spread: a quarter don't "
			.. "grow, most slowly, a few fast"),
		check("Big towns better connected", store.simBias, function(on) store.simBias = on end,
			"ON: towns with a larger start are more often connected and connected better (metropolis candidates)"),
		check("Tour all towns when stopped", store.simTour, function(on) store.simTour = on end,
			"When the simulation stops (button or year limit) the Tour all towns starts (screenshots as set in the "
			.. "Camera & tour tab)"),
		check("Move the game date with the simulated years", store.simMoveDate, function(on)
			store.simMoveDate = on
			simOpt({ moveDate = on })
		end, "ON (default): at each build round the date jumps to the map's start year plus the simulated years "
			.. "(forward only, January 1st; vehicles, eras and the main mod's era styles follow). Changes the save "
			.. "for good. OFF: the calendar stands still, so a map started in 1900 stays before 1950 and its towns "
			.. "never get level 3-4 buildings (era limits: level 3 from 1950, level 4 from 1990)"),
		head("Build out (mature towns)", running and {} or { buildOutButton(st) }),
		wrap("Every town " .. SG.BUILDOUT.years .. " more years in " .. SG.BUILDOUT.chunks .. " big steps, then the "
			.. "tour. For judging mature towns; Quick shows the early branching better. SIMGROW chunk lines."),
		head("Game speed", {
			button("Game speed 4x", "Sets the base game bar's fastest speed", function() send("simSpeed", { speed = 4 }) end),
			button("Game speed " .. SG.SIM_SPEED .. "x", "Sets game speed " .. SG.SIM_SPEED .. "x (sticks; the town developer "
				.. "builds the houses in game time)", function() send("simSpeed", { speed = SG.SIM_SPEED }) end),
		}),
		head("Tour all towns", { tourAllButton() }),
		wrap("Measures every town (ALLTOWN lines) and flies to the " .. tostring(TOUR_ALL_MAX) .. " biggest. Screenshots, "
			.. "views, seconds per view and camera distance: Camera & tour tab."),
	}
end

---------------------------------------------------------------------------
-- Showcase tab

local function showcaseTab(st)
	local sh = st and st.show
	local o = st and st.showOpts or {}
	local destroyArmed = store.destroyArmedUs ~= nil and nowUs() - store.destroyArmedUs < ARM_US
	local settleIdx = S.index(S.SETTLE, o.settle or S.SETTLE_DEFAULT, 1)
	local settleLabels = {}
	for i, e in ipairs(S.SETTLE) do settleLabels[i] = e.label end
	local capIdx = S.index(S.SETTLE_CAP, o.settleCap or S.SETTLE_CAP_DEFAULT, 2)
	local items = {
		head("Showcase (Blank Slate map)", {
			primary("Showcase: build all", "Lays out and creates one town per style plus control and Probe C towns on the "
				.. "island, then grows them round-robin: each step a forced increment in the town's style and two forced "
				.. "growth passes. Pauses the main driver (stays paused). Runs unattended; Stop ends it after the "
				.. "current step, pressing this again resumes", function() send("showcase", { sn = store.sn }) end),
			button("Stop", "Stops the showcase (and other dev tasks) after the current step; logs the numbers so far",
				function() send("stop") end, "sqotd-risky"),
		}),
		wrap("One town per style, controls, Probe C angles. Progress: the Showcase line at the top and below."),
		row("Increments per town", choice(labels(S.SHOW_N, "%d"), store.sn, function(i) store.sn = i end)),
		head("Next new showcase", {}),
		check("Shape row", o.shapes ~= false, function() send("showOpt", { opt = "shapes" }) end,
			"One EU extension town per shape archetype (compact, linear, cross, fingers, fan, twin, lens, ridge). "
			.. "Next new showcase"),
		check("Density row", o.density ~= false, function() send("showOpt", { opt = "density" }) end,
			"Four EU extension towns, one density lever each: level weights, upgrade at the centre, medium streets, "
			.. "control. Next new showcase"),
		check("Fill mod streets (probe)", o.fill == true, function() send("showOpt", { opt = "fill" }) end,
			"Probe: after each round's growth, makeTownDevelopAtCmd (no streets, no upgrade) on both sides of the "
			.. "round's new mod streets, so houses start there. Applies to the next new showcase"),
		check("Freeze style towns (probe)", o.freeze == true, function() send("showOpt", { opt = "freeze" }) end,
			"Probe: style towns are created with town development off (makeTownSetDevelopmentActiveCmd false). STEP "
			.. "lines show whether forced growth still adds vanilla streets (vanilla=). Next new showcase"),
		row("Ring", choice(V.RING_LABELS, V.ringIndex(o.ringMode), function(i)
			if V.ringToggle(i, o.ringMode) then send("showOpt", { opt = "ring" }) end
		end, { "Roundabout ring road: a one-way town street ring with the engine's own one-way lane pattern (falls "
			.. "back to the two-way ring when refused, RB FALLBACK)", "Roundabout ring road: the dead end's own two-way "
			.. "town street" })),
		head("Settle after the rounds", {}),
		row("Settle", choice(settleLabels, settleIdx, function(i) send("showOpt", { opt = "settle", value = i }) end)),
		row("At most, real min", choice(labels(S.SETTLE_CAP, "%d"), capIdx,
			function(i) send("showOpt", { opt = "settleCap", value = i }) end)),
		check("Forced growth passes during the settle", o.settleForce == true,
			function() send("showOpt", { opt = "settleForce" }) end,
			"During the settle, every 2 game months one forced growth pass for every showcase town (UpdateSize at "
			.. "its current schedule size). Off: only the game's own growth"),
		check("Tour after settle", o.tourAfter == true, function() send("showOpt", { opt = "tourAfter" }) end,
			"After the settle phase the auto tour starts by itself (screenshots as set in the Camera & tour tab)"),
		head("Tour", { autoTourButton(), prevTownButton(), nextTownButton() }),
		wrap("Screenshots, views, seconds per view and camera distance: Camera & tour tab."),
		head("Reset", {
			button("Forget showcase", "Drops the showcase state (not the towns): the next run lays out again and "
				.. "reuses towns named like its items", function() send("showReset") end),
			button(destroyArmed and "CONFIRM reset showcase" or "Reset showcase (destroy towns)",
				"Destroys every showcase town (makeTownDestroyCmd) and logs which streets stay; if streets stay, the next "
				.. "layout moves by 1250 m. Click twice within 8 s", function()
					if destroyArmed then
						store.destroyArmedUs = nil
						send("showDestroy")
					else
						store.destroyArmedUs = nowUs()
						bump()
					end
				end, destroyArmed and "sqotd-armed" or "sqotd-risky"),
		}),
	}
	if o.offset then items[#items + 1] = wrap("Next layout offset: " .. o.offset .. " (streets stayed after the reset)") end
	if sh then
		items[#items + 1] = head("Progress", {})
		items[#items + 1] = wrap(sh.head or "")
		for _, l in ipairs(sh.focus or {}) do items[#items + 1] = wrap("> " .. l) end
		if sh.results and #sh.results > 0 then
			items[#items + 1] = head("Results", {})
			for _, l in ipairs(sh.results) do items[#items + 1] = wrap(l) end
		else
			for _, l in ipairs(sh.lines or {}) do items[#items + 1] = wrap(l) end
		end
	end
	return items
end

---------------------------------------------------------------------------
-- Town tab (the selected town)

local function townTab(st)
	local armed = store.armedUs ~= nil and nowUs() - store.armedUs < ARM_US
	local styleLabels, styleTips = {}, {}
	for i, sty in ipairs(S.STYLES) do
		styleLabels[i] = sty.label
		styleTips[i] = "Grow now and Plan only use " .. sty.id
			.. (i == 1 and ": what the main mod builds (NA grid; outer suburbs by era)"
				or (i == 2 and ": the profile the map's region and climate pick" or " (with its era's outer zone)"))
	end
	local motifLabels, motifTips = {}, {}
	for i, mo in ipairs(S.MOTIFS) do
		motifLabels[i] = mo.label
		motifTips[i] = i == 1 and "Grow now and Plan only use the motifs the main mod picks for the town (none, or its "
			.. "crescents / hill road)" or ("Grow now and Plan only force the motif " .. mo.id .. " on the picked town (dev "
			.. "only, for screenshots; the town's saved frame keeps its own motifs)")
	end
	local items = {
		head("Town", {
			button("Pick town nearest the camera", "Selects the town closest to the camera centre and inspects it",
				needCamera(function(x, y) send("select", { x = x, y = y }) end)),
			button("Refresh", "Inspect the selected town again", function() send("inspect") end),
		}),
	}
	local lines = st and st.townLines or {}
	if #lines == 0 then items[#items + 1] = wrap("No town picked.") end
	for _, l in ipairs(lines) do items[#items + 1] = wrap(l) end
	for _, it in ipairs({
		head("City type for Grow now / Plan only", {}),
		choice(styleLabels, store.style, function(i)
			store.style = i
			send("style")
		end, styleTips, true),
		head("Motif for Grow now / Plan only (dev)", {}),
		choice(motifLabels, store.motif, function(i)
			store.motif = i
			send("style")
		end, motifTips, true),
		head("Forest (main mod)", {
			button("Forest lane test", "Dry-runs the picked town, then the most wooded towns, until a plan crosses forest "
				.. "wooded on both sides (LANETEST pick). Builds that increment with every such stretch as a locked country lane "
				.. "(no houses), grows the town, builds a second increment and grows again; LANETEST logs the houses on the lane "
				.. "(want 0) and the streets beyond it. Costs money",
				function() send("forestLane") end),
			button("Force deep forest", "The picked town plans as a deep forest town from its next plan (main mod, deep "
				.. "forest round): winding streets, every street near the trees locked, small woods inside the town kept, "
				.. "2 of 3 lanes, a quarter of the clearing budget (FOREST mode=deep why=force). Session only; its first build "
				.. "after this saves it as deep on the town's frame. Throwaway save",
				function() send("deepForest") end, "sqotd-risky"),
		}),
		head("Character (main mod)", {
			button("Force character", "The picked town plans as the strong character kind chosen below from its next plan "
				.. "(main mod, ot_character): its style, form, blocks, motifs; the roundabout town one-way rings at its new "
				.. "crossings (RB lines). densify: the densify trait at once (DENSIFY). \"-\": back to the map's pick. Session "
				.. "only; a first build saves the kind on the town's frame. Throwaway save",
				function() send("forceChar", { kind = S.CHARS[store.charKind or 1] }) end, "sqotd-risky"),
		}),
		choice(S.CHARS, store.charKind or 1, function(i) store.charKind = i end, nil, true),
		head("District town (main mod)", {
			button("Found a district", "The main mod founds a district town (a small residential town of its own) for the "
				.. "picked town on its next build, whatever its size, seed and the map quota say (the site rules apply: a "
				.. "hilltop, shore, far bank, lane end or valley head 0.6-1.5 km out, open land). Press again once "
				.. "DISTRICT created shows: links it by a road now. Creates a real town: throwaway save",
				function() send("district") end, "sqotd-risky"),
		}),
		head("Industrial satellite probe (R7)", {
			button("Industrial satellite probe", "Creates a separate town 0.9-1.5 km from the picked town (across water when it "
				.. "can) with initial capacities 10 / 10 / 200 (residential / commercial / industrial), grows it 3 passes and "
				.. "logs SATIND: does it build only industry? Creates a real town: throwaway save",
				function() send("satInd") end, "sqotd-risky"),
		}),
		head("Stop names (main mod)", {
			button("Place test stops (named)", "Builds one kerbside Road Stop (no line) per stop theme the picked town offers "
				.. "(hill, shore, river, valley, forest, station, centre, outskirts; at most 8), each on a town street, and has "
				.. "the main mod name it (TESTSTOP + STOPNAME lines). Costs money; remove them with the bulldozer",
				function() send("testStops") end),
		}),
		head("Grow the selected town", {
			primary("Grow now", "Builds the next increment(s) now in the picked style (needs-room test ignored), each "
				.. "followed by forced growth: first pass x growth factor, then 2 more passes at the reached size",
				function() send("grow") end),
		}),
		row("Increments", choice(labels(S.N, "%d"), store.n, function(i) store.n = i end)),
		row("Growth", choice(labels(S.FACTORS, "x%g"), store.factor, function(i) store.factor = i end)),
		flow({
			button("Plan only (dry run)", "Plans and pre-checks the next increment in the picked style, logs every edge, "
				.. "shows leaf markers along it for 30 s. Builds nothing", function() send("dry") end),
			button("Show plan again", "Markers of the last dry run again", function() send("markers") end),
			button("Grow town only", "Forced growth of the selected town (3 passes), no streets", function() send("growTown") end),
			button(armed and "CONFIRM undo" or "Undo last increment",
				"Removes the streets of the town's last increment built this session (main mod or dev). Removing streets "
				.. "with houses demolishes them. Click twice within 8 s", function()
					if armed then
						store.armedUs = nil
						send("undo")
					else
						store.armedUs = nowUs()
						bump()
					end
				end, armed and "sqotd-armed" or "sqotd-risky"),
		}),
		check("Join own dead ends (dev builds; UNVERIFIED in game: backup save first)", st and st.ownJoins,
			function(on) send("ownJoins", { on = on }) end,
			"Dev builds only. Off (as the main mod): dead ends of our own streets that the town hasn't adopted yet (no "
			.. "lane config) are never joined, so Grow now may stop after one increment (noJoin=noConfig). On: they are "
			.. "joined, adding a lane config to a script node. UNVERIFIED in game: backup save first"),
	}) do items[#items + 1] = it end
	if st and st.plan and st.plan ~= "" then items[#items + 1] = wrap("Last plan: " .. st.plan) end
	for _, it in ipairs({
		head("Roundabouts and nodes (near the camera)", {}),
		flow({
			button("Roundabout here", (st and st.rb) and ("Builds a small 4-arm roundabout (square_roundabouts geometry, "
				.. "plain streets) at the dead end nearest the camera of the town nearest the camera; logs RB lines")
				or "Needs Roundabouts & Interchanges (square_roundabouts) enabled",
				needCamera(function(x, y) send("roundabout", { x = x, y = y }) end),
				(st and st.rb) and "sqotd-risky" or "sqotd-button"),
			button("Roundabout adoption", "Logs the parcels and houses on the last roundabout's ring and arms (RB ADOPT)",
				function() send("rbAdopt") end),
			button("Node dump", "Logs the street nodes nearest the camera (60 m): edges, every lane connection with what its "
				.. "lanes mean, and our pattern for the same node (NODEDUMP / NODECONN / NODEOURS). Read-only. Use it on "
				.. "a Roundabouts & Interchanges one-way ring node",
				needCamera(function(x, y) send("nodeDump", { x = x, y = y }) end)),
		}),
	}) do items[#items + 1] = it end
	if st and st.rbProbe then items[#items + 1] = wrap("Last roundabout: " .. st.rbProbe) end
	if st and not st.rb then items[#items + 1] = wrap("Roundabouts: not available (" .. tostring(st.rbWhy) .. ")") end
	return items
end

---------------------------------------------------------------------------
-- Main mod tab (driver, debug log, all towns)

local function mainTab(st)
	local dbg = st and st.debug or "param"
	return {
		head("Main mod driver", { pauseButton(st) }),
		row("Debug log", choice(V.DEBUG_LABELS, V.debugIndex(dbg), function(i)
			send("debug", { mode = V.DEBUG_MODES[i] })
		end, { "The mod's Debug log setting decides", "Every check and planning step of the main mod goes to stdout.txt",
			"Only builds are logged" })),
		check("Build as player (off: free town streets, the default; on: the player pays, refunded)",
			st ~= nil and st.player == true, function(on) send("player", { on = on }) end,
			"Every street build (main mod and dev) without a player in its context (off, the default: free, the town's "
			.. "streets) or with the player (on: charged, then refunded; SEND logs player=on|off)"),
		wrap("While a dev task is queued or running, the main driver is held automatically."),
		head("All towns the main mod acts on", {
			primary("Fast-forward all", "Rounds x every acted-on town: one forced growth pass (growth factor), then the "
				.. "main mod's check with its needs-room trigger, building when it fires. No 3 s spacing",
				function() send("fast") end),
		}),
		row("Rounds", choice(labels(S.M, "%d"), store.m, function(i) store.m = i end)),
		row("Growth", choice(labels(S.FACTORS, "x%g"), store.factor, function(i) store.factor = i end)),
		flow({
			button("Grow all towns", "One forced growth pass (growth factor) for every acted-on town, no streets",
				function() send("growAll") end),
			button("Place test stops: all towns", "Place test stops (named) for the first 6 acted-on towns (at most 24 "
				.. "stops in all; TESTSTOP + STOPNAME lines)", function() send("testStops", { all = true }) end),
		}),
	}
end

---------------------------------------------------------------------------
-- Camera & tour tab

local function cameraTab()
	return {
		head("Tours", { autoTourButton(), tourAllButton() }),
		wrap("Auto tour: every showcase town. Tour all towns: any map, the " .. tostring(TOUR_ALL_MAX) .. " biggest towns. "
			.. "Each SHOT is logged in order; the game names and stores the files (userdata folder)."),
		check("Screenshots during the tour", store.tourShots, function(on) store.tourShots = on end,
			"During the tour: one game screenshot per view (api.gui.camera.takeScreenshot); the game names the files, "
			.. "the log lists them in order (SHOT)"),
		check("Two views per town (overview, then top-down)", store.tourBoth, function(on) store.tourBoth = on end,
			"Two views per town (oblique overview, then straight down) or one (Top-down decides)"),
		row("s per view", choice(labels(TOUR_DWELL, "%d"), store.tourDwell, function(i) store.tourDwell = i end)),
		head("Camera", { prevTownButton(), nextTownButton(),
			button("Reset camera angle", "The next jump takes the camera's current angle and pitch again",
				function() store.cam = nil end) }),
		row("Distance, m", choice(labels(S.CAM_DIST, "%d"), store.camDist, function(i) store.camDist = i end)),
		check("Top-down (pitch " .. S.TOPDOWN_PITCH .. ")", store.topDown, function(on) store.topDown = on end,
			"Next / Previous town look straight down; off keeps the first jump's pitch"),
		check("Shape row: top-down, one distance step wider", store.shapeTop, function(on) store.shapeTop = on end,
			"Camera: shape-row towns (Shape: ...) are seen straight down from one distance step wider, so their "
			.. "outline reads. Off: as every other town"),
	}
end

---------------------------------------------------------------------------
-- Window content

local TAB_BUILDERS = { sim = simTab, showcase = showcaseTab, town = townTab, main = mainTab, camera = cameraTab }

local windowState = nil

--- Every tab's item is the same fixed-size ScrollArea, so the TabWidget's height never depends on the selected
--- tab (Stress Test tabChild). Only the selected tab is built.
local function tabChild(key, label, items)
	return builtin.TabWidgetChild{
		localKey = "sqotd_tab_" .. key,
		value = key,
		indicator = text(label, "font-scale-tab-widget-indicator"),
		item = builtin.Component{
			layout = box({ scroll("sqotd-tabscroll", box(items, false, "sqotd-tab")) }),
		},
	}
end

local OtdContent = react.RegisterRecipe("OtdContent", function()
	local verState = react.useState(store.version)
	windowState = verState
	local nextRender = react.useRef(0)
	react.onStep(function()
		local now = nowUs()
		if now < nextRender:get() then return end
		nextRender:set(now + RENDER_US)
		if verState:hasExpired() then return end
		if verState:old() ~= store.version then verState:set(store.version) end
	end)
	local st = store.status
	local selected = V.tabKey(store.tab)
	local tabs = {}
	for _, t in ipairs(V.TABS) do
		tabs[#tabs + 1] = tabChild(t.key, t.label, t.key == selected and TAB_BUILDERS[t.key](st) or {})
	end
	local logLines = {}
	for _, l in ipairs(st and st.log or {}) do logLines[#logLines + 1] = wrap(l) end
	if #logLines == 0 then logLines[1] = wrap("No output yet. Everything is also in stdout.txt ([SQOT_DEV] and [SQOT] lines).") end
	local items = topPart(st)
	items[#items + 1] = builtin.TabWidget{
		orientation = builtin.type.TabOrientation.North,
		deselectAllowed = false,
		value = selected,
		onValueChange = function(newTab)
			if newTab == nil then return end
			store.tab = V.tabKey(newTab)
			bump()
			if not verState:hasExpired() then verState:set(store.version) end
		end,
		tabs = tabs,
	}
	items[#items + 1] = section("Log")
	items[#items + 1] = scroll("sqotd-logscroll", box(logLines))
	return box(items, false, "sqotd-content")
end)

local OtdWindow = react.RegisterWrapperRecipe("OtdWindow", builtin.Window, function(params)
	return builtin.Window{
		id = WINDOW_ID,
		title = "DEV Organic Towns tools",
		closable = true,
		movable = true,
		onClose = params.onClose,
		content = OtdContent(),
	}
end)

local function closeWindow()
	windowState = nil
	local wa = game_react_globals.getDefaultWindowApi()
	if wa ~= nil then wa.removeAllWindows(OtdWindow) end
end

local function toggleWindow()
	if windowState ~= nil and not windowState:hasExpired() then
		closeWindow()
		return
	end
	local wa = game_react_globals.getDefaultWindowApi()
	if wa == nil then
		log.warning(S.PREFIX .. " no window container")
		return
	end
	wa.addSingletonWindow(OtdWindow, { onClose = closeWindow })
	wa.moveSingletonWindowToFront(OtdWindow)
	send("poll")
end

---------------------------------------------------------------------------
-- HUD button (always mounted: hears the status events)

local OtdHudPlugin = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension, "OtdHudPlugin", function()
	local isEditor = react.useRefLazy(function() return api.gui.game.isMapEditor() end)
	react.onEvent(S.EV_STATUS, function(_name, param)
		local ok, err = pcall(accept, param)
		if not ok then log.warning(S.PREFIX .. " HUD status: " .. tostring(err)) end
	end)
	react.onStep(function()
		if isEditor:get() then return end
		if store.tour then
			local okT, errT = pcall(tourStep, nowUs())
			if not okT then
				log.warning(S.PREFIX .. " HUD tour: " .. tostring(errT))
				store.tour = nil
			end
		end
		local cc = store.camCheck
		if cc ~= nil and nowUs() >= cc.us then
			store.camCheck = nil
			local ok, d = pcall(function() return api.gui.camera.getCameraData() end)
			local vw = cc.view or {}
			log.message(string.format("%s CAMERA town=%s key=%s dist=%.0f topdown=%s why=%s asked=%s before=%s read=%s",
				S.PREFIX, tostring(cc.label), tostring(cc.key), vw.dist or 0, tostring(vw.top), tostring(vw.why), cc.asked,
				cc.before, ok and d and camText(d) or "?"))
		end
		-- no status for a while and the window is open: ask (the game script answers through the return value)
		if windowState == nil or windowState:hasExpired() then return end
		local now = nowUs()
		if (store.lastUs == nil or now - store.lastUs > POLL_US) and now - store.pollUs > POLL_US then
			store.pollUs = now
			send("poll")
		end
	end)
	if isEditor:get() then return nil end
	return builtin.BoxLayout{
		meta = { class = "sqotd-box" },
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Button{
				meta = { class = "sqotd-hud-button", tooltip = "DEV Organic Towns tools\n(builds streets and grows towns; use a throwaway save)" },
				content = text("OT Dev"),
				onClick = toggleWindow,
			},
		},
	}
end)

-- .script.lua resources expose their exports through data(), not a return value
function data()
	return {
		OtdHudPlugin = OtdHudPlugin,
	}
end
