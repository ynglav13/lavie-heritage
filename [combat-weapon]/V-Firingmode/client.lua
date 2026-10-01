local firemode = 0
local rifleGroupHash = GetHashKey("GROUP_RIFLE")
local smgGroupHash = GetHashKey("GROUP_SMG")
local isFiringModeThreadActive = false

local firemode_options =
{
    {
        text = "FULL AUTO", logic = function() end
    },
    {
        text = "SEMI-AUTO", logic = function(ped, weaponHash)

        if IsControlJustPressed(0, 24) then
            Wait(300)
            
            while (IsControlPressed(0, 24) or IsDisabledControlPressed(0, 24)) and GetSelectedPedWeapon(ped) == weaponHash do
                DisablePlayerFiring(PlayerId(), true)
                
                Wait(0)
            end
        end
    end
    },
    {
        text = "SINGLE", logic = function(ped, weaponHash)
        
        if IsControlJustPressed(0, 24) then
            while (IsControlPressed(0, 24) or IsDisabledControlPressed(0, 24)) and GetSelectedPedWeapon(ped) == weaponHash do
                DisablePlayerFiring(PlayerId(), true)
                
                Wait(0)
            end
        end
    end
    },
    {
        text = "SAFETY",
        logic = function()
            
        DisablePlayerFiring(PlayerId(), true)
        
        if IsDisabledControlJustPressed(0, 24) then
            PlaySoundFrontend(-1, "Place_Prop_Fail", "DLC_Dmod_Prop_Editor_Sounds", false)
        end
    end
    }
}

function IsAutomaticWeapon(weaponHash)
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        return false
    end

    if weaponHash == GetHashKey("WEAPON_VF18") then
        return true
    end

    local weaponGroup = GetWeapontypeGroup(weaponHash)
    return weaponGroup == rifleGroupHash or weaponGroup == smgGroupHash
end

function updateHUD()
    local current_mode = firemode_options[firemode + 1]

    SendNUIMessage(
    {
        action = "update",
        text = current_mode.text
    })
end

function firingModeThread()
    updateHUD()

    while isFiringModeThreadActive do
        Wait(0)

        local ped = PlayerPedId()
        local weaponHash = GetSelectedPedWeapon(ped)

        if IsAutomaticWeapon(weaponHash) then
            local current_mode = firemode_options[firemode + 1]

            current_mode.logic(ped, weaponHash)
        else
            isFiringModeThreadActive = false
        end
    end

    SendNUIMessage(
    {
        action = "hide"
    })
end

RegisterKeyMapping("+firingmode_toggle", "Thay Doi Che Do Ban", "keyboard", "O")
RegisterCommand("+firingmode_toggle", function()
    if IsAutomaticWeapon(GetSelectedPedWeapon(PlayerPedId())) then
        firemode = (firemode + 1) % #firemode_options

        PlaySoundFrontend(-1, "Place_Prop_Success", "DLC_Dmod_Prop_Editor_Sounds", false)

        updateHUD()
    end
end, false)

RegisterCommand("-firingmode_toggle", function() end, false)
AddEventHandler('ox_inventory:currentWeapon', function(currentWeapon)
    if currentWeapon then
        local weaponHash = currentWeapon.hash

        if IsAutomaticWeapon(weaponHash) then
            if not isFiringModeThreadActive then
                isFiringModeThreadActive = true

                CreateThread(firingModeThread)
            end
        else
            isFiringModeThreadActive = false
        end
    else
        isFiringModeThreadActive = false
    end
end)
