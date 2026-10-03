---
title: Construction Types
page_id: modding:constructions:types
source: https://wiki.transportfever3.com/doku.php?id=modding:constructions:types
---

# Construction Types

Constructions in Transport Fever 3 are not assigned to a specific type but may consist of zero, one or more different subconstructions with different functionalities. When clicking on a construction, the player will have a window with a tab per functional subconstruction, e.g. one for a station and one for a depot.

> **Tip:**
>
> To improve performance, for simple constructions that only contain one subconstruction and do not contain ground faces, terrain alignments or depot/station/industry/town building definitions, there is no construction placed in the game but just the seperate mdls. These cannot be clicked and configured afterwards or be deleted all at once. Furthermore these types of assets do not support the `labelText` custom texts from constructions.

## Stations

Stations are the subconstructions where people and cargo items can board and leave vehicles. They are identified by a `station` struct in the subconstruction:

```lua
subconstruction.station = {
  tag = 1,
  terminals = { ... },
  pool = { ... },
  catchmentAreas = { ... },
}
```

The `tag` is used to match this station subconstruction to the same one when the construction is updated.

### Terminals

The `terminals` define where the vehicles stop:

```lua
...
subconstruction.station.terminals = {
  {
    tag = 1,
    personEdges = { { 4, 2 }, { 4, 0 }, { 4, 1 }, },
    personNodes = { { 4, 2 }, { 4, 0 }, { 4, 1 }, },
    vehicleNode = { 6, 1 },
    passengers = true,
    cargo = false,
    comfortFactor = 1.0,
    cargoTransferSpeeds = {
      {
        cargoTypeSet = {
          cargoClassesIncluded = { "LIQUID" },
        },
        loadSpeedModifier = 2.0,
        length = 120
      }
    }
  },
  ...
}
...
```

Each terminal has several properties:

- `tag` is an identifier used to match this terminal to the same one when the construction is rebuilt.
- `personEdges` is a list of indices pairs where the first value is the index of the lane List in `laneLists` of the same subconstruction and the second value is the index of the lane in this lane list. If the first value is -1, then the n-th edge from the `edgeLists` of the construction is used. These edges are used as waiting zones for passengers items. There the passenger items will wait in idle mode until the vehicle arrives. The length and width of these lanes is used for the capacity calculation. These edges need to support the right mode (either `"PERSON"` or `"CARGO"`).
- `personNodes` is a list of indices pairs where the first value is the index of the lane List in `laneLists` of the same subconstruction and the second value is the index of the node in this lane list. If the first value is -1, then the n-th node from the `edgeLists` of the construction is used. These nodes are the nodes where passengers that alight of vehicles spawn in the station. From there they walk to the station exit or to a personEdge for the next vehicle to take. The invisible cargo items do the same. These nodes need to be on `"PERSON"` or `"CARGO"` edges.
- `vehicleNode`is a value pair where the first value is the index of the lane List in `laneLists` of the same subconstruction and the second value is the index of the node in this lane list. If the first value is -1, then the n-th node from the `edgeLists` of the construction is used. This node is where the vehicle stops. It depends on the vehicle type whether the front or middle of the vehicle exactly stops there. This node needs to be on an edge or lane that support vehicles.
- `vehicleEdges` is a list of indices pairs where the first value is the index of the lane List in `laneLists` of the same subconstruction and the second value is the index of the lane in this lane list. If the first value is -1, then the n-th edge from the `edgeLists` of the construction is used. These edges are an alternative to the `vehicleNode`. They allow simultaneous (un-)loading of several vehicles.
- `passengers` and `cargo` are boolean flags to mark this terminal suitable for passengers and or cargo.
- `comfortFactor` is a numeric factor used to describe how fast the waiting passengers get impatient.
- `cargoTransferSpeeds` is a list of structs that describe the specializations of the terminal. Each struct has:

  - a `cargoTypeSet` to define for which cargoTypes the entry is valid.
  - a `loadSpeedModifier` to define the loadSpeedFactor.
  - a `length` to define how long the section of the terminal with that specialization is. This is relevant for mixed trains.

### Pools

Aside from the platforms, stations may have a shared waiting area for passengers as an overflow `pool`:

```lua
...
subconstruction.station = {
  ...
  pool = {
    edges = { { 1, 1 } },
    capacity = 100,
  },
  ...
}
...
```

The `pool` consists of:

- a list of `edges` as pairs of `laneList` indices and lane indices in that `laneList`.
- a total `capacity` of that pool.

### Catchment Areas

Each station may have one or more circular `catchmentAreas` around it:

```lua
...
subconstruction.station = {
  ...
  catchmentAreas = {
    {
      position = { 0.0, 0.0, 0.0 },
      radius = 200
    }
  },
  ...
}
...
```

Each catchment area has a `position` relative to the origin of the construction and a `radius` in meter.

Other constructions within these circles are reachable from this station:

- when there is a complete path to it from the station for passengers.
- by teleportation for all other cargo types.

### Terminal Groups

For constructions, terminals from the models can be grouped together. This is not neccessary, but it might be helpful e.g. when several models are used to form a platform of a train station.

The `result.terminalGroups` list may contain zero or more structs:

```lua
result.terminalGroups = {
  {
    terminals = { {5, 0 } }, 
    vehicleNodeOverride = 42
  },
  ...
}
```

Each struct in the list contains two properties:

- `terminals` is a list of terminal references in models that should be grouped together. The list items are two value pairs with the id of the model in `result.models` as first number and the number of the terminal inside this model as second number.
- `vehicleNodeOverride` is the id of the node in the `result.edgeLists` that should replace the `vehicleNode` values of the terminals included in this terminal group.

Please note, that it is currently not possible to select the lane of streets that are defined by edges in the construction for the vehicle node. By default, the vehicleNode will be placed on the first lane that is most likely a sidewalk.

Once a `result.terminalGroups` struct is defined, non grouped terminals are ignored.

### Assignment of Terminals to Stations

To distinguish between the passenger and cargo part of a station, the `result.stations` list is used.
It contains a list of sub stations each with their own properties:

- `terminals` is a list of terminalGroup ids that are fetched in the order of the groups in `result.terminalGroups`.
- `tag` is an integer that is used to match a station to the station with the same tag before the update of the construction. If some orders change, this would lead to broken lines otherwise.

```lua
result.stations = {
  { 
    terminals = { 0,1 }, 
    tag = 0
  },
  { 
    terminals = { 2,3 }, 
    tag = 1
  },
  ...
}
```

The same is done for terminals of different carrier types.

## Depots & Maintenance Buildings

Depots are the places where the vehicles can be bought by the player. They and the standalone maintenance buildings have a positive maintenance effect on vehicles that are within a certain radius around these buildings.

### Depot

To define a depot, a subconstruction may have the `depot` struct:

```lua
depot = {
  transportModes = { "TRAIN", "ELECTRIC_TRAIN", },
  filterTags = { "default", },
  inNodes = { { 1, 0 }, },
  outNodes = { { 0, 0 }, },
},
```

The struct has three properties:

- `transportModes` is a list of [transport modes](https://wiki.transportfever3.com/script-doc/api/type.html#$api.type~TransportMode) for which vehicles can be bought in this depot.
- `filterTags` is a list of custom tags. Only vehicles with at least one matching tag will appear in the depot vehicle store. If the list is not set, all vehicles with at least one tag set will be available.
- `inNodes` is a list of nodes from the lane list that are used as entry points for vehicles that enter the depot. The first value of the pairs points to the n-th lane list in this subconstruction, the second to the lane in that list. If the first value is -1, it refers to the edge list of the whole construction.
- `outNodes` is a list of nodes from the lane list that are used as exit points for vehicles that leave the depot. The first value of the pairs points to the n-th lane list in this subconstruction, the second to the lane in that list. If the first value is -1, it refers to the edge list of the whole construction.

Both `inNodes` and `outNodes` need to have a valence of 1, so there might only be one lane attached to these nodes.

Depots support some [animation events](../../modding/general/resourcetypes/mdl.md#animations) for models in their subconstruction:

- `open` animation is used to open the main doors.
- `close` animation is used to close the main doors.

### Maintenance Buildings

To define a maintenance building, the `depot` struct in the subconstruction may have additional or other properties:

```lua
depot = {
  ...
  transportModes = { "TRAIN", "ELECTRIC_TRAIN", },
  catchmentArea = {
    radius = 800,
    position = { 0, 0, 0 },
  },
  maintenancePool = 6,
}
```

The maintenanceStation has three properties:

- `transportModes` is a list of [transport modes](https://wiki.transportfever3.com/script-doc/api/type.html#$api.type~TransportMode) for which vehicles should be maintained within the radius of this maintenance building.
- `catchmentArea` describes the `radius` of the maintenance effect in meters around the center that is located with `position` relative to the construction origin.
- `maintenancePool` sets the limit for how many vehicles can be maintained at the same time while in the radius of this maintenance building.

## Industries

Industries are used for cargo production, conversion and consumption. Subconstructions are identified as industries if they have an `industry` struct in the result of the `updateFn`:

```lua
subconstruction.industry = {
  maxLevel = 0,
}
```

The generation and selection of suitable locations is managed in the economy. To map the industries to a tag used in the economies, the `.con.lua` has an additional string property `placementTag`. All constructions with the `isIndustry` property set to `true` are considered when generating new industries to balance demand and offer.

### Cargo Production & Consumption

To define the cargo storage and production of an industry, the `updateFn` result may contain a subconstruction with a `stocks` and a `rules` struct:

```lua
subconstruction.stocks = {
  {
    type = "INPUT_STOCK",
    cargoType = "::/cargos/grain/grain.cargo",
    capacity = 400,
    loadIndicators = { 10, 11 },
    tag = 1,
  }
  ...
}
```

Each stock has the following properties:

- `type` is one out of `"INPUT_STOCK"`, `"OUTPUT_STOCK"` or '"STORAGE_STOCK"'. The later is used for warehouses described below.
- `cargoType` refers to the cargo type that may be stored in this stock.
- `capacity` is the number of cargo items that can be stored in this stock.
- `loadIndicators` is a list of indices refering to the models of the same subconstruction, which have a defined load indicator and should be used as visual representation of the stored cargo.
- `tag` is an integer used to match the stock and the contained items with the right ones after the construction gets updated.

Additional properties of stocks are tailored for the storage stocks in warehouses. See below for further explanations.

So far, the construction knows which cargo types it can receive/send and where it should store them. But it knows nothing about how many cargo items it can produce/consume per year and how the required items relate to the produced items. This is specified by the stock rules. Following code shows a rule that refers to the above example for the stock lists:

```lua
subconstruction.rules = {
  {
    input = { { 8, 3 } },
    output = { ["::/cargos/beverages/beverages.cargo"] = 8 },
    capacity = 45,
    priority = 1,
  },
},
```

The `input` property contains a number of items for every input stock of the subconstruction. These items are then processed and the items defined in `output` are produced and put in fitting stocks of the subconstruction.

The number of times that the rule can be processed per year is limited by `capacity`. If more than one rule is defined and the inputs for both rules are available, they alternate, except for when there are different `priority` values set for the rules. Then the higher ones win.

### Boosters

Industry production can be boosted by providing some special cargo items or by providing commuting possibilities for workers. In general it is recommended to provide both boosters for raw material industries like mines and farms while intermediate industries only have the worker booster.

Cargo boosters are set up by providing a rule with the property `booster` set to true. It can then run independent from the other rules and while it runs, the main production rule is processing faster.

```lua
subconstruction.rules = {
  ...
  {
    input = { { 1 } },
    output = { },
    capacity = 4 ,
    booster = true,
    boostFactor = 1.4,
  },
},
```

The `boostFactor` describes the speed increase of the normal production rules.

Worker boosters are set up by defining a `personCapacity` for workplaces:

```lua
subconstruction.personCapacity = {
  type = "INDUSTRIAL",
  capacity = 20,
}
```

See below for a detailed explanation about the `personCapacity` struct.

### Fields/Satellites

Industries may have some fields or satellites around them by using the modular construction concept with slots. To properly function in the context of industries, the `industry` struct on the subconstruction needs to have the following property set:

```lua
subconstruction.industry = {
  maxLevel = 5,
}
```

The `maxLevel` property describes the maximum number of fields/satellites the industry can have if fully upgraded. If it is set to 0, the industry does not use fields/satellites at all, this is the case for most of the intermediate industries.

When the industry is initially built or updated, the industry `updateFn` receives an additional parameter `sizeFactor` that can be used to scale the rule throughput:

```lua
subconstruction.rules = {
  {
    ...
    consumptionFactor = params.sizeFactor
  }
}
```

## Assets

Assets are generic constructions that are mainly used for decorative purposes. They may contain functional elements like edges though.

Depending on the used `type` they have a slightly different placement behavior. If set to `"ASSET_DEFAULT"` they can be placed freely. If set to `"ASSET_TRACK"`, they snap along nearby tracks by default. It can be suppressed by pressing SHIFT while clicking.

Assets have some additional properties as well as parameters for the updateFn. They do not have additional properties for the result data struct.

### Asset Properties

The additional properties of assets are:

```lua
  ...
  buildMode = "MULTI",
  skipCollision = true,
  autoRemovable = false,
  keepBuildingsAndFields = true,
  categories = { "misc" },
  snapping = { 
    rail = true, 
    road = true, 
    water = false 
  },
  ...
```

The `buildMode` property specifies, whether one can build one (`"SINGLE"`) or more constructions (`"MULTI"`) until the construction menu is closed. It's also possible to build constructions with a brush (`"BRUSH"`).

To ignore collider information and enable the intersection of models, it is possible to skip collision by setting `skipCollision` to true.

When assets should be removed when they are in the way for other constructions (both player built and game built ones), the `autoRemovable` property can be set to true. The `keepBuildingsAndFields` property prevents this asset from removing buildings and fields.

To provide additional filter possibilities, it is possible to assign an asset construction to one or more categories. The string keys are added to the `categories` list.

To allow snapping along tracks, streets or the water surface, the appropriate flags can be set to true in the `snapping` property.

### UpdateFn Parameters

The available parameters for assets are:

- `paramX` and `paramY` are from the keyboard controls. See the [basics](../../modding/constructions/basics.md#models) to find out more about them.
- `seed` is a number that can be used for randomization purposes. It increases whenever a construction is set.
- `state` is a data struct containing several cached informations about assets and tracks.
- `year` is the current year.
- All custom parameters that were set in other asset constructions before and the custom parameters of the current asset construction.

## Town Buildings

Town Buildings are automatically placed by the town development, depending on the configured purposes and availability of the construction. To inform the game for which purposes the house is suitable, there is a `townBuildingParams` struct in the construction definition:

```lua
  ...
  townBuildingParams = {
    landUseType = "COMMERCIAL",
    parcelSize = { 1, 1 },
    level = 1,
  },
  ...
```

This struct has three properties:

- `landUseType` is the type of building. It may either be `"RESIDENTIAL"`, `"COMMERCIAL"` or `"INDUSTRIAL"`.
- `parcelSize` is the size of the building in 8 meter steps. `{ 1, 2 }` would be a building that has an 8 meter section along the street and is 16 meters long away from the street.
- `level` is the level of the building. The higher the value is, the wealthier and large the building is. The minimum level is 1, the maximum level is 4.

When a town building construction is placed by the town development simulation its `updateFn` receives some additional parameters:

- `capacity` is the capacity that should be set for the town building.
- `cargoTypes` is a list of [cargo typ keys](../../modding/misc/cargo.md) that should be accepted by this town building.
- `depth` is the size of the parcel away from the street front.
- `width` is the size of the parcel along the street front.
- `parcelFace` is the face of the parcel.

The town building subconstruction needs to return some properties. It is recommended to forward them from the construction definition along the script reference:

```lua
subconstruction.townBuilding = {
  level = closureParam.townBuildingParams.level,
  width = closureParam.townBuildingParams.parcelSize[1],
  depth = closureParam.townBuildingParams.parcelSize[2],
}
```

### Scaffolding

The scaffolding is shown while the building is constructed. To define its outline, there is a `scaffold` struct that can be added to the subconstruction of the `updateFn` result:

```lua
subconstruction.scaffold = {    
  buildingFace = { { { 7.68415, 4.89475, 0 }, { 7.67744, 15.68718, 0 }, { 0.80814, 15.69474, 0 }, ... } },
  height = -1
},
```

The `buildingFace` is the bottom polygon around the house. The scaffolding is placed along the edges of this polygon with a slight offset so that it does not collide with the walls. The x and y coordinates are relative to the construction origin, z coordinates are ignored and automatically calculated depending on the terrain. The `height` value is used to offset the top height of the scaffolding below the roof.

### Capacity & Demand

To define the capacity of living places, shopping possibilities and workplaces, a `personCapacity` struct may be added to the subconstruction:

```lua
...
subconstruction.personCapacity = {
  type = "RESIDENTIAL",
  capacity = 4,
  personNodes = personNodes
}
...
```

It has three properties:

- `type` is one of the three land uses `"RESIDENTIAL"`, `"COMMERCIAL"` or `"INDUSTRIAL"`
- `capacity` is the capacity of the building. The recommended capacity is also provided by `params.capacity`.
- `personNodes` is a list of nodes where people may enter the building. They will disappear there as they arrive at the building.

Town Buildings may also have some cargo demand. The correct cargo type is provided by the town development as `params.cargoTypes` and can be used to set up the correct stock and a consumption rule that converts the cargo to nothing:

```lua
local ruleCapacity = 4
 
for i=1, #params.cargoTypes do
  local t = {}
  for j=1, #params.cargoTypes do
    t[j] = 0
  end
  t[i] = 1
  inputs[#inputs + 1] = t
 
  subconstruction.stocks[i] = {
    cargoType = params.cargoTypes[i],
    type = "INPUT_STOCK",
    edges = { },
    capacity = ruleCapacity, -- match capacity of rule, since the capacity is currently nowhere shown in the UI
  }
end
 
subconstruction.rules = {
  {
    input = inputs,
    output = { },
    capacity = ruleCapacity,
    consumptionFactor = 1.2,
  },
}
```

To ensure that cargo is consumed even if only one of the types is delivered, the inputs are put as alternatives instead of a combined rule:

```lua
subconstruction.rules = {
  {
    input = { { 1, 0, 0}, {0, 1, 0}, {0, 0, 1} },
    ...
  },
}
```

In this case at least one but potentially all of the inputs are consumed when the rule is processed.

> **Tip:**
>
> The `townbuildingutil.lua` provides a `makeBuildingScript` function that receives some parameters and returns a full functioning `updateFn` script.

## Landmarks

Landmarks are unique points of interest that may be built by the player. It is possible to:

- limit them to a certain number of instances on the map and make them unlockable with the company progression as described below
- define a person capacity to offer workplaces or shopping destinations as known from the industries and town buildings above
- have several building stage levels before completing the industry as described below
- require delivery of cargo amounts to complete construction by adding stocks and cargo rules as known from the industries above
- apply an effect to the surrounding area as described below

### Unlock and limit instances

To make the landmark unlockable based on the company level, the construction definition may receive some `metadata`:

```lua
return {
  ...
  description = {
    name = _("LANDMARK_ARENA_OF_VERONA_NAME"),
    description = _("LANDMARK_ARENA_OF_VERONA_DESCRIPTION"),
    ...
  },
  availability = {
    yearFrom = 0,
  },
  metadata = {
    company = {
      perkCategory = "LANDMARK",
      rankAndPermits = {{2, 1}},
    },
  },
  menuCategory = {
    categories = {
      {
        category = "landmarks",
        order = 10000,
      },
    },
  },
  ...
}
end
```

The `company` struct contains the necessary properties:

- `perkCategory` is either `LANDMARK` for landmarks, `HQ` for headquarter upgrade modules, `PROSPECTION` or `MECHANICS`.
- `rankAndPermits` is an array of number pairs where the first value describes the rank at which as many instances as the second number defines are unlocked for building. In the example above, with the second company rank, the player is allowed to build exactly one arena.

### Building stage levels

To use different building levels for landmarks, the `updateFn` result needs to have the required `metadata`:

```lua
...
result.metadata = {
  constructionConfig = {
    numLevels = 4,
    level = 0,
    underConstructionMessage = _("Supply the construction site with resources."), 
    underConstructionDescription = _("This is the site where the Amphitheater is taking shape. Supply all necessary resources to complete..."),
    requirements = {
      {
        cargoType = "::/cargos/stone/stone.cargo",
        amount = 800,
      },
      ...
    },
    ...
  },
}
...
```

The `numLevels` is the number of levels that are defined for the construction, where the last one is the finalized construction. The `level` selects the level that shall be active at start. If set to 0, the game script for landmarks will update the construction automatically as soon as enough resources are delivered.

To define this resource `requirements`, pairs of cargo types and quantities can be specified. The entity window of a landmark construction will show the `underConstructionDescription` until the construction is completed and a notification with the `underConstructionMessage` text is shown.

### Effects

A landmark may have some effect on vehicles in the surrounding region, if specified in the `metadata` struct of the `updateFn` result:

```lua
...
result.metadata = {
  constructionConfig = {
    effects = {
      {
        carrier = "ROAD",
        type = "noise",
        value = 0.75,
      },
    },
  },
}
...
```

Each effect is specified with:

- `carrier` out of `"ROAD"`, `"RAIL"`, `"TRAM"`, `"AIR"` or `"WATER"`
- `type` out of `"topSpeed"`, `"noise"`, `"pollution"` or `"comfort"`
- `value` as a multiplier to scale the effect type above

## Warehouses

Warehouses are identified by the subconstruction property `warehouse`:

```lua
result.subconstructions[1].warehouse = { }
```

Warehouses require stocks with type `"STORAGE_STOCK"` to work as expected:

```lua
result.subconstructions[1].stocks = {
  {
    type = "STORAGE_STOCK",
    cargoTypes = {
      cargoClassesIncluded = {
        "UNIVERSAL"
      },
      cargoTypesExcluded = {
        "::/cargos/passengers/passengers.cargo"
      },
    },
    mixedTypes = true,
    capacity = 0,
    loadSpeedModifier = 1.0,
  }
  ...
}
```

Warehouse stocks may have more than one compatible cargo type, hence instead of a single reference with `cargoType`, it is also possible to have a whole set of cargo types by using `cargoTypes` similar to vehicles.

In general, the first item restricts the current stock to exactly types, except when the `mixedTypes` property is set to true. Then a stock is not restricted to one specific cargo type once the first item is stored, but it remains open for items of all supported types. Non mixed stocks extend the lifetime of cargo items while they are stored.

It is also possible to scale the load speed of vehicles that are loading and unloading cargo items from and to this stock by setting a value other than 1.0 for `loadSpeedModifier`.

## Edge Objects

Edge objects like signals and road stops are defined as constructions as well. They are identified by the `.con.lua` property `edgeObject` which is a list with multiple properties:

```lua
...
edgeObject = {
  snapToStreet = true,
  snapToTrack = false,
  minDistToCrossing = 10,
  catchmentCargo = true,
  catchmentPassengers = true,
  catchmentAreaRadius = 100,
},
...
```

The edge object is restricted to street and/or track with `snapToStreet` and `snapToTrack`. To ensure a safe distance to crossings, it is possible to define a minimum distance with `minDistToCrossing`. For stops, it is possible to enable catchment area previews with the three related properties.

The `updateFn` of the edge object construction receives some additional `params`:

- `params.baseEdgeType` is either `NORMAL`, `BRIDGE` or `TUNNEL`.
- `params.roadType` is either `STREET` or `TRACK`.

When the `edgeObject` property is set, the construction only accepts a limited subset of result properties in its `updateFn`. The `cost` and `maintenanceCost` properties work as for regular constructions. Models of the edge object are listed in `edgeModels`:

```lua
...
edgeModels = {
  {
    edgeOffset = -5,
    model = {
      id = resolve("signal_path_c.mdl"),
      transf = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1, },
    }
  }
}
...
```

The `edgeOffset` allows specifying an offset along the edge, following its curvature and slope. If unset, it is considered as 0.
The `model` contains an `id` and `transf` like normal constructions do.

Functional data is provided in the `signal` and `streetTerminal` properties:

- The `signal` struct contains a `type` property. There it is possible to select whether the model should be a `"PATH_SIGNAL"` (two-way) or `"ONE_WAY_PATH_SIGNAL"`. To trigger sound events of passing vehicles, the name of an event can be added as value of the optional `soundevent` property. The `upright` flag defines wheter the orientation shall be facing upwards along z-axis (`upright = true`) or if it is following the gradient of the track/road (`upright = false`).
- The `streetTerminal` allows defining the data for road side stops.

```lua
streetTerminal = {
  capacity = 50,
  catchmentArea = { 
    position = { 0, 0, 0, },
    radius = 160,
  },
  passengers = true,
  cargoLoad = true,
  cargoUnload = true,
 
  cargoTransferSpeeds = {
    { 
      cargoTypeSet = { 
        cargoClassesExcluded = { },
        cargoClassesIncluded = { "PASSENGERS", "UNIVERSAL", },
        cargoTypesExcluded = { },
        cargoTypesIncluded = { },
      },
      length = 1000,
      loadSpeedModifier = 1,
    },
  },
  wantSymmetric = captureParams.twoSided,
}
```

Its properties are

- `capacity` for the waiting capacity.
- `catchmentArea` for the position and radius of the catchment coverage.
- `passengers`, `cargoLoad` and `cargoUnload` for the accepted types.
- `cargoTransferSpeeds` for a list of `cargoTypeSet`s and assigned `loadSpeedModifier`s.
- `wantSymmetric` as a boolean flag to build the same stop on the other road side if applicable.

The `edgeObjectEmissionEmitter` allows configuring `noise` and `pollution` values for the edge object.
