---
title: Modular Constructions
page_id: modding:constructions:modular
source: https://wiki.transportfever3.com/doku.php?id=modding:constructions:modular
---

# Modular Constructions

Modular constructions are built like every other construction with parameters but can be edited afterwards by adding and removing some parts like pieces of a puzzle. These parts are called modules. The locations where they can be placed are indicated by slots.

To provide different start configurations, it is possible to define [construction templates](../../modding/constructions/templates.md).

## Method Cycle

Whenever a construction shall be previewed or actually built, a meta function is executed that orchestrates the execution of update functions for the whole construction as well as the individual modules.

It first calls the `updateFn` function of the construction and stores its result. If the parameters contain modules - both via template calls or during construction reconfiguration - a second part is executed. For each module, sorted in ascending order of the `slotId`s, the following steps are executed:

1. Search for the `slotId` in the list of existing slots in the current result set from the construction and previous modules.
2. If the `slotId` is not in the list and invalid slots are not accepted (`result.callInvalidModules` unset or `false`) skip the current module.
3. Fetch the slot location and tag name.
4. Prepare the `addModel` function.
5. Call the `updateFn` function of the module and provide the `addModel` function.

Finally if the construction added a `terminateConstructionHook`, that will be executed.

## Construction UpdateFn

The `updateFn` function of the construction is used to assemble the core elements of the construction add put them in the result data struct. This may cover basic models, ground faces and terrain alignments as well as additional functions that can be called from modules later:

```lua
...
updateFn = function(captureParams, params)
  ...
  return result
end
...
```

### Parameters

Beside the usual parameters of a construction `updateFn`, it receives a list of all modules that should be built for the construction in `modules`:

```lua
  modules = {
    [10001000] = {
      metadata = {},
      name = "airfield_main_building.module",
      updateScript = {
        fileName = "",
        params = {}
      },
      variant = 0
    },
    ...
  },
```

The index is the slotID where the module should be placed. The properties are:

- `metadata` is a struct containing all the metadata that was set in the `metadata` struct of the module.
- `name` is the reference to the module relative to the construction.
- `updateScript` is the reference to the module updateFn function.
- `variant` is an integer that is increased and decreased by pressing M and N while placing a module. It can be used to provide rotated variants of models in a module or cycle through different assets. The value can be positive and negative, default is 0.

### Return Data Struct

