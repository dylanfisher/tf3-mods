function data()
return { 
		availability = { 
			yearFrom = 0,
			yearTo = 1940,
		},
		borderGroundTex = "::/infrastructure/street/shared/town_street_border.gtex",
		cost = 80,
		description = { 
			description = _("SQUARE_OWR_ONE_WAY_TOWN_OLD_MEDIUM_DESC"),
			icon = "one_way_town_old_medium.tga",
			name = _("SQUARE_OWR_ONE_WAY_TOWN_OLD_MEDIUM_NAME"),
			previewIcon = "::/infrastructure/street/town/town_old_medium_preview.tga",
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
				offset = 0,
				speed = 11.11,
				transportModes = { "CAR", "BUS", "TRUCK", },
				width = 4,
			},
			{ 
				forward = true,
				height = 0,
				offset = 0,
				speed = 11.11,
				transportModes = { "CAR", "BUS", "TRUCK", },
				width = 4,
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
		maintenanceCost = 13,
		menuCategory = { 
			categories = {
				{ 
					category = "roads_medium",
					filterCategories = { },
					order = 185,
				},
			},
		},
		modifiers = { 
			maxSpeedModifier = 0,
			noiseModifier = 0,
			pollutionModifier = 0,
		},
		priority = 330,
		roadType = "STREET",
		sidewalkFillGroundTex = "::/infrastructure/street/shared/street_sidewalk_fill.gtex",
		streetStyle = "::/infrastructure/street/town/town_old.street",
		builderAudioRes = "::/gui/construction/sound/buildoze_street.builder_audio",
	}
end
