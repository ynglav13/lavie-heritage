local ESX = exports["es_extended"]:getSharedObject()

Citizen.CreateThread(function()
    while ESX.GetPlayerData().job == nil do
        Citizen.Wait(100)
    end
end)

local isSearching = false
local targetPlayerId = nil

local function isStateActive(stateValue)
    if type(stateValue) == 'table' and stateValue.Status == true then
        return true
    end
    if stateValue == true then
        return true
    end
    return false
end

local function getTargetLifeState(entity, targetId)
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

    if DoesEntityExist(entity) and (IsEntityDead(entity) or IsPedFatallyInjured(entity)) then
        return 'dead'
    end

    return 'alive'
end

local function isTargetDownedOrDead(entity, targetId)
    local lifeState = getTargetLifeState(entity, targetId)
    return lifeState == 'dead' or lifeState == 'injured'
end

RegisterNetEvent('lv_search:client:startSearchAnim')
AddEventHandler('lv_search:client:startSearchAnim', function(targetId)
    isSearching = true
    targetPlayerId = targetId

    Citizen.CreateThread(function()
        local ped = PlayerPedId()
        FreezeEntityPosition(ped, true)

        Citizen.Wait(500)

        local dict = 'custom@police'
        local anim = 'police'

        RequestAnimDict(dict)
        while not HasAnimDictLoaded(dict) do
            Citizen.Wait(10)
        end

        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 49, 0, false, false, false)
    end)
end)

RegisterNetEvent('lv_search:client:startTargetAnim')
AddEventHandler('lv_search:client:startTargetAnim', function()
    local ped = PlayerPedId()
    local myState = LocalPlayer.state
    if isStateActive(myState.Dead) or isStateActive(myState.Injured) or isStateActive(myState.Helpup) or myState.isDead or myState.dead or IsEntityDead(ped) then
        return
    end

    FreezeEntityPosition(ped, true)

    local dict = 'missfam5_yoga'
    local anim = 'a2_pose'

    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Citizen.Wait(10)
    end

    TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 49, 0, false, false, false)
end)

RegisterNetEvent('lv_search:client:stopTargetAnim')
AddEventHandler('lv_search:client:stopTargetAnim', function()
    local ped = PlayerPedId()
    local myState = LocalPlayer.state
    if isStateActive(myState.Dead) or isStateActive(myState.Injured) or isStateActive(myState.Helpup) or myState.isDead or myState.dead or IsEntityDead(ped) then
        return
    end

    ClearPedTasks(ped)
    FreezeEntityPosition(ped, false)
end)

AddStateBagChangeHandler('invOpen', ('player:%s'):format(GetPlayerServerId(PlayerId())), function(bagName, key, value, reserved, replicated)
    if value or not isSearching then return end

    isSearching = false

    local ped = PlayerPedId()
    ClearPedTasks(ped)
    FreezeEntityPosition(ped, false)

    if targetPlayerId then
        TriggerServerEvent('lv_search:server:stopTargetAnim', targetPlayerId)
        targetPlayerId = nil
    end
end)

local function isTargetHandsUpOrCuffed(entity, targetId)
    local targetState = Player(targetId).state
    if targetState and (targetState.handsup or targetState.handCuff or targetState.isCuffed) then
        return true
    end

    if DoesEntityExist(entity) then
        return IsEntityPlayingAnim(entity, 'missminuteman_1ig_2', 'handsup_base', 3)
            or IsEntityPlayingAnim(entity, 'missminuteman_1ig_2', 'handsup_enter', 3)
            or IsEntityPlayingAnim(entity, 'random@mugging3', 'handsup_standing_base', 3)
            or IsEntityPlayingAnim(entity, 'anim@mp_player_intuppersurrender', 'idle_a_fp', 3)
            or IsEntityPlayingAnim(entity, 'anim@mp_player_intuppersurrender', 'idle_a', 3)
            or IsEntityPlayingAnim(entity, 'mp_am_hold_up', 'handsup_base', 3)
            or IsEntityPlayingAnim(entity, 'random@busted', 'idle_a', 3)
            or IsEntityPlayingAnim(entity, 'anim@mp_rollarcoaster', 'hands_up_idle_a_player_one', 3)
    end

    return false
