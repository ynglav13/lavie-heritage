local function notifyPlayer(target, data, notifyType, duration, title)
    local playerId = tonumber(target)

    if not playerId then
        return false
    end

    if type(data) == 'table' then
        TriggerClientEvent('lv_notify:client:notify', playerId, data)
    else
        TriggerClientEvent('lv_notify:client:notify', playerId, data, notifyType, duration, title)
    end
    return true
end

local function notifyAll(data, notifyType, duration, title)
    if type(data) == 'table' then
        TriggerClientEvent('lv_notify:client:notify', -1, data)
    else
        TriggerClientEvent('lv_notify:client:notify', -1, data, notifyType, duration, title)
    end
    return true
end

exports('Notify', notifyPlayer)
exports('lv_notify', notifyPlayer)
exports('NotifyAll', notifyAll)

RegisterNetEvent('lv_notify:server:notify', function(data, notifyType, duration, title)
    notifyPlayer(source, data, notifyType, duration, title)
end)
