local ESX = exports['es_extended']:getSharedObject()
local Config = require 'magazine.config'

local playerTransactions = {}
local completedRequests = {}
local magazineIdCounter = 0

local function clone(value)
    if type(value) ~= 'table' then
        return value
    end

    return lib.table.deepclone(value)
end

local function newMagazineId(source)
    magazineIdCounter = magazineIdCounter + 1

    return ('mag:%s:%s:%s:%s:%s'):format(
        tonumber(source) or 0,
        os.time(),
        GetGameTimer(),
        math.random(100000, 999999),
        magazineIdCounter
    )
end

local function rememberRequest(source, requestId, result)
    if not requestId then
        return result
    end

    completedRequests[source] = completedRequests[source] or {}

    for id, entry in pairs(completedRequests[source]) do
        if entry.expiresAt < GetGameTimer() then
            completedRequests[source][id] = nil
        end
    end

    completedRequests[source][requestId] =
    {
        result = clone(result),
        expiresAt = GetGameTimer() + 15000
    }

    return result
end

local function getRememberedRequest(source, requestId)
    local requests = requestId and completedRequests[source]
    local entry = requests and requests[requestId]

    if not entry then
        return nil
    end

    if entry.expiresAt < GetGameTimer() then
        requests[requestId] = nil
        return nil
    end

    return clone(entry.result)
end

local function runTransaction(source, action, handler)
    if playerTransactions[source] then
        return
        {
            success = false,
            reason = 'busy',
            message = 'Một thao tác băng đạn khác đang được xử lý'
        }
    end

    playerTransactions[source] = action or true

    local ok, result = xpcall(handler, debug.traceback)

    playerTransactions[source] = nil

    if not ok then
        print(('[lv_Magazine] transaction %s failed for %s: %s'):format(action or 'unknown', source, result))

        return
        {
            success = false,
            reason = 'internal_error',
            message = 'Không thể xử lý băng đạn, dữ liệu cũ đã được giữ lại'
        }
    end

    return result or
    {
        success = false,
        reason = 'empty_result',
        message = 'Thao tác băng đạn không trả về kết quả hợp lệ'
    }
end

AddEventHandler('playerDropped', function()
    playerTransactions[source] = nil
    completedRequests[source] = nil
end)

local function cleanMessage(text)
    text = tostring(text or '')
    text = text:gsub('{%x%x%x%x%x%x}', '')
    text = text:gsub('%[vMagazine%]%s*', '')
    return text
end

local function Notify(src, notifyType, message, duration)
    if not src or src == 0 then
        return
    end

    local isError = (notifyType == 'error')

    if not isError and not Config.EnableNotifications then
        return
    end

    local payload =
    {
        type = notifyType or 'info',
        title = 'Băng Đạn',
        message = cleanMessage(message),
        duration = duration or 3500
    }

    if GetResourceState('lv_notify') == 'started' then
        exports['lv_notify']:Notify(src, payload)
        return
    end

    TriggerClientEvent('ox_lib:notify', src,
    {
        type = payload.type,
        title = payload.title,
        description = payload.message,
        duration = payload.duration
    })
end

local function SendMsg(src, color, text)
    local notifyType = 'info'

    if color == 'FF4444' then
        notifyType = 'error'
    elseif color == '44FF88' then
        notifyType = 'success'
    elseif color == 'FFB800' then
        notifyType = 'warning'
    end

    Notify(src, notifyType, text)
end

local function IsAdmin(src)
    if src == 0 then
        return true
    end

    if GetResourceState('aCore') == 'started' then
        return exports['aCore']:IsAdmin(src)
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and (xPlayer.getGroup() == 'admin' or xPlayer.getGroup() == 'superadmin')
end

local function resolveMagazineType(metadata)
    metadata = type(metadata) == 'table' and metadata or {}

    local declaredType = metadata.magType
    local declaredConfig = declaredType and Config.MagazineTypes[declaredType]

    if declaredConfig then
        local ammoMatches = not metadata.ammoType or metadata.ammoType == declaredConfig.ammoType
        local sizeMatches = not metadata.magSize or tonumber(metadata.magSize) == declaredConfig.magSize

        if ammoMatches and sizeMatches then
            return declaredType
        end
    end

    local matchedType

    for magType, configDef in pairs(Config.MagazineTypes) do
        if metadata.ammoType == configDef.ammoType and tonumber(metadata.magSize) == configDef.magSize then
            if matchedType then
                return declaredConfig and declaredType or nil
            end

            matchedType = magType
        end
    end
    return matchedType or (declaredConfig and declaredType) or nil
