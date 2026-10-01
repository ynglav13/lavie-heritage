Config = {}

Config.DefaultWebhook = GetConvar('legacyWebhook:defaultWebhook', GetConvar('inventory:webhook', ''))
Config.AuditWebhook = GetConvar('legacyWebhook:auditWebhook', Config.DefaultWebhook)
Config.NamedWebhooks = {
    invincibility = GetConvar('legacyWebhook:invincibilityWebhook', ''),
    vehicle_contract = GetConvar('legacyWebhook:vehicleContractWebhook', ''),
    casino = GetConvar('legacyWebhook:casinoWebhook', Config.AuditWebhook)
}
Config.DefaultName = 'Logs'
Config.DefaultAvatar = ''
Config.DefaultColor = 3447003
Config.Interval = GetConvarInt('legacyWebhook:interval', 500)
Config.DatabaseFlushInterval = GetConvarInt('legacyWebhook:databaseFlushInterval', 500)
Config.DatabaseBatchSize = GetConvarInt('legacyWebhook:databaseBatchSize', 50)
Config.DatabaseBatchBytes = GetConvarInt('legacyWebhook:databaseBatchBytes', 1000000)
Config.DiscordBatchSize = GetConvarInt('legacyWebhook:discordBatchSize', 10)
Config.DiscordPayloadLimit = GetConvarInt('legacyWebhook:discordPayloadLimit', 5500)
Config.MaxDeliveryAttempts = GetConvarInt('legacyWebhook:maxDeliveryAttempts', 12)
Config.RetryBase = GetConvarInt('legacyWebhook:retryBase', 5000)
Config.RetryMaximum = GetConvarInt('legacyWebhook:retryMaximum', 300000)
Config.OutboxRetentionDays = GetConvarInt('legacyWebhook:outboxRetentionDays', 7)
Config.OutboxCleanupInterval = GetConvarInt('legacyWebhook:outboxCleanupInterval', 60000)
Config.OutboxCleanupBatchSize = GetConvarInt('legacyWebhook:outboxCleanupBatchSize', 1000)
Config.AllowClientEvents = GetConvarInt('legacyWebhook:allowClientEvents', 0) == 1
Config.StoreDiscordLogs = GetConvarInt('legacyWebhook:storeDiscordLogs', 1) == 1
Config.AuditDiscord = GetConvarInt('legacyWebhook:auditDiscord', 1) == 1
Config.AlertWebhook = GetConvar('legacyWebhook:alertWebhook', '')
Config.AlertPingEveryone = GetConvarInt('legacyWebhook:alertPingEveryone', 0) == 1
Config.LargeMoneyThreshold = GetConvarInt('legacyWebhook:largeMoneyThreshold', 500000)
Config.AdminItemSmuggleWindowSeconds = GetConvarInt('legacyWebhook:adminItemSmuggleWindow', 600)
Config.ContinuousReviveWindowSeconds = GetConvarInt('legacyWebhook:continuousReviveWindowSeconds', 30)
Config.ContinuousReviveCountThreshold = GetConvarInt('legacyWebhook:continuousReviveCountThreshold', 3)
