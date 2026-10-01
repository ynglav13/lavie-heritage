ESX = exports["es_extended"]:getSharedObject()

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function validateBodyWeaponConfig(coords, info)
    if type(coords) ~= 'table' or type(info) ~= 'table' then return false end

    local configuredWeapon = nil
    for i = 1, #Config.WeaponList do
        if Config.WeaponList[i].label == info.weaponItem then
            configuredWeapon = Config.WeaponList[i]
            break
        end
    end
    if not configuredWeapon or configuredWeapon.object ~= info.weapon then return false end

    local configuredBone = nil
    for i = 1, #Config.Bones do
        if Config.Bones[i].value == tonumber(info.bone) then
            configuredBone = Config.Bones[i]
            break
        end
    end
    if not configuredBone then return false end

    local limit = Config.Editor.positionHardLimit
    for _, axis in ipairs({ 'x', 'y', 'z' }) do
        if not isFiniteNumber(coords[axis]) or coords[axis] < -limit or coords[axis] > limit then
            return false
        end
    end
    for _, axis in ipairs({ 'rx', 'ry', 'rz' }) do
        local value = coords[axis] or 0.0
        if not isFiniteNumber(value) or value < Config.Editor.rotationMin or value > Config.Editor.rotationMax then
            return false
        end
    end

    return true, configuredWeapon, configuredBone
end

ESX.RegisterServerCallback('BodyWeapon:server:AddedBodyWeapon', function(playerId, cb, coords, info)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then return cb(false) end

    local valid, configuredWeapon, configuredBone = validateBodyWeaponConfig(coords, info)
    if not valid then return cb(false) end
    
    local objectCoords = {
        x = coords.x, y = coords.y, z = coords.z,
        rx = coords.rx or coords.px or 0.0,
        ry = coords.ry or coords.py or 0.0,
        rz = coords.rz or coords.pz or 0.0,
    }
    local objectInfo = {
        name = configuredWeapon.object,
        label = configuredWeapon.name,
        bone = configuredBone.value,
        boneName = configuredBone.label,
        weaponName = configuredWeapon.label
    }

    MySQL.Async.fetchAll('SELECT * FROM body_weapon WHERE id = @id AND weapon = @weapon', {
        ['@id'] = xPlayer.identifier,
        ['@weapon'] = info.weaponItem
    }, function(results)
        if #results == 0 then
            MySQL.Async.execute('INSERT INTO body_weapon (id, weapon, coords, info) VALUES (@id, @weapon, @coords, @info)', {
                ['@id'] = xPlayer.identifier,
                ['@weapon'] = info.weaponItem,
                ['@coords'] = json.encode(objectCoords),
                ['@info'] = json.encode(objectInfo)
            }, function()
                cb(true)
            end)
        else
            MySQL.Async.execute('UPDATE body_weapon SET coords = @coords, info = @info WHERE id = @id AND weapon = @weapon', {
                ['@coords'] = json.encode(objectCoords),
                ['@info'] = json.encode(objectInfo),
                ['@id'] = xPlayer.identifier,
                ['@weapon'] = info.weaponItem
            }, function()
                cb(true)
            end)
        end
    end)
end)

ESX.RegisterServerCallback('BodyWeapon:server:GetAllBodyWeapons', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        MySQL.Async.fetchAll('SELECT * FROM body_weapon WHERE id = @id', {
            ['@id'] = xPlayer.identifier
        }, function(results)
            cb(results)
        end)
    else
        cb({})
    end
end)

ESX.RegisterServerCallback('BodyWeapon:server:DeleteBodyWeapon', function(source, cb, weaponName)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        MySQL.Async.execute('DELETE FROM body_weapon WHERE id = @id AND weapon = @weapon', {
            ['@id'] = xPlayer.identifier,
            ['@weapon'] = weaponName
        }, function(affectedRows)
            cb(affectedRows > 0)
        end)
    else
        cb(false)
    end
end)
