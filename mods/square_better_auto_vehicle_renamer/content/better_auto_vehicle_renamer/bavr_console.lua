-- Better Auto Vehicle Renamer: the fleet register as console lines (docs/console.md "Our mods' console helpers").
-- Paste the whole line in the in-game console:
--   ug_require("square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_console.lua").reg()
--   ug_require("square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_console.lua").reg(2000)
-- It prints "[SQFN] REG ..." lines (stdout.txt: `make logs-grep PAT='\[SQFN\] REG' ARGS='--session live'`): one per
-- vehicle (the first MAX_SHOWN, or the number passed; then a count line), sorted by type letter and fleet number,
-- untouched vehicles last; then one line per type letter with its numbers (next, held, retired) and a summary.
-- Read-only: it reads the game script's saved state the way the GUI does (getEntityForGameScript + GAME_SCRIPT
-- .state_native:find(...):asTable(), docs/findings/game-scripts.md; never state:get_native) and the vehicles through
-- the game script's own reader (bavr_reader.lua). A console ug_require gets its own module copy, so nothing of the
-- running game script is shared (docs/console.md).
--
-- Entry points:
--   Console.reg([max]) -> the summary line (the per-vehicle lines are printed)
--   Console.lines(st, vehicles, cfg, max) -> array of lines (pure; tests): st = { v, nt, na, welcome, pass, standDown,
--       cutoff }, vehicles = array of { id, letter, model, year, line, name, old, parts, wagons } (letter nil: a type
--       the mod does not know), cfg from Settings.parse.
-- Vehicle status: ours (the name we set), pending (numbered, its fleet name not arrived yet: budget or a new input),
-- hand-typed (the player's own name, kept), untouched (no record: "Not now", a type switched off, or before the
-- welcome answer). Records whose vehicle is no longer listed are counted as stale (pruned within a cycle).

local Settings = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_settings.lua"
local Reg = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_register.lua"
local Text = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_text.lua"
local Classify = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_classify.lua"

local M = {}

M.TAG = "[SQFN] REG"
M.MAX_SHOWN = 500        -- vehicle lines printed by default
M.MAX_VEHICLES = 100000  -- loop cap on the vehicle list (= the sweep's MAX_LIST)
M.LETTER_RANK = { B = 1, T = 2, R = 3, L = 4, S = 5, A = 6, H = 7 }

local function q(s)
	if s == nil then return "-" end
	return '"' .. string.gsub(tostring(s), '"', "'") .. '"'
end

local function statusOf(rec, name)
	if rec == nil then return "untouched" end
	if rec.user == 1 then return "hand-typed" end
	if rec.last ~= nil and name == rec.last then return "ours" end
	return "pending"
end

function M.lines(st, vehicles, cfg, max)
	max = tonumber(max) or M.MAX_SHOWN
	if max < 0 then max = 0 end
	local v = type(st) == "table" and type(st.v) == "table" and st.v or {}
	local n = #vehicles
	if n > M.MAX_VEHICLES then n = M.MAX_VEHICLES end
	-- sort: type letter, then the per-type fleet number, untouched last (by id)
	local order = {}
	for i = 1, n do order[i] = i end
	local recOf, listed = {}, {}
	for i = 1, n do
		local id = vehicles[i].id
		recOf[i] = v[Reg.key(id)]
		listed[Reg.key(id)] = true
	end
	table.sort(order, function(x, y)
		local rx, ry = recOf[x], recOf[y]
		if (rx == nil) ~= (ry == nil) then return rx ~= nil end
		local lx = M.LETTER_RANK[(rx and rx.k) or vehicles[x].letter] or 9
		local ly = M.LETTER_RANK[(ry and ry.k) or vehicles[y].letter] or 9
		if lx ~= ly then return lx < ly end
		if rx ~= nil and rx.t ~= ry.t then return (rx.t or 0) < (ry.t or 0) end
		return vehicles[x].id < vehicles[y].id
	end)
	local out = {}
	local counts = { ours = 0, pending = 0, ["hand-typed"] = 0, untouched = 0 }
	local oldN = 0
	for j = 1, n do
		local i = order[j]
		local veh, rec = vehicles[i], recOf[i]
		local status = statusOf(rec, veh.name)
		counts[status] = counts[status] + 1
		if veh.old then oldN = oldN + 1 end
		if j <= max then
			local letter = (rec and rec.k) or veh.letter or "?"
			local no = rec and (letter .. "-" .. Text.number(rec.t or 0, 4)) or "-"
			out[#out + 1] = string.format("%s %s id=%s type=%s t=%s a=%s m=%s lp=%s model=%s year=%s line=%s status=%s "
				.. "old=%s parts=%s wagons=%s name=%s", M.TAG, no, tostring(veh.id), letter, tostring(rec and rec.t or "-"),
				tostring(rec and rec.a or "-"), tostring(rec and rec.m or "-"), tostring(rec and rec.lp or "-"), q(veh.model),
				tostring(veh.year or "-"), q(veh.line), status, veh.old and "yes" or "no", tostring(veh.parts or "-"),
				tostring(veh.wagons or "-"), q(veh.name))
		end
	end
	if n > max then
		out[#out + 1] = string.format("%s ... %d more vehicles not listed (cap %d; pass a larger number: .reg(%d))", M.TAG,
			n - max, max, n)
	end
	-- numbers per type letter: next to give, held by a record, retired (given out and no longer held: sold)
	local held, stale, records = {}, 0, 0
	for k, rec in pairs(v) do
		records = records + 1
		if records > Reg.MAX_RECORDS then break end
		if type(rec) == "table" and rec.k ~= nil then held[rec.k] = (held[rec.k] or 0) + 1 end
		if not listed[k] then stale = stale + 1 end
	end
	local start = cfg.start or 1
	local nt = type(st) == "table" and type(st.nt) == "table" and st.nt or {}
	for _, l in ipairs(Settings.LETTERS) do
		local nx = tonumber(nt[l])
		if nx ~= nil or held[l] ~= nil then
			local given = nx and math.max(0, nx - start) or 0
			out[#out + 1] = string.format("%s numbers %s next=%s held=%d retired=%d", M.TAG, l, tostring(nx or start),
				held[l] or 0, math.max(0, given - (held[l] or 0)))
		end
	end
	out[#out + 1] = string.format("%s summary vehicles=%d records=%d ours=%d pending=%d handTyped=%d untouched=%d "
		.. "stale=%d old=%d shown=%d welcome=%s pass=%s standDown=%s counter=%s nextAll=%s", M.TAG, n, records,
		counts.ours, counts.pending, counts["hand-typed"], counts.untouched, stale, oldN, math.min(n, max),
		tostring(type(st) == "table" and st.welcome or nil), tostring(type(st) == "table" and st.pass ~= nil),
		tostring(type(st) == "table" and st.standDown or nil), tostring(cfg.counter),
		tostring(type(st) == "table" and st.na or nil))
	return out
end

-- a NativeLuaTable (state_native) as a plain table; plain tables and other values as they are
local function plain(x)
	if x == nil then return nil end
	local okF, f = pcall(function() return x.asTable end)
	if okF and type(f) == "function" then
		local ok, t = pcall(f, x)
		if ok and type(t) == "table" then return t end
	end
	return x
end

--- The saved state's fields this needs (state_native, as the GUI reads it), or nil and a reason.
function M.savedState(gsName)
	local e = api.engine.system.gameScriptSystem.getEntityForGameScript(gsName)
	if e == nil or e < 0 then return nil, "no game script entity" end
	local gs = api.engine.getComponent(e, api.type.ComponentType.GAME_SCRIPT)
	if gs == nil or gs.state_native == nil then return nil, "no game script state" end
	local native = gs.state_native
	local st = { v = {}, nt = plain(native:find("nt")) or {}, na = native:find("na"), welcome = native:find("welcome"),
		pass = native:find("pass") ~= nil and {} or nil, standDown = native:find("standDown") }
	local v = plain(native:find("v"))
	if type(v) == "table" then
		local walked = 0
		for k, rec in pairs(v) do
			walked = walked + 1
			if walked > Reg.MAX_RECORDS then break end
			local r = plain(rec)
			if type(r) == "table" then st.v[tostring(k)] = r end
		end
	end
	if type(st.nt) ~= "table" then st.nt = {} end
	return st
end

local function body(max)
	local Reader = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_reader.lua"
	local Game = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_game.lua"
	local okP, all = pcall(function() return api.engine.config.getModParams() end)
	local cfg = Settings.parse(okP and type(all) == "table" and all[Settings.MOD_ID] or nil)
	local st, why = M.savedState(Game.GS_NAME)
	if st == nil then return { M.TAG .. " error " .. tostring(why) } end
	local r = Reader.new(api)
	r.wantYear, r.wantParts = true, true
	local now = nil
	pcall(function()
		now = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
	end)
	local ids = r.list()
	if ids == nil then return { M.TAG .. " error the vehicle list could not be read" } end -- i18n: ignore
	local vehicles, buf, models = {}, {}, {}
	local n = math.min(#ids, M.MAX_VEHICLES)
	for i = 1, n do
		for k in pairs(buf) do buf[k] = nil end
		local id = ids[i]
		if r.read(id, buf) then
			local mi = models[buf.model]
			if mi == nil and buf.model ~= nil then
				mi = r.modelInfo(buf.model) or false
				models[buf.model] = mi
			end
			local line = buf.line and r.lineName(buf.line) or nil
			vehicles[#vehicles + 1] = { id = id, letter = Classify.letter(buf.carrier, mi and mi.pax, mi and mi.heli),
				model = mi and mi.name or nil, year = buf.year, line = line, name = buf.name,
				old = buf.exp ~= nil and now ~= nil and now >= buf.exp, parts = buf.parts, wagons = buf.wagons }
		end
	end
	return M.lines(st, vehicles, cfg, max)
end

--- Console: print the fleet register (see the header). Returns the summary line.
function M.reg(max)
	local ok, lines = pcall(body, max)
	if not ok then lines = { M.TAG .. " error " .. tostring(lines) } end
	for i = 1, #lines do print(lines[i]) end
	return lines[#lines]
end

return M
