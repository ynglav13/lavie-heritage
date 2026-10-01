local legacyTimestampOffset = os.time() - os.time(os.date('!*t'))

local function canViewDamages(requesterId, targetId)
    if requesterId == targetId then
        return true
    end

    local requesterPed = GetPlayerPed(requesterId)
    local targetPed = GetPlayerPed(targetId)

    if requesterPed == 0
        or targetPed == 0
        or GetPlayerRoutingBucket(requesterId) ~= GetPlayerRoutingBucket(targetId) then
        return false
    end

    return #(GetEntityCoords(requesterPed) - GetEntityCoords(targetPed)) <= DamageConfig.Runtime.DamageViewDistance
end

local function getCurrentInjuryStatus(targetId)
    if not InjuryServer or type(InjuryServer.GetPlayerStatus) ~= 'function' then
        return nil
    end

    local ok, status, _, ready = pcall(function()
        return InjuryServer.GetPlayerStatus(targetId)
    end)

    status = tonumber(status)

    if not ok
        or ready ~= true
        or not status
        or status % 1 ~= 0
        or status < 0
        or status > 3 then
        return nil
    end

    return status
end

local function getPlayerDamagesCallback(source, serverId)
    if DamageConfig.Framework ~= 'esx' then
        return nil, os.time(), {}, 'unavailable'
    end

    source = tonumber(source)
    serverId = tonumber(serverId) or source

    local xRequester = source and ESX.GetPlayerFromId(source)
    local xTarget = serverId and ESX.GetPlayerFromId(serverId)

    if not xRequester or not xTarget then
        return nil, os.time(), {}, 'too_far'
    end

    if type(xRequester.identifier) ~= 'string'
        or xRequester.identifier == ''
        or type(xTarget.identifier) ~= 'string'
        or xTarget.identifier == ''
        or not canViewDamages(source, serverId) then
        return nil, os.time(), {}, 'too_far'
    end

    local requesterIdentifier = xRequester.identifier
    local targetIdentifier = xTarget.identifier
    local ok, cached, loadError = pcall(GetBodyDamageData, targetIdentifier)
    xRequester = ESX.GetPlayerFromId(source)
    xTarget = ESX.GetPlayerFromId(serverId)

    if not xRequester
        or not xTarget
        or xRequester.identifier ~= requesterIdentifier
        or xTarget.identifier ~= targetIdentifier
        or not canViewDamages(source, serverId) then
        return nil, os.time(), {}, 'identity_changed'
    end

    local targetName = xTarget.getName and xTarget.getName() or xTarget.name or 'Unknown'

    if not ok or type(cached) ~= 'table' then
        return targetName, os.time(), {}, loadError or 'unavailable'
    end

    local response = {}

    for index = 1, #cached do
        local sourceData = cached[index]

        if type(sourceData) == 'table' then
            local data = {}

            for key, value in pairs(sourceData) do
                data[key] = value
            end

            if not data.schemaVersion and tonumber(data.timestamp) then
                data.timestamp = tonumber(data.timestamp) + legacyTimestampOffset
            end

            local weaponData = DamageUtil.Function.GetWeaponData(data.weaponHash or data.caused)

            if weaponData and weaponData.name then
                data.caused = DamageUtil.Function.FirstToUpper(weaponData.name)
            end

            response[#response + 1] = data
        end
    end

    return targetName, os.time(), response, false, getCurrentInjuryStatus(serverId)
end

lib.callback.register('lavie_injury:callback:GetPlayerDamages', getPlayerDamagesCallback)
lib.callback.register('lavie_bodydamages:callback:GetPlayerDamages', getPlayerDamagesCallback)
