local DutyWebhooks = {
    ['lspd'] = GetConvar('faction_duty_webhook_lspd', ''),
    ['lsmc'] = GetConvar('faction_duty_webhook_lsmc', ''),
    ['mechanic'] = '',
    ['cardealer'] = '',
    ['lssd'] = '',
}

local defaultWebhook = GetConvar('faction_duty_webhook_default', '')

local lastDutyState = {}
local dutyStartTimes = {}

local function FormatTime(seconds)
    if not seconds or seconds < 0 then return "0 giây" end
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    local timeStr = ""
    if hours > 0 then timeStr = timeStr .. hours .. " giờ " end
    if mins > 0 then timeStr = timeStr .. mins .. " phút " end
    timeStr = timeStr .. secs .. " giây"
    return timeStr
end

local function SendDutyWebhook(tag, src, dutyState, dutyDuration)
    local webhook = DutyWebhooks[tag:lower()]
    if not webhook or webhook == '' then
        webhook = defaultWebhook
    end

    if not webhook or webhook == '' then return end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local state = Player(src).state
    local name = (state and state.playerName) or xPlayer.getName()
    local identifier = xPlayer.identifier

    local statusStr = dutyState and "**ON DUTY**" or "**OFF DUTY**"
    local color = dutyState and 3066993 or 15158332

    local fields = {
        {
            ["name"] = "Nhân viên",
            ["value"] = string.format("%s (ID: %s)", name, src),
            ["inline"] = true
        },
        {
            ["name"] = "Identifier",
            ["value"] = identifier,
            ["inline"] = true
        },
        {
            ["name"] = "Trạng thái",
            ["value"] = statusStr,
            ["inline"] = false
        }
    }

    if dutyDuration then
        table.insert(fields, {
            ["name"] = "Thời gian onduty",
            ["value"] = dutyDuration,
            ["inline"] = false
        })
    end

    local embed = {
        {
            ["title"] = "Duty Log - " .. string.upper(tag),
            ["color"] = color,
            ["fields"] = fields,
            ["footer"] = {
                ["text"] = "Los Santos Legacy",
            },
            ["timestamp"] = os.date('!%Y-%m-%dT%H:%M:%SZ')
        }
    }

    PerformHttpRequest(webhook, function(err, text, headers) end, 'POST', json.encode({username = "Duty Logger", embeds = embed}), { ['Content-Type'] = 'application/json' })
end

AddStateBagChangeHandler('factionDuty', nil, function(bagName, key, value, _reserved, replicated)
    if not bagName then return end
    local src = tonumber(bagName:gsub('player:', ''), 10)
    if not src then return end

    if lastDutyState[src] == value then return end
    lastDutyState[src] = value

    local state = Player(src).state
    if not state then return end

    local tag = state.factionTag
    if not tag then return end

    local dutyDuration = nil
    if value == true then
        dutyStartTimes[src] = os.time()
    else
        if dutyStartTimes[src] then
            local durationSecs = os.time() - dutyStartTimes[src]
            dutyDuration = FormatTime(durationSecs)
            dutyStartTimes[src] = nil
        end
    end

    SendDutyWebhook(tag, src, value, dutyDuration)
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    if lastDutyState[src] then
        lastDutyState[src] = nil
    end
    if dutyStartTimes[src] then
        dutyStartTimes[src] = nil
    end
end)
