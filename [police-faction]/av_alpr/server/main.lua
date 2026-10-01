local plateCache = {}
local plateCacheCount = 0
local pendingLookups = {}
local lookupRateLimits = {}

local function TrimPlate(plate)
    return tostring(plate or ''):match('^%s*(.-)%s*$'):upper()
end

local function NormalizePlate(plate)
    return TrimPlate(plate):gsub('%s+', '')
end

local function DefaultProfile()
    return {
        owner = 'Unknown',
        photo = nil,
        flags = {},
        autoLock = false
    }
end

local function FactionProfile(factionTag)
    factionTag = type(factionTag) == 'string' and TrimPlate(factionTag) or 'FACTION'
    if factionTag == '' then factionTag = 'FACTION' end

    return {
        owner = ('Faction Vehicle - %s'):format(factionTag),
        photo = nil,
        flags = {},
        autoLock = false,
        factionTag = factionTag
    }
end

local function IsPolice(source)
    local player = Player(source)
    local state = player and player.state
    return state and state.factionCategory == 'police'
end

local function SendProfile(request, profile)
    if GetPlayerName(request.source) then
        TriggerClientEvent('av_alpr:setOwner', request.source, request.camera, request.plate, profile)
    end
end

local function StoreCache(cacheKey, profile)
    local now = os.time()
    local maxEntries = Config.ProfileCacheMaxEntries or 1000

    if not plateCache[cacheKey] and plateCacheCount >= maxEntries then
        local oldestKey, oldestExpiry
        for key, cached in pairs(plateCache) do
            if not oldestExpiry or cached.expiresAt < oldestExpiry then
                oldestKey = key
                oldestExpiry = cached.expiresAt
            end
        end
        if oldestKey then
            plateCache[oldestKey] = nil
            plateCacheCount = math.max(0, plateCacheCount - 1)
        end
    end

    if not plateCache[cacheKey] then
        plateCacheCount = plateCacheCount + 1
    end
    plateCache[cacheKey] = {
        profile = profile,
        expiresAt = now + (Config.ProfileCacheTTL or 30)
    }
end

local function GetTargetVehicle(source, targetNetId, expectedPlate)
    targetNetId = tonumber(targetNetId) or 0
    if targetNetId <= 0 then return false, nil end

    local vehicle = NetworkGetEntityFromNetworkId(targetNetId)
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        return false, nil
    end

    if GetPlayerRoutingBucket(source) ~= GetEntityRoutingBucket(vehicle) then
        return false, nil
    end

    local playerPed = GetPlayerPed(source)
    if playerPed == 0 or not DoesEntityExist(playerPed) then
        return false, nil
    end

    local maxDistance = Config.ServerLookupMaxDistance or 75.0
    if #(GetEntityCoords(playerPed) - GetEntityCoords(vehicle)) > maxDistance then
        return false, nil
    end

    if NormalizePlate(GetVehicleNumberPlateText(vehicle)) ~= expectedPlate then
        return false, nil
    end

    local state = Entity(vehicle).state
    local factionTag = state and state[Config.FactionVehicleStateKey or 'FactionVehicle']
    return vehicle, factionTag
end

