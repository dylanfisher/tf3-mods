---
title: Base Config
page_id: modding:scripting:baseconfig
source: https://wiki.transportfever3.com/doku.php?id=modding:scripting:baseconfig
---

> **Wip:**
>
> This page is not yet adapted for Transport Fever 3. The content may be outdated.

# Base Config

Global properties that are relevant for the simulation and gameplay aspects are defined in the `config` struct. It's initial values are loaded from the `base_config.lua` file in the `res/config/` folder.

To set new values for the properties, call:

- `game.config.<property> = <new value>` in the `runFn` function.
- `api.res.getBaseConfig().<property> = <new value>` in the `postRunFn` function.

To read values from the properties, call:

- `game.config.<property>` in the `runFn` function.
- `api.res.getBaseConfig().<property>` in `postRunFn` or game scripts.

Calling `game.config.<property>` outside of the `runFn` will respond with outdated data and should not be used.

## Config variables

| Property | Default Value | Description |
| --- | --- | --- |
| Costs (not available with getBaseConfig()) | | |
| cost.terrainRaise | 0.75 \* 6.0 | Cost per m³ to raise the land |
| cost.terrainLower | 0.75 \* 7.0 | Cost per m³ to lower the land |
| cost.railroadCatenary | 0.3 | Fraction of track building cost for catenary construction |
| cost.roadBusLane | 0.1 | Fraction of street building cost for bus lane construction |
| cost.roadTramLane | 0.2 | Fraction of street building cost for tram lane construction |
| cost.roadElectricTramLane | 0.4 | Fraction of street building cost for electric tram lane construction |
| cost.bulldozeRefundTimeOut | 60 | Time after construction, in which a certain fraction of the building costs is refunded |
| cost.bulldozeRefundFactor | 0.75 | Fraction of construction cost that is refunded while still in time |
| cost.removeField | 200000 | Bulldozing cost for removal of farm fields. |
| Construction Function (not available with getBaseConfig()) | | |
| ConstructWithModules | <function> | Function that is called for every construction during placement. See the [explanation of constructions](../../modding/constructions/modular.md#method_cycle) for more information. |
| Scaffolding (not available with getBaseConfig()) | | |
| scaffold.<era>.scaffold | <list> | List with two model references relative to `res/models/`. The first references the normal scaffolding element, the second is a reference to an element with a ladder. |
| scaffold.<era>.crane | <list> | List with five models that are used to construct the crane that is displayed during town building construction. |
| Terrain Tools | | |
| terrainToolMinStrength | 5 | Minimum limit of the strength slider |
| terrainToolMaxStrength | 100 | Maximum limit of the strength slider |
| terrainToolMaxSize | 16 | Maximum terrain tool size in game (large values may result in performance issues!) |
| terrainPainterMaxSize | 256 | Maximum paint tool size in game |
| terrainToolMaxSizeEditor | 256 | Maximum terrain tool size in map editor |
| terrainPainterMaxSizeEditor | 256 | Maximum paint tool size in map editor |
| assetBrushMaxSize | 256 | Maximum asset brush tool size |
| GUI | | |
| gui.layers.defaultColors.baseTerrainColor | { 0.82, 0.82, 0.82, 1.0 } | The default terrain color used in most data layers. |
| gui.layers.defaultColors.baseWaterColorFactors | { 0.5, 0.5, 0.5, 0.25 } | A vector of four factors that alter the default water color relative to the baseTerrainColor property. |
| gui.layers.defaultColors.entityColorFactor | 0.33 | Factor that darkens streets, tracks & bridges. |
| gui.layers.contourLines.numLevels | 6 | Number of color levels of the contour lines data layer. |
| gui.layers.contourLines.baseTerrainColor | { 0.82, 0.82, 0.82, 1.0 } | Base color that is used for the contour lines layer. |
| gui.layers.contourLines.baseEntityColor | { 1.0, 1.0, 1.0, 1.0 } | Color that is used for buildings, vehicles, rocks and trees. |
| gui.layers.contourLines.terrainMinColor | {.82,.82,.82,1 } | Color that is used for the lowest terrain level. |
| gui.layers.contourLines.terrainMaxColor | {.235,.54,.25,1 } | Color that is used for the highest terrain level. |
| gui.layers.contourLines.waterColor | {.47, .64, .76, 1.0 } | Color that is used for the water. |
| gui.layers.contourLines.contours | <list> | A list of 4 contour line definitions with different names, colors, levels, widths and fade out distances. |
| gui.layers.navigableWaters.baseEntityColor | { 1.0, 1.0, 1.0, 1.0 } | Color that is used for buildings, vehicles, rocks and trees. |
| gui.layers.navigableWaters.navigableWaterColor | { 0.435, 0.827, 0.380, 1.0} | Color that is used for navigable waters. |
| gui.layers.navigableWaters.baseWaterColor | { 0.318, 0.494, 0.600, -0.85} | Color that is used for non-navigable waters. The negative alpha value indicates that the color is drawn underneath the navigable water color. |
| gui.layers.landUse.baseEntityColor | { 1.0, 1.0, 1.0, 1.0 } | Color that is used for buildings, vehicles, rocks and trees. |
| gui.layers.landUse.residentialColors | <list> | A list of 2 colors that are used for the residential buildings. The first is the minimum color, used for level 1 buildings, the second is the maximum color, used for level 4 buildings. |
| gui.layers.landUse.commercialColors | <list> | Like above but for commerical buildings. |
| gui.layers.landUse.industrialColors | <list> | Like above but for industrial buildings. |
| gui.layers.trackSpeedLimits.baseEntityColor | { 1.0, 1.0, 1.0, 1.0 } | Color that is used for buildings, vehicles, rocks and trees. |
| gui.layers.trackSpeedLimits.numLevels | 5 | Number of color levels of the speed limits data layer. |
| gui.layers.trackSpeedLimits.tunnelOutlineSize | 2.0 | Size of the tunnel outline. |
| gui.layers.trackSpeedLimits.tunnelOutlineColor | { 0.0, 0.0, 0.0, 0.3 } | Color that is used for the tunnel outline. |
| gui.layers.trackSpeedLimits.speedLimitColors | <list> | A list of 3 colors that are used for the track speed limits. The first color is used for very bad speeds, the second for neutral speeds and the third for very good speeds. |
| gui.layers.destinations.baseEntityColor | { 1.0, 1.0, 1.0, 1.0 } | Color that is used for buildings, vehicles, rocks and trees. |
| gui.layers.destinations.residentialColor | { 0.4, 0.4, 0.4, 1.0 } | Color that is used for residential buildings. |
| gui.layers.destinations.destinationColor | { 1.0, 1.0, 1.0, 1.0 } | Color that is used for destinations. |
| gui.layers.destinations.publicTransportColors | <list> | A list of 2 colors that are used for public transport. The first is the minimum color, the second is the maximum color. |
| gui.layers.destinations.privateTransportColors | <list> | Like above but for private transport. |
| gui.layers.destinations.numTransportLevels | 5 | Number of color levels of the destinations data layer. |
| gui.layers.cargo.baseEntityColor | { 1.0, 1.0, 1.0, 1.0 } | Color that is used for buildings, vehicles, rocks and trees. |
| gui.layers.cargo.transportColors | <list> | A list of 2 colors that are used for transport routes. The first is the minimum color, the second is the maximum color. |
| gui.layers.cargo.residentialColors | <list> | A list of 2 colors that are used for residential buildings. The first is the minimum color, the second is the maximum color. This property does not have an effect unless there are residential buildings that accept cargo. |
| gui.layers.cargo.commercialColors | <list> | A list of 2 colors that are used for commercial buildings. The first is the minimum color, the second is the maximum color. |
| gui.layers.cargo.industrialColors | <list> | Like above but for industrial buildings. |
| gui.layers.cargo.numTransportLevels | 5 | Number of color levels for transport routes. |
| gui.layers.cargo.numBuildingLevels | 3 | Number of color levels for the buildings. |
| gui.layers.stations.baseEntityColor | { 1.0, 1.0, 1.0, 1.0 } | Color that is used for buildings, vehicles, rocks and trees. |
| gui.layers.stations.stationColors | <list> | A list of 3 colors that are used for the stations. The first color is used for very overloaded stations, the second for neutral stations and the third for very good stations. |
| gui.layers.stations.numLevels | 5 | Number of color levels of the stations data layer. |
| gui.layers.streetTraffic.baseEntityColor | { 1.0, 1.0, 1.0, 1.0 } | Color that is used for buildings, vehicles, rocks and trees. |
| gui.layers.streetTraffic.trafficColors | <list> | A list of 3 colors that are used for the streets. The first color is used for very congested streets, the second for neutral streets and the third for very good streets. |
| gui.layers.streetTraffic.numLevels | 5 | Number of color levels of the street traffic data layer. |
| gui.layers.emissions.baseTerrainColor | { 0.82, 0.82, 0.82, 1.0 } | The terrain color used in the emissions data layer. |
| gui.layers.emissions.baseEntityColor | { 1.0, 1.0, 1.0, -1.0 } | Color that is used for buildings, vehicles, rocks and trees. The negative alpha value indicates that the color is drawn underneath the emissions color. |
| gui.layers.emissions.residentialColor | { 0.4, 0.4, 0.4, 1.0 } | Color that is used for residential buildings. |
| gui.layers.emissions.emissionColors | <list> | A list of 2 colors that are used for emissions. The first is the minimum color, the second is the maximum color. |
| gui.layers.emissions.numLevels | 17 | Number of color levels of the emissions data layer. |
| gui.signConfig.signRenderDistance | 1500 | The distance from which number signs, used in speed limits, destinations and cargo data layers, are shown. |
| gui.signConfig.signBackgroundTintColor | { 1.0, 1.0, 1.0, 1.0 } | Color that is used to tint the background of these number signs. The color is multiplied with the texture color of res/textures/ui/traffic_sign_min.tga. Only has an effect, if the background texture has a non-black color. |
| gui.signConfig.signTextColor | { 0.9, 0.9, 0.9, 1.0 } | Color that is used for the text in these number signs. |
| gui.iconRenderDistances | <struct> | Far limit scale for rendering of specific HUD icon types. |
| gui.defaultChartColors | <list> | A list of base colors that are used for the statistical charts. |
| gui.incomeCostsChartColors | <list> | A list of 2 colors that are used for the income and cost chart. |
| gui.loadedUnloadedChartColors | <list> | A list of 2 colors that are used for the chart with transported items. |
| gui.landUseChartColors | <list> | A list of 3 colors that are used for the land use chart. |
| gui.lineColors | <list> | A list of colors that is used for the transport lines. |
| gui.modifierColors | <list> | A list of 8 colors that are used for the track and street modifiers. There are 4 values each for enabled and disabled state in certain situations. |
| Audio | | |
| audio.environment.lake | <struct> | Name of the sound file that should be used for lake areas and reference distance in which the sound can be heard at full volume. |
| audio.environment.birds | <struct> | Like above for area with birds. |
| audio.environment.forest | <struct> | Like above for forest areas. |
| audio.environment.meadow | <struct> | Like above for meadow areas. |
| audio.environment.mountain | <struct> | Like above for mountain areas. |
| audio.environment.commercial1850 | <struct> | Like above for commercial buildings in era a. |
| audio.environment.commercial1920 | <struct> | Like above for commercial buildings in era b. |
| audio.environment.commercial1990 | <struct> | Like above for commercial buildings in era c. |
| audio.environment.industrial1850 | <struct> | Like above for industrial buildings in era a. |
| audio.environment.industrial1920 | <struct> | Like above for industrial buildings in era b. |
| audio.environment.industrial1990 | <struct> | Like above for industrial buildings in era c. |
| audio.environment.residential1850 | <struct> | Like above for residential buildings in era a. |
| audio.environment.residential1920 | <struct> | Like above for residential buildings in era b. |
| audio.environment.residential1990 | <struct> | Like above for residential buildings in era c. |
| audio.environment.crowd | <struct> | Like above for areas with many people. |
| audio.environment.traffic1850 | <struct> | Name of the sound file that should be used for traffic in era a and reference distance and height in which the sound can be at full volume. |
| audio.environment.traffic1920 | <struct> | Like above for traffic in era b. |
| audio.environment.traffic1990 | <struct> | Like above for traffic in era c. |
| audio.environment.atmosphere | <struct> | Name of the sound file that should be used when the camera is far away from ground and reference distance in which the sound can be at full volume. |
| Locations | | |
| locations.town.maxNumberPerArea | 0.2 | Number of towns per km² (by default overridden based on map settings) |
| locations.town.allowInRoughTerrain | false | Allows towns in steeper regions of the map |
| locations.industry.absoluteMinimum | 5 | Minimum number of industries on the map |
| locations.industry.maxNumberPerArea | 0.8 | Number of industries per km² on map creation (by default overridden based on map settings) |
| locations.industry.targetMaxNumberPerArea | 0.8 | Target number of industries per km² over time (by default overridden based on map settings) |
| locations.makeInitialStreets | true | Builds the initial street network on map creation |
| Animals | | |
| animal.populationDensityMultiplier | 1 | All population densities (in km²) are multiplied by this value |
| animal.useLocalSpawning | true | If set to `true`, spawning is done in subgrids of size 'localTileSize'. This results in a distribution that is closer to the chosen density but less uniform |
| animal.localTileSize | 1000 | Size of local spawning grid |
| animal.notifyAnimalDespawn | true | Play a notification when animal despawns |
| Geometry Quality | | |
| settings.geometryQualityOptions | <list> | This list contains 5 elements which each represent one distance level from the camera (Low, Medium, High, Camera Tool, Cockpit View). Each of the levels has 3 properties. Keep in mind that extending the ranges may have a heavy impact on the rendering performance! |
| `viewNearFar` for the render limits in the area near the camera and far away. |
| `fogStartEndFarPerc` for the start and end factors of the fog that appears in distance. |
| `lodDistanceScaling` for the scaling of the distance influence on LOD choosing for models. |
| Particles | | |
| particles.textures | <struct> | Texture references for smoke particles |
| water.textures | <struct> | Texture references for water foam particles |
| Economy | | |
| economy.industryDevelopment.spawnTargetTimeSpan | 50 \* 365.25 \* 2000 | Time span on which the industry spawning is projected |
| economy.industryDevelopment.spawnProbabilityExponent | 3.0 | Probability exponent for industry spawning |
| economy.industryDevelopment.spawnIndustries | false | Enables/Disables industry spawning (by default overridden based on map settings) |
| economy.industryDevelopment.closureCountdownTimeSpan | 730.5 \* 2000 | Time span between notification and actual closure |
| economy.industryDevelopment.closureProbability | 1 | Probability exponent for industry closure (by default overridden based on map settings) |
| economy.townDevelopment.cargoNeedsPerTown | 2 | Probability exponent for industry closure (by default overridden based on map settings) |
| Advanced options | | |
| advancedOptions.maximumLoanScale | 1.0 | Scales the maximum amount of money that can be borrowed from the bank. (by default overridden based on map settings) |
| advancedOptions.loanInterestScale | 1.0 | Scales the height of the interest rate for a loan. (by default overridden based on map settings) |
| advancedOptions.publicTransportDestinationsSensitivityScale | 1.0 | Scales the influence of reachable destinations by public transport on town growth. (by default overridden based on map settings) |
| advancedOptions.privateTransportDestinationsSensitivityScale | 1.0 | Scales the influence of reachable destinations by private transport on town growth. (by default overridden based on map settings) |
| advancedOptions.cargoSupplySensitivityScale | 1.0 | Scales the influence of the cargo supply rating on town growth. (by default overridden based on map settings) |
| advancedOptions.emissionSensitivityScale | 1.0 | Scales the influence of emissions around town buildings on town growth. (by default overridden based on map settings) |
| advancedOptions.trafficSpeedSensitivityScale | 1.0 | Scales the influence of traffic slowdowns on town growth. (by default overridden based on map settings) |
| advancedOptions.stationOverflowSensitivityScale | 1.0 | Scales the influence of overcrowded passenger stations on town growth. (by default overridden based on map settings) |
| Misc | | |
| environment | "temperate.lua" | Default environment |
| climate | "temperate.clima.lua" | Default climate |
| terrain.lodErrorMultiplier | 1 | Factor influencing the terrain simplification threshold |
| nameList.folder | "" | Names list folder reference |
| loadspeedPenaltyForTrainOverlength | true | Enables load speed penalty for trains which are longer than the platform |
| earnAchievementsWithMods | false | Enables achievements even with mods |
| industryButton | false | Enables the industry button in free game |
| sandboxButton | false | Enables the sandbox button (to build towns) in free game |
| difficulty | "EASY" | Default difficulty level |
| noCosts | false | disables all costs |
| enforceMainConnections | true | checks if main connections are interrupted and throws warnings |
| townDevelopInterval | 60 | Number of half days after which the town will be adjusted (grow or shrink) |
| chargeMaintenanceInterval | 60 | Length of interval in half days after which the maintenance fees will be charged |
| simulateCargoWeight | true | Simulates the weight of loaded cargo |
| simPersonDestinationRecomputationProbability | 1.0 | The probability that a person will look for a new job or shopping facility. Smaller values reduce performance load. Larger values will adapt to changes in the offered public transport faster. |
| townMajorStreetAngleRange | 0 | Angle of default town crossings. 0 results in parallel streets without curves in town. |
| townInitialMajorStreetAngleRange | 0 | The same, but only during first creation of a town. |
| tramCatenaryYearFrom | 1875 | Start date of tram catenaries |
| trackCatenaryYearFrom | 1910 | Start date of rail catenaries |
| busLaneYearFrom | 1925 | Start date of bus lanes |
| maxVehicleCloneAmount | 50 | Maximum number of vehicles that can be cloned at once. Only used for console edition. |
| trainAccelerationFactor | 1.0 | Global acceleration factor |
| trainBrakeDeceleration | 2.5 | Global deceleration factor. Lower values will result in slower deceleration. |

[Scripting Basics](../../modding/scripting/basics.md)

[Modifiers & Filters](../../modding/scripting/modifiersfilters.md)
