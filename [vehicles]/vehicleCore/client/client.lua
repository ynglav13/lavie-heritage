local CRASH_DAMAGE_MULTIPLIER = 0.2
local lastCrashStressTime = 0
local BAIL_DAMAGE_MULTIPLIER = 0.2

local function IsMotorcycle(class, vehicle)
    if class == 8 or class == 13 then
        return true
    end

    if vehicle and DoesEntityExist(vehicle) then
        if GetEntityModel(vehicle) == GetHashKey("lapdr1200") then
            return true
        end
    end
    return false
end

local function GetClosestVehicleWithCoords(coords, radius)
    local vehicles = GetGamePool('CVehicle')
    local closestDistance = radius
    local closestVehicle = 0

    for i = 1, #vehicles do
        local vehicleCoords = GetEntityCoords(vehicles[i])
        local distance = #(coords - vehicleCoords)

        if distance < closestDistance then
            closestDistance = distance
            closestVehicle = vehicles[i]
        end
    end
    return closestVehicle
end

local animTimer = nil
local function playAnimLock()
    CreateThread(function()
        if animTimer then
            animTimer:forceEnd(true)

            Wait(100)
        end

        local ped = PlayerPedId()
        local keyProp = nil
        local coords = GetEntityCoords(ped)
        local keyModel = lib.requestModel('p_car_keys_01')

        if keyModel then
            keyProp = CreateObject(keyModel, coords.x, coords.y, coords.z - 2.0, true, true, true)

            AttachEntityToEntity(
                keyProp, ped, GetPedBoneIndex(ped, 57005),
                0.08, 0.039, 0.0, 0.0, 0.0, 0.0,
                true, true, false, true, 1, true
            )

            SetModelAsNoLongerNeeded(keyModel)
        end

        local animDict = lib.requestAnimDict('anim@mp_player_intmenu@key_fob@')

        if animDict then
            TaskPlayAnim(ped, animDict, 'fob_click', 8.0, -8.0, -1, 48, 0, false, false, false)

            RemoveAnimDict(animDict)
        end

        animTimer = lib.timer(1000, function()
            ClearPedTasks(ped)

            if keyProp and DoesEntityExist(keyProp) then
                DetachEntity(keyProp, false, false)
                DeleteEntity(keyProp)
            end
        end)
    end)
end

local function closeAllVehicleDoors(vehicle)
    if DoesEntityExist(vehicle) then
        SetVehicleDoorsShut(vehicle, false)
        for i = 0, 7 do
            SetVehicleDoorShut(vehicle, i, false)
        end
    end
end

local function playVehicleLock(entity)
    CreateThread(function()
        if not DoesEntityExist(entity) then
            return

        end

        Wait(500)

        SetVehicleLights(entity, 2)
        SetVehicleIndicatorLights(entity, 1, true)
        SetVehicleIndicatorLights(entity, 0, true)

        for i = 0, 5 do
            Wait(0)

            SoundVehicleHornThisFrame(entity)
        end

        PlayVehicleDoorOpenSound(entity, 0)
        PlayVehicleDoorOpenSound(entity, 1)
        PlayVehicleDoorOpenSound(entity, 0)
        PlayVehicleDoorOpenSound(entity, 1)

        Wait(200)

        SetVehicleLights(entity, 0)
        SetVehicleIndicatorLights(entity, 1, false)
        SetVehicleIndicatorLights(entity, 0, false)

        for i = 0, 5 do
            Wait(0)

            SoundVehicleHornThisFrame(entity)
        end

        Wait(200)

        SetVehicleLights(entity, 2)
        SetVehicleIndicatorLights(entity, 1, true)
        SetVehicleIndicatorLights(entity, 0, true)

        Wait(200)

        SetVehicleLights(entity, 0)
        SetVehicleIndicatorLights(entity, 1, false)
        SetVehicleIndicatorLights(entity, 0, false)
    end)
end

