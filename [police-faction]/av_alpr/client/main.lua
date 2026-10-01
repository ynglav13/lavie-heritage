local display = false
local isPaused = false
local frontLocked = false
local frontPlate = nil
local frontData = {}

local radarPower = false
local radarMode = "moving"
local speedLimit = Config.SpeedLimit or 50
local menuOpen = false
local remoteOpen = false
local radarDisplay = false
local radarPaused = false
local pauseMenuOpened = false
local radarVehicleStates = {}
local currentRadarVehicleKey = nil
local radarTargetVehicle = nil
local radarTargetRefreshAt = 0
local cachedFrontRadarVehicle = nil
local cachedRearRadarVehicle = nil
local lastRadarPayloadKey = nil
local npcVehicleCache = {}
local npcVehicleCacheCleanupAt = 0
local lastOwnerLookupAt = -1000
local ownerLookupGeneration = 0

local frontRadar = {
    xmit = true,
    same = true,
    opp = true,
    target = -1,
    fast = -1,
    lock = -1,
    dir = "none"
}

local rearRadar = {
    xmit = true,
    same = true,
    opp = true,
    target = -1,
    fast = -1,
    lock = -1,
    dir = "none"
}

local function CopyTable(data)
    local copy = {}
    for key, value in pairs(data or {}) do
        if type(value) == "table" then
            copy[key] = CopyTable(value)
        else
            copy[key] = value
        end
    end
    return copy
end

local function NormalizePlate(plate)
    return tostring(plate or ""):gsub("%s+", ""):upper()
end

local function NormalizePlateIndex(index)
    index = tonumber(index)
    if not index then return Config.DefaultPlateIndex or 0 end

    index = math.floor(index)
    if Config.ValidPlateIndices and Config.ValidPlateIndices[index] then
        return index
    end

    return Config.DefaultPlateIndex or 0
end

local function GetRadarVehicleKey(vehicle)
    if not DoesEntityExist(vehicle) then return nil end

    if NetworkGetEntityIsNetworked(vehicle) then
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        if netId and netId > 0 then
            return ("net:%s"):format(netId)
        end
    end

    local plate = (GetVehicleNumberPlateText(vehicle) or ""):gsub("%s+", "")
    local model = GetEntityModel(vehicle)
    return ("local:%s:%s"):format(model, plate)
end

local function SetRadarVehicleState(vehicleKey, state)
    radarVehicleStates[vehicleKey] = state

    local maxEntries = Config.RadarStateMaxEntries or 32
    local count = 0
    for _ in pairs(radarVehicleStates) do
        count = count + 1
    end

    if count <= maxEntries then return end

    for key in pairs(radarVehicleStates) do
        if key ~= currentRadarVehicleKey and key ~= vehicleKey then
            radarVehicleStates[key] = nil
            count = count - 1
            if count <= maxEntries then break end
        end
    end
end

local function SaveRadarVehicleState(vehicle)
    local vehicleKey = GetRadarVehicleKey(vehicle)
    if not vehicleKey then return end

    SetRadarVehicleState(vehicleKey, {
        radarPower = radarPower,
        radarMode = radarMode,
        speedLimit = speedLimit,
        menuOpen = menuOpen,
        radarDisplay = radarDisplay,
        display = display,
        frontLocked = frontLocked,
        frontPlate = frontPlate,
        frontData = CopyTable(frontData),
        frontRadar = CopyTable(frontRadar),
        rearRadar = CopyTable(rearRadar)
    })
end

local function SaveCurrentRadarVehicleState()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        SaveRadarVehicleState(vehicle)
    elseif currentRadarVehicleKey then
        SetRadarVehicleState(currentRadarVehicleKey, {
            radarPower = radarPower,
            radarMode = radarMode,
            speedLimit = speedLimit,
            menuOpen = menuOpen,
            radarDisplay = radarDisplay,
            display = display,
            frontLocked = frontLocked,
            frontPlate = frontPlate,
            frontData = CopyTable(frontData),
            frontRadar = CopyTable(frontRadar),
            rearRadar = CopyTable(rearRadar)
        })
    end
end

