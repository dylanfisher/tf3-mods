-- Roundabouts & Interchanges: the bridge of the "Structure: Bridge" setting from 1970
-- (square_roundabouts_result.lua result.structureBridgeType). A copy of base concrete.bridge.lua
-- (Urban Games) with pillars every 12-24 m instead of 60-84 m: a roundabout's ring and arm pieces are
-- 15-30 m long, so base concrete gives them no pillars at all (a floating deck, in game 2026-10-22,
-- docs/findings/roads.md). Only the lines marked "changed" differ. Every base path is prefixed "::/":
-- in a mod a plain "/" path means the mod's own folder, and a missing bridge model crashes the game on
-- build (docs/findings/scripting.md 2026-10-22). tests/square_roundabouts/test_structure.lua checks
-- every path. Hidden from the player's bridge menu as base placeholder.bridge.lua (yearFrom / yearTo
-- -1: gui/main/menu_category_util.tl getAvailableObjectsSorted skips it); constructions name it by
-- edgeTypeName (plans/square_roundabouts/PLAN.md "Structure").
local bridgeutil = require "::/infrastructure/bridge/bridgeutil2.lua"

function data()

local newdir = "::/infrastructure/bridge/concrete/" -- changed: ::

local c_6_rep_l = {
	newdir .. "c_6_rep_l.mdl",
	{ { 0, -0.8, -2.4 }, { 6, 0, 1.1 } },
}
local c_6_rep_low_l = {
	newdir .. "c_6_rep_low_l.mdl",
	{ { 0, -0.8, -2.4 }, { 6, 0, 0.1 } },
}
local c_6_rep_low_r = {
	newdir .. "c_6_rep_low_r.mdl",
	{ { 0, 0, -2.4 }, { 6, 0.8, 0.1 } },
}
local c_6_rep_r = {
	newdir .. "c_6_rep_r.mdl",
	{ { 0, 0, -2.4 }, { 6, 0.8, 1.1 } },
}
local c_6_rep_rep = {
	newdir .. "c_6_rep_rep.mdl",
	{ { 0, 0, -2.4 }, { 6, 4, 0 } },
}
local c_abut_bot_l = {
	newdir .. "c_abut_bot_l.mdl",
	{ { -0.1, -1.3, -1 }, { 2.9, 0, 3 } },
}
local c_abut_bot_m = {
	newdir .. "c_abut_bot_m.mdl",
	{ { -0.1, 0, -1 }, { 2.9, 4, 3 } },
}
local c_abut_bot_r = {
	newdir .. "c_abut_bot_r.mdl",
	{ { -0.1, 0, -1 }, { 2.9, 1.3, 3 } },
}
local c_abut_rep_l = {
	newdir .. "c_abut_rep_l.mdl",
	{ { -0.1, -1.3, 0 }, { 2.9, 0, 4 } },
}
local c_abut_rep_m = {
	newdir .. "c_abut_rep_m.mdl",
	{ { -0.1, 0, 0 }, { 2.9, 4, 4 } },
}
local c_abut_rep_r = {
	newdir .. "c_abut_rep_r.mdl",
	{ { -0.1, 0, 0 }, { 2.9, 1.3, 4 } },
}
local c_abut_top_l = {
	newdir .. "c_abut_top_l.mdl",
	{ { -0.1, -1.3, -2 }, { 2.9, 0, 0.1 } },
}
local c_abut_top_m = {
	newdir .. "c_abut_top_m.mdl",
	{ { -0.1, 0, -2 }, { 2.9, 4, 0.1 } },
}
local c_abut_top_r = {
	newdir .. "c_abut_top_r.mdl",
	{ { -0.1, 0, -2 }, { 2.9, 1.3, 0.1 } },
}
local c_pillar_small_bot_l = {
	newdir .. "c_pillar_small_bot_l.mdl",
	{ { -1.5, -0.4, -0.5 }, { 1.5, 1, 3.4 } },
}
local c_pillar_small_bot_m = {
	newdir .. "c_pillar_small_bot_m.mdl",
	{ { -1.5, 0, -0.5 }, { 1.5, 3, 3.4 } },
}
local c_pillar_small_bot_r = {
	newdir .. "c_pillar_small_bot_r.mdl",
	{ { -1.5, -1, -0.5 }, { 1.5, 0.4, 3.4 } },
}
local c_pillar_small_rep_l = {
	newdir .. "c_pillar_small_rep_l.mdl",
	{ { -1.5, -0.4, 0 }, { 1.5, 1, 4 } },
}
local c_pillar_small_rep_m = {
	newdir .. "c_pillar_small_rep_m.mdl",
	{ { -1.5, 0, 0 }, { 1.5, 3, 4 } },
}
local c_pillar_small_rep_r = {
	newdir .. "c_pillar_small_rep_r.mdl",
	{ { -1.5, -1, 0 }, { 1.5, 0.4, 4 } },
}
local c_pillar_small_top_l = {
	newdir .. "c_pillar_small_top_l.mdl",
	{ { -1.5, -1.4, -4 }, { 1.5, 1, -2.1 } },
}
local c_pillar_small_top_m = {
	newdir .. "c_pillar_small_top_m.mdl",
	{ { -1.5, 0, -4 }, { 1.5, 3, -2.3 } },
}
local c_pillar_small_top_r = {
	newdir .. "c_pillar_small_top_r.mdl",
	{ { -1.5, -1, -4 }, { 1.5, 1.4, -2.1 } },
}

