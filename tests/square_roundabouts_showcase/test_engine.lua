-- sc_engine with a fake api: generic param reading from the rep, transf numbers (+0, finite).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_showcase/"
local H = loadfile(here .. "helpers.lua", "t", _ENV)()
local config = ug_require "/showcase/sc_config.lua"
local engine = ug_require "/showcase/sc_engine.lua"

local function isNegZero(v) return v == 0 and 1 / v < 0 end

test("transf numbers: no -0 at any rotation, nil for NaN", function()
	local fp = H.fakeFp(100, 50, -0.0, 3)
	for _, rot in ipairs({ 0, 90, 180, 270, 45, 359.5 }) do
		local p = { rot = rot, ox = -0.0, oy = 0, x = 0, y = 0, fp = fp }
		local t = engine.transfNumbers(p, -0.0)
		eq(#t, 16)
		for i, v in ipairs(t) do ok(not isNegZero(v), "rot " .. rot .. " [" .. i .. "]") end
	end
	local t, err = engine.transfNumbers({ rot = 0, ox = 0 / 0, oy = 0, fp = fp }, 0)
	eq(t, nil)
	ok(err:find("finite"))
	eq(#engine.corners({ rot = 30, x = 1, y = 2, fp = fp }), 5)
end)

test("readEntry: params from the rep as the .con defines them, non-sqrb keys left out", function()
	local con = H.loadCon("square_roundabouts_highway_parclo.con.lua")
	local params = {}
	for i, p in ipairs(con.params) do params[i] = p end
	params[#params + 1] = { key = "height", values = { "0", "5" }, defaultIndex = 1 }
	set_global("api", { res = { constructionRep = {
		get = function(id) return { params = params, updateScript = con.updateScript, description = con.description } end,
	} } })
	local lines = {}
	local eng = engine.new(config.fromModParams({ sqrb_show_run = 2 }), function(l) lines[#lines + 1] = l end)
	local m = eng:readEntry(config.entryById("parclo"), "square_roundabouts::/x.con", 5)
	eq(#m.params, #con.params)
	eq(m.script, con.updateScript.fileName)
	eq(m.captureParams.types, con.updateScript.params.types)
	local text = table.concat(lines, "\n")
	ok(text:find("ENTRY", 1, true) and text:find("height", 1, true))
end)
