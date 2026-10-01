local ESX         = exports['es_extended']:getSharedObject()
local adminLevel  = 0
local isNuiOpen   = false
local isGod       = false
local isInvisible = false
local isFrozen    = false
local advisorReturnCoords = nil
local advisorHelpState = nil

local function GetDefaultRanks()
    local ranks = {}
    for i = 1, Config.MaxAdminLevel do
        ranks[tostring(i)] = {
            name = Config.DefaultLevelNames[i] or ('Level ' .. i),
            color = Config.AdminTagColors[i] or '#ffffff'
        }
    end
    return ranks
end

-- Startup
AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    Citizen.Wait(500)
    TriggerServerEvent('admincore:requestRankNames')
end)

-- Sync rank names tu server
RegisterNetEvent('admincore:syncRankNames', function(cache)
    if isNuiOpen then
        SendNUIMessage({ type = 'syncRankNames', data = GetDefaultRanks() })
    end
end)

local originalRegisterCommand = RegisterCommand
RegisterCommand = function(commandName, handler, restricted)
    originalRegisterCommand(commandName, function(source, args, rawCommand)
        local cmdLower = commandName:lower()

        if LocalPlayer.state.isWatchdog then
            local watchdogAllowed = {
                ['c'] = true,
                ['togglec'] = true,
                ['tc'] = true,
                ['toggleadvisorchat'] = true,
                ['tadvisor'] = true,
                ['report'] = true,
                ['huybaocao'] = true,
                ['cancelreport'] = true,
            }
            if not watchdogAllowed[cmdLower] then
                TriggerEvent('admincore:notify', 'Role Watchdog chỉ có thể sử dụng lệnh /c.', 'error')
                return
            end
        end

        if adminLevel == 2 or adminLevel == 3 then
            local allowedCommands = {
                ['rpanel'] = true,
                ['apanel'] = true,
                ['goto'] = true,
                ['agoto'] = true,
                ['bring'] = true,
                ['abring'] = true,
                ['gethere'] = true,
                ['agethere'] = true,
                ['aspectate'] = true,
                ['spectate'] = true,
                ['spec'] = true,
                ['agetcar'] = true,
                ['givekeys'] = true,
                ['checkinv'] = true,
                ['admins'] = true,
                ['players'] = true,
                ['agetinfo'] = true,
                ['getinfo'] = true,
                ['revive'] = true,
                ['fly'] = true,
                ['nametags'] = true,
                ['kick'] = true,
                ['jail'] = true,
                ['unjail'] = true,
                ['unjailic'] = true,
                ['fixtime'] = true,
                ['freeze'] = true,
                ['warn'] = true,
                ['afix'] = true,
                ['fixveh'] = true,
                ['a'] = true,
                ['aduty'] = true,
                ['c'] = true,
                ['pc'] = true,
                ['tooglepc'] = true,
                ['togglepc'] = true,
                ['ahelp'] = true,
                ['getvector2'] = true,
                ['getvector3'] = true,
                ['getvector4'] = true,
                ['report'] = true,
                ['huybaocao'] = true,
                ['cancelreport'] = true,
            }
            if not allowedCommands[cmdLower] then
                TriggerEvent('admincore:notify', 'Bạn không có quyền thực hiện lệnh này', 'error')
                return
            end
        end
        handler(source, args, rawCommand)
    end, restricted)
end

-- /apanel – Mo/dong Admin Panel
RegisterCommand('apanel', function()
    if LocalPlayer.state.isWatchdog then
        TriggerEvent('admincore:notify', 'Role Watchdog không có quyền truy cập admin panel.', 'error')
        return
    end

    if adminLevel < 2 then
        TriggerEvent('admincore:notify', 'Bạn không có quyền truy cập admin panel.', 'error')
        return
    end

    if adminLevel <= 4 and not LocalPlayer.state.adminDutyName then
        TriggerEvent('admincore:notify', 'Bạn phải On Duty (/aduty) mới có thể mở Admin Panel.', 'error')
        return
    end

    isNuiOpen = not isNuiOpen
    SetNuiFocus(isNuiOpen, isNuiOpen)
    SendNUIMessage({
        type     = isNuiOpen and 'open' or 'close',
        level    = adminLevel,
        ranks    = GetDefaultRanks(),
        maxLevel = Config.MaxAdminLevel,
        mode     = 'admin',
    })
    if isNuiOpen then
        TriggerServerEvent('admincore:getPlayers')
    end
end, false)

