---
title: Tracks and Streets
page_id: modding:infrastructure:tracksstreets
source: https://wiki.transportfever3.com/doku.php?id=modding:infrastructure:tracksstreets
---

# Tracks and Streets

Tracks and streets are defined by 2 different types of config files:

- `.street_template.lua` for the simulation relevant properties.
- `.street.lua` for visual properties. One of these can be used by multiple `.street_template.lua` files.

## Track & Street Templates

The common properties for both tracks and streets in `.street_template.lua` templates are structured like below:

```lua
return { 
  description = { 
    name = _("STREET_TOWN_OLD_SMALL_NAME"),
    description = _("STREET_TOWN_OLD_SMALL_DESC"),
    icon = "::/infrastructure/street/town/town_old_small.tga",
    previewIcon = "::/infrastructure/street/town/town_old_small_preview.tga",
  },
  availability = { 
    yearFrom = 0,
    yearTo = 1940,
  },
  menuCategory = { 
    categories = {
      { 
        category = "roads_small",
        filterCategories = { },
        order = 10,
      },
    },
  },
 
  ...
}
```

The `description`, `menuCategory` and `availability` properties work as described for [constructions](../../modding/constructions/basics.md).

### Template

```lua
return { 
  ...
  roadType = "STREET",
  streetStyle = "::/infrastructure/street/town/town_old.street",
  laneConfigs = { ... },
  defaultEdgeDecorations = {
    { "::/infrastructure/edge_addons/barrier_a.edge", false, },
    { "::/infrastructure/edge_addons/barrier_a.edge", true, },
  },
 
  cost = 60,
  maintenanceCost = 10,
 
  ...
}
```

To define the template itself, use the following properties:

- `roadType` is either `"STREET"` or `"TRACK"`
- `streetStyle` is the reference to the style resource described further below.
- `laneConfigs` is a list of properties describing every individual lane of the street/track. Each lane may have the following properties:

  - `speed` is the speed limit of the lane in meter per second
  - `width` is the lane width. For tracks this is also used to define the ballast base width.
  - `offset` is an offset of the l: number
  - `height` is the height of the lane in meters. For roads this is used to raise the sidewalk too.
  - `forward` is a boolean value telling if the lane is in the same direction the street was dragged by the player.
  - `transportModes` is a list of transport modes supported by the lane. Possible values are:

    - `"PERSON"` and `"CARGO"` for sidewalks
    - `"CAR"`, `"BUS"` and `"TRUCK"` for streets
    - `"TRAM"` and `"ELECTRIC_TRAM"` for tram tracks
    - `"TRAM_TRACK"` and `"ELECTRIC_TRAM_TRACK"` for tram trains on rails
    - `"TRAIN"` and `"ELECTRIC_TRAIN"` for rail tracks

The `defaultEdgeDecorations` is a list of `.edge` references, each consisting of the resource reference and a boolean value describing if it should be on the left side of the edge. With `const` and `maintenanceCost` it is possible to the initial and reoccuring costs per meter.

### Emissions & Modifiers

```lua
  emissions = { 
    noise = 0,
    pollution = 0,
    pollutionRadius = 0,
    radius = 0,
  },
  modifiers = { 
    maxSpeedModifier = 0,
    noiseModifier = 0,
    pollutionModifier = 0,
  },
```

The tracks and streets can have an effect on the environment as well as on the vehicles using them:

- `emission` contains values for the radius and intensity of `noise` and `pollution`.
- `modifiers` is a list of scale factors for the vehicles:

  - `maxSpeedModifier` scales the top Speed of the vehicles.
  - `noiseModifier` scales the noise emission of the vehicles.
  - `pollutionModifier` scales the pollution emission of the vehicles.

### Slopes

![](../../_media/modding/infrastructure/track_slope.png)

```lua
  maxSlope = 0.4,
  maxSlopeBuild = 0.2,
  maxSlopeShape = 0.4,
  slopeBuildSteps = 4,
 
  embankmentSlopeLow = 0.75,
  embankmentSlopeHigh = 2.5,
```

The maximum slope is defined by three values. `maxSlopeBuild` is the slope of a straight line between start and end point 1. `maxSlope` is the limit for the track/street curve that aligns to the slopes of tracks/streets at the start and end point 2. `maxSlopeShape` is the limit for the actual track/street that may be displaced by intersecting roads or crossing tracks 3.

