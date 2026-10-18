-- Line Manager Plus vehicle list name column weight (vehicle_columns.lua) with fake react / builtin.
-- Covers: install (wraps builtin.ColumnDesc once, keeps the previous wrapper in the chain, shims ReplaceRecipe), the
-- swap (only the VehicleName column gets weight NAME_WEIGHT, every other field kept, the caller's param unchanged;
-- other columns and malformed params pass through untouched; a failing ColumnDesc with our copy falls back).

local react, builtin, vcol, prevCalls, recipes

local function setup(opts)
	opts = opts or {}
	reset_modules()
	clear_logs()
	prevCalls = {}
	local names = {}
	react = { GetRecipeName = function(fn) return names[fn] end }
	recipes = {}
	for _i, n in ipairs({ "VehicleName", "VehicleIcon" }) do
		recipes[n] = function() return n end
		names[recipes[n]] = n
	end
	builtin = { ColumnDesc = function(...)
		prevCalls[#prevCalls + 1] = table.pack(...)
		if opts.failOurs and type((...)) == "table" and (...).weight ~= nil then error("column boom") end
		return { kind = "ColumnDesc", args = table.pack(...) }
	end }
	stub_module("::/gui/main/react.lua", react)
	stub_module("::/gui/main/builtin.lua", builtin)
	vcol = ug_require "square_line_manager_plus::/line_manager_plus/vehicle_columns.lua"
end

local function warnings()
	local n = 0
	for _i, e in ipairs(log_entries()) do if e.level == "warning" then n = n + 1 end end
	return n
end

test("install: wraps ColumnDesc once; a later ReplaceRecipe of our wrapper gets the wrapped one", function()
	setup()
	local before = builtin.ColumnDesc
	local calls = {}
	local r = { ReplaceRecipe = function(orig) calls[#calls + 1] = orig end }
	ok(vcol.install(r))
	local ours = builtin.ColumnDesc
	ok(ours ~= before)
	ok(vcol.install(r))
	ok(builtin.ColumnDesc == ours)
	r.ReplaceRecipe(ours)
	ok(calls[1] == before)
end)

test("swap: the name column gets the weight, other fields kept; other columns untouched", function()
	setup()
	vcol.install({})
	local p = { name = " ", recipe = recipes.VehicleName, getCompareValue = function() end }
	local got = builtin.ColumnDesc(p).args[1]
	ok(got ~= p)
	eq(got.weight, vcol.NAME_WEIGHT)
	ok(got.recipe == p.recipe); ok(got.getCompareValue == p.getCompareValue); eq(got.name, " ")
	eq(p.weight, nil) -- the caller's param unchanged
	local icon = { name = " ", recipe = recipes.VehicleIcon }
	ok(builtin.ColumnDesc(icon).args[1] == icon)
	ok(builtin.ColumnDesc("x").args[1] == "x")
	local two = builtin.ColumnDesc(p, "extra").args
	ok(two[1] == p); eq(two[2], "extra")
	eq(warnings(), 0)
end)

test("swap: a failing ColumnDesc with our copy falls back to the caller's param, logged once", function()
	setup({ failOurs = true })
	vcol.install({})
	local p = { name = " ", recipe = recipes.VehicleName }
	ok(builtin.ColumnDesc(p).args[1] == p)
	ok(builtin.ColumnDesc(p).args[1] == p)
	eq(warnings(), 1)
end)
