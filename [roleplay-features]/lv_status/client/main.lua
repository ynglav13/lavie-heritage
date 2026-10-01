--[[
    client/main.lua - Core logic client
    lv_status
--]]

local ESX = exports['es_extended']:getSharedObject()

local function debugPrint(...)
    if Config.Debug then
        print(...)
    end
end


local LocalData =
{
    hunger = Config.DefaultHunger,
    thirst = Config.DefaultThirst,
    stress = Config.DefaultStress,
    addiction = Config.DefaultAddiction,
    lastAddictionAt = 0,
    loaded = false,
    consuming = false,
}

local NotifyState =
{
    hungerWarn = false,
    hungerCrit = false,
    thirstWarn = false,
    thirstCrit = false,
    wellFed = false,
}


local function clamp(val, min, max)
    local n = tonumber(val) or 0
    return math.max(min, math.min(max, n))
end


exports('GetHunger',  function() return LocalData.hunger end)
exports('GetThirst',  function() return LocalData.thirst end)
exports('GetStress', function() return LocalData.stress end)
exports('GetAddiction', function() return LocalData.addiction end)
exports('SetHunger',  function(val)
    LocalData.hunger = clamp(val, 0, 100)

    SyncStatusToHud()
end)

exports('SetThirst',  function(val)
    LocalData.thirst = clamp(val, 0, 100)

    SyncStatusToHud()
end)


exports('useItem', function(data)
    local itemName = data and data.item and data.item.name

    if not itemName then
        return
    end

    if not Config.Items[itemName] then
        return
    end

    local durability = 100

    if data.item and data.item.metadata and data.item.metadata.durability then
        durability = tonumber(data.item.metadata.durability) or 100
    end

    ConsumeItem(itemName, durability)
end)


function SyncStatusToHud()
    TriggerEvent('esx_status:onTick',
    {
        {
            name = 'hunger',
            percent = LocalData.hunger
        },
        {
            name = 'thirst',
            percent = LocalData.thirst
        },
        {
            name = 'stress',
            percent = LocalData.stress
        },
    })
end

local function CheckAndNotify()
    local h = LocalData.hunger
    local t = LocalData.thirst

    if h < Config.CritThreshold then
        if not NotifyState.hungerCrit then
            NotifyState.hungerCrit = true
            NotifyState.hungerWarn = true

            FoodNotify.Error(Config.Notifications.hunger_crit, 7000)
        end
    elseif h < Config.WarnThreshold then
        if not NotifyState.hungerWarn then
            NotifyState.hungerWarn = true

            FoodNotify.Warning(Config.Notifications.hunger_warn, 6000)
        end
    else
        NotifyState.hungerWarn = false
        NotifyState.hungerCrit = false
    end

    if t < Config.CritThreshold then
        if not NotifyState.thirstCrit then
            NotifyState.thirstCrit = true
            NotifyState.thirstWarn = true

            FoodNotify.Error(Config.Notifications.thirst_crit, 7000)
        end
    elseif t < Config.WarnThreshold then
        if not NotifyState.thirstWarn then
            NotifyState.thirstWarn = true

            FoodNotify.Warning(Config.Notifications.thirst_warn, 6000)
        end
    else
        NotifyState.thirstWarn = false
        NotifyState.thirstCrit = false
    end

    if h >= Config.FullThreshold and t >= Config.FullThreshold then
        if not NotifyState.wellFed then
            NotifyState.wellFed = true

            FoodNotify.Success(Config.Notifications.well_fed, 5000)
        end
    else
        NotifyState.wellFed = false
    end
end

function ConsumeItem(itemName, durability)
    if LocalData.consuming then
        return
    end

    local itemCfg = Config.Items[itemName]

    if not itemCfg then
        return
    end

    LocalData.consuming = true

    local durability = tonumber(durability) or 100

    TriggerServerEvent('lv_status:server:consume', itemName, durability)

    LocalData.consuming = false
end


RegisterNetEvent('lv_status:client:setStatus', function(hunger, thirst, stress, addiction, lastAddictionAt)
    LocalData.hunger = clamp(hunger, 0, 100)
    LocalData.thirst = clamp(thirst, 0, 100)
    LocalData.stress = clamp(stress, 0, 100)
    LocalData.addiction = clamp(addiction, 0, 100)
    LocalData.lastAddictionAt = tonumber(lastAddictionAt) or os.time()
    LocalData.loaded = true

    SyncStatusToHud()

    StartStatusDebuffs(
        function() return
            LocalData.stress
        end,
        function() return
            LocalData.addiction
        end,
        function() return
            LocalData.lastAddictionAt
        end
    )

    CheckAndNotify()

    UpdateEffects(
        LocalData.hunger,
        LocalData.thirst,
        function() return
            LocalData.hunger
        end,
        function() return
            LocalData.thirst
        end
    )
end)


RegisterNetEvent('lv_status:client:updateAfterConsume', function(hunger, thirst, itemName, durability)
    LocalData.hunger = clamp(hunger, 0, 100)
    LocalData.thirst = clamp(thirst, 0, 100)

    local cfg = Config.Items[itemName]
    local dur = tonumber(durability) or 100

    if cfg then
        local hAdd = cfg.hunger or 0
        local tAdd = cfg.thirst or 0

        if hAdd > 0 then
            hAdd = math.max(0, math.floor(hAdd * (dur / 100)))
        end

        if tAdd > 0 then
            tAdd = math.max(0, math.floor(tAdd * (dur / 100)))
        end

        if cfg.type == 'food' then
            FoodNotify.Success(Config.Notifications.ate(cfg.label, hAdd), 4000)
        else
            FoodNotify.Success(Config.Notifications.drank(cfg.label, tAdd), 4000)
        end
    end

    SyncStatusToHud()

    CheckAndNotify()

    UpdateEffects(
        LocalData.hunger,
        LocalData.thirst,
        function() return
            LocalData.hunger
        end,
        function() return
            LocalData.thirst
        end
    )
end)

