-- production_label_shift: when the pills show for "Show only while holding Shift" (PLAN "Show only while
-- holding Shift (2026-10-19)"): Shift held with an allowed top tool, the selected (window open)
-- constructions counted per window, not installed = always, and toConstruction.

local CON, PART, LONE = 100, 101, 300

set_global("api", {
	type = { ComponentType = { CONSTRUCTION = 2 } },
	engine = {
		getComponent = function(e, ct)
			if ct == 2 and e == CON then return {} end
			return nil
		end,
		system = {
			streetConnectorSystem = {
				getConstructionEntityForSubconstruction = function(e)
					if e == PART then return CON end
					return -1
				end,
			},
		},
	},
})

local shift = ug_require "square_industry_production_label::/production_label/production_label_shift.tl"

before_each(function()
	shift.reset()
	shift.installed = true
end)

test("not installed (no entry point in this Lua state): every label shows", function()
	shift.installed = false
	ok(shift.isShown(CON))
	ok(shift.isShown(nil))
end)

test("nothing held, nothing selected: hidden", function()
	eq(shift.isShown(CON), false)
	eq(shift.isShown(nil), false)
end)

test("Shift held on the map, in an entity window or in Passenger Destinations' Shift tool: every label shows", function()
	for _, tool in ipairs({ "EntityDetailsTool", "SquarePassengerDestinations" }) do
		eq(shift.update(true, tool), true)
		ok(shift.isShown(CON) and shift.isShown(LONE), tool)
	end
	eq(shift.update(false, "EntityDetailsTool"), false)
	eq(shift.isShown(CON), false)
end)

test("Shift held in another tool (building, line manager, layers) or an unknown one: hidden", function()
	for _, tool in ipairs({ "ConstructionTool", "Manager", "LayersTool" }) do
		eq(shift.update(true, tool), false, tool)
	end
	eq(shift.update(true, nil), false)
	eq(shift.isShown(CON), false)
end)

test("selected: shown while any of its windows is open, counted per window", function()
	shift.opened(CON)
	ok(shift.isShown(CON))
	eq(shift.isShown(LONE), false)
	shift.opened(CON)
	shift.closed(CON)
	ok(shift.isShown(CON), "second window still open")
	shift.closed(CON)
	eq(shift.isShown(CON), false)
	shift.closed(CON) -- an extra close is harmless
	eq(shift.selected[CON], nil)
end)

test("opened / closed ignore nil and negative", function()
	shift.opened(nil)
	shift.opened(-1)
	shift.closed(nil)
	eq(next(shift.selected), nil)
end)

test("toConstruction: a construction itself, a part its construction, anything else itself; -1 for nil / negative", function()
	eq(shift.toConstruction(CON), CON)
	eq(shift.toConstruction(PART), CON)
	eq(shift.toConstruction(LONE), LONE)
	eq(shift.toConstruction(-5), -1)
	eq(shift.toConstruction(nil), -1)
end)