RegisterCommand('rpanel', function()
    if LocalPlayer.state.isWatchdog then
        TriggerEvent('admincore:notify', 'Role Watchdog không có quyền truy cập report panel.', 'error')
        return
    end

    if adminLevel < 1 then
        TriggerEvent('admincore:notify', 'Bạn không có quyền truy cập report panel.', 'error')
        return
    end

    if adminLevel <= 4 and not LocalPlayer.state.adminDutyName and not LocalPlayer.state.advisorDutyName then
        TriggerEvent('admincore:notify', 'Bạn phải On Duty (/aduty) mới có thể mở Report Panel.', 'error')
        return
    end

    isNuiOpen = not isNuiOpen
    SetNuiFocus(isNuiOpen, isNuiOpen)
    SendNUIMessage({
        type     = isNuiOpen and 'open' or 'close',
        level    = adminLevel,
        ranks    = GetDefaultRanks(),
        maxLevel = Config.MaxAdminLevel,
        mode     = 'reports',
    })
    if isNuiOpen then
        TriggerServerEvent('admincore:getReports')
    end
end, false)

-- NUI Callbacks
RegisterNUICallback('close', function(_, cb)
    isNuiOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('getPlayers', function(_, cb)
    TriggerServerEvent('admincore:getPlayers')
    cb('ok')
end)

RegisterNUICallback('getBans', function(data, cb)
    TriggerServerEvent('admincore:getBans', data.page or 1)
    cb('ok')
end)

RegisterNUICallback('getReports', function(_, cb)
    TriggerServerEvent('admincore:getReports')
    cb('ok')
end)

RegisterNUICallback('reportAction', function(data, cb)
    TriggerServerEvent('admincore:reportAction', data.action, data.id, data.reason)
    cb('ok')
end)

RegisterNUICallback('cancelMyReport', function(_, cb)
    TriggerServerEvent('admincore:cancelMyReport')
    cb('ok')
end)

RegisterNUICallback('action', function(data, cb)
    local act = data.action
    if act == 'goto' then
        TriggerServerEvent('admincore:doAction', 'goto', data.id)
    elseif act == 'gethere' then
        TriggerServerEvent('admincore:doAction', 'gethere', data.id)
    elseif act == 'spectate' then
        TriggerServerEvent('admincore:doAction', 'spectate', data.id)
    elseif act == 'checkinv' then
        TriggerServerEvent('admincore:doAction', 'checkinv', data.id)
    elseif act == 'freeze' then
        TriggerServerEvent('admincore:doAction', 'freeze', data.id)
    elseif act == 'revive' then
        TriggerServerEvent('admincore:doAction', 'revive', data.id)
    elseif act == 'kick' then
        TriggerServerEvent('admincore:doAction', 'kick', data.id, data.reason)
    elseif act == 'ban' then
        TriggerServerEvent('admincore:doAction', 'ban', data.id, data.reason)
    elseif act == 'warn' then
        TriggerServerEvent('admincore:doAction', 'warn', data.id, data.reason)
    elseif act == 'setlevel' then
        TriggerServerEvent('admincore:doAction', 'setlevel', data.id, data.level)
    elseif act == 'getinfo' then
        TriggerServerEvent('admincore:doAction', 'getinfo', data.id)
    elseif act == 'unban' then
        TriggerServerEvent('admincore:doAction', 'unban', data.id, data.reason)
    elseif act == 'setprime' then
        TriggerServerEvent('admincore:doAction', 'setprime', data.id, data.days)
    elseif act == 'setrankname' then
        TriggerServerEvent('admincore:setRankName', data.id, data.name, data.color)
    end
    cb('ok')
end)

RegisterNUICallback('getGiftcodes', function(_, cb)
    TriggerServerEvent('admincore:getGiftcodes')
    cb('ok')
end)

RegisterNUICallback('deleteGiftcode', function(data, cb)
    if data and data.code then
        TriggerServerEvent('admincore:deleteGiftcode', data.code)
    end
    cb('ok')
end)

-- Nhan data tu server → NUI
RegisterNetEvent('admincore:updatePlayers', function(players)
    if isNuiOpen then
        SendNUIMessage({ type = 'updatePlayers', data = players })
    end
end)

RegisterNetEvent('admincore:updateBans', function(bans, total, page)
    if isNuiOpen then
        SendNUIMessage({ type = 'updateBans', data = bans, total = total, page = page })
    end
end)

RegisterNetEvent('admincore:updateReports', function(reports)
    SendNUIMessage({ type = 'updateReports', data = reports or {} })
end)

RegisterNetEvent('admincore:updateGiftcodes', function(giftcodes)
    if isNuiOpen then
        SendNUIMessage({ type = 'updateGiftcodes', data = giftcodes or {} })
    end
end)

RegisterNetEvent('admincore:reportNotify', function(payload)
    payload = payload or {}
    local report = payload.report or {}
    local notifyType = payload.accent == 'danger' and 'error' or (payload.accent == 'advisor' and 'info' or 'info')
    local reportLine = ('#%s - %s (%s)'):format(report.id or '?', report.playerName or '?', report.playerId or '?')
    local message = reportLine

    if report.message and report.message ~= '' then
        message = message .. '\n' .. report.message
    end

    if GetResourceState('lv_notify') == 'started' then
        exports['lv_notify']:Notify({
            type = notifyType,
            title = payload.title or 'Report',
            message = message,
            duration = 6500
        })
        return
    end

    TriggerEvent('admincore:notify', message, notifyType)
end)

RegisterNetEvent('admincore:showInfo', function(info)
    if not isNuiOpen then
        isNuiOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({ type = 'open', level = adminLevel, ranks = GetDefaultRanks(), maxLevel = Config.MaxAdminLevel, mode = 'admin' })
    end
    SendNUIMessage({ type = 'showInfo', data = info })
end)

-- Teleport
RegisterNetEvent('admincore:teleport', function(x, y, z, heading)
    local ped = PlayerPedId()
    SetEntityCoords(ped, x, y, z, false, false, false, false)
    if heading then
        SetEntityHeading(ped, heading)
    end
end)

RegisterNetEvent('admincore:advisorHelpTeleport', function(x, y, z)
    local ped = PlayerPedId()
    advisorReturnCoords = GetEntityCoords(ped)
    advisorHelpState = {
        health = GetEntityHealth(ped),
        armor = GetPedArmour(ped),
        invincible = isGod,
    }
    SetEntityInvincible(ped, true)
    SetPlayerInvincible(PlayerId(), true)
    SetEntityCoords(ped, x, y, z, false, false, false, false)
    TriggerEvent('admincore:notify', 'Đã teleport tới người cần hỗ trợ. God mode hỗ trợ đã bật.', 'success')
end)

RegisterNetEvent('admincore:advisorHelpReturn', function()
    local ped = PlayerPedId()
    if not advisorReturnCoords then
        if advisorHelpState then
            SetEntityHealth(ped, advisorHelpState.health or GetEntityHealth(ped))
            SetPedArmour(ped, advisorHelpState.armor or GetPedArmour(ped))
            SetEntityInvincible(ped, advisorHelpState.invincible == true)
            SetPlayerInvincible(PlayerId(), advisorHelpState.invincible == true)
            advisorHelpState = nil
        end
        TriggerEvent('admincore:notify', 'Không tìm thấy vị trí cũ để quay về.', 'warning')
        return
    end

    SetEntityCoords(ped, advisorReturnCoords.x, advisorReturnCoords.y, advisorReturnCoords.z, false, false, false, false)
    advisorReturnCoords = nil

    if advisorHelpState then
        SetEntityHealth(ped, advisorHelpState.health or GetEntityHealth(ped))
        SetPedArmour(ped, advisorHelpState.armor or GetPedArmour(ped))
        SetEntityInvincible(ped, advisorHelpState.invincible == true)
        SetPlayerInvincible(PlayerId(), advisorHelpState.invincible == true)
        advisorHelpState = nil
    else
        SetEntityInvincible(ped, isGod)
        SetPlayerInvincible(PlayerId(), isGod)
    end
end)

-- Freeze
RegisterNetEvent('admincore:setFrozen', function(state)
    isFrozen = state
    FreezeEntityPosition(PlayerPedId(), state)
end)

-- Revive
RegisterNetEvent('admincore:revive', function()
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, 0.0, true, false)
    ClearPedTasksImmediately(ped)
    SetEntityMaxHealth(ped, 200)
    SetEntityHealth(ped, 200)
    TriggerEvent('esx:onPlayerSpawn')
end)

