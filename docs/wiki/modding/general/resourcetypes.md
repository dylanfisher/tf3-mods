---
title: Resource Types & Structure
page_id: modding:general:resourcetypes
source: https://wiki.transportfever3.com/doku.php?id=modding:general:resourcetypes
---

# Resource Types & Structure

In Transport Fever 3, the game resources are not distinguished by their folder, but by their individual file endings.

## File Endings

The game resources as well as the mod resources consist of code files (scripts, configurations, …), 3D files, texture files and soundfiles. The following table contains an overview over all used file endings in Transport Fever 3. Below are additional infos for the most common ones.

| Category | Resource | File Endings |
| --- | --- | --- |
| General | Models | `.mdl` |
|  | Meshes | `.msh`, `.msh.blob` |
|  | Materials | `.mtl` |
|  | Animations | `.ani` |
|  | Textures | `.dds`, `.tga`, `.hdr` |
|  | Icons | `.tga` |
|  | Transformators | `.trf.lua` |
|  | Sound Sets | `.snd.lua` |
|  | [Sound Effects](../../modding/misc/soundeffects.md) | `.wav` |
| Configurations | Climates | `.clima.lua` |
|  | Terrain Generators | `.gen.lua` |
|  | Economies | `.eco.lua` |
|  | Environments | `.env.lua` |
|  | Terrain Materials | `.tmat.lua` |
|  | Grass | `.grass.lua` |
| Scripts | Generic Scripts/Utils | `.lua`, `.tl` |
| Scripts | Script Resources | `.script.lua`, `.script.tl` |
|  | Teal Definitions | `.d.tl` |
|  | Game Scripts | `.gs.lua` |
|  | Campaigns | `.campaign.lua` |
|  | Missions | `.mission.lua` |
| Content | Constructions | `.con.lua` |
|  | Modules | `.module.lua` |
|  | Ground Textures | `.gtex.lua` |
|  | Auto Ground Textures | `.agt.lua` |
|  | Track/Street Templates | `.street_template.lua` |
|  | Track/Street Styles | `.street.lua` |
|  | Bridges | `.bridge.lua` |
|  | Tunnels | `.tunnel.lua` |
|  | Railroad Crossings | `.rcr.lua` |
|  | Traffic Lights | `.trl.lua` |
|  | Cargo Types | `.cargo.lua` |
|  | Cargo Formats | `cmf.lua` |
|  | Cargo Classes | `.cargoclass.lua` |
|  | Multiple Units | `.mu.lua` |
| Rendering | [Shaders](../../modding/misc/shaders.md) | `.fs`, `.tesc`, `.tese`, `.vs`, `.gs`, `.glsl` |
|  | Render Descriptors | `desc` |
|  | Render Programs | `.prog` |
|  | Techniques | `.tec` |
|  | Material Properties | `.prop` |
|  | Material Types | `.mat` |
| Misc | Stylesheets | `.css.lua` |
|  | Playlists | `.plist.lua` |
|  | Songs | `.ogg` |
|  | Layer Nodes | `.node.lua` |
|  | Names | `.names.lua` |
|  | [Locale](../../modding/misc/localizations.md) | `.lang.lua` |
|  | Generic Resources | `.res.lua` |

## File Names & References

> **Caution:**
>
> All text files (models, meshes, scripts etc.) should be encoded in **UTF-8 without BOM**. For file and folder names the following conditions apply:
>
> - Only use lower case letters `a-z`, underscore `_`, dash `-` and numbers `0-9`.
> - Do **not** use upper case letters and blank spaces.
> - Keep folder and file names short

To reference another file, it is possible to either reference relative to the current file or absolute from the base game `content` directory or the root of a mod:

```lua
"/assets/<...>/filename.mdl" -- absolute path
"tex/logo_mga.dds" -- path relative to current file
```

To reference files in another mod than the current one or from the base game, the whole path is prefixed:

