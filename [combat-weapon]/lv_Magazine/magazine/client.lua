local Config = require 'magazine.config'

local currentMag =
{
    prop = 0,
    item = nil,
    slot = -1,
    metadata = {}
}
local isReloading = false
local lastReloadAttempt = 0
local validatedWeaponSlot = nil
local reloadRequestCounter = 0
local reloadControlLockRunning = false

local function Notify(data)
    data = data or {}

    local isError = (data.type == 'error')

    if not isError and not Config.EnableNotifications and not data.force then
        return
    end

    if GetResourceState('lv_notify') == 'started' then
        exports['lv_notify']:Notify(
        {
            type = data.type or 'info',
            title = data.title or 'Băng Đạn',
            message = data.description or data.message or 'Thông Báo',
            duration = data.duration or 3000
        })
        return
    end

    lib.notify(data)
end

local function nextReloadRequestId(weaponSlot, magazineId)
    reloadRequestCounter = reloadRequestCounter + 1

    return ('reload:%s:%s:%s:%s'):format(
        cache.serverId or GetPlayerServerId(cache.playerId),
        GetGameTimer(),
        weaponSlot or 0,
        magazineId or reloadRequestCounter
    )
end

local function startReloadControlLock()
    if reloadControlLockRunning then
        return
    end

    reloadControlLockRunning = true

    CreateThread(function()
        while isReloading do
            DisablePlayerFiring(cache.playerId, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 45, true)
            Wait(0)
        end

        reloadControlLockRunning = false
    end)
end

local function getCanonicalAmmoContext(result)
    if not result or not result.success or not result.weaponName then
        return
    end

    local currentWeapon = exports.ox_inventory:getCurrentWeapon()

    if not currentWeapon
        or currentWeapon.name ~= result.weaponName
        or (result.weaponSlot and currentWeapon.slot ~= result.weaponSlot)
    then
        return
    end

    local ped = cache.ped
    local weaponHash = currentWeapon.hash or joaat(result.weaponName)
    local ammo = math.max(0, math.floor(tonumber(result.ammo) or 0))

    return currentWeapon, ped, weaponHash, ammo
end

local function applyMagazineComponents(result, ped, weaponHash)
    if result.removedComponent and result.removedComponent ~= result.newComponent then
        local removedHash = joaat(result.removedComponent)

        if HasPedGotWeaponComponent(ped, weaponHash, removedHash) then
            RemoveWeaponComponentFromPed(ped, weaponHash, removedHash)
        end
    end

    if result.newComponent then
        local componentHash = joaat(result.newComponent)

        if DoesWeaponTakeWeaponComponent(weaponHash, componentHash)
            and not HasPedGotWeaponComponent(ped, weaponHash, componentHash)
        then
            GiveWeaponComponentToPed(ped, weaponHash, componentHash)
        end
    end
end

local function applyCanonicalAmmo(result)
    local currentWeapon, ped, weaponHash, ammo = getCanonicalAmmoContext(result)

    if not currentWeapon then
        return false
    end

    applyMagazineComponents(result, ped, weaponHash)

    local existingTotal = GetAmmoInPedWeapon(ped, weaponHash)
    local _, existingClip = GetAmmoInClip(ped, weaponHash)

    if existingTotal == ammo and existingClip == ammo then
        return true
    end

    SetPedAmmo(ped, weaponHash, 0)

    if ammo == 0 then
        return GetAmmoInPedWeapon(ped, weaponHash) == 0
    end

    SetPedAmmo(ped, weaponHash, ammo)

    for _ = 1, 10 do
        local activeWeapon = exports.ox_inventory:getCurrentWeapon()

        if not activeWeapon or activeWeapon.hash ~= weaponHash then
            return false
        end

        RefillAmmoInstantly(ped)

        local totalAmmo = GetAmmoInPedWeapon(ped, weaponHash)
        local _, clipAmmo = GetAmmoInClip(ped, weaponHash)

        if totalAmmo == ammo and clipAmmo == ammo then
            return true
        end

        Wait(50)
    end

    -- One bounded retry from a clean native state. Never write clip ammo directly;
    -- SetAmmoInClip is what previously created reserve ammunition intermittently.
    SetPedAmmo(ped, weaponHash, 0)
    Wait(0)
    SetPedAmmo(ped, weaponHash, ammo)

    for _ = 1, 5 do
        RefillAmmoInstantly(ped)
        Wait(50)
    end

    local totalAmmo = GetAmmoInPedWeapon(ped, weaponHash)
    local _, clipAmmo = GetAmmoInClip(ped, weaponHash)

    if totalAmmo == ammo and clipAmmo == ammo then
        return true
    end

    TriggerEvent('ox_inventory:disarm', true)
    Notify(
    {
        type = 'error',
        force = true,
        description = ('Ổ đạn của %s không tương thích sức chứa %d; vũ khí đã được cất để tránh sai đạn'):format(result.weaponName, ammo)
    })

    return false
