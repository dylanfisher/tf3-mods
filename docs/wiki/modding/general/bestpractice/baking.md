---
title: Blender: Material Baking Workflow
page_id: modding:general:bestpractice:baking
source: https://wiki.transportfever3.com/doku.php?id=modding:general:bestpractice:baking
---

# Blender: Material Baking Workflow

This page is intended to provide a step by step manual for baking multiple texture sets onto a single set of texture to reduce draw call and material count needed for an asset to render.

While the text is useful for understanding everything in detail step by step, advanced users might also have a good experience just following the helper images one by one.

## The topic of Draw Calls

![](../../../_media/modding/general/bestpractice/baking_tutorial_01.png)As explained in the parent page, Draw Calls can be a major performance bottleneck for Transport Fever 3 content.

The number of Draw Calls increases with every separate mesh and material.

In terms of re-usability and Texel Size, sometimes there are not really good alternatives to using separate materials; at least for lod0. This in general really is fine and common standard in Transport Fever 3 as well as other current-gen games. The focus is more on reducing the number of draw calls for later lods by merging objects, removing small detail materials like glasses and also combining textures onto a single texture set, saving the need for separate materials in the process.

## Draw Call scaling with LODS

![](../../../_media/modding/general/bestpractice/baking_tutorial_02.png)While (generally speaking) a higher number of Draw Calls in lod0 is not the biggest issue, it becomes more of a problem if later lods still retain a high number of Draw Calls and cannot fallback to a really low number. The more we zoom out, the more they add up. Especially for the last lod, just a single draw call is the optimal target.

For vehicles its often easy to just keep the chassis/shell of the vehicle as the last remaining mesh and material, but it can be a bit of a challenge for buildings. They often use separate trim sheets or tileable textures for ceiling, walls and ground and still have a noticable color contrast from a far distance that cannot be discarded easily without some really visible plopping between lod levels.

That's where the process of Material Baking can come in handy.

## Material Baking

![](../../../_media/modding/general/bestpractice/baking_tutorial_03.png)So, what exactly is Material Baking? It essentially describes the process of combining multiple separate texture sets on an object onto a single, shared texture that only needs a single material afterwards and thus, will only cause a single Draw Call to render. While it could be done manually by first stitching the textures together and then adjusting the UVs, this would be very tedious. Luckily, modern 3D content creation tools like Blender have a different approach that is a lot less work: They transfer the texture data for you - from one UV set to another.

We will look at the principles of this workflow using the "PAWS: Bakery" addon for Blender. There are different tools avialable with slightly different workflows, but this tool has the advantage of being free, integrated into the vanilla Blender 5.0 Extensions menu and still being in active development (at the point of this tutorial being written).

## The PAWS: Bakery Blender Addon

- ![](../../../_media/modding/general/bestpractice/baking_tutorial_04.png)Get the tool by opening Blender and navigating to Edit → Preferences
- In the "Get Extensions" menu, you can search for "paws" and will find the PAWS: Bakery addon. We used Blender 5.0.
- The newly activated tool can be found in the N-Panel, which can be unfolded by pressing the N key or via clicking the small arrow to the right of the Blender viewport, directly next to the transform gizmo.
- For this tutorial, we can collapse all Dropdowns and unfold the "Texture Set Mode" dropdown. It's the only menu we will need
- With the addon setupped, we need to do some preparations directly on our model next

## Preparing a new UV map shared between all materials

- ![](../../../_media/modding/general/bestpractice/baking_tutorial_05.png)To apply the theory of Material Baking, we need to create a new, single UV set that is shared between all materials that we want to combine
- We may not break our existing UVs, so its necessary to create a second set by hitting the Plus-Button next to the "UV Maps" dropdown in the "Data" panel of your model.
- Make sure this second UV set is selected (setting it to visible using the camera icon is optional), or you will change the original Unwrap and break your textures. If you don't just have separate materials on a single model, but also on separate models and materials you wish to combine into a single-material model, you will also need to select this new UV Map on every model individually.
- Once you have everything selected, enter Edit mode (this works also while selecting multiple separate models) and unwrap the faces as you would with a single model/material: it should fill the whole normalized UV area without overlaps.

## Adding all models to PAWS with the correct UV set

![](../../../_media/modding/general/bestpractice/baking_tutorial_06.png)Now that everything's prepared, lets add all of our models to the PAWS: Bakery!

The "Texture Set Mode" should already be unfolded, that's the one we will be working in. Set the "Output Mode" to Single Texture.

Then create a new "Texture Set", it will be like a preset storing all of our settings for this bake. This way you could direct different baking setup inside a single file without running into override/settings conflicts.

Give your new texture set a proper name and add all the meshes associated with the bake. For this step, it's important to have the newly added UV set visible using the camera icon. You can see in the second text column which texture set is used, so if it's faulty for some meshes, remove them, fix the "Active Render" flag on the UV Map and add the model again.

## Defining the source UV Map and setting up resulting Texture Types

![](../../../_media/modding/general/bestpractice/baking_tutorial_07.png)Before we start baking, we need to make sure our materials have definite mapping and are not jumping to the "active" UV Map. We can set it the mapping of textures to our original UV set by using the UV Map node and specifically assigning your original UV Map.

Next we can setup all of the respective maps we want to bake. The names are a bit different in the addon compared to TF3 and it uses a trick to render them without baking lights into them, so here is the mapping: TF3 vs PAWS Bakery names

|  |  |
| --- | --- |
| **Transport Fever 3** | **PAWS: Bakery** |
| Albedo | Color(Emit) / EMIT_COLOR |
| Normal | Normal / NORMAL |
| MGA | AORM / AORM |
| MGA as separate maps | AO / AO, Roughness(Emit) / EMIT_ROUGHNESS, Metalness(Emit) / EMIT_METALNESS |

The easiest way to support custom maps like CDR or EmissionMasks would probably be compress the setup a bit to use as many channels as possible in a single baking setup. For example you could plug your CDR texture into the Emission material input (since it supports RGB) dirt and use the material's opacity slot for EmissionMask. This way you can even setup complex source materials for baking.

Once everything is setupped, you can hit the small buttons next to every map listed in PAWS: Bakery to bake the respective map.

## Final Steps

![](../../../_media/modding/general/bestpractice/baking_tutorial_08.png)The maps are baked into a child folder relative to your blender file called "pawsbkr_textures". Inside it, new folders are created based on your texture set names. Alternatively you can open them in the image Viewer and export them via the burger menu → Image → Save As…

Unfortunately we cannot bake the exact channel layout of the MGA map, so we need to do some fixes in order for them to be usable ingame, e.g. in an external software like Gimp or Photoshop:

- If it's not already flipped in your Blender node editor pre-baking: Flip the Roughness texture to get Glossiness
- If you baked AORM, switch the Red (AO in PAWS) and blue channels (metalness in PAWS). Otherwise, combine the separate maps into MGA.
- After that is done, the only steps left on your baked model/last lod is to delete the original UV channel and assign a single material.
