local pairByPlayer = {}
local requestTimes = {}
local pairSequence = 0
local REQUEST_COOLDOWN = 500

local function notify(playerId, notificationType, description)
    if not InjuryServer.PlayerExists(playerId) then
        return
    end

    TriggerClientEvent('lv_notify:client:notify', playerId,
    {
        title = 'Carry/Drag',
        message = description,
        type = notificationType,
    })
end

local function clearPair(pair)
    if not pair then
        return
    end

    if pairByPlayer[pair.carrier] == pair then
        pairByPlayer[pair.carrier] = nil
    end

    if pairByPlayer[pair.target] == pair then
        pairByPlayer[pair.target] = nil
    end

    if InjuryServer.PlayerExists(pair.carrier) then
        Player(pair.carrier).state:set('InjuryCarryDrag', nil, true)
        TriggerClientEvent('Injury:client:CarryDrag:Stop', pair.carrier)
    end

    if InjuryServer.PlayerExists(pair.target) then
        Player(pair.target).state:set('InjuryCarryDrag', nil, true)
        TriggerClientEvent('Injury:client:CarryDrag:Stop', pair.target)
    end
end

local function stopByPlayer(playerId)
    playerId = tonumber(playerId)

    if not playerId then
        return false
    end

    local pair = pairByPlayer[playerId]

    if not pair then
        return false
    end

    clearPair(pair)
    return true
end

InjuryCarryDragStopPlayer = stopByPlayer

RegisterNetEvent('Injury:server:CarryDrag:Request', function(targetId, mode)
    local carrierId = source
    local now = GetGameTimer()
    local previousRequest = requestTimes[carrierId]

    if previousRequest and now - previousRequest < REQUEST_COOLDOWN then
        return
    end

    requestTimes[carrierId] = now

    if not InjuryConfig.CarryDrag.Enabled then
        return
    end

    targetId = tonumber(targetId)
    mode = tostring(mode or '')

    local modeConfig = InjuryConfig.CarryDrag.Modes[mode]

    if not targetId or not modeConfig or targetId == carrierId then
        notify(carrierId, 'error', 'Người chơi hoặc kiểu thao tác không hợp lệ')
        return
    end

    local carrier = ESX.GetPlayerFromId(carrierId)
    local target = ESX.GetPlayerFromId(targetId)

    if not carrier or not target then
        notify(carrierId, 'error', 'Người chơi không tồn tại')
        return
    end

    if not InjuryServer.IsPlayerReady(carrierId) or not InjuryServer.IsPlayerReady(targetId) then
        notify(carrierId, 'error', 'Trạng thái người chơi chưa sẵn sàng')
        return
    end

    if InjuryServer.GetPlayerStatus(carrierId) ~= 0 then
        notify(carrierId, 'error', 'Bạn đang bị thương/chết nên không thể thực hiện')
        return
    end

    if InjuryServer.GetPlayerStatus(targetId) == 0 then
        notify(carrierId, 'error', 'Người chơi này không ở trạng thái bị thương/chết')
        return
    end

    if pairByPlayer[carrierId] or pairByPlayer[targetId] then
        notify(carrierId, 'error', 'Một trong hai người đang ở trong thao tác vác/kéo khác')
        return
    end

    if not InjuryServer.ArePlayersNear(carrierId, targetId, (tonumber(InjuryConfig.CarryDrag.Distance) or 3.0) + 1.0) then
        notify(carrierId, 'error', 'Bạn không ở gần người chơi này')
        return
    end

    local carrierPed = GetPlayerPed(carrierId)
    local targetPed = GetPlayerPed(targetId)

    if carrierPed == 0
        or targetPed == 0
        or GetVehiclePedIsIn(carrierPed, false) ~= 0
        or GetVehiclePedIsIn(targetPed, false) ~= 0 then
        notify(carrierId, 'error', 'Không thể vác/kéo khi một trong hai người đang ở trên phương tiện')
        return
    end

    pairSequence = pairSequence + 1

    local pair =
    {
        id = pairSequence,
        carrier = carrierId,
        target = targetId,
        mode = mode,
    }

    pairByPlayer[carrierId] = pair
    pairByPlayer[targetId] = pair

    Player(carrierId).state:set('InjuryCarryDrag',
    {
        role = 'carrier',
        mode = mode,
        target = targetId,
        version = pair.id,
    }, true)
    Player(targetId).state:set('InjuryCarryDrag',
    {
        role = 'target',
        mode = mode,
        carrier = carrierId,
        version = pair.id,
    }, true)

    TriggerClientEvent('Injury:client:CarryDrag:StartCarrier', carrierId, targetId, mode)
    TriggerClientEvent('Injury:client:CarryDrag:StartTarget', targetId, carrierId, mode)
    TriggerClientEvent('custom-chat:showBubble', -1, carrierId, ('* %s đang %s %s'):format(carrier.getName(), modeConfig.label, target.getName()),
    {
        r = 194,
        g = 162,
        b = 218,
        a = 255,
    }, 15.0, 5000)
end)

RegisterNetEvent('Injury:server:CarryDrag:Stop', function()
    stopByPlayer(source)
end)

CreateThread(function()
    while true do
        local pairsToClear = {}
        local activePairs = 0

        for playerId, pair in pairs(pairByPlayer) do
            if playerId == pair.carrier then
                activePairs = activePairs + 1

                local valid = InjuryServer.PlayerExists(pair.carrier)
                    and InjuryServer.PlayerExists(pair.target)
                    and InjuryServer.IsPlayerReady(pair.carrier)
                    and InjuryServer.IsPlayerReady(pair.target)
                    and InjuryServer.GetPlayerStatus(pair.carrier) == 0
                    and InjuryServer.GetPlayerStatus(pair.target) ~= 0
                    and GetVehiclePedIsIn(GetPlayerPed(pair.carrier), false) == 0
                    and GetVehiclePedIsIn(GetPlayerPed(pair.target), false) == 0
                    and InjuryServer.ArePlayersNear(
                        pair.carrier,
                        pair.target,
                        (tonumber(InjuryConfig.CarryDrag.Distance) or 3.0) + 1.0
                    )

                if not valid then
                    pairsToClear[#pairsToClear + 1] = pair
                end
            end
        end

        for index = 1, #pairsToClear do
            clearPair(pairsToClear[index])
        end

        Wait(activePairs > 0 and 1000 or 3000)
    end
end)

AddEventHandler('Injury:server:StatusChanged', function(playerId, _, newStatus)
    local pair = pairByPlayer[tonumber(playerId)]

    if not pair then
        return
    end

    if playerId == pair.carrier and newStatus ~= 0 then
        clearPair(pair)
    elseif playerId == pair.target and newStatus == 0 then
        clearPair(pair)
    end
end)

AddEventHandler('playerDropped', function()
    local playerId = source
    stopByPlayer(playerId)
    requestTimes[playerId] = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    local pairsToClear = {}

    for playerId, pair in pairs(pairByPlayer) do
        if playerId == pair.carrier then
            pairsToClear[#pairsToClear + 1] = pair
        end
    end

    for index = 1, #pairsToClear do
        clearPair(pairsToClear[index])
    end
end)
