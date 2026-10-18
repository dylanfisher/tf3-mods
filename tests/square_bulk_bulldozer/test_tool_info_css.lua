-- Shared tool info style (docs/ui-guide.md "Construction toolbar"): Smart Lanes and Bulk Bulldozer
-- ship the same 4-rule block under the class "sq-tool-info"; only the first active mod of the
-- list adds it (mod stylesheet rules are capped, docs/findings.md). Offline: every combination of
-- active mods gives exactly 4 rules, and both blocks stay identical except ME.
-- (Identical copy in tests/square_smart_lanes/ and tests/square_bulk_bulldozer/.)

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/"
local SHEETS = {
	square_smart_lanes = here .. "../../mods/square_smart_lanes/content/smart_lanes/sl_tool.css.lua",
	square_bulk_bulldozer = here .. "../../mods/square_bulk_bulldozer/content/bulk_bulldozer/bulk_bulldozer.css.lua",
}
local ORDER = { "square_smart_lanes", "square_bulk_bulldozer" }

-- Run one stylesheet's data() with the given mods active; returns its selector parts.
local function rules(modId, active)
	local parts = {}
	local res = { "default_colors" }
	local env = setmetatable({
		log = { message = function() end },
		require = function(name)
			assert(name:find("stylesheetutil"), name)
			return { makeAdder = function(result) return function(sel, props)
				for p in sel:gmatch("[^,]+") do parts[#parts + 1] = p:match("^%s*(.-)%s*$") end
				result[#result + 1] = { sel, props }
			end end }
		end,
		api = { gui = { genericRep = {
			find = function(path)
				local owner = path:match("^(.-)::/square_tool_info/marker%.gres$")
				if owner ~= nil then return active[owner] and 7 or -1 end
				return 1
			end,
			get = function(id)
				if id == 7 then return { data = { squareToolInfo = true } } end
				return { data = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }) }
			end,
		} } },
	}, { __index = _ENV })
	assert(loadfile(SHEETS[modId], "t", env))()
	env.data()
	return parts
end

test("exactly one copy of the 4 rules for every set of active tools", function()
	for mask = 1, 3 do
		local active, total = {}, 0
		for i, m in ipairs(ORDER) do active[m] = (mask >> (i - 1)) & 1 == 1 end
		for _, m in ipairs(ORDER) do
			if active[m] then total = total + #rules(m, active) end
		end
		eq(total, 4, "mask " .. mask)
	end
end)

test("rules are scoped under the dashed class sq-tool-info", function()
	for _, p in ipairs(rules("square_bulk_bulldozer", { square_bulk_bulldozer = true })) do
		ok(p:find("^R::Component!sq%-tool%-info ") ~= nil, p)
	end
end)

test("the shared block is identical in both stylesheets except ME", function()
	local function block(path)
		local f = assert(io.open(path, "r"))
		local s = f:read("a")
		f:close()
		local b = assert(s:match("(%-%- TOOL INFO STYLE.*)"), path)
		return (b:gsub('local ME = "[%w_]+"', 'local ME = ?'))
	end
	eq(block(SHEETS.square_smart_lanes), block(SHEETS.square_bulk_bulldozer))
end)