end

local function playReloadAnimation(result)
    local currentWeapon, ped, weaponHash, ammo = getCanonicalAmmoContext(result)

    if not currentWeapon then
        return false
    end

    if ammo == 0 or IsPedDeadOrDying(ped, true) then
        return applyCanonicalAmmo(result)
    end

    isReloading = true
    startReloadControlLock()
    applyMagazineComponents(result, ped, weaponHash)

    -- Keep the incoming rounds in reserve so GTA can play its weapon-specific
    -- reload task. The canonical pass below fills the clip and removes reserve.
    SetPedAmmo(ped, weaponHash, 0)
    Wait(0)
    AddAmmoToPed(ped, weaponHash, ammo)
    Wait(100)

    if cache.vehicle then
        TaskReloadWeapon(ped, true)
    else
        MakePedReload(ped)
    end

    local issuedAt = GetGameTimer()
    local startDeadline = issuedAt + (Config.WeaponReloadStartTimeout or 1000)
    local finishDeadline = issuedAt + (Config.WeaponReloadTimeout or 5000)
    local reloadStarted = false
    local forcedTask = cache.vehicle and true or false

    while GetGameTimer() < finishDeadline do
        local activeWeapon = exports.ox_inventory:getCurrentWeapon()

        if not activeWeapon
            or activeWeapon.hash ~= weaponHash
            or IsPedDeadOrDying(ped, true)
        then
            return false
        end

        if IsPedReloading(ped) then
            reloadStarted = true
        elseif reloadStarted then
            break
        elseif GetGameTimer() >= startDeadline then
            if forcedTask then
                break
            end

            TaskReloadWeapon(ped, true)
            forcedTask = true
            startDeadline = GetGameTimer() + (Config.WeaponReloadStartTimeout or 1000)
        end

        Wait(0)
    end

    return applyCanonicalAmmo(result)
end

local function loadAnimDict(dict)
    if not dict or HasAnimDictLoaded(dict) then
        return true
    end

    RequestAnimDict(dict)

    local timeout = 0

    while not HasAnimDictLoaded(dict) and timeout < 30 do
        Wait(20)

        timeout = timeout + 1
    end
    return HasAnimDictLoaded(dict)
end

local function getPackAnimation()
    local anim = Config.PackAnimation or {}
    local dict = anim.dict or 'anim@cover@weapons@reloads@pistol@gadget_pistol@'
    local clip = anim.clip or 'reload_low_left'

    if loadAnimDict(dict) then
        return dict, clip, anim.flag or 49
    end

    local fallbackDict = anim.fallbackDict or 'mp_common'
    local fallbackClip = anim.fallbackClip or 'givetake1_a'
    if loadAnimDict(fallbackDict) then
        return fallbackDict, fallbackClip, anim.flag or 49
    end

    return nil, nil, nil
end

local function playPackAnimation(dict, clip, flag)
    if not dict or not clip then
        return
    end

    TaskPlayAnim(
        cache.ped,
        dict,
        clip,
        4.0,
        -4.0,
        math.max((Config.MagazineReloadTime or 400) + 100, 550),
        flag or 49,
        0.0,
        false,
        false,
        false
    )
end

local function assertMetadata(metadata)
    if metadata and type(metadata) ~= 'table' then
        metadata =
        {
            type = metadata
        }
    end
    return metadata
end

function ReturnFirstOrderedItem(itemName, metadata, strict)
    local inventory = exports.ox_inventory:Search('slots', 'magazine') or {}
    local item = exports.ox_inventory:Items(itemName)

    if item then
        return exports.ox_inventory:GetSlotIdWithItem(itemName, {}, strict)
    else
        local matchedItems = {}

        metadata = assertMetadata(metadata)

        local tablematch = strict and lib.table.matches or lib.table.contains

        for _, slotData in pairs(inventory) do
            if slotData and slotData.metadata then
                local isMagTypeCompatible = slotData.metadata.magType == itemName

                if (slotData.metadata.ammo or 0) > 0 and isMagTypeCompatible and (not metadata or tablematch(slotData.metadata, metadata)) then
                    table.insert(matchedItems, slotData)
                end
            end
        end

        if #matchedItems == 0 then
            return
        end

        table.sort(matchedItems, function(a, b)
            return (a.metadata.ammo or 0) > (b.metadata.ammo or 0)
        end)
        return matchedItems[1].slot
    end
