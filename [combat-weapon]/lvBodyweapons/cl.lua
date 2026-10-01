ESX = exports["es_extended"]:getSharedObject()

local preview = {
    weaponName   =   nil,
    boneName     =   nil,
    bone         =   nil,
    weapon       =   nil,
    weaponItem   =   nil,
    object       =   nil
}

local adjust = {
    editMode = false,
    x   =   0.0,
    y   =   0.0,
    z   =   0.0,
    rx  =   0.0,
    ry  =   0.0,
    rz  =   0.0,
    tol =   0.001,
}

local playerWeaponConfig = {}
local spawnedObjects = {}
local initialHeading = 0.0
local coordsChanged = false
local weaponActiveComponents = {}
local stateUpdateVersion = 0
local saveRequestVersion = 0
local saveInProgress = false
local nextPreviewRetryAt = 0

local function deleteSpawnedWeapons(serverId)
    local weapons = spawnedObjects[serverId]
    if not weapons then return end

    for weaponName, obj in pairs(weapons) do
        if DoesEntityExist(obj) then
            DeleteEntity(obj)
        end
        weapons[weaponName] = nil
    end
end

local function spawnWeaponObject(weaponName, ped)
    if not weaponName or not DoesEntityExist(ped) then return nil end

    local weaponHash = GetHashKey(weaponName)
    
    if not HasWeaponAssetLoaded(weaponHash) then
        RequestWeaponAsset(weaponHash, 31, 0)
        local deadline = GetGameTimer() + Config.Editor.previewAssetTimeout
        while not HasWeaponAssetLoaded(weaponHash) and GetGameTimer() < deadline do
            Wait(10)
        end
    end
    
    if not HasWeaponAssetLoaded(weaponHash) then return nil end
    
    local coords = GetEntityCoords(ped)
    local weaponObj = CreateWeaponObject(weaponHash, 50, coords.x, coords.y, coords.z, true, 1.0, 0)
    if not DoesEntityExist(weaponObj) then return nil end
    
    SetEntityAsMissionEntity(weaponObj, true, true)
    SetEntityCollision(weaponObj, false, false)
    SetEntityCompletelyDisableCollision(weaponObj, false, false)
    FreezeEntityPosition(weaponObj, true)
    
    local inventory = exports.ox_inventory:GetPlayerItems()
    local weaponSlot = nil
    if inventory then
        for _, item in pairs(inventory) do
            if item.name == weaponName then
                weaponSlot = item
                break
            end
        end
    end
    
    if weaponSlot then
        local weaponUpper = weaponName:upper()
        if weaponUpper:sub(1, 7) == "WEAPON_" then
            local weaponBaseName = weaponUpper:sub(8)
            local defaultClip = "COMPONENT_" .. weaponBaseName .. "_CLIP_01"
            GiveWeaponComponentToWeaponObject(weaponObj, GetHashKey(defaultClip))
        end

        if weaponSlot.metadata and weaponSlot.metadata.components then
            for _, compName in pairs(weaponSlot.metadata.components) do
                local compList = nil
                if type(compName) == 'string' then
                    local compItem = exports.ox_inventory:Items(compName)
                    if compItem and compItem.client and compItem.client.component then
                        compList = compItem.client.component
                    else
                        compList = { compName }
                    end
                elseif type(compName) == 'table' then
                    compList = compName.component or compName
                else
                    compList = { compName }
                end
                
                if compList then
                    if type(compList) ~= 'table' then compList = { compList } end
                    for v = 1, #compList do
                        local componentValue = compList[v]
                        local compHash = type(componentValue) == 'string' and GetHashKey(componentValue) or math.floor(tonumber(componentValue) or 0)
                        if compHash ~= 0 then
                            GiveWeaponComponentToWeaponObject(weaponObj, compHash)
                        end
                    end
                end
            end
        end
        
        if weaponSlot.metadata then
            local magComp = nil
            if weaponSlot.metadata.originalMagInfo and weaponSlot.metadata.originalMagInfo.component then
                magComp = weaponSlot.metadata.originalMagInfo.component
            elseif weaponSlot.metadata.magazine and weaponSlot.metadata.magazine.component then
                magComp = weaponSlot.metadata.magazine.component
            elseif weaponSlot.metadata.magComponent then
                magComp = weaponSlot.metadata.magComponent
            end
            
            if magComp then
                local compHash = type(magComp) == 'string' and GetHashKey(magComp) or math.floor(tonumber(magComp) or 0)
                if compHash ~= 0 then
                    GiveWeaponComponentToWeaponObject(weaponObj, compHash)
                end
            end
        end
        
        if weaponSlot.metadata and weaponSlot.metadata.tint then
            SetWeaponObjectTintIndex(weaponObj, weaponSlot.metadata.tint)
        end
    end
    
    return weaponObj