end

local function getMagazineMetadata(magType, currentAmmo, overrides)
    local configDef = Config.MagazineTypes[magType]

    if not configDef then
        return nil
    end

    overrides = type(overrides) == 'table' and overrides or {}

    local maxAmmo = configDef.magSize

    currentAmmo = math.max(0, math.min(math.floor(tonumber(currentAmmo) or 0), maxAmmo))
    return
    {
        label = overrides.label or configDef.label,
        magType = magType,
        ammoType = configDef.ammoType,
        magSize = maxAmmo,
        model = overrides.model or configDef.model,
        image = overrides.image or configDef.image,
        component = overrides.component or configDef.component,
        ammo = currentAmmo,
        id = overrides.id,
        magazineSchema = Config.MagazineSchema or 2,
        durability = math.max(1, math.floor((currentAmmo / maxAmmo) * 100)),
        description = ('Đạn: %d/%d'):format(currentAmmo, maxAmmo)
    }
end

local function getWeaponProfile(weapon)
    if not weapon or not weapon.name then
        return nil
    end

    local configured = Config.WeaponProfiles and Config.WeaponProfiles[weapon.name]
    local weaponData = exports.ox_inventory:Items(weapon.name)
    local magType = configured and configured.magType or (weaponData and weaponData.ammoname)
    local magConfig = magType and Config.MagazineTypes[magType]

    if not magConfig then
        return nil
    end

    return
    {
        magType = magType,
        capacity = magConfig.magSize,
        component = configured and configured.component or magConfig.component,
        definition = magConfig
    }
end

local function hasExternalClipComponent(weapon)
    for _, componentItem in ipairs((weapon.metadata and weapon.metadata.components) or {}) do
        local item = exports.ox_inventory:Items(componentItem)

        if item and item.type == 'magazine' then
            return true, componentItem
        end
    end

    return false
end

local function installedMagazineMetadata(source, weapon, profile, observedAmmo)
    local info = type(weapon.metadata.originalMagInfo) == 'table' and weapon.metadata.originalMagInfo or {}
    local declaredType = resolveMagazineType(info)

    if declaredType and declaredType ~= profile.magType then
        return nil, 'wrong_type', declaredType
    end

    local hasMagazine = weapon.metadata.hasMagazine == true
    local serverAmmo = math.max(0, math.min(math.floor(tonumber(weapon.metadata.ammo) or 0), profile.capacity))

    if not hasMagazine and serverAmmo <= 0 and not declaredType then
        return nil
    end

    if observedAmmo ~= nil then
        serverAmmo = math.min(serverAmmo, math.max(0, math.floor(tonumber(observedAmmo) or 0)))
    end

    local metadata = getMagazineMetadata(profile.magType, serverAmmo,
    {
        id = info.id or newMagazineId(source),
        component = profile.component
    })

    return metadata
end

local function setInstalledMagazineMetadata(weaponMetadata, profile, magazineMetadata)
    weaponMetadata.ammo = magazineMetadata.ammo
    weaponMetadata.hasMagazine = true
    weaponMetadata.magazineSchema = Config.MagazineSchema or 2
    weaponMetadata.magazineType = magazineMetadata.label
    weaponMetadata.description = ('Băng Đạn: %s (%d/%d)'):format(
        magazineMetadata.label or 'Băng đạn',
        magazineMetadata.ammo,
        magazineMetadata.magSize
    )
    weaponMetadata.originalMagInfo =
    {
        id = magazineMetadata.id,
        label = magazineMetadata.label,
        magType = profile.magType,
        ammoType = magazineMetadata.ammoType,
        magSize = profile.capacity,
        model = magazineMetadata.model,
        image = magazineMetadata.image,
        component = profile.component,
        magazineSchema = Config.MagazineSchema or 2
    }
end

local function clearInstalledMagazineMetadata(weaponMetadata)
    weaponMetadata.ammo = 0
    weaponMetadata.hasMagazine = false
    weaponMetadata.magazineSchema = Config.MagazineSchema or 2
    weaponMetadata.magazineType = nil
    weaponMetadata.originalMagInfo = nil
    weaponMetadata.description = 'Không Có Băng Đạn'
end

