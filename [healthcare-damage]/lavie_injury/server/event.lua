local pendingByTarget = {}
local pendingByHelper = {}
local helpupRequestTimes = {}
local helpupSequence = 0
local HELPUP_DISTANCE = 5.0
local HELPUP_DURATION = 5000
local HELPUP_REQUEST_TTL = 20000
local HELPUP_REQUEST_COOLDOWN = 1500

local function notify(playerId, notificationType, message)
    if not InjuryServer.PlayerExists(playerId) then
        return
    end

    TriggerClientEvent('lv_notify:client:notify', playerId,
    {
        title = 'Kéo Dậy',
        message = message,
        type = notificationType,
    })
end

local function normalizeCoords(value)
    if type(value) == 'vector3' then
        if value.x == value.x and value.y == value.y and value.z == value.z
            and value.x ~= math.huge and value.x ~= -math.huge
            and value.y ~= math.huge and value.y ~= -math.huge
            and value.z ~= math.huge and value.z ~= -math.huge then
            return value
        end

        return nil
    end

    if type(value) ~= 'table' then
        return nil
    end

    local x = tonumber(value.x or value.X or value[1])
    local y = tonumber(value.y or value.Y or value[2])
    local z = tonumber(value.z or value.Z or value[3])

    if not x or not y or not z
        or x ~= x or y ~= y or z ~= z
        or x == math.huge or x == -math.huge
        or y == math.huge or y == -math.huge
        or z == math.huge or z == -math.huge then
        return nil
    end

    return vector3(x, y, z)
end

local function processBaseeventsFallback(victimId, weaponHash, fatalPart, coords, killerId, reason, killerType)
    victimId = tonumber(victimId)

    if not victimId or not InjuryServer.PlayerExists(victimId) then
        return
    end

    Wait(250)

    if not InjuryServer.PlayerExists(victimId) then
        return
    end

    if InjuryServer.ConsumeBodydamageFallback(victimId, weaponHash, fatalPart) then
        return
    end

    local ped = GetPlayerPed(victimId)

    if ped == 0 or GetEntityHealth(ped) > 101 then
        return
    end

    InjuryServer.ProcessDamage(
    {
        victimId = victimId,
        claimedKillerId = tonumber(killerId),
        weaponHash = weaponHash or 0,
        fatalPart = fatalPart,
        wouldDown = true,
        diedInVehicle = ped ~= 0 and GetVehiclePedIsIn(ped, false) ~= 0 or false,
        coords = normalizeCoords(coords),
        reason = reason,
        killerType = type(killerType) == 'number' and killerType or type(killerType) == 'string' and killerType:sub(1, 64) or nil,
    })
end

RegisterNetEvent('baseevents:onPlayerDied', function(killerType, position, fatalPart)
    local victimId = source
    local ped = GetPlayerPed(victimId)
    local weaponHash = 0

    if ped ~= 0 and type(GetPedCauseOfDeath) == 'function' then
        local ok, cause = pcall(GetPedCauseOfDeath, ped)

        if ok and tonumber(cause) then
            weaponHash = cause
        end
    end

    processBaseeventsFallback(victimId, weaponHash, fatalPart, position, nil, 'baseevents_died', killerType)
end)

RegisterNetEvent('baseevents:onPlayerKilled', function(killerId, deathData)
    deathData = type(deathData) == 'table' and deathData or {}

    processBaseeventsFallback(
        source,
        deathData.weaponhash or deathData.weaponHash or deathData.deathCause or 0,
        deathData.fatalPart or deathData.bodyPart,
        deathData.deathCoords or deathData.deathpos,
        killerId,
        'baseevents_killed'
    )
end)

local safeEvents =
{
    'Injury:server:SetPlayerStatus',
    'Injury:server:FinePlayerCash',
    'Injury:server:ClearInventoryOnRespawn',
    'Injury:server:RequestHelpUp',
    'Injury:server:ConfirmHelpUp',
    'Injury:server:RefuseHelpUp',
    'Injury:server:CarryDrag:Request',
    'Injury:server:CarryDrag:Stop',
    'Injury:server:PutInVehicle',
    'Injury:server:PullOutVehicle',
    'Injury:server:ReportInvincibilityEpisode',
}

AddEventHandler('fg:ExportsLoaded', function(resourceName, scope)
    if scope ~= '*' and scope ~= GetCurrentResourceName() then
        return
    end

    if type(resourceName) ~= 'string' or resourceName == '' then
        return
    end

    for index = 1, #safeEvents do
        local eventName = safeEvents[index]
        local ok, registered, registrationError = pcall(function()
            return exports[resourceName]:RegisterSafeEvent(eventName,
            {
                ban = true,
                log = true,
            }, false)
        end)

        if not ok or registered == false then
            print(('[lavie_injury] Safe-event registration failed for %s: %s'):format(eventName, tostring(registrationError or registered)))
        end
    end
end)