local function BuildLookupQuery(plateTrimmed, plateCompact)
    local boloSelect = ''
    local parameters = {}

    if GetResourceState('police_mdt') == 'started' then
        boloSelect = [[,
            (SELECT title FROM police_bolos
                WHERE status = 'active' AND (expires_at IS NULL OR expires_at > NOW())
                AND ((type = 'vehicle' AND plate = ?) OR (type = 'person' AND target_identifier = ov.owner))
                ORDER BY FIELD(priority, 'critical', 'high', 'medium', 'low'), created_at DESC LIMIT 1) AS bolo_title]]
        parameters[#parameters + 1] = plateTrimmed
    end

    parameters[#parameters + 1] = plateTrimmed
    parameters[#parameters + 1] = plateCompact
    parameters[#parameters + 1] = plateTrimmed
    parameters[#parameters + 1] = plateCompact

    local query = ([[SELECT COALESCE(id.firstname, u.firstname) AS firstname,
        COALESCE(id.lastname, u.lastname) AS lastname, id.id AS idcard_id, id.photo_url%s,
        (SELECT COUNT(*) FROM police_tickets AS pt
            WHERE pt.target_identifier = ov.owner
            AND (pt.status = 'overdue' OR (pt.status = 'active' AND pt.due_at < NOW()))) AS overdue_ticket_count
        FROM owned_vehicles AS ov
        LEFT JOIN users AS u ON u.identifier = ov.owner
        LEFT JOIN lv_idcards AS id ON id.identifier = ov.owner AND id.status = 'approved'
        WHERE ov.plate IN (?, ?) OR ov.fakeplate IN (?, ?)
        LIMIT 1]]):format(boloSelect)

    return query, parameters
end

local function QueryProfile(plateTrimmed, plateCompact)
    if not Config.UseESX then return DefaultProfile() end

    local query, parameters = BuildLookupQuery(plateTrimmed, plateCompact)
    local result = MySQL.query.await(query, parameters)
    local profile = DefaultProfile()

    if result and result[1] then
        local row = result[1]
        local firstName = row.firstname or 'Unknown'
        local lastName = row.lastname or ''

        if firstName ~= 'Unknown' then
            profile.owner = (firstName .. ' ' .. lastName):match('^%s*(.-)%s*$')
        end

        profile.photo = row.photo_url or nil
        if not row.idcard_id then
            profile.flags[#profile.flags + 1] = 'NO ID CARD'
        end

        local overdueTicketCount = tonumber(row.overdue_ticket_count) or 0
        if overdueTicketCount > 0 then
            profile.flags[#profile.flags + 1] = ('OVERDUE TICKETS (%d)'):format(overdueTicketCount)
        end

        if row.bolo_title and row.bolo_title ~= '' then
            profile.flags[#profile.flags + 1] = 'BOLO'
        end

        profile.autoLock = #profile.flags > 0
    end

    return profile
end

RegisterNetEvent('av_alpr:checkOwner', function(plate, camera, targetNetId)
    local source = source
    if not IsPolice(source) or type(plate) ~= 'string' then return end

    local plateTrimmed = TrimPlate(plate)
    local plateCompact = NormalizePlate(plate)
    if plateCompact == '' or #plateTrimmed > 16 then return end
    if camera ~= 'front' then return end

    local now = GetGameTimer()
    if now < (lookupRateLimits[source] or 0) then return end
    lookupRateLimits[source] = now + (Config.ServerLookupMinInterval or 200)

    local targetVehicle, factionTag = GetTargetVehicle(source, targetNetId, plateCompact)
    if targetVehicle == false then return end
    if factionTag then
        SendProfile({ source = source, camera = camera, plate = plate }, FactionProfile(factionTag))
        return
    end

    local cached = plateCache[plateCompact]
    if cached and cached.expiresAt > os.time() then
        SendProfile({ source = source, camera = camera, plate = plate }, cached.profile)
        return
    elseif cached then
        plateCache[plateCompact] = nil
        plateCacheCount = math.max(0, plateCacheCount - 1)
    end

    local request = {
        source = source,
        camera = camera,
        plate = plate
    }

    if pendingLookups[plateCompact] then
        pendingLookups[plateCompact][#pendingLookups[plateCompact] + 1] = request
        return
    end

    pendingLookups[plateCompact] = { request }

    CreateThread(function()
        local ok, profileOrError = xpcall(function()
            return QueryProfile(plateTrimmed, plateCompact)
        end, debug.traceback)

        local requests = pendingLookups[plateCompact] or {}
        pendingLookups[plateCompact] = nil

        local profile = ok and profileOrError or DefaultProfile()
        if ok then
            StoreCache(plateCompact, profile)
        else
            print(('[av_alpr] Profile lookup failed for plate %s: %s'):format(plateCompact, tostring(profileOrError)))
        end

        for _, queuedRequest in ipairs(requests) do
            SendProfile(queuedRequest, profile)
        end
    end)
end)

RegisterNetEvent('av_alpr:saveLog', function(data)
end)

AddEventHandler('playerDropped', function()
    local source = source
    lookupRateLimits[source] = nil

    for _, requests in pairs(pendingLookups) do
        for index = #requests, 1, -1 do
            if requests[index].source == source then
                table.remove(requests, index)
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait((Config.ProfileCacheCleanupInterval or 60) * 1000)
        local now = os.time()
        for key, cached in pairs(plateCache) do
            if cached.expiresAt <= now then
                plateCache[key] = nil
                plateCacheCount = math.max(0, plateCacheCount - 1)
            end
        end
    end
end)
