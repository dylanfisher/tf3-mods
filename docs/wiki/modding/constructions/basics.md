---
title: Construction Basics
page_id: modding:constructions:basics
source: https://wiki.transportfever3.com/doku.php?id=modding:constructions:basics
---

# Construction Basics

The concept of constructions allows to configure and create a lot of different building types and assets in just one format. This includes stations, depots, industries, town buildings and different kinds of assets. They are stored in `.con.lua` files and are usually grouped in folders for specific purposes like `depots/` or `industries/`.

## Construction Definition

The format mainly consists of meta information, parameter definitions and several functions for different purposes:

```lua
function data()
 
return { 
  availability = {
    yearFrom = 1900,
    yearTo = 1950
  },
  description = {
    name = _("DEPOTS_RAIL_DEPOT_NAME"),
    description = _("DEPOTS_RAIL_DEPOT_DESCRIPTION"),
    icon = "rail_depot.tga",
    previewIcon = "rail_depot_preview@2x.tga",
    attributes = {
      noise =  { 50, -1 },
      pollution = { 100, -1 },
      maintenanceCost = { 100000 * yearCoefficient, -1 },
      cost = { 600000 * yearCoefficient, -1 },
    }
  },
  menuCategory = {
    categories = {
      {
        category = "rail_buildings",
        filterCategories = {"building"},
        order = 5000,
      },
    },
  },
```

The availability is set by `yearFrom` for the year from when the construction should be available. Unset or values below 1900 mean from start. The end limit is set by `yearTo`. It is the year until when the construction should be available. Unset or value 0 means unlimited availability, values below 1900 result in a never available construction.

The `description` struct contains data used for the menu entry in the construction menu. This covers:

- `name` for the display name. It should not be longer than 32 characters.
- `description` for a short descriptive text showcasing the most important feature. It should not be longer than 320 characters.
- `icon` is a reference to a small `@2x.tga` icon which has a resolution of 240×150 pixels shown in the menu.
- `previewIcon` is reference to a `.tga` image that is used as background image for the info box. It has a resolution of 720×405 pixels.
- `attributes` contains values to be displayed as metadata in the info box:

  - `noise` is the display interval for the noise emission. If the second value is -1, only one value is shown.
  - `pollution` is the display interval for the pollution emission. If the second value is -1, only one value is shown.
  - `maintenanceCost` is the display interval for the yearly maintenance cost. If the second value is -1, only one value is shown.
  - `cost` is the display interval for the build cost. If the second value is -1, only one value is shown.

The `menuCategory` struct is used to provide the construction in the right menu. See the [construction menu](../../modding/constructions/menu.md) for more details about the menu tags.

```lua
  namePrefix = _("{townName} Train Depot"),
  subConstructionNamePrefix = "{constructionName}",
  soundConfig = {
    soundSet = { 
      name = "sound/raildepot.snd" 
    },
    effects = {
      select =  {
        "sound/selected_traindepot3.wav"
      }
    },
    builderAudioRes = "::/gui/construction/sound/buildoze_construction_large.builder_audio",
  },
 
  keepBuildingsAndFields = false,
  heightModView = true,
```

Some constructions have names for the user interface window, these can be templated by providing `namePrefix` and `subConstructionNamePrefix`.

