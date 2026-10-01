local ESX = exports['es_extended']:getSharedObject()

local zones = {}
local active
local observers = {}
local sourceIdentifiers = {}
local lastOutside = {}
local ejectCooldowns = {}
local killCooldowns = {}
local vehicleCooldowns = {}
local managerCache = {}
local rosterBroadcastAt = 0
local databaseReady = false

local function notify(src, message, notifyType, duration)
    if src == 0 then
        print(('[legacy_turf] %s'):format(message))
        return
    end

    local ok = GetResourceState('lv_notify') == 'started' and pcall(function()
        exports['lv_notify']:Notify(src, {
            type = notifyType or 'info',
            title = 'Turf Event',
            message = message,
            duration = duration or 4500,
        })
    end)
    if not ok then TriggerClientEvent('esx:showNotification', src, message) end
end

local function cleanName(value)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%c]', ''):match('^%s*(.-)%s*$') or ''
    if value == '' or #value > 64 then return nil end
    return value
end

local function canManage(src, fresh)
    if src == 0 then return true end

    local now = GetGameTimer()
    local cached = managerCache[src]
    if not fresh and cached and now < cached.expires then return cached.value end

    local okPermission, permitted = pcall(function()
        return exports.aCore:HasPermission(src, Config.Permission)
    end)
    if not okPermission or not permitted then
        managerCache[src] = { value = false, expires = now + 2000 }
        return false
    end

    local okDuty, dutyAllowed = pcall(function()
        return exports.aCore:IsAdminDutyAllowed(src)
    end)
    local allowed = okDuty and dutyAllowed == true
    managerCache[src] = { value = allowed, expires = now + 2000 }
    return allowed
end

local function requireManager(src)
    if canManage(src, true) then return true end
    notify(src, 'Bạn cần quyền Admin Level 4+ và trạng thái duty hợp lệ.', 'error')
    return false
end

local function getXPlayer(src)
    return ESX.GetPlayerFromId(tonumber(src))
end

local function getIdentifier(src)
    local xPlayer = getXPlayer(src)
    if xPlayer and xPlayer.identifier then
        sourceIdentifiers[src] = xPlayer.identifier
        return xPlayer.identifier
    end
    return sourceIdentifiers[src]
end

local function getDisplayName(src, xPlayer)
    xPlayer = xPlayer or getXPlayer(src)
    local name = xPlayer and xPlayer.getName and xPlayer.getName() or GetPlayerName(src)
    if not name or name == '' then name = ('ID %s'):format(src) end
    return name:sub(1, 80)
end

local function getCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil, 0 end
    local coords = GetEntityCoords(ped)
    return { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 }, ped
end