end

function startEditMode(isReAdjusting)
    if not isReAdjusting then
        adjust.x, adjust.y, adjust.z = 0.0, 0.0, 0.0
        adjust.rx, adjust.ry, adjust.rz = 0.0, 0.0, 0.0
    end

    if DoesEntityExist(preview.object) then
        DeleteEntity(preview.object)
        preview.object = nil
    end

    local ped = PlayerPedId()
    initialHeading = GetEntityHeading(ped)
    adjust.editMode = true
    saveInProgress = false
    nextPreviewRetryAt = 0
    preview.object = spawnWeaponObject(preview.weaponItem, ped)
    if preview.object then
        AttachEntityToEntity(preview.object, ped, GetPedBoneIndex(ped, preview.bone), adjust.x, adjust.y, adjust.z, adjust.rx, adjust.ry, adjust.rz, true, false, false, false, 2, true)
    else
        nextPreviewRetryAt = GetGameTimer() + Config.Editor.previewRetryDelay
        exports['lv_notify']:lv_notify('Preview đang tải, hệ thống sẽ tự thử lại.', 'warning', 3500, 'Hệ thống')
    end

    RequestAnimDict("missfam5_yoga")
    local animTimeout = 100
    while not HasAnimDictLoaded("missfam5_yoga") and animTimeout > 0 do
        Wait(10)
        animTimeout = animTimeout - 1
    end
    if HasAnimDictLoaded("missfam5_yoga") then
        TaskPlayAnim(ped, "missfam5_yoga", "a2_pose", 8.0, -8.0, -1, 50, 0, false, false, false)
    end
    
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'showEditor',
        weaponLabel = preview.weaponName,
        boneLabel = preview.boneName,
        coords = {
            x = adjust.x,
            y = adjust.y,
            z = adjust.z,
            rx = adjust.rx,
            ry = adjust.ry,
            rz = adjust.rz
        },
        bones = Config.Bones,
        editorConfig = Config.Editor
    })
end

local function openDashboard()
    local inventory = {}
    local rawInv = exports.ox_inventory:GetPlayerItems()
    
    if rawInv then
        for _, item in pairs(rawInv) do
            for i = 1, #Config.WeaponList do
                if item.name == Config.WeaponList[i].label then
                    table.insert(inventory, {
                        name = Config.WeaponList[i].label,
                        label = Config.WeaponList[i].name
                    })
                    break
                end
            end
        end
    end

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'showDashboard',
        inventory = inventory,
        configs = playerWeaponConfig,
        bones = Config.Bones
    })
end

RegisterCommand('bodyweapon', function()
    preview = { weaponName=nil, boneName=nil, bone=nil, weapon=nil, weaponItem=nil, object=nil }
    openDashboard()
end)

