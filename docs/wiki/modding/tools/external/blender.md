---
title: Blender
page_id: modding:tools:external:blender
source: https://wiki.transportfever3.com/doku.php?id=modding:tools:external:blender
---

# Blender

<https://www.blender.org/>

A free and open-source software popular for its vast adoption among the industry and hobbyists; with an active community, lots of plugins and addons, and a competitive allrounder toolkit for modeling, animation and so on.

> **Note:**
>
> We use Blender's accessible addon infrastructure to provide our own tools to the modding community. The scripts are provided "as is"; we cannot guarantee to support all versions of Blender forever into the future, but we will do our best to support the community in any way possible.

## Importing .mtl files from Transport Fever 3

### Installation

> **Download:**
>
> Find the **TF3 Tools: .mtl Importer** python script [here](../../../_media/modding/tools/external/ug_import_tf_material.zip).
>
> It is currently tested with Blender Versions: `3.6 LTS`, `4.5 LTS` & `5.0.0`.

![](../../../_media/modding/tools/external/blender_mtl_import_interface2.png)
To install it, you can drag the `.zip` folder into the viewport, or alternatively:

1. Navigate to Edit → Preferences → Add-ons
2. Use the dropdown arrow in the top right corner and choose Install from Disk…
3. Pick the downloaded `.py` script file, it should install without errors.
4. The add-on needs two variables set in the add-on preferences to work correctly:

   - "**Root:**" Set this text input field to your game installation content folder. It will be used to resolve relative references.
   - "**Staging Area:**" Your main folder for all your mods, located inside your userdata directory. Setting up this folder correctly will make references to other mods work properly.

### Interface

1. "**.mtl:**" Now using the Blender file browser, select the `.mtl` file you want to import as material onto your mesh.
2. If needed, you can select a different **UV channel** than UV0. This might only make sense for special workflows. For example if you want to bake multiple materials onto single texture sheets, using UV1 might make sense.
3. **Flip Texture Y** should be enabled by default. It will flip the UV in Y Direction since `.dds` textures are flipped in Transport Fever 3.
4. Select the model, or the faces of the mesh that the material should be assigned to and hit Assign to Selected.

![](../../../_media/modding/tools/external/pasted/20260415-135650.png)

### Material Paths

- You might notice the material paths are set up to work as absolute references, either into the game or mod files. (e.g. `::/…`, or `<modID>::/…`)
- This is generally a good approach instead of creating entirely new materials, but you could convert them to relative paths depending on if it fits your case.
- You can assign any number of materials using the script, with submaterials being assigned based on your face selection.
- You can use entirely separate UV sets per material while you work. Keep in mind: In Transport Fever 3, only UV0 will be used so if you use other UV channels, you will need to make these UV0 in the end.
- If the staging area folder is properly set upped, the script also supports correctly referencing files from your mods; e.g. in the format `<modID>::/mat/<materialname>`

## Material Baking

![](../../../_media/modding/tools/external/baking_tutorial_01.png) Material Baking is the process of combining multiple texture sets onto a single one to be able to use one material. While it could be done manually by first stitching the textures together and then adjusting the UVs, this would be very tedious. Luckily, modern 3D content creation tools like Blender have a different approach that is a lot less work: They transfer the texture data for you - from one UV set to another.

We will look at the principles of this workflow using the **PAWS: Bakery** addon for Blender. There are different tools available with slightly different workflows, but this tool has the advantage of being free, integrated into the vanilla Blender 5.0 Extensions menu and still being in active development (at the point of this tutorial being written).

### PAWS: Bakery Blender Addon

- Get the tool by opening Blender and navigating to Edit → Preferences → Add-ons.
- In the Get Extensions menu, you can search for `paws` and will find the **PAWS: Bakery** addon.
- The newly activated tool can be found in the N-Panel, which can be unfolded by pressing the N key or via clicking the small arrow to the right of the Blender viewport, directly next to the transform gizmo.
- For this tutorial, we can collapse all dropdowns and unfold the Texture Set Mode dropdown. It's the only menu we will need.

![](../../../_media/modding/tools/external/baking_tutorial_03.png)

### Preparing shared UV map

- To apply the theory of material baking, we need to create a single new UV set that is shared between all materials that we want to combine.
- We may not break our existing UVs, so its necessary to create a second set by hitting the +-Button next to the UV Maps dropdown in the Data panel of your model.
- Make sure this second UV set is selected (setting it to visible using the camera icon is optional), or you will change the original mapping and break your textures. If you don't just have separate materials on a single model, but also on separate models and materials you wish to combine into a single-material model, you will also need to select this new UV Map on every model individually.
- Once you have everything selected, enter Edit mode (this works also while selecting multiple separate models) and unwrap the faces as you would with a single model/material: it should fill the whole normalized UV area without overlaps.

### Adding models with correct UV set

![](../../../_media/modding/tools/external/baking_tutorial_04.png) Now that everything's prepared, lets add all of our models to the PAWS: Bakery!

The Texture Set Mode should already be unfolded, that's the one we will be working in. Set the Output Mode to Single Texture.

Then create a new Texture Set, it will be like a preset storing all of our settings for this bake. This way you could direct different baking setup inside a single file without running into override/settings conflicts.

Give your new texture set a proper name and add all the meshes associated with the bake. For this step, it's important to have the newly added UV set visible using the camera icon. You can see in the second text column which texture set is used, so if it's faulty for some meshes, remove them, fix the Active Render flag on the UV Map and add the model again.

### Configuration and Baking

Before baking starts, it is required to make sure the materials have definite mapping and are not jumping to the "active" UV Map. We can set it the mapping of textures to our original UV set by using the UV Map node and specifically assigning the original UV Map.

![](../../../_media/modding/tools/external/baking_tutorial_05.png)
Next all of the relevant maps for baking are set up. The names are a bit different in the addon compared to TF3 and it uses a trick to render them without baking lights into them:

|  |  |
| --- | --- |
| **Transport Fever 3** | **PAWS: Bakery** |
| `_albedo` | `Color(Emit)` / `EMIT_COLOR` |
| `normal` | `Normal` / `NORMAL` |
| `_metal_gloss_ao` | `AORM` / `AORM` |
| `_metal_gloss_ao` as separate maps | `AO` / `AO`, `Roughness(Emit)` / `EMIT_ROUGHNESS`, `Metalness(Emit)` / `EMIT_METALNESS` |

The easiest way to support custom maps like CDR or emission masks would probably be compress the setup a bit to use as many channels as possible in a single baking setup. For example you could plug your CDR texture into the Emission material input (since it supports RGB) dirt and use the material's opacity slot for emission mask. This way you can even setup complex source materials for baking.

Once everything is set up, you can hit the small buttons next to every map listed in PAWS: Bakery to bake the respective map.

### Final Steps

![](../../../_media/modding/tools/external/baking_tutorial_06.png)

The maps are baked into a child folder relative to your blender file called `pawsbkr_textures`. Inside it, new folders are created based on your texture set names. Alternatively you can open them in the image viewer and export them via the burger menu → Image → Save As…

Unfortunately we cannot bake the exact channel layout of the MGA map, so we need to do some fixes in order for them to be usable in game, e.g. in an external software like Gimp or Photoshop:

- If it's not already inverted in your Blender node editor before baking: Invert the roughness texture to get glossiness
- If you baked AORM, switch the Red (AO in PAWS) and blue channels (metalness in PAWS). Otherwise, combine the separate maps into MGA.
- After that is done, the only steps left on your baked model/last lod is to delete the original UV channel and assign a single material.
