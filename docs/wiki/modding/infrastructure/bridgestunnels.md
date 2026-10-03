---
title: Bridges and Tunnels
page_id: modding:infrastructure:bridgestunnels
source: https://wiki.transportfever3.com/doku.php?id=modding:infrastructure:bridgestunnels
---

# Bridges and Tunnels

Bridges and tunnels for streets and tracks are defined with [config files](../../modding/general/resourcetypes.md#lua_for_configurations) too.

## Bridges

A bridge configuration files specifies a set of parameters to define the properties, dimension, features, and visuals of bridges. They are stored in `.bridge.lua` filesand have the following format:

```lua
function data()
return {
  -- property definitions
 
  materialsToReplace = { ... },
  assetsToReplace = { ... },
 
  updateScript = {...}
}
end
```

### Property Definitions

The bridge properties start with the common metadata properties:

```lua
  description = {
    name = _("Stone bridge"),
    icon = "stone.tga",
  },
  availability = {
    yearFrom = 0,
    yearTo = 0,
  },
  menuCategory = {
    categories = {
      {
        filterCategories = {"special"},
        order = 5000,
      },
    },
  },
 
  cost = 200.0,
  maintenanceCost = 10.0,
  costFactors = { 10.0, 2.5, 1.0 },
 
  carriers = { "RAIL" , "ROAD"},
  speedLimit = 90.0 / 3.6,
  isAutoSelectable = true,
```

Their meaning is as follows:

- `description` contains two properties:

  - `name` is the name of the bridge type. It can be translated in a [strings.json](../../modding/general/moddefinition.md#modinfojson) file.
  - `description` is the description tooltip. It can be translated in a [strings.json](../../modding/general/moddefinition.md#modinfojson) file.
  - `icon` is a reference to a small `@2x.tga` icon which has a resolution of 120×76 pixels shown in the menu when bridge types can be selected.
- `availability` contains

  - `yearFrom` is the year from when the bridge should be available. Unset or values below 1901 mean from start.
  - `yearTo` is the year until when the bridge should be available. Unset or value 0 means unlimited availability, values below 1900 result in a never available bridge.
- `menuCategory` is used to define the filter categories and order. See the [construction menu](../../modding/constructions/menu.md) for more details about them.
- `cost` is the building cost coefficient. The costs of the bridge itself are calculated by multiplying this value with the area below the bridge. In addition the street or track on top has its own cost.
- `maintenanceCost` is the monthly billed cost coefficient. The maintenance costs of the bridge itself are calculated by multiplying this value with the area below the bridge. In addition the street or track on top has its own cost.
- `costFactors` are three additional coefficients that are used to calculate the area below the bridge. For every ~5m along the bridge, the height difference to the ground is measured and the resulting area for that step is calculated with: `5 * (a * heightDiff ^ b + c)` where a is `1 / (costFactors[1] ^ costFactors[2])`, b is `costFactors[2]` and c is `costFactors[3]`.
- `carriers` is a list of carrier keys to define if bridges should be available for `"RAIL"` and/or `"ROAD"`.
- `speedLimit` is the maximum speed in meter per second. If the track or street has a lower speed restriction, the bridge speed limit is ignored.
- `isAutoSelectable` is a boolean flag used to prevent some special bridge types from being automatically selected when building roads or tracks. If unset, it is considered as `true`.

There are several properties available to control the pillars:

```lua
  pillarLen = 3,
  pillarWidth = 5,
 
  pillarMinDist = 12.0,
  pillarMaxDist = 48.0,
  pillarTargetDist = 12.0,
  ignoreWaterCollision = false,
 
  pillarGroundTexture = "/terrain/materials/dirt/dirt.gtex",
  pillarGroundTextureOffset = 10.0,
 
  abutmentLen = 3,
  abutmentWidth = 4,
 
  noParallelStripSubdivision = false,
  autoGeneration = false,
```

- `pillarLen` is the length of pillar on ground level that is used for collision calculation and ground texture.
- `pillarWidth` is the width of pillar on ground level that is used for collision calculation and ground texture.
- `pillarMinDist` is the minimum distance between 2 pillars.
- `pillarMaxDist` is the maximum distance between 2 pillars.
- `pillarTargetDist` is the optimum distance between 2 pillars that is used as default.
- `ignoreWaterCollision` is a boolean flag that will encourage equally spread pillars even if it results in them being in the water. When set to `false`, the pillars are preferably build on land.
- `pillarGroundTexture` is a reference to a [ground texture](../../modding/constructions/groundtextures.md) that should be used around the pillars.
- `pillarGroundTextureOffset` is a distance which is added to all sides of the pillar in which the pillar ground texture is used too.
- `abutmentLen` is the length of abutments on track/street level that is used for height, collision calculation and ground texture.
- `abutmentWidth` is the width of abutments on track/street level that is used for height, collision calculation and ground texture.

Another property is `noParallelStripSubdivision`. If it is set to `true`, the `updateFn` will be called for the whole bridge instead of seperate segements. Be aware that bridge segments are limited to a length of 100 meters, so this property might be relevant for bridges with large gaps between pillars. If set to `false` or the property is unset, the `updateScript` will be called several times. Larger pillar distances then will result in no pillars.

To prevent bridge types from being used during map generation and automated spawning of new roads, the `autoGeneration` flag can be set to false.

### Material & Assets Override

![](../../_media/modding/infrastructure/bridges/materialstoreplace.png)
ballast material is replaced

To adjust the optics of the street or track on the bridge, it is possible to override materials and assets as well as the `sidewalkHeight`.

The `materialsToReplace` list is used to overwrite materials defined in the [street](../../modding/infrastructure/tracksstreets.md#materials) and [track](../../modding/infrastructure/tracksstreets.md#materials) configuration. See there for further details on the purposes of the different types.

The `assetsToReplace` list allows removing or replacing materials:

```lua
assetsToReplace = {
  ["street_light"] = {
    name = "/assets/streets/street_light_eu_b.mdl",
    offset = 8.0,
    distance = 16.0,
    prob = 1.0,
    offsetOrth = 3.0,
    randRot = false,
    oneSideOnly = false,
    alignToElevation = false,
    avoidFaceEdges = false,
  }, 
  ["fireplug"] = { }, 
```

The keys of the struct need to be the same as used in the `.street.lua`. If an empts list is assigned to a key (as in the `fireplug` entry), the asset will be skipped completely.

### Update Script

The `updateScript` references a function in a `.script.lua` file that is used to construct the bridge from individual model parts. It is common to forward some metadata next to the reference which is then available as `captureParams` in the function.

When called, the update function receives the mentioned `captureParams` and a second set of `params` containing the bridge configuration that shall be built. It has the following values:

- `pillarHeights` contains a list with the heights of all the pillars.
- `pillarWidth` is the width of a pillar.
- `pillarLength` is the length of a pillar.
- `railingWidth` is the width of the bridge.
- `railingIntervals` is list of bridge parts between the pillars. There are six properties for each section:

  - `curvature` is the inversion of the radius in this railing section (`1/radius`).
  - `hasPillar` is a pair of two values that are the ids of the pillars at the start and end of the railing section. `-1` tells that it is the start or end of the whole bridge part that is built with the `updateFn` call.
  - `lanes` is a list of lanes that are built with the bridge. For streets and single tracks, there is only one entry in the list but for parallel tracks, there is an entry for each track. Each entry has two properties:

    - `offset` is the orthogonal offset from the bridge center lane. For tracks this is usually a multiple of 5.
    - `type` is the collision type of this particular lane, see below.
  - `length` is the length of the railing section between the pillars.
- `hasAbutment` is a pair of boolean values, describing if there is an abutment at the start and/or end of the bridge segment.
- `abutmentHeight` is a pair of numbers providing info about the needed height for the abutments.
- `beginNeedEntry` is a boolean value describing if the bridge has a transition from land at the start of the segment.
- `endNeedEntry` is a boolean value describing if the bridge has a transition to land at the end of the segment.

The collision types that can be used to prevent railings are:

- `0` no collision
- `1` collision on the left (in the dragging direction)
- `2` collision on the right (in the dragging direction)
- `3` collision on both sides

It is expected that the result contains two lists:

- `result.pillarModels` is a list of pillars and abutments. Each element of the list corresponds to one of the `params.pillarHeights` entries and after that the start and end abutments if needed. The elements are lists themselves containing all the rows of models for each pillar.
- `result.railingModels` is a list of railing sections. Each element of the list corresponds to one of the `params.railingIntervals` entries, thus both lists have the same length. The elements are lists themselves containing all the rows of models for each railing section.

```lua
return {
  pillarModels = { 
    { -- pillar 1
      { -- row 1
        { id = "bridge/stone/pillar_btm_side.mdl", transf = { ... } }, 
        { id = "bridge/stone/pillar_btm_rep.mdl", transf = { ... } },
        { id = "bridge/stone/pillar_btm_side2.mdl", transf = { ... } },
      },
      ... -- more rows
    },
    ... -- more pillars and abutments if needed
  },
  railingModels = {
    { -- section 1
      { -- row 1
        { id = "bridge/stone/railing_end_side.mdl", transf = { ... } }, 
        { id = "bridge/stone/railing_end_rep.mdl", transf = { ... } },
        { id = "bridge/stone/railing_end_rep.mdl", transf = { ... } },
      },
      ... -- more rows
    },
    ... -- more sections
  },
}
```

#### Bridge Util

To ease the configuration of simple bridges, the `/infrastructure/bridges/bridgeutil2.lua` offers a prefabricated update function `makeDefaultUpdateFn`, which is also used by several of the vanilla bridges. This function gets a config struct as `captureParams`. The contents of this struct are described below.

Each model reference in the next sections is actually a struct of the following structure:

```lua
{
  "/infrastructure/bridge/steel/b_12_end_rep_l.mdl",
  { { 0, -1.6, -1.7 }, { 12, 0, 9 } },
}
```

The first entry in the struct is the actual reference of a model and the second entry is the bounding box data of the model.

##### Pillars

![](../../_media/modding/infrastructure/pillar.png)

Bridge pillars consist of three mandatory layers, of which the middle layer can be repeated several times:

- `pillarTop` (yellow) is a list of models used for the upper end of the pillar.
- `pillarRepeat` (green) is a list of models used for the height variable part of the pillar. These models are put together vertically several times and, if necessary, scaled slightly to reach the required height.
- `pillarBase` (purple) is a list of models that are used for the bottom layer of the pillar that touches the ground.

An additional `pillarMain` layer list can be added that is used on top of the `pillarTop` layer and above the track or street bed.

All four lists may vary in length. Possible lengths are:

|  |  |  |
| --- | --- | --- |
| 1 model reference |  | This model is set in the middle as a pillar. |
| 2 model references |  | The first model is used for the edges of the pillar (rotated once accordingly), the second model is placed next to each other for the middle of the pillar and scaled slightly until it fills the required width. |
| 3 model references |  | The first model is used for one side of the pillar, the second model is placed next to each other for the middle of the pillar and scaled slightly until it fills the required width and the third model is used for the other side, but not rotated. |

##### Abutments

Bridge abutments are defined in a similar way as the pillars. They consist of three mandatory layers, of which the middle layer can be repeated several times:

- `abutmentTop` (yellow) is a list of models used for the upper end of the abutment.
- `abutmentRepeat` (green) is a list of models used for the height variable part of the abutment. These models are put together vertically several times and, if necessary, scaled slightly to reach the required height.
- `abutmentBase` (purple) is a list of models that are used for the bottom layer of the abutment that touches the ground.

All three lists may vary in length like the ones of the pillars.

##### Railings

![](../../_media/modding/infrastructure/railing.png)

The bridge railing also consists of several rows that are placed next to each other:

- `railingBegin` (purple) is a list of models that are used for the beginning of a bridge railing segment. A railing segment starts at the beginning of the bridge and at each pillar.
- `railingRepeat` (green) is a list of models that are used for the center of a bridge girder segment. These models are lined up horizontally several times and, if necessary, scaled slightly to reach the required length.
- `railingEnd` (yellow) is a list of models that are used for the end of a bridge railing segment.

All three lists may vary in length. There can be either 5 or 8 models in the list. If only 5 elements are included, the elements 1-3 are used as a substitute for 6-8 in a rotated version. The purpose of the elements are:

1. side element
2. side element with no roof because of a collision on the other side
3. side element with no railing and roof because of a colission on this side, e.g. a track switch
4. middle element (that is repeated to fill the bridge width)
5. middle element with no roof because of a collision on at least one of the sides
6. other side element
7. other side element with no roof because of a collision on the other side
8. other side element with no railing and roof because of a colission on this side

##### Other Parameters

There are additional parameters for bridge configurations:

- `alwaysAddRailingBeginEnd` forces the railing to start/end at the segment ends even though there is no pillar.
- `minIntervalLength` allows setting a threshold length in meter under which the segments are not considered to have roofs.

## Tunnels

A tunnel configuration files specifies a set of parameters to define the properties, dimension, features, and visuals of tracks. They are stored in `.tunnel.lua` files.

### Configuration

The file has the following format:

```lua
function data()
return {  
  description = {
    name = _("Standard tunnel"),
    icon = "tunnel_a.tga",
  },
  availability = {
    yearFrom = 0,
    yearTo = 1950,
  },
  menuCategory = {
    categories = {
      {
        filterCategories = {"special"},
        order = 5000,
      },
    },
  },
 
  cost = 200.0,
  maintenanceCost = 10.0,
  costFactors = { 10.0, 2.5, 1.0 },
 
  carriers = { "RAIL" , "ROAD"},
 
  padding = 2,
  height = 10.03,
 
  updateScript = {
    fileName = "tunnel.script@tunnel.updateFn",
    params = config
  },
}
end
```

Many properties are the same as for the bridges. Their meaning is as follows:

- `description` contains two properties:

  - `name` is the name of the tunnel type. It can be translated in a [strings.json](../../modding/general/moddefinition.md#modinfojson) file.
  - `description` is the description tooltip. It can be translated in a [strings.json](../../modding/general/moddefinition.md#modinfojson) file.
  - `icon` is a reference to a small `@2x.tga` icon which has a resolution of 120×76 pixels shown in the menu when tunnel types can be selected.
- `availability` contains

  - `yearFrom` is the year from when the tunnel should be available. Unset or values below 1901 mean from start.
  - `yearTo` is the year until when the tunnel should be available. Unset or value 0 means unlimited availability, values below 1900 result in a never available tunnel.
- `menuCategory` is used to define the filter categories and order. See the [construction menu](../../modding/constructions/menu.md) for more details about them.
- `cost` is the building cost coefficient. The costs of the tunnel itself is calculated by multiplying this value with the area of the tunnel. In addition the street or track inside has its own cost.
- `maintenanceCost` is the monthly billed cost coefficient. The maintenance costs of the tunnel itself are calculated by multiplying this value with the area of the tunnel. In addition the street or track inside has its own cost.
- `costFactors` are three additional coefficients that are used to calculate the in the tunnel. For every ~5m along the tunnel, the height difference to the ground is measured and the resulting area for that step is calculated with: `5 * (a * heightDiff ^ b + c)` where a is `1 / (costFactors[1] ^ costFactors[2])`, b is `costFactors[2]` and c is `costFactors[3]`.
- `carriers` is a list of carrier keys to define if tunnels should be available for `"RAIL"` and/or `"ROAD"`.

It is also possible to overwrite materials and assets as described for bridges above.

Additionally there are functional properties specifically for tunnels. The `padding` describes the offset from the side of the outer lanes to the walls. It is used to calculate the split point of tunnels with diverging tracks/roads. The `height` defines the minimum height of the terrain at the position of the tunnel. It is not possible to lower terrain above the tunnel lower than that with terrain tools.

### Update Script

The `updateScript` references a function in a `.script.lua` file that is used to construct the tunnel from individual model parts. It is common to forward some metadata next to the reference which is then available as `captureParams` in the function.

When called, the update function receives the mentioned `captureParams` and a second set of `params` containing the bridge configuration that shall be built. The params are the same as described for bridges above. There are two properties in the `railingIntervals` for tunnels:

- `beginDeadEndIntervals` describes the front wall of the tunnel segment begin if there is a dead ending lane. It is described from the left wall end of the segment.
- `endDeadEndIntervals` describes the end wall of the tunnel segment end if there is a dead ending lane. It is described from the right wall end of the segment.

It is expected that the result contains a `result.railingModels` list. Each element of the list corresponds to one of the `params.railingIntervals` entries, thus both lists have the same length. The elements are lists themselves containing all the rows of models for each railing section.

#### Default Update Script

The vanilla tunnels use the script in `content/infrastructure/tunnel/tunnel.script.lua@tunnel`. It expects a config struct as `captureParams`:

```lua
updateScript = {
  fileName = "tunnel.script@tunnel.updateFn",
  params = {
    railingBegin = { ... },
    railingRepeat = { ... },
    railingEnd = { ... },
    portalsConfig = { tunnel_a_startportal_rgt, tunnel_a_startportal_rep, tunnel_a_startportal_lft },
    endPortalsConfig = { tunnel_a_endportal_rgt, tunnel_a_endportal_rep, tunnel_a_endportal_lft },
    deadConfig = { tunnel_a_dead_rgt, tunnel_a_dead_rep, tunnel_a_dead_lft, tunnel_a_dead_rgt_end, tunnel_a_dead_lft_end },
    assetsConfig = {
      { tunnel_a_m1_side_lft[1], tunnel_a_m1_add_lamp_lft1[1], 15, 3},
      { tunnel_a_m1_side_rgt[1], tunnel_a_m1_add_lamp_rgt1[1], 20, 5},
      { tunnel_a_m1_side_lft[1], tunnel_a_m1_add_lamp_lft2[1], 13, 0},
      { tunnel_a_m1_side_rgt[1], tunnel_a_m1_add_lamp_rgt2[1], 16, 0},
    }
  }
}
```

Here the properties are the following:

- `railingBegin` is a list of 5 or 8 models for segment starts as described for the bridges above.
- `railingRepeat` is a list of 5 or 8 models for repeating parts of segments as described for the bridges above.
- `railingEnd` is a list of 5 or 8 models for segment ends as described for the bridges above.
- `portalsConfig` is a list of 3 models used for the portal at the start of the tunnel. The models are used as right side, repeating and left side model.
- `endPortalsConfig` is a list of 3 models used for the portal at the end of the tunnel. The models are used as right side, repeating and left side model.
- `deadConfig` is a list of 5 models used for dead ends of tracks in tunnels. The models are used as:

  1. right side of the dead end.
  2. repeating part of a dead end.
  3. left side of a dead end.
  4. corner where there is a dead end on the right and the tunnel continues on the left.
  5. corner where there is a dead end on the left and the tunnel continues on the right.
- `assetConfig` is a list of asset configurations. Each entry has:

  1. a reference to a `.mdl` file to which the asset shall be added.
  2. a reference to a `.mdl` file for the asset.
  3. an interval number to attach the asset every n instances of the parent `.mdl`
  4. an offset to start at the nth instance of the parent `.mdl`
