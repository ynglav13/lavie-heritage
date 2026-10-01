local function getPlayerIdentifier(source)
    return GetPlayerIdentifier(source, 0)
end

RegisterNetEvent('vRadioAnimation:saveAnimChoice', function(styleKey)
    local identifier = getPlayerIdentifier(source)
    if identifier and Config.Anims[styleKey] then
        MySQL.insert.await(
            'INSERT INTO player_radio_anim (identifier, anim_style) VALUES (?, ?) ON DUPLICATE KEY UPDATE anim_style = ?',
            { identifier, styleKey, styleKey }
        )
    end
end)

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS player_radio_anim (
            identifier VARCHAR(80) NOT NULL,
            anim_style VARCHAR(50) NOT NULL,
            PRIMARY KEY (identifier)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end)

lib.callback.register('vRadioAnimation:getAnimChoice', function(source)
    local identifier = getPlayerIdentifier(source)
    if identifier then
        local result = MySQL.query.await('SELECT anim_style FROM player_radio_anim WHERE identifier = ?', { identifier })
        if result and #result > 0 then
            return result[1].anim_style
        else
            return nil
        end
    end
    return nil
end)