local function handleUpdateMagazine(source, action, value, slot)
    source = tonumber(source)
    slot = tonumber(slot)
    value = tonumber(value) or 0

    if not source or source <= 0 or not slot or value <= 0 then
        return
        {
            success = false
        }
    end

    return runTransaction(source, 'pack_magazine', function()
    if action == 'loadMagazine' then
        local magazine = exports.ox_inventory:GetSlot(source, slot)

        if not magazine or magazine.name ~= 'magazine' or not magazine.metadata then
            return
            {
                success = false
            }
        end

        local magType = resolveMagazineType(magazine.metadata)
        local configDef = magType and Config.MagazineTypes[magType]

        if not configDef then
            return
            {
                success = false
            }
        end

        local magSize = configDef.magSize
        local currentAmmo = math.max(0, math.min(tonumber(magazine.metadata.ammo) or 0, magSize))
        local ammoType = configDef.ammoType

        if currentAmmo >= magSize then
            return
            {
                success = false
            }
        end

        local ammoToAdd = math.min(value, magSize - currentAmmo)

        if ammoToAdd <= 0 then
            return
            {
                success = false
            }
        end

        local availableAmmo = exports.ox_inventory:Search(source, 'count', ammoType)

        if availableAmmo < ammoToAdd then
            ammoToAdd = availableAmmo
        end

        if ammoToAdd <= 0 then
            return
            {
                success = false
            }
        end

        local oldMagazineMetadata = clone(magazine.metadata)

        if not exports.ox_inventory:RemoveItem(source, ammoType, ammoToAdd) then
            return
            {
                success = false
            }
        end

        local newAmmo = currentAmmo + ammoToAdd
        local metadata = getMagazineMetadata(magType, newAmmo,
        {
            id = magazine.metadata.id or newMagazineId(source)
        })

        exports.ox_inventory:SetMetadata(source, slot, metadata)

        local verifiedMagazine = exports.ox_inventory:GetSlot(source, slot)

        if not verifiedMagazine or tonumber(verifiedMagazine.metadata.ammo) ~= newAmmo then
            exports.ox_inventory:AddItem(source, ammoType, ammoToAdd)
            exports.ox_inventory:SetMetadata(source, slot, oldMagazineMetadata)

            return
            {
                success = false,
                reason = 'verification_failed'
            }
        end

        return
        {
            success = true,
            ammoAdded = ammoToAdd
        }
    end
    return
    {
        success = false
    }
    end)
end

lib.callback.register('vMagazine:server:updateMagazine', handleUpdateMagazine)
lib.callback.register('p_ox_inventory_addon:updateMagazine', handleUpdateMagazine)

RegisterNetEvent('vMagazine:server:updateMagazineLabel', function(slot, removeLabel)
    local src = source
    local item = exports.ox_inventory:GetSlot(src, slot)

    if not item or not item.metadata then
        return
    end

    local newMetadata = item.metadata

    if removeLabel then
        if newMetadata.label then
            newMetadata.label = newMetadata.label:gsub('⚡ ', '')
        end
    else
        if Config.UseStatusLabelPrefix then
            if newMetadata.label then
                newMetadata.label = newMetadata.label:gsub('⚡ ', '')
            end

            newMetadata.label = '⚡ ' .. (newMetadata.label or 'Băng Đạn')
        end
    end

    exports.ox_inventory:SetMetadata(src, slot, newMetadata)
end)

local function getMagazineLimit(source)
    if not Config.EnableMagazineLimit then
        return 999
    end

    local isPD = false

    if Player(source).state.factionCategory == 'police' then
        isPD = true
    else
        local xPlayer = ESX.GetPlayerFromId(source)

        if xPlayer and xPlayer.job and xPlayer.job.name == 'police' then
            isPD = true
        end
    end
    
    if isPD then
        return Config.PoliceMagLimit or 5
    end
    return Config.DefaultMagLimit or 3
end

