local ESX = exports['es_extended']:getSharedObject()
local Queue = {}

-- Helper to extract identifiers
local function GetIdentifiers(source)
    local identifiers = {
        steam = nil,
        licenseFull = nil,
        discord = nil
    }
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if string.sub(id, 1, 6) == "steam:" then
            identifiers.steam = id
        elseif string.sub(id, 1, 8) == "license:" then
            identifiers.licenseFull = id
        elseif string.sub(id, 1, 8) == "discord:" then
            identifiers.discord = id
        end
    end
    return identifiers
end

-- Get priority from database
local function GetPriority(licenseFull, steamIdentifier)
    if not licenseFull then
        return Config.Points.Normal
    end

    local priority = Config.Points.Normal

    pcall(function()
        local adminLevel = nil
        if steamIdentifier then
            local rawSteam = string.sub(steamIdentifier, 7)
            adminLevel = MySQL.scalar.await('SELECT level FROM admin_levels WHERE identifier = ? OR identifier LIKE ? OR identifier = ? OR identifier LIKE ?', {
                rawSteam,
                'char%:' .. rawSteam,
                licenseFull,
                'char%:' .. licenseFull
            })
        else
            adminLevel = MySQL.scalar.await('SELECT level FROM admin_levels WHERE identifier = ? OR identifier LIKE ?', {
                licenseFull,
                'char%:' .. licenseFull
            })
        end

        if adminLevel and tonumber(adminLevel) > 0 then
            priority = Config.Points.Admin
            return
        end

        if steamIdentifier then
            local rawSteam = string.sub(steamIdentifier, 7)
            local queryResult = MySQL.scalar.await('SELECT IF(prime_expiry > NOW(), 1, 0) as is_active FROM prime_accounts WHERE steam_hex = ?', {
                rawSteam
            })
            if queryResult and tonumber(queryResult) == 1 then
                priority = Config.Points.Prime
            end
        end
    end)

    return priority
end

-- Sort queue helper
local function SortQueue()
    table.sort(Queue, function(a, b)
        if a.priority == b.priority then
            return a.timeAdded < b.timeAdded
        end
        return a.priority > b.priority
    end)
end