The environment and click sounds are configured in the `soundConfig`. The `soundSet.name` is a reference to a [soundset](../../modding/misc/soundsets.md#sound_sets) file. The path is relative to the `.con.lua` file. `effects` is a mapping of event names to file names. The path is relative to the `.con.lua` as well.

With the `keepBuildingsAndFields` property, it is possible to prevent the construction from bulldozing town buildings, farm fields and other satellites. The `heightModView` property allows disabling the grid like terrain modification preview pattern. This is usually switched off for very large constructions.

Contructions may have additional properties and functionality for gameplay purposes. See the [construction types documentation](../../modding/constructions/types.md) for further details.

### Parameters

Parameters can be used to let the user set some preferences and influence the outcome of the construction script:

```lua
...
  params = {
    {
      key = "postbox_type",
      name = _("Postbox"),
      tooltip = _("Choose the type of postbox you'd like to place."),
      uiType = "Button",
      values = { _("Germany"), _("Switzerland"), _("Austria"), },
      defaultIndex = 0,
    },
    ...
  },
...
```

Each parameter struct has several properties:

| Property | Value | Default | Description |
| --- | --- | --- | --- |
| key | String | mandatory | Unique identifier for the parameter |
| name | String | `""` (empty) | Display name for the parameter menu |
| group | String | `""` (empty) | Assignment to group, groups are divided by horizontal lines |
| tooltip | String | `""` (empty) | Tooltip that is displayed above the parameter name when hovering |
| tooltips | {String,String,…} | {"", "", … } | Tooltip texts for the individual options |
| values | {String,String,…} | mandatory | Display values for the parameter menu, see below |
| numbers | {Number,Number,…} | {1, 2, 3, …} | Return values for each option of the parameter |
| defaultIndex | Integer | 1 | Pre-selected option on first call |
| uiType | `"Button"` or `"Slider"` or `"ComboBox"`   or `"IconButton"` or `"CheckBox"` | `"Button"` | Type of parameter, see below |
| yearFrom | Integer | 0 | Parameter is displayed from |
| yearTo | Integer | infinite | Parameter is displayed until |
| hideLabel | Boolean | false | The name is not shown |
| location | `"Default"` or `"Toolbar"` | `"Default"` | The parameter is shown in the left or right menu |
| displayMode | `"Default"` or `"Compact"` | `"Default"` | The name is shown normal or as button with popup menu |
| checkEnabledScript | Script reference, see below | none | Optional script function that decides if this parameter should be shown, see below |
| postConstructionModifiable | Boolean | false | The parameter can be changed after the construction is already built |

The `checkEnabledScript` function allows to define conditional functions for certain parameters:

```lua
...
{
  key = "additional_param",
  name = _("Additional Parameter"),
  uiType = "ComboBox",
  values = { _("ABC"), _("DEF") },
  checkEnabledScript = {
    fileName = "custom_construction.script@checkEnabledFn",
    params = {
      key = "other_param",
      threshold = 100,
    },
  },
}
...
```

A `.script.lua` / `.script.tl` file contains this function:

```lua
...
checkEnabledFn = function(capturedParams, params)
  return params[capturedParams.key] < capturedParams.threshold and "Disabled" or "Enabled"
end,
...
```

The referenced function receives three parameters:

- `captureParams` is the struct attached in the parameter definition in the `.con.lua`.
- `params` is the list containing the return values of all the params of this construction.
- `scriptRefParams` contains the custom keys and values provided next to the script reference, like `key` and `threshold` in the example above.

> **Caution:**
>
> It is not possible to access other scripting interfaces in this function.

The function may return one of the following strings:

- `"Enabled"` when the parameter should be offered.
- `"Hidden"` when the parameter should be disabled and invisible.
- `"Disabled"` when the parameter should be disabled but visible and greyed out.

> **Tip:**
>
> It is recommended to choose key names that are totally unique, not only on mod level. Otherwise it could happen, that a preselected parameter value from another third-party construction is used once your construction is loaded. This could result in unintended behavior, if you do not check for the parameter range.

In the `updateFn` function of the construction, the selected options can be called up with `params.<key>`. Numbers starting from 1 are returned. The first entry of a dropdown, for example, returns a 1. For a checkbox, 1 corresponds to the non-activated state, 2 to the activated state.

> **Caution:**
>
> Be aware that in comparison to Transport Fever 2, the return values are 1-based, not 0-based.

The individual characteristics of the different types are shown below.

#### Button

![](../../_media/modding/constructions/parameter_button.png)

Simple text buttons are lined up in the menu as a centered list. The labels of the buttons are passed as a string list in the `values` parameter, they can also be translated in [''strings.json''](../../modding/general/moddefinition.md#stringsjson).

```lua
{
  key = "postbox_type",
  name = _("Postbox"),
  uiType = "Button",
  values = { _("Germany"), _("Switzerland"), _("Austria"), },
  tooltip = _("Choose the type of postbox you'd like to place."),
},
```

#### Slider

![](../../_media/modding/constructions/parameter_slider.png)

Especially for many linear values, such as numerical series or size increments, sliders can be used as easy-to-use controllers. The name of the currently selected position is displayed to the right of the slider. The display names of the buttons are passed as a string list in the `values` parameter, these can also be translated in [''strings.json''](../../modding/general/moddefinition.md#stringsjson).

```lua
{
  key = "parcelstation_length",
  name = _("Parcel Station Length"),
  uiType = "Slider",
  values = { _("5m"), _("8m"), _("10m"), _("12m"), _("15m"), _("20m"), },
  tooltip = _("Choose the length of the parcel station."),
},
```

#### Combo Box

![](../../_media/modding/constructions/parameter_combobox.png)

If a large number of text options should be available, a simple list of buttons is not sufficient. Then a combo box, also known as a drop-down menu, can be used to offer a compact number of options. The entries of the list are passed as a string list in the `values` parameter, they can also be translated in [''strings.json''](../../modding/general/moddefinition.md#stringsjson).

```lua
{
  key = "post_assets",
  name = _("Post Assets"),
  uiType = "ComboBox",
  values = { _("Few Parcels"), _("Many Parcels"), _("Oversized Parcels"), _("Letterboxes"), _("Empty"), },
  tooltip = _("Choose the decoration that should lay around."),
},
```

#### Icon Button

![](../../_media/modding/constructions/parameter_icon_button.png)

Unlike the text buttons, the icon buttons display small images in TGA format. If the list of buttons becomes wider than the parameter menu, it will wrap to another line. It is therefore advisable that the images for the buttons all have the same height. Also, the border of the buttons should be transparent so that you can see which option is currently selected. The file paths to the images are passed as a string list in the `values` parameter, the paths are relative to the `.con.lua`. The tooltip is used for hovering over the parameter name. It is not possible to add tooltips for the individual icons.

```lua
{
  key = "post_horns",
  name = _("Post Horns"),
  uiType = "IconButton",
  values = { "ui/parameters/post_de.tga", "ui/parameters/post_ch.tga", "ui/parameters/post_at.tga", },
  tooltip = _("Choose the post horn that should be displayed."),
},
```

#### Check Box

![](../../_media/modding/constructions/parameter_checkbox.png)

If only one value is assigned with yes or no, a check box is also suitable as parameter type. Only the name is displayed, but the `values` parameter must still be defined with two values, but it's values are never shown.

```lua
{
  key = "post_box_open",
  name = _("post box is open"),
  uiType = "CheckBox",
  values = {"1", "2"},
  tooltip = _("Choose if the post box is shown in opened state."),
},
```

### Construction Scripts

Each construction may have references for some of the following functions to provide different functionality. The following scripts are used to build or update the construction:

- `updateScript` is the most important function reference. The function assembles the construction that is placed in the 3D world.
- `createTemplateScript` is the function that is called to put the initial modules in slots according to the selected [template](../../modding/constructions/templates.md).
- `isAffectedByToolScript` is the function that is called when road or rail tools are active to check if they can be applied on the construction.
- `upgradeScript` is used when a [modular construction](../../modding/constructions/modular.md) is changed by such a tool to swap out modules.

The `updateScript` is the only mandatory one for constructions, the others are only required for individual use cases.

The following optional scripts control the UI behavior:

- `hudIconScript` is used to specify a hud icon for the construction.
- `configureHudIconsScript` is used to specify which hud icons shall be shown in the 3D world while the construction is selected.
- `configureLayerScript` is used to specify which data layer shall be shown in the 3D world while the construction is selected.
- `entityWindowScript` is used to control the content of the entity window for this construction.

If one of these scripts is not specified for a construction, the game will fall back to the default variant which might be nothing in some cases.

## Update Script

The `updateScript` references a function in a `.script.tl` or `.script.lua` file:

```lua
...
updateScript = {
  fileName = "rail_depot.script@updateFn",
  params = {
    ["param_key_1"] = "value_1",
  },
},
...
```

The `fileName` is referencing the function `updateFn` in the `rail_depot.script.lua` file. In this function, the construction is configured and specified. It has the following structure:

```lua
...
updateFn = function(captureParams, params)
  ... -- logic
  return {
    cost = 10000,
    bulldozeCost = 1000,
    maintenanceCost = 1000,
    costMultiplier = 1.0,
    noCostAtAll = false,
    snapPoint = { ... },
    subconstructions = { ... },
    edgeLists = { ... },
    edgeObjects = { ... },
  }
end
```

The `captureParams` contains the params data that is provided with the script reference in the `.con.lua`.

You can use the content of the struct `params` to configure the construction. It also contains the selection of the user parameters you have specified in the `params` list of the `.con.lua` definition and the templates. See the [list of construction types](../../modding/constructions/types.md) to find out, which additional properties are available in the `params` struct depending on the construction type.

The `updateFn` returns a large result data struct with several mandatory and many optional properties.

There are five properties that can be used to set the costs of the construction:

- `cost` is paid when the construction is built.
- `bulldozeCost` is paid when the construction is demolished.
- `maintenanceCost` is paid monthly to maintain the infrastructure.
- `costMultiplier` is a factor that can be applied on top of the cost values, e.g. depending on time.
- `noCostAtAll` is a boolean value that allows supressing all costs including terrain alignment.

To fine tune the positioning of the construction, it is possible to provide a snapPoint:

```lua
...
snapPoint = {
  transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 },
  transportModes = { "TRAIN", "ELECTRIC_TRAIN" },
  snapToBaseEdgeTypes = { "TRACK", "STREET"},
  allowSnapToBaseEdgeEnds = true,
  alignWithCoast = false,
  placeAtTerrainHeight = false,
  forceSnapToWaterSurfaceHeight = false, 
  snapHeightOffsetAboveWater = 0.0,
  onlySnapToWaterSurfaceHeightWhenInWater = false,
  allowSnapToMesh = false,
}
...
```

The properties of the `snapPoint` are:

- `transf` is the position of the construction that is below the mouse cursor while placing the construction.
- `transportModes` is a list of lane transport modes to which the construction may snap.
- `snapToBaseEdgeTypes` is a list of all edge types where the construction will align with the base edges.
- `allowSnapToBaseEdgeEnds` is a boolean value that enables snapping at crossings and ends of base edges.
- `alignWithCoast` is a boolean value that enables snapping along the coastline.
- `placeAtTerrainHeight` is a boolean value that forces placement at the height of the terrain when snapping to transport network or base edges.
- `forceSnapToWaterSurfaceHeight` is a boolean value that forces the construction to the height of the water.
- `snapHeightOffsetAboveWater` is a numeric value used as offset in meters from water surface when `forceSnapToWaterSurfaceHeight` is enabled.
- `onlySnapToWaterSurfaceHeightWhenInWater` is a boolean value that softens the restriction of `forceSnapToWaterSurfaceHeight` to only be active while pointing on water.
- `allowSnapToMesh` is a boolean value that enables snapping to mesh geometry of models. To activate this snapping behavior, the player needs to press ALT once.

### Subconstructions

Almost all things that actually affect the 3D world and have a gameplay function are assigned to a subconstruction in the `subconstructions` list:

```lua
...
{
  tag = 1,
  -- generic properties
  models = { ...},
  groundFaces = { ...},
  colliders = { ...},
  terrainAlignmentLists = { ...},
  laneLists = { ... },
  runways = { ... },
  labelText = { ... },
  metadata = { ... },
  emissionEmitter = { ... },
  stocks = { ... },
  rules = { ... },
  personCapacity = { ... },
 
  -- game mechanic relevant properties:
  industry = { ... },
  field = { ... },
  warehouse = { ... },
  maintenanceStation = { ... },
  depot = { ... },
  station = { ... },
  townBuilding = { ... },
}
...
```

The `tag` integer is used to map the subconstructions consistently when the construction is updated.

Each subconstruction may have have multiple of the generic properties described below, but in practice there is often a primary subconstruction that has most of the properties and the others only have a subset, e.g. models.

Additionally the subconstruction may have some out of the game mechanic relevant properties. Some of them cannot be combined in the same subconstruction though, so to combine e.g. a station and a depot in the same construction, there has to be a subconstruction for each of them. See the details about the [construction types](../../modding/constructions/types.md) for more details.

#### Models

It is possible and very common to add models to a construction. Almost every model can be added by adding it to the list of `models` in the subconstruction data struct.

```lua
models = { {
  id = "building_small.mdl",
  transf = transf.transl(vec3.new(20, -10 , 0))
} }
 
-- alternative with dynamic index depending on the already existing list
local models = { }
...
models[#result.models + 1] = {
  id = "building_small.mdl",
  transf = transf.transl(vec3.new(20, -10 , 0)),
  tag = "office",
}
```

Each entry contains some properties:

- `id` is the path to the `.mdl` file relative to the `.con.lua`.
- `transf` is the transformation matrix relative to the origin of the construction. It may either be provided as a 16 value list or by use of one of the functions from `mat4.tl` that can be found in the `scripts` folder.
- `tag` is an optional property to label the model with a certain string. It can be used as reference in code elsewhere to map models to the ones from earlier executions of the `updateFn`.

> **Tip:**
>
> The game offers two pairs of hotkeys as additional inputs for custom parameters. Per default the keys are O/P and Ü/+ or [/] (depending on keyboard layout). They each have steps of 2π/32 so that 32 steps can be mapped to a full rotation around an axis.
>
> To support rotation around all three axis, add `paramsutil.makeRotationParam("constructOpt56", _("Rotation X")),` and `paramsutil.makeRotationParam("constructOpt78", _("Rotation Y")),` to the construction parameters and encapsulate the transformation matrix of the model with the `rotateTransf` function
> `transf = constructionutil.rotateTransf(params, { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 })`.Make sure to import the `paramsutil` with `local paramsutil = require "::/scripts/construction/param_util.tl"` in the `.con.lua` and the `constructionutil` with `local constructionutil = require "::/scripts/construction/constructionutil.lua"` at the begin of the script file (before `function data()`).

#### Ground Faces

Ground faces are used to paint the terrain below the construction to blend in with the construction.

```lua
groundFaces = {
  {  
    face = { { -10, -10, 0 }, { 10, -10, 0 }, { 10, 10, 0 } },
    modes = {
      {
        type = "FILL",               
        key = "industry_floor.gtex",
        texCoords = {
          { 0, 0 },
          { 0, 1 },
          { 1, 1 },
          { 1, 0 },
        }
      }
    },
    loop = true,
    alignmentOffsetMode = "OBJECT",
    alignmentDirMode = "OBJECT",
    alignmentOffset = { -2.0, -1.0 },
 
  },
  ...
}
```

The `groundFaces` list contains 0 or more structs with the following attributes:

- `face` is the list of coordinates that span the surface which should be painted. Each point has a value relative to the construction origin for x, y and z axis, but the z axis is ignored. At least three points are required and they shall be in counterclockwise order.
- `modes` is a list of paint modes that should be applied to the face:

  - `type` is the actual painting mode. `"FILL"` fills the whole face, `"STROKE"` paints a line with soft sides along the face edge, `"STROKE_INNER"` paints a line with a soft side to the inside of the face and `"STROKE_OUTER"` paints a line with a soft side to the outside of the face.
  - `key` is the reference to the [ground texture](../../modding/constructions/groundtextures.md) that should be used relative to the `.con.lua`.
  - `texCoords` is a list of positions on the ground texture. The x and y coordinates are in the range between 0.0 and 1.0. The number of positions needs to match the number of `face` coordinates.
- `loop` is a boolean value used to describe if the face is closed. If set to `false`, the edge between last and first coordinate will not get a stroke paint.
- `alignmentOffsetMode` specifies whether the offset is applied relative to the construction orientation (`"OBJECT"`) or the game world orientation (`"WORLD"`).
- `alignmentOffset` contains the offset values in x and y direction.
- `alignmentDirMode` specifies if the uv direction setting is applied relative to the construction orientation (`"OBJECT"`) or the game world orientation (`"WORLD"`).
- `alignmentDir` contains the direction rotation values in x and y axis. They are computed as `tan2(y,x)` to calculate the actual rotation.

#### Collider

Colliders are used to define the areas where no other object can be built.

```lua
colliders = {
  {
    params = {
      halfExtents = { 1.5, 1.5, 1.5, },
    },
    transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, },
    type = "BOX",
  },
  {
    colliderutil.createBox({ 0, 0, 0 }, { 1.5, 1.5, 1.5 })
  }
}
```

The `colliders` list contains 0 or more structs with the following properties:

- `params` is a list of parameters. These depend on the `type` used.

  - For `"BOX"` the required parameter is provided in `halfExtents`. That is a 3 value vector with the half box lengths for all three axis.
  - For `"CYLINDER"` it is provided in `halfExtents` too. The 3 values represent the half sizes for all three axis.
  - For `"POINT_CLOUD"`, a list of points is provided in the `points` parameter. Each point has three values for the position on all three axis relative to the construction origin. The `transf` parameter is ignored.
- `transf` is transformation matrix that point on the center of the collider. It is relative to the construction origin.
- `type` is the type of collider. It can be either `"BOX"`, `"CYLINDER"` or `"POINT_CLOUD"` for constructions.

The `collider_util.tl` in the `scripts/construction` folder provides some useful functions to prepare the collider definition based on some parameters.

#### Terrain Alignment List

The adjustment of terrain height to the construction is done with the terrain alignment. If the required alignment can't be done due to other nearby constructions or infrastructure, the construction can't be built.

```lua
terrainAlignmentLists = {
  {
    type = "EQUAL",               -- accepted values: "EQUAL", "LESS" and "GREATER"
    faces = { { { -10, -10, 0 }, { 10, -10, 0 }, { 10, 10, 0 } } }, -- a list of polygons
    slopeLow = 0.3,
    slopeHigh = 0.6,
    triangles = { { -10, -10, 0 }, { 10, -10, 0 }, { 10, 10, 0 }, }
    optional = false,
  },
  ...
}
```

The `terrainAlignmentLists` list contains 0 or more structs with several properties:

- `type` is the policy that should be used for terrain alignment. With `"EQUAL"` the terrain is aligned exactly to the specified faces, with `"LESS"` only higher areas are taken down, with `"GREATER"` areas below the faces will be filled up.
- `faces` is a list of polygons. Each polygon consists of at least three points with three coordinates relative to the construction origin each.
- `slopeLow` is the gradient for the slope on the outside of the construction that is needed to make the transition to the modified terrain when the surrounding terrain is lower or higher than the construction area.
- `slopeHigh` is the steeper gradient for the slope if the height difference is too big and the slope would get too wide or when another object constraints the sloping.
- `triangles` is a list of points. The number of points needs to be a multiple of 3. Every three points are considered as the corners of triangles. This property is an alternative to the `faces` property.
- `optional` should be set to true if the alignment should not throw collision errors when competing against other terrain alignments in the same construction.

#### Lane Lists

The `laneLists` struct contains 0 or more lists for vehicle and passenger lane definitions :

```lua
laneLists = {
  {
    transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, },
    nodes = {
      { { 0, -20, -2.1, }, { 0, 20, 0, }, 30, },
      { { 0, 0, -2.1, },   { 0, 20, 0, }, 30, },
 
      { { 0, 0, -2.1, },   { 0, 20, 0, }, 30, },
      { { 0, 20, -2.1, },  { 0, 20, 0, }, 30, },
    },
    speedLimit = 20,
    transportModes = { "SHIP", "SMALL_SHIP" },
    linkable = false,
  },
  ...
},
```

Each line list has several properties:

- `transf` is a transformation matrix that defines the origin location of this lane list relative to the construction origin. This can be used to define lanes relative to module positions or model positions.
- `nodes` is a list of nodes which are used to define the edges. Every two nodes form one edge. Each node has three properties:

  1. The coordinate relative to the model origin.
  2. The tangent at the node position. Please note that the length of the vector must be equal to the length of the edge. Otherwise negative side effects like compression and stretching of vehicles may occur.
  3. The width of the edge. It is only used for the capacity calculation.
- `speedLimit` is the maximum speed on all edges defined by the nodes above in meter per second.
- `transportModes` is a list of allowed modes on the edges defined by the nodes above. Possible values are `"PERSON"`, `"CARGO"`, `"CAR"`, `"BUS"`, `"TRUCK"`, `"TRAM"`, `"ELECTRIC_TRAM"`, `"TRAIN"`, `"ELECTRIC_TRAIN"`, `"AIRCRAFT"`, `"SHIP"`, `"SMALL_AIRCRAFT"`and `"SMALL_SHIP"`.

For lanes that are used by vehicles, two additional properties are available:

- `needsReservation` is a boolean value that decides if the lane can be only used when a proper reservation is possible (similar to trains on train tracks).
- `forwardOnly` is a boolean value that tells if the lane is only usable in the direction it is defined or not.

For lanes that are used by pedestrians, two additional properties are available:

- `linkable` is a boolean value that decides if the lane can be targeted by the small automatically generated footpath links.
- `pedestrianWalkPenalty` is a boolean value that tells if the usage of these lanes leads to reduced happiness for pedestrians.

The `laneutil` in `scripts/construction` provides some useful helper function to ease the definition of lanes.

#### Runways

The `runways` struct contains 0 or more runways which have several properties related to the entry and exit points of the freely moving planes and ships:

```lua
runways = {
  {
    edges = { { 0, 0 }, },
    node = { 0, 0 }
    type = "LANDING",
  },
  {
    edges = { { 1, 0 }, },
    node = { 0, 0 }
    type = "TAKEOFF",
  },
},
```

Each runway has three properties:

- `edges` is a list of indices pairs where the first value is the index of the lane List in `laneLists` of the same subconstruction and the second value is the index of the lane in this lane list. If the first value is -1, then the n-th edge from the `edgeLists` of the construction is used. All edges/lanes referenced this way are part of the runway.
- `node` is an indices pair where the first value is the index of the lane list in `laneLists` of the subconstruction and the second value is the index of the node in this lane list. It is the point where the vehicle is slowed down after landing or starting speedup for takeoff. It must be the node where the runway connects to the non-runway edges or lanes. If the first value is -1, then the n-th node from the `edgeLists` of the construction is used.
- `type` is either `"LANDING"` or `"TAKEOFF"` depending on the type of runway.

An aircraft tries to land and slow down in front of the landing node. After passing it, it will taxi to the terminal. On departure, it will speed up and take off after passing the takeoff node. The landing/takeoff direction is given by the tangent of the first/last edge in the `edges` list. Same holds for ships.

#### Label List

For models with `"CUSTOM"` typed labels, the content can be provided here:

```lua
labelText = {
  [12] = { "Label", "SomeText"}
}
```

The `labelText` list contains a mapping of keys to value lists. The key number equals the id of the model in the `models` of the same subconstruction that should be provided with some custom label texts. The list contains the strings. The first string is for the first label of the model, the second for the second label of this model and so on.

### Edge Lists

Edge lists are used to add streets and tracks to a construction. The following code adds a street segment and a track segment to the construction:

```lua
result.edgeLists = {
  -- specify a street segment
  {
    type = "STREET",                             
    params = {
      type = "::/infrastructure/street/country/country_new_small.street_template",    
      tramTrackType = "YES"                      
    },
    edgeType = "BRIDGE",                                     -- optional
    edgeTypeName = "::/infrastructure/bridge/steel.bridge",  -- optional
    edges = {
      -- one entry refers to a position and a tangent
      { { .0, -79.0,  .0 },  { .0, 15.0, .0 }, "tag1" },  -- node 0 (snap node)
      { { .0, -64.0,  .0 },  { .0, 15.0, .0 }, "tag2" }   -- node 1
    },
    snapNodes = { 0 } , -- node 0 is allowed to snap to other edges of the same type
    freeNodes = {},
    tag2Nodes = {},
  },
 
  -- specify a track segment
  {
    type = "TRACK",
    params = {
      type = "::/infrastructure/track/standard/standard.street_template",                    
      catenary = true
    },
    edgeType = "BRIDGE",                                     -- optional
    edgeTypeName = "::/infrastructure/bridge/steel.bridge",  -- optional
    edges = {
      { { -19.1, .0, .0 }, { -20.0, .0, .0 } },  -- node 0 
      { { -39.1, .0, .0 }, { -20.0, .0, .0 } },  -- node 1 (snap node)
    },
    snapNodes = { 1 },  -- node 1 is allowed to snap to other edges of the same type
    freeNodes = {},
  }
}
```

Each struct in the `edgeList` has several properties:

- `type` selects if the edges should be `"STREET"` or `"TRACK"` edges.
- `params` is a struct with two properties:

  - `type` is a reference to a street template for the track or street to use. It is recommended to use absolute references.
  - `tramTrackType` is a string value only considered for actual streets. If set to `"NO"`, no tramtracks will be built. If set to `"YES"`, tram tracks will be built. If set to `"ELECTRIC"`, tram tracks with catenary will be built.
- `edgeType` decides if the segment is built as a `"BRIDGE"`, `"TUNNEL"` or normal (unset).
- `edgeTypeName` selects the type of bridge or tunnel to be used. It is recommended to use absolute references.
- `edges` is a list. Every two entries form an edge. The first entry is the start node of the edge, the second entry is the end node of the edge. Every node has two vectors with three values and an optional third string parameter:

  - the first vector is the point relative to the construction origin with values for x, y and z axis.
  - the second vector is the tangent in this point with values for x, y, and z axis.
  - the optional string parameter can be used to merge nodes that do not have exactly the same coordinates into one node, allowing off-center intersection. If there are untagged nodes at the same location as a tagged one, they won't be merged.
- `snapNodes` is a list of node indizes from the `edges` list. These nodes can be used to snap streets or tracks while manually building later.
- `freeNodes` is a list of nodes, that are not part of the construction. Edges with two free nodes can be deleted or modified independently.
- `trafficLightNodePreference` is an array of pairs with integers and strings. The integers refer to nodes of the construction edgeLists, the strings specify the preference:

  - `YES` will force traffic lights at the intersection
  - `NO` will force the abscence of traffic lights at the intersection
  - `AUTO` will build traffic lights if possible/available.
- `alignTerrain` is a boolean value. If set to true, the terrain aligns to the built edge like normal track/street building would do.
- `addNoisePollutionEmitter` is a boolean value. If set to true, the tracks/street in the construction have their own pollution emitter as well. Default is `false`.

The `constructionutil` in `scripts/construction` offers a helper function to add edges.

### Edge Objects

Some game objects can be attached to edges, for example signals. This is not only possible by the player, but also possible in constructions for edges contained by the constructions, as shown in the following code sample:

```lua
-- we need some edges to attach edge objects to them
taxiway = { }
 
-- edge 0
taxiway[#taxiway + 1] = { { 180.0,  20.0,  .0 },  {    .0, -20.0, .0 } } 
taxiway[#taxiway + 1] = { { 180.0,   0.0,  .0 },  {    .0, -20.0, .0 } }
 
-- edge 1
taxiway[#taxiway + 1] = { { 180.0,   0.0,  .0 },  {    .0, -47.1, .0 } }
taxiway[#taxiway + 1] = { { 150.0, -30.0,  .0 },  { -47.1,   0.0, .0 } }
 
-- add taxi way to edge lists...
 
-- attach a signal to one of the above defined edges
result.edgeObjects = {
  {
    edge = 1,                                              -- attach object to edge 1
    param = .5,                                            -- param along the edge
    left = false,
    model = "::/stations/airport/asset/signal_runway_old.mdl" 
  }
}
```

The `edgeObjects` list contains all object attachments with properties:

- `edge` is the number of the edge. Edge 0 is between node 0 and 1, edge 1 is between node 2 and 3, …
- `param` is the offset along the edge from the start node in meter.
- `left` is set to false, if the object should be placed on the right side of the edge. `true` leads to objects on the left side.
- `model` is a reference to a `.mdl` file.

Please be aware that it is not possible to add more than one object per edge by script.

## Is Affected By Tool Script

When the player uses the electrification tool or wants to upgrade tracks or streets, the `isAffectedByToolScript` is used as a callback to determine if the construction can be upgraded:

```lua
...
isAffectedByToolFn = function(captureParams, params, conConfigAdd, conConfigRevert)
  ... -- some logic
  return false -- or true
end,
...
```

The function receives the following parameters:

- `capturedParams` contains the parameters forwarded with the script reference in the `.con.lua`.
- `params` contains the parameter values from when the construction update function was executed previously.
- `conConfigAdd` contains info about what the tool wants to do.
- `conConfigRevert` contains info about what the tool would do if it was already applied before.

Depending on the used tool, different data is available in `conConfigAdd` and `conConfigRevert`:

| Tool | Parameter | Value |
| --- | --- | --- |
| Electrification | catenary | 1 = false  2 = true |
| Track Modification | catenary | 1 = false  2 = true |
| Track Modification | streetTemplate | resource name of selected template |
| Street Modification | streetTemplate | resource name of selected template |
| Bus Lane Tool | busLane | 1 = false  2 = true |
| Tram Lane Tool | tramTrack | 1 = false  2 = true |
| Tram Lane Tool | tramCatenary | 1 = false  2 = true |

It shall return true when the tool can be applied onto the construction and false if it may not. If the function is not set for a construction, `true` is assumed.
The function may use `api.res` functions, but no other functions from `api`.

## Upgrade Script

The `upgradeScript` function is called when an existing construction shall be changed with one of the tools.

It receives the previous params of the construction as well as the info what shall be changed and returns the modified params which are then forwarded to the update script.

```lua
...
upgradeFn = function(captureParams, params, slotId, constructionConfig)
  ... -- edit params
  return params
end
...
```

The `capturedParams` contains the parameters forwarded with the script reference in the `.con.lua`. Beside that, `params` contains the parameter values from when the construction update function was executed previously. `slotId` is `-1` for non-modular constructions and `constructionConfig` contains values as described for the `conConfigAdd` above.

The function may use `api.res` functions, but no other functions from `api`.

In practice this could e.g. be changing a param `tramCatenary` to a new value or replacing a param like `streetType` with another.

## HUD Icon Script

The `hudIconScript` function allows defining the hud icon that shall be shown by the construction:

```lua
...
hudIconFn = function(_captureParams : any, params : Builtin.HudIconParam, _userParam : HudIconToolbox.HudIconMasterUserParam) : TreeNodeId
  return hud_icon_toolbox.PerkHudIcon{
    class = "landmark",
    path = "::/gui/hud/icons/building_temple_32.tga",
  }
end,
...
```

The `capturedParams` contains the parameters forwarded with the script reference in the `.con.lua`. Beside that, `params` contains info about the entity itself and `userParam` contains some additional context info related to notifications.

It is expected that the function returns a valid BoxLayout. The `::/gui/main/hud_icon_toolbox.tl` provides helper functions to create such a BoxLayout.

## Configure HUD Icons Script

The `configureHudIconsScript` function allows defining which hud icons shall be displayed while the construction is being placed:

```lua
...
configureWarehouseHudIconsFn = function() : ConstructionActionHudIcons
  return {
    componentTypes = {
      api.type.ComponentType.TOWN,
      api.type.ComponentType.STATION_GROUP,
      api.type.ComponentType.WAREHOUSE,
      api.type.ComponentType.INDUSTRY,
    },
    showDistricts = true,
    showTownBorders = true,
    showPerksAndTowns = true,
    params = {
      stationType = "CARGO",
    },
  }
end,
...
```

It is expected that the function returns a valid `ConstructionActionHudIcons` configuration. The `componentTypes` is a list that may contain zero or more [component types](https://wiki.transportfever3.com/script-doc/api/engine.html#$api.engine~Engine.ComponentType) for which the icons shall be displayed. If the type `api.type.ComponentType.TOWN` is included, it is possible to use:

- `showDistricts` to highlight residential, commercial and industrial districts of towns
- `showTownBorders` to display the zones around the towns
- `showPerksAndTowns` to show landmarks

Further information can be found in the [scripting api reference](https://wiki.transportfever3.com/script-doc/content/gui/construction/construction_menu.html#$content.gui.construction.construction_menu~ConstructionActionHudIcons).

The usual defaults for different construction types are provided in the `::/gui/construction/construction_desc_hud_icons.script.tl` script file.

## Configure Layer Script

The `configureLayerScript` function allows defining a custom layer state that shall be displayed when the entity window of this construction is open

```lua
...
upgradeFn = function(captureParams, layerConfig)
  return layerPollution.getConfig()
end
...
```

The `capturedParams` contains the parameters forwarded with the script reference in the `.con.lua`. Beside that, `layerConfig` contains the currently visible layerConfig on the screen.

It is expected that the function returns a valid [layer configuration](https://wiki.transportfever3.com/script-doc/api/type.html#$api.type~LayerConfig).

## Entity Window Script

The `entityWindowScript` function allows defining custom content for the entity window that is visible when the construction is selected.

```lua
...
entityWindowFn = function(
    captureParams : table, 
    entity : Engine.Entity,
    tag : string,
    gameCtx : GameContext,
    isMapEditor : boolean,
    isSandboxMode : boolean,
    setActionFnAndProxy : {function(actionFn? : (function() : TreeNodeId), key2? : string), any},
    entityRevisionCloseConditionAndProxy : ({(function() : boolean), any})) : ViewManager.MakeEntityWindowResult
 
  ...
 
  return {
    recipe = make_entity_window.ConstructionWindow,
    param = {
      meta = { tag = tag .. "con" },
      keyEntity = entity,
      gameCtx = gameCtx,
      isMapEditor = isMapEditor,
      isSandboxMode = isSandboxMode,
      setActionFn = actionFnAndProxy.fn,
      setActionFn_compareProxy = actionFnAndProxy.proxy,
      customTabs = customTabs,
    } as ConstructionWindowParam,
    fallbackTitle = _("Construction"),
    replacedEntity = entity,
    autoCloseCondition = entityRevisionCloseConditionAndProxy[1],
    autoCloseCondition_compareProxy = entityRevisionCloseConditionAndProxy[2],
  }
end
...
```

The `capturedParams` contains the parameters forwarded with the script reference in the `.con.lua`. The other parameters provide additional info about the current game state and proxies. Most of them can be forwarded in the default `make_entity_window.ConstructionWindow` function in the `::/gui/entity_window/make_entity_window.tl`.

The result structure of the `entityWindowScript` contains:

- `recipe` with a react recipy that returns a list of tab contents for each subconstruction and optionally some custom ones.
- `params` that are forwarded to the recipy when it is called.
- `fallbackTitle` for the window name.

and some other optional properties.
