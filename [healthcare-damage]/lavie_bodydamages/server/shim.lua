local loggedCallers = {}

local function logLegacyCall(exportName)
    local caller = GetInvokingResource() or 'unknown'
    local key = ('%s:%s'):format(caller, exportName)

    if not loggedCallers[key] then
        loggedCallers[key] = true
        print(('[lavie_bodydamages] Deprecated export %s used by %s; migrate to exports.lavie_injury'):format(exportName, caller))
    end

    return caller
end

local function injuryStarted()
    return GetResourceState('lavie_injury') == 'started'
end

exports('GetPlayerDamages', function(serverId)
    logLegacyCall('GetPlayerDamages')
    if not injuryStarted() then return nil, 'lavie_injury_not_started' end
    return exports.lavie_injury:GetPlayerDamages(serverId)
end)

exports('ClearPlayerDamages', function(serverId)
    logLegacyCall('ClearPlayerDamages')
    if not injuryStarted() then return false, 'lavie_injury_not_started' end
    return exports.lavie_injury:ClearPlayerDamages(serverId)
end)

exports('GetQueueStats', function()
    logLegacyCall('GetQueueStats')
    if not injuryStarted() then return {ready = false, reason = 'lavie_injury_not_started'} end
    return exports.lavie_injury:GetDamageQueueStats()
end)

exports('RegisterTrustedK9Hit', function(victimId, attackerId, weaponHash, bone)
    local caller = logLegacyCall('RegisterTrustedK9Hit')
    if caller ~= 'k9model' or not injuryStarted() then return false end
    return exports.lavie_injury:RegisterTrustedK9Hit(victimId, attackerId, weaponHash, bone, caller)
end)

CreateThread(function()
    print('[lavie_bodydamages] Compatibility shim active; gameplay and persistence are owned by lavie_injury')
end)
