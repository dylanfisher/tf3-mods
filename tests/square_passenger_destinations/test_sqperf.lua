-- SQPERF wiring of paxdest_eow.script.tl (plans/sqperf/README.md): the wrapped plugin renders, scans and
-- LayerConfig still behave the same, the 30 s summary (Debug: performance log On) lists them, and the
-- per-refresh "[PaxDest] refresh" diagnostics line is only written with that setting On. Base GUI
-- modules and the engine API are faked; the engine world is empty (a person without data).
-- run_tests: no-split (each test reloads the module; the fakes record per test)

local MOD = "square_passenger_destinations"
local PATH = MOD .. "::/passenger_destinations/gui/paxdest_eow.script.tl"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_passenger_destinations/"
local MOD_ROOT = here .. "../../mods/square_passenger_destinations/"

local F -- per-test fakes and records

local function widget(name)
	return function(p) return { w = name, p = p } end
end

local function find(node, pred)
	if type(node) ~= "table" then return nil end
	if node.w ~= nil and pred(node) then return node end
	if node.p == nil then return nil end
	for _, child in ipairs(node.p.children or node.p.extraChildrenPermanent or {}) do
		local hit = find(child, pred)
		if hit then return hit end
	end
	if node.p.child then return find(node.p.child, pred) end
	return nil
end

local function newState(v)
	local s = { v = v }
	function s:old() return self.v end
	function s:set(x) self.v = x end
	function s:hasExpired() return false end
	return s
end

local function stubs()
	stub_module("::/gui/main/react.lua", {
		RegisterRecipe = function(_name, fn) return fn end,
		RegisterPluginRecipe = function(_ext, _name, fn) return fn end,
		RegisterTool = function(def) return def end,
		useRefLazy = function(init)
			local r = { v = init() }
			function r:get() return self.v end
			return r
		end,
		useState = function(v) return newState(v) end,
		onUnmount = function() end,
		onStepTimer = function() end,
		enqueueJoin = function(fn) fn() end,
	})
	stub_module("::/gui/main/builtin.lua", {
		TextView = widget("TextView"), BoxLayout = widget("BoxLayout"), CheckBox = widget("CheckBox"),
		Component = widget("Component"),
		type = { Orientation = { Horizontal = "H", Vertical = "V" } },
	})
	stub_module("::/gui/main/color_util.tl", { toArray4 = function(c) return c end })
	stub_module("::/gui/main/content_card.tl", { ContentCard = widget("ContentCard") })
	-- the poll runs once at mount (as the first useStepStateTimer call does) and again on F.tick()
	stub_module("::/gui/main/engine_react_util.tl", {
		useStepStateTimer = function(fn)
			local s = newState(fn())
			F.polls[#F.polls + 1] = function() s:set(fn()) end
			return s
		end,
	})
	stub_module("::/gui/main/game_react_globals.tl", {
		getDefaultToolStackApi = function()
			return {
				push = function(_tool, _key, param) F.pushed = param end,
				pop = function() F.pushed = nil end,
			}
		end,
	})
	stub_module("::/scripts/lang_util.tl", { format = function(s, args)
		return (s:gsub("{(%w+)}", function(k) return tostring(args[k]) end))
	end })
	stub_module("::/gui/main/styleutil.tl", { makeStyle = function(t) return t end })
	stub_module("::/gui/main/selector_react_util.tl", {
		makeDefaultSelectorAction = function(_ctx, layerConfig)
			F.layerConfig = layerConfig
			return function() return "action" end
		end,
	})
	stub_module("::/gui/entity_window/station_group/station_group_eow.script.tl", { StationGroupEowExtensionPoint = "sg" })
	stub_module("::/gui/entity_window/sim_person/sim_person_eow.script.tl", { SimPersonEowExtensionPoint = "sp" })
end

local function load(sqperfLog)
	F = { polls = {}, clockUs = 1e9 }
	clear_logs()
	stubs()
	set_global("api", {
		type = {
			Clock = { new = function() return { getTime = function() return F.clockUs end } end },
			ComponentType = setmetatable({}, { __index = function(_, k) return k end }),
			LayerConfig = { new = function() return { layerConfig = true } end },
		},
		engine = {
			getComponent = function() return nil end,
			config = { getModParams = function() return { [MOD] = { sqperf_log = sqperfLog } } end },
		},
		res = { cargoTypeRep = { getPassengerCargoTypeId = function() return 0 end } },
	})
	reset_modules()
	return ug_require(PATH)
end

local function lines(pattern)
	local out = {}
	for _, e in ipairs(log_entries()) do
		if e.msg:find(pattern, 1, true) then out[#out + 1] = e.msg end
	end
	return out
end

-- Person window: render, tick "Show destination", run the pushed tool's action (its poll logs the
-- refresh line), a second render 31 s later closes the SQPERF window.
local function personSession(m)
	local card = m.PaxDestPersonPlugin({ entityId = 7, gameCtx = {}, showCalloutOnRightSide = false })
	local box = find(card, function(n) return n.w == "CheckBox" and n.p.label == "Show destination" end)
	ok(box ~= nil, "Show destination checkbox")
	box.p.onValueChange(1)
	ok(F.pushed ~= nil, "tool pushed")
	eq(F.pushed.actionFn(), "action")
	ok(F.layerConfig ~= nil and F.layerConfig.layerConfig, "LayerConfig built")
	-- the station card: no terminals in the empty world, so no card (read_terminals still runs)
	local st = m.PaxDestStationPlugin({ entityId = 9, gameCtx = {}, showCalloutOnRightSide = false })
	eq(st.w, "BoxLayout")
	eq(#st.p.children, 0)
	F.clockUs = F.clockUs + 31e6
	m.PaxDestPersonPlugin({ entityId = 7, gameCtx = {}, showCalloutOnRightSide = false })
end

test("debug Off: same behaviour, no refresh line and no SQPERF output", function()
	local m = load(1)
	personSession(m)
	eq(#lines("[PaxDest] refresh"), 0)
	eq(#lines("[SQPERF]"), 0)
	ok(#lines("[PaxDest] push:") > 0, "the push diagnostics stay")
end)

test("debug On: refresh line and a 30 s summary with every section", function()
	local m = load(2)
	personSession(m)
	eq(#lines("[PaxDest] refresh owner="), 1)
	local win = lines("win_ms=")
	eq(#win, 1, "one window summary")
	ok(win[1]:find("ctx=gui", 1, true) and win[1]:find("timer=clock", 1, true), win[1])
	for _, name in ipairs({ "person_render", "compute_person", "layer_config", "station_render", "read_terminals" }) do
		ok(win[1]:find("| " .. name .. " n=", 1, true), name .. ": " .. win[1])
	end
end)

test("a slow scan is logged with the debug param Off", function()
	local m = load(1)
	local api0 = api
	api0.engine.getComponent = function()
		F.clockUs = F.clockUs + 30000 -- 30 ms engine read
		return nil
	end
	m.PaxDestPersonPlugin({ entityId = 7, gameCtx = {}, showCalloutOnRightSide = false })
	local card = m.PaxDestPersonPlugin({ entityId = 7, gameCtx = {}, showCalloutOnRightSide = false })
	find(card, function(n) return n.w == "CheckBox" and n.p.label == "Show destination" end).p.onValueChange(1)
	eq(#lines("slow=compute_person max=30.0"), 1)
end)

test("mod.json has the Debug: performance log param (Off default)", function()
	local f = assert(io.open(MOD_ROOT .. "mod.json", "r"))
	local s = f:read("a")
	f:close()
	ok(s:find('"key": "sqperf_log"', 1, true))
	ok(s:find('"defaultIndex": 0', 1, true))
end)