end
exports('ReturnFirstOrderedItem', ReturnFirstOrderedItem)

local disablePunchThreadRunning = false
local function StartDisablePunchLoop()
    if disablePunchThreadRunning then
        return
    end

    disablePunchThreadRunning = true

    CreateThread(function()
        while currentMag.prop ~= 0 and DoesEntityExist(currentMag.prop) do
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)

            Wait(0)
        end

        disablePunchThreadRunning = false
    end)
end

local function detachMagazine()
    if currentMag.prop ~= 0 then
        if DoesEntityExist(currentMag.prop) then
            DetachEntity(currentMag.prop, true, true)
            DeleteEntity(currentMag.prop)
        end

        TriggerEvent('ox_inventory:itemNotify',
        {
            currentMag.item, 'ui_holstered'
        })

        if Config.UseStatusLabelPrefix then
            TriggerServerEvent('vMagazine:server:updateMagazineLabel', currentMag.slot, true)
        end

        currentMag =
        {
            prop = 0,
            item = nil,
            slot = nil,
            metadata = {}
        }
    end
end

local function attachMagazine(data, context)
    local weapon = exports.ox_inventory:getCurrentWeapon()

    if weapon then
        TriggerEvent('ox_inventory:disarm', false)
    end

    if currentMag.prop ~= 0 then
        detachMagazine()
    end

    currentMag =
    {
        prop = 0,
        item = context,
        slot = context.slot,
        metadata = table.clone(context.metadata or {})
    }

    CreateThread(function()
        local modelName = context.metadata and context.metadata.model or 'w_pi_combatpistol_mag1'
        local modelHash = joaat(type(modelName) == 'string' and modelName or 'w_pi_combatpistol_mag1')

        if not IsModelInCdimage(modelHash) or not IsModelValid(modelHash) then
            modelHash = joaat('w_pi_combatpistol_mag1')
        end

        RequestModel(modelHash)

        local timeout = 0

        while not HasModelLoaded(modelHash) and timeout < 20 do
            Wait(10)

            timeout = timeout + 1
        end

        currentMag.prop = CreateObject(modelHash, 0.0, 0.0, 0.0, true, true, false)

        AttachEntityToEntity(currentMag.prop, cache.ped, GetPedBoneIndex(cache.ped, 18905), 0.109, 0.086, -0.023, 63.75, 180.3, -184.2, true, true, false, true, 1, true)
        
        SetModelAsNoLongerNeeded(modelHash)

        if Config.UseStatusLabelPrefix then
            TriggerServerEvent('vMagazine:server:updateMagazineLabel', context.slot, false)
        end

        StartDisablePunchLoop()

        TriggerEvent('ox_inventory:itemNotify',
        {
            context, 'ui_equipped'
        })
    end)
end

