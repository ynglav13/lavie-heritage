local CarryDrag =
{
    active = false,
    role = nil,
    mode = nil,
    targetId = nil,
    carrierId = nil,
    hinted = false,
    lockedHeading = nil,
    stopRequested = false,
}

local function notify(type, title, description)
    local self = GetSelf()

    if GetResourceState('lv_notify') == 'started' then
        exports['lv_notify']:Notify(
        {
            type = type == 'hint' and 'warning' or type,
            title = title,
            message = description,
            duration = 6000,
        })
    elseif vlib then
        vlib:Notify(self.id, 6000, type, title, description)
    elseif lib then
        lib.notify(
        {
            type = type,
            title = title,
            description = description
        })
    end
end

local function showDropHint(mode)
    if CarryDrag.hinted then
        return
    end

    local modeConfig = InjuryConfig.CarryDrag.Modes[mode]
    local label = modeConfig and modeConfig.label or 'bế/kéo'

    CarryDrag.hinted = true

    notify('hint', 'Hướng Dẫn', ('Bấm X hoặc /dropbody để thả người đang được %s'):format(label))
end

local function isDownedState(state)
    return state and state.Status
end

local function isLocalDowned()
    return isDownedState(LocalPlayer.state.Helpup) or isDownedState(LocalPlayer.state.Injured) or isDownedState(LocalPlayer.state.Dead)
end

local function isTargetDowned(serverId)
    local state = Player(serverId).state
    return isDownedState(state.Helpup) or isDownedState(state.Injured) or isDownedState(state.Dead)
end

local function loadAnimDict(dict)
    if HasAnimDictLoaded(dict) then
        return true
    end

    RequestAnimDict(dict)

    local timeout = GetGameTimer() + 5000

    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > timeout then
            return false
        end

        Wait(10)
    end
    return true
end

local function playLoopedAnim(ped, anim)
    if not loadAnimDict(anim.dict) then
        return false
    end

    if not IsEntityPlayingAnim(ped, anim.dict, anim.anim, 3) then
        TaskPlayAnim(ped, anim.dict, anim.anim, 8.0, -8.0, -1, anim.flag or 49, 0.0, false, false, false)
    end
    return true
end

local function playTimedAnim(ped, anim, name, duration)
    if not name or not duration or duration <= 0 then
        return false
    end

    if not loadAnimDict(anim.dict) then
        return false
    end

    TaskPlayAnim(ped, anim.dict, name, 2.0, 2.0, duration, 1, 0.0, false, false, false)
    return true
end

local function disableControlForGroups(control)
    DisableControlAction(0, control, true)
    DisableControlAction(1, control, true)
    DisableControlAction(2, control, true)
end

local function disableDragMovementControls()
    disableControlForGroups(21)
    disableControlForGroups(22)
    disableControlForGroups(30)
    disableControlForGroups(31)
    disableControlForGroups(32)
    disableControlForGroups(33)
    disableControlForGroups(34)
    disableControlForGroups(35)
end

local function getBackwardVectorFromHeading(heading)
    local radians = math.rad(heading)
    return vector3(math.sin(radians), -math.cos(radians), 0.0)
end

local findPlayerByServerId

local function stopLocalCarryDrag(keepTasks)
    local ped = PlayerPedId()
    local dropCoords = nil

    if CarryDrag.role == 'target' then
        dropCoords = GetEntityCoords(ped)
    end

    CarryDrag.active = false
    CarryDrag.role = nil
    CarryDrag.mode = nil
    CarryDrag.targetId = nil
    CarryDrag.carrierId = nil
    CarryDrag.hinted = false
    CarryDrag.lockedHeading = nil

    if IsEntityAttached(ped) then
        DetachEntity(ped, true, false)
    end

    SetEntityCollision(ped, true, true)

    if dropCoords then
        local foundGround, groundZ = GetGroundZFor_3dCoord(dropCoords.x, dropCoords.y, dropCoords.z + 1.0, false)
        local z = foundGround and groundZ or dropCoords.z

        SetEntityCoordsNoOffset(ped, dropCoords.x, dropCoords.y, z, false, false, false)

    end

    if not keepTasks then
        ClearPedTasksImmediately(ped)

        local HelpupState = LocalPlayer.state.Helpup
        local InjuryState = LocalPlayer.state.Injured
        local DeadState   = LocalPlayer.state.Dead

        if (HelpupState and HelpupState.Status) or (InjuryState and InjuryState.Status) or (DeadState and DeadState.Status) then
            CreateThread(function()
                local dict, anim = 'missarmenian2', 'corpse_search_exit_ped'

                if loadAnimDict(dict) then
                    ClearPedTasksImmediately(ped)

                    TaskPlayAnim(ped, dict, anim, 8.0, 8.0, -1, 1, 1, false, false, false)
                end
            end)
        end
    end