local isOOCJailed = false
local jailCoords = vector3(-509.63, 5785.06, 1928.15)

RegisterNetEvent('admincore:jail', function(duration, reason)
    local wasJailed = isOOCJailed
    isOOCJailed = true
    LocalPlayer.state:set('IsJailed', true, true)
    local ped = PlayerPedId()
    SetEntityCoords(ped, jailCoords.x, jailCoords.y, jailCoords.z, false, false, false, false)
    FreezeEntityPosition(ped, true)
    TriggerEvent('admincore:notify', ('Bạn bị giam %d phút. Lý do: %s'):format(duration, reason or '?'), 'error')
    
    if wasJailed then return end

    Citizen.CreateThread(function()
        while isOOCJailed do
            Citizen.Wait(2000)
            if not isOOCJailed then break end
            local currentPed = PlayerPedId()
            FreezeEntityPosition(currentPed, true)
            local coords = GetEntityCoords(currentPed)
            if #(coords - jailCoords) > 5.0 then
                SetEntityCoords(currentPed, jailCoords.x, jailCoords.y, jailCoords.z, false, false, false, false)
                TriggerEvent('admincore:notify', 'Bạn không thể trốn khỏi tù OOC!', 'error')
            end
        end
    end)

    Citizen.CreateThread(function()
        while isOOCJailed do
            Citizen.Wait(0)
            DisableControlAction(0, 245, true)
            DisableControlAction(0, 246, true)
            DisableControlAction(0, 288, true)
            DisableControlAction(0, 289, true)
            DisableControlAction(0, 170, true)
            DisableControlAction(0, 166, true)
            DisableControlAction(0, 167, true)
            DisableControlAction(0, 168, true)
            DisableControlAction(0, 311, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 244, true)
            DisableControlAction(0, 303, true)
            DisableControlAction(0, 290, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 23, true)
            DisableControlAction(0, 75, true)
        end
    end)
end)

