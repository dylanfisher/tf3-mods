-- Organic Towns: "Streets at industries" (pure; 2026-10-13, real map round 5).
--
-- User (real map runs, Barnes, Ilkeston, earlier Barnard Castle): small house clusters appear right next to industries
-- 1-2 km from the towns, on the country road, sometimes across a river: odd next to heavy industry. Organic Towns did not
-- build them (no mod build there, SATELLITE on=false). They are most likely the map generator's
-- `baseConfig.locations.makeInitialStreets` streets ("Add small streets at the edge of industries", api type.d.tl:3554;
-- base/content/base/mod.script.tl:135 sets it true, "default true, false experimental"), which the nearest town later
-- fills with houses. mod.script.lua's preRunFn sets the field from this setting:
--   off   makeInitialStreets = false: no generator streets at the industries of a new map (and, it seems, no roads
--         between towns: docs/findings/towns.md "`makeInitialStreets = false` also drops the roads between towns")
--   game  (default since the final test) baseConfig untouched (the game's default, true)
--
-- Read from the game files (unverified in game): the new-game page's map preview (GameMap, api type.d.tl:229-315) holds
-- only town / industry positions, sizes and town connections, no streets, so the industry-edge streets are laid when the
-- game starts and builds the map, after preRunFn, from the running baseConfig (which preRunFn has set). The preview's own
-- locations config sets makeInitialStreets = true (gui/menu/new_game_or_map_settings_page.tl:407) but has no streets to
-- make. On an existing save the map is built already: preRunFn runs on every load and writes the field again, which
-- touches no existing street; it could only leave out such streets at industries the game founds later, if the game reads
-- the field then too (unknown). Industries: their cargo goes to stations in their catchment, no street needed; their
-- workplaces are a production booster (gui/entity_window/industry/industry.tl:176-180: PERSON_CAPACITY counts as a
-- booster), so an industry without those streets still produces; the worker boost may come later until a street reaches
-- it (unverified).

local M = {}

M.CHOICES = { "off", "game" }   -- mod.json order
M.VALUE = { off = false, game = nil }   -- nil: untouched

local function txt(v)
	if type(v) == "number" then return string.format("%.4g", v) end
	return (tostring(v):gsub("%s+", "_"))
end

--- Writes baseConfig.locations.makeInitialStreets for `choice` (preRunFn). "game" (and unknown) leaves baseConfig
--- untouched (not even read-written). Returns { choice, from, to, applied, err }.
function M.apply(baseConfig, choice)
	local out = { choice = choice, applied = false }
	local okR, from = pcall(function() return baseConfig.locations.makeInitialStreets end)
	if okR then out.from = from else out.err = "read:" .. txt(from) end
	local want = M.VALUE[choice]
	if want == nil or not okR then
		out.to = out.from
		return out
	end
	local okW, err = pcall(function() baseConfig.locations.makeInitialStreets = want end)
	if not okW then
		out.err = "write:" .. txt(err)
		out.to = out.from
		return out
	end
	local okB, back = pcall(function() return baseConfig.locations.makeInitialStreets end)
	out.to = okB and back or want
	out.applied = true
	return out
end

--- The [SQOT] INDSTREETS line's fields for an apply() result.
function M.fields(r, where)
	return {
		{ "where", where or "preRunFn" }, { "choice", r.choice or "-" },
		{ "makeInitialStreets", txt(r.from) .. "->" .. txt(r.to) }, { "applied", r.applied == true },
		{ "err", r.err or "-" }, { "note", "newMapsOnly" },
	}
end

return M
