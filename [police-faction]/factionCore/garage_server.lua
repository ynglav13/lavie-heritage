local function cleanPlate(plate)
    if not plate then return "" end
    return (string.gsub(plate, "%s+", ""))
end

local function isFactionMember(playerId, tag)
    return type(tag) == 'string' and exports.factionCore:GetPlayerFactionMembership(playerId, tag) ~= nil
end

local function canManageFaction(playerId, tag)
    return ESX.IsPlayerAdmin and ESX.IsPlayerAdmin(playerId) == true
        or type(tag) == 'string' and exports.factionCore:HasPlayerFactionPermission(playerId, tag, 'leader') == true
end

local function getVehicleFaction(plate)
    return MySQL.scalar.await('SELECT type FROM faction_vehicles WHERE plate = ? LIMIT 1', {plate})
end

local function nearFactionGarage(playerId, tag, garageIdentifier)
    local ped = GetPlayerPed(playerId)
    if ped == 0 then return false end
    local row = MySQL.single.await('SELECT garage FROM faction WHERE tag = ?', {tag})
    local garages = row and (json.decode(row.garage or '[]') or {}) or {}
    local position = GetEntityCoords(ped)
    for i = 1, #garages do
        local coords = garages[i].coords
        local identifier = 'garage' .. tostring(garages[i].id or i)
        if coords and (not garageIdentifier or garageIdentifier == identifier) and #(position - vector3(tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0)) <= 12.0 then return true end
    end
    return false
end

local function nearFactionVehicle(playerId, plate)
    local ped = GetPlayerPed(playerId)
    if ped == 0 then return false end
    local position = GetEntityCoords(ped)
    local cleanedPlate = cleanPlate(plate)
    for _, vehicle in pairs(GetAllVehicles()) do
        if cleanPlate(GetVehicleNumberPlateText(vehicle)) == cleanedPlate and #(position - GetEntityCoords(vehicle)) <= 12.0 then return true end
    end
    return false
end

RegisterServerEvent('VehicleFaction:server:RestartVehicles', function(tag)
    if not canManageFaction(source, tag) then return end
    local data = MySQL.query.await('SELECT * FROM faction_vehicles WHERE type = ?', {tag})
    if not data or #data == 0 then return end

    local platesToUpdate = {}

    for _, v in pairs(data) do
        local deleted = false
        local found = false
        local cleanedPlate = cleanPlate(v.plate)

        for _, veh in pairs(GetAllVehicles()) do
            if cleanPlate(GetVehicleNumberPlateText(veh)) == cleanedPlate then
                found = true
                local driver = GetPedInVehicleSeat(veh, -1)

                if not (driver and driver ~= 0 and IsPedAPlayer(driver)) then
                    DeleteEntity(veh)
                    deleted = true
                end
            end
        end

        if (not found) or deleted then
            table.insert(platesToUpdate, v.plate)
        end
    end

    for _, plate in ipairs(platesToUpdate) do
        MySQL.update.await('UPDATE faction_vehicles SET status = 0 WHERE plate = ? AND type = ?', {plate, tag})
    end
end)



lib.callback.register('VehicleFaction:server:GetFactionData', function(source, tag)
    if not isFactionMember(source, tag) then return {} end
    local data = MySQL.query.await('SELECT id, name, tag, type, garage, colour FROM faction WHERE tag = ?', {tag})
    return data
end)

ESX.RegisterServerCallback('VehicleFaction:server:GetGarageData', function(source, cb, id, tag, status)
    if not isFactionMember(source, tag) or not nearFactionGarage(source, tag, id) then return cb({}) end
    local data = MySQL.query.await(
        'SELECT * FROM faction_vehicles WHERE identifier = ? AND type = ? AND status = ?',
        {id, tag, status}
    )
    cb(data)
end)


