-- Line Manager Plus: the Line Manager's "Show Only Visible Lines" remembered across loads and followed by the Send to
-- Line popover (lmp_visible.lua), with fake react / popover / manager / statistics modules and fake GUI save data.
-- Covers: install (wraps the three fields once, shims ReplaceRecipe, builtin.ToggleButton never touched, a missing
-- popover leaves the Line Manager pair installed), the settings (read once from getGuiSaveData, written whole
-- with setGuiSaveData only on a change, malformed data ignored, a broken API logged once), the Line Manager (the stored value goes into lvmFilterStateRef
-- once per load, before the content; the filter bar's eye is recorded, category clicks and the Statistics window's
-- filter are not), the Send to Line popover (nothing remembered or the same value: untouched; the Line Manager's value
-- goes in on a copy, the caller's tables unchanged; follows a click in this game; other popovers pass through) and
-- errors while deciding (pass through, logged once).

local react, builtin, pop, mw, sru, vis, popCalls, current, names, RAPI_CALLS, saveData, saves

local function setup(opts)
	opts = opts or {}
	reset_modules()
	clear_logs()
	popCalls, names, RAPI_CALLS, saves = {}, {}, {}, 0
	current = "SendToLineSelection"
	saveData = { other_mod = { x = 1 }, square_line_manager_plus = opts.stored }
	set_global("api", {
		gui = { game = {
			getGuiSaveData = function(modId)
				if opts.brokenSave then error("no save data") end
				return saveData[modId]
			end,
			setGuiSaveData = function(modId, data)
				if opts.brokenSave then error("no save data") end
				saveData[modId] = data
				saves = saves + 1
			end,
		} },
	})
	react = {
		GetRecipeName = function(fn) return names[fn] end,
		getCurrentRecipeName = function() return current end,
	}
	builtin = { ToggleButton = function() end }
	pop = {}
	if opts.noPop ~= true then
		pop.PopoverWindowContent = function(...)
			popCalls[#popCalls + 1] = table.pack(...)
			return { kind = "PopoverWindowContent", args = table.pack(...) }
		end
	end
	mw = { ManagerWindowContent = function(...) return { kind = "ManagerWindowContent", args = table.pack(...) } end }
	sru = { createCarrierCategoryFilter = function(...) return { kind = "Filter", args = table.pack(...) } end }
	stub_module("::/gui/main/react.lua", react)
	stub_module("::/gui/main/builtin.lua", builtin)
	stub_module("::/gui/main/popover_react_util.tl", pop)
	stub_module("::/gui/line_vehicle_mgmt/manager_window.tl", mw)
	stub_module("::/gui/statistics/statistics_react_util.tl", sru)
	vis = ug_require "square_line_manager_plus::/line_manager_plus/lmp_visible.lua"
end

local function stored() return saveData.square_line_manager_plus end

local function recipe(name)
	local r = function() end
	names[r] = name
	return r
end

local function rapi()
	return { ReplaceRecipe = function(orig, repl) RAPI_CALLS[#RAPI_CALLS + 1] = { orig = orig, repl = repl } end }
end

local function warnings(text)
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if e.level == "warning" and (text == nil or e.msg:find(text, 1, true)) then n = n + 1 end
	end
	return n
end

-- the Send to Line PopoverWindow param (manager_window.tl:7336-7366 shape)
local function stl(onlyVisible)
	return {
		meta = { forceFocusable = true },
		onClose = function() end,
		recipe = recipe("SendToLineSelection"),
		params = { selection = { 21 }, commonParams = {}, onlyVisible = onlyVisible == true },
	}
end

-- the Line Manager: ManagerWindowContent's payload with ManagerEntryPoint's filter ref (:8349-8353)
local function payload(onlyVisible)
	local ref = { v = { category = {}, search = "", onlyVisible = onlyVisible == true }, sets = 0 }
	function ref:get() return self.v end
	function ref:set(v) self.v = v; self.sets = self.sets + 1 end
	return { toolParam = { lvmFilterStateRef = ref } }, ref
end

-- the Line Manager's filter bar (LineManagerActionButtons, :1767-1789): a fake filter state and the transformState
-- that reached the vanilla createCarrierCategoryFilter
local function filterBar(statsType)
	local state = { v = { category = {}, onlyVisible = false } }
	local transform = function(fn) state.v = fn(state.v) end
	local node = sru.createCarrierCategoryFilter({}, statsType or "Lines", function() return state.v end, transform)
	return state, node.args[4], transform
end

local function eyeClick(t, val)
	t(function(cur) local r = { category = cur.category, onlyVisible = val }; return r end)
end

-- install ------------------------------------------------------------------------------------------------------------

test("install: wraps the three fields once, shims ReplaceRecipe; builtin.ToggleButton untouched", function()
	setup()
	local toggle = builtin.ToggleButton
	local before = { pop.PopoverWindowContent, mw.ManagerWindowContent, sru.createCarrierCategoryFilter }
	local r = rapi()
	ok(vis.install(r))
	ok(vis.install(r))
	local after = { pop.PopoverWindowContent, mw.ManagerWindowContent, sru.createCarrierCategoryFilter }
	for i = 1, 3 do
		ok(after[i] ~= before[i], "field " .. i)
		r.ReplaceRecipe(after[i], "x")
		ok(RAPI_CALLS[i].orig == before[i], "field " .. i)
	end
	ok(builtin.ToggleButton == toggle)
	eq(warnings(), 0)
end)

test("install: a missing popover field leaves Send to Line alone, the Line Manager pair still installs", function()
	setup({ noPop = true })
	local prevMw = mw.ManagerWindowContent
	ok(vis.install(rapi()))
	eq(pop.PopoverWindowContent, nil)
	ok(mw.ManagerWindowContent ~= prevMw)
	eq(warnings("[LineManagerPlus] visible lines: install stl"), 1)
end)

-- settings -----------------------------------------------------------------------------------------------------------

test("settings: read once; written only on a change, under our modId only", function()
	setup({ stored = { lineManager = true } })
	eq(vis.get("lineManager"), true)
	vis.set("lineManager", true)
	eq(saves, 0)
	vis.set("lineManager", false)
	eq(saves, 1)
	eq(stored().lineManager, false)
	eq(saveData.other_mod.x, 1)
end)

test("settings: malformed save data is ignored", function()
	setup({ stored = { lineManager = "yes" } })
	eq(vis.get("lineManager"), nil)
	setup({ stored = 42 })
	eq(vis.get("lineManager"), nil)
	eq(warnings("[LineManagerPlus] visible lines: load settings"), 0)
end)

test("settings: a broken save data API is logged once each way and remembers for the session", function()
	setup({ brokenSave = true })
	eq(vis.get("lineManager"), nil)
	vis.set("lineManager", true)
	vis.set("lineManager", false)
	eq(vis.get("lineManager"), false)
	eq(warnings("[LineManagerPlus] visible lines: load settings"), 1)
	eq(warnings("[LineManagerPlus] visible lines: save settings"), 1)
end)

-- Send to Line -------------------------------------------------------------------------------------------------------

test("send to line popover: nothing remembered or the same value leaves the param untouched", function()
	setup()
	vis.install(rapi())
	local p = stl(false)
	ok(pop.PopoverWindowContent(p).args[1] == p)
	setup({ stored = { lineManager = false } })
	vis.install(rapi())
	ok(pop.PopoverWindowContent(p).args[1] == p)
end)

test("send to line popover: the Line Manager's stored value goes in on a copy; the caller unchanged", function()
	setup({ stored = { lineManager = true } })
	vis.install(rapi())
	local p = stl(false)
	local q = pop.PopoverWindowContent(p).args[1]
	eq(#popCalls, 1)
	ok(q ~= p and q.params ~= p.params)
	eq(q.params.onlyVisible, true)
	ok(q.recipe == p.recipe and q.onClose == p.onClose and q.meta == p.meta)
	ok(q.params.selection == p.params.selection and q.params.commonParams == p.params.commonParams)
	eq(p.params.onlyVisible, false)
	-- the player turns the Line Manager's eye off in this game: the next popover follows
	current = "LineManagerActionButtons"
	local _s, t = filterBar()
	eyeClick(t, true)
	eyeClick(t, false)
	eq(pop.PopoverWindowContent(stl(true)).args[1].params.onlyVisible, false)
end)

test("send to line popover: other popovers, a ref argument and malformed params pass through untouched", function()
	setup({ stored = { lineManager = true } })
	vis.install(rapi())
	local term = stl(false)
	term.recipe = recipe("TerminalSelection")
	local noParams = stl(false)
	noParams.params = nil
	for i, args in ipairs({ { term }, { noParams }, { "ref", stl(false) }, { "notatable" } }) do
		local node = pop.PopoverWindowContent(table.unpack(args))
		eq(node.args.n, #args, "case " .. i)
		for j = 1, #args do ok(node.args[j] == args[j], "case " .. i) end
	end
	eq(warnings(), 0)
end)

-- Line Manager -------------------------------------------------------------------------------------------------------

test("line manager: the stored value goes into the filter ref once per load, before the content", function()
	setup({ stored = { lineManager = true } })
	vis.install(rapi())
	local p, ref = payload(false)
	local node = mw.ManagerWindowContent(p)
	ok(node.args[1] == p)
	eq(ref:get().onlyVisible, true)
	eq(ref:get().search, "")
	eq(ref.sets, 1)
	-- the player turns it off in this game: later renders keep the game's value
	ref.v.onlyVisible = false
	mw.ManagerWindowContent(p)
	eq(ref:get().onlyVisible, false)
	eq(ref.sets, 1)
end)

test("line manager: nothing stored or the same value leaves the ref alone", function()
	setup()
	vis.install(rapi())
	local p, ref = payload(false)
	mw.ManagerWindowContent(p)
	eq(ref.sets, 0)
	setup({ stored = { lineManager = true } })
	vis.install(rapi())
	p, ref = payload(true)
	mw.ManagerWindowContent(p)
	eq(ref.sets, 0)
end)

test("line manager filter bar: the eye is recorded; category clicks write nothing", function()
	setup()
	vis.install(rapi())
	current = "LineManagerActionButtons"
	local state, t = filterBar()
	t(function(cur) return { category = { true }, onlyVisible = cur.onlyVisible } end)
	eq(saves, 0)
	eyeClick(t, true)
	eq(state.v.onlyVisible, true)
	eq(stored().lineManager, true)
	eyeClick(t, false)
	eq(stored().lineManager, false)
	eq(saves, 2)
end)

test("line manager filter bar: the Statistics window and other stats types pass through untouched", function()
	setup()
	vis.install(rapi())
	current = "StatisticsWindow"
	local _s, t, orig = filterBar()
	ok(t == orig)
	current = "LineManagerActionButtons"
	_s, t, orig = filterBar("Vehicles")
	ok(t == orig)
end)

test("errors while deciding pass through untouched and warn once each", function()
	setup({ stored = { lineManager = true } })
	vis.install(rapi())
	react.GetRecipeName = function() error("no names") end
	for _i = 1, 3 do
		local p = stl(false)
		ok(pop.PopoverWindowContent(p).args[1] == p)
	end
	eq(warnings("[LineManagerPlus] visible lines: popover"), 1)
	-- a payload without toolParam: logged, the content still renders
	local node = mw.ManagerWindowContent({})
	eq(node.kind, "ManagerWindowContent")
	eq(warnings("[LineManagerPlus] visible lines: line manager"), 1)
end)
