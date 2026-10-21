-- Line Manager Plus, feature "Line actions: Match line rate" (setting line_rate_matcher; the former mod Line Rate
-- Matcher, square_line_rate_matcher, merged 2026-10-11: plans/square_line_manager_plus/MERGE_RM_PLAN.md). One entry in
-- the "Line actions" menu (lmp_actions.lua) that opens the Rate Matcher window (rate_matcher_window.tl) for the edited
-- line. Installed by lmp.script.lua (doReplace) through install() below. GUI code only; nothing in the savegame.
--
-- Needs the Line actions button: with "line_actions" Off there is no menu, so this feature reports "not installed"
-- with one log line (and "Line actions button" Off keeps meaning "no button").
--
-- The window gets the Line Manager's context through context() below, every step while it is open: the edited line
-- (exactly one selected), the protected entities and mission vehicle filter (gameCtx.filters) and the manager's
-- vehicle list functions. The window outlives the Line Manager, and the captured commonParams then belong to a closed
-- window whose react states have expired: reading them (:old() / :get()) prints "Calling Old() on expired
-- ReactStateWrap" plus a traceback to stdout.txt every time (docs/findings.md "Expired react states"). So every read
-- here goes through lmp_capture (editedLine, selectedLineCount check hasExpired first) or capture.expired, and the
-- vehicle list functions re-check at call time.

local detect = ug_require "square_line_manager_plus::/line_manager_plus/lmp_detect.lua"
local capture = ug_require "square_line_manager_plus::/line_manager_plus/lmp_capture.lua"
local actions = ug_require "square_line_manager_plus::/line_manager_plus/lmp_actions.lua"
local window = ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher_window.tl"

local PREFIX = "[LineManagerPlus] rate matcher: "

local function say(msg)
	if log and log.message then log.message(PREFIX .. msg) else print(PREFIX .. msg) end
end

local M = {}

-- The Line Manager's vehicle list, as vanilla Clone's onBuy adds its new vehicles (manager_window.tl:5108-5117):
-- commonParams.addOrRemoveVehicleToVehicleList({entity, removeFromList}) (manager_window.tl:7000-7017,
-- line_util.d.tl:525-527) calls the vehicle manager's addVehiclesToVehicleListAndSelect /
-- removeVehiclesFromVehicleList. The list is otherwise only filled when a line is selected (:1405-1410).
-- That closure reads the manager window's own states (creatingNewLineState:old(), vehicleManagerRef:get()), so it is
-- offered only while the window lives (lineState not expired) and skipped silently once it has closed.
local function listFn(params, remove)
	local fn = params and params.addOrRemoveVehicleToVehicleList
	if type(fn) ~= "function" or capture.expired(params.lineState) then return nil end
	return function(ids)
		if capture.expired(params.lineState) then return end
		for _i, id in ipairs(ids or {}) do
			fn({ entity = id, removeFromList = remove })
		end
	end
end

--- SquareRateMatcherContext or nil (no manager opened yet): the line (exactly one selected, edited, >= 0), protected
--- entities, the mission vehicle filter and the vehicle list functions. Never reads an expired state.
local function context()
	local p = capture.params()
	if not p then return nil end
	local line = nil
	if capture.selectedLineCount(p) == 1 then
		local e = capture.editedLine(p) -- nil when p.lineState has expired
		if type(e) == "number" and e >= 0 then line = e end
	end
	-- gameCtx.filters is game-level (gui/main/game.tl:182), not window-scoped; checked anyway
	local filters = nil
	local f = p.gameCtx and p.gameCtx.filters
	if f and not capture.expired(f) then filters = f:get() end
	return {
		line = line,
		protected = filters and filters.protectedEntities or nil,
		vehicleFilter = filters and filters.vehicleFilter or nil,
		listAdd = listFn(p, false),
		listRemove = listFn(p, true),
	}
end
M.context = context

-- Install ----------------------------------------------------------------------------------------------------------
local installed = false

--- Registers "Match line rate" in the Line actions menu; true when installed (now or before), false when the Line
--- actions button is Off or a base function is missing. Errors pass to the caller (lmp.script.lua pcall).
function M.install(_replacementApi, params)
	if installed then return true end
	if not detect.paramOn(params, "line_actions") then
		say("needs the Line actions button (line_actions Off), not installed")
		return false
	end
	if not actions.install() then return false end
	window.setContextFn(context)
	-- order 50: first in the menu, above Duplicate (100), Reverse (200) and Duplicate + reverse (300)
	actions.register({
		id = "rate_matcher", order = 50, label = "Match line rate", icon = window.ICON, -- i18n: keys label
		view = function(_ctx)
			return { enabled = true,
				tooltip = _("Compares the line's Rate with its supply: how many vehicles\nto add or remove, and which model costs least.") }
		end,
		-- lmp_actions.runEntry runs this in a pcall (feedback + one log line on error) and closes the menu after it
		run = function(ctx) window.open(ctx.line) end,
	})
	installed = true
	say("installed")
	return true
end

return M