exports.ox_inventory:registerHook('swapItems', function(payload)
    if type(payload.fromSlot) == 'table' and payload.fromSlot.name == 'magazine' then
        if type(payload.toSlot) == 'table' and payload.toSlot.name:find('WEAPON_') then
            local playerId = payload.source
            local weaponSlot = payload.toSlot.slot
            local magazineSlot = payload.fromSlot.slot
            local magazineId = payload.fromSlot.metadata and payload.fromSlot.metadata.id

            CreateThread(function()
                local requestId = ('drag:%s:%s:%s'):format(playerId, GetGameTimer(), magazineId or magazineSlot)
                local result = PerformReload(playerId, weaponSlot, magazineSlot, true, nil, requestId, magazineId)

                TriggerClientEvent('vMagazine:client:reloadResult', playerId, result)
            end)
            return false
        end

        if payload.toType == 'player' and payload.fromInventory ~= payload.toInventory then
            local playerId = tonumber(payload.toInventory)

            if playerId then
                local limit = getMagazineLimit(playerId)
                local currentCount = exports.ox_inventory:GetItemCount(playerId, 'magazine')
                local moveCount = payload.count or 1
                local leavingCount = 0

                if payload.action == 'swap' and type(payload.toSlot) == 'table' and payload.toSlot.name == 'magazine' then
                    leavingCount = payload.toSlot.count or 1
                end

                if (currentCount + moveCount - leavingCount) > limit then
                    Notify(playerId, 'error', ('Bạn chỉ có thể mang tối đa %d băng đạn trong túi đồ'):format(limit))
                    return false
                end
            end
        end
    end
    return true
end,
{
    itemFilter =
    {
        ['magazine'] = true
    }
})

exports.ox_inventory:registerHook('buyItem', function(payload)
    if payload.itemName == 'magazine' then
        local playerId = payload.source
        local limit = getMagazineLimit(playerId)
        local currentCount = exports.ox_inventory:GetItemCount(playerId, 'magazine')
        local moveCount = payload.count or 1

        if (currentCount + moveCount) > limit then
            Notify(playerId, 'error', ('Bạn chỉ có thể mang tối đa %d băng đạn trong túi đồ'):format(limit))
            return false
        end
    end
    return true
end,
{
    itemFilter =
    {
        ['magazine'] = true
    }
})

exports.ox_inventory:registerHook('craftItem', function(payload)
    if payload.recipe and payload.recipe.name == 'magazine' then
        local playerId = payload.source
        local limit = getMagazineLimit(playerId)
        local currentCount = exports.ox_inventory:GetItemCount(playerId, 'magazine')
        local moveCount = payload.recipe.count or 1

        if (currentCount + moveCount) > limit then
            Notify(playerId, 'error', ('Bạn chỉ có thể mang tối đa %d băng đạn trong túi đồ.'):format(limit))
            return false
        end
    end
    return true
end,
{
    itemFilter =
    {
        ['magazine'] = true
    }
})

exports.ox_inventory:registerHook('createItem', function(payload)
    if payload.item and (payload.item.name == 'magazine' or payload.item.magazine) then
        payload.metadata = payload.metadata or {}

        local magType = resolveMagazineType(payload.metadata) or 'magazine-9mm'
        local configDef = Config.MagazineTypes[magType]
        local initialAmmo = payload.metadata.ammo ~= nil and tonumber(payload.metadata.ammo) or 0
        local metadataOverrides = clone(payload.metadata)
        metadataOverrides.id = payload.metadata.id or newMagazineId(payload.inventoryId or payload.source)
        local metadata = getMagazineMetadata(magType, initialAmmo, metadataOverrides)

        payload.metadata = metadata
    end
    return payload.metadata
end,
{
    itemFilter =
    {
        ['magazine'] = true
    }
})

RegisterCommand('givemag', function(source, args)
    local src = source
    local hasPerm = false

    if src == 0 then
        hasPerm = true
    elseif GetResourceState('aCore') == 'started' then
        hasPerm = exports['aCore']:GetAdminLevel(src) >= 4
    else
        local xPlayer = ESX.GetPlayerFromId(src)
        hasPerm = xPlayer and (xPlayer.getGroup() == 'superadmin' or xPlayer.getGroup() == 'admin')
    end

    if not hasPerm then
        SendMsg(src, 'FF4444', 'Bạn không đủ quyền hạn để sử dụng lệnh này (Yêu cầu Admin 4+)')
        return
    end

    local inputType = args[1]
    local targetId = tonumber(args[2]) or src
    local amount = tonumber(args[3]) or 1

    if not inputType then
        TriggerClientEvent('custom-chat:addMessage', src, "{FF6347}Sử Dụng:{FFFFFF} /givemag [Loại] [Player] [Số lượng]")

        local list = {}

        for k, _ in pairs(Config.MagazineTypes) do
            local shortName = k:gsub('^magazine%-', '')

            table.insert(list, shortName)
        end

        table.sort(list)
        
        TriggerClientEvent('custom-chat:addMessage', src, "{FF6347}Danh Sách: " .. table.concat(list, '| '))
        return
    end

    local magType = inputType

    if not Config.MagazineTypes[magType] then
        magType = 'magazine-' .. inputType
    end

    if not Config.MagazineTypes[magType] then
        SendMsg(src, 'FF4444', 'Loại băng đạn ' .. inputType .. ' không hợp lệ')
        return
    end

    local target = ESX.GetPlayerFromId(targetId)

    if not target then
        SendMsg(src, 'FF4444', 'Người chơi không hợp lệ')
        return
    end

    local magazineData = Config.MagazineTypes[magType]
    local maxAmmo = magazineData.magSize or 15
    local successCount = 0

    for i = 1, amount do
        local newMagazineMetadata = getMagazineMetadata(magType, maxAmmo)
        newMagazineMetadata.id = newMagazineId(targetId)
        if exports.ox_inventory:AddItem(targetId, 'magazine', 1, newMagazineMetadata) then
            successCount = successCount + 1
        else           
            break
        end
    end
    if successCount > 0 then
        SendMsg(src, '44FF88', ('Đã đưa x%d băng đạn %s (%d/%d) cho ID #%d'):format(successCount, magazineData.label or magType, maxAmmo, maxAmmo, targetId))
        if successCount < amount then
            SendMsg(src, 'FF4444', ('Túi đồ người nhận đã đầy! Chỉ nhận được %d/%d băng đạn.'):format(successCount, amount))
        end
    else
        SendMsg(src, 'FF4444', 'Túi đồ của người nhận đã đầy')
    end
end, false)

