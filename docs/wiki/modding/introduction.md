---
title: Introduction
page_id: modding:introduction
source: https://wiki.transportfever3.com/doku.php?id=modding:introduction
---

# Introduction

While the vanilla game of Transport Fever 3 provides the player with a great number of models and content from different regions of the world, some people prefer to extend the variety further by adding more content. Others like to tweak some game mechanics or to alter some configurations to better suite their style of gameplay. The modding support of Transport Fever 3 reaches from the addition of new model content over the altering of existing contents to the scripting possibilities which reach deep into the game mechanics.

It is not recommended to adjust the files in the installation directory of Transport Fever 3! Instead, a mod should be created. From a file system perspective, a mod is simply a directory containing all the necessary data and script files. If you like to setup your own mod, look at the two examples at the bottom of this page or the [mod definition](../modding/general/moddefinition.md) description. Read more for the [syntax](../modding/general/syntax.md) and the [common resource types](../modding/general/resourcetypes.md).

Working mods can be [shared](../modding/general/publishing.md) to other users.

## Typical Use Cases

Below are some typical use cases for mods with varying degrees of difficulty. Please note, that mods are not restricted to one of these possibilities, but can be a combination of more than one or go beyond them in many ways.

### Repaints of existing vehicle models

For many vehicles there are lots of color variations out there in the real world. As somebody who is not familiar with 3D modelling, this kind of mod might be a way to get into vehicle modding. Further information on this topic can be found in the [manual for vehicle repaints](../modding/vehicles/repaints.md).

### New vehicle or asset models

Both vehicles as well as static models like decorative assets mainly focus on 3D modelling and texturing. The amount of coding needed to get those contents into the game are very limited, thus it's a good entry point for interested people with less coding affinity. People interested in vehicle modding can find some details in the [vehicle modding section](../modding/vehicles/basics.md). For assets, a simple example can be found below.

### Add new constructions with parameters

As single static models might not cover every needs for decoration, the possibility to add parameters is one step further into scripting. Models might get rotated or scaled, different models get added depending on the users choice, … the possibilities are almost endless, but the needed information can be found in the [construction section](../modding/constructions/basics.md).

### Change config values by mod

A lot of basic configurations can be altered by simple mods. The amount of script code needed is very limited and the 3D models and textures do not need to be touched. An example for this type of mod can be found below.

### Rebalance existing models

If desired, certain or all vehicles can be adapted in the same way, e.g. to increase the capacity equally without manually modifying the source files. The details for resource modifiers are located in the [scripting section](../modding/scripting/modifiersfilters.md).

## Hello Modding-World

Here are two exemplaric demo mods which show small examples of what can be modded for Transport Fever 3.

> **Download:**
>
> ![](../_media/modding/introduction/demo_asset.png)
>
> ### Demo Asset
>
> This demo adds the Transport Fever logo as an asset to the game. It can be placed ingame.
> The minimal setup for a static 3D model in Transport Fever consist of three parts:
>
> - [''mod.json''](../modding/general/moddefinition.md#modjson) and [''_metadata/modinfo.json''](../modding/general/moddefinition.md#modinfojson) for the setup of the mod itself
> - a 3D model with [''.msh''](../modding/general/resourcetypes/msh.md), [''.mdl''](../modding/general/resourcetypes/mdl.md) and [textures](../modding/general/resourcetypes.md#texture_files) for the content
> - [''.con.lua''](../modding/constructions/basics.md) and [''.script.lua''](../modding/constructions/basics.md#update_script) for the scripting as a placeable asset.
>
> You can [download](../_media/modding/introduction/ug_tf3_example_asset.zip) the mod for further investigation. This mod includes a simplified asset construction based on the `assetbuilderutil`, too.

> **Download:**
>
> ![](../_media/modding/introduction/demo_config_change.png)
>
> ### Demo Config Change
>
> This demo overrides a config value from the [base config](../modding/scripting/baseconfig.md) to force trains to start breaking earlier.
> The minimal setup for a mod that changes a base config value consists just of the first part:
>
> - [''mod.json''](../modding/general/moddefinition.md#modjson) and [''_metadata/modinfo.json''](../modding/general/moddefinition.md#modinfojson) for the setup of the mod itself
> - `mod.script.tl` for the script function that changes the config
>
> You can [download](../_media/modding/introduction/wiki_example_config_change.zip) the mod for further investigation.