RegisterNetEvent('Injury:server:SetPlayerStatus', function(targetId, status, enabled)
    local requesterId = source
    local requester = ESX.GetPlayerFromId(requesterId)
    targetId = tonumber(targetId)
    status = tonumber(status)

    if not requester or not targetId or not status or status % 1 ~= 0 or status < 0 or status > 3 then
        return
    end

    local group = requester.getGroup and requester.getGroup() or 'user'

    if group ~= 'admin' and group ~= 'superadmin' then
        print(('[lavie_injury] Rejected status override from player %s'):format(requesterId))
        return
    end

    if not InjuryServer.PlayerExists(targetId) then
        return
    end

    if enabled == false or status == 0 then
        InjuryServer.ClearPlayerStatus(targetId, 'admin_clear', {allowCorruptRepair = true})
        return
    end

    InjuryServer.SetPlayerStatus(targetId, status,
    {
        reason = 'admin_override',
        actorId = requesterId,
        allowCorruptRepair = true,
    })
end)

RegisterNetEvent('Injury:server:FinePlayerCash', function()
    notify(source, 'error', 'Yêu cầu viện phí cũ không còn hợp lệ, hãy dùng lại lệnh hồi phục')
end)

RegisterNetEvent('Injury:server:ClearInventoryOnRespawn', function()
    notify(source, 'error', 'Yêu cầu hồi sinh cũ không còn hợp lệ, hãy dùng lại lệnh /respawnme')
end)

local function clearPending(pending)
    if not pending then
        return
    end

    if pendingByTarget[pending.target] == pending then
        pendingByTarget[pending.target] = nil
    end

    if pendingByHelper[pending.helper] == pending then
        pendingByHelper[pending.helper] = nil
    end
end

local function stopHelpupAnimations(pending)
    if InjuryServer.PlayerExists(pending.helper) then
        TriggerClientEvent('lavie_injury:client:SetHelpUpAnimation', pending.helper, false)
    end

    if InjuryServer.PlayerExists(pending.target) then
        TriggerClientEvent('lavie_injury:client:SetHelpUpAnimation2', pending.target, false)
    end
end

local function cancelPending(pending, message)
    if not pending or pending.cancelled then
        return
    end

    pending.cancelled = true
    clearPending(pending)

    if pending.processing then
        stopHelpupAnimations(pending)
    end

    if message then
        notify(pending.helper, 'error', message)
    end
end

local function cancelPendingForPlayer(playerId, message)
    playerId = tonumber(playerId)

    if not playerId then
        return
    end

    local pending = pendingByTarget[playerId] or pendingByHelper[playerId]

    if pending then
        cancelPending(pending, message)
    end
end

local function validateHelpupPair(helperId, targetId, targetVersion)
    if helperId == targetId
        or not InjuryServer.PlayerExists(helperId)
        or not InjuryServer.PlayerExists(targetId) then
        return false
    end

    if not InjuryServer.IsPlayerReady(helperId) or not InjuryServer.IsPlayerReady(targetId) then
        return false
    end

    local helperStatus = InjuryServer.GetPlayerStatus(helperId)
    local targetStatus = InjuryServer.GetPlayerStatus(targetId)

    if helperStatus ~= 0 or targetStatus ~= 1 then
        return false
    end

    local targetRecord = InjuryServer.GetRecord(targetId)

    if targetVersion and (not targetRecord or targetRecord.version ~= targetVersion) then
        return false
    end

    return InjuryServer.ArePlayersNear(helperId, targetId, HELPUP_DISTANCE)
end

RegisterNetEvent('Injury:server:RequestHelpUp', function(firstArgument, secondArgument)
    local helperId = source
    local targetId = tonumber(secondArgument or firstArgument)
    local now = GetGameTimer()
    local previousRequest = helpupRequestTimes[helperId]

    if previousRequest and now - previousRequest < HELPUP_REQUEST_COOLDOWN then
        return
    end

    helpupRequestTimes[helperId] = now

    local helperPending = pendingByHelper[helperId]

    if helperPending and now >= helperPending.expiresAt then
        cancelPending(helperPending)
        helperPending = nil
    end

    local targetPending = targetId and pendingByTarget[targetId] or nil

    if targetPending and now >= targetPending.expiresAt then
        cancelPending(targetPending)
        targetPending = nil
    end

    if not targetId or helperPending or targetPending then
        notify(helperId, 'error', 'Một yêu cầu kéo dậy khác đang được xử lý')
        return
    end

    if not validateHelpupPair(helperId, targetId) then
        notify(helperId, 'error', 'Không thể kéo người chơi này dậy tại vị trí hoặc trạng thái hiện tại')
        return
    end

    local helper = ESX.GetPlayerFromId(helperId)
    local targetRecord = InjuryServer.GetRecord(targetId)

    if not helper or not targetRecord then
        return
    end

    helpupSequence = helpupSequence + 1

    local pending =
    {
        id = helpupSequence,
        helper = helperId,
        target = targetId,
        targetVersion = targetRecord.version,
        expiresAt = now + HELPUP_REQUEST_TTL,
        processing = false,
    }

    pendingByHelper[helperId] = pending
    pendingByTarget[targetId] = pending

    TriggerClientEvent('Injury:client:ReceiveHelpUpRequest', targetId, helperId, helper.getName())

    SetTimeout(HELPUP_REQUEST_TTL, function()
        if pendingByTarget[targetId] == pending and not pending.processing then
            cancelPending(pending, 'Yêu cầu kéo dậy đã hết hạn')
        end
    end)
end)

