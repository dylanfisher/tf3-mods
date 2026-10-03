---
title: Mod Definition
page_id: modding:general:moddefinition
source: https://wiki.transportfever3.com/doku.php?id=modding:general:moddefinition
---

# Mod Definition

Mods are folders containing resource files similar to the base game and some additional metadata files to describe and define the mod:

```
  mods/
    urbangames_example_mod         (1)
      _metadata/                   (2)
        modinfo.json               (3)
        description.html           (4) (optional)
        0.png                      (5) (optional)
        ...
      content                      (6)
        mod.script.tl              (7) (optional)
      mod.json                     (8)
      strings.json                 (9) (optional)
```

1. The directory name has no functional relevance. Best practice is to name the mod in the form `<author>_<modname>`. It may not contain characters other than `A-Z`, `a-z`, `0-9`, `_` and .
2. The `_metadata` folder contains the metadata used to describe the mod in the Mod Browser. It contains:
3. The `modinfo.json` file contains all descriptive metadata (like name, description, tags, …). See below for more information.
4. The `description.html` is an optional file for the description which is shown in the ingame mod browser and on mod.io.
5. PNG files with `<number>.png` are used for the Mod Browser and preview. The `0.png` will be used in the grid, the others in the detail view. The images should have 1920x1080 pixels.
6. All the game resources of the mod like vehicles, scripts, … are located in the `content` folder. It is best practice to use a structure similar to the base game.
7. The `mod.script.tl` contains the executable script functions referenced from mod.json. See [here](../../modding/general/modscripts.md) for further information.
8. The `mod.json` contains the technical definition of the mod, most important its id. See below for further information.
9. The `strings.json` file contains translations of the mod’s texts. See below for further information.

## mod.json