-- Main playerConnecting handler
AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local src = source
    deferrals.defer()

    Wait(50)

    local identifiers = GetIdentifiers(src)
    print(string.format("[ConnectionQueue] Player '%s' connecting. Steam: %s, Discord: %s", name, tostring(identifiers.steam), tostring(identifiers.discord)))

    if not identifiers.steam then
        deferrals.done(Config.Messages.NoSteam)
        return
    end

    local licenseFull = identifiers.licenseFull
    if not licenseFull then
        deferrals.done("Không tìm thấy License Rockstar. Vui lòng thử kết nối lại.")
        return
    end

    local priority = GetPriority(licenseFull, identifiers.steam)

    local convarVal = tostring(GetConvar('queue_maintenance', '0')):match("^%s*(.-)%s*$")
    local isMaintenance = Config.MaintenanceMode == true or GetConvarInt('queue_maintenance', 0) == 1 or convarVal == '1' or convarVal == 'true'

    local isAdmin = priority >= Config.Points.Admin
    if isMaintenance and Config.AdminBypassMaintenance and isAdmin then
        print(string.format("[ConnectionQueue] Admin '%s' bypassed maintenance mode.", name))
        isMaintenance = false
    end

    if isMaintenance and Config.MaintenanceBypassRole and Config.MaintenanceBypassRole ~= "" then
        local roleList = nil
        local apiError = false
        if GetResourceState('discordapi') == 'started' then
            local ok, result = pcall(function() return exports['discordapi']:GetDiscordRoles(src) end)
            if ok then 
                roleList = result 
            else
                apiError = true
            end
        end
        if not roleList and GetResourceState('Badger_Discord_API') == 'started' then
            local ok, result = pcall(function() return exports['Badger_Discord_API']:GetDiscordRoles(src) end)
            if ok then 
                roleList = result 
            else
                apiError = true
            end
        end
        
        if roleList then
            if type(roleList) == "table" then
                for _, roleId in pairs(roleList) do
                    if tostring(roleId) == tostring(Config.MaintenanceBypassRole) then
                        print(string.format("[ConnectionQueue] Player '%s' bypassed maintenance mode (Discord Role).", name))
                        isMaintenance = false
                        break
                    end
                end
            end
        elseif roleList == false then
            print(string.format("[ConnectionQueue] Unable to fetch Discord roles for player '%s' (User might not be in the Discord server).", name))
        else
            print("[ConnectionQueue] Warning: Discord API is not started or failed to execute, unable to verify Discord roles.")
        end
    end

    -- Post maintenance validation function
    local function ProceedToJoin()
        -- Discord Whitelist Check
        if Config.CheckDiscordWhitelist then
            deferrals.update(Config.Messages.CheckingWhitelist)

            if not identifiers.discord then
                deferrals.done(Config.Messages.NoDiscord)
                return
            end

            local rawSteam = string.sub(identifiers.steam, 7)
            local rawDiscordId = string.sub(identifiers.discord, 9)
            local isWhitelisted = false
            local isDiscordMatching = false

            local ok, result = pcall(function()
                return MySQL.query.await('SELECT * FROM discord_whitelist WHERE steam_hex = ? OR steam_hex = ?', { identifiers.steam, rawSteam })
            end)

            if ok and result and #result > 0 then
                isWhitelisted = true
                if tostring(result[1].discord_id) == tostring(rawDiscordId) then
                    isDiscordMatching = true
                end
            end

            if not isWhitelisted then
                deferrals.done(string.format(Config.Messages.NotWhitelisted, identifiers.steam))
                return
            end

            if not isDiscordMatching then
                deferrals.done(Config.Messages.DiscordNotMatching)
                return
            end
        end

        -- Check queue
        if not Config.EnableQueue then
            deferrals.done()
            return
        end

        local maxClients = GetConvarInt('sv_maxclients', 32)
        local currentClients = #GetPlayers()

        if currentClients < maxClients and #Queue == 0 then
            deferrals.done()
            return
        end

        table.insert(Queue, {
            src = src,
            name = name,
            steam = identifiers.steam,
            licenseFull = licenseFull,
            priority = priority,
            timeAdded = os.time(),
            deferrals = deferrals
        })

        SortQueue()
    end

    -- Maintenance Mode Active: Present Card
    if isMaintenance then
        print(string.format("[ConnectionQueue] Maintenance mode active for player '%s'", name))
        deferrals.update("MÁY CHỦ ĐANG BẢO TRÌ\n\nVui lòng nhập mật khẩu bảo trì để kết nối:")

        local cardPayload = {
            ["$schema"] = "http://adaptivecards.io/schemas/adaptive-card.json",
            type = "AdaptiveCard",
            version = "1.0",
            body = {
                {
                    type = "TextBlock",
                    text = Config.Messages.MaintenanceTitle,
                    weight = "Bolder",
                    size = "Large"
                },
                {
                    type = "TextBlock",
                    text = Config.Messages.MaintenanceDesc,
                    wrap = true
                },
                {
                    type = "Input.Text",
                    id = "maintenance_password",
                    placeholder = Config.Messages.MaintenancePlaceholder
                }
            },
            actions = {
                {
                    type = "Action.Submit",
                    title = Config.Messages.MaintenanceSubmitBtn
                }
            }
        }

        local cardSubmitted = false
        local passCorrect = false
        local kickReason = nil

        deferrals.presentCard(json.encode(cardPayload), function(data, rawData)
            print(string.format("[ConnectionQueue] Maintenance submit from '%s'. Raw: %s", name, tostring(rawData)))

            local inputPass = ""
            if type(data) == "table" and data.maintenance_password then
                inputPass = tostring(data.maintenance_password)
            elseif type(rawData) == "string" and rawData ~= "" then
                local ok, decoded = pcall(json.decode, rawData)
                if ok and type(decoded) == "table" and decoded.maintenance_password then
                    inputPass = tostring(decoded.maintenance_password)
                end
            end

            inputPass = inputPass:match("^%s*(.-)%s*$")
            if inputPass == "" then
                return
            end

            local rawConvarPass = GetConvar('queue_maintenance_password', '')
            local expectedPass = (rawConvarPass ~= '' and rawConvarPass or Config.MaintenancePassword):match("^%s*(.-)%s*$")

            print(string.format("[ConnectionQueue] Pass check '%s' vs '%s'", inputPass, expectedPass))

            cardSubmitted = true

            if inputPass == expectedPass then
                passCorrect = true
                deferrals.update("Mật khẩu chính xác! Đang kết nối...")
            else
                passCorrect = false
                kickReason = Config.Messages.MaintenanceIncorrectPass
            end
        end)

        local waitCount = 0
        while not cardSubmitted do
            Wait(100)
            waitCount = waitCount + 1
            if waitCount > 1200 then
                deferrals.done(Config.Messages.MaintenanceCanceled)
                return
            end
        end

        if not passCorrect then
            deferrals.done(kickReason or Config.Messages.MaintenanceIncorrectPass)
            return
        end

        ProceedToJoin()
    else
        ProceedToJoin()
    end
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    for i, p in ipairs(Queue) do
        if p.src == src then
            table.remove(Queue, i)
            break
        end
    end
end)

-- Queue Processing Loop
CreateThread(function()
    while true do
        Wait(1000)

        if Config.EnableQueue and #Queue > 0 then
            local maxClients = GetConvarInt('sv_maxclients', 32)
            local currentClients = #GetPlayers()

            for i, p in ipairs(Queue) do
                p.deferrals.update(string.format(Config.Messages.QueueMessage, i, #Queue))
            end

            if currentClients < maxClients then
                local firstPlayer = Queue[1]
                local allowed = false
                local reservedSlots = Config.ReservedSlots or 4
                local publicSlots = math.max(0, maxClients - reservedSlots)

                if currentClients < publicSlots then
                    allowed = true
                elseif firstPlayer.priority >= Config.Points.Prime then
                    allowed = true
                end

                if allowed then
                    table.remove(Queue, 1)
                    firstPlayer.deferrals.done()
                end
            end
        end
    end
end)
