-- sg_labels: the area-label HUD wrappers with stubbed base modules (react renders eagerly here).
-- Checks: wrappers installed once, base recipe always rendered, rows under the town icon and the Cargo
-- Flow district icons, district sub-icons of the town recipe pass through, errors stay inside.
-- The own pill when base gui_react_util lacks makeContentLabelIndictator or it raises (PS5 report
-- 2026-10-19, Smart Lanes; docs/findings/gui.md "Base GUI modules differ by platform").

local nodes = {}
local react = {
	RegisterRecipe = function(name, fn)
		return function(...) return fn(...) end
	end,
	setMouseTransparent = function() end,
}
local builtin = {
	type = { Orientation = { Horizontal = "H", Vertical = "V" }, ImageViewScaling = { AutoFit = "fit" } },
	BoxLayout = function(p) return { kind = "BoxLayout", class = p.meta and p.meta.class, children = p.children or {} } end,
	Component = function(p) return { kind = "Component", class = p.meta and p.meta.class, layout = p.layout } end,
	ImageView = function(p) return { kind = "ImageView", class = p.meta and p.meta.class, path = p.path } end,
	TextView = function(p) return { kind = "TextView", class = p.meta and p.meta.class, text = p.text } end,
}
local gru = {
	makeContentLabelIndictator = function(p) return { kind = "pill", icon = p.iconPath, label = p.label, tone = p.labelFontColor, mode = p.labelMode } end,
}
local eru = {
	useStepStateTimer = function(fn)
		local v = fn()
		return { old = function() return v end }
	end,
}
local townCalls = 0
local thru = { TownHudIcon = function(params, g, c) townCalls = townCalls + 1; return { kind = "town", entity = params.entity } end }
local cfCalls = 0
local lcf = { HudIconMaster = function(param) cfCalls = cfCalls + 1; return { kind = "cargoflow", entity = param.entity } end }
stub_module("::/gui/main/react.lua", react)
stub_module("::/gui/main/builtin.lua", builtin)
stub_module("::/gui/main/gui_react_util.tl", gru)
stub_module("::/gui/main/engine_react_util.tl", eru)
stub_module("::/gui/main/town_hud_react_util.tl", thru)
stub_module("::/gui/layers/layer_cargo_flow.tl", lcf)

local TOWN_TYPE = "TownDetails"
set_global("api", { gui = { SelectionDetails = { Type = { Town = TOWN_TYPE } } } })

local overlay = ug_require "square_supply_gaps::/supply_gaps/sg_overlay.tl"
local labels = ug_require "square_supply_gaps::/supply_gaps/sg_labels.lua"
local installStatus = labels.install()
local wrappedTown, wrappedCF = thru.TownHudIcon, lcf.HudIconMaster

local FISH, FOOD = 7, 4

local function chip(c, text) return { icon = "i" .. c, text = text, tone = "Poor", cargo = c } end

local function store()
	return {
		byTown = {
			[100] = {
				{ landUse = 1, chips = { chip(FOOD, "20%") } },
				{ landUse = 2, chips = { chip(FISH, "73%"), chip(FOOD, "90%") } },
			},
		},
		shown = 2, areas = 2,
	}
end

local function townParams(entity) return { entity = entity, details = { data = { kind = TOWN_TYPE } } } end
local function districtParams(entity, dt) return { entity = entity, details = { data = { kind = TOWN_TYPE, districtType = dt } } } end

local function logged(text)
	for _, e in ipairs(log_entries()) do
		if e.msg:find(text, 1, true) then return true end
	end
	return false
end

-- the AreaLabel node (BoxLayout!sqsg-area) inside a wrapper result
local function areaOf(node)
	for _, ch in ipairs(node.children) do
		if ch.kind == "BoxLayout" and ch.class == "sqsg-area" then return ch end
	end
	return nil
end

before_each(function()
	overlay.session.on, overlay.session.labels = true, true
	overlay.labelStore = store()
	townCalls, cfCalls = 0, 0
end)

test("install: wraps each base field once and returns the status", function()
	eq(installStatus, "town=ok cargoflow=ok")
	eq(labels.install(), "already")
	labels.installed = false
	eq(labels.install(), "town=already cargoflow=already")
	eq(thru.TownHudIcon, wrappedTown)
	eq(lcf.HudIconMaster, wrappedCF)
end)

test("districtOf: land use index for district sub-icons only", function()
	eq(labels.districtOf(districtParams(100, 0)), 1)
	eq(labels.districtOf(districtParams(100, 2)), 3)
	eq(labels.districtOf(townParams(100)), nil)
	eq(labels.districtOf({ entity = 1, details = { data = { kind = "Station", districtType = 1 } } }), nil)
	eq(labels.districtOf(nil), nil)
	eq(labels.districtOf({ details = setmetatable({}, { __index = function() error("userdata") end }) }), nil)
end)

