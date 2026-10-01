local active
local zoneObject
local radiusBlip
local centerBlip
local insideZone = false
local isManager = false
local manualMonitor = false
local autoMonitor = false
local adminOpen = false
local adminRequested = false
local participantState
local polyDraft
local lastVehicleExit = 0

local function notify(message, notifyType, duration)
    exports['lv_notify']:Notify({
        type = notifyType or 'info',
        title = 'Turf Event',
        message = message,
        duration = duration or 4500,
    })
end

local function removeZoneObject()
    if zoneObject then
        zoneObject:destroy()
        zoneObject = nil
    end
end

local function removeBlips()
    if radiusBlip then RemoveBlip(radiusBlip) radiusBlip = nil end
    if centerBlip then RemoveBlip(centerBlip) centerBlip = nil end
end

local function sendMemberHud()
    if not active then
        SendNUIMessage({ action = 'member', visible = false })
        return
    end

    local visible = not isManager and (insideZone or participantState == 'outside' or participantState == 'eliminated')
    SendNUIMessage({
        action = 'member',
        visible = visible,
        zone = active.zone.name,
        state = active.state,
        status = participantState or (insideZone and 'inside' or 'outside'),
        allowVehicles = active.allowVehicles,
    })
end

local function updateAutoMonitor(enabled)
    enabled = enabled == true and isManager and active ~= nil
    if autoMonitor == enabled then return end
    autoMonitor = enabled
    TriggerServerEvent('legacy_turf:server:setMonitor', enabled, 'auto')
end

local function updatePresence(isInside)
    insideZone = isInside == true
    updateAutoMonitor(insideZone)
    sendMemberHud()
end

local function createZoneObject(zone)
    removeZoneObject()
    if not zone then return end

    if zone.shape == 'circle' then
        zoneObject = CircleZone:Create(vector3(zone.center.x, zone.center.y, zone.center.z), zone.radius + 0.0, {
            name = ('legacy_turf_%s'):format(zone.id),
            useZ = false,
            debugPoly = false,
        })
    else
        local points = {}
        for i = 1, #(zone.points or {}) do
            points[#points + 1] = vector2(zone.points[i].x, zone.points[i].y)
        end
        zoneObject = PolyZone:Create(points, {
            name = ('legacy_turf_%s'):format(zone.id),
            useZ = false,
            debugPoly = false,
        })
    end

    zoneObject:onPointInOut(PolyZone.getPlayerPosition, function(isInside)
        updatePresence(isInside)
    end, 300)
end

local function createBlips(zone, state)
    removeBlips()
    if not zone then return end

    local center = TurfGeometry.getCenter(zone)
    local radius = TurfGeometry.getBoundingRadius(zone)
    local color = state == 'locked' and Config.LockedBlipColor or zone.color

    radiusBlip = AddBlipForRadius(center.x, center.y, center.z, radius + 0.0)
    SetBlipColour(radiusBlip, color)
    SetBlipAlpha(radiusBlip, Config.BlipAlpha)

    centerBlip = AddBlipForCoord(center.x, center.y, center.z)
    SetBlipSprite(centerBlip, 84)
    SetBlipColour(centerBlip, color)
    SetBlipScale(centerBlip, 0.85)
    SetBlipAsShortRange(centerBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('Turf: %s [%s]'):format(zone.name, state == 'locked' and 'LOCKED' or 'OPEN'))
    EndTextCommandSetBlipName(centerBlip)
end

local function applyActive(payload)
    local previousZoneId = active and active.zone and active.zone.id
    active = payload
    insideZone = false
    removeZoneObject()
    removeBlips()

    if not active then
        participantState = nil
        updateAutoMonitor(false)
        SendNUIMessage({ action = 'countdownCancel' })
        SendNUIMessage({ action = 'member', visible = false })
        SendNUIMessage({ action = 'hideObserver' })
        return
    end

    if previousZoneId and previousZoneId ~= active.zone.id then participantState = nil end
    if active.state == 'open' then participantState = nil end
    createZoneObject(active.zone)
    createBlips(active.zone, active.state)

    local coords = GetEntityCoords(PlayerPedId())
    updatePresence(TurfGeometry.contains(active.zone, { x = coords.x, y = coords.y, z = coords.z }))
end

local function closeAdmin()
    adminOpen = false
    adminRequested = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeAdmin' })
end

local function requestAdmin(openPanel)
    adminRequested = openPanel == true
    TriggerServerEvent('legacy_turf:server:requestAdminData')
end

local function stopPolyEditor(reopen)
    polyDraft = nil
    SendNUIMessage({ action = 'polyEditor', visible = false })
    if reopen then
        SetTimeout(350, function() requestAdmin(true) end)
    end
end

RegisterNetEvent('legacy_turf:client:initialState', function(payload, manager)
    isManager = manager == true
    applyActive(payload)
end)

RegisterNetEvent('legacy_turf:client:syncActive', function(payload)
    applyActive(payload)
end)

RegisterNetEvent('legacy_turf:client:openAdmin', function()
    requestAdmin(true)
end)

RegisterNetEvent('legacy_turf:client:adminData', function(data)
    SendNUIMessage({ action = 'adminData', data = data })
    if adminRequested then
        adminRequested = false
        adminOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'openAdmin' })
    end
