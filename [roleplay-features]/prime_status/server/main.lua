local ESX = exports['es_extended']:getSharedObject()
local primeSchemaReady = false

local function SendChatMessage(target, message)
    if GetResourceState('custom-chat') == 'started' then
        TriggerClientEvent('custom-chat:addMessage', target, message)
        return
    end

    TriggerClientEvent('chat:addMessage', target, {
        color = {255, 215, 0},
        multiline = true,
        args = { message }
    })
end

local function Notify(source, data, notifyType, duration, title)
    if source == 0 then
        print(('[prime_status] %s'):format(type(data) == 'table' and (data.message or data.title or 'Notification') or tostring(data)))
        return
    end

    if GetResourceState('lv_notify') == 'started' then
        exports['lv_notify']:Notify(source, data, notifyType, duration, title)
        return
    end

    local message = type(data) == 'table' and (data.message or data.title or 'Notification') or tostring(data)
    print(('[prime_status] lv_notify is not started: %s'):format(message))
end

local function IsPrimeAdmin(xPlayer)
    if not xPlayer then
        return false
    end

    local src = xPlayer.source or xPlayer.playerId
    local aCoreState = GetResourceState('aCore')
    if src and (aCoreState == 'started' or aCoreState == 'starting') then
        local ok, level = pcall(function()
            return exports['aCore']:GetAdminLevel(src)
        end)
        if ok and type(level) == 'number' and (level >= 5 or level == 2 or level == 3) then
            return true
        end

        local rank = Player(src).state.AdminRank
        if type(rank) == 'number' and (rank >= 5 or rank == 2 or rank == 3) then
            return true
        end
    end

    return false
end

local function IsPrimeAdminState(source)
    local rank = Player(source).state.AdminRank
    return type(rank) == 'number' and (rank >= 5 or rank == 2 or rank == 3)
end

local function GetAcoreStaffRole(src)
    local aCoreState = GetResourceState('aCore')
    if not src or (aCoreState ~= 'started' and aCoreState ~= 'starting') then
        return nil
    end

    local ok, rankName = pcall(function()
        return exports['aCore']:GetPlayerRankName(src)
    end)

    if ok and rankName then
        return rankName
    end

    local levelOk, level = pcall(function()
        return exports['aCore']:GetAdminLevel(src)
    end)

    if levelOk and type(level) == 'number' and level >= 1 then
        return level == 1 and 'Advisor' or 'Admin'
    end

    local rank = Player(src).state.AdminRank
    if type(rank) == 'number' and rank >= 1 then
        return rank == 1 and 'Advisor' or 'Admin'
    end

    return nil
end

local DiscordSettings = {
    BotToken = "", -- Điền Discord Bot Token vào đây (tùy chọn: dùng để đồng bộ Prime Role Discord)
    GuildId = "",  -- Discord Server ID
    PrimeRole = "" -- Discord Role ID cho Prime VIP
}

local function GetDiscordId(source)
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if string.sub(id, 1, string.len("discord:")) == "discord:" then
            return string.sub(id, 9)
        end
    end
    return nil
end

local discordQueue = {}
local processingQueue = false

local function ProcessDiscordQueue()
    if processingQueue then return end
    if #discordQueue == 0 then return end

    processingQueue = true
    CreateThread(function()
        while #discordQueue > 0 do
            local nextReq = discordQueue[1]
            local url = nextReq.url
            local method = nextReq.method

            local completed = false
            local rateLimited = false

            PerformHttpRequest(url, function(err, text, headers)
                if err == 429 then
                    print('^3[prime_status]^7 Discord rate limited (429). Retrying in 5 seconds...')
                    rateLimited = true
                elseif err ~= 204 and err ~= 200 then
                    print('^3[prime_status]^7 Failed to ' .. nextReq.action .. ' Discord role for ' .. nextReq.discordId .. ' (Error: ' .. tostring(err) .. ')')
                    table.remove(discordQueue, 1)
                else
                    table.remove(discordQueue, 1)
                end
                completed = true
            end, method, '', {
                ['Authorization'] = 'Bot ' .. DiscordSettings.BotToken,
                ['Content-Type'] = 'application/json'
            })

            while not completed do
                Wait(50)
            end

            if rateLimited then
                Wait(5000)
            else
                Wait(1000)
            end
        end
        processingQueue = false
    end)
end

local function ManageDiscordRole(discordId, action)
    if DiscordSettings.BotToken == "" or DiscordSettings.GuildId == "" then return end
    if not discordId then return end

    local url = string.format("https://discord.com/api/v10/guilds/%s/members/%s/roles/%s", DiscordSettings.GuildId, discordId, DiscordSettings.PrimeRole)
    local method = action == 'add' and 'PUT' or 'DELETE'

    table.insert(discordQueue, {
        url = url,
        method = method,
        action = action,
        discordId = discordId
    })
    ProcessDiscordQueue()
