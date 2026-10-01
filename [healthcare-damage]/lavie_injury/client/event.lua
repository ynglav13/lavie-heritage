local function currentRecoveryPayload(mode, health, coords, heading)
    local ped = PlayerPedId()
    local currentCoords = GetEntityCoords(ped)

    return
    {
        ok = true,
        action = mode,
        coords = coords or
        {
            x = currentCoords.x,
            y = currentCoords.y,
            z = currentCoords.z,
        },
        heading = tonumber(heading) or GetEntityHeading(ped),
        health = tonumber(health) or GetEntityMaxHealth(ped),
        armor = GetPedArmour(ped),
    }
end

local function tryLegacyRecovery(payload)
    CreateThread(function()
        Wait(100)

        if not AwaitCanonicalInjuryClear(1000) then
            return
        end

        ApplyInjuryRecovery(payload)
    end)
end

RegisterNetEvent('Injury:client:SetPlayerStatus', function(status, enabled, deathCoords, forceStatus, stateData)
    SetPlayerStatus(status, enabled, deathCoords, forceStatus, stateData)
end)

RegisterNetEvent('lavie_injury:client:applyRecovery', function(payload)
    ApplyInjuryRecovery(payload)
end)

RegisterNetEvent('lavie_injury:client:revive', function()
    tryLegacyRecovery(currentRecoveryPayload('revive'))
end)

RegisterNetEvent('lavie_injury:client:helpupStandUp', function()
    tryLegacyRecovery(currentRecoveryPayload('helpup', 130))
end)

RegisterNetEvent('esx_ambulancejob:revive', function()
    tryLegacyRecovery(currentRecoveryPayload('revive'))
end)

RegisterNetEvent('admincore:revive', function()
    tryLegacyRecovery(currentRecoveryPayload('revive'))
end)

RegisterNetEvent('lavie_injury:client:forceRespawnMe', function()
    tryLegacyRecovery(currentRecoveryPayload(
        'respawn',
        GetEntityMaxHealth(PlayerPedId()),
        InjuryConfig.RespawnMe.Coords,
        InjuryConfig.RespawnMe.Heading
    ))
end)

RegisterNetEvent('Injury:client:ShowHelpUpProgress', function(duration, label)
    InjuryClient.progressActive = true

    lib.progressBar(
    {
        duration = math.max(0, tonumber(duration) or 0),
        label = label or 'Đang Xử Lý...',
        useWhileDead = true,
        canCancel = false,
        disable =
        {
            move = true,
            car = true,
            combat = true,
        }
    })

    InjuryClient.progressActive = false

    if not IsPlayerInjuryDowned() and not (LocalPlayer.state.cuffed or (ESX and ESX.PlayerData and ESX.PlayerData.cuffed)) then
        InventoryBusy(false)
        LocalPlayer.state:set('invBusy', false, false)
    end
end)

RegisterNetEvent('Injury:client:ReceiveHelpUpRequest', function(helperIdOrName, helperName)
    if not helperName and type(helperIdOrName) == 'string' then
        helperName = helperIdOrName
    end

    local alert = exports['lv_notify']:Confirm(
    {
        title = 'Yêu cầu',
        message = ('%s muốn kéo bạn đứng dậy. Bạn có đồng ý không?'):format(tostring(helperName or 'Một người chơi')),
        yesLabel = 'Đồng Ý',
        noLabel = 'Từ Chối'
    })

    if alert then
        TriggerNetEvent('Injury:server:ConfirmHelpUp')
    else
        TriggerNetEvent('Injury:server:RefuseHelpUp')
    end
end)