local function arrayZones()
    local result = {}
    for _, zone in pairs(zones) do result[#result + 1] = zone end
    table.sort(result, function(a, b) return a.name:lower() < b.name:lower() end)
    return result
end

local function decodeZone(row)
    local points = {}
    if row.points and row.points ~= '' then
        local ok, decoded = pcall(json.decode, row.points)
        if ok and type(decoded) == 'table' then points = decoded end
    end

    local zone = {
        id = tonumber(row.id),
        name = tostring(row.name),
        shape = row.shape == 'poly' and 'poly' or 'circle',
        color = Config.Colors[tonumber(row.color)] and tonumber(row.color) or Config.DefaultColor,
        allowVehicles = tonumber(row.allow_vehicles) == 1,
        createdBy = row.created_by,
        points = points,
    }
    if zone.shape == 'circle' then
        zone.center = {
            x = tonumber(row.center_x) or 0.0,
            y = tonumber(row.center_y) or 0.0,
            z = tonumber(row.center_z) or 0.0,
        }
        zone.radius = tonumber(row.radius) or Config.MinRadius
        if zone.radius < Config.MinRadius or zone.radius > Config.MaxRadius then
            return nil, 'circle radius is outside configured bounds'
        end
    else
        local validPoints, validationError = TurfGeometry.validatePolygon(zone.points)
        if not validPoints then return nil, validationError end
        zone.points = validPoints
    end
    return zone
end

local function loadZones()
    local rows = MySQL.query.await('SELECT * FROM legacy_turf_zones ORDER BY name ASC') or {}
    zones = {}
    local loaded = 0
    for i = 1, #rows do
        local zone, validationError = decodeZone(rows[i])
        if zone then
            zones[zone.id] = zone
            loaded = loaded + 1
        else
            print(('[legacy_turf] Skipped invalid zone id %s: %s'):format(tostring(rows[i].id), tostring(validationError)))
        end
    end
    databaseReady = true
    print(('[legacy_turf] Loaded %d zone(s). Active event state was reset.'):format(loaded))
end

local function createTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `legacy_turf_zones` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(64) NOT NULL,
            `shape` VARCHAR(16) NOT NULL,
            `center_x` DOUBLE NULL,
            `center_y` DOUBLE NULL,
            `center_z` DOUBLE NULL,
            `radius` DOUBLE NULL,
            `points` LONGTEXT NULL,
            `color` SMALLINT UNSIGNED NOT NULL DEFAULT 3,
            `allow_vehicles` TINYINT(1) NOT NULL DEFAULT 1,
            `created_by` VARCHAR(191) NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uq_legacy_turf_zones_name` (`name`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
end

local function clientZone(zone)
    local result = {
        id = zone.id,
        name = zone.name,
        shape = zone.shape,
        color = zone.color,
        allowVehicles = zone.allowVehicles,
    }
    if zone.shape == 'circle' then
        result.center = zone.center
        result.radius = zone.radius
    else
        result.points = zone.points
    end
    return result
end

local function activePayload()
    if not active then return nil end
    return {
        zone = clientZone(active.zone),
        state = active.state,
        allowVehicles = active.allowVehicles,
        bucket = active.bucket,
    }
end

local function isObserving(src)
    local subscription = observers[src]
    return subscription and (subscription.manual or subscription.auto) and canManage(src)
end

local function broadcastActive()
    TriggerClientEvent('legacy_turf:client:syncActive', -1, activePayload())
end

local function sendAdminData(src)
    if not canManage(src) then return end
    TriggerClientEvent('legacy_turf:client:adminData', src, {
        zones = arrayZones(),
        active = activePayload(),
    })
end

local function sendAdminDataToObservers()
    for src in pairs(observers) do
        if isObserving(src) then sendAdminData(src) end
    end
end

local function notifyObservers(message, kind)
    for src in pairs(observers) do
        if isObserving(src) then
            TriggerClientEvent('legacy_turf:client:observerNotice', src, message, kind or 'info')
        end
    end
end

local function rosterPlayers()
    if not active then return {} end
    local players = {}
    local now = GetGameTimer()

    if active.state == 'open' then
        for src, entry in pairs(active.presence) do
            if entry.inside then
                players[#players + 1] = {
                    id = src,
                    name = entry.name,
                    status = 'inside',
                }
            end
        end
    else
        for _, entry in pairs(active.roster) do
            local status = 'inside'
            local remaining
            if entry.eliminated then
                status = 'eliminated'
            elseif entry.outsideSince then
                status = 'outside'
                remaining = math.max(0, Config.CountdownSeconds - math.floor((now - entry.outsideSince) / 1000))
            end
            players[#players + 1] = {
                id = entry.src or '-',
                name = entry.name,
                status = status,
                remaining = remaining,
            }
        end
    end

    table.sort(players, function(a, b)
        local aId = tonumber(a.id) or 999999
        local bId = tonumber(b.id) or 999999
        if a.status == b.status then return aId < bId end
        return a.status < b.status
    end)
    return players
end

local function broadcastRoster(force)
    if not active then return end
    local now = GetGameTimer()
    if not force and now - rosterBroadcastAt < 1000 then return end
    rosterBroadcastAt = now

    local players = rosterPlayers()
    local snapshot = {
        zone = active.zone.name,
        state = active.state,
        allowVehicles = active.allowVehicles,
        count = #players,
        players = players,
    }
    for src in pairs(observers) do
        if isObserving(src) then
            TriggerClientEvent('legacy_turf:client:observerSnapshot', src, snapshot)
        end
    end
end

local function resetRuntimeClients()
    TriggerClientEvent('legacy_turf:client:resetRuntime', -1)
end

local function normalizeZonePayload(payload, existing)
    if type(payload) ~= 'table' then return nil, 'Dữ liệu zone không hợp lệ.' end

    local name = cleanName(payload.name)
    if not name then return nil, 'Tên zone phải dài từ 1 đến 64 ký tự.' end

    local shape = payload.shape == 'poly' and 'poly' or payload.shape == 'circle' and 'circle' or existing and existing.shape
    if shape ~= 'circle' and shape ~= 'poly' then return nil, 'Loại zone không hợp lệ.' end

    local color = tonumber(payload.color) or (existing and existing.color) or Config.DefaultColor
    if not Config.Colors[color] then color = Config.DefaultColor end
    local allowVehicles = payload.allowVehicles
    if allowVehicles == nil and existing then allowVehicles = existing.allowVehicles end
    allowVehicles = allowVehicles == true or allowVehicles == 1 or allowVehicles == 'true'

    local zone = {
        id = existing and existing.id or nil,
        name = name,
        shape = shape,
        color = color,
        allowVehicles = allowVehicles,
        createdBy = existing and existing.createdBy or nil,
    }

    if shape == 'circle' then
        local center = TurfGeometry.normalizePoint(payload.center or (existing and existing.center))
        local radius = tonumber(payload.radius or (existing and existing.radius))
        if not center then return nil, 'Tâm circle không hợp lệ.' end
        if not radius or radius < Config.MinRadius or radius > Config.MaxRadius then
            return nil, ('Bán kính phải từ %.0f đến %.0f mét.'):format(Config.MinRadius, Config.MaxRadius)
        end
        zone.center = center
        zone.radius = radius + 0.0
    else
        local points, errorMessage = TurfGeometry.validatePolygon(payload.points or (existing and existing.points))
        if not points then return nil, errorMessage end
        zone.points = points
    end

    return zone
end

local function findZone(input)
    local id = tonumber(input)
    if id and zones[id] then return zones[id] end
    local wanted = tostring(input or ''):lower():match('^%s*(.-)%s*$')
    if wanted == '' then return nil end
    for _, zone in pairs(zones) do
        if zone.name:lower() == wanted then return zone end
    end
end

local function persistZone(src, payload)
    if not databaseReady then return notify(src, 'Cơ sở dữ liệu Turf chưa sẵn sàng.', 'error') end
    if not requireManager(src) then return end

    local id = tonumber(payload and payload.id)
    local existing = id and zones[id] or nil
    if id and not existing then return notify(src, 'Không tìm thấy zone cần sửa.', 'error') end
    if active and existing and active.zone.id == existing.id then
        return notify(src, 'Hãy Stop event trước khi sửa zone đang hoạt động.', 'error')
    end

    local zone, validationError = normalizeZonePayload(payload, existing)
    if not zone then return notify(src, validationError, 'error', 6000) end

    local duplicate = MySQL.scalar.await(
        'SELECT id FROM legacy_turf_zones WHERE LOWER(name) = LOWER(?) AND id <> ? LIMIT 1',
        { zone.name, id or 0 }
    )
    if duplicate then return notify(src, 'Tên zone đã tồn tại.', 'error') end

    local xPlayer = getXPlayer(src)
    local createdBy = xPlayer and xPlayer.identifier or 'console'
    local center = zone.center or {}
    local pointsJson = zone.shape == 'poly' and json.encode(zone.points) or ''
    local centerX = center.x or 0.0
    local centerY = center.y or 0.0
    local centerZ = center.z or 0.0
    local radius = zone.radius or 0.0

    if existing then
        local ok, updateError = pcall(MySQL.update.await, [[
                UPDATE legacy_turf_zones
                SET name = ?, shape = ?, center_x = ?, center_y = ?, center_z = ?, radius = ?, points = ?, color = ?, allow_vehicles = ?
                WHERE id = ?
            ]], {
                zone.name, zone.shape, centerX, centerY, centerZ, radius, pointsJson,
                zone.color, zone.allowVehicles and 1 or 0, existing.id,
            })
        if not ok then
            print(('[legacy_turf] Failed to update zone %s: %s'):format(existing.id, tostring(updateError)))
            return notify(src, 'Không thể cập nhật zone trong cơ sở dữ liệu.', 'error')
        end
        zone.id = existing.id
        zone.createdBy = existing.createdBy
        zones[zone.id] = zone
        notify(src, ('Đã cập nhật zone %s.'):format(zone.name), 'success')
    else
        local ok, insertedId = pcall(MySQL.insert.await, [[
                INSERT INTO legacy_turf_zones
                    (name, shape, center_x, center_y, center_z, radius, points, color, allow_vehicles, created_by)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]], {
                zone.name, zone.shape, centerX, centerY, centerZ, radius, pointsJson,
                zone.color, zone.allowVehicles and 1 or 0, createdBy,
            })
        if not ok or not insertedId then
            print(('[legacy_turf] Failed to create zone %s: %s'):format(zone.name, tostring(insertedId)))
            return notify(src, 'Không thể tạo zone trong cơ sở dữ liệu.', 'error')
        end
        zone.id = tonumber(insertedId)
        zone.createdBy = createdBy
        zones[zone.id] = zone
        notify(src, ('Đã tạo zone %s.'):format(zone.name), 'success')
    end

    sendAdminData(src)
end

local function startEvent(src, zoneInput, allowVehicles)
    if not requireManager(src) then return end
    if active then return notify(src, 'Đang có một Turf event hoạt động.', 'error') end

    local zone = findZone(zoneInput)
    if not zone then return notify(src, 'Không tìm thấy zone.', 'error') end

    active = {
        zone = zone,
        state = 'open',
        allowVehicles = allowVehicles == nil and zone.allowVehicles or allowVehicles == true,
        bucket = src == 0 and 0 or GetPlayerRoutingBucket(src),
        roster = {},
        presence = {},
    }
    lastOutside = {}
    ejectCooldowns = {}
    killCooldowns = {}
    vehicleCooldowns = {}

    broadcastActive()
    sendAdminData(src)
    sendAdminDataToObservers()
    notify(src, ('Đã mở Turf %s. Người chơi có thể tập trung vào zone.'):format(zone.name), 'success')
    notifyObservers(('~g~OPEN~w~ Turf %s'):format(zone.name), 'success')
    broadcastRoster(true)
    print(('[legacy_turf] %s started zone %s (%d).'):format(GetPlayerName(src) or 'console', zone.name, zone.id))
end

local function lockEvent(src)
    if not requireManager(src) then return end
    if not active then return notify(src, 'Không có Turf event đang mở.', 'error') end
    if active.state == 'locked' then return notify(src, 'Turf đã được Lock.', 'warning') end

    active.state = 'locked'
    active.roster = {}
    local count = 0
    for _, xPlayer in ipairs(ESX.GetExtendedPlayers()) do
        local playerId = xPlayer.source
        local coords = getCoords(playerId)
        if coords and GetPlayerRoutingBucket(playerId) == active.bucket
            and TurfGeometry.contains(active.zone, coords) and not canManage(playerId, true) then
            local identifier = xPlayer.identifier
            sourceIdentifiers[playerId] = identifier
            active.roster[identifier] = {
                identifier = identifier,
                src = playerId,
                name = getDisplayName(playerId, xPlayer),
                eliminated = false,
            }
            count = count + 1
            TriggerClientEvent('legacy_turf:client:participantState', playerId, {
                participant = true,
                status = 'inside',
            })
        end
    end

    broadcastActive()
    notify(src, ('Đã Lock Turf với %d người chơi.'):format(count), 'success')
    notifyObservers(('~r~LOCKED~w~ %s - %d người chơi'):format(active.zone.name, count), 'warning')
    broadcastRoster(true)
    sendAdminData(src)
    sendAdminDataToObservers()
    print(('[legacy_turf] %s locked zone %s with %d participant(s).'):format(GetPlayerName(src) or 'console', active.zone.name, count))
end

local function unlockEvent(src)
    if not requireManager(src) then return end
    if not active then return notify(src, 'Không có Turf event đang chạy.', 'error') end
    if active.state ~= 'locked' then return notify(src, 'Turf hiện chưa Lock.', 'warning') end

    active.state = 'open'
    active.roster = {}
    active.presence = {}
    resetRuntimeClients()
    broadcastActive()
    notify(src, 'Đã Unlock và xóa roster cũ. Lần Lock sau sẽ chụp roster mới.', 'success')
    notifyObservers(('~g~UNLOCKED~w~ %s'):format(active.zone.name), 'info')
    broadcastRoster(true)
    sendAdminData(src)
    sendAdminDataToObservers()
end

local function stopEvent(src)
    if not requireManager(src) then return end
    if not active then return notify(src, 'Không có Turf event đang chạy.', 'error') end

    local zoneName = active.zone.name
    active = nil
    lastOutside = {}
    ejectCooldowns = {}
    killCooldowns = {}
    vehicleCooldowns = {}
    resetRuntimeClients()
    broadcastActive()
    TriggerClientEvent('legacy_turf:client:hideObserver', -1)
    notify(src, ('Đã Stop Turf %s.'):format(zoneName), 'success')
    sendAdminData(src)
    sendAdminDataToObservers()
    print(('[legacy_turf] %s stopped zone %s.'):format(GetPlayerName(src) or 'console', zoneName))
end

RegisterNetEvent('legacy_turf:server:requestState', function()
    local src = source
    getIdentifier(src)
    TriggerClientEvent('legacy_turf:client:initialState', src, activePayload(), canManage(src, true))
end)

RegisterNetEvent('legacy_turf:server:requestAdminData', function()
    local src = source
    if not requireManager(src) then return end
    sendAdminData(src)
end)

RegisterNetEvent('legacy_turf:server:saveZone', function(payload)
    persistZone(source, payload)
end)

RegisterNetEvent('legacy_turf:server:deleteZone', function(zoneId)
    local src = source
    if not requireManager(src) then return end
    zoneId = tonumber(zoneId)
    local zone = zoneId and zones[zoneId]
    if not zone then return notify(src, 'Không tìm thấy zone.', 'error') end
    if active and active.zone.id == zoneId then
        return notify(src, 'Hãy Stop event trước khi xóa zone đang hoạt động.', 'error')
    end

    MySQL.update.await('DELETE FROM legacy_turf_zones WHERE id = ?', { zoneId })
    zones[zoneId] = nil
    notify(src, ('Đã xóa zone %s.'):format(zone.name), 'success')
    sendAdminData(src)
end)

RegisterNetEvent('legacy_turf:server:start', function(zoneId, allowVehicles)
    startEvent(source, zoneId, allowVehicles)
end)

RegisterNetEvent('legacy_turf:server:lock', function()
    lockEvent(source)
end)

RegisterNetEvent('legacy_turf:server:unlock', function()
    unlockEvent(source)
end)

RegisterNetEvent('legacy_turf:server:stop', function()
    stopEvent(source)
end)

RegisterNetEvent('legacy_turf:server:setMonitor', function(enabled, mode)
    local src = source
    if not canManage(src, true) then return end
    mode = mode == 'auto' and 'auto' or 'manual'
    observers[src] = observers[src] or { manual = false, auto = false }
    observers[src][mode] = enabled == true

    if not observers[src].manual and not observers[src].auto then
        observers[src] = nil
        TriggerClientEvent('legacy_turf:client:hideObserver', src)
        return
    end
    if active then broadcastRoster(true) end
end)

RegisterCommand('turfadmin', function(src)
    if src == 0 then return notify(src, 'Lệnh này chỉ dùng trong game.', 'error') end
    if not requireManager(src) then return end
    TriggerClientEvent('legacy_turf:client:openAdmin', src)
end, false)

RegisterCommand('startturf', function(src, args)
    if src == 0 then return notify(src, 'Hãy dùng ID zone từ console.', 'error') end
    if #args == 0 then
        if not requireManager(src) then return end
        return TriggerClientEvent('legacy_turf:client:openAdmin', src)
    end
    startEvent(src, table.concat(args, ' '), nil)
end, false)

RegisterCommand('lockturf', function(src) lockEvent(src) end, false)
RegisterCommand('unlockturf', function(src) unlockEvent(src) end, false)
RegisterCommand('stopturf', function(src) stopEvent(src) end, false)

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    sourceIdentifiers[playerId] = xPlayer.identifier
    SetTimeout(1500, function()
        if GetPlayerName(playerId) then
            TriggerClientEvent('legacy_turf:client:initialState', playerId, activePayload(), canManage(playerId, true))
        end
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local identifier = sourceIdentifiers[src]
    observers[src] = nil
    lastOutside[src] = nil
    ejectCooldowns[src] = nil
    killCooldowns[src] = nil
    vehicleCooldowns[src] = nil
    managerCache[src] = nil
    sourceIdentifiers[src] = nil

    if not active then return end
    local presence = active.presence[src]
    if active.state == 'open' and presence and presence.inside then
        notifyObservers(('~r~OUT~w~ [%d] %s (disconnect)'):format(src, presence.name), 'warning')
    end
    active.presence[src] = nil

    if active.state == 'locked' and identifier then
        local entry = active.roster[identifier]
        if entry and not entry.eliminated then
            entry.eliminated = true
            entry.disconnected = true
            entry.src = nil
            entry.outsideSince = nil
            notifyObservers(('~r~ELIMINATED~w~ %s (disconnect)'):format(entry.name), 'error')
            broadcastRoster(true)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(Config.ServerTickMs)
        if active then
            local now = GetGameTimer()
            local needsRosterBroadcast = false

            for _, xPlayer in ipairs(ESX.GetExtendedPlayers()) do
                local src = xPlayer.source
                local identifier = xPlayer.identifier
                sourceIdentifiers[src] = identifier
                local coords, ped = getCoords(src)
                if coords then
                    local sameBucket = GetPlayerRoutingBucket(src) == active.bucket
                    local inside = sameBucket and TurfGeometry.contains(active.zone, coords)
                    local manager = canManage(src)
                    local oldPresence = active.presence[src]

                    if not inside then
                        lastOutside[src] = { coords = coords, at = now }
                    end

                    if active.state == 'open' then
                        if manager then
                            if oldPresence then needsRosterBroadcast = true end
                            active.presence[src] = nil
                        elseif not oldPresence or oldPresence.inside ~= inside then
                            active.presence[src] = {
                                inside = inside,
                                name = getDisplayName(src, xPlayer),
                            }
                            if inside then
                                notifyObservers(('~g~IN~w~ [%d] %s'):format(src, active.presence[src].name), 'success')
                            elseif oldPresence and oldPresence.inside then
                                notifyObservers(('~r~OUT~w~ [%d] %s'):format(src, active.presence[src].name), 'warning')
                            end
                            needsRosterBroadcast = true
                        end
                    else
                        local entry = active.roster[identifier]
                        if manager and entry then
                            active.roster[identifier] = nil
                            entry = nil
                            TriggerClientEvent('legacy_turf:client:participantState', src, {
                                participant = false,
                                status = nil,
                            })
                            notifyObservers(('~o~OBSERVER~w~ [%d] %s đã chuyển sang Admin duty.'):format(src, getDisplayName(src, xPlayer)), 'info')
                            needsRosterBroadcast = true
                        end
                        if entry then
                            entry.src = src
                            if entry.eliminated then
                                if inside then
                                    local cooldown = killCooldowns[src] or 0
                                    if now >= cooldown then
                                        killCooldowns[src] = now + Config.ReentryKillCooldownMs
                                        TriggerClientEvent('esx:killPlayer', src)
                                        pcall(SetEntityHealth, ped, 0)
                                        TriggerClientEvent('legacy_turf:client:participantState', src, {
                                            participant = true,
                                            status = 'eliminated',
                                        })
                                        notify(src, 'Bạn đã bị loại và không được quay lại Turf.', 'error', 7000)
                                        notifyObservers(('~r~RE-ENTRY~w~ [%d] %s đã quay lại sau khi bị loại.'):format(src, entry.name), 'error')
                                    end
                                else
                                    killCooldowns[src] = nil
                                end
                            elseif inside then
                                if entry.outsideSince then
                                    entry.outsideSince = nil
                                    TriggerClientEvent('legacy_turf:client:cancelCountdown', src)
                                    TriggerClientEvent('legacy_turf:client:participantState', src, {
                                        participant = true,
                                        status = 'inside',
                                    })
                                    notifyObservers(('~g~BACK IN~w~ [%d] %s'):format(src, entry.name), 'success')
                                    needsRosterBroadcast = true
                                end
                            else
                                if not entry.outsideSince then
                                    entry.outsideSince = now
                                    TriggerClientEvent('legacy_turf:client:startCountdown', src, Config.CountdownSeconds)
                                    TriggerClientEvent('legacy_turf:client:participantState', src, {
                                        participant = true,
                                        status = 'outside',
                                    })
                                    notifyObservers(('~r~OUT~w~ [%d] %s - %ds'):format(src, entry.name, Config.CountdownSeconds), 'warning')
                                    needsRosterBroadcast = true
                                elseif now - entry.outsideSince >= Config.CountdownSeconds * 1000 then
                                    entry.eliminated = true
                                    entry.outsideSince = nil
                                    TriggerClientEvent('legacy_turf:client:cancelCountdown', src)
                                    TriggerClientEvent('legacy_turf:client:participantState', src, {
                                        participant = true,
                                        status = 'eliminated',
                                    })
                                    notify(src, 'Bạn đã ở ngoài Turf quá 10 giây và bị loại.', 'error', 7000)
                                    notifyObservers(('~r~ELIMINATED~w~ [%d] %s'):format(src, entry.name), 'error')
                                    needsRosterBroadcast = true
                                end
                            end
                        elseif inside and not manager then
                            local cooldown = ejectCooldowns[src] or 0
                            if now >= cooldown then
                                ejectCooldowns[src] = now + Config.EjectCooldownMs
                                local safe = TurfGeometry.nearestOutside(active.zone, coords, Config.EjectOffset)
                                local previous = lastOutside[src]
                                if previous and now - previous.at <= 30000 then
                                    local dx = previous.coords.x - coords.x
                                    local dy = previous.coords.y - coords.y
                                    if dx * dx + dy * dy <= 10000.0 then safe = previous.coords end
                                end
                                TriggerClientEvent('legacy_turf:client:eject', src, safe)
                                pcall(SetEntityCoords, ped, safe.x, safe.y, safe.z, false, false, false, false)
                                notify(src, 'Turf đã Lock. Bạn không thuộc roster.', 'error')
                                notifyObservers(('~o~BLOCKED~w~ [%d] %s cố vào Turf.'):format(src, getDisplayName(src, xPlayer)), 'warning')
                            end
                        end
                    end

                    if inside and not active.allowVehicles and not manager then
                        local vehicle = GetVehiclePedIsIn(ped, false)
                        if vehicle and vehicle ~= 0 and now >= (vehicleCooldowns[src] or 0) then
                            vehicleCooldowns[src] = now + 1500
                            TriggerClientEvent('legacy_turf:client:forceExitVehicle', src)
                        end
                    end
                end
            end

            if needsRosterBroadcast or (active.state == 'locked' and next(active.roster)) then
                broadcastRoster(needsRosterBroadcast)
            end
        end
    end
end)

MySQL.ready(function()
    local ok, errorMessage = pcall(function()
        createTable()
        loadZones()
    end)
    if not ok then
        databaseReady = false
        print(('[legacy_turf] Database initialization failed: %s'):format(tostring(errorMessage)))
    end
end)
