-- DEV ONLY (never upload). Organic Towns dev tools: constants shared by the HUD (GUI plugin state) and the game
-- script (guiUpdate state). Pure, no requires: the two states each load their own copy.

local S = {}

S.MOD_ID = "square_organic_towns_dev"
S.MAIN_ID = "square_organic_towns"
S.PREFIX = "[SQOT_DEV]"

-- HUD -> game script: api.gui.fireGuiScriptEvent(GUI_ID, EV_CMD, { action = ..., ... }) reaches the dev game
-- script's guiHandleEvent (base pattern: the vehicle store fires "mission.buyVehicle" at the mission script).
-- Game script -> HUD: api.gui.fireReactEvent(EV_STATUS, status) reaches react.onEvent(EV_STATUS, fn) in the HUD
-- plugin (base pattern: mission_sim.script.tl guiUpdate fires "setMenuFilter" at game.tl).
S.GUI_ID = "square_organic_towns_dev"
S.EV_CMD = "sqotdev.cmd"
S.EV_STATUS = "sqotdev.status"

-- Pickers (1-based indices into these lists travel in the commands)
S.N = { 1, 3, 5, 10 }                 -- increments per Grow now
S.M = { 1, 3, 5, 10 }                 -- rounds per Fast-forward
S.FACTORS = { 1.25, 1.5, 2, 3 }       -- growth factor of a forced growth's first pass
S.SHOW_N = { 10, 20, 40 }             -- showcase: increments per town (= otd_showcase.NS)
-- Showcase settle phase after the rounds (v4): off, a few forced growth passes back to back (v6 default: no
-- waiting for game time; v5's 2 game years took ~16 real minutes), a number of game years, or until the buildings
-- stop growing (plateau, otd_showcase.settle). `months` = game months to wait, `passes` = forced passes.
S.SETTLE = {
	{ id = "off", label = "off" },
	{ id = "1y", label = "1 year", months = 12 },
	{ id = "2y", label = "2 years", months = 24 },
	{ id = "5y", label = "5 years", months = 60 },
	{ id = "plateau", label = "until growth stops" },
	{ id = "passes", label = "3 grow passes", passes = 3 },   -- last: older pickers' indices stay
}
S.SETTLE_DEFAULT = "passes"
S.SETTLE_CAP = { 5, 10, 20, 40 }      -- real minutes at most for any settle mode (then reason=cap)
S.SETTLE_CAP_DEFAULT = 20   -- v3 ran ~40 s per game month at speed 4: 2 years ~16 min

-- Showcase camera (HUD): overview distance picker (m) and the top-down pitch. Shape-row towns (key SHAPE_*) read
-- round from 1000 m, so with "Shape row: top-down" (default ON) they are seen straight down from one step wider.
S.CAM_DIST = { 1000, 1800, 2500 }
S.CAM_DIST_DEFAULT = 2                -- 1800 m
S.TOPDOWN_PITCH = 1.45

-- Style modes for Grow now / Plan only: the driver's styleMode values (ot_driver.styleFor). Profile ids must
-- match ot_style.IDS (tests/square_organic_towns_dev/test_runner.lua checks).
S.STYLES = {
	{ id = "main", label = "Main mod (auto)" },
	{ id = "region", label = "Region (auto)" },
	{ id = "NA_GRID", label = "NA grid" },
	{ id = "NA_SUBURB", label = "NA suburb" },
	{ id = "EU_ORGANIC", label = "EU organic" },
	{ id = "EU_EXTENSION", label = "EU extension" },
	{ id = "MED_HILL", label = "MED hill" },
	{ id = "MED_ENSANCHE", label = "MED ensanche" },
	{ id = "JP_DENSE", label = "JP dense" },
	{ id = "NORDIC", label = "Nordic" },
	{ id = "SUPERBLOCK", label = "Superblock" },
}

-- Motif for Grow now / Plan only (Town tab, M0 2026-10-13): "main" = the main mod's own motifs, else an ot_motif kind
-- forced on the picked town (startJob opts.motif). Ids must match ot_motif.IDS (tests/square_organic_towns_dev/
-- test_runner.lua checks); append new kinds as the motif phases add them.
-- Strong character kinds of the main mod (Town tab "Force character", 2026-10-14): "-" = back to the map's pick,
-- "densify" = the densify trait now; the others must match ot_character.IDS (test_runner checks).
S.CHARS = { "-", "hilltop", "clifftop", "harbour_cove", "waterfront", "street_village", "company_town", "garden_city",
	"island_town", "roundabout_town", "deep_forest", "densify" }

S.MOTIFS = {
	{ id = "main", label = "Main mod (auto)" },
	{ id = "crescent", label = "Crescent" },
	{ id = "hill_road", label = "Hill road" },
	{ id = "hill_climb", label = "Hill climb" },
	{ id = "valley_fishbone", label = "Valley fishbone" },
	{ id = "harbour_crescent", label = "Harbour crescent" },
	{ id = "fishing_village", label = "Fishing village" },
	{ id = "ribbon_village", label = "Ribbon village" },
	{ id = "village_green", label = "Village green" },
	{ id = "crossroads_hamlet", label = "Crossroads hamlet" },
	{ id = "ring_road", label = "Ring road" },
	{ id = "station_quarter", label = "Station quarter" },
	{ id = "workers_terraces", label = "Workers' terraces" },
	{ id = "culdesac_pods", label = "Cul-de-sac pods" },
	{ id = "switchbacks", label = "Switchbacks" },
	{ id = "ridge_street", label = "Ridge street" },
	{ id = "headland_street", label = "Headland street" },
	{ id = "bridgehead_quarter", label = "Bridgehead quarter" },
	{ id = "peninsula_tip", label = "Peninsula tip" },
}

--- true for a shape-row town of the showcase status (otd_showcase.status towns: key, kind, shape, row).
function S.isShapeTown(t)
	if type(t) ~= "table" then return false end
	if t.shape ~= nil and t.shape ~= "" then return true end
	if t.metro ~= nil and t.metro ~= "" then return true end   -- (v7 metropolis row: top-down too)
	if t.form ~= nil and t.form ~= "" then return true end     -- (v8 form row: top-down too)
	return type(t.key) == "string" and (t.key:sub(1, 6) == "SHAPE_" or t.key:sub(1, 6) == "METRO_" or t.key:sub(1, 5) == "FORM_")
end

--- Camera view for one showcase town: distance (m), top-down or not, and why. o = { distIdx (S.CAM_DIST index),
--- shapeTop (bool, "Shape row: top-down"), topDown (bool, the window's Top-down), forceTop (bool or nil: the
--- tour's second view) }. Shape-row towns with shapeTop: one picker step wider (the widest stays) and straight
--- down unless a view forces the pitch.
function S.view(t, o)
	o = o or {}
	local i = o.distIdx or S.CAM_DIST_DEFAULT
	if S.CAM_DIST[i] == nil then i = S.CAM_DIST_DEFAULT end
	local top = o.topDown == true
	local why = "picked"
	if o.shapeTop ~= false and S.isShapeTown(t) then
		i = math.min(i + 1, #S.CAM_DIST)
		top = true
		why = "shapeRow"
	end
	if o.forceTop ~= nil then top = o.forceTop end
	return S.CAM_DIST[i], top, why
end

--- true when the auto tour may start now: no showcase, or its phase is not the settle (Showcase v5: a tour asked
--- for mid-settle waits until the settle ends). show = the status's showcase part (otd_showcase.status) or nil.
function S.tourMayStart(show)
	if type(show) ~= "table" then return true end
	return show.phase ~= "settle"
end

--- Index (1-based) of a value in a list, or the default.
function S.index(list, v, default)
	for i, x in ipairs(list) do
		if x == v or (type(x) == "table" and x.id == v) then return i end
	end
	return default
end

return S
