Config = Config or {}

Config.Debug = false

Config.Diagnostics = {
    VehicleDeletes = true,
    SuspiciousCreates = true,
}

Config.Deformation = {
    Enabled = true,
    CaptureDelay = 1000,
    DamageThreshold = 0.05,
    AngleThreshold = 0.5,
    MaxApplyIterations = 50,
    InitialDamage = 50.0,
    DamageIncrement = 5.0,
    MaxPoints = 128,
    DecimalPlaces = 4,
    MaxVectorComponent = 50.0,
    MaxEncodedBytes = 8192,
    FixMaxDistance = 15.0,
    FixValidationTimeout = 2000,
    BlacklistedTypes = {
        bike = true,
        boat = true,
        heli = true,
        plane = true,
        submarine = true,
        train = true,
    },
}

Config.Tracking = {
    SaveOnlyOwnedVehicles = true,
    RequireDriver = true,
    RequirePlayerOwnership = true,
    ClientSnapshotInterval = 60000,
    PositionSnapshotInterval = 30000,
    FullPropertiesInterval = 300000,
    FullSnapshotRetryInterval = 30000,
    PositionDistance = 50.0,
    StateCacheLifetime = 120000,
    RecentAccessGrace = 20000,
    SnapshotMinInterval = 10000,
    SnapshotMaxBytes = 60000,
    PersistedStateBagKeys = {
        deformation = true,
    },
}

Config.Persistence = {
    FlushInterval = 15000,
    BatchSize = 50,
    GarageSyncInterval = 10000,
    GarageSyncBatchSize = 30,
    ExternalDeleteDistance = 50.0,
    ReconcileInterval = 60000,
    ReconcileBatchSize = 100,
    SpawnTickInterval = 5000,
    SpawnTransitionLeaseMs = 30000,
    RespawnScanBatch = 50,
    RespawnDistance = 15.0,
    RespawnDelay = 1,
    MaxSpawnsPerTick = 2,
    ShutdownFlushMaxBatches = 8,
}

Config.Visual = {
    FadeIn = true,
    FadeInDuration = 500,
    FadeInStartAlpha = 210,
    FadeInStep = 35,
    FadeOut = true,
    FadeOutDuration = 500,
    FadeOutEndAlpha = 0,
    FadeOutStep = 45,
}

Config.Cleanup = {
    Enabled = true,
    CheckInterval = 300000,
    MissingVehicleThreshold = 1800,
    ReturnDisconnectedVehicles = true,
    ReturnDisconnectedAfterMinutes = 15,
    ReturnDisconnectedCheckInterval = 60000,
    ReturnDisconnectedBatchSize = 30,
    SendToGarage = true,
    DeleteDistantVehicles = false,
    DistantVehicleInterval = 300000,
    DistantVehicleDistance = 350.0,
    BatchSize = 30,
}
