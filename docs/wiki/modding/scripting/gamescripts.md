---
title: Game Scripts
page_id: modding:scripting:gamescripts
source: https://wiki.transportfever3.com/doku.php?id=modding:scripting:gamescripts
---

> **Wip:**
>
> This page is not yet adapted for Transport Fever 3. The content may be outdated.

# Game Scripts

With game scripts, it is possible to provide functions that are called in certain situations. Game script files are defined in `.gs.lua` resources:

```lua
function data()
  return {
    updateScript = {
      fileName = "towns.script@update",
    },
    handleEventScript = {
      fileName = "towns.script@handleEvent",
    },
    guiHandleEventScript = {
      fileName = "towns.script@guiHandleEvent",
    },
  }
end
```

The returned struct has a list of callbacks which may called by the game. Actually, the game has two seperate main threads:

- the engine thread that deals with the simulation
- the gui thread that deals with the user interaction and visualization

Both threads are seperated and it is not possible to directly share variables between them!

The list in a game script consist of functions some of which are called by the engine thread and some of which are called by the gui thread.

It is possible to use `api` functions in the callback functions. See the [API reference](../../modding/scripting/api.md) for further details.

## Engine Callbacks

There are three script callbacks that are used by the engine thread:

- `updateScript` is a callback that is regularily called to do update processing in the engine simulation. As it is executed in parallel for every game script, it may not write the state itself. Its result struct is forwarded to the next script.
- `postUpdateScript` is a callback that is executed after all the update scripts are done.
- `handleEventScript` is a callback that is called whenever an engine event happens, including the `init` and `initMapEditor` events triggered once after start or load of a savegame/map.

## UI Callbacks

There are two callbacks that are used by the gui thread:

- `guiUpdateScript` is a callback that is regularily called to refresh the gui.
- `guiHandleEventScript` is a callback that is called whenever a registered gui event happens.

## Communication between Threads

To send information from the ui thread to the engine thread, it is possible to invoke an engine thread event that will be called later by the engine thread with

```lua
game.interface.sendScriptEvent(...)
```

The same game script or any other game script can then deal with it in its `handleEvent` callback.

To send information from the engine thread to the ui thread, the engine thread should use the `save` function to store some data. It can be accessed from the gui thread at a later point with the `load` callback that is triggered several times in a second.

## Serialization

Some game scripts need the possibility to store some information into savegames and restore them at a later point. The `save` and `load` callbacks are used for this purpose too:

### Save

The `save` callback is used to store information in a shared state that can be read by both threads to update their local state variables. When the game is saved, this state will be serialized and stored in the `.sav.lua` file that comes with the savegame.

```lua
  ...
  save = function ()
    return ...
  end,
  ...
```

The function has no parameters but returns a struct that is then stored in

### Load

The `load` callback is used to fetch the information from the shared state on savegame load and during the game. Both thread call it once on savegame load and it is repeatedly called during the game for the ui thread.

```lua
local state = { counter = 0 }
 
  ...
  load = function (allState)
    state = allState or state
  end,
  ...
```

The stored information is provided as a parameter and can then be proceeded in the callback method. As it is possible that savegames do not contain stored data, e.g. when the game script with the `load` callback was added with a new mod just before the load of the savegame, it is recommended to have a default state as fallback.

Please note that the game scripts only receive stored data that was saved from a game script file with the same filename. They do not get access to stored data of another script.

[Modifiers & Filters](../../modding/scripting/modifiersfilters.md)

[Missions](../../modding/scripting/missions.md)
