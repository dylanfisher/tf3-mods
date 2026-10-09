function data()
return { 
		availability = { 
			yearFrom = 0,
			yearTo = 1940,
		},
		borderGroundTex = "::/infrastructure/street/shared/old_country_border.gtex",
		cost = 40,
		country = true,
		defaultWithCrosswalk = false,
		description = { 
			description = _("SQUARE_OWR_ONE_WAY_COUNTRY_OLD_SMALL_DESC"),
			icon = "one_way_country_old_small.tga",
			name = _("SQUARE_OWR_ONE_WAY_COUNTRY_OLD_SMALL_NAME"),
			previewIcon = "::/infrastructure/street/country/country_old_small_preview.tga",
		},
		emissions = { 
			noise = 0,
			pollution = 0,
			pollutionRadius = 0,
			radius = 0,
		},
		fillGroundTex = "::/infrastructure/street/shared/old_country_fill.gtex",
		laneConfigs = {
			{ 
				forward = false,
				height = 0,
				offset = -1,
				speed = 16.67,
				transportModes = { "PERSON", "CARGO", },
				width = 2,
			},
			{ 
				forward = true,
				height = 0,
				offset = -0.5,
				speed = 16.67,
				transportModes = { "CAR", "BUS", "TRUCK", },
				width = 5,
			},
			{ 
				forward = true,
				height = 0,
				offset = 0.5,
				speed = 16.67,
				transportModes = { "CAR", "BUS", "TRUCK", },
				width = 5,
			},
			{ 
				forward = true,
				height = 0,
				offset = 1,
				speed = 16.67,
				transportModes = { "PERSON", "CARGO", },
				width = 2,
			},
		},
		maintenanceCost = 7,
		menuCategory = { 
			categories = {
				{ 
					category = "roads_country",
					filterCategories = { },
					order = 435,
				},
			},
		},
		modifiers = { 
			maxSpeedModifier = 0,
			noiseModifier = 0,
			pollutionModifier = 0,
		},
		pedestrianWalkPenalty = true,
		priority = 95,
		roadType = "STREET",
		sidewalkFillGroundTex = "::/infrastructure/shared/none.gtex",
		streetStyle = "::/infrastructure/street/country/country_old.street",
		builderAudioRes = "::/gui/construction/sound/buildoze_street.builder_audio",
	}
end
