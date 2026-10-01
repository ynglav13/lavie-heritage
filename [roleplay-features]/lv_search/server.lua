local ESX = exports["es_extended"]:getSharedObject()

local allowedPoliceJobs = {
    police = true,
    sheriff = true
}

local allowedPoliceTags = {
    LSPD = true,
    LSSD = true,
    SHERIFF = true
}

local function Notify(src, message, notifyType, title)
    TriggerClientEvent('lv_notify:client:notify', src, {
        title = title or 'Steal System',
        message = message,
        type = notifyType or 'info'
    })
end

local function isStateActive(stateValue)
    if type(stateValue) == 'table' and stateValue.Status == true then
        return true
    end
    if stateValue == true then
        return true
    end
    return false
end

local function GetTargetLifeState(targetId)
    targetId = tonumber(targetId)
    if not targetId then return 'alive' end

    if GetResourceState('lavie_injury') == 'started' then
        local ok, status = pcall(function()
            return exports.lavie_injury:GetPlayerStatus(targetId)
        end)
        if ok and type(status) == 'number' then
            if status == 3 then
                return 'dead'
            elseif status == 1 or status == 2 then
                return 'injured'
            end
        end
    end

    local targetState = Player(targetId).state
    if targetState then
        if isStateActive(targetState.Dead) then
            return 'dead'
        end
        if isStateActive(targetState.Injured) or isStateActive(targetState.Helpup) or targetState.inLastStand == true then
            return 'injured'
        end
        if targetState.isDead == true or targetState.dead == true then
            return 'dead'
        end
    end

    local targetPed = GetPlayerPed(targetId)
    if targetPed ~= 0 and GetEntityHealth(targetPed) <= 0 then
        return 'dead'
    end

    return 'alive'
end

local function IsOnDutyPolice(src, xPlayer)
    local state = Player(src).state
    local jobName = xPlayer and xPlayer.job and xPlayer.job.name
    local isPoliceJob = allowedPoliceJobs[jobName] == true
    local isPoliceFaction = state.factionCategory == 'police'
    local isAllowedTag = not state.factionTag or allowedPoliceTags[state.factionTag] == true

    return state.factionDuty == true and isAllowedTag and (isPoliceFaction or isPoliceJob)
end

local function IsNearTarget(src, targetId)
    local sourcePed = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetId)

    if sourcePed == 0 or targetPed == 0 then return false end

    local sourceCoords = GetEntityCoords(sourcePed)
    local targetCoords = GetEntityCoords(targetPed)

    return #(sourceCoords - targetCoords) <= 3.0
end

RegisterNetEvent('lv_search:server:requestSearch')
AddEventHandler('lv_search:server:requestSearch', function(targetId, clientIsHandsUp)
    local src = source
    targetId = tonumber(targetId)

    if not targetId or targetId == src then return end

    local xPlayer = ESX.GetPlayerFromId(src)
    local tPlayer = ESX.GetPlayerFromId(targetId)

    if not xPlayer or not tPlayer then return end

    if not IsOnDutyPolice(src, xPlayer) then
        Notify(src, 'Bạn phải On Duty PD/SD để lục soát.', 'error', 'Cảnh sát')
        return
    end

    if not IsNearTarget(src, targetId) then
        Notify(src, 'Người chơi ở quá xa để lục soát.', 'error', 'Cảnh sát')
        return
    end

    local lifeState = GetTargetLifeState(targetId)
    local targetState = Player(targetId).state
    local isHandsUp = (targetState.handsup == true) or (clientIsHandsUp == true)
    local isCuffed = (targetState.handCuff == true) or (targetState.isCuffed == true)
    local isDowned = (lifeState == 'dead' or lifeState == 'injured')
    local targetPed = GetPlayerPed(targetId)

    if not isHandsUp and not isCuffed and not isDowned then
        Notify(src, 'Người chơi phải đang giơ tay (handsup), bị còng tay hoặc bị thương/ngất xỉu để lục soát.', 'error', 'Cảnh sát')
        return
    end

    local sourcePed = GetPlayerPed(src)

    if GetVehiclePedIsIn(sourcePed, false) ~= 0 or GetVehiclePedIsIn(targetPed, false) ~= 0 then
        Notify(src, 'Không thể lục soát khi ở trên xe.', 'error', 'Cảnh sát')
        return
    end

    TriggerClientEvent('lv_search:client:startSearchAnim', src, targetId)
    if lifeState == 'alive' then
        TriggerClientEvent('lv_search:client:startTargetAnim', targetId)
    end
    exports.ox_inventory:forceOpenInventory(src, 'player', targetId)
end)

local pendingStealRequests = {}