CreateThread(function()
    while not LocalData.loaded do
        Wait(1000)
    end

    while true do
        Wait(Config.DecayInterval)

        if not LocalData.loaded then
            goto continue
        end

        if IsEntityDead(PlayerPedId()) then
            goto continue
        end

        if LocalPlayer.state.IsJailed then
            goto continue
        end

        LocalData.hunger = math.max(0, LocalData.hunger - Config.HungerDecay)
        LocalData.thirst = math.max(0, LocalData.thirst - Config.ThirstDecay)

        SyncStatusToHud()

        CheckAndNotify()

        UpdateEffects(
            LocalData.hunger,
            LocalData.thirst,
            function() return
                LocalData.hunger
            end,
            function() return
                LocalData.thirst
            end
        )

        TriggerServerEvent('lv_status:server:syncStatus', LocalData.hunger, LocalData.thirst)

        ::continue::
    end
end)

AddEventHandler('esx:playerLoaded', function()
    TriggerServerEvent('lv_status:server:requestStatus')
end)

RegisterNetEvent('esx:onPlayerLogout')
AddEventHandler('esx:onPlayerLogout', function()
    LocalData.loaded = false
    LocalData.hunger = Config.DefaultHunger
    LocalData.thirst = Config.DefaultThirst
    LocalData.stress = Config.DefaultStress
    LocalData.addiction = Config.DefaultAddiction
    LocalData.lastAddictionAt = 0

    ClearAllEffects()
end)

CreateThread(function()
    Wait(2000)

    if not LocalData.loaded then
        TriggerServerEvent('lv_status:server:requestStatus')
    end
end)

RegisterNetEvent('esx_ambulancejob:revive')
AddEventHandler('esx_ambulancejob:revive', function()
    LocalData.hunger = 100
    LocalData.thirst = 100

    SyncStatusToHud()

    ClearAllEffects()

    NotifyState.hungerWarn = false
    NotifyState.hungerCrit = false
    NotifyState.thirstWarn = false
    NotifyState.thirstCrit = false

    CheckAndNotify()

    UpdateEffects(
        LocalData.hunger,
        LocalData.thirst,
        function() return
            LocalData.hunger
        end,
        function() return
            LocalData.thirst
        end
    )

    StartStatusDebuffs(
        function() return
            LocalData.stress
        end,
        function() return
            LocalData.addiction
        end,
        function() return
            LocalData.lastAddictionAt
        end
    )

    TriggerServerEvent('lv_status:server:syncStatus', 100, 100)
end)

CreateThread(function()
    while true do
        Wait(2000)

        if LocalData.loaded then
            SyncStatusToHud()
        end
    end
end)

RegisterNetEvent('admincore:revive')
AddEventHandler('admincore:revive', function()
    LocalData.hunger = 100
    LocalData.thirst = 100
    LocalData.stress = 0

    SyncStatusToHud()

    ClearAllEffects()

    NotifyState.hungerWarn = false
    NotifyState.hungerCrit = false
    NotifyState.thirstWarn = false
    NotifyState.thirstCrit = false

    CheckAndNotify()

    UpdateEffects(
        LocalData.hunger,
        LocalData.thirst,
        function() return
            LocalData.hunger
        end,
        function() return
            LocalData.thirst
        end
    )

    StartStatusDebuffs(
        function() return
            LocalData.stress
        end,
        function() return
            LocalData.addiction
        end,
        function() return
            LocalData.lastAddictionAt
        end
    )

    TriggerServerEvent('lv_status:server:syncStatus', 100, 100)
end)

RegisterNetEvent('lavie_injury:client:revive')
AddEventHandler('lavie_injury:client:revive', function()
    LocalData.hunger = 100
    LocalData.thirst = 100

    SyncStatusToHud()

    ClearAllEffects()

    NotifyState.hungerWarn = false
    NotifyState.hungerCrit = false
    NotifyState.thirstWarn = false
    NotifyState.thirstCrit = false

    CheckAndNotify()

    UpdateEffects(
        LocalData.hunger,
        LocalData.thirst,
        function() return
            LocalData.hunger
        end,
        function() return
            LocalData.thirst
        end
    )

    StartStatusDebuffs(
        function() return
            LocalData.stress
        end,
        function() return
            LocalData.addiction
        end,
        function() return
            LocalData.lastAddictionAt
        end
    )

    TriggerServerEvent('lv_status:server:syncStatus', 100, 100)
end)

RegisterNetEvent('esx:onPlayerSpawn')
AddEventHandler('esx:onPlayerSpawn', function()
    Citizen.Wait(500)

    if not LocalData.loaded then
        TriggerServerEvent('lv_status:server:requestStatus')
        return
    end

    SyncStatusToHud()

    ClearAllEffects()

    NotifyState.hungerWarn = false
    NotifyState.hungerCrit = false
    NotifyState.thirstWarn = false
    NotifyState.thirstCrit = false

    CheckAndNotify()

    UpdateEffects(
        LocalData.hunger,
        LocalData.thirst,
        function() return
            LocalData.hunger
        end,
        function() return
            LocalData.thirst
        end
    )

    StartStatusDebuffs(
        function() return
            LocalData.stress
        end,
        function() return
            LocalData.addiction
        end,
        function() return
            LocalData.lastAddictionAt
        end
    )
end)