RegisterNetEvent('vMagazine:server:removeMagazine', function(weaponSlot, clientAmmo)
    local src = source

    local result = runTransaction(src, 'remove_magazine', function()
        weaponSlot = tonumber(weaponSlot)

        local weapon = weaponSlot and exports.ox_inventory:GetSlot(src, weaponSlot)
        local currentWeapon = exports.ox_inventory:GetCurrentWeapon(src)
        local profile = getWeaponProfile(weapon)

        if not weapon or not profile or not currentWeapon or currentWeapon.slot ~= weaponSlot then
            return { success = false, message = 'Vũ khí hiện tại không hợp lệ' }
        end

        local returnedMagazine = installedMagazineMetadata(src, weapon, profile, clientAmmo)

        if not returnedMagazine then
            return { success = false, message = 'Vũ khí hiện tại không có băng đạn để tháo' }
        end

        local oldWeaponMetadata = clone(weapon.metadata)
        local added, addedSlot = exports.ox_inventory:AddItem(
            src,
            'magazine',
            1,
            returnedMagazine,
            nil,
            nil,
            { reason = 'lv_Magazine.removeMagazine', requestId = returnedMagazine.id }
        )

        if not added then
            return { success = false, message = 'Túi đồ đã đầy không thể tháo băng đạn' }
        end

        local newWeaponMetadata = clone(oldWeaponMetadata)
        clearInstalledMagazineMetadata(newWeaponMetadata)
        exports.ox_inventory:SetMetadata(src, weaponSlot, newWeaponMetadata)

        local verifiedWeapon = exports.ox_inventory:GetSlot(src, weaponSlot)

        if not verifiedWeapon or verifiedWeapon.metadata.hasMagazine or tonumber(verifiedWeapon.metadata.ammo) ~= 0 then
            local returnSlot = type(addedSlot) == 'table' and addedSlot.slot
            exports.ox_inventory:RemoveItem(src, 'magazine', 1, returnedMagazine, returnSlot, false, true)
            exports.ox_inventory:SetMetadata(src, weaponSlot, oldWeaponMetadata)

            return { success = false, message = 'Không thể tháo băng đạn, dữ liệu cũ đã được khôi phục' }
        end

        return
        {
            success = true,
            weaponName = weapon.name,
            weaponSlot = weaponSlot,
            ammo = 0,
            removedComponent = returnedMagazine.component
        }
    end)

    result = result or { success = false }

    if result.success then
        TriggerClientEvent('vMagazine:client:reloadResult', src, result)
        SendMsg(src, '44FF88', 'Đã tháo băng đạn khỏi vũ khí')
    else
        SendMsg(src, 'FF4444', result.message or 'Không thể tháo băng đạn')
    end
end)

