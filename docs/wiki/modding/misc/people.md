---
title: People
page_id: modding:misc:people
source: https://wiki.transportfever3.com/doku.php?id=modding:misc:people
---

# People

To make the game world more lively passengers, pedestrians and drivers are simulated as animated characters. The standard character models are located in `content/characters/` and identified by a special metadata struct.

## Metadata

The model files consist of the following parts:

```lua
function data()
return {
  -- bounding box
  -- collider
  -- levels of detail
  metadata = {
    availability = {
      yearFrom = 1850,
      yearTo = 1920,
    },
    colorConfig = {
      configs = {
	{
	  { 0.72, 0.70, 0.65, },
	  { 0.40, 0.36, 0.34, },
	  { 0.62, 0.60, 0.58, },
	  { 0.81, 0.67, 0.63, },
	},
        ...
      },
    },
    person = {
      drivingLicenses = { "WATER", },
      gender = "FEMALE",
    },
  },
  version = 2,
}
end
```

The `availability` struct restricts the character to be available in a certain era only. `yearFrom` and/or `yearTo` can be left out or set to zero to define an indefinite start respectively end year.

Character models can be recolored to get more diversity in the game world. The `colorConfig` struct contains a list named `configs` that consists of a list of configuration structs. As the character models use a material with a four channel [color blend map](../../modding/general/resourcetypes/mtl.md#color_blending_dirt_rust), each of the structs has a set of 4 different colors with three values for the three color channels red, green and blue in a range of 0 to 1.

The `person` struct is the unique identifyer for character models. It contains two properties:

- `drivingLicenses` is a list of keys. If left blank, the character is used as pedestrian or passenger. If at least one of the keys `"BUS"`, `"TRUCK"`, `"TRAM"`, `"RAIL"`, `"WATER"`, `"AIR"` and `"AIR_OUTDOOR"` is used, the character is used as a crew model for the matching types of vehicles.
- `gender` is a key that is either `"FEMALE"` or `"MALE"`. It is used to select matching character models to female or male resident names.

## Events

![](../../_media/modding/character/anim_driving.gif)
![](../../_media/modding/character/anim_driving_upright.gif)
![](../../_media/modding/character/anim_idle.gif)
![](../../_media/modding/character/anim_sitting.gif)
![](../../_media/modding/character/anim_walk.gif)

The character models support various animation events to reflect the current state of the people:

- `driving` is a looped animation where the character sits in a low driving seat like in a car.
- `driving_upright` is a looped animation where the character sits on a higher driving seat like in most other vehicles.
- `idle` is a looped animation where the character stands around literally doing nothing. This is used when pedestrians are waiting at traffic lights or passengers at stations as well as standing passengers in vehicles.
- `sitting` is a looped animation where the character sits around. This is usually used for passengers in vehicles.
- `walk` is a looped animation for walking pedestrians and passengers.
