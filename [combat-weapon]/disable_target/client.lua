local Wait = Citizen.Wait
local PlayerPedId = PlayerPedId
local PlayerId = PlayerId
local DoesEntityExist = DoesEntityExist
local IsPedInAnyVehicle = IsPedInAnyVehicle
local IsPedSwimming = IsPedSwimming
local IsPedArmed = IsPedArmed
local GetSelectedPedWeapon = GetSelectedPedWeapon
local GetWeapontypeGroup = GetWeapontypeGroup
local SetPlayerLockon = SetPlayerLockon
local SetPlayerLockonRangeOverride = SetPlayerLockonRangeOverride
local SetPlayerTargetingMode = SetPlayerTargetingMode
local DisableControlAction = DisableControlAction
local IsPlayerFreeAiming = IsPlayerFreeAiming
local IsControlPressed = IsControlPressed
local IsDisabledControlPressed = IsDisabledControlPressed
local SetPedToRagdoll = SetPedToRagdoll
local IsPedRagdoll = IsPedRagdoll

local meleeWeaponGroup = `GROUP_MELEE`

local function DisableMeleeComboControls()
    DisableControlAction(0, 140, true)
    DisableControlAction(0, 141, true)
    DisableControlAction(0, 142, true)
    DisableControlAction(0, 263, true)
    DisableControlAction(0, 264, true)
end

Citizen.CreateThread(function()
    local playerId = PlayerId()

    while true do
        local sleep = 0
        local ped = PlayerPedId()

        if DoesEntityExist(ped) then
            local inVehicle = IsPedInAnyVehicle(ped, false)
            local isSwimming = IsPedSwimming(ped)

            local selectedWeapon = GetSelectedPedWeapon(ped)
            local isMeleeWeapon = IsPedArmed(ped, 1) or GetWeapontypeGroup(selectedWeapon) == meleeWeaponGroup

            if selectedWeapon == `WEAPON_UNARMED` then
                SetPlayerLockon(playerId, true)
            else
                SetPlayerLockon(playerId, false)
                SetPlayerLockonRangeOverride(playerId, 0.0)
                SetPlayerTargetingMode(3)
            end

            if IsPedArmed(ped, 6) and not isMeleeWeapon then
                sleep = 0
                DisableMeleeComboControls()
            end
        else
            sleep = 500
        end

        Wait(sleep)
    end
end)

Citizen.CreateThread(function()
    while true do
        local sleep = 250
        local ped = PlayerPedId()

        if DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) and not IsPedSwimming(ped) then
            if IsPedArmed(ped, 4) then
                sleep = 0
               
                if IsControlPressed(0, 22) and (
                    IsControlPressed(0, 24) or IsDisabledControlPressed(0, 24) or
                    IsControlPressed(0, 25) or IsDisabledControlPressed(0, 25) or
                    IsPlayerFreeAiming(PlayerId())
                ) then
                    Wait(1000)
                    local currentPed = PlayerPedId()
                    if DoesEntityExist(currentPed) and not IsPedInAnyVehicle(currentPed, false) and not IsPedRagdoll(currentPed) then
                        SetPedToRagdoll(currentPed, 5000, 5000, 0, true, true, false)
                    end
                    Wait(5000)
                end
            end
        end

        Wait(sleep)
    end
end)