local function LoadRadarVehicleState(vehicle)
    local vehicleKey = GetRadarVehicleKey(vehicle)
    if not vehicleKey then return false end

    if currentRadarVehicleKey ~= vehicleKey then
        if currentRadarVehicleKey then
            SetRadarVehicleState(currentRadarVehicleKey, {
                radarPower = radarPower,
                radarMode = radarMode,
                speedLimit = speedLimit,
                menuOpen = menuOpen,
                radarDisplay = radarDisplay,
                display = display,
                frontLocked = frontLocked,
                frontPlate = frontPlate,
                frontData = CopyTable(frontData),
                frontRadar = CopyTable(frontRadar),
                rearRadar = CopyTable(rearRadar)
            })
        end
        currentRadarVehicleKey = vehicleKey
        radarTargetVehicle = nil
        radarTargetRefreshAt = 0
        cachedFrontRadarVehicle = nil
        cachedRearRadarVehicle = nil
        lastRadarPayloadKey = nil
    end

    local state = radarVehicleStates[vehicleKey]
    if not state then return false end

    radarPower = state.radarPower
    radarMode = state.radarMode or "moving"
    speedLimit = state.speedLimit or Config.SpeedLimit or 50
    menuOpen = state.menuOpen or false
    radarDisplay = state.radarDisplay or false
    display = state.display or false
    frontLocked = state.frontLocked or false
    frontPlate = state.frontPlate
    frontData = CopyTable(state.frontData or {})
    frontRadar = CopyTable(state.frontRadar or frontRadar)
    rearRadar = CopyTable(state.rearRadar or rearRadar)

    return true
end

local function ToggleUI()
    display = not display
    SendNUIMessage({
        type = "ui",
        display = display
    })
    if not display then
        frontLocked = false
        SendNUIMessage({type = "unlock"})
    end
end

local function LockFrontPlate()
    if frontLocked then return end

    frontLocked = true
    SendNUIMessage({
        type = "lock",
        data = frontData
    })
    if frontData.plate then
        TriggerServerEvent('av_alpr:saveLog', frontData)
    end
    SaveCurrentRadarVehicleState()
end

RegisterCommand(Config.Command, function()
    if IsPauseMenuActive() then return end
    if LocalPlayer.state.factionCategory ~= 'police' then
        exports['lv_notify']:Notify({
            type = 'error',
            title = 'Radar',
            message = 'Bạn không phải cảnh sát',
            duration = 4500
        })
        return
    end
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return end
    
    local vehicle = GetVehiclePedIsIn(ped, false)
    if GetVehicleClass(vehicle) ~= 18 then
        exports['lv_notify']:Notify({
            type = 'error',
            title = 'Radar',
            message = 'Xe này không được trang bị hệ thống Radar/ALPR',
            duration = 4500
        })
        return
    end

    LoadRadarVehicleState(vehicle)
    
    remoteOpen = not remoteOpen
    radarDisplay = true
    display = true
    radarPaused = false
    isPaused = false
    
    SetNuiFocus(remoteOpen, remoteOpen)
    SendNUIMessage({
        type = "ui",
        display = display
    })
    SendNUIMessage({
        type = "radar_ui",
        display = radarDisplay
    })
    SendNUIMessage({
        type = "remote_ui",
        display = remoteOpen
    })
    SaveCurrentRadarVehicleState()
end)
RegisterKeyMapping(Config.Command, 'Toggle Radar Remote', 'keyboard', Config.Keys.Toggle)

RegisterCommand('vradar_lock', function()
    if IsPauseMenuActive() or not display then return end
    LockFrontPlate()
end)
RegisterKeyMapping('vradar_lock', 'Lock ALPR Plate', 'keyboard', Config.Keys.LockPlate)

