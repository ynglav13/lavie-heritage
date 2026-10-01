Config = {}

Config.DisableInVehicle = false
Config.DisableWhenDead = true
Config.PreviewDuration = 2000

Config.AnimOrder = {
    'default',
    'cop_mic_1',
    'cop_mic_2',
    'cop_mic_3',
    'cop_mic_4',
    'cop_radio_pose'
}

Config.Anims = {
    default = {
        name = 'Radio tiêu chuẩn',
        animDict = 'random@arrests',
        animAnim = 'generic_radio_enter',
        playAnimArgs = { 8.0, 2.0, -1, 50, 2.0, 0, 0, 0 },
        stopAnimArgs = { -4.0 }
    },
    cop_mic_1 = {
        name = 'Micro ngực 1',
        animDict = 'anim@cop_mic_pose_001',
        animAnim = 'chest_mic'
    },
    cop_mic_2 = {
        name = 'Micro ngực 2',
        animDict = 'anim@cop_mic_pose_002',
        animAnim = 'chest_mic'
    },
    cop_mic_3 = {
        name = 'Micro ngực 3',
        animDict = 'anim@cop_mic_pose_002_1',
        animAnim = 'chest_mic_pose'
    },
    cop_mic_4 = {
        name = 'Micro ngực 4',
        animDict = 'anim@cop_mic_pose_002_2',
        animAnim = 'chest_mic_02'
    },
    cop_radio_pose = {
        name = 'Cầm bộ đàm',
        animDict = 'anim@cop_radio_pose',
        animAnim = 'holding_radio',
        prop = 'prop_cs_hand_radio',
        AttachArguments = {
            Bone = 18905, -- Tay trái (PH_L_Hand: 18905 hoặc SKEL_L_Hand: 57005)
            xPos = 0.145,
            yPos = 0.05,
            zPos = 0.03,
            xRot = -105.8,
            yRot = -10.9,
            zRot = -33.7
        }
    }
}

Config.CurrentAnim = Config.Anims.default
