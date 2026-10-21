-- Supply Gaps area labels in the HUD ("[cargo icon] 73%" per town district). Plain Lua (dynamic
-- wrapping of base module fields). PLAN "Phase 2c" has the research and ranking.
--
-- The vanilla district label (Cargo Flow layer, station tools) is a HUD icon of the TOWN entity: the HUD
-- manager calls its master recipe once for the town and once per district "sub-entity", with
-- param.details.data = Gui.SelectionDetails.Town {townEntity, districtType} (api/tealdef/api/gui.d.tl:213-219;
-- base/content/gui/layers/layer_cargo_flow.tl:66-95, 129-150).
--
-- install() wraps two module fields once, each in pcall (guards on the wrapped module tables):
--   1. town_hud_react_util.TownHudIcon (gui/main/town_hud_react_util.tl:46). HudIconMasterGame, the
--      free-play HUD master, calls it through the module table for every town (hud_icon_toolbox.tl:343-346,
--      and HudIconMasterBase :41 for other layers; TOWN is in the default HUD pre-filter,
--      selector_react_util.tl:14-23). Our wrapper renders the base icon unchanged plus, below it, one row
--      per labelled district of that town (district colour bar + chips). Skipped when showCargo == false
--      (the Cargo Flow layer's town icon, layer_cargo_flow.tl:137, whose districts get the chips via 2.).
--      Base never calls TownHudIcon for a district sub-icon; if one comes anyway it gets the base alone.
--   2. layer_cargo_flow.HudIconMaster (layer_cargo_flow.tl:50), read at render by the layer's
--      HudIconManagerConfig (layer_cargo_flow.tl:338): district sub-icons get our row under the vanilla
--      supply chips.
--
-- Threads: HUD recipes run on worker threads (memory "HUD recipes not on GUI thread"). The wrappers only
-- read overlay.labelStore / overlay.session (plain Lua data, built on the GUI thread by the tick and
-- replaced as a whole) and build builtin nodes; no api.engine / api.res / GUI-thread-only calls. The tick
-- runs in react.enqueueJoin, after the parallel react work, so it never overlaps a HUD render.
-- Every wrapper falls back to the base recipe alone on any error (ERR log, rate-limited).

local overlay = ug_require "square_supply_gaps::/supply_gaps/sg_overlay.tl"
-- SQPERF (plans/sqperf/README.md), own instrument ctx "hud": the HUD wrappers and the area label's
-- render and rows poll. They run on worker threads (HUD recipes, onStepTimer: "Main Pool N"), where
-- api.type.Clock is safe (docs/findings.md "Timers and threads in GUI contexts"). Section names are
-- literals; nothing is allocated per call.
local sqperf = ug_require "square_supply_gaps::/sqperf/square_supply_gaps.lua"
local perf = sqperf.new({ mod = "square_supply_gaps", ctx = "hud", paramKey = "sqperf_log" })

local labels = {}

local LOG_PREFIX = "[SQSG] "
local ERR_LOGS = 20
local errLogged = 0

local function err(where, m)
	errLogged = errLogged + 1
	if errLogged <= ERR_LOGS then log.message(LOG_PREFIX .. "ERR label " .. where .. " " .. tostring(m)) end
end

--- Rows to draw for a town (landUse nil = every labelled district of it). Plain data only.
function labels.rowsFor(town, landUse)
	local s = overlay.session
	local st = overlay.labelStore
	if st == nil or s == nil or not s.on or not s.labels or town == nil then return {} end
	local rows = st.byTown and st.byTown[town] or nil
	if rows == nil then return {} end
	if landUse == nil then return rows end
	for _, r in ipairs(rows) do
		if r.landUse == landUse then return { r } end
	end
	return {}
end

--- Land use index (1..3) of a district sub-icon, nil for a town's main icon (or anything else).
function labels.districtOf(params)
	local ok, lu = pcall(function()
		local details = params and params.details
		local data = details and details.data
		if data == nil then return nil end
		if data.kind ~= api.gui.SelectionDetails.Type.Town then return nil end
		local dt = tonumber(data.districtType)
		if dt == nil then return nil end
		return dt + 1
	end)
	if ok then return lu end
	return nil
end

local react, builtin, gui_react_util, engine_react_util
local AreaLabel

-- The base HUD pill builder, when this platform has it. Console builds ship their own base GUI scripts, which
-- can lack functions the PC copy has (PS5 report 2026-10-19, Smart Lanes; docs/findings/gui.md "Base GUI
-- modules differ by platform"). Resolved on the first pill: the base function's first call runs in pcall;
-- when it works it is called directly from then on (no per-label pcall), else fallbackPill for the session.
-- install() resets it. fallbackPill is the base HUD-mode tree (gui_react_util.tl:113-140, 277-310) for the
-- params our chips pass (one icon path, label, labelFontColor, labelMode "HudIconMain", shippingState),
-- with the same classes, so base styling applies where the stylesheet has them.
local SHIPPING_CLASS = {
	Warehouse = "warehouse", WaitingPassenger = "waiting-passenger", Vehicle = "vehicle",
	IndustryInput = "industry-input", IndustryOutput = "industry-output",
}
local pillFn = nil

local function fallbackPill(p)
	if type(react.setStyleClasses) == "function" then react.setStyleClasses("hud-icon-main") end
	local hud = p.labelMode == "HudIconMain" or p.labelMode == "HudIconLayer"
	local inner = {}
	if p.iconPath ~= nil then
		inner[#inner + 1] = builtin.ImageView{
			meta = { tooltip = p.tooltip, class = "iconlabelindicator-icon-size" .. (hud and ",hud-icon" or "") },
			path = p.iconPath,
			scaling = builtin.type.ImageViewScaling.AutoFit,
		}
	end
	if p.label ~= nil then
		inner[#inner + 1] = builtin.TextView{
			meta = { class = "iconlabelindicator-label, font-scale-annotation", tooltip = p.tooltip },
			text = p.label,
		}
	end
	local bg = "hud-icon-background, " .. (p.labelFontColor or "Default")
	local ship = p.shippingState and SHIPPING_CLASS[p.shippingState]
	if ship then bg = bg .. ", " .. ship end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			builtin.Component{
				meta = { class = bg },
				layout = builtin.BoxLayout{
					meta = { class = "iconlabelindicator-layout" },
					orientation = builtin.type.Orientation.Horizontal,
					children = { builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = inner } },
				},
			},
		},
	}
