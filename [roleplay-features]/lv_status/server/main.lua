local ESX = exports['es_extended']:getSharedObject()

local function clamp(val, min, max)
    return math.max(min, math.min(max, val))
end

local function debugPrint(...)
    if Config.Debug then
        print(...)
    end
end

local PlayerStatus = {}
local LoadingStatus = {}
local FlushInProgress = false

local function markDirty(data)
    data.version = (data.version or 0) + 1
    data.dirty = true
end

local function saveStatusNow(data)
    if not data or not data.identifier then
        return false
    end

    while FlushInProgress do
        Wait(0)
    end

    local savedVersion = data.version or 0
    local success, result = pcall(
        DB_SaveStatus,
        data.identifier,
        data.hunger,
        data.thirst,
        data.stress,
        data.lastStressAt,
        data.addiction,
        data.lastAddictionAt
    )

    if success and data.version == savedVersion then
        data.dirty = false
    end

    if not success then
        print(('[lv_status] Failed to save %s: %s'):format(data.identifier, tostring(result)))
    end
    return success
end

local function flushDirtyStatuses(forceAll)
    if FlushInProgress then
        if not forceAll then
            return 0
        end

        while FlushInProgress do
            Wait(0)
        end
    end

    local rows = {}
    local snapshots = {}

    for _, data in pairs(PlayerStatus) do
        if data.identifier and (forceAll or data.dirty) then
            rows[#rows + 1] =
            {
                identifier = data.identifier,
                hunger = data.hunger,
                thirst = data.thirst,
                stress = data.stress,
                lastStressAt = data.lastStressAt,
                addiction = data.addiction,
                lastAddictionAt = data.lastAddictionAt
            }
            snapshots[data.identifier] =
            {
                data = data,
                version = data.version or 0
            }
        end
    end

    if #rows == 0 then
        return 0
    end

    FlushInProgress = true

    local success, result = pcall(DB_SaveStatuses, rows)

    FlushInProgress = false

    if not success then
        print(('[lv_status] Failed to flush %d statuses: %s'):format(#rows, tostring(result)))
        return 0
    end

    for identifier, snapshot in pairs(snapshots) do
        local data = snapshot.data

        if data.identifier == identifier and data.version == snapshot.version then
            data.dirty = false
        end
    end
    return #rows
end

local function GetIdentifier(src)
    local xPlayer = ESX.GetPlayerFromId(src)

    if xPlayer then
        return xPlayer.getIdentifier()
    end
    return nil
end

local function loadPlayerStatus(src, identifier, callback)
    local current = PlayerStatus[src]

    if current and current.identifier == identifier then
        callback(current)
        return
    end

    local pending = LoadingStatus[src]

    if pending and pending.identifier == identifier then
        pending.callbacks[#pending.callbacks + 1] = callback
        return
    end

    pending =
    {
        identifier = identifier,
        callbacks =
        {
            callback
        }
    }

    LoadingStatus[src] = pending

    DB_LoadStatus(identifier, function(hunger, thirst, stress, lastStressAt, addiction, lastAddictionAt)
        if LoadingStatus[src] ~= pending then
            return
        end

        LoadingStatus[src] = nil

        if GetIdentifier(src) ~= identifier then
            return
        end

        local data = PlayerStatus[src]

        if not data or data.identifier ~= identifier then
            local now = os.time()

            lastStressAt = tonumber(lastStressAt) or 0

            if lastStressAt <= 0 then
                lastStressAt = now
            end

            lastAddictionAt = tonumber(lastAddictionAt) or 0

            if lastAddictionAt <= 0 then
                lastAddictionAt = now
            end

            local elapsed = math.max(0, now - lastAddictionAt)
            local decaySteps = 0

            if addiction > 0 and elapsed >= Config.AddictionDecayDelay then
                decaySteps = math.floor(
                    (elapsed - Config.AddictionDecayDelay) / Config.AddictionDecayInterval
                ) + 1

                addiction = clamp(
                    addiction - (decaySteps * Config.AddictionDecayAmount),
                    0,
                    100
                )
            end

            local stressElapsed = math.max(0, now - lastStressAt)
            local stressDecaySteps = 0

            if stress > 0 and stressElapsed >= Config.StressDecayDelay then
                stressDecaySteps = math.floor(
                    (stressElapsed - Config.StressDecayDelay) / Config.StressDecayInterval
                ) + 1
                stress = clamp(
                    stress - (stressDecaySteps * Config.StressDecayAmount),
                    0,
                    100
                )
            end

            data =
            {
                identifier = identifier,
                hunger = hunger,
                thirst = thirst,
                stress = stress,
                lastStressAt = lastStressAt,
                nextStressDecayAt = lastStressAt
                    + Config.StressDecayDelay
                    + (stressDecaySteps * Config.StressDecayInterval),
                addiction = addiction,
                lastAddictionAt = lastAddictionAt,
                nextAddictionDecayAt = lastAddictionAt
                    + Config.AddictionDecayDelay
                    + (decaySteps * Config.AddictionDecayInterval),
                version = 0,
                dirty = decaySteps > 0 or stressDecaySteps > 0
            }

            if decaySteps > 0 or stressDecaySteps > 0 then
                data.version = 1
            end

            PlayerStatus[src] = data
        end

        for i = 1, #pending.callbacks do
            pending.callbacks[i](data)
        end
    end)
end

AddEventHandler('esx:playerLoaded', function(src)
    local identifier = GetIdentifier(src)

    if not identifier then
        return
    end

    loadPlayerStatus(src, identifier, function(data)
        TriggerClientEvent(
            'lv_status:client:setStatus',
            src,
            data.hunger,
            data.thirst,
            data.stress,
            data.addiction,
            data.lastAddictionAt
        )
    end)
end)

local function unloadPlayer(src)
    src = tonumber(src)

    if not src then
        return
    end

    LoadingStatus[src] = nil

    local data = PlayerStatus[src]

    if data and Config.SaveOnDisconnect then
        saveStatusNow(data)
    end

    PlayerStatus[src] = nil
end

AddEventHandler('esx:playerDropped', function(src)
    unloadPlayer(src)
end)

AddEventHandler('playerDropped', function()
    unloadPlayer(source)
end)

RegisterNetEvent('lv_status:server:requestStatus', function()
    local src        = source
    local identifier = GetIdentifier(src)

    if not identifier then
        return
    end

    if PlayerStatus[src] then
        TriggerClientEvent('lv_status:client:setStatus', src,
            PlayerStatus[src].hunger,
            PlayerStatus[src].thirst,
            PlayerStatus[src].stress,
            PlayerStatus[src].addiction,
            PlayerStatus[src].lastAddictionAt)
        return
    end

    loadPlayerStatus(src, identifier, function(data)
        TriggerClientEvent(
            'lv_status:client:setStatus',
            src,
            data.hunger,
            data.thirst,
            data.stress,
            data.addiction,
            data.lastAddictionAt
        )
    end)
end)

RegisterNetEvent('lv_status:server:syncStatus', function(hunger, thirst)
    local src = source

    hunger = clamp(tonumber(hunger) or 0, 0, 100)
    thirst = clamp(tonumber(thirst) or 0, 0, 100)

    if PlayerStatus[src] then
        local data = PlayerStatus[src]

        if data.hunger ~= hunger or data.thirst ~= thirst then
            data.hunger = hunger
            data.thirst = thirst

            markDirty(data)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(Config.SaveInterval)

        local saved = flushDirtyStatuses(false)
    end
end)

local function CalculateStatusChange(itemCfg, durability)
    durability = tonumber(durability) or 100

    local hungerAdded = itemCfg.hunger or 0
    local thirstAdded = itemCfg.thirst or 0

    if hungerAdded > 0 then
        hungerAdded = math.max(0, math.floor(hungerAdded * (durability / 100)))
    end

    if thirstAdded > 0 then
        thirstAdded = math.max(0, math.floor(thirstAdded * (durability / 100)))
    end

    if itemCfg.type == 'food' and durability < 100 then
        local thirstPenalty = math.floor(30 * (1.0 - (durability / 100))) 
    end

    if hungerAdded < 0 then
        hungerAdded = math.floor(hungerAdded * (2.0 - (durability / 100)))
    end

    if thirstAdded < 0 and itemCfg.type ~= 'food' then
        thirstAdded = math.floor(thirstAdded * (2.0 - (durability / 100)))
    end
    return hungerAdded, thirstAdded
end


RegisterNetEvent('lv_status:server:consume', function(itemName, durability)
    local src = source
    local itemCfg = Config.Items[itemName]
    local durability = tonumber(durability) or 100

    if not itemCfg then
        return
    end

    local data = PlayerStatus[src]

    if not data then
        return
    end

    local hAdd, tAdd = CalculateStatusChange(itemCfg, durability)

    data.hunger = clamp(data.hunger + hAdd, 0, 100)
    data.thirst = clamp(data.thirst + tAdd, 0, 100)

    markDirty(data)

    TriggerClientEvent('lv_status:client:updateAfterConsume', src,
        data.hunger, data.thirst, itemName, durability)
end)

for itemName, itemCfg in pairs(Config.Items) do
    ESX.RegisterUsableItem(itemName, function(source, item)
        local src = source

        local identifier = GetIdentifier(src)

        if not identifier then
            return
        end

        local durability = 100

        if item and item.metadata and item.metadata.durability then
            durability = tonumber(item.metadata.durability) or 100
        end

        if not PlayerStatus[src] then
            loadPlayerStatus(src, identifier, function(data)
                if exports.ox_inventory:RemoveItem(src, itemName, 1) then
                    local hAdd, tAdd = CalculateStatusChange(itemCfg, durability)

                    data.hunger = clamp(data.hunger + hAdd, 0, 100)
                    data.thirst = clamp(data.thirst + tAdd, 0, 100)

                    markDirty(data)

                    TriggerClientEvent('lv_status:client:updateAfterConsume', src, data.hunger, data.thirst, itemName, durability)
                else
                    debugPrint(('[lv_status] Failed to remove item %s from %s (after DB load)'):format(itemName, tostring(src)))
                end
            end)
            return
        end

        local data = PlayerStatus[src]

        if exports.ox_inventory:RemoveItem(src, itemName, 1) then
            local hAdd, tAdd = CalculateStatusChange(itemCfg, durability)

            data.hunger = clamp(data.hunger + hAdd, 0, 100)
            data.thirst = clamp(data.thirst + tAdd, 0, 100)

            markDirty(data)

            TriggerClientEvent('lv_status:client:updateAfterConsume', src, data.hunger, data.thirst, itemName, durability)
        else
            debugPrint(('[lv_status] Failed to remove item %s from %s'):format(itemName, tostring(src)))
        end
    end)
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    print('^1[lv_status]^0 Saving player statuses before resource stops...')

    flushDirtyStatuses(true)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    local count = 0

    for _ in pairs(Config.Items) do
        count = count + 1
    end

    print(('^2[lv_status]^0 Khoi Dong — %d Items an uong san sang'):format(count))
end)

exports('GetPlayerHunger', function(src)
    return PlayerStatus[src] and PlayerStatus[src].hunger or 100
end)

exports('GetPlayerThirst', function(src)
    return PlayerStatus[src] and PlayerStatus[src].thirst or 100
end)

exports('SetPlayerHunger', function(src, val)
    src = tonumber(src)

    if not src or not PlayerStatus[src] then
        return false
    end

    PlayerStatus[src].hunger = clamp(tonumber(val) or 0, 0, 100)

    markDirty(PlayerStatus[src])

    TriggerClientEvent('lv_status:client:setStatus', src,
        PlayerStatus[src].hunger,
        PlayerStatus[src].thirst,
        PlayerStatus[src].stress,
        PlayerStatus[src].addiction,
        PlayerStatus[src].lastAddictionAt)
    return true
end)

exports('SetPlayerThirst', function(src, val)
    src = tonumber(src)

    if not src or not PlayerStatus[src] then
        return false
    end

    PlayerStatus[src].thirst = clamp(tonumber(val) or 0, 0, 100)

    markDirty(PlayerStatus[src])

    TriggerClientEvent('lv_status:client:setStatus', src,
        PlayerStatus[src].hunger,
        PlayerStatus[src].thirst,
        PlayerStatus[src].stress,
        PlayerStatus[src].addiction,
        PlayerStatus[src].lastAddictionAt)
    return true
end)

local function updatePlayerStatus(src, statusName, value)
    src = tonumber(src)

    local data = src and PlayerStatus[src]

    if not data then
        return false
    end

    local oldValue = data[statusName]
    local newValue = clamp(tonumber(value) or 0, 0, 100)

    data[statusName] = newValue

    if statusName == 'addiction' and newValue >= oldValue then
        data.lastAddictionAt = os.time()
        data.nextAddictionDecayAt = data.lastAddictionAt + Config.AddictionDecayDelay
    elseif statusName == 'stress' and newValue >= oldValue then
        data.lastStressAt = os.time()
        data.nextStressDecayAt = data.lastStressAt + Config.StressDecayDelay
    end

    markDirty(data)

    TriggerClientEvent(
        'lv_status:client:setStatus',
        src,
        data.hunger,
        data.thirst,
        data.stress,
        data.addiction,
        data.lastAddictionAt
    )

    if statusName == 'stress' and newValue > oldValue then
        TriggerClientEvent('lv_notify:client:notify', src,
        {
            title = 'Stress',
            message = ('Mức độ căng thẳng tăng +%d'):format(newValue - oldValue),
            type = 'warning',
            duration = 3000,
            position = 'top-right'
        })
    end
    return true
end

local function touchPlayerAddiction(src)
    src = tonumber(src)

    local data = src and PlayerStatus[src]

    if not data then
        return false
    end

    local now = os.time()

    if now - (data.lastAddictionAt or 0) < Config.AddictionTouchCooldown then
        return true
    end

    data.lastAddictionAt = now
    data.nextAddictionDecayAt = now + Config.AddictionDecayDelay

    markDirty(data)

    TriggerClientEvent(
        'lv_status:client:setStatus',
        src,
        data.hunger,
        data.thirst,
        data.stress,
        data.addiction,
        data.lastAddictionAt
    )
    return true
end

CreateThread(function()
    while true do
        Wait(60 * 1000)

        local now = os.time()

        for src, data in pairs(PlayerStatus) do
            if data.stress > 0
                and data.nextStressDecayAt
                and now >= data.nextStressDecayAt
            then
                local stressDecaySteps = math.floor(
                    (now - data.nextStressDecayAt) / Config.StressDecayInterval
                ) + 1
                local newStress = clamp(
                    data.stress - (stressDecaySteps * Config.StressDecayAmount),
                    0,
                    100
                )

                data.nextStressDecayAt = data.nextStressDecayAt
                    + (stressDecaySteps * Config.StressDecayInterval)

                if newStress ~= data.stress then
                    data.stress = newStress

                    markDirty(data)

                    TriggerClientEvent(
                        'lv_status:client:setStatus',
                        src,
                        data.hunger,
                        data.thirst,
                        data.stress,
                        data.addiction,
                        data.lastAddictionAt
                    )
                end
            end

            if data.addiction > 0
                and data.nextAddictionDecayAt
                and now >= data.nextAddictionDecayAt
            then
                local decaySteps = math.floor(
                    (now - data.nextAddictionDecayAt) / Config.AddictionDecayInterval
                ) + 1
                local newValue = clamp(
                    data.addiction - (decaySteps * Config.AddictionDecayAmount),
                    0,
                    100
                )

                data.nextAddictionDecayAt = data.nextAddictionDecayAt
                    + (decaySteps * Config.AddictionDecayInterval)

                if newValue ~= data.addiction then
                    data.addiction = newValue

                    markDirty(data)

                    TriggerClientEvent(
                        'lv_status:client:setStatus',
                        src,
                        data.hunger,
                        data.thirst,
                        data.stress,
                        data.addiction,
                        data.lastAddictionAt
                    )
                end
            end
        end
    end
end)

exports('GetPlayerStress', function(src)
    src = tonumber(src)
    return src and PlayerStatus[src] and PlayerStatus[src].stress or Config.DefaultStress
end)

exports('SetPlayerStress', function(src, value)
    return updatePlayerStatus(src, 'stress', value)
end)

exports('AddPlayerStress', function(src, amount)
    src = tonumber(src)

    local data = src and PlayerStatus[src]

    if not data then
        return false
    end

    return updatePlayerStatus(src, 'stress', data.stress + math.abs(tonumber(amount) or 0))
end)

RegisterNetEvent('lv_status:server:addStress', function(amount)
    local src = source

    amount = tonumber(amount) or 0

    if amount <= 0 then
        return
    end

    exports['lv_status']:AddPlayerStress(src, amount)
end)

RegisterNetEvent('lv_status:server:setStress', function(val)
    local src = source

    exports['lv_status']:SetPlayerStress(src, tonumber(val) or 0)
end)

RegisterNetEvent('lv_status:server:addJobStress', function(isDirty)
    local src = source

    TriggerClientEvent('lv_status:client:addJobStress', src, isDirty == true)
end)

exports('RemovePlayerStress', function(src, amount)
    src = tonumber(src)

    local data = src and PlayerStatus[src]

    if not data then
        return false
    end
    return updatePlayerStatus(src, 'stress', data.stress - math.abs(tonumber(amount) or 0))
end)

exports('GetPlayerAddiction', function(src)
    src = tonumber(src)
    return src and PlayerStatus[src] and PlayerStatus[src].addiction or Config.DefaultAddiction
end)

exports('SetPlayerAddiction', function(src, value)
    return updatePlayerStatus(src, 'addiction', value)
end)

exports('AddPlayerAddiction', function(src, amount)
    src = tonumber(src)

    local data = src and PlayerStatus[src]

    if not data then
        return false
    end
    return updatePlayerStatus(src, 'addiction', data.addiction + math.abs(tonumber(amount) or 0))
end)

exports('RemovePlayerAddiction', function(src, amount)
    src = tonumber(src)

    local data = src and PlayerStatus[src]

    if not data then
        return false
    end
    return updatePlayerStatus(src, 'addiction', data.addiction - math.abs(tonumber(amount) or 0))
end)

exports('TouchPlayerAddiction', function(src)
    return touchPlayerAddiction(src)
end)

exports('GetStress', function(src)
    src = tonumber(src)
    return src and PlayerStatus[src] and PlayerStatus[src].stress or Config.DefaultStress
end)

exports('SetStress', function(src, value)
    return updatePlayerStatus(src, 'stress', value)
end)

exports('AddStress', function(src, amount)
    src = tonumber(src)

    local data = src and PlayerStatus[src]

    if not data then
        return false
    end
    return updatePlayerStatus(src, 'stress', data.stress + math.abs(tonumber(amount) or 0))
end)

exports('RemoveStress', function(src, amount)
    src = tonumber(src)

    local data = src and PlayerStatus[src]

    if not data then
        return false
    end
    return updatePlayerStatus(src, 'stress', data.stress - math.abs(tonumber(amount) or 0))
end)

exports('GetAddiction', function(src)
    src = tonumber(src)
    return src and PlayerStatus[src] and PlayerStatus[src].addiction or Config.DefaultAddiction
end)

exports('SetAddiction', function(src, value)
    return updatePlayerStatus(src, 'addiction', value)
end)

exports('AddAddiction', function(src, amount)
    src = tonumber(src)

    local data = src and PlayerStatus[src]

    if not data then
        return false
    end
    return updatePlayerStatus(src, 'addiction', data.addiction + math.abs(tonumber(amount) or 0))
end)

exports('RemoveAddiction', function(src, amount)
    src = tonumber(src)

    local data = src and PlayerStatus[src]

    if not data then
        return false
    end
    return updatePlayerStatus(src, 'addiction', data.addiction - math.abs(tonumber(amount) or 0))
end)

exports('TouchAddiction', function(src)
    return touchPlayerAddiction(src)
end)

exports('useItem', function(event, item, inventory, slot)
    if event == 'usedItem' then
        local src = inventory.id
        local itemName = item.name
        local itemCfg = Config.Items[itemName]

        if not itemCfg then
            return
        end

        local identifier = GetIdentifier(src)

        if not identifier then
            return
        end

        local durability = 100

        if item and item.metadata and item.metadata.durability then
            durability = tonumber(item.metadata.durability) or 100
        end

        if not PlayerStatus[src] then
            loadPlayerStatus(src, identifier, function(data)
                local hAdd, tAdd = CalculateStatusChange(itemCfg, durability)

                data.hunger = clamp(data.hunger + hAdd, 0, 100)
                data.thirst = clamp(data.thirst + tAdd, 0, 100)

                markDirty(data)

                TriggerClientEvent('lv_status:client:updateAfterConsume', src, data.hunger, data.thirst, itemName, durability)
            end)
            return
        end

        local data = PlayerStatus[src]
        local hAdd, tAdd = CalculateStatusChange(itemCfg, durability)

        data.hunger = clamp(data.hunger + hAdd, 0, 100)
        data.thirst = clamp(data.thirst + tAdd, 0, 100)

        markDirty(data)
        
        TriggerClientEvent('lv_status:client:updateAfterConsume', src, data.hunger, data.thirst, itemName, durability)
    end
end)
