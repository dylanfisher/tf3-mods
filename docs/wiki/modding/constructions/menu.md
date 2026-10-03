---
title: Construction Menu
page_id: modding:constructions:menu
source: https://wiki.transportfever3.com/doku.php?id=modding:constructions:menu
---

# Construction Menu

The construction menu consists of different menus accessible in the main game bar at the bottom of the screen. Each of the menus provides different menu categories, shown as tabs. All content may reference one or more of these menu categories to appear there.

```lua
...
menuCategory = {
  categories = {
    {
      category = "rail_buildings",
      filterCategories = {"building"},
      order = 5000,
    },
  },
},
... 
```

To reference the correct tabs in the construction menu, the `menuCategory.categories` list can contain one or more entries, each with:

- the reference to a `category` by the defined tag of the category itself.
- an optional list of `filterCategories` with their individual tags.
- an optional `order` entry used to enforce the order in the construction menu.

## Menu Categories

The following categories are available to be referenced:

| Menu | Name | Tag | Mod only | Content | Icon |
| --- | --- | --- | --- | --- | --- |
| Road | Buildings | `road_buildings` | no | Road Stations, Depots |  |
| Road | Tools | `road_tools` | no | Tram and Bus lanes |  |
| Rail | Assets | `road_assets` | yes | Decoration for roads |  |
| Rail | Buildings | `rail_buildings` | no | Rail Stations, Depots |  |
| Rail | Tracks | `tracks` | no | Track Types |  |
| Rail | Tools | `rail_tools` | no | Electrification |  |
| Rail | Assets | `rail_assets` | yes | Decoration for railway |  |
| Rail | Rail Constructions | `rail_constructions` | yes | Switches, Underpasses |  |
| Rail | Signals | `rail_signals` | yes | Signals |  |
| Water | Buildings | `water_buildings` | no | Harbors, Shipyards |  |
| Water | Tools | `water_tools` | no | Tools for water transportation |  |
| Water | Assets | `water_assets` | yes | Decoration for harbors |  |
| Air | Buildings | `air_buildings` | no | Airports, Heliports, Hangars |  |
| Air | Tools | `air_tools` | no | Tools for air transportation |  |
| Air | Assets | `air_assets` | yes | Decoration for airports |  |
| Roads | Small Streets | `roads_small` | no | 1-3 lane streets |  |
| Roads | Medium Streets | `roads_medium` | no | 4-5 lane streets |  |
| Roads | Large Streets | `roads_large` | no | 6+ lane streets |  |
| Roads | Country Roads | `roads_country` | no | Country roads without visible sidewalk |  |
| Roads | Highways | `roads_highway` | no | Highway roads with hard shoulders |  |
| Roads | Road Constructions | `street_constructions` | no | Roundabouts |  |
| Warehouse | Warehouses | `warehouses` | no | Warehouses |  |
| Perks | Landmarks | `landmarks` | no | Unique constructions like eiffel tower |  |
| Perks | Prospections | `prospections` | no | Industry Prospection |  |
| Perks | Mechanics | `perks_mechanics` | no | Marketing campaign, Greenify |  |
| Industry | Industries | `industries` | no | Industry construction (only in sandbox mode) |  |
| Industry | Assets | `industries_assets` | yes | Industry assets (only in sandbox mode) |  |
| Landscaping | Landscaping | `landscaping_terrain` | no | Terraforming Tools |  |
| Landscaping | Ground | `landscaping_ground` | no | Terrain Materials |  |
| Landscaping | Vegetation | `landscaping_vegetation` | no | Trees/Plants |  |
| Landscaping | Animals | `landscaping_animals` | yes | Animal Assets |  |
| Landscaping | People | `landscaping_people` | yes | People Assets |  |
| Landscaping | Vehicles | `landscaping_vehicles` | yes | Vehicle Assets |  |
| Landscaping | Assets | `landscaping_assets` | yes | All other Assets |  |
| Landscaping | Residential Buildings | `town_buildings_res` | yes | Residential Buildings |  |
| Landscaping | Commercial Buildings | `town_buildings_com` | yes | Commercial Buildings |  |
| Landscaping | Industrial Buildings | `town_buildings_ind` | yes | Industrial Buildings |  |
| Landscaping | Other Buildings | `town_buildings_other` | yes | Other Buildings |  |

> **Note:**
>
> While it is technically possible to define custom categories, we highly recommend to stick to the predefined ones to keep the menu clean. If there is need to define a custom category, please get in touch with us first.

## Filter Categories

The following filter categories are available to be used in any menu:

| Topic | Name | Tag | Exemplaric Content | Icon |
| --- | --- | --- | --- | --- |
| Ground | Asphalt | `asphalt` | Asphalt terrain materials |  |
| Ground | Ground | `ground` | Dirt terrain materials |  |
| Ground | Gravel | `gravel` | Gravel terrain materials |  |
| Ground | Grass | `grass` | Grass terrain materials |  |
| Ground | Plant | `plant` | Plant terrain materials |  |
| Ground | Rock | `rock` | Rock terrain materials |  |
| Ground | Sand | `sand` | Sand terrain materials |  |
| Ground | Misc | `misc` | Misc terrain materials |  |
| Vegetation | Tree | `tree` | Trees |  |
| Vegetation | Bush | `bush` | Bushes |  |
| Vegetation | Plant | `plant` | Farm Plants |  |
| Vegetation | Flower | `flower` | Flowers |  |
| Animals | Air Animals | `bird` | Bird assets |  |
| Animals | Land Animals | `land` | Land animal assets |  |
| Animals | Water Animals | `fish` | Water animal assets |  |
| People | Residents | `residential` | Normal people assets |  |
| People | Workers | `worker` | Worker assets |  |
| Vehicles | Bike | `bike` | Bikes and motorcycles |  |
| Vehicles | Car | `car` | Cars |  |
| Vehicles | Bus | `bus` | Buses |  |
| Vehicles | Truck | `truck` | Trucks |  |
| Vehicles | Tram | `tram` | Trams |  |
| Vehicles | Train | `train` | Trains and locomotives |  |
| Vehicles | Passenger Wagon | `passenger_wagon` | Passenger wagons |  |
| Vehicles | Cargo Wagon | `cargo_wagon` | Cargo wagons |  |
| Vehicles | Plane | `plane` | Planes |  |
| Vehicles | Helicopter | `helicopter` | Helicopters |  |
| Vehicles | Ship | `ship` | Boats and ships |  |
| Buildings | Culture | `culture` | Theaters, cinemas, museums |  |
| Buildings | Sport | `sport` | Stadiums, tennis courts |  |
| Buildings | Public | `public` | Libraries, schools, administration |  |
| Buildings | Emergency | `emergency` | Hospital, police, rescue |  |
| Buildings | Tower | `tower` | Towers |  |
| Buildings | Level 1 | `lvl_1` | Level 1 town buildings |  |
| Buildings | Level 2 | `lvl_2` | Level 2 town buildings |  |
| Buildings | Level 3 | `lvl_3` | Level 3 town buildings |  |
| Buildings | Level 4 | `lvl_4` | Level 4 town buildings |  |
| Industries | Farm | `farm` | Farms |  |
| Industries | Mine | `mine` | Mines |  |
| Industries | Factory | `factory` | Factories |  |
| Industries | Water | `water` | Water industries |  |
| Infrastructure | Stop | `stop` | Stops |  |
| Infrastructure | Station | `station` | Stations |  |
| Infrastructure | Depot | `depot` | Depots |  |
| Infrastructure | Tracks | `tracks` | Tracks |  |
| Infrastructure | Bridge | `bridge` | Bridge constructions |  |
| Infrastructure | Tunnel | `tunnel` | Tunnel constructions |  |
| Infrastructure | Intersection | `intersection` | Intersections |  |
| Tracks | 600 mm | `600mm` | Narrow gauge track types with 600mm and less width |  |
| Tracks | 750 mm | `750mm` | Narrow gauge track types with about 750mm width |  |
| Tracks | 1000 mm | `1000mm` | Meter gauge track types |  |
| Tracks | 1435 mm | `1435mm` | Standard gauge track types |  |
| Tracks | 1500 mm | `1500mm` | Broad gauge track types |  |
| Tracks | 3rd Rail | `3rd_rail` | Track types with 3rd rail for electric power |  |
| Tracks | Catenary | `catenary` | Track types with overhead power |  |
| Tracks | Cogwheel | `cogwheel` | Track types for cogwheel vehicles |  |
| Tracks | High Speed | `high_speed` | Track types for high speed |  |
| Tracks | Wood | `wood` | Track types with wooden sleepers |  |
| Tracks | Concrete | `concrete` | Track types with concrete sleepers |  |
| Bridges | Viaduct | `bridge_viaduct` | Viaducts |  |
| Bridges | Arch | `bridge_arch` | Arch bridges |  |
| Bridges | Beam | `bridge_beam` | Beam bridges |  |
| Bridges | Truss | `bridge_truss` | Truss bridges |  |
| Bridges | Suspension | `bridge_suspension` | Suspension bridges |  |
| Tunnels | Round | `tunnel_round` | Round tunnels |  |
| Tunnels | Rectangular | `tunnel_rectangular` | Rectangular tunnels |  |
| Misc | Cargo | `cargo` | Cargo |  |
| Misc | Passenger | `passenger` | Passengers |  |
| Misc | Building | `building` | Generic buildings |  |
| Misc | Barrier | `barrier` | Barriers |  |
| Misc | Construction | `construction` | Cranes, containers, excavators |  |
| Misc | Lamp | `lamp` | Lamps |  |
| Misc | Sign | `sign` | Sign |  |
| Misc | Spline | `spline` | Fences |  |
| Misc | Tools | `tools` | Tools |  |

> **Note:**
>
> While it is technically possible to define custom filter categories, we highly recommend to stick to the predefined ones to keep the menu clean. If there is need to define a custom filter category, please get in touch with us first.
