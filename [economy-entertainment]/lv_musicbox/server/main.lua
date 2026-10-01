local resourceName = GetCurrentResourceName()
local musicboxTokenPath = '/srv/lslegacy/state/musicbox-token'

local function loadMusicboxToken()
    local configured = GetConvar('musicboxApiToken', '')

    if configured ~= '' then
        return configured
    end

    local handle = io.open(musicboxTokenPath, 'r')

    if not handle then
        return ''
    end

    local token = handle:read('*l') or ''
    handle:close()
    return token
end

local function musicboxHeaders()
    local token = loadMusicboxToken()

    if token == '' then
        return {}
    end

    return { ['X-Musicbox-Token'] = token }
end

local sources = {}
local vehicleSources = {}
local libraries = {}
local lastRequestAt = {}
local nextSourceId = 0
local saveQueued = false
local syncSources

local function locale(key, ...)
    local pack = Locales[Config.Locale] or Locales.en or {}
    local fallback = Locales.en or {}
    local text = pack[key] or fallback[key] or key

    if select('#', ...) > 0 then
        return text:format(...)
    end
    return text
end

local function debugPrint(...)
    if Config.Debug then
        print(('[%s]'):format(resourceName), ...)
    end
end

local function clamp(value, min, max)
    value = tonumber(value) or min

    if value < min then
        return min
    end

    if value > max then
        return max
    end
    return value
end

local function notify(target, message, notifyType)
    if not target or target <= 0 then
        return
    end

    if Config.Notification.useLvNotify and GetResourceState('lv_notify') == 'started' then
        exports['lv_notify']:Notify(target,
        {
            title = Config.Notification.title,
            message = message,
            type = notifyType or 'inform'
        })
        return
    end

    TriggerClientEvent('ox_lib:notify', target,
    {
        title = Config.Notification.title,
        description = message,
        type = notifyType or 'inform'
    })
end

local function sendPlayStatus(target, requestId, state, message, sourceId)
    if not target or target <= 0 then
        return
    end

    TriggerClientEvent('lv_musicbox:client:playStatus', target,
    {
        requestId = requestId,
        state = state,
        message = message,
        sourceId = sourceId
    })
end

local function coordsToTable(coords)
    if not coords then
        return nil
    end
    return
    {
        x = coords.x + 0.0,
        y = coords.y + 0.0,
        z = coords.z + 0.0
    }
end

local function tableToVec3(coords)
    if not coords then
        return nil
    end
    return vector3(
        tonumber(coords.x) or 0.0,
        tonumber(coords.y) or 0.0,
        tonumber(coords.z) or 0.0
    )
end

local function getIdentifier(src)
    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if identifier:find('license:', 1, true) then
            return identifier
        end
    end
    return ('source:%s'):format(src)
end

local function loadLibraries()
    local raw = LoadResourceFile(resourceName, Config.StorageFile)

    if not raw or raw == '' then
        libraries = {}
        return
    end

    local ok, decoded = pcall(json.decode, raw)

    libraries = ok and type(decoded) == 'table' and decoded or {}
end

local function saveLibraries()
    SaveResourceFile(resourceName, Config.StorageFile, json.encode(libraries), -1)
end

local PlacedSourcesFile = 'data/placed_sources.json'

local function savePlacedSources()
    local persistent = {}

    for sourceId, sourceData in pairs(sources) do
        if sourceData.type ~= 'vehicle' then
            persistent[sourceId] =
            {
                id = sourceData.id,
                type = sourceData.type,
                ownerIdentifier = sourceData.ownerIdentifier,
                label = sourceData.label,
                item = sourceData.item,
                model = sourceData.model,
                coords = sourceData.coords,
                heading = sourceData.heading,
                distance = sourceData.distance,
                volume = sourceData.volume,
                loop = sourceData.loop,
                paused = sourceData.paused,
                pausedAt = sourceData.pausedAt,
                startedAt = sourceData.startedAt,
                url = sourceData.url,
                input = sourceData.input,
                videoId = sourceData.videoId,
                title = sourceData.title,
                duration = sourceData.duration,
                queue = sourceData.queue or {}
            }
        end
    end

    SaveResourceFile(resourceName, PlacedSourcesFile, json.encode(persistent,
    {
        indent = true
    }), -1)
end

local function loadPlacedSources()
    local content = LoadResourceFile(resourceName, PlacedSourcesFile)

    if not content then
        return
    end

    local ok, decoded = pcall(json.decode, content)

    if not ok or type(decoded) ~= 'table' then
        return
    end

    CreateThread(function()
        for sourceId, data in pairs(decoded) do
            local modelHash = type(data.model) == 'string' and GetHashKey(data.model) or data.model
            local entity = CreateObjectNoOffset(modelHash, data.coords.x, data.coords.y, data.coords.z, true, true, false)
            local timeout = 50

            while not DoesEntityExist(entity) and timeout > 0 do
                Wait(10)

                timeout = timeout - 1
            end

            if DoesEntityExist(entity) then
                SetEntityHeading(entity, data.heading or 0.0)

                local netId = NetworkGetNetworkIdFromEntity(entity)

                sources[sourceId] =
                {
                    id = data.id,
                    type = data.type,
                    ownerIdentifier = data.ownerIdentifier,
                    label = data.label,
                    item = data.item,
                    model = data.model,
                    netId = netId,
                    mode = 'placed',
                    coords = data.coords,
                    heading = data.heading,
                    distance = data.distance,
                    volume = data.volume,
                    loop = data.loop == true,
                    paused = data.paused == true,
                    pausedAt = data.pausedAt,
                    startedAt = data.startedAt,
                    url = data.url,
                    input = data.input,
                    videoId = data.videoId,
                    title = data.title,
                    duration = data.duration,
                    queue = data.queue or {},
                    version = 0
                }
            end
        end

        syncSources()
    end)
