---
title: External Tools
page_id: modding:tools:external
source: https://wiki.transportfever3.com/doku.php?id=modding:tools:external
---

# External Tools

Every modder has individual preferences which programs he likes to use for modding. Here are some recommendations and hints on tools that are often used in the community. The list below is not exclusive, there are many other compatible programs.

## Scripting

The various [text based](../../modding/general/resourcetypes.md#code_files) resouce types can be edited with almost any text editor. This reaches from *Microsoft Editor* to integrated development environments like *Eclipse*. Two commonly used text editors are:

- **Visual Studio Code** is afree text editor that runs under Microsoft Windows, MacOS and Linux. It can be downloaded for free at [code.visualstudio.com](https://code.visualstudio.com/).
- **Notepad++**  is another free text editor for Microsoft Windows. It can open multiple tabs in several windows and has builtin Lua syntax highlighting. It can be downloaded for free at [notepad-plus-plus.org](https://notepad-plus-plus.org/).

> **Tip:**
>
> ### VS Code Setup
>
> To ease development of mods with VS Code, it is recommended to follow this setup guide.
>
> #### Install Teal & Extensions
>
> TEAL is an augmentation for LUA that provides additional features. When using TEAL, autocompletion and compile time type checking is possible also in LUA. Download it from the [official repository](https://github.com/teal-language/tl).
>
> There are several helpful extensions for autocompletion and syntax highlighting:
>
> - [Lua by sumneko](https://marketplace.visualstudio.com/items?itemName=sumneko.lua)
> - [Teal by Patrick Desaulniers](https://marketplace.visualstudio.com/items?itemName=pdesaulniers.vscode-teal)
>
> After installing the Teal extension, go to the settings of the extension and configure the path to the Teal executable.
>
> #### Preparing Development Workspace
>
> To create the development workspace, start the [Model Editor](../../modding/tools/modeleditor.md) once. It creates the following files in the Staging Area:
>
> - `tlconfig.lua`
> - `workspace_def.lua`
> - `.vscode/extensions.json`
>
> If this did not work, you can manually copy them from `<tf3_install_folder>/dev-workspace` and adjust `tlconfig.lua` to have proper folders set.
>
> To test the workspace setup, create an example script in your mod called `example.tl` and paste
>
> ```lua
> local function myFirstTealFunction()
> 	log.warning("Hello World!")
> end
> ```
>
> You should be able to navigate to the definition of the `warning` function via CTRL and click or F12 or right click → Go To Definition.
>
> #### Adding your own Teal definitions
>
> To add your own definitions, create `*.d.tl` files in your mod and add the folder of your mod in the `tlconfig.lua` and `workspace_def.tl`.
>
> As a trial run, you may
>
> 1. uncomment `– "example_mod_1"` from both: `tlconfig.lua` and `workspace_def.tl`
> 2. add a file called `example_mod_1/example_mod_1.d.tl` with the following content:
>
> ```lua
> global record MyFirstRecord
> 	myFirstField : string
> end
> ```
>
> Now you should be able to use it in the `example.tl`:
>
> ```lua
> local function myFirstTealFunction(aRecord : MyFirstRecord)
> 	log.warning("Hello World : " .. aRecord.myFirstField)
> end
> ```

## 3D Modelling

Like with the text editors, there are plenty of available software solutions for 3D modelling.

- **Blender** is a free allround software for 3D modelling, animation, … It supports bone animations too and bake texture maps like for ambient occlusion. Models exported as FBX may be imported with the [model editor](../../modding/tools/modeleditor.md). Blender can be downloaded at [www.blender.org](https://www.blender.org/).
- **Modo** is a payware 3D modelling software by Foundry. It's the software used by Urban Games to develop the content for Transport Fever 3. The FBX import into the model editor is suited for FBX files exported by Modo. As Foundry stopped the support for Modo, it is not recommended to use it for new mod projects anymore.
- **3ds Max** is a payware 3D modelling software by Autodesk. See [www.autodesk.de/products/3ds-max/overview](https://www.autodesk.de/products/3ds-max/overview) for more information.
- **Maya** is the other payware 3D modelling software by Autodesk. See [www.autodesk.de/products/maya/overview](https://www.autodesk.de/products/maya/overview) for more information.
- **Cinema4D** is a payware 3D modelling software by Maxon. See [www.maxon.net/de/produkte/cinema-4d/](https://www.maxon.net/de/produkte/cinema-4d/) for more information.

As the payware tools have very expensive licenses, it's not recommended to invest in them if you are not an advanced user. Students may get a discount or free license though as long as they do not use the software for professional and commercial projects.

There are other tools that are used regularily. These have some problems regarding the compatibility to Transport Fever 3 that are described below:

- **Sketchup** is a 3D modelling software that many prefer because of its ease of use. However, it does not offer the possibility to map the 3D model itself, so it is not possible to import it directly into Transport Fever 3. The models must first be mapped in another program. In addition, cylindrical objects are often exported very finely, so that the models have high tris numbers.
- **Solidworks** and similar parametrized CAD modelling tools are especially popular with people in the CAD field. They offer the possibility to create systematic models. However, they have the same problems as Sketchup, i.e. it is usually not possible to map the model and curves are implemented very finely.

## Texturing

Beside the modelling tools, there are various texturing tools. These have different advantages and disadvantages and many artists stick to tools they are familiar with.

- **GIMP** is a freeware image editing software that is commonly used. It is capable of loading some Photoshop files too. You can find it on [www.gimp.org](https://www.gimp.org/).
- **Paint.NET** is a freeware image editing software that originally started as an alternative to the classical Microsoft Paint. It can be downloaded at [www.getpaint.net](https://www.getpaint.net/).
- **Photoshop** is a payware software for professional 2D artists by Adobe. It is available as part of the Adobe Creative Cloud or separate but not with a perpetual license. Find more information about Photoshop at [www.adobe.com/products/photoshop.html](https://www.adobe.com/products/photoshop.html).
- **Paint Shop Pro** is a payware software by Corel. It can be bought with a perpetual license at [www.paintshoppro.com](https://www.paintshoppro.com/).
- **Substance Painter** is a payware software for professional 3D artists originally developed by Allegorithmic and now maintained and developed further by Adobe. It is used for texturing at Urban Games. In contrast to the software above, the textures can be painted directly on the 3D model. Interactive texture materials can be used with lots of modifiers to accommodate various needs. Get more information at [www.adobe.com/products/substance3d-painter.html](https://www.adobe.com/products/substance3d-painter.html). A perpetual lifetime license can be bought on [Steam](https://store.steampowered.com/app/4329260/Substance_3D_Painter_2026/).

### DDS Export

To export DDS files, a plugin or standalone program might be needed. Here is a list of common ones. Be aware that their internal compression algorithms may differ resulting in slightly different output.

- Both **Gimp** and **Paint.net** have included support for exporting DDS textures.
- **NVIDIA Texture Tools** require a NVIDIA CUDA capable GPU. They are available standalone as well as plugin for Adobe Photoshop. Find more information at [developer.nvidia.com/nvidia-texture-tools-exporter](https://developer.nvidia.com/nvidia-texture-tools-exporter).
- **Intel Texture Works** is a Photoshop plugin made by Intel. You can find more information at [software.intel.com/.../intel-texture-works-plugin.html](https://software.intel.com/content/www/us/en/develop/articles/intel-texture-works-plugin.html).
- **Compressonator** is an AMD based GUI and command line tool that is now hosted on GitHub. See [github.com/GPUOpen-Tools/compressonator](https://github.com/GPUOpen-Tools/compressonator) for more information.

## Custom Tools for Transport Fever 3

There are fanmade tools available that support the development of mods for Transport Fever 3. Some common ones are:

- An interactive transformation matrix calculator by Xanos can be found at [transportfever.net](https://www.transportfever.net/lexicon/index.php?entry/77-transformationsmatrix/).
