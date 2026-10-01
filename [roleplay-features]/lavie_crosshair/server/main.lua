local ESX = exports['es_extended']:getSharedObject()

MySQL.ready(function()
    MySQL.query([[
        ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `crosshair_type` VARCHAR(32) DEFAULT 'cross';
    ]], {}, function(result)
        if result then
            print('^2[lavie_crosshair]^7 Database column ready.')
        end
    end)
    MySQL.query([[
        ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `crosshair_settings` LONGTEXT DEFAULT NULL;
    ]], {}, function(result)
        if result then
            print('^2[lavie_crosshair]^7 Database settings column ready.')
        end
    end)
end)

local function Notify(source, message, notifyType)
    if GetResourceState('lv_notify') == 'started' then
        exports['lv_notify']:Notify(source, message, notifyType, 3000, 'Crosshair')
        return
    end
    TriggerClientEvent('lavie_crosshair:notify', source, notifyType, message)
end

local function GetDefaultSettings()
    return {
        type = Config.DefaultType or 'cross',
        color = Config.DefaultColor or {255, 255, 255, 255},
        outline = Config.DefaultOutline or false,
        outlineColor = Config.DefaultOutlineColor or {0, 0, 0, 255},
        size = Config.Size or 0.0038,
        thickness = Config.Thickness or 0.0015,
        gap = Config.Gap or 0,
        dotSize = Config.DotSize or 0.003,
        radius = 0.6,
        outlineWidth = 0.8
    }
end

local function IsValidCrosshair(crosshairType, source)
    local crosshairData = Config.Crosshairs[crosshairType]
    if not crosshairData then
        return false
    end

    if crosshairData.prime then
        local state = Player(source).state
        if not state or state.isPrime ~= true then
            return false
        end
    end

    return true
end

local function ResetPlayerCrosshair(playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then return end

    local defaultSettings = GetDefaultSettings()
    MySQL.update('UPDATE users SET crosshair_settings = NULL, crosshair_type = ? WHERE identifier = ?',
        { Config.DefaultType or 'cross', xPlayer.identifier })

    TriggerClientEvent('lavie_crosshair:setCrosshair', playerId, defaultSettings)
end

local function LoadPlayerCrosshair(playerId, xPlayer)
    if not xPlayer then return end
    
    CreateThread(function()
        local timeout = 15
        while Player(playerId).state.isPrime == nil and timeout > 0 do
            Wait(200)
            timeout = timeout - 1
        end

        if not ESX.GetPlayerFromId(playerId) then return end

        local isPrime = Player(playerId).state.isPrime == true

        if not isPrime then
            ResetPlayerCrosshair(playerId)
            return
        end

        local result = MySQL.query.await(
            'SELECT crosshair_type, crosshair_settings FROM users WHERE identifier = ?',
            { xPlayer.identifier }
        )

        local settings = GetDefaultSettings()

        if result and result[1] then
            if result[1].crosshair_settings and result[1].crosshair_settings ~= '' then
                local decoded = json.decode(result[1].crosshair_settings)
                if decoded then
                    settings = decoded
                end
            elseif result[1].crosshair_type then
                local savedType = result[1].crosshair_type
                if IsValidCrosshair(savedType, playerId) then
                    settings.type = savedType
                end
            end
        end

        
        if not IsValidCrosshair(settings.type, playerId) then
            settings.type = Config.DefaultType or 'cross'
        end

        TriggerClientEvent('lavie_crosshair:setCrosshair', playerId, settings)
    end)
end

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    LoadPlayerCrosshair(playerId, xPlayer)
end)

RegisterNetEvent('lavie_crosshair:requestSettings', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if xPlayer then
        LoadPlayerCrosshair(src, xPlayer)
    end
end)

-- reload settings khi restart script
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    Wait(1000)
    local xPlayers = ESX.GetExtendedPlayers()
    for _, xPlayer in ipairs(xPlayers) do
        LoadPlayerCrosshair(xPlayer.source, xPlayer)
    end
end)

AddStateBagChangeHandler('isPrime', nil, function(bagName, key, value, _reserved, replicated)
    if value == false then
        local playerId = string.match(bagName, '^player:(%d+)')
        if playerId then
            playerId = tonumber(playerId)
            ResetPlayerCrosshair(playerId)
        end
    end
end)

RegisterNetEvent('lavie_crosshair:save', function(settings)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local state = Player(src).state
    local isPrime = state and state.isPrime == true

    if not isPrime then
        ResetPlayerCrosshair(src)
        Notify(src, 'Bạn cần có Prime để sử dụng tùy chỉnh Crosshair!', 'error')
        return
    end

    if type(settings) ~= 'table' or not settings.type then
        Notify(src, 'Dữ liệu không hợp lệ.', 'error')
        return
    end

    if not IsValidCrosshair(settings.type, src) then
        Notify(src, 'Crosshair không hợp lệ.', 'error')
        return
    end

    local settingsJson = json.encode(settings)

    MySQL.update('UPDATE users SET crosshair_settings = ?, crosshair_type = ? WHERE identifier = ?',
        { settingsJson, settings.type, xPlayer.identifier })

    TriggerClientEvent('lavie_crosshair:setCrosshair', src, settings)
    Notify(src, 'Đã lưu thiết lập crosshair.', 'success')
end)
