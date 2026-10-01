local REPORT_EVENT = 'Injury:server:ReportInvincibilityEpisode'
local RATE_WINDOW_SECONDS = 60
local RATE_LIMIT = 20
local MIN_HEARTBEAT_INTERVAL = 10000

local allowedPhases =
{
    enter = true,
    heartbeat = true,
    exit = true,
}

local proofKeys = { 'available', 'nativeResult', 'bullet', 'fire', 'explosion', 'collision', 'melee', 'steam', 'p7', 'drown' }
local ownerKeys = { 'appearance', 'injuryTreatment', 'vangelico', 'multicharHold', 'injuryDowned', 'god', 'noclip', 'customizationLegacy', 'genericInvincible', 'fireResistant', 'esxFreezeInferred' }
local booleanClientStateKeys = { 'dead', 'injured', 'helpup', 'isGod', 'aCoreNoclip', 'inNoclip', 'inCustomization', 'genericInvincible', 'fireResistant', 'smokeResistant', 'jailed' }
local resourceKeys = { 'lavie_injury', 'illenium-appearance', '0r-heistpack', 'op-multicharacter', 'aCore', 'rac' }
local serverStateKeys = { 'legacyInvAppearance', 'legacyInvInjuryTreatment', 'legacyInvVangelico', 'legacyInvMulticharHold', 'isGod', 'aCoreNoclip', 'inNoclip', 'inCustomization', 'invincible', 'isFireResistant', 'AdminRank' }

local rates = {}
local activeEpisodes = {}

local function finiteNumber(value, minimum, maximum)
    if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end

    if (minimum and value < minimum) or (maximum and value > maximum) then
        return nil
    end

    return value
end

local function optionalBoolean(value)
    if type(value) == 'boolean' then
        return value
    end

    return nil
end

local function finiteInteger(value, minimum, maximum)
    value = finiteNumber(value, minimum, maximum)

    if not value or value % 1 ~= 0 then
        return nil
    end

    return value
end

local function sanitizeBooleanMap(value, keys)
    if type(value) ~= 'table' then
        return nil
    end

    local result = {}

    for index = 1, #keys do
        local key = keys[index]
        result[key] = value[key] == true
    end

    return result
end

local function sanitizeCoordinates(value)
    if type(value) ~= 'table' then
        return nil
    end

    local x = finiteNumber(value.x, -100000.0, 100000.0)
    local y = finiteNumber(value.y, -100000.0, 100000.0)
    local z = finiteNumber(value.z, -100000.0, 100000.0)

    if not x or not y or not z then
        return nil
    end

    return { x = x, y = y, z = z }
end

local function sanitizeSnapshot(value)
    if type(value) ~= 'table' or type(value.ped) ~= 'table' then
        return nil
    end

    local proofs = sanitizeBooleanMap(value.proofs, proofKeys)
    local owners = sanitizeBooleanMap(value.owners, ownerKeys)
    local clientStates = sanitizeBooleanMap(value.clientStates, booleanClientStateKeys)

    if not proofs or not owners or not clientStates then
        return nil
    end

    clientStates.adminRank = finiteInteger(value.clientStates.adminRank, 0, 100) or 0

    local resources = {}
    local reportedResources = type(value.resourceStates) == 'table' and value.resourceStates or {}

    for index = 1, #resourceKeys do
        local key = resourceKeys[index]
        local state = reportedResources[key]
        resources[key] = type(state) == 'string' and state:sub(1, 24) or 'unknown'
    end

    return {
        playerInvincible = optionalBoolean(value.playerInvincible),
        entityCanBeDamaged = optionalBoolean(value.entityCanBeDamaged),
        proofs = proofs,
        ped = {
            handle = finiteInteger(value.ped.handle, 0, 2147483647),
            model = finiteInteger(value.ped.model, -2147483648, 4294967295),
            health = finiteInteger(value.ped.health, -10000, 100000),
            maxHealth = finiteInteger(value.ped.maxHealth, 0, 100000),
            armor = finiteInteger(value.ped.armor, 0, 100000),
            dead = value.ped.dead == true,
            frozen = optionalBoolean(value.ped.frozen),
            visible = optionalBoolean(value.ped.visible),
            collisionDisabled = optionalBoolean(value.ped.collisionDisabled),
        },
        coordinates = sanitizeCoordinates(value.coordinates),
        owners = owners,
        clientStates = clientStates,
        resourceStates = resources,
    }
end