ESX.RegisterServerCallback('VehicleFaction:server:GetFactionVehicle', function(source, cb, plate)
    local factionTag = getVehicleFaction(plate)
    if not factionTag or not isFactionMember(source, factionTag) or not nearFactionGarage(source, factionTag) then return cb(nil) end
    local data = MySQL.query.await('SELECT * FROM faction_vehicles WHERE plate = ?', {plate})
    cb(data[1])
end)


ESX.RegisterServerCallback('VehicleFaction:server:Despawn', function(source, callback, plate, vehicleProps)
    local factionTag = getVehicleFaction(plate)
    if not factionTag or not isFactionMember(source, factionTag) or not nearFactionGarage(source, factionTag) or not nearFactionVehicle(source, plate) then return callback(false) end
    local trimmedPlate = string.match(plate, "^%s*(.-)%s*$")
    local upperPlate = string.upper(trimmedPlate)

    local trunkInv = exports.ox_inventory:GetInventory('trunk'..upperPlate, false)
    local trunkItems = {}
    if trunkInv and trunkInv.items then
        for _, item in pairs(trunkInv.items) do
            local metadata = {}
            if item.metadata and json.encode(item.metadata) ~= '[]' then
                metadata = item.metadata
            end
            table.insert(trunkItems, {
                ['name'] = item.name,
                ['slot'] = item.slot,
                ['count'] = item.count,
                ['metadata'] = metadata
            })
        end
    end

    local gloveInv = exports.ox_inventory:GetInventory('glove'..upperPlate, false)
    local gloveItems = {}
    if gloveInv and gloveInv.items then
        for _, item in pairs(gloveInv.items) do
            local metadata = {}
            if item.metadata and json.encode(item.metadata) ~= '[]' then
                metadata = item.metadata
            end
            table.insert(gloveItems, {
                ['name'] = item.name,
                ['slot'] = item.slot,
                ['count'] = item.count,
                ['metadata'] = metadata
            })
        end
    end

    local tunerData = vehicleProps and json.encode(vehicleProps) or nil

    MySQL.Async.execute('UPDATE faction_vehicles SET status = 0, trunk = @trunk, glovebox = @glovebox, tuner_data = @tuner_data WHERE plate = @plate AND type = @type', {
        ['@trunk'] = json.encode(trunkItems),
        ['@glovebox'] = json.encode(gloveItems),
        ['@tuner_data'] = tunerData,
        ['@plate'] = trimmedPlate,
        ['@type'] = factionTag,
    }, function(result)
        exports['vehicleCore']:RemoveVehicleKey(source, trimmedPlate)
        callback(true)
    end)
end)

ESX.RegisterServerCallback('FactionVehicle:server:GetLSPDVehicles', function(source, cb)
    if not isFactionMember(source, 'LSPD') then return cb({}) end
    local data = MySQL.query.await('SELECT plate, name FROM faction_vehicles WHERE type = ?', {'LSPD'})
    cb(data)
end)

ESX.RegisterServerCallback('FactionVehicle:server:GetLSSDVehicles', function(source, cb)
    if not isFactionMember(source, 'LSSD') then return cb({}) end
    local data = MySQL.query.await('SELECT plate, name FROM faction_vehicles WHERE type = ?', {'LSSD'})
    cb(data)
end)

ESX.RegisterServerCallback('FactionVehicle:server:DeleteVehicle', function(source, cb, plate, factionType)
    local tag = factionType or 'LSPD'
    if not canManageFaction(source, tag) then return cb({success = false, reason = 'forbidden'}) end
    local cleanedPlate = cleanPlate(plate)
    for _, veh in pairs(GetAllVehicles()) do
        if cleanPlate(GetVehicleNumberPlateText(veh)) == cleanedPlate then
            local driver = GetPedInVehicleSeat(veh, -1)

            if driver and IsPedAPlayer(driver) then
                TriggerClientEvent('VehicleFaction:client:ForceLeave', NetworkGetEntityOwner(veh), NetworkGetNetworkIdFromEntity(veh))
                SetTimeout(2500, function()
                    if DoesEntityExist(veh) then
                        DeleteEntity(veh)
                    end
                end)
            else
                DeleteEntity(veh)
            end
        end
    end

    local trimmedPlate = string.match(plate, "^%s*(.-)%s*$")
    exports['vehicleCore']:RemoveVehicleKey(source, trimmedPlate)
    local deleted = MySQL.update.await('DELETE FROM faction_vehicles WHERE plate = ? AND type = ?', {trimmedPlate, tag})
    if deleted > 0 then
        cb({ success = true })
    else
        cb({ success = false, reason = 'db_delete_fail' })
    end
end)