end

local function queueSave()
    if saveQueued then
        return
    end

    saveQueued = true

    SetTimeout(1500, function()
        saveQueued = false

        saveLibraries()
    end)
end

local function getLibrary(src)
    local identifier = getIdentifier(src)

    libraries[identifier] = libraries[identifier] or
    {
        favorites = {},
        recent = {}
    }

    libraries[identifier].favorites = libraries[identifier].favorites or {}
    libraries[identifier].recent = libraries[identifier].recent or {}
    return libraries[identifier]
end

local function sendLibrary(src)
    local library = getLibrary(src) or
    {
        favorites = {},
        recent = {}
    }
    local libraryCopy =
    {
        favorites = library.favorites or {},
        recent = library.recent or {},
        cdnFiles = cdnFiles or {}
    }

    TriggerClientEvent('lv_musicbox:client:library', src, libraryCopy)
end

local function sameTrack(a, b)
    if not a or not b then
        return false
    end

    if a.videoId and b.videoId and a.videoId == b.videoId then
        return true
    end
    return a.input and b.input and a.input == b.input
end

local function trimList(list, maxItems)
    while #list > maxItems do
        table.remove(list)
    end
end

local function addRecent(src, track)
    local library = getLibrary(src)

    for index = #library.recent, 1, -1 do
        if sameTrack(library.recent[index], track) then
            table.remove(library.recent, index)
        end
    end

    table.insert(library.recent, 1,
    {
        input = track.input,
        videoId = track.videoId,
        title = track.title or track.input,
        addedAt = os.time()
    })

    trimList(library.recent, Config.MaxRecent)

    queueSave()

    sendLibrary(src)
end

local function countOwnedSources(src)
    local count = 0

    for _, sourceData in pairs(sources) do
        if sourceData.owner == src and sourceData.type ~= 'vehicle' then
            count = count + 1
        end
    end
    return count
end

local function makeSourceId(prefix)
    nextSourceId = nextSourceId + 1
    return ('%s:%d:%d'):format(prefix, os.time(), nextSourceId)
end

local function playbackPosition(sourceData)
    if not sourceData or not sourceData.url then
        return 0
    end

    if sourceData.paused then
        return sourceData.pausedAt or 0
    end
    
    local elapsed = math.max(0, os.time() - (sourceData.startedAt or os.time()))
    local duration = tonumber(sourceData.duration) or 0
    
    if duration > 0 then
        if sourceData.loop then
            return elapsed % duration
        elseif elapsed > duration then
            return duration
        end
    end
    return elapsed
end

local function touchSource(sourceData)
    sourceData.version = (sourceData.version or 0) + 1
end

local function exportSource(sourceData)
    return
    {
        id = sourceData.id,
        type = sourceData.type,
        owner = sourceData.owner,
        label = sourceData.label,
        item = sourceData.item,
        model = sourceData.model,
        netId = sourceData.netId,
        vehicleNetId = sourceData.vehicleNetId,
        holder = sourceData.holder,
        mode = sourceData.mode,
        coords = sourceData.coords,
        heading = sourceData.heading,
        distance = sourceData.distance,
        volume = sourceData.volume,
        url = sourceData.url,
        input = sourceData.input,
        videoId = sourceData.videoId,
        title = sourceData.title,
        duration = sourceData.duration,
        loop = sourceData.loop,
        paused = sourceData.paused,
        position = playbackPosition(sourceData),
        queue = sourceData.queue or {},
        version = sourceData.version or 0
    }
end

local function exportSources()
    local payload = {}

    for sourceId, sourceData in pairs(sources) do
        payload[sourceId] = exportSource(sourceData)
    end
    return payload
end

syncSources = function(target)
    TriggerClientEvent('lv_musicbox:client:syncSources', target or -1, exportSources())
end

local function getPlayerCoords(src)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return nil
    end
    return GetEntityCoords(ped)
end

local function getNetworkEntityCoords(netId)
    if not netId or not NetworkGetEntityFromNetworkId then
        return nil
    end

    local entity = NetworkGetEntityFromNetworkId(tonumber(netId))

    if entity and entity ~= 0 and DoesEntityExist(entity) then
        return GetEntityCoords(entity)
    end
    return nil
end

local function getSourceCoords(sourceData)
    if sourceData.vehicleNetId then
        local vehicleCoords = getNetworkEntityCoords(sourceData.vehicleNetId)

        if vehicleCoords then
            return vehicleCoords
        end
    end

    if sourceData.netId then
        local objectCoords = getNetworkEntityCoords(sourceData.netId)

        if objectCoords then
            return objectCoords
        end
    end
    return tableToVec3(sourceData.coords)
end