RegisterNetEvent('admincore:unjail', function(coords)
    isOOCJailed = false
    LocalPlayer.state:set('IsJailed', false, true)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    print("DEBUG CLIENT RECEIVED COORDS:", json.encode(coords))
    if coords then
        Citizen.CreateThread(function()
            Citizen.Wait(500)
            SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z, false, false, false, false)
        end)
    end
    TriggerEvent('admincore:notify', 'Bạn đã được thả.', 'success')
end)

-- Announce
RegisterNetEvent('admincore:announce', function(message, adminName)
    local text = ("{FF0000}[OOC]{FFFFFF} %s: %s"):format(adminName, message)
    if GetResourceState('custom-chat') == 'started' then
        TriggerEvent('custom-chat:addMessage', text)
        return
    end

    TriggerEvent('chat:addMessage', {
        color = {255, 0, 0},
        multiline = true,
        args = { text }
    })
end)

-- Notify
local function ShowAdminNotify(msg, msgType)
    if GetResourceState('lv_notify') == 'started' then
        exports['lv_notify']:Notify({
            type = msgType or 'info',
            title = 'AdminCore',
            message = msg,
            duration = 4500
        })
        return
    end

    local hexColor = "{FFFFFF}"
    if msgType == 'error' then hexColor = "{F56565}"
    elseif msgType == 'success' then hexColor = "{48BB78}"
    elseif msgType == 'warning' then hexColor = "{ECC94B}"
    elseif msgType == 'info' then hexColor = "{63B3ED}"
    end

    TriggerEvent('chat:addMessage', {
        color = {255, 255, 255}, -- Fallback
        multiline = true,
        args = { hexColor .. "[AdminCore] " .. msg .. "{FFFFFF}" }
    })
