function Notify(duration, type, title, message)
    exports.lv_notify:Notify(
    {
        title = title or 'Thông Báo',
        message = message or type,
        type = type or 'info',
        duration = duration
    })
end

RegisterNetEvent('lavie_bodydamages:client:Notify', Notify)
RegisterNetEvent('lavie_injury:client:Notify', Notify)
