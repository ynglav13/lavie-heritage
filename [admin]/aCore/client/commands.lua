local ESX = exports['es_extended']:getSharedObject()

RegisterCommand('aduty', function(source, args, rawCommand)
    local dutyName = table.concat(args, ' ')
    TriggerServerEvent('admincore:toggleDuty', dutyName)
end, false)

RegisterNetEvent('admincore:adminList', function(list)
    if not list or #list == 0 then
        TriggerEvent('chat:addMessage', { color = {99, 179, 237}, args = { '{63B3ED}[AdminCore] Khong co admin online.{FFFFFF}' } })
        return
    end

    local lines = {}
    for _, admin in ipairs(list) do
        local duty = admin.onDuty and ' [DUTY]' or ''
        lines[#lines + 1] = ('[%s] %s (ID: %d)%s'):format(admin.rankName, admin.name, admin.id, duty)
    end

    TriggerEvent('chat:addMessage', {
        color = {99, 179, 237},
        multiline = true,
        args = { "{63B3ED}[AdminCore] Admin online (" .. #list .. "):\n" .. table.concat(lines, '\n') .. "{FFFFFF}" }
    })
end)

local function requireAdminCommand(cb)
    ESX.TriggerServerCallback('admincore:canUseAdminCommands', function(canUse)
        if not canUse then
            TriggerEvent('admincore:notify', 'Bạn không có quyền thực hiện lệnh này.', 'error')
            return
        end

        cb()
    end)
end

RegisterCommand('getvector2', function()
    requireAdminCommand(function()
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local text = string.format("vector2(%.2f, %.2f)", coords.x, coords.y)

        lib.setClipboard(text)
        TriggerEvent('admincore:notify', 'Da sao chep: ' .. text, 'success')
        print("Toa do cua ban: " .. text)
    end)
end, false)

RegisterCommand('getvector3', function()
    requireAdminCommand(function()
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local text = string.format("vector3(%.2f, %.2f, %.2f)", coords.x, coords.y, coords.z)

        lib.setClipboard(text)
        TriggerEvent('admincore:notify', 'Da sao chep: ' .. text, 'success')
        print("Toa do cua ban: " .. text)
    end)
end, false)

RegisterCommand('getvector4', function()
    requireAdminCommand(function()
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        local text = string.format("vector4(%.2f, %.2f, %.2f, %.2f)", coords.x, coords.y, coords.z, heading)

        lib.setClipboard(text)
        TriggerEvent('admincore:notify', 'Da sao chep: ' .. text, 'success')
        print("Toa do cua ban: " .. text)
    end)
end, false)

-- Register chat suggestions for Admin commands
CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/setinjury', 'Đặt trạng thái thương tích của người chơi', {
        { name = 'id', help = 'ID người chơi (hoặc r / me)' },
        { name = 'status', help = 'helpup (1) | injured (2) | dead (3)' }
    })
    TriggerEvent('chat:addSuggestion', '/revive', 'Hồi sinh người chơi', {
        { name = 'id', help = 'ID người chơi (hoặc me)' }
    })
    TriggerEvent('chat:addSuggestion', '/jail', 'Giam người chơi OOC', {
        { name = 'id', help = 'ID người chơi' },
        { name = 'phút', help = 'Số phút giam' },
        { name = 'lý do', help = 'Lý do giam (tùy chọn)' }
    })
    TriggerEvent('chat:addSuggestion', '/unjail', 'Thả người chơi khỏi tù OOC', {
        { name = 'id', help = 'ID người chơi' }
    })
    TriggerEvent('chat:addSuggestion', '/warn', 'Cảnh cáo người chơi', {
        { name = 'id', help = 'ID người chơi' },
        { name = 'lý do', help = 'Lý do cảnh cáo' }
    })
    TriggerEvent('chat:addSuggestion', '/giveitem', 'Give vật phẩm cho người chơi', {
        { name = 'id', help = 'ID người chơi' },
        { name = 'item', help = 'Tên item' },
        { name = 'amount', help = 'Số lượng' }
    })
    TriggerEvent('chat:addSuggestion', '/setjob', 'Đặt nghề nghiệp cho người chơi', {
        { name = 'id', help = 'ID người chơi' },
        { name = 'job', help = 'Tên job' },
        { name = 'grade', help = 'Cấp bậc (grade)' }
    })
    TriggerEvent('chat:addSuggestion', '/spawnveh', 'Spawn xe bằng model', {
        { name = 'model', help = 'Tên model xe' }
    })
    TriggerEvent('chat:addSuggestion', '/afix', 'Sửa xe và đổ xăng đầy bình', {
        { name = 'id/biển số', help = 'ID người chơi hoặc biển số xe' }
    })
    TriggerEvent('chat:addSuggestion', '/c', 'Kênh chat Staff / Advisor / Watchdog', {
        { name = 'nội dung', help = 'Nội dung tin nhắn' }
    })
    TriggerEvent('chat:addSuggestion', '/setwatchdog', 'Cấp hoặc xóa role Watchdog cho người chơi (chỉ có quyền /c)', {
        { name = 'id', help = 'ID người chơi' },
        { name = 'trạng thái', help = '1/0 hoặc on/off (tùy chọn)' }
    })
    TriggerEvent('chat:addSuggestion', '/setlevel', 'Đặt cấp bậc Admin cho người chơi', {
        { name = 'id', help = 'ID người chơi' },
        { name = 'level', help = '0-5 (0 = Player)' }
    })
end)
