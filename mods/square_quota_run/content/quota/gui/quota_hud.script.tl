-- Quota Run HUD + card picker + end screen (PLAN.md §6 Phase 3). GUI thread: read-only, only
-- sends QuotaRun.* events (PLAN §4.2, §4.4).
-- Modelled file-for-file on
--   .cache/game/base/content/gui/game_bar/game_bar_display_transported_plugin/
--   (.res.lua registers the plugin, .script.tl polls engine state and returns a tree or nil,
--    .css.lua styles the recipe by its R::<name> selector).
-- Widget patterns: .cache/game/base/content/game_mechanics/subventions/subventions_gui.tl:139-158
-- Widget types: .cache/game/base/tealdef/scripts/builtin.d.tl
--
-- MOUNT POINT: registered at "::MainModButtonAreaExtension" (quota_hud.res.lua), NOT the PLAN's
-- "::ModEntryPointExtension": game.tl mounts all ModEntryPointExtension plugins inside the
-- EntryPoints node with meta.class = "invisible" (.cache/game/base/content/gui/main/game.tl:574-586, class at :579),
-- and "!invisible" is visibility = "none" (.cache/game/base/content/gui/main/default.css.lua:139-142),
-- so a HUD there could never be seen. MainModButtonArea is the visible mod slot in the top-left
-- button ridge (game.tl:529-556, main_mod_button_area.tl:13).
-- If nothing renders in the playtest, see plans/square_quota_run/GUI_FALLBACK.md
-- (game-bar fallback + console commands for picks).
--
-- LAYOUT (Phase 4): the ridge is a ScrollArea with verticalPolicy AlwaysOff
-- (.cache/game/base/content/gui/main/main_mod_button_area.tl:26-31), so a tall panel would be
-- clipped. Default: a compact one-row HUD; in "choosing" it shows a "Pick a card" button and in
-- "ended" a "Run over" button. Their onClick opens a centered dialog window (base DialogWindow
-- via the game's window container). react.lua has no effect hook, so the dialog only opens from
-- a click. config.GUI_INLINE_PICKER = true restores the old inline vertical panel.
--
-- DEV PANEL (config.DEBUG only, PLAN §4.6): a "Dev" button in the HUD (also on an inert save and in
-- sandbox, see quota_hud_model) opens QuotaRunDevWindow, a custom builtin.Window (not DialogWindow:
-- its choices always call onClose first and lay out in one row, dialog_react_util.tl:89-93,103-116,
-- so it cannot stay open or group buttons). The window content polls the state itself, so its
-- status line is live, and it stays open until its close button is clicked. Every button sends
-- QuotaRun.debug. With GUI_INLINE_PICKER = true the same buttons render inline under a Dev toggle.

-- Base modules: always "::/" from a mod (PLAN §4 path rules).
local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local lang_util = ug_require "::/scripts/lang_util.tl" as LangUtil
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl" as MainModButtonArea
-- src: .cache/game/base/content/gui/main/pause_menu.tl:8 (dialog_react_util require);
-- mod precedent for game_react_globals: .cache/game/mods/release/urbangames_campaign_mission_05/content/mission/perk_icons_replacement.script.tl:4
local dialog_react_util = ug_require "::/gui/menu/dialog_react_util.tl" as DialogReactUtil
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl" as GameReactGlobals

local hud_model = ug_require "square_quota_run::/quota/gui/quota_hud_model.tl" as QuotaRunHudModel
local config = ug_require "square_quota_run::/quota/quota_config.tl" as QuotaRunConfig
local cards = ug_require "square_quota_run::/quota/quota_cards.tl" as QuotaRunCards
-- v2.1 addendum: rule-target names (town / cargo type), shared with the notification script.
local target_names = ug_require "square_quota_run::/quota/gui/quota_target_names.tl" as QuotaRunTargetNames

-- Multi-line tooltips joined with "\n": .cache/game/base/content/gui/main/cargo_react_util.tl:147
-- src: .cache/game/mods/release/urbangames_campaign_mission_08/content/mission/mission_story.tl:891 (mod gs name)
local GS_NAME <const> = "square_quota_run::/quota/quota.gs"

local function sendEvent(name : string, param : table)
	-- src: .cache/game/api/tealdef/api/cmd.d.tl:788; GUI usage: subventions_gui.tl:135
	api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", name, param))
end

--- Poll: a fresh, small view table, or nil (no entity, or hud_model.build says nothing to show:
--- inactive / sandbox, except the DEBUG-only "inert"/"sandbox" dev views).
local function getFromEngine() : QuotaRunHudView
	-- src: .cache/game/base/content/mission/mission_framework/mission_framework_react.tl:49-51 (GUI reads GAME_SCRIPT state)
	local entity = api.engine.system.gameScriptSystem.getEntityForGameScript(GS_NAME)
	if entity == nil or entity < 0 then return nil end
	local gs = api.engine.getComponent(entity, api.type.ComponentType.GAME_SCRIPT) as Engine.Component.GameScript<QuotaRunState>
	if gs == nil then return nil end
	local s = gs.state
	if (s == nil or s.active ~= true) and not config.DEBUG then return nil end
	-- src: .cache/game/base/content/game_mechanics/company/company_notification_marketing.script.tl:16 (GUI reads GAME_TIME)
	local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	local v = hud_model.build(s, gt and gt.gameTime or nil)
	-- v2.1 addendum: name the rule target here (the model is pure). One cheap, nil-safe engine
	-- lookup per poll; the result is a plain string on the fresh view, so deepEquals stays cheap.
	if v ~= nil and v.ruleTarget ~= nil then
		v.ruleTargetName = target_names.resolve(v.ruleTargetKind, v.ruleTarget)
	end
	return v
end

local function text(str : string, class? : string) : TreeNodeId
	return builtin.TextView{
		meta = { class = class or "font-scale-body" },
		text = str,
	}
end

local function vbox(children : {TreeNodeId}, class? : string) : TreeNodeId
	return builtin.BoxLayout{
		meta = class and { class = class } or nil,
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end

local function pickedLine(v : QuotaRunHudView) : string
	local names : {string} = {}
	for i, name in ipairs(v.picked) do names[i] = _(name) end
	return lang_util.format(_("Cards: {cards}"), { cards = table.concat(names, ", ") })
end

--- v2: "<name> - <description>" (name only when there is no description).
local function nameDesc(name : string, description : string) : string
	if description == nil or description == "" then return _(name) end
	return _(name) .. " - " .. _(description)
end

--- v2.1 addendum: "Target town: X" / "Target cargo: X" for a rule with a resolved target, else nil.
local function targetLine(v : QuotaRunHudView) : string
	if v.ruleTargetName == nil then return nil end
	if v.ruleTargetKind == "town" then
		return lang_util.format(_("Target town: {town} (only deliveries into it count)"), { town = v.ruleTargetName })
	elseif v.ruleTargetKind == "cargoType" then
		return lang_util.format(_("Target cargo: {cargo}"), { cargo = v.ruleTargetName })
	end
	return nil
end

--- v2.1 addendum: a short label plus the target name in parentheses, e.g. "Local Hero (Springfield)".
local function withTarget(label : string, v : QuotaRunHudView) : string
	if v.ruleTargetName == nil then return label end
	return lang_util.format(_("{label} ({target})"), { label = label, target = v.ruleTargetName })
end

--- v2: what counts this round (boss, rule, rule target) and the announced boss, one line each; {} on
--- v1 states. Used by the tooltip, the inline panel and the picker (PLAN §9.3, §9.4).
local function roundInfoLines(v : QuotaRunHudView) : {string}
	local lines : {string} = {}
	if v.bossName ~= nil then
		lines[#lines + 1] = lang_util.format(_("Boss round: {boss}"), { boss = nameDesc(v.bossName, v.bossDescription) })
	end
	if v.ruleName ~= nil then
		lines[#lines + 1] = lang_util.format(_("Rule: {rule}"), { rule = nameDesc(v.ruleName, v.ruleDescription) })
		local target = targetLine(v)
		if target ~= nil then lines[#lines + 1] = target end
	end
	if v.nextBossName ~= nil then
		lines[#lines + 1] = lang_util.format(_("Next round's boss: {boss}"), { boss = nameDesc(v.nextBossName, v.nextBossDescription) })
	end
	return lines
end

local function hudRows(v : QuotaRunHudView) : {TreeNodeId}
	local rows : {TreeNodeId} = {
		text(lang_util.format(_("Quota Run - Round {round}"), { round = tostring(v.round) }), "font-scale-headline"),
	}
	if v.monthsLeft ~= nil then
		rows[#rows + 1] = text(lang_util.format(_("Months left: {months}"), { months = tostring(v.monthsLeft) }))
	end
	local quotaText = lang_util.format(_("Delivered {progress} / {quota}"), {
		progress = lang_util.formatInt(v.progress),
		quota = lang_util.formatInt(v.quota),
	})
	if v.provisional then
		quotaText = quotaText .. " " .. _("(provisional)")
	end
	-- ProgressBar: value must be in [0, 1] (builtin.d.tl:1013-1018); usage town_hud_react_util.tl:169-174
	rows[#rows + 1] = builtin.ProgressBar{
		meta = { class = "quota-run-progress, font-scale-annotation" },
		value = v.fraction,
	}
	rows[#rows + 1] = text(quotaText)
	if v.redWarning then
		rows[#rows + 1] = text(lang_util.format(_("In the red: {n} / {max} months"), {
			n = tostring(v.redMonths),
			max = tostring(v.bankruptMonths),
		}), "font-scale-body, quota-run-warning")
	end
	-- v2: boss / rule / next boss (only during play: the model leaves them nil when ended).
	for __, line in ipairs(roundInfoLines(v)) do
		rows[#rows + 1] = text(line, "font-scale-annotation, quota-run-round-info")
	end
	if #v.picked > 0 then
		rows[#rows + 1] = text(pickedLine(v), "font-scale-annotation, quota-run-picked")
	end
	return rows
end

local function pickerRows(v : QuotaRunHudView) : {TreeNodeId}
	local buttons : {TreeNodeId} = {}
	for __, card in ipairs(v.offer) do
		local index = card.index
		buttons[#buttons + 1] = builtin.Button{
			meta = { class = "primary, quota-run-card" },
			content = builtin.Component{
				layout = vbox({
					text(_(card.name), "font-scale-body, quota-run-card-name"),
					text(_(card.description), "font-scale-annotation, quota-run-card-desc"),
				}),
			},
			onClick = function()
				sendEvent("QuotaRun.pickCard", { index = index })
			end,
		}
	end
	local rows : {TreeNodeId} = {
		text(lang_util.format(_("Round {round} cleared! Pick a card:"), { round = tostring(v.roundsCleared) }),
			"font-scale-body, quota-run-section"),
	}
	-- v2: the boss / rule of the round that just started (v.round), above the cards (hudRows lists the
	-- full lines; repeat only the headline here so the player sees what counts next to the choice).
	if v.bossName ~= nil then
		rows[#rows + 1] = text(lang_util.format(_("Round {round} is a boss round: {boss}"),
			{ round = tostring(v.round), boss = withTarget(_(v.bossName), v) }), "font-scale-body, quota-run-boss")
	elseif v.ruleName ~= nil then
		rows[#rows + 1] = text(lang_util.format(_("Round {round} rule: {rule}"),
			{ round = tostring(v.round), rule = withTarget(_(v.ruleName), v) }), "font-scale-body, quota-run-rule")
	end
	rows[#rows + 1] = builtin.BoxLayout{
		meta = { class = "quota-run-cards" },
		orientation = builtin.type.Orientation.Horizontal,
		children = buttons,
	}
	return rows
end

local function endRows(v : QuotaRunHudView) : {TreeNodeId}
	local reason : string
	if v.endReason == "bankrupt" then
		reason = lang_util.format(_("Bankrupt: {n} months in the red."), { n = tostring(v.bankruptMonths) })
	else
		reason = lang_util.format(_("Quota missed in round {round}."), { round = tostring(v.round) })
	end
	local rows : {TreeNodeId} = {
		text(_("Quota Run - Run over"), "font-scale-headline"),
		text(reason, "font-scale-body, quota-run-warning"),
		text(lang_util.format(_("Rounds cleared: {n}"), { n = tostring(v.roundsCleared) })),
		text(lang_util.format(_("Total moved: {n}"), { n = lang_util.formatInt(v.totalTransported or 0) })),
	}
	if #v.picked > 0 then
		rows[#rows + 1] = text(pickedLine(v), "font-scale-annotation, quota-run-picked")
	end
	rows[#rows + 1] = builtin.Button{
		meta = { class = "primary" },
		content = text(_("Continue as sandbox")),
		onClick = function()
			sendEvent("QuotaRun.continueSandbox", {})
		end,
	}
	return rows
end

---------------------------------------------------------------------------
-- Dialog window (default layout). Pattern: .cache/game/base/content/mission/mission_framework/mission_framework_react.tl:136-164
-- Param record: .cache/game/base/tealdef/gui/menu/dialog_react_util.d.tl:3-29
-- Window API: .cache/game/base/tealdef/gui/main/game_react_globals.d.tl:7 (getDefaultWindowApi, may return nil,
-- .cache/game/base/content/gui/main/game_react_globals.tl:14-20), .cache/game/base/tealdef/scripts/builtin.d.tl:1216-1232

local function closeDialog()
	local wa = game_react_globals.getDefaultWindowApi()
	if wa ~= nil then
		wa.removeAllWindows(dialog_react_util.DialogWindow)
	end
end

local function openDialog(title : string, body : string, choices : {DialogReactUtil.DialogWindowParam.Choice})
	local wa = game_react_globals.getDefaultWindowApi()
	if wa == nil then
		log.warning("[QuotaRun] no window container; use the console commands (GUI_FALLBACK.md)")
		return
	end
	wa.addSingletonWindow(dialog_react_util.DialogWindow, {
		-- Clicking outside / ESC call onClose (dialog_react_util.tl:52-70); we close the window and
		-- the HUD button reopens it, so the player can look at the map before picking.
		onClose = closeDialog,
		closable = false,
		x = 0.5,
		y = 0.5,
		windowTitle = title,
		displayText = body,
		choices = choices,
	})
	wa.moveSingletonWindowToFront(dialog_react_util.DialogWindow)
end

local function openPicker(v : QuotaRunHudView)
	local lines : {string} = {
		lang_util.format(_("Round {round} cleared! Round {next} has started; its quota ({quota}) is provisional until you pick."),
			{ round = tostring(v.roundsCleared), next = tostring(v.round), quota = lang_util.formatInt(v.quota) }),
		"",
	}
	-- v2: what counts in the round that just started (boss, rule, next boss), above the cards.
	local info = roundInfoLines(v)
	if #info > 0 then
		for __, line in ipairs(info) do lines[#lines + 1] = line end
		lines[#lines + 1] = ""
	end
	local choices : {DialogReactUtil.DialogWindowParam.Choice} = {}
	for __, card in ipairs(v.offer) do
		local index = card.index
		lines[#lines + 1] = _(card.name) .. ": " .. _(card.description)
		choices[#choices + 1] = {
			text = _(card.name),
			tooltip = _(card.description),
			onClick = function()
				sendEvent("QuotaRun.pickCard", { index = index })
				closeDialog()
			end,
		}
	end
	openDialog(_("Quota Run - Pick a card"), table.concat(lines, "\n"), choices)
end

local function openEnd(v : QuotaRunHudView)
	local reason : string
	if v.endReason == "bankrupt" then
		reason = lang_util.format(_("Bankrupt: {n} months in the red."), { n = tostring(v.bankruptMonths) })
	else
		reason = lang_util.format(_("Quota missed in round {round}."), { round = tostring(v.round) })
	end
	local lines : {string} = {
		reason,
		lang_util.format(_("Rounds cleared: {n}"), { n = tostring(v.roundsCleared) }),
		lang_util.format(_("Total moved: {n}"), { n = lang_util.formatInt(v.totalTransported or 0) }),
	}
	if #v.picked > 0 then lines[#lines + 1] = pickedLine(v) end
	openDialog(_("Quota Run - Run over"), table.concat(lines, "\n"), {
		{
			text = _("Continue as sandbox"),
			onClick = function()
				sendEvent("QuotaRun.continueSandbox", {})
				closeDialog()
			end,
		},
	})
end

---------------------------------------------------------------------------
-- Dev panel (config.DEBUG only). Window pattern: a wrapper recipe around builtin.Window, like
-- .cache/game/base/content/gui/menu/main_page.tl:44-63 (DeluxeContentWindow: closable, onClose
-- removes it); opened with addSingletonWindow (.cache/game/base/tealdef/scripts/builtin.d.tl:1216-1232).
-- Window params: builtin.d.tl:1186-1210 (WindowParam). Recipe API: .cache/game/base/tealdef/scripts/react.d.tl:251-259.
-- Button meta.enabled / tooltip: same use as dialog_react_util.tl:79-84.

local function sendDebug(op : string, n? : integer, id? : string)
	sendEvent("QuotaRun.debug", { op = op, n = n, id = id })
end

local function devButton(label : string, op : string, n? : integer, id? : string, enabled? : boolean, tooltip? : string) : TreeNodeId
	return builtin.Button{
		meta = { class = "quota-run-dev-button", enabled = enabled ~= false, tooltip = tooltip },
		content = text(label, "font-scale-annotation"),
		onClick = function() sendDebug(op, n, id) end,
	}
end

local function hrow(children : {TreeNodeId}) : TreeNodeId
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = children,
	}
end

local DEV_CARDS_PER_ROW <const> = 4

--- Read-only one-line status for the dev panel (plain English: debug-only text, not translated).
local function devStatus(v : QuotaRunHudView) : string
	if v == nil then return "Quota Run: no game script state" end
	if v.phase == "inert" then
		return "phase=inert (no run in this save). Force start activates one: use a COPY of the save."
	end
	local parts : {string} = {
		"phase=" .. tostring(v.phase),
		"R" .. tostring(v.round),
	}
	if v.phase ~= "sandbox" then
		parts[#parts + 1] = lang_util.formatInt(v.progress) .. "/" .. lang_util.formatInt(v.quota)
		parts[#parts + 1] = "mo=" .. (v.monthsLeft ~= nil and tostring(v.monthsLeft) or "?")
		parts[#parts + 1] = "red=" .. tostring(v.redMonths) .. "/" .. tostring(v.bankruptMonths)
	end
	parts[#parts + 1] = "cleared=" .. tostring(v.roundsCleared)
	parts[#parts + 1] = "fx: " .. tostring(v.fxSummary)
	return table.concat(parts, "  ")
end

--- The grouped dev buttons (shared by the window and the inline fallback).
local function devRows(v : QuotaRunHudView) : {TreeNodeId}
	local inert = v == nil or v.phase == "inert"
	local active = not inert
	local rows : {TreeNodeId} = {
		text(devStatus(v), "font-scale-annotation, quota-run-dev-status"),
		text("Round", "font-scale-body, quota-run-dev-section"),
		hrow({
			devButton("Pass round", "passRound", nil, nil, active),
			devButton("Fail round", "failRound", nil, nil, active),
			devButton("+25% quota", "addQuotaPct", 25, nil, active),
			devButton("+100% quota", "addQuotaPct", 100, nil, active),
		}),
		hrow({
			devButton("Skip 1 month", "skipMonths", 1, nil, active),
			devButton("Skip 6 months", "skipMonths", 6, nil, active),
			devButton("Force offer", "offer", nil, nil, active),
		}),
		text("Cards (apply directly, no offer used)", "font-scale-body, quota-run-dev-section"),
	}
	local row : {TreeNodeId} = {}
	for __, card in ipairs(cards.list) do
		row[#row + 1] = devButton(card.name, "applyCard", nil, card.id, active, card.description)
		if #row == DEV_CARDS_PER_ROW then
			rows[#rows + 1] = hrow(row)
			row = {}
		end
	end
	if #row > 0 then rows[#rows + 1] = hrow(row) end
	rows[#rows + 1] = text("Money", "font-scale-body, quota-run-dev-section")
	rows[#rows + 1] = hrow({
		devButton("+$10M", "addMoney", 10000000, nil, active),
		devButton("-$10M", "addMoney", -10000000, nil, active),
		devButton("Bankrupt: red months", "bankrupt", nil, nil, active,
			"redMonths = limit - 1: the next month tick in the red ends the run (try Skip 1 month)"),
	})
	rows[#rows + 1] = text("Run", "font-scale-body, quota-run-dev-section")
	rows[#rows + 1] = hrow({
		devButton("Clear effects", "clearEffects", nil, nil, active),
		devButton("Reset run", "reset", nil, nil, active),
		devButton("Force start", "forceStart", nil, nil, inert,
			"Activate a run on this inert save (debug only; never in missions or the map editor). Use a copy of the save."),
		devButton("Dump state to log", "dump"),
	})
	return rows
end

local QuotaRunDevPanel = react.RegisterRecipe("QuotaRunDevPanel", function() : TreeNodeId
	-- Live status: the panel polls on its own (same hook and interval as the HUD).
	local state = engine_react_util.useStepStateTimer(getFromEngine, 0.5)
	return vbox(devRows(state:old()), "quota-run-dev-panel")
end)

local record QuotaRunDevWindowParam
	onClose : function()
end

local QuotaRunDevWindow = react.RegisterWrapperRecipe("QuotaRunDevWindow", builtin.Window, function(params : QuotaRunDevWindowParam) : TreeNodeId
	return builtin.Window{
		title = "Quota Run - Dev",
		closable = true,
		movable = true,
		initialX = 0.5,
		initialY = 0.5,
		onClose = params.onClose,
		content = QuotaRunDevPanel(),
	}
end)

local function closeDevWindow()
	local wa = game_react_globals.getDefaultWindowApi()
	if wa ~= nil then
		wa.removeAllWindows(QuotaRunDevWindow)
	end
end

local function openDevWindow()
	local wa = game_react_globals.getDefaultWindowApi()
	if wa == nil then
		log.warning("[QuotaRun] no window container for the dev panel; use the console helper (TESTING.md)")
		return
	end
	wa.addSingletonWindow(QuotaRunDevWindow, { onClose = closeDevWindow })
	wa.moveSingletonWindowToFront(QuotaRunDevWindow)
end

local function devOpenButton() : TreeNodeId
	return builtin.Button{
		meta = { class = "quota-run-dev-button" },
		content = text("Dev", "font-scale-annotation"),
		onClick = openDevWindow,
	}
end

--- One compact row for the ridge (default layout).
local function compactRow(v : QuotaRunHudView) : TreeNodeId
	local children : {TreeNodeId} = {}
	if v.phase == "inert" or v.phase == "sandbox" then
		-- DEBUG-only views (quota_hud_model): just a label and the Dev button.
		children[#children + 1] = text(v.phase == "inert" and "Quota Run: inert" or "Quota Run: sandbox", "font-scale-annotation")
	elseif v.phase == "ended" then
		children[#children + 1] = text(_("Quota Run: run over"), "font-scale-body, quota-run-warning")
		children[#children + 1] = builtin.Button{
			meta = { class = "primary" },
			content = text(_("Run over")),
			onClick = function() openEnd(v) end,
		}
	else
		local str = lang_util.format(_("Quota Run R{round}: {progress} / {quota}"), {
			round = tostring(v.round),
			progress = lang_util.formatInt(v.progress),
			quota = lang_util.formatInt(v.quota),
		})
		if v.monthsLeft ~= nil then
			str = str .. " - " .. lang_util.format(_("{months} mo left"), { months = tostring(v.monthsLeft) })
		end
		if v.provisional then str = str .. " " .. _("(provisional)") end
		children[#children + 1] = text(str)
		-- ProgressBar: value in [0, 1] (builtin.d.tl:1013-1018)
		children[#children + 1] = builtin.ProgressBar{
			meta = { class = "quota-run-progress" },
			value = v.fraction,
		}
		if v.redWarning then
			children[#children + 1] = text(lang_util.format(_("Red {n}/{max}"), {
				n = tostring(v.redMonths), max = tostring(v.bankruptMonths),
			}), "font-scale-body, quota-run-warning")
		end
		-- v2: short tags; the full descriptions are in the panel tooltip (roundInfoLines).
		if v.bossName ~= nil then
			-- v2.1 addendum: a boss's targeted rule (local_hero / specialist) names its target too.
			children[#children + 1] = text(lang_util.format(_("BOSS: {boss}"), { boss = withTarget(_(v.bossName), v) }),
				"font-scale-body, quota-run-boss")
		elseif v.ruleName ~= nil then
			children[#children + 1] = text(withTarget(_(v.ruleName), v), "font-scale-body, quota-run-rule")
		end
		if v.nextBossName ~= nil then
			children[#children + 1] = text(lang_util.format(_("Next: {boss}"), { boss = _(v.nextBossName) }),
				"font-scale-annotation, quota-run-next-boss")
		end
		if v.phase == "choosing" then
			children[#children + 1] = builtin.Button{
				meta = { class = "primary" },
				content = text(_("Pick a card")),
				onClick = function() openPicker(v) end,
			}
		end
	end
	if v.debug then
		children[#children + 1] = devOpenButton()
	end
	-- Tooltip: boss / rule / next boss descriptions (v2), then the picked cards.
	local tips = roundInfoLines(v)
	if #v.picked > 0 then tips[#tips + 1] = pickedLine(v) end
	return builtin.Component{
		meta = { class = "quota-run-panel, quota-run-compact", tooltip = #tips > 0 and table.concat(tips, "\n") or nil },
		layout = builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = children,
		},
	}
end

--- A plugin recipe's root must be a layout: MainModButtonArea mounts plugins as BoxLayout children,
--- and a Component root fails with "Recipe child must be a layout". Same shape as the base plugin
--- (.cache/game/base/content/gui/game_bar/game_bar_display_transported_plugin/game_bar_display_transported.tl:28).
local function pluginRoot(child : TreeNodeId) : TreeNodeId
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = { child },
	}
end

local QuotaRunHudPlugin = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension, "QuotaRunHudPlugin", function() : TreeNodeId
	-- Hooks first, unconditionally (same order as the transported plugin).
	local isMapEditorRef : ReactRefT<boolean> = react.useRefLazy(function() : boolean return api.gui.game.isMapEditor() end)
	-- src: .cache/game/base/content/gui/main/engine_react_util.tl:126-145 (0.5 s, deepEquals)
	local state = engine_react_util.useStepStateTimer(getFromEngine, 0.5)
	-- Inline dev section toggle (GUI_INLINE_PICKER + DEBUG). src: .cache/game/base/content/gui/music_player/music_player.tl:267
	local devOpen = react.useState(false) as ReactStateT<boolean>

	if isMapEditorRef:get() then
		return nil
	end
	local v = state:old()
	if v == nil then
		return nil
	end

	if not config.GUI_INLINE_PICKER then
		return pluginRoot(compactRow(v))
	end

	-- GUI_INLINE_PICKER = true: the old inline vertical panel (may be clipped by the ridge).
	local rows : {TreeNodeId}
	if v.phase == "inert" or v.phase == "sandbox" then
		rows = { text(v.phase == "inert" and "Quota Run: inert" or "Quota Run: sandbox", "font-scale-body") }
	elseif v.phase == "ended" then
		rows = endRows(v)
	else
		rows = hudRows(v)
		if v.phase == "choosing" then
			for __, row in ipairs(pickerRows(v)) do rows[#rows + 1] = row end
		end
	end
	if v.debug then
		rows[#rows + 1] = builtin.Button{
			meta = { class = "quota-run-dev-button" },
			content = text(devOpen:old() and "Dev (hide)" or "Dev", "font-scale-annotation"),
			onClick = function() devOpen:set(not devOpen:old()) end,
		}
		if devOpen:old() then
			for __, row in ipairs(devRows(v)) do rows[#rows + 1] = row end
		end
	end

	-- Root sized to content (no full-screen panel; it must not cover the map).
	return pluginRoot(builtin.Component{
		meta = { class = "quota-run-panel" },
		layout = vbox(rows),
	})
end)

local result = {
	QuotaRunHudPlugin = QuotaRunHudPlugin,
}

return result