The result data struct is based on the one from [normal constructions](../../modding/constructions/basics.md#update_script). On top there are additional structs specifically for modular constructions:

- `result.slotConfig` for slot type restrictions.
- `result.slots` for a list of slots currently available in the construction.

It is possible that construction extend the `result` by custom structs, e.g. helper functions that can then be used by modules at a later point.

> **Tip:**
>
> The `result.cost` is just the cost of the main construction. Modules may add their cost later.

In the `result.slotConfig` list, there can be restrictions for some slot types. The list uses the slot type as a key and contains two properties for each entry:

- `maxModules` is the maximum amount of modules with this slot type that can be built in the whole construction. If `maxModules` is set to `-2`, it depends on the value of `message` if the module button is enabled or disabled. No messages results in the button being enabled, a set message disables the button. ![FIXME](/lib/images/smileys/fixme.gif)
- `message` is a message that is displayed on modules of this type in the menu, when they can't be build due to the slot configuration restrictions.
- `skipCollisionCheck` is an optional boolean value that is used to disable the ui collision checks. With skipped checks, the slot markers are not painted red when they are obstructed by something else, e.g. free tracks. The potential collider collisions of the module models still apply.

The `result.slots` struct is a list of all currently existing slots in the construction. Each entry in the list has the following properties:

- `id` is the unique slot id that is used as reference for the placed modules. It is a non-negative number.
- `type` is the key that is used to restrict the compatible modules on this position.
- `transf` is the position relative to the construction origin as a transformation matrix.
- `spacing` is a four value vector that is used to set the size of the slot around the `transf` position. It is `{-x, x, -y, y }`.
- `shape` is a value that is used to select the style of the slot marker symbol. It is either `0` for a square, `1` for a triangle, `2` for a transverse rectangle or `3` for a longitudinal rectangle.
- `height` is the height of the slot counted from the position of `transf`. Together with the `spacing` this is used for selection and bulldozing purposes.
- `autofill` is a boolean value used for industry fields/satellites. If set to true, these slots are considered to be filled on initial construction of the industry.
- `alignToTerrain` is a boolean value used for constructions that should adapt to the terrain. If set to true, the slot is considered to be aligned to the terrain height at its position.
- `replaceable` is a boolean value used to mark slots where modules may be overridden by modules of the same `type`.

With `result.callInvalidModules` set to `true` it is possible to allow modules in slots that were not predefined, e.g. because they have an ID that is lower than the slot that defines them.

## Construction Upgrade Script

The `upgradeScript` function for modular buildings is only slightly different than [the one for non-modular constructions](../../modding/constructions/basics.md#upgrade_script). The `slotId` parameter contains the slotId where the cursor pointed on when applying the tool.

## Modules

A module is a construct of one or more models that can be placed in certain positions in modular constructions. They are defined in `.module.lua` files. The basic structure of a module is:

```lua
function data()
return {
  availability = { ... },
  menuCategory = { ... },
  description = { ... },
 
  buildMode = "SINGLE",
  autoRemovable = false,
 
  type = "shed",
  metadata = {
    price = 12000,
    maintenanceCost = 2000,
  }
 
  getModelsScript = {
    fileName = "roundhouse_modules.script@shed.getModelsFn",
    params = {
      ...
    },
  },
 
  updateScript = {
    fileName = "roundhouse_modules.script@shed.updateFn",
    params = {
      ...
    },
  },
}
end
```

Beside the usual `availability`, `description`, `menuCategory` and `buildMode` known from constructions, each modules has additional properties:

- `autoRemovable` is an optional property to flag this module for automatic removal when something else is built over it. This is used for fields of industries. If unset, it is considered as `false`
- `type` is a key that is used to restrict modules to a certain slot type

To provide additional static metadata, the modules can provide more information in a `metadata` struct. It might be used by the construction and other modules to identify this module properly. It also may contain info about the build and maintenance cost of the module.

Before a module is actually placed, the `getModelsScript` is used to provide the models for a floating module preview attached to the cursor. The `updateScript` references the update function that is executed on update of the construction. It may receive additional parameters as `captureParams`. See below for more details.

### Module GetModelsFn

The `getModelsFn` is a function without any parameters other than `captureParams`. It returns a list of models that should be used for the floating preview that follows the mouse cursor while not pointing on a slot. The function looks like:

```lua
...
getModelsFn = function()
  local result = {
    { 
      id = "hangar_preview.mdl",
      transf = transf.identity(),
    }
  }
  return result
end,
...
```

### Module UpdateFn

The `updateFn` function of modules is called after the construction `updateFn` to add the models of the module to the construction as well as do all the stuff that is needed for the module, e.g. adding terminals. It receives several parameters:

1. the `captureParams` provided by the script reference in the `.module.lua`
2. the `result` of the `updateFn` from the construction or the module that was called before containing all previously added models, data etc.
3. the `transformation` of the slot relative to the construction origin as a transformation matrix. This should be applied to all models of the module if they are located relative to the slot. Be aware that the `transformation` is nil if the construction makes use of the `callInvalidModules` property.
4. a `tag` that should be added to the models in the result to assign them to the current module at that slot. This is used to identify models that are removed when a module is demolished.
5. the `slotId` that is a unique numeric identifier of this slot.
6. the `addModuleFn` function is a function that adds models to the construction and ensures that the correct `tag` is set. It is provided in the `construction.script.tl` in `constructWithModules`.
7. the `constrParams` struct containing all params that the construction got for its `updateFn` function too.

Note that not all modules need every parameter. It is possible to omit parameters from the end of the function header. A function that uses only some of the parameters could look like:

```lua
...
updateFn = function(captureParams, result, transform, tag)
  result.subconstructions[1].models[#result.subconstructions[1].models + 1] = { 
    id = "hangar.mdl",
    transf = transform,
    tag = tag
  }
 
  local faces = { {-25.0, -25.0, 0.0, 1.0}, {25.0, -25.0, 0.0, 1.0}, ... }
  modulesutil.TransformFaces(transform, faces)
  result.subconstructions[1].groundFaces[#result.subconstructions[1].groundFaces + 1] = {  
    face =  faces,
    modes = {
      {
        type = "FILL",
        key = "airfield_hangar.gtex.lua",
	texCoords = { {.0, .0}, {1.0, .0}, {1.0, 1.0}, {.0, 1.0} }
      },
    }
  }
 
  -- add further stuff		
end,
...
```

The `updateFn` should return the `result` that was received where the content of the module was inserted.

> **Tip:**
>
> Make sure to apply the transformation matrix received as `transform` parameter to all models, ground faces, terrain alignments, … of the module before adding them to the `result` if you intend to place them relative to the slot position.

> **Download:**
>
> ##### Rail Station Module
>
> This example provides a custom roof module for the vanilla train station that allows to span large hall roofs over multiple tracks. It is available for [download](../../_media/modding/constructions/modular/wiki_example_station_module.zip).
>
> Explanation
>
> The `platform_passenger_roof_hall.module.lua` defines an additional module for the vanilla rail station:
>
> ```lua
> ...
> local modelConfig = {
>   stands = resolve("roof_hall_stands.mdl"),
> }
> ... 
>   updateScript = {
>   fileName = "station_hall_modules.script@platformPassengerHallRoof.updateFn",
>   params = {
>     modelConfig = modelConfig,
>   },
> },
> getModelsScript = {
>   fileName = "station_hall_modules.script@platformPassengerHallRoof.getModelsFn",
>   params = {
>     modelConfig = modelConfig,
>   },
> },
> ...
> ```
>
> At the very top, there is a local struct named `modelConfig` which contains some data about models to be used, here the pillar models for the station roof. This data is provided to the module script functions as `captureParams`.
>
> Other relevant properties are the `type` and `metadata`:
>
> ```lua
> ...
> type = "passenger_platform_roof",
> metadata = {
>   platform_roof = true,
>   platform_roof_curved = true,
>   platform_roof_hall_style = "test",
>   maintenanceCost = 0,
> },
> ...
> ```
>
> The `type` is the same as the one of the vanilla roofs, so this roof module can be built wherever the other roofs could be placed. The `metadata` is available to be used as context info by other modules. This possibility is used to identify a second placed module with the same metadata and calculate the roof span between them. This happens in the `updateFnPlatformPassengerHallRoof` function in the `station_hall_modules.script.lua`:
>
> ```lua
> local updateFnPlatformPassengerHallRoof = function(captureParams, result, transform, tag, slotId, addModel, constrParams, params)
>   local modelConfig = captureParams.modelConfig
>   result = result.cargoStation
>   local addModelFn = function(a, b, c) addModel(a, b, c, result.models) end
>  
>   addModelFn(modelConfig.stands, transf.rotZTransl(math.rad(90), vec3.new(0, 0, -2)))
>  
>   local coords = result.GetCoord(slotId)
>   local i = coords[1]
>   local j = coords[2]
>  
>   for i2 = i+1, i+9 do
>     local roofAti2 = result.GetRoofAt(i2, j)
>     if roofAti2 and roofAti2.metadata.platform_roof_hall_style == result.GetRoofAt(i, j).metadata.platform_roof_hall_style then
>       local roofModel = hallRoofStyle2Size2ModelsConfig[roofAti2.metadata.platform_roof_hall_style][(i2-i)*5]
>       addModelFn(roofModel, transf.rotZTransl(math.rad(-90), vec3.new(0, 0, -2)))
>       break
>     end
>   end
> end
> ```
>
> First, the pillar model is added to the result by calling `addModelFn(modelConfig.stands, transf.rotZTransl(math.rad(90), vec3.new(0, 0, -2)))`. This `addModelFn` is a function that is defined directly above. It basically just forwards the call to the `addModel` function provided as parameter in the `updateFn`.
>
> Next, the coordinates in the vanilla station grid are calculated. The relevant info is coded into the `slotId` and the vanilla station offers a helper function to retrieve the coordinates, called `GetCoords(slotId)`.
>
> Based on these coordinates, the neighbors to one side are checked for the presence of another roof module. This is done by retrieving info with the `GetRoofAt(x,y)` function in a loop that steps further away step by step. If a roof module is present at a position, `roofAti2` is not nil. Then the metadata of the current module and the found one are compared to check if `platform_roof_hall_style` is equal. In that case, the correct model for the distance is selected by using the look up table `hallRoofStyle2Size2ModelsConfig` and it is added to the result as well. Afterwards the loop is stopped with `break`.

> **Download:**
>
> ##### Standalone Modular Construction
>
> This example provides a simple independent modular construction. It showcases how to set up slots and how modules may react depending on neighboring slots. It is available for [download](../../_media/modding/constructions/modular/wiki_example_modular_construction.zip).
>
> Explanation
>
> The example vaguely resembles a turntable with adjacent roundhouse. Every locomotive stand can be set as seperate module, either with a shed or without. If a shed has no other shed module as neighbor, a wall should fill the side.
>
> The mod contains several files relevant for the construction:
>
> - `.mdl` files and the required materials and meshes for turntable, empty stand, shed stand and a left and right sidewall for the shed.
> - the static `roundhouse.con.lua` for the definition of the construction and its `roundhouse.script.lua` for the scripts.
> - two module files `shed.module.lua` and `empty.module.lua` for the two module types and a shared `roundhouse_modules.script.lua` file for the scripts of both modules.
>
> The `roundhouse.con.lua` is rather simple and follows the standards described in the [construction basics](../../modding/constructions/basics.md). It could be extended by providing parameters or even different templates for the player to choose.
>
> The `roundhouse.script.lua` adds the turntable model to the result:
>
> ```lua
> ...
> mainSubconstruction.models[#mainSubconstruction.models + 1] = {
>   id = "turntable.mdl",
>   transf = transf.identity()
> }
> ...
> ```
>
> Additionally it sets up the slots that can be filled by the player by placing modules:
>
> ```lua
> ...
> result.slots = { }
>  
> for i = 1, 30 do
>   result.slots[i] = {
>     id = i,
>     type = "shed",
>     transf = transf.mul(transf.rotZ(math.rad(-12 + i * 12)), transf.transl(vec3.new(30, 0, 0))),
>     spacing = {4, 4, 1, 1},
>     shape = 1,
>     height = 1,
>     replaceable = true,
>   }
> end
> ...
> ```
>
> The full circle is divided in 30 12-degree segments and with a for loop, a slot is added for each segment. The slots are 30 meters away from the turntable center and rotated to align to the rays from the center. Their `type` is set to `shed`, so any module of the same type can be placed there.
>
> Both module definition files are rather simple. The big difference is that the `shed.module.lua` has an additional entry `type = "shed"` in the metadata. This is relevant for the neighbor logic in the script. As required, both modules reference both a getModelsScript and an `updateScript`.
>
> The `roundhouse_modules.script.lua` returns a hierarchical table with the functions:
>
> ```lua
> function data()
>   return {
>     shed = {
>       updateFn = updateFnShed,
>       getModelsFn = getModelsFnShed,
>     },
>     empty = {
>       updateFn = updateFnEmpty,
>       getModelsFn = getModelsFnEmpty,
>     },
>   }
> end
> ```
>
> When editing the construction, the player sees what is returned by the `getModelsFn` floating at the cursor. To ensure the shed looks proper, the function returns not just one but three models. All these models are shifted by -30 meters to compensate the slot offset that was previously defined in the main construction:
>
> ```lua
> ...
> local getModelsFnShed = function(captureParams)
>   return {
>     { 
>       id = "shed_wall_left.mdl", 
>       transf = transf.transl(vec3.new(-30,0,0)) 
>     },
>     { 
>       id = "shed_segment.mdl", 
>       transf = transf.transl(vec3.new(-30,0,0)) 
>     },
>     { 
>       id = "shed_wall_right.mdl", 
>       transf = transf.transl(vec3.new(-30,0,0)) 
>     }
>   }
> end
> ...
> ```
>
> The update function of the empty module is rather simple, it just adds a single `.mdl`. The `updateFnShed` starts doing the same, but has some additional logic:
>
> ```lua
> ...
> local leftIndex  = (slotId % maxSegments) + 1
> local rightIndex = ((slotId - 2) % maxSegments) + 1
>  
> local moduleLeft = constrParams.modules[leftIndex]
> local moduleRight = constrParams.modules[rightIndex]
> ...
> ```
>
> Based on the `slotId`, the left and right neighbor ids are calculated, using the modulo operation `%`. To safely wrap around from 1 to 30, some shifting is done. Then for both potential neighbors, data is retrieved with `constrParams.modules[index]`. If these slots are not occupied or the modules in the slots do not have the metadata `type = "shed"`, the side wall models are added as well:
>
> ```lua
> ...
> if not (moduleLeft ~= nil and moduleLeft.metadata ~= nil and moduleLeft.metadata.type == "shed") then
>   addModel("shed_wall_left.mdl", transf.transl(vec3.new(-30, 0, 0)), tag, result.subconstructions[1].models)
> end
> if not (moduleRight ~= nil and moduleRight.metadata ~= nil and moduleRight.metadata.type == "shed") then
>   addModel("shed_wall_right.mdl", transf.transl(vec3.new(-30, 0, 0)), tag, result.subconstructions[1].models)
> end
> ...
> ```