end

RegisterNetEvent('admincore:notify', function(msg, msgType)
    ShowAdminNotify(msg, msgType)
end)

-- God Mode
RegisterNetEvent('admincore:toggleGod', function()
    isGod = not isGod
    local ped = PlayerPedId()
    SetEntityInvincible(ped, isGod)
    SetPlayerInvincible(PlayerId(), isGod)
    LocalPlayer.state:set('isGod', isGod, true)
    TriggerEvent('admincore:notify', 'God mode: ' .. (isGod and 'BẬT' or 'TẮT'), isGod and 'success' or 'info')
end)

-- Invisible
RegisterNetEvent('admincore:toggleInvisible', function()
    isInvisible = not isInvisible
    LocalPlayer.state:set('aCoreInvisible', isInvisible, true)

    SetEntityVisible(PlayerPedId(), not isInvisible, false)
    TriggerEvent('admincore:notify', 'Ẩn hình: ' .. (isInvisible and 'BẬT' or 'TẮT'), isInvisible and 'success' or 'info')
end)

-- Set Ped Model (Tạm thời)
RegisterNetEvent('admincore:setPed', function(modelName)
    local modelHash = GetHashKey(modelName)
    
    if not IsModelInCdimage(modelHash) or not IsModelValid(modelHash) then
        TriggerEvent('admincore:notify', 'Model ped không hợp lệ.', 'error')
        return
    end

    RequestModel(modelHash)
    local timeout = 1000
    while not HasModelLoaded(modelHash) and timeout > 0 do
        Wait(5)
        timeout = timeout - 1
    end

    if not HasModelLoaded(modelHash) then
        TriggerEvent('admincore:notify', 'Không thể tải model ped.', 'error')
        return
    end

    SetPlayerModel(PlayerId(), modelHash)
    SetPedDefaultComponentVariation(PlayerPedId())
    SetModelAsNoLongerNeeded(modelHash)
    
    TriggerEvent('admincore:notify', ('Đã đổi ped thành %s tạm thời.'):format(modelName), 'success')
end)

-- Spawn Vehicle
RegisterNetEvent('admincore:spawnVehicle', function(model)
    local hash = GetHashKey(model)
    if not IsModelValid(hash) then
        TriggerEvent('admincore:notify', 'Model không hợp lệ: ' .. model, 'error')
        return
    end

    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) do
        Citizen.Wait(100)
        timeout = timeout + 1
        if timeout > 50 then break end
    end

    if not HasModelLoaded(hash) then
        TriggerEvent('admincore:notify', 'Không thể load model: ' .. model, 'error')
        return
    end

    local ped     = PlayerPedId()
    local coords  = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local veh     = CreateVehicle(hash, coords.x, coords.y, coords.z, heading, true, false)
    if veh ~= 0 then
        Entity(veh).state:set('vehiclePersistIgnore', true, true)
    end
    SetPedIntoVehicle(ped, veh, -1)
    SetEntityAsMissionEntity(veh, true, true)
    SetModelAsNoLongerNeeded(hash)
    TriggerEvent('admincore:notify', 'Đã tạo xe: ' .. model, 'success')

    local plate = GetVehicleNumberPlateText(veh)
    Citizen.CreateThread(function()
        local timeout = 0
        while (not plate or plate == "" or string.match(plate, "^%s*$")) and timeout < 50 do
            Citizen.Wait(50)
            plate = GetVehicleNumberPlateText(veh)
            timeout = timeout + 1
        end
        if plate and not string.match(plate, "^%s*$") then
            TriggerServerEvent('vehicleCore:server:giveKey', plate)
        end
    end)
