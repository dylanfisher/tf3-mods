---
title: Scripting Basics
page_id: modding:scripting:basics
source: https://wiki.transportfever3.com/doku.php?id=modding:scripting:basics
---

This page has been moved, the new location is [API Reference](../../modding/scripting/api.md).

> **Wip:**
>
> This page is not yet adapted for Transport Fever 3. The content may be outdated.

# Scripting Basics

There are plenty of scripting possibilities for Transport Fever 2. Beside the functions in other game resources like constructions, there are some general possibilities:

- `runFn` function in `mod.lua` is a function that is called when the mod is loaded.
- `postRunFn` function in `mod.lua` is a function that is called after the `runFn` of all activated mods ran at least once and the other resources are loaded.
- [Game scripts](../../modding/scripting/gamescripts.md) that are callback based and used ingame.
- [Missions](../../modding/scripting/missions.md) as specialized game scripts with indicated tasks to fulfill.

The two basic functions are described below.

## Scripting in mod.lua

The main file of every mod is `mod.lua`. This file contains the mod's metadata as well as the functions that are executed when the game is initialized. The general properties are described in [mod components documentation](https://wiki.transportfever3.com/doku.php?id=modding:modcomponents#modlua).

```lua
function data()
return {
  -- metadata
  info = {
     -- Properties as described in Mod Components
     -- Mod Parameters: (optional)
     params =  { ... } 
  },
 
  -- additional options to show in the advanced game settings menu (optional)
  options = {
    terrain = { { "test1", _("Test entry 1") }, ... },
  },
 
  -- main function before resource loading (optional)
  runFn = function (settings, modParams)
    -- put your code here!
  end, 
 
  -- additional function after resource loading (optional)
  postRunFn = function (settings, params)
    -- put your code here!
  end,
}
end
```

All scripting possibilities in the `mod.lua` are optional and can be omitted if not needed.

### Mod Parameters

Mods can provide individual parameters in the `params` property of the `info` struct. These use the parameter types that are available for [constructions](../../modding/constructions/basics.md#parameters) too. The user can select his preferences in the advanced settings when creating a new game or loading an existing savegame. Parameters of all mods are available in the `runFn` function described below.

A small demo mod was provided in the game release notes once the mod parameter feature was introduced. You can [download it here](../../_media/modding/templates/mod_params_1.zip) too.

### Options

The `options` struct enables mods to add additional values to the advanced game option categories provided by the game:

- `climate` contains a list of available climates.
- `vehicles` contains a list of available vehicle sets.
- `nameList` contains a list of available town name sets.
- `environment` contains a list of available environments.
- `difficulty` contains a list of difficulty levels.

The initial set of options (and the base run functions) are defined in `res\config\base_mod.lua`. To add additional options in one of the categories, a list can be added to the `options` struct with the category as the key. Eack element of the list consists of two values:

1. the option identifier that will be provided to the runFn.
2. the text that should be displayed in the dropdown.

### RunFn

The main function that is called when a mod is loaded is the `runFn` function. It receives two parameters:

- `settings` containing the list of option categories and the chosen option identifiers.
- `modParams` a list of all mod parameters with the mod id as key of the list items. To retrieve the list of parameters for the current mod, `modParams[getCurrentModId()]` can be used.

What is done with these parameters is up to the mod. There are multiple ways how a mod can do its work:

- Config variables: the game configuration can be changed directly by setting the appropriate values in the configuration struct.
- File filter: a function that is invoked for all files in a directory. The function can then decide whether the file should be included or not. The file filter can access the data in the file, making it a very versatile tool.
- Modifier: a function that is invoked after a resource file has been loaded. It is used for modifying the data on the fly.

See the following pages for information on [game configs](../../modding/scripting/baseconfig.md), [resource modifiers](../../modding/scripting/modifiersfilters.md#resource_modifiers) and [file filters](../../modding/scripting/modifiersfilters.md#file_filters).

### PostRunFn

The `postRunFn` function is called once after all resources are loaded. It receives two parameters:

- `settings` containing the list of option categories and the chosen option identifiers.
- `modParams` a list of all mod parameters with the mod id as key of the list items. To retrieve the list of parameters for the current mod, `modParams[getCurrentModId()]` can be used.

It is possible to use script functions provided by the [Scripting API](../../modding/scripting/api.md), e.g. it is possible to add additional multiple unit configurations or construction modules based on the loaded resources.

#### Example

The `base_mod.lua` contains an exemplaric `postRunFn` function that dynamically adds track modules for all loaded track types.

```lua
postRunFn = function(settings, params)
  -- fetch all loaded track types from the track types repository
  local tracks = api.res.trackTypeRep.getAll()
 
  -- iterate over the list and do for each of the track types
  for __, trackName in pairs(tracks) do
 
    -- initialize a new module
    local mod = api.type.ModuleDesc.new()
 
    -- fetch the data for the current track type
    local track = api.res.trackTypeRep.get(api.res.trackTypeRep.find(trackName))
 
    -- exclude the vanilla track types as there are already trackmodules for them
    if trackName ~= "standard.lua" and trackName ~= "high_speed.lua" then 
 
      -- generate two modules per tracktype, one without and one with catenary
      for __, catenary in pairs({false, true}) do
 
        -- mimic a fileName
        mod.fileName = "trainstation_" .. tostring(trackName) .. (catenary and "catenary" or "")
 
	...
 
        -- add description and an icon reference		
	mod.description.name = track.name .. (catenary and _(" with catenary") or "")
	mod.description.description = track.desc .. (catenary and _(" (with catenary)") or "")
	mod.description.icon = track.icon
	if mod.description.icon ~= "" then
	  mod.description.icon = string.gsub(mod.description.icon, ".tga", "")
	  mod.description.icon = mod.description.icon .. "_module" .. (catenary and "_catenary" or "") .. ".tga"
        end
 
        ...
 
        -- provide functions for ''updateFn'' and ''getModelsFn'' 				
        mod.updateScript.fileName = "construction/station/rail/modular_station/trackmodule.updateFn"
        mod.updateScript.params = {
	  trackType = trackName,
	  catenary = catenary
        }
        mod.getModelsScript.fileName = "construction/station/rail/modular_station/trackmodule.getModelsFn"
        mod.getModelsScript.params = { 
          trackType = trackName,
	  catenary = catenary
        }
 
        -- add the new module definition to the module repository			
        api.res.moduleRep.add(mod.fileName, mod, true)
      end
    end
  end
end
```

Due to parallelized resource loading, the `runFn` and `postRunFn` function may be called more than one time. Keep this in mind if experimenting with advanced scripts and try to reduce stdout output if not needed.

[Base Config](../../modding/scripting/baseconfig.md)