RegisterNetEvent('lv_search:server:requestSteal')
AddEventHandler('lv_search:server:requestSteal', function(targetId, clientIsHandsUp)
    local src = source
    targetId = tonumber(targetId)

    if not targetId or targetId == src then return end

    local xPlayer = ESX.GetPlayerFromId(src)
    local tPlayer = ESX.GetPlayerFromId(targetId)

    if not xPlayer or not tPlayer then return end

    if pendingStealRequests[src] then
        Notify(src, 'Bạn đã gửi một yêu cầu cướp đồ trước đó. Vui lòng chờ phản hồi.', 'error', 'Cướp đồ')
        return
    end

    if not IsNearTarget(src, targetId) then
        Notify(src, 'Người chơi ở quá xa để cướp đồ.', 'error', 'Cướp đồ')
        return
    end

    local targetPed = GetPlayerPed(targetId)
    local sourcePed = GetPlayerPed(src)

    if GetVehiclePedIsIn(sourcePed, false) ~= 0 or GetVehiclePedIsIn(targetPed, false) ~= 0 then
        Notify(src, 'Không thể cướp đồ khi ở trên xe.', 'error', 'Cướp đồ')
        return
    end

    local lifeState = GetTargetLifeState(targetId)
    local targetState = Player(targetId).state
    local isHandsUp = (targetState and targetState.handsup == true) or (clientIsHandsUp == true)
    local isCuffed = targetState and ((targetState.handCuff == true) or (targetState.isCuffed == true))

    -- Case 1: Chết -> Force steal luôn
    if lifeState == 'dead' then
        Notify(src, ('Đang lục túi đồ của %s (ID: %s)...'):format(tPlayer.getName(), targetId), 'info', 'Cướp đồ')
        Notify(targetId, ('%s (ID: %s) đang lục túi đồ của bạn.'):format(xPlayer.getName(), src), 'warning', 'Cướp đồ')

        TriggerClientEvent('lv_search:client:startSearchAnim', src, targetId)
        exports.ox_inventory:forceOpenInventory(src, 'player', targetId)
        return
    end

    -- Case 2: Bị thương -> Cho request steal luôn (không bắt buộc handsup/cuffed)
    -- Case 3: Bình thường -> Bắt buộc handsup hoặc cuffed
    if lifeState ~= 'injured' and not isHandsUp and not isCuffed then
        Notify(src, 'Nạn nhân phải đang giơ tay (handsup), bị còng tay hoặc bị thương/ngất xỉu.', 'error', 'Cướp đồ')
        return
    end

    pendingStealRequests[src] = targetId

    SetTimeout(20000, function()
        if pendingStealRequests[src] == targetId then
            pendingStealRequests[src] = nil
            Notify(src, 'Yêu cầu cướp đồ đã hết thời gian chờ.', 'warning', 'Cướp đồ')
        end
    end)

    local robberName = xPlayer.getName()
    local victimName = tPlayer.getName()

    if lifeState == 'injured' then
        Notify(src, ('Đã gửi yêu cầu cướp đồ đến người bị thương %s (ID: %s). Đang chờ đồng ý...'):format(victimName, targetId), 'info', 'Cướp đồ')
    else
        Notify(src, ('Đã gửi yêu cầu cướp đồ đến %s (ID: %s). Đang chờ đồng ý...'):format(victimName, targetId), 'info', 'Cướp đồ')
    end

    TriggerClientEvent('lv_search:client:requestStealConsent', targetId, src, robberName)
end)

RegisterNetEvent('lv_search:server:respondStealConsent')
AddEventHandler('lv_search:server:respondStealConsent', function(robberId, accepted)
    local targetId = source
    robberId = tonumber(robberId)

    if not robberId or pendingStealRequests[robberId] ~= targetId then return end

    pendingStealRequests[robberId] = nil

    local xPlayer = ESX.GetPlayerFromId(robberId)
    local tPlayer = ESX.GetPlayerFromId(targetId)

    if not xPlayer or not tPlayer then return end

    if not accepted then
        Notify(robberId, ('Người chơi %s (ID: %s) đã TỪ CHỐI cho bạn cướp đồ.'):format(tPlayer.getName(), targetId), 'error', 'Cướp đồ')
        Notify(targetId, 'Bạn đã TỪ CHỐI yêu cầu cướp đồ.', 'info', 'Cướp đồ')
        return
    end

    if not IsNearTarget(robberId, targetId) then
        Notify(robberId, 'Nạn nhân đã ở quá xa, không thể mở túi đồ.', 'error', 'Cướp đồ')
        Notify(targetId, 'Khoảng cách quá xa, việc cướp đồ đã hủy.', 'error', 'Cướp đồ')
        return
    end

    Notify(robberId, ('%s đã ĐỒNG Ý. Đang mở túi đồ...'):format(tPlayer.getName()), 'success', 'Cướp đồ')
    Notify(targetId, ('Bạn đã ĐỒNG Ý cho %s lục túi đồ.'):format(xPlayer.getName()), 'warning', 'Cướp đồ')

    TriggerClientEvent('lv_search:client:startSearchAnim', robberId, targetId)

    local targetLifeState = GetTargetLifeState(targetId)
    if targetLifeState == 'alive' then
        TriggerClientEvent('lv_search:client:startTargetAnim', targetId)
    end

    exports.ox_inventory:forceOpenInventory(robberId, 'player', targetId)
end)

RegisterNetEvent('lv_search:server:stopTargetAnim')
AddEventHandler('lv_search:server:stopTargetAnim', function(targetId)
    TriggerClientEvent('lv_search:client:stopTargetAnim', targetId)
end)