local function playerNearSource(src, sourceData, distance)
    local playerCoords = getPlayerCoords(src)
    local sourceCoords = getSourceCoords(sourceData)

    if not playerCoords or not sourceCoords then
        return false
    end
    return #(playerCoords - sourceCoords) <= distance
end

local function canControl(src, sourceData)
    if not sourceData then
        return false
    end

    if sourceData.owner == src or sourceData.holder == src then
        return true
    end

    if sourceData.type == 'vehicle' then
        return playerNearSource(src, sourceData, Config.InteractionDistance + 1.5)
    end
    return false
end

local function urlencode(value)
    value = tostring(value or '')
    value = value:gsub('\n', '\r\n')
    value = value:gsub('([^%w%-_%.~])', function(char)
        return ('%%%02X'):format(string.byte(char))
    end)
    return value
end

local function trim(value)
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function extractVideoId(input)
    input = trim(input)

    if input:match('^[%w_-][%w_-][%w_-][%w_-][%w_-][%w_-][%w_-][%w_-][%w_-][%w_-][%w_-]$') then
        return input
    end

    local patterns =
    {
        '[?&]v=([%w_-]+)',
        'youtu%.be/([%w_-]+)',
        '/shorts/([%w_-]+)',
        '/embed/([%w_-]+)'
    }

    for _, pattern in ipairs(patterns) do
        local found = input:match(pattern)

        if found and #found >= 11 then
            return found:sub(1, 11)
        end
    end

    if input ~= '' and not input:find('^https?://') then
        return input
    end
    return nil
end

local function isDirectUrl(input)
    return input:match('^https?://') and not input:find('youtube%.com', 1, false) and not input:find('youtu%.be', 1, false)
end

local function resolverUrl(videoId)
    local endpoint = trim(Config.Resolver.endpoint)

    if endpoint == '' then
        return nil
    end

    local encodedId = urlencode(videoId)

    if endpoint:find('{id}', 1, true) then
        return endpoint:gsub('{id}', encodedId)
    end

    local separator = endpoint:find('?', 1, true) and '&' or '?'
    return endpoint .. separator .. 'id=' .. encodedId
end

local function resolveTrack(src, input, cb)
    input = trim(input)

    if input == '' then
        cb(false, locale('invalid_input'))
        return
    end

    if isDirectUrl(input) then
        if not Config.Resolver.allowDirectUrls then
            cb(false, locale('direct_url_disabled'))
            return
        end

        cb(true,
        {
            input = input,
            url = input,
            title = input
        })
        return
    end

    local lowerInput = input:lower()
    for _, file in ipairs(cdnFiles or {}) do
        if type(file) == 'table' then
            local fn = tostring(file.filename or '')
            local tt = tostring(file.title or '')

            if fn ~= '' and (fn:lower() == lowerInput or tt:lower() == lowerInput or fn:lower() == lowerInput .. '.mp3' or fn:lower() == lowerInput .. '.webm') then
                local baseEndpoint = Config.Resolver.endpoint:gsub('/resolve.*', '')
                local streamUrl = baseEndpoint .. '/stream/' .. urlencode(fn)

                cb(true,
                {
                    input = input,
                    url = streamUrl,
                    title = file.title or fn,
                    duration = tonumber(file.duration) or 0
                })
                return
            end
        end
    end

    local videoId = extractVideoId(input)

    if not videoId then
        cb(false, locale('invalid_input'))
        return
    end

    local isYoutube = #videoId == 11 and not videoId:find('%.')

    if isYoutube then
        local ESX = exports['es_extended']:getSharedObject()
        local xPlayer = ESX.GetPlayerFromId(src)
        local isAdmin = false

        if xPlayer then
            local group = xPlayer.getGroup()

            isAdmin = group == 'admin' or group == 'superadmin' or group == 'god' or group == 'helper'
        end

        local isPrime = Player(src).state.isPrime == true

        if not isPrime and not isAdmin then
            cb(false, 'Tính năng phát nhạc YouTube chỉ dành cho người chơi Prime')
            return
        end
    end

    local url = resolverUrl(videoId)

    if not url then
        cb(false, locale('resolver_missing'))
        return
    end

    PerformHttpRequest(url, function(statusCode, body)
        local code = tonumber(statusCode) or 0

        if code < 200 or code >= 300 or not body then
            debugPrint('resolver failed', statusCode, body)

            cb(false, locale('resolver_failed'))
            return
        end

        local ok, decoded = pcall(json.decode, body)

        if not ok or type(decoded) ~= 'table' then
            debugPrint('resolver invalid json', body)

            cb(false, locale('resolver_failed'))
            return
        end

        local streamUrl = decoded.url or decoded.streamUrl or decoded.audioUrl

        if type(streamUrl) ~= 'string' or not streamUrl:match('^https?://') then
            cb(false, locale('resolver_failed'))
            return
        end

        local duration = tonumber(decoded.duration or decoded.lengthSeconds)

        if duration and Config.Resolver.maxDurationSeconds and duration > Config.Resolver.maxDurationSeconds then
            cb(false, locale('duration_blocked'))
            return
        end

        cb(true,
        {
            input = input,
            url = streamUrl,
            videoId = videoId,
            title = decoded.title or videoId,
            duration = duration
        })
    end, 'GET', '', musicboxHeaders())
end