end)

-- Delete vehicle
RegisterNetEvent('admincore:deleteVehicle', function()
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local veh    = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
    if DoesEntityExist(veh) then
        SetEntityAsMissionEntity(veh, true, true)
        DeleteEntity(veh)
        TriggerEvent('admincore:notify', 'Đã xóa xe.', 'success')
    else
        TriggerEvent('admincore:notify', 'Không có xe trong phạm vi 5m.', 'error')
    end
end)

-- Fix vehicle
local function fixVehicle(veh)
    if veh and veh ~= 0 and DoesEntityExist(veh) then
        SetVehicleFixed(veh)
        SetVehicleDeformationFixed(veh)
        SetVehicleUndriveable(veh, false)
        SetVehicleEngineOn(veh, true, true, false)
        SetVehicleFuelLevel(veh, 100.0)
        SetVehicleDirtLevel(veh, 0.0)

        WashDecalsFromVehicle(veh, 1.0)

        Entity(veh).state:set('fuel', 100.0, true)

        if GetResourceState("vehicle_persist") == "started" then
            exports.vehicle_persist:FixVehicleDeformation(veh)
        end

        if GetResourceState("jg-mechanic") == "started" then
            local defaultServicing =
            {
                suspension = 100,
                tyres = 100,
                brakePads = 100,
                engineOil = 100,
                clutch = 100,
                airFilter = 100,
                sparkPlugs = 100,
                evMotor = 100,
                evBattery = 100,
                evCoolant = 100
            }

            Entity(veh).state:set("servicingData", defaultServicing, true)

            pcall(function()
                lib.callback.await("jg-mechanic:server:set-vehicle-statebag", false, VehToNet(veh), "servicingData", defaultServicing, true)
            end)
        end

        TriggerEvent('admincore:notify', 'Đã sửa phương tiện và đổ đầy bình xăng.', 'success')
    else
        TriggerEvent('admincore:notify', 'Bạn không ở trong phương tiện nào.', 'error')
    end
end

RegisterNetEvent('admincore:fixVehicle', function()
    fixVehicle(GetVehiclePedIsIn(PlayerPedId(), false))
end)

RegisterNetEvent('admincore:fixVehicleByNetId', function(netId, expectedPlate)
    local veh = NetToVeh(netId)

    if not DoesEntityExist(veh) then
        return
    end

    local actualPlate = GetVehicleNumberPlateText(veh):upper():gsub('%s+', '')

    if actualPlate ~= expectedPlate then
        return
    end

    fixVehicle(veh)
end)

-- Vehicle Color Picker (ox_lib)
RegisterNetEvent('admincore:openColorPicker', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then
        TriggerEvent('admincore:notify', 'Bạn không ở trong phương tiện nào', 'error')
        return
    end

    local colorInput = lib.inputDialog('Tùy chỉnh màu xe', {
        { type = 'color', label = 'Màu sơn chính (Primary)', default = '#ffffff' },
        { type = 'color', label = 'Màu sơn phụ (Secondary)', default = '#ffffff' }
    })

    if colorInput then
        local primary = colorInput[1]
        local secondary = colorInput[2]

        if primary then
            local hex = primary:gsub("#", "")
            if #hex == 6 then
                local r = tonumber("0x" .. hex:sub(1, 2))
                local g = tonumber("0x" .. hex:sub(3, 4))
                local b = tonumber("0x" .. hex:sub(5, 6))
                SetVehicleCustomPrimaryColour(veh, r, g, b)
            end
        end

        if secondary then
            local hex = secondary:gsub("#", "")
            if #hex == 6 then
                local r = tonumber("0x" .. hex:sub(1, 2))
                local g = tonumber("0x" .. hex:sub(3, 4))
                local b = tonumber("0x" .. hex:sub(5, 6))
                SetVehicleCustomSecondaryColour(veh, r, g, b)
            end
        end

        TriggerEvent('admincore:notify', 'Đã thay đổi màu xe thành công.', 'success')
    end
end)


