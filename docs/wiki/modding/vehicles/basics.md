---
title: Vehicle Basics
page_id: modding:vehicles:basics
source: https://wiki.transportfever3.com/doku.php?id=modding:vehicles:basics
---

# Vehicle Basics

Vehicles are the models that are moving around the game world to transport passengers or cargo. There are two types of vehicles:

- Vehicles that can be bought and managed by the player ([buses](../../modding/vehicles/types.md#road_vehicles), [trucks](../../modding/vehicles/types.md#road_vehicles), [trams](../../modding/vehicles/types.md#road_vehicles), [trains](../../modding/vehicles/types.md#rail_vehicles), [ships](../../modding/vehicles/types.md#water_vehicles) and [planes](../../modding/vehicles/types.md#air_vehicles))
- Vehicles that are controlled by the AI to represent the private transportation ([cars](../../modding/vehicles/types.md#road_vehicles))

The technical specialities for the different means of transport are listed in the sections linked above. Common properties for all vehicle types are explained below as well as other relevant metadata elements for vehicles. To get an overview over the gameplay relevant aspects of the different vehicle types, have a look at the [game manual section](https://wiki.transportfever3.com/doku.php?id=gamemanual:simulation:vehicles) for vehicles.

To find out more about 3D models in general, have a look at the [file type section](../../modding/general/resourcetypes.md#d_files). The general properties of `.mdl` files are described in the [model definition section](../../modding/general/resourcetypes/mdl.md). Below are the specific things that are added to models to use them as vehicles.

## Emissions

Vehicles have both noise and pollution depending on their maintenance level and current power and speed. The emissions are configured in the `emissions` metadata struct:

```lua
emissions = { 
  noise = { 
    score = 30,
    idle = 0,	[0.0, 100.0]
    speed = 0,	[0.0, 2.0]
    power = 0,	[0.0, 0.0002]
  },
  pollution = { 
    score = 25,
    idle = 0,	[0.0, 100.0]
    speed = 0,	[0.0, 2.0]
    power = 0,	[0.0, 0.0002]
  },
},
```

If `score` is set, the game automatically fills in the other three values based on a unified formula per vehicle type. The value range for `score` is between 0 and 100 to describe the impact within the vehicle type. It is automatically mapped into actual ranges per vehicle type. By using `-1` for the score, it is automatically calculated by the game depending on other properties of the vehicle.

The `idle` property is used when the vehicle stands still. `power` defines the emission when the thrust of the engine is at maximum and `speed` is the emission when the vehicle is at full speed. For situations between, the values are interpolated.

> **Tip:**
>
> **Game Balancing vs. realism**   
> Noise and pollution are two of the properties that are used for game balancing. To make the game interesting for tycoon players, every vehicle should have its own pros and cons. Hence vehicles with superior power and speed attributes should have higher noise and pollution for compensation as well. If unsure which value should be chosen, use `-1` to rely on the automated calculation.

## Transport Vehicles

Vehicles that can be bought and controlled by the player all have a general metadata struct called `transportVehicle`:

```lua
transportVehicle = {
  -- Simulation
  carrier = "RAIL",
  transportModes = { "TRAIN", "ELECTRIC_TRAIN" },  
  engineTransportModes = { "ELECTRIC_TRAIN" },
 
  -- Capacities
  compartmentsList = {
    ...
  },  
 
  -- Misc 
  loadSpeed = 1,
  comfortFactor = 0.5,    
  maintenanceFactor = 1.0,
  priceFactor = 0.5,
  arrivalDelay = 2000,
  departureDelay = 2000,
 
  reversible = false,
 
  filterTags = { "default", },
  groupFileName = "",
},
```

![](../../_media/modding/vehicles/vehicle_doors.png)  
passenger wagon with 4 doors

There are three major properties for the assignment to the different transport modes:

- `carrier` distinguishes between the different means of transportation. Possible values are `"ROAD"` for buses and trucks, `"TRAM"` for trams and light rails, `"RAIL"` for locomotives. multiple units and wagons, `"WATER"` for ships and `"AIR"` for planes and helicopters.
- `transportModes` help to categorize further. Vehicles can roll on all infrastructures that support these transport modes. Available are `BUS`, `TRUCK`, `TRAM`, `ELECTRIC_TRAM`, `ELECTRIC_TRAM_TRACK`, `TRAM_TRACK`, `TRAIN`, `ELECTRIC_TRAIN`, `SMALL_SHIP`, `SHIP`, `SMALL_AIRCRAFT`, `AIRCRAFT`and `HELICOPTER`.
- `engineTransportModes` work the same, but allow the use of engines too. Hence electric locomotives have both `TRAIN` and `ELECTRIC_TRAIN` in their `tags`, but only the later in `engineTransportModes`.

The `compartmentsList` is used to define the load of the vehicle. See below for further information.

Further properties are:

- `loadSpeed` is a property that specifies how fast passengers and cargo items are loaded/unloaded. For passenger waggons, a rule of thumb is that each door lane where a passenger could step into the vehicle or out of it at the same time counts as one loading speed unit. The load speed can be automatically calculated by setting it to `-1`.
- `comfortFactor` describes how fast the passenger happiness decreases, while they travel with this vehicle. The value range is from `0.0` to `1.0`, average and default is `0.5`. If set to `-1`, the comfort level is automatically calculated depending on other properties of the vehicle.
- `maintenanceFactor` is currently unused. ![FIXME](/lib/images/smileys/fixme.gif). The value range is from `0.0` to `1.0`, average and default is `0.5`.
- `priceFactor` is currently unused. ![FIXME](/lib/images/smileys/fixme.gif) The value range is from `0.0` to `1.0`, average is `0.5`.
- `arrivalDelay` is a custom value in milliseconds that describes the time span between the vehicle arrival and the begin of loading/unloading. It should be as long as the longest door open animation of the model.
- `departureDelay` is a custom value in milliseconds that describes the time span between the end of loading/unloading and the vehicle departure. It should be as long as the longest door close animation of the model.
- `reversible` specifies if this vehicle is capable of being used in push/pull trains. See the [reversible trains details](../../modding/vehicles/advancedtopics.md#reversible_trains) for more information.
- `filterTags` is a list of custom tags. The vehicle will only appear in depots when it matches all of the tags defined by the depot. If the list of the vehicle is empty, the vehicle does not appear in any depot. It is still usable in [multiple units](../../modding/vehicles/types.md#multiple_units) though. If the list is not set, it is considered as having the tag `default` which is used in vanilla depots.
- `groupFileName` is used whenever vehicles are grouped as subvariants in the buy menus. See the [buy menu group details](../../modding/vehicles/advancedtopics.md#buy_menu_groups) for more information.

## Cars

Some residents are considered as car owners. If they decide to not use public transportation to travel to their destination, they might use a car. To set a road vehicle model to be used by the AI as a car, it requires an empty metadata struct:

```lua
car = { },
```

As a reference for better balancing here are the common top speeds for different eras of vanilla cars:

| 1900 - 1925 | 1925 - 1950 | 1950 - 1980 | 1980 - 2000 | from 2000 |
| --- | --- | --- | --- | --- |
| 20 km/h   5.56 m/s | 50 km/h   13.89 m/s | 80 km/h   22.22 m/s | 100 km/h   27.77 m/s | 120 km/h   33.33 m/s |

To extend variety in private transportation, cars can have a preset of colors that can be used to recolor the cars randomly. It is required to have a material with a [color blending map](../../modding/general/resourcetypes/mtl.md#color_blending_dirt_rust). The colors then can be defined in a metadata struct in the `.mdl` file of a car:

```lua
colorConfig = {
  configs = {
    { { 0.26554900407791, 0.31372499465942, 0.22268399596214, }, },
    { { 0.61393797397614, 0.61960798501968, 0.52241402864456, }, },
    ...
  },
},
```

The colors each are three values, one for red, green and blue channel with a range from 0 to 1.

## Compartment List

Most properties that are load related can be found in the `compartmentsList` struct that is part of the `transportVehicle` struct. It is a nested structure with various hierarchy levels.

```lua
compartmentsList = {
  {
    loadConfigs = {
      {
        cargoEntry = {
          capacity = 650,
          cargoTypeSet = {
          cargoClassesIncluded = { "PASSENGERS", },
          cargoClassesExcluded = {  },
          cargoTypesIncluded = {  },
          cargoTypesExcluded = {  },
        },
        loadIndicator = "",
        seats = { },
      },
      toHide = { "comp_a", "comp_b", },
      },
    },
    ... -- other load configurations
  },
  ... -- other compartments
},
```

![](../../_media/modding/vehicles/loading_configs.gif)

The `compartmentsList` struct is a list of compartments. A vehicle can have one or more of these compartments. Usually one compartment is enough, but for vehicles that can carry several cargos, this might be a relevant use of multiple compartments. For example a hypothetic double deck tram has an upper deck for passengers only and a lower deck for various cargos. Then the upper deck is represented with the first compartment and the lower deck is represented in an independent compartment.

Each compartment currently only contains one property, another struct called `loadConfigs`. This `loadConfigs` struct is a list with one or more load configurations. A compartment can be used with different cargo combinations, e.g. a ship could either be loaded with coal only or it could be split in two halves with coal in one and iron ore in the other one of them. As a rule of thumb, every different capacity distribution possibility needs a seperate load configuration. When a vehicle is empty and should be loaded, the first suitable configuration that results in the most transported cargo items is used with consideration of the cargo type filters set in the game.

A load configuration has two properties, one of them being the `cargoEntry` which is a set of properties itself:

- `capacity` is the amount of cargo items or passengers that fits in the compartment.
- `cargoTypeSet` defines which cargo types can be loaded. See [cargo types](../../modding/misc/cargo.md#cargo_type_sets) for information about the cargo types and the `cargoTypeSet`.
- `loadIndicator` is a reference to a [load indicator](../../modding/general/resourcetypes/mdl.md#loadindicator) defined in the model metadata with the same name to be used for the display of the loaded cargo.
- `seats` is a list of indices for seats which should be assigned to this cargo compartment, useful for vehicles with multiple cargo compartments that might be used by cargo or passengers, like early ships.

The other property of load configurations, `toHide` is a list of node names that are hidden when this load configuration is used. This may be used for mixed passenger and cargo vehicles as well.

## Seats

Seats are the positions, where passenger and crew models are located. The positions are defined in another metadata struct called `seatProvider`:

```lua
seatProvider = {
  drivingLicense = "TRAM",
  crewModels = { "characters/era_c_driver_rail.mdl", },
  seats = {
    {
      animation = "idle",
      crew = true,
      forward = true,
      group = "RootNode",
      transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1.5, 0.15, 0.85, 1, },
    },
    ...
  },
```

![](../../_media/modding/character/anim_driving.gif)
![](../../_media/modding/character/anim_driving_upright.gif)
![](../../_media/modding/character/anim_idle.gif)
![](../../_media/modding/character/anim_sitting.gif)
![](../../_media/modding/character/anim_walk.gif)

The `drivingLicense` property is used to locate the right default crew models. Available are `"BUS"`, `"TRUCK"`, `"TRAM"`, `"RAIL"`, `"WATER"`, `"AIR"` and `"AIR_OUTDOOR"` (with pilot helmet).
To use custom crew models, it is possible to list model references in `crewModels`.

The `seats` struct contains a list of zero or more seat substructs. Every struct has the following properties:

- `animation` specifies which posture and animation should be used for this seat. Available are `driving`, `driving_upright`, `idle`, `sitting` and `walk`.
- `crew` defines if this person is a crew member. Crew members are visible even if there is no passenger on board. Non-crew member seats are used for passengers. This parameter is optional, if omitted default `false` is used.
- `forward` is used to show crew members only in the right direction when [reversible trains](../../modding/vehicles/advancedtopics.md#reversible_trains) are used. See there for more details. This parameter is optional.
- `group` is a node name. This node is used as an anchor for the seat, e.g. if it rotates or scales, the seat rotates or scales as well. If the anchor node is used as a part that is only visible under certain conditions, the seat is only visible then too. This can be used to hide crew members in secondary locomotives.
- `transf` is used to scale, rotate and position the seat relative to the anchor mesh. It requires a 16 number transformation matrix. The `transf.lua` and `vec3.lua` scripts can be used if these operations should be parameterized with seperate values for scaling, rotation and positioning.

## Sound Configuration

The `soundConfig` struct contains the sound related properties:

```lua
...
soundConfig = { 
  soundSet = { 
    name = "/vehicle/tram/shared/sound/tram_modern.snd",
  },
  effects = {
    "horn" = "audio/horn.wav",
  }
},
```

It has two parts:

- `soundSet.name` is a reference to a [soundset](../../modding/misc/soundsets.md#sound_sets) file. The path is relative to the `.mdl` file.
- `effects` is a mapping of event names to file names. If an event is set, it overrides the same event reference in the soundset above. The path is relative to the `.mdl` as well.