`slopeBuildSteps` is the number of steps that are available with the fixed slope arrow buttons ![](../../_media/gamemanual/interface/buttons/slope_down.png). The more steps, the smaller they are.

For tracks and streets on embankments, the terrain gradient is defined by:

- `embankmentSlopeLow` is the slope gradient that usually is tried to be used.
- `embankmentSlopeHigh` is used, if the low gradient would require very wide embankments or there are other objects with terrain alignments that prevent the use of the low gradient.

### Ground Textures

![](../../_media/modding/infrastructure/street_ground_tex.png)

```lua
  borderGroundTex = "::/infrastructure/street/shared/town_street_border.gtex",
  sidewalkFillGroundTex = "::/infrastructure/street/shared/street_sidewalk_fill.gtex",
  fillGroundTex = "::/infrastructure/street/shared/town_street_fill.gtex",
```

There are three properties that can be used for [ground textures](../../modding/constructions/groundtextures.md) in the area of tracks and streets:

1 `borderGroundTex` is the ground texture that is used for the border along the track/street.  
2 `sidewalkFillGroundTex` is used for the area below the sidewalks. If the street does not have a sidewalk material, this ground texture can be seen. This is often used with country roads. Tracks do not use this property.  
3 `fillGroundTex` is used for the area below the track/street itself. It is usually not visible at all except the street does not have a paving material.

### Street Specific Properties

The following properties are only used for streets:

```lua
  aiLock = true,
  simBuildable = true,
  country = false,
  priority = 0,
  busAndTramRight = true,
  defaultWithCrosswalk = true,
  pedestrianWalkPenalty = false,
  transportModesStreet = { "CAR", "BUS", "TRUCK", },
```

Several properties influence the functionality of the street:

- `aiLock` is a boolean variable. If set to `true`, built street segments with this street type will not be changed by the town development.
- `simBuildable` is a boolean variable. If the street template is not a country road, has two lanes in opposing directions and this property is set to true, the street type is considered as potential target type for street upgrades by town development.
- `country` is another boolean variable. If set to `true`, no houses will spawn along streets of this type.
- `priority` is an integer value used for the prioritization of street types when it comes to the visualization of markings at crossings. The higher the value is, the more likely this streets markings are used for the optic at intersections. This is used for the junction\* materials described below.
- `busAndTramRight` is a boolean value that tells if the right lane should be the one for bus and tram lanes by default. Otherwise it is the leftmost lane.
- `defaultWithCrosswalk` is a boolean value that tells if there should be crosswalks by default.
- `pedestrianWalkPenalty` is a boolean value that tells if walking along this street is not favored by pedestrians, e.g. along country roads.
- `transportModesStreet` is a list of keys for transport modes that are allowed on this street. It is possible to use `"BUS"`, `"TRUCK"` and `"CAR"`.

### Track Specific Properties

The following properties are only used for tracks:

```lua
  trackDistance = 5.0,
  speedCoeffs = { .9, 15.0, .63 },
  minCurveRadiusBuild = 60.0,
  minCurveRadius = 44.0,
  catenaryAdd = "::/infrastructure/track/standard/standard_catenary.street_template",
  catenaryRemove = "::/infrastructure/track/standard/standard.street_template",
```

It is possible to drag parallel tracks with the `trackDistance` from an existing track. Be aware that a `trackDistance` other than 5 meters might result in problems with the ballast track bed and catenary pole gantry generation.

The speed limit in curves is calculated based on the following formula: `curve speed limit = a * (radius + b) ^ c`.

The minimum radius in meter when dragging is described by `minCurveRadiusBuild` while the lower limit `minCurveRadius` is allowed when snapping to or along existing tracks.

The template that shall be used when adding or removing catenaries is referenced with `catenaryAdd` / `catenaryRemove`.

### Filter Station Modules

The game automatically generates station modules for every track template in the vanilla postRun function. To prevent these modules from appearing, a custom `postRunScript` function can be used in the mod to hide them. The below code crawls through the repository of modules and sets the visibility property to false for the modules specified in the list.

```lua
postRunFn = function ()
 
  local filteredModules = {      
      ["::trainstation_<tracktypename>.lua"]         = 1,
      ["::trainstation_<tracktypename>.luacatenary"] = 1,
  }
 
  local modules = api.res.moduleRep.getAll()
  for index, moduleFileName in ipairs(modules) do
      if filteredModules[moduleFileName] == 1 then
          api.res.moduleRep.setVisible(index - 1,false)
      end
  end
end, 
```

