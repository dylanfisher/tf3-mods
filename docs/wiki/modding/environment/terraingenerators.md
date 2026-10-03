---
title: Terrain Generators
page_id: modding:environment:terraingenerators
source: https://wiki.transportfever3.com/doku.php?id=modding:environment:terraingenerators
---

# Terrain Generators

Terrain generators are used to define biome regions, generate a heightmap and distribute tree and rock assets on them. They are configured in `.gen.lua` files and their basic structure is:

```lua
function data() 
return {
  climate = "temperate.clima.lua",
  desc = {
    name = _("Temperate"),
  }
  order = 0,
  editorOnly = false,
  params = {...},
  nodeTree = "temperate_gen.tree.lua",
  previewSeed = "yQKiK",
}
end
```

There are several simple properties:

- `climate` is a reference to the `.clima.lua` climate, for which this generator can be used.
- `desc.name` is the name that should be displayed in a dropdown if multiple generators are available for the climate zone. It can be translated using a [strings.json](../../modding/general/moddefinition.md#stringsjson) file.
- `order` is used for the order in the dropdown where the generators can be selected.
- `editorOnly` restricts the generator to only be available in the map editor (useful for pure asset generators). Unset or false results in the generator being available in the main menu too.

It is possible to provide several parameters with which the user can set some preferences for terrain generation. See the [construction basics](../../modding/constructions/basics.md#parameters) to learn more about parameter properties.

The `nodeTree` references the node tree `.tree.lua` file containing the actual logic of the map generator. The `previewSeed` can be defined to provide an initial seed when editing the generator in the Terrain Generator Editor.

## Node Tree

The terrain generator is defined as a procedural node graph that can be edited with the  [Terrain Generator Editor](../../modding/tools/terraingeneratoreditor.md) included in the Map Editor.

### Inputs

![](../../_media/modding/environment/terrain_gen_300.gif)

The tree may get multiple inputs:

- `Map data` is used to retrieve the map size and seed value:

  - `Seed` contains the map seed as number output.
  - `Map bounds min.` provides the x an y minimums of the map bounds.
  - `Map bounds max.` provides the x an y maximums of the map bounds.
  - `Water level` is currently not provided ![FIXME](/lib/images/smileys/fixme.gif).
- `Input parameter` is used to retrieve the selected parameter values. This node has two parameters:

  - `Key` is used to reference the correct parameter.
  - `Dummy` is used to define the value that shall be used as placeholder within the Terrain Generator Editor.

Both types of nodes can be used multiple times.

### Output

The terrain generator tree has multiple outputs used for different aspects.

#### Biome masks

With nodes of the type `Data output`, the biome masks can be extracted. They are stored within the savegame to be used, e.g. for environmental sounds. Each `Data output` node has three parameters aside from the `Output` map that is injected from another node:

- `Key` is the identifier used in other game resources, e.g. for the environmental sounds in the `.clima.lua`.
- `x-Resolution scale` is an integer value defining the equivalent in meters for one pixel of that mask in x direction.
- `y-Resolution scale` is an integer value defining the equivalent in meters for one pixel of that mask in y direction.

The values for the output maps are from 0 to 1.

#### Heightmap

The main heightmap is exported with the `Heightmap output` node. It does not have any additional parameters beside the input map. The values of that map need to be in meters.

#### Forests & Assets

The third part of the terrain generator usually covers the generation of trees, rocks and other assets. A mask containing the forest areas is exported using the `Data output` node described above. It is used for the dynamic reforestation over time, after the player deleted structures that previously removed trees from forests.

The initial generation of assets and trees is defined in the `Asset output` node. It receives two maps as input, one for `Assets` and one for `Forests`. In the `Assets mapping` and `Forest mapping` parameter tables, the values of these maps are then mapped to tags. Assets available in the climate zone with the same tags in their `categoryList.categories` are then randomly selected during the actual generation.
