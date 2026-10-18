-- Organic Towns: "Starting town size" (pure). 2026-10-13, a TEST round: does the generator's town population factor
-- shrink a new map's starting town cores (fewer streets), or only their residents? mod.script.lua's preRunFn scales
-- baseConfig.locations.town.populationDensity ("Population will be scaled by this factor", api/type.d.tl TownParamList)
-- by the chosen factor. The base game's preRunFn sets that field from its own "Population" setting (advanced settings,
-- 50 % .. 200 %, base/content/base/mod.script.tl:200, difficulty_util level2IndustryProductivityFactor) before ours
-- runs, so ours multiplies the player's choice and keeps the other TownParamList fields.
--
-- Read from the game files only (unverified in game): the new-game page generates the map preview (towns included)
-- in the menu from its OWN locations config (gui/menu/new_game_or_map_settings_page.tl:402-421, from the base params
-- only) and app.startGame2 hands that map over; and the base "Population" setting can also be changed on a savegame
-- (advanced_settings.tl:416, outside `if not isSavegame`). Both hint that populationDensity is a runtime population
-- factor rather than a street-core size. The [SQOT] START lines (first load of a fresh map) answer it.
--
-- The head start scales up with a smaller choice (more rounds, larger increments) so small cores still reach a
-- size with character quickly; the lead limit and the map-edge margin still hold.

local M = {}

M.CHOICES = { "game", "smaller", "small" }   -- mod.json order
M.FACTOR = { game = nil, smaller = 0.6, small = 0.35 }
-- head start: + rounds (and the max), x edges per increment
M.HEAD = {
	game = { rounds = 0, edgesMul = 1 },
	smaller = { rounds = 1, edgesMul = 1.25 },
	small = { rounds = 2, edgesMul = 1.5 },
}

function M.factor(choice)
	return M.FACTOR[choice]
end

function M.head(choice)
	return M.HEAD[choice] or M.HEAD.game
end

local function txt(v)
	if type(v) == "number" then return string.format("%.4g", v) end
	return (tostring(v):gsub("%s+", "_"))
end

--- Scales baseConfig.locations.town.populationDensity for `choice` (preRunFn). "game" (and unknown) leaves baseConfig
--- untouched (not even read-written). Returns { choice, factor, from, to, applied, err }.
function M.apply(baseConfig, choice)
	local out = { choice = choice, factor = M.FACTOR[choice], applied = false }
	local okR, from = pcall(function() return baseConfig.locations.town.populationDensity end)
	out.from = okR and tonumber(from) or nil
	if not okR then out.err = "read:" .. txt(from) end
	if out.factor == nil then
		out.to = out.from
		return out
	end
	if out.from == nil then
		out.err = out.err or "noValue"
		return out
	end
	local to = out.from * out.factor
	local okW, err = pcall(function() baseConfig.locations.town.populationDensity = to end)
	if not okW then
		out.err = "write:" .. txt(err)
		out.to = out.from
		return out
	end
	local okB, back = pcall(function() return baseConfig.locations.town.populationDensity end)
	out.to = okB and tonumber(back) or to
	out.applied = true
	return out
end

--- The [SQOT] TOWNSIZE line's fields for an apply() result.
function M.fields(r, where)
	return {
		{ "where", where or "preRunFn" }, { "choice", r.choice or "-" }, { "factor", r.factor or 1 },
		{ "populationDensity", txt(r.from or "nil") .. "->" .. txt(r.to or "nil") }, { "applied", r.applied == true },
		{ "err", r.err or "-" }, { "note", "newMapGeneratorUnverified" },
	}
end

--- "[SQOT] WHAT k=v ..." (mod.script.lua has no driver loaded).
function M.line(what, fields)
	local parts = { "[SQOT]", what }
	for _, f in ipairs(fields or {}) do
		local v = f[2]
		if type(v) == "number" then v = txt(v) end
		parts[#parts + 1] = f[1] .. "=" .. txt(v)
	end
	return table.concat(parts, " ")
end

local function median(list)
	local n = #list
	if n == 0 then return 0 end
	local c = {}
	for i = 1, n do c[i] = list[i] end
	table.sort(c)
	if n % 2 == 1 then return c[(n + 1) / 2] end
	return (c[n / 2] + c[n / 2 + 1]) / 2
end

--- Summary of the START rows { {buildings, edges, length, cap} }: { towns, buildings = {mean, median}, edges, length,
--- cap }.
function M.summary(rows)
	local out = { towns = #rows }
	for _, k in ipairs({ "buildings", "edges", "length", "cap" }) do
		local list, sum = {}, 0
		for _, r in ipairs(rows) do
			local v = tonumber(r[k]) or 0
			list[#list + 1] = v
			sum = sum + v
		end
		out[k] = { mean = #list > 0 and sum / #list or 0, median = median(list) }
	end
	return out
end

--- The START summary line's fields.
function M.summaryFields(s, choice)
	local f = { { "towns", s.towns }, { "townSize", choice or "-" } }
	for _, k in ipairs({ "buildings", "edges", "length", "cap" }) do
		f[#f + 1] = { k, string.format("mean%.0f/median%.0f", s[k].mean, s[k].median) }
	end
	return f
end

return M
