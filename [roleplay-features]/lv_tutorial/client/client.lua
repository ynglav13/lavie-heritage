local ESX = exports['es_extended']:getSharedObject()
local currentStep = 1
local totalSteps = #Config.Steps
local isTutorialActive = false
local currentZoneId = nil
local currentBlip = nil
local newbiePlayers = {}
local isNewbieTagLoopActive = false
local tutorialHidden = false

local function DrawText3D(x, y, z, text, scale)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)

    if onScreen then
        local textScale = scale or 0.25

        SetTextScale(textScale, textScale)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 255)
        SetTextDropshadow(0, 0, 0, 0, 255)
        SetTextEdge(2, 0, 0, 0, 150)
        SetTextDropShadow()
        SetTextOutline() 
        SetTextCentre(1)

        AddTextComponentString(text)

        DrawText(_x, _y)
    end
end

local function InitNUI()
    if tutorialHidden then
        return
    end

    local stepsData = {}

    for i = 1, totalSteps do
        table.insert(stepsData,
        {
            name = Config.Steps[i].name,
            icon = Config.Steps[i].icon,
            desc = Config.Steps[i].desc
        })
    end

    SendNUIMessage(
    {
        action = "show",
        steps = stepsData,
        currentStep = currentStep
    })
end

local function UpdateNUI()
    if currentStep > totalSteps then
        SendNUIMessage(
        {
            action = "hide"
        })
    else
        SendNUIMessage(
        {
            action = "update",
            currentStep = currentStep
        })
    end
end

local function SetupTargetForStep()
    if currentZoneId then
        exports.ox_target:removeZone(currentZoneId)

        currentZoneId = nil
    end

    if currentBlip then
        RemoveBlip(currentBlip)

        currentBlip = nil
    end

    if currentStep <= totalSteps and not tutorialHidden then
        local stepData = Config.Steps[currentStep]
        
        if stepData.coords then
            SetNewWaypoint(stepData.coords.x, stepData.coords.y)

            currentBlip = AddBlipForCoord(stepData.coords.x, stepData.coords.y, stepData.coords.z)

            SetBlipSprite(currentBlip, 1)
            SetBlipColour(currentBlip, 5)
            SetBlipRoute(currentBlip, true)

            BeginTextCommandSetBlipName("STRING")

            AddTextComponentString("Tutorial: " .. stepData.name)

            EndTextCommandSetBlipName(currentBlip)
        end
        
        if stepData.type == "checkpoint" then
        elseif stepData.type ~= "action" then
            currentZoneId = exports.ox_target:addBoxZone(
            {
                coords = stepData.coords,
                size = stepData.size or vec3(2.0, 2.0, 2.0),
                rotation = 0.0,
                debug = false,
                options =
                {
                    {
                        name = 'tutorial_step_' .. currentStep,
                        icon = stepData.icon,
                        label = stepData.label,
                        distance = 2.5,
                        onSelect = function()
                            exports.lv_notify:Notify(stepData.notify, stepData.notifyType, 5000, "Hướng Dẫn")

                            TriggerServerEvent('lv_tutorial:advanceStep', currentStep)
                        end
                    }
                }
            })
        end
    end
end

local function StartNewbieTagLoop()
    if isNewbieTagLoopActive then
        return
    end

    isNewbieTagLoopActive = true

    CreateThread(function()
        while isNewbieTagLoopActive do
            local waitTime = 500
            local myPed = PlayerPedId()
            local myCoords = GetEntityCoords(myPed)

            for serverId, enabled in pairs(newbiePlayers) do
                if enabled then
                    local playerId = GetPlayerFromServerId(tonumber(serverId))

                    if playerId ~= -1 then
                        local ped = GetPlayerPed(playerId)

                        if DoesEntityExist(ped) then
                            local pedCoords = GetEntityCoords(ped)
                            local drawDistance = Config.NewbieDrawDistance or 25.0

                            if #(myCoords - pedCoords) <= drawDistance then
                                local boneCoords = GetPedBoneCoords(ped, Config.NewbieBone, 0.0, 0.0, 0.0)

                                DrawText3D(boneCoords.x, boneCoords.y, boneCoords.z + 0.4, Config.NewbieText, 0.22)

                                waitTime = 0
                            end
                        end
                    end
                end
            end

            Wait(waitTime)
        end
    end)
