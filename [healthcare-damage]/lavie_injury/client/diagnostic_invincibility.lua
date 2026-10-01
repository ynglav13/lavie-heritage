local REPORT_EVENT = 'Injury:server:ReportInvincibilityEpisode'
local SAMPLE_INTERVAL = 1000
local REQUIRED_SAMPLES = 3
local HEARTBEAT_INTERVAL = 15000
local STARTUP_GRACE = 15000

local ownerStateKeys =
{
    appearance = 'legacyInvAppearance',
    injuryTreatment = 'legacyInvInjuryTreatment',
    vangelico = 'legacyInvVangelico',
    multicharHold = 'legacyInvMulticharHold',
}

local trackedResources =
{
    'lavie_injury',
    'illenium-appearance',
    '0r-heistpack',
    'op-multicharacter',
    'aCore',
    'rac',
}

local episodeSequence = 0

local function safeBoolean(native, ...)
    if type(native) ~= 'function' then
        return nil
    end

    local ok, value = pcall(native, ...)

    if not ok or type(value) ~= 'boolean' then
        return nil
    end

    return value
end

local function collectProofs(ped)
    if type(GetEntityProofs) ~= 'function' then
        return { available = false }
    end

    local values = table.pack(pcall(GetEntityProofs, ped))

    if values[1] ~= true then
        return { available = false }
    end

    -- Some artifacts expose the native BOOL return before the eight proof outputs.
    local proofOffset = values.n >= 10 and 3 or 2

    return {
        available = values.n >= 9,
        nativeResult = values.n >= 10 and values[2] == true or nil,
        bullet = values[proofOffset] == true,
        fire = values[proofOffset + 1] == true,
        explosion = values[proofOffset + 2] == true,
        collision = values[proofOffset + 3] == true,
        melee = values[proofOffset + 4] == true,
        steam = values[proofOffset + 5] == true,
        p7 = values[proofOffset + 6] == true,
        drown = values[proofOffset + 7] == true,
    }
end

local function hasProof(proofs)
    return proofs.bullet == true
        or proofs.fire == true
        or proofs.explosion == true
        or proofs.collision == true
        or proofs.melee == true
        or proofs.steam == true
        or proofs.p7 == true
        or proofs.drown == true
end

local function stateStatusEnabled(key)
    local state = LocalPlayer.state[key]
    return type(state) == 'table' and state.Status == true
end

local function collectSnapshot()
    local playerId = PlayerId()
    local ped = PlayerPedId()

    if not NetworkIsPlayerActive(playerId) or not DoesEntityExist(ped) then
        return nil
    end

    local coords = GetEntityCoords(ped)
    local playerInvincible = safeBoolean(GetPlayerInvincible, playerId)
    local entityCanBeDamaged = safeBoolean(GetEntityCanBeDamaged, ped)
    local frozen = safeBoolean(IsEntityPositionFrozen, ped)
    local collisionDisabled = safeBoolean(GetEntityCollisionDisabled, ped)
    local proofs = collectProofs(ped)
    local downed = type(IsPlayerInjuryDowned) == 'function' and IsPlayerInjuryDowned() == true
    local owners = {}

    for owner, stateKey in pairs(ownerStateKeys) do
        owners[owner] = LocalPlayer.state[stateKey] == true
    end

    owners.injuryDowned = downed
    owners.god = LocalPlayer.state.isGod == true
    owners.noclip = LocalPlayer.state.aCoreNoclip == true or LocalPlayer.state.inNoclip == true
    owners.customizationLegacy = LocalPlayer.state.inCustomization == true
    owners.genericInvincible = LocalPlayer.state.invincible == true
    owners.fireResistant = LocalPlayer.state.isFireResistant == true
    owners.esxFreezeInferred = playerInvincible == true and frozen == true

    local resources = {}

    for index = 1, #trackedResources do
        local resourceName = trackedResources[index]
        resources[resourceName] = GetResourceState(resourceName)
    end

    return {
        sampledAt = GetGameTimer(),
        playerInvincible = playerInvincible,
        entityCanBeDamaged = entityCanBeDamaged,
        proofs = proofs,
        ped = {
            handle = ped,
            model = GetEntityModel(ped),
            health = GetEntityHealth(ped),
            maxHealth = GetEntityMaxHealth(ped),
            armor = GetPedArmour(ped),
            dead = IsEntityDead(ped) == true,
            frozen = frozen,
            visible = safeBoolean(IsEntityVisible, ped),
            collisionDisabled = collisionDisabled,
        },
        coordinates = {
            x = coords.x,
            y = coords.y,
            z = coords.z,
        },
        owners = owners,
        clientStates = {
            dead = stateStatusEnabled('Dead'),
            injured = stateStatusEnabled('Injured'),
            helpup = stateStatusEnabled('Helpup'),
            isGod = LocalPlayer.state.isGod == true,
            aCoreNoclip = LocalPlayer.state.aCoreNoclip == true,
            inNoclip = LocalPlayer.state.inNoclip == true,
            inCustomization = LocalPlayer.state.inCustomization == true,
            genericInvincible = LocalPlayer.state.invincible == true,
            fireResistant = LocalPlayer.state.isFireResistant == true,
            smokeResistant = LocalPlayer.state.isSmokeResistant == true,
            jailed = LocalPlayer.state.IsJailed == true,
            adminRank = tonumber(LocalPlayer.state.AdminRank) or 0,
        },
        resourceStates = resources,
    }
end

local function hasObservedProtection(snapshot)
    if snapshot.playerInvincible == true then
        return true
    end

    if snapshot.ped.dead == true then
        return false
    end

    return snapshot.entityCanBeDamaged == false or hasProof(snapshot.proofs)
end

local function nextEpisodeId()
    episodeSequence = episodeSequence + 1

    return ('%s:%s:%s'):format(GetPlayerServerId(PlayerId()), GetGameTimer(), episodeSequence)
end

local function reportEpisode(episodeId, phase, snapshot)
    TriggerServerEvent(REPORT_EVENT, {
        episodeId = episodeId,
        phase = phase,
        sampledAt = snapshot.sampledAt,
        snapshot = snapshot,
    })
end

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do
        Wait(250)
    end

    Wait(STARTUP_GRACE)

    local candidateSamples = 0
    local activeEpisode
    local lastHeartbeat = 0

    while true do
        local snapshot = collectSnapshot()

        if snapshot and hasObservedProtection(snapshot) then
            candidateSamples = candidateSamples + 1

            if not activeEpisode and candidateSamples >= REQUIRED_SAMPLES then
                activeEpisode = nextEpisodeId()
                lastHeartbeat = GetGameTimer()
                reportEpisode(activeEpisode, 'enter', snapshot)
            elseif activeEpisode and GetGameTimer() - lastHeartbeat >= HEARTBEAT_INTERVAL then
                lastHeartbeat = GetGameTimer()
                reportEpisode(activeEpisode, 'heartbeat', snapshot)
            end
        elseif snapshot then
            candidateSamples = 0

            if activeEpisode then
                reportEpisode(activeEpisode, 'exit', snapshot)
                activeEpisode = nil
                lastHeartbeat = 0
            end
        end

        Wait(SAMPLE_INTERVAL)
    end
end)
