Config = {}

Config.Locale = 'vi'
Config.Command = 'musicbox'
Config.DefaultKey = ''
Config.Debug = false

Config.StorageFile = 'data/library.json'
Config.MaxRecent = 20
Config.MaxFavorites = 50
Config.RequestCooldownMs = 2500
Config.MaxSourcesPerPlayer = 3

Config.Notification =
{
    title = 'SpityFork',
    useLvNotify = true
}

Config.Inventory =
{
    removeOnPlace = true,
    returnOnPickup = true,
    requireItem = true
}

Config.Resolver =
{
    endpoint = 'https://cdn.lslegacy.net/musicbox/resolve/{id}',
    allowDirectUrls = true,
    maxDurationSeconds = 900
}

Config.Audio =
{
    is2D = true,
    updateMs = 250,
    farUpdateMs = 1000,
    preloadDistance = 10.0,
    warmCacheMs = 15000,
    refDistance = 2.0,
    rolloffFactor = 1.0,
    masterVolume = 0.5,
    softSyncThreshold = 0.65,
    hardSyncThreshold = 6.0,
    bufferTimeoutMs = 10000,

    maxRetries = 8
}

Config.InteractionDistance = 2.4
Config.UiSourceDistance = 45.0
Config.PlaceDuration = 1600

Config.Target =
{
    enabled = true,
    distance = 2.4
}

Config.Vehicle =
{
    enabled = false,
    label = 'Vehicle speakers',
    distance = 38.0,
    volume = 0.55
}

Config.Effects =
{
    vehicleMuffle =
    {
        enabled = false,
        strength = 0.68,
        volumeMultiplier = 0.55
    },
    realisticEcho =
    {
        enabled = false,
        amount = 0.26
    },
    interiorMuffle =
    {
        enabled = false,
        strength = 0.72,
        volumeMultiplier = 0.48
    }
}

Config.Attachments =
{
    hand =
    {
        bone = 57005,
        offset = vec3(0.23, 0.02, -0.02),
        rotation = vec3(-92.0, 8.0, 12.0)
    },
    back =
    {
        bone = 24818,
        offset = vec3(0.18, -0.22, 0.02),
        rotation = vec3(0.0, 88.0, 178.0)
    }
}

Config.BoomboxItems =
{
    boombox_black =
    {
        label = 'Black Boombox',
        model = 'prop_boombox_01',
        type = 'portable',
        distance = 26.0,
        volume = 0.5
    },
    boombox_red =
    {
        label = 'Red Boombox',
        model = 'prop_boombox_01',
        type = 'portable',
        distance = 26.0,
        volume = 0.75
    },
    boombox_gold =
    {
        label = 'Gold Boombox',
        model = 'prop_boombox_01',
        type = 'portable',
        distance = 28.0,
        volume = 0.8
    },
    boombox_mini =
    {
        label = 'Mini Boombox',
        model = 'prop_tapeplayer_01',
        type = 'portable',
        distance = 20.0,
        volume = 0.65
    },
    speaker_small =
    {
        label = 'Small Speaker',
        model = 'prop_speaker_01',
        type = 'stationary',
        distance = 32.0,
        volume = 0.8
    },
    speaker_large =
    {
        label = 'Large Speaker',
        model = 'prop_speaker_03',
        type = 'stationary',
        distance = 46.0,
        volume = 0.9
    }
}
