Rental = Rental or {}

Rental.log = Rental.log or function() end

function Rental.trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

function Rental.round(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

function Rental.clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue

    if value < minValue then
        return minValue
    end

    if value > maxValue then
        return maxValue
    end
    return value
end

function Rental.safeString(value, maxLength)
    value = Rental.trim(value)

    if maxLength and #value > maxLength then
        value = value:sub(1, maxLength)
    end
    return value
end

function Rental.isPlate(plate)
    plate = Rental.trim(plate)
    return #plate >= 4 and #plate <= 8 and plate:match('^[A-Z0-9]+$') ~= nil
end

function Rental.notify(source, message, notifyType)
    local nType = notifyType == 'inform' and 'info' or (notifyType or 'info')

    if GetResourceState('lv_notify') == 'started' then
        exports['lv_notify']:Notify(source,
        {
            title = 'Thuê Phương Tiện',
            message = message,
            type = nType,
            duration = 4200
        })
        return
    end

    TriggerClientEvent('lv_notify:client:notify', source,
    {
        title = 'Thuê Phương Tiện',
        message = message,
        type = nType,
        duration = 4200
    })
end
