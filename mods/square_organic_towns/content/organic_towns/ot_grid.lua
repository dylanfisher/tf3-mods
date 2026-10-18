-- Organic Towns: organic <-> gridded balance (pure; 2026-10-13, real map round 3).
--
-- User (real map run 2026-10-13_0137_sqot-dev): "Is our code set up so that in later years cities are more likely to
-- become more gridded? Perhaps a mod setting to choose how organic vs gridded towns are in general. Default should
-- tend toward organic, especially early game ... Most cities are organic, and none have any grid; we might be too far
-- on the organic end." Before, the era only gated styles (ot_site FROM_YEAR) and a style was picked once per town.
--
-- Now a grid bias per year and setting:
--   era trend   e(year) = 0 until ERA_FROM (1910), rising linearly to 1 at ERA_FULL (1970), on to ERA_MAX at ERA_LATE
--               (2000): early game clearly organic, later years more planned / gridded towns and districts. (Era range
--               1900+, 2026-10-13: TF3's earliest start year is 1900 (user); the trend was 0 until 1870, so a 1900
--               start already had a third of it.)
--   setting     "Town layout" (mod param town_layout): very organic / organic (default) / mixed / gridded / very
--               gridded, a multiplier SETTING[k] on the gridded styles' weight and an offset on the grid look.
-- Applied (ot_site.weights, ot_style.resolve):
--   * style weights: the gridded styles (NA grid, NA suburb, MED ensanche, superblock) x factor(GRIDDED), the
--     19th-c. extension x factor(SEMI); organic styles unchanged. factor = SETTING x exp(K x e).
--   * grid look (0..1, `look`): organic growers' gridness / jitter / curve move toward a straight, regular plan
--     (LOOK_MAX at most); the outer zone (EU organic's extension ring, beyond `from` m, which shrinks with the look)
--     gets OUTER_EXTRA more look, so new outer districts of an old town turn more regular as the years pass while
--     the old core keeps its lanes. The outer zone is re-resolved per decade (ot_driver style cache key).
-- Saved styles stay (a town keeps the style saved at its first build); the setting changes new picks and the outer
-- districts' look from the next decade / load on.

local M = {}

M.ON = true   -- (the offline tests of the other rules turn it off: their baselines were measured without it)

M.IDS = { "very_organic", "organic", "mixed", "gridded", "very_gridded" }   -- (mod.json order)
M.DEFAULT = 2
M.SETTING = { 0.25, 0.7, 1.3, 2.4, 4.5 }        -- x the gridded styles' weight
M.LOOK_OFFSET = { -0.25, 0, 0.12, 0.3, 0.5 }     -- + on the grid look
M.ERA_FROM, M.ERA_FULL, M.ERA_LATE, M.ERA_MAX = 1910, 1970, 2000, 1.3
M.K = { GRIDDED = 1.3, SEMI = 0.55, SEMI_BASE = 0.65, SEMI_POW = 0.7 }
M.GROUP = { NA_GRID = "GRIDDED", NA_SUBURB = "GRIDDED", MED_ENSANCHE = "GRIDDED", SUPERBLOCK = "GRIDDED",
	EU_EXTENSION = "SEMI" }
M.LOOK_ERA = 0.45          -- grid look from the era trend at e = 1
M.LOOK_MAX = 0.85
M.OUTER_EXTRA = 0.25       -- the outer zone's extra look
M.OUTER_SHRINK = 120       -- m: the outer zone starts up to this much closer at look 1

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end

--- Era trend 0 .. ERA_MAX for a year (nil: 1960).
function M.era(year)
	year = tonumber(year) or 1960
	if year <= M.ERA_FROM then return 0 end
	if year <= M.ERA_FULL then return (year - M.ERA_FROM) / (M.ERA_FULL - M.ERA_FROM) end
	return math.min(M.ERA_MAX, 1 + (M.ERA_MAX - 1) * (year - M.ERA_FULL) / (M.ERA_LATE - M.ERA_FULL))
end

--- The bias for a year and setting index (1..5; nil: default): { e, setting, look, gridded = factor, semi = factor }.
function M.bias(year, setting)
	local k = tonumber(setting) or M.DEFAULT
	if M.SETTING[k] == nil then k = M.DEFAULT end
	local e = M.era(year)
	local s = M.SETTING[k]
	return {
		e = e, setting = k,
		gridded = s * math.exp(M.K.GRIDDED * e),
		semi = s ^ M.K.SEMI_POW * (M.K.SEMI_BASE + M.K.SEMI * e),
		look = clamp(M.LOOK_ERA * e + M.LOOK_OFFSET[k], -0.3, M.LOOK_MAX),
	}
end

--- Weight factor of a style id under bias b (1 for organic styles or without a bias).
function M.factor(b, id)
	if b == nil then return 1 end
	local grp = M.GROUP[id]
	if grp == "GRIDDED" then return b.gridded end
	if grp == "SEMI" then return b.semi end
	return 1
end

--- Applies a grid look (-0.3 .. LOOK_MAX) to a resolved / zone profile p in place (organic growers: gridness up,
--- jitter / curve / block spread down; a negative look the other way, a little). Grids are already regular.
function M.applyLook(p, look)
	if p == nil or look == nil or look == 0 then return end
	if p.grower ~= "organic" then return end
	if look > 0 then
		p.gridness = (p.gridness or 0.5) + (1 - (p.gridness or 0.5)) * look
		p.jitter = (p.jitter or 0) * (1 - look)
		p.curve = (p.curve or 0) * (1 - look)
		if p.block then p.block.sd = (p.block.sd or 0) * (1 - 0.6 * look) end
	else
		local a = -look
		p.gridness = (p.gridness or 0.5) * (1 - 0.5 * a)
		p.jitter = (p.jitter or 0) * (1 + a)
		p.curve = (p.curve or 0) * (1 + a)
	end
	p.gridLook = look
end

--- "e=0.67,set=2,look=0.30,x=1.58/1.14" for the STYLE line.
function M.text(b)
	if b == nil then return "-" end
	return string.format("e=%.2f,set=%d,look=%.2f,x=%.2f/%.2f", b.e, b.setting, b.look, b.gridded, b.semi)
end

return M
