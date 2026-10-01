Config = {}

Config.Size       = 0.0038
Config.Thickness  = 0.0015
Config.Gap        = 0
Config.DotSize    = 0.003
Config.CircleSegments = 20

Config.DefaultColor = {255, 255, 255, 255}
Config.DefaultOutline = false
Config.DefaultOutlineColor = {0, 0, 0, 255}

Config.DefaultType = 'cross'
Config.OnlyWithWeapon = true
Config.OnlyWhenAiming = true

Config.BlacklistedWeapons = {
    `WEAPON_UNARMED`,
    `WEAPON_KNIFE`,
    `WEAPON_NIGHTSTICK`,
    `WEAPON_HAMMER`,
    `WEAPON_BAT`,
    `WEAPON_CROWBAR`,
    `WEAPON_GOLFCLUB`,
    `WEAPON_BOTTLE`,
    `WEAPON_DAGGER`,
    `WEAPON_HATCHET`,
    `WEAPON_KNUCKLE`,
    `WEAPON_MACHETE`,
    `WEAPON_SWITCHBLADE`,
    `WEAPON_POOLCUE`,
    `WEAPON_WRENCH`,
    `WEAPON_FLASHLIGHT`,
    `WEAPON_STONE_HATCHET`,
    `WEAPON_BATTLEAXE`,
    `WEAPON_BALL`,
    `WEAPON_SNOWBALL`,
    `WEAPON_FIREEXTINGUISHER`,
    `WEAPON_PETROLCAN`,
    `WEAPON_HAZARDCAN`,
    `WEAPON_FERTILIZERCAN`,
    `WEAPON_SPEEDLIDAR4`,
}

Config.Crosshairs = {
    ['cross']        = { label = 'Dấu Cộng',           prime = false, order = 1 },
    ['dot']          = { label = 'Chấm Tròn',           prime = true, order = 2 },
}

