-- Better Auto Vehicle Renamer: the fleet register console command (bavr_console.lua): the REG lines (status of each
-- vehicle, sort order, the cap and its count line, numbers per letter, the summary), and reg() on a fake API reading
-- the saved state through state_native the way the GUI does. docs/console.md.

local Console = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_console.lua"
local Settings = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_settings.lua"
local Reg = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_register.lua"

local cfg = Settings.parse(nil)

local function grep(lines, pat)
	local n = 0
	for _, l in ipairs(lines) do
		if string.find(l, pat) then n = n + 1 end
	end
	return n
end

local function register()
	local st = Reg.new()
	st.welcome = "apply"
	-- B-0001 ours, B-0002 hand-typed, B-0003 pending, L-0001 ours; B-0004 sold (retired); a stale record
	local function rec(id, k, t, last, user)
		st.v[Reg.key(id)] = { k = k, t = t, a = t, li = 900, lp = t, last = last, user = user }
	end
	rec(10, "B", 1, "B-0001 | Citaro")
	rec(11, "B", 2, "B-0002 | Citaro", 1)
	rec(12, "B", 3, "B-0003 | Citaro")
	rec(20, "L", 1, "L-0001 | Class 101")
	rec(99, "B", 5, "B-0005 | Citaro") -- its vehicle is no longer listed
	st.nt = { B = 6, L = 2 }
	st.na = 6
	local vehicles = {
		{ id = 30, letter = "T", model = "Scania R", name = "Road Vehicle 30" }, -- untouched
		{ id = 20, letter = "L", model = "Class 101", line = "IC 5", name = "L-0001 | Class 101", parts = 9, wagons = 8 },
		{ id = 12, letter = "B", model = "Citaro", line = "Bus 12", name = "Road Vehicle 12" },
		{ id = 11, letter = "B", model = "Citaro", line = "Bus 12", name = "Pride of London", old = true },
		{ id = 10, letter = "B", model = "Citaro", line = "Bus 12", name = "B-0001 | Citaro", year = 1925 },
	}
	return st, vehicles
end

test("REG lines: one per vehicle with its numbers and status, sorted by letter and number, untouched last", function()
	local st, vehicles = register()
	local lines = Console.lines(st, vehicles, cfg)
	ok(lines[1]:find('^%[SQFN%] REG B%-0001 id=10 type=B t=1 a=1 m=%- lp=1 model="Citaro" year=1925 line="Bus 12" '
		.. 'status=ours old=no'), lines[1])
	ok(lines[2]:find("REG B%-0002 id=11 .* status=hand%-typed old=yes"), lines[2])
	ok(lines[3]:find("REG B%-0003 id=12 .* status=pending"), lines[3])
	ok(lines[4]:find("REG L%-0001 id=20 .* status=ours .* parts=9 wagons=8"), lines[4])
	ok(lines[5]:find('REG %- id=30 type=T .* status=untouched .* name="Road Vehicle 30"'), lines[5])
	eq(grep(lines, "REG numbers B next=6 held=4 retired=1"), 1, "B-0004 was given out and is gone")
	eq(grep(lines, "REG numbers L next=2 held=1 retired=0"), 1)
	eq(grep(lines, "REG summary vehicles=5 records=5 ours=2 pending=1 handTyped=1 untouched=1 stale=1 old=1 shown=5 "
		.. "welcome=apply"), 1, lines[#lines])
end)

test("REG cap: the first max vehicles, then one count line; the vehicle loop is capped", function()
	local st = Reg.new()
	local vehicles = {}
	for i = 1, 30 do
		Reg.create(st, cfg, i, "B", nil, i, 0)
		vehicles[i] = { id = i, letter = "B", name = "x" }
	end
	local lines = Console.lines(st, vehicles, cfg, 10)
	eq(grep(lines, "^%[SQFN%] REG B%-"), 10)
	eq(grep(lines, "REG %.%.%. 20 more vehicles not listed %(cap 10"), 1)
	eq(grep(lines, "shown=10"), 1)
	local old = Console.MAX_VEHICLES
	Console.MAX_VEHICLES = 5
	lines = Console.lines(st, vehicles, cfg, 100)
	Console.MAX_VEHICLES = old
	eq(grep(lines, "^%[SQFN%] REG B%-"), 5, "at most MAX_VEHICLES looked at")
	eq(#Console.lines(Reg.new(), {}, cfg), 1, "empty: the summary only")
end)

test("reg(): reads state_native (asTable) and the vehicles through the reader; prints the lines; errors are a line", function()
	local st, _ = register()
	-- state_native: find returns NativeLuaTable-like values for tables (asTable), as the engine does
	local function native(t)
		return setmetatable({}, { __index = {
			find = function(_, k)
				local x = t[k]
				if type(x) == "table" then return native(x) end
				return x
			end,
			asTable = function() return t end,
		} })
	end
	local comps = {
		[5] = { state_native = native(st) },
		[10] = { carrier = 0, state = 1, line = 900, transportVehicleConfig = { vehicles = {
			{ part = { modelId = 1 }, purchaseTime = 10 } } } },
	}
	local printed = {}
	set_global("print", function(s) printed[#printed + 1] = s end)
	set_global("api", {
		type = { ComponentType = { TRANSPORT_VEHICLE = 11, GAME_SCRIPT = 12, GAME_TIME = 13 }, enum = {} },
		engine = {
			system = { gameScriptSystem = { getEntityForGameScript = function() return 5 end } },
			config = { getModParams = function() return {} end },
			entityExists = function(id) return id == 10 or id == 900 end,
			getComponent = function(id, ct)
				if ct == 13 then return { gameTime = 1e12 } end
				return comps[id]
			end,
			getEntitiesWithComponent = function() return { 10 } end,
			util = {
				getPlayer = function() return 1 end,
				getWorld = function() return 1 end,
				getEntityName = function(id) return id == 900 and "Bus 12" or "B-0001 | Citaro" end,
				getCalendarDate = function() return { year = 1925 } end,
			},
		},
		res = { modelRep = {
			get = function() return { metadata = { description = { name = "Citaro" }, maintenance = { lifespan = 10 },
				transportVehicle = { compartments = {} }, landVehicle = { engines = { { power = 100 } } } } } end,
			getName = function() return "vehicle/bus/citaro.mdl" end,
		} },
	})
	local summary = Console.reg()
	ok(summary:find("REG summary vehicles=1 records=5 ours=1 .* stale=4 old=1"), summary)
	ok(printed[1]:find('REG B%-0001 id=10 .* model="Citaro" year=1925 line="Bus 12" status=ours old=yes'), printed[1])
	eq(printed[#printed], summary)
	-- no game script entity: one error line
	api.engine.system.gameScriptSystem.getEntityForGameScript = function() return -1 end
	printed = {}
	ok(Console.reg():find("REG error no game script entity"))
	eq(#printed, 1)
end)
