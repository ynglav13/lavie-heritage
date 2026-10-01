local ESX = exports['es_extended']:getSharedObject()

AdminLogger = {}

Config.Discord.webhook = ''
Config.ReportDiscord.webhook = ''

local discordQueue = {}
local reportDiscordQueue = {}

local ReportLogActions = {
    report = true,
    report_cancel = true,
    report_accept_admin = true,
    report_deny = true,
    report_push_advisor = true,
    report_finish_admin = true,
    advisor_help_accept = true,
    advisor_help_finish = true,
    advisorchat = true,
    cduty = true,
}

local ReportActionLabels = {
    report = 'Gửi report',
    report_cancel = 'Hủy report',
    report_accept_admin = 'Admin nhận report',
    report_deny = 'Từ chối report',
    report_push_advisor = 'Đẩy xuống Advisor',
    report_finish_admin = 'Admin kết thúc report',
    advisor_help_accept = 'Advisor nhận hỗ trợ',
    advisor_help_finish = 'Advisor kết thúc hỗ trợ',
    advisorchat = 'Advisor chat',
    cduty = 'Advisor duty',
}

local AdminActionLabels = {
    aduty = 'Admin duty',
    adminchat = 'Admin chat',
    ban = 'Ban',
    unban = 'Unban',
    kick = 'Kick',
    warn = 'Warn',
    checkinv = 'Check inventory',
    setlevel = 'Set level',
    setwatchdog = 'Set Watchdog',
    setprime = 'Set Prime',
    setprimeplus = 'Set Prime Plus',
    upgradeprimeplus = 'Upgrade Prime Plus',
    alogout = 'Force Logout',
}

local function truncate(value, maxLength)
    value = tostring(value or '')
    maxLength = maxLength or 900
    if #value <= maxLength then
        return value
    end

    return value:sub(1, maxLength - 3) .. '...'
end

local function getIdentifier(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if xPlayer and xPlayer.identifier then
        return xPlayer.identifier
    end

    return GetPlayerIdentifierByType(src, 'license') or GetPlayerIdentifierByType(src, 'steam') or 'unknown'
end

local function getPlayerLogInfo(src)
    if type(src) ~= 'number' then
        return {
            id = tostring(src or 'console'),
            name = 'console',
            serverId = nil,
        }
    end

    return {
        id = getIdentifier(src),
        name = GetPlayerName(src) or ('ID ' .. src),
        serverId = src,
    }
end

local function formatPlayer(info)
    if info.serverId then
        return ('%s\nID: `%s`\nIdentifier: `%s`'):format(info.name, info.serverId, info.id)
    end

    return ('%s\nIdentifier: `%s`'):format(info.name, info.id)
end

local function getActionLabel(action, isReportLog)
    if isReportLog then
        return ReportActionLabels[action] or action
    end

    return AdminActionLabels[action] or action
end

local function FlushQueue(queue, discordConfig)
    if not discordConfig or not discordConfig.enabled or discordConfig.webhook == '' or #queue == 0 then
        for i = #queue, 1, -1 do
            queue[i] = nil
        end
        return
    end

    local batch = {}
    for i, embed in ipairs(queue) do
        batch[i] = embed
    end
    for i = #queue, 1, -1 do
        queue[i] = nil
    end

    for _, embed in ipairs(batch) do
        PerformHttpRequest(discordConfig.webhook, function() end, 'POST',
            json.encode({
                username   = discordConfig.botName,
                avatar_url = discordConfig.avatar,
                embeds     = { embed },
            }),
            { ['Content-Type'] = 'application/json' }
        )
    end
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(Config.LogBatchInterval)
        FlushQueue(discordQueue, Config.Discord)
        FlushQueue(reportDiscordQueue, Config.ReportDiscord)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    FlushQueue(discordQueue, Config.Discord)
    FlushQueue(reportDiscordQueue, Config.ReportDiscord)
end)

-- =============================================
--   Log entry
-- =============================================
---@param adminSrc   number|string
---@param action     string
---@param targetSrc  number|nil
---@param details    string|nil
function AdminLogger.Log(adminSrc, action, targetSrc, details)
    local isReportLog = ReportLogActions[action] == true
    local actor = getPlayerLogInfo(adminSrc)
    local target = targetSrc and getPlayerLogInfo(targetSrc) or nil
    local discordConfig = isReportLog and Config.ReportDiscord or Config.Discord
    local queue = isReportLog and reportDiscordQueue or discordQueue

    if discordConfig and discordConfig.enabled and discordConfig.webhook ~= '' then
        local color  = discordConfig.colors[action] or discordConfig.colors.action or 10070709
        local actionLabel = getActionLabel(action, isReportLog)
        local fields = {
            { name = isReportLog and 'Người thao tác' or 'Admin', value = formatPlayer(actor), inline = true },
            { name = 'Hành động', value = actionLabel, inline = true },
        }
        if target then
            fields[#fields + 1] = { name = isReportLog and 'Người report / Target' or 'Target', value = formatPlayer(target), inline = true }
        end
        if details then
            fields[#fields + 1] = { name = 'Chi tiết', value = truncate(details), inline = false }
        end

        local title = (isReportLog and '[ReportCore] ' or '[AdminCore] ') .. actionLabel

        if GetResourceState('legacyWebhook') == 'started' then
            local invoked, accepted = pcall(function()
                return exports['legacyWebhook']:SendDiscordLog({
                    webhook = discordConfig.webhook,
                    title = title,
                    message = '',
                    color = color,
                    fields = fields,
                    username = discordConfig.botName,
                    avatar = discordConfig.avatar
                })
            end)

            if invoked then
                return
            end
        end

        queue[#queue + 1] = {
            title     = title,
            color     = color,
            fields    = fields,
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        }
    end
end