RegisterCommand('vradar_unlock', function()
    if IsPauseMenuActive() or not display then return end
    frontLocked = false
    frontRadar.lock = -1
    rearRadar.lock = -1
    SendNUIMessage({type = "unlock"})
    SaveCurrentRadarVehicleState()
end)
local function ResetALPRUI()
    remoteOpen = false
    radarDisplay = false
    display = false
    isPaused = false
    radarPaused = false
    frontLocked = false
    frontPlate = nil
    frontData = {}
    currentRadarVehicleKey = nil

    SetNuiFocus(false, false)

    SendNUIMessage({ type = "resetPosition" })
    SendNUIMessage({ type = "ui", display = false })
    SendNUIMessage({ type = "radar_ui", display = false })
    SendNUIMessage({ type = "remote_ui", display = false })
    SendNUIMessage({ type = "clearLog" })
    SendNUIMessage({ type = "unlock" })

    exports['lv_notify']:Notify({
        type = 'success',
        title = 'Radar / ALPR',
        message = 'Đã khôi phục vị trí mặc định toàn bộ giao diện Radar & ALPR!',
        duration = 3500
    })
end

RegisterCommand('resetalpr', function()
    ResetALPRUI()
end, false)

RegisterCommand('vradar_reset', function()
    ResetALPRUI()
end, false)

RegisterNUICallback('remote_click', function(data, cb)
    local btn = data.button
    if btn == "close" then
        remoteOpen = false
        SaveCurrentRadarVehicleState()
        SetNuiFocus(false, false)
        SendNUIMessage({
            type = "remote_ui",
            display = false
        })
        PlaySoundFrontend(-1, "NAV_UP_DOWN", "HUD_FRONTEND_DEFAULT_SOUNDSET", 1)
        cb('ok')
        return
    elseif btn == "reset_ui" or btn == "reset" then
        ResetALPRUI()
        PlaySoundFrontend(-1, "NAV_UP_DOWN", "HUD_FRONTEND_DEFAULT_SOUNDSET", 1)
        cb('ok')
        return
    elseif btn == "toggle_alpr" then
        display = not display
        SendNUIMessage({
            type = "ui",
            display = display
        })
        if not display then
            frontLocked = false
            SendNUIMessage({type = "unlock"})
        end
        SaveCurrentRadarVehicleState()
        PlaySoundFrontend(-1, "NAV_UP_DOWN", "HUD_FRONTEND_DEFAULT_SOUNDSET", 1)
        cb('ok')
        return
    elseif btn == "toggle_radar" then
        radarDisplay = not radarDisplay
        radarPaused = false
        lastRadarPayloadKey = nil
        SendNUIMessage({
            type = "radar_ui",
            display = radarDisplay
        })
        SaveCurrentRadarVehicleState()
        PlaySoundFrontend(-1, "NAV_UP_DOWN", "HUD_FRONTEND_DEFAULT_SOUNDSET", 1)
        cb('ok')
        return
    end

    PlaySoundFrontend(-1, "NAV_UP_DOWN", "HUD_FRONTEND_DEFAULT_SOUNDSET", 1)

    if btn == "power" then
        radarPower = not radarPower
        if not radarPower then
            menuOpen = false
        end
    elseif radarPower then
        if btn == "menu" then
            menuOpen = not menuOpen
        elseif btn == "front_xmit" then
            frontRadar.xmit = not frontRadar.xmit
        elseif btn == "front_opp" then
            if menuOpen then
                speedLimit = math.max(10, speedLimit - 5)
            else
                frontRadar.opp = not frontRadar.opp
                if frontRadar.lock ~= -1 then
                    frontRadar.lock = -1
                    frontLocked = false
                    SendNUIMessage({type = "unlock"})
                end
            end
        elseif btn == "front_same" then
            if menuOpen then
                speedLimit = math.min(150, speedLimit + 5)
            else
                frontRadar.same = not frontRadar.same
                if frontRadar.lock ~= -1 then
                    frontRadar.lock = -1
                    frontLocked = false
                    SendNUIMessage({type = "unlock"})
                end
            end
        elseif btn == "rear_xmit" then
            rearRadar.xmit = not rearRadar.xmit
        elseif btn == "rear_opp" then
            rearRadar.opp = not rearRadar.opp
            if rearRadar.lock ~= -1 then
                rearRadar.lock = -1
                frontLocked = false
                SendNUIMessage({type = "unlock"})
            end
        elseif btn == "rear_same" then
            rearRadar.same = not rearRadar.same
            if rearRadar.lock ~= -1 then
                rearRadar.lock = -1
                frontLocked = false
                SendNUIMessage({type = "unlock"})
            end
        elseif btn == "blank" then
            frontRadar.lock = -1
            rearRadar.lock = -1
            frontLocked = false
            SendNUIMessage({type = "unlock"})
        end
    end
    radarTargetRefreshAt = 0
    lastRadarPayloadKey = nil
    SaveCurrentRadarVehicleState()
    cb('ok')
end)

