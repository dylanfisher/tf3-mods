---
title: Climates
page_id: modding:environment:climates
source: https://wiki.transportfever3.com/doku.php?id=modding:environment:climates
---

# Climates

Transport Fever 3 has the ability to define different climate zones. They vary in the look and feel of the environment, as they have different plants, colors, terrain textures and lighting.

## Configuration

A climate zone is defined in a `.clima.lua` file. The file has the following setup:

```lua
function data() 
 
return {
  id = "temperate",
  desc = { 
    name = _("Temperate"),
    description = _("Mixed Forest Vegetation"),
    icon = "temperate.tga"
  },
  order = 1,
  category = "temperate.clima",
 
  defaultNames = "/names/europe/europe.names",
  economy = "/economy/temperate.eco",
  environment = "temperate.env",
 
  nodeTree = "temperate_clima.tree",
 
  audio = { environment = {...}},
  mapColoring = {...},
  groundTextures = {...},
  skirt = {...},
}
end
```

While `id` is a unique technical identifier, `name` and `description` are strings which can be translated in a [strings.json](../../modding/general/moddefinition.md#stringsjson) file. The referenced ui `icon` for climates is used in some main menu dialogs and is 600x400 px in @2 resolution. The climate zones are ordered in the dialogs according to their `order` values and the `category` key is used to filter trees and other game resources properly.

To set the default game settings per climate zone, the following properties reference the equivalent game resources:

- `defaultNames` references the default [name set](../../modding/misc/names.md) to be used for towns, bus stop and people names.
- `economy` references the default economy to be played in this climate zone.
- `environment` references the sky and water [environment](../../modding/environment/environments.md) settings to be used in this climate zone.

The `nodeTree` reference points to the node tree used for [material distribution](../../modding/environment/climates.md#terrain_material_distribution).

[Environmental sounds](../../modding/environment/climates.md#environment_audio) can be configured in `audio.environment`.

![](../../_media/modding/environment/map_coloring.png)

The `mapColoring` struct defines the colors that are used for the map preview in terrain generator dialogs. It has several properties:

- `levels` is a list of level definitions. Each level stands for a color at a certain height and consists of two values:

  - `color` is a color definition with three values between 0 and 1 for the red, green and blue channel.
  - `height` is the height level at which this color should be used. Intermediate height levels are interpolated between colors.
- `waterColor0` is the color definition for the shallow water in the shore area.
- `waterColor1` is the color definition for the deep water area.
- `ambientColor` is the color definition for the overall color grading of the preview map.
- `sunColor` is the color definition for the sun exposure.

![](../../_media/modding/environment/skirt.png)

The `groundTextures` struct is used to assign special `.gtex` ground textures for several purposes:

- `waterGround` is the texture that is used below water, e.g. in lakes and rivers.
- `waterShore` is the border texture that is used along the shoreline.

The `skirt` struct is used to define the textures used for the edges of the game world:

1 `colorTex` is the texture map that is used as base colors for the edge faces.   
2 `detailTex` is the texture map that is used as overlay to get some randomzation of colors at the faces.   
3 `waterText` is the texture map that is used as base color for the areas of edge faces that touch water.

## Environment Audio

The environmental sounds are configured in the `audio.environment` struct of the climate. There are different types of configurations, all basing on a few standard properties:

```lua
mountain = {
  sounds = { 
    { file = "::/climates/sound/environment/nature/mountain.wav" }
  },
  refDist = 15.0,
  height = 0.0,
  layer = 3,
  ambient = true,
  altitudeRange = { 200.0, 4000.0 },
},
```

The properties are:

- `sounds` with a list of sounds, see details below.
- `refDist` is a numeric value describing the reference distance for the standard loudness of the sound.
- `height` is a numeric value to define the height above ground where the sound is emitted
- `layer` is an integer used to prioritize sounds. The environment audio system will prefer to play sounds from the layer with the lowest number, if any sound from a layer is used, then sounds of higher layer won't be played. If a layer has multiple sounds defined, a mix of them will play.
- `altitudeRange` is pair of boundaries to restrict the sound to a certain camera height.
- `ambient` is a flag to mark this sound to be a fallback if no other environment sound is active.

The following keys can be used for the structs:

- `water`: Sounds used where there's a water mesh.
- `forest`: Sounds used where tree density is high enough.
- `traffic`: Sounds used where cars are present.
- `crowd`: Sounds used where person are present.
- `atmosphere`: Wind sounds for the sky. This audio source is always active and fixed at 4000m altitude.
- `rain`: The audio source is always at the camera position and the volume depends on the rain intensity.
- `lowland` / `mountain`: they use the `ambient` flag. If no other sounds are playing, those will try to play based on their conditions.

Additionally there are keys for every district in towns: `residential`, `commercial` and `industrial`. They each have a list of 4 entries describing the 4 building levels.

To add custom sound layers, the key `terrainMasks` holds a list with struct entries. The keys of the structs need to match the mask keys exported with `Data Output` nodes during map generation.

The `sounds` list contains substructs with two keys:

- file: the file path to the sound resource
- tags: a list of tags used to filter the sounds, see below.

Only one matching sound out of the `sounds` list is played at a time.

The following tags are available:

- `"day"`: set during the daytime, for now fixed based on game time, the day always starts at 6:00 and ends at 19:00
- `"night"`: set during nighttime
- `"clear"`: set when the sky is clear (opposite of rain)
- `"rain:"`: set when it's raining (opposite of clear)
- `"year1900"`: set between 1900 and 1919
- `"year1920"`: set between 1920 and 1989
- `"year1990"`: set from 1990 onwards

## Terrain Material Distribution

The `nodeTree` of climates is called after every change of terrain to recalculate the default terrain texture distribution over the map. It can be edited with the  [Terrain Generator Editor](../../modding/tools/terraingeneratoreditor.md) included in the Map Editor.

### Inputs

![](../../_media/modding/environment/terrain_texture.gif)  
layers generated by updateFn

The tree may get multiple inputs:

- `Heightmap input` is used to retrieve the actual heightmap of the map.
- `Map data` is used to retrieve the map size and seed value:

  - `Seed` contains the map seed as number output.
  - `Map bounds min.` provides the x an y minimums of the map bounds.
  - `Map bounds max.` provides the x an y maximums of the map bounds.
  - `Water level` is currently not provided ![FIXME](/lib/images/smileys/fixme.gif).
- `Data input` is used to retrieve masks saved during map generation. It receives a `Key` parameter to identify the right mask.

All three types of nodes can be used multiple times.

### Output

![](../../_media/modding/environment/dithering.gif)  
no dithering and dithering

The tree may generate one or more terrain material masks. Each mask output is defined in a `Material Output` node that receives a `Material Map` as the map that will be used to draw the material (transparency value between 0 and 1). Additionally it receives several parameters:

- `Order` is the integer number used as layer order of this terrain material.
- `Key` is ![FIXME](/lib/images/smileys/fixme.gif)
- `Material type` is the reference to the terrain material that shall use this mask.
- `Dither` is a boolean parameter used to select if the material should be dithered / mixed with the neighbors.

To define the underlying base terrain material, a `Material background output` node needs to be added as well. It just has one parameter `Material type` to reference the terrain material.