end)

RegisterNetEvent('legacy_turf:client:observerSnapshot', function(snapshot)
    SendNUIMessage({ action = 'observerSnapshot', data = snapshot })
end)

RegisterNetEvent('legacy_turf:client:observerNotice', function(message, kind)
    SendNUIMessage({ action = 'observerNotice', message = message, kind = kind })
end)

RegisterNetEvent('legacy_turf:client:hideObserver', function()
    SendNUIMessage({ action = 'hideObserver' })
end)

RegisterNetEvent('legacy_turf:client:participantState', function(data)
    participantState = data and data.status or nil
    sendMemberHud()
end)

RegisterNetEvent('legacy_turf:client:startCountdown', function(seconds)
    participantState = 'outside'
    SendNUIMessage({ action = 'countdownStart', seconds = tonumber(seconds) or Config.CountdownSeconds })
    sendMemberHud()
end)

RegisterNetEvent('legacy_turf:client:cancelCountdown', function()
    if participantState ~= 'eliminated' then participantState = insideZone and 'inside' or participantState end
    SendNUIMessage({ action = 'countdownCancel' })
    sendMemberHud()
end)

RegisterNetEvent('legacy_turf:client:resetRuntime', function()
    participantState = nil
    SendNUIMessage({ action = 'countdownCancel' })
    sendMemberHud()
end)

RegisterNetEvent('legacy_turf:client:eject', function(coords)
    coords = TurfGeometry.normalizePoint(coords)
    if not coords then return end

    CreateThread(function()
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 16)
            local deadline = GetGameTimer() + 1200
            while IsPedInAnyVehicle(ped, false) and GetGameTimer() < deadline do Wait(50) end
        end
        SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    end)
end)

RegisterNetEvent('legacy_turf:client:forceExitVehicle', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 16)
        notify('Zone này không cho phép sử dụng xe.', 'warning')
    end
end)

RegisterNUICallback('close', function(_, cb)
    closeAdmin()
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
    requestAdmin(false)
    cb({ ok = true })
end)

RegisterNUICallback('saveCircle', function(data, cb)
    local coords = GetEntityCoords(PlayerPedId())
    local center = data.center
    if data.recenter == true or not center then
        center = { x = coords.x, y = coords.y, z = coords.z }
    end

    TriggerServerEvent('legacy_turf:server:saveZone', {
        id = tonumber(data.id),
        name = data.name,
        shape = 'circle',
        center = center,
        radius = tonumber(data.radius),
        color = tonumber(data.color),
        allowVehicles = data.allowVehicles == true,
    })
    cb({ ok = true })
end)