## Track Styles

The visual styling of tracks is configured in `.street.lua` files. The `roadType` property needs to be set to `"TRACK"`.

```lua
function data()
  return {
    roadType = "TRACK",
    trackStraightModel = { "2m_standard.mdl", "4m_standard.mdl", "8m_standard.mdl", "16m_standard.mdl", },
    ...
  }
end
```

The `trackStraightModel` struct contains 4 model references for 2, 4, 8 and 16 meter long sections of tracks with sleepers. For very small sections and tight curves, the model is constructed from the single `sleeperModel` and two instances of the single `railModel` below. All models have their origin at the terrain height, not the ballast top height and are centered in length and width.

### Shape

![](../../_media/modding/infrastructure/track_step.png)  
shapeStep = 5 and shapeStep = 1

Shapes represent the base geometry of the tracks and are used for collision tests, terrain alignment generation and generation of the procedural geometry. The width of the track is based on the lane width in the `laneConfig` of the track template.

```lua
    shapeStep = 4.0,                 -- [m] shape step
    shapeSleeperStep = 8.0 / 13.0,   -- [m] distance between sleepers
```

The step size allows for smoother curves (small) or less geometric primitives (high), which speed up collision checks. Tracks that allow a small minimal radius and have a small track width should tend to smaller shapeSteps to avoid corners in the tracks.

### Ballast

![](../../_media/modding/infrastructure/track_ballast_cutoff.png)  
ballastCutOff = 0.5 and ballastCutOff = 0.1

Ballast is the bed for track usually made from crushed stone. The height and material (see below) can be configured.

```lua
    ballastHeight = 0.3,   -- [m] height of the ballast
    ballastCutOff = 0.35,  -- [m] cut off profile 
```

The `ballastCutOff` can be used to influence the steepness of the ballast sides. 0.1 is relatively steep,
0.5 is not as steep but the horizontal top part is reduced so the ends of sleepers get nearer to the ballast bed edges.

### Sleeper

![](../../_media/modding/infrastructure/static_procedural_1.jpg)
static models and procedurally generated ones

Sleepers (or ties) are the rail supports usually made from wood, concrete or steel. The dimension and material (see below) can be configured. These settings are only used for procedural generated sleepers at switches and crossings. Normal sleepers use the static model in `sleeperModel` or for longer sections the ones included in `trackStraightModel` above.

```lua
    sleeperBase = 0.3,       -- [m] bottom height from ground level
    sleeperLength = 0.2,     -- [m] length of the sleeper along track
    sleeperWidth = 2.27,     -- [m] width of the sleeper
    sleeperHeight = 0.0633,  -- [m] height of the sleeper
    sleeperCutOff = 0.006,   -- [m] cut off profile
    sleeperModel = "single_sleeper_standard.mdl" 
```

The `sleeperCutOff` property is used to define the cut off angle for the sleepers. Usually it is a higher value for steel sleepers which have non vertical sides.

### Rail

![](../../_media/modding/infrastructure/static_procedural_2.jpg)
static models and procedurally generated ones

The rail configuration is used for switches and crossings. Along normal tracks, the static model from `railModel` or for longer sections the ones included in `trackStraightModel` are used.

```lua
    railTrackWidth = 1.435,  -- [m] track gauge (space between rails)
    railBase = 0.37,         -- [m] base height from ground level
    railHeight = 0.17,       -- [m] height of the rail
    railWidth = 0.07,        -- [m] width of the rail
    railCutOff = 0.012,      -- [m] cutoff profile
    railModel ="::/infrastructure/track/shared/single_rail.mdl"
```

The `railCutOff`  property is used to define the cut off angle for the rail. Usually it is very low.

### Catenary

![](../../_media/modding/infrastructure/track_catenary.png)

Electrified tracks need catenary for the power transfer. The poles are instances of a model, whereas the cable is procedural generated.

