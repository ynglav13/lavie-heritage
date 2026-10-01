DamageServer = DamageServer or {}

local webhookQueue = {}
local isQueueProcessing = false
local damageStores = {}
local playerIdentifiers = {}
local damageRates = {}
local verifiedHits = {}
local DAMAGE_FLUSH_INTERVAL = DamageConfig.Runtime.DamageFlushInterval
local DAMAGE_LOAD_TIMEOUT = DamageConfig.Runtime.DamageLoadTimeout

DamageConfig.Webhook = DamageConfig.Webhook or {}
DamageConfig.Webhook.BotToken = GetConvar('lavie_injury_damage_bot_token',
    GetConvar('lavie_bodydamages_bot_token', DamageConfig.Webhook.BotToken or ''))
DamageConfig.Webhook.Damage = GetConvar('lavie_injury_damage_webhook',
    GetConvar('lavie_bodydamages_webhook', DamageConfig.Webhook.Damage or ''))

local function getPlayerByIdentity(playerId, identifier)
    local xPlayer = ESX.GetPlayerFromId(tonumber(playerId))

    if xPlayer and type(identifier) == 'string' and identifier ~= '' and xPlayer.identifier == identifier then
        return xPlayer
    end

    return nil
end

local function isAllowedDiscordWebhook(value)
    if type(value) ~= 'string' or value == '' then
        return false
    end

    local host = value:match('^https://([^/]+)/')
    local path = value:match('^https://[^/]+(/[^%s]*)$')
    host = host and host:lower() or ''
    path = path or ''

    local allowedHost = host == 'discord.com'
        or host == 'www.discord.com'
        or host == 'discordapp.com'
        or host == 'www.discordapp.com'
        or host == 'canary.discord.com'
        or host == 'ptb.discord.com'
    local allowedPath = path:match('^/api/webhooks/%d+/[%w%._%-]+')
        or path:match('^/api/v%d+/webhooks/%d+/[%w%._%-]+')

    return allowedHost and allowedPath ~= nil
end

if DamageConfig.Webhook.BotToken == ''
    and DamageConfig.Webhook.Damage ~= ''
    and not isAllowedDiscordWebhook(DamageConfig.Webhook.Damage) then
    print('[lavie_injury:damage] Invalid lavie_bodydamages_webhook; using the central default audit route')
    DamageConfig.Webhook.Damage = ''
end

if DamageConfig.Webhook.BotToken ~= ''
    and (type(DamageConfig.Webhook.Damage) ~= 'string' or not DamageConfig.Webhook.Damage:match('^%d+$')) then
    print('[lavie_injury:damage] Invalid bot channel; using the central default audit route')
    DamageConfig.Webhook.BotToken = ''
    DamageConfig.Webhook.Damage = ''
end

local function decodeDamages(value)
    if value == nil or value == '' then
        return {}
    end

    if type(value) ~= 'string' then
        return nil, 'invalid_type'
    end

    local ok, data = pcall(json.decode, value)

    if ok and type(data) == 'table' then
        return data
    end

    return nil, 'invalid_json'
end

local function getDamageStore(identifier)
    local store = damageStores[identifier]

    if not store then
        store = {
            data = nil,
            pending = {},
            pendingHead = 1,
            pendingTail = 0,
            loading = false,
            loadError = nil,
            nextLoadRetry = 0,
            revision = 0,
            persistedRevision = 0,
            generation = 0,
            flushing = false,
            nextFlushRetry = 0,
            releaseWhenClean = false
        }
        damageStores[identifier] = store
    end

    return store
end

