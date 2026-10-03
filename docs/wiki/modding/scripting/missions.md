---
title: Missions
page_id: modding:scripting:missions
source: https://wiki.transportfever3.com/doku.php?id=modding:scripting:missions
---

# Missions

Transport Fever 3 ships with one [campaign](https://wiki.transportfever3.com/doku.php?id=gamemanual:gamemodes:campaign). For modders, it is possible to provide additional campaigns or single missions. These are then available over CAMPAIGN in the main menu.

Each campaign consists of several missions.

### Campaign File

The campaign file is must carry the suffix `.campaign.lua`. The file can be placed either in a mission mod file or within a separate mod.
It should have the following content specified:

```lua
function data()
return {
	name = _("CAMPAIGN_NAME"),
	icon = "campaign.tga",
	description = _("CAMPAIGN_DESC"),
	order = 1,
	unlockingProgression = true,
}
end
```

The properties are:

- `name` for the title of the campaign that is displayed in the campaign selection menu.
- `icon` for the image button that is used to select the campaign. The double sized `<name>@2x.tga` image should have a resolution of 675 × 1080 pixels.
- `description` for the descriptive text in the campaign selection menu.
- `order` for the sort order in the campaign selection menu. The vanilla campaigns have place 1.
- `unlockingProgression` whether all missions are unlocked or if the next mission must be unlocked by achieving at least one star.

### Mission Folder

Inside each mission folder should consist of the following files, which we will explain one after the other:

- `info.mission.lua` specified the metadata of the mission
- `savegame.sav` the actual savegame
- `mission.res.lua` entry point for the overall mission simulation script in the base game
- `mission.script.lua` entry point for the specific mission script
- `mission.tl` actual implementation of the mission
- `mission_story.tl` task logic of the mission

#### info.mission.lua

```lua
function data()
	return {
		name = _("MISSION_01_NAME"),
		description = _("MISSION_01_DESC"),
		image = "/gui/mission/m01_preview.tga",
		imagePreview = "/gui/mission/m01_preview2.tga",
		imageSuccess = "/gui/mission/m01_suc.tga",
		imageFailure = "/gui/mission/m01_fail.tga",
		languageScript = "urbangames_campaign_mission_01::/mission/keyframes/languages.script@get",
		loadscreen = "/gui/mission/m01_loadscreen.tga",
		loadscreenDescription = _("MISSION_01_LOADSCREEN"),
		loadscreenVoiceOver = "/audio/voice_over/MISSION_01_LOADSCREEN.wav",
		savegame = "/savegames/savegame.sav",
		starsDescription = _("MISSION_01_STARS_INFO"),
		stars = {
			{
				id = "MISSION_01_STAR_1",
				name = _("MISSION_01_STAR_1"),
				iconLocked = "::/gui/menu/icons/star_1.tga",
				iconCompleted = "::/gui/menu/icons/star_1.tga",
			},
			{
				id = "MISSION_01_STAR_2",
				name = _("MISSION_01_STAR_2"),
				iconLocked = "::/gui/menu/icons/star_2.tga",
				iconCompleted = "::/gui/menu/icons/star_2.tga",
			},
			{
				id = "MISSION_01_STAR_3",
				name = _("MISSION_01_STAR_3"),
				iconLocked = "::/gui/menu/icons/star_3.tga",
				iconCompleted = "::/gui/menu/icons/star_3.tga",
			},
		},
		medals = {
			{
				id = "MISSION_01_MEDAL_1",
				name = _("MISSION_01_MEDAL"),
				nameLocked = _("MISSION_01_MEDAL_LOCKED"),
				iconLocked = "::/gui/menu/icons/star_1.tga",
				iconCompleted = "::/gui/menu/icons/star_1.tga",
			},
		},
		characters = {
			{
				name = _("MISSION_01_CHARACTER_1_NAME"),
				info = _("MISSION_01_CHARACTER_1_INFO"),
				portrait = "urbangames_campaign_mission_01::/mission/dialogue/major_neutral.tga",
			},
			{
				name = _("MISSION_01_CHARACTER_2_NAME"),
				info = _("MISSION_01_CHARACTER_2_INFO"),
				portrait = "urbangames_campaign_mission_01::/mission/dialogue/katie_baker_neutral.tga",
			},
			{
				name = _("MISSION_01_CHARACTER_3_NAME"),
				info = _("MISSION_01_CHARACTER_3_INFO"),
				portrait = "urbangames_campaign_mission_01::/mission/dialogue/andrew_neutral.tga",
			},
		},
		location = _("MISSION_01_LOCATION"),
		year = 1906,
		campaign = "urbangames_campaign::/info.campaign",
		order = 1,
		musicTracks = {
			{ "urbangames_campaign_mission_01::/audio/music/m1_intro.ogg", false },
			{ "urbangames_campaign_mission_01::/audio/music/m1_theme_chapter_1.ogg", true },
		},
	}
end
```

Notable properties are:

- `campaign` each mission must belong to a campaign
- `stars` required if you want to have a progress in your campaign
- `languageScript` required for dialogue tasks. At least one language should be supported

#### savegame.sav

You can either create a new game or use an existing savegame. Important is that the mission mod is active, when creating/loading the game so that the game scripts for the mission are loaded. Then you can save the game and copy the savegame to your mission folder.

#### mission.tl

This is the entry point for your mission. The mission interface is highly flexible, but as a starting point, we recommend this pattern here:

```lua
local mission_boot_util = ug_require "::/mission/mission_boot_util.tl" as MissionBootUtil
local taskDataFactory = ug_require "mission_story.tl" as function(taskKey : string) : MissionTaskUtil.StaticTaskInfo
 
return mission_boot_util.makeMission({
	scriptKey = "urbangames_campaign_mission_01::/mission/mission.script",
	taskDataFactory = taskDataFactory,
	bootTasks = {
		{ taskKey = "your_first_task" },
	},
})
```

The `mission_story.tl` contains the entire logic of the mission and it contains a function that takes a key as an input and returns a mission task.
The bootTasks select all tasks that are triggered at the start of the mission.
These will be retrieved from the `mission_story.tl` file.

## Mission Scripting

Basically a mission is the combination of an orchestrating [game script](../../modding/scripting/gamescripts.md) and a savegame that is played on.

### Mission Tasks

Missions are just a sequence of tasks. These tasks can either be tasks that have to be completed by the player, or they can be executed in the background and can be completed by themselves when their internal logic is completed.

#### Task Scripts

Task scripts are the base of all tasks. These tasks have parameters that need to be specified in the `mission_story.tl` file and they are triggered sequentially.
Task scripts can define various methods in them. We show here only the most essential methods, and we refer to the source code for a complete definition.

```lua
	interface TaskScript<TaskSpecificState, TaskParams>
		taskScriptName : string
 
		-- prepare the initial state when attempting to spawn (return nil to prevent spawning)
		onSpawn : function(TaskParams, guiTimeSeconds : number) : TaskSpecificState | nil
 
		isComplete : function(state: TaskContext<TaskSpecificState, TaskParams>) : boolean
 
		onUpdate : function(ctx : TaskContext<TaskSpecificState, TaskParams>, readOnlyApi : MissionTaskReadOnlyApi)
		handleEvent : function(src : string, id : string, name : string, param : any, ctx : TaskContext<TaskSpecificState, TaskParams>, missionTaskApi : MissionTaskApi) : any
		guiHandleEvent : function(src : string, id : string, name : string, param : any, ctx : TaskContext<TaskSpecificState, TaskParams>, taskApi : DeferredTaskApi) : any
		guiUpdate : function(ctx : TaskContext<TaskSpecificState, TaskParams>, taskApi : DeferredTaskApi)
	end
```

Here, we will focus on the most important ones:

- Usually, each task has a completeness check: `isComplete`. If it returns true, the follow-up task is triggered and the task is completed.
- `onSpawn` initializes the task state, usually given the parameters specified in the story file.
- `onUpdate` is executed every simulation step. Here lies usually the main logic of the task.
- `guiUpdate` is executed in every frame
- `handleEvent` receives all game script events
- `guiHandleEvent` receives all gui events

The `mission_story.tl` file registers each task with a unique key within the file.

The base game already provides a variety of pre-defiend tasks in `::/mission/tasks/`. For example, there is the `buy_vehicle` task:

```lua
global record MissionTaskBuyVehicle is MissionInterface.TaskScript<MissionTaskBuyVehicle.State, MissionTaskBuyVehicle.Params>
	record Params
		carrier : Carrier
		cargoTypeRes : string
		minCount : integer
		allowBuyVehicles : {string: integer}
	end
	record State
		result : {Engine.Entity}
		purchasedVehicles : {string: integer}
	end
end
```

This task takes as parameters:

- `carrier` which carrier type the player is supposed to buy, e.g., road, rail, etc.
- `cargoTypeRes` the path to the cargo resource which the vehicle is supposed to be able to transport
- `minCount` the number of vehicles the player is supposed to buy
- `allowBuyVehicles` a map of resource paths to integer, which specified which vehicles are allowed to be bought in the vehicle store during this tasks lifetime

The state is used by the task internally.

For tasks that are to be completed by the player's action, usually some UI is wanted. In this case, the task info must be specified. Here, we display the essential fields. See the source code for the complete definition.

```lua
	record TaskInfo
		record Paragraph
			text : string
		end
		record Option
			text : string
			key : any
		end
 
		name : string
		paragraphs : { Paragraph }
		options : { Option }
 
		instructionData : MissionDialogueData.InstructionData
	end
```

The fields are:

- `name` of the task
- `paragraphs` description of the task. First entry is the task description, follow up components are *hints*.
- `options` represent buttons the player can select in the mission UI
- `instructionData` a record that holds voice over/subtitle/portrait images

In the `mission_story.tl` file, the task might be defined as follows:

```lua
	if taskKey == "buy_truck" then
		return {
			taskScript = buy_vehicle as MissionInterface.TaskScript<any, any>,
			taskParams : MissionTaskBuyVehicle.Params = {
				carrier = api.type["enum"].Carrier.ROAD,
				cargoTypeRes = "::/cargos/logs/logs.cargo",
			},
			taskInfo = {
				name = _("Buy a Truck"),
				paragraphs = {
					{ text = _("Buy a truck that can transport logs.") },
				},
 
			},
			followup = {
				{ taskKey = "<NEXT TASK>" },
			},
		}
	end
```

We present one more example, that shows a branching point. The flow of the mission can be imagined as a directed graph. In this graph, branching points are allowed. The conditions can be given in the follow up definition. We present here the example where the player can choose between two different options `A` and `B`:

```lua
	if taskKey == "branching_point" then
		return {
			taskScript = page as MissionInterface.TaskScript<any, any>,
			showInHistory = true,
			taskInfo = {
				name = _("Branching point"),
				paragraphs = {
					{ text = _("Make your decision") },
				},
				options = {
					{ text = _("Choose A"), key = "finish-a" },
					{ text = _("Choose B"), key = "finish-b" },
				},
			},
			followup = {
 
				{
					taskKey = "a",
					condition = function(ctx : MissionInterface.TaskContext<any, any>) : boolean
						if ctx.genericState.optionDecision == "finish-a" then
							return true
						end
					end,
				 },
				{
					taskKey = "b",
					condition = function(ctx : MissionInterface.TaskContext<any, any>) : boolean
						if ctx.genericState.optionDecision == "finish-b" then
							return true
						end
					end,
				 },
			}
		}
	end
```

Here we used the `page` task. This is an empty task that completes once the player selects a button in the mission window.

To conclude this section, we explain how to end the mission. There are two possible endings: success and failure, defined by the `finish` task.

```lua
	if taskKey == "failure" then
		return {
			taskScript = finish as MissionInterface.TaskScript<any, any>,
			taskParams = {
				success = false,
			},
		}
	end
	if taskKey == "success" then
		return {
			taskScript = finish as MissionInterface.TaskScript<any, any>,
		}
	end
```

**Takeaway**

1. Functions in handlers operate on engine thread (api.gui unavailable, engine functions available)
2. Functions in guiHandlers operate on ui thread (api.gui available, engine functions unavailable)
