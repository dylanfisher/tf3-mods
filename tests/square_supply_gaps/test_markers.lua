-- sg_markers: marker lifecycle against a fake api.gui.mission (keys, diff, kinds, clearAll, forget,
-- pcall around failing engine calls). API shape: api/tealdef/api/gui.d.tl:685-745.

local markers = ug_require "square_supply_gaps::/supply_gaps/sg_markers.tl"

local calls, failOn

local function fakeApi()
	calls = {}
	local function rec(name)
		return function(...)
			local args = { ... }
			calls[#calls + 1] = { name, args[1], args[3] }
			if failOn and failOn(name, args) then error("boom " .. name) end
		end
	end
	return {
		gui = { mission = {
			setMarkerAtEntity = rec("set"), removeMarker = rec("remove"),
		} },
	}
end

local function names(kind)
	local out = {}
	for _, c in ipairs(calls) do if c[1] == kind then out[#out + 1] = c[2] end end
	return out
end

before_each(function()
	set_global("api", fakeApi())
	failOn = nil
	markers.shown, markers.typeOf = {}, {}
	clear_logs()
end)

test("apply sets a keyed marker per entity", function()
	local st = markers.apply({ 5, 3 })
	eq(names("set"), { "sqsg:5", "sqsg:3" })
	eq(st.added, 2)
	eq(st.shown, 2)
	eq(calls[1][3], "arrow")
end)

test("apply diffs: only new ones set, gone ones removed", function()
	markers.apply({ 1, 2, 3 })
	calls = {}
	local st = markers.apply({ 2, 3, 4 })
	eq(names("remove"), { "sqsg:1" })
	eq(names("set"), { "sqsg:4" })
	eq(st.added, 1)
	eq(st.removed, 1)
	eq(st.shown, 3)
end)

test("unchanged set sends nothing", function()
	markers.apply({ 1, 2 })
	calls = {}
	markers.apply({ 2, 1 })
	eq(#calls, 0)
end)

test("clearAll removes every marker of ours", function()
	markers.apply({ 7, 8 })
	calls = {}
	local st = markers.clearAll()
	eq(names("remove"), { "sqsg:7", "sqsg:8" })
	eq(st.removed, 2)
	eq(next(markers.shown), nil)
end)

test("a failing set is counted, not shown, and logged as ERR", function()
	failOn = function(name, args) return name == "set" and args[2] == 2 end
	local st = markers.apply({ 2, 3 })
	eq(st.errors, 1)
	eq(st.shown, 1)
	ok(markers.shown[2] == nil)
	local found = false
	for _, e in ipairs(log_entries()) do
		if e.msg:find("[SQSG] ERR marker 2 ", 1, true) then found = true end
	end
	ok(found, "ERR line logged")
end)

test("forget drops our bookkeeping without engine calls", function()
	markers.apply({ 1, 2 })
	calls = {}
	eq(markers.forget(), 2)
	eq(#calls, 0)
	eq(next(markers.shown), nil)
end)

test("kinds: starved -> TYPE_STARVED, unreached -> TYPE; a kind change removes and re-sets", function()
	markers.apply({ 1, 2 }, { [1] = "unreached", [2] = "starved" })
	local types = {}
	for _, c in ipairs(calls) do if c[1] == "set" then types[c[2]] = c[3] end end
	eq(types, { ["sqsg:1"] = "arrow", ["sqsg:2"] = "question_red" })
	calls = {}
	local st = markers.apply({ 1, 2 }, { [1] = "starved", [2] = "starved" })
	eq(names("remove"), { "sqsg:1" })
	eq(names("set"), { "sqsg:1" })
	eq(calls[#calls][3], "question_red")
	eq(st.retyped, 1)
	eq(st.added, 1)
	eq(st.shown, 2)
	calls = {}
	markers.apply({ 1, 2 }, { [1] = "starved", [2] = "starved" })
	eq(#calls, 0)
end)