RegisterCommand('alpr_ui', function()
    if IsPauseMenuActive() then return end
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return end
    if display then
        SetNuiFocus(true, true)
        SendNUIMessage({type = "enterEditMode"})
    else
        TriggerEvent('chat:addMessage', { args = { '^1ALPR ', 'Bạn phải bật ALPR trước' } })
    end
end)

RegisterNUICallback('closeEditMode', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)


local function ComputeIsNPCVehicle(targetVeh)
    if not targetVeh or targetVeh == 0 or not DoesEntityExist(targetVeh) then return true end

    local maxSeats = GetVehicleMaxNumberOfPassengers(targetVeh)
    for seat = -1, maxSeats - 1 do
        local ped = GetPedInVehicleSeat(targetVeh, seat)
        if ped ~= 0 and DoesEntityExist(ped) and IsPedAPlayer(ped) then
            return false
        end
    end

    local driver = GetPedInVehicleSeat(targetVeh, -1)
    if driver ~= 0 and DoesEntityExist(driver) and not IsPedAPlayer(driver) then
        return true
    end

    local state = Entity(targetVeh).state
    if state and (
        state.isPlayerVehicle or state.PlayerVehicle or state.vehiclePersistIgnore or
        state[Config.FactionVehicleStateKey or 'FactionVehicle'] or
        state.owner or state.ownerName or state.citizenid or state.identifier
    ) then
        return false
    end

    local popType = GetEntityPopulationType(targetVeh)
    if popType == 2 or popType == 3 or popType == 4 then
        return true
    end

    return true
end

local function isNPCVehicle(targetVeh)
    if not targetVeh or targetVeh == 0 or not DoesEntityExist(targetVeh) then return true end

    local now = GetGameTimer()
    local cached = npcVehicleCache[targetVeh]
    if cached and cached.expiresAt > now then
        return cached.value
    end

    local value = ComputeIsNPCVehicle(targetVeh)
    npcVehicleCache[targetVeh] = {
        value = value,
        expiresAt = now + (Config.NPCVehicleCacheTTL or 1000)
    }

    if now >= npcVehicleCacheCleanupAt then
        npcVehicleCacheCleanupAt = now + 10000
        for vehicle, entry in pairs(npcVehicleCache) do
            if entry.expiresAt <= now or not DoesEntityExist(vehicle) then
                npcVehicleCache[vehicle] = nil
            end
        end
    end

    return value
end

local function GetVehicleInDirection(entFrom, coordFrom, coordTo)
	local rayHandle = StartShapeTestCapsule(coordFrom.x, coordFrom.y, coordFrom.z, coordTo.x, coordTo.y, coordTo.z, 6.0, 10, entFrom, 7)
	local _, _, _, _, vehicle = GetShapeTestResult(rayHandle)
	return vehicle
end

local function GetEntityRelativeDirection(myAng, tarAng)
	local angleDiff = math.abs((myAng - tarAng + 180) % 360 - 180)
	if (angleDiff < 45) then return 1 elseif (angleDiff > 135) then return 2 end
	return 0
end

local function GetFactionVehicleTag(vehicle)
    if not DoesEntityExist(vehicle) then return nil end

    local state = Entity(vehicle).state
    local value = state and state[Config.FactionVehicleStateKey or 'FactionVehicle']
    if not value then return nil end

    if type(value) == 'string' then
        value = value:match('^%s*(.-)%s*$'):upper()
        return value ~= '' and value or 'FACTION'
    end

    return 'FACTION'
end