local function takeItem(src, itemName)
    if not Config.Inventory.requireItem then
        return true
    end

    if GetResourceState('ox_inventory') ~= 'started' then
        return not Config.Inventory.removeOnPlace
    end

    local count = exports.ox_inventory:GetItemCount(src, itemName) or 0

    if count < 1 then
        return false
    end

    if Config.Inventory.removeOnPlace then
        return exports.ox_inventory:RemoveItem(src, itemName, 1)
    end
    return true
end

local function giveItem(src, itemName)
    if not Config.Inventory.returnOnPickup or not itemName then
        return true
    end

    if GetResourceState('ox_inventory') ~= 'started' then
        return true
    end
    return exports.ox_inventory:AddItem(src, itemName, 1)
end

local function ensureVehicleSource(src, payload)
    if not Config.Vehicle.enabled then
        return nil
    end

    local vehicleNetId = tonumber(payload.vehicleNetId)

    if not vehicleNetId then
        return nil
    end

    local key = tostring(vehicleNetId)
    local existingId = vehicleSources[key]

    if existingId and sources[existingId] then
        local existing = sources[existingId]

        if payload.coords then
            existing.coords = payload.coords
        end
        return existing
    end

    local sourceId = makeSourceId('vehicle')
    local sourceData =
    {
        id = sourceId,
        type = 'vehicle',
        owner = src,
        label = Config.Vehicle.label,
        vehicleNetId = vehicleNetId,
        mode = 'vehicle',
        coords = payload.coords,
        heading = payload.heading or 0.0,
        distance = Config.Vehicle.distance,
        volume = Config.Vehicle.volume,
        loop = false,
        paused = false,
        version = 0
    }

    sources[sourceId] = sourceData

    vehicleSources[key] = sourceId
    return sourceData
end

RegisterNetEvent('lv_musicbox:server:requestSync', function()
    syncSources(source)
end)

RegisterNetEvent('lv_musicbox:server:requestLibrary', function()
    sendLibrary(source)
end)

RegisterNetEvent('lv_musicbox:server:registerDevice', function(payload)
    local src = source

    if type(payload) ~= 'table' then
        return
    end

    local license = GetPlayerIdentifierByType(src, 'license')

    if blacklistedLicenses[license] then
        notify(src, 'Bạn đã bị đưa vào danh sách đen và không thể sử dụng Boombox', 'error')

        TriggerClientEvent('lv_musicbox:client:deleteNetEntity', src, payload.netId)
        return
    end

    local itemName = tostring(payload.item or '')
    local itemConfig = Config.BoomboxItems[itemName]

    if not itemConfig then
        notify(src, locale('invalid_item'), 'error')

        TriggerClientEvent('lv_musicbox:client:deleteNetEntity', src, payload.netId)
        return
    end

    if countOwnedSources(src) >= Config.MaxSourcesPerPlayer then
        notify(src, locale('source_limit'), 'error')

        TriggerClientEvent('lv_musicbox:client:deleteNetEntity', src, payload.netId)
        return
    end

    if not takeItem(src, itemName) then
        notify(src, locale('inventory_missing'), 'error')

        TriggerClientEvent('lv_musicbox:client:deleteNetEntity', src, payload.netId)
        return
    end

    local sourceType = itemConfig.type == 'stationary' and 'speaker' or 'boombox'
    local sourceId = makeSourceId(sourceType)

    sources[sourceId] =
    {
        id = sourceId,
        type = sourceType,
        owner = src,
        ownerIdentifier = GetPlayerIdentifierByType(src, 'license'),
        label = itemConfig.label,
        item = itemName,
        model = itemConfig.model,
        netId = tonumber(payload.netId),
        mode = 'placed',
        coords = payload.coords,
        heading = payload.heading or 0.0,
        distance = itemConfig.distance,
        volume = itemConfig.volume,
        loop = false,
        paused = false,
        version = 0
    }

    savePlacedSources()

    notify(src, locale('placed'), 'success')

    syncSources()
end)

