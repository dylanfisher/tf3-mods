---
title: Construction Templates
page_id: modding:constructions:templates
source: https://wiki.transportfever3.com/doku.php?id=modding:constructions:templates
---

# Construction Templates

It is possible that a `.con.lua` construction file can be used by several construction templates that are offered to the player with different properties and icons. They can be defined in `metacon.lua` files. They contain the same basic metadata as normal constructions:

```lua
...
return {
  {
    type = "DYNAMIC",
    availability = { ... },
    description = { ... },
    menuCategory = { ... },
    ...
    createTemplateScript = {
      fileName = "airfield.script@createTemplateFn",
      params = { }
    },
  },
  ...
}
```

The `createTemplateScript` reference points to a script that provides the actual content of the template. The function is called when the template shall be used:

```lua
...
createTemplateFn(captureParams, params)
  ...
  return result
end
...
```

The `capturedParams` contains the parameters forwarded with the script reference in the `.con.lua`. The `params` contains the following parameters:

- `paramX` and `paramY` are from the keyboard controls. See the [basics](../../modding/constructions/basics.md#models) to find out more about them.
- `seed` is a number that can be used for randomization purposes. It increases whenever a construction is set or proposed.
- `year` is the current year.
- `templateIndex` is the id of the template that was used for this function call.
- All custom parameters of the `data.params` struct in the current asset construction template.

The function returns a `constructions` list of the following pattern:

```lua
{
  constructions = {
    {
      modules = {  
        [10001000] = "airfield_main_building.module",  
        [10002004] = "airfield_hangar.module",  
        [10070002] = "airfield_passenger_terminal.module"
      },
      constructionFileName = "airfield.con"
      transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 },
      params = params
    }
  }
}
```

Each entry has a list of module slots and assigned `modules` and a reference to the `constructionFileName` that shall be used. With the `transf` property, it is possible to offset the construction relative to the origin of the template. If unset, the same location is used. The `params` property allows to forward custom parameters to the construction. If unset, the `params` of the template are forwarded.

For non-modular constructions with templates, the function may simply use an empty list `{}` for `modules`.
