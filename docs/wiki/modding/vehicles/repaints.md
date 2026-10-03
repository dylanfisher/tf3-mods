---
title: Repaint Mods
page_id: modding:vehicles:repaints
source: https://wiki.transportfever3.com/doku.php?id=modding:vehicles:repaints
---

# Repaint Mods

A very common use case for mods is the addition of liveries to existing vehicles. The community usually calls them **Repaints**. There are several kinds of repaints regarding the level of complexity:

- Different textures for existing models
- Different textures and additional meshes for existing models
- Different textures and modified meshes for identical models

While the first two cases do not require original files to be present in the repaint mod, the third one requires adapted contents of the original mod. **Thus it is required to get permission by the original author before such a mod is shared with others.**

> **Tip:**
>
> In the community, the general standard is to inform the original author in advance and obtain their consent when creating a repaint mod. Many authors then also offer working files that facilitate the creation of texture or model variants.

In general, it is recommended to only deliver files that are changed or new to reduce duplicates. Most importantly, the `modId` of the repaint mod needs to be different and the [dependency](../../modding/general/moddefinition.md#dependencies_and_incompatibilities) needs to be specified correctly. The description below only covers the first type of repaint where only textures are changed.

## Neccessary Files

To get a working repaint mod, there are several required files:

- basic mod files as described in the [mod definition section](../../modding/general/moddefinition.md)
- a `.mtl` file for every material that should use other textures
- a `.mdl` file for every new model variant
- the ui icons for every new model variant
- the new textures

To get a better overview over the folder and file structure of a repaint mod, you can download an [example repaint](../../_media/modding/templates/wiki_example_repaint.zip). It contains a texture variant of the eCitaro bus in the base game. As no other mod is required, there is no dependency specified. Please pay attention to set up the correct dependency when repainting contents from other mods.

### Basic Mod Files

The `mod.json` does not differ much from the `mod.json` of other mods, most important is the specification of the correct [dependency](../../modding/general/moddefinition.md#dependencies_and_incompatibilities).

The `modinfo.json` contains the display data for the repaint mod in the mod browser. It is a nice gesture to name the original author as a co-author. The mod name should be chosen so that it is clear what the content is. It is useful to point out in the mod description if other mods are mandatory. The preview image should represent the mod content to give the user a hint of what he should expect from the mod.

### Material Files

The `.mtl` files contain all the texture file references. Thus it is required to add a new material file for every material that shall use a different texture than the original model. Usually up to 4 different texure map entries have to be changed:

- `map_albedo_opacity` is the texture with the actual color and transparency information.
- `map_normal` is the texture for normalmapping, this could be relevant e.g. for old number plates.
- `map_metal_gloss_ao` is the texture with physical effects information.
- `map_cblend_dirt_rust` ist the texture with the information which areas can be recolored ingame.

Learn more about material definitions in the [material description](../../modding/general/resourcetypes/mtl.md).

When copying a material file from the base game or another mod, it is mandatory to adjust the contained file reference to point to the original context. If the folder structure is not the same as in the original place, it is also required to swap relative paths to absolute paths. See more about file names and references in the [resource types section](../../modding/general/resourcetypes.md#file_names_references).

### Model Files

The `.mdl` file contains all the neccessary metadata as well as the actual 3D model tree. Learn more about model definitions in the [model description](../../modding/general/resourcetypes/mdl.md).

Usually there are several things to change:

- the material references to the new `.mtl` files. Remember to change them in every level of detail.
- the availability information.
- the vehicle name and description

The relevant lines where these things can be changed are:

```lua
function data()
return {
  ...
  lods = {
    {
      node = {
        children = {
          {
            materials = { 
              "<original_modid>::mat/<vehiclename_liveryname>.mtl", 
              "<original_modid>::mat/<vehiclename_liveryname>_glass.mtl", 
            },
            mesh = "<original_modid>::msh/body_lod0.msh",
            ...
          },
          ...
        },
        ...
      },
      ...
    },
    ...
  },
  metadata = {
    availability = {
      yearFrom = 2000,
      yearTo = 0,
    },
    description = {
      description = _("VEHICLE_<vehiclename_liveryname>_DESCRIPTION"),
      name = _("VEHICLE_<vehiclename_liveryname>_NAME"),
    },
    ...
  },
  ...
}
end
```

### UI Icons

There are three UI icons needed for vehicle models:

- `<vehiclename>_store` for details in the vehicle store
- `<vehiclename>_small_icon` for the compact list in the vehicle store
- `<vehiclename>_icon20` for other windows and lists ingame

All three can be generated with the [Model Editor](../../modding/tools/modeleditor.md) by loading the model and pressing the SCREENSHOT button in the top right corner. They are automatically moved to the correct folder.

### Textures

The technical requirements for [texture files](../../modding/general/resourcetypes.md#texture_files) apply here too.
As most texture files are using DDS format with a compression that is not lossless, it is not recommended to base texture work on DDS textures, as these contain some artifacts. Instead existing texture workfiles should be used whenever possible. You may ask the original author if he can provide you some.
