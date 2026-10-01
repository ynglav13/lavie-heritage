local open = false
local lastCadCallsign

local function closeMdt()
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openMdt(initialApp, initialTab)
    if open then
        if initialApp then
            SendNUIMessage({ action = 'navigate', app = initialApp, tab = initialTab or 'home' })
        end
        return
    end
    lib.callback('police_mdt:bootstrap', false, function(response)
        if not response or not response.ok then
            return lib.notify({ title = 'MDT', description = response and response.message or 'Không thể mở MDT.', type = 'error' })
        end
        open = true
        SetNuiFocus(true, true)
        if response.data then
            response.data.onDuty = (LocalPlayer.state.factionDuty == true)
        end
        SendNUIMessage({
            action = 'open',
            data = response.data,
            initialApp = initialApp,
            initialTab = initialTab
        })
    end)
end

RegisterNetEvent('police_mdt:client:openTab', function(appType, tabType)
    openMdt(appType or 'mdt', tabType or 'tickets')
end)

exports('openMdtWithTab', function(appType, tabType)
    openMdt(appType or 'mdt', tabType or 'tickets')
end)

RegisterCommand(MdtConfig.Command, function()
    if open then return closeMdt() end
    openMdt()
end, false)


RegisterNUICallback('close', function(_, cb)
    closeMdt()
    cb({ ok = true })
end)

RegisterNUICallback('toggleDuty', function(_, cb)
    local ok, success, newDuty
    if exports['police'] and exports['police'].toggleDuty then
        ok, success, newDuty = pcall(function()
            return exports['police']:toggleDuty()
        end)
    end

    if not ok or success == nil then
        local oldDuty = LocalPlayer.state.factionDuty == true
        TriggerEvent('police:client:toggleDuty')
        local timeout = 0
        while (LocalPlayer.state.factionDuty == true) == oldDuty and timeout < 25 do
            Wait(50)
            timeout = timeout + 1
        end
        newDuty = LocalPlayer.state.factionDuty == true
    end

    local onDuty = LocalPlayer.state.factionDuty == true
    cb({ ok = true, onDuty = onDuty })
end)

AddStateBagChangeHandler('factionDuty', ('player:%s'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
    if open then
        SendNUIMessage({ action = 'dutyChanged', onDuty = (value == true) })
    end
end)

RegisterNUICallback('request', function(data, cb)
    if data.action == 'cad911Calls' then
        return lib.callback('medic:callback:getActiveCalls', false, function(calls)
            cb({ ok = true, data = calls or {} })
        end)
    end
    if data.action == 'cad911Accept' then
        TriggerServerEvent('medic:server:acceptCall', tonumber(data.id))
        return cb({ ok = true })
    end
    if data.action == 'cad911Finish' then
        TriggerServerEvent('medic:server:finishCall', tonumber(data.id))
        return cb({ ok = true })
    end
    lib.callback('police_mdt:request', false, function(response)
        local function vehicleLabel(model)
            if type(model) == 'string' then model = tonumber(model) or joaat(model) end
            if type(model) ~= 'number' or model == 0 then return 'Không xác định' end
            local display = GetDisplayNameFromVehicleModel(model)
            if not display or display == '' or display == 'CARNOTFOUND' then return tostring(model) end
            local label = GetLabelText(display)
            return label and label ~= '' and label ~= 'NULL' and label or display
        end
        local payload = response and response.data
        local vehicles = payload and (payload.vehicles or payload)
        if type(vehicles) == 'table' then
            for _, vehicle in ipairs(vehicles) do
                if type(vehicle) == 'table' and vehicle.model then vehicle.model = vehicleLabel(vehicle.model) end
            end
        end
        if data.action == 'cadLocate' and response and response.ok and response.data then
            SetNewWaypoint(response.data.x, response.data.y)
        end
        if data.action == 'cadSaveUnit' and data.callsign ~= nil and response and response.ok and tostring(data.callsign or '') ~= tostring(lastCadCallsign or '') then
            local coords = GetEntityCoords(PlayerPedId())
            local street = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
            TriggerServerEvent('TacticalRoom:server:UpdateCallsign', tostring(data.callsign or ''), GetStreetNameFromHashKey(street))
            lastCadCallsign = tostring(data.callsign or '')
        end
        if data.action == 'cadMyUnit' and response and response.ok and response.data then
            lastCadCallsign = tostring(response.data.callsign or '')
        end
        cb(response or { ok = false, message = 'Không thể tải dữ liệu.' })
    end, data)
end)

RegisterNetEvent('police_mdt:client:boloChanged', function()
    if open then SendNUIMessage({ action = 'boloChanged' }) end
end)

RegisterNetEvent('police_mdt:client:cadChanged', function()
    if open then SendNUIMessage({ action = 'cadChanged' }) end
end)