local function BuildVehicleScanData(targetVeh)
    if not DoesEntityExist(targetVeh) then return nil end

    local plate = GetVehicleNumberPlateText(targetVeh) or ''
    local modelLabel = GetDisplayNameFromVehicleModel(GetEntityModel(targetVeh))
    local model = GetLabelText(modelLabel)
    if model == "NULL" then model = modelLabel end

    local color = GetVehicleColours(targetVeh)
    local factionTag = GetFactionVehicleTag(targetVeh)
    local netId = NetworkGetEntityIsNetworked(targetVeh) and NetworkGetNetworkIdFromEntity(targetVeh) or 0

    return {
        plate = plate,
        plateKey = NormalizePlate(plate),
        model = model,
        color = GetColorName(color),
        plateIndex = NormalizePlateIndex(GetVehicleNumberPlateTextIndex(targetVeh)),
        owner = factionTag and ('Faction Vehicle - %s'):format(factionTag) or "Scanning...",
        photo = nil,
        flags = {},
        factionTag = factionTag,
        targetNetId = netId > 0 and netId or 0
    }
end

local function RequestOwnerProfile(data)
    ownerLookupGeneration = ownerLookupGeneration + 1
    local generation = ownerLookupGeneration
    local minInterval = (Config.ServerLookupMinInterval or 200) + 25
    local delay = math.max(0, minInterval - (GetGameTimer() - lastOwnerLookupAt))

    local function sendRequest()
        if generation ~= ownerLookupGeneration then return end
        if data.factionTag or NormalizePlate(frontData.plate) ~= data.plateKey then return end

        lastOwnerLookupAt = GetGameTimer()
        TriggerServerEvent('av_alpr:checkOwner', data.plate, 'front', data.targetNetId)
    end

    if delay == 0 then
        sendRequest()
    else
        CreateThread(function()
            Wait(delay)
            sendRequest()
        end)
    end
end

local function UpdateFrontVehicleScan(targetVeh, lockAfterUpdate)
    local data = BuildVehicleScanData(targetVeh)
    if not data or data.plateKey == '' then return false end

    local currentKey = NormalizePlate(frontData.plate)
    local currentFaction = frontData.factionTag or ''
    if data.plateKey == currentKey and (data.factionTag or '') == currentFaction then
        if lockAfterUpdate and not frontLocked then
            LockFrontPlate()
        end
        return false
    end

    frontPlate = data.plate
    frontData = data

    if not data.factionTag then
        RequestOwnerProfile(data)
    else
        ownerLookupGeneration = ownerLookupGeneration + 1
    end

    SendNUIMessage({
        type = "update",
        data = frontData
    })

    if lockAfterUpdate then
        LockFrontPlate()
    end

    return true
end

local function FindRadarTargets(vehicle, coords)
    local closestFrontVeh, closestFrontDist = nil, Config.RadarScanDistance
    local closestRearVeh, closestRearDist = nil, Config.RadarScanDistance
    local vehiclesList = GetGamePool('CVehicle')

    for _, targetVeh in ipairs(vehiclesList) do
        if targetVeh ~= vehicle and not isNPCVehicle(targetVeh) then
            local vehicleClass = GetVehicleClass(targetVeh)
            if vehicleClass ~= 14 and vehicleClass ~= 15 and vehicleClass ~= 16 and vehicleClass ~= 21 then
                local targetCoords = GetEntityCoords(targetVeh)
                local distance = #(coords - targetCoords)

                if distance < Config.RadarScanDistance then
                    local relativeCoords = GetOffsetFromEntityGivenWorldCoords(vehicle, targetCoords)
                    if math.abs(relativeCoords.z) <= 3.5 and math.abs(relativeCoords.x) <= 6.5 then
                        local direction = GetEntityRelativeDirection(GetEntityHeading(vehicle), GetEntityHeading(targetVeh))

                        if relativeCoords.y > 0 and frontRadar.xmit then
                            local valid = (direction == 1 and frontRadar.same) or (direction == 2 and frontRadar.opp)
                            if valid and distance < closestFrontDist then
                                closestFrontDist = distance
                                closestFrontVeh = targetVeh
                            end
                        elseif relativeCoords.y <= 0 and rearRadar.xmit then
                            local valid = (direction == 1 and rearRadar.same) or (direction == 2 and rearRadar.opp)
                            if valid and distance < closestRearDist then
                                closestRearDist = distance
                                closestRearVeh = targetVeh
                            end
                        end
                    end
                end
            end
        end
    end

    return closestFrontVeh, closestRearVeh
