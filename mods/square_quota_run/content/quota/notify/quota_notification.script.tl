-- Quota Run notifications (GUI thread, read-only). Sent by quota_effects.notify as
-- type "square_quota_run::/quota/notify/quota_notification.script" with
-- params = QuotaRunNotificationParams (key + the logic's notify params).
-- Modelled on .cache/game/base/content/game_mechanics/company/company_notification_rank_up.script.tl;
-- the popup/log call "<type>@useDataState" (.cache/game/base/content/game_mechanics/notifications/gui/notification_popups.tl:62).
-- Contract: .cache/game/base/tealdef/game_mechanics/notifications/notifications.d.tl:4-49.

-- src: .cache/game/base/tealdef/scripts/lang_util.d.tl:3-7 (format, formatInt)
local lang_util = ug_require "::/scripts/lang_util.tl" as LangUtil
-- v2.1 (PLAN §9.3, §9.4): data-only modules (no api.*), safe on the GUI thread.
local rules = ug_require "square_quota_run::/quota/quota_rules.tl" as QuotaRunRules
local bosses = ug_require "square_quota_run::/quota/quota_bosses.tl" as QuotaRunBosses
-- v2.1 addendum: rule-target names (engine lookups, nil-safe), shared with the HUD.
local target_names = ug_require "square_quota_run::/quota/gui/quota_target_names.tl" as QuotaRunTargetNames

local ICON_DIR <const> = "::/game_mechanics/notifications/gui/icons/"
-- Icons referenced by base notification scripts (so they exist in every install):
-- company_rank_up (company_notification_rank_up.script.tl:17), symbol_dollar (mission/notification.script.tl:38),
-- line_cargo_minus_unload (types/cargo_rtc_warning.script.tl:38), building_industry_x (company_notification_prospection.script.tl:64)
local ICON_START <const> = ICON_DIR .. "company_rank_up.tga"
local ICON_MONEY <const> = ICON_DIR .. "symbol_dollar.tga"
local ICON_WARN <const> = ICON_DIR .. "line_cargo_minus_unload.tga"
local ICON_OVER <const> = ICON_DIR .. "building_industry_x.tga"

--- Integer text; params may come back as floats after the event round trip.
local function int(v : any) : string
	if type(v) ~= "number" then return "?" end
	return lang_util.formatInt(math.floor(v as number) as integer)
end

local function money(v : any) : string
	if type(v) ~= "number" then return "?" end
	-- src: .cache/game/api/tealdef/api/util.d.tl:55-58 (formatMoney)
	return api.util.formatMoney(math.floor(v as number) as integer)
end

--- v2: "<name> - <description>" (trailing period dropped: the sentence template adds one);
--- the lookups below return nil for nil / unknown ids (never an error).
local function nameAndDescription(name : string, description : string) : string
	if description == nil or description == "" then return _(name) end
	local d = _(description):gsub("%.%s*$", "")
	return _(name) .. " - " .. d
end

local function ruleText(id : any) : string
	if type(id) ~= "string" or rules == nil or rules.byId == nil then return nil end
	local rule = rules.byId[id as string]
	return rule and nameAndDescription(rule.name, rule.description) or nil
end

local function bossText(id : any) : string
	if type(id) ~= "string" or bosses == nil or bosses.byId == nil then return nil end
	local boss = bosses.byId[id as string]
	return boss and nameAndDescription(boss.name, boss.description) or nil
end

--- v2.1 addendum: "Target town: X." / "Target cargo: X." for a rule with a target; nil when the
--- rule has no target, the id is missing or the name can't be resolved.
local function targetText(ruleId : any, target : any) : string
	if type(ruleId) ~= "string" or type(target) ~= "number" or rules == nil or rules.byId == nil then return nil end
	local rule = rules.byId[ruleId as string]
	if rule == nil then return nil end
	local name = target_names.resolve(rule.target, target as integer)
	if name == nil then return nil end
	if rule.target == "town" then
		return lang_util.format(_("Target town: {town}. Only deliveries into it count."), { town = name })
	elseif rule.target == "cargoType" then
		return lang_util.format(_("Target cargo: {cargo}."), { cargo = name })
	end
	return nil
end

--- roundStart: the base text plus the boss / rule of this round and next round's boss.
local function roundStartDescription(p : QuotaRunNotificationParams) : string
	local parts : {string} = {
		lang_util.format(_("Move {quota} units within {months} months."),
			{ quota = int(p.quota), months = int(p.months) }),
	}
	local boss = bossText(p.boss)
	if boss ~= nil then
		parts[#parts + 1] = lang_util.format(_("Boss round: {boss}."), { boss = boss })
	end
	local rule = ruleText(p.rule)
	if rule ~= nil then
		parts[#parts + 1] = lang_util.format(_("Scoring rule: {rule}."), { rule = rule })
		local target = targetText(p.rule, p.ruleTarget)
		if target ~= nil then parts[#parts + 1] = target end
	end
	local nextBoss = bossText(p.nextBoss)
	if nextBoss ~= nil then
		parts[#parts + 1] = lang_util.format(_("Next round's boss: {boss}."), { boss = nextBoss })
	end
	return table.concat(parts, " ")
end

local data : NotificationType<QuotaRunNotificationParams> = {}

data.useDataState = function(p : QuotaRunNotificationParams) : NotificationGuiData
	p = p or {}
	local key = p.key
	if key == "roundStart" then
		return {
			title = bossText(p.boss) ~= nil
				and lang_util.format(_("Boss round {round} started"), { round = int(p.round) })
				or lang_util.format(_("Round {round} started"), { round = int(p.round) }),
			description = roundStartDescription(p),
			icon = ICON_START,
		}
	elseif key == "roundCleared" then
		return {
			title = lang_util.format(_("Round {round} cleared"), { round = int(p.round) }),
			description = lang_util.format(_("Quota met with {progress} of {quota} units. Reward: {reward}. Pick a card."),
				{ progress = int(p.progress), quota = int(p.quota), reward = money(p.reward) }),
			icon = ICON_MONEY,
		}
	elseif key == "halfway" then
		return {
			title = _("Quota behind schedule"),
			description = lang_util.format(_("Half the time of round {round} is gone and only {progress} of {quota} units are moved. {months} months left."),
				{ round = int(p.round), progress = int(p.progress), quota = int(p.quota), months = int(p.months) }),
			icon = ICON_WARN,
		}
	elseif key == "bankruptWarn" then
		return {
			title = _("Company in the red"),
			description = lang_util.format(_("Your balance has been negative for {redMonths} months. {monthsLeft} more and the run ends in bankruptcy."),
				{ redMonths = int(p.redMonths), monthsLeft = int(p.monthsLeft) }),
			icon = ICON_MONEY,
		}
	elseif key == "runOver" then
		local reason = p.reason == "bankrupt" and _("The company went bankrupt.") or _("The quota was missed.")
		return {
			title = _("Run over"),
			description = reason .. " " .. lang_util.format(_("Rounds cleared: {rounds}. Units moved: {total}."),
				{ rounds = int(p.rounds), total = int(p.total) }),
			icon = ICON_OVER,
		}
	end
	return {
		title = _("Quota Run"),
		description = "",
		icon = ICON_START,
	}
end

return data
