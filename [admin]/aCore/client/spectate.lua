local isSpectating   = false
local spectateTarget = nil
local savedCoords    = nil

RegisterNetEvent('admincore:startSpectate', function(targetId)
    if isSpectating then
        StopSpectate()
        return
    end

    local targetPlayer = GetPlayerFromServerId(targetId)
    if targetPlayer == -1 then
        TriggerEvent('admincore:notify', 'Không tìm thấy người chơi này (ở quá xa hoặc đã thoát).', 'error')
        return
    end

    local targetPed = GetPlayerPed(targetPlayer)
    if not DoesEntityExist(targetPed) then
        TriggerEvent('admincore:notify', 'Chưa load được ped của người chơi.', 'error')
        return
    end

    isSpectating   = true
    spectateTarget = targetId

    local selfPed = PlayerPedId()
    savedCoords = GetEntityCoords(selfPed)

    -- teleport xuong duoi map doi load map
    local tCoord = GetEntityCoords(targetPed)
    RequestCollisionAtCoord(tCoord.x, tCoord.y, tCoord.z)
    SetEntityVisible(selfPed, false, false)
    SetEntityCollision(selfPed, false, false)
    FreezeEntityPosition(selfPed, true)
    SetEntityCoords(selfPed, tCoord.x, tCoord.y, tCoord.z - 50.0, false, false, false, false)

    -- bat spectate
    Citizen.Wait(500)
    targetPed = GetPlayerPed(targetPlayer)
    NetworkSetInSpectatorMode(true, targetPed)

    TriggerEvent('admincore:notify', 'Đang spectate (góc nhìn thứ 3). Dùng /spec hoặc /aspectate để thoát.', 'info')

    Citizen.CreateThread(function()
        while isSpectating do
            Citizen.Wait(1000)
            local target = GetPlayerFromServerId(spectateTarget)
            if target == -1 or not DoesEntityExist(GetPlayerPed(target)) then
                StopSpectate()
                break
            end
        end
    end)
end)

RegisterNetEvent('admincore:stopSpectate', function()
    if isSpectating then
        StopSpectate()
    end
end)

function StopSpectate()
    isSpectating   = false
    spectateTarget = nil

    -- tat spectate
    NetworkSetInSpectatorMode(false, PlayerPedId())

    local selfPed = PlayerPedId()
    SetEntityVisible(selfPed, true, false)
    SetEntityCollision(selfPed, true, true)
    FreezeEntityPosition(selfPed, false)

    -- tra ve vi tri cu
    if savedCoords then
        SetEntityCoords(selfPed, savedCoords.x, savedCoords.y, savedCoords.z, false, false, false, false)
        savedCoords = nil
    end

    TriggerEvent('admincore:notify', 'Đã thoát spectate.', 'info')
end