local function rateAllowed(playerId)
    local now = os.time()
    local rate = rates[playerId]

    if not rate or now - rate.startedAt >= RATE_WINDOW_SECONDS then
        rate = { startedAt = now, count = 0 }
        rates[playerId] = rate
    end

    if rate.count >= RATE_LIMIT then
        return false
    end

    rate.count = rate.count + 1
    return true
end

local function getProofNames(proofs)
    local names = {}

    for index = 3, #proofKeys do
        local key = proofKeys[index]

        if proofs[key] == true then
            names[#names + 1] = key
        end
    end

    return names
end

local function getActiveOwnerNames(owners)
    local names = {}

    for index = 1, #ownerKeys do
        local key = ownerKeys[index]

        if owners[key] == true then
            names[#names + 1] = key
        end
    end

    return names
end

local function classifySnapshot(phase, snapshot)
    if phase == 'exit' then
        return 'cleared'
    end

    if snapshot.playerInvincible == true then
        return 'player_level'
    end

    if snapshot.entityCanBeDamaged == false then
        return 'entity_damage_disabled'
    end

    if #getProofNames(snapshot.proofs) > 0 then
        return 'proof_flags'
    end

    return 'unknown_client_report'
end

local function hasExpectedOwner(snapshot, serverStates, adminLevel)
    local owners = snapshot.owners
    local ownerStatePairs =
    {
        appearance = 'legacyInvAppearance',
        injuryTreatment = 'legacyInvInjuryTreatment',
        vangelico = 'legacyInvVangelico',
        multicharHold = 'legacyInvMulticharHold',
        customizationLegacy = 'inCustomization',
        genericInvincible = 'invincible',
    }

    for owner, stateKey in pairs(ownerStatePairs) do
        if owners[owner] == true and serverStates[stateKey] == true then
            return true
        end
    end

    if owners.injuryDowned == true and serverStates.injuryDowned == true then
        return true
    end

    if adminLevel > 0 and owners.god == true and serverStates.isGod == true then
        return true
    end

    if adminLevel > 0 and owners.noclip == true
        and (serverStates.aCoreNoclip == true or serverStates.inNoclip == true) then
        return true
    end

    if owners.esxFreezeInferred == true and snapshot.playerInvincible == true
        and snapshot.ped.frozen == true then
        return true
    end

    local proofNames = getProofNames(snapshot.proofs)
    return #proofNames == 1 and proofNames[1] == 'fire'
        and owners.fireResistant == true and serverStates.isFireResistant == true
end

local function hasReportedProtection(snapshot)
    if snapshot.playerInvincible == true then
        return true
    end

    if snapshot.ped.dead == true then
        return false
    end

    return snapshot.entityCanBeDamaged == false or #getProofNames(snapshot.proofs) > 0
end

local function getServerCoordinates(playerId)
    local ped = GetPlayerPed(playerId)

    if not ped or ped == 0 then
        return nil, nil
    end

    local coords = GetEntityCoords(ped)

    return {
        x = coords.x,
        y = coords.y,
        z = coords.z,
    }, {
        handle = ped,
        health = GetEntityHealth(ped),
    }
end

local function getAuthoritativeStates(playerId)
    local player = Player(playerId)

    if not player then
        return {}
    end

    local state = player.state
    local values = {}

    for index = 1, #serverStateKeys do
        local key = serverStateKeys[index]
        local value = state[key]

        if type(value) == 'boolean' or type(value) == 'number' or type(value) == 'string' then
            values[key] = value
        end
    end

    local injuryDowned = false

    for _, key in ipairs({ 'Dead', 'Injured', 'Helpup' }) do
        local injuryState = state[key]

        if type(injuryState) == 'table' and injuryState.Status == true then
            injuryDowned = true
            break
        end
    end

    values.injuryDowned = injuryDowned

    return values
end

local function getAdminLevel(playerId)
    if GetResourceState('aCore') ~= 'started' then
        return 0
    end

    local ok, level = pcall(function()
        return exports.aCore:GetAdminLevel(playerId)
    end)

    return ok and finiteInteger(level, 0, 100) or 0
end

local function persistEpisode(playerId, episodeId, phase, sampledAt, snapshot)
    local xPlayer = ESX.GetPlayerFromId(playerId)

    if not xPlayer then
        return
    end

    local coordinates, serverPed = getServerCoordinates(playerId)
    local group = xPlayer.getGroup and xPlayer.getGroup() or 'user'
    local adminLevel = getAdminLevel(playerId)
    local serverStates = getAuthoritativeStates(playerId)
    local classification = classifySnapshot(phase, snapshot)
    local expectedOwner = phase ~= 'exit' and hasExpectedOwner(snapshot, serverStates, adminLevel)
    local characterName = xPlayer.getName and xPlayer.getName() or GetPlayerName(playerId)
    local identifier = xPlayer.identifier
    local license = xPlayer.license or GetPlayerIdentifierByType(playerId, 'license')
    local status = phase == 'exit' and 'observed' or expectedOwner and 'expected' or 'unexpected'
    local requestId = ('inv:%s:%s:%s:%s'):format(playerId, episodeId, phase, sampledAt)
    local sendDiscord = phase ~= 'heartbeat'
    local activeOwners = getActiveOwnerNames(snapshot.owners)
    local activeProofs = getProofNames(snapshot.proofs)
    local payload = {
        category = 'player_state',
        action = 'invincibility_' .. phase,
        status = status,
        sourceResource = GetCurrentResourceName(),
        reason = classification,
        route = 'invincibility',
        title = ('Godmode Diagnostic - %s'):format(phase:upper()),
        message = ('Episode: %s\nGroup: %s | Admin level: %s | Expected owner: %s\nOwners: %s\nProofs: %s\nPlayer invincible: %s | Entity damageable: %s'):format(
            episodeId,
            group,
            adminLevel,
            tostring(expectedOwner),
            #activeOwners > 0 and table.concat(activeOwners, ', ') or 'none',
            #activeProofs > 0 and table.concat(activeProofs, ', ') or 'none',
            tostring(snapshot.playerInvincible),
            tostring(snapshot.entityCanBeDamaged)
        ),
        username = 'Godmode Diagnostics',
        color = status == 'unexpected' and 15158332 or phase == 'exit' and 3447003 or 3066993,
        requestId = requestId,
        idempotencyKey = requestId,
        player = {
            id = playerId,
            name = characterName,
            identifier = identifier,
            license = license,
        },
        coordinates = coordinates,
        context = {
            diagnosticVersion = 1,
            episodeId = episodeId,
            phase = phase,
            classification = classification,
            expectedOwner = expectedOwner,
            connectionName = GetPlayerName(playerId),
            group = group,
            adminLevel = adminLevel,
            routingBucket = GetPlayerRoutingBucket(playerId),
            serverPed = serverPed,
            serverStates = serverStates,
            clientReported = snapshot,
        },
        discord = sendDiscord,
    }

    local ok, accepted, eventId = pcall(function()
        return exports.legacyWebhook:AuditTransaction(payload)
    end)

    if not ok or accepted ~= true then
        print(('[lavie_injury] Failed to persist invincibility diagnostic for player %s episode %s (%s)'):format(playerId, episodeId, tostring(eventId or accepted)))
    elseif phase == 'enter' and not expectedOwner then
        print(('[lavie_injury] Unexpected invincibility episode %s for %s [%s], classification=%s'):format(episodeId, characterName, playerId, classification))
    end
end

RegisterNetEvent(REPORT_EVENT, function(payload)
    local playerId = source

    if type(payload) ~= 'table' or not rateAllowed(playerId) then
        return
    end

    local episodeId = type(payload.episodeId) == 'string' and payload.episodeId or nil
    local phase = type(payload.phase) == 'string' and payload.phase or nil
    local sampledAt = finiteInteger(payload.sampledAt, 0, 4294967295)

    if not episodeId or #episodeId < 3 or #episodeId > 64 or not episodeId:match('^[%w:._%-]+$')
        or not allowedPhases[phase] or not sampledAt then
        return
    end

    local snapshot = sanitizeSnapshot(payload.snapshot)

    if not snapshot then
        return
    end

    local reportedProtection = hasReportedProtection(snapshot)

    if (phase == 'exit' and reportedProtection) or (phase ~= 'exit' and not reportedProtection) then
        return
    end

    local now = GetGameTimer()
    local active = activeEpisodes[playerId]

    if phase == 'enter' then
        if active and active.id == episodeId then
            return
        end

        activeEpisodes[playerId] = {
            id = episodeId,
            lastHeartbeat = now,
        }
    elseif not active or active.id ~= episodeId then
        return
    elseif phase == 'heartbeat' then
        if now - active.lastHeartbeat < MIN_HEARTBEAT_INTERVAL then
            return
        end

        active.lastHeartbeat = now
    else
        activeEpisodes[playerId] = nil
    end

    persistEpisode(playerId, episodeId, phase, sampledAt, snapshot)
end)

AddEventHandler('playerDropped', function()
    rates[source] = nil
    activeEpisodes[source] = nil
end)
