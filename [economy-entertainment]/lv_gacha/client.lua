local opened = false
local gachaPed

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

local function setOpen(state)
    opened = state
    SetNuiFocus(state, state)
    SendNUIMessage({ action = state and 'open' or 'close' })
    if state then TriggerServerEvent('lv_gacha:server:requestData') end
end

exports('openCase', function()
    setOpen(true)
end)


RegisterNetEvent('lv_gacha:client:open', function()
    setOpen(true)
end)

RegisterNetEvent('lv_gacha:client:data', function(payload)
    SendNUIMessage({ action = 'data', payload = payload })
end)

RegisterNetEvent('lv_gacha:client:result', function(payload)
    SendNUIMessage({ action = 'result', payload = payload })
end)

RegisterNetEvent('lv_gacha:client:spinFailed', function()
    SendNUIMessage({ action = 'spinFailed' })
end)

RegisterNUICallback('close', function(_, cb)
    setOpen(false)
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
    TriggerServerEvent('lv_gacha:server:requestData')
    cb({ ok = true })
end)

RegisterNUICallback('spin', function(data, cb)
    TriggerServerEvent('lv_gacha:server:spin', tostring(data.banner or ''))
    cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    if opened then
        SetNuiFocus(false, false)
    end

    if gachaPed and DoesEntityExist(gachaPed) then
        pcall(function()
            exports.ox_target:removeLocalEntity(gachaPed, 'npc_gacha')
        end)
        DeleteEntity(gachaPed)
        gachaPed = nil
    end
end)

exports('GetCaseInfo', function(caseId)
    local caseData = Config.Cases[caseId]
    if not caseData then return nil end
    return {
        caseId = caseId,
        label = caseData.label,
        image = caseData.image or caseData.inventoryIcon
    }
end)

CreateThread(function()
    local npcModel = `a_m_y_business_03`
    RequestModel(npcModel)
    while not HasModelLoaded(npcModel) do Wait(10) end
    local npcCoords = vector4(247.35, -799.92, 29.56, 67.75)

    gachaPed = CreatePed(4, npcModel, npcCoords.x, npcCoords.y, npcCoords.z, npcCoords.w, false, true)
    FreezeEntityPosition(gachaPed, true)
    SetEntityInvincible(gachaPed, true)
    SetBlockingOfNonTemporaryEvents(gachaPed, true)
    SetModelAsNoLongerNeeded(npcModel)

    exports.ox_target:addLocalEntity(gachaPed, {
        {
            name = 'npc_gacha',
            icon = 'fas fa-box-open',
            label = 'Mở Hộp Gacha',
            onSelect = function()
                TriggerEvent('lv_gacha:client:open')
            end,
            distance = 2.5
        }})
end)

CreateThread(function()
    while true do
        local sleep = 1000

        if gachaPed and DoesEntityExist(gachaPed) then
            local distance = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(gachaPed))

            if distance <= 15.0 then
                sleep = 0
                drawNpcLabel(gachaPed, 'GACHA')
            end
        end

        Wait(sleep)
    end
end)