The `mod.json` file contains the most important technical properties to define the mod. It is written in [JSON snytax](https://en.wikipedia.org/wiki/JSON) and its basic structure is as follows:

```javascript
{
    "modId": "urbangames_example_mod",
    "revision": 1,
    "severityAdd" : "Critical",
    "severityRemove" : "Critical",
    "visible" : true,
    "cosmetic" : false
}
```

The `modId` property is a string that is used to identify the mod. It may not contain characters other than `a-z`, `0-9` and `_`. It is best practice to name the mod in the form `<author>_<modname>`. The mods are identified based on this id and independent of its location of installation, e.g. a mod in the staging area and in the directory for manually installed mods is considered as the same if the `modId` is the same. If more than one installed mod has the same ID, the game prefers them in following order:
Staging Area > Manual Installation Directory > Subscribed Mods.

> **Tip:**
>
> While the folder name has no functional meaning in Transport Fever 3, it is recommended to keep it in sync with the `modId`. In comparison to previous games of the Transport Fever series, there is no major version like `_3` at the end of the `modId`.

The `revision` integer is used to indicate updated versions of the mod. It is also shown in the ingame mod detail pages. Whenever a new update of the mod is published, this number should be increased. In case of an update that is not compatible with the previous version of the mod, it is recommended to change the mod id and publish the new version as an independent mod to not break user savegames with the update of the mod.

To inform players of expected behavior when adding mods to or removing mods from existing savegames, the `severityAdd` and `severityRemove` properties are used. There are three possible values:

- `None` may be used when adding or removing may not harm the savegame in any way, e.g. when only doing cosmetic adjustments.
- `Warning` shall be used when some impacts, e.g. missing vehicle models, are expected, but the savegame will not get into an unstable state.
- `Critical` is used for anything that might result in broken savegames, e.g. missing cargo types.

If the properties are unset, they behave like `severityAdd` is set to `None` and `severityRemove` is set to `Warning`.

To hide mods from appearing in the list of mods, it is possible to set `visible` to `false`. The default value if emitted is `true`. This might be relevant for mods that provide content for a campaign savegame and should not be used in other free games.

Purely cosmetic mods can set the `cosmetic` property to `true` to ensure that achievements can still be earned if only cosmetic mods are used. It is up to the modder to judge if a mod can be considered as cosmetic. Anything that has an impact on the simulation, e.g. faster vehicles, higher capacities or different production output should not be considered as cosmetic.

### Dependencies & Incompatibilities

Beyond the two properties above, it is possible to define dependencies and incompatibilities to other mods. Dependencies are used to reference mods that are required to use this mod properly, e.g. a base mod containing a vehicle that you provide a repaint skin for. If a mod is not compatible, due to conflicting behavior, it is possible to warn the player by referencing it as an incompatibility.

The user will be informed in both cases while activating mods. Dependency mods will be activated before the dependent mod if needed and dependencies that are not yet installed will be offered to be downloaded. There will be a warning if a user tries to start a game with missing dependencies or active incompatible mods.

```javascript
{
    ...
    "dependencies": [
        {
            "mod": {
                "modId": "testing_mod_params",
                "revisionMin": 1,
                "revisionMax": 1
            },
            "modInfo": {
                "displayName": "Testing Mod Params",
                 "url": "http://www.urbangames.com"
            },
            "loadBefore": false,
            "optional": false
        }
    ],
    ...
}
```

Each dependency has four properties:

- `mod` is used to identify the other mod. It consists of three values:

  - `modId` is the modId as defined in the mod.json of the other mod.
  - `revisionMin` is an optional lower revision limit, if earlier version of the other mod are not yet providing what is needed. Omitting this parameter or setting it to `-1` results in no lower limit.
  - `revisionMax` is an optional upper revision limit, if only older versions of other mods are compatible. If omitted or set to `-1`, any (newer) version is considered as compatible. Usually this is not required as mod updates should be backward compatible anyway.
- `modInfo` contains info that is displayed when the dependency mod is not installed, so players can see what they need to install:

  - `displayName` is shown in the Mod Browser.
  - `url` is an optional url to reference a location where the mod can be downloaded manually, e.g. from 3rd-party sites.
- `loadBefore` is an optional bool that needs to be set to `true`, if it is necessary that the dependency mod is loaded before this mod. If unset, it is considered as `true`.
- `optional` is an optional bool that can be set to `true` to specify that the dependency is not a must have, but is recommended to be used to have the full functionality available. If unset, it is considered as `false`.

```javascript
{
    ...
    "incompatibilities": [
        {
            "mod": {
                "modId": "urbangames_sandbox",
                "revisionMax": 1,
                "revisionMin": 1
            }
        }
    ],
    ...
}
```

For incompatibilities, the `mod` property is defined as above with the dependencies.

### Mod Parameters & Scripts

Mods may have parameters to customize the user experience depending on the user preferences. The selected parameters can be used in the scripts that each mod can provide. See the page about these [parameters and scrips](../../modding/general/modscripts.md) for more details.

## modinfo.json

The display name and description for the mod browser are configured in the `modinfo.json` file in the `_metadata` folder:

```javascript
{
    "name": "MOD_NAME",
    "summary": "MOD_SUMMARY",
    "description": "MOD_DESCRIPTION",
    "localization" : {
        "en": {
            "name": "Wiki Example Config Change",
            "summary": "Vehicle brake intensity change",
            "description": "Vehicles brake stronger or weaker based on the configured parameter."
        },
        "de": {
            "name": "Wiki-Beispiel Konfigurationsänderung",
            "summary": "Fahrzeug-Bremsintensitätsänderung.",
            "description": "Fahrzeuge bremsen stärker oder schwächer, abhängig vom eingestellten Wert."
        }
    },
    "authors": [
        {
            "name": "Urban Games",
            "role": "CREATOR"
        }
    ],
    "tags": [
        "Script Mod"
    ],
    "dependencies": [
        "5499706"
    ],
    "url": ""
}
```

The three important attributes are:

- `name`: The display name of the mod. This name should not be longer than 32 characters and may not contain line breaks.
- `summary`: This brief summary of the mod content is shown as a tooltip when hovering over a mod in the mod browser. It may not be longer than 100 characters and may not contain line breaks.
- `description`: This may be a longer description text and supports line breaks. It is ignored if a seperate description.html is available.

To localize these texts, it is possible to provide a set for some language in the `localization` attribute. The default ones are used for all other languages. For a list of possible language codes, have a look at the information on the [localization](../../modding/misc/localizations.md) page.

> **Caution:**
>
> As mod.io currently does not support multiple languages, the different languages are concatenated to a longer description which is uploaded for the mod browser. Only the english title is uploaded. The support of multiple languages is planned to arrive until Q2/2027.

The `authors` list contains a list of authors with their roles.

The `tags` list may contain one or more of the officially supported tags. See the [list of supported tags](../../modding/general/modtags.md) for more details.

To automatically link to the correct dependencies on mod.io, the `dependencies` list contains the mod.io internal modIds. They can be found in the info boxes on the right side of a mod detail page on mod.io.

> **Note:**
>
> When a dependency shall be removed, removing from the list above alone is not sufficient. This has to be manually updated on mod.io.

The optional `url` attribute may contain a link to a place where more info about this mod can be found, e.g. a github repository or website. Please be aware that it is not possible to access this url from ingame when playing on console. Hence the description should already contain every relevant info for using the mod.

> **Note:**
>
> Currently, the URL is not shown ingame, but it is accessible for players on mod.io.

## strings.json

To provide support for multiple languages, a `strings.json` can be provided in the mod:

```javascript
{
	"en" : {
		"brake_intensity_name" : "Brake Intensity",
		"brake_intensity_tooltip" : "Adjust the global brake intensity."
	},
	"de" : {
		"brake_intensity_name" : "Bremsintensität",
		"brake_intensity_tooltip" : "Passen Sie die globale Bremsintensität an."
	}
}
```

This file contains translations for strings, specified as a list of key/value pairs for each language. If a key does not exist for a given language, the English text is used. If this isn’t defined neither, the key itself is displayed. For a list of possible language codes, have a look at the information on the [localization](../../modding/misc/localizations.md) page.
