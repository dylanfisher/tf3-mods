---
title: Railroad Crossings
page_id: modding:infrastructure:railroadcrossings
source: https://wiki.transportfever3.com/doku.php?id=modding:infrastructure:railroadcrossings
---

# Railroad Crossings

Railroad Crossings are defined in `.rcr.lua` configuration files. They use models that can have certain animation events.

## Configuration

The configuration file of a railroad crossing has several properties:

```lua
function data()
return {
  description = {
    name = _("Half-barrier crossing"),
    icon = "era_b_eu.tga",
  },
  availability = {
    yearFrom = 1925,
    yearTo = 1975,
  },
  menuCategory = {
    categories = {
      {
        filterCategories = {"special"},
        order = 5000,
      },
    },
  },
 
  categoryList = {
    categories = {
      "temperate.clima", "subarctic.clima"
    },
  },
 
  cost = 16000,
  soundFileName = "railroad_crossing.wav",
  crossingMaterial = "street/railroad_crossing.mtl",
  trafficDelay = 3500,
 
  config = {
    { 
      modelLeft = "railroad/crossing/eu_a_simple.mdl", 
      modelRight = "railroad/crossing/eu_b_barrier_small.mdl", 
      streetWidth = 12.0
    },
  },
}
end
```

The properties in detail:

- `description` contains two properties:

  - `name` is the name of the railroad crossing type. It can be translated in a [strings.json](../../modding/general/moddefinition.md#modinfojson) file.
  - `description` is the description tooltip. It can be translated in a [strings.json](../../modding/general/moddefinition.md#modinfojson) file.
  - `icon` is a reference to a small `@2x.tga` icon which has a resolution of 120×76 pixels shown in the menu when railroad crossing types can be selected.
- `availability` contains

  - `yearFrom` is the year from when the railroad crossing should be available. Unset or values below 1901 mean from start.
  - `yearTo` is the year until when the railroad crossing should be available. Unset or value 0 means unlimited availability, values below 1900 result in a never available railroad crossing.
- `menuCategory` is used to define the filter categories and order. See the [construction menu](../../modding/constructions/menu.md) for more details about them.
- `categoryList.categories` is a list of tags that are used in the terrain generation process and climate filtering. Entries that equal the filename of a climate are used to assign the model to a certain climate. It will not be available in other climates.
- `cost` is the cost for a railroad crossing.
- `soundFileName` is a reference to a sound effect file that is played while the railroad crossing is closing or closed.
- `crossingMaterial` is a material reference for the shape that lays between the two rails of the track. If unset, `infrastructure/railroad_crossing/shared/mat/railroad_crossing.mtl` is used as fallback.
- `trafficDelay` is the time in milliseconds between the begin of the open animation and the point where the road traffic starts to move again. If unset, the delay is 2500 ms.

The `config` list contains one or more configuration structs. Each of the configuration structs has three properties:

- `modelLeft` is the model that is used at the left side of the street in direction towards the crossing.
- `modelRight` is the model that is used at the right side of the street in direction towards the crossing.
- `streetWidth` is the street width for which the configuration is suited best.

If there is more than one configuration available, the one that matches the actual street width best is chosen.

## Events

![](../../_media/modding/infrastructure/railroad_crossing.gif)  
railroad crossing animations

Railroad crossings support some [animation events](../../modding/general/resourcetypes/mdl.md#animations) that are triggered depending on their state. They can be used in mesh nodes of their models to support the visualisation of the two states 'open' and 'closed':

- `forever` animation is used for any permanently looped animation.
- `idle_open` animation is used as a loop while the railroad crossing is in 'open' state.
- `close` animation is used when the railroad crossing switches from 'open' to 'close'.
- `idle_closed` animation is used as a loop while the railroad crossing is in 'closed' state.
- `open` animation is used when the railroad crossing switches from 'closed' to 'open'.

While the `forever` animation runs constantly, the other four events form a loop.
Usually a railroad crossing is in 'open' state and the `idle_open` animation is performed. As soon as a train is approaching the `close` animation is performed once. Then `idle_closed` is looped as long as the railroad crossing stays closed. When the train is through and the railroad crossing turns back to open, `open` is performed once before `idle_open` is looped again.

The idle animations can be used e.g. for blinking lights.