local function packMagazine(data)
    local resp = currentMag.item

    if not resp or not resp.metadata then
        return
    end

    if isReloading then
        return
    end

    isReloading = true

    SetTimeout(30000, function()
        if isReloading then
            isReloading = false
        end
    end)

    local ammoType = resp.metadata.ammoType

    if not ammoType then
        isReloading = false
        return
    end

    local bulletsAddedToMag = 0
    local initialAvailableAmmo = exports.ox_inventory:Search('count', ammoType)
    local currentAmmoInMag = resp.metadata.ammo or 0
    local magSize = resp.metadata.magSize or 15

    if initialAvailableAmmo <= 0 then
        Notify(
        {
            id = 'pack_failed',
            type = 'error',
            description = 'Không có đạn tương thích để nạp'
        })

        isReloading = false
        return
    end

    if currentAmmoInMag >= magSize then
        Notify(
        {
            id = 'pack_full',
            type = 'error',
            description = 'Băng đạn đã đầy'
        })

        isReloading = false
        return
    end

    CreateThread(function()
        local animDict, animName, animFlag = getPackAnimation()

        while isReloading do
            if not DoesEntityExist(currentMag.prop) then
                isReloading = false
                break
            end

            if (currentAmmoInMag + bulletsAddedToMag) >= magSize then
                Notify(
                {
                    id = 'pack_full',
                    type = 'success',
                    description = 'Băng đạn đã được nạp đầy'
                })
                break
            end

            if bulletsAddedToMag >= initialAvailableAmmo then
                Notify(
                {
                    id = 'pack_no_more',
                    type = 'error',
                    description = 'Đã hết đạn để có thể tiếp tục nạp'
                })
                break
            end

            playPackAnimation(animDict, animName, animFlag)

            local success = lib.progressCircle(
            {
                duration = Config.MagazineReloadTime or 400,
                position = 'bottom',
                label = ('Đang Lắp Đạn (%d/%d)...'):format(currentAmmoInMag + bulletsAddedToMag + 1, magSize),
                useWhileDead = false,
                canCancel = true,
                disable =
                {
                    move = false,
                    car = false,
                    combat = true,
                    mouse = false
                }
            })

            if success then
                bulletsAddedToMag = bulletsAddedToMag + 1
            else
                break
            end
        end

        if animDict and animName then
            StopAnimTask(cache.ped, animDict, animName, 1.0)
        end

        if bulletsAddedToMag > 0 then
            local result = lib.callback.await('vMagazine:server:updateMagazine', false, 'loadMagazine', bulletsAddedToMag, resp.slot)

            if not result or not result.success then
                Notify(
                {
                    id = 'pack_error',
                    type = 'error',
                    description = 'Không thể cập nhật số lượng đạn'
                })
            end
        end

        detachMagazine()

        isReloading = false
    end)
end

local function equipMagazine(context)
    attachMagazine(nil, context)
end

exports('equipMagazine', equipMagazine)

local function unequipMagazine()
    detachMagazine()
end

exports('unequipMagazine', unequipMagazine)

local function IsPedEquippingOrHolstering()
    local ped = cache.ped
    local anims =
    {
        {
            dict = 'reaction@intimidation@1h',
            clip = 'intro'
        },
        {
            dict = 'reaction@intimidation@cop@unarmed',
            clip = 'intro'
        },
        {
            dict = 'combat@combat_reactions@pistol_1h_gang',
            clip = '0'
        },
        {
            dict = 'combat@combat_reactions@pistol_1h_hillbilly',
            clip = '0'
        },
        {
            dict = 'reaction@male_stand@big_variations@d',
            clip = 'react_big_variations_m'
        },
        {
            dict = 'melee@holster',
            clip = 'unholster'
        }
    }

    for i = 1, #anims do
        local anim = anims[i]

        if IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3) then
            return true
        end
    end
    return false
end

local function isWeaponCompatibleWithMag(weapon, magMetadata)
    if not weapon or not magMetadata then
        return false
    end
    
    local itemData = exports.ox_inventory:Items(weapon.name)
    local weaponAmmo = itemData and itemData.ammoname or weapon.ammo

    if not weaponAmmo then
        return false
    end

    local magType = magMetadata.magType or ''
    
    if magType == '' then
        return false
    end
    return weaponAmmo == magType
end

local function useMagazine(data, contextOrSlot, thirdArg)
    local isManualReload = (thirdArg == true)
    local context = type(contextOrSlot) == 'number' and thirdArg or contextOrSlot

    if not isManualReload then
        if currentMag.prop ~= 0 and DoesEntityExist(currentMag.prop) then
            detachMagazine()
        else
            attachMagazine(data, context)
        end
        return
    end

    local weapon = exports.ox_inventory:getCurrentWeapon()

    if not weapon then
        return
    end

    context = context or {}
    context.metadata = context.metadata or {}

    if not isWeaponCompatibleWithMag(weapon, context.metadata) then
        Notify(
        {
            id = 'no_magazine',
            type = 'error',
            description = 'Loại băng đạn không phù hợp với vũ khí này'
        })
        return
    end

    if isReloading or IsPedEquippingOrHolstering() or IsPedDeadOrDying(cache.ped, true) then
        return
    end

    isReloading = true
    startReloadControlLock()

    SetTimeout(
        (Config.TransactionTimeout or 5000) + (Config.WeaponReloadTimeout or 5000) + 1000,
        function()
            if isReloading then
                isReloading = false
            end
        end
    )

    local _, clipAmmo = GetAmmoInClip(cache.ped, weapon.hash)
    local magazineId = context.metadata.id
    local requestId = nextReloadRequestId(weapon.slot, magazineId)
    local callbackOk, result = pcall(function()
        return lib.callback.await(
            'vMagazine:server:performReload',
            false,
            weapon.slot,
            context.slot,
            clipAmmo,
            requestId,
            magazineId
        )
    end)

    if result and result.success then
        if result.animateReload then
            playReloadAnimation(result)
        else
            applyCanonicalAmmo(result)
        end
    elseif not callbackOk or not result then
        Notify(
        {
            type = 'error',
            force = true,
            description = 'Máy chủ không phản hồi thao tác thay băng; vũ khí và băng đạn được giữ nguyên'
        })
    end

    isReloading = false
