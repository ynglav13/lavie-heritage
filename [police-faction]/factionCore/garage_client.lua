local NUI = {}





RegisterNetEvent('VehicleFaction:client:ShowVehicleMenu', function(garageId, type)
    ESX.TriggerServerCallback('VehicleFaction:server:GetGarageData', function(cb)
        NUI:ShowFactionVehicle(cb, garageId, type)
    end, 'garage'..garageId, LocalPlayer.state.factionTag, type)
end)

function NUI:ShowFactionVehicle(data, garageId, type)
    SetNuiFocus(true, true)
    SendNUIMessage({
        display = true,
        edit = 'garageSpawn',
        reset = true,
        clear = true,
    })

    if #data == 0 then
        SendNUIMessage({
            display = true,
            edit = 'garageSpawn',
            reset = true,
            garageId = garageId,
            nomore = true, 
        })
    end

    local count = false
    local idd = 0  
    for i, v in pairs(data) do
        if v.status == type then
            count = true
            idd = idd + 1
            SendNUIMessage({
                idd = idd,
                display = true,
                edit = 'garageSpawn',
                results = true,
                type = type,
                id = v.id,
                garageId = garageId,
                lastDriver = v.lastDriver,
                status = v.status,
                model = v.name,
                plate = v.plate,
            })
        end
    end
    if not count then
        SendNUIMessage({
            display = true,
            edit = 'garageSpawn',
            reset = true,
            garageId = garageId,
            nomore = true, 
            type = type,
        })
    end
end

RegisterNUICallback('SelectVehicleMenu', function(data, cb)
    SendNUIMessage({
        clear = true,
    })
    TriggerEvent('VehicleFaction:client:ShowVehicleMenu', data.garageId, data.type)
end)