```lua
"/assets/<...>/filename.mdl" -- absolute path in the current mod
"::/assets/<...>/filename.mdl" -- absolute path in the base game
"mod_id::/assets/<...>/filename.mdl" -- absolute path in mod ''mod_id''
 
"tex/logo_mga.dds" -- path relative to current file in the current mod
"::tex/logo_mga.dds" -- path relative to current file but in the folders of the base game
"mod_id::tex/logo_mga.dds" -- path relative to current file but in the folders of the mod ''mod_id''
```

> **Tip:**
>
> It is not possible to use `../` to reference to the parent directory.

## Static Resources & Scripts

In general, the lua and Teal based static resources consist at least of the `data()` function that is executed once when the game loads all the resources at the start of a savegame:

```lua
function data()
return {
  -- content of data struct depending on type of configuration
}
end
```

Beside the static metadata file, many of the resources like constructions have a dynamic script part. The static resource file has a reference to the script file like in the following example:

```lua
...
updateScript = {
  fileName = "underground_station.script@updateFn",
  params = {
    key = value,
  }
},
```

The `fileName` follows the pattern: `resourceRef@functionKey` where `resourceRef` may be a full path as described above. The `functionKey` refers to a key in the result of the `data()` function in that script file.

The `params` struct is injected as the first parameter into these referenced functions and is commonly called `captureParams`:

```lua
function data()
return {
  updateFn = function(captureParams, params)
    ...
  end,
  ...
}
end
```

## 3D Files

The model resources consist of the following file types:

- `.mdl` for model definitions
- `.msh` for mesh index files
- `.msh.blob` for mesh 3D data
- `.mtl` for material definitions
- `.ani` for extracted animations

### .mdl for Model Definitions

Model files are a special kind of configuration file as well, thus their structure is similar with a `data()`-function.

```lua
function data()
return {
  boundingInfo = { ... }, -- optional bounding box used e.g. for render borders
  collider = { ... },     -- optional collider for collision calculation
  lods = { ... },         -- geometric information for 3D data and textures
  metadata = { ... },     -- metadata depending on model type
  version = 2,            -- required to distinguish from the old Transport Fever 2 model format
}
end
```

Detailed information about bounding boxes, colliders and the lod tree can be found in the [model documentation](../../modding/general/resourcetypes/mdl.md).

### .msh / .msh.blob for Mesh Data

The mesh files contain the threedimensional mesh information known as the actual 3D model. A mesh can consist of more than one submesh. This data is stored in a binary blob file that contains all the positions, orientations etc. of every vertex, edge and face. To tell the engine where the right information is stored in the binary blob file, there is a second file with indices. This text based file can be edited with any text editor.

```lua
function data()
return {
  subMeshes = { ... },
  vertexAttr = { ... },
}
end
```

Both files share the same name, but the blob file has `.blob` as a suffix. For example, if the index file is called `cube_lod_0.msh`, then the blob file is called `cube_lod_0.msh.blob`. Read more about meshes and the internal structure of these files in the [mesh documentation](../../modding/general/resourcetypes/msh.md).

### .mtl for Material Definition

Materials contain the reference to texture files. The basic structure is a `data()` function as well.

```lua
function data()
return {
  order = 0, -- used to determine rendering order between materials of same type
  params = { ... }, -- parameters vary depending on type
  type = "PHYSICAL_NRML_MAP",
}
end
```

There are many different material types available. For a full overview of available types, see the [material documentation](../../modding/general/resourcetypes/mtl.md).

### .ani for Extracted Animations

If animations are extracted from `.mdl` files to external files, they are located in `.ani` files.

These files contain a `data()` function as most of the other resources:

```lua
function data()
return {
  times = { 0, ... }, -- timestamps in milliseconds from 0 as begin of animation 
  transfs = {
    { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, }, -- transformation matrix for each timestamp
    ...
  },
}
end
```

The number of timestamps must equal the number of matrices!

## Texture Files

The preferred texture format for Transport Fever 3 is `.dds` with compression and mip maps. In some rare cases and for ui elements the `.tga` format is files and compressed `.dds` files.

