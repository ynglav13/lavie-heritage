local informationRunning = false
local nearbyInjuredPlayers = {}

local function getInformationState()
    local status, key, state = GetActiveInjuryState()

    if status then
        return status, key, state
    end

    if InjuryClient.visualActive and GetGameTimer() - InjuryClient.visualStartedAt <= 1500 then
        local fallbackKey = InjuryClient.visualStatus == 3 and 'Dead'
            or InjuryClient.visualStatus == 2 and 'Injured'
            or 'Helpup'

        return InjuryClient.visualStatus, fallbackKey, InjuryClient.visualState
    end
end

local function setInformationTimecycle(status)
    local modifier = status == 3 and 'glasses_red' or 'dying'

    if InjuryClient.timecycleActive == modifier then
        return
    end

    SetTimecycleModifier(modifier)
    InjuryClient.timecycleActive = modifier
end

local function showEligibilityNotice(status, state)
    local remaining = GetInjuryRemainingSeconds(state, status)

    if remaining > 0 then
        return
    end

    local key = ('%s:%s:%s'):format(
        tostring(status),
        tostring(state and state.Version or 'legacy'),
        tostring(state and state.EligibleAt or state and state.LeftTime or 0)
    )

    if InjuryClient.eligibilityNotices[key] then
        return
    end

    InjuryClient.eligibilityNotices[key] = true

    if GetResourceState('custom-chat') ~= 'started' then
        return
    end

    if status == 3 then
        exports['custom-chat']:SendClientMessage('Bạn đã đủ điều kiện để hồi sinh. Bạn có thể sử dụng lệnh {FFAE42}/respawnme{FFFFFF}')
    else
        exports['custom-chat']:SendClientMessage('Bạn đã đủ điều kiện để skip EMS. Bạn có thể sử dụng lệnh {FFAE42}/skipems{FFFFFF}')
    end
end

RegisterNetEvent('Injury:client:ShowInformation', function()
    if informationRunning then
        return
    end

    informationRunning = true
    InjuryClient.informationGeneration = InjuryClient.informationGeneration + 1

    local generation = InjuryClient.informationGeneration

    while generation == InjuryClient.informationGeneration do
        local status, _, state = getInformationState()

        if not status then
            break
        end

        setInformationTimecycle(status)
        showEligibilityNotice(status, state)

        if status == 3 then
            local ped = PlayerPedId()
            local maximumHealth = GetEntityMaxHealth(ped)

            if IsPedDeadOrDying(ped, true) or GetEntityHealth(ped) <= 0 then
                SetPlayerStatus(3, true, LocalPlayer.state.DeadthCoords, false, state)
            elseif GetEntityHealth(ped) < maximumHealth then
                SetEntityHealth(ped, maximumHealth)
            end
        end

        EffectUpdate()
        Wait(500)
    end

    informationRunning = false

    if IsPlayerInjuryDowned() then
        TriggerEvent('Injury:client:ShowInformation')
    elseif not InjuryClient.recoveryRunning then
        CleanupInjuryVisuals(not LocalPlayer.state.isBeingHelpedUp)
    end
end)

RegisterNetEvent('Injury:client:CountingTime', function()
    TriggerEvent('Injury:client:ShowInformation')
end)

local function isLocalPlayerStateBag(bagName)
    return bagName == ('player:%s'):format(GetPlayerServerId(PlayerId()))
end

local statusByKey =
{
    Helpup = 1,
    Injured = 2,
    Dead = 3,
}

for key, status in pairs(statusByKey) do
    AddStateBagChangeHandler(key, nil, function(bagName, _, value)
        if not isLocalPlayerStateBag(bagName) then
            return
        end

        if type(value) == 'table' and value.Status == true then
            SetTimeout(0, function()
                SetPlayerStatus(status, true, LocalPlayer.state.DeadthCoords, false, value)
            end)
            return
        end

        SetTimeout(100, function()
            if IsPlayerInjuryDowned() then
                return
            end

            if type(StopInjuryCarryDragForRecovery) == 'function' then
                StopInjuryCarryDragForRecovery()
            end

            if ESX and ESX.SetPlayerData then
                ESX.SetPlayerData('dead', false)
            end

            if not InjuryClient.recoveryRunning then
                CleanupInjuryVisuals(true)
            end
        end)
    end)
end

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do
        Wait(100)
    end

    local status, _, state = GetActiveInjuryState()

    if status then
        SetPlayerStatus(status, true, LocalPlayer.state.DeadthCoords, false, state)
    end
end)

CreateThread(function()
    while true do
        if ESX.IsPlayerLoaded() then
            local localPed = PlayerPedId()
            local localCoords = GetEntityCoords(localPed)
            local nearby = {}

            for _, player in ipairs(GetActivePlayers()) do
                if player ~= PlayerId() then
                    local ped = GetPlayerPed(player)

                    if DoesEntityExist(ped) then
                        local serverId = GetPlayerServerId(player)
                        local state = Player(serverId).state
                        local dead = state.Dead
                        local helpup = state.Helpup
                        local injured = state.Injured
                        local text

                        if dead and dead.Status == true then
                            text = ('(( Nguoi choi nay da chet. /damages %s de xem thuong tich ))'):format(serverId)
                        elseif helpup and helpup.Status == true then
                            text = ('(( Nguoi choi nay dang bi thuong nhe. /helpup %s de keo day | /damages %s de xem thuong tich ))'):format(serverId, serverId)
                        elseif injured and injured.Status == true then
                            text = ('(( Nguoi choi nay dang bi thuong. /damages %s de xem thuong tich ))'):format(serverId)
                        end

                        if text and #(localCoords - GetEntityCoords(ped)) < 10.0 then
                            nearby[#nearby + 1] =
                            {
                                ped = ped,
                                text = text,
                            }
                        end
                    end
                end
            end

            nearbyInjuredPlayers = nearby
        else
            nearbyInjuredPlayers = {}
        end

        Wait(1500)
    end
end)

CreateThread(function()
    while true do
        if #nearbyInjuredPlayers == 0 then
            Wait(1000)
        else
            for index = 1, #nearbyInjuredPlayers do
                local entry = nearbyInjuredPlayers[index]

                if DoesEntityExist(entry.ped) then
                    local coords = GetEntityCoords(entry.ped)

                    DrawText3D(coords.x, coords.y, coords.z + 0.4, entry.text)
                end
            end

            Wait(0)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(3000)
        local playerId = PlayerId()
        local ped = PlayerPedId()

        if DoesEntityExist(ped) and not IsEntityDead(ped) then
            local isInvincible = GetPlayerInvincible(playerId)
            if isInvincible then
                local isDowned = false
                if type(IsPlayerInjuryDowned) == 'function' then
                    isDowned = IsPlayerInjuryDowned()
                end

                local isTreatmentInvincible = InjuryClient and InjuryClient.invincible == true
                local isLocalGod = LocalPlayer.state.isGod == true or LocalPlayer.state.aCoreNoclip == true or LocalPlayer.state.inNoclip == true
                local isCustomizing = LocalPlayer.state.inCustomization == true or LocalPlayer.state.invincible == true

                if not isDowned and not isTreatmentInvincible and not isLocalGod and not isCustomizing then
                    SetPlayerInvincible(playerId, false)
                    SetEntityInvincible(ped, false)
                end
            end
        end
    end
end)