RegisterNUICallback('Clicked', function(data, cb)
    local playerId = GetPlayerServerId(PlayerId())
    SendNUIMessage({
        display = false,
        clear = true,
    })
    SetNuiFocus(false, false)

    if data.status == '0' then
        ESX.TriggerServerCallback('VehicleFaction:server:GetFactionVehicle', function(callback)
            if callback ~= nil then
                local vehicle = callback
                local allVehicles = ESX.Game.GetVehicles()
                local vehicleAvailable = true
                local targetPlate = string.upper(string.match(vehicle.plate, "^%s*(.-)%s*$"))
                for i, v in ipairs(allVehicles) do
                    local currentPlate = GetVehicleNumberPlateText(v)
                    if currentPlate then
                        local cleanCurrent = string.upper(string.match(currentPlate, "^%s*(.-)%s*$"))
                        if cleanCurrent == targetPlate then
                            vehicleAvailable = false
                            break
                        end
                    end
                end
                if vehicleAvailable then
                    local coords = GetEntityCoords(PlayerPedId())
                    local heading = GetEntityHeading(PlayerPedId())
                    local model = type(vehicle.name) == 'number' and vehicle.name or joaat(vehicle.name)
                    
                    CreateThread(function()
                        local vehicleColour = json.decode(vehicle.colour)
                        local customColorPrimary = nil
                        local customColorSecondary = nil

                        if vehicleColour and vehicleColour.chooseColor then
                            local colorInput = lib.inputDialog('Tùy chỉnh màu xe', {
                                { type = 'color', label = 'Màu sơn chính (Primary)', default = '#ffffff' },
                                { type = 'color', label = 'Màu sơn phụ (Secondary)', default = '#ffffff' }
                            })
                            
                            if colorInput then
                                if colorInput[1] then
                                    local hex = colorInput[1]:gsub("#","")
                                    if #hex == 6 then
                                        customColorPrimary = {
                                            r = tonumber("0x"..hex:sub(1,2)),
                                            g = tonumber("0x"..hex:sub(3,4)),
                                            b = tonumber("0x"..hex:sub(5,6))
                                        }
                                    end
                                end
                                if colorInput[2] then
                                    local hex = colorInput[2]:gsub("#","")
                                    if #hex == 6 then
                                        customColorSecondary = {
                                            r = tonumber("0x"..hex:sub(1,2)),
                                            g = tonumber("0x"..hex:sub(3,4)),
                                            b = tonumber("0x"..hex:sub(5,6))
                                        }
                                    end
                                end
                            end
                        end

                        ESX.Streaming.RequestModel(model)
                        local vehResults = CreateVehicle(model, coords.x, coords.y, coords.z, heading, true, false)
                        
                        local networkId = NetworkGetNetworkIdFromEntity(vehResults)
                        SetNetworkIdCanMigrate(networkId, true)
                        SetEntityAsMissionEntity(vehResults, true, false)
                        if vehResults ~= 0 then
                            Entity(vehResults).state:set('vehiclePersistIgnore', true, true)
                            Entity(vehResults).state:set('FactionVehicle', tostring(vehicle.type or LocalPlayer.state.factionTag or 'FACTION'):upper(), true)
                        end
                        SetVehicleHasBeenOwnedByPlayer(vehResults, true)
                        SetVehicleNeedsToBeHotwired(vehResults, false)
                        SetModelAsNoLongerNeeded(model)
                        
                        ESX.Game.SetVehicleProperties(vehResults, {
                            plate = vehicle.plate,
                            engineHealth = 1000.0,
                            bodyHealth = 1000.0,
                            tankHealth = 1000.0
                        })
                        
                        SetVehicleFixed(vehResults)
                        SetVehicleDeformationFixed(vehResults)
                        SetVehicleDirtLevel(vehResults, 0.0)

                        Entity(vehResults).state:set('Locked', false, true)
                        Entity(vehResults).state:set('PlayerVehicle', true, true)
                        Entity(vehResults).state:set('fuel', 100.0, true)
                        SetVehicleDoorsLocked(vehResults, 1)

                        SetVehicleModKit(vehResults, 0)
                        local maxEngine = GetNumVehicleMods(vehResults, 11) - 1
                        local maxBrakes = GetNumVehicleMods(vehResults, 12) - 1
                        local maxTrans = GetNumVehicleMods(vehResults, 13) - 1
                        local maxSusp = GetNumVehicleMods(vehResults, 15) - 1

                        local vMod = vehicle.tuner_data and json.decode(vehicle.tuner_data) or nil
                        if vMod and type(vMod) == 'table' and next(vMod) ~= nil then
                            if vMod.modEngine or vMod.model then
                                ESX.Game.SetVehicleProperties(vehResults, vMod)
                            else
                                if vMod.exhaust     and vMod.exhaust    ~= -1 then SetVehicleMod(vehResults, 4, vMod.exhaust) end
                            if vMod.frame       and vMod.frame      ~= -1 then SetVehicleMod(vehResults, 5, vMod.frame) end
                            if vMod.bumper_f    and vMod.bumper_f   ~= -1 then SetVehicleMod(vehResults, 1, vMod.bumper_f) end
                            if vMod.bumper_r    and vMod.bumper_r   ~= -1 then SetVehicleMod(vehResults, 2, vMod.bumper_r) end
                            if vMod.xeon_light  and vMod.xeon_light ~= -1 then
                                ToggleVehicleMod(vehResults, 22, true)
                                SetVehicleHeadlightsColour(vehResults, vMod.xeon_light_id)
                            end
                            if vMod.plate       and vMod.plate      ~= -1 then  SetVehicleNumberPlateTextIndex(vehResults, vMod.plate) end

                            if vMod.hood        and vMod.hood       ~= -1 then  SetVehicleMod(vehResults, 7, vMod.hood) end
                            if vMod.horn        and vMod.horn       ~= -1 then  SetVehicleMod(vehResults, 14, vMod.horn) end
                            if vMod.roof        and vMod.roof       ~= -1 then  SetVehicleMod(vehResults, 10, vMod.roof) end
                            if vMod.skirts      and vMod.skirts     ~= -1 then  SetVehicleMod(vehResults, 3, vMod.skirts) end
                            if vMod.spoiler     and vMod.spoiler    ~= -1 then  SetVehicleMod(vehResults, 0, vMod.spoiler) end

                            if vMod.grille      and vMod.grille     ~= -1 then  SetVehicleMod(vehResults, 6, vMod.grille) end
                            if vMod.fenders     and vMod.fenders    ~= -1 then  SetVehicleMod(vehResults, 8, vMod.fenders) end

                            if vMod.plateholders    and vMod.plateholders   ~= -1 then  SetVehicleMod(vehResults, 25, vMod.plateholders) end
                            if vMod.vanityplate     and vMod.vanityplate    ~= -1 then  SetVehicleMod(vehResults, 26, vMod.vanityplate) end
                            if vMod.trimdesign      and vMod.trimdesign     ~= -1 then  SetVehicleMod(vehResults, 27, vMod.trimdesign) end
                            if vMod.ornaments       and vMod.ornaments      ~= -1 then  SetVehicleMod(vehResults, 28, vMod.ornaments) end
                            if vMod.dashboard       and vMod.dashboard      ~= -1 then  SetVehicleMod(vehResults, 29, vMod.dashboard) end
                            if vMod.dialdesign      and vMod.dialdesign     ~= -1 then  SetVehicleMod(vehResults, 30, vMod.dialdesign) end
                            if vMod.doorspeaker     and vMod.doorspeaker    ~= -1 then  SetVehicleMod(vehResults, 31, vMod.doorspeaker) end
                            if vMod.seats           and vMod.seats          ~= -1 then  SetVehicleMod(vehResults, 32, vMod.seats) end
                            if vMod.steeringwheel   and vMod.steeringwheel  ~= -1 then  SetVehicleMod(vehResults, 33, vMod.steeringwheel) end
                            if vMod.shifterleavers  and vMod.shifterleavers ~= -1 then  SetVehicleMod(vehResults, 34, vMod.shifterleavers) end
                            if vMod.plaques         and vMod.plaques        ~= -1 then  SetVehicleMod(vehResults, 35, vMod.plaques) end
                            if vMod.speakers        and vMod.speakers       ~= -1 then  SetVehicleMod(vehResults, 36, vMod.speakers) end

                            if vMod.engineblock  and vMod.engineblock   ~= -1 then  SetVehicleMod(vehResults, 39, vMod.engineblock) end
                            if vMod.airfilter    and vMod.airfilter     ~= -1 then  SetVehicleMod(vehResults, 40, vMod.airfilter) end
                            if vMod.struts       and vMod.struts        ~= -1 then  SetVehicleMod(vehResults, 41, vMod.struts) end
                            if vMod.archcover    and vMod.archcover     ~= -1 then  SetVehicleMod(vehResults, 42, vMod.archcover) end
                            if vMod.aerials      and vMod.aerials       ~= -1 then  SetVehicleMod(vehResults, 43, vMod.aerials) end
                            if vMod.trim         and vMod.trim          ~= -1 then  SetVehicleMod(vehResults, 44, vMod.trim) end
                            if vMod.tank         and vMod.tank          ~= -1 then  SetVehicleMod(vehResults, 45, vMod.tank) end
                            if vMod.windowsframe and vMod.windowsframe  ~= -1 then  SetVehicleMod(vehResults, 46, vMod.windowsframe) end

                            if vMod.modLivery ~= nil then
                                SetVehicleMod(vehResults, 48, vMod.modLivery, false)
                            end
                            
                            if vMod.livery ~= nil then
                                SetVehicleLivery(vehResults, vMod.livery)
                            end

                            local neon_light = vMod.neon_light
                            if neon_light and (neon_light.left or neon_light.right or neon_light.front or neon_light.back) then
                                SetVehicleNeonLightsColour(vehResults, neon_light.color[1], neon_light.color[2], neon_light.color[3])
                                if neon_light.left  then SetVehicleNeonLightEnabled(vehResults, 0, true) end
                                if neon_light.right then SetVehicleNeonLightEnabled(vehResults, 1, true) end
                                if neon_light.front then SetVehicleNeonLightEnabled(vehResults, 2, true) end
                                if neon_light.back  then SetVehicleNeonLightEnabled(vehResults, 3, true) end
                            end

                            local tire_smoke = vMod.tire_smoke
                            if tire_smoke then
                                ToggleVehicleMod(vehResults, 20, tire_smoke.status or false)
                                if tire_smoke.status then
                                    SetVehicleTyreSmokeColor(vehResults, tire_smoke.color[1], tire_smoke.color[2], tire_smoke.color[3])
                                end
                            end

                            if vMod.brakes and vMod.brakes ~= -1 then
                                SetVehicleMod(vehResults, 12, vMod.brakes, false)
                            elseif maxBrakes >= 0 then
                                SetVehicleMod(vehResults, 12, maxBrakes, false)
                            end

                            if vMod.engine and vMod.engine ~= -1 then
                                SetVehicleMod(vehResults, 11, vMod.engine, false)
                            elseif maxEngine >= 0 then
                                SetVehicleMod(vehResults, 11, maxEngine, false)
                            end

                            if vMod.suspension and vMod.suspension ~= -1 then
                                SetVehicleMod(vehResults, 15, vMod.suspension, false)
                            end

                            if vMod.transmission and vMod.transmission ~= -1 then
                                SetVehicleMod(vehResults, 13, vMod.transmission, false)
                            elseif maxTrans >= 0 then
                                SetVehicleMod(vehResults, 13, maxTrans, false)
                            end

                            if vMod.turbo ~= nil then
                                ToggleVehicleMod(vehResults, 18, vMod.turbo)
                            else
                                ToggleVehicleMod(vehResults, 18, true)
                            end
                        
                            if vMod.window_tint then SetVehicleWindowTint(vehResults, vMod.window_tint) end
                                
                            local wheels = vMod.wheels
                            if wheels and wheels.type then
                                SetVehicleWheelType(vehResults, wheels.type)
                                SetVehicleMod(vehResults, 23, wheels.value)
                                SetVehicleExtraColours(vehResults, wheels.pearlescent, wheels.color)
                            end
                            end
                        else
                            Wait(200)
                            SetVehicleModKit(vehResults, 0)
                            print("[FactionGarage Debug] Engine Mods count:", GetNumVehicleMods(vehResults, 11), "Selected Mod Index:", maxEngine)
                            if maxEngine >= 0 then SetVehicleMod(vehResults, 11, maxEngine, false) end
                            if maxBrakes >= 0 then SetVehicleMod(vehResults, 12, maxBrakes, false) end
                            if maxTrans >= 0 then SetVehicleMod(vehResults, 13, maxTrans, false) end
                            ToggleVehicleMod(vehResults, 18, true)
                        end
                        
                        SetVehicleModKit(vehResults, 0)
                        if maxEngine >= 0 then SetVehicleMod(vehResults, 11, maxEngine, false) end
                        if maxBrakes >= 0 then SetVehicleMod(vehResults, 12, maxBrakes, false) end
                        if maxTrans >= 0 then SetVehicleMod(vehResults, 13, maxTrans, false) end
                        ToggleVehicleMod(vehResults, 18, true)

                        SetVehicleEnginePowerMultiplier(vehResults, 2.0)

                        ESX.TriggerServerCallback('FactionVehicle:server:UpdateStatusSpawn', function(callback)
                            local windows = callback.windows and json.decode(callback.windows) or {}
                            local actualPlate = GetVehicleNumberPlateText(vehResults)
                            
                            TaskWarpPedIntoVehicle(PlayerPedId() , vehResults, -1)

                            if LocalPlayer.state.factionCategory == 'police' then
                                if vehicle.name == 'polmav' then
                                    SetVehicleLivery(vehResults, 0)
                                elseif vehicle.name == 'vvpi' then
                                    SetVehicleLivery(vehResults, 0)
                                end
                            end

                            local vehicleColour = json.decode(vehicle.colour)

                            if customColorPrimary or customColorSecondary then
                                if customColorPrimary then
                                    SetVehicleCustomPrimaryColour(vehResults, customColorPrimary.r, customColorPrimary.g, customColorPrimary.b)
                                else
                                    if vehicleColour.r and vehicleColour.g and vehicleColour.b then
                                        SetVehicleCustomPrimaryColour(vehResults, tonumber(vehicleColour.r), tonumber(vehicleColour.g), tonumber(vehicleColour.b))
                                    end
                                end
                                
                                if customColorSecondary then
                                    SetVehicleCustomSecondaryColour(vehResults, customColorSecondary.r, customColorSecondary.g, customColorSecondary.b)
                                else
                                    if vehicleColour.r and vehicleColour.g and vehicleColour.b then
                                        SetVehicleCustomSecondaryColour(vehResults, tonumber(vehicleColour.r), tonumber(vehicleColour.g), tonumber(vehicleColour.b))
                                    end
                                end
                            else
                                if vehicleColour.r and vehicleColour.g and vehicleColour.b then
                                    SetVehicleCustomPrimaryColour(vehResults, tonumber(vehicleColour.r), tonumber(vehicleColour.g), tonumber(vehicleColour.b))
                                    SetVehicleCustomSecondaryColour(vehResults, tonumber(vehicleColour.r), tonumber(vehicleColour.g), tonumber(vehicleColour.b))
                                else
                                    SetVehicleColours(vehResults, vehicleColour.primaryColour or 131, vehicleColour.secondColour or 0)
                                end
                            end

                            Wait(500)
                            for i, v in ipairs(windows) do 
                                if v.status == 1 then FixVehicleWindow(vehResults, v.id) end
                            end
                            TriggerServerEvent("FactionData:server:UpdateData", GetPlayerServerId(PlayerId()))
                        end, vehicle.plate, playerId)
                        
                    end)
                end
            end
        end, data.plate)
    elseif data.status == '1' then
        local allVehicles = ESX.Game.GetVehicles()
        local vehicleId = nil
        local targetPlate = string.upper(string.match(data.plate, "^%s*(.-)%s*$"))
        for i, v in ipairs(allVehicles) do
            local currentPlate = GetVehicleNumberPlateText(v)
            if currentPlate then
                local cleanCurrent = string.upper(string.match(currentPlate, "^%s*(.-)%s*$"))
                if cleanCurrent == targetPlate then
                    vehicleId = v
                    break
                end
            end
        end
        Wait(200)
        if vehicleId then
            local vehicleProps = ESX.Game.GetVehicleProperties(vehicleId)
            ESX.TriggerServerCallback('VehicleFaction:server:Despawn', function(callback)
                if callback then
                    CreateThread(function()
                        local ped = PlayerPedId()
                        if IsPedInAnyVehicle(ped, false) then
                            local currentVeh = GetVehiclePedIsIn(ped, false)
                            if currentVeh == vehicleId then
                                TaskLeaveVehicle(ped, vehicleId, 0)
                                Wait(2000)
                            end
                        end

                        if DoesEntityExist(vehicleId) then
                            NetworkRequestControlOfEntity(vehicleId)
                            local timeout = 2000
                            while not NetworkHasControlOfEntity(vehicleId) and timeout > 0 do
                                Wait(10)
                                timeout = timeout - 10
                            end

                            SetEntityCollision(vehicleId, false, false)
                            SetVehicleDoorsLocked(vehicleId, 2)
                            
                            for alpha = 255, 0, -15 do
                                if DoesEntityExist(vehicleId) then
                                    SetEntityAlpha(vehicleId, alpha, false)
                                    Wait(30)
                                else
                                    break
                                end
                            end
                        end
                        TriggerServerEvent('VehicleFaction:server:DeleteEntityGracefully', data.plate)
                        TriggerServerEvent("FactionData:server:UpdateData", GetPlayerServerId(PlayerId()))
                    end)
                end
            end, data.plate, vehicleProps)
        end
    end
    cb('ok')
end)


