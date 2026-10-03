---
title: Modifiers and Filters
page_id: modding:scripting:modifiersfilters
source: https://wiki.transportfever3.com/doku.php?id=modding:scripting:modifiersfilters
---

> **Wip:**
>
> This page is not yet adapted for Transport Fever 3. The content may be outdated.

# Modifiers and Filters

It is possible to modify and filter game resources from vanilla and mods by using resource modifiers and filters in the runFn function in mod.lua file.

## Resource Modifiers

Modifier functions allow to modify resources on the fly at the time they’re loaded. This is useful to edit the same value in multiple files. in fact, it’s much more convenient than copying and editing all affected files by hand. Furthermore, multiple modifiers can be added by different mods without one mod overriding the files of the other.

A modifier is a function that receives two parameters:

- `fileName` is the name of the resource file that might get modified.
- `data` is the content of the `data()` function in this file.

The function should return the `data` unchanged or adjusted.

To register a resource modifier, call `addModifier(category, fn)` where:

- `category` is the category of resource file that this modifier should be applied to.
- `fn` is the modifier function explained above.

Resource modifiers can be specified for the following categories:

- `loadModel`
- `loadModule`
- `loadStreet`
- `loadTrack`
- `loadBridge`
- `loadTunnel`

- `loadMultipleUnit`
- `loadRailroadCrossing`
- `loadTrafficLight`
- `loadConstruction`
- `loadConstructionCategory`
- `loadConstructionMenu`

- `loadClimate`
- `loadEnvironment`
- `loadTerrainMaterial`
- `loadTerrainGenerator`
- `loadGrass`
- `loadGroundTex`

- `loadCargoType`
- `loadSoundSet`
- `loadScript`
- `loadGameScript`

### Example

As an exemplaric use case, the following modifier function sets the speed limit of all bridges to 200%:

```lua
local function bridgeModifier (fileName, data)
  if data.speedLimit then
    data.speedLimit = 2.0 * data.speedLimit
  end
 
  return data
end
 
addModifier( "loadBridge", bridgeModifier )
```

## File Filters

File filters filter the content of a directory, i.e. they define which files are visible to the game. Mods can install as many file filters as needed, and multiple file filters per category can be specified (to form a filter chain).

A filter is a function that receives two parameters:

- `fileName` is the name of the resource file that might get filtered.
- `data` is the content of the `data()` function in this file.

The function should return `false` if the resource should be deactivated and `true` if the resource should not be deactivated.

To register a file filter, call `addFileFilter(category, fn)` where:

- `category` is the category of resource file that this filter should be applied to.
- `fn` is the filter function explained above.

File filters can be specified for the following categories:

- `model/vehicle`
- `model/person`
- `model/car`
- `model/rock`
- `model/tree`
- `model/other`

- `multipleUnit`
- `street`
- `track`
- `bridge`
- `tunnel`
- `railroadCrossing`

- `trafficLight`
- `environment`
- `construction`
- `module`
- `autoGroundTex`
- `groundTex`

- `terrainGenerator`
- `terrainMaterial`
- `cargoType`
- `grass`
- `gameScript`
- `climate`

### File Filter Util

The `filefilterutil.lua` in `res/scripts/` provides various functions to help with file filtering:

- `util.always` is a pass through filter that does not deactivate anything.
- `util.combineOr` is a function to combine the results of several file filters with an `or` condition. If any of the file filters returns `true`, the function returns `true`.
- `util.combineAnd` is a function to combine the results of several file filters with an `and` condition. If any of the file filters returns `false`, the function returns `false`.
- `package.base` is a file filter that tests if the resource is not part of a DLC or mod.
- `package.mod` is a file filter that tests if the resource is part of a mod.
- `package.baseOrMod` is a file filter that tests if the resource is part of the base game or a mod.
- `package.dlcOrMod` is a file filter that tests if the resource is part of a DLC or mod.
- `model` contains several additional file filters that test if the resource is a model of a certain type.

### Example

The following code installs a filter for vehicles which removes all non-steam-locomotives from the game.

```lua
local function myFilter(fileName, data)
  if data.metadata.railVehicle and data.metadata.railVehicle.engines and
      #data.metadata.railVehicle.engines == 1 and data.metadata.railVehicle.engines[1].type ~= "STEAM" then
    return false
  end
  return true
end
 
addFileFilter("model/vehicle", myFilter)
```

[Base Config](../../modding/scripting/baseconfig.md)

[Game Scripts](../../modding/scripting/gamescripts.md)
