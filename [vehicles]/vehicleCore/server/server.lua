local LastCrashStressUpdate = {}
local LastCrashReportByVehicle = {}

local function isFiniteNumber(value)
    return type(value) == 'number'
        and value == value
        and value > -math.huge
        and value < math.huge
end

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end

    if value > maximum then
        return maximum
    end

    return value
end

RegisterNetEvent('vehicleCore:server:reportCrash', function(payload)
    local src = source

    if type(payload) ~= 'table' then
        return
    end

    local netId = tonumber(payload.netId)
    local severity = tonumber(payload.severity)
    local velocityX = tonumber(payload.velocityX)
    local velocityY = tonumber(payload.velocityY)
    local velocityZ = tonumber(payload.velocityZ)

    if not netId or netId <= 0 or netId % 1 ~= 0
        or not isFiniteNumber(severity)
        or not isFiniteNumber(velocityX)
        or not isFiniteNumber(velocityY)
        or not isFiniteNumber(velocityZ)
        or severity <= Config.CrashMinimumSeverity
    then
        return
    end

    local vehicle = NetworkGetEntityFromNetworkId(netId)

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        return
    end

    local ped = GetPlayerPed(src)

    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return
    end

    local sourceVehicle = GetVehiclePedIsIn(ped, false)
    local sourceIsDriver = sourceVehicle == vehicle and GetPedInVehicleSeat(vehicle, -1) == ped
    local sourceIsRecentOwner = NetworkGetEntityOwner(vehicle) == src
        and #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= Config.CrashSyncRadius

    if not sourceIsDriver and not sourceIsRecentOwner then
        return
    end

    local now = GetGameTimer()
    local lastReport = LastCrashReportByVehicle[netId]

    if lastReport and now - lastReport < Config.CrashSyncCooldown then
        return
    end

    LastCrashReportByVehicle[netId] = now

    local crashPayload =
    {
        crashId = ('%d:%d'):format(netId, now),
        netId = netId,
        severity = math.min(severity, Config.CrashMaximumSeverity),
        velocityX = clamp(velocityX, -Config.CrashMaximumVelocity, Config.CrashMaximumVelocity),
        velocityY = clamp(velocityY, -Config.CrashMaximumVelocity, Config.CrashMaximumVelocity),
        velocityZ = clamp(velocityZ, -Config.CrashMaximumVelocity, Config.CrashMaximumVelocity)
    }

    local vehicleCoords = GetEntityCoords(vehicle)

    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        local occupantPed = GetPlayerPed(target)

        if occupantPed and occupantPed ~= 0 and DoesEntityExist(occupantPed)
            and (GetVehiclePedIsIn(occupantPed, false) == vehicle
                or #(GetEntityCoords(occupantPed) - vehicleCoords) <= Config.CrashSyncRadius)
        then
            TriggerClientEvent('vehicleCore:client:applyCrash', target, crashPayload)
        end
    end
end)

RegisterNetEvent('vehicleCore:server:addCrashStress', function()
    if not Config.CrashStressEnabled then
        return
    end

    if GetResourceState('lv_status') ~= 'started' then
        return
    end

    local src = source
    local now = GetGameTimer()
    local lastUpdate = LastCrashStressUpdate[src] or 0

    if now - lastUpdate < Config.CrashStressServerCooldown then
        return
    end
    
    LastCrashStressUpdate[src] = now

    exports.lv_status:AddStress(src, Config.CrashStressAmount)
end)

AddEventHandler('playerDropped', function()
    LastCrashStressUpdate[source] = nil
end)

RegisterNetEvent('vehicleCore:engineBubble')
AddEventHandler('vehicleCore:engineBubble', function(vehicleName, vehicleEngineOn)
    local src = source
    local text

    if vehicleEngineOn then
        text = string.format("* đang khởi động phương tiện %s", vehicleName)
    else
        text = string.format("* đã tắt động cơ phương tiện %s", vehicleName)
    end

    TriggerClientEvent('custom-chat:showBubble', -1, src, text,
    {
        r = 194,
        g = 162,
        b = 218,
        a = 255
    }, 15.0, 4000)
end)

RegisterNetEvent('vehicleCore:seatbeltBubble')
AddEventHandler('vehicleCore:seatbeltBubble', function(seatbeltOn)
    local src = source
    local text

    if seatbeltOn then
        text = string.format("* kéo dây an toàn qua người và khóa lại")
    else
        text = string.format("* tháo chốt và kéo dây an toàn ra khỏi người", vehicleName)
    end

    TriggerClientEvent('custom-chat:showBubble', -1, src, text,
    {
        r = 194,
        g = 162,
        b = 218,
        a = 255
    }, 15.0, 4000)
end)

local function SendMsg(src, color, msg)
    TriggerClientEvent('custom-chat:addMessage', src, msg)
end

RegisterCommand('givekeys', function(source, args, rawCommand)
    local src = source

    if not exports['aCore']:IsAdmin(src) then
        return
    end

    local plate = nil

    if args[1] then
        plate = tostring(args[1])
    else
        local ped = GetPlayerPed(src)
        local vehicle = GetVehiclePedIsIn(ped, false)
        
        if vehicle and vehicle ~= 0 then
            plate = GetVehicleNumberPlateText(vehicle)
        end
    end

    if not plate then
        return
    end

    local trimmedPlate = string.match(plate, "^%s*(.-)%s*$")
    local success = exports.ox_inventory:AddItem(src, 'vehicle_key', 1,
    {
        plate = trimmedPlate,
        description = 'Chìa khóa cho phương tiện với biển số: ' .. trimmedPlate
    })

end, false)



RegisterNetEvent('vehicleCore:server:toggleLock', function(netId, plate, newStatus)
    local src = source
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    
    if not vehicle or vehicle == 0 then
        return
    end

    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    local vehCoords = GetEntityCoords(vehicle)
    
    if #(coords - vehCoords) > 10.0 then
        return
    end
    
    local trimmedClientPlate = string.upper(string.match(plate, "^%s*(.-)%s*$"))
    local items = exports.ox_inventory:Search(src, 'slots', 'vehicle_key')
    local hasKey = false

    if items then
        for _, item in pairs(items) do
            if item.metadata and item.metadata.plate and string.upper(string.match(item.metadata.plate, "^%s*(.-)%s*$")) == trimmedClientPlate then
                hasKey = true
                break
            end
        end
    end

    if hasKey then
        Entity(vehicle).state.locked = newStatus

        SetVehicleDoorsLocked(vehicle, newStatus)
        if newStatus == 2 then
            pcall(function()
                SetVehicleDoorsShut(vehicle, false)
            end)
        end

        TriggerClientEvent('vehicleCore:client:syncFlash', -1, netId, newStatus)
    else
        TriggerClientEvent('custom-chat:addMessage', source, "{FFFFFF}Bạn {FF6347}không có chìa khóa{FFFFFF} của phương tiện này")
    end
end)



exports('GiveVehicleKey', function(source, plate)
    local src = source
    local trimmedPlate = string.upper(string.match(plate, "^%s*(.-)%s*$"))

    exports.ox_inventory:AddItem(src, 'vehicle_key', 1,
    {
        plate = trimmedPlate,
        description = 'Chìa khóa cho phương tiện với biển số: ' .. trimmedPlate
    })
end)

exports('RemoveVehicleKey', function(source, plate)
    local src = source
    local trimmedPlate = string.upper(string.match(plate, "^%s*(.-)%s*$"))

    local items = exports.ox_inventory:Search(src, 'slots', 'vehicle_key')

    if items then
        for _, item in pairs(items) do
            if item.metadata and item.metadata.plate and string.upper(string.match(item.metadata.plate, "^%s*(.-)%s*$")) == trimmedPlate then
                exports.ox_inventory:RemoveItem(src, 'vehicle_key', 1, nil, item.slot)
                break
            end
        end
    end
end)

RegisterNetEvent('vehicleCore:server:giveKey', function(plate)
    local src = source
    
    exports['vehicleCore']:GiveVehicleKey(src, plate)
end)

RegisterNetEvent('vehicleCore:server:removeKey', function(plate)
    exports['vehicleCore']:RemoveVehicleKey(source, plate)
end)

RegisterNetEvent('vehicleCore:server:buyKey', function(plate)
    local src = source
    local ESX = exports['es_extended']:getSharedObject()
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer then
        return
    end

    local trimmedPlate = string.match(plate, "^%s*(.-)%s*$")
    
    MySQL.query('SELECT * FROM owned_vehicles WHERE owner = ? AND plate = ?',
    {
        xPlayer.identifier,
        trimmedPlate
    }, function(result)
        if result and #result > 0 then
            local money = xPlayer.getMoney()

            if money >= 200 then
                xPlayer.removeMoney(2000)
                
                exports['vehicleCore']:GiveVehicleKey(src, trimmedPlate)

                TriggerClientEvent('custom-chat:addMessage', src, "{FFFFFF}Bạn đã rèn thành công chìa khóa mới với giá {33AA33}$2,000")
            else
                TriggerClientEvent('custom-chat:addMessage', src, "{FFFFFF}Bạn {FF6347}không đủ $2,000{FFFFFF} để có thể rèn chìa khóa")
            end
        else
            TriggerClientEvent('custom-chat:addMessage', src, "{FFFFFF}Phương tiện này {FF6347}không thuộc sở hữu của bạn{FFFFFF} để có thể rèn chìa khóa")
        end
    end)
end)

local ESX = exports['es_extended']:getSharedObject()

ESX.RegisterServerCallback('vehicleCore:server:getOwnedVehicles', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then 
        cb({}) 
        return 
    end

    MySQL.query('SELECT plate, vehicle FROM owned_vehicles WHERE owner = ?',
    {
        xPlayer.identifier
    }, function(result)
        if result then
            cb(result)
        else
            cb({})
        end
    end)
end)

RegisterNetEvent('vehicleCore:server:openGunrack', function(plate)
    local src = source
    local trimmedPlate = string.upper(string.match(plate, "^%s*(.-)%s*$"))
    local items = exports.ox_inventory:Search(src, 'slots', 'vehicle_key')
    local hasKey = false

    if items then
        for _, item in pairs(items) do
            if item.metadata and item.metadata.plate and string.upper(string.match(item.metadata.plate, "^%s*(.-)%s*$")) == trimmedPlate then
                hasKey = true
                break
            end
        end
    end
    
    if hasKey then
        local stashId = 'gunrack_' .. trimmedPlate

        exports.ox_inventory:RegisterStash(stashId, 'Giá Súng - ' .. trimmedPlate, 2, 15000)

        TriggerClientEvent('vehicleCore:client:openStash', src, stashId)
    end
end)
