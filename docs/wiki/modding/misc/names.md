---
title: Names
page_id: modding:misc:names
source: https://wiki.transportfever3.com/doku.php?id=modding:misc:names
---

# Names

In Transport Fever 3, there are name lists for people, towns and street stops. A name set is defined in a `.names.lua` file:

```lua
function data()
return
  {
    name = _("English"),
    personNamesScript = {
      fileName = "/names/names.script@personNameScriptFn",
      params = { ... },
    },
    townNamesScript = {
      fileName = "/names/names.script@townsNameScriptFn",
      params = { ... },
    },
    streetNamesScript = {
      fileName = "/names/names.script@streetsNameScriptFn",
      params = { ... },
    }
end
```

The `name` property defines the display name of the name set in the game settings. Beside that, there is a script reference for each type of names:

## People

The function referenced in `personNamesScript` receives two parameters:

- `captureParams` containing the custom parameters provided next to the reference above
- `params` containing two values:

  - `lang` is the language short handle of the currently selected game language, e.g. `en`.
  - `isMale` is a boolean value to decide whether a male or female name shall be returned.

The expected result is a string containing a name, e.g. `Madeline Lyla`.

The names usually are random combinations of first and last names. A `personnameutil.lua` in the `content/names/` folder contains several lists of name parts which can be referenced and concatenated to form the full names.

## Towns

The function referenced in `townsNameScriptFn` receives two parameters:

- `captureParams` containing the custom parameters provided next to the reference above
- `params` containing two values:

  - `lang` is the language short handle of the currently selected game language, e.g. `en`.
  - `num` is the number of needed town names that shall be returned. If the number is -1, all names shall be returned.

The expected result is a list of strings with length `num` containing town names, e.g. `Adelaide`.

It is recommended to ensure there are no duplicates returned, hence there needs to be a sufficient amount of town names to prevent several towns with the same name on the map.

## Streets

The function referenced in `streetNameScriptFn` receives two parameters:

- `captureParams` containing the custom parameters provided next to the reference above
- `params` containing two values:

  - `lang` is the language short handle of the currently selected game language, e.g. `en`.
  - `num` is the number of needed street names that shall be returned. If the number is -1, all names shall be returned.

The expected result is a list of strings with length `num` containing street names, e.g. `Main Street`.