RegisterNetEvent('Injury:server:ConfirmHelpUp', function(claimedHelperId)
    local targetId = source
    local pending = pendingByTarget[targetId]

    if not pending or pending.processing then
        return
    end

    if claimedHelperId ~= nil and tonumber(claimedHelperId) ~= pending.helper then
        return
    end

    if GetGameTimer() >= pending.expiresAt
        or not validateHelpupPair(pending.helper, targetId, pending.targetVersion) then
        cancelPending(pending, 'Yêu cầu kéo dậy không còn hợp lệ')
        return
    end

    pending.processing = true

    if type(InjuryCarryDragStopPlayer) == 'function' then
        InjuryCarryDragStopPlayer(pending.helper)
        InjuryCarryDragStopPlayer(targetId)
    end

    local helper = ESX.GetPlayerFromId(pending.helper)
    local target = ESX.GetPlayerFromId(targetId)

    if not helper or not target then
        cancelPending(pending)
        return
    end

    TriggerClientEvent('Injury:client:RemoveHelpUp', targetId)
    TriggerClientEvent('lavie_injury:client:SetHelpUpAnimation', pending.helper, true, targetId)
    TriggerClientEvent('lavie_injury:client:SetHelpUpAnimation2', targetId, true, pending.helper)
    TriggerClientEvent('custom-chat:showBubble', -1, pending.helper, ('* %s đang cố gắng kéo %s dậy'):format(helper.getName(), target.getName()),
    {
        r = 194,
        g = 162,
        b = 218,
        a = 255,
    }, 15.0, HELPUP_DURATION)
    TriggerClientEvent('custom-chat:showBubble', -1, targetId, ('* %s đang được %s kéo dậy'):format(target.getName(), helper.getName()),
    {
        r = 194,
        g = 162,
        b = 218,
        a = 255,
    }, 15.0, HELPUP_DURATION)
    TriggerClientEvent('Injury:client:ShowHelpUpProgress', pending.helper, HELPUP_DURATION, 'Đang Kéo Người Chơi Dậy...')
    TriggerClientEvent('Injury:client:ShowHelpUpProgress', targetId, HELPUP_DURATION, 'Đang Được Kéo Dậy...')

    Wait(HELPUP_DURATION)

    if pendingByTarget[targetId] ~= pending
        or pendingByHelper[pending.helper] ~= pending
        or GetGameTimer() >= pending.expiresAt
        or not validateHelpupPair(pending.helper, targetId, pending.targetVersion) then
        cancelPending(pending, 'Kéo dậy thất bại vì vị trí hoặc trạng thái đã thay đổi')
        return
    end

    clearPending(pending)
    stopHelpupAnimations(pending)

    local revived = InjuryServer.RevivePlayer(targetId,
    {
        mode = 'helpup',
        reason = 'helpup',
        health = 130,
        clearBodyDamage = true,
    })

    if not revived then
        notify(pending.helper, 'error', 'Không thể hoàn tất kéo dậy')
    end
end)

RegisterNetEvent('Injury:server:RefuseHelpUp', function(claimedHelperId)
    local targetId = source
    local pending = pendingByTarget[targetId]

    if not pending then
        return
    end

    if claimedHelperId ~= nil and tonumber(claimedHelperId) ~= pending.helper then
        return
    end

    cancelPending(pending, 'Người đó đã từ chối được bạn kéo dậy')
end)

AddEventHandler('Injury:server:StatusChanged', function(playerId)
    cancelPendingForPlayer(playerId, 'Yêu cầu kéo dậy đã bị hủy vì trạng thái thay đổi')
end)

AddEventHandler('playerDropped', function()
    local playerId = source
    cancelPendingForPlayer(playerId)
    helpupRequestTimes[playerId] = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    local pendingRequests = {}

    for _, pending in pairs(pendingByTarget) do
        pendingRequests[#pendingRequests + 1] = pending
    end

    for index = 1, #pendingRequests do
        cancelPending(pendingRequests[index])
    end
end)
