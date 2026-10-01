Config = {}

Config.Animations =
{
    police =
    {
        title = 'Rút Từ Hông Của Bạn',
        description = 'Thiết lập Animation rút súng kiểu cảnh sát',
        anim =
        {
            'reaction@intimidation@cop@unarmed',
            'intro',
            200,
            'reaction@intimidation@cop@unarmed',
            'outro',
            200
        }
    },
    default_ox =
    {
        title = 'Rút Từ Phía Sau Lưng',
        description = 'Thiết lập Animation mặc định',
        anim =
        {
            'reaction@intimidation@1h',
            'intro',
            1200,
            'reaction@intimidation@1h',
            'outro',
            1400
        }
    },
    pistol =
    {
        title = 'Rút Từ Phía Trước',
        description = 'Thiết lập Animation rút súng ngắn từ trước',
        anim =
        {
            'weaponanimation@wlz',
            'wlz_clip',
            400,
            'weaponanimation@wlz',
            'wlz_clip',
            450
        }
    },
    rifle =
    {
        title = 'Rút Từ Ngực',
        description = 'Thiết lập Animation rút súng từ trước ngực',
        anim =
        {
            'wlz_weaponanimation2@animation',
            'wlz_clip',
            400,
            'wlz_weaponanimation2@animation',
            'wlz_clip',
            450
        }
    },
    heavy =
    {
        title = 'Heavy Weapon Animation',
        description = 'Animation for Heavy Weapons',
        anim =
        {
            'wlz_weaponanimation2@animation',
            'wlz_clip',
            400,
            'wlz_weaponanimation2@animation',
            'wlz_clip',
            450
        }
    },
    shotgun =
    {
        title = 'Shotgun Animation',
        description = 'Animation dành cho các loại Shotgun',
        anim =
        {
            'wlz_weaponanimation2@animation',
            'wlz_clip',
            400,
            'wlz_weaponanimation2@animation',
            'wlz_clip',
            450
        }
    },
    smg =
    {
        title = 'SMG Animation',
        description = 'Animation dành cho các loại súng tiểu liên (SMG)',
        anim =
        {
            'wlz_weaponanimation2@animation',
            'wlz_clip',
            400,
            'wlz_weaponanimation2@animation',
            'wlz_clip',
            450
        }
    },
    melee =
    {
        title = 'Melee Animation',
        description = 'Animation dành cho các loại vũ khí cận chiến',
        anim =
        {
            'melee@holster',
            'unholster',
            200,
            'melee@holster',
            'holster',
            600
        }
    }
}

Config.Groups =
{
    "GROUP_PISTOL",
    "GROUP_HEAVY",
    "GROUP_SHOTGUN",
    "GROUP_RIFLE",
    "GROUP_SMG",
    "GROUP_MELEE",
    "GROUP_STUNGUN"
}

Config.DefaultAnimations =
{
    [GetHashKey("GROUP_PISTOL")] = 'pistol',
    [GetHashKey("GROUP_HEAVY")] = 'heavy',
    [GetHashKey("GROUP_SHOTGUN")] = 'shotgun',
    [GetHashKey("GROUP_RIFLE")] = 'rifle',
    [GetHashKey("GROUP_SMG")] = 'smg',
    [GetHashKey("GROUP_MELEE")] = 'melee',
    [GetHashKey("GROUP_STUNGUN")] = 'pistol'
}

Config.FallbackAnim =
{
    'reaction@intimidation@1h',
    'intro',
    1200,
    'reaction@intimidation@1h',
    'outro',
    1400
}

-- Danh sách các vũ khí custom / addon cho phép sử dụng tư thế ngắm & tư thế cầm súng 1 tay (Hold One Arm)
Config.CustomPistols = {
    "WEAPON_ZN509",
    "WEAPON_VF9C",
    "WEAPON_VF17",
    "WEAPON_VF18",
    -- Thêm các vũ khí custom khác tại đây (ví dụ: "WEAPON_GLOCK17", "WEAPON_APPISTOL", ...)
}


