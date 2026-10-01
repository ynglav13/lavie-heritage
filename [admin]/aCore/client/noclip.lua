local noclipActive = false
local noclipSpeed  = 1.0

local function GetCamDirection()
    local rot = GetGameplayCamRot(2)
    local pitch = math.rad(rot.x)
    local heading = math.rad(rot.z)

    local dirX = -math.sin(heading) * math.cos(pitch)
    local dirY = math.cos(heading) * math.cos(pitch)
    local dirZ = math.sin(pitch)

    local rightX = math.cos(heading)
    local rightY = math.sin(heading)

    return dirX, dirY, dirZ, rightX, rightY, rot.z
end

RegisterNetEvent('admincore:toggleNoclip', function()
    noclipActive = not noclipActive
    LocalPlayer.state:set('aCoreNoclip', noclipActive, true)

    local ped = PlayerPedId()
    local entity = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or ped

    if noclipActive then
        SetEntityCollision(entity, false, false)
        SetEntityVisible(entity, false, false)
        SetEntityInvincible(entity, true)
        SetEveryoneIgnorePlayer(ped, true)
        SetPoliceIgnorePlayer(ped, true)
        TriggerEvent('admincore:notify', 'Noclip: BẬT | Shift=Nhanh | Ctrl=Chậm | Q/E=Lên/Xuống', 'success')
    else
        SetEntityCollision(entity, true, true)
        SetEntityVisible(entity, true, false)
        SetEntityInvincible(entity, false)
        SetEveryoneIgnorePlayer(ped, false)
        SetPoliceIgnorePlayer(ped, false)
        
        -- reset velocity tranh mat mau
        SetEntityVelocity(entity, 0.0, 0.0, 0.0)
        TriggerEvent('admincore:notify', 'Noclip: TẮT', 'info')
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        if noclipActive then
            local ped    = PlayerPedId()
            local entity = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or ped
            local coords = GetEntityCoords(entity)

            -- khoa di chuyen khi mo chat/menu
            DisableControlAction(0, 32, true) -- W
            DisableControlAction(0, 33, true) -- S
            DisableControlAction(0, 34, true) -- A
            DisableControlAction(0, 35, true) -- D
            DisableControlAction(0, 21, true) -- Shift
            DisableControlAction(0, 36, true) -- Ctrl
            DisableControlAction(0, 44, true) -- Q
            DisableControlAction(0, 46, true) -- E
            DisableControlAction(0, 22, true) -- Space

            local speed = 1.0
            if IsDisabledControlPressed(0, 21) then speed = 5.0 end
            if IsDisabledControlPressed(0, 36) then speed = 0.2 end

            local dirX, dirY, dirZ, rightX, rightY, camHeading = GetCamDirection()
            local dx, dy, dz = 0.0, 0.0, 0.0

            if IsDisabledControlPressed(0, 32) then -- W
                dx = dx + dirX * speed
                dy = dy + dirY * speed
                dz = dz + dirZ * speed
            end
            if IsDisabledControlPressed(0, 33) then -- S
                dx = dx - dirX * speed
                dy = dy - dirY * speed
                dz = dz - dirZ * speed
            end
            if IsDisabledControlPressed(0, 34) then -- A
                dx = dx - rightX * speed
                dy = dy - rightY * speed
            end
            if IsDisabledControlPressed(0, 35) then -- D
                dx = dx + rightX * speed
                dy = dy + rightY * speed
            end
            if IsDisabledControlPressed(0, 44) then -- Q
                dz = dz - speed
            end
            if IsDisabledControlPressed(0, 46) then -- E
                dz = dz + speed
            end

            -- update coords
            SetEntityVelocity(entity, 0.0, 0.0, 0.0)
            SetEntityCoordsNoOffset(entity, coords.x + dx, coords.y + dy, coords.z + dz, true, true, true)
            SetEntityHeading(entity, camHeading)
        else
            Citizen.Wait(200)
        end
    end
end)
