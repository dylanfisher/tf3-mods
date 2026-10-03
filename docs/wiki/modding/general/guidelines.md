---
title: Guidelines & Requirements
page_id: modding:general:guidelines
source: https://wiki.transportfever3.com/doku.php?id=modding:general:guidelines
---

# Guidelines & Requirements

This page outlines the guidelines and technical requirements for mods. The primary goals are a consistent user experience as well as stability, performance and compatibility.

## Content Guidelines

These guidelines aim to provide a consistent and familiar experience for players worldwide, ensuring that mods feel like an official part of the game.

**Basic Principles**

- Mod content should integrate in a seamless way, feeling like a natural extension of the original game.
- This includes adhering to technical requirements as well as respecting the game's visual style.
- Content should be available in English (with optional localizations) to appeal to a global audience.
- In general, follow the original game content as a reference for design and implementation.
- That said, if your goal is to introduce something entirely new or experimental, that is of course also possible!

**Visual Style**

- Ensure that the proportions are correct, with specific details potentially slightly exaggerated. As a rule of thumb, imagine a scale model world rather than the real world.
- The elements that define the silhouette are particularly important and should be modeled, while minor details can be left on normal maps.
- Make use of the full range of materials (metal, plastic, paint, wood, stone etc.) offered by the PBR metallic approach. Be generous with details and avoid repetitions to achieve authentic and believable surfaces.
- Always add some signs of weathering (light dirt, edge damage, diesel traces etc.) to avoid an unnaturally clean look. Cargo vehicles and industrial items should be more weathered than their passenger counterparts.

**Modeling/Texturing**

- Geometry

  - Find a good compromise for highly detailed elements so that you don't end up with too many triangles. Spend more triangles for important/characteristic elements than for minor details.
  - Avoid having many different meshes/objects, but keep in mind that functional (movable) parts need to be separate meshes. Each unique (sub)mesh/material combination requires a "draw call", which can negatively affect performance.
  - In general, maintain a vertex and triangle count consistent with original game assets. For example, typical vehicles range from 20.000 to 50.000 triangles depending on size and complexity. Some of the largest vehicles have up to 100.000 triangles.
- Texturing

  - Texel density: Aim for a density between 128 and 170 pixels/meter and keep it consistent for all UV islands. If necessary, you can allocate a smaller density for less important elements like interior or hidden surfaces.
  - Make sure that the UV space is well used (not too much empty space), but have some padding (32 px) between different regions. When creating variants of the same model (such as the cars in a multiple-unit train), try to minimize duplicate texture space.
  - Avoid having too many texture sets. For example, typical vehicles have between 1 and 3 sets (depending on size/complexity).
- LOD (Level of Detail)

  - Provide an adequate number of lower-detail versions of the model. A typical asset has 1 to 3 LODs (in addition to the base version) depending on complexity and how far the asset is visible.
  - LODs should reduce both triangle count and number of meshes/materials (to reduce the number of draw calls). Typically, the triangle count is reduced by a factor of 4 per level.
  - Pay particular attention to the lowest-detail version as it usually has the largest impact on performance. Reduce the geometry to the bare minimum and make sure only a single mesh/material is used.

**Folder Structure**

- While resources don't *have* to be organized in a specific way, it is considered good practice to follow the game's conventions.
- The general recommendation is to have one subfolder per asset and all its dependencies.
- If some resources are shared by multiple assets, place them in a "shared" folder (next to the asset folders).
- For models, there is typically a subfolder per resource type ("msh", "mat" and "ani") with textures placed in "mat/tex".
- Try to avoid extra long names, deeply nested folders, name repetitions, empty folders etc.

**Vehicle-Specific Topics**

- Bounding Box & Extent

  - Make sure that the bounding box contains the model and all light sources. In contrast, the "extent" should only contain the physical model.
  - Tip: Use the Model Editor to calculate these properties.
- Aging & Coloring

  - Include the necessary masks (cblend/dirt/rust) to make these features work.
  - There should be enough visual contrast between a brand-new vehicle and one in a bad state.
- Windows & Interior

  - Provide an interior mesh (with reduced detail level) so that it's possible to see through the windows.
  - Keep in mind that when the doors are open, it may be possible to see through the windows from the inside.
  - Use "sorted" meshes/materials to make transparency work from all angles.
- Animations

  - Create animations for doors, blinkers, wheels etc. (if applicable).
- Axles & Fake Bogies

  - These properties are needed for a vehicle to be correctly positioned on the rails (or on the road).
- Seats & Cargo Bays

  - Use a "Seat provider" to define seats for passengers and the driver.
  - Load indicators allow to define how cargo (loaded in a vehicle) is displayed.
- Particle Systems

  - Define emitters so that smoke and steam is generated in a realistic way.
  - Refer to the base game vehicles to configure strength and appearance.
  - Make sure that each particle system is attached to the correct node (via the "child" property).
- Lights

  - Configure light sources (such as headlights) so that vehicles work with night mode.
  - Avoid making light volumes too large (as a guideline, not more than twice the length of the vehicle).
- Display Panels

  - In order for a vehicle to have functioning display panels, "labels" should be defined.

## Technical Requirements

To ensure stability, performance, and compatibility across all platforms (PC and Console), all mods must adhere to the following requirements.

Note: All mods undergo an automatic validation process for both PC and console versions, which includes structural & file acceptance tests as well as syntax, metadata and resource integrity checks. Validation is mandatory to pass for a mod to be released on all platforms.

**Basics**

