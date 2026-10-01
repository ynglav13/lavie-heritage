Config = {}

-- Owner theo character identifier (char_id), ví dụ: char1:licensexxxxxxxx...
Config.Owners = {
    -- 'discord:929158298798805022',
}

Config.DefaultLevelNames = {
    [0] = 'Player',
    [1] = 'Advisor',
    [2] = 'Level 2',
    [3] = 'Level 3',
    [4] = 'Level 4',
    [5] = 'Level 5',
}

Config.AdminTagColors = {
    [1] = '#3498db',
    [2] = '#2ecc71',
    [3] = '#e67e22',
    [4] = '#e74c3c',
    [5] = '#ff1744',
}

Config.MaxAdminLevel = 5

Config.ExternalAdminAceMinLevel = 4

Config.Advisor = {
    minLevel = 1,
    level = 1,
    reportAdminMinLevel = 2,
    reportAutoPushSeconds = 300,
    tag = 'Advisor',
    color = '#38bdf8',
    cooldowns = {
        report = 30,
        chat = 3,
        action = 2,
        duty = 5,
        cancel = 10,
    },
}

Config.Watchdog = {
    tag = 'Watchdog',
    color = '#94a3b8',
}

-- =============================================
--   DISCORD LOGGING
-- =============================================
Config.Discord = {
    enabled     = true,
    webhook     = '',
    botName     = 'Admin Core',
    avatar      = '',
    colors = {
        ban     = 16711680,
        unban   = 65280,
        kick    = 16753920,
        warn    = 16776960,
        setlevel = 3447003,
        action  = 10070709,
    },
}

Config.ReportDiscord = {
    enabled     = true,
    webhook     = '',
    botName     = 'Report Core',
    avatar      = '',
    colors = {
        report                 = 3447003,
        report_cancel          = 10070709,
        report_accept_admin    = 3447003,
        report_deny            = 16711680,
        report_push_advisor    = 16776960,
        report_finish_admin    = 65280,
        advisor_help_accept    = 3447003,
        advisor_help_finish    = 65280,
        advisorchat            = 39167,
        cduty                  = 39167,
        action                 = 10070709,
    },
}

-- =============================================
--   AUTO-BAN KHI ĐẠT GIỚI HẠN WARN
-- =============================================
Config.AutoBan = {
    enabled     = true,
    warnLimit   = 3,
    banDuration = 1440,
    reason      = 'Đạt giới hạn cảnh cáo tối đa (%d lần)',
}

-- =============================================
--   ADMIN PANEL & UI
-- =============================================
Config.PanelKey      = 57        -- F3 (FiveM key code)
Config.DutyColor     = { r = 255, g = 165, b = 0, a = 200 }

Config.LogBatchInterval = 30000

Config.DefaultBanDuration  = 0
Config.DefaultJailDuration = 10