RegisterNetEvent('lv_musicbox:server:play', function(payload)
    local src = source

    if type(payload) ~= 'table' then
        return
    end

    local requestId = tostring(payload.requestId or '')
    local function rejectPlay(message, notifyType, sourceId)
        notify(src, message, notifyType or 'error')

        sendPlayStatus(src, requestId, 'error', message, sourceId)
    end

    local nowMs = GetGameTimer()

    if lastRequestAt[src] and nowMs - lastRequestAt[src] < Config.RequestCooldownMs then
        rejectPlay(locale('cooldown'), 'error')
        return
    end

    lastRequestAt[src] = nowMs

    local sourceData = payload.sourceId and sources[tostring(payload.sourceId)] or nil

    if not sourceData and payload.targetType == 'vehicle' then
        sourceData = ensureVehicleSource(src, payload)
    end

    if not sourceData then
        rejectPlay(locale('no_source'), 'error')
        return
    end

    if not canControl(src, sourceData) then
        rejectPlay(locale('not_allowed'), 'error', sourceData.id)
        return
    end

    local requestedInput = trim(payload.input)
    local now = os.time()

    if sourceData.resolvingInput == requestedInput and now - (sourceData.resolveStartedAt or 0) < 45 then
        rejectPlay(locale('already_loading'), 'inform', sourceData.id)
        return
    end

    sendPlayStatus(src, requestId, 'loading', locale('loading_track'), sourceData.id)

    sourceData.resolveToken = (sourceData.resolveToken or 0) + 1
    sourceData.resolvingInput = requestedInput
    sourceData.resolveStartedAt = now

    local resolveToken = sourceData.resolveToken
    local sourceId = sourceData.id

    resolveTrack(src, requestedInput, function(ok, result)
        -- A different request may have been started while the HTTP resolver
        -- was still working. Never let the older response replace it.
        if sources[sourceId] ~= sourceData or sourceData.resolveToken ~= resolveToken then
            sendPlayStatus(src, requestId, 'error', locale('action_failed'), sourceId)
            return
        end

        sourceData.resolvingInput = nil
        sourceData.resolveStartedAt = nil

        if not ok then
            rejectPlay(result, 'error', sourceId)
            return
        end

        sourceData.url = result.url
        sourceData.input = result.input
        sourceData.videoId = result.videoId
        sourceData.title = result.title
        sourceData.duration = result.duration
        sourceData.volume = clamp(payload.volume or sourceData.volume, 0.0, 1.0)
        sourceData.loop = payload.loop == true
        sourceData.paused = false
        sourceData.pausedAt = 0
        sourceData.startedAt = os.time()

        if payload.coords then
            sourceData.coords = payload.coords
        end

        touchSource(sourceData)

        addRecent(src, result)

        savePlacedSources()

        syncSources()

        sendPlayStatus(src, requestId, 'resolved', locale('loading_audio'), sourceId)
    end)
end)

RegisterNetEvent('lv_musicbox:server:control', function(payload)
    local src = source

    if type(payload) ~= 'table' then
        return

    end

    local sourceData = sources[tostring(payload.sourceId or '')]

    if not sourceData then
        return

    end

    if not canControl(src, sourceData) then
        notify(src, locale('not_allowed'), 'error')
        return
    end

    local action = tostring(payload.action or '')

    if action == 'pause' then
        if sourceData.url and not sourceData.paused then
            sourceData.pausedAt = playbackPosition(sourceData)
            sourceData.paused = true

            touchSource(sourceData)
        end
    elseif action == 'resume' then
        if sourceData.url and sourceData.paused then
            sourceData.startedAt = os.time() - (sourceData.pausedAt or 0)
            sourceData.paused = false

            touchSource(sourceData)
        end
    elseif action == 'stop' then
        sourceData.url = nil
        sourceData.input = nil
        sourceData.videoId = nil
        sourceData.title = nil
        sourceData.duration = nil
        sourceData.paused = false
        sourceData.pausedAt = 0
        sourceData.startedAt = nil

        touchSource(sourceData)
    elseif action == 'volume' then
        sourceData.volume = clamp(payload.volume, 0.0, 1.0)

        touchSource(sourceData)
    elseif action == 'loop' then
        sourceData.loop = payload.loop == true

        touchSource(sourceData)
    elseif action == 'distance' then
        sourceData.distance = clamp(tonumber(payload.distance) or 25.0, 5.0, 150.0)

        touchSource(sourceData)
    elseif action == 'seek' then
        if sourceData.url then
            local targetTime = tonumber(payload.time)

            if not targetTime or targetTime ~= targetTime or targetTime == math.huge or targetTime == -math.huge then
                notify(src, locale('action_failed'), 'error')
                return
            end

            targetTime = math.max(0.0, targetTime)

            local duration = tonumber(sourceData.duration) or 0

            if duration > 0 then
                targetTime = math.min(targetTime, duration)
            end

            if sourceData.paused then
                sourceData.pausedAt = targetTime
            else
                sourceData.startedAt = os.time() - targetTime
            end

            touchSource(sourceData)
        end
    elseif action == 'next' or action == 'skip' then
        playNextInQueue(src, sourceData)
        return
    end

    savePlacedSources()

    syncSources()
end)

local function playNextInQueue(src, sourceData)
    sourceData.queue = sourceData.queue or {}

    if #sourceData.queue == 0 then
        sourceData.url = nil
        sourceData.input = nil
        sourceData.videoId = nil
        sourceData.title = nil
        sourceData.duration = nil
        sourceData.paused = true
        sourceData.pausedAt = 0
        sourceData.startedAt = nil

        touchSource(sourceData)
        savePlacedSources()
        syncSources()
        return
    end

    local nextTrack = table.remove(sourceData.queue, 1)
    local requestedInput = trim(nextTrack.input or nextTrack.videoId or '')

    if requestedInput == '' then
        playNextInQueue(src, sourceData)
        return
    end

    resolveTrack(src or 0, requestedInput, function(ok, result)
        if not ok or not result then
            playNextInQueue(src, sourceData)
            return
        end

        sourceData.url = result.url
        sourceData.input = result.input
        sourceData.videoId = result.videoId
        sourceData.title = result.title
        sourceData.duration = result.duration
        sourceData.paused = false
        sourceData.pausedAt = 0
        sourceData.startedAt = os.time()

        touchSource(sourceData)
        savePlacedSources()
        syncSources()
    end)
end