end

local function requestServerStop(keepTasks)
    local wasActive = CarryDrag.active or LocalPlayer.state.InjuryCarryDrag ~= nil

    if wasActive and not CarryDrag.stopRequested then
        CarryDrag.stopRequested = true
        TriggerNetEvent('Injury:server:CarryDrag:Stop')
    end

    stopLocalCarryDrag(keepTasks)
end

function StopInjuryCarryDrag(reportServer, keepTasks)
    if reportServer then
        requestServerStop(keepTasks)
    else
        stopLocalCarryDrag(keepTasks)
    end
end

function StopInjuryCarryDragForRecovery()
    if CarryDrag.active and CarryDrag.role == 'target' then
        requestServerStop(true)
    end
end

function IsInjuryCarryDragTarget()
    return CarryDrag.active and CarryDrag.role == 'target'
end

local function getClosestValidTarget()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local maxDistance = InjuryConfig.CarryDrag.Distance
    local closestId, closestDistance

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local serverId = GetPlayerServerId(player)
            local ped = GetPlayerPed(player)

            if DoesEntityExist(ped) and isTargetDowned(serverId) then
                local distance = #(playerCoords - GetEntityCoords(ped))

                if distance <= maxDistance and (not closestDistance or distance < closestDistance) then
                    closestId = serverId
                    closestDistance = distance
                end
            end
        end
    end
    return closestId
end

findPlayerByServerId = function(serverId)
    for _, player in ipairs(GetActivePlayers()) do
        if GetPlayerServerId(player) == serverId then
            return player
        end
    end
    return nil
end

local function requestMode(mode, targetId)
    if not InjuryConfig.CarryDrag.Enabled then
        return
    end

    if CarryDrag.active or LocalPlayer.state.InjuryCarryDrag then
        requestServerStop()
        return
    end

    if isLocalDowned() then
        return notify('error', 'Không Thể Thực Hiện', 'Bạn đang bị thương/chết nên không thể bế hoặc kéo người khác')
    end

    targetId = tonumber(targetId) or getClosestValidTarget()

    if not targetId or targetId == GetPlayerServerId(PlayerId()) then
        return notify('error', 'Không Thể Thực Hiện', 'Không tìm thấy người bị thương ở gần')
    end

    if not isTargetDowned(targetId) then
        return notify('error', 'Không Thể Thực Hiện', 'Người chơi này không ở trạng thái bị thương/chết')
    end

    local targetPlayer = findPlayerByServerId(targetId)

    if not targetPlayer then
        return notify('error', 'Không Thể Thực Hiện', 'Người chơi không ở gần bạn')
    end

    local distance = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(GetPlayerPed(targetPlayer)))

    if distance > InjuryConfig.CarryDrag.Distance then
        return notify('error', 'Không Thể Thực Hiện', 'Bạn không ở gần người chơi này')
    end

    TriggerNetEvent('Injury:server:CarryDrag:Request', targetId, mode)
end