- Integrity: All resources must be syntactically correct and load without errors or warnings.
- Security: Batch files, shell scripts or other executable files are not allowed.
- Encoding: Text-based files (e.g. .lua, .json, .mdl, .msh) must be encoded in UTF-8 without BOM.

**Files & Folders**

- Size limit: The maximum unpacked size for a single mod must not exceed 500 MB. Avoid using more space than comparable assets in the base game.
- Naming conventions: Use lowercase only for all files and folders. Avoid whitespaces and special characters.
- No ballast: Include only essential files. Remove source assets (like .psd or .fbx) and temporary files before uploading.

**Models & Textures**

- The lowest-detail LOD meshes (blob files) must not exceed 256 KB.
- Texture format: Use the DDS format *with mipmaps*. Dimensions must be power-of-two (e.g. 512, 1024, 2048).

**Scripting**

- API usage: Only use the official Transport Fever 3 scripting API.
- Robustness: Scripts should be written to handle edge cases in a graceful way.

**Misc**

- Audio: All .wav files must be exported with a sample width of 16-bit (sampwidth: 2) and a frame rate of 48.000 Hz.
- Stability: The severityRemove parameter in mod.json must be correctly defined to indicate the impact of removing the mod from a save game.

For consoles, there are a few additional requirements:

**Console-Specific Constraints**

- No shaders: Custom shader files are not permitted on consoles due to platform-specific constraints.
- Stable gameplay: Mods may not alter fundamental gameplay features that could compromise performance.

## Mod Metadata

The metadata needs to be set up according to the description in [Mod Definition](../../modding/general/moddefinition.md). This covers the mod name, description and images which are the most relevant elements to gather attention by the users. Hence it is important to have a consistent and appealing quality.

The **name** of your mod is the first thing users will see, making it crucial for their decision to explore further. It should be clear, memorable, and in title case for consistency. Use Title Case (e.g., “Awesome Mod Name”) to ensure uniformity across all mods. This name should not be longer than 32 characters and may not contain line breaks.

The **cover** (sometimes called "mod listing image" or "thumbnail") and the other gallery images should show the main subject of the mod and contain only English texts, if necessary at all.

![](../../_media/modding/general/bestpractice/mods_screenshot.png)  
Cover based on ingame screenshot  
![](../../_media/modding/general/bestpractice/mods_screenshot_with_overlay.png)  
Cover based on ingame screenshot with icons  
![](../../_media/modding/general/bestpractice/mods_ui.png)  
Cover based on ui screenshot with tilt-shift effect  
![](../../_media/modding/general/bestpractice/mods_icons_example.png)  
Cover with stylized icon and colored accent

Refer to these **guidelines for creating a high-quality cover image**:

- Highlight the main subject: The image should showcase the primary element of your mod in an attractive and clear way.
- Use in-game screenshots: Using a screenshot from the game is the recommended approach for authenticity.
- Avoid extra elements: Do not add text, logos, or graphical overlays; let the image speak for itself. Keep in mind that the mod title is always displayed directly below the image. If desired, a small branding logo may be added (see below).
- Frame the subject appropriately: Ensure the main subject occupies a significant portion of the total image area. Use the "Advanced Camera" to find the best perspective (e.g. telephoto view for planes).
- Balance contrast and detail: Ensure the subject stands out from the background without making the environment look too plain or boring.
- Seek inspiration: Review other popular mods to see how they compose their images for effective presentation.

If the mod is difficult to represent visually (e.g. **script mods**), use one of the following alternatives:

- Add graphical overlays: Place simple icons or other visual elements over an in-game screenshot (using a 3D perspective if appropriate). Avoid using text.
- Show the GUI: Use a direct screenshot of an in-game menu, settings screen, or other relevant user interface. Frame the image so that the most important element is clearly highlighted (e.g. with a tilt-shift effect).
- Use a schematic representation: Create a clean, minimalist 2D icon that illustrates the mod's function. Use the provided background or, where available, the full category template as visual inspiration.

In technical terms, the image should be:

- 1920 x 1080 px
- 16:9 aspect ratio
- At most 8MB in size

If you (as an individual or group) plan to release multiple mods, you may want to add a small **logo** to the cover image. This so-called branding helps other players recognize your content immediately. Note that the logo should represent you as the creator, not the content of a specific mod. When designing the logo, keep in mind that the cover image is usually displayed in thumbnail size. Therefore, avoid including small details or too many graphical elements. Please also follow these technical guidelines for a consistent appearance:

- (Assuming the cover image is 1920 x 1080 px)
- Size: 270 x 270 px (or similar area if non-square)
- Position: Bottom left corner
- Margin: 54 px (from the left and bottom)

> **Download:**
>
> ### Template
>
> The templates for mod thumbnails are available here:
>
> - [png](../../_media/modding/templates/background_png.zip)
> - [psd (for Photoshop)](../../_media/modding/templates/script_mod_template_psd.zip)
> - [xcf (for Gimp)](../../_media/modding/templates/script_mod_template_xcf.zip)

The **description** will be shown in the ingame browser and on the website. It is mandatory that the description is provided in English. Not all formatting types are supported ingame, hence we recommend to use the following ones:

- Paragraph, Header 1, Header 2 and Header 3
- Bold text
- Unordered and ordered lists
- Horizontal lines

It is not recommended to use tables and embedded images or videos in the description. Both images and videos can be added to the gallery at the top instead.

Make sure you have included some **tags** describing your mod. They are used to offer filter categories to the players. See the [list of supported tags](../../modding/general/modtags.md). This example shows how to add tags in the `modinfo.json`:

```javascript
{
    "name": "MOD_NAME",
    ...
    "tags": [
        "Town Building",
        "Depot"
    ],
    ...
}
```