end

local function pill(p)
	local f = pillFn
	if f ~= nil then return f(p) end
	local base = gui_react_util.makeContentLabelIndictator
	if type(base) == "function" then
		local ok, node = pcall(base, p)
		if ok and node ~= nil then
			pillFn = base
			return node
		end
		err("pill", node)
	else
		log.message(LOG_PREFIX .. "label pill: base makeContentLabelIndictator " .. type(base) .. ", own pill")
	end
	pillFn = fallbackPill
	return fallbackPill(p)
end

local function chipNode(ch)
	-- The stock HUD pill (icon + label), as HudIconMasterGame's StockHudIcon (hud_icon_toolbox.tl:60-84)
	-- and square_industry_production_label's makePill.
	return pill({
		iconPath = ch.icon,
		label = ch.text,
		labelFontColor = ch.tone,
		labelMode = "HudIconMain",
		shippingState = "IndustryInput",
	})
end

local function rowNode(r, mark)
	local children = {}
	if mark then
		children[#children + 1] = builtin.Component{ meta = { class = "sqsg-lu-mark, sqsg-lu-" .. tostring(r.landUse) } }
	end
	for _, ch in ipairs(r.chips or {}) do
		if ch.icon ~= nil and ch.icon ~= "" then children[#children + 1] = chipNode(ch) end
	end
	return builtin.BoxLayout{
		meta = { class = "sqsg-area-row" },
		orientation = builtin.type.Orientation.Horizontal,
		children = children,
	}
end

local function makeRecipes()
	-- param: {town, landUse (nil = all rows of the town), mark (draw the district colour bar)}
	-- SQPERF sections "hud_area_render" and "hud_area_poll"
	AreaLabel = react.RegisterRecipe("SupplyGapsAreaLabel", perf:wrap("hud_area_render", function(param)
		react.setMouseTransparent(true)
		-- hook first, unconditionally; refreshed every second from the store (deepEquals). Decided here,
		-- not at the wrapper's render, because the base parents re-render rarely.
		local state = engine_react_util.useStepStateTimer(function()
			local t = perf:start()
			local ok, rows = pcall(labels.rowsFor, param.town, param.landUse)
			perf:stop("hud_area_poll", t)
			if ok then return { rows = rows } end
			return { rows = {} }
		end, 1.0)
		local rows = (state:old() or {}).rows or {}
		local ok, node = pcall(function()
			local children = {}
			for _, r in ipairs(rows) do children[#children + 1] = rowNode(r, param.mark) end
			return builtin.BoxLayout{
				meta = { class = "sqsg-area" },
				orientation = builtin.type.Orientation.Vertical,
				children = children,
			}
		end)
		if ok then return node end
		err("hud", node)
		return builtin.BoxLayout{ children = {} }
	end))
end

local function areaLabel(param)
	local ok, node = pcall(AreaLabel, param)
	if ok then return node end
	err("areaLabel", node)
	return nil
end

local function wrapTownHudIcon(thru)
	if thru.__sqsgLabelPatched then return "already" end
	local orig = thru.TownHudIcon
	if orig == nil then return "missing" end
	thru.__sqsgLabelPatched = true
	-- SQPERF section "hud_town" (includes the base icon's recipe call)
	thru.TownHudIcon = react.RegisterRecipe("SupplyGapsTownHudIcon", perf:wrap("hud_town", function(params, showGrowth, showCargo)
		react.setMouseTransparent(true)
		local children = { orig(params, showGrowth, showCargo) }
		-- showCargo == false: the Cargo Flow layer's town icon (its districts get rows via wrapCargoFlow);
		-- a district sub-icon (never sent by base): base only
		if showCargo ~= false and labels.districtOf(params) == nil then
			children[#children + 1] = areaLabel({ town = params.entity, landUse = nil, mark = true })
		end
		return builtin.BoxLayout{ children = children }
	end))
	return "ok"
end

local function wrapCargoFlow(lcf)
	if lcf.__sqsgLabelPatched then return "already" end
	local orig = lcf.HudIconMaster
	if orig == nil then return "missing" end
	lcf.__sqsgLabelPatched = true
	-- SQPERF section "hud_cargoflow" (includes the base master's recipe call)
	lcf.HudIconMaster = react.RegisterRecipe("SupplyGapsCargoFlowHudIconMaster", perf:wrap("hud_cargoflow", function(param, userParam)
		react.setMouseTransparent(true)
		local children = { orig(param, userParam) }
		local district = labels.districtOf(param)
		if district ~= nil then
			children[#children + 1] = areaLabel({ town = param.entity, landUse = district, mark = false })
		end
		return builtin.BoxLayout{ children = children }
	end))
	return "ok"
end

local function step(name, fn)
	local ok, r = pcall(fn)
	if ok then return tostring(r) end
	err("install " .. name, r)
	return "err"
end

function labels.install()
	if labels.installed then return "already" end
	labels.installed = true
	local base = step("modules", function()
		react = ug_require("::/gui/main/react.lua")
		builtin = ug_require("::/gui/main/builtin.lua")
		gui_react_util = ug_require("::/gui/main/gui_react_util.tl")
		engine_react_util = ug_require("::/gui/main/engine_react_util.tl")
		pillFn = nil
		makeRecipes()
		return "ok"
	end)
	if base ~= "ok" then return "base=" .. base end
	local town = step("town", function() return wrapTownHudIcon(ug_require("::/gui/main/town_hud_react_util.tl")) end)
	local cf = step("cargoflow", function() return wrapCargoFlow(ug_require("::/gui/layers/layer_cargo_flow.tl")) end)
	return "town=" .. town .. " cargoflow=" .. cf
end

return labels