RegisterNetEvent('vMagazine:server:unloadAmmo', function(slot)
    local src = source

    local result = runTransaction(src, 'unload_magazine', function()
        slot = tonumber(slot)
        local magazine = slot and exports.ox_inventory:GetSlot(src, slot)

        if not magazine or magazine.name ~= 'magazine' or not magazine.metadata then
            return { success = false, message = 'Dữ liệu băng đạn không hợp lệ' }
        end

        local magType = resolveMagazineType(magazine.metadata)
        local configDef = magType and Config.MagazineTypes[magType]

        if not configDef then
            return { success = false, message = 'Dữ liệu băng đạn không hợp lệ' }
        end

        local currentAmmo = math.max(0, math.min(math.floor(tonumber(magazine.metadata.ammo) or 0), configDef.magSize))

        if currentAmmo <= 0 then
            return { success = false, message = 'Băng đạn rỗng' }
        end

        if not exports.ox_inventory:AddItem(
            src,
            configDef.ammoType,
            currentAmmo,
            nil,
            nil,
            nil,
            { reason = 'lv_Magazine.unloadAmmo', requestId = magazine.metadata.id }
        ) then
            return { success = false, message = 'Túi đồ đã đầy không thể lấy đạn ra' }
        end

        local oldMagazineMetadata = clone(magazine.metadata)
        exports.ox_inventory:SetMetadata(src, slot, getMagazineMetadata(magType, 0,
        {
            id = magazine.metadata.id or newMagazineId(src)
        }))

        local verifiedMagazine = exports.ox_inventory:GetSlot(src, slot)

        if not verifiedMagazine or tonumber(verifiedMagazine.metadata.ammo) ~= 0 then
            exports.ox_inventory:RemoveItem(src, configDef.ammoType, currentAmmo)
            exports.ox_inventory:SetMetadata(src, slot, oldMagazineMetadata)

            return { success = false, message = 'Không thể xác minh thao tác; dữ liệu cũ đã được khôi phục' }
        end

        return { success = true, ammo = currentAmmo }
    end)

    result = result or { success = false }

    if result.success then
        SendMsg(src, '44FF88', ('Đã lấy %d viên đạn ra khỏi băng đạn'):format(result.ammo))
    else
        SendMsg(src, 'FF4444', result.message or 'Không thể lấy đạn ra')
    end
end)

RegisterNetEvent('vMagazine:server:validateWeaponMagazine', function(weaponSlot)
    local src = source

    local result = runTransaction(src, 'validate_magazine', function()
        weaponSlot = tonumber(weaponSlot)

        local weapon = weaponSlot and exports.ox_inventory:GetSlot(src, weaponSlot)
        local profile = getWeaponProfile(weapon)

        if not weapon or not weapon.metadata or not profile then
            return { success = false, silent = true }
        end

        local hasExternalClip, componentItem = hasExternalClipComponent(weapon)

        if hasExternalClip then
            return
            {
                success = false,
                block = true,
                weaponName = weapon.name,
                message = ('Hãy tháo attachment ổ đạn %s trước khi dùng băng đạn vật lý'):format(componentItem)
            }
        end

        local normalized, reason, declaredType = installedMagazineMetadata(src, weapon, profile)

        if reason == 'wrong_type' then
            local wrongConfig = Config.MagazineTypes[declaredType]
            local wrongInfo = weapon.metadata.originalMagInfo or {}
            local wrongAmmo = math.max(0, math.min(math.floor(tonumber(weapon.metadata.ammo) or 0), wrongConfig.magSize))
            local returned = getMagazineMetadata(declaredType, wrongAmmo,
            {
                id = wrongInfo.id or newMagazineId(src),
                component = wrongInfo.component
            })

            local oldWeaponMetadata = clone(weapon.metadata)
            local added, addedSlot = exports.ox_inventory:AddItem(src, 'magazine', 1, returned)

            if not added then
                return
                {
                    success = false,
                    block = true,
                    weaponName = weapon.name,
                    message = 'Hãy chừa một ô trống để hệ thống trả băng đạn sai loại'
                }
            end

            local clearedMetadata = clone(weapon.metadata)
            clearInstalledMagazineMetadata(clearedMetadata)
            exports.ox_inventory:SetMetadata(src, weaponSlot, clearedMetadata)

            local verifiedWeapon = exports.ox_inventory:GetSlot(src, weaponSlot)

            if not verifiedWeapon or verifiedWeapon.metadata.hasMagazine or tonumber(verifiedWeapon.metadata.ammo) ~= 0 then
                local returnSlot = type(addedSlot) == 'table' and addedSlot.slot
                exports.ox_inventory:RemoveItem(src, 'magazine', 1, returned, returnSlot, false, true)
                exports.ox_inventory:SetMetadata(src, weaponSlot, oldWeaponMetadata)

                return
                {
                    success = false,
                    block = true,
                    weaponName = weapon.name,
                    message = 'Không thể phục hồi băng sai loại; dữ liệu cũ đã được giữ nguyên'
                }
            end

            return
            {
                success = true,
                weaponName = weapon.name,
                weaponSlot = weaponSlot,
                ammo = 0,
                removedComponent = wrongInfo.component,
                message = 'Đã tháo băng đạn sai loại khỏi vũ khí'
            }
        end

        if not normalized then
            local clearedMetadata = clone(weapon.metadata)
            clearInstalledMagazineMetadata(clearedMetadata)
            exports.ox_inventory:SetMetadata(src, weaponSlot, clearedMetadata)

            return
            {
                success = true,
                weaponName = weapon.name,
                weaponSlot = weaponSlot,
                ammo = 0
            }
        end

        local normalizedWeaponMetadata = clone(weapon.metadata)
        setInstalledMagazineMetadata(normalizedWeaponMetadata, profile, normalized)
        exports.ox_inventory:SetMetadata(src, weaponSlot, normalizedWeaponMetadata)

        return
        {
            success = true,
            weaponName = weapon.name,
            weaponSlot = weaponSlot,
            ammo = normalized.ammo,
            newComponent = profile.component
        }
    end)

    result = result or { success = false, silent = true }

    if result.block then
        Notify(src, 'error', result.message)
        TriggerClientEvent('vMagazine:client:blockInvalidMagazine', src, result.weaponName)
    elseif result.success then
        TriggerClientEvent('vMagazine:client:reloadResult', src, result)

        if result.message then
            Notify(src, 'error', result.message)
        end
    end
end)

