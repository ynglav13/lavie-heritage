local workStack = 0
local lastActivityTime = 0

function TriggerStressEvent(minStress, maxStress, chance, isDirtyJob)
    if not Config.StressSystem or not Config.StressSystem.Enabled then
        return
    end

    local roll = math.random(1, 100)

    if roll > (chance or 30) then
        return
    end

    local now = GetGameTimer()
    local resetDelayMs = (Config.StressSystem.ResetStackAfterInactive or 30) * 1000

    if lastActivityTime > 0 and (now - lastActivityTime) > resetDelayMs then
        workStack = 0
    end

    local maxStack = Config.StressSystem.StackMax or 10

    workStack = math.min(workStack + 1, maxStack)

    lastActivityTime = now

    local multStep = Config.StressSystem.StackMultiplierPerLevel or 0.15
    local multiplier = 1.0 + ((workStack - 1) * multStep)

    local base = math.random(minStress or 1, maxStress or 3)
    local finalAmount = math.floor((base * multiplier) + 0.5)

    if finalAmount > 0 then
        TriggerServerEvent('lv_status:server:addStress', finalAmount)
    end
end

function AddJobStress(isDirty)
    if not Config.StressSystem or not Config.StressSystem.Jobs.Enabled then
        return
    end

    local cfg = isDirty and Config.StressSystem.Jobs.Dirty or Config.StressSystem.Jobs.Clean

    TriggerStressEvent(cfg.MinStress, cfg.MaxStress, cfg.Chance, isDirty)
end

exports('AddJobStress', AddJobStress)
exports('TriggerJobStress', AddJobStress)

RegisterNetEvent('lv_status:client:addJobStress', function(isDirty)
    AddJobStress(isDirty == true)
end)

CreateThread(function()
    local lastHealth = nil
    local lastArmour = nil

    while true do
        Wait(1500)

        if Config.StressSystem and Config.StressSystem.Enabled and Config.StressSystem.Combat.Enabled then
            local ped = PlayerPedId()

            if DoesEntityExist(ped) and not IsEntityDead(ped) then
                local currentHealth = GetEntityHealth(ped)
                local currentArmour = GetPedArmour(ped)
                local damagedByPed = HasEntityBeenDamagedByAnyPed(ped)

                local tookDamage = lastHealth ~= nil
                    and damagedByPed
                    and (currentHealth < lastHealth or currentArmour < lastArmour)

                lastHealth = currentHealth
                lastArmour = currentArmour

                ClearEntityLastDamageEntity(ped)

                if tookDamage then
                    local cfg = Config.StressSystem.Combat

                    TriggerStressEvent(cfg.MinStress, cfg.MaxStress, cfg.Chance, false)

                    Wait(cfg.CheckIntervalMs or 2500)
                end
            else
                lastHealth = nil
                lastArmour = nil
            end
        else
            lastHealth = nil
            lastArmour = nil
        end
    end
end)

CreateThread(function()
    while true do
        Wait(2000)

        if Config.StressSystem and Config.StressSystem.Enabled and Config.StressSystem.Speeding.Enabled then

            local ped = PlayerPedId()

            if DoesEntityExist(ped) and IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)

                if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
                    local speedMph = GetEntitySpeed(veh) * 2.236936
                    local cfg = Config.StressSystem.Speeding

                    if speedMph >= (cfg.MinSpeedMph or 60.0) then
                        TriggerStressEvent(cfg.MinStress, cfg.MaxStress, cfg.Chance, false)

                        Wait(cfg.CheckIntervalMs or 4000)
                    end
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(5000)

        if workStack > 0 and lastActivityTime > 0 then
            local now = GetGameTimer()
            local resetDelayMs = (Config.StressSystem.ResetStackAfterInactive or 30) * 1000

            if(now - lastActivityTime) > resetDelayMs then
                workStack = 0
            end
        end
    end
end)
