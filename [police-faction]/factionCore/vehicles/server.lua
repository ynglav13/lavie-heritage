CreateThread(function()
    local columns = MySQL.query.await('SHOW COLUMNS FROM `faction_vehicles`')
    if columns then
        local hasTrunk = false
        local hasTunerData = false
        for _, col in ipairs(columns) do
            if col.Field == 'trunk' then
                hasTrunk = true
            elseif col.Field == 'tuner_data' then
                hasTunerData = true
            end
        end
        if not hasTrunk then
            MySQL.query.await('ALTER TABLE `faction_vehicles` ADD COLUMN `trunk` LONGTEXT NULL')
            print('[FactionVehicle] Đã thêm column trunk vào bảng faction_vehicles')
        end
        if not hasTunerData then
            MySQL.query.await('ALTER TABLE `faction_vehicles` ADD COLUMN `tuner_data` LONGTEXT NULL')
            print('[FactionVehicle] Đã thêm column tuner_data vào bảng faction_vehicles')
        end
    end
end)

local function isAuthorizedToEditVehicles(playerId, tag)
    return ESX.IsPlayerAdmin and ESX.IsPlayerAdmin(playerId) == true
        or type(tag) == 'string' and exports.factionCore:HasPlayerFactionPermission(playerId, tag, 'leader') == true
end

local function isFactionMember(playerId, tag)
    return type(tag) == 'string' and exports.factionCore:GetPlayerFactionMembership(playerId, tag) ~= nil
end

local function getVehicleFaction(plate)
    return MySQL.scalar.await('SELECT type FROM faction_vehicles WHERE plate = ? LIMIT 1', {plate})
end

local function nearFactionGarage(playerId, tag)
    local ped = GetPlayerPed(playerId)
    if ped == 0 then return false end
    local row = MySQL.single.await('SELECT garage FROM faction WHERE tag = ?', {tag})
    local garages = row and (json.decode(row.garage or '[]') or {}) or {}
    local position = GetEntityCoords(ped)
    for i = 1, #garages do
        local coords = garages[i].coords
        if coords and #(position - vector3(tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0)) <= 12.0 then return true end
    end
    return false
end

local function nearFactionVehicle(playerId, plate)
    local ped = GetPlayerPed(playerId)
    if ped == 0 then return false end
    local position = GetEntityCoords(ped)
    local cleanedPlate = tostring(plate or ''):gsub('%s+', '')
    for _, vehicle in pairs(GetAllVehicles()) do
        if tostring(GetVehicleNumberPlateText(vehicle) or ''):gsub('%s+', '') == cleanedPlate and #(position - GetEntityCoords(vehicle)) <= 12.0 then return true end
    end
    return false
end