RegisterNetEvent('Injury:client:CarryDrag:StartCarrier', function(targetId, mode)
    local modeConfig = InjuryConfig.CarryDrag.Modes[mode]

    if not modeConfig then
        return
    end

    stopLocalCarryDrag(true)

    CarryDrag.stopRequested = false
    CarryDrag.active = true
    CarryDrag.role = 'carrier'
    CarryDrag.mode = mode
    CarryDrag.targetId = targetId
    CarryDrag.lockedHeading = mode == 'drag' and GetEntityHeading(PlayerPedId()) or nil

    showDropHint(mode)

    CreateThread(function()
        local introEndsAt = 0

        if mode == 'drag' and modeConfig.carrier.intro then
            introEndsAt = GetGameTimer() + (modeConfig.carrier.introDuration or 5700)

            playTimedAnim(PlayerPedId(), modeConfig.carrier, modeConfig.carrier.intro, modeConfig.carrier.introDuration or 5700)
        end

        while CarryDrag.active and CarryDrag.role == 'carrier' and CarryDrag.targetId == targetId do
            local ped = PlayerPedId()

            DisableControlAction(0, 21, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisablePlayerFiring(PlayerId(), true)

            if mode == 'drag' then
                disableDragMovementControls()

                if CarryDrag.lockedHeading then
                    SetEntityHeading(ped, CarryDrag.lockedHeading)
                end
            end

            if IsPedInAnyVehicle(ped, false) or isLocalDowned() or not isTargetDowned(targetId) then
                requestServerStop()
                break
            end

            if GetGameTimer() < introEndsAt then
                if CarryDrag.lockedHeading then
                    SetEntityHeading(ped, CarryDrag.lockedHeading)
                end
            elseif mode == 'drag' and IsDisabledControlPressed(0, 33) and CarryDrag.lockedHeading then
                local coords = GetEntityCoords(ped)
                local backward = getBackwardVectorFromHeading(CarryDrag.lockedHeading)
                local speed = (InjuryConfig.CarryDrag.BackpedalSpeed or 1.05) * GetFrameTime()

                if CarryDrag.lockedHeading then
                    SetEntityHeading(ped, CarryDrag.lockedHeading)
                end

                SetEntityCoordsNoOffset(
                    ped,
                    coords.x + backward.x * speed,
                    coords.y + backward.y * speed,
                    coords.z,
                    true,
                    true,
                    true
                )
                playLoopedAnim(ped, modeConfig.carrier)
            else
                playLoopedAnim(ped, modeConfig.carrier)
            end

            if IsControlJustPressed(0, InjuryConfig.CarryDrag.Controls.Drop) then
                requestServerStop()
                break
            end

            Wait(0)
        end
    end)
end)

RegisterNetEvent('Injury:client:CarryDrag:StartTarget', function(carrierId, mode)
    local modeConfig = InjuryConfig.CarryDrag.Modes[mode]

    if not modeConfig then
        return
    end

    stopLocalCarryDrag(true)

    CarryDrag.stopRequested = false
    CarryDrag.active = true
    CarryDrag.role = 'target'
    CarryDrag.mode = mode
    CarryDrag.carrierId = carrierId

    CreateThread(function()
        local introEndsAt = 0

        if mode == 'drag' and modeConfig.target.intro then
            introEndsAt = GetGameTimer() + (modeConfig.target.introDuration or 5700)

            playTimedAnim(PlayerPedId(), modeConfig.target, modeConfig.target.intro, modeConfig.target.introDuration or 5700)
        end

        while CarryDrag.active and CarryDrag.role == 'target' and CarryDrag.carrierId == carrierId do
            local ped = PlayerPedId()
            local carrierPlayer = findPlayerByServerId(carrierId)

            if not isLocalDowned() then
                requestServerStop(true)
                break
            end

            if not carrierPlayer then
                requestServerStop()
                break
            end

            local carrierPed = GetPlayerPed(carrierPlayer)

            if not DoesEntityExist(carrierPed) or IsPedInAnyVehicle(carrierPed, false) then
                requestServerStop()
                break
            end

            SetEntityCollision(ped, false, false)

            local attach = modeConfig.target.attach
            local boneIndex = 0

            if attach.bone and attach.bone ~= 0 then
                boneIndex = GetPedBoneIndex(carrierPed, attach.bone)
            end

            if not IsEntityAttachedToEntity(ped, carrierPed) then
                AttachEntityToEntity(
                    ped,
                    carrierPed,
                    boneIndex,
                    attach.offset.x,
                    attach.offset.y,
                    attach.offset.z,
                    attach.rotation.x,
                    attach.rotation.y,
                    attach.rotation.z,
                    false,
                    false,
                    false,
                    false,
                    2,
                    true
                )
            end

            if GetGameTimer() >= introEndsAt then
                playLoopedAnim(ped, modeConfig.target)
            end

            DisablePlayerFiring(PlayerId(), true)

            Wait(250)
        end

        SetEntityCollision(PlayerPedId(), true, true)
    end)
end)

RegisterNetEvent('Injury:client:CarryDrag:Stop', function(keepTasks)
    stopLocalCarryDrag(keepTasks)
    CarryDrag.stopRequested = false
end)

RegisterCommand(InjuryConfig.CarryDrag.Commands.Carry, function(_, args)
    requestMode('carry', args[1])
end)

RegisterCommand(InjuryConfig.CarryDrag.Commands.Drag, function(_, args)
    requestMode('drag', args[1])
end)

RegisterCommand(InjuryConfig.CarryDrag.Commands.Drop, function()
    if CarryDrag.active or LocalPlayer.state.InjuryCarryDrag then
        requestServerStop()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        stopLocalCarryDrag()
    end
end)

exports('IsCarryDragActive', function()
    return CarryDrag.active
end)

exports('GetCarryDragRole', function()
    return CarryDrag.active and CarryDrag.role or nil
end)

exports('GetCarryDragTarget', function()
    return (CarryDrag.active and CarryDrag.role == 'carrier') and CarryDrag.targetId or nil
end)

exports('IsPlayerCarried', function()
    return CarryDrag.active and CarryDrag.role == 'target'
end)