ESX.RegisterServerCallback('FactionVehicle:server:AddVehicle', function(source, cb, data)
    if not data or not data.model or not data.plate then
        print('[FactionVehicle] Thiếu dữ liệu khi thêm xe.')
        return cb(false)
    end

    local tag = data.tag or 'LSPD'
    if not canManageFaction(source, tag) then return cb(false) end

    local exists = MySQL.scalar.await('SELECT 1 FROM faction_vehicles WHERE plate = ?', {data.plate})
    if exists then
        print(('[FactionVehicle] Biển số %s đã tồn tại, không thể thêm.'):format(data.plate))
        return cb(false)
    end

    local tires = {
        { name = "wheel_lf", id = 0, status = false },
        { name = "wheel_rf", id = 1, status = false },
        { name = "wheel_lm", id = 2, status = false },
        { name = "wheel_rm", id = 3, status = false },
        { name = "wheel_lr", id = 4, status = false },
        { name = "wheel_rr", id = 5, status = false }
    }

    local body = {
        { name = "door_lf", id = 0, status = 0 },
        { name = "door_rf", id = 1, status = 0 },
        { name = "door_lr", id = 2, status = 0 },
        { name = "door_rr", id = 3, status = 0 },
        { name = "hood",    id = 4, status = 0 },
        { name = "trunk",   id = 5, status = 0 }
    }

    local windows = {
        { name = "window_lf", id = 0, status = 1 },
        { name = "window_rf", id = 1, status = 1 },
        { name = "window_lr", id = 2, status = 1 },
        { name = "window_rr", id = 3, status = 1 }
    }

    local coords = json.encode({
        posX = 441.0,
        posY = -982.0,
        posZ = 29.0,
        heading = 90.0
    })

    local insert = MySQL.insert.await([[
        INSERT INTO faction_vehicles 
            (name, type, plate, status, fuel, health, colour, coords, tires, body, windows, identifier) 
        VALUES 
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.model,
        tag,
        data.plate,
        0,
        100.0,
        json.encode({ engine = 1000.0, body = 1000.0, tank = 1000.0 }),
        json.encode({ r = 255, g = 255, b = 255 }),     
        coords,
        json.encode(tires),
        json.encode(body),
        json.encode(windows),
        'garage1'
    })

    if insert > 0 then
        TriggerClientEvent('FactionVehicle:client:AddVehicleToNUI', source, {
            plate = data.plate,
            model = data.model,
            garageId = 0,
            status = 0,
            lastDriver = "Chưa sử dụng",
            type = 0
        })
        cb(true)
    else
        cb(false)
    end
end)









RegisterNetEvent('VehicleFaction:server:DeleteEntityGracefully', function(plate)
    local factionTag = getVehicleFaction(plate)
    if not factionTag or not canManageFaction(source, factionTag) then return end
    local cleanedPlate = cleanPlate(plate)
    for _, veh in pairs(GetAllVehicles()) do
        if cleanPlate(GetVehicleNumberPlateText(veh)) == cleanedPlate then
            local driver = GetPedInVehicleSeat(veh, -1)
            if driver and IsPedAPlayer(driver) then
                TriggerClientEvent('VehicleFaction:client:ForceLeave', NetworkGetEntityOwner(veh), NetworkGetNetworkIdFromEntity(veh))
                SetTimeout(2500, function()
                    if DoesEntityExist(veh) then
                        DeleteEntity(veh)
                    end
                end)
            else
                DeleteEntity(veh)
            end
            break
        end
    end
end)