local function drainPending(store)
    if not store.data then
        return
    end

    while store.pendingHead <= store.pendingTail do
        store.data[#store.data + 1] = store.pending[store.pendingHead]
        store.pending[store.pendingHead] = nil
        store.pendingHead = store.pendingHead + 1
    end

    if store.pendingHead > store.pendingTail then
        store.pending = {}
        store.pendingHead = 1
        store.pendingTail = 0
    end
end

local function startDamageLoad(identifier, store)
    if store.data or store.loading or GetGameTimer() < store.nextLoadRetry then
        return
    end

    store.loading = true
    local generation = store.generation

    CreateThread(function()
        local ok, value = pcall(MySQL.scalar.await,
            'SELECT bodydamages FROM users WHERE identifier = ?',
            { identifier }
        )

        if damageStores[identifier] ~= store then
            return
        end

        if store.generation == generation then
            if ok then
                local decoded, decodeError = decodeDamages(value)

                if decoded then
                    store.data = decoded
                    store.loadError = nil
                    store.nextLoadRetry = 0
                else
                    store.loadError = decodeError
                    store.nextLoadRetry = GetGameTimer() + 60000
                    print(('[lavie_injury:damage] Refusing to overwrite invalid bodydamages JSON for %s (%s)'):format(identifier, decodeError))
                end
            else
                store.loadError = tostring(value)
                store.nextLoadRetry = GetGameTimer() + 5000
                print(('[lavie_injury:damage] Failed to load bodydamages for %s: %s'):format(identifier, tostring(value)))
            end
        end

        store.loading = false

        if store.data then
            drainPending(store)
        end
    end)
end

function GetBodyDamageData(identifier, timeout)
    if type(identifier) ~= 'string' or identifier == '' then
        return nil, 'invalid_identifier'
    end

    local store = getDamageStore(identifier)
    startDamageLoad(identifier, store)

    local timeoutAt = GetGameTimer() + (tonumber(timeout) or DAMAGE_LOAD_TIMEOUT)

    while store.loading and GetGameTimer() < timeoutAt do
        Wait(25)
    end

    if not store.data then
        return nil, store.loading and 'timeout' or store.loadError or 'unavailable'
    end

    drainPending(store)
    return store.data
end

local function cloneDamageRecords(records)
    local response = {}

    for index = 1, #records do
        local sourceData = records[index]

        if type(sourceData) == 'table' then
            local entry = {}

            for key, value in pairs(sourceData) do
                entry[key] = value
            end

            response[#response + 1] = entry
        end
    end

    return response
end

function DamageServer.GetPlayerDamages(serverId)
    serverId = tonumber(serverId)
    local xPlayer = ESX.GetPlayerFromId(serverId)

    if not xPlayer or type(xPlayer.identifier) ~= 'string' or xPlayer.identifier == '' then
        return {}
    end

    local identifier = xPlayer.identifier
    local records, loadError = GetBodyDamageData(identifier)

    if not getPlayerByIdentity(serverId, identifier) then
        return nil, 'player_changed'
    end

    if not records then
        return nil, loadError
    end

    return cloneDamageRecords(records)
end

exports('GetPlayerDamages', DamageServer.GetPlayerDamages)

local function queueDamage(identifier, entry)
    local store = getDamageStore(identifier)
    store.pendingTail = store.pendingTail + 1
    store.pending[store.pendingTail] = entry
    store.revision = store.revision + 1
    store.releaseWhenClean = false

    if store.data then
        drainPending(store)
    else
        startDamageLoad(identifier, store)
    end
end

local function flushDamage(identifier)
    local store = damageStores[identifier]

    if not store then
        return true
    end

    if store.data then
        drainPending(store)
    elseif not store.loading then
        startDamageLoad(identifier, store)
    end

    if not store.data or store.loading or store.flushing or GetGameTimer() < store.nextFlushRetry then
        return false
    end

    if store.persistedRevision >= store.revision then
        return true
    end

    local encodedOk, encoded = pcall(json.encode, store.data)

    if not encodedOk then
        store.nextFlushRetry = GetGameTimer() + 5000
        print(('[lavie_injury:damage] Failed to encode bodydamages for %s: %s'):format(identifier, tostring(encoded)))
        return false
    end

    local revision = store.revision
    local generation = store.generation
    store.flushing = true

    local ok, updated = pcall(MySQL.update.await,
        'UPDATE users SET bodydamages = ? WHERE identifier = ?',
        { encoded, identifier }
    )

    store.flushing = false

    if ok and updated ~= false and updated ~= nil then
        store.nextFlushRetry = 0

        if store.generation == generation then
            store.persistedRevision = math.max(store.persistedRevision, revision)
            return true
        end

        return false
    end

    store.nextFlushRetry = GetGameTimer() + 2000
    print(('[lavie_injury:damage] Failed to persist bodydamages for %s: %s'):format(identifier, tostring(updated)))
    return false
end

function ClearBodyDamageData(serverId)
    serverId = tonumber(serverId)

    local xPlayer = serverId and ESX.GetPlayerFromId(serverId)

    if not xPlayer then
        return false, 'player_not_found'
    end

    local identifier = xPlayer.identifier

    if type(identifier) ~= 'string' or identifier == '' then
        return false, 'invalid_identifier'
    end

    local store = getDamageStore(identifier)

    store.generation = store.generation + 1
    store.data = {}
    store.pending = {}
    store.pendingHead = 1
    store.pendingTail = 0
    store.loading = false
    store.loadError = nil
    store.nextLoadRetry = 0
    store.revision = store.revision + 1
    store.nextFlushRetry = 0
    store.releaseWhenClean = false

    local hasPostClearDamage = #store.data > 0
    local playerState = Player(serverId).state
    playerState:set('hasBodyDamage', hasPostClearDamage, true)

    if not hasPostClearDamage then
        playerState:set('lastDamage', nil, true)
        playerState:set('LastDamageWeapon', nil, true)
        playerState:set('DeadByWeapon', false, true)
    end

    CreateThread(function()
        if damageStores[identifier] == store then
            flushDamage(identifier)
        end
    end)

    return true
end

exports('ClearPlayerDamages', ClearBodyDamageData)
DamageServer.ClearPlayerDamages = ClearBodyDamageData

local function collectQueueStats()
    local stats = {
        stores = 0,
        dirty = 0,
        loading = 0,
        flushing = 0,
        pending = 0,
        webhookPending = 0,
        centralPersistence = 0,
        centralQuarantine = 0,
        centralWebhookEntries = 0
    }

    for _, store in pairs(damageStores) do
        stats.stores = stats.stores + 1

        if store.revision > store.persistedRevision then
            stats.dirty = stats.dirty + 1
        end

        if store.loading then
            stats.loading = stats.loading + 1
        end

        if store.flushing then
            stats.flushing = stats.flushing + 1
        end

        stats.pending = stats.pending + math.max(store.pendingTail - store.pendingHead + 1, 0)
    end

    for _, queue in pairs(webhookQueue) do
        stats.webhookPending = stats.webhookPending + math.max(queue.tail - queue.head + 1, 0)
    end

    if GetResourceState('legacyWebhook') == 'started' then
        local ok, central = pcall(function()
            return exports.legacyWebhook:GetQueueStats()
        end)

        if ok and type(central) == 'table' then
            stats.centralPersistence = tonumber(central.persistence) or 0
            stats.centralQuarantine = tonumber(central.quarantine) or 0
            stats.centralWebhookEntries = tonumber(central.webhookEntries) or 0
        end
    end

    stats.ready = stats.dirty == 0
        and stats.loading == 0
        and stats.flushing == 0
        and stats.pending == 0
        and stats.webhookPending == 0
        and stats.centralPersistence == 0
        and stats.centralQuarantine == 0
        and stats.centralWebhookEntries == 0

    return stats
end

DamageServer.GetQueueStats = collectQueueStats
exports('GetDamageQueueStats', collectQueueStats)

RegisterCommand('bodydamageready', function(sourceId)
    if sourceId ~= 0 then
        local xPlayer = ESX.GetPlayerFromId(sourceId)
        local group = xPlayer and xPlayer.getGroup and xPlayer.getGroup() or 'user'

        if group == 'user' then
            return
        end
    end

    local stats = collectQueueStats()
    local ready = stats.ready == true

    print(('[lavie_injury:damage] Queue status: stores=%d dirty=%d loading=%d flushing=%d pending=%d webhook=%d central_persistence=%d central_quarantine=%d central_webhook=%d ready=%s'):format(
        stats.stores,
        stats.dirty,
        stats.loading,
        stats.flushing,
        stats.pending,
        stats.webhookPending,
        stats.centralPersistence,
        stats.centralQuarantine,
        stats.centralWebhookEntries,
        ready and 'true' or 'false'
    ))
end, false)

CreateThread(function()
    while true do
        Wait(DAMAGE_FLUSH_INTERVAL)

        for identifier, store in pairs(damageStores) do
            if store.revision > store.persistedRevision then
                flushDamage(identifier)
            elseif store.releaseWhenClean and not store.loading and not store.flushing and store.pendingHead > store.pendingTail then
                damageStores[identifier] = nil
            end
        end
    end
end)

local function removeWebhookBatch(data, count)
    for _ = 1, count do
        data.queue[data.head] = nil
        data.head = data.head + 1
    end

    if data.head > data.tail then
        data.queue = {}
        data.head = 1
        data.tail = 0
    end
end

local function sendWebhookDirect(url, embeds, username, token)
    if type(url) ~= 'string' or url == '' then
        return false, 2000
    end

    local payloadOk, payload = pcall(json.encode, {
        username = token and token ~= '' and nil or username,
        embeds = embeds
    })

    if not payloadOk then
        return false, 5000
    end

    local completed = false
    local succeeded = false
    local retryDelay = 2000
    local apiUrl = url
    local headers = { ['Content-Type'] = 'application/json' }

    if token and token ~= '' then
        if type(apiUrl) ~= 'string' or not apiUrl:match('^%d+$') then
            return false, 5000
        end

        apiUrl = string.format('https://discord.com/api/v10/channels/%s/messages', apiUrl)
        headers.Authorization = 'Bot ' .. token
    end

    PerformHttpRequest(apiUrl, function(statusCode, _, responseHeaders)
        succeeded = statusCode >= 200 and statusCode < 300

        if statusCode == 429 and type(responseHeaders) == 'table' then
            local retryAfter = tonumber(responseHeaders['retry-after'] or responseHeaders['Retry-After'])

            if retryAfter then
                retryDelay = math.max(math.floor(retryAfter * 1000), 1000)
            end
        end

        completed = true
    end, 'POST', payload, headers)

    local timeoutAt = GetGameTimer() + 10000

    while not completed and GetGameTimer() < timeoutAt do
        Wait(25)
    end

    return completed and succeeded, retryDelay
end

local function submitCentralWebhook(url, embeds, username)
    if GetResourceState('legacyWebhook') ~= 'started' then
        return false
    end

    local request = {
        username = username,
        category = 'body_damage',
        action = 'damage',
        embeds = embeds
    }

    if type(url) == 'string' and url ~= '' then
        request.webhook = url
    end

    local invoked, accepted = pcall(function()
        return exports.legacyWebhook:SendDiscordEmbeds(request)
    end)

    return invoked and accepted == true
end

function QueueWebhook(url, embed, username)
    if type(embed) ~= 'table' then
        return false
    end

    url = type(url) == 'string' and url or ''

    if (not DamageConfig.Webhook.BotToken or DamageConfig.Webhook.BotToken == '')
        and submitCentralWebhook(url, {embed}, username) then
        return true
    end

    local routeKey = url ~= '' and url or '__default__'

    if not webhookQueue[routeKey] then
        webhookQueue[routeKey] = {
            queue = {},
            head = 1,
            tail = 0,
            username = username,
            url = url
        }
    end

    local target = webhookQueue[routeKey]
    target.tail = target.tail + 1
    target.queue[target.tail] = embed

    if isQueueProcessing then
        return
    end

    isQueueProcessing = true

    CreateThread(function()
        while true do
            local processedAny = false

            for _, data in pairs(webhookQueue) do
                if data.head <= data.tail then
                    processedAny = true

                    local embedsToSend = {}
                    local count = math.min(data.tail - data.head + 1, 10)

                    for index = 1, count do
                        embedsToSend[index] = data.queue[data.head + index - 1]
                    end

                    local accepted = false
                    local retryDelay = 2000
                    local token = DamageConfig.Webhook.BotToken

                    if not token or token == '' then
                        accepted = submitCentralWebhook(data.url, embedsToSend, data.username)
                    end

                    if not accepted then
                        accepted, retryDelay = sendWebhookDirect(data.url, embedsToSend, data.username, token)
                    end

                    if accepted then
                        removeWebhookBatch(data, count)
                    else
                        Wait(retryDelay)
                    end
                end
            end

            if not processedAny then
                isQueueProcessing = false
                break
            end

            Wait(2000)
        end
    end)
end

local boneLabels = {}
local boneZones = {}
local displayZones = {}
local criticalBones = {
    [39317] = true,
    [31086] = true,
    [12844] = true,
    [65068] = true,
    [58331] = true,
    [45750] = true,
    [25260] = true,
    [57597] = true,
    [23553] = true
}
local incapacitationWeapons = {
    [joaat('WEAPON_STUNGUN')] = true,
    [joaat('WEAPON_STUNGUN_MP')] = true,
    [joaat('WEAPON_Y2')] = true,
    [joaat('WEAPON_C9')] = true
}

for label, boneId in pairs(DamageConfig.ExtendedBodypart) do
    boneLabels[tonumber(boneId)] = DamageUtil.Function.FirstToUpper(label)
end

for zone, bones in pairs(DamageConfig.Bodypart) do
    for index = 1, #bones do
        local boneId = tonumber(bones[index])
        boneZones[boneId] = zone
    end
end

for boneId, label in pairs(boneLabels) do
    local zone = boneZones[boneId]

    if boneId == 39317 then
        displayZones[boneId] = 'neck'
    elseif zone == 'hand' then
        if label:find('Trái', 1, true) then
            displayZones[boneId] = 'left-arm'
        elseif label:find('Phải', 1, true) or boneId == 58866 then
            displayZones[boneId] = 'right-arm'
        end
    elseif zone == 'leg' then
        if label:find('Trái', 1, true) then
            displayZones[boneId] = 'left-leg'
        elseif label:find('Phải', 1, true) then
            displayZones[boneId] = 'right-leg'
        end
    elseif zone == 'head' or zone == 'torso' then
        displayZones[boneId] = zone
    end
end

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

local function getServerHealth(playerId)
    local ped = GetPlayerPed(playerId)

    if not ped or ped == 0 then
        return nil
    end

    local health = tonumber(GetEntityHealth(ped))

    if isFiniteNumber(health) then
        return health
    end

    return nil
end

local function consumeDamageRate(sourceId)
    if sourceId == 0 then
        return true
    end

    local now = GetGameTimer()
    local rate = damageRates[sourceId]
    local limit = DamageConfig.Runtime.DamageRateLimit or 300
    local window = DamageConfig.Runtime.DamageRateWindow or 5000

    if not rate then
        rate = { tokens = limit, lastUpdate = now, logged = false }
        damageRates[sourceId] = rate
    else
        local elapsed = now - rate.lastUpdate
        if elapsed > 0 then
            local addTokens = elapsed * (limit / window)
            rate.tokens = math.min(limit, rate.tokens + addTokens)
            rate.lastUpdate = now
        end
    end

    if rate.tokens < 1 then
        if not rate.logged then
            rate.logged = true
            print(('[lavie_injury:damage] Rejected damage rate overflow from player %s'):format(sourceId))
        end
        return false
    end

    rate.tokens = rate.tokens - 1
    if rate.tokens >= 20 then
        rate.logged = false
    end

    return true
end

local function getDownedStatus(playerId)
    local state = Player(playerId).state

    if state.Dead and state.Dead.Status then
        return 3
    end

    if state.Injured and state.Injured.Status then
        return 2
    end

    if state.Helpup and state.Helpup.Status then
        return 1
    end

    return 0
end

local function statusLabel(status)
    if status == 3 then
        return 'Chết'
    end

    if status == 2 then
        return 'Bị Thương'
    end

    return 'Bị Thương Nhẹ'
end

local function resolveRecordStatus(injuryStatus, damage, caused)
    if injuryStatus and injuryStatus > 0 then
        return injuryStatus
    end

    local causedName = tostring(caused or '')
    local causedLower = causedName:lower()
    local isGun = causedName:find('Đạn', 1, true)
        or causedName:find('đạn', 1, true)
        or causedLower:find('ammo', 1, true)

    if damage >= 15 or isGun then
        return 2
    end

    return 1
end

local function resolveDisplaySeverity(statusCode, damage, warning)
    if statusCode == 3 then
        return 3
    end

    if statusCode == 2 or damage >= 20 or warning or damage >= 50 then
        return 2
    end

    return 1
end

local function rememberVerifiedHit(victimId, attackerId, data)
    victimId = tonumber(victimId)
    attackerId = tonumber(attackerId)

    if attackerId ~= nil
        and (not isFiniteNumber(attackerId)
            or attackerId % 1 ~= 0
            or attackerId < 1
            or attackerId > 65535) then
        attackerId = nil
    end

    if not victimId or not attackerId or victimId == attackerId or type(data) ~= 'table' then
        return
    end

    local xAttacker = ESX.GetPlayerFromId(attackerId)
    local attackerIdentifier = xAttacker and xAttacker.identifier

    if type(attackerIdentifier) ~= 'string' or attackerIdentifier == '' then
        return
    end

    local _, weaponHash = DamageUtil.Function.NormalizeWeaponHash(data.weaponType)

    if not weaponHash then
        return
    end

    local hits = verifiedHits[victimId]

    if not hits then
        hits = { head = 1, tail = 0 }
        verifiedHits[victimId] = hits
    end

    hits.tail = hits.tail + 1
    hits[hits.tail] = {
        attackerId = attackerId,
        attackerIdentifier = attackerIdentifier,
        weaponHash = weaponHash,
        hitComponent = tonumber(data.hitComponent),
        willKill = data.willKill == true,
        recordedAt = GetGameTimer()
    }

    while hits.tail - hits.head + 1 > 64 do
        hits[hits.head] = nil
        hits.head = hits.head + 1
    end
end

function DamageServer.RegisterTrustedK9Hit(victimId, attackerId, weaponHash, bone, invokingResource)
    invokingResource = invokingResource or GetInvokingResource()
    if invokingResource ~= 'k9model' then return false end
    victimId = tonumber(victimId)
    attackerId = tonumber(attackerId)
    bone = tonumber(bone)
    local _, unsignedHash = DamageUtil.Function.NormalizeWeaponHash(weaponHash)
    if not victimId or not attackerId or victimId == attackerId or not bone or bone % 1 ~= 0 then return false end
    if unsignedHash ~= (`WEAPON_ANIMAL` & 0xFFFFFFFF) or not boneZones[bone] then return false end
    local victim = ESX.GetPlayerFromId(victimId)
    local attacker = ESX.GetPlayerFromId(attackerId)
    if not victim or not attacker or GetPlayerRoutingBucket(victimId) ~= GetPlayerRoutingBucket(attackerId) then return false end
    local victimPed = GetPlayerPed(victimId)
    local attackerPed = GetPlayerPed(attackerId)
    if victimPed == 0 or attackerPed == 0 or #(GetEntityCoords(victimPed) - GetEntityCoords(attackerPed)) > 100.0 then return false end
    rememberVerifiedHit(victimId, attackerId, {
        weaponType = unsignedHash,
        hitComponent = bone,
        willKill = false
    })
    return true
end

exports('RegisterTrustedK9Hit', function(victimId, attackerId, weaponHash, bone, forwardedCaller)
    local invokingResource = GetInvokingResource()

    if invokingResource == 'lavie_bodydamages' and forwardedCaller == 'k9model' then
        invokingResource = forwardedCaller
    end

    return DamageServer.RegisterTrustedK9Hit(victimId, attackerId, weaponHash, bone, invokingResource)
end)

AddEventHandler('weaponDamageEvent', function(sender, data)
    if not DamageConfig.Bodydamages.Enable or type(data) ~= 'table' then
        return
    end

    local networkIds = {}
    local seen = {}

    if tonumber(data.hitGlobalId) then
        networkIds[#networkIds + 1] = tonumber(data.hitGlobalId)
    end

    if type(data.hitGlobalIds) == 'table' then
        for index = 1, #data.hitGlobalIds do
            local networkId = tonumber(data.hitGlobalIds[index])

            if networkId then
                networkIds[#networkIds + 1] = networkId
            end
        end
    end

    for index = 1, #networkIds do
        local entity = NetworkGetEntityFromNetworkId(networkIds[index])

        if entity and entity ~= 0 then
            local victimId = tonumber(NetworkGetEntityOwner(entity))

            if victimId and victimId > 0 and not seen[victimId] and GetPlayerPed(victimId) == entity then
                seen[victimId] = true
                rememberVerifiedHit(victimId, sender, data)
            end
        end
    end
end)

local function consumeCorrelatedHit(victimId, claimedAttackerId, weaponHash, exactOnly)
    local hits = verifiedHits[victimId]

    if not hits then
        return nil
    end

    local now = GetGameTimer()
    local exactIndex
    local sameAttackerIndex
    local sameWeaponIndex

    for index = hits.head, hits.tail do
        local hit = hits[index]

        if hit then
            if now - hit.recordedAt > 2500 then
                hits[index] = nil
                hits.head = index + 1
            else
                if claimedAttackerId and hit.attackerId == claimedAttackerId and hit.weaponHash == weaponHash then
                    exactIndex = index
                    break
                end

                if claimedAttackerId and hit.attackerId == claimedAttackerId then
                    sameAttackerIndex = sameAttackerIndex or index
                end

                if hit.weaponHash == weaponHash then
                    sameWeaponIndex = sameWeaponIndex or index
                end
            end
        end
    end

    local matchIndex = exactIndex

    if not matchIndex and not exactOnly then
        matchIndex = sameAttackerIndex or sameWeaponIndex
    end

    if not matchIndex then
        if hits.head > hits.tail then
            verifiedHits[victimId] = nil
        end

        return nil
    end

    local hit = hits[matchIndex]
    hits[matchIndex] = nil

    if matchIndex == hits.head then
        while hits.head <= hits.tail and not hits[hits.head] do
            hits.head = hits.head + 1
        end
    end

    if hits.head > hits.tail then
        verifiedHits[victimId] = nil
    end

    hit.exact = exactIndex ~= nil
    return hit
end

local function handleSetPlayerDamages(victimId, attackerId, hash, bone, damage, dist, wouldDown, _, diedInVehicle, incidentType)
    if not DamageConfig.Bodydamages.Enable then
        return
    end

    local src = tonumber(source) or 0
    victimId = tonumber(victimId)

    if not victimId or src ~= 0 and victimId ~= src then
        print(('[lavie_injury:damage] Rejected mismatched victim %s from player %s'):format(tostring(victimId), src))
        return
    end

    CreateThread(function()
        local xPlayer = ESX.GetPlayerFromId(victimId)

        if not xPlayer or type(xPlayer.identifier) ~= 'string' or xPlayer.identifier == '' then
            return
        end

        local victimIdentifier = xPlayer.identifier

        local rawHash = type(hash) == 'number' and hash or nil
        damage = tonumber(damage)
        dist = dist == nil and 0.0 or tonumber(dist)
        bone = bone == nil and 0 or tonumber(bone)
        attackerId = tonumber(attackerId)

        if attackerId ~= nil
            and (not isFiniteNumber(attackerId)
                or attackerId % 1 ~= 0
                or attackerId < 1
                or attackerId > 65535) then
            attackerId = nil
        end

        local claimedAttackerId = attackerId
        local signedHash, unsignedHash = DamageUtil.Function.NormalizeWeaponHash(rawHash)
        local claimedIncapacitation = incidentType == 'incapacitation'
            and signedHash
            and (incapacitationWeapons[signedHash] or incapacitationWeapons[unsignedHash]) == true

        if not isFiniteNumber(damage)
            or not isFiniteNumber(dist)
            or not isFiniteNumber(bone)
            or not signedHash
            or damage < 0
            or damage == 0 and not claimedIncapacitation
            or damage > 500
            or dist < 0
            or dist > 1000
            or bone < 0
            or bone > 65535
            or bone % 1 ~= 0 then
            print(string.format('[lavie_injury:damage] Rejected invalid damage payload from player %s | Wep: %s (Raw: %s) | Dmg: %s | Dist: %s | Bone: %s | AttackerId: %s | IncidentType: %s',
                tostring(src), tostring(signedHash), tostring(rawHash), tostring(damage), tostring(dist), tostring(bone), tostring(claimedAttackerId), tostring(incidentType)))
            return
        end

        local weaponHash = unsignedHash or signedHash
        local correlationWaited = false
        local correlatedHit = consumeCorrelatedHit(victimId, attackerId, weaponHash, true)

        if not correlatedHit and attackerId and attackerId > 0 and attackerId ~= victimId then
            Wait(100)
            correlationWaited = true
            xPlayer = getPlayerByIdentity(victimId, victimIdentifier)

            if not xPlayer then
                return
            end

            correlatedHit = consumeCorrelatedHit(victimId, attackerId, weaponHash, true)
        end

        if not correlatedHit then
            correlatedHit = consumeCorrelatedHit(victimId, attackerId, weaponHash, false)
        end

        local correlationExact = correlatedHit and correlatedHit.exact == true or false
        local weaponCorrelated = correlatedHit and correlatedHit.weaponHash == weaponHash or false
        local xAttacker
        local correlatedAttackerIdentifier = correlatedHit and correlatedHit.attackerIdentifier or nil
        local attackerIdentityVerified = false
        local attackerIdentityMismatch = false
        local attackerPositionVerified = false

        if attackerId and attackerId > 0 and attackerId ~= victimId then
            xAttacker = ESX.GetPlayerFromId(attackerId)

            if correlationExact then
                attackerIdentityVerified = xAttacker ~= nil
                    and type(correlatedAttackerIdentifier) == 'string'
                    and correlatedAttackerIdentifier ~= ''
                    and xAttacker.identifier == correlatedAttackerIdentifier
                attackerIdentityMismatch = not attackerIdentityVerified
            end

            if xAttacker and GetPlayerRoutingBucket(attackerId) == GetPlayerRoutingBucket(victimId) then
                local victimPed = GetPlayerPed(victimId)
                local attackerPed = GetPlayerPed(attackerId)

                if victimPed ~= 0 and attackerPed ~= 0 then
                    dist = #(GetEntityCoords(victimPed) - GetEntityCoords(attackerPed))
                    attackerPositionVerified = true
                end
            end
        end

        local attackerVerified = correlationExact and attackerIdentityVerified and attackerPositionVerified

        if not attackerPositionVerified or attackerIdentityMismatch then
            attackerId = nil
            xAttacker = nil
        end

        local isIncapacitation = claimedIncapacitation and (src == 0 or attackerVerified and weaponCorrelated)

        if damage == 0 and not isIncapacitation then
            print(('[lavie_injury:damage] Rejected unverified zero-damage incapacitation from player %s'):format(src))
            return
        end

        if not consumeDamageRate(src) then
            return
        end

        local claimedWouldDown = wouldDown == true
        local serverHealth = getServerHealth(victimId)

        if claimedWouldDown
            and src ~= 0
            and not isIncapacitation
            and not attackerVerified
            and (serverHealth == nil or serverHealth > 101)
            and not correlationWaited then
            Wait(100)
            xPlayer = getPlayerByIdentity(victimId, victimIdentifier)

            if not xPlayer then
                return
            end

            serverHealth = getServerHealth(victimId)
        end

        local serverHealthVerified = serverHealth ~= nil
        local serverWouldDown = serverHealthVerified and serverHealth <= 101 or false
        local correlatedWillKill = correlatedHit and correlatedHit.willKill == true or false
        local effectiveWouldDown = not isIncapacitation
            and claimedWouldDown
            and (src == 0 or attackerVerified or serverWouldDown)
            or false

        local confirmedAttackerId = attackerVerified and attackerId or nil
        local claimedBoneId = math.floor(bone)
        local correlatedBoneId

        if correlatedHit then
            local hitComponent = tonumber(correlatedHit.hitComponent)

            if isFiniteNumber(hitComponent)
                and hitComponent % 1 == 0
                and hitComponent >= 0
                and hitComponent <= 65535
                and boneZones[hitComponent] then
                correlatedBoneId = math.floor(hitComponent)
            end
        end

        local boneVerified = correlationExact and correlatedBoneId ~= nil
        local boneMismatch = boneVerified and correlatedBoneId ~= claimedBoneId or false
        local rawBone = boneVerified and correlatedBoneId or claimedBoneId
        local bodyPart = boneZones[rawBone] or 'torso'
        local displayZone = displayZones[rawBone]
        local boneName = boneLabels[rawBone]

        if not boneName then
            boneName = rawBone == 0 and 'Toàn Thân' or ('Không Xác Định (%d)'):format(rawBone)
        end

        local weaponData = DamageUtil.Function.GetWeaponData(weaponHash)
        local caused = weaponData and weaponData.name and DamageUtil.Function.FirstToUpper(weaponData.name) or tostring(weaponHash)
        xPlayer = getPlayerByIdentity(victimId, victimIdentifier)

        if not xPlayer then
            return
        end

        local injuryStatus = getDownedStatus(victimId)

        if InjuryServer and type(InjuryServer.ProcessDamage) == 'function' then
            local ok, evaluatedStatus = pcall(function()
                return InjuryServer.ProcessDamage({
                    victimId = victimId,
                    attackerId = confirmedAttackerId,
                    attackerIdentifier = attackerVerified and correlatedAttackerIdentifier or nil,
                    claimedAttackerId = claimedAttackerId,
                    correlatedAttackerIdentifier = correlatedAttackerIdentifier,
                    attackerIdentityVerified = attackerIdentityVerified,
                    attackerIdentityMismatch = attackerIdentityMismatch,
                    correlationExact = correlationExact,
                    correlationTrusted = attackerVerified,
                    weaponHash = weaponHash,
                    bone = rawBone,
                    claimedBoneId = claimedBoneId,
                    correlatedBoneId = correlatedBoneId,
                    boneVerified = boneVerified,
                    boneMismatch = boneMismatch,
                    bodyPart = bodyPart,
                    damage = damage,
                    distance = dist,
                    claimedWouldDown = claimedWouldDown,
                    wouldDown = effectiveWouldDown,
                    serverHealth = serverHealth,
                    serverHealthVerified = serverHealthVerified,
                    serverWouldDown = serverWouldDown,
                    correlatedWillKill = correlatedWillKill,
                    incapacitation = isIncapacitation,
                    diedInVehicle = diedInVehicle == true
                })
            end)

            if ok and tonumber(evaluatedStatus) then
                injuryStatus = tonumber(evaluatedStatus)
            elseif not ok then
                print(('[lavie_injury:damage] Injury evaluator failed for player %s: %s'):format(victimId, tostring(evaluatedStatus)))
            end
        end

        xPlayer = getPlayerByIdentity(victimId, victimIdentifier)

        if not xPlayer then
            return
        end

        local warning = criticalBones[rawBone] == true
        local statusCode = resolveRecordStatus(injuryStatus, damage, caused)
        local severityCode = resolveDisplaySeverity(statusCode, damage, warning)
        local status = statusLabel(statusCode)
        local formattedDamage = string.format('%.2f', damage)
        local formattedDist = string.format('%.2f', dist)
        local attackerName = xAttacker and xAttacker.getName() or 'Không Xác Định Đối Tượng'
        local attackerIdentifier = xAttacker and xAttacker.identifier or 'Không Xác Định'
        local attackerIdText = claimedAttackerId and tostring(claimedAttackerId) or 'Không Xác Định'
        local verificationText

        if attackerIdentityMismatch then
            verificationText = 'Net hit khớp source/vũ khí nhưng identifier đối tượng đã thay đổi'
        elseif attackerVerified and boneVerified then
            if boneMismatch then
                verificationText = ('Đã đối chiếu net hit; client báo bone #%d, net hit xác nhận bone #%d'):format(
                    claimedBoneId,
                    correlatedBoneId
                )
            else
                verificationText = 'Đã đối chiếu net hit: đối tượng, vũ khí và vị trí'
            end
        elseif attackerVerified then
            verificationText = 'Đã đối chiếu đối tượng/vũ khí; vị trí do client ghi nhận'
        elseif correlationExact then
            verificationText = 'Net hit khớp source/vũ khí nhưng chưa xác minh được đối tượng hiện tại'
        elseif correlatedHit then
            verificationText = 'Net hit không khớp hoàn toàn'
        elseif claimedAttackerId then
            verificationText = 'Chưa đối chiếu net hit'
        else
            verificationText = 'Không áp dụng'
        end
        local content = ('**%s** đã bị tấn công bằng **%s** vào vị trí **%s** sát thương: **%s** ở khoảng cách **%sm** bởi **%s** - Tình Trạng: **%s** - Xác Minh: **%s**'):format(
            xPlayer.getName(), caused, boneName, formattedDamage, formattedDist, attackerName, status, verificationText
        )

        TriggerEvent('AdminLog:server:DamageLogs', 10889513, 'Damage Log', content)

        local embed = {
            color = 16711680,
            title = 'LOG SÁT THƯƠNG',
            fields = {
                {
                    name = 'Nạn Nhân',
                    value = string.format('Tên: %s\nID: %s\nIdentifier: %s', xPlayer.getName(), victimId, victimIdentifier),
                    inline = true
                },
                {
                    name = attackerVerified and 'Gây Ra Bởi' or 'Đối Tượng Client Ghi Nhận',
                    value = string.format('Tên: %s\nID: %s\nIdentifier: %s', attackerName, attackerIdText, attackerIdentifier),
                    inline = true
                },
                {
                    name = 'Chi Tiết',
                    value = string.format('Vũ Khí: %s\nVị Trí: %s\nSát Thương: %s\nKhoảng Cách: %sm\nTình Trạng: %s\nXác Minh: %s', caused, boneName, formattedDamage, formattedDist, status, verificationText),
                    inline = false
                }
            },
            footer = { text = os.date('%d/%m/%Y %H:%M:%S') }
        }

        QueueWebhook(DamageConfig.Webhook.Damage, embed, 'Lavie Damage Log')

        local recordedAt = os.time()

        xPlayer = getPlayerByIdentity(victimId, victimIdentifier)

        if not xPlayer then
            return
        end

        queueDamage(victimIdentifier, {
            schemaVersion = 2,
            timestamp = recordedAt,
            recordedAt = recordedAt,
            warning = warning,
            bone = boneName,
            boneId = rawBone,
            claimedBoneId = claimedBoneId,
            correlatedBoneId = correlatedBoneId,
            boneVerified = boneVerified,
            boneMismatch = boneMismatch,
            bodyPart = bodyPart,
            zoneCode = displayZone,
            damage = formattedDamage,
            damageValue = damage,
            caused = caused,
            weaponHash = weaponHash,
            attackerId = confirmedAttackerId,
            attackerIdentifier = attackerVerified and correlatedAttackerIdentifier or nil,
            claimedAttackerId = claimedAttackerId,
            attackerVerified = attackerVerified,
            correlatedAttackerIdentifier = correlatedAttackerIdentifier,
            attackerIdentityVerified = attackerIdentityVerified,
            attackerIdentityMismatch = attackerIdentityMismatch,
            weaponCorrelated = weaponCorrelated,
            hitComponent = correlatedHit and correlatedHit.hitComponent or nil,
            correlatedAttackerId = correlatedHit and correlatedHit.attackerId or nil,
            correlatedWeaponHash = correlatedHit and correlatedHit.weaponHash or nil,
            correlationExact = correlationExact,
            correlationTrusted = attackerVerified,
            claimedWouldDown = claimedWouldDown,
            effectiveWouldDown = effectiveWouldDown,
            serverHealth = serverHealth,
            serverHealthVerified = serverHealthVerified,
            serverWouldDown = serverWouldDown,
            correlatedWillKill = correlatedWillKill,
            incidentType = isIncapacitation and 'incapacitation' or nil,
            status = status,
            statusCode = statusCode,
            injuryStatusCode = injuryStatus,
            severityCode = severityCode
        })

        if not getPlayerByIdentity(victimId, victimIdentifier) then
            return
        end

        local playerState = Player(victimId).state
        playerState:set('hasBodyDamage', true, true)
        playerState:set('lastDamage', {
            damage = damage,
            hash = weaponHash,
            bone = boneName,
            boneId = rawBone,
            claimedBoneId = claimedBoneId,
            correlatedBoneId = correlatedBoneId,
            boneVerified = boneVerified,
            boneMismatch = boneMismatch,
            bodyPart = bodyPart,
            dist = dist,
            attackerId = confirmedAttackerId,
            attackerIdentifier = attackerVerified and correlatedAttackerIdentifier or nil,
            claimedAttackerId = claimedAttackerId,
            correlatedAttackerIdentifier = correlatedAttackerIdentifier,
            attackerIdentityVerified = attackerIdentityVerified,
            attackerIdentityMismatch = attackerIdentityMismatch,
            correlationExact = correlationExact,
            correlationTrusted = attackerVerified,
            claimedWouldDown = claimedWouldDown,
            effectiveWouldDown = effectiveWouldDown,
            serverHealth = serverHealth,
            serverHealthVerified = serverHealthVerified,
            serverWouldDown = serverWouldDown,
            correlatedWillKill = correlatedWillKill,
            recordedAt = recordedAt
        }, true)
    end)
end

RegisterNetEvent('lavie_injury:server:SetPlayerDamages', handleSetPlayerDamages)
RegisterNetEvent('lavie_bodydamages:server:SetPlayerDamages', handleSetPlayerDamages)

local function canClearFromClient(requesterId, victimId)
    if requesterId == victimId then
        return false
    end

    local xRequester = ESX.GetPlayerFromId(requesterId)

    if not xRequester then
        return false
    end

    local group = xRequester.getGroup and xRequester.getGroup() or 'user'
    local job = xRequester.job and xRequester.job.name

    if job ~= 'ambulance' and group == 'user' then
        return false
    end

    if getDownedStatus(victimId) > 0 then
        return false
    end

    local requesterPed = GetPlayerPed(requesterId)
    local victimPed = GetPlayerPed(victimId)

    if requesterPed == 0 or victimPed == 0 then
        return false
    end

    if GetPlayerRoutingBucket(requesterId) ~= GetPlayerRoutingBucket(victimId) then
        return false
    end

    return #(GetEntityCoords(requesterPed) - GetEntityCoords(victimPed)) <= 5.0
end

local function handleRemoveData(victimId)
    local src = tonumber(source) or 0
    victimId = tonumber(victimId)
    local xVictim = victimId and ESX.GetPlayerFromId(victimId)

    if not xVictim or type(xVictim.identifier) ~= 'string' or xVictim.identifier == '' then
        return
    end

    local victimIdentifier = xVictim.identifier
    local requesterIdentifier

    if src ~= 0 then
        local xRequester = ESX.GetPlayerFromId(src)

        if not xRequester or type(xRequester.identifier) ~= 'string' or xRequester.identifier == '' then
            return
        end

        requesterIdentifier = xRequester.identifier
    end

    if src ~= 0 and not canClearFromClient(src, victimId) then
        print(('[lavie_injury:damage] Rejected damage clear for player %s from player %s'):format(victimId, src))
        return
    end

    local ok, clearError = ClearBodyDamageData(victimId)

    if not ok then
        print(('[lavie_injury:damage] Failed to clear damage for player %s: %s'):format(victimId, tostring(clearError)))
        return
    end

    if not getPlayerByIdentity(victimId, victimIdentifier)
        or src ~= 0 and not getPlayerByIdentity(src, requesterIdentifier) then
        return
    end

    TriggerEvent('AdminLog:server:DamageLogs', 5763719, 'Damage Clear', ('Body damage của ID %s đã được xóa bởi %s'):format(victimId, src == 0 and 'server' or ('ID ' .. src)))
end

RegisterNetEvent('lavie_injury:server:RemoveDamageData', handleRemoveData)
RegisterNetEvent('lavie_bodydamages:server:RemoveData', handleRemoveData)

function DamageServer.LoadPlayer(playerId, xPlayer)
    playerId = tonumber(playerId)

    if not playerId or not xPlayer or not xPlayer.identifier then
        return
    end

    local identifier = xPlayer.identifier
    playerIdentifiers[playerId] = identifier

    CreateThread(function()
        local records = GetBodyDamageData(identifier)
        local current = ESX.GetPlayerFromId(playerId)

        if not current or current.identifier ~= identifier or type(records) ~= 'table' then
            return
        end

        Player(playerId).state:set('hasBodyDamage', #records > 0, true)
    end)
end

function DamageServer.IsPlayerReady(playerId)
    playerId = tonumber(playerId)
    local xPlayer = playerId and ESX.GetPlayerFromId(playerId)
    local identifier = xPlayer and xPlayer.identifier
    local store = identifier and damageStores[identifier]

    if not identifier then
        return false, 'invalid_player'
    end

    if not store or store.loading or not store.data then
        return false, store and store.loadError or 'loading'
    end

    return true
end

function DamageServer.ReleasePlayer(playerId)
    playerId = tonumber(playerId)
    local identifier = playerId and playerIdentifiers[playerId]

    if not identifier then
        return
    end

    playerIdentifiers[playerId] = nil
    damageRates[playerId] = nil
    verifiedHits[playerId] = nil

    local store = damageStores[identifier]

    if store then
        store.releaseWhenClean = true
        flushDamage(identifier)
    end
end

function DamageServer.FlushAll()
    local dirty = 0

    for identifier, store in pairs(damageStores) do
        if store.revision > store.persistedRevision then
            if not flushDamage(identifier) then
                dirty = dirty + 1
            end
        end
    end

    local stats = collectQueueStats()
    print(('[lavie_injury:damage] Shutdown flush complete: dirty=%d webhook=%d'):format(dirty, stats.webhookPending))
    return dirty, stats
end
