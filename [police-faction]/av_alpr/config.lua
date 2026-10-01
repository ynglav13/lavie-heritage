Config = {}

Config.Command = 'vradar'
Config.ClearLogCommand = 'clearalpr'

Config.Keys = {
    Toggle = 'NUMPAD5',
    LockPlate = 'SPACE',
    UnlockPlate = 'BACK'
}

Config.ScanDistance = 20.0
Config.ScanInterval = 300

Config.RadarTargetScanInterval = 400
Config.RadarUIInterval = 250
Config.NPCVehicleCacheTTL = 1000
Config.RadarStateMaxEntries = 32

Config.FactionVehicleStateKey = 'FactionVehicle'
Config.DefaultPlateIndex = 0
Config.ValidPlateIndices = {
    [0] = true,
    [1] = true,
    [2] = true,
    [3] = true,
    [4] = true,
    [5] = true
}

Config.ServerLookupMinInterval = 200
Config.ServerLookupMaxDistance = 75.0
Config.ProfileCacheTTL = 30
Config.ProfileCacheMaxEntries = 1000
Config.ProfileCacheCleanupInterval = 60

Config.UseESX = true

Config.SpeedRadar = true
Config.SpeedLimit = 50
Config.RadarScanDistance = 60.0
Config.UseMph = true
Config.RadarKeys = {
    Toggle = 'NUMPAD5'
}