end

local function RoundRadarValue(value)
    if value == nil or value == -1 then return -1 end
    return math.floor(value + 0.5)
end

local function SendRadarUpdateIfChanged(patrolSpeed)
    local data = {
        power = radarPower,
        patrolSpeed = RoundRadarValue(patrolSpeed),
        frontTarget = RoundRadarValue(frontRadar.target),
        frontFast = menuOpen and speedLimit or -1,
        frontLock = RoundRadarValue(frontRadar.lock),
        rearTarget = RoundRadarValue(rearRadar.target),
        rearFast = menuOpen and speedLimit or -1,
        rearLock = RoundRadarValue(rearRadar.lock),
        frontSame = frontRadar.same,
        frontOpp = frontRadar.opp,
        frontXmit = frontRadar.xmit,
        frontDir = frontRadar.dir,
        rearSame = rearRadar.same,
        rearOpp = rearRadar.opp,
        rearXmit = rearRadar.xmit,
        rearDir = rearRadar.dir
    }

    local payloadKey = table.concat({
        tostring(data.power), data.patrolSpeed,
        data.frontTarget, data.frontFast, data.frontLock,
        data.rearTarget, data.rearFast, data.rearLock,
        tostring(data.frontSame), tostring(data.frontOpp), tostring(data.frontXmit), data.frontDir,
        tostring(data.rearSame), tostring(data.rearOpp), tostring(data.rearXmit), data.rearDir
    }, '|')

    if payloadKey == lastRadarPayloadKey then return end
    lastRadarPayloadKey = payloadKey

    SendNUIMessage({
        type = "radar_update",
        data = data
    })
end

local function LockSpeederPlate(targetVeh, speed)
    if not DoesEntityExist(targetVeh) then return end
    UpdateFrontVehicleScan(targetVeh, true)
end

