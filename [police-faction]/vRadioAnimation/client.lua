local isTalking = false
local prop = 0
local isAnimating = false
local isPreviewing = false
local previewVersion = 0

Config.DisableInVehicle = Config.DisableInVehicle == nil and true or Config.DisableInVehicle
Config.DisableWhenDead = Config.DisableWhenDead == nil and true or Config.DisableWhenDead

Citizen.CreateThread(function()
    if GetResourceState('pma-voice') == 'started' then
        exports['pma-voice']:setDisableRadioAnim(true)
    end

    Citizen.Wait(2000)
    local savedAnimStyle = lib.callback.await('vRadioAnimation:getAnimChoice', false)
    if savedAnimStyle and Config.Anims[savedAnimStyle] then
        Config.CurrentAnim = Config.Anims[savedAnimStyle]
        lib.notify({
            title = '[vRadioAnimation]',
            description = 'Đã load anim radio: ' .. Config.CurrentAnim.name,
            type = 'inform'
        })
    end
end)

AddEventHandler('pma-voice:radioActive', function(state)
    isTalking = state
end)

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local shouldAnimate = isTalking or isPreviewing

        if Config.DisableInVehicle and IsPedInAnyVehicle(ped, false) then
            shouldAnimate = false
        end

        if Config.DisableWhenDead and IsEntityDead(ped) then
            shouldAnimate = false
        end

        if shouldAnimate and not isAnimating then
            isAnimating = true
            startAnimation()
        elseif not shouldAnimate and isAnimating then
            isAnimating = false
            stopAnimation()
        end

        if isAnimating or isTalking then
            Wait(100)
        else
            Wait(500)
        end
    end
end)

function startAnimation()
    CreateThread(function()
        local currentAnim = Config.CurrentAnim
        if not currentAnim then return end

        RequestAnimDict(currentAnim.animDict)
        local propHash
        if currentAnim.prop then
            propHash = type(currentAnim.prop) == 'string' and GetHashKey(currentAnim.prop) or currentAnim.prop
            RequestModel(propHash)
        end

        local waited = 0
        while not HasAnimDictLoaded(currentAnim.animDict) or (propHash and not HasModelLoaded(propHash)) do
            Wait(50)
            waited = waited + 50
            if waited > 3000 then
                isAnimating = false
                lib.notify({
                    title = 'Lỗi Radio Anim',
                    description = 'Thiếu file anim/prop: ' .. currentAnim.animDict,
                    type = 'error'
                })
                return
            end
        end

        if not isAnimating then
            return
        end

        local ped = PlayerPedId()
        if DoesEntityExist(prop) then
            DetachEntity(prop, true, false)
            DeleteEntity(prop)
            prop = 0
        end

        if currentAnim.prop and currentAnim.AttachArguments then
            prop = CreateObject(propHash, 0.0, 0.0, 0.0, true, true, false)
            AttachEntityToEntity(
                prop, ped,
                GetPedBoneIndex(ped, currentAnim.AttachArguments.Bone or 28422),
                currentAnim.AttachArguments.xPos or 0.0,
                currentAnim.AttachArguments.yPos or 0.0,
                currentAnim.AttachArguments.zPos or 0.0,
                currentAnim.AttachArguments.xRot or 0.0,
                currentAnim.AttachArguments.yRot or 0.0,
                currentAnim.AttachArguments.zRot or 0.0,
                true, true, false, true, 1, true
            )
            SetModelAsNoLongerNeeded(propHash)
        end

        local playSpeed = currentAnim.playAnimArgs and currentAnim.playAnimArgs[1] or 8.0
        local playSpeedMultiplier = currentAnim.playAnimArgs and currentAnim.playAnimArgs[2] or -8.0
        local playDuration = currentAnim.playAnimArgs and currentAnim.playAnimArgs[3] or -1
        local playFlag = currentAnim.playAnimArgs and currentAnim.playAnimArgs[4] or 49
        local playPlaybackRate = currentAnim.playAnimArgs and currentAnim.playAnimArgs[5] or 0
        local playLockX = currentAnim.playAnimArgs and currentAnim.playAnimArgs[6] or false
        local playLockY = currentAnim.playAnimArgs and currentAnim.playAnimArgs[7] or false
        local playLockZ = currentAnim.playAnimArgs and currentAnim.playAnimArgs[8] or false

        TaskPlayAnim(ped, currentAnim.animDict, currentAnim.animAnim, playSpeed, playSpeedMultiplier, playDuration, playFlag, playPlaybackRate, playLockX, playLockY, playLockZ)
    end)
end

function stopAnimation(animData)
    local ped = PlayerPedId()
    local currentAnim = animData or Config.CurrentAnim
    if not currentAnim then return end

    RequestAnimDict(currentAnim.animDict)
    local waited = 0
    while not HasAnimDictLoaded(currentAnim.animDict) and waited < 1000 do
        Wait(50)
        waited = waited + 50
    end

    local stopBlendOut = currentAnim.stopAnimArgs and currentAnim.stopAnimArgs[1] or 2.0
    StopAnimTask(ped, currentAnim.animDict, currentAnim.animAnim, stopBlendOut)
    if DoesEntityExist(prop) then
        DetachEntity(prop, true, false)
        DeleteEntity(prop)
        prop = 0
    end
end

local function previewAnimation(oldAnim)
    previewVersion = previewVersion + 1
    local currentPreview = previewVersion

    if isAnimating then
        stopAnimation(oldAnim)
    end

    isPreviewing = true
    isAnimating = true
    startAnimation()

    CreateThread(function()
        Wait(Config.PreviewDuration or 2000)
        if previewVersion == currentPreview then
            isPreviewing = false
        end
    end)
end

function openAnimMenu()
    local options = {}
    for _, key in ipairs(Config.AnimOrder) do
        local animData = Config.Anims[key]
        table.insert(options, {
            title = animData.name,
            description = key,
            onSelect = function()
                local oldAnim = Config.CurrentAnim
                Config.CurrentAnim = Config.Anims[key]
                
                TriggerServerEvent('vRadioAnimation:saveAnimChoice', key)

                lib.notify({
                    title = '[vRadioAnimation]',
                    description = 'Bạn đã chọn và lưu anim: ' .. Config.CurrentAnim.name,
                    type = 'success'
                })

                previewAnimation(oldAnim)
            end
        })
    end

    lib.registerContext({
        id = 'vradio_anim_menu',
        title = 'Chọn hoạt ảnh radio',
        options = options
    })

    lib.showContext('vradio_anim_menu')
end

RegisterCommand('animradio', function()
    openAnimMenu()
end, false)

AddEventHandler('onClientResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        stopAnimation()
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'pma-voice' then
        exports['pma-voice']:setDisableRadioAnim(true)
    end
end)