end

MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `prime_accounts` (
            `steam_hex` VARCHAR(60) NOT NULL,
            `prime_expiry` DATETIME DEFAULT NULL,
            `prime_type` VARCHAR(20) NOT NULL DEFAULT 'prime',
            `created_at` TIMESTAMP DEFAULT current_timestamp(),
            `updated_at` TIMESTAMP DEFAULT current_timestamp() ON UPDATE current_timestamp(),
            PRIMARY KEY (`steam_hex`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function(result)
        if result then
            MySQL.query([[
                ALTER TABLE `prime_accounts`
                ADD COLUMN IF NOT EXISTS `prime_type` VARCHAR(20) NOT NULL DEFAULT 'prime'
                AFTER `prime_expiry`
            ]], {}, function()
                primeSchemaReady = true
                print('^2[prime_status]^7 Checked and ensured prime_accounts table exists.')
            end)
        end
    end)
end)

local function SyncPrimeStatus(source)
    if not primeSchemaReady then
        return false
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false end

    local steamHex = xPlayer.identifier
    if steamHex and string.find(steamHex, ":") then
        steamHex = string.match(steamHex, ":(.*)")
    end
    if not steamHex then return false end

    local isPrime = false
    local isPrimePlus = false
    local primeType = 'none'
    local result = MySQL.query.await(
        "SELECT IF(prime_expiry > NOW(), 1, 0) AS is_active, COALESCE(prime_type, 'prime') AS prime_type FROM prime_accounts WHERE steam_hex = ?",
        {steamHex}
    )

    if result and result[1] and result[1].is_active and result[1].is_active == 1 then
        isPrime = true
        primeType = result[1].prime_type == 'prime_plus' and 'prime_plus' or 'prime'
        isPrimePlus = primeType == 'prime_plus'
    end

    local wasPrime = Player(source).state.isPrime == true
    local hasSynced = Player(source).state.discordRoleSynced == true

    Player(source).state:set('isPrime', isPrime, true)
    Player(source).state:set('isPrimePlus', isPrimePlus, true)
    Player(source).state:set('primeType', primeType, true)

    local discordId = GetDiscordId(source)
    if discordId then
        if not hasSynced or wasPrime ~= isPrime then
            if isPrime then
                ManageDiscordRole(discordId, 'add')
            else
                ManageDiscordRole(discordId, 'remove')
            end
            Player(source).state:set('discordRoleSynced', true, true)
        end
    end

    return isPrime, isPrimePlus, primeType
end

CreateThread(function()
    while not primeSchemaReady do
        Wait(100)
    end

    local players = ESX.GetPlayers()
    for _, playerId in ipairs(players) do
        SyncPrimeStatus(playerId)
        Wait(100)
    end
end)

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    Player(playerId).state:set('primePcMuted', Player(playerId).state.primePcMuted == true, true)
    SyncPrimeStatus(playerId)
end)

CreateThread(function()
    while true do
        Wait(5 * 60 * 1000)
        local players = ESX.GetPlayers()
        for _, playerId in ipairs(players) do
            local state = Player(playerId).state
            if state.isPrime then
                SyncPrimeStatus(playerId)
                Wait(100)
            end
        end
    end
end)

exports('IsPlayerPrime', function(source)
    local state = Player(source).state
    if state and state.isPrime then
        return true
    end
    return false
end)

exports('IsPlayerPrimePlus', function(source)
    local state = Player(source).state
    return state and state.isPrimePlus == true or false
end)

local function SetPrimeTier(source, days, primeType)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, "Không tìm thấy người chơi" end

    days = tonumber(days) or 0
    primeType = primeType == 'prime_plus' and 'prime_plus' or 'prime'
    local steamHex = xPlayer.identifier
    if steamHex and string.find(steamHex, ":") then
        steamHex = string.match(steamHex, ":(.*)")
    end
    if not steamHex then return false, "Không lấy được Steam HEX" end

    while not primeSchemaReady do
        Wait(100)
    end

    if days > 0 then
        MySQL.query.await([[
            INSERT INTO prime_accounts (steam_hex, prime_expiry, prime_type)
            VALUES (?, DATE_ADD(NOW(), INTERVAL ? DAY), ?)
            ON DUPLICATE KEY UPDATE
            prime_type = IF(
                VALUES(prime_type) = 'prime_plus' OR (prime_type = 'prime_plus' AND prime_expiry > NOW()),
                'prime_plus',
                'prime'
            ),
            prime_expiry = IF(prime_expiry > NOW(), DATE_ADD(prime_expiry, INTERVAL ? DAY), DATE_ADD(NOW(), INTERVAL ? DAY))
        ]], {steamHex, days, primeType, days, days})
    else
        MySQL.query.await(
            "DELETE FROM prime_accounts WHERE steam_hex = ?",
            {steamHex}
        )
    end

    local isPrime = SyncPrimeStatus(source)
    return true, isPrime