function ReloadFactionGarage(garageId, type)
    ESX.TriggerServerCallback('VehicleFaction:server:GetGarageData', function(cb)
        NUI:ShowFactionVehicle(cb, garageId, type)
    end, 'garage'..garageId, LocalPlayer.state.factionTag, type)
end

RegisterNetEvent('FactionVehicle:client:AddVehicleToNUI', function(data)
    SendNUIMessage({
        display = true,
        reset = false,
        results = true,
        plate = data.plate,
        model = data.model,
        garageId = data.garageId or 0,
        status = data.status or 0,
        lastDriver = data.lastDriver or "Chưa sử dụng",
        type = data.type or 0
    })
end)

RegisterNetEvent("FactionVehicle:client:OpenLSPDMenu", function()
    OpenFactionVehicleMenu('LSPD', 'Danh sách xe LSPD', 'lspd_vehicle_list')
end)

RegisterNetEvent("FactionVehicle:client:OpenLSSDMenu", function()
    OpenFactionVehicleMenu('LSSD', 'Danh sách xe LSSD', 'lssd_vehicle_list')
end)

function OpenFactionVehicleMenu(factionTag, menuTitle, menuId)
    factionTag = factionTag or 'LSPD'
    local callbackName = factionTag == 'LSSD' and 'FactionVehicle:server:GetLSSDVehicles' or 'FactionVehicle:server:GetLSPDVehicles'
    ESX.TriggerServerCallback(callbackName, function(vehicles)
        local menuOptions = {}

        table.insert(menuOptions, {
            title = 'Thêm xe mới',
            icon = 'plus',
            onSelect = function()
                AddVehiclePrompt(factionTag)
            end
        })

        if vehicles and #vehicles > 0 then
            for _, v in pairs(vehicles) do
                table.insert(menuOptions, {
                    title = v.plate,
                    description = 'Model: ' .. v.name,
                    icon = 'car',
                    onSelect = function()
                        ConfirmDeleteVehicle(v.plate, v.name, factionTag)
                    end
                })
            end
        end

        lib.registerContext({
            id = menuId,
            title = menuTitle,
            options = menuOptions
        })

        lib.showContext(menuId)
    end)