### DDS (DirectDraw Surface)

The `.dds` textures are compressed and have a smaller filesize, reducing the memory usage.

The common compression types supported by Transport Fever 3 are:

- BC1/DXT1 with binary alpha information
- BC2/DXT3 with 4bit alpha
- BC3/DXT5 with interpolated alpha
- BC7/DX11 with interpolated alpha
- BC5/3Dc for normal maps
- BC4/R8/L8 for m8 bit greyscale masks

While DXT1 has the smallest file size, it is only suitable where no transparency or full transparency (either 100% opaque or 100% transparent) is needed.

For normalmaps, the `3Dc ATI2A2XY` standard is required. See [external tools documentation](../../modding/tools/external.md) for more information on tools supporting these compressions.

To ensure compatibility with ATI and Intel graphic cards, it is important that the texture resolutions use multiples of 2 for the sizes: 16, 32, 64, 128, 256, 512, 1024, 2048, 4096.

Keep in mind that larger textures occupy a lot more memory space. Therefore only use large textures when absolutely necessary.

### TGA (TARGA)

`.tga` files usually are used for UI elements and smaller graphics. To provide graphics with high resolution for 4k-monitors, the ui icons usually are provided in double scale, meaning a 24 px large icon is actually 48 px large in the file. The file name ends with `@2x.tga` in that case.

> **Caution:**
>
> As `.tga` filesize is greater than the file size of a similar image with compressed `.dds`-format, it is not recommended to use `.tga` for model textures.

## Directory Structure

While in most cases there is no mandatory directory structure for mods, it is recommended to use a similar directory structure as used in the base game of Transport Fever 3. Below is a description of all relevant folders inside of the `content` directory of Transport Fever 3. Only those which are relevant for a specific mod need to be included in a mod.

The directories in Transport Fever 3 are grouped by game element, not by filetype. Thus the folders contain 3D models, sounds and additional script files all in one place:

| Folder | Description |
| --- | --- |
| assets | 3D models without special functionality. Used to decorate other game elements, e.g. town buildings and industries |
| base | Important files for the basic functionality of the game |
| buildings | 3D models and construction files for town buildings |
| cargos | 3D models, icons and definitions for cargo types |
| characters | 3D models for sim people and drivers |
| climates | metadata and generator files for climate zones |
| depots | 3D models and construction files for [depots](../../modding/constructions/types.md#depots) and maintenance buildings |
| economy | economy definition files |
| gui | scripts and icons for the user interface |
| industries | 3D models and construction files for [industries](../../modding/constructions/types.md#industries) |
| infrastructure | 3D models and definition files for [tracks](../../modding/infrastructure/tracksstreets.md#tracks), [streets](../../modding/infrastructure/tracksstreets.md#streets), [bridges](../../modding/infrastructure/bridgestunnels.md#bridges), [tunnels](../../modding/infrastructure/bridgestunnels.md#tunnels), [signals](../../modding/infrastructure/signals.md#signals), [railroad crossings](../../modding/infrastructure/railroadcrossings.md), [traffic lights](../../modding/infrastructure/trafficlights.md) and [edge addons](https://wiki.transportfever3.com/doku.php?id=modding:edgeaddons) |
| landmarks | 3D models and construction files for [landmarks](../../modding/constructions/types.md#landmarks) |
| mission | scripts for campaign mechanics |
| music | music tracks for the background music |
| names | lists of [people, street and town names](../../modding/misc/names.md) |
| scripts | generic scripts used in various places |
| stations | 3D models and construction files for [stations](../../modding/constructions/types.md#stations) of all types of transport |
| terrain | textures and configurations of [terrain materials](../../modding/environment/terrainmaterials.md) used by terrain generation as well as brush tools |
| vehicle | 3D models for all types of [vehicles](../../modding/vehicles/basics.md) and configurations of [multiple units](../../modding/vehicles/types.md#multiple_units) |
| warehouses | 3D models and construction files for [warehouses](../../modding/constructions/types.md#warehouses) |
