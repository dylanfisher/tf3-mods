---
title: Sound Effects
page_id: modding:misc:soundeffects
source: https://wiki.transportfever3.com/doku.php?id=modding:misc:soundeffects
---

# Sound Effects

The immersion of the game is not only supported by the graphics but also by an appealing sound design. It is therefore possible to specify a large number of sound effects in Transport Fever 3.

## Sound Files

All sound files used by Transport Fever 3 adhere to the following technical requirements:

- The required file format is the [Waveform audio file format](https://en.wikipedia.org/wiki/WAV) with the file ending `.wav`.
- The files have to be **mono** sounds. Stereo leads to unintended side effects regarding the sound orientation and distance calculation.
- The bitrate should be **16 bit** and the frequency should be **48000 hertz**.

## Sound Effect Mapping

The sound files may either be referenced in [soundsets](../../modding/misc/soundsets.md) (mostly for vehicles) or in other resources described below:

### Builder Audio Sets

For build and demolition sounds of constructions and terraforming, there are `.builder_audio.lua` resources. They contain references to the relevant subsets of sound effects:

```lua
function data()
  return {
    noMoney = "build/no_money.wav",
    build = "build/construction/large.wav",
 
    dragStart = "build/street/drag_start.wav",
    drag = {
      "build/street/drag_1.wav",
      "build/street/drag_2.wav",
      "build/street/drag_3.wav",
      "build/street/drag_4.wav",
      "build/street/drag_5.wav",
    },
    dragBridge = {
      "build/street/drag_bridge_1.wav",
      "build/street/drag_bridge_2.wav",
      "build/street/drag_bridge_3.wav",
    },
    dragTunnel = {
      "build/street/drag_tunnel_1.wav",
      "build/street/drag_tunnel_2.wav",
      "build/street/drag_tunnel_3.wav",
    },
    dragEnd = "build/street/drag_end.wav",
    dragOffset = -0.2,
 
    bulldoze = "bulldoze/construction/small.wav",
 
    terraform = "terraform/smooth.wav",
  }
end
```

The keys for bulldozing and construction effects are:

- `noMoney` is played when a construction can't be constructed due to a lack of money.
- `build` is played when a construction is built.
- `dragStart` is played when the player starts dragging a street/track (mouse down).
- `drag` contains a list of effects from which some are randomly played while the player drags the street.
- `dragBridge` contains a list of effects from which some are randomly played while a street/track is dragged as a bridge.
- `dragTunnel` contains a list of effects from which some are randomly played while a street/track is dragged as a tunnel.
- `dragEnd` is played when the dragging is done (mouse release).
- `dragOffset` is an offset between the playback of dragging sounds. If negative, they slightly overlap.
- `bulldoze` is played if an element is demolished.
- `terrain` is played while the terrain is modified.

The `builder_audio.lua` files are referenced in different kinds of resources. [Constructions](../../modding/constructions/basics.md), [rocks](../../modding/environment/landscapeassets.md) and [trees](../../modding/environment/landscapeassets.md) reference them as a property in the `soundConfig`:

```lua
soundConfig = {
  effects = {
    select =  {
      "sound/selected_rail_depot.wav"
    }
  },
  builderAudioRes = "::/gui/construction/sound/buildoze_construction_large.builder_audio",
},
```

For [modules](../../modding/constructions/modular.md#modules), [templates](../../modding/constructions/templates.md), [edge addons](../../modding/infrastructure/edgeaddons.md), [streets](../../modding/infrastructure/tracksstreets.md) and [tracks](../../modding/infrastructure/tracksstreets.md) the `builderAudioRes` property is directly on their top level.

Script tools may provide the property as part of the [ConstructionDefinition](https://wiki.transportfever3.com/script-doc/content/gui/construction/construction_menu.html#$content.gui.construction.construction_menu~ConstructionDefinition).

### General Sound Effects

The general sound effects are defined in `.gres.lua` resources.

#### Define Sound Effects

To define sound effects, `.gres.lua` files are used:

```lua
local sfx = {}
 
sfx.LevelUp = {
  resolve("/game_mechanics/towns/sound/level_up_0.wav"),
  resolve("/game_mechanics/towns/sound/level_up_1.wav"),
  resolve("/game_mechanics/towns/sound/level_up_2.wav"),
}
 
sfx.Select = { resolve("/game_mechanics/towns/sound/select.wav") }
 
function data()
  return {
    type = "gui_res",
    data = sfx,
  }
end
```

The type is set to `gui_res` and data contains a table with keys and lists of `.wav` files.

#### Use Sound Effects in Scripts

To use the defined sound resources in the script and retrieve a sound file reference, the following code is used:

```lua
local companySFX = api.gui.genericRep.get(api.gui.genericRep.find("::/game_mechanics/company/sound/company_sfx.gres")).data as CompanySFX
local sound : ResName
 
if companySFX and companySFX.LevelUp and #companySFX.LevelUp > 0 then
  sound = companySFX.LevelUp[math.random(1, #companySFX.LevelUp)]
end
```

#### Overwrite Sound Effects

To overwrite sound effects defined in `.gres.lua` files, it is possible to define another `.gres.lua` file with the following content:

```lua
function data()
  return {
    type = "gui_res_overwrite",
    data = {
      overwriteScript = {
        fileName = "sound_overwrite.script@overwrite",
        params = {},
      },
    },
  }
end
```

The type is set to `gui_res_overwrite` and the referenced script file contains

```lua
local data : OverwriteGuiRes = {}
data.overwrite = function(_params : table)
  local soundRes = api.gui.genericRep.get(api.gui.genericRep.find("::/game_mechanics/company/sound/company_sfx.gres"))
  local companySounds = soundRes.data
 
  -- overwrite values
  companySounds.Select = { resolve("better_town_select.wav") }
  -- ...
 
  -- save values
  soundRes:setData(companySounds as table)
end
 
return data
```

The script does the following:

1. The original resource with sound definitions is fetched from the generic repository with `api.gui.genericRep.get()`.
2. Some values are replaced.
3. The resource is updated with `setData`.
