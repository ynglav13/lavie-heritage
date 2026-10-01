Singleplayer

How to install:

1. Use Jennie's custom anims mod add-on folder.
https://www.gta5-mods.com/misc/custom-animations-add-on-customanims

2. Drag the .ycd files to clip_amb@.rpf file.

3. Put this line to menyoostuff/favoriteanims.xml

	<Anim dict="anim@hand_rest_belt" name="cop_idle" />
    	<Anim dict="anim@cop_radio_pose" name="holding_radio" />
    	<Anim dict="anim@hand_rest_holster" name="hand_rest" />
    	<Anim dict="anim@cop_pose_escorting" name="escorting_rifle" />
    	<Anim dict="anim@cop_pose" name="pullout_gun" />
    	<Anim dict="anim@belt_pose_hlstr" name="hand_hlstr_scene" />
   	<Anim dict="anim@cop_mic_pose_001" name="chest_mic" />
    	<Anim dict="anim@cop_mic_pose_002" name="chest_mic" />
    	<Anim dict="anim@cop_mic_pose_002_1" name="chest_mic_pose" />
    	<Anim dict="anim@cop_mic_pose_002_2" name="chest_mic_02" />

DPEMOTES USERS ON FIVEM: 

NOTE: For prop placement, please use this guide
https://forum.cfx.re/t/how-to-menyoo-to-dpemotes-conversion-streaming-custom-add-on-props/4775018

Place the ycd files into this folder:

resources/dpemotes-master/streams 

Then copy this line into your AnimationList.lua 

["handrestbelt"] = {
        "anim@hand_rest_belt",
        "cop_idle",
        "Hand Rest Belt",
        AnimationOptions = {
            EmoteLoop = true,
            EmoteMoving = false,
        }
    },
["copradiopose"] = {
        "anim@cop_radio_pose",
        "holding_radio",
        "Holding Radio",
        AnimationOptions = {
            EmoteLoop = true,
            EmoteMoving = false,
        }
    },
["handrestholster"] = {
        "anim@hand_rest_holster",
        "hand_rest",
        "Hand Rest",
        AnimationOptions = {
            EmoteLoop = true,
            EmoteMoving = false,
        }
    },
["copposeexcorting"] = {
        "anim@cop_pose_escorting",
        "escorting_rifle",
        "Escorting Crook",
        AnimationOptions = {
            EmoteLoop = true,
            EmoteMoving = false,
        }
    },
["coppose"] = {
        "anim@cop_pose",
        "pullout_gun",
        "Pullout From Holster",
        AnimationOptions = {
            EmoteLoop = true,
            EmoteMoving = false,
        }
    },
["copmicpose001"] = {
        "anim@cop_mic_pose_001",
        "chest_mic",
        "Chest Mic Pose 1",
        AnimationOptions = {
            EmoteLoop = true,
            EmoteMoving = false,
        }
    },
["copmicpose002"] = {
        "anim@cop_mic_pose_002",
        "chest_mic",
        "Chest Mic Pose 2",
        AnimationOptions = {
            EmoteLoop = true,
            EmoteMoving = false,
        }
    },
["copmicpose0021"] = {
        "anim@cop_mic_pose_002_1",
        "chest_mic_pose",
        "Chest Mic Pose 3",
        AnimationOptions = {
            EmoteLoop = true,
            EmoteMoving = false,
        }
    },
["copmicpose0022"] = {
        "anim@cop_mic_pose_002_2",
        "chest_mic_02",
        "Chest Mic Pose 4",
        AnimationOptions = {
            EmoteLoop = true,
            EmoteMoving = false,
        }
    },