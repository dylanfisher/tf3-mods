---
title: Shaders
page_id: modding:misc:shaders
source: https://wiki.transportfever3.com/doku.php?id=modding:misc:shaders
---

> **Wip:**
>
> This page is not yet adapted for Transport Fever 3. The content may be outdated.

# Shaders

[Shaders](https://en.wikipedia.org/wiki/Shader) are small data processing programm snippets that are used by the GPU to calculate what is drawn on the screen. This covers the 3D meshes as well as textures. Beside the lighting and shadowing, atmospheric effects like the [reyleigh scattering](../../modding/environment/environments.md#atmosphere), light emission and other effects are realized with shaders too.

There are several graphics libraries on the market, that can be used as standardized APIs for graphic visualization. The most common are DirectX® and OpenGL®. Transport Fever 3 uses the the Vulkan® Graphics API and the shaders are programmed in the [OpenGL® Shading Language Version 1.50](https://www.khronos.org/registry/OpenGL/specs/gl/GLSLangSpec.1.50.pdf).

Each shader actually is a pipeline of several shader stages. Usually, these are:

1. **Vertex shaders** that run once for each vertex of each triangle (where you can do some computation and vertex transformation).
2. **Geometry shaders** that compute additional geometry (where the smoke, tree billboards and grass geometry is added).
3. **Fragment shaders** that run for each pixel (where you can control stuff like pixel color, lighting etc.).

For Transport Fever 3, the shader related files are located in `content/rendering/programs/shaders/`. The vertex shaders `.vs`, geometry shaders `.gs` and fragment shaders `.fs` are compiled by the game on load to be used ingame. To recompile them after some changes, use AltGr + R ingame.

## Shaders in Transport Fever 3

There are five groups of shaders:

- Material shaders for the different material types.
- Terrain shaders for the terrain textures and grass plants.
- UI shaders for data layers.
- HDR shaders for lighting effects.
- Misc shaders for [ambient occlusion](https://en.wikipedia.org/wiki/Screen_space_ambient_occlusion) and smoke effects.

### Material Shaders

Each material type is defined in a `mat.lua` file:

```lua
function data()
return {
  legacyName = "PHYS_TRANSPARENT_NRML_MAP",
  prefix = "TN",
  properties = { 
    { name = "two_sided", id = "properties/two_sided.prop", },
    { name = "map_albedo_opacity", id = "properties/map_albedo_opacity.prop", },
    ...
  },
  renderPasses = {
    COLOR = {
      needsAlphaBlending = true,
      needsBlend4 = false,
      programName = "programs/color_alpha_diffuse.prog"
    },
    ...
  },
  technique = "techniques/standard_transparent.tec",
  transparent = true,
  needsTangentVertexAttrib = false,
  hasSmoothLod = false,
 
  order = 60,
}
end
```

The properties are:

- `legacyName` is used e.g. in the Model Editor.
- `prefix` is a short abbreviation that can be used for quick assignments in `.fbx` files.
- `properties` contains all property and map definitions for the material. See below for more details.
- `renderPasses` contains a list of render passes that are executed. See below for more details.
- `technique` is a reference to a `.tec` file. See below.
- `transparent` is a boolean attribute flagging this material as a transparent one. This is important for the render order.
- `needsTangentVertexAttrib` is a boolean attribute ![FIXME](/lib/images/smileys/fixme.gif).
- `hasSmoothLod` ![FIXME](/lib/images/smileys/fixme.gif).