function resetAdjust()
    adjust.editMode = false
    saveInProgress = false
    adjust.x, adjust.y, adjust.z  = 0.0, 0.0, 0.0
    adjust.rx, adjust.ry, adjust.rz = 0.0, 0.0, 0.0
    adjust.tol = 0.001
    if DoesEntityExist(preview.object) then
        DeleteEntity(preview.object)
        preview.object = nil
    end
    if initialHeading ~= 0.0 then
        SetEntityHeading(PlayerPedId(), initialHeading)
        initialHeading = 0.0
    end
    ClearPedTasks(PlayerPedId())
end

local function updateAttachedPreview()
    if not adjust.editMode or not DoesEntityExist(preview.object) then return end
    local ped = PlayerPedId()
    AttachEntityToEntity(preview.object, ped, GetPedBoneIndex(ped, preview.bone),
        adjust.x, adjust.y, adjust.z, adjust.rx, adjust.ry, adjust.rz,
        false, false, false, false, 2, true)
end

local function clampEditorValue(value, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return 0.0
    end

    -- JSON values such as 30/90/150 are decoded by Lua 5.4 as integers.
    -- FiveM attachment rotations are float parameters; keeping the integer
    -- subtype made only the float clamp bounds (-180.0/180.0) visibly apply.
    value = value + 0.0
    return math.max(minimum + 0.0, math.min(maximum + 0.0, value)) + 0.0
end

RegisterNUICallback('updateCoords', function(data, cb)
    if not adjust.editMode or saveInProgress then cb('ok') return end

    local limit = Config.Editor.positionHardLimit
    adjust.x = clampEditorValue(data.x, -limit, limit)
    adjust.y = clampEditorValue(data.y, -limit, limit)
    adjust.z = clampEditorValue(data.z, -limit, limit)
    adjust.rx = clampEditorValue(data.rx, Config.Editor.rotationMin, Config.Editor.rotationMax)
    adjust.ry = clampEditorValue(data.ry, Config.Editor.rotationMin, Config.Editor.rotationMax)
    adjust.rz = clampEditorValue(data.rz, Config.Editor.rotationMin, Config.Editor.rotationMax)
    
    coordsChanged = true
    cb('ok')
end)

RegisterNUICallback('changeBone', function(data, cb)
    if not adjust.editMode or saveInProgress then cb('ok') return end

    local selectedBone = nil
    for i = 1, #Config.Bones do
        if Config.Bones[i].name == data.boneKey then
            selectedBone = Config.Bones[i]
            break
        end
    end
    if not selectedBone then cb('invalid_bone') return end

    preview.boneName = selectedBone.label
    preview.bone = selectedBone.value
    
    coordsChanged = true
    cb('ok')
end)

RegisterNUICallback('mouseDrag', function(data, cb)
    if not adjust.editMode or saveInProgress then cb('ok') return end
    
    local dx = tonumber(data.dx) or 0
    local dy = tonumber(data.dy) or 0
    local button = tonumber(data.button) or 0
    local rotSensitivity = 0.5
    
    if button == 0 then
        adjust.rz = adjust.rz + (dx * rotSensitivity)
        if adjust.rz > Config.Editor.rotationMax then adjust.rz = Config.Editor.rotationMin end
        if adjust.rz < Config.Editor.rotationMin then adjust.rz = Config.Editor.rotationMax end
    elseif button == 2 then
        adjust.rx = adjust.rx + (dy * rotSensitivity)
        adjust.ry = adjust.ry + (dx * rotSensitivity)
        
        if adjust.rx > Config.Editor.rotationMax then adjust.rx = Config.Editor.rotationMin end
        if adjust.rx < Config.Editor.rotationMin then adjust.rx = Config.Editor.rotationMax end
        if adjust.ry > Config.Editor.rotationMax then adjust.ry = Config.Editor.rotationMin end
        if adjust.ry < Config.Editor.rotationMin then adjust.ry = Config.Editor.rotationMax end
    end
    
    adjust.x = math.max(-2.0, math.min(2.0, adjust.x))
    adjust.y = math.max(-2.0, math.min(2.0, adjust.y))
    adjust.z = math.max(-2.0, math.min(2.0, adjust.z))

    coordsChanged = true
    
    SendNUIMessage({
        action = 'updateValues',
        coords = {
            x = adjust.x,
            y = adjust.y,
            z = adjust.z,
            rx = adjust.rx,
            ry = adjust.ry,
            rz = adjust.rz
        }
    })
    cb('ok')
end)

RegisterNUICallback('rotatePlayer', function(data, cb)
    local heading = tonumber(data.heading) or 0.0
    local ped = PlayerPedId()
    local targetHeading = (initialHeading + heading) % 360.0
    SetEntityHeading(ped, targetHeading)
    cb('ok')
end)

RegisterNUICallback('saveConfig', function(data, cb)
    if not adjust.editMode or saveInProgress then cb('busy') return end

    if type(data) == 'table' and data.x ~= nil then
        local limit = Config.Editor.positionHardLimit
        adjust.x = clampEditorValue(data.x, -limit, limit)
        adjust.y = clampEditorValue(data.y, -limit, limit)
        adjust.z = clampEditorValue(data.z, -limit, limit)
        adjust.rx = clampEditorValue(data.rx, Config.Editor.rotationMin, Config.Editor.rotationMax)
        adjust.ry = clampEditorValue(data.ry, Config.Editor.rotationMin, Config.Editor.rotationMax)
        adjust.rz = clampEditorValue(data.rz, Config.Editor.rotationMin, Config.Editor.rotationMax)
        updateAttachedPreview()
    end

    saveInProgress = true
    saveRequestVersion = saveRequestVersion + 1
    local requestVersion = saveRequestVersion
    SendNUIMessage({ action = 'saveState', saving = true })
    
    local cleanCoords = {
        x = adjust.x, y = adjust.y, z = adjust.z,
        rx = adjust.rx, ry = adjust.ry, rz = adjust.rz
    }
    local cleanInfo = {
        weapon = preview.weapon,
        weaponName = preview.weaponName,
        bone = preview.bone,
        boneName = preview.boneName,
        weaponItem = preview.weaponItem
    }
    
    ESX.TriggerServerCallback('BodyWeapon:server:AddedBodyWeapon', function(success)
        if requestVersion ~= saveRequestVersion or not saveInProgress then return end
        saveInProgress = false

        if success then
            exports['lv_notify']:lv_notify('Đã lưu cấu hình vị trí.', 'success', 3500, 'Hệ thống')
            SetNuiFocus(false, false)
            SendNUIMessage({ action = 'saveState', saving = false })
            SendNUIMessage({ action = 'hideEditor' })

            -- Apply the confirmed value immediately instead of briefly
            -- rebuilding the old attachment while the DB refresh is pending.
            playerWeaponConfig[cleanInfo.weaponItem] = {
                weapon = cleanInfo.weaponItem,
                coords = json.encode(cleanCoords),
                info = json.encode({
                    name = cleanInfo.weapon,
                    label = cleanInfo.weaponName,
                    bone = cleanInfo.bone,
                    boneName = cleanInfo.boneName,
                    weaponName = cleanInfo.weaponItem
                })
            }
            resetAdjust()
            updateMyBodyWeaponsState()
            deleteSpawnedWeapons(GetPlayerServerId(PlayerId()))
            TriggerEvent('BodyWeapon:client:RefreshWeapons')
        else
            exports['lv_notify']:lv_notify('Lỗi: Không thể lưu cấu hình.', 'error', 3500, 'Hệ thống')
            SendNUIMessage({ action = 'saveState', saving = false })
        end
    end, cleanCoords, cleanInfo)

    SetTimeout(Config.Editor.saveTimeout, function()
        if requestVersion ~= saveRequestVersion or not saveInProgress then return end
        saveInProgress = false
        saveRequestVersion = saveRequestVersion + 1
        SendNUIMessage({ action = 'saveState', saving = false })
        exports['lv_notify']:lv_notify('Lưu quá thời gian chờ, vị trí vẫn được giữ để thử lại.', 'error', 4500, 'Hệ thống')
    end)
    
    cb('ok')
end)

RegisterNUICallback('cancelConfig', function(data, cb)
    saveRequestVersion = saveRequestVersion + 1
    saveInProgress = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideEditor' })
    resetAdjust()
    updateMyBodyWeaponsState()
    deleteSpawnedWeapons(GetPlayerServerId(PlayerId()))
    openDashboard()
    cb('ok')
end)

RegisterNUICallback('closeDashboard', function(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideEditor' })
    cb('ok')
end)

RegisterNUICallback('startSetup', function(data, cb)
    preview.weaponName = data.weaponLabel
    preview.weaponItem = data.weaponItem
    preview.boneName = data.boneName
    preview.bone = data.boneValue
    for i = 1, #Config.WeaponList do
        if Config.WeaponList[i].label == data.weaponItem then
            preview.weapon = Config.WeaponList[i].object
            break
        end
    end
    startEditMode(false)
    cb('ok')
end)

RegisterNUICallback('readjustConfig', function(data, cb)
    local config = playerWeaponConfig[data.weapon]
    if config then
        local info = json.decode(config.info)
        local coords = json.decode(config.coords)
        preview.weaponName = info.label
        preview.weapon = info.name
        preview.weaponItem = info.weaponName
        preview.boneName = info.boneName
        preview.bone = info.bone
        
        local positionLimit = Config.Editor.positionHardLimit
        adjust.x = clampEditorValue(coords.x, -positionLimit, positionLimit)
        adjust.y = clampEditorValue(coords.y, -positionLimit, positionLimit)
        adjust.z = clampEditorValue(coords.z, -positionLimit, positionLimit)
        adjust.rx = clampEditorValue(coords.rx or 0.0, Config.Editor.rotationMin, Config.Editor.rotationMax)
        adjust.ry = clampEditorValue(coords.ry or 0.0, Config.Editor.rotationMin, Config.Editor.rotationMax)
        adjust.rz = clampEditorValue(coords.rz or 0.0, Config.Editor.rotationMin, Config.Editor.rotationMax)
        startEditMode(true)
    end
    cb('ok')
end)


RegisterNUICallback('deleteConfig', function(data, cb)
    ESX.TriggerServerCallback('BodyWeapon:server:DeleteBodyWeapon', function(success)
        if success then
            exports['lv_notify']:lv_notify('Đã xóa cấu hình thành công.', 'success', 3500, 'Hệ thống')
            playerWeaponConfig[data.weapon] = nil
            updateMyBodyWeaponsState()
            openDashboard()
        else
            exports['lv_notify']:lv_notify('Lỗi: Không thể xóa cấu hình.', 'error', 3500, 'Hệ thống')
        end
    end, data.weapon)
    cb('ok')
end)

local lastBodyWeaponsData = nil
local playerBodyWeapons = {}

function updateMyBodyWeaponsState()
    if not ESX.IsPlayerLoaded() then return end

    -- Keep the last valid replicated state while editing. Publishing an empty
    -- table here made every client delete the weapon and caused visible sync
    -- flicker (and occasionally a stale empty state after closing the editor).
    if adjust.editMode then return end
    
    local data = {}
    do
        local currentWeapon = exports.ox_inventory:getCurrentWeapon()
        local _, currentPedWeaponHash = GetCurrentPedWeapon(PlayerPedId(), true)
        local inventory = exports.ox_inventory:GetPlayerItems()
        
        local configuredWeaponNames = {}
        for weaponName in pairs(playerWeaponConfig) do
            configuredWeaponNames[#configuredWeaponNames + 1] = weaponName
        end
        table.sort(configuredWeaponNames)

        for i = 1, #configuredWeaponNames do
            local weaponName = configuredWeaponNames[i]
            local weaponData = playerWeaponConfig[weaponName]
            local hasItem = (exports.ox_inventory:Search('count', weaponName) or 0) > 0
            local weaponHash = GetHashKey(weaponName)
            local isCurrentWeapon = (currentWeapon and currentWeapon.name == weaponName) or (currentPedWeaponHash == weaponHash)
            
            if hasItem and not isCurrentWeapon then
                local info = json.decode(weaponData.info)
                local coords = json.decode(weaponData.coords)
                
                local components = {}
                local tint = 0
                if inventory then
                    for _, item in pairs(inventory) do
                        if item.name == weaponName then
                            if item.metadata then
                                if item.metadata.components then
                                    for _, compName in pairs(item.metadata.components) do
                                        local compItem = exports.ox_inventory:Items(compName)
                                        if compItem then
                                            if compItem.client and compItem.client.component then
                                                for v = 1, #compItem.client.component do
                                                    local componentHash = compItem.client.component[v]
                                                    local compHash = type(componentHash) == 'string' and GetHashKey(componentHash) or componentHash
                                                    
                                                    local alreadyAdded = false
                                                    for _, existingComp in ipairs(components) do
                                                        local existingHash = type(existingComp) == 'string' and GetHashKey(existingComp) or existingComp
                                                        if existingHash == compHash then
                                                            alreadyAdded = true
                                                            break
                                                        end
                                                    end
                                                    
                                                    if not alreadyAdded then
                                                        table.insert(components, componentHash)
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                                if item.metadata.originalMagInfo and item.metadata.originalMagInfo.component then
                                    local magComp = item.metadata.originalMagInfo.component
                                    local magHash = type(magComp) == 'string' and GetHashKey(magComp) or magComp
                                    
                                    local alreadyAdded = false
                                    for _, existingComp in ipairs(components) do
                                        local existingHash = type(existingComp) == 'string' and GetHashKey(existingComp) or existingComp
                                        if existingHash == magHash then
                                            alreadyAdded = true
                                            break
                                        end
                                    end
                                    
                                    if not alreadyAdded then
                                        table.insert(components, magComp)
                                    end
                                end
                                if item.metadata.tint then
                                    tint = item.metadata.tint
                                end
                            end
                            break
                        end
                    end
                end
                
                table.insert(data, {
                    weapon = weaponName,
                    model = info.name,
                    bone = info.bone,
                    coords = coords,
                    components = components,
                    tint = tint
                })
            end
        end
    end
    
    local serialized = json.encode(data)
    if lastBodyWeaponsData ~= serialized then
        lastBodyWeaponsData = serialized
        LocalPlayer.state:set('bodyweapons', data, true)
    end
end

local function queueBodyWeaponsStateUpdate(delay)
    stateUpdateVersion = stateUpdateVersion + 1
    local version = stateUpdateVersion

    SetTimeout(delay or 150, function()
        if version == stateUpdateVersion then
            updateMyBodyWeaponsState()
        end
    end)
end

local function syncAllPlayersBodyWeapons()
    local players = GetActivePlayers()
    for i = 1, #players do
        local serverId = GetPlayerServerId(players[i])
        playerBodyWeapons[serverId] = Player(serverId).state.bodyweapons
    end
end

AddStateBagChangeHandler("bodyweapons", nil, function(bagName, key, value, reserved, replicated)
    local serverId = tonumber((bagName:gsub('player:', '')))
    if not serverId then return end
    playerBodyWeapons[serverId] = value

    -- Force a rebuild so changed bone/coords/components are applied instead of
    -- leaving an already existing object attached with stale data.
    deleteSpawnedWeapons(serverId)
end)

CreateThread(function()
    while not ESX.IsPlayerLoaded() do Wait(500) end
    syncAllPlayersBodyWeapons()
    
    while true do
        Wait(1000)
        
        local activePlayersMap = {}
        local players = GetActivePlayers()
        local myPed = PlayerPedId()
        local myCoords = GetEntityCoords(myPed)
        
        for i = 1, #players do
            local player = players[i]
            local serverId = GetPlayerServerId(player)
            activePlayersMap[serverId] = true
        end
        
        for i = 1, #players do
            local player = players[i]
            local ped = GetPlayerPed(player)
            
            if DoesEntityExist(ped) then
                local serverId = GetPlayerServerId(player)
                local isMe = (ped == myPed)
                local distance = 0.0
                if not isMe then
                    distance = #(myCoords - GetEntityCoords(ped))
                end
                
                if not spawnedObjects[serverId] then
                    spawnedObjects[serverId] = {}
                end
                local currentSpawned = spawnedObjects[serverId]
                local targetWeapons = {}

                -- State bags can arrive after the player streams in. Reading
                -- the live value here makes the loop self-heal if an initial
                -- change notification was missed.
                local liveState = Player(serverId).state.bodyweapons
                if liveState ~= nil then
                    playerBodyWeapons[serverId] = liveState
                end
                
                local inRange = isMe or (distance < Config.Editor.renderDistance)
                local showWeapons = inRange and not IsEntityDead(ped) and not IsPedInAnyVehicle(ped, true)

                if showWeapons then
                    local bodyweapons = playerBodyWeapons[serverId]
                    if bodyweapons then
                        for _, weaponData in ipairs(bodyweapons) do
                            -- Only suppress the weapon currently being previewed.
                            -- Other equipped body props stay visible locally and
                            -- the replicated state remains untouched for everyone.
                            local isEditedWeapon = isMe and adjust.editMode and weaponData.weapon == preview.weaponItem
                            if not isEditedWeapon then
                                targetWeapons[weaponData.weapon] = weaponData
                            end
                        end
                    end
                end
                
                for weaponName, obj in pairs(currentSpawned) do
                    if not targetWeapons[weaponName] or GetEntityAttachedTo(obj) ~= ped then
                        if DoesEntityExist(obj) then
                            DeleteEntity(obj)
                        end
                        currentSpawned[weaponName] = nil
                    end
                end
                
                for weaponName, weaponData in pairs(targetWeapons) do
                    local obj = currentSpawned[weaponName]
                    if not obj or not DoesEntityExist(obj) then
                        local weaponHash = GetHashKey(weaponData.weapon)
                        if not HasWeaponAssetLoaded(weaponHash) then
                            RequestWeaponAsset(weaponHash, 31, 0)
                            local timeout = 5
                            while not HasWeaponAssetLoaded(weaponHash) and timeout > 0 do
                                Wait(10)
                                timeout = timeout - 1
                            end
                        end
                        
                        if HasWeaponAssetLoaded(weaponHash) and DoesEntityExist(ped) and spawnedObjects[serverId] and not spawnedObjects[serverId][weaponName] then
                            local coords = GetEntityCoords(ped)
                            local weaponObj = CreateWeaponObject(weaponHash, 50, coords.x, coords.y, coords.z, true, 1.0, 0)
                            if DoesEntityExist(weaponObj) then
                                SetEntityAsMissionEntity(weaponObj, true, true)
                                SetEntityCollision(weaponObj, false, false)
                                SetEntityCompletelyDisableCollision(weaponObj, false, false)
                                FreezeEntityPosition(weaponObj, true)
                                local weaponUpper = weaponData.weapon:upper()
                                if weaponUpper:sub(1, 7) == "WEAPON_" then
                                    local weaponBaseName = weaponUpper:sub(8)
                                    local defaultClip = "COMPONENT_" .. weaponBaseName .. "_CLIP_01"
                                    local defaultClipHash = GetHashKey(defaultClip)
                                    GiveWeaponComponentToWeaponObject(weaponObj, defaultClipHash)
                                end

                                if weaponData.components then
                                    for _, compHashOrString in pairs(weaponData.components) do
                                        local compHash = type(compHashOrString) == 'string' and GetHashKey(compHashOrString) or math.floor(tonumber(compHashOrString) or 0)
                                        if compHash ~= 0 then
                                            RequestWeaponAsset(compHash, 31, 0)
                                            GiveWeaponComponentToWeaponObject(weaponObj, compHash)
                                        end
                                    end
                                end
                                
                                if weaponData.tint then
                                    SetWeaponObjectTintIndex(weaponObj, weaponData.tint)
                                end
                                
                                local boneIndex = GetPedBoneIndex(ped, weaponData.bone)
                                local coordsData = weaponData.coords
                                AttachEntityToEntity(weaponObj, ped, boneIndex,
                                    (tonumber(coordsData.x) or 0.0) + 0.0,
                                    (tonumber(coordsData.y) or 0.0) + 0.0,
                                    (tonumber(coordsData.z) or 0.0) + 0.0,
                                    (tonumber(coordsData.rx) or 0.0) + 0.0,
                                    (tonumber(coordsData.ry) or 0.0) + 0.0,
                                    (tonumber(coordsData.rz) or 0.0) + 0.0,
                                    true, false, false, false, 2, true)
                                
                                spawnedObjects[serverId][weaponName] = weaponObj
                            end
                        end
                    end
                end
            end
        end
        
        for serverId, weapons in pairs(spawnedObjects) do
            if not activePlayersMap[serverId] then
                for weaponName, obj in pairs(weapons) do
                    if DoesEntityExist(obj) then
                        DeleteEntity(obj)
                    end
                end
                spawnedObjects[serverId] = nil
                playerBodyWeapons[serverId] = nil
            end
        end
    end
end)

CreateThread(function()
    while not ESX.IsPlayerLoaded() do Wait(500) end
    TriggerEvent('BodyWeapon:client:RefreshWeapons')
end)

RegisterNetEvent('BodyWeapon:client:RefreshWeapons', function()
    playerWeaponConfig = {}

    ESX.TriggerServerCallback('BodyWeapon:server:GetAllBodyWeapons', function(results)
        if results then
            for _, result in ipairs(results) do
                playerWeaponConfig[result.weapon] = result
            end
        end
        updateMyBodyWeaponsState()
    end)
end)

RegisterNetEvent('ox_inventory:updateSlots', function()
    queueBodyWeaponsStateUpdate(200)
end)

AddEventHandler('ox_inventory:currentWeapon', function()
    queueBodyWeaponsStateUpdate(200)
end)

-- Periodic reconciliation covers inventory resources that do not emit an
-- event for every metadata/current-weapon transition.
CreateThread(function()
    while true do
        Wait(Config.Editor.reconciliationInterval)
        updateMyBodyWeaponsState()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        SetNuiFocus(false, false)
        for _, weapons in pairs(spawnedObjects) do
            for _, obj in pairs(weapons) do
                if DoesEntityExist(obj) then
                    DeleteEntity(obj)
                end
            end
        end
        if DoesEntityExist(preview.object) then
            DeleteEntity(preview.object)
        end
    end
end)

CreateThread(function()
    while true do
        local sleep = 1000
        if adjust.editMode then
            sleep = 0
            InvalidateIdleCam()
            local ped = PlayerPedId()
            local previewExists = DoesEntityExist(preview.object)
            if not previewExists and GetGameTimer() >= nextPreviewRetryAt then
                preview.object = spawnWeaponObject(preview.weaponItem, ped)
                previewExists = DoesEntityExist(preview.object)
                if previewExists then
                    coordsChanged = true
                else
                    nextPreviewRetryAt = GetGameTimer() + Config.Editor.previewRetryDelay
                end
            end

            -- Never pass a missing handle to attachment natives. A single
            -- failed respawn used to terminate this thread and leave the gun
            -- gone for the rest of the editing session.
            if previewExists and (coordsChanged or GetEntityAttachedTo(preview.object) ~= ped) then
                updateAttachedPreview()
                coordsChanged = false
            end
        end
        Wait(sleep)
    end
end)