RegisterNetEvent('lv_musicbox:server:queueAction', function(payload)
    local src = source

    if type(payload) ~= 'table' then
        return
    end

    local sourceData = nil
    if payload.sourceId then
        local sId = payload.sourceId
        sourceData = sources[tostring(sId)] or sources[tonumber(sId)]
    end

    if not sourceData and payload.targetType == 'vehicle' then
        sourceData = ensureVehicleSource(src, payload)
    end

    if not sourceData then
        notify(src, locale('no_source'), 'error')
        return
    end

    if not canControl(src, sourceData) then
        notify(src, locale('not_allowed'), 'error')
        return
    end

    sourceData.queue = sourceData.queue or {}
    local action = tostring(payload.action or '')

    if action == 'add' then
        local input = trim(payload.input or '')
        if input == '' then return end

        resolveTrack(src, input, function(ok, result)
            if not ok or not result then
                notify(src, result or locale('action_failed'), 'error')
                return
            end

            table.insert(sourceData.queue, {
                input = result.input,
                videoId = result.videoId,
                title = result.title or result.input,
                duration = result.duration
            })

            notify(src, ('Đã thêm "%s" vào hàng đợi'):format(result.title or result.input), 'inform')

            if not sourceData.url or sourceData.url == '' then
                playNextInQueue(src, sourceData)
            else
                savePlacedSources()
                syncSources()
            end
        end)
    elseif action == 'remove' then
        local index = tonumber(payload.index)

        if index and sourceData.queue[index] then
            table.remove(sourceData.queue, index)
            notify(src, 'Đã xóa bài hát khỏi hàng đợi', 'inform')
            savePlacedSources()
            syncSources()
        end
    elseif action == 'clear' then
        sourceData.queue = {}
        notify(src, 'Đã xóa toàn bộ hàng đợi', 'inform')
        savePlacedSources()
        syncSources()
    elseif action == 'skip' then
        playNextInQueue(src, sourceData)
    end
end)

RegisterNetEvent('lv_musicbox:server:favorite', function(payload)
    local src = source

    if type(payload) ~= 'table' then
        return
    end

    local library = getLibrary(src)
    local action = tostring(payload.action or '')
    local track = payload.track

    if type(track) ~= 'table' or not track.input then
        notify(src, locale('invalid_input'), 'error')
        return
    end

    if action == 'add' then
        for _, favorite in ipairs(library.favorites) do
            if sameTrack(favorite, track) then
                sendLibrary(src)
                return
            end
        end

        table.insert(library.favorites, 1,
        {
            input = trim(track.input),
            videoId = track.videoId,
            title = track.title or track.input,
            addedAt = os.time()
        })

        trimList(library.favorites, Config.MaxFavorites)

        notify(src, locale('saved'), 'success')
    elseif action == 'remove' then
        for index = #library.favorites, 1, -1 do
            if sameTrack(library.favorites[index], track) then
                table.remove(library.favorites, index)
            end
        end

        notify(src, locale('removed'), 'success')
    end

    queueSave()

    sendLibrary(src)
end)

RegisterNetEvent('lv_musicbox:server:deviceAction', function(payload)
    local src = source

    if type(payload) ~= 'table' then
        return
    end

    local sourceData = sources[tostring(payload.sourceId or '')]

    if not sourceData or sourceData.type == 'vehicle' then
        return
    end

    if not canControl(src, sourceData) then
        notify(src, locale('not_allowed'), 'error')
        return
    end

    local action = tostring(payload.action or '')

    if action == 'carry' or action == 'back' then
        sourceData.holder = src
        sourceData.mode = action
    elseif action == 'drop' then
        sourceData.holder = nil
        sourceData.mode = 'placed'
        sourceData.coords = payload.coords or sourceData.coords
        sourceData.heading = payload.heading or sourceData.heading
    else
        return
    end

    touchSource(sourceData)

    savePlacedSources()

    syncSources()
end)

RegisterNetEvent('lv_musicbox:server:pickup', function(payload)
    local src = source
    
    if type(payload) ~= 'table' then
        return
    end

    local sourceId = tostring(payload.sourceId or '')
    local sourceData = sources[sourceId]

    if not sourceData or sourceData.type == 'vehicle' then
        return
    end

    if not canControl(src, sourceData) then
        notify(src, locale('not_allowed'), 'error')
        return
    end

    if not giveItem(src, sourceData.item) then
        notify(src, locale('action_failed'), 'error')
        return
    end

    local netId = sourceData.netId
    
    if netId then
        local entity = NetworkGetEntityFromNetworkId(netId)

        if entity and entity ~= 0 and DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
    end

    sources[sourceId] = nil

    savePlacedSources()

    notify(src, locale('picked_up'), 'success')

    syncSources()

    TriggerClientEvent('lv_musicbox:client:deleteNetEntity', -1, netId)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local license = GetPlayerIdentifierByType(src, 'license')
    local changed = false

    for sourceId, sourceData in pairs(sources) do
        if sourceData.ownerIdentifier == license or sourceData.holder == src then
            if sourceData.type ~= 'vehicle' then
                giveItem(src, sourceData.item)
                
                local netId = sourceData.netId

                if netId then
                    local entity = NetworkGetEntityFromNetworkId(netId)

                    if entity and entity ~= 0 and DoesEntityExist(entity) then
                        DeleteEntity(entity)
                    end

                    TriggerClientEvent('lv_musicbox:client:deleteNetEntity', -1, netId)
                end
                
                sources[sourceId] = nil

                changed = true

            elseif sourceData.holder == src then
                sourceData.holder = nil
                sourceData.mode = 'placed'

                touchSource(sourceData)

                changed = true
            end
        end
    end

    if changed then
        savePlacedSources()

        syncSources()
    end
    
    lastRequestAt[src] = nil
end)