function PerformReload(src, weaponSlot, magSlot, isDragDrop, clientAmmo, requestId, expectedMagId)
    src = tonumber(src)
    weaponSlot = tonumber(weaponSlot)
    magSlot = tonumber(magSlot)
    requestId = requestId and tostring(requestId) or nil

    if not src or not weaponSlot or not magSlot then
        return { success = false, reason = 'invalid_request', message = 'Yêu cầu thay băng không hợp lệ' }
    end

    local remembered = getRememberedRequest(src, requestId)

    if remembered then
        return remembered
    end

    if clientAmmo == nil then
        local currentWeapon = exports.ox_inventory:GetCurrentWeapon(src)

        if currentWeapon and currentWeapon.slot == weaponSlot then
            local ok, pedAmmo = pcall(function()
                return lib.callback.await('vMagazine:client:getCurrentClipAmmo', src, joaat(currentWeapon.name))
            end)

            if ok and type(pedAmmo) == 'number' then
                clientAmmo = pedAmmo
            end
        end
    end

    local result = runTransaction(src, 'swap_magazine', function()
        local weapon = exports.ox_inventory:GetSlot(src, weaponSlot)
        local magazine = exports.ox_inventory:GetSlot(src, magSlot)
        local profile = getWeaponProfile(weapon)

        if not weapon or not weapon.metadata or not magazine or magazine.name ~= 'magazine' or not magazine.metadata or not profile then
            return { success = false, reason = 'slots_changed', message = 'Vũ khí hoặc băng đạn đã bị di chuyển' }
        end

        if not isDragDrop then
            local currentWeapon = exports.ox_inventory:GetCurrentWeapon(src)

            if not currentWeapon or currentWeapon.slot ~= weaponSlot then
                return { success = false, reason = 'weapon_changed', message = 'Bạn đã đổi vũ khí trong lúc thay băng' }
            end
        end

        local incomingType = resolveMagazineType(magazine.metadata)

        if incomingType ~= profile.magType then
            return { success = false, reason = 'incompatible', message = 'Băng đạn không phù hợp với vũ khí này' }
        end

        if expectedMagId and magazine.metadata.id ~= expectedMagId then
            return { success = false, reason = 'magazine_changed', message = 'Băng đạn đã thay đổi trước khi giao dịch hoàn tất' }
        end

        local hasExternalClip, componentItem = hasExternalClipComponent(weapon)

        if hasExternalClip then
            return
            {
                success = false,
                reason = 'external_clip',
                message = ('Hãy tháo attachment ổ đạn %s trước khi thay băng'):format(componentItem)
            }
        end

        local oldWeaponMetadata = clone(weapon.metadata)
        local outgoingMagazine, outgoingReason = installedMagazineMetadata(src, weapon, profile, clientAmmo)

        if outgoingReason == 'wrong_type' then
            return { success = false, reason = 'invalid_loaded_magazine', message = 'Băng đạn đang gắn không đúng loại; hãy equip lại súng để hệ thống phục hồi' }
        end

        local incomingMagazine = getMagazineMetadata(profile.magType, magazine.metadata.ammo,
        {
            id = magazine.metadata.id or newMagazineId(src),
            component = profile.component
        })
        local auditContext = { reason = 'lv_Magazine.swapMagazine', requestId = requestId or incomingMagazine.id }

        if not exports.ox_inventory:RemoveItem(src, 'magazine', 1, nil, magSlot, false, true, auditContext) then
            return { success = false, reason = 'remove_failed', message = 'Không thể lấy băng đạn khỏi túi đồ' }
        end

        if outgoingMagazine then
            local added = exports.ox_inventory:AddItem(src, 'magazine', 1, outgoingMagazine, magSlot, nil, auditContext)

            if not added then
                exports.ox_inventory:AddItem(src, 'magazine', 1, incomingMagazine, magSlot, nil, auditContext)
                return { success = false, reason = 'return_failed', message = 'Không thể trả băng đạn cũ; giao dịch đã được hoàn tác' }
            end
        end

        local newWeaponMetadata = clone(oldWeaponMetadata)
        setInstalledMagazineMetadata(newWeaponMetadata, profile, incomingMagazine)
        exports.ox_inventory:SetMetadata(src, weaponSlot, newWeaponMetadata)

        local verifiedWeapon = exports.ox_inventory:GetSlot(src, weaponSlot)
        local verifiedInfo = verifiedWeapon and verifiedWeapon.metadata and verifiedWeapon.metadata.originalMagInfo
        local verified = verifiedInfo
            and verifiedInfo.id == incomingMagazine.id
            and tonumber(verifiedWeapon.metadata.ammo) == incomingMagazine.ammo

        if not verified then
            if outgoingMagazine then
                exports.ox_inventory:RemoveItem(src, 'magazine', 1, outgoingMagazine, magSlot, false, true, auditContext)
            end

            exports.ox_inventory:AddItem(src, 'magazine', 1, incomingMagazine, magSlot, nil, auditContext)
            exports.ox_inventory:SetMetadata(src, weaponSlot, oldWeaponMetadata)

            return { success = false, reason = 'verification_failed', message = 'Giao dịch không vượt qua kiểm tra an toàn và đã được hoàn tác' }
        end

        return
        {
            success = true,
            animateReload = true,
            requestId = requestId,
            weaponName = weapon.name,
            weaponSlot = weaponSlot,
            ammo = incomingMagazine.ammo,
            removedComponent = outgoingMagazine and outgoingMagazine.component,
            newComponent = profile.component
        }
    end)

    result = result or { success = false, reason = 'internal_error', message = 'Không thể xử lý thay băng' }

    if not result.success and result.message then
        Notify(src, 'error', result.message)
    end

    return rememberRequest(src, requestId, result)