CreateThread(function()
    while true do
        local sleep = 1000
        if radarDisplay then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            
            if vehicle ~= 0 and GetVehicleClass(vehicle) == 18 and LocalPlayer.state.factionCategory == 'police' and GetPedInVehicleSeat(vehicle, -1) == ped then
                local vehicleKey = GetRadarVehicleKey(vehicle)
                if vehicleKey and currentRadarVehicleKey ~= vehicleKey then
                    LoadRadarVehicleState(vehicle)
                end
                if radarPaused then
                    radarPaused = false
                    if not IsPauseMenuActive() then
                        SendNUIMessage({ type = "radar_ui", display = true })
                    end
                end
                sleep = Config.RadarUIInterval or 250
                
                local coords = GetEntityCoords(vehicle)
                local patrolSpeed = GetEntitySpeed(vehicle) * 2.236936
                local closestFrontVeh = nil
                local closestRearVeh = nil
                
                if radarPower then
                    local now = GetGameTimer()
                    if radarTargetVehicle ~= vehicle or now >= radarTargetRefreshAt then
                        radarTargetVehicle = vehicle
                        radarTargetRefreshAt = now + (Config.RadarTargetScanInterval or 400)
                        cachedFrontRadarVehicle, cachedRearRadarVehicle = FindRadarTargets(vehicle, coords)
                    end

                    if cachedFrontRadarVehicle and DoesEntityExist(cachedFrontRadarVehicle) then
                        closestFrontVeh = cachedFrontRadarVehicle
                    end
                    if cachedRearRadarVehicle and DoesEntityExist(cachedRearRadarVehicle) then
                        closestRearVeh = cachedRearRadarVehicle
                    end

                    if closestFrontVeh then
                        local vehSpeed = GetEntitySpeed(closestFrontVeh) * 2.236936
                        local myH = GetEntityHeading(vehicle)
                        local tarH = GetEntityHeading(closestFrontVeh)
                        local dir = GetEntityRelativeDirection(myH, tarH)
                        
                        if frontRadar.lock == -1 then
                            frontRadar.target = vehSpeed
                            if dir == 1 then
                                if vehSpeed > patrolSpeed then
                                    frontRadar.dir = "receding"
                                else
                                    frontRadar.dir = "approaching"
                                end
                            else
                                frontRadar.dir = "approaching"
                            end
                            
                            if vehSpeed > speedLimit then
                                frontRadar.lock = vehSpeed
                                CreateThread(function()
                                    for i = 1, 3 do
                                        PlaySoundFrontend(-1, "Beep_Red", "DLC_HEIST_HACKING_SNAKE_SOUNDS", 1)
                                        Wait(150)
                                    end
                                end)
                                LockSpeederPlate(closestFrontVeh, vehSpeed)
                            end
                        else
                            frontRadar.target = frontRadar.lock
                        end
                    else
                        if frontRadar.lock == -1 then
                            frontRadar.target = -1
                            frontRadar.dir = "none"
                        else
                            frontRadar.target = frontRadar.lock
                        end
                    end
                    
                    if closestRearVeh then
                        local vehSpeed = GetEntitySpeed(closestRearVeh) * 2.236936
                        local myH = GetEntityHeading(vehicle)
                        local tarH = GetEntityHeading(closestRearVeh)
                        local dir = GetEntityRelativeDirection(myH, tarH)
                        
                        if rearRadar.lock == -1 then
                            rearRadar.target = vehSpeed
                            if dir == 1 then
                                if vehSpeed > patrolSpeed then
                                    rearRadar.dir = "approaching"
                                else
                                    rearRadar.dir = "receding"
                                end
                            else
                                rearRadar.dir = "receding"
                            end
                            
                            if vehSpeed > speedLimit then
                                rearRadar.lock = vehSpeed
                                CreateThread(function()
                                    for i = 1, 3 do
                                        PlaySoundFrontend(-1, "Beep_Red", "DLC_HEIST_HACKING_SNAKE_SOUNDS", 1)
                                        Wait(150)
                                    end
                                end)
                                LockSpeederPlate(closestRearVeh, vehSpeed)
                            end
                        else
                            rearRadar.target = rearRadar.lock
                        end
                    else
                        if rearRadar.lock == -1 then
                            rearRadar.target = -1
                            rearRadar.dir = "none"
                        else
                            rearRadar.target = rearRadar.lock
                        end
                    end
                else
                    frontRadar.target = -1
                    frontRadar.dir = "none"
                    rearRadar.target = -1
                    rearRadar.dir = "none"
                    radarTargetVehicle = nil
                    radarTargetRefreshAt = 0
                    cachedFrontRadarVehicle = nil
                    cachedRearRadarVehicle = nil
                end

                SendRadarUpdateIfChanged(patrolSpeed)
            else
                if not radarPaused then
                    radarPaused = true
                    SendNUIMessage({ type = "radar_ui", display = false })
                end
                radarTargetVehicle = nil
                radarTargetRefreshAt = 0
                cachedFrontRadarVehicle = nil
                cachedRearRadarVehicle = nil
                lastRadarPayloadKey = nil
            end
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        local sleep = 1000
        if display then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            
            if vehicle ~= 0 and GetVehicleClass(vehicle) == 18 and LocalPlayer.state.factionCategory == 'police' then
                local vehicleKey = GetRadarVehicleKey(vehicle)
                if vehicleKey and currentRadarVehicleKey ~= vehicleKey then
                    LoadRadarVehicleState(vehicle)
                end
                if isPaused then
                    isPaused = false
                    if not IsPauseMenuActive() then
                        SendNUIMessage({ type = "ui", display = true })
                    end
                end

                if GetPedInVehicleSeat(vehicle, -1) == ped then
                    sleep = Config.ScanInterval
                    
                    local coords = GetEntityCoords(vehicle)
                    local forward = GetEntityForwardVector(vehicle)
                    
                    if not frontLocked then
                        local frontVeh = GetVehicleInDirection(vehicle, coords, coords + forward * Config.ScanDistance)
                        if DoesEntityExist(frontVeh) and IsEntityAVehicle(frontVeh) and not isNPCVehicle(frontVeh) then
                            local vClass = GetVehicleClass(frontVeh)
                            if vClass ~= 14 and vClass ~= 15 and vClass ~= 16 and vClass ~= 21 then
                                local relCoords = GetOffsetFromEntityGivenWorldCoords(vehicle, GetEntityCoords(frontVeh))
                                if math.abs(relCoords.z) <= 3.5 and math.abs(relCoords.x) <= 6.5 then
                                     local myH = GetEntityHeading(vehicle)
                                     local tarH = GetEntityHeading(frontVeh)
                                     local dir = GetEntityRelativeDirection(myH, tarH)
                                     if dir > 0 then
                                        UpdateFrontVehicleScan(frontVeh, false)
                                    end
                                end
                            end
                        end
                    end
                end
            else
                if not isPaused then
                    isPaused = true
                    SendNUIMessage({ type = "ui", display = false })
                end
            end
        end
        Wait(sleep)
    end
end)