AddEventHandler('onResourceStart', function(startedResource)
    if startedResource ~= resourceName then
        return
    end

    loadLibraries()
    loadPlacedSources()
    loadBlacklist()

    debugPrint('loaded libraries, placed sources and blacklist')
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    if stoppedResource ~= resourceName then
        return
    end
    
    for sourceId, sourceData in pairs(sources) do
        if sourceData.type ~= 'vehicle' then
            if sourceData.owner then
                local ping = GetPlayerPing(sourceData.owner)

                if ping and tonumber(ping) > 0 then
                    giveItem(sourceData.owner, sourceData.item)

                    TriggerClientEvent('ox_lib:notify', sourceData.owner,
                    {
                        type = 'info',
                        description = 'Loa của bạn đã được tự động cất vào túi đồ'
                    })

                    sources[sourceId] = nil
                end
            end

            if sourceData.netId then
                local entity = NetworkGetEntityFromNetworkId(sourceData.netId)

                if entity and entity ~= 0 and DoesEntityExist(entity) then
                    DeleteEntity(entity)
                end
            end
        end
    end

    savePlacedSources()

    saveLibraries()
end)

exports('GetSources', function()
    return sources
end)

CreateThread(function()
    while true do
        Wait(5000)

        local changed = false

        for sourceId, sourceData in pairs(sources) do
            if sourceData.type ~= 'vehicle' and sourceData.mode == 'placed' and sourceData.netId then
                local entity = NetworkGetEntityFromNetworkId(sourceData.netId)

                if not entity or entity == 0 or not DoesEntityExist(entity) then
                    local modelHash = type(sourceData.model) == 'string' and GetHashKey(sourceData.model) or sourceData.model
                    local newEntity = CreateObjectNoOffset(modelHash, sourceData.coords.x, sourceData.coords.y, sourceData.coords.z, true, true, false)
                    
                    local timeout = 50

                    while not DoesEntityExist(newEntity) and timeout > 0 do
                        Wait(10)

                        timeout = timeout - 1
                    end

                    if DoesEntityExist(newEntity) then
                        SetEntityHeading(newEntity, sourceData.heading or 0.0)

                        local newNetId = NetworkGetNetworkIdFromEntity(newEntity)

                        sourceData.netId = newNetId

                        changed = true

                        debugPrint(('Recreated entity for source %s server-side because it was deleted.'):format(sourceId))
                    end
                end
            end
        end

        if changed then
            syncSources()

            savePlacedSources()
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)

        for _, sourceData in pairs(sources) do
            local duration = tonumber(sourceData.duration) or 0

            if sourceData.url and duration > 0 and not sourceData.loop and not sourceData.paused then
                if playbackPosition(sourceData) >= duration then
                    if sourceData.queue and #sourceData.queue > 0 then
                        playNextInQueue(0, sourceData)
                    else
                        sourceData.paused = true
                        sourceData.pausedAt = duration
                        sourceData.startedAt = nil

                        touchSource(sourceData)
                        savePlacedSources()
                        syncSources()
                    end
                end
            end
        end
    end
end)

RegisterNetEvent('lv_musicbox:server:adminPickup', function(sourceId)
    local src = source

    sourceId = tostring(sourceId or '')

    local sourceData = sources[sourceId]

    if not sourceData or sourceData.type == 'vehicle' then
        return
    end

    if not isAdmin(src) then
        notify(src, locale('not_allowed'), 'error')
        return
    end

    local ownerLicense = sourceData.ownerIdentifier
    local ESX = exports['es_extended']:getSharedObject()
    local xPlayers = ESX.GetExtendedPlayers()
    local ownerPlayer = nil
    
    for _, xPlayer in ipairs(xPlayers) do
        if xPlayer.identifier == ownerLicense then
            ownerPlayer = xPlayer
            break
        end
    end

    local netId = sourceData.netId

    if netId then
        local entity = NetworkGetEntityFromNetworkId(netId)

        if entity and entity ~= 0 and DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
    end
    
    sources[sourceId] = nil
    
    savePlacedSources()
    
    syncSources()

    TriggerClientEvent('lv_musicbox:client:deleteNetEntity', -1, netId)

    if ownerPlayer then
        if giveItem(ownerPlayer.source, sourceData.item) then
            notify(ownerPlayer.source, ('Loa %s của bạn đã được Admin thu hồi về túi đồ'):format(sourceData.label), 'success')
            notify(src, ('Đã thu hồi loa và trả về túi đồ của chủ sở hữu %s'):format(ownerPlayer.name), 'success')
        else
            notify(src, 'Không thể gửi vật phẩm vào túi đồ chủ sở hữu (Túi đồ đầy?) và loa đã bị xóa', 'warning')
        end
    else
        notify(src, 'Chủ sở hữu hiện tại không trực tuyến. Đã xóa loa này khỏi bản đồ', 'success')
    end
end)