RegisterCommand('vehiclekey', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then
        local coords = GetEntityCoords(ped)

        vehicle = GetClosestVehicleWithCoords(coords, 5.0)
    end

    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        local class = GetVehicleClass(vehicle)

        if class == 21 then
            return
        end

        local plate = GetVehicleNumberPlateText(vehicle)

        if plate then
            local trimmedClientPlate = string.upper(string.match(plate, "^%s*(.-)%s*$"))
            local items = exports.ox_inventory:Search('slots', 'vehicle_key')
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
                if not IsPedInAnyVehicle(ped, false) then
                    playAnimLock()
                end

                local currentLock = GetVehicleDoorLockStatus(vehicle)
                local newStatus = (currentLock == 1 or currentLock == 0) and 2 or 1
                
                SetVehicleDoorsLocked(vehicle, newStatus)
                if newStatus == 2 then
                    closeAllVehicleDoors(vehicle)
                end

                local statusText = newStatus == 2 and 'locked' or 'unlocked'

                SendNUIMessage(
                {
                    action = 'SHOW_LOCK_UI',
                    status = statusText
                })
                
                CreateThread(function()
                    local endTime = GetGameTimer() + 2000
                    local min, max = GetModelDimensions(GetEntityModel(vehicle))
                    local offsetZ = max.z + 0.5
                    
                    while GetGameTimer() < endTime do
                        Wait(0)
                        if DoesEntityExist(vehicle) then
                            local coords = GetEntityCoords(vehicle)
                            local targetCoords = vector3(coords.x, coords.y, coords.z + offsetZ)
                            
                            local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(targetCoords.x, targetCoords.y, targetCoords.z)
                            
                            if onScreen then
                                SendNUIMessage(
                                {
                                    action = 'UPDATE_COORDS',
                                    x = screenX,
                                    y = screenY
                                })
                            else
                                SendNUIMessage(
                                {
                                    action = 'UPDATE_COORDS',
                                    x = -1,
                                    y = -1
                                })
                            end
                        else
                            break
                        end
                    end
                end)

                local netId = NetworkGetEntityIsNetworked(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or 0
                
                TriggerServerEvent('vehicleCore:server:toggleLock', netId, plate, newStatus)
            else
                exports['custom-chat']:SendClientMessage("{FFFFFF}Bạn {FF6347}không có chìa khóa{FFFFFF} của phương tiện này")
            end
        end
    end
end, false)
RegisterKeyMapping('vehiclekey', 'Khoa/Mo Khoa Phuong Tien', 'keyboard', 'M')

AddStateBagChangeHandler('locked', nil, function(bagName, key, value, _reserved, replicated)
    if not value then
        return
    end
    
    local entity = GetEntityFromStateBagName(bagName)
    
    if entity == 0 then
        return
    end
    
    -- Ensure it's a vehicle
    if IsEntityAVehicle(entity) then
        SetVehicleDoorsLocked(entity, value)
        if value == 2 then
            closeAllVehicleDoors(entity)
        end
    end
end)

RegisterNetEvent('vehicleCore:client:syncFlash', function(netId, newStatus)
    if NetworkDoesNetworkIdExist(netId) then
        local vehicle = NetworkGetEntityFromNetworkId(netId)

        if vehicle ~= 0 and DoesEntityExist(vehicle) then
            playVehicleLock(vehicle)
            local status = newStatus or GetVehicleDoorLockStatus(vehicle)
            if status == 2 then
                closeAllVehicleDoors(vehicle)
            end
        end
    end
end)

local seatbeltOn = false
local speedBuffer =
{
    0.0,
    0.0,
    0.0
}

local velocityBuffer =
{
    vector3(0,0,0),
    vector3(0,0,0)
}

local healthBuffer =
{
    1000.0,
    1000.0,
    1000.0
}

local wasInCar = false
local lastVehicleNetId = 0
local lastVehicleSeenAt = 0
local lastVehicleSeatbelt = false
local lastVehicleClass = 0
local lastVehicleIsMotorcycle = false
local lastCrashReportTime = nil
local lastAppliedCrashId = nil
local lastSyncedCrashAt = 0
local lastSyncedCrashVehicleNetId = 0

local crashEffectState =
{
    running = false,
    stage = 'idle',
    primaryUntil = 0,
    aftershockUntil = 0,
    intensity = 0.0
}

local crashBlackoutState =
{
    running = false,
    owned = false,
    stage = 'idle',
    holdUntil = 0,
    restartFade = false
}

exports('HasSeatbelt', function() return seatbeltOn end)

local function waitForScreenFade(predicate, timeout)
    local deadline = GetGameTimer() + timeout

    while not predicate() and GetGameTimer() < deadline do
        Wait(0)
    end
end

local function DisableCrashBlackoutVehicleControls()
    DisableControlAction(0, 59, true) -- INPUT_VEH_MOVE_LR
    DisableControlAction(0, 60, true) -- INPUT_VEH_MOVE_UD
    DisableControlAction(0, 61, true) -- INPUT_VEH_MOVE_UP_ONLY
    DisableControlAction(0, 62, true) -- INPUT_VEH_MOVE_DOWN_ONLY
    DisableControlAction(0, 63, true) -- INPUT_VEH_MOVE_LEFT_ONLY
    DisableControlAction(0, 64, true) -- INPUT_VEH_MOVE_RIGHT_ONLY
    DisableControlAction(0, 71, true) -- INPUT_VEH_ACCELERATE
    DisableControlAction(0, 72, true) -- INPUT_VEH_BRAKE
    DisableControlAction(0, 76, true) -- INPUT_VEH_HANDBRAKE
end

local function StartCrashBlackout(duration)
    local now = GetGameTimer()
    local timeBeforeFadeIn = math.max(
        duration - Config.CrashBlackoutFadeIn,
        Config.CrashBlackoutFadeOut
    )
    local requestedHoldUntil = now + timeBeforeFadeIn

    crashBlackoutState.holdUntil = math.max(crashBlackoutState.holdUntil, requestedHoldUntil)

    if crashBlackoutState.running then
        if crashBlackoutState.stage == 'fadein' then
            crashBlackoutState.restartFade = true
        end

        return
    end

    crashBlackoutState.running = true
    crashBlackoutState.owned = true

    CreateThread(function()
        while crashBlackoutState.running do
            DisableCrashBlackoutVehicleControls()
            Wait(0)
        end
    end)

    SendNUIMessage(
    {
        action = 'PLAY_CRASH_SOUND',
        volume = Config.CrashSoundVolume
    })

    CreateThread(function()
        while crashBlackoutState.running do
            crashBlackoutState.stage = 'fadeout'

            DoScreenFadeOut(Config.CrashBlackoutFadeOut)
            waitForScreenFade(IsScreenFadedOut, Config.CrashBlackoutFadeOut + 1000)

            crashBlackoutState.stage = 'hold'

            while crashBlackoutState.running and GetGameTimer() < crashBlackoutState.holdUntil do
                Wait(50)
            end

            if not crashBlackoutState.running then
                break
            end

            crashBlackoutState.stage = 'fadein'
            crashBlackoutState.restartFade = false

            DoScreenFadeIn(Config.CrashBlackoutFadeIn)

            local fadeInDeadline = GetGameTimer() + Config.CrashBlackoutFadeIn + 1000

            while crashBlackoutState.running
                and not crashBlackoutState.restartFade
                and not IsScreenFadedIn()
                and GetGameTimer() < fadeInDeadline
            do
                Wait(50)
            end

            if not crashBlackoutState.restartFade then
                break
            end

            crashBlackoutState.restartFade = false
        end

        crashBlackoutState.running = false
        crashBlackoutState.owned = false
        crashBlackoutState.stage = 'idle'
        crashBlackoutState.holdUntil = 0
        crashBlackoutState.restartFade = false
    end)
end

local function CleanupCrashEffect(ped)
    if crashEffectState.running then
        ClearTimecycleModifier()
        StopGameplayCamShaking(true)
        ResetPedMovementClipset(ped, 0)
        RemoveAnimSet("move_m@injured")
    end

    crashEffectState.running = false
    crashEffectState.stage = 'idle'
    crashEffectState.primaryUntil = 0
    crashEffectState.aftershockUntil = 0
    crashEffectState.intensity = 0.0
end

local function ApplyCrashEffect(ped, speedDelta, severityMultiplier)
    local effectiveSeverity = speedDelta * severityMultiplier
    local intensity = math.min((speedDelta / 12.0) * severityMultiplier, 3.0)
    local duration = math.min(math.floor(speedDelta * 300 * severityMultiplier), 15000)
    local now = GetGameTimer()

    crashEffectState.primaryUntil = math.max(crashEffectState.primaryUntil, now + duration)
    crashEffectState.aftershockUntil = math.max(
        crashEffectState.aftershockUntil,
        crashEffectState.primaryUntil + (duration * 2)
    )
    crashEffectState.intensity = math.max(crashEffectState.intensity, intensity)

    ShakeGameplayCam("DRUNK_SHAKE", (crashEffectState.intensity * 0.5) + 1.0)

    if speedDelta >= Config.CrashBlackoutThreshold then
        local severityRange = Config.CrashMaximumSeverity - Config.CrashBlackoutThreshold
        local normalizedSeverity = severityRange > 0.0
            and (effectiveSeverity - Config.CrashBlackoutThreshold) / severityRange
            or 1.0
        normalizedSeverity = math.max(0.0, math.min(normalizedSeverity, 1.0))

        local blackoutDuration = math.floor(
            Config.CrashBlackoutMinDuration
                + ((Config.CrashBlackoutMaxDuration - Config.CrashBlackoutMinDuration) * normalizedSeverity)
        )

        StartCrashBlackout(blackoutDuration)
    end

    if crashEffectState.running then
        return
    end

    crashEffectState.running = true

    RequestAnimSet("move_m@injured")
    SetFollowVehicleCamViewMode(2)

    CreateThread(function()
        while crashEffectState.running and GetGameTimer() < crashEffectState.aftershockUntil do
            local isPrimaryEffect = GetGameTimer() < crashEffectState.primaryUntil

            if isPrimaryEffect then
                if crashEffectState.stage ~= 'primary' then
                    crashEffectState.stage = 'primary'
                    SetTimecycleModifier("Damage")
                end

                SetTimecycleModifierStrength(crashEffectState.intensity)

                if not IsGameplayCamShaking() then
                    ShakeGameplayCam("DRUNK_SHAKE", (crashEffectState.intensity * 0.5) + 1.0)
                end

                DisableControlAction(0, 0, true)
            else
                if crashEffectState.stage ~= 'aftershock' then
                    crashEffectState.stage = 'aftershock'
                    ClearTimecycleModifier()
                    ShakeGameplayCam("DRUNK_SHAKE", (crashEffectState.intensity * 0.2) + 0.5)
                end

                if HasAnimSetLoaded("move_m@injured") then
                    SetPedMovementClipset(ped, "move_m@injured", true)
                end

                if not IsGameplayCamShaking() then
                    ShakeGameplayCam("DRUNK_SHAKE", (crashEffectState.intensity * 0.2) + 0.5)
                end

                DisableControlAction(0, 0, true)
                DisableControlAction(0, 21, true)
                DisableControlAction(0, 22, true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                DisableControlAction(0, 257, true)
                DisablePlayerFiring(PlayerId(), true)
            end

            Wait(0)
        end

        CleanupCrashEffect(ped)
    end)
end

local function EjectPlayer(ped, vehicle, velocity)
    local co = GetEntityCoords(ped)
    local fw = GetEntityForwardVector(ped)
    local class = GetVehicleClass(vehicle)

    if not IsMotorcycle(class, vehicle) then
        SmashVehicleWindow(vehicle, 6)
    end

    ClearPedTasksImmediately(ped)
    
    SetEntityCoords(ped, co.x + (fw.x * 0.5), co.y + (fw.y * 0.5), co.z + 0.2, true, true, true)
    
    Wait(1)

    if IsMotorcycle(class, vehicle) then
        -- Bike
        SetEntityVelocity(ped, velocity.x * 1.5, velocity.y * 1.5, velocity.z * 0.8)
    else
        -- Car
        SetEntityVelocity(ped, velocity.x * 2.0, velocity.y * 1.2, velocity.z * 1.0)
    end
    
    CreateThread(function()
        SetPedCanRagdoll(ped, true)
        SetPedToRagdoll(ped, 3000, 3000, 0, true, true, false)

        local endTime = GetGameTimer() + 4000

        while GetGameTimer() < endTime do
            Wait(200)

            if not IsPedRagdoll(ped) and GetEntitySpeed(ped) < 0.5 then
                break
            end
        end
    end)
end

RegisterCommand('veh_seatbelt', function()
    local ped = PlayerPedId()

    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        local class = GetVehicleClass(vehicle)
        local text

        if not IsMotorcycle(class, vehicle) and class ~= 14 then
            seatbeltOn = not seatbeltOn
            
            TriggerEvent("InteractSound_CL:PlayOnOne", seatbeltOn and "carbuckle" or "carunbuckle", 0.25)
            
            if seatbeltOn then
                TriggerServerEvent('vehicleCore:seatbeltBubble', seatbeltOn)
            else
                TriggerServerEvent('vehicleCore:seatbeltBubble', seatbeltOn)
            end
        end
    end
end, false)
RegisterKeyMapping('veh_seatbelt', 'Deo/Thao Day An Toan', 'keyboard', 'B')

RegisterNetEvent('vehicleCore:client:applyCrash', function(payload)
    if type(payload) ~= 'table'
        or type(payload.crashId) ~= 'string'
        or payload.crashId == lastAppliedCrashId
    then
        return
    end

    local netId = tonumber(payload.netId)
    local crashSeverity = tonumber(payload.severity)
    local velocityX = tonumber(payload.velocityX)
    local velocityY = tonumber(payload.velocityY)
    local velocityZ = tonumber(payload.velocityZ)

    if not netId or netId <= 0
        or not crashSeverity or crashSeverity <= Config.CrashMinimumSeverity
        or not velocityX or not velocityY or not velocityZ
    then
        return
    end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local currentVehicleNetId = (vehicle ~= 0 and NetworkGetEntityIsNetworked(vehicle)) and NetworkGetNetworkIdFromEntity(vehicle) or 0
    local isCurrentOccupant = currentVehicleNetId == netId
    local isRecentOccupant = lastVehicleNetId == netId
        and GetGameTimer() - lastVehicleSeenAt <= Config.CrashRecentOccupantGrace

    if not isCurrentOccupant and not isRecentOccupant then
        return
    end

    lastAppliedCrashId = payload.crashId
    lastSyncedCrashAt = GetGameTimer()
    lastSyncedCrashVehicleNetId = netId

    local crashSeatbeltOn = isCurrentOccupant and seatbeltOn or lastVehicleSeatbelt
    local class = isCurrentOccupant and GetVehicleClass(vehicle) or lastVehicleClass
    local isMotorcycle = IsMotorcycle(class, isCurrentOccupant and vehicle or 0)
    local severityMultiplier = crashSeatbeltOn and 1.0 or 1.5

    if Config.CrashStressEnabled
        and (not lastCrashStressTime
            or GetGameTimer() - lastCrashStressTime >= Config.CrashStressClientCooldown)
    then
        lastCrashStressTime = GetGameTimer()

        if math.random(100) <= Config.CrashStressChance then
            TriggerServerEvent('vehicleCore:server:addCrashStress')
        end
    end

    local baseDamage = math.floor(crashSeverity * CRASH_DAMAGE_MULTIPLIER)
    local flyOutChance = 0

    if crashSeatbeltOn then
        baseDamage = math.floor(baseDamage * 0.8)
    else
        if isMotorcycle then
            flyOutChance = 100
        elseif crashSeverity > 25.0 then
            flyOutChance = 80
        elseif crashSeverity > 15.0 then
            flyOutChance = 50
        end
    end

    ApplyCrashEffect(ped, crashSeverity, severityMultiplier)

    if isCurrentOccupant and math.random(1, 100) <= flyOutChance then
        EjectPlayer(ped, vehicle, vector3(velocityX, velocityY, velocityZ))

        if isMotorcycle then
            baseDamage = baseDamage + math.floor(crashSeverity * 2.0) + 20
        else
            baseDamage = baseDamage + math.floor(crashSeverity * 1.0) + 10
        end
    end

    if baseDamage > 0 then
        TriggerEvent(
            'lavie_injury:client:applyDamage',
            baseDamage,
            0,
            `WEAPON_VEHICLE_CRASH`,
            GetPlayerServerId(PlayerId())
        )
    end
end)

local function ScheduleBailEffect(ped, vehicleNetId, bailSpeed, wasMotorcycle, exitedAt)
    CreateThread(function()
        Wait(Config.CrashRecentOccupantGrace)

        local wasHandledBySyncedCrash = lastSyncedCrashVehicleNetId == vehicleNetId
            and lastSyncedCrashAt >= exitedAt - Config.CrashRecentOccupantGrace
            and lastSyncedCrashAt <= GetGameTimer()

        if wasHandledBySyncedCrash or ped ~= PlayerPedId() or not DoesEntityExist(ped) then
            return
        end

        ApplyCrashEffect(ped, bailSpeed, 1.5)

        local baseDamage

        if wasMotorcycle then
            baseDamage = math.floor(bailSpeed * 2.0 * BAIL_DAMAGE_MULTIPLIER) + 30
        else
            baseDamage = math.floor(bailSpeed * 1.0 * BAIL_DAMAGE_MULTIPLIER) + 20
        end

        TriggerEvent(
            'lavie_injury:client:applyDamage',
            baseDamage,
            0,
            `WEAPON_VEHICLE_CRASH`,
            GetPlayerServerId(PlayerId())
        )
    end)
end

CreateThread(function()
    while true do
        Wait(100)

        local ped = PlayerPedId()

        local vehicle = GetVehiclePedIsIn(ped, false)
        local class = vehicle ~= 0 and GetVehicleClass(vehicle) or -1

        if vehicle ~= 0 and class ~= 14 then
            local vehicleNetId = NetworkGetEntityIsNetworked(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or 0

            if not wasInCar or lastVehicleNetId ~= vehicleNetId then
                wasInCar = true

                local initialHealth = GetVehicleBodyHealth(vehicle)

                speedBuffer[1], speedBuffer[2], speedBuffer[3] = 0.0, 0.0, 0.0
                velocityBuffer[1], velocityBuffer[2] = vector3(0,0,0), vector3(0,0,0)
                healthBuffer[1], healthBuffer[2], healthBuffer[3] = initialHealth, initialHealth, initialHealth
            end

            lastVehicleNetId = vehicleNetId
            lastVehicleSeenAt = GetGameTimer()
            lastVehicleSeatbelt = seatbeltOn
            lastVehicleClass = class
            lastVehicleIsMotorcycle = IsMotorcycle(class, vehicle)

            if not lastVehicleIsMotorcycle then
                SetPedConfigFlag(ped, 32, not seatbeltOn)
            end

            local speed = GetEntitySpeed(vehicle)

            speedBuffer[3] = speedBuffer[2]
            speedBuffer[2] = speedBuffer[1]
            speedBuffer[1] = speed

            velocityBuffer[2] = velocityBuffer[1]
            velocityBuffer[1] = GetEntityVelocity(vehicle)

            healthBuffer[3] = healthBuffer[2]
            healthBuffer[2] = healthBuffer[1]
            healthBuffer[1] = GetVehicleBodyHealth(vehicle)

            if GetPedInVehicleSeat(vehicle, -1) == ped then
                local speedDelta = speedBuffer[3] - speedBuffer[1]
                local healthDrop = healthBuffer[3] - healthBuffer[1]
                local roll = GetEntityRoll(vehicle)
                local pitch = GetEntityPitch(vehicle)
                local isRolledOver = math.abs(roll) > 75.0 or math.abs(pitch) > 75.0
                local crashSeverity = 0.0

                if speedBuffer[3] > 15.0
                    and speedDelta > (speedBuffer[3] * 0.25)
                    and healthDrop > 2.0
                then
                    crashSeverity = speedDelta
                elseif speedBuffer[1] > 10.0 and isRolledOver and healthDrop > 2.0 then
                    crashSeverity = speedBuffer[1] * 0.5
                end

                local currentTime = GetGameTimer()

                if crashSeverity > Config.CrashMinimumSeverity
                    and vehicleNetId > 0
                    and (not lastCrashReportTime
                        or currentTime - lastCrashReportTime >= Config.CrashSyncCooldown)
                then
                    lastCrashReportTime = currentTime

                    local crashVelocity = velocityBuffer[2]

                    TriggerServerEvent('vehicleCore:server:reportCrash',
                    {
                        netId = vehicleNetId,
                        severity = crashSeverity,
                        velocityX = crashVelocity.x,
                        velocityY = crashVelocity.y,
                        velocityZ = crashVelocity.z
                    })
                end
            end
        else
            if wasInCar then
                wasInCar = false
                local bailSpeed = speedBuffer[1]
                local exitedAt = GetGameTimer()

                if bailSpeed > 10.0 then
                    ScheduleBailEffect(ped, lastVehicleNetId, bailSpeed, lastVehicleIsMotorcycle, exitedAt)
                end

                seatbeltOn = false

                speedBuffer[1], speedBuffer[2], speedBuffer[3] = 0.0, 0.0, 0.0
                velocityBuffer[1], velocityBuffer[2] = vector3(0,0,0), vector3(0,0,0)
                healthBuffer[1], healthBuffer[2], healthBuffer[3] = 1000.0, 1000.0, 1000.0
            end

            Wait(1000)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    CleanupCrashEffect(PlayerPedId())

    if crashBlackoutState.owned then
        crashBlackoutState.running = false
        DoScreenFadeIn(0)
    end

    SendNUIMessage(
    {
        action = 'STOP_CRASH_SOUND'
    })
end)

local vehicleEngineOn = false
local currentVehicle = 0
local lastSteeringAngle = nil

RegisterCommand('toggleengine', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    local model = GetEntityModel(vehicle)
    local displayName = GetDisplayNameFromVehicleModel(model)
    local vehicleName = GetLabelText(displayName)
    if not vehicleName or vehicleName == "NULL" or vehicleName == "" then
        vehicleName = displayName
    end

    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
        local class = GetVehicleClass(vehicle)

        if class == 13 or class == 15 or class == 16 or class == 21 then
            return
        end
        
        if vehicleEngineOn then
            vehicleEngineOn = false

            SetVehicleEngineOn(vehicle, false, false, true)
            SetVehicleKeepEngineOnWhenAbandoned(vehicle, false)

            TriggerServerEvent('vehicleCore:engineBubble', vehicleName, vehicleEngineOn)
        else
            local plate = GetVehicleNumberPlateText(vehicle)
            
            if plate then
                local trimmedClientPlate = string.upper(string.match(plate, "^%s*(.-)%s*$"))
                local items = exports.ox_inventory:Search('slots', 'vehicle_key')
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
                    vehicleEngineOn = true

                    SetVehicleEngineOn(vehicle, true, false, true)
                    SetVehicleKeepEngineOnWhenAbandoned(vehicle, true)

                    TriggerServerEvent('vehicleCore:engineBubble', vehicleName, vehicleEngineOn)
                else
                    exports['custom-chat']:SendClientMessage("{FFFFFF}Bạn {FF6347}không có chìa khóa{FFFFFF} của phương tiện này")
                end
            end
        end
    end
end, false)
RegisterKeyMapping('toggleengine', 'Bat/Tat Dong Co Phuong Tien', 'keyboard', 'UP')

CreateThread(function()
    while true do
        local sleep = 500
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if vehicle == 0 then
            vehicle = GetVehiclePedIsTryingToEnter(ped)
        end

        local class = vehicle ~= 0 and GetVehicleClass(vehicle) or nil

        
        SetPedConfigFlag(ped, 241, true) 
        SetPedConfigFlag(ped, 184, true)
        SetPedConfigFlag(ped, 35, false)

        if class and (class == 13 or class == 15 or class == 16 or class == 21) then
            SetPedConfigFlag(ped, 429, false)
        else
            SetPedConfigFlag(ped, 429, true) -- Prevent engine starting
        end
        
        local tryingVeh = GetVehiclePedIsTryingToEnter(ped)

        if tryingVeh ~= 0 then
            SetVehicleNeedsToBeHotwired(tryingVeh, false)
        end

        if IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            local isDriver = GetPedInVehicleSeat(vehicle, -1) == ped
            local class = GetVehicleClass(vehicle)

            if seatbeltOn then
                sleep = 0
                
                DisableControlAction(0, 75, true)
            end

            if vehicle ~= 0 and isDriver and class ~= 13 and class ~= 15 and class ~= 16 and class ~= 21 then
                sleep = 0
                
                if currentVehicle ~= vehicle then
                    vehicleEngineOn = GetIsVehicleEngineRunning(vehicle)

                    currentVehicle = vehicle

                    lastSteeringAngle = nil
                end

                SetVehicleKeepEngineOnWhenAbandoned(vehicle, vehicleEngineOn)

                if not vehicleEngineOn then
                    SetVehicleEngineOn(vehicle, false, true, true)
                end

                -- Track steering angle
                local steeringAngle = GetVehicleSteeringAngle(vehicle)

                if not GetIsTaskActive(ped, 2) and steeringAngle and steeringAngle ~= 0.0 then
                    lastSteeringAngle = steeringAngle
                end
                
                if GetIsTaskActive(ped, 2) and lastSteeringAngle then
                    SetVehicleSteeringAngle(vehicle, lastSteeringAngle)
                end
            end
        else
            if currentVehicle ~= 0 then
                if lastSteeringAngle and DoesEntityExist(currentVehicle) then
                    SetVehicleSteeringAngle(currentVehicle, lastSteeringAngle)
                end

                lastSteeringAngle = nil

                currentVehicle = 0
            end
        end

        Wait(sleep)
    end
end)

local keyMakerCoords = vector4(165.13, -1808.15, 29.32, 314.84)
local keyMakerModel = `a_m_m_farmer_01`

CreateThread(function()
    RequestModel(keyMakerModel)
    
    while not HasModelLoaded(keyMakerModel) do
        Wait(10)
    end

    local ped = CreatePed(4, keyMakerModel, keyMakerCoords.x, keyMakerCoords.y, keyMakerCoords.z - 1.0, keyMakerCoords.w, false, false)
    
    SetEntityInvincible(ped, true)
    
    FreezeEntityPosition(ped, true)
    
    SetBlockingOfNonTemporaryEvents(ped, true)
    
    SetModelAsNoLongerNeeded(keyMakerModel)

    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:addLocalEntity(ped,
        {
            {
                name = 'make_vehicle_key',
                icon = 'fas fa-key',
                label = 'Rèn Chìa Khóa',
                onSelect = function()
                    local ESX = exports['es_extended']:getSharedObject()
                    
                    ESX.TriggerServerCallback('vehicleCore:server:getOwnedVehicles', function(vehicles)
                        if not vehicles or #vehicles == 0 then
                            exports.ox_lib:notify(
                            {
                                title = 'Lỗi',
                                description = 'Bạn không sở hữu phương tiện nào để có thể rèn chìa khóa',
                                type = 'error'
                            })
                            return
                        end

                        local options = {}

                        for i = 1, #vehicles do
                            local plate = vehicles[i].plate
                            local vehicleData = json.decode(vehicles[i].vehicle)
                            local modelName = "Unknown"

                            if vehicleData and vehicleData.model then
                                modelName = GetDisplayNameFromVehicleModel(vehicleData.model)

                                local labelText = GetLabelText(modelName)

                                if labelText and labelText ~= "NULL" then
                                    modelName = labelText
                                end
                            end

                            table.insert(options,
                            {
                                title = 'Biển Số: ' .. plate,
                                description = 'Phương Tiện: ' .. modelName,
                                icon = 'car',
                                onSelect = function()
                                    TriggerServerEvent('vehicleCore:server:buyKey', plate)
                                end
                            })
                        end

                        exports.ox_lib:registerContext(
                        {
                            id = 'make_key_menu',
                            title = 'Chọn Phương Tiện',
                            options = options
                        })

                        exports.ox_lib:showContext('make_key_menu')
                    end)
                end
            }
        })
    end
end)

exports('setEngineState', function(state, veh)
    vehicleEngineOn = state
    
    if veh and DoesEntityExist(veh) then
        currentVehicle = veh
        
        SetVehicleEngineOn(veh, state, true, true)
        SetVehicleKeepEngineOnWhenAbandoned(veh, state)
    end
end)

local function hasVehicleKey(plate)
    if not plate then
        return false
    end
    
    local trimmedPlate = string.upper(string.match(plate, "^%s*(.-)%s*$"))
    
    local items = exports.ox_inventory:Search('slots', 'vehicle_key')
    
    if items then
        for _, item in pairs(items) do
            if item.metadata and item.metadata.plate and string.upper(string.match(item.metadata.plate, "^%s*(.-)%s*$")) == trimmedPlate then
                return true
            end
        end
    end
    return false
end

CreateThread(function()
    if GetResourceState('ox_target') ~= 'started' then
        return
    end

    exports.ox_target:addGlobalVehicle(
    {
        {
            name = 'vehicle_trunk_inventory',
            icon = 'fas fa-archive',
            label = 'Mở Cốp Phương Tiện',
            distance = 2.0,
            canInteract = function(entity)
                return exports.ox_inventory:CanAccessTrunk(entity) ~= nil
            end,
            onSelect = function(data)
                return exports.ox_inventory:OpenTrunk(data.entity)
            end
        }
    })
end)

RegisterNetEvent('vehicleCore:client:openStash', function(stashId)
    exports.ox_inventory:openInventory('stash', stashId)
end)

RegisterCommand('gunrack', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        if GetVehicleClass(vehicle) == 18 then
            local plate = GetVehicleNumberPlateText(vehicle)

            if hasVehicleKey(plate) then
                local trimmedPlate = string.upper(string.match(plate, "^%s*(.-)%s*$"))

                TriggerServerEvent('vehicleCore:server:openGunrack', trimmedPlate)
            else
                exports['lv_notify']:Notify(
                {
                    type = 'error',
                    title = 'Giá Súng',
                    message = 'Bạn không có chìa khóa của phương tiện này',
                    duration = 4500
                })
            end
        end
    end
end, false)

Citizen.CreateThread(function()
    local blip = AddBlipForCoord(166.18, -1806.90, 29.32)
    
    SetBlipSprite(blip, 134)          
    SetBlipDisplay(blip, 4)           
    SetBlipScale(blip, 0.8)           
    SetBlipColour(blip, 0)            
    SetBlipAsShortRange(blip, true)  
    
    BeginTextCommandSetBlipName("STRING")

    AddTextComponentString("Locksmith")
    
    EndTextCommandSetBlipName(blip)
end)