end

function AddVehiclePrompt(factionTag)
    factionTag = factionTag or 'LSPD'
    local defaultPlate = factionTag == 'LSSD' and 'LSSD001' or 'LSPD001'
    local input = lib.inputDialog(('Thêm xe vào %s'):format(factionTag), {
        {type = 'input', label = 'Model xe', placeholder = 'police3', required = true},
        {type = 'input', label = 'Biển số', placeholder = defaultPlate, required = true}
    })

    if not input then return end

    local model = input[1]
    local plate = input[2]

    ESX.TriggerServerCallback('FactionVehicle:server:AddVehicle', function(result)
        if result == true or (type(result) == "table" and result.success) then
            lib.notify({type = 'success', description = ('Đã thêm xe mới vào %s!'):format(factionTag)})
            ReloadFactionGarage(0, 0)
        elseif type(result) == "table" and result.reason == "plate_exists" then
            lib.notify({type = 'error', description = 'Biển số đã tồn tại! Vui lòng chọn biển khác.'})
        else
            lib.notify({type = 'error', description = 'Không thể thêm xe.'})
        end
    end, {
        model = model,
        plate = plate,
        tag = factionTag
    })
end

function ConfirmDeleteVehicle(plate, model, factionTag)
    factionTag = factionTag or 'LSPD'
    local yes = lib.alertDialog({
        header = 'Xác nhận xóa xe',
        content = ('Bạn có chắc muốn xóa xe %s (%s)?'):format(model, plate),
        centered = true,
        cancel = true
    })

    if yes == 'confirm' then
        ESX.TriggerServerCallback('FactionVehicle:server:DeleteVehicle', function(result)
            if result.success then
                lib.notify({type = 'success', description = 'Xe đã bị xoá.'})
                if factionTag == 'LSSD' then
                    TriggerEvent("FactionVehicle:client:OpenLSSDMenu")
                else
                    TriggerEvent("FactionVehicle:client:OpenLSPDMenu")
                end
            elseif result.reason == 'vehicle_in_use' then
                lib.notify({type = 'error', description = 'Không thể xoá xe khi đang có người lái!'})
            else
                lib.notify({type = 'error', description = 'Xảy ra lỗi khi xoá xe.'})
            end
        end, plate, factionTag)
    end
end


RegisterNetEvent('VehicleFaction:client:ForceLeave', function(netId)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle and DoesEntityExist(vehicle) then
        local ped = PlayerPedId()
        if GetVehiclePedIsIn(ped, false) == vehicle then
            TaskLeaveVehicle(ped, vehicle, 0)
        end
    end
end)