end

exports('SetPrime', function(source, days)
    return SetPrimeTier(source, days, 'prime')
end)

exports('SetPrimePlus', function(source, days)
    return SetPrimeTier(source, days, 'prime_plus')
end)

exports('UpgradePrimeToPlus', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, "Không tìm thấy người chơi" end

    while not primeSchemaReady do
        Wait(100)
    end

    local steamHex = xPlayer.identifier
    if steamHex and string.find(steamHex, ":") then
        steamHex = string.match(steamHex, ":(.*)")
    end
    if not steamHex then return false, "Không lấy được Steam HEX" end

    local account = MySQL.single.await([[
        SELECT COALESCE(prime_type, 'prime') AS prime_type,
            UNIX_TIMESTAMP(prime_expiry) - UNIX_TIMESTAMP() AS seconds_left
        FROM prime_accounts
        WHERE steam_hex = ? AND prime_expiry > NOW()
    ]], {steamHex})

    if not account then
        return false, "Người chơi không có Prime đang hoạt động"
    end
    if account.prime_type == 'prime_plus' then
        return false, "Người chơi đã là Prime Plus"
    end

    MySQL.update.await(
        "UPDATE prime_accounts SET prime_type = 'prime_plus' WHERE steam_hex = ? AND prime_expiry > NOW()",
        {steamHex}
    )
    SyncPrimeStatus(source)

    return true, tonumber(account.seconds_left) or 0
end)

RegisterCommand('pc', function(source, args)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local isAdmin = IsPrimeAdmin(xPlayer)

    local state = Player(source).state
    local isPrime = state.isPrime == true

    if not isPrime and not isAdmin then
        Notify(source, {
            type = 'warning',
            title = 'Prime Chat',
            message = 'Bạn không có Prime Account.'
        })
        return
    end

    local msg = table.concat(args, ' ')
    if msg == '' then
        Notify(source, {
            type = 'info',
            title = 'Prime Chat',
            message = 'Vui lòng nhập tin nhắn.'
        })
        return
    end

    local name = xPlayer.getName() or GetPlayerName(source)
    local role = GetAcoreStaffRole(source)
    local displayName = role and (role .. ' ' .. name) or name

    local chatMessage = ('{7B68EE}(( [Prime Chat] %s: %s )){FFFFFF}'):format(displayName, msg)
    local players = GetPlayers()
    for i = 1, #players do
        local playerId = tonumber(players[i])
        local targetState = playerId and Player(playerId).state
        if targetState then
            local tIsPrime = targetState.isPrime == true
            local tIsAdmin = IsPrimeAdminState(playerId)
            local isMuted = targetState.primePcMuted == true

            if not isMuted and (tIsPrime or tIsAdmin) then
                SendChatMessage(playerId, chatMessage)
            end
        end
    end
end, false)