RegisterServerEvent('FactionVehicle:server:CreateVehicle', function(vehicleName, tag, id, plate, chooseColor)
    local playerId = source
    if not isAuthorizedToEditVehicles(playerId, tag) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit CreateVehicle!'):format(GetPlayerName(playerId), playerId))
        return
    end

    local vehiclePlate = plate
    if not vehiclePlate or vehiclePlate == "" then
        local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
        local length = 8
        local randomString = ''

        charTable = {}
        for c in chars:gmatch"." do
            table.insert(charTable, c)
        end

        for i = 1, length do
            randomString = randomString .. charTable[math.random(1, #charTable)]
        end
        vehiclePlate = randomString
    end

    local vehicleColour = {
        ["primaryColour"] = 131,
        ["secondColour"] = 0,
        ["chooseColor"] = chooseColor or false
    }
    local vehicleHealth = {
        ['engine'] = 1000.0,
        ['body'] = 1000.0,
        ['tank'] = 1000.0,
    }
    MySQL.insert.await('INSERT INTO faction_vehicles (identifier, name, type, plate, status, colour) VALUES\n\
                                                 (@identifier, @name, @type, @plate, 0, @colour)', {
        ['@identifier'] = 'garage'..id,
        ['@name'] = vehicleName,
        ['@type'] = tag,
        ['@plate'] = vehiclePlate,
        ['@colour'] = json.encode(vehicleColour)
    })
end)

RegisterServerEvent('FactionVehicle:server:RemoveVehicle', function(plate, tag)
    local playerId = source
    if not isAuthorizedToEditVehicles(playerId, tag) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit RemoveVehicle!'):format(GetPlayerName(playerId), playerId))
        return
    end

    MySQL.query('DELETE FROM faction_vehicles WHERE plate = ? AND type = ?', {plate, tag})
end)

ESX.RegisterServerCallback('FactionVehicle:server:GetFactionVehicle', function(source, callback, plate, tag)
    if not isFactionMember(source, tag) or not nearFactionGarage(source, tag) then return callback(nil) end
    MySQL.Async.fetchAll('SELECT * FROM faction_vehicles WHERE plate = @plate and type = @tag', {
        ['@plate'] = plate,
        ['@tag'] = tag
    }, function(results)
        callback(results[1])
    end)
end)

ESX.RegisterServerCallback('FactionVehicle:server:UpdateStatusSpawn', function(source, callback, plate, playerId)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        print(("[FactionVehicle] Error: xPlayer not found for source %s"):format(source))
        callback(nil)
        return
    end
    local factionTag = getVehicleFaction(plate)
    if not factionTag or not isFactionMember(source, factionTag) or not nearFactionGarage(source, factionTag) then return callback(nil) end

    MySQL.Async.fetchAll('UPDATE faction_vehicles SET status = 1, lastDriver = @lastDriver WHERE plate = @plate', {
        ['@plate'] = plate,
        ['@lastDriver'] = xPlayer.getName()
    }, function(result)
        MySQL.Async.fetchAll('SELECT * FROM faction_vehicles WHERE plate = @plate', {['@plate'] = plate
        }, function(results)
            local trimmedPlate = string.match(plate, "^%s*(.-)%s*$")
            pcall(function()
                exports['jg-mechanic']:ResetVehicleServicingData(plate)
                exports['jg-mechanic']:ResetVehicleServicingData(trimmedPlate)
            end)
            exports['vehicleCore']:GiveVehicleKey(src, trimmedPlate)
            callback(results[1])
        end)
    end)
end)

ESX.RegisterServerCallback('FactionVehicle:server:Despawn', function(source, callback, plate, tag, coords, colour, tires, body, windows, health, fuel)
    if not isFactionMember(source, tag) or not nearFactionGarage(source, tag) or not nearFactionVehicle(source, plate) then return callback(false) end
    MySQL.Async.fetchAll('SELECT * FROM faction_vehicles WHERE plate = @plate AND type = @type', {
        ['@plate'] = plate,
        ['@type'] = tag
    }, function(results)
        if results and results[1] then
            dataTires = json.decode(results[1].tires)
            for i, v in ipairs(dataTires) do
                for _, gv in ipairs(tires) do
                    if v.name == gv.name then
                        v.status = gv.status
                    end
                end
            end
            dataBody = json.decode(results[1].body)
            for i, v in ipairs(dataBody) do
                for _, gv in ipairs(body) do
                    if v.name == gv.name then
                        v.status = gv.status
                    end
                end
            end
            dataWindows = json.decode(results[1].windows)
            for i, v in ipairs(dataWindows) do
                for _, gv in ipairs(windows) do
                    if v.name == gv.name then
                        v.status = gv.status
                    end
                end
            end

            local inv = exports.ox_inventory:GetInventory('glove'..plate, false)
            local items = {}
            for _, results in pairs(inv.items) do
                local metadata = {}
                if json.encode(results.metadata) ~= '[]' then
                    metadata = results.metadata
                end
                table.insert(items, {
                    ['name'] = results.name,
                    ['slot'] = results.slot,
                    ['count'] = results.count,
                    ['metadata'] = metadata
                })
            end
            exports.ox_inventory:ClearInventory('glove'..plate, false)

            -- Lưu trunk inventory
            local trimmedPlate = string.upper(string.match(plate, "^%s*(.-)%s*$"))
            local trunkInv = exports.ox_inventory:GetInventory('trunk'..trimmedPlate, false)
            local trunkItems = {}
            if trunkInv and trunkInv.items then
                for _, tItem in pairs(trunkInv.items) do
                    local metadata = {}
                    if json.encode(tItem.metadata) ~= '[]' then
                        metadata = tItem.metadata
                    end
                    table.insert(trunkItems, {
                        ['name'] = tItem.name,
                        ['slot'] = tItem.slot,
                        ['count'] = tItem.count,
                        ['metadata'] = metadata
                    })
                end
            end

            MySQL.Async.fetchAll('UPDATE faction_vehicles SET status = 0, fuel = @fuel, tires = @tires, body = @body, windows = @windows, \n\
                                                            coords = @coords, colour = @colour, health = @health, glovebox = @glovebox, trunk = @trunk WHERE plate = @plate AND type = @type', {
                ['@fuel'] = tonumber(fuel),
                ['@tires'] = json.encode(dataTires),
                ['@body'] = json.encode(dataBody),
                ['@windows'] = json.encode(dataWindows),
                ['@coords'] = json.encode(coords),
                ['@colour'] = json.encode(colour),
                ['@health'] = json.encode(health),
                ['@glovebox'] = json.encode(items),
                ['@trunk'] = json.encode(trunkItems),
                ['@plate'] = plate,
                ['@type'] = tag
            }, function(result)
                callback(result)
            end)
        end
    end)
end)

ESX.RegisterServerCallback('FactionPanel:server:GetGarageVehicles', function(source, callback, tag, garageId)
    if not isFactionMember(source, tag) then return callback({}) end
    MySQL.Async.fetchAll('SELECT * FROM faction_vehicles WHERE type = @type AND identifier = @identifier', {
        ['@type'] = tag,
        ['@identifier'] = 'garage'..tostring(garageId)
    }, function(results)
        callback(results)
    end)
end)
