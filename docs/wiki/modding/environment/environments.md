---
title: Environments
page_id: modding:environment:environments
source: https://wiki.transportfever3.com/doku.php?id=modding:environment:environments
---

# Environments

Environments define the sun light, atmosphere, water coloring and skybox. The configuration is done in `.env.lua` files and basically look like this:

```lua
function data()
  return {
    atmosphere = {...},
    light = {...},
    shadows = {...},
    water = {...},
 
    skyBox = {...},
    useSkyBoxOverwrite = false,
  }
end
```

## Atmosphere

![](../../_media/modding/environment/rayleigh.png)

The `atmosphere` struct contains several properties which are used to simulate the atmospheric light model in the game.

The following properties are adjusted in the simulation

- `cloudCoverage` is the range between blue sky, clouds and rain. Values are between `0.0` and `0.5`, the rain starts at around `0.45`.
- `dayOfYear` is the day in the year counting from `1` to `365`.
- `timeOfDaySec` is the time of the current day in seconds.

The following properties affect the sun and the moon:

- `sunBloom` is the bloom intensity of the sun. Values are between `0` and `1000` and smaller values result in larger bloom haze.
- `sunBloomScale` is a scale for the bloom of the sun. Values are between `0` and `10`.
- `sunIlluminance` is the illuminance strength of the sun, affecting the indirect light on the planet. Values are between `0` and `100`.
- `sunIntensity` is the intensity of the sun, affecting the direct light on the planet. Values are between `0` and `100000`.
- `sunSizeAngle`is the dimension of the sun (in degrees) as seen from the planet. Values are between `0` and `5`.
- `moonIlluminance` is the illuminance strength of the moon at night, affecting the indirect light on the planet. Values are between `0` and `100`.
- `moonIntensity` is the intensity of the night emitted from the moon at night. Values are between `0` and `1000`.

The clouds are configured with the following properties:

- `cloudBase` is the lowest level where clouds are present in meter.
- `cloudTop` is the highest level where clouds are present in meter.
- `cloudSpeed` is the drift speed of the clouds.
- `cloudPhase` ![FIXME](/lib/images/smileys/fixme.gif)
- `cloudScattering` ![FIXME](/lib/images/smileys/fixme.gif)

The mie model describes the amount of scattered light for aerosols (i.e. particles bigger than the visible wavelength) like fog, droplets, haze, etc. The scattered light is independent of wavelength and affects mostly the horizon. Dry climates tend to have low amounts of such particles.

- `miePhaseG` is the g-factor of the mie phase function (Cornette-Shanks). It affects the halo around the sun and horizon.
- `mieScatteringScale` is the strength of mie scattering. Values are between `0` and `1` and higher values result in stronger scattering.
- `mieAbsorptionScale` is the strength of the mie absorption. Values can be between `0` and `1` and high values lead to strong absorption.
- `mieScaleHeight` is the scale for the height influence in the mie model. It affects the mie density and how strong the scattering and absorption are. The factors are based on the height in atmosphere. Values are between `0` and `100`.

In the real world, the atmosphere usually has a blue sky at daylight and some red colors in the morning and evening at dawn and sunset. This is caused by the [rayleigh scattering](https://en.wikipedia.org/wiki/Rayleigh_scattering) phenomena. It describes the amount of scattered light due to air molecules (i.e. particles smaller than the wavelength of light). Its effect is highly dependent on wavelength and affects the entire atmosphere: longer wavelengths (blue-like) are more scattered (this makes the sky blue), while shorter wavelengths (red-like) are more likely to be transmitted (this makes the sunset red).

- `rayScatteringCoeff` is the color of the light spectrum, that is mostly affected by rayleigh scattering.
- `rayScatteringScale` is the strength of rayleigh scattering. Values are between `0` and `1` and higher values result in stronger scattering.
- `rayScaleHeight` is the scale for the height influence in the rayleigh model. It affects the ray density and how strong the scattering and absorption are. The factors are based on the height in atmosphere. Values are between `0` and `100`.

The ozone model describes the amount of light absorption due to ozone layer. It does not scatter the light.

- `absorptionCoeff` is the absorption color defining the light absorption due to ozone.
- `absorptionScale` is the strength of the absorption due to ozone. Values can be between `0` and `1` and high values lead to strong absorption.

Additional advanced atmosphere parameters are:

- `bottomRadius` is the radius of the planet in km.
- `atmosphereHeight` is the thickness of the atmosphere in km.
- `heightOffset` is the height/offset of the terrain above the ground in km.
- `fogScaleLow` is the scale of fog effect (aerial perspective) when the camera is low above ground. Values can be between `0.1` and `25.0`.
- `fogScaleHigh` is the scale of fog effect (aerial perspective) when the camera is high above ground. Values can be between `0.1` and `25.0`.

> **Tip:**
>
> It is recommended to use the [ingame debug tools](../../modding/tools/ingame.md#debug_tool_window) to experiment with the values.

## Light

The `light` struct consists of several properties:

- `latitude` is the latitude of the environment in radians. It controls the path of the sun.
- `refBrightness` is a value that adjusts the overall brightness. 10 is the maximum value that results in a darker mood. Values near 0 are very bright while 0 is absolute darkness.
- `ambientDayColor` is an ambient color that tints the whole world slightly during day time.
- `ambientNightColor` is an ambient color that tints the whole world slightly during night time.
- `hdrExposureDay` is a number used to scale the hdr exposure during day time.
- `hdrExposureNight` is a number used to scale the hdr exposure during night time.
- `hdrContrastDay` is a number used to scale the hdr contrast during day time.
- `hdrContrastNight` is a number used to scale the hdr contrast during night time.

## Sky

While most of the sky box is dynamic, there are a few textures used for the elements on the sky:

- `starsTex` is a texture reference for the texture that shall be used as sky in the night.
- `starsTexMask` is a texture reference for a mask texture that provides brightness info about the `starsTex`. White pixels are consider as very bright star lights.
- `moonTex` is a texture reference for the texture that shall be used as the moon.
- `environmentTex` is a default skybox used for simple reflections. It is a cube map .dds texture.

## Water

![](../../_media/modding/environment/water.png)  
less and more intense waves

The water effects are adjusted with the properties in the `water` struct:

- `normalTex` is a texture reference to a normal map that is used for the wave effects on the water.
- `normalScale` is a factor to adjust the intensity of the wave effect. 0 results in still water.
- `preferLowFreq` is a boolean value. If set to true, the water movement effect is more subtle to simulate still water.
- `roughness` is another factor to control the roughness of water surface. The higher this factor is, the less reflexion effects will occur on the water surface.
- `depthColorTex` is a texture reference to a file that contains a set of colors that is used for the deepness effect of water.
- `particleDensity` ![FIXME](/lib/images/smileys/fixme.gif)
- `extinctionCoeff` is the factor that controls the clearness of the water. 0 is total transparency, 1 is opaque water. The lower the value is, the deeper can be seen through the water.
- `waveFoamTex` is a texture reference to a texture that shows some waves. If set, there is a shoreline effect with animated foam waves visible.

> **Tip:**
>
> Most of the properties for water effects can be controlled with the [ingame debug tools](../../modding/tools/ingame.md#debug_tool_window) too.
