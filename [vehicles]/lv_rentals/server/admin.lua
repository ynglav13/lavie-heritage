local ESX = exports['es_extended']:getSharedObject()

local function asBool(value)
    return value == true or value == 1 or value == '1' or value == 'true' or value == 'on'
end

local function isAdmin(source)
    if source == 0 then
        return true
    end

    if Config.Admin.UseACore and GetResourceState('aCore') == 'started' then
        local ok, allowed = pcall(function()

            return exports['aCore']:IsAdmin(source)
        end)

        if ok and allowed then
            return true
        end
    end

    if IsPlayerAceAllowed(source, Config.Admin.AcePermission) then
        return true
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    return xPlayer and Config.Admin.Groups[xPlayer.getGroup()] == true
end

local function normalizeStation(input)
    input = input or {}

    local coords = input.coords or {}
    local heading = tonumber(coords.w or input.heading) or 0.0
    return
    {
        id = tonumber(input.id),
        code = Rental.safeString(input.code, 64),
        label = Rental.safeString(input.label, 100),
        coords =
        {
            x = tonumber(coords.x) or 0.0,
            y = tonumber(coords.y) or 0.0,
            z = tonumber(coords.z) or 0.0,
            w = heading
        },
        heading = heading,
        enabled = asBool(input.enabled),
        blip = input.blip ~= false and input.blip ~= 'false' and input.blip ~= 0 and input.blip ~= '0',
        maxHours = Rental.clamp(input.maxHours, Config.MinHours, Config.HardMaxHours),
        deposit = math.max(0, Rental.round(input.deposit))
    }
end

local function normalizeSpawn(input)
    input = input or {}

    local coords = input.coords or input
    return
    {
        id = tonumber(input.id),
        stationId = tonumber(input.stationId),
        coords =
        {
            x = tonumber(coords.x) or 0.0,
            y = tonumber(coords.y) or 0.0,
            z = tonumber(coords.z) or 0.0,
            w = tonumber(coords.w or input.heading) or 0.0
        }
    }
end

local function normalizeVehicle(input)
    input = input or {}
    return
    {
        id = tonumber(input.id),
        stationId = tonumber(input.stationId),
        model = Rental.safeString(input.model, 60):lower(),
        label = Rental.safeString(input.label, 100),
        pricePerHour = math.max(0, Rental.round(input.pricePerHour)),
        deposit = math.max(0, Rental.round(input.deposit)),
        image = Rental.safeString(input.image, 255),
        enabled = asBool(input.enabled)
    }
end

lib.callback.register('lv_rentals:server:isAdmin', function(source)
    return isAdmin(source)
end)

lib.callback.register('lv_rentals:server:adminData', function(source)
    if not isAdmin(source) then
        return
        {
            ok = false,
            message = Config.Text.noPermission
        }
    end

    local stations = MySQL.query.await('SELECT * FROM lv_rental_stations ORDER BY id ASC') or {}
    local spawns = MySQL.query.await('SELECT * FROM lv_rental_spawns ORDER BY id ASC') or {}
    local vehicles = MySQL.query.await('SELECT * FROM lv_rental_vehicles ORDER BY id ASC') or {}
    local active = MySQL.query.await('SELECT * FROM lv_rental_active ORDER BY rented_at DESC') or {}
    return
    {
        ok = true,
        stations = stations,
        spawns = spawns,
        vehicles = vehicles,
        active = active,
        hardMaxHours = Config.HardMaxHours
    }
end)

lib.callback.register('lv_rentals:server:saveStation', function(source, payload)
    if not isAdmin(source) then
        return
        {
            ok = false,
            message = Config.Text.noPermission
        }
    end

    local station = normalizeStation(payload)

    if station.code == '' or station.label == '' then
        return
        {
            ok = false,
            message = Config.Text.invalidRequest
        }
    end

    if station.id then
        MySQL.update.await('UPDATE lv_rental_stations SET code = ?, label = ?, coords = ?, heading = ?, enabled = ?, blip = ?, max_hours = ?, deposit = ? WHERE id = ?',
        {
            station.code,
            station.label,
            json.encode(station.coords),
            station.heading,
            station.enabled and 1 or 0,
            station.blip and 1 or 0,
            station.maxHours,
            station.deposit,
            station.id
        })
    else
        station.id = MySQL.insert.await('INSERT INTO lv_rental_stations (code, label, coords, heading, enabled, blip, max_hours, deposit) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        {
            station.code,
            station.label,
            json.encode(station.coords),
            station.heading,
            station.enabled and 1 or 0,
            station.blip and 1 or 0,
            station.maxHours,
            station.deposit
        })
    end

    Rental.ReloadStations()
    Rental.log('admin_station_save', source,
    {
        stationId = station.id,
        metadata = station
    })
    return
    {
        ok = true,
        id = station.id,
        message = 'Đã lưu điểm thuê phương tiện'
    }
end)