RegisterNetEvent('lv_musicbox:server:adminDeleteOrphanObject', function(netId)
    local src = source
    local ESX = exports['es_extended']:getSharedObject()
    local xPlayer = ESX.GetPlayerFromId(src)
    local group = xPlayer and xPlayer.getGroup()
    local isAdmin = group == 'admin' or group == 'superadmin' or group == 'god' or group == 'helper'

    if not isAdmin then
        notify(src, locale('not_allowed'), 'error')
        return
    end

    local entity = NetworkGetEntityFromNetworkId(netId)

    if entity and entity ~= 0 and DoesEntityExist(entity) then
        DeleteEntity(entity)
        
        notify(src, 'Đã xóa loa không chủ sở hữu thành công', 'success')
    else
        notify(src, 'Không tìm thấy loa hợp lệ', 'error')
    end
end)

local BlacklistFile = 'data/blacklist.json'

blacklistedLicenses = {} -- Định nghĩa global hoặc local

function loadBlacklist()
    local content = LoadResourceFile(resourceName, BlacklistFile)

    if content then
        local ok, decoded = pcall(json.decode, content)

        if ok and type(decoded) == 'table' then
            blacklistedLicenses = decoded
        end
    else
        blacklistedLicenses = {}
    end
end

function saveBlacklist()
    SaveResourceFile(resourceName, BlacklistFile, json.encode(blacklistedLicenses, { indent = true }), -1)
end

local function countKeys(tbl)
    local count = 0

    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function isAdmin(src)
    if src == 0 then
        return true
    end -- Console là admin

    local ESX = exports['es_extended']:getSharedObject()
    local xPlayer = ESX.GetPlayerFromId(src)
    local group = xPlayer and xPlayer.getGroup()
    return group == 'admin' or group == 'superadmin' or group == 'god' or group == 'helper'
end

cdnFiles = {}

local function fetchCdnFiles()
    local endpoint = Config.Resolver.endpoint
    local listUrl = endpoint:gsub('/resolve/.*', '/list'):gsub('/resolve.*', '/list')

    if not listUrl:find('/list') then
        listUrl = 'https://cdn.lslegacy.net/musicbox/list'
    end

    PerformHttpRequest(listUrl, function(statusCode, body)
        local code = tonumber(statusCode) or 0

        if code == 200 and body then
            local ok, decoded = pcall(json.decode, body)

            if ok and decoded and type(decoded.files) == 'table' then
                local filtered = {}
                local seen = {}

                for _, file in ipairs(decoded.files) do
                    local filename = type(file) == 'table' and tostring(file.filename or '') or ''
                    local key = filename:lower()

                    if (key:match('%.mp3$') or key:match('%.webm$') or key:match('%.m4a$') or key:match('%.ogg$') or key:match('%.wav$') or key:match('%.opus$')) and not seen[key] then
                        local isAvailable = true
                        if type(file) == 'table' then
                            if file.available == false then
                                isAvailable = false
                            end

                            local dur = tonumber(file.duration) or 0
                            if file.duration ~= nil and dur == 0 then
                                isAvailable = false
                            end

                            if file.size ~= nil then
                                local fileSize = tonumber(file.size) or 0
                                if fileSize > 0 and fileSize < 5000 then
                                    isAvailable = false
                                end
                            end
                        end

                        if isAvailable then
                            seen[key] = true

                            filtered[#filtered + 1] = file
                        end
                    end
                end

                table.sort(filtered, function(a, b)
                    return tostring(a.title or a.filename) < tostring(b.title or b.filename)
                end)

                cdnFiles = filtered

                debugPrint('Loaded ' .. #cdnFiles .. ' files from CDN')
            end
        else
            debugPrint('Failed to load CDN files', statusCode)
        end
    end, 'GET', '', musicboxHeaders())
end

CreateThread(function()
    while true do
        fetchCdnFiles()

        Wait(60000) -- Cập nhật danh sách mỗi 60 giây
    end
end)


RegisterCommand('deleteboombox', function(src, args)
    if not isAdmin(src) then
        notify(src, locale('not_allowed'), 'error')
        return
    end

    TriggerClientEvent('lv_musicbox:client:adminPickup', src)
end, false)

RegisterCommand('takeboombox', function(src, args)
    if not isAdmin(src) then
        notify(src, locale('not_allowed'), 'error')
        return
    end

    local target = tonumber(args[1])

    if not target or not GetPlayerName(target) then
        TriggerServerEvent('custom-chat:addMessage', src, "{FF6347}Sử Dụng:{FFFFFF} /takeboombox [Player]")
        return
    end

    if GetResourceState('ox_inventory') ~= 'started' then
        notify(src, 'ox_inventory chưa được khởi động', 'error')
        return
    end

    local removed = 0

    for itemName, itemConfig in pairs(Config.BoomboxItems) do
        if itemConfig.type == 'portable' then
            local count = exports.ox_inventory:GetItemCount(target, itemName) or 0

            if count > 0 and exports.ox_inventory:RemoveItem(target, itemName, count) then
                removed = removed + count
            end
        end
    end

    if removed == 0 then
        notify(src, ('%s không có Boombox trong túi đồ'):format(GetPlayerName(target)), 'inform')
        return
    end

    notify(src, ('Đã tịch thu %d Boombox từ %s'):format(removed, GetPlayerName(target)), 'success')
    notify(target, ('Admin đã tịch thu %d Boombox trong túi đồ của bạn'):format(removed), 'error')
end, false)
