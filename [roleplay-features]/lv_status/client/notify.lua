local function Notify(type, message, duration)
    duration = duration or 5000

    if GetResourceState('lv_notify'):find('start') then
        exports['lv_notify']:Notify(
        {
            type     = type,
            message  = message,
            duration = duration,
            position = 'top-right',
        })
    else
        local ESX = exports['es_extended']:getSharedObject()

        if ESX then
            ESX.ShowNotification(message)
        end
    end
end

FoodNotify =
{
    Info = function(msg, dur)
        Notify('info', msg, dur)
    end,
    Success = function(msg, dur)
        Notify('success', msg, dur)
    end,
    Warning = function(msg, dur)
        Notify('warning', msg, dur)
    end,
    Error = function(msg, dur)
        Notify('error', msg, dur)
    end,
}
