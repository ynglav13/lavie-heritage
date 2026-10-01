local damageReportOpen = false

function CloseDamageReport(keepFocus)
    if not damageReportOpen then
        return
    end

    damageReportOpen = false
    SendNUIMessage({display = false, clear = true})

    if not keepFocus then
        SetNuiFocus(false, false)
    end
end

function ShowPlayerDamages(serverId)
    local name, timestamp, response, errorCode, injuryStatus = lib.callback.await('lavie_injury:callback:GetPlayerDamages', false, serverId)

    if type(response) == 'table' and #response > 0 then
        SendNUIMessage(
        {
            display = true,
            damages = response,
            timestamp = timestamp,
            targetName = name,
            injuryStatus = injuryStatus,
        })

        if type(CloseInjurySeatSelection) == 'function' then
            CloseInjurySeatSelection(true)
        end

        damageReportOpen = true
        SetNuiFocus(true, true)
    else
        if errorCode == 'too_far' then
            return Notify(6000, 'error', 'Thông Báo', 'Người chơi không tồn tại hoặc không ở gần bạn')
        end

        if errorCode then
            return Notify(6000, 'error', 'Thông Báo', 'Dữ liệu thương tích đang bận, vui lòng thử lại')
        end

        return Notify(6000, 'error', 'Thông Báo', 'Người này không có vết thương nào trên cơ thể')
    end
end

RegisterNUICallback('finish-check', function(data, cb)
    CloseDamageReport(false)
    cb('ok')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        damageReportOpen = false
        SetNuiFocus(false, false)
    end
end)
