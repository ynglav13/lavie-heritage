local helpupAnimation =
{
    dict = 'missheist_agency3amcs_4a',
    helper = 'help_standup_player1',
    target = 'help_standup_crew2'
}

local animationStates = {
    helper = {
        active = false,
        animation = helpupAnimation.helper
    },
    target = {
        active = false,
        animation = helpupAnimation.target
    }
}
local freezeOwnership = {}

local function loadAnimationDictionary(dictionary)
    if HasAnimDictLoaded(dictionary) then
        return true
    end

    RequestAnimDict(dictionary)

    local timeoutAt = GetGameTimer() + 5000

    while not HasAnimDictLoaded(dictionary) do
        if GetGameTimer() >= timeoutAt then
            return false
        end

        Wait(10)
    end

    return true
end

local function facePlayer(serverId)
    local player = GetPlayerFromServerId(tonumber(serverId) or -1)

    if player == -1 then
        return false
    end

    local targetPed = GetPlayerPed(player)

    if not DoesEntityExist(targetPed) then
        return false
    end

    local targetCoords = GetEntityCoords(targetPed)
    local playerCoords = GetEntityCoords(PlayerPedId())
    SetEntityHeading(PlayerPedId(), GetHeadingFromVector_2d(targetCoords.x - playerCoords.x, targetCoords.y - playerCoords.y))
    return true
end

local function acquireFreeze(state, ped)
    local ownership = freezeOwnership[ped]

    if not ownership then
        local wasFrozen = IsEntityPositionFrozen(ped) == true
        ownership = {
            references = 0,
            owned = not wasFrozen
        }
        freezeOwnership[ped] = ownership

        if ownership.owned then
            FreezeEntityPosition(ped, true)
        end
    end

    ownership.references = ownership.references + 1
    state.freezePed = ped
end

local function releaseFreeze(state)
    local ped = state.freezePed
    local ownership = ped and freezeOwnership[ped]
    state.freezePed = nil

    if not ownership then
        return
    end

    ownership.references = math.max(ownership.references - 1, 0)

    if ownership.references > 0 then
        return
    end

    freezeOwnership[ped] = nil

    if ownership.owned and DoesEntityExist(ped) and IsEntityPositionFrozen(ped) then
        FreezeEntityPosition(ped, false)
    end
end

local function stopAnimation(role)
    local state = animationStates[role]

    if not state or not state.active then
        return
    end

    state.active = false

    if state.ped and DoesEntityExist(state.ped) then
        StopAnimTask(state.ped, helpupAnimation.dict, state.animation, 3.0)
    end

    state.ped = nil
    releaseFreeze(state)

    if role == 'target' then
        LocalPlayer.state:set('isBeingHelpedUp', false, false)
    end
end

local function startAnimation(role, targetId)
    local state = animationStates[role]

    if not state then
        return false
    end

    stopAnimation(role)

    if not facePlayer(targetId) or not loadAnimationDictionary(helpupAnimation.dict) then
        return false
    end

    local ped = PlayerPedId()
    state.active = true
    state.ped = ped

    ClearPedTasksImmediately(ped)
    acquireFreeze(state, ped)
    TaskPlayAnim(ped, helpupAnimation.dict, state.animation, 8.0, -8.0, -1, 0, 0.0, false, false, false)

    if role == 'target' then
        LocalPlayer.state:set('isBeingHelpedUp', true, false)
    end

    return true
end

local function setHelperAnimation(status, targetId)
    if not status then
        stopAnimation('helper')
        return
    end

    startAnimation('helper', targetId)
end

local function setTargetAnimation(status, targetId)
    if not status then
        stopAnimation('target')
        return
    end

    startAnimation('target', targetId)
end

RegisterNetEvent('lavie_injury:client:SetHelpUpAnimation', setHelperAnimation)
RegisterNetEvent('lavie_bodydamages:client:SetHelpUpAnimation', setHelperAnimation)
RegisterNetEvent('lavie_injury:client:SetHelpUpAnimation2', setTargetAnimation)
RegisterNetEvent('lavie_bodydamages:client:SetHelpUpAnimation2', setTargetAnimation)

RegisterNetEvent('BodyDamages:client:HelpUpPlayer', function()
    LocalPlayer.state:set('CanHelpUp', false, false)
end)

RegisterNetEvent('BodyDamages:client:RemoveHelpUp', function()
    LocalPlayer.state:set('CanHelpUp', false, false)
end)

RegisterNetEvent('Injury:client:RemoveHelpUp', function()
    LocalPlayer.state:set('CanHelpUp', false, false)
end)

local function setPlayerHelpUp(enabled)
    LocalPlayer.state:set('CanHelpUp', enabled == true, false)
end

RegisterNetEvent('lavie_injury:client:SetPlayerHelpUp', setPlayerHelpUp)
RegisterNetEvent('lavie_bodydamages:client:SetPlayerHelpUp', setPlayerHelpUp)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    stopAnimation('helper')
    stopAnimation('target')
end)
