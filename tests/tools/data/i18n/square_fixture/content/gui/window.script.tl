-- Fixture for tests/tools/test_i18n.py: every extraction case, one per line. _("in a comment") is not a key.
local LABELS = {
	small = "Small", -- i18n: keys
	large = "Large", -- i18n: keys
}
local ROWS = {
	-- i18n: keys begin label
	{ key = "a", label = "Alpha row" },
	{ key = "b", label = "Beta row" },
	-- i18n: keys end
}

local function build(n: integer, name: string, kind: string): {string}
	local out = {
		_("Filter"),
		_('Single quoted'),
		_("Tab\tquote\" backslash\\ newline\n end"),
		_("caf\u{E9} \65\x42"),
		_([[Long
string]]),
		_ "Call without parens",
		_ [==[Level two ]] inside]==],
		_("{n} vehicles"),
		_("%d of %s"),
		_("Filter"),
		foo_("Not a key: foo_"),
		obj._("Not a key: field"),
		obj:_("Not a key: method"),
		_(name),
		_("Prefix " .. name),
		_(string.format("%d", n)),
		_(LABELS[kind]), -- i18n: ignore
		_("Total:") .. " " .. tostring(n) .. " " .. _("items"),
		_("Speed") .. " km/h",
		_("Name") .. ": " .. name,
	}
	local view = { text = "Untranslated title", tooltip = _("Translated tip"), title = "font-scale-body" }
	local t = text("Raw text call")
	local s = text("Ignored literal") -- i18n: ignore
	local w = api.gui.comp.TextView.new("Raw constructor")
	return out
end

local function _(s: string): string return s end
for _, row in ipairs(ROWS) do print(row) end
