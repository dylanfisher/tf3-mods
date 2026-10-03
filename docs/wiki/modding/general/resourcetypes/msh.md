---
title: Mesh Definition (.msh/.msh.blob)
page_id: modding:general:resourcetypes:msh
source: https://wiki.transportfever3.com/doku.php?id=modding:general:resourcetypes:msh
---

# Mesh Definition (.msh/.msh.blob)

The mesh files contain the threedimensional mesh information known as the actual 3D model. A mesh can consist of more than one submesh. This data is stored in a binary blob file that contains all the positions, orientations etc. of every vertex, edge and face. To tell the engine where the right information is stored in the binary blob file, there is a second file with indices.

Both files share the same name, but the blob file has `.blob` as a suffix. For example, if the index file is called `cube_lod_0.msh`, then the blob file is called `cube_lod_0.msh.blob`.

## .msh Index File

This text based index file can be edited with any text editor. It returns a struct with two parts:

```lua
function data()
return {
  subMeshes = { ... }, -- list of submesh references
  vertexAttr = { ... }, -- list of global attributes
}
end
```

`subMeshes` contains another struct for every submesh of this mesh. Each submesh can use a different material, thus the number of submeshes has to be equal to the number of materials assigned in the `.mdl`.

### Vertex Attributes

The 3D information is described by various `vertexAttributes` stored in the blob. These attribute types are:

- attrOffsetLOD
- normal
- position
- positionAmbient
- offset
- tangent
- jointWeights
- uv0
- uv1

Not all meshes use all of these attributes.

## .msh.blob Data Files

The actual 3D information is stored in the blob files. The file is divided in two sections:

### Section 1: Attribute Store

Every 4 byte are one float value. The index file informs the engine where which type of attribute is stored (offset), how many floats form an information item (numComp) and how many information items are there per attribute (count).

### Section 2: Submesh Indices

The submeshes are representated by reference lists starting at an offset as well with a given number of elements (count). The indices refer to information items from section 1.
