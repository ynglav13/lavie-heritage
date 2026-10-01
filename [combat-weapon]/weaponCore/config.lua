Config = {}

Config.GlobalRecoilMultiplier = 1.0
Config.GlobalShakeMultiplier = 1.0
Config.MaxRecoilReductionFromSkill = 30.0
Config.FirstPersonMultiplier = 1.5
Config.MovementMultiplier = 1.3
Config.VehicleMultiplier = 5.0

Config.EnableSprayRecoil = true
Config.SprayMultiplierPerShot = 0.1
Config.MaxSprayMultiplier = 2.5

Config.EnableDistanceRecoil = true
Config.DistanceMultiplierBase = 1.0
Config.DistanceMultiplierMax = 3.0
Config.MaxDistanceThreshold = 100.0

Config.StressOnShooting = true -- Bat/tat stress khi ban sung
Config.StressChance = 15 -- Phan tram co hoi tang stress trong moi lan roll (giam xuong 15%)
Config.StressAmount = 1 -- So diem stress tang khi roll thanh cong (1 diem)
Config.StressClientCooldown = 10000 -- Thoi gian cho giua hai lan roll, tinh bang ms (10s)
Config.StressServerCooldown = 9000 -- Cooldown server chong spam event, tinh bang ms

Config.DefaultRecoil =
{
    vertical = 10.0,
    horizontal = 10.0,
    shake = 0.02
}

Config.Weapons =
{
    [`WEAPON_PISTOL`] =
    {
        vertical = 0.4,
        horizontal = 0.1,
        shake = 0.02
    },
    [`WEAPON_COMBATPISTOL`] =
    {
        vertical = 5.0,
        horizontal = 5.0,
        shake = 0.03
    },
    [`WEAPON_APPISTOL`] =
    {
        vertical = 0.6,
        horizontal = 0.2,
        shake = 0.04
    },
    [`WEAPON_PISTOL50`] =
    {
        vertical = 1.0,
        horizontal = 0.3,
        shake = 0.06
    },
    [`WEAPON_HEAVYPISTOL`] =
    {
        vertical = 0.8,
        horizontal = 0.2,
        shake = 0.05
    },
    [`WEAPON_SNSPISTOL`] =
    {
        vertical = 0.3,
        horizontal = 0.1,
        shake = 0.02
    },
    [`WEAPON_VINTAGEPISTOL`] =
    {
        vertical = 0.4,
        horizontal = 0.1,
        shake = 0.02
    },
    [`WEAPON_CERAMICPISTOL`] =
    {
        vertical = 0.4,
        horizontal = 0.1,
        shake = 0.02
    },
    [`WEAPON_MICROSMG`] =
    {
        vertical = 0.5,
        horizontal = 0.3,
        shake = 0.03
    },
    [`WEAPON_SMG`] =
    {
        vertical = 0.4,
        horizontal = 0.2,
        shake = 0.03
    },
    [`WEAPON_ASSAULTSMG`] =
    {
        vertical = 0.4,
        horizontal = 0.2,
        shake = 0.03
    },
    [`WEAPON_COMBATPDW`] =
    {
        vertical = 0.3,
        horizontal = 0.15,
        shake = 0.02
    },
    [`WEAPON_MACHINEPISTOL`] =
    {
        vertical = 0.5,
        horizontal = 0.3,
        shake = 0.04
    },
    [`WEAPON_MINISMG`] =
    {
        vertical = 0.6,
        horizontal = 0.35,
        shake = 0.04
    },

    [`WEAPON_ASSAULTRIFLE`] =
    {
        vertical = 0.6,
        horizontal = 0.25,
        shake = 0.04
    },
    [`WEAPON_CARBINERIFLE`] =
    {
        vertical = 0.5,
        horizontal = 0.2,
        shake = 0.03
    },
    [`WEAPON_VFCARBINE`] =
    {
        vertical = 2.7,
        horizontal = 2.0,
        shake = 0.02
    },
    [`WEAPON_SPCARBINE`] =
    {
        vertical = 2.5,
        horizontal = 2.0,
        shake = 0.02
    },
    [`WEAPON_ADVANCEDRIFLE`] =
    {
        vertical = 0.55,
        horizontal = 0.2,
        shake = 0.04
    },
    [`WEAPON_SPECIALCARBINE`] =
    {
        vertical = 3.0,
        horizontal = 2.5,
        shake = 0.1
    },
    [`WEAPON_BULLPUPRIFLE`] =
    {
        vertical = 0.5,
        horizontal = 0.2,
        shake = 0.03
    },
    [`WEAPON_COMPACTRIFLE`] =
    {
        vertical = 0.7,
        horizontal = 0.3,
        shake = 0.05
    },

    [`WEAPON_PUMPSHOTGUN`] =
    {
        vertical = 1.5,
        horizontal = 0.4,
        shake = 0.08
    },
    [`WEAPON_SAWNOFFSHOTGUN`] =
    {
        vertical = 2.0,
        horizontal = 0.6,
        shake = 0.1
    },
    [`WEAPON_ASSAULTSHOTGUN`] =
    {
        vertical = 1.2,
        horizontal = 0.3,
        shake = 0.07
    },
    [`WEAPON_BULLPUPSHOTGUN`] =
    {
        vertical = 1.3,
        horizontal = 0.35,
        shake = 0.07
    },
    [`WEAPON_HEAVYSHOTGUN`] =
    {
        vertical = 1.4,
        horizontal = 0.4,
        shake = 0.08
    },
    [`WEAPON_DBSHOTGUN`] =
    {
        vertical = 2.5,
        horizontal = 0.8,
        shake = 0.12
    },
    [`WEAPON_AUTOSHOTGUN`] =
    {
        vertical = 1.0,
        horizontal = 0.3,
        shake = 0.06
    },

    [`WEAPON_SNIPERRIFLE`] =
    {
        vertical = 1.5,
        horizontal = 0.3,
        shake = 0.1
    },
    [`WEAPON_HEAVYSNIPER`] =
    {
        vertical = 2.5,
        horizontal = 0.5,
        shake = 0.15
    },
    [`WEAPON_MARKSMANRIFLE`] =
    {
        vertical = 0.8,
        horizontal = 0.2,
        shake = 0.05
    },

    [`WEAPON_MG`] =
    {
        vertical = 0.8,
        horizontal = 0.4,
        shake = 0.06
    },
    [`WEAPON_COMBATMG`] =
    {
        vertical = 0.7,
        horizontal = 0.35,
        shake = 0.05
    },
    [`WEAPON_GUSENBERG`] =
    {
        vertical = 0.5,
        horizontal = 0.2,
        shake = 0.04
    },

    [`WEAPON_VF17`] =
    {
        vertical = 1.8,
        horizontal = 1.5,
        shake = 0.02
    },
    [`WEAPON_VF18`] =
    {
        vertical = 1.8,
        horizontal = 1.5,
        shake = 0.02
    },
    [`WEAPON_VF9C`] =
    {
        vertical = 1.6,
        horizontal = 1.1,
        shake = 0.02
    },
    [`WEAPON_ZN509`] =
    {
        vertical = 1.5,
        horizontal = 1.0,
        shake = 0.02
    },
    [`WEAPON_HL50E`] =
    {
        vertical = 10.5,
        horizontal = 5.0,
        shake = 0.03
    },
    [`WEAPON_HLTMP7`] =
    {
        vertical = 2.5,
        horizontal = 1.5,
        shake = 0.04
    },
    [`WEAPON_870SO_SHOTGUN`] =
    {
        vertical = 20.5,
        horizontal = 10.0,
        shake = 0.5
    },
    [`WEAPON_PISTOL_MK2`] =
    {
        vertical = 1.5,
        horizontal = 1.0,
        shake = 0.02
    },
    [`WEAPON_PROSMG`] =
    {
        vertical = 3.5,
        horizontal = 2.0,
        shake = 0.06
    },
    [`WEAPON_HLCP`] =
    {
        vertical = 7.5,
        horizontal = 4.5,
        shake = 0.02
    },
    [`WEAPON_TCARBINE`] =
    {
        vertical = 2.5,
        horizontal = 2.0,
        shake = 0.02
    },
    [`WEAPON_BEANBAG`] =
    {
        vertical = 0.0,
        horizontal = 0.0,
        shake = 0.0
    },
    [`WEAPON_YBEANBAG`] =
    {
        vertical = 0.0,
        horizontal = 0.0,
        shake = 0.0
    },
    [`WEAPON_LESSLAUNCHER`] =
    {
        vertical = 0.0,
        horizontal = 0.0,
        shake = 0.0
    },
    [`WEAPON_YLESSLAUNCHER`] =
    {
        vertical = 0.0,
        horizontal = 0.0,
        shake = 0.0
    },
    [`WEAPON_STUNGUN`] =
    {
        vertical = 0.0,
        horizontal = 0.0,
        shake = 0.0
    },
    [`WEAPON_Y2`] =
    {
        vertical = 0.0,
        horizontal = 0.0,
        shake = 0.0
    },
    [`WEAPON_C9`] =
    {
        vertical = 0.0,
        horizontal = 0.0,
        shake = 0.0
    },
    [`WEAPON_BATTLERIFLE`] =
    {
        vertical = 0.6,
        horizontal = 0.25,
        shake = 0.04
    },
    [`WEAPON_SNOWLAUNCHER`] =
    {
        vertical = 0.0,
        horizontal = 0.0,
        shake = 0.0
    },
    [`WEAPON_TECPISTOL`] =
    {
        vertical = 0.5,
        horizontal = 0.3,
        shake = 0.03
    },
}