test("town icon: base icon first, then one row per labelled district with pills", function()
	local n = thru.TownHudIcon(townParams(100), true, true)
	eq(townCalls, 1)
	eq(n.children[1].kind, "town")
	local area = areaOf(n)
	eq(#area.children, 2)
	local row = area.children[2]
	eq(row.class, "sqsg-area-row")
	eq(row.children[1].class, "sqsg-lu-mark, sqsg-lu-2")
	eq(row.children[2], { kind = "pill", icon = "i7", label = "73%", tone = "Poor", mode = "HudIconMain" })
	eq(#row.children, 3)
end)

test("town icon: nothing extra when off, labels off, or the town has no rows", function()
	overlay.session.on = false
	eq(#areaOf(thru.TownHudIcon(townParams(100), true, true)).children, 0)
	overlay.session.on, overlay.session.labels = true, false
	eq(#areaOf(thru.TownHudIcon(townParams(100), true, true)).children, 0)
	overlay.session.labels = true
	eq(#areaOf(thru.TownHudIcon(townParams(200), true, true)).children, 0)
	overlay.labelStore = nil
	eq(#areaOf(thru.TownHudIcon(townParams(100), true, true)).children, 0)
end)

test("town icon with showCargo=false (Cargo Flow layer): base only", function()
	local n = thru.TownHudIcon(townParams(100), true, false)
	eq(#n.children, 1)
	eq(n.children[1].kind, "town")
end)

test("district sub-icon of the town recipe (never sent by base): base only", function()
	local n = thru.TownHudIcon(districtParams(100, 1), true, true)
	eq(townCalls, 1)
	eq(#n.children, 1)
	eq(n.children[1].kind, "town")
end)

test("cargo flow master: base first; district sub-icons get their row, the town icon nothing", function()
	local n = lcf.HudIconMaster(districtParams(100, 0), {})
	eq(cfCalls, 1)
	eq(n.children[1].kind, "cargoflow")
	local row = n.children[2].children[1]
	eq(row.children[1].label, "20%") -- no district bar: the vanilla label is already district-coloured
	local t = lcf.HudIconMaster(townParams(100), {})
	eq(#t.children, 1)
end)

-- install() again: the pill builder is resolved anew on the next pill (install resets it)
local function reinstall()
	labels.installed = false
	labels.install()
	wrappedTown, wrappedCF = thru.TownHudIcon, lcf.HudIconMaster
end

-- the fallback pill's tree: BoxLayout > Component!hud-icon-background > BoxLayout > BoxLayout > {icon, label}
local function fallbackParts(p)
	eq(p.kind, "BoxLayout")
	local bg = p.children[1]
	eq(bg.kind, "Component")
	local layout = bg.layout
	eq(layout.class, "iconlabelindicator-layout")
	local inner = layout.children[1].children
	return bg.class, inner[1], inner[2]
end

test("a raising base pill builder: logged once, own pills from then on, base icon kept", function()
	local orig = gru.makeContentLabelIndictator
	local calls = 0
	gru.makeContentLabelIndictator = function() calls = calls + 1; error("pill") end
	reinstall()
	local n = thru.TownHudIcon(townParams(100), true, true)
	thru.TownHudIcon(townParams(100), true, true)
	gru.makeContentLabelIndictator = orig
	eq(calls, 1, "base tried once")
	eq(n.children[1].kind, "town")
	local row = areaOf(n).children[2]
	local cls, icon, label = fallbackParts(row.children[2])
	eq(cls, "hud-icon-background, Poor, industry-input")
	eq(icon.class, "iconlabelindicator-icon-size,hud-icon")
	eq(icon.path, "i7")
	eq(label.text, "73%")
	ok(logged("[SQSG] ERR label pill"))
	reinstall()
	eq(areaOf(thru.TownHudIcon(townParams(100), true, true)).children[2].children[2].kind, "pill", "base again after install")
end)

test("base gui_react_util without makeContentLabelIndictator (PS5 report 2026-10-19, Smart Lanes): own pills", function()
	local orig = gru.makeContentLabelIndictator
	gru.makeContentLabelIndictator = nil
	reinstall()
	local n = thru.TownHudIcon(townParams(100), true, true)
	local cf = lcf.HudIconMaster(districtParams(100, 0), {})
	gru.makeContentLabelIndictator = orig
	eq(n.children[1].kind, "town")
	local row = areaOf(n).children[2]
	eq(#row.children, 3)
	local cls, icon, label = fallbackParts(row.children[3])
	eq(cls, "hud-icon-background, Poor, industry-input")
	eq(icon.path, "i4")
	eq(label.text, "90%")
	local _, _, cfLabel = fallbackParts(cf.children[2].children[1].children[1])
	eq(cfLabel.text, "20%")
	ok(logged("base makeContentLabelIndictator nil, own pill"))
	reinstall()
end)

test("a raising row builder never escapes: empty label, base icon kept", function()
	local orig = builtin.BoxLayout
	builtin.BoxLayout = function(p)
		if p.meta and p.meta.class == "sqsg-area-row" then error("row") end
		return orig(p)
	end
	local n = thru.TownHudIcon(townParams(100), true, true)
	builtin.BoxLayout = orig
	eq(n.children[1].kind, "town")
	eq(#n.children[2].children, 0)
	ok(logged("[SQSG] ERR label hud"))
end)
