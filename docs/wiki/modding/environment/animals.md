---
title: Animals
page_id: modding:environment:animals
source: https://wiki.transportfever3.com/doku.php?id=modding:environment:animals
---

# Animals

Animals basically are [models](../../modding/general/resourcetypes/mdl.md) as any other object in the game, but they have some unique events and a special metadata struct so they are spawned and move around the map.

## Metadata

In addition to the general `.mdl` properties, animals use the `cameraConfig` struct as players can follow animals in first person view. Furthermore, there is a metadata struct called `animal`:

```lua
function data()
return {
  -- bounding box
  -- collider
  -- lods
 
  metadata = {
    description = {
      name = _("Salmon"),
    },
    cameraConfig = {...},
    animal = {
      config = {...},
      flockName = "",
      flockFormationFn = { 
        fileName = "/animal/animal.script@flock.salmon",
        params = { },
      },
      movement = {...},
      movementTypes = {...},
      suitableAreas = {...},
    },
    categoryList = { 
      categories = { "temperate.clima", "subarctic.clima", },
    },
  },
  version = 1,
}
end
```

The `name` is shown as the default name if the user clicks on an animal. It can be translated in a [strings.json](../../modding/general/moddefinition.md#stringsjson) file.

The `cameraConfig` struct is used for the first person view. To learn how to define camera views, read the relevant section in the [model definition documentation](../../modding/general/resourcetypes/mdl.md#cameraconfig).

The `animal` struct contains several property structs, these are described below.

### Config

![](../../_media/modding/environment/predator.png)  
highlighted area around predators

The `config` struct contains several general properties for animals:

- `density` is a float value. Land animals and birds usually have value 1, fishes have density 4.
- `fish` is a boolean value. When it is set to `true`, the animal is restricted to water.
- `idleTime` is the time that is spent in idle mode before moving somewhere else.
- `predator` is a boolean value. If set to true, this animal will be avoided by some others, e.g. deers avoid bears.
- `targetDistance` is a float value. It is the distance in which the animals look for new target locations.

### Flocks

![](../../_media/modding/environment/salmons.gif)

Birds and Fishes may travel around in flock formations. If an animal has a configured flock, it will move in this group. Otherwise the animal will move alone.

The flock formations have a name that is specified in `flockName`. The formation is configured in an external `.script.lua` file. This is referenced in `flockFormationFn`.
The `.script.lua` looks like this:

```lua
function data()
return {
  flock = {
    salmon = function()
    ...
    return { 
      positions = {...},
      overrides = {...},
    }
    end
  },
  ...
}
end
```

The functions do not have any parameters. The expected result struct contains two properties:

- `positions` is a list of positions with three numbers for the X/Y/Z coordinates each. The coordinates are relative to the flock origin
- `overrides` is an optional list of models that shall be used instead of the main model, e.g. to have color variant.

### Movement

The `movement` struct describes some restrictions regarding where the animals move:

- `alignToTerrain` is `true` for land animals, as they move along the terrain surface. Birds or fishes have the property set to `false`.
- `heightOffset` is the value they are offsetted of the water height if `alignToTerrain` is `false` or the terrain surface, if `alignToTerrain` is set to `true`. Fishes usually have negative values, birds have positive values.
- `rollWhileTurning` is set to `true` if the animal should roll a bit when turning around curves. Usually that is done for birds.
- `stickToWater` restricts animals to water areas. This is set to `true` for fishes.
- `wobbleWhenIdle` is set to `true`, if the animal should move slightly in idle state. This is usually used for fishes too.

### Movement Types

It is possible to define several movement types. For example, land animals can stay around (idle), walk and run. For each of the movement types, there is a struct in the `movementTypes` list with the following properties:

- `angularSpeed` is the turn speed. Slow angular speed results in the animal having very large curve radii.
- `description` is a translatable string to describe the current action. It is shown in the animal detail window.
- `despawnAtEnd` is a boolean value set to true if the animal should be removed after the animation completed, e.g. after an animal died.
- `duration` is a number value setting the length of the animation.
- `eventName` is the name of the event that is defined in the levels of detail.
- `playOnce` is set to `true`, if the animation is not looping, e.g. when the animal dies.
- `playRandomly` is set to `true`, if this movementType can occure randomly. The normal behaviour of an animal is a series of such random animations.
- `playWhenSelected` is set to `true` if the animation should be played whenever the player clicks on the animal. For example, a bear is roaring.
- `speed` is the speed of the animal while this animation is played. It is specified in meter per second.

### Suitable Areas

![](../../_media/modding/environment/animal_score.png)

The `suitableAreas` struct is used to limit the occurance and movement of animals to certain areas. There are several terrain related factors as well as factors related to other animals. All factors are mapped to scores. The overall sum of scores summarizes the likelyhood of the animal existing in a certain spot. If an animal gets into an area with negative score, it will try to run away. If it fails to leave the non suitable area it will eventually die.

- `bias` is a static score offset applied to any animal.
- `height` is a struct property that maps an interval of heightlevels `mapFrom` to an interval of scores `mapTo`. Height values below the lower interval limit are considered equal to the lower limit, height values above the upper limit are considered equal to the upper limit.
- `noise` is a struct property that maps an interval of emission levels `mapFrom` to an interval of scores `mapTo`. Height values below the lower interval limit are considered equal to the lower limit, height values above the upper limit are considered equal to the upper limit.
- `scores` is a struct of criterias with static scores:

  - `civilisation` is everywhere were AI or player constructed buildings and streets are.
  - `fish` is the area around water animals.
  - `forest` is the area around trees.
  - `predator` is the area around animals with `config.predator == true`.
  - `ship` is the area around ships on rivers or lakes.
  - `shore` is the area along river and lake borders.
  - `water` is the area where there is water.
- `slope` is a struct property that maps an interval of steepness levels `mapFrom` to an interval of scores `mapTo`. Height values below the lower interval limit are considered equal to the lower limit, height values above the upper limit are considered equal to the upper limit.
- `waterDepth` is a struct property that maps an interval of water depth levels `mapFrom` to an interval of scores `mapTo`. Height values below the lower interval limit are considered equal to the lower limit, height values above the upper limit are considered equal to the upper limit.

It is possible to analyze the score factor maps with the [ingame debug tools](../../modding/tools/ingame.md#debug_tool_window).

## Events

The events of animals are mostly defined by their `movementTypes`. The most common events are:

- `idle` animation is used for a resting animal or for sailing birds. It can be looped.
- `idle_standing` animation is used for resting birds. It can be looped.
- `walk` / `fly` / `swim` animations are used for actively moving animals. It can be looped.
- `run` animation is used for fast moving animals. It can be looped.
- `roar` / `intimidate` / `eat` / `pee` / `baa` / `kick` / `sitdown` animations are used for random events or when the player clicks on an animal.
- `die` is used for the end of life sequence of an animal. It is played only once.

![](../../_media/modding/environment/deer_idle.gif)![](../../_media/modding/environment/deer_walk.gif)![](../../_media/modding/environment/deer_run.gif)![](../../_media/modding/environment/deer_intimidate.gif)![](../../_media/modding/environment/deer_die.gif)