RegisterNUICallback('saveMetadata', function(data, cb)
    TriggerServerEvent('legacy_turf:server:saveZone', {
        id = tonumber(data.id),
        name = data.name,
        shape = data.shape,
        color = tonumber(data.color),
        allowVehicles = data.allowVehicles == true,
    })
    cb({ ok = true })
end)

RegisterNUICallback('beginPoly', function(data, cb)
    if not data.name or data.name == '' then
        cb({ ok = false, message = 'Vui lòng nhập tên zone.' })
        return
    end

    polyDraft = {
        id = tonumber(data.id),
        name = data.name,
        shape = 'poly',
        color = tonumber(data.color) or Config.DefaultColor,
        allowVehicles = data.allowVehicles == true,
        points = {},
    }
    closeAdmin()
    SendNUIMessage({ action = 'polyEditor', visible = true, points = 0 })
    notify('Đi tới từng góc: E thêm điểm, Backspace hoàn tác, Enter lưu, Esc hủy.', 'info', 8000)
    cb({ ok = true })
end)

RegisterNUICallback('deleteZone', function(data, cb)
    TriggerServerEvent('legacy_turf:server:deleteZone', tonumber(data.id))
    cb({ ok = true })
end)

RegisterNUICallback('start', function(data, cb)
    TriggerServerEvent('legacy_turf:server:start', tonumber(data.id), data.allowVehicles == true)
    cb({ ok = true })
end)

RegisterNUICallback('lock', function(_, cb)
    TriggerServerEvent('legacy_turf:server:lock')
    cb({ ok = true })
end)

RegisterNUICallback('unlock', function(_, cb)
    TriggerServerEvent('legacy_turf:server:unlock')
    cb({ ok = true })
end)

RegisterNUICallback('stop', function(_, cb)
    TriggerServerEvent('legacy_turf:server:stop')
    cb({ ok = true })
end)

RegisterNUICallback('monitor', function(data, cb)
    manualMonitor = data.enabled == true
    TriggerServerEvent('legacy_turf:server:setMonitor', manualMonitor, 'manual')
    cb({ ok = true })
end)

RegisterNUICallback('saveOverlaySettings', function(data, cb)
    local side = data.side == 'left' and 'left' or 'right'
    local scale = math.max(0.7, math.min(1.35, tonumber(data.scale) or 1.0))
    SetResourceKvp('legacy_turf:overlay', json.encode({ side = side, scale = scale }))
    cb({ ok = true })
end)

CreateThread(function()
    local saved = GetResourceKvpString('legacy_turf:overlay')
    if saved then
        local ok, settings = pcall(json.decode, saved)
        if ok and type(settings) == 'table' then
            SendNUIMessage({ action = 'overlaySettings', data = settings })
        end
    end

    Wait(1000)
    TriggerServerEvent('legacy_turf:server:requestState')
end)