end

local function StartTutorialLoop()
    if isTutorialActive or tutorialHidden then
        return
    end

    isTutorialActive = true

    CreateThread(function()
        while isTutorialActive and currentStep <= totalSteps and not tutorialHidden do
            local ped = PlayerPedId()
            local stepData = Config.Steps[currentStep]

            if stepData and stepData.type == "checkpoint" and stepData.coords then
                local pCoords = GetEntityCoords(ped)
                local dist = #(pCoords - stepData.coords)
                local radius = stepData.radius or 3.0
                
                if dist < 50.0 then
                    local m = Config.Marker

                    DrawMarker(m.type, stepData.coords.x, stepData.coords.y, stepData.coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, radius * 2.0, radius * 2.0, 1.0, m.color.r, m.color.g, m.color.b, m.color.a, m.bounce, m.faceCamera, 2, false, nil, nil, false)
                    
                    if dist < radius then
                        exports.lv_notify:Notify(stepData.notify, stepData.notifyType, 5000, "Hướng Dẫn")

                        TriggerServerEvent('lv_tutorial:advanceStep', currentStep)

                        Wait(2000)
                    end
                end
            end
            
            Wait(0)
        end

        isTutorialActive = false
    end)
end

RegisterNetEvent('lv_tutorial:setHidden', function(hidden)
    tutorialHidden = hidden == true

    if tutorialHidden then
        isTutorialActive = false

        SendNUIMessage(
        {
            action = "hide"
        })

        if currentZoneId then
            exports.ox_target:removeZone(currentZoneId)

            currentZoneId = nil
        end

        if currentBlip then
            RemoveBlip(currentBlip)

            currentBlip = nil
        end
    elseif currentStep <= totalSteps then
        InitNUI()

        SetupTargetForStep()

        StartTutorialLoop()
    end
end)

RegisterNetEvent('lv_tutorial:syncNewbieTags')
AddEventHandler('lv_tutorial:syncNewbieTags', function(players)
    newbiePlayers = {}

    for serverId, enabled in pairs(players or {}) do
        if enabled then
            newbiePlayers[tonumber(serverId)] = true
        end
    end

    StartNewbieTagLoop()
end)

RegisterNetEvent('lv_tutorial:setNewbieTag')
AddEventHandler('lv_tutorial:setNewbieTag', function(serverId, enabled)
    serverId = tonumber(serverId)

    if not serverId then
        return
    end

    if enabled then
        newbiePlayers[serverId] = true
    else
        newbiePlayers[serverId] = nil
    end

    StartNewbieTagLoop()
end)

RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function(xPlayer)
    ESX.TriggerServerCallback('lv_tutorial:getStep', function(step)
        currentStep = step

        if currentStep <= totalSteps then
            InitNUI()

            SetupTargetForStep()

            StartTutorialLoop()
        end
    end)
end)

RegisterNetEvent('lv_tutorial:updateStep')
AddEventHandler('lv_tutorial:updateStep', function(newStep)
    currentStep = newStep

    UpdateNUI()

    SetupTargetForStep()
    
    if currentStep <= totalSteps then
        StartTutorialLoop()
    else
        isTutorialActive = false
    end
end)

exports('IsTutorialDone', function()
    return currentStep > totalSteps
end)

AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end

    Wait(1000)

    if ESX.IsPlayerLoaded() then
        ESX.TriggerServerCallback('lv_tutorial:getStep', function(step)
            currentStep = step

            if currentStep <= totalSteps then
                InitNUI()

                SetupTargetForStep()
                
                StartTutorialLoop()
            end
        end)
    end
end)