end
exports('useMagazine', useMagazine)

AddEventHandler('ox_inventory:currentWeapon', function(currentWeapon)
    if currentWeapon and currentWeapon.name then
        detachMagazine()

        if currentWeapon.slot ~= validatedWeaponSlot then
            local itemData = exports.ox_inventory:Items(currentWeapon.name)
            local magType = itemData and itemData.ammoname

            if magType and Config.MagazineTypes[magType] then
                validatedWeaponSlot = currentWeapon.slot

                TriggerServerEvent('vMagazine:server:validateWeaponMagazine', currentWeapon.slot)
            end
        end

        if currentWeapon.metadata and currentWeapon.metadata.originalMagInfo and currentWeapon.metadata.originalMagInfo.component then
            local componentHash = joaat(currentWeapon.metadata.originalMagInfo.component)

            if not HasPedGotWeaponComponent(cache.ped, currentWeapon.hash, componentHash) then
                GiveWeaponComponentToPed(cache.ped, currentWeapon.hash, componentHash)
            end
        end
    else
        validatedWeaponSlot = nil
    end
end)

local function findBestMagazine(weapon)
    local items = exports.ox_inventory:Search('slots', 'magazine') or {}
    local bestMag = nil
    local highestAmmo = -1

    for _, item in pairs(items) do
        if item.metadata and isWeaponCompatibleWithMag(weapon, item.metadata) then
            local ammo = item.metadata.ammo or 0

            if ammo > highestAmmo then
                highestAmmo = ammo

                bestMag = item
            end
        end
    end
    return bestMag
end

local function weaponUsesMagazine(weapon)
    if not weapon or not weapon.name then
        return false
    end

    local itemData = exports.ox_inventory:Items(weapon.name)
    local ammoName = itemData and itemData.ammoname

    if not ammoName then
        return false
    end
    return Config.MagazineTypes[ammoName] ~= nil
end

CreateThread(function()
    while true do
        local weapon = exports.ox_inventory:getCurrentWeapon()

        if weaponUsesMagazine(weapon) then
            -- The mapped R key below is the only reload entrypoint for managed weapons.
            -- Blocking GTA's native reload prevents stale reserve ammo from racing it.
            DisableControlAction(0, 45, true)
            Wait(0)
        else
            Wait(250)
        end
    end
end)

lib.addKeybind(
{
    name = 'reloadweapon_addon',
    description = 'Nap Dan',
    defaultKey = 'r',
    onPressed = function(self)
        local currentTime = GetGameTimer()
        
        if (currentTime - lastReloadAttempt) < 800 then
            return
        end
        
        lastReloadAttempt = currentTime

        if isReloading or IsPedReloading(cache.ped) or IsPedEquippingOrHolstering() or IsPedDeadOrDying(cache.ped, true) then
            return
        end

        local weapon = exports.ox_inventory:getCurrentWeapon()

        if not weapon then
            if currentMag.prop ~= 0 and DoesEntityExist(currentMag.prop) then
                if currentMag.metadata and currentMag.metadata.ammoType then
                    local ammoCount = exports.ox_inventory:Search('count', currentMag.metadata.ammoType)

                    if ammoCount > 0 then
                        packMagazine(currentMag)
                    else
                        Notify(
                        {
                            id = 'no_ammo',
                            type = 'error',
                            description = 'Không có đạn tương thích trong túi đồ'
                        })
                    end
                end
            end
            return
        end

        if not weaponUsesMagazine(weapon) then
            return
        end

        weapon.metadata = weapon.metadata or {}

        local bestMag = findBestMagazine(weapon)

        if weapon.metadata.hasMagazine then
            local currentWepAmmo = type(weapon.metadata.ammo) == 'number' and weapon.metadata.ammo or 0

            if bestMag and (bestMag.metadata.ammo or 0) > currentWepAmmo then
                useMagazine(bestMag, bestMag, true)
            else
                Notify(
                {
                    id = 'no_better_mag',
                    type = 'error',
                    description = 'Không có băng đạn khác có nhiều đạn hơn băng hiện tại'
                })
            end
        else
            if bestMag and (bestMag.metadata.ammo or 0) > 0 then
                useMagazine(bestMag, bestMag, true)
            else
                Notify(
                {
                    id = 'no_mag',
                    type = 'error',
                    description = 'Không tìm thấy băng đạn phù hợp có đạn'
                })
            end
        end
    end
})

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        detachMagazine()
    end
