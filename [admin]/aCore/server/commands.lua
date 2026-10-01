local ESX = exports['es_extended']:getSharedObject()

local originalRegisterCommand = RegisterCommand
RegisterCommand = function(commandName, handler, restricted)
    originalRegisterCommand(commandName, function(source, args, rawCommand)
        if source ~= 0 then
            local cmdLower = commandName:lower()
            local level = AdminFunctions.GetLevel(source)
            local isWatchdog = AdminFunctions.IsWatchdog(source)

            if isWatchdog then
                local watchdogAllowed = {
                    ['c'] = true,
                    ['togglec'] = true,
                    ['tc'] = true,
                    ['toggleadvisorchat'] = true,
                    ['tadvisor'] = true,
                    ['report'] = true,
                    ['huybaocao'] = true,
                    ['cancelreport'] = true,
                }
                if not watchdogAllowed[cmdLower] then
                    AdminFunctions.Notify(source, 'Role Watchdog chỉ có thể sử dụng lệnh /c.', 'error')
                    return
                end
            end

            local exemptCommands = {
                ['aduty'] = true,
                ['cduty'] = true,
                ['report'] = true,
                ['huybaocao'] = true,
                ['cancelreport'] = true,
                ['a'] = true,
                ['c'] = true,
                ['toggleac'] = true,
                ['tac'] = true,
                ['toggleadminchat'] = true,
                ['togglec'] = true,
                ['tc'] = true,
                ['toggleadvisorchat'] = true,
                ['tadvisor'] = true,
            }

            if level == 2 or level == 3 then
                local allowedCommands = {
                    ['rpanel'] = true,
                    ['apanel'] = true,
                    ['goto'] = true,
                    ['agoto'] = true,
                    ['bring'] = true,
                    ['abring'] = true,
                    ['gethere'] = true,
                    ['agethere'] = true,
                    ['aspectate'] = true,
                    ['spectate'] = true,
                    ['spec'] = true,
                    ['agetcar'] = true,
                    ['givekeys'] = true,
                    ['checkinv'] = true,
                    ['admins'] = true,
                    ['players'] = true,
                    ['agetinfo'] = true,
                    ['getinfo'] = true,
                    ['revive'] = true,
                    ['fly'] = true,
                    ['nametags'] = true,
                    ['kick'] = true,
                    ['jail'] = true,
                    ['unjail'] = true,
                    ['unjailic'] = true,
                    ['fixtime'] = true,
                    ['freeze'] = true,
                    ['warn'] = true,
                    ['afix'] = true,
                    ['fixveh'] = true,
                    ['a'] = true,
                    ['aduty'] = true,
                    ['c'] = true,
                    ['pc'] = true,
                    ['tooglepc'] = true,
                    ['togglepc'] = true,
                    ['ahelp'] = true,
                    ['getvector2'] = true,
                    ['getvector3'] = true,
                    ['getvector4'] = true,
                    ['report'] = true,
                    ['huybaocao'] = true,
                    ['cancelreport'] = true,
                    ['toggleac'] = true,
                    ['tac'] = true,
                    ['toggleadminchat'] = true,
                    ['togglec'] = true,
                    ['tc'] = true,
                    ['toggleadvisorchat'] = true,
                    ['tadvisor'] = true,
                }
                if not allowedCommands[cmdLower] then
                    AdminFunctions.Notify(source, 'Bạn không có quyền thực hiện lệnh này', 'error')
                    return
                end
            end

            -- Bắt buộc Admin 4 trở xuống phải On Duty mới dùng được lệnh admin
            if not exemptCommands[cmdLower] and level >= 1 and level <= 4 and not AdminFunctions.IsAdminDutyAllowed(source) then
                AdminFunctions.Notify(source, 'Bạn phải On Duty (/aduty) mới có thể sử dụng lệnh admin.', 'error')
                return
            end
        end
        handler(source, args, rawCommand)
    end, restricted)
end

local function PrimeNotify(target, notifyType, message, duration)
    target = tonumber(target)

    if not target or target == 0 then
        print(('[Prime] %s'):format(message))
        return
    end

    if GetResourceState('lv_notify') == 'started' then
        exports['lv_notify']:Notify(target, {
            type = notifyType or 'info',
            title = 'Prime',
            message = message,
            duration = duration or 4500,
            icon = 'VIP',
            accent = notifyType == 'error' and '#fb7185' or '#facc15'
        })
        return
    end

    AdminFunctions.Notify(target, message, notifyType or 'info')
end

-- =============================================
--   Helper: parse command args
-- =============================================
local function requireAdmin(src, action, cb)
    if not AdminFunctions.HasPermission(src, action) then
        AdminFunctions.Notify(src, 'Bạn không có quyền thực hiện lệnh này', 'error')
        return
    end

    if not AdminFunctions.RequireAdminDuty(src) then
        return
    end

    cb()
end

local function requireAdminDuty(src, cb, message)
    if not AdminFunctions.RequireAdminDuty(src) then
        return
    end

    cb()
end

local function getTarget(src, idStr)
    local id = tonumber(idStr)
    if not id then
        AdminFunctions.Notify(src, 'ID người chơi không hợp lệ.', 'error')
        return nil
    end
    if not ESX.GetPlayerFromId(id) then
        AdminFunctions.Notify(src, 'Người chơi không tồn tại.', 'error')
        return nil
    end
    return id
end