local config = {
	pillarBase = { c_pillar_small_bot_l, c_pillar_small_bot_m, c_pillar_small_bot_r },
	pillarRepeat = { c_pillar_small_rep_l, c_pillar_small_rep_m, c_pillar_small_rep_r },
	pillarTop = { c_pillar_small_top_l, c_pillar_small_top_m, c_pillar_small_top_r },

	abutmentBase = { c_abut_bot_l, c_abut_bot_m, c_abut_bot_r },
	abutmentRepeat = { c_abut_rep_l, c_abut_rep_m, c_abut_rep_r },
	abutmentTop = { c_abut_top_l, c_abut_top_m, c_abut_top_r },
	--[[
	railingBegin = 
	{
		-- side left
		c_6_end_rep_l,
		c_6_end_rep_l,
		c_6_end_rep_low_l,
		-- rep
		c_6_end_rep_rep,
		c_6_end_rep_rep,
		-- side right
		c_6_end_rep_r,
		c_6_end_rep_r,
		c_6_end_rep_low_r,
	},
	]]--
	railingRepeat = 
	{
		-- side left
		c_6_rep_l,
		c_6_rep_l,
		c_6_rep_low_l,
		-- rep
		c_6_rep_rep,
		c_6_rep_rep,
		-- side right
		c_6_rep_r,
		c_6_rep_r,
		c_6_rep_low_r,
	},
	--[[
	railingEnd = 
	{
		-- side left
		c_6_start_rep_l,
		c_6_start_rep_l,
		c_6_start_rep_low_l,
		-- rep
		c_6_start_rep_rep,
		c_6_start_rep_rep,
		-- side right
		c_6_start_rep_r,
		c_6_start_rep_r,
		c_6_start_rep_low_r,
	},
	]]
}

return {
	description = {
		name = _("Concrete, short spans"), -- changed
		icon = "::/infrastructure/bridge/concrete.tga", -- changed: ::
	},
	availability = { -- changed: never in the bridge menu (as base placeholder.bridge.lua)
		yearFrom = -1, -- changed
		yearTo = -1, -- changed
	},

	menuCategory = {
		categories = {
			{
				order = 50,
			},
		},
	},

	carriers = { "RAIL" , "ROAD"},

	speedLimit = 280.0 / 3.6,
	
	pillarLen = 4,
	
	pillarMinDist = 12.0, -- changed
	pillarMaxDist = 24.0, -- changed
	pillarTargetDist = 16.0, -- changed
	noParallelStripSubdivision = true,

	abutmentLen = 4.0,

	cost = 200.0,
	costFactors = { 10.0, 2.5, 1.0 },
	
	pillarGroundTexture = "::/terrain/materials/dirt/dirt.gtex", -- changed: ::
	pillarGroundTextureOffset = 2.0,
	
	materialsToReplace = {
		streetPaving = {
			name = "::/infrastructure/street/town/mat/town_new_street_paving.mtl",
			size = { 6.0, 6.0 }
		},
		streetLane = {
			name = "::/infrastructure/street/town/mat/town_new_streetlane.mtl",
			size = { 4.0, 5.0 }
		},
		crossingLane = {
			name = "::/infrastructure/street/town/mat/town_new_streetlane.mtl",
		},
		sidewalkPaving = {
			name = "::/infrastructure/street/town/mat/new_medium_sidewalk_paving.mtl",
			size = {32.0,32.0}
		},
		sidewalkBorderInner = {
			name = "::/infrastructure/street/town/mat/new_town_sw_in.mtl",
			size = { 24, 1.5 }
		},
		sidewalkBorderOuter = {
			name = "::/infrastructure/street/town/mat/new_town_sw_in.mtl",
			size = { 24, 1.5 },
			reversed = true,
		},
		sidewalkCurb = {
			name = "::/infrastructure/street/town/mat/new_town_sw_curb.mtl",
			size = { 24, .35 }
		},
		sidewalkWall  = {
			name = "::/infrastructure/street/town/mat/new_town_sw_curb.mtl",
			size = {24,0.35}
		},
	},
	
	updateScript = {
		fileName = "::/infrastructure/bridge/bridge.script@placeholder.updateFn",
		params = config
	},
}
end
