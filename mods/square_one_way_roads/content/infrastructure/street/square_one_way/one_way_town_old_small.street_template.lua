function data()
return { 
		availability = { 
			yearFrom = 0,
			yearTo = 1940,
		},
		borderGroundTex = "::/infrastructure/street/shared/town_street_border.gtex",
		cost = 40,
		description = { 
			description = _("SQUARE_OWR_ONE_WAY_TOWN_OLD_SMALL_DESC"),
			icon = "one_way_town_old_small.tga",
			name = _("SQUARE_OWR_ONE_WAY_TOWN_OLD_SMALL_NAME"),
			previewIcon = "::/infrastructure/street/town/town_old_small_preview.tga",
		},
		emissions = { 
			noise = 0,
			pollution = 0,
			pollutionRadius = 0,
			radius = 0,
		},
		fillGroundTex = "::/infrastructure/street/shared/town_street_fill.gtex",
		laneConfigs = {
			{ 
				forward = false,
				height = 0.15,
				offset = 0.15,
				speed = 11.11,
				transportModes = { "PERSON", "CARGO", },
				width = 3,
			},
			{ 
				forward = true,
				height = 0,
				offset = -0.5,
				speed = 11.11,
				transportModes = { "CAR", "BUS", "TRUCK", },
				width = 5,
			},
			{ 
				forward = true,
				height = 0,
				offset = 0.5,
				speed = 11.11,
				transportModes = { "CAR", "BUS", "TRUCK", },
				width = 5,
			},
			{ 
				forward = true,
				height = 0.15,
				offset = -0.15,
				speed = 11.11,
				transportModes = { "PERSON", "CARGO", },
				width = 3,
			},
		},
		maintenanceCost = 7,
		menuCategory = { 
			categories = {
				{ 
					category = "roads_small",
					filterCategories = { },
					order = 15,
				},
			},
		},
		modifiers = { 
			maxSpeedModifier = 0,
			noiseModifier = 0,
			pollutionModifier = 0,
		},
		priority = 310,
		roadType = "STREET",
		sidewalkFillGroundTex = "::/infrastructure/street/shared/street_sidewalk_fill.gtex",
		streetStyle = "::/infrastructure/street/town/town_old.street",
		builderAudioRes = "::/gui/construction/sound/buildoze_street.builder_audio",
	}
end