local function parseGotoCoords(args)
    local input = table.concat(args, ' '):lower()
    local vectorSize, valuesString = input:match('^%s*vector([34])%s*%((.*)%)%s*$')
    if not vectorSize then return nil end

    local values = {}
    for value in valuesString:gmatch('[^,%s]+') do
        value = tonumber(value)
        if not value then return false end
        values[#values + 1] = value
    end

    local expectedValues = tonumber(vectorSize)
    if #values ~= expectedValues then return false end

    return {
        x = values[1],
        y = values[2],
        z = values[3],
        heading = values[4],
    }
end

local Reports = {}
local NextReportId = 1
local ActiveAdvisorHelps = {}
local Cooldowns = {}

local disabledCommandMessage = 'Dùng /rpanel để kiểm tra report.'

local function isAdvisor(src)
    return AdminFunctions.GetLevel(src) == (Config.Advisor.level or 1)
end

local function isAdvisorOnDuty(src)
    return Player(src).state.advisorDutyName ~= nil
end

local function isReportAdmin(src)
    return AdminFunctions.IsOwner(src) or AdminFunctions.GetLevel(src) >= (Config.Advisor.reportAdminMinLevel or 2)
end

local function getCooldownSeconds(name)
    local cd = Config.Advisor.cooldowns or {}
    return cd[name] or 2
end

local function checkCooldown(src, name)
    if AdminFunctions.GetLevel(src) >= 1 then return true end

    local seconds = getCooldownSeconds(name)
    if seconds <= 0 then return true end

    local now = os.time()
    Cooldowns[src] = Cooldowns[src] or {}
    local expires = Cooldowns[src][name] or 0
    if expires > now then
        AdminFunctions.Notify(src, ('Vui lòng chờ %d giây rồi thử lại.'):format(expires - now), 'warning')
        return false
    end

    Cooldowns[src][name] = now + seconds
    return true
end

local function disableCommand(src)
    AdminFunctions.Notify(src, disabledCommandMessage, 'info')
end

local function requireAdvisor(src, cb)
    if not isAdvisor(src) then
        AdminFunctions.Notify(src, 'Bạn không có quyền Advisor.', 'error')
        return
    end

    if not isAdvisorOnDuty(src) then
        AdminFunctions.Notify(src, 'Bạn phải bật /cduty để sử dụng lệnh Advisor.', 'error')
        return
    end

    cb()
end

local function sendChat(target, color, message)
    if GetResourceState('custom-chat') == 'started' then
        TriggerClientEvent('custom-chat:addMessage', target, message)
        return
    end

    TriggerClientEvent('chat:addMessage', target, {
        color = color,
        multiline = true,
        args = { message }
    })
end

local function sendReportNui(target, payload)
    TriggerClientEvent('admincore:reportNotify', target, payload)
end

local function broadcastToStaff(color, message)
    for _, xPlayer in ipairs(ESX.GetExtendedPlayers()) do
        if isReportAdmin(xPlayer) then
            sendChat(xPlayer.source, color, message)
        end
    end
end

local function broadcastReportNuiToStaff(payload)
    for _, xPlayer in ipairs(ESX.GetExtendedPlayers()) do
        if isReportAdmin(xPlayer) then
            sendReportNui(xPlayer.source, payload)
        end
    end
end

local function broadcastReportNuiToAdvisors(payload)
    for _, xPlayer in ipairs(ESX.GetExtendedPlayers()) do
        if isAdvisor(xPlayer) then
            sendReportNui(xPlayer.source, payload)
        end
    end
end

local function isReportActive(report)
    return report and report.status ~= 'closed' and report.status ~= 'denied' and report.status ~= 'cancelled' and report.status ~= 'deleted'
end

local function serializeReport(report)
    return {
        id = report.id,
        playerId = report.playerId,
        playerName = report.playerName,
        message = report.message,
        status = report.status,
        createdAt = report.createdAt,
        acceptedBy = report.acceptedBy,
        acceptedName = report.acceptedBy and GetPlayerName(report.acceptedBy) or nil,
        pushedBy = report.pushedBy,
        pushedName = report.pushedBy and GetPlayerName(report.pushedBy) or nil,
    }
end

local function getVisibleReports(src)
    local result = {}
    local advisorOnly = not isReportAdmin(src)
    local activeReportCount = 0
    local totalReportCount = 0
    for _ in pairs(Reports) do totalReportCount = totalReportCount + 1 end

    -- print(('[AdminCore Debug] getVisibleReports: advisorOnly=%s | totalReports=%d'):format(advisorOnly, totalReportCount))

    for id, report in pairs(Reports) do
        local visible = isReportActive(report)
        -- print(('[AdminCore Debug] Report #%d | status=%s | active=%s'):format(id, report.status, visible))
        if advisorOnly then
            local prevVisible = visible
            visible = visible and (report.status == 'advisor' or report.status == 'advisor_accepted')
            -- print(('[AdminCore Debug] AdvisorOnly check on Report #%d: was %s -> now %s'):format(id, prevVisible, visible))
        end

        if visible then
            result[#result + 1] = serializeReport(report)
        end
    end

    table.sort(result, function(a, b) return a.id > b.id end)
    return result
end

local function syncReportsForStaff()
    local adminReports
    local advisorReports

    for _, xPlayer in ipairs(ESX.GetExtendedPlayers()) do
        local pid = xPlayer.source
        if isReportAdmin(xPlayer) then
            adminReports = adminReports or getVisibleReports(xPlayer)
            TriggerClientEvent('admincore:updateReports', pid, adminReports)
        elseif isAdvisor(xPlayer) then
            advisorReports = advisorReports or getVisibleReports(xPlayer)
            TriggerClientEvent('admincore:updateReports', pid, advisorReports)
        end
    end
end

local function broadcastToAdvisors(color, message)
    for _, xPlayer in ipairs(ESX.GetExtendedPlayers()) do
        if isAdvisor(xPlayer) then
            sendChat(xPlayer.source, color, message)
        end
    end
end

local function getReportById(src, idStr)
    local id = tonumber(idStr)
    if not id or not Reports[id] then
        AdminFunctions.Notify(src, 'Report không tồn tại.', 'error')
        return nil, nil
    end
    return id, Reports[id]
end

local function getActiveReportByPlayer(src)
    for id, report in pairs(Reports) do
        if report.playerId == src and isReportActive(report) then
            return id, report
        end
    end
    return nil, nil
end

local function releaseAdvisorHelpForReport(reportId, message)
    for advisorSrc, active in pairs(ActiveAdvisorHelps) do
        if active.reportId == reportId then
            ActiveAdvisorHelps[advisorSrc] = nil
            TriggerClientEvent('admincore:advisorHelpReturn', advisorSrc)
            if message then
                AdminFunctions.Notify(advisorSrc, message:format(reportId), 'warning')
            end
        end
    end
end

local function getAdvisorReviveTarget(src, targetId)
    if not isAdvisor(src) then return nil end

    if not isAdvisorOnDuty(src) then
        AdminFunctions.Notify(src, 'Bạn phải bật /cduty để sử dụng /revive.', 'error')
        return nil
    end

    local active = ActiveAdvisorHelps[src]
    local report = active and Reports[active.reportId]
    if not active or not report or report.status ~= 'advisor_accepted' or report.acceptedBy ~= src then
        AdminFunctions.Notify(src, 'Bạn chỉ được dùng /revive sau khi nhận report.', 'error')
        return nil
    end

    targetId = tonumber(targetId)
    if not targetId then
        AdminFunctions.Notify(src, ('Cú pháp: /revive %d'):format(report.playerId), 'error')
        return nil
    end

    if targetId == src then
        AdminFunctions.Notify(src, 'Advisor không được tự revive bản thân.', 'error')
        return nil
    end

    if targetId ~= report.playerId or active.playerId ~= targetId then
        AdminFunctions.Notify(src, 'Bạn chỉ được revive người chơi đã gửi report mà bạn đang nhận.', 'error')
        return nil
    end

    if not ESX.GetPlayerFromId(targetId) then
        AdminFunctions.Notify(src, 'Người gửi report không còn online.', 'error')
        return nil
    end

    return targetId
end

local function cancelPlayerReport(src)
    if not checkCooldown(src, 'cancel') then return end

    local id, report = getActiveReportByPlayer(src)
    if not id then
        AdminFunctions.Notify(src, 'Bạn không có báo cáo nào đang mở.', 'error')
        return
    end

    report.status = 'cancelled'
    report.closedBy = src
    report.closedAt = os.time()

    releaseAdvisorHelpForReport(id, 'Report #%d đã bị người chơi hủy.')

    AdminFunctions.Notify(src, ('Đã hủy báo cáo #%d.'):format(id), 'success')
    broadcastToStaff({160, 174, 192}, ('{A0AEC0}[Report] %s đã hủy report #%d.{FFFFFF}'):format(GetPlayerName(src), id))
    AdminLogger.Log(src, 'report_cancel', nil, ('Report #%d | Noi dung: %s'):format(id, report.message or ''))
    syncReportsForStaff()
end

local function formatReport(report)
    return ('#%d [%s] %s (ID: %d): %s'):format(
        report.id,
        report.status,
        report.playerName,
        report.playerId,
        report.message
    )
end

local function showReports(src, advisorOnly)
    local lines = {}
    for id, report in pairs(Reports) do
        local visible = isReportActive(report)
        if advisorOnly then
            visible = visible and (report.status == 'advisor' or report.status == 'advisor_accepted')
        end

        if visible then
            lines[#lines + 1] = formatReport(report)
        end
    end

    table.sort(lines)

    if #lines == 0 then
        AdminFunctions.Notify(src, advisorOnly and 'Không có hỗ trợ nào được đẩy xuống Advisor.' or 'Không có report nào đang mở.', 'info')
        return
    end

    sendChat(src, {56, 189, 248}, ('{38BDF8}[Reports]\n%s{FFFFFF}'):format(table.concat(lines, '\n')))
end

local function closeAdvisorHelp(advisorSrc, reason)
    local active = ActiveAdvisorHelps[advisorSrc]
    if not active then
        if reason ~= false then
            AdminFunctions.Notify(advisorSrc, 'Bạn chưa nhận hỗ trợ nào.', 'error')
        end
        return
    end

    local report = Reports[active.reportId]
    if report then
        report.status = 'closed'
        report.closedBy = advisorSrc
        report.closedAt = os.time()
        if ESX.GetPlayerFromId(report.playerId) then
            AdminFunctions.Notify(report.playerId, 'Phiên hỗ trợ của bạn đã kết thúc.', 'success')
        end
    end

    ActiveAdvisorHelps[advisorSrc] = nil
    TriggerClientEvent('admincore:advisorHelpReturn', advisorSrc)
    AdminFunctions.Notify(advisorSrc, reason or 'Đã kết thúc hỗ trợ.', 'success')
    broadcastToStaff({56, 189, 248}, ('{38BDF8}[Report] Advisor %s đã kết thúc report #%d.{FFFFFF}'):format(GetPlayerName(advisorSrc), active.reportId))
    AdminLogger.Log(advisorSrc, 'advisor_help_finish', report and report.playerId or nil, ('Report #%d'):format(active.reportId))
    syncReportsForStaff()
end

local function toggleAdminDuty(src, dutyName)
    local isOwner = AdminFunctions.IsOwner(src)
    local level = AdminFunctions.GetLevel(src)
    local reportAdminMinLevel = Config.Advisor.reportAdminMinLevel or 2
    local advisorLevel = Config.Advisor.level or 1

    if not isOwner and level < reportAdminMinLevel then
        if level == advisorLevel then
            AdminFunctions.Notify(src, 'Advisor không thể bật Admin Duty. Hãy dùng /cduty.', 'error')
        else
            AdminFunctions.Notify(src, 'Bạn không có quyền sử dụng lệnh này.', 'error')
        end
        return
    end

    if not checkCooldown(src, 'duty') then return end

    if Player(src).state.adminDutyName then
        Player(src).state:set("adminDutyName", nil, true)
        TriggerClientEvent('admincore:dutyState', -1, false, src, '')
        AdminFunctions.Notify(src, 'Đã tắt chế độ Admin Duty.', 'info')
        return
    end

    if not dutyName or dutyName == '' then
        AdminFunctions.Notify(src, 'Bạn bắt buộc phải nhập tên On Duty, vd: /aduty [Tên]', 'error')
        return
    end

    local displayName = dutyName
    local lvl = AdminFunctions.GetLevel(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    local rData = xPlayer and PlayerRankCache[xPlayer.identifier]
    local rName = (rData and rData.name) or Config.DefaultLevelNames[lvl] or ('Level ' .. lvl)
    local dutyWithRank = ('[%s] %s'):format(rName, displayName)

    Player(src).state:set("adminDutyName", dutyWithRank, true)
    TriggerClientEvent('admincore:dutyState', -1, true, src, dutyWithRank)
    AdminFunctions.Notify(src, ('Đã bật chế độ Admin Duty dưới tên: %s'):format(displayName), 'success')
    AdminLogger.Log(src, 'aduty', nil, 'Bat duty: ' .. displayName)
end

local function toggleAdvisorDuty(src, dutyName)
    if not checkCooldown(src, 'duty') then return end

    if not isAdvisor(src) then
        AdminFunctions.Notify(src, 'Chỉ Advisor level 1 mới có thể bật Advisor Duty.', 'error')
        return
    end

    if Player(src).state.advisorDutyName then
        Player(src).state:set('advisorDutyName', nil, true)
        TriggerClientEvent('admincore:advisorDutyState', -1, false, src, '')
        AdminFunctions.Notify(src, 'Đã tắt chế độ Advisor Duty.', 'info')
        return
    end

    local displayName = (dutyName and dutyName ~= '') and dutyName or GetPlayerName(src)
    local lvl = AdminFunctions.GetLevel(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    local rData = xPlayer and PlayerRankCache[xPlayer.identifier]
    local tag = (rData and rData.name) or Config.Advisor.tag or 'Advisor'
    local dutyWithRank = ('[%s] %s'):format(tag, displayName)

    Player(src).state:set('advisorDutyName', dutyWithRank, true)
    TriggerClientEvent('admincore:advisorDutyState', -1, true, src, dutyWithRank)
    AdminFunctions.Notify(src, ('Đã bật Advisor Duty dưới tên: %s'):format(displayName), 'success')
    AdminLogger.Log(src, 'cduty', nil, 'Bat advisor duty: ' .. displayName)
end

AddEventHandler('playerDropped', function()
    local src = source

    if Player(src).state.adminDutyName then
        Player(src).state:set('adminDutyName', nil, true)
    end

    if Player(src).state.advisorDutyName then
        Player(src).state:set('advisorDutyName', nil, true)
    end

    TriggerClientEvent('admincore:clearDutyState', -1, src)
end)

local function sendAdminChat(src, msg)
    local level = AdminFunctions.GetLevel(src)
    local isOwner = AdminFunctions.IsOwner(src)
    local reportAdminMinLevel = Config.Advisor.reportAdminMinLevel or 2

    if AdminFunctions.IsWatchdog(src) then return end
    if not isOwner and level < reportAdminMinLevel then return end
    if not checkCooldown(src, 'chat') then return end

    msg = tostring(msg or '')
    if msg == '' then
        AdminFunctions.Notify(src, 'Vui lòng nhập nội dung tin nhắn.', 'error')
        return
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    local rankName = (xPlayer and PlayerRankCache[xPlayer.identifier] and PlayerRankCache[xPlayer.identifier].name) or Config.DefaultLevelNames[level] or ('Level ' .. level)
    local name = GetPlayerName(src)

    for _, xPlayer in ipairs(ESX.GetExtendedPlayers()) do
        local pid = xPlayer.source
        local pLvl = AdminFunctions.GetLevel(xPlayer)
        if AdminFunctions.IsOwner(xPlayer) or pLvl >= reportAdminMinLevel then
            if not Player(pid).state.adminChatMuted then
                sendChat(pid, {255, 215, 0}, ('{FFD700}(( [Admin Chat] %s - %s: %s )){FFFFFF}'):format(rankName, name, msg))
            end
        end
    end
    AdminLogger.Log(src, 'adminchat', nil, msg)
end

local function sendAdvisorChat(src, msg)
    local level = AdminFunctions.GetLevel(src)
    local isWatchdog = AdminFunctions.IsWatchdog(src)
    if level < 1 and not isAdvisor(src) and not isWatchdog then
        AdminFunctions.Notify(src, 'Bạn không có quyền thực hiện lệnh này.', 'error')
        return
    end
    if not checkCooldown(src, 'chat') then return end

    msg = tostring(msg or '')
    if msg == '' then
        AdminFunctions.Notify(src, 'Vui lòng nhập nội dung tin nhắn.', 'error')
        return
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    local rData = xPlayer and PlayerRankCache[xPlayer.identifier]
    local rankName = (rData and rData.name) or (isWatchdog and (Config.Watchdog and Config.Watchdog.tag or 'Watchdog')) or (level == (Config.Advisor.level or 1) and 'Advisor' or 'Admin')
    local displayName = GetPlayerName(src)

    for _, xPlayer in ipairs(ESX.GetExtendedPlayers()) do
        local pid = xPlayer.source
        if AdminFunctions.GetLevel(xPlayer) >= 1 or isAdvisor(xPlayer) or AdminFunctions.IsWatchdog(xPlayer) then
            if not Player(pid).state.advisorChatMuted then
                sendChat(pid, {56, 189, 248}, ('{38BDF8}(( [%s] %s: %s )){FFFFFF}'):format(rankName, displayName, msg))
            end
        end
    end
    AdminLogger.Log(src, 'advisorchat', nil, ('[%s] %s'):format(rankName, msg))
end

AddEventHandler('playerDropped', function()
    local src = source

    if ActiveAdvisorHelps[src] then
        local active = ActiveAdvisorHelps[src]
        local report = Reports[active.reportId]
        if report and report.status == 'advisor_accepted' then
            report.status = 'advisor'
            report.acceptedBy = nil
            broadcastToAdvisors({56, 189, 248}, ('{38BDF8}[Advisor Help #%d] Advisor đã rời server, ticket được mở lại. Dùng /rpanel để kiểm tra.{FFFFFF}'):format(active.reportId))
        end
        ActiveAdvisorHelps[src] = nil
    end

    for id, report in pairs(Reports) do
        if report.playerId == src and isReportActive(report) then
            report.status = 'closed'
            report.closedAt = os.time()
            broadcastToStaff({160, 174, 192}, ('{A0AEC0}[Report] Người gửi report #%d đã rời server, ticket được đóng.{FFFFFF}'):format(id))
        end
    end
end)

-- =============================================
--   /ahelp  – Xem danh sach lenh
-- =============================================
local CommandSyntaxes = {
    ['getinfo'] = '/agetinfo [id]',
    ['goto'] = '/agoto [id]',
    ['gethere'] = '/agethere [id]',
    ['spectate'] = '/aspectate [id/none] hoặc /spec [id/none]',
    ['spec'] = '/spec [id/none]',
    ['agetcar'] = '/agetcar [biển số/Player ID]',
    ['givekeys'] = '/givekeys [biển số/none]',
    ['apanel'] = '/apanel',
    ['admins'] = '/admins',
    ['players'] = '/players',
    ['ahelp'] = '/ahelp',
    ['ban'] = '/ban [id] [reason]',
    ['kick'] = '/kick [id] [reason]',
    ['warn'] = '/warn [id] [reason]',

    ['freeze'] = '/freeze [id]',
    -- ['unban'] = '/unban [banId] [reason]',
    ['jail'] = '/jail [id] [minutes/0] [reason]',
    ['unjail'] = '/unjail [id]',
    ['unjailic'] = '/unjailic [id]',
    ['revive'] = '/revive [id]',
    ['setinjury'] = '/setinjury [id] [helpup/injured/dead]',
    ['setjob'] = '/setjob [id] [job] [grade]',
    ['checkinv'] = '/checkinv [id]',
    ['giveitem'] = '/giveitem [id] [item] [amount]',
    -- ['setmoney'] = '/setmoney [id] [cash/bank] [amount]',
    ['spawnveh'] = '/spawnveh [model]',
    ['deleteveh'] = '/deleteveh',
    ['fixveh'] = '/afix [id/biển số]',
    ['noclip'] = '/fly',
    ['god'] = '/god',
    ['invisible'] = '/invisible',
    ['clearwarns'] = '/clearwarns [id]',
    ['setlevel'] = '/setlevel [id] [level]',
    ['setwatchdog'] = '/setwatchdog [id] [1/0]',
    ['announce'] = '/o [message]',
    ['ads'] = '/ads [nđ]',
    ['setrankname'] = '/setrankname [id] [name] [#color]',
    ['nametags'] = '/nametags',
    ['a'] = '/a [message]',
    ['setprime'] = '/setprime [id] [days]',
    ['setprimeplus'] = '/setprimeplus [id] [days]',
    ['upgradeprimeplus'] = '/upgradeprimeplus [id]',
    ['setped'] = '/setped [id] [model] hoặc /setped [model]',
    ['skiptutorial'] = '/skiptutorial [id]',
}

RegisterCommand('ahelp', function(src)
    if AdminFunctions.GetLevel(src) < 1 then return end

    local level = AdminFunctions.GetLevel(src)
    local perms = Permissions.GetAll(level)

    if perms[1] == '*' then
        perms = {}
        for k, _ in pairs(CommandSyntaxes) do
            perms[#perms + 1] = k
        end
    end

    table.sort(perms)
    local lines = {}
    for _, p in ipairs(perms) do
        if CommandSyntaxes[p] then
            lines[#lines + 1] = '  ' .. CommandSyntaxes[p]
        end
    end
    TriggerClientEvent('chat:addMessage', src, {
        color = {99, 179, 237},
        multiline = true,
        args = { "{63B3ED}[AdminCore] Lệnh admin của bạn:\n" .. table.concat(lines, '\n') .. "{FFFFFF}" }
    })
    AdminLogger.Log(src, 'ahelp', nil, 'Xem danh sách lệnh admin')
end, false)

-- =============================================
--   /admins – Danh sach admin online
-- =============================================
RegisterCommand('admins', function(src)
    if AdminFunctions.GetLevel(src) < 1 then return end


    local list = {}
    for _, xPlayer in ipairs(ESX.GetExtendedPlayers()) do
        local pid = xPlayer.source
        local lvl = AdminFunctions.GetLevel(xPlayer)
        if lvl >= 1 then
            local rData = xPlayer and PlayerRankCache[xPlayer.identifier]
            list[#list + 1] = {
                id       = pid,
                name     = GetPlayerName(pid),
                level    = lvl,
                rankName = (rData and rData.name) or Config.DefaultLevelNames[lvl] or ('Level ' .. lvl),
                onDuty   = Player(pid).state.adminDutyName ~= nil,
            }
        end
    end

    TriggerClientEvent('admincore:adminList', src, list)
    AdminLogger.Log(src, 'admins', nil, 'Xem danh sách admin online')
end, false)


-- =============================================
--   /players – Danh sach nguoi choi online
-- =============================================
RegisterCommand('players', function(src)
    if AdminFunctions.GetLevel(src) < 1 then return end


    local players = GetPlayers()
    table.sort(players, function(a, b)
        return tonumber(a) < tonumber(b)
    end)

    local lines = {}
    for _, pid in ipairs(players) do
        pid = tonumber(pid)
        local xPlayer = ESX.GetPlayerFromId(pid)
        local charInfo = AdminFunctions.GetCharacterInfo(xPlayer)

        lines[#lines + 1] = ('[%d] CharID: %s | IC: %s | Steam: %s (%s)'):format(
            pid,
            charInfo.charid,
            charInfo.icName,
            charInfo.steamName,
            charInfo.steamIdentifier
        )
    end

    local message = #lines > 0
        and ('Người chơi online (%d):\n%s'):format(#lines, table.concat(lines, '\n'))
        or 'Không có người chơi online.'

    TriggerClientEvent('chat:addMessage', src, {
        color = { 80, 200, 255 },
        multiline = true,
        args = { 'AdminCore', message }
    })
    AdminLogger.Log(src, 'players', nil, 'Xem danh sách người chơi online')
end, false)


-- =============================================
--   /getinfo [id]
-- =============================================
RegisterCommand('agetinfo', function(src, args)
    requireAdmin(src, 'getinfo', function()
        local id = getTarget(src, args[1])
        if id then AdminFunctions.GetInfo(src, id) end
    end)
end, false)

-- =============================================
--   /goto [id]
-- =============================================
RegisterCommand('agoto', function(src, args)
    requireAdmin(src, 'goto', function()
        local id = getTarget(src, args[1])
        if id then AdminFunctions.Goto(src, id) end
    end)
end, false)

RegisterCommand('goto', function(src, args)
    requireAdmin(src, 'goto', function()
        local coords = parseGotoCoords(args)
        if coords then
            AdminFunctions.GotoCoords(src, coords)
            return
        elseif coords == false then
            AdminFunctions.Notify(src, 'Tọa độ không hợp lệ. Dùng vector3(x, y, z) hoặc vector4(x, y, z, heading).', 'error')
            return
        end

        local id = getTarget(src, args[1])
        if id then AdminFunctions.Goto(src, id) end
    end)
end, false)

-- =============================================
--   /gethere [id]
-- =============================================
RegisterCommand('agethere', function(src, args)
    requireAdmin(src, 'gethere', function()
        local id = getTarget(src, args[1])
        if id then AdminFunctions.GetHere(src, id) end
    end)
end, false)

RegisterCommand('bring', function(src, args)
    requireAdmin(src, 'gethere', function()
        local id = getTarget(src, args[1])
        if id then AdminFunctions.GetHere(src, id) end
    end)
end, false)

RegisterCommand('abring', function(src, args)
    requireAdmin(src, 'gethere', function()
        local id = getTarget(src, args[1])
        if id then AdminFunctions.GetHere(src, id) end
    end)
end, false)

-- =============================================
--   /spectate [id]
-- =============================================
RegisterCommand('aspectate', function(src, args)
    requireAdmin(src, 'spectate', function()
        if not args[1] then
            TriggerClientEvent('admincore:stopSpectate', src)
            return
        end
        local id = getTarget(src, args[1])
        if id then
            TriggerClientEvent('admincore:startSpectate', src, id)
            AdminLogger.Log(src, 'spectate', id, nil)
        end
    end)
end, false)

RegisterCommand('spectate', function(src, args)
    requireAdmin(src, 'spectate', function()
        if not args[1] then
            TriggerClientEvent('admincore:stopSpectate', src)
            return
        end
        local id = getTarget(src, args[1])
        if id then
            TriggerClientEvent('admincore:startSpectate', src, id)
            AdminLogger.Log(src, 'spectate', id, nil)
        end
    end)
end, false)

RegisterCommand('spec', function(src, args)
    requireAdmin(src, 'spectate', function()
        if not args[1] then
            TriggerClientEvent('admincore:stopSpectate', src)
            return
        end
        local id = getTarget(src, args[1])
        if id then
            TriggerClientEvent('admincore:startSpectate', src, id)
            AdminLogger.Log(src, 'spectate', id, nil)
        end
    end)
end, false)

-- =============================================
--   /freeze [id]
-- =============================================
RegisterCommand('freeze', function(src, args)
    requireAdmin(src, 'freeze', function()
        local id = getTarget(src, args[1])
        if id then AdminFunctions.Freeze(src, id) end
    end)
end, false)

-- =============================================
--   /kick [id] [reason]
-- =============================================
RegisterCommand('kick', function(src, args)
    requireAdmin(src, 'kick', function()
        local id = getTarget(src, args[1])
        if not id then return end
        local reason = table.concat(args, ' ', 2)
        if reason == '' then reason = nil end
        AdminFunctions.Kick(src, id, reason)
    end)
end, false)

RegisterCommand('ban', function(src, args)
    if AdminFunctions.GetLevel(src) < 4 then
        AdminFunctions.Notify(src, 'Lệnh này yêu cầu admin level 4 trở lên.', 'error')
        return
    end

    requireAdmin(src, 'ban', function()
        local id = getTarget(src, args[1])
        if not id then return end
        local reason = table.concat(args, ' ', 2)
        if reason == '' then reason = nil end
        AdminFunctions.Ban(src, id, reason)
    end)
end, false)

-- =============================================
--   /warn [id] [reason]
-- =============================================
RegisterCommand('warn', function(src, args)
    requireAdmin(src, 'warn', function()
        local id = getTarget(src, args[1])
        if not id then return end
        local reason = table.concat(args, ' ', 2)
        if reason == '' then
            AdminFunctions.Notify(src, 'Vui lòng nhập lý do cảnh cáo.', 'error')
            return
        end
        AdminFunctions.Warn(src, id, reason)
    end)
end, false)



-- =============================================
--   /revive [id?]
-- =============================================
RegisterCommand('revive', function(src, args)
    if isAdvisor(src) then
        local targetId = getAdvisorReviveTarget(src, args[1])
        if targetId then AdminFunctions.Revive(src, targetId) end
        return
    end

    requireAdmin(src, 'revive', function()
        if args[1] then
            local id = getTarget(src, args[1])
            if id then AdminFunctions.Revive(src, id) end
        else
            AdminFunctions.Revive(src, src)
        end
    end)
end, false)

-- =============================================
--   /setinjury [id] [helpup|injured|dead|1|2|3]
-- =============================================
RegisterCommand('setinjury', function(src, args)
    requireAdmin(src, 'setinjury', function()
        if not args[1] or not args[2] then
            AdminFunctions.Notify(src, 'Cú pháp: /setinjury [id] [helpup|injured|dead|1|2|3]', 'warning')
            return
        end

        local id = getTarget(src, args[1])
        if not id then return end

        local state = args[2]:lower()
        local xTarget = ESX.GetPlayerFromId(id)
        if not xTarget then
            AdminFunctions.Notify(src, 'Không tìm thấy người chơi.', 'error')
            return
        end

        local statusAliases =
        {
            helpup = 1,
            ['1'] = 1,
            injured = 2,
            bitheong = 2,
            ['2'] = 2,
            dead = 3,
            chot = 3,
            ['tu-vong'] = 3,
            tuvong = 3,
            ['3'] = 3,
        }
        local status = statusAliases[state]

        if not status then
            AdminFunctions.Notify(src, 'Cú pháp: /setinjury [id] [helpup|injured|dead|1|2|3]', 'warning')
            return
        end

        if GetResourceState('lavie_injury') ~= 'started' then
            AdminFunctions.Notify(src, 'Hệ thống thương tích đang không sẵn sàng.', 'error')
            return
        end

        local readinessInvoked, injuryReady, injuryReadyError = pcall(function()
            return exports.lavie_injury:IsPlayerReady(id)
        end)

        if not readinessInvoked or (injuryReady ~= true and injuryReadyError ~= 'corrupt_storage') then
            AdminFunctions.Notify(src, ('Dữ liệu thương tích của người chơi chưa sẵn sàng (%s).'):format(tostring(injuryReadyError or 'readiness_check_failed')), 'error')
            return
        end

        local targetCoords = xTarget.getCoords()
        local targetName = GetPlayerName(id) or xTarget.getName()
        local invoked, changed, changeError = pcall(function()
            return exports.lavie_injury:SetPlayerStatus(id, status,
            {
                reason = 'admin_override',
                attackerId = src,
                coords = targetCoords,
                allowCorruptRepair = true,
            })
        end)

        if not invoked or changed ~= true then
            AdminFunctions.Notify(src, ('Không thể đặt trạng thái thương tích (%s).'):format(tostring(changeError or changed or 'transition_failed')), 'error')
            return
        end

        local bodyResourceStarted = GetResourceState('lavie_injury') == 'started'
        local bodyDamageCleared = false
        local bodyDamageError = bodyResourceStarted and nil or 'resource_unavailable'

        if bodyResourceStarted then
            local bodyInvoked, cleared, clearError = pcall(function()
                return exports.lavie_injury:ClearPlayerDamages(id)
            end)

            bodyDamageCleared = bodyInvoked and cleared == true
            bodyDamageError = clearError or cleared
        end

        local labels = {
            [1] = 'Helpup',
            [2] = 'Bị thương',
            [3] = 'Tử vong',
        }

        if bodyDamageCleared then
            AdminFunctions.Notify(src, ('Đã đặt trạng thái của %s thành %s (Status %d)'):format(targetName, labels[status], status), 'success')
        else
            AdminFunctions.Notify(src, ('Đã đặt trạng thái của %s nhưng chưa thể dọn dữ liệu vết thương.'):format(targetName), 'warning')
        end

        AdminLogger.Log(src, 'setinjury', id, ('Set state to %s (Status %d), body cleanup: %s'):format(labels[status], status, bodyDamageCleared and 'ok' or tostring(bodyDamageError)))
    end)
end, false)


-- =============================================
--   /jail [id] [time_minutes] [reason?]
-- =============================================
RegisterCommand('jail', function(src, args)
    requireAdmin(src, 'jail', function()
        local id       = getTarget(src, args[1])
        local duration = tonumber(args[2]) or Config.DefaultJailDuration
        local reason   = table.concat(args, ' ', 3)
        if not id then return end
        AdminFunctions.Jail(src, id, duration, reason)
    end)
end, false)

local function UnifiedUnjail(src, targetId)
    local xTarget = ESX.GetPlayerFromId(targetId)
    if not xTarget then return end

    local targetName = GetPlayerName(targetId) or xTarget.getName()
    local adminName = (src > 0) and GetPlayerName(src) or "Console"

    local isOOC = (JailCache[xTarget.identifier] ~= nil)
    local isIC = false

    local res = MySQL.query.await('SELECT jail_time FROM users WHERE identifier = ?', { xTarget.identifier })
    if res and res[1] and res[1].jail_time and res[1].jail_time > 0 then
        isIC = true
    end

    if not isOOC and not isIC then
        if src > 0 then
            AdminFunctions.Notify(src, 'Đối tượng không ở trong tù (IC hoặc OOC).', 'error')
        end
        return
    end

    if isOOC then
        AdminFunctions.Unjail(src, targetId)
        local msg = ("{33AA33} Admin %s đã thả tự do cho %s."):format(adminName, targetName)
        TriggerClientEvent('custom-chat:addMessage', -1, msg)
    end

    if isIC then
        local success = exports['police']:UnjailPlayer(targetId)
        if success then
            local msg = ("{33AA33} Admin %s đã thả tự do cho %s."):format(adminName, targetName)
            TriggerClientEvent('custom-chat:addMessage', -1, msg)
            if src > 0 then
                TriggerClientEvent('lv_notify:client:notify', src, { title = 'Hệ thống', message = 'Đã thả tù IC cho đối tượng.', type = 'success' })
            end
        else
            if src > 0 then
                TriggerClientEvent('lv_notify:client:notify', src, { title = 'Lỗi', message = 'Không thể thả tù IC cho đối tượng.', type = 'error' })
            end
        end
    end
end

-- =============================================
--   /unjail [id]
-- =============================================
RegisterCommand('unjail', function(src, args)
    requireAdmin(src, 'unjail', function()
        local id = getTarget(src, args[1])
        if id then UnifiedUnjail(src, id) end
    end)
end, false)

-- =============================================
--   /unjailic [id]
-- =============================================
RegisterCommand('unjailic', function(src, args)
    requireAdmin(src, 'unjail', function()
        local id = getTarget(src, args[1])
        if id then UnifiedUnjail(src, id) end
    end)
end, false)

RegisterCommand('fixtime', function(src, args)
    requireAdmin(src, 'jail', function()
        local id = getTarget(src, args[1])
        local duration = tonumber(args[2])
        if not id or not duration then return end
        local xTarget = ESX.GetPlayerFromId(id)
        if not xTarget then return end
        local jailData = JailCache[xTarget.identifier]
        if not jailData then
            AdminFunctions.Notify(src, 'Người chơi này không ở trong tù OOC.', 'error')
            return
        end
        local expireAt = os.time() + duration * 60
        jailData.expire_at = expireAt
        MySQL.query.await('UPDATE admin_jails SET expire_at = ? WHERE identifier = ?', { expireAt, xTarget.identifier })
        TriggerClientEvent('admincore:jail', id, duration, "Điều chỉnh thời gian tù")
        AdminFunctions.Notify(src, ('Đã sửa thời gian tù của %s thành %d phút.'):format(GetPlayerName(id), duration), 'success')
    end)
end, false)

-- =============================================
--   /unban [banId] [reason]
-- =============================================
-- RegisterCommand('unban', function(src, args)
--     if AdminFunctions.GetLevel(src) < 4 then
--         AdminFunctions.Notify(src, 'Lệnh này yêu cầu admin level 4 trở lên.', 'error')
--         return
--     end

--     requireAdmin(src, 'unban', function()
--         local banId = args[1]
--         if not banId then
--             AdminFunctions.Notify(src, 'Cú pháp: /unban [banId] [lý do]', 'error')
--             return
--         end
--         local reason = table.concat(args, ' ', 2)
--         if reason == '' then reason = nil end
--         AdminFunctions.RavenUnban(src, banId, reason)
--     end)
-- end, false)

-- =============================================
--   /skiptutorial [id]
-- =============================================
RegisterCommand('skiptutorial', function(src, args)
    requireAdmin(src, 'setlevel', function()
        local id = getTarget(src, args[1])
        if id then
            local xTarget = ESX.GetPlayerFromId(id)
            if xTarget then
                exports['lv_tutorial']:SkipTutorial(id)
                AdminFunctions.Notify(src, 'Đã bỏ qua tutorial cho ' .. GetPlayerName(id), 'success')
                AdminFunctions.Notify(id, 'Admin đã bỏ qua tutorial cho bạn.', 'info')
                AdminLogger.Log(src, 'skiptutorial', id, 'Bỏ qua tutorial')
            end
        end
    end)
end, false)

-- =============================================
--   /setjob [id] [job] [grade]
-- =============================================
RegisterCommand('setjob', function(src, args)
    requireAdmin(src, 'setjob', function()
        local id    = getTarget(src, args[1])
        local job   = args[2]
        local grade = tonumber(args[3]) or 0
        if not id or not job then
            AdminFunctions.Notify(src, 'Cú pháp: /setjob [id] [job] [grade]', 'error')
            return
        end
        AdminFunctions.SetJob(src, id, job, grade)
    end)
end, false)

-- -- =============================================
-- --   /setmoney [id] [cash|bank] [amount]
-- -- =============================================
-- RegisterCommand('setmoney', function(src, args)
--     requireAdmin(src, 'setmoney', function()
--         local id      = getTarget(src, args[1])
--         local accType = args[2]
--         local amount  = tonumber(args[3])
--         if not id or not accType or not amount then
--             AdminFunctions.Notify(src, 'Cú pháp: /setmoney [id] [cash|bank] [số_tiền]', 'error')
--             return
--         end
--         AdminFunctions.SetMoney(src, id, accType, amount)
--     end)
-- end, false)

-- =============================================
--   /checkinv [id]
-- =============================================
RegisterCommand('checkinv', function(src, args)
    requireAdmin(src, 'checkinv', function()
        if src == 0 then
            print('[AdminCore] /checkinv chi co the dung trong game.')
            return
        end

        if GetResourceState('ox_inventory') ~= 'started' then
            AdminFunctions.Notify(src, 'ox_inventory chua duoc khoi dong.', 'error')
            return
        end

        local id = getTarget(src, args[1])
        if not id then return end

        local openedInventory = exports.ox_inventory:forceOpenInventory(src, 'player', id)
        if not openedInventory then
            AdminFunctions.Notify(src, 'Khong the mo inventory cua nguoi choi nay.', 'error')
            return
        end

        AdminFunctions.Notify(src, ('Dang kiem tra inventory cua %s (ID: %d).'):format(GetPlayerName(id), id), 'success')
        AdminLogger.Log(src, 'checkinv', id, 'Mo inventory nguoi choi')
    end)
end, false)

-- =============================================
--   /giveitem [id] [item] [amount]
-- =============================================
RegisterCommand('giveitem', function(src, args)
    requireAdmin(src, 'giveitem', function()
        local id     = getTarget(src, args[1])
        local item   = args[2]
        local amount = tonumber(args[3]) or 1
        if not id or not item then
            AdminFunctions.Notify(src, 'Cú pháp: /giveitem [id] [item] [số_lượng]', 'error')
            return
        end
        AdminFunctions.GiveItem(src, id, item, amount)
    end)
end, false)

-- =============================================
--   /spawnveh [model]
-- =============================================
RegisterCommand('spawnveh', function(src, args)
    requireAdmin(src, 'spawnveh', function()
        local model = args[1]
        if not model then
            AdminFunctions.Notify(src, 'Cú pháp: /spawnveh [model]', 'error')
            return
        end
        AdminFunctions.SpawnVehicle(src, model)
    end)
end, false)

RegisterCommand('car', function(src, args)
    requireAdmin(src, 'spawnveh', function()
        local model = args[1]
        if not model then
            AdminFunctions.Notify(src, 'Cú pháp: /car [model]', 'error')
            return
        end
        AdminFunctions.SpawnVehicle(src, model)
    end)
end, false)

-- =============================================
--   /deleteveh  – Xoa xe gan nhat
-- =============================================
RegisterCommand('deleteveh', function(src)
    requireAdmin(src, 'deleteveh', function()
        AdminFunctions.DeleteVehicle(src, nil)
    end)
end, false)

-- =============================================
--   /afix [id/biển số]  – Sửa xe theo ID hoặc biển số (bỏ trống để sửa xe đang lái)
-- =============================================
RegisterCommand('afix', function(src, args)
    requireAdmin(src, 'fixveh', function()
        if #args > 0 then
            local plate = table.concat(args, ' ')
            if plate:gsub('%s+', '') == '' then
                AdminFunctions.Notify(src, 'Vui lòng nhập biển số xe.', 'error')
                return
            end

            local target = #args == 1 and ESX.GetPlayerFromId(tonumber(args[1]) or -1)
            if target then
                AdminFunctions.FixVehicle(src, target.source)
            else
                AdminFunctions.FixVehicleByPlate(src, plate)
            end
        else
            AdminFunctions.FixVehicle(src, src)
        end
    end)
end, false)

-- =============================================
--   /fly  – Toggle (client-side)
-- =============================================
RegisterCommand('fly', function(src)
    requireAdmin(src, 'noclip', function()
        TriggerClientEvent('admincore:toggleNoclip', src)
        AdminLogger.Log(src, 'noclip', nil, 'Toggle noclip')
    end)
end, false)

-- =============================================
--   /god  – Toggle god mode (client-side)
-- =============================================
RegisterCommand('god', function(src)
    if isAdvisor(src) then
        AdminFunctions.Notify(src, 'Advisor không được tự bật god mode.', 'error')
        return
    end

    requireAdmin(src, 'god', function()
        TriggerClientEvent('admincore:toggleGod', src)
        AdminLogger.Log(src, 'god', nil, 'Toggle god mode')
    end)
end, false)

-- =============================================
--   /invisible – Toggle invisible
-- =============================================
RegisterCommand('invisible', function(src)
    requireAdmin(src, 'invisible', function()
        TriggerClientEvent('admincore:toggleInvisible', src)
        AdminLogger.Log(src, 'invisible', nil, 'Toggle invisible')
    end)
end, false)

-- =============================================
--   /clearwarns [id]
-- =============================================
RegisterCommand('clearwarns', function(src, args)
    requireAdmin(src, 'clearwarns', function()
        local id = getTarget(src, args[1])
        if id then AdminFunctions.ClearWarns(src, id) end
    end)
end, false)

-- =============================================
--   /setlevel [id] [level]
-- =============================================
RegisterCommand('setlevel', function(src, args)
    requireAdmin(src, 'setlevel', function()
        local id    = getTarget(src, args[1])
        local level = tonumber(args[2])
        if not id or level == nil then
            AdminFunctions.Notify(src, ('Cú pháp: /setlevel [id] [0-%d]'):format(Config.MaxAdminLevel), 'error')
            return
        end
        local ok, msg = AdminFunctions.SetLevel(src, id, level)
        AdminFunctions.Notify(src, msg, ok and 'success' or 'error')
    end)
end, false)

-- =============================================
--   /setwatchdog [id] [1/0]
-- =============================================
RegisterCommand('setwatchdog', function(src, args)
    requireAdmin(src, 'setlevel', function()
        local id = getTarget(src, args[1])
        if not id then
            AdminFunctions.Notify(src, 'Cú pháp: /setwatchdog [id] [1/0 hoặc on/off]', 'error')
            return
        end

        local status = nil
        if args[2] then
            local val = tostring(args[2]):lower()
            if val == '1' or val == 'on' or val == 'true' or val == 'yes' then
                status = true
            elseif val == '0' or val == 'off' or val == 'false' or val == 'no' then
                status = false
            end
        end

        local ok, msg = AdminFunctions.SetWatchdog(src, id, status)
        AdminFunctions.Notify(src, msg, ok and 'success' or 'error')
    end)
end, false)

-- =============================================
--   /setprime [id] [days]
-- =============================================
RegisterCommand('setprime', function(src, args)
    local level = AdminFunctions.GetLevel(src)
    if level < 4 then 
        AdminFunctions.Notify(src, 'Bạn không có quyền thực hiện lệnh này.', 'error')
        return
    end



    local id = getTarget(src, args[1])
    local days = tonumber(args[2])

    if not id or days == nil then
        AdminFunctions.Notify(src, 'Cú pháp: /setprime [id] [số ngày (0 = xóa)]', 'error')
        return
    end

    if exports['prime_status'] then
        local ok, isPrime = exports['prime_status']:SetPrime(id, days)
        if ok then
            if days > 0 then
                PrimeNotify(src, 'success', ('Đã cấp Prime cho ID %d thời hạn %d ngày.'):format(id, days))
                PrimeNotify(id, 'success', ('Bạn đã được cấp Prime thời hạn %d ngày.'):format(days))
            else
                PrimeNotify(src, 'warning', ('Đã xóa Prime của ID %d.'):format(id))
                PrimeNotify(id, 'warning', 'Prime của bạn đã hết hạn hoặc bị xóa.')
            end
            AdminLogger.Log(src, 'setprime', id, days > 0 and ('Cấp Prime %d ngày'):format(days) or 'Xóa Prime')
        else
            PrimeNotify(src, 'error', 'Có lỗi khi thao tác Prime.')
        end
    else
        AdminFunctions.Notify(src, 'Resource prime_status không hoạt động.', 'error')
    end
end, false)

RegisterCommand('setprimeplus', function(src, args)
    local level = AdminFunctions.GetLevel(src)
    if level < 4 then
        AdminFunctions.Notify(src, 'Bạn không có quyền thực hiện lệnh này.', 'error')
        return
    end

    local id = getTarget(src, args[1])
    local days = tonumber(args[2])

    if not id or days == nil then
        AdminFunctions.Notify(src, 'Cú pháp: /setprimeplus [id] [số ngày (0 = xóa)]', 'error')
        return
    end

    if exports['prime_status'] then
        local ok = exports['prime_status']:SetPrimePlus(id, days)
        if ok then
            if days > 0 then
                PrimeNotify(src, 'success', ('Đã cấp Prime Plus cho ID %d thời hạn %d ngày.'):format(id, days))
                PrimeNotify(id, 'success', ('Bạn đã được cấp Prime Plus thời hạn %d ngày.'):format(days))
            else
                PrimeNotify(src, 'warning', ('Đã xóa Prime Plus của ID %d.'):format(id))
                PrimeNotify(id, 'warning', 'Prime Plus của bạn đã hết hạn hoặc bị xóa.')
            end
            AdminLogger.Log(src, 'setprimeplus', id, days > 0 and ('Cấp Prime Plus %d ngày'):format(days) or 'Xóa Prime Plus')
        else
            PrimeNotify(src, 'error', 'Có lỗi khi thao tác Prime Plus.')
        end
    else
        AdminFunctions.Notify(src, 'Resource prime_status không hoạt động.', 'error')
    end
end, false)

RegisterCommand('upgradeprimeplus', function(src, args)
    local level = AdminFunctions.GetLevel(src)
    if level < 4 then
        AdminFunctions.Notify(src, 'Bạn không có quyền thực hiện lệnh này.', 'error')
        return
    end

    local id = getTarget(src, args[1])
    if not id then
        AdminFunctions.Notify(src, 'Cú pháp: /upgradeprimeplus [id]', 'error')
        return
    end

    if exports['prime_status'] then
        local ok, result = exports['prime_status']:UpgradePrimeToPlus(id)
        if ok then
            local daysLeft = math.max(1, math.ceil((tonumber(result) or 0) / 86400))
            PrimeNotify(src, 'success', ('Đã nâng cấp ID %d lên Prime Plus, giữ nguyên %d ngày còn lại.'):format(id, daysLeft))
            PrimeNotify(id, 'success', ('Prime của bạn đã được nâng cấp lên Prime Plus, còn %d ngày.'):format(daysLeft))
            AdminLogger.Log(src, 'upgradeprimeplus', id, ('Nâng cấp Prime Plus, còn %d ngày'):format(daysLeft))
        else
            PrimeNotify(src, 'error', result or 'Không thể nâng cấp Prime Plus.')
        end
    else
        AdminFunctions.Notify(src, 'Resource prime_status không hoạt động.', 'error')
    end
end, false)

-- =============================================
--   /o [message]
-- =============================================
RegisterCommand('o', function(src, args)
    requireAdmin(src, 'announce', function()
        local msg = table.concat(args, ' ')
        if msg == '' then
            AdminFunctions.Notify(src, 'Vui lòng nhập nội dung thông báo.', 'error')
            return
        end
        AdminFunctions.Announce(src, msg)
    end)
end, false)

-- =============================================
--   /ads [message]
-- =============================================
RegisterCommand('ads', function(src, args)
    requireAdmin(src, 'announce', function()
        local msg = table.concat(args, ' ')
        if msg == '' then
            AdminFunctions.Notify(src, 'Vui lòng nhập nội dung thông báo.', 'error')
            return
        end
        if GetResourceState('custom-chat') == 'started' then
            TriggerClientEvent('custom-chat:addMessage', -1, "{19AE61}[Advertisement] " .. msg)
        else
            TriggerClientEvent('chat:addMessage', -1, {
                color = {25, 174, 97},
                multiline = true,
                args = { "[Advertisement] " .. msg }
            })
        end
        AdminLogger.Log(src, 'ads', nil, msg)
    end)
end, false)

-- =============================================
--   /a [message] - Admin Chat
-- =============================================
RegisterCommand('a', function(src, args)
    sendAdminChat(src, table.concat(args, ' '))
end, false)

local function toggleAdminChat(src)
    local level = AdminFunctions.GetLevel(src)
    local isOwner = AdminFunctions.IsOwner(src)
    local reportAdminMinLevel = Config.Advisor.reportAdminMinLevel or 2

    if not isOwner and level < reportAdminMinLevel then
        AdminFunctions.Notify(src, 'Bạn không có quyền thực hiện lệnh này.', 'error')
        return
    end

    local state = Player(src).state
    local muted = not state.adminChatMuted
    state:set('adminChatMuted', muted, true)

    if muted then
        AdminFunctions.Notify(src, 'Đã tắt nhận tin nhắn Admin Chat.', 'success')
    else
        AdminFunctions.Notify(src, 'Đã bật nhận tin nhắn Admin Chat.', 'success')
    end
end

RegisterCommand('toggleac', function(src)
    toggleAdminChat(src)
end, false)

RegisterCommand('tac', function(src)
    toggleAdminChat(src)
end, false)

RegisterCommand('toggleadminchat', function(src)
    toggleAdminChat(src)
end, false)

-- =============================================
--   /c [message] - Advisor Chat
-- =============================================
RegisterCommand('c', function(src, args)
    sendAdvisorChat(src, table.concat(args, ' '))
end, false)

local function toggleAdvisorChat(src)
    local level = AdminFunctions.GetLevel(src)
    if level < 1 and not isAdvisor(src) and not AdminFunctions.IsWatchdog(src) then
        AdminFunctions.Notify(src, 'Bạn không có quyền thực hiện lệnh này.', 'error')
        return
    end

    local state = Player(src).state
    local muted = not state.advisorChatMuted
    state:set('advisorChatMuted', muted, true)

    if muted then
        AdminFunctions.Notify(src, 'Đã tắt nhận tin nhắn Advisor Chat.', 'success')
    else
        AdminFunctions.Notify(src, 'Đã bật nhận tin nhắn Advisor Chat.', 'success')
    end
end

RegisterCommand('togglec', function(src)
    toggleAdvisorChat(src)
end, false)

RegisterCommand('tc', function(src)
    toggleAdvisorChat(src)
end, false)

RegisterCommand('toggleadvisorchat', function(src)
    toggleAdvisorChat(src)
end, false)

RegisterCommand('tadvisor', function(src)
    toggleAdvisorChat(src)
end, false)

-- =============================================
--   /cduty [name?] - Advisor Duty
-- =============================================
RegisterCommand('cduty', function(src, args)
    toggleAdvisorDuty(src, table.concat(args, ' '))
end, false)

RegisterCommand('chelp', function(src)
    disableCommand(src)
end, false)

-- =============================================
--   /report [message] - Member report to admin
-- =============================================
RegisterCommand('report', function(src, args)
    if not checkCooldown(src, 'report') then return end

    local msg = table.concat(args, ' ')
    if msg == '' then
        AdminFunctions.Notify(src, 'Cú pháp: /report [nội dung cần hỗ trợ]', 'error')
        return
    end

    local activeId = getActiveReportByPlayer(src)
    if activeId then
        AdminFunctions.Notify(src, ('Bạn đang có report #%d chưa kết thúc. Dùng /huybaocao để hủy trước khi gửi report mới.'):format(activeId), 'error')
        return
    end

    local id = NextReportId
    NextReportId = NextReportId + 1

    Reports[id] = {
        id = id,
        playerId = src,
        playerName = GetPlayerName(src),
        message = msg,
        status = 'open',
        createdAt = os.time(),
    }

    SetTimeout((Config.Advisor.reportAutoPushSeconds or 300) * 1000, function()
        local report = Reports[id]
        if not report or report.status ~= 'open' then return end

        report.status = 'advisor'
        report.autoPushedAt = os.time()
        broadcastToAdvisors({56, 189, 248}, ('{38BDF8}[Advisor Help #%d] %s (ID: %d): %s\nReport không được Admin nhận sau 5 phút. Dùng /rpanel để kiểm tra.{FFFFFF}'):format(
            id,
            report.playerName,
            report.playerId,
            report.message
        ))
        if ESX.GetPlayerFromId(report.playerId) then
            AdminFunctions.Notify(report.playerId, 'Report chưa được Admin nhận sau 5 phút và đã tự chuyển cho Advisor.', 'info')
        end
        broadcastReportNuiToAdvisors({
            kind = 'pushed',
            title = 'Hỗ trợ Advisor (tự động)',
            accent = 'advisor',
            report = serializeReport(report),
        })
        syncReportsForStaff()
    end)

    AdminFunctions.Notify(src, ('Đã gửi report #%d. Vui lòng chờ staff phản hồi.'):format(id), 'success')
    broadcastToStaff({248, 113, 113}, ('{F87171}[Report #%d] %s (ID: %d): %s\nDùng /rpanel để kiểm tra.{FFFFFF}'):format(
        id,
        GetPlayerName(src),
        src,
        msg
    ))
    broadcastReportNuiToStaff({
        kind = 'new',
        title = 'Report mới',
        accent = 'danger',
        report = serializeReport(Reports[id]),
    })
    syncReportsForStaff()
    AdminLogger.Log(src, 'report', nil, msg)
end, false)

RegisterCommand('huybaocao', function(src)
    cancelPlayerReport(src)
end, false)

RegisterNetEvent('admincore:cancelMyReport', function()
    cancelPlayerReport(source)
end)

-- =============================================
--   /rfinish|/endhelp - Finish Advisor help
-- =============================================
RegisterCommand('rfinish', function(src)
    disableCommand(src)
end, false)

RegisterCommand('endhelp', function(src)
    disableCommand(src)
end, false)

RegisterNetEvent('admincore:getReports', function()
    local src = source
    local level = AdminFunctions.GetLevel(src)
    local isRepAdmin = isReportAdmin(src)
    local isAdv = isAdvisor(src)
    -- print(('[AdminCore Debug] getReports called by Src: %s | Level: %s | isReportAdmin: %s | isAdvisor: %s'):format(src, level, isRepAdmin, isAdv))
    if not isRepAdmin and not isAdv then
        -- print('[AdminCore Debug] Blocked: player is neither report admin nor advisor')
        return
    end
    local reports = getVisibleReports(src)
    -- print(('[AdminCore Debug] Sending %d report(s) to Src: %s'):format(#reports, src))
    TriggerClientEvent('admincore:updateReports', src, reports)
end)

RegisterNetEvent('admincore:reportAction', function(action, reportId, reason)
    local src = source
    if not checkCooldown(src, 'action') then return end

    local id, report = getReportById(src, reportId)
    if not id then return end

    if action == 'accept' then
        if isReportAdmin(src) and not isAdvisorOnDuty(src) then
            if report.status ~= 'open' then
                AdminFunctions.Notify(src, 'Report này không còn ở trạng thái chờ admin.', 'error')
                return
            end

            report.status = 'admin_accepted'
            report.acceptedBy = src
            AdminFunctions.Notify(src, ('Đã nhận report #%d.'):format(id), 'success')
            if ESX.GetPlayerFromId(report.playerId) then
                AdminFunctions.Notify(report.playerId, ('Admin %s đã nhận report của bạn.'):format(GetPlayerName(src)), 'info')
            end
            broadcastToStaff({56, 189, 248}, ('{38BDF8}[Report] %s đã nhận report #%d.{FFFFFF}'):format(GetPlayerName(src), id))
            AdminLogger.Log(src, 'report_accept_admin', report.playerId, ('Report #%d | Noi dung: %s'):format(id, report.message or ''))
            syncReportsForStaff()
            return
        end

        requireAdvisor(src, function()
            if report.status ~= 'advisor' then
                AdminFunctions.Notify(src, 'Report này chưa được admin đẩy xuống Advisor hoặc đã có người nhận.', 'error')
                return
            end

            if ActiveAdvisorHelps[src] then
                AdminFunctions.Notify(src, 'Bạn đang xử lý một hỗ trợ khác. Dùng /rfinish trước.', 'error')
                return
            end

            if not ESX.GetPlayerFromId(report.playerId) then
                report.status = 'closed'
                AdminFunctions.Notify(src, 'Người report đã offline, report đã được đóng.', 'error')
                syncReportsForStaff()
                return
            end

            report.status = 'advisor_accepted'
            report.acceptedBy = src
            ActiveAdvisorHelps[src] = { reportId = id, playerId = report.playerId }

            local coords = GetEntityCoords(GetPlayerPed(report.playerId))
            TriggerClientEvent('admincore:advisorHelpTeleport', src, coords.x, coords.y, coords.z + 1.0)
            AdminFunctions.Notify(src, ('Đã nhận report #%d. Dùng /rfinish hoặc /endhelp để kết thúc.'):format(id), 'success')
            AdminFunctions.Notify(report.playerId, ('Advisor %s đã nhận hỗ trợ của bạn.'):format(GetPlayerName(src)), 'info')
            broadcastToStaff({56, 189, 248}, ('{38BDF8}[Report] Advisor %s đã nhận report #%d.{FFFFFF}'):format(GetPlayerName(src), id))
            AdminLogger.Log(src, 'advisor_help_accept', report.playerId, ('Report #%d | Noi dung: %s'):format(id, report.message or ''))
            syncReportsForStaff()
        end)
    elseif action == 'deny' then
        if not isReportAdmin(src) then return end

        reason = tostring(reason or '')
        if reason == '' then reason = 'Không phù hợp' end

        report.status = 'denied'
        report.closedBy = src
        report.closedAt = os.time()
        releaseAdvisorHelpForReport(id, 'Report #%d đã bị admin từ chối.')
        if ESX.GetPlayerFromId(report.playerId) then
            AdminFunctions.Notify(report.playerId, ('Report #%d đã bị từ chối. Lý do: %s'):format(id, reason), 'error')
        end
        AdminFunctions.Notify(src, ('Đã từ chối report #%d.'):format(id), 'success')
        broadcastToStaff({248, 113, 113}, ('{F87171}[Report] %s đã từ chối report #%d: %s{FFFFFF}'):format(GetPlayerName(src), id, reason))
        AdminLogger.Log(src, 'report_deny', report.playerId, ('Report #%d | Ly do: %s | Noi dung: %s'):format(id, reason, report.message or ''))
        syncReportsForStaff()
    elseif action == 'push' then
        if not isReportAdmin(src) then return end

        if report.status ~= 'open' and report.status ~= 'admin_accepted' then
            AdminFunctions.Notify(src, 'Report này không thể đẩy xuống Advisor.', 'error')
            return
        end

        report.status = 'advisor'
        report.pushedBy = src
        AdminFunctions.Notify(src, ('Đã đẩy report #%d xuống Advisor.'):format(id), 'success')
        broadcastToAdvisors({56, 189, 248}, ('{38BDF8}[Advisor Help #%d] %s (ID: %d): %s\nDùng /rpanel để kiểm tra.{FFFFFF}'):format(
            id,
            report.playerName,
            report.playerId,
            report.message
        ))
        if ESX.GetPlayerFromId(report.playerId) then
            AdminFunctions.Notify(report.playerId, 'Report của bạn đã được chuyển cho Advisor.', 'info')
        end
        AdminLogger.Log(src, 'report_push_advisor', report.playerId, ('Report #%d | Noi dung: %s'):format(id, report.message or ''))
        broadcastReportNuiToStaff({
            kind = 'pushed_admin',
            title = 'Đã đẩy xuống Advisor',
            accent = 'advisor',
            report = serializeReport(report),
        })
        broadcastReportNuiToAdvisors({
            kind = 'pushed',
            title = 'Hỗ trợ Advisor',
            accent = 'advisor',
            report = serializeReport(report),
        })
        syncReportsForStaff()
    elseif action == 'finish' then
        local activeHelp = ActiveAdvisorHelps[src]
        if activeHelp and activeHelp.reportId == id then
            closeAdvisorHelp(src)
            return
        end

        if isReportAdmin(src) then
            report.status = 'closed'
            report.closedBy = src
            report.closedAt = os.time()
            releaseAdvisorHelpForReport(id, 'Report #%d đã được admin kết thúc.')
            if ESX.GetPlayerFromId(report.playerId) then
                AdminFunctions.Notify(report.playerId, ('Report #%d đã được xử lý xong.'):format(id), 'success')
            end
            AdminFunctions.Notify(src, ('Đã kết thúc report #%d.'):format(id), 'success')
            AdminLogger.Log(src, 'report_finish_admin', report.playerId, ('Report #%d | Noi dung: %s'):format(id, report.message or ''))
            syncReportsForStaff()
            return
        end

        requireAdvisor(src, function()
            closeAdvisorHelp(src)
        end)
    elseif action == 'delete' then
        if not isReportAdmin(src) then return end

        report.status = 'deleted'
        report.closedBy = src
        report.closedAt = os.time()
        
        releaseAdvisorHelpForReport(id, 'Report #%d đã bị admin xóa.')
        
        AdminFunctions.Notify(src, ('Đã xóa report #%d.'):format(id), 'success')
        AdminLogger.Log(src, 'report_delete', report.playerId, ('Report #%d | Noi dung: %s'):format(id, report.message or ''))
        syncReportsForStaff()
        return
    end
end)

-- =============================================
--   /setrankname [id] [name] [color?]
-- =============================================
RegisterCommand('setrankname', function(src, args)
    requireAdmin(src, 'setrankname', function()
        local id = getTarget(src, args[1])
        if not id or not args[2] then
            AdminFunctions.Notify(src, 'Cú pháp: /setrankname [id] [tên] [#màu?]', 'error')
            return
        end

        local nameParts = {}
        local color = nil

        if #args > 2 then
            local lastArg = args[#args]
            if lastArg:sub(1, 1) == '#' or lastArg:match('^%x%x%x%x%x%x$') or lastArg:match('^%x%x%x$') then
                color = lastArg
                if color:sub(1, 1) ~= '#' then color = '#' .. color end
                for i = 2, #args - 1 do
                    table.insert(nameParts, args[i])
                end
            else
                for i = 2, #args do
                    table.insert(nameParts, args[i])
                end
            end
        else
            table.insert(nameParts, args[2])
        end

        local name = table.concat(nameParts, ' ')
        AdminFunctions.SetRankName(src, id, name, color)
    end)
end, false)

-- =============================================
--   /nametags – Toggle ESP / Nametags (client-side)
-- =============================================
RegisterCommand('nametags', function(src)
    requireAdmin(src, 'nametags', function()
        TriggerClientEvent('admincore:toggleNametags', src)
        AdminLogger.Log(src, 'nametags', nil, 'Toggle nametags')
    end)
end, false)

-- =============================================
--   /setped [id] [model] hoặc /setped [model]
-- =============================================
RegisterCommand('setped', function(src, args)
    requireAdmin(src, 'setped', function()
        local target, model
        if args[2] then
            target = getTarget(src, args[1])
            if not target then return end
            model = args[2]
        else
            target = src
            model = args[1]
        end

        if not model or model == '' then
            AdminFunctions.Notify(src, 'Cú pháp: /setped [id] [model] hoặc /setped [model]', 'error')
            return
        end

        TriggerClientEvent('admincore:setPed', target, model)
        AdminLogger.Log(src, 'setped', target, ('Set ped model tam thoi: %s'):format(model))
        if target ~= src then
            AdminFunctions.Notify(src, ('Đã đổi ped của ID %d thành %s tạm thời.'):format(target, model), 'success')
        end
    end)
end, false)



-- =============================================
--   ESX Callback: getMyLevel
-- =============================================
ESX.RegisterServerCallback('admincore:getMyLevel', function(src, cb)
    local level = AdminFunctions.GetLevel(src)
    -- Đảm bảo statebag luôn được đồng bộ khi client request
    AdminFunctions.SetAdminStateBag(src, level)
    cb(level)
end)

-- =============================================
--   Admin Duty System
-- =============================================
RegisterNetEvent('admincore:toggleDuty', function(dutyName)
    toggleAdminDuty(source, dutyName)
end)

-- =============================================
--   Admin List (net event từ client /admins)
-- =============================================
RegisterNetEvent('admincore:getAdminList', function()
    local src = source
    if AdminFunctions.GetLevel(src) < 1 then return end


    local list = {}
    for _, xPlayer in ipairs(ESX.GetExtendedPlayers()) do
        local pid = xPlayer.source
        local lvl = AdminFunctions.GetLevel(xPlayer)
        if lvl >= 1 then
            local rData = xPlayer and PlayerRankCache[xPlayer.identifier]
            list[#list + 1] = {
                id       = pid,
                name     = GetPlayerName(pid),
                level    = lvl,
                rankName = (rData and rData.name) or Config.DefaultLevelNames[lvl] or ('Level ' .. lvl),
                onDuty   = Player(pid).state.adminDutyName ~= nil,
            }
        end
    end

    TriggerClientEvent('admincore:adminList', src, list)
end)

-- =============================================
--   Action bridge từ NUI
-- =============================================
RegisterNetEvent('admincore:doAction', function(action, ...)
    local src  = source
    local args = { ... }

    local level = AdminFunctions.GetLevel(src)


    if action == 'goto' then
        if AdminFunctions.HasPermission(src, 'goto') then AdminFunctions.Goto(src, args[1]) end
    elseif action == 'gethere' then
        if AdminFunctions.HasPermission(src, 'gethere') then AdminFunctions.GetHere(src, args[1]) end
    elseif action == 'spectate' then
        if AdminFunctions.HasPermission(src, 'spectate') then
            TriggerClientEvent('admincore:startSpectate', src, args[1])
            AdminLogger.Log(src, 'spectate', args[1], nil)
        end
    elseif action == 'freeze' then
        if AdminFunctions.HasPermission(src, 'freeze') then AdminFunctions.Freeze(src, args[1]) end
    elseif action == 'revive' then
        if isAdvisor(src) then
            local targetId = getAdvisorReviveTarget(src, args[1])
            if targetId then AdminFunctions.Revive(src, targetId) end
        elseif AdminFunctions.HasPermission(src, 'revive') then
            AdminFunctions.Revive(src, args[1])
        end
    elseif action == 'checkinv' then
        if AdminFunctions.HasPermission(src, 'checkinv') then
            local targetId = tonumber(args[1])
            if targetId and exports.ox_inventory then
                exports.ox_inventory:forceOpenInventory(src, 'player', targetId)
                AdminLogger.Log(src, 'checkinv', targetId, 'Mo inventory nguoi choi')
            end
        end
    elseif action == 'kick' then
        if AdminFunctions.HasPermission(src, 'kick') then
            AdminFunctions.Kick(src, args[1], args[2])
        end
    elseif action == 'ban' then
        if level >= 4 and AdminFunctions.HasPermission(src, 'ban') then
            AdminFunctions.Ban(src, args[1], args[2])
        end
    elseif action == 'warn' then
        if AdminFunctions.HasPermission(src, 'warn') then AdminFunctions.Warn(src, args[1], args[2]) end
    elseif action == 'setlevel' then
        if AdminFunctions.HasPermission(src, 'setlevel') then
            local ok, msg = AdminFunctions.SetLevel(src, args[1], tonumber(args[2]) or 0)
            AdminFunctions.Notify(src, msg, ok and 'success' or 'error')
        end
    elseif action == 'setwatchdog' then
        if AdminFunctions.HasPermission(src, 'setlevel') or AdminFunctions.GetLevel(src) >= 4 then
            local ok, msg = AdminFunctions.SetWatchdog(src, args[1], args[2])
            AdminFunctions.Notify(src, msg, ok and 'success' or 'error')
        end
    elseif action == 'getinfo' then
        if AdminFunctions.HasPermission(src, 'getinfo') then AdminFunctions.GetInfo(src, args[1]) end
    elseif action == 'unban' then
        if level >= 4 and AdminFunctions.HasPermission(src, 'unban') then
            AdminFunctions.Unban(src, args[1], args[2])
        end
    elseif action == 'setprime' then
        if AdminFunctions.GetLevel(src) >= 4 then
            if exports['prime_status'] then
                local id = tonumber(args[1])
                local days = tonumber(args[2]) or 0
                if not id then
                    PrimeNotify(src, 'error', 'ID người chơi không hợp lệ.')
                    return
                end

                local ok = exports['prime_status']:SetPrime(id, days)
                if ok then
                    if days > 0 then
                        PrimeNotify(src, 'success', ('Đã cấp Prime cho ID %d thời hạn %d ngày.'):format(id, days))
                        PrimeNotify(id, 'success', ('Bạn đã được cấp Prime thời hạn %d ngày.'):format(days))
                    else
                        PrimeNotify(src, 'warning', ('Đã xóa Prime của ID %d.'):format(id))
                        PrimeNotify(id, 'warning', 'Prime của bạn đã hết hạn hoặc bị xóa.')
                    end
                    AdminLogger.Log(src, 'setprime', id, days > 0 and ('Cấp Prime %d ngày'):format(days) or 'Xóa Prime')
                else
                    PrimeNotify(src, 'error', 'Có lỗi khi thao tác Prime.')
                end
            else
            AdminFunctions.Notify(src, 'Resource prime_status không hoạt động.', 'error')
            end
        else
            AdminFunctions.Notify(src, 'Bạn không có quyền Set Prime.', 'error')
        end
    end
end)

-- =============================================
--   /sethunger [id] [0-100]  — lv_status
-- =============================================
RegisterCommand('sethunger', function(src, args)
    requireAdmin(src, 'sethunger', function()
        local id    = getTarget(src, args[1])
        local value = tonumber(args[2])

        if not id or not value then
            AdminFunctions.Notify(src, 'Cú pháp: /sethunger [id] [0-100]', 'error')
            return
        end

        if value < 0 or value > 100 then
            AdminFunctions.Notify(src, 'Giá trị đói phải từ 0 đến 100.', 'error')
            return
        end

        if GetResourceState('lv_status') ~= 'started' then
            AdminFunctions.Notify(src, 'Resource lv_status chưa khởi động.', 'error')
            return
        end

        exports['lv_status']:SetPlayerHunger(id, value)

        local adminName  = GetPlayerName(src) or ('Server [%d]'):format(src)
        local targetName = GetPlayerName(id)  or ('ID %d'):format(id)

        AdminFunctions.Notify(src,
            ('Đã set đói của %s (#%d) thành %d%%.'):format(targetName, id, value),
            'success')

        AdminFunctions.Notify(id,
            ('Admin đã set độ đói của bạn thành %d%%.'):format(value),
            'info')

        AdminLogger.Log(src, 'sethunger', id,
            ('Set đói → %d%%'):format(value))
    end)
end, false)

-- =============================================
--   /setthirst [id] [0-100]  — lv_status
-- =============================================
RegisterCommand('setthirst', function(src, args)
    requireAdmin(src, 'setthirst', function()
        local id    = getTarget(src, args[1])
        local value = tonumber(args[2])

        if not id or not value then
            AdminFunctions.Notify(src, 'Cú pháp: /setthirst [id] [0-100]', 'error')
            return
        end

        if value < 0 or value > 100 then
            AdminFunctions.Notify(src, 'Giá trị khát phải từ 0 đến 100.', 'error')
            return
        end

        if GetResourceState('lv_status') ~= 'started' then
            AdminFunctions.Notify(src, 'Resource lv_status chưa khởi động.', 'error')
            return
        end

        exports['lv_status']:SetPlayerThirst(id, value)

        local adminName  = GetPlayerName(src) or ('Server [%d]'):format(src)
        local targetName = GetPlayerName(id)  or ('ID %d'):format(id)

        AdminFunctions.Notify(src,
            ('Đã set khát của %s (#%d) thành %d%%.'):format(targetName, id, value),
            'success')

        AdminFunctions.Notify(id,
            ('Admin đã set độ khát của bạn thành %d%%.'):format(value),
            'info')

        AdminLogger.Log(src, 'setthirst', id,
            ('Set khát → %d%%'):format(value))
    end)
end, false)

-- =============================================
--   /carcolor – Chỉnh màu xe bằng oxlib color picker
-- =============================================
RegisterCommand('carcolor', function(src, args)
    requireAdmin(src, 'spawnveh', function()
        TriggerClientEvent('admincore:openColorPicker', src)
    end)
end, false)

RegisterCommand('adoiten', function(src, args)
    local level = AdminFunctions.GetLevel(src)
    if level < 5 then
        AdminFunctions.Notify(src, 'Bạn không có quyền thực hiện lệnh này (Yêu cầu Admin Level 5).', 'error')
        return
    end



    local id = getTarget(src, args[1])
    if not id then return end

    local ho = args[2]
    local ten = args[3]

    if not ho or not ten or ho == '' or ten == '' then
        AdminFunctions.Notify(src, 'Cú pháp: /adoiten [id] [họ] [tên]', 'error')
        return
    end

    local xTarget = ESX.GetPlayerFromId(id)
    if xTarget then
        xTarget.set("lastName", ten)
        xTarget.set("firstName", ho)
        xTarget.setName(ho .. " " .. ten)

        MySQL.update('UPDATE users SET firstname = ?, lastname = ? WHERE identifier = ?', {ho, ten, xTarget.identifier}, function(rowsChanged)
            if rowsChanged and rowsChanged > 0 then
                AdminFunctions.Notify(src, ('Đã đổi tên ID %d thành %s %s thành công.'):format(id, ho, ten), 'success')
                AdminFunctions.Notify(id, ('Tên của bạn đã được Admin đổi thành: %s %s.'):format(ho, ten), 'info')
                AdminLogger.Log(src, 'adoiten', id, ('Đổi tên thành: %s %s'):format(ho, ten))
            else
                AdminFunctions.Notify(src, 'Không thể cập nhật tên vào cơ sở dữ liệu.', 'error')
            end
        end)
    else
        AdminFunctions.Notify(src, 'Người chơi không online.', 'error')
    end
end, false)

RegisterCommand('afaceid', function(src, args)
    local level = AdminFunctions.GetLevel(src)
    if level < 5 then
        AdminFunctions.Notify(src, 'Bạn không có quyền thực hiện lệnh này (Yêu cầu Admin Level 5).', 'error')
        return
    end



    local id = getTarget(src, args[1])
    if not id then return end

    local xTarget = ESX.GetPlayerFromId(id)
    if xTarget then
        TriggerClientEvent('illenium-appearance:client:OpenSurgeonShop', id)
        AdminFunctions.Notify(src, ('Đã mở menu tạo mặt lại cho ID %d.'):format(id), 'success')
        AdminFunctions.Notify(id, 'Admin đã cho phép bạn tạo lại khuôn mặt của mình.', 'info')
        AdminLogger.Log(src, 'ataomat', id, 'Mở menu tạo lại khuôn mặt')
    else
        AdminFunctions.Notify(src, 'Người chơi không online.', 'error')
    end
end, false)

-- =============================================
--   /alogout [id]
-- =============================================
RegisterCommand('alogout', function(src, args)
    requireAdmin(src, 'logout', function()
        local id = getTarget(src, args[1])
        if not id then return end

        local xTarget = ESX.GetPlayerFromId(id)
        if xTarget then
            TriggerEvent('esx:playerLogout', id, function()
                TriggerClientEvent('op-multicharacter:completeLogout', id)
            end)
            AdminFunctions.Notify(src, ('Đã logout ID %d thành công.'):format(id), 'success')
            AdminLogger.Log(src, 'alogout', id, 'Cho người chơi về màn hình chọn nhân vật')
        else
            AdminFunctions.Notify(src, 'Người chơi không online.', 'error')
        end
    end)
end, false)

RegisterCommand('delloa', function(src, args)
    requireAdmin(src, 'deleteveh', function()
        TriggerClientEvent('lv_musicbox:client:adminPickup', src)
    end)
end, false)
