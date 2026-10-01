local ESX = exports.es_extended:getSharedObject()
local isOpen = false
local lastInputAt = GetGameTimer()
local lastCoords
local challengeOpen = false
local dailyPed

local function drawNpcLabel(ped, label)
    if not ped or not DoesEntityExist(ped) then
        return
    end

    local coords = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.35)
    local onScreen, screenX, screenY = World3dToScreen2d(coords.x, coords.y, coords.z)

    if not onScreen then
        return
    end

    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 255)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandDisplayText(screenX, screenY)
end

local function resolvedRewards(configuredRewards)
    local output = {}
    for day, reward in pairs(configuredRewards) do
        local resolved = table.clone(reward)
        if resolved.type == 'gacha_crate' and GetResourceState('lv_gacha') == 'started' then
            local caseInfo = exports.lv_gacha:GetCaseInfo(resolved.caseId)
            if caseInfo then
                resolved.label = caseInfo.label
                resolved.image = caseInfo.image
            end
        end
        output[day] = resolved
    end
    return output
end

local function antiBotEnabled()
    return Config.AntiBot == nil or Config.AntiBot.Enabled ~= false
end

local function close()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function open()
    if Config.Enabled == false then
        TriggerEvent('lv_dailyreward:notify', 'Hệ thống điểm danh đang tắt.', 'error')
        return
    end

    ESX.TriggerServerCallback('lv_dailyreward:getState', function(state)
        if not state then return end
        isOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = 'open',
            state = state,
            rewards = {
                free = resolvedRewards(Config.DailyPass.FreeRewards),
                premium = resolvedRewards(Config.DailyPass.PrimeRewards)
            },
            pass = {
                milestones = Config.DailyPass.Milestones,
                freeLabel = Config.DailyPass.Free.Label,
                premiumLabel = Config.DailyPass.Premium.Label
            },
            title = Config.Title
        })
    end)
end

RegisterNUICallback('claim', function(_, cb)
    TriggerServerEvent('lv_dailyreward:claim')
    cb({ ok = true })
end)

RegisterNUICallback('claimPastPremium', function(data, cb)
    TriggerServerEvent('lv_dailyreward:claimPastPremium', data and data.day)
    cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb)
    close()
    cb({ ok = true })
end)

RegisterNetEvent('lv_dailyreward:claimed', function(state)
    if isOpen then SendNUIMessage({ action = 'update', state = state }) end
end)

RegisterNetEvent('lv_dailyreward:progress', function()
    if not isOpen then return end
    ESX.TriggerServerCallback('lv_dailyreward:getState', function(state)
        if state then SendNUIMessage({ action = 'update', state = state }) end
    end)
end)

RegisterNetEvent('lv_dailyreward:notify', function(message, notifyType)
    if GetResourceState('lv_notify') == 'started' then
        exports.lv_notify:Notify({ title = 'DAILY REWARD', message = message, type = notifyType })
    else
        ESX.ShowNotification(message)
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        if DoesEntityExist(ped) and not IsEntityDead(ped) then
            local coords = GetEntityCoords(ped)
            local moved = lastCoords and #(coords - lastCoords) >= 1.0 or false
            local input = IsControlPressed(0, 30) or IsControlPressed(0, 31) or
                IsControlJustPressed(0, 24) or IsControlJustPressed(0, 38) or IsControlJustPressed(0, 51)
            if moved or input then lastInputAt = GetGameTimer() end
            lastCoords = coords
        end
    end
end)

CreateThread(function()
    while true do
        Wait(30000)
        if Config.Enabled ~= false and Config.RequireOnlineTime ~= false then
            TriggerServerEvent('lv_dailyreward:activity', GetGameTimer() - lastInputAt <= 90000, IsPauseMenuActive())
        end
    end
end)

RegisterNetEvent('lv_dailyreward:challenge', function(nonce, code)
    if not antiBotEnabled() then
        TriggerServerEvent('lv_dailyreward:challengeResult', nonce, '')
        return
    end

    local reopenDaily = isOpen
    if isOpen then
        close()
        Wait(250)
    end

    challengeOpen = true
    local result = lib.inputDialog('Xác minh hoạt động', {
        { type = 'input', label = ('Nhập mã %s để tiếp tục tính giờ điểm danh'):format(code), required = true }
    }, { allowCancel = false })
    challengeOpen = false
    TriggerServerEvent('lv_dailyreward:challengeResult', nonce, result and tostring(result[1]) or '')

    if reopenDaily and Config.Enabled ~= false then
        Wait(250)
        open()
    end
end)

CreateThread(function()
    while true do
        if not challengeOpen then
            Wait(250)
        else
            Wait(0)
            DisableControlAction(0, 199, true)
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 322, true)
            if IsPauseMenuActive() then SetPauseMenuActive(false) end
        end
    end
end)
exports('openDaily', open)

CreateThread(function()
    local npcModel = `a_f_y_business_02`
    RequestModel(npcModel)
    while not HasModelLoaded(npcModel) do Wait(10) end
    local npcCoords = vector4(231.85, -815.67, 30.48, 33.57)

    dailyPed = CreatePed(4, npcModel, npcCoords.x, npcCoords.y, npcCoords.z, npcCoords.w, false, true)
    FreezeEntityPosition(dailyPed, true)
    SetEntityInvincible(dailyPed, true)
    SetBlockingOfNonTemporaryEvents(dailyPed, true)
    SetModelAsNoLongerNeeded(npcModel)

    exports.ox_target:addLocalEntity(dailyPed, {
        {
            name = 'npc_daily',
            icon = 'fas fa-calendar-check',
            label = 'Điểm Danh Hằng Ngày',
            onSelect = function()
                exports.lv_dailyreward:openDaily()
            end,
            distance = 2.5
        }
    })
end)

CreateThread(function()
    while true do
        local sleep = 1000

        if dailyPed and DoesEntityExist(dailyPed) then
            local distance = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(dailyPed))

            if distance <= 15.0 then
                sleep = 0
                drawNpcLabel(dailyPed, 'ĐIỂM DANH')
            end
        end

        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() or not dailyPed or not DoesEntityExist(dailyPed) then
        return
    end

    pcall(function()
        exports.ox_target:removeLocalEntity(dailyPed, 'npc_daily')
    end)
    DeleteEntity(dailyPed)
    dailyPed = nil
end)