local function TogglePrimeChat(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        Notify(source, {
            type = 'error',
            title = 'Prime Chat',
            message = 'Không tìm thấy dữ liệu người chơi.'
        })
        return
    end

    local isAdmin = IsPrimeAdmin(xPlayer)
    local state = Player(source).state
    local isPrime = state.isPrime == true

    if not isPrime and not isAdmin then
        Notify(source, {
            type = 'warning',
            title = 'Prime Chat',
            message = 'Bạn không có quyền sử dụng kênh Prime Chat.'
        })
        return
    end

    local muted = state.primePcMuted == true
    state:set('primePcMuted', not muted, true)

    Notify(source, {
        type = muted and 'success' or 'info',
        title = 'Prime Chat',
        message = muted and 'Đã bật kênh Prime Chat.' or 'Đã tắt kênh Prime Chat.'
    })
end

RegisterCommand('tooglepc', function(source)
    TogglePrimeChat(source)
end, false)

RegisterCommand('togglepc', function(source)
    TogglePrimeChat(source)
end, false)

RegisterNetEvent('prime_status:togglePcChat', function()
    TogglePrimeChat(source)
end)

RegisterCommand('prime', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local steamHex = string.match(xPlayer.identifier, ":(.*)")
    local result = steamHex and MySQL.query.await(
        "SELECT prime_expiry, COALESCE(prime_type, 'prime') AS prime_type, UNIX_TIMESTAMP(prime_expiry) - UNIX_TIMESTAMP() as seconds_left FROM prime_accounts WHERE steam_hex = ?",
        {steamHex}
    ) or nil

    if result and result[1] and result[1].prime_expiry then
        local secondsLeft = tonumber(result[1].seconds_left) or 0
        local primeName = result[1].prime_type == 'prime_plus' and 'Prime Plus' or 'Prime'
        if secondsLeft > 0 then
            local d = math.floor(secondsLeft / 86400)
            local h = math.floor((secondsLeft % 86400) / 3600)
            local m = math.floor((secondsLeft % 3600) / 60)
            local s = secondsLeft % 60
            Notify(source, {
                type = 'info',
                title = primeName,
                message = ('Thời hạn %s còn lại: %d ngày / %d giờ / %d phút / %d giây.'):format(primeName, d, h, m, s),
                icon = 'VIP',
                accent = '#facc15',
                duration = 6500
            })
        else
            Notify(source, {
                type = 'warning',
                title = 'Prime',
                message = 'Prime của bạn đã hết hạn.'
            })
        end
    else
        Notify(source, {
            type = 'info',
            title = 'Prime',
            message = 'Bạn chưa từng được cấp Prime.'
        })
    end
end, false)

RegisterCommand('checkprime', function(source, args)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local adminLevel = 0
    if GetResourceState('aCore') == 'started' then
        local ok, level = pcall(function()
            return exports['aCore']:GetAdminLevel(source)
        end)
        if ok and type(level) == 'number' then
            adminLevel = level
        end
    end
    if adminLevel < 5 then
        Notify(source, {
            type = 'warning',
            title = 'Prime',
            message = 'Bạn không có quyền sử dụng lệnh này. (Yêu cầu Admin Level 5)'
        })
        return
    end

    local targetId = tonumber(args[1])
    if not targetId then
        Notify(source, {
            type = 'info',
            title = 'Prime',
            message = 'Vui lòng nhập ID người chơi.'
        })
        return
    end

    local tPlayer = ESX.GetPlayerFromId(targetId)
    if not tPlayer then
        Notify(source, {
            type = 'error',
            title = 'Prime',
            message = 'Người chơi không online.'
        })
        return
    end

    local tSteamHex = string.match(tPlayer.identifier, ":(.*)")
    local result = tSteamHex and MySQL.query.await(
        "SELECT prime_expiry, COALESCE(prime_type, 'prime') AS prime_type, UNIX_TIMESTAMP(prime_expiry) - UNIX_TIMESTAMP() as seconds_left FROM prime_accounts WHERE steam_hex = ?",
        {tSteamHex}
    ) or nil

    if result and result[1] and result[1].prime_expiry then
        local secondsLeft = tonumber(result[1].seconds_left) or 0
        local primeName = result[1].prime_type == 'prime_plus' and 'Prime Plus' or 'Prime'
        if secondsLeft > 0 then
            local d = math.floor(secondsLeft / 86400)
            local h = math.floor((secondsLeft % 86400) / 3600)
            local m = math.floor((secondsLeft % 3600) / 60)
            local s = secondsLeft % 60
            Notify(source, {
                type = 'info',
                title = primeName,
                message = ('Thời hạn %s của ID %s: %d ngày / %d giờ / %d phút / %d giây.'):format(primeName, targetId, d, h, m, s),
                icon = 'VIP',
                accent = '#facc15',
                duration = 6500
            })
        else
            Notify(source, {
                type = 'warning',
                title = 'Prime',
                message = 'Người chơi này đã hết hạn Prime.'
            })
        end
    else
        Notify(source, {
            type = 'info',
            title = 'Prime',
            message = 'Người chơi này chưa từng được cấp Prime.'
        })
    end
end, false)

-- HTTP Handler for Discord Bot Sync
local SYNC_TOKEN = "lslegacy_prime_sync_token_2026_xyz"

local function GetPlayerFromIdentifier(identifier)
    local players = ESX.GetPlayers()
    for _, playerId in ipairs(players) do
        local xPlayer = ESX.GetPlayerFromId(playerId)
        if xPlayer and xPlayer.identifier == identifier then
            return playerId
        end
    end
    return nil
end

SetHttpHandler(function(req, res)
    if req.path == '/sync' then
        req.setDataHandler(function(body)
            local success, data = pcall(json.decode, body)
            if not success or not data or data.token ~= SYNC_TOKEN then
                res.writeHead(403, {['Content-Type'] = 'application/json'})
                res.send(json.encode({error = "Unauthorized"}))
                return
            end

            local identifier = data.identifier
            if identifier then
                local source = GetPlayerFromIdentifier(identifier)
                if source then
                    local isPrime = SyncPrimeStatus(source)
                    res.writeHead(200, {['Content-Type'] = 'application/json'})
                    res.send(json.encode({success = true, message = "Synced online player", isPrime = isPrime}))
                else
                    res.writeHead(200, {['Content-Type'] = 'application/json'})
                    res.send(json.encode({success = true, message = "Player is offline, database updated"}))
                end
            else
                res.writeHead(400, {['Content-Type'] = 'application/json'})
                res.send(json.encode({error = "Missing identifier"}))
            end
        end)
    else
        res.writeHead(404)
        res.send("Not Found")
    end
end)
