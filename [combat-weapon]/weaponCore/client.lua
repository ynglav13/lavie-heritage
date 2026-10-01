local isArmed = false
local currentWeapon = nil
local sprayCount = 0
local lastShotTime = 0
local lastStressShotTime = 0

local function GetAimDistance(ped)
    local camPos = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local rx = math.rad(camRot.x)
    local ry = math.rad(camRot.y)
    local rz = math.rad(camRot.z)
    
    local dirX = -math.sin(rz) * math.abs(math.cos(rx))
    local dirY = math.cos(rz) * math.abs(math.cos(rx))
    local dirZ = math.sin(rx)
    
    local endCoords = vector3(camPos.x + dirX * 1000.0, camPos.y + dirY * 1000.0, camPos.z + dirZ * 1000.0)
    
    local ray = StartShapeTestRay(camPos.x, camPos.y, camPos.z, endCoords.x, endCoords.y, endCoords.z, -1, ped, 0)
    local _, hit, hitCoords = GetShapeTestResult(ray)
    
    if hit == 1 then
        return #(camPos - hitCoords)
    end
    return Config.MaxDistanceThreshold or 100.0
end

CreateThread(function()
    while true do
        Wait(500)

        local ped = PlayerPedId()

        if IsPedArmed(ped, 4) then 
            isArmed = true

            _, currentWeapon = GetCurrentPedWeapon(ped, true)
        else
            isArmed = false

            currentWeapon = nil

            sprayCount = 0
        end
    end
end)

CreateThread(function()
    while true do
        local sleep = 1000
        local isBypass = LocalPlayer.state.bypassRecoil or false

        if isArmed and not isBypass then
            local ped = PlayerPedId()

            sleep = 0
            
            if IsPedShooting(ped) then
                local currentTime = GetGameTimer()

                if Config.StressOnShooting and currentTime - lastStressShotTime >= Config.StressClientCooldown then
                    lastStressShotTime = currentTime
                    
                    if math.random(100) <= Config.StressChance then
                        TriggerServerEvent('weaponCore:server:addShootingStress')
                    end
                end

                if currentTime - lastShotTime < 400 then
                    sprayCount = sprayCount + 1
                else
                    sprayCount = 0
                end

                lastShotTime = currentTime

                local recoilData = Config.Weapons[currentWeapon] or Config.DefaultRecoil
                local fppMultiplier = 1.0
                local moveMultiplier = 1.0
                local vehicleMultiplier = 1.0
                local sprayMult = 1.0
                local distanceMult = 1.0
                
                if GetFollowPedCamViewMode() == 4 then
                    fppMultiplier = Config.FirstPersonMultiplier
                end
                
                if GetEntitySpeed(ped) > 1.5 then
                    moveMultiplier = Config.MovementMultiplier
                end
                
                if IsPedInAnyVehicle(ped, false) then
                    vehicleMultiplier = Config.VehicleMultiplier
                end
                
                if Config.EnableSprayRecoil then
                    sprayMult = 1.0 + (sprayCount * Config.SprayMultiplierPerShot)

                    if sprayMult > Config.MaxSprayMultiplier then
                        sprayMult = Config.MaxSprayMultiplier
                    end
                end
                
                if Config.EnableDistanceRecoil then
                    local dist = GetAimDistance(ped)
                    local extra = (dist / Config.MaxDistanceThreshold) * (Config.DistanceMultiplierMax - Config.DistanceMultiplierBase)

                    distanceMult = Config.DistanceMultiplierBase + extra

                    if distanceMult > Config.DistanceMultiplierMax then
                        distanceMult = Config.DistanceMultiplierMax
                    end
                end
                
                local drugRecoilMult = LocalPlayer.state.drugRecoilMult or 1.0
                local skillMult = 1.0

                if GetResourceState('vms_gym') == 'started' then
                    local shootingSkill = exports['vms_gym']:getSkill('shooting') or 0.0
                    local maxReduction = (Config.MaxRecoilReductionFromSkill or 30.0) / 100.0
                    local reduction = (shootingSkill / 100.0) * maxReduction

                    skillMult = 1.0 - reduction
                end

                local totalMultiplier = Config.GlobalRecoilMultiplier * fppMultiplier * moveMultiplier * vehicleMultiplier * sprayMult * distanceMult * drugRecoilMult * skillMult
                
                local aimStyle = Entity(ped).state.aim_style
                local weaponGroup = GetWeapontypeGroup(currentWeapon)
                local isPistol = (weaponGroup == `GROUP_PISTOL`)

                if (aimStyle == "GangsterAS" or aimStyle == "HillbillyAS") and isPistol then
                    totalMultiplier = totalMultiplier * 3.0
                end
            
                local verticalRecoil = recoilData.vertical * totalMultiplier
                local horizontalRecoil = recoilData.horizontal * totalMultiplier
                local shakeAmount = recoilData.shake * Config.GlobalShakeMultiplier * totalMultiplier
                
                local pitch = GetGameplayCamRelativePitch()
                local heading = GetGameplayCamRelativeHeading()
                
                local randomPitch, randomHeading
                
                if (aimStyle == "GangsterAS" or aimStyle == "HillbillyAS") and isPistol then
                    randomPitch = verticalRecoil + (math.random() * verticalRecoil * 0.25)
                    
                    local direction = (math.random() > 0.5) and -1 or 1
                    
                    randomHeading = (horizontalRecoil * 1.5 + (math.random() * horizontalRecoil * 0.5)) * direction
                else
                    randomPitch = verticalRecoil + (math.random() * verticalRecoil * 0.25)
                    
                    local direction = (math.random() > 0.5) and 1 or -1
                    
                    randomHeading = (horizontalRecoil + (math.random() * horizontalRecoil * 0.25)) * direction
                end
                
                SetGameplayCamRelativePitch(pitch + randomPitch, 1.0)
                SetGameplayCamRelativeHeading(heading + randomHeading)
                
                if shakeAmount > 0 then
                    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', shakeAmount)
                end
            end
        end
        
        Wait(sleep)
    end
end)

local inDriveBy = false
local originalCamMode = 1

CreateThread(function()
    while true do
        local sleep = 500
        local ped = PlayerPedId()

        if IsPedInAnyVehicle(ped, false) then
            sleep = 0
            local playerId = PlayerId()
            local doingDriveby = IsPedDoingDriveby(ped)
                or IsPlayerFreeAiming(playerId)
                or (IsPedArmed(ped, 6) and (IsControlPressed(0, 25) or IsControlPressed(0, 68) or IsControlPressed(0, 69) or IsControlPressed(0, 70) or IsControlPressed(0, 92)))

            if doingDriveby then
                if not inDriveBy then
                    inDriveBy = true
                    local currentCam = GetFollowVehicleCamViewMode()
                    if currentCam ~= 4 then
                        originalCamMode = currentCam
                        SetFollowVehicleCamViewMode(4)
                    end
                else
                    if GetFollowVehicleCamViewMode() ~= 4 then
                        SetFollowVehicleCamViewMode(4)
                    end
                end
            elseif inDriveBy then
                inDriveBy = false
                if GetFollowVehicleCamViewMode() == 4 and originalCamMode ~= 4 then
                    SetFollowVehicleCamViewMode(originalCamMode)
                end
            end
        else
            if inDriveBy then
                inDriveBy = false
            end
        end

        Wait(sleep)
    end
end)