-- Admin Duty 3D Text
local DUTY_TEXT_SCALE = 0.22
local ADVISOR_TEXT_SCALE = 0.20
local NAMETAG_TEXT_SCALE = 0.20

local function DrawText3D(x, y, z, text, scale, font)
    local s = scale or 0.3
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    if onScreen then
        SetTextScale(0.0, s)
        SetTextFont(font or 4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 245)
        SetTextEntry("STRING")
        SetTextCentre(1)
        SetTextDropshadow(1, 0, 0, 0, 220)
        SetTextEdge(1, 0, 0, 0, 210)
        SetTextOutline()
        AddTextComponentString(text)
        DrawText(_x, _y)
    end
end

local activeDutyAdmins = {}
local activeDutyAdvisors = {}

local function setDutyName(cache, src, enabled, dutyName)
    if enabled and dutyName and dutyName ~= '' then
        cache[src] = dutyName
    else
        cache[src] = nil
    end
end

Citizen.CreateThread(function()
    Citizen.Wait(1000)
    for _, player in ipairs(GetActivePlayers()) do
        local id = GetPlayerServerId(player)
        local dutyName = Player(id).state.adminDutyName
        if dutyName then
            activeDutyAdmins[id] = dutyName
        end

        local advisorDutyName = Player(id).state.advisorDutyName
        if advisorDutyName then
            activeDutyAdvisors[id] = advisorDutyName
        end
    end
end)

AddStateBagChangeHandler('adminDutyName', nil, function(bagName, key, value, _reserved, replicated)
    local src = tonumber(bagName:gsub('player:', ''), 10)
    if src then
        setDutyName(activeDutyAdmins, src, value ~= nil, value)
    end
end)

AddStateBagChangeHandler('advisorDutyName', nil, function(bagName, key, value, _reserved, replicated)
    local src = tonumber(bagName:gsub('player:', ''), 10)
    if src then
        setDutyName(activeDutyAdvisors, src, value ~= nil, value)
    end
end)

RegisterNetEvent('admincore:dutyState', function(enabled, src, dutyName)
    src = tonumber(src)
    if not src then return end

    setDutyName(activeDutyAdmins, src, enabled, dutyName)
end)

RegisterNetEvent('admincore:advisorDutyState', function(enabled, src, dutyName)
    src = tonumber(src)
    if not src then return end

    setDutyName(activeDutyAdvisors, src, enabled, dutyName)
end)