end

lib.callback.register('vMagazine:server:performReload', function(source, weaponSlot, magSlot, clientAmmo, requestId, expectedMagId)
    return PerformReload(source, weaponSlot, magSlot, false, clientAmmo, requestId, expectedMagId)
end)

RegisterNetEvent('vMagazine:server:performReload', function(weaponSlot, magSlot, isDragDrop, clientAmmo, requestId, expectedMagId)
    local src = source
    local result = PerformReload(src, weaponSlot, magSlot, isDragDrop == true, clientAmmo, requestId, expectedMagId)

    TriggerClientEvent('vMagazine:client:reloadResult', src, result)
end)

exports('GiveMagazine', function(playerId, magType, amount, customData)
    local magazineData = Config.MagazineTypes[magType]

    if not magazineData and magType and not string.find(magType, 'magazine-') then
        magazineData = Config.MagazineTypes['magazine-' .. magType]

        if magazineData then
            magType = 'magazine-' .. magType
        end
    end

    if not magazineData then
        return false
    end

    amount = math.max(1, math.floor(tonumber(amount) or 1))

    customData = type(customData) == 'table' and customData or nil
    
    local maxAmmo = magazineData.magSize
    local added = 0

    for i = 1, amount do
        local newMagazineMetadata = getMagazineMetadata(magType, maxAmmo, customData)
        
        newMagazineMetadata.id = newMagazineId(playerId)
        
        if not exports.ox_inventory:AddItem(playerId, 'magazine', 1, newMagazineMetadata) then
            return false, added
        end
        
        added = added + 1
    end
    return true, added
end)