```lua
    catenary = {
      catenaryBase = 5.917 + 0.54,                                -- [m] base height of the cable over ground level
      catenaryHeight = 1.35,                                      -- [m] height of the support cable at the poles
      catenaryPoleDistance = 25.0,                                -- [m] target distance between poles
      catenaryMaxPoleDistanceFactor = 2.0,                        -- factor for maximum pole distance
      catenaryMinPoleDistanceFactor = 0.8,                        -- factor for minimal pole distance (in curves)
      catenaryPoleModel = "power_pole_2_standard.mdl",
      catenaryMultiPoleModel = "power_pole_1_standard.mdl",
      catenaryMultiGirderModel = "power_pole_1a_standard.mdl",
      catenaryMultiInnerPoleModel = "power_pole_1b_standard.mdl",     
    },
```

![](../../_media/modding/infrastructure/track_catenary_meshes.png)

The catenary uses four different models for different situations:

- for a single track, the normal pole is used 1.
- for a double track section, the poles are rotated so that they are on the outer side of each track.
- for 3 or 4 tracks, multi poles 2 are used and the middle tracks get girder section models 3.
- for more than 4 tracks, additional supporting inner poles are placed below the girders 4.

### Assets

There are additional models for the bumper and switch signals which are optional.

```lua
    bumperModel = "bumper_standard.mdl",
    switchSignalModel = "switch_box_standard.mdl",
```

### Materials

![](../../_media/modding/infrastructure/track_materials.png)

The procedural generated parts of the tracks use the following materials:

```lua
    materials = {
      ballastMaterial = "::/infrastructure/track/shared/mat/ballast.mtl",       -- (1)
      sleeperMaterial = "mat/sleeper_standard_tileable.mtl",                    -- (2)
      railMaterial = "::/infrastructure/track/shared/mat/rail_tileable.mtl",    -- (3)
      catenaryMaterial = "::/infrastructure/shared/mat/catenary.mtl",           -- (4)
    },
```

## Street Styles

The styling of streets is defined in `.street.lua` files reference by templates. The `roadType` property needs to be set to `"STREET"`.

```lua
function data()
  return {
    roadType = "STREET",
    materials = { ... },
    arrowIndices = { ... },
    assets = { ... },
    catenary = { ... },
    categoryList = { ... },
  }
end
```

### Materials

The list of `materials` defines the materials used for various parts of the street. Every definition contains a link to a `.mtl` file and its size:

```lua
    materials = {
      streetPaving = {
        name = "mat/town_new_street_paving.mtl",  -- reference to material file
        size = { 8.0, 8.0 }                       -- the size of the texture tile
      },
      -- more material definitions...
    },
```

The materials are used as tiled textures which are laid next to each other to fill the required area. With `size`, it is possible to specify the size of such a tile in meters for x and y dimension.

![](../../_media/modding/infrastructure/street_materials.png)

Available material definitions:

1 `streetPaving` is the base texture of streets. It is not orientated along the lane direction.  
2 `streetBorder` is the overlay texture stripe that is used along the outer edges of the outermost lanes. A second material can be defined as `streetBorder2`. It will be applied at the same time.   
3 `streetLane` is an overlay texture of street lanes. It is oriented along the lane.  
4 `streetArrow` is an overlay decal used for arrows in front of crossings.  
5 `streetStripe` is the overlay texture stripe that is used between lanes of the same direction.  
6 `streetStripeMedian` is the overlay texture stripe that is used between lanes of different directions.  
7 `streetTram` is the overlay texture with the tram track basement.  
8 `streetTramTrack` is the overlay texture with the actual tram tracks.  
9 `streetBus` is the overlay texture of bus lanes. It is oriented along the lane.  
10 `sidewalkPaving` is the base texture of sidewalks. It is not orientated along the lane direction.  
11 `sidewalkLane` is the oberlay texture of sidewalk lanes. It is oriented along the lane.  
12 `sidewalkBorderInner` is the overlay texture stripe that is used along the sidewalk edge towards the street lanes.  
13 `sidewalkBorderOuter` is the overlay texture stripe that is used along the outer edge of the sidewalk.  
14 `sidewalkCurb` is the texture that is used for the face at the side of the higher sidewalks towards the street and front faces where sidewalks have different heights. This often happens at railroad crossings and the contact points between town and country roads.  
15 `crossingLane` is an overlay texture of street lanes in intersections. It is oriented along the lane.  
16 `crossingTram` is the overlay texture with the tram track basement in intersections.  
17 `crossingTramTrack` is the overlay texture with the actual tram tracks in intersections.  
18 `crossingCrosswalk` ist the overlay decal for crosswalk markings.

Further material definitions are not shown in the picture above:

- `sidewalkWall` is the texture that is shown at the vertical faces at the outside of the sidewalks.
- `crossingBus` is the overlay texture used by bus lanes at crossings. This works similar to the other crossing overlays.
- `crossingStripeMedian` is the overlay texture stripe that is used between lanes of different directions at crossings.
- `crossingStopline` is an overlay decal used for stop lines in front of crossings.
- `junctionBorder` is the overlay texture stripe that is used along the outer edges of the outermost lanes at the dead ends of streets and in crossings. A second material can be defined as `junctionBorder2`. It will be applied at the same time.
- `junctionLane` is an overlay texture of street lanes at the dead ends of streets and in crossings. It is oriented along the lane.
- `junctionEntryLane` is an overlay texture of street lanes at the dead ends of streets and in
- `junctionStripe` is the overlay texture stripe that is used between lanes of the same direction at the dead ends of streets and crossings with a prioritized street.
- `junctionStripeMedian` is the overlay texture stripe that is used between lanes of different directions at crossings when there is a street with higher priority.
- `junctionLine` is the overlay texture stripe that is only used if there is no prioritized street.
- `catenary` is the material used for the tram catenary wires.

If a material is not set for a street type, this part is invisible ingame.

Base materials - like street and sidewalk pavings - require the following setup for the `polygon_offset`:

```lua
    polygon_offset = {
      factor = -3,
      units = -1.2,
      forceDepthWrite = true,
    },
```

Overlay materials - like markings, borders, bus lanes or tram tracks - require the following parameters:

```lua
    polygon_offset = {
      factor = -4,
      units = -1.3,
    },
```

Detailed information about material definitions can be found at the [material definitions](../../modding/general/resourcetypes/mtl.md).

### Assets

Streets can be decorated by placing different assets along the street. The `assets` struct contains a list of them:

```lua
    assets = {
      ["street_light"] = {
        name = "/assets/streets/street_light_eu_c.mdl",
        offset = 8.0,
        distance = 16.0,
        prob = 1.0,
        offsetOrth = 3.0,
        randRot = false,
        oneSideOnly = false,
        alignToElevation = false,
        avoidFaceEdges = false,
        placeOnBridge = true,
      }, 
      ...
    },
```

It contains a list of entries where the key is used for referencing when overriding for [bridges or tunnels](../../modding/infrastructure/bridgestunnels.md). Each entry may have the following properties:

- `name` is the reference to the asset model.
- `offset` is the start offset along the street in meter.
- `distance` is the distance between these assets in meter.
- `prob` is a placement probability in the range between 0.0 and 1.0.
- `offsetOrth` is the offset perpendicular to the street direction in meter.
- `randRot` is a boolean flag telling if the assets shall be rotated randomly.
- `oneSideOnly` is a boolean flag telling if the assets shall only be added on one side of the street, e.g. for street lights on small streets.
- `alignToElevation` is a boolean flag telling if the assets shall be orthogonal to the surface or upright. Usually assets are not aligned to the elevation when they are trees or (lamp) posts. Aligned assets could be the tree beds.
- `avoidFaceEdges` is a boolean flag telling the asset not to be placed at street segment border, e.g. to avoid overlaps with bigger assets, i.e. tree beds.

The `categoryList` contains a list of `categories` which are used to match the requirements for [edge addons](../../modding/infrastructure/edgeaddons.md).

### Catenary

The catenary models that should be used are referenced in the `catenary` struct.

```lua
    catenary = {
      pole = {
        name = "/assets/streets/tram_pole.mdl",
        assets = { "/assets/streets/tram_pole_light.mdl" }  
      },
      poleCrossbar = {
        name = "/assets/streets/tram_pole_crossbar.mdl",
        assets = { "/assets/streets/tram_pole_light.mdl" }  
      },
      poleDoubleCrossbar = {
        name = "/assets/streets/tram_pole_double_crossbar.mdl",
        assets = { "/assets/streets/tram_pole_light.mdl" }  
      },
      isolatorStraight = "/assets/streets/cable_isolator.mdl",
      isolatorCurve = "/assets/streets/cable_isolator.mdl",
      junction = "/assets/streets/cable_junction.mdl"
    },
```

The `pole`, `poleCrossbar` and `poleDoubleCrossbar` consist of a main model referenced with `name` as well as a list of asset models that are added on top. The `poleCrossbar` and `poleDoubleCrossbar` are currently unused.