RegisterNetEvent('admincore:clearDutyState', function(src)
    src = tonumber(src)
    if src then
        activeDutyAdmins[src] = nil
        activeDutyAdvisors[src] = nil
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local sleep = true
        local myPed = PlayerPedId()
        local myCoords = GetEntityCoords(myPed)

        for src, dutyName in pairs(activeDutyAdmins) do
            local player = GetPlayerFromServerId(src)
            if player ~= -1 then
                local ped = GetPlayerPed(player)
                if DoesEntityExist(ped) and ped ~= 0 then
                    local pState = Player(src).state
                    if not pState.aCoreNoclip and not pState.aCoreInvisible and IsEntityVisible(ped) then
                        local headCoords = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
                        if headCoords.x == 0.0 and headCoords.y == 0.0 and headCoords.z == 0.0 then
                            local entityCoords = GetEntityCoords(ped)
                            headCoords = vector3(entityCoords.x, entityCoords.y, entityCoords.z + 0.9)
                        end
                        local dist = #(myCoords - headCoords)

                        if dist < 5.0 then
                            sleep = false
                            DrawText3D(headCoords.x, headCoords.y, headCoords.z + 0.28, "~y~ADMIN\n~w~" .. dutyName, DUTY_TEXT_SCALE)
                        end
                    end
                end
            end
        end

        for src, dutyName in pairs(activeDutyAdvisors) do
            local player = GetPlayerFromServerId(src)
            if player ~= -1 then
                local ped = GetPlayerPed(player)
                if DoesEntityExist(ped) and ped ~= 0 then
                    local pState = Player(src).state
                    if not pState.aCoreNoclip and not pState.aCoreInvisible and IsEntityVisible(ped) then
                        local headCoords = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
                        if headCoords.x == 0.0 and headCoords.y == 0.0 and headCoords.z == 0.0 then
                            local entityCoords = GetEntityCoords(ped)
                            headCoords = vector3(entityCoords.x, entityCoords.y, entityCoords.z + 0.9)
                        end
                        local dist = #(myCoords - headCoords)

                        if dist < 5.0 then
                            sleep = false
                            DrawText3D(headCoords.x, headCoords.y, headCoords.z + 0.40, "~b~ADVISOR\n~w~" .. dutyName, ADVISOR_TEXT_SCALE)
                        end
                    end
                end
            end
        end

        if sleep then
            Citizen.Wait(500)
        end
    end
end)

-- Lay admin level khi load
Citizen.CreateThread(function()
    while ESX.GetPlayerData().identifier == nil do
        Citizen.Wait(200)
    end
    Citizen.Wait(1000)
    ESX.TriggerServerCallback('admincore:getMyLevel', function(level)
        adminLevel = level or 0
        SendNUIMessage({ type = 'setLevel', level = adminLevel })
    end)
end)

RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function()
    ESX.TriggerServerCallback('admincore:getMyLevel', function(level)
        adminLevel = level or 0
        SendNUIMessage({ type = 'setLevel', level = adminLevel })
    end)
end)

RegisterNetEvent('admincore:setLevel', function(level)
    adminLevel = level or 0
    SendNUIMessage({ type = 'setLevel', level = adminLevel })
end)

RegisterNetEvent('admincore:setWatchdog', function(state)
    LocalPlayer.state:set('isWatchdog', state == true, true)
end)

-- Nametags (ESP)
local showNametags = false

RegisterNetEvent('admincore:toggleNametags', function()
    showNametags = not showNametags
    TriggerEvent('admincore:notify', 'Nametags (ESP): ' .. (showNametags and 'BẬT' or 'TẮT'), showNametags and 'success' or 'info')
    
    if showNametags then
        Citizen.CreateThread(function()
            while showNametags do
                Citizen.Wait(0)
                local myPed = PlayerPedId()
                local myCoords = GetEntityCoords(myPed)
                
                for _, player in ipairs(GetActivePlayers()) do
                    if player ~= PlayerId() then
                        local ped = GetPlayerPed(player)
                        if DoesEntityExist(ped) then
                            local headCoords = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
                            local dist = #(myCoords - headCoords)
                            
                            if dist < 1000.0 then
                                local id = GetPlayerServerId(player)
                                local icName = Player(id).state.name
                                local name = icName and icName or GetPlayerName(player)
                                
                                local health = GetEntityHealth(ped) - 100
                                if health < 0 then health = 0 end
                                local armor = GetPedArmour(ped)
                                
                                local text = string.format("~b~%d~w~ %s\n~g~%dHP ~b~%dAP", id, name, health, armor)
                                DrawText3D(headCoords.x, headCoords.y, headCoords.z + 0.26, text, NAMETAG_TEXT_SCALE)
                            end
                        end
                    end
                end
            end
        end)
    end
end)