end

RegisterNetEvent('lv_search:client:requestStealConsent')
AddEventHandler('lv_search:client:requestStealConsent', function(robberId, robberName)
    local accepted = exports.lv_notify:Confirm({
        title = 'Yêu cầu cướp đồ',
        message = ('%s (ID: %s) muốn lục túi đồ của bạn để cướp. Bạn có đồng ý không?'):format(robberName, robberId),
        yesLabel = 'Đồng Ý',
        noLabel = 'Từ Chối'
    })

    TriggerServerEvent('lv_search:server:respondStealConsent', robberId, accepted == true)
end)

RegisterCommand('steal', function(_, args)
    local targetId = tonumber(args[1])
    local targetEntity = 0
    if not targetId then
        local closestPlayer, closestDistance = ESX.Game.GetClosestPlayer()
        if closestPlayer ~= -1 and closestDistance <= 2.5 then
            targetId = GetPlayerServerId(closestPlayer)
            targetEntity = GetPlayerPed(closestPlayer)
        end
    else
        local playerIdx = GetPlayerFromServerId(targetId)
        if playerIdx ~= -1 then
            targetEntity = GetPlayerPed(playerIdx)
        end
    end

    if not targetId or targetId <= 0 then
        return exports.lv_notify:Notify({
            title = 'Cướp đồ',
            message = 'Không tìm thấy người chơi ở gần.',
            type = 'error'
        })
    end

    local isHandsUp = isTargetHandsUpOrCuffed(targetEntity, targetId)
    TriggerServerEvent('lv_search:server:requestSteal', targetId, isHandsUp)
end, false)

Citizen.CreateThread(function()
    exports.ox_target:addGlobalPlayer({
        {
            name = 'police_search_player',
            icon = 'fas fa-search',
            label = 'Lục soát (Cảnh sát)',
            canInteract = function(entity, distance, coords, name, bone)
                if LocalPlayer.state.factionCategory ~= 'police' or not LocalPlayer.state.factionDuty then return false end
                if IsPedInAnyVehicle(PlayerPedId(), false) or IsPedInAnyVehicle(entity, false) then return false end
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                if targetId <= 0 then return false end
                return isTargetHandsUpOrCuffed(entity, targetId) or isTargetDownedOrDead(entity, targetId)
            end,
            onSelect = function(data)
                local targetEntity = data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(targetEntity))

                if targetId > 0 then
                    local isHandsUp = isTargetHandsUpOrCuffed(targetEntity, targetId)
                    exports.lv_notify:Notify({
                        title = 'Cảnh sát',
                        message = 'Đang lục soát...',
                        type = 'info'
                    })
                    TriggerServerEvent('lv_search:server:requestSearch', targetId, isHandsUp)
                else
                    exports.lv_notify:Notify({
                        title = 'Lỗi',
                        message = 'Không tìm thấy người chơi.',
                        type = 'error'
                    })
                end
            end
        },
        {
            name = 'steal_player',
            icon = 'fas fa-hand-holding',
            label = 'Cướp đồ',
            canInteract = function(entity, distance, coords, name, bone)
                if IsPedInAnyVehicle(PlayerPedId(), false) or IsPedInAnyVehicle(entity, false) then return false end
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                if targetId <= 0 then return false end
                return isTargetHandsUpOrCuffed(entity, targetId) or isTargetDownedOrDead(entity, targetId)
            end,
            onSelect = function(data)
                local targetEntity = data.entity
                local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(targetEntity))

                if targetId > 0 then
                    local isHandsUp = isTargetHandsUpOrCuffed(targetEntity, targetId)
                    TriggerServerEvent('lv_search:server:requestSteal', targetId, isHandsUp)
                else
                    exports.lv_notify:Notify({
                        title = 'Lỗi',
                        message = 'Không tìm thấy người chơi.',
                        type = 'error'
                    })
                end
            end
        }
    })
end)