end)

RegisterNetEvent('vMagazine:client:setAmmoZero', function(weaponHash)
    local currentWeapon = exports.ox_inventory:getCurrentWeapon()
    local hash = weaponHash or (currentWeapon and currentWeapon.hash)

    if currentWeapon and hash == currentWeapon.hash then
        applyCanonicalAmmo(
        {
            success = true,
            weaponName = currentWeapon.name,
            weaponSlot = currentWeapon.slot,
            ammo = 0
        })
    end
end)

RegisterNetEvent('vMagazine:client:syncWeaponAmmo', function(weaponHash, ammo)
    local weapon = exports.ox_inventory:getCurrentWeapon()

    if not weapon or weapon.hash ~= weaponHash then
        return
    end

    applyCanonicalAmmo(
    {
        success = true,
        weaponName = weapon.name,
        weaponSlot = weapon.slot,
        ammo = ammo
    })
end)

RegisterNetEvent('vMagazine:client:blockInvalidMagazine', function(weaponNameOrHash)
    local weapon = exports.ox_inventory:getCurrentWeapon()
    local weaponHash = type(weaponNameOrHash) == 'string' and joaat(weaponNameOrHash) or weaponNameOrHash

    if not weapon or weapon.hash ~= weaponHash then
        return
    end

    SetPedAmmo(cache.ped, weaponHash, 0)
    TriggerEvent('ox_inventory:disarm', true)
end)

RegisterNetEvent('vMagazine:client:reloadResult', function(result)
    if result and result.success then
        if result.animateReload then
            playReloadAnimation(result)
        else
            applyCanonicalAmmo(result)
        end
    end

    isReloading = false
end)

-- Compatibility for older callers while every in-resource path migrates to reloadResult.
RegisterNetEvent('vMagazine:client:reloadSuccess', function(weaponName, newAmmo, removedComponent, newComponent)
    local currentWeapon = exports.ox_inventory:getCurrentWeapon()

    applyCanonicalAmmo(
    {
        success = true,
        weaponName = weaponName,
        weaponSlot = currentWeapon and currentWeapon.slot,
        ammo = newAmmo,
        removedComponent = removedComponent,
        newComponent = newComponent
    })

    isReloading = false
end)

RegisterNetEvent('vMagazine:client:removeComponent', function(componentName)
    local playerPed = cache.ped
    local weapon = exports.ox_inventory:getCurrentWeapon()

    if not weapon or not componentName then
        return
    end

    local componentHash = joaat(componentName)

    if HasPedGotWeaponComponent(playerPed, weapon.hash, componentHash) then
        RemoveWeaponComponentFromPed(playerPed, weapon.hash, componentHash)
    end
end)

lib.callback.register('vMagazine:client:getCurrentClipAmmo', function(weaponHash)
    local currentWeapon = exports.ox_inventory:getCurrentWeapon()
    if currentWeapon and currentWeapon.hash == weaponHash then
        local _, clipAmmo = GetAmmoInClip(cache.ped, weaponHash)
        return clipAmmo
    end
    return nil
end)

local function unloadAmmo(data)
    if not data or not data.slot then
        return
    end

    TriggerServerEvent('vMagazine:server:unloadAmmo', data.slot)
end
exports('unloadAmmo', unloadAmmo)

RegisterCommand('removemag', function()
    local weapon = exports.ox_inventory:getCurrentWeapon()

    if not weapon or not weapon.metadata or not weapon.metadata.hasMagazine then
        Notify(
        {
            type = 'error',
            description = 'Bạn không cầm vũ khí có băng đạn trên tay'
        })
        return
    end

    local _, clipAmmo = GetAmmoInClip(cache.ped, weapon.hash)
    
    TriggerServerEvent('vMagazine:server:removeMagazine', weapon.slot, clipAmmo)
end, false)
