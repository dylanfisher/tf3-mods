---
title: Model Editor
page_id: modding:tools:modeleditor
source: https://wiki.transportfever3.com/doku.php?id=modding:tools:modeleditor
---

# Model Editor

The Model Editor is the main tool to be used when importing and editing models for Transport Fever 3. It features various import and conversion tools as well as editing functionality for the model metadata. Testing of different things like particles, aging, labels and animations is possible too. For presentation in the vehicle store, the Model Editor also includes an option to create screenshots and GUI icons.

## Setup

To start the Model Editor, execute the `ModelEditor.bat` in the installation directory of Transport Fever 2 on Windows, `ModelEditor.sh` in the installation directory of Linux or `ModelEditor.command` in the installation directory of MacOS. This will open two windows, a console window with debug output and the actual user interface window.

On first startup, the Model Editor creates a configuration file in

- `%APPDATA%/Transport Fever 3/` for Windows
- `~/.local/share/Transport Fever 2` for Linux
- `/Users/<username>/Library/Application Support/Transport Fever 3/` for MacOS

and asks the user to fill in the userdata location in this file. The configuration file contains several references to directories. The `userDataPath` is the directory where the userData is located. It is used to find the staging area and screenshot folders. You can find your userdata folder over the game's main menu > SETTINGS > ADVANCED > OPEN USER DATA FOLDER.

> **Caution:**
>
> Only use forward slashes / in the path, otherwise the model editor may not start properly.

After saving the file, the Model Editor may be started again.

## User Interface

Once the Model Editor has started, the main window is visible with the toolbar at the top and the viewport where the models are rendered below.

![](../../_media/modding/tools/modeleditor/model_editor_toolbar.png)

The toolbar is split into 5 different groups of interactive elements:

1 dropdowns and buttons to select mods and models and save them  
2 model rendering options  
3 animation trigger  
4 detail windows  
5 validation, screenshots and options

As long as no model is loaded, most buttons are deactivated.

The viewport camera is controlled with the mouse:

- Hold the left mouse button and move the mouse to rotate the camera around.
- Hold the right mouse button and move the mouse to move the camera around.
- Scroll the mouse wheel to zoom in and out.
- Hold CTRL and the left mouse button to rotate the skybox around the model.

### Model Loading and Saving

To open a model, click on the ![](../../_media/modding/tools/modeleditor/open.png) button. The open dialog allows browsing through the content of the base game as well as all mods in the staging area. It is possible to search for models with the search field. It covers all subfolders of the currently selected folder. The ![](../../_media/modding/tools/modeleditor/open_folder.png) button opens the currently selected folder in the file explorer.

A list of previously opened models can be accessed by clicking the ![](../../_media/modding/tools/modeleditor/recent.png) button. It is sorted by date. To close the currently loaded model, use the ![](../../_media/modding/tools/modeleditor/close.png) button.

If you want to save a model, use the ![](../../_media/modding/tools/modeleditor/save.png) button. It will save the currently loaded model to the mod that is selected in the dropdown next to it. Please be aware that there is no extra confirmation in case you overwrite existing files. To only save certain parts of the model, you may deselect the options provided in the dropdown next to the save button:

- MODEL will save the .mdl file
- MESH will save the .msh and .msh.blob files if they were just imported from fbx.
- MATERIAL will save the .mtl files
- ANIMATION will save the .ani files if they were just imported from fbx.

### Model Rendering

The model rendering in the viewport can be influenced by the second group of buttons in the toolbar 2. The three icon buttons are:

- ![](../../_media/modding/tools/modeleditor/model_material.png) for the model with the materials as it looks in the game.
- ![](../../_media/modding/tools/modeleditor/model_solid.png) for the model in plain white.
- ![](../../_media/modding/tools/modeleditor/model_wireframe.png) for the model as a wire mesh.

The level of detail can be selected further to the right. With Auto the used level of detail depends on the zoom level like in the game. 0 and above select specific levels of detail independent of the zoom level.

### Animation Preview

The third button group 3 allows direct playing of one animation. If the model has any animation, it can be selected in the dropdown. Then it can be started with the ![](../../_media/modding/tools/modeleditor/resume.png) button. To loop the animation, activate the ![](../../_media/modding/tools/modeleditor/refresh.png) toggle next to it.

### Model Properties

The fourth group 4 allows accessing detailed windows for the model tree, metadata, materials and animations.

#### Model Tree

A click on the Model button opens the model window.

![](../../_media/modding/tools/modeleditor/model_editor_model_dialogue.png)

At the top of the window, the full path of the model resource is shown. To the right 1, there are three action buttons:

1. Recalculation of the [bounding box](../../modding/general/resourcetypes/mdl.md#bounding_box).
2. Recalculation of the [simulation extent](../../modding/general/resourcetypes/mdl.md#extent).
3. Open the model folder in the file explorer.

In the section below 2, the bounding box of the model can be manually adjusted.

The bottom section of the window is a tab widget 3 that has a tab for each level of detail. For each level of detail, it is possible to adjust the `visibleFrom` and `visibleTo` distances and lods can be marked as [texture lod base](../../modding/general/resourcetypes/mdl.md#level_of_detail) 4.

Below is a tree 5 that shows the node hierarchy of the model with the node names and mesh file references. If you activate checkboxes on the left or hover over lines, the mesh will be displayed alone in the viewport. This helps with identifying model parts. If you want to manually transform a mesh, e.g. to correct its position, you can open a popup with transformation parameters by clicking on the right button. The columns at the very right tell how many materials and animations are assigned to the node. They are listed in a tooltip when hovering the numbers or by clicking the checkbox Extended View further above.

#### Metadata Editor

To access the metadata editor, press the Metadata button. It presents all the data that is set in the `metadata` struct of a model.

![](../../_media/modding/tools/modeleditor/model_editor_metadata_dialogue.png)

To add new properties, you can press on the + button in the top right corner 1. There you can select new property types and add them to the metadata of the currently loaded model. To delete all metadata, use the gear button next to it and select Delete all. If you want to reset to the initial loaded values, press Reset.

The properties are collapsed by default 2 . Press the arrow markers on the left to unfold the hierarchy levels of properties. To unfold the complete hierarchy inside of a property, you can hold SHIFT while you click on the arrow marker.

To reset a single property or only a value of the property, you can use the ![](../../_media/modding/tools/modeleditor/recent.png) arrow on the right side 3. To completely remove it, press the ![](../../_media/gamemanual/interface/buttons/bin.png) button instead. Some properties contain lists, e.g. the labels. You can add a new entry by clicking on ![](../../_media/gamemanual/interface/buttons/plus.png) button. If you want to add a duplicate of an existing list element, use the ![](../../_media/gamemanual/interface/buttons/duplicate.png) button next to it. Both are added to the end of the list.

Depending on the property there are one or more attributes to configure 4. Some require numeric or text input, others are checkboxes or sliders. For some attributes or even whole metadata properties, there are templates. They can be selected with the gear button on the left 5.

#### Material Editor

The MATERIALS button leads you to the materials editor. It provides access to all material files that are used in the model.

![](../../_media/modding/tools/modeleditor/model_editor_material_dialogue.png)

The top section 1 lists all materials used in this model. The ones referenced with relative path are more emphasized than the ones referenced with absolute path to differentiate between materials that are local and materials that are likely shared and should only be edited with caution. On the right side, the short tag of the individual material type is shown. Hovering over a line will hide all other geometry in the viewport.

For the currently selected material, the full material type is shown below the list 2. Its order can be changed on the right side and the material can be converted to another [material type](../../modding/general/resourcetypes/mtl.md#types) by pressing the ![](../../_media/gamemanual/interface/buttons/settings.png). There you can reset a material file to the initially loaded values too by clicking the ![](../../_media/modding/tools/modeleditor/recent.png) button.

Below is a list of all material properties depending on the material type 3. To unfold properties, you can press the arrow button and to reset a single property, you can click on the ![](../../_media/modding/tools/modeleditor/recent.png) arrow on the right side.

You can edit the properties in a similar way as the properties in the metadata editor. Texture references can either be written by hand or selected with a file picker that can be opened with the ![](../../_media/modding/tools/modeleditor/open.png) button on the right side 4.

Some material properties offer templates, they can be accessed as in the metadata editor by clicking on the gear button on the left side 5.

#### Metadata Validation

To check if there are major issues with the configured metadata, you can use the ![](../../_media/modding/tools/modeleditor/validate.png) button in the top bar. It will run a check and informs you as soon as it finds an issue. Run it again after you fixed the issue to check if there are further issues.

Currently the following metadata issues are covered by the validation tool:

|  |  |  |
| --- | --- | --- |
| `loadIndicator` | `Referenced mesh node 'XYZ' not found (key: 'cargoBay.childId' in '<file>')` | The `cargoBay` is not assigned to an existing node in the model. |
| `loadIndicator` | `Area too small for 'loadIndicator.configs[1].cargoBay.bbox' at <file>` | The `cargoBay` bounding box is too small. |
| `loadIndicator` | `The configuration 'loadIndicator.configurations[1][2][3]' references invalid slot 1 at <file>` | The referenced slot in the config does not exist in the model. |
| `roadVehicle` | `roadVehicle/configs/fakeBogies: size (= 2) must match number of lods (= 3) or be empty` | There needs to be a list of `fakeBogies` per LOD. It might be an empty list `{}`. |
| `railVehicle` | `railVehicle/configs/fakeBogies: size (= 2) must match number of lods (= 3) or be empty` | There needs to be a list of `fakeBogies` per LOD. It might be an empty list `{}`. |
| `waterVehicle` | `waterVehicle/availPower: ship will never reach top speed, increase power or reduce area` | The `waterVehicle.area` value is too large in relation to the `availPower`. |
| `airVehicle` | `airVehicle/configs/axles: missing entry (but wheels specified)` | If `wheels` are configured, `axles` need to be configured as well. |
| `airVehicle` | `airVehicle/configs/wheels: missing entry (but axles specified)` | If `axles` are configured, `wheels` need to be configured as well. |
| `airVehicle` | `airVehicle/configs: invalid landing gear configuration; wheels defined but not axles` | If `wheels` are configured, `axles` need to be configured as well. |
| `airVehicle` | `airVehicle/configs: invalid landing gear configuration; axles defined but not wheels` | If `axles` are configured, `wheels` need to be configured as well. |
| `airVehicle` | `airVehicle/configs: invalid landing gear configuration; zero distance between main and front/back gear` | The configured wheels and axles may not be in the same spot. |
| `airVehicle` | `airVehicle/configs: invalid landing gear configuration; aircraft's initial pitch on ground is below <number> deg` | The plane gear results in a too negative pitch on the ground. |
| `airVehicle` | `airVehicle/configs: invalid landing gear configuration; aircraft's initial pitch on ground is above <number> deg` | The plane gear results in a too high pitch on the ground. |
| `seatProvider` | `Referenced mesh node 'XYZ' not found (key: 'seatProvider.seats[10]' in '<file>')` | The `seat` is not assigned to an existing node in the model. |
| `transportVehicle` | `transportVehicle/loadConfigs: list of load configs must not be empty` | The compartment needs at least one load config. |
| `transportVehicle` | `Model has a cargo entry specifying a load indicator '1' but no load indicator metadata` | The cargo configuration is referencing a `loadIndicator` but none are configured. |
| `transportVehicle` | `Model does not have load indicator '2`' | The cargo configuration is referencing a non-existent `loadIndicator`. |
| `transportVehicle` | `Wrong seat index in transportVehicle, seat 3 is invalid, should between 0 and 2 (compartment = 1, loadConfig = 2)` | The cargo configuration is referencing a non-existent `seat`. |
| `transportVehicle` | `transportVehicle/capacities: capacity '-1' not valid` | The capacity may not be negative. |
| `transportVehicle` | `transportVehicle/capacities: 'excluded' cargo type 'cargos/coal/coal.cargo' not found` | The cargo configuration is referencing a non-existent cargo type. |
| `transportVehicle` | `transportVehicle/capacities: cargo class 'BULK' not found` | The cargo configuration is referencing a non-existent cargo class. |
| `categoryList` | `Referenced cargo type not found: cargos/coal/coal.cargo, referenced by <file>` | The model is referencing a non-existent cargo type. |
| `categoryList` | `Referenced cargo format not found: RECT_40x10, referenced by <file>` | The model is referencing a non-existent cargo format. |

The following error messages might appear when there are misconfigured meshes, materials or animations:

|  |  |  |
| --- | --- | --- |
| `Mesh` | `'body' with '<file>' (SKINNING_PHYS_NRML_MAP): Used technique '<file>' requires missing mesh attribute 'XYZ' in mesh {}. Usually this means a model is missing UV1 vertex attributes or a skinned material is used with a unskinned mesh.` | The mesh is not compatible with the material type. |
| `Material` | `'body' with '<file>' (PHYS_TRANSPARENT): map_albedo has missing texture <file>.` | A material is referencing a non-existent texture file. |
| `Material` | `Group 'body' has 2 materials but mesh has 3 groups (they must be equal). The group has been patched but this might lead to unexpected results.` | The number of submeshes needs to match the number of assigned materials. |
| `Material` | `Group 'body' has no materials but mesh has 2 groups` | Materials need to be assigned to the meshes. |
| `Material` | `Group body has 2 skin materials but mesh has 3 groups (they must be equal). The group has been patched but this might lead to unexpected results.` | The number of subgroups needs to match the number of assigned skin materials. |
| `Material` | `Group 'body' has no skin materials but mesh has 2 groups` | Materials need to be assigned to the meshes. |
| `Material` | `Model Group 'body' uses skinned mesh '<file>' with an unskinned material '<file>'. This might lead to unexpected crashes or glitches.` | Meshes with vertex groups should be used with skinned materials. |
| `Animation` | `Animation at body named <file> has incorrent number of times 12 and transforms 10.` | Number of time stamps and transformations need to match. |
| `Animation` | `Animation at body named <file> has no keyframes.` | Animations need to have at least one time stamp. |
| `Animation` | `Animation at body named <file> has keyframes starting after 0: 1200.` | The first time stamp needs to be at time 0. |

### Options

The options window can be opened by a click on the OPTIONS button in the top right. It contains several tabs with different settings. All settings are persisted and loaded when the model editor is opened. Most of the tabs have a RESET TO DEFAULT button to revert them to their default values.

#### Rendering

![](../../_media/modding/tools/modeleditor/options_rendering.png)

The Rendering tab provides several general options to show and hide annotations. The **Render Settings** cover general annotations:

- **Axes** renders the three orientation axis that meet at the origin in the 3D space. These mark the global positive directions of the x (red), y (green) and z (blue) dimension.
- **Nodes** renders the hierarchy of nodes in the model node tree as well as their individual orientation.
- **Node Names** renders the assigned names for each node.
- **Bounding Box** renders the [bounding box](../../modding/general/resourcetypes/mdl.md#bounding_box) used for rendering as it is specified in the `.mdl` file.
- **Extent Box** renders the [extent box](../../modding/general/resourcetypes/mdl.md#extent) used for simulation as it is specified in the `.mdl` file.
- **Collider** renders the [collider shape](../../modding/general/resourcetypes/mdl.md#collider) as it is specified in the `.mdl` file.

The **Locator Settings** cover annotations for individual features:

- **Seat Locators** renders small indicators at the positions of defined [passenger seats](../../modding/vehicles/basics.md#seats1).
- **Light Source Locators** renders origins and shapes of defined [light sources](../../modding/general/resourcetypes/mdl.md#lightsourcelist).
- **Particle System Locators** renders small indicators where particle emitters are located.
- **Label Outlines** enables small markers and rectangles where [text labels](../../modding/general/resourcetypes/mdl.md#labellist) are placed in the model. The text boxes below can be used to define some demo texts to test the display.
- **Water Line** renders a line that indicates the position of the [water line](../../modding/vehicles/types.md#metadata2) definition of ships.
- **Cargo Bay Bounding Box** renders the bounding boxes of defined [cargo bays](../../modding/vehicles/basics.md#cargobay).
- **Cargo Slot Locators** renders small indicators at the positions of defined [cargo slots](../../modding/vehicles/advancedtopics.md#custom_cargo_models).
- **Bogies** renders small indicators where axles and wheels are located.
- **Bogies** renders small indicators where bogies are located.
- **Fake Bogies** renders small indicators where [fake bogies](../../modding/vehicles/advancedtopics.md#fake_bogies) are located.

For investigation of meshes, it is also possible to select **Vertex Settings**:

- **Normals** renders the normals of vertices.
- **Tangents** renders the tangents of vertices.

#### Config

![](../../_media/modding/tools/modeleditor/options_config.png)

The Config tab provides options to test various features of vehicles. In the top section **General Settings** holds various options for general testing:

- **Enable Auto Update** decides whether and when the model should be reloaded whenever one of the source files changes. Be aware that unsaved changes to the model are lost if the model is reloaded. If you encounter black textures or crashes while exporting textures from your graphic program, this might be caused by the Model Editor reloading the texture files before they are completely written by the program. In this case, use the `On Focus` option.
- **Animation Speed Scale** is the speed factor that is used for animations.
- **Lod scale** is a slider that can be used to mimic lower geometry graphic settings.
- **Reference Model** is allows showing a second model of the same mod or the base game as a reference to compare. If a model is referenced, it is visible as static asset. It won't be used in the screenshots. Click on the ![](../../_media/modding/tools/modeleditor/open.png) button and navigate through the file picker to select a model. With the ![](../../_media/gamemanual/interface/buttons/transform.png) button you can transform the reference model and with the ![](../../_media/modding/tools/modeleditor/eye.png) button you can toggle its visibility.
- **Color** lets you choose a color for models that have [color blending materials](../../modding/general/resourcetypes/mtl.md#color_blending_dirt_rust) in use.
- **Age** is a slider that can be used to simulate the [aging](../../modding/general/resourcetypes/mtl.md#color_blending_dirt_rust) of the vehicle. Depending on the age, the dirt and rust layers have different intensities.

The **Load Settings** section allows testing the [cargo](../../modding/vehicles/basics.md#compartment_list) and [passengers](../../modding/vehicles/basics.md#seats) of vehicles:

- **Passengers** is a slider that lets you choose the amount of passengers that should be displayed.
- **Cargo** is a slider that lets you choose the amount of cargo that should be displayed.
- **Random Seed** is a spinner that can be used to select a seed for the randomisation of cargo slots and configurations.
- **Cargo indicators** is a list of compartments where you can select the cargo type that should be used in the preview.

The **Particle Settings** section allows testing the [particle emitters](../../modding/general/resourcetypes/mdl.md#particlesystem):

- **Preview Particles** enables the particle rendering.
- **Reverse Direction** changes the direction of the preview velocity configured with the slider below.
- **Particle Velocity** is a slider to select a preview velocity that mimics movement of the model.
- **Particle Filter Tag** allows restricting the preview to particle emitters with a specific tag.

The **Label Settings** section allows testing the [labels](../../modding/general/resourcetypes/mdl.md#labellist). There are text inputs for the different label data types.

#### Graphics

![](../../_media/modding/tools/modeleditor/options_graphics.png)

The Graphics tab provides graphic settings:

- **Texture Quality** selects the maximum displayed texture mip map level. `Very High` uses the original texture resolution, `High` skips the highest resolution, …
- **Anti-Aliasing Quality** sets the anti-aliasing quality for the rendering.
- **Bloom Quality** sets the quality of the emissive bloom.
- **Enable Bloom** allows disabling or enabling the bloom altogether.
- **Enable Screen Space Reflections (SSR)** toggles the reflections on glossy surfaces based on the actual surroundings.
- **Enable Screen Space Ambient Occlusion (SSAO)** enables the smooth ambient occlusion that is computed by the engine.
- **Enable Shadows** enables shadows that are computed depending on the direction of the sun.
- **Enable Legacy HDR Rendering** switches back to the Transport Fever 2 dynamic range rendering.
- **Enable VSync** toggles the frame rate synchronization.

Some of the graphic settings require a restart of the Model Editor to take effect.

#### Environment

![](../../_media/modding/tools/modeleditor/options_environment.png)

The Environment tab provides several camera and environment related options. The camera settings are:

- **Field of View (FOV)** allows choosing the field of view. The larger the chosen value is, the wider is the camera angle.
- **Background** can be used to set the rgb values for the background color that should be used when the environment is not rendered (see above). A colorpicker is opened on click to select the color by numbers, hex code or visually.

For the environment, the following settings are available:

- **Enable Environment** activates a gray ground face at height 0 and a simple blue skybox as the background. If unchecked, no ground face is shown.
- **Environment** offers all available [environments](../../modding/environment/environments.md) that may be used in the model editor.
- **Time of Day** is a slider to set the current time of the environment.
- **Day of Year** is a slider to set the day of the year. The height of the sun depends on the calendar.
- **Reference Brightness** is a slider to adjust the overall brightness. 10 is the maximum value that results in a darker mood.
- **Sun Intensity** is a slider to adjust the intensity of the sun, affecting the direct light on the planet.
- **Ambient Color (Day)** is an ambient color that tints the whole world slightly during day time.
- **HDR Exposure (Day)** is a number used to scale the hdr exposure during day time.
- **HDR Contrast (Day)** is a number used to scale the hdr contrast during day time.
- **Ambient Color (Night)** is an ambient color that tints the whole world slightly during night time.
- **HDR Exposure (Night)** is a number used to scale the hdr exposure during night time.
- **HDR Contrast (Night)** is a number used to scale the hdr contrast during night time.

#### Icons

![](../../_media/modding/tools/modeleditor/options_icons.png)

To generate vehicle icons and take representative screenshots of the vehicle models, you can use the SCREENSHOT button on the right side of the top bar. This will generate the necessary ui icons and moves them at the correct position in the mod. Additionally, larger renderings from all sides as well as a perspective view will be generated and saved in the `screenshots/` folder in the specified `userDataPath`.

The Icons tab provides options for the creation of ui icons and other screenshots. The **Screenshot Settings** are general settings for the screenshot generation:

- **Screenshot extension** allows choosing the file extension that is used for the generation. The game requires the `.tga` format, while `.png` might be useful for websites.
- **Use Default Stage Files** switches between the standard stages for tracks/streets and the ones configured below.
- **Stage file (bus, tram, truck)** is the model reference that is used as street segment for screenshots of road vehicles.
- **Stage file (train, wagon)** is the model reference that is used as track segment for screenshots of rail vehicles.
- **Use Viewport Environment** switches between the standard environment for screenshots and the ones selected in the Environment.
- **Use Viewport Animations** switches between the default animation state and the one configured in the Animation Window.

The sections below can be used to fine tune the generated icons and screenshots. The **UI Icons** setting **Max Width** sets the maximum horizontal size for ui icons. The pixel per meter ratio for the icon is set with **Pixels Per Meter**. The same settings are available for the **Large Ortho Screenshot** further down below.

The **3D Screenshot Settings** are used for the diagonal screenshots:

- **Angle** is the horizontal rotation around the model.
- **Height** is the height of the camera. The height is computed automatically with value `-1`.
- **Radius** is the distance of the camera to the center point of the model. The distance is computed automatically with value `-1`.
- **Field of View** is the camera angle that sets the focal length.
- **Size X** sets the maximum horizontal size.
- **Size Y** sets the maximum vertical size.

The **Viewport Screenshot Settings** allow setting the size for viewport screenshots.

Below are several checkboxes allowing to adjust the behavior of the screenshot button in the top bar:

- **Disable Screenshot Button** disables the screenshot button in the top bar so it can't be triggered accidentally.
- **Generate UI Icons** will generate the ui icons for vehicle models in the mod.
- **Generate Cblend Mask** will generate the cblend masks for vehicle models in the mod.
- **Generate 3D Screenshots** will generate the perspective screenshots for vehicle models in the mod.
- **Generate Large Ortho Screenshots** will generate large orthographic screenshots for vehicle models in the mod.
- **Generate Viewport Screenshots** will generate screenshots with the current perspective in the Model Editor.
- **Generate Ortho Screenshots** will generate small orthographic renderings for vehicle models in the mod.

The **Bulk Actions** section allows taking screenshots for multiple models at once. The **Bulk Prefix** allows selecting a folder containing multiple models. The operation is then started with Bulk Generate.

> **Caution:**
>
> Keep in mind that this may take a long time depending on the number of models in the mod and the hardware of the computer.

#### Im-/ Export

![](../../_media/modding/tools/modeleditor/options_import.png)

The Im-/Export tab allows configuring the behavior when importing `.fbx` files:

- **Overwrite Meshes** allows overwriting existing meshes when re-importing a `.fbx` file.
- **Overwrite Animations** allows overwriting existing animations when re-importing a `.fbx` file.
- **Overwrite Materials** allows overwriting existing materials when re-importing a `.fbx` file.
- **Overwrite PHYS_TRANSPARENT_DIFFUSE Materials** allows overwriting the placeholder materials when re-importing a `.fbx` file.
- **Overwrite Textures** allows overwriting existing textures when re-importing a `.fbx` file.
- **Use Blender Coordinate System** needs to be selected when importing `.fbx` files exported from Blender.

When saving models, the Model Editor automatically converts `.tga` textures to `.dds`. It is possible to adjust the **Texture Conversion Quality** and the compression can be disabled completely with **Skip Compression of Existing Textures**.

#### Tools

![](../../_media/modding/tools/modeleditor/options_tools.png)

The Tools tab provides several tools to adjust the currently opened model or several models at the same time. The general settings are:

- **Target Mod** allows selecting the mod in which the result of the tool operation will be saved.
- **Bulk Prefix** can be used to select the folder which contains the model that will be affected.

The **Rename** tool allows searching and replacing parts of filenames. There are two inputs:

- **Search Token** is used to specify the string that is searched.
- **Replace Token** can be used to specify the string that shall be inserted where the search token is found. If empty, the search token is removed without replacement.

The **Convert** tool allows migrating Transport Fever 2 models to Transport Fever 3. This covers:

- restructuring files from `res` to the `content` structure. Be aware that the result depends on how consistent the folder structure in the `res` directory are.
- adjusting `.mtl` files to the new structure. This automatically sets the [legacy flag](../../modding/general/resourcetypes/mtl.md#light_receiver).
- adjusting the metadata of the mdl. New values need to be added manually.

The **Copy** tool allows creating a copy of a model in another mod.

The **Validate** tool allows validating several models at once.

## Importing Models & Data

The Model Editor supports the import of different things:

- `.import.lua` files for material/metadata templates
- `.fbx` files for 3D models
- `.fbx` files for construction data

### Material/Metadata Templates

It is possible to import a preset containing both info for materials and metadata before importing 3D models. These `.import.lua` files have the following structure with three optional functions:

```lua
fbxLoader = {
  predictMaterial = function(params)
    return "::physical_nrml_map_op_uv1_ao_op_mask.mat.lua"
  end,
  overrideProperties = function(params)
    return params.properties
  end,
  getMetadataMap = function()
    return {
      availability = { 
        yearFrom = 1900,
        yearTo = 0,
      },
    }
  end,
}
```

The `predictMaterial` function is called for every material and allows to provide a custom function to identify the material type. The `params` struct contains:

- `fbxPath` contains the folder path of the `.fbx`, e.g. `C:/Users/<user>/Desktop/stations-water-models+main_building_small`.
- `fbxName` contains the file name of the `.fbx` without the `lodX` suffix and file ending, e.g. `test_`.
- `fbxMaterialName` contains the name of the material in the `.fbx` for which the function is called during the import, e.g. `/buildings/a/r1/4x4_04/mat/a_rs_r_wd01`.
- `textures` contains a list of texture resources that are assigned to the material in the `.fbx`, e.g. `{"<TF3 install path>/content/buildings/a/r1/shared/a_res_l1/a_rs_r_wd01_alb.dds"}`.

Expected return value is either `nil` or a file path to a material type definition, e.g. `phys_transparent_nrml_map_cblend.mat`.

The `overrideProperties` function is called for every material and allows to override the material properties. The `params` struct contains:

- `fbxPath` contains the folder path of the `.fbx`, e.g. `C:/Users/<user>/Desktop/stations-water-models+main_building_small`.
- `fbxName` contains the file name of the `.fbx` without the `lodX` suffix and file ending, e.g. `test_`.
- `fbxMaterialName` contains the name of the material in the `.fbx` for which the function is called during the import, e.g. `/buildings/a/r1/4x4_04/mat/a_rs_r_wd01`.
- `materialType` contains the material type reference, e.g. `::/rendering/physical.mat`.
- `properties` contains the full table with all material properties, similar to the content of the `.mtl` files.

Expected return value is the altered or unaltered list of properties.

The `getMetadataMap` function has no parameters and returns a table that is used as is for the `metadata` of the models that are imported afterwards.

> **Download:**
>
> ##### Material Override
>
> This example provides a rather complex override template that alters properties of materials. It is available for [download](../../_media/modding/tools/modeleditor/pnouam_light_soft_overlay_materials.import.lua).
>
> Explanation
>
> The example contains both a `predictMaterial` and a `overrideProperties` function used to alter material types and properties of building windows when importing them.
>
> The `predictMaterial` function checks if the material name ends with `PNOUA` or `PNOL` and returns a specific material type for these. Other materials are untouched by returning nothing.
>
> The `overrideProperties` function overrides several properties, e.g. `map_id`, `map_ao`, `map_op_1`, `map_op_2` and others. Some of them are only altered if the material name has a certain suffix.

> **Download:**
>
> ##### Metadata Template
>
> This example provides a template that contains the usual metadata for a bus model. It is available for [download](../../_media/modding/tools/modeleditor/bus.import.lua).

### FBX Model Import

To import models, the `.fbx` file format is used. To import a single file, drag and drop it from the file explorer into the Model Editor window. To import multiple files at once, do the same with a folder.

> **Caution:**
>
> As there are some differences in `.fbx` files exported out of software from different vendors, not all files are imported properly. Currently, `.fbx` files from Modo and Blender are supported. See the information about [external tools](../../modding/tools/external.md) to find out more about the available modelling software.

#### File & Folder Names

Each `.fbx` file may contain the 3D model of one level of detail. The `.fbx` files for the different levels of detail are distinguished by the `_lodX.fbx` ending, where X=0 is mandatory and higher levels of detail are optional. To import several files together in a model, they should be placed in the same folder. The name of the folder will be used to determine the folder structure, where the imported resources will be placed in the mod:

- `<folder1>-<folder2>-<mdlname>/` Use hyphens to define the folder hierarchy. This will place the model and its resources in `folder1/folder2/mdlname/mdlname.mdl`.
- `<folder1>-<folder2>+<mdlname>/` If the folder is set up like this, the model will end up in `folder1/folder2/mdlname.mdl`. This can be used for the import of multiple models into the same folder, e.g. for multiple units.

#### Nodes / Meshes

The names of nodes are structured as following:

```
<elementname>[#<comment>]
```

The `<elementname>` is the name of the element that is used for the mesh by default. The element name may not contain `|`, `%` or `#`! Usually, the element names consist of lowercase words seperated with `_`. It will be suffixed with the current LOD automatically, so there is no need to append a `_lodX` manually.

- By default, the meshes will be imported into a `msh` subfolder next to the `.mdl`.
- To reference existing meshes from other models, the element name uses a path with '/' relative to the content root directory, e.g.: `/vehicle/waggon/bay_05/msh/w1`. If the importer can find the mesh at this specified location, it will only be referenced, otherwise the mesh at that position in the folder hierarchy will be generated.
- To reference meshes from another mod, the path is prefixed with `<modid>::` and the other mod needs to be listed as dependency of the current mod in its `mod.json`.

The following examples will have different results:

- `w1` will create a mesh `msh/w1_lodX.msh` in the current mod relative to the directory of the model.
- `/vehicle/waggon/bay_05/msh/w1` will use or create the mesh `vehicle/waggon/bay_05/msh/w1_lodX.msh` relative to the content root of the current mod.
- `::/vehicle/waggon/bay_05/msh/w1` will use the mesh `vehicle/waggon/bay_05/msh/w1_lodX.msh` in the base game `content`.
- `master_mod::/vehicle/waggon/bay_05/msh/w1` will use the mesh `vehicle/waggon/bay_05/msh/w1_lodX.msh` from the mod with the mod id `master_mod`.

If there is a `#` then the rest of the name behind it is ignored. This can be used to mask out `.001` or similar things automatically created by modifiers or to distinguish between different lod level meshes/nodes with the same name.

```
middle_interior
middle_interior#borrowed_from_middle
```

These two will both create a node with mesh `…/middle_interior_lodX.msh` and name `middle_interior`.

> **Tip:**
>
> In Blender, the name of the empty/object is the one that is used for the node name on import. The name of the mesh assigned to the object is the one used for the `.msh` filename.

#### Materials

The names of materials are structured in a similar pattern as the nodes/meshes:

```
<materialname>[|<prefix>][#<comment>]
```

The `<materialname>` works the same as the one for meshes. Referencing existing materials in other mods and both relative and absolute is possible. To reference existing materials, use absolute paths starting with `/` like `/infrastructure/tracks/standard/mat/ballast`. If the importer can find the material at this specified location, it will only be referenced, otherwise the material at that position in the folder hierarchy will be generated with the assigned textures.

The material types that should be used by the importer can be specified by appending `|<shortcode>` which is listed in the tables in the [material type documentation](../../modding/general/resourcetypes/mtl.md#types).

#### Textures

The import process recognizes albedo textures if they:

- have the same name as the material + the suffix from below or
- are assigned to the material in the fbx.

All other textures are recognized based on the same file name as the albedo textures together with the appropriate suffixes:

| Map | Supported Suffixes |
| --- | --- |
| map_albedo | `_alb` or `_albedo` |
| map_albedo_opacity | `_albo` or `_albedo_opacity` |
| map_normal | `_nrm` or `_normal` |
| map_metal_gloss_ao | `_mga` or `_metal_gloss_ao` |
| map_cblend_dirt_rust | `_cdr` or `_cblend_dirt_rust` |
| map_cblend | `_cblend` |
| map_ao | `_uv1_ao` |
| map_id | `_id` or `_emissive_ID_lod1` |
| map_lgt | `_e` |
| map_op_1 | `_op1` |
| map_op_2 | `_op2` |

#### Animations

Imported models will generate `.ani` files from the key frames that are defined in animations assigned to the meshes.

> **Tip:**
>
> In Blender, the animations need to be saved as non linear animations (NLA) to have the correct names. It is important that the strips themselves have the correct name of the animation event. To have multiple strips (one for each animated mesh) for the same animation event, it is possible to use `#` again to clip off the `.001` suffixes.

#### Metadata

Some metadata elements can be (partially) imported with the `.fbx`.

##### Light Sources

[Light](../../modding/general/resourcetypes/mdl.md#lightsourcelist) objects in `.fbx` files can be imported as long as their type is one of the three:

- `Point`
- `Spot`
- `Directional` which will be used as `Parallel` in Transport Fever 3

The following properties will be imported: `lightId` based on the object name, `type` as written above, `transf`, `color`, `strength`, `angleMin` and `angleMax`. The `childId` is derived from the parent to which the light is assigned as a child node in the fbx.

> **Tip:**
>
> In Blender, the three light types are called `Point`, `Spot` and `Sun`. The `strength` is taken from `Intensity`/`Power` and multiplied with factor 100. For the `Spot` type, the `angleMin` is calculated based on `Angle` and `Blend`.

##### Seats

A locator with `|seat_<anim>` or `|seat_crew_<anim>` is used to define the position, rotation and scaling of [seat](../../modding/vehicles/basics.md#seats1) positions. `<anim>` needs to be replaced by the name of one of the supported character animations `idle`, `sitting`, `driving_upright`, `driving`. If there are meshes attached to the node, they will be removed and not be present in the imported model.

##### Draft Animals

Similar to the seats, it is possible to set locations for draft animals with `|draft_animal_<mdlreference>[(<colorconfigindex>)]`. The `<mdlreference>` is a fully qualified reference to an existing `.mdl`. Optionally, it is possible to append a specific index for a color config behind the model reference. A valid example would be `something|draft_animal_mymod::/animal/draft_horse/draft_horse.mdl(2)#something`. This would pick the second color config of the `draft_horse.mdl`.

##### Particle Emitters

A locator with `emitter` in the name is considered as [particle emitter](../../modding/general/resourcetypes/mdl.md#particlesystem). The following properties are imported: `particleId` as the complete name before the `#` comment suffix, `position` and `velocity` based on the scale along x axis. If the name contains `smoke_bright` or `smoke_dark` the properties `colorOverLifetime`, `frequency`, `lifeTime` and `sizeOverLifeTime` are set with fitting standard values.

##### Bounding Box, Extent & Collider

A mesh named with `|bounding_box` will be used to define the size of the [bounding box](../../modding/general/resourcetypes/mdl.md#bounding_box) for the model. The mesh itself will be removed on import, it’s bounding box will be used for the whole model though.

The same method can be used to set the [extent](../../modding/general/resourcetypes/mdl.md#extent) with `|extent` and a box [collider](../../modding/general/resourcetypes/mdl.md#collider) with `|collider_list`.

##### Labels

A [label](../../modding/general/resourcetypes/mdl.md#label_list) is defined by two locators with `|label` of which one is the child of the other. The parent defines the bottom left corner, the offset to the nested child at the top right corner defines the size of the label. They

1. need to be rotated in the same way.
2. need to lay in the same plane along their x/y axis.
3. need to have the z axis to look forward.

### Bulk Import

To import many models at once, e.g. for bridges and tunnels, it is possible to drag a `.txt` or `.log` file from the file explorer into the Model Editor. It must have the following content:

```csv
Scene;<scenename>
ModRefName;<modid>
DeleteTargetFolders;<False or True>
Path;<path to folder with fbx>
Path;<another path to folder with fbx>
```

It consists of:

- `Scene`, which is an optional tag to memorize from which source file things were exported.
- `ModRefName`, which contains the mod id of the mod where the models shall be imported to.
- `DeleteTargetFolders`, which is an optional flag that allows overwriting all existing files in the mod.
- `Path`, which contains one folder path with `_lod0.fbx`, `_lod1.fbx`… . It is possible to have any number of such lines in the file.

### FBX Construction Data Import

To import construction data, the `.fbx` file format is used. Drag and drop it from the file explorer into the box of the option window Im-/Export tab.

> **Caution:**
>
> As there are some differences in `.fbx` files exported out of software from different vendors, not all files are imported properly. Currently, `.fbx` files from Modo and Blender are supported. See the information about [external tools](../../modding/tools/external.md) to find out more about the available modelling software.

#### Target Construction

The `*.fbx` file needs to have `Empty` nodes on top level that point to the correct `*.script` file. The reference is written in the name, e.g. `/industries/brewery/brewery.script`.

This `*.script` file needs to have the following lines:

```lua
...
--Begin Generated
 
--End Generated
...
```

Anything between these two lines will be replaced on import.

#### Hierarchy

Depending on the used util, different top levels are used, e.g. `base`, `static` and `level1`. They are imported from `Empty` nodes with the name `<name>.id`. Optionally, it is possible to append a comment with `#<comment>` which will be ignored for the import.

All the other elements described below are nested as children of these top level nodes.

#### Collider & Terrain Alignment

The collider of the construction is defined with a `mesh` node with the name `collider.curve[#comment]`.

To define the geometry for the terrain alignment, you can use `mesh` nodes with the names:

- `less.mesh[#comment]` for the mesh that defines the upper limit for the terrain.
- `greater.mesh[#comment]` for the mesh that defines the lower limit for the terrain.
- `equal.mesh` for the mesh that defines the exact terrain alignment.

#### Set Dressing

The position, scale and rotation of models can be defined by adding `mesh` nodes with the name `<mod>::<pathToMdl>/<name>.mdl[#comment]`. The properties of these nodes are taken for the transformation of the models.

There are predefined groups of random assets in the `/scripts/construction/asset_util.tl`. These can be referenced with `<key>.grp`.

To synchronize the randomization of multiple elements, it is possible to set a `seed(<number>`, e.g. `seed(123)|era_a_garden_chair.grp`.

By default, the models will adjust their z coordinate according to the terrain at their position. To enforce the height relative to the construction origin, it is possible to add an `align` tag: `align|<mod>::<pathToMdl>/<name>.mdl[#comment]`.

It is possible to randomly skip set dressing models. This is done by using the keyword `ignore(<propability>)`, e.g. `ignore(50)|::/assets/buildings/ind/boxes/wood_box_long.mdl#` will show the wooden box in 50% of the cases.

If these three properties shall be applied on several models or group instances, it is possible to add an `Empty` node with the property, e.g. `align[#comment]` and nest all affected instances as children.

> **Download:**
>
> ##### Construction Data Example
>
> An exemplaric `*.fbx` file containing construction data is available for [download](../../_media/modding/tools/modeleditor/construction_data_example.zip).