CreateThread(function()
    while true do
        if polyDraft then
            Wait(0)
            DisableControlAction(0, 38, true)
            DisableControlAction(0, 177, true)
            DisableControlAction(0, 191, true)
            DisableControlAction(0, 200, true)

            if IsDisabledControlJustReleased(0, 38) then
                if #polyDraft.points >= Config.MaxPolygonPoints then
                    notify(('PolyZone chỉ được tối đa %d điểm.'):format(Config.MaxPolygonPoints), 'error')
                else
                    local coords = GetEntityCoords(PlayerPedId())
                    polyDraft.points[#polyDraft.points + 1] = { x = coords.x, y = coords.y, z = coords.z }
                    SendNUIMessage({ action = 'polyEditor', visible = true, points = #polyDraft.points })
                end
            elseif IsDisabledControlJustReleased(0, 177) then
                if #polyDraft.points > 0 then
                    table.remove(polyDraft.points)
                    SendNUIMessage({ action = 'polyEditor', visible = true, points = #polyDraft.points })
                end
            elseif IsDisabledControlJustReleased(0, 191) then
                local points, validationError = TurfGeometry.validatePolygon(polyDraft.points)
                if not points then
                    notify(validationError, 'error', 6000)
                else
                    polyDraft.points = points
                    TriggerServerEvent('legacy_turf:server:saveZone', polyDraft)
                    stopPolyEditor(true)
                end
            elseif IsDisabledControlJustReleased(0, 200) then
                stopPolyEditor(true)
                notify('Đã hủy vẽ PolyZone.', 'info')
            end
        else
            Wait(500)
        end
    end
end)

CreateThread(function()
    while true do
        local drawing = active ~= nil or polyDraft ~= nil
        if not drawing then
            Wait(1000)
        else
            local pedCoords = GetEntityCoords(PlayerPedId())
            local zone = polyDraft and { shape = 'poly', points = polyDraft.points } or active.zone
            local center = TurfGeometry.getCenter(zone)
            local dx = pedCoords.x - center.x
            local dy = pedCoords.y - center.y
            local withinDistance = polyDraft ~= nil or (dx * dx + dy * dy <= Config.DrawDistance * Config.DrawDistance)

            if withinDistance then
                Wait(0)
                local colorId = active and active.state == 'locked' and Config.LockedBlipColor
                    or polyDraft and polyDraft.color or zone.color
                local color = Config.Colors[colorId] or Config.Colors[Config.DefaultColor]

                if zone.shape == 'circle' and zone.center then
                    local previous
                    for i = 0, Config.CircleSegments do
                        local angle = (i / Config.CircleSegments) * math.pi * 2.0
                        local point = vector3(
                            zone.center.x + math.cos(angle) * zone.radius,
                            zone.center.y + math.sin(angle) * zone.radius,
                            zone.center.z + 0.15
                        )
                        if previous then
                            DrawLine(previous.x, previous.y, previous.z, point.x, point.y, point.z, color.r, color.g, color.b, 220)
                        end
                        previous = point
                    end
                else
                    local points = zone.points or {}
                    for i = 1, #points do
                        local nextIndex = i == #points and 1 or i + 1
                        if polyDraft and i == #points then break end
                        local a = points[i]
                        local b = points[nextIndex]
                        DrawLine(a.x, a.y, a.z + 0.1, b.x, b.y, b.z + 0.1, color.r, color.g, color.b, 230)
                        DrawLine(a.x, a.y, a.z + 0.1, a.x, a.y, a.z + Config.BoundaryHeight, color.r, color.g, color.b, 160)
                    end
                    if polyDraft then
                        for i = 1, #points do
                            DrawMarker(28, points[i].x, points[i].y, points[i].z + 0.25, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                                0.22, 0.22, 0.22, color.r, color.g, color.b, 220, false, false, 2, false, nil, nil, false)
                        end
                    end
                end
            else
                Wait(250)
            end
        end
    end
end)

CreateThread(function()
    while true do
        if active and insideZone and not active.allowVehicles and not isManager then
            Wait(0)
            DisableControlAction(0, 23, true)
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) and GetGameTimer() - lastVehicleExit > 1500 then
                lastVehicleExit = GetGameTimer()
                TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 16)
            end
        else
            Wait(300)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(2000)
        local rank = tonumber(LocalPlayer.state.AdminRank) or 0
        local derivedManager = rank >= 5 or (rank >= 4 and LocalPlayer.state.adminDutyName ~= nil)
        if derivedManager ~= isManager then
            isManager = derivedManager
            if not isManager then
                manualMonitor = false
                updateAutoMonitor(false)
            elseif insideZone then
                updateAutoMonitor(true)
            end
            sendMemberHud()
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    removeZoneObject()
    removeBlips()
    SetNuiFocus(false, false)
end)