RegisterNetEvent('av_alpr:setOwner', function(cam, plate, profile)
    if cam == 'front' and frontData.plate and NormalizePlate(frontData.plate) == NormalizePlate(plate) then
        frontData.owner = profile.owner or "Unknown"
        frontData.photo = profile.photo
        frontData.flags = profile.flags or {}
        frontData.factionTag = profile.factionTag or frontData.factionTag
        SendNUIMessage({
            type = "updateOwner",
            owner = frontData.owner,
            photo = frontData.photo,
            flags = frontData.flags,
            plate = frontData.plate
        })
        if profile.autoLock then
            LockFrontPlate()
        end
        SaveCurrentRadarVehicleState()
    end
end)

CreateThread(function()
    local lastVehicle = nil
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        
        if vehicle ~= 0 and GetVehicleClass(vehicle) == 18 and LocalPlayer.state.factionCategory == 'police' then
            if lastVehicle ~= vehicle then
                if lastVehicle then
                    SaveRadarVehicleState(lastVehicle)
                end
                lastVehicle = vehicle
                local loaded = LoadRadarVehicleState(vehicle)
                if loaded then
                    if not IsPauseMenuActive() then
                        SendNUIMessage({
                            type = "ui",
                            display = display
                        })
                        SendNUIMessage({
                            type = "radar_ui",
                            display = radarDisplay
                        })
                        SendNUIMessage({
                            type = "remote_ui",
                            display = remoteOpen
                        })
                    end
                    if frontData and frontData.plate then
                        SendNUIMessage({
                            type = "update",
                            data = frontData
                        })
                    end
                else
                    radarPower = false
                    radarDisplay = false
                    display = false
                    remoteOpen = false
                    frontLocked = false
                    SendNUIMessage({ type = "ui", display = false })
                    SendNUIMessage({ type = "radar_ui", display = false })
                    SendNUIMessage({ type = "remote_ui", display = false })
                end
            end
        else
            if lastVehicle ~= nil then
                SaveRadarVehicleState(lastVehicle)
                lastVehicle = nil
                
                radarDisplay = false
                display = false
                remoteOpen = false
                SendNUIMessage({ type = "ui", display = false })
                SendNUIMessage({ type = "radar_ui", display = false })
                SendNUIMessage({ type = "remote_ui", display = false })
            end
        end
        Wait(1000)
    end
end)

CreateThread(function()
    while true do
        Wait(200)
        local paused = IsPauseMenuActive()
        if paused and not pauseMenuOpened then
            pauseMenuOpened = true
            SendNUIMessage({ type = "ui", display = false })
            SendNUIMessage({ type = "radar_ui", display = false })
            SendNUIMessage({ type = "remote_ui", display = false })
            if remoteOpen then
                SetNuiFocus(false, false)
            end
        elseif not paused and pauseMenuOpened then
            pauseMenuOpened = false
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle ~= 0 and GetVehicleClass(vehicle) == 18 and LocalPlayer.state.factionCategory == 'police' then
                if display and not isPaused then
                    SendNUIMessage({ type = "ui", display = true })
                end
                if radarDisplay and not radarPaused and GetPedInVehicleSeat(vehicle, -1) == ped then
                    SendNUIMessage({ type = "radar_ui", display = true })
                end
                if remoteOpen then
                    SetNuiFocus(true, true)
                    SendNUIMessage({ type = "remote_ui", display = true })
                end
            end
        end
    end
end)
