local ESX = exports['es_extended']:getSharedObject()
Config.Webhook.url = ''

local ActionLabels =
{
    rent = 'Thuê Phương Tiện',
    ['return'] = 'Trả Phương Tiện',
    expired = 'Hết Hạn Thuê',
    admin_station_save = 'Admin Lưu Điểm Thuê',
    admin_station_delete = 'Admin Xoá Điểm Thuê',
    admin_spawn_save = 'Admin Lưu Điểm Spawn',
    admin_spawn_delete = 'Admin Xoá Điểm Spawn',
    admin_vehicle_save = 'Admin Lưu Phương Tiện Thuê',
    admin_vehicle_delete = 'Admin Xoá Phương Tiện Thuê'
}

local function discordLog(action, payload)
    if not Config.Webhook.enabled or Config.Webhook.url == '' then
        return
    end

    local fields = {}
    
    for key, value in pairs(payload or {}) do
        fields[#fields + 1] =
        {
            name = tostring(key),
            value = tostring(value),
            inline = true
        }
    end

    if GetResourceState('legacyWebhook') == 'started' then
        local invoked = pcall(function()
            return exports['legacyWebhook']:SendDiscordLog({
                webhook = Config.Webhook.url,
                title = ('Thuê Phương Tiện: %s'):format(ActionLabels[action] or action),
                message = "",
                color = 3447003,
                fields = fields,
                username = Config.Webhook.username,
                avatar = Config.Webhook.avatar
            })
        end)

        if invoked then
            return
        end
    end

    PerformHttpRequest(Config.Webhook.url, function() end, 'POST', json.encode(
    {
        username = Config.Webhook.username,
        avatar_url = Config.Webhook.avatar,
        embeds =
        {
            {
                title = ('Thuê Phương Tiện: %s'):format(ActionLabels[action] or action),
                color = 3447003,
                fields = fields,
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
            }
        }
    }),
    {
        ['Content-Type'] = 'application/json'
    })
end

local function getIcName(source, xPlayer)
    if xPlayer then
        local okName, name = pcall(function()
            return xPlayer.getName and xPlayer.getName()
        end)
        
        if okName and name and name ~= '' then
            return name
        end

        local firstName = xPlayer.get and (xPlayer.get('firstName') or xPlayer.get('firstname')) or nil
        local lastName = xPlayer.get and (xPlayer.get('lastName') or xPlayer.get('lastname')) or nil
        
        if (not firstName or firstName == '') and xPlayer.variables then
            firstName = xPlayer.variables.firstName or xPlayer.variables.firstname
            lastName = xPlayer.variables.lastName or xPlayer.variables.lastname
        end

        local fullName = Rental.trim(('%s %s'):format(firstName or '', lastName or ''))
        
        if fullName ~= '' then
            return fullName
        end
    end
    return source and GetPlayerName(source) or nil
end

function Rental.log(action, source, data)
    data = data or {}

    local xPlayer = source and ESX.GetPlayerFromId(source) or nil
    local identifier = data.identifier or (xPlayer and xPlayer.identifier) or nil
    local playerName = data.playerName or getIcName(source, xPlayer)

    discordLog(action,
    {
        ['Hành Động'] = ActionLabels[action] or action,
        ['Người Chơi'] = playerName or 'Hệ Thống',
        ['Identifier'] = identifier or 'Không Có',
        ['Biển Số'] = data.plate or 'Không Có',
        ['Model'] = data.model or 'Không Có',
        ['Điểm Thuê'] = data.stationId or 'Không Có',
        ['Phí Thuê'] = data.amount or 'Không Có'
    })
end