lib.callback.register('lv_rentals:server:deleteStation', function(source, stationId)
    if not isAdmin(source) then
        return
        {
            ok = false,
            message = Config.Text.noPermission
        }
    end

    stationId = tonumber(stationId)

    if not stationId then
        return
        {
            ok = false,
            message = Config.Text.invalidRequest
        }
    end

    local exists = MySQL.scalar.await('SELECT id FROM lv_rental_stations WHERE id = ?',
    {
        stationId
    })

    if not exists then
        return
        {
            ok = false,
            message = 'Không tìm thấy điểm thuê phương tiện'
        }
    end

    local activeCount = MySQL.scalar.await('SELECT COUNT(*) FROM lv_rental_active WHERE station_id = ?',
    {
        stationId
    }) or 0
    
    if activeCount > 0 then
        return
        {
            ok = false,
            message = 'Điểm thuê này hiện đang có phương tiện đang được thuê'
        }
    end

    MySQL.query.await('DELETE FROM lv_rental_stations WHERE id = ?',
    {
        stationId
    })
    MySQL.query.await('DELETE FROM lv_rental_spawns WHERE station_id = ?',
    {
        stationId
    })
    MySQL.query.await('DELETE FROM lv_rental_vehicles WHERE station_id = ?',
    {
        stationId
    })

    Rental.ReloadStations()
    Rental.log('admin_station_delete', source,
    {
        stationId = stationId
    })
    return
    {
        ok = true,
        message = 'Đã xóa điểm thuê phương tiện'
    }
end)

lib.callback.register('lv_rentals:server:saveSpawn', function(source, payload)
    if not isAdmin(source) then
        return
        {
            ok = false,
            message = Config.Text.noPermission
        }
    end

    local spawn = normalizeSpawn(payload)
    
    if not spawn.stationId then
        return
        {
            ok = false,
            message = Config.Text.invalidRequest
        }
    end

    if spawn.id then
        MySQL.update.await('UPDATE lv_rental_spawns SET coords = ?, heading = ? WHERE id = ? AND station_id = ?',
        {
            json.encode(spawn.coords),
            spawn.coords.w,
            spawn.id,
            spawn.stationId
        })
    else
        spawn.id = MySQL.insert.await('INSERT INTO lv_rental_spawns (station_id, coords, heading) VALUES (?, ?, ?)',
        {
            spawn.stationId,
            json.encode(spawn.coords),
            spawn.coords.w
        })
    end

    Rental.ReloadStations()
    Rental.log('admin_spawn_save', source,
    {
        stationId = spawn.stationId,
        metadata = spawn
    })
    return
    {
        ok = true,
        id = spawn.id,
        message = 'Đã lưu điểm Spawn phương tiện'
    }
end)

lib.callback.register('lv_rentals:server:deleteSpawn', function(source, spawnId)
    if not isAdmin(source) then
        return
        {
            ok = false,
            message = Config.Text.noPermission
        }
    end

    spawnId = tonumber(spawnId)

    if not spawnId then
        return
        {
            ok = false,
            message = Config.Text.invalidRequest
        }
    end

    MySQL.query.await('DELETE FROM lv_rental_spawns WHERE id = ?',
    {
        spawnId
    })

    Rental.ReloadStations()
    Rental.log('admin_spawn_delete', source,
    {
        metadata =
        {
            spawnId = spawnId
        }
    })
    return
    {
        ok = true,
        message = 'Đã xóa điểm Spawn phương tiện'
    }
end)

lib.callback.register('lv_rentals:server:saveVehicle', function(source, payload)
    if not isAdmin(source) then
        return
        {
            ok = false,
            message = Config.Text.noPermission
        }
    end

    local vehicle = normalizeVehicle(payload)
    
    if not vehicle.stationId or vehicle.model == '' or vehicle.label == '' then
        return
        {
            ok = false,
            message = Config.Text.invalidRequest
        }
    end

    if vehicle.id then
        MySQL.update.await('UPDATE lv_rental_vehicles SET model = ?, label = ?, price_per_hour = ?, deposit = ?, image = ?, enabled = ? WHERE id = ? AND station_id = ?',
        {
            vehicle.model,
            vehicle.label,
            vehicle.pricePerHour,
            vehicle.deposit,
            vehicle.image,
            vehicle.enabled and 1 or 0,
            vehicle.id,
            vehicle.stationId
        })
    else
        vehicle.id = MySQL.insert.await('INSERT INTO lv_rental_vehicles (station_id, model, label, price_per_hour, deposit, image, enabled) VALUES (?, ?, ?, ?, ?, ?, ?)',
        {
            vehicle.stationId,
            vehicle.model,
            vehicle.label,
            vehicle.pricePerHour,
            vehicle.deposit,
            vehicle.image,
            vehicle.enabled and 1 or 0
        })
    end

    Rental.ReloadStations()
    Rental.log('admin_vehicle_save', source,
    {
        stationId = vehicle.stationId,
        model = vehicle.model,
        metadata = vehicle
    })
    return
    {
        ok = true,
        id = vehicle.id,
        message = 'Đã lưu phương tiện'
    }
end)

lib.callback.register('lv_rentals:server:deleteVehicle', function(source, vehicleId)
    if not isAdmin(source) then
        return
        {
            ok = false,
            message = Config.Text.noPermission
        }
    end

    vehicleId = tonumber(vehicleId)

    if not vehicleId then
        return
        {
            ok = false,
            message = Config.Text.invalidRequest
        }
    end

    MySQL.query.await('DELETE FROM lv_rental_vehicles WHERE id = ?',
    {
        vehicleId
    })

    Rental.ReloadStations()
    Rental.log('admin_vehicle_delete', source,
    {
        metadata =
        {
            vehicleId = vehicleId
        }
    })
    return
    {
        ok = true,
        message = 'Đã xóa phương tiện'
    }
end)

RegisterCommand(Config.AdminCommand, function(source)
    if not isAdmin(source) then
        Rental.notify(source, Config.Text.noPermission, 'error')
        return
    end

    TriggerClientEvent('lv_rentals:client:openAdmin', source)
end, false)
