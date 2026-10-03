---
title: Sound Sets
page_id: modding:misc:soundsets
source: https://wiki.transportfever3.com/doku.php?id=modding:misc:soundsets
---

# Sound Sets

Sound sets are configuration files that group several [sounds](../../modding/misc/soundeffects.md) together to get an appropriate sound background. This is used e.g. for vehicles. The sound sets are defined in `.snd.lua` files. They need to have a `data()` function that returns a data struct like below:

```lua
function data()
  return {
    tracks = { ... },
    events = { ... },
    updateScript = {
      fileName = "::/scripts/soundset_default.script@updateSoundSet",
      params = { ... },
    },
  }
end
```

The sound set data struct has three properties:

- `tracks` is a list of data pairs with two properties each:

  - `name` is a reference to a sound file.
  - `refDist` is the reference distance to which the loudness of the sound file is normalized.
- `events` is a list of event structs. Each struct is identified by a key and has two properties:

  - `names` is a list of references to sound files.
  - `refDist` is the reference distance to which the loudness of the sound file is normalized.
- `updateScript` is a script reference to an update function that is used to modify pitch and gain depending on the current ingame situation, e.g. the speed of a vehicle.

Tracks are looped sounds, whereas events are only played once per trigger.

## Update Script

The script function referenced with `updateScript` receives three parameters:

- `captureParams` contains the provided parameters next to the reference in the `.snd.lua`.
- `params`: A struct with global data as well as info about the individual models and its context to be used to adjust the particles. See the documentation about [transformators](../../modding/vehicles/advancedtopics.md#transformatorparams).
- `soundTransfOutput` is the output object that is used in the update function.

The function is expected to call the two functions provided by the `soundTransfOutput`:

- `addTrack` is called once per track to provide a pitch and gain value.
- `addEvent` may be called to playback an event. The function retrieves the event key as used in the soundset definition above as well as gain and pitch.

## Soundset Util

To facilitate the creation of soundsets, there is a soundsetutil that is used in most sound sets. Therefore the effective structure of the sound set files is mostly like this:

```lua
local soundsetutil = require "/scripts/soundsetutil.lua"
 
function data()
  local data = soundsetutil.makeSoundSet()
 
  soundsetutil.addTrackParam01(
    data, "vehicle/tram_old/drive.wav", 18.0,                 
    { { .0, .0 }, { .1, .32 }, ... }, { { .0, 1.0 } }, {"vehicle", "speed01"} 
  )	
  ...
 
  soundsetutil.addEvent( data, "openDoors", { "vehicle/tram_old/bell.wav" }, 5.0 )
  ...
 
return data
end
```

The `soundsetutil.lua` provides a couple of functions that can be used:

### makeSoundSet

The `soundsetutil.makeSoundSet()` function is the basic function that sets up the internal structure of the soundset for the use of other util functions. It is required to be used before the other functions.

### addEvent

The `soundsetutil.addEvent(data, key, names, refDist)` function is used to add an unconditionally event to the sound set. The parameters are:

- `data` is the reference to the result data struct.
- `key` is the key that is used as event trigger.
- `names` is the list of references to sound files.
- `refDist` is the reference distance for the sound radius.

If there is more than one sound file referenced, one is chosen randomly.

### addEventParam01

The `soundsetutil.addEventParam01(data, key, names, refDist, gainCurve, pitchCurve, infoAndParamGain, infoAndParamPitch)` function is used to add an event to the sound set in dependence of input conditions. The parameters are:

- `data` is the reference to the result data struct.
- `key` is the key that is used as event trigger.
- `names` is the list of references to sound files.
- `refDist` is the reference distance to which the loudness of the sound file is normalized.
- `gainCurve` is a list of `{<input value>, <gain value>}` pairs. Values between are interpolated, inputs beyond the lowest and highest index values are clamped.
- `pitchCurve` is a list of `{<input value>, <pitch value>}` pairs. Values between are interpolated, inputs beyond the lowest and highest index values are clamped.
- `infoAndParamGain` is a pair of keys where the first key is one of the structs in the `CurrentInfo` struct, e.g. `"vehicle"` and the second is one of the children of that struct, e.g. `"speed01"`. This parameter is used to map the gain according to the `gainCurve`.
- `infoAndParamPitch` is a pair of keys where the first key is one of the structs in the `CurrentInfo` struct, e.g. `"vehicle"` and the second is one of the children of that struct, e.g. `"speed01"`. This parameter is used to map the gain according to the `pitchCurve`. If unset, `infoAndParamGain` is used for the pitch as well.

### addTrackParam01

The `soundsetutil.addTrackParam01(data, name, refDist, gainCurve, pitchCurve, infoAndParamGain, infoAndParamPitch)` function is used to add a track to the sound set in dependence of input conditions. The parameters are:

- `data` is the reference to the result data struct.
- `name` is the reference to a sound file.
- `refDist` is the reference distance to which the loudness of the sound file is normalized.
- `gainCurve` is a list of `{<input value>, <gain value>}` pairs. Values between are interpolated, inputs beyond the lowest and highest index values are clamped.
- `pitchCurve` is a list of `{<input value>, <pitch value>}` pairs. Values between are interpolated, inputs beyond the lowest and highest index values are clamped.
- `infoAndParamGain` is a pair of keys where the first key is one of the structs in the `CurrentInfo` struct, e.g. `"vehicle"` and the second is one of the children of that struct, e.g. `"speed01"`. This parameter is used to map the gain according to the `gainCurve`.
- `infoAndParamPitch` is a pair of keys where the first key is one of the structs in the `CurrentInfo` struct, e.g. `"vehicle"` and the second is one of the children of that struct, e.g. `"speed01"`. This parameter is used to map the gain according to the `pitchCurve`. If unset, `infoAndParamGain` is used for the pitch as well.

### addSimpleTrackParam01

The `soundsetutil.addSimpleTrackParam01(data, name, refDist, infoAndParamGain)` function is a simplified version of the function above. Pitch is constant at level 1, while gain is equal to the input value. The parameters are:

- `data` is the reference to the result data struct.
- `name` is the reference to a sound file.
- `refDist` is the reference distance to which the loudness of the sound file is normalized.
- `infoAndParamGain` is a pair of keys where the first key is one of the structs in the `CurrentInfo` struct, e.g. `"vehicle"` and the second is one of the children of that struct, e.g. `"speed01"`. This parameter is used to define the gain.

### addTrackSqueal

The `soundsetutil.addTrackSqueal(data, name, refDist)` function is a specialised function to add a track in dependance of the speed and side force. It usually can be heared when a train drives over switches. The parameters are:

- `data` is the reference to the result data struct.
- `name` is the reference to a sound file.
- `refDist` is the reference distance to which the loudness of the sound file is normalized.

### addTrackBrake

The `soundsetutil.addTrackBrake(data, name, refDist, maxGain)` function is a specialised function to add a track in dependance of the speed and brake intensity. It usually can be heared when a vehicle decelerates. The parameters are:

- `data` is the reference to the result data struct.
- `name` is the reference to a sound file.
- `refDist` is the reference distance to which the loudness of the sound file is normalized.
- `maxGain` is the upper limit of the gain curve. Vehicles with modern brake systems often have lower gain limits.

### addEventClacks

The `soundsetutil.addEventClacks(data, names, refDist, axleRefWeight)` function is a specialised function to add an event in dependance of the speed, weight and number of axles. It usually can be heared as small clack sounds when a train runs along tracks and the wheels run over imperfect welding seams or screwed track ends. The more weight lasts on an axle, the louder the sounds can be heared. The parameters are:

- `data` is the reference to the result data struct.
- `names` is the list of references to sound files.
- `refDist` is the reference distance to which the loudness of the sound file is normalized.
- `axleRefWeight` is the reference weight that lasts on one axle when the vehicle is fully loaded.

### addTrackCustom

The `soundsetutil.addTrackCustom(data, name, refDist, gainCurve, pitchCurve, infoAndParamGain, infoAndParamPitch, customUpdateScript)` function is used to add a track with a custom update function to the sound set. The parameters are:

- `data` is the reference to the result data struct.
- `name` is the reference to a sound file.
- `refDist` is the reference distance to which the loudness of the sound file is normalized.
- `gainCurve` is a list of `{<input value>, <gain value>}` pairs. Values between are interpolated, inputs beyond the lowest and highest index values are clamped.
- `pitchCurve` is a list of `{<input value>, <pitch value>}` pairs. Values between are interpolated, inputs beyond the lowest and highest index values are clamped.
- `infoAndParamGain` is a pair of keys where the first key is one of the structs in the `CurrentInfo` struct, e.g. `"vehicle"` and the second is one of the children of that struct, e.g. `"speed01"`. This parameter is used to map the gain according to the `gainCurve`.
- `infoAndParamPitch` is a pair of keys where the first key is one of the structs in the `CurrentInfo` struct, e.g. `"vehicle"` and the second is one of the children of that struct, e.g. `"speed01"`. This parameter is used to map the gain according to the `pitchCurve`. If unset, `infoAndParamGain` is used for the pitch as well.
- `customUpdateScript` is a script reference to custom update function.

A custom update function receives the following parameters:

- `result` is the result struct that shall be edited. It has two properties: `gain` and `pitch`. Both are initialized with 1.
- `customParams` containing the info provided with the parameters of the util function, e.g. `gainCurve`.
- `currentInfoParams` allows for individual and additional conditions as it the full `CurrentInfo` struct.

The `content/vehicle/bus/shared/sound/bus_electric.snd.lua` sound set is an example using this function to restrict a track to only play during acceleration and not during deceleration.

### addEventCustom

The `soundsetutil.addEventCustom(data, key, names, refDist, gainCurve, pitchCurve, infoAndParamGain, infoAndParamPitch, customUpdateScript)` function is used to add an event with a custom update function to the sound set. The parameters are:

- `data` is the reference to the result data struct.
- `key` is the key that is used as event trigger.
- `names` is the list of references to sound files.
- `refDist` is the reference distance to which the loudness of the sound file is normalized.
- `gainCurve` is a list of `{<input value>, <gain value>}` pairs. Values between are interpolated, inputs beyond the lowest and highest index values are clamped.
- `pitchCurve` is a list of `{<input value>, <pitch value>}` pairs. Values between are interpolated, inputs beyond the lowest and highest index values are clamped.
- `infoAndParamGain` is a pair of keys where the first key is one of the structs in the `CurrentInfo` struct, e.g. `"vehicle"` and the second is one of the children of that struct, e.g. `"speed01"`. This parameter is used to map the gain according to the `gainCurve`.
- `infoAndParamPitch` is a pair of keys where the first key is one of the structs in the `CurrentInfo` struct, e.g. `"vehicle"` and the second is one of the children of that struct, e.g. `"speed01"`. This parameter is used to map the gain according to the `pitchCurve`. If unset, `infoAndParamGain` is used for the pitch as well.
- `customUpdateScript` is a script reference to custom update function.

A custom update function for events receives the following parameters:

- `result` is the result struct that shall be edited. It has two properties: `gain` and `pitch`. Both are initialized with 1. Additionally there is a boolean `trigger` which needs to be set to true if the event is custom and shall be triggered right away.
- `customParams` containing the info provided with the parameters of the util function, e.g. `gainCurve`.
- `currentInfoParams` allows for individual and additional conditions as it the full `CurrentInfo` struct.
- `previousInfoParams` allows for individual and additional conditions as it the full `PreviousInfo` struct.

> **Caution:**
>
> The `trigger` flag should be true only one frame, otherwise the sound will be triggered multiple times in short succession. Hence it is good to use transitions between previous and current state to be precise.

### makeRoadVehicle2

The `soundsetutil.makeRoadVehicle2(data, speeds, idle, idleSpeed, idleGain0, drive, driveSpeed, refDist, infoAndParamGain, infoAndParamPitch)` function is a specialized function to add sounds for a road vehicle. The parameters are:

- `data` is the reference to the result data struct.
- `speeds` is a list of three relative speed values in the range between 0 and 1 where the first and second values limit the interval in which the idle sound should be heard loudest and the third one marks the point where the drive sound can be heard and the idle sound is gone.
- `idle` is the reference to an idle sound file.
- `idleSpeed` is a coefficient for the pitching curve of the idle sound. It usually is 0.075.
- `idleGain0`is the gain value for the idle sound when the input parameter (most times speed) is zero.
- `drive` is the reference to a drive sound file.
- `driveSpeed` is a coefficient for the pitching curve of the drive sound. It usually is 0.4.
- `refDist` is the reference distance to which the loudness of the sound file is normalized.
- `infoAndParamGain` is a pair of keys where the first key is one of the structs in the `CurrentInfo` struct, e.g. `"vehicle"` and the second is one of the children of that struct, e.g. `"speed01"`. This parameter is used to map the gain according to the `gainCurve`.
- `infoAndParamPitch` is a pair of keys where the first key is one of the structs in the `CurrentInfo` struct, e.g. `"vehicle"` and the second is one of the children of that struct, e.g. `"speed01"`. This parameter is used to map the gain according to the `pitchCurve`. If unset, `infoAndParamGain` is used for the pitch as well.

### makeSteamTrain

The `soundsetutil.makeSteamTrain(data, idle, fast, tracksRefDist, chuffNames, chuffsRefDist, chuffsFastFreq, refWeight)` function is a specialised function to add sounds for a steam engine. The parameters are:

- `data` is the reference to the result data struct.
- `idle` is the reference to an idle running sound file.
- `fast` is the reference to a fast running sound file.
- `tracksRefDist` is the reference distance to which the loudness of the track sound file is normalized.
- `chuffNames` is the list of references to chuffing sound files.
- `chuffRefDist` is the reference distance to which the loudness of the chuff sound files is normalized.
- `chuffsFastFreq` is a coefficient for the calculation of the gain and pitching curve of the fast running sound.
- `refWeight` is the reference weight that is used to influence the gain in dependance of the vehicle wait.

## Event Keys

Depending on the type of object, there are several keys available for the sound events defined in sound sets:

| Event Key | Town Buildings | Stations | Industries | Road Vehicles | Rail Vehicles | Water Vehicles | Air Vehicles | Description |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| "random<n>" | ✔ | ✔ | ✔ |  |  |  |  | occurs approx. every n seconds (n is one of 1, 2, 4, 8, 16, 32, 64) |
| "openDoors" |  |  |  | ✔ | ✔ | ✔ | ✔ | occurs after arrival at a station |
| "closeDoors" |  |  |  | ✔ | ✔ | ✔ | ✔ | occurs before departure from a station |
| "horn" |  |  |  |  | ✔ | ✔ |  | occurs at station departure |
| "clacks" |  |  |  |  | ✔ |  |  | occurs regularily while moving (for axle clacks) |
| "chuffs" |  |  |  |  | ✔ |  |  | occurs regularily while moving (for steam chuffs) |
| "sonicBoom" |  |  |  |  |  |  | ✔ | occurs when speed gets larger than the speed of sound |
| "land" |  |  |  |  |  |  | ✔ | occurs when the weels touch the ground |

Adding custom events is currently only supported through triggers from [edge objects](../../modding/infrastructure/signals.md).
