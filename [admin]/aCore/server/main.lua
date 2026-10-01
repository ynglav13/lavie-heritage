local ESX = exports['es_extended']:getSharedObject()

AdminCache      = {}  -- { [identifier] = level }
FrozenPlayers   = {}  -- { [playerId] = true }
JailCache       = {}  -- { [identifier] = { expire_at } }
PlayerRankCache = {}  -- { [identifier] = { name, color } }
RankNameCache   = {}  -- { [level] = { name, color } }
WatchdogCache   = {}  -- { [identifier] = true }

local function IsAdminDutyAllowed(src)
    return AdminFunctions.IsAdminDutyAllowed(src)
end

local function RequireAdminDuty(src)
    return AdminFunctions.RequireAdminDuty(src)
end

-- Load admin list + mutes + rank names
local function LoadAllCaches(syncJails)
    local admins = MySQL.query.await('SELECT identifier, level, rank_name, rank_color FROM admin_levels WHERE level > 0 OR rank_name IS NOT NULL')
    AdminCache = {}
    PlayerRankCache = {}
    WatchdogCache = {}
    if admins then
        for _, row in ipairs(admins) do
            if row.level and row.level > 0 then
                AdminCache[row.identifier] = row.level
            end
            if row.rank_name then
                PlayerRankCache[row.identifier] = { name = row.rank_name, color = row.rank_color }
                if row.rank_name:lower() == 'watchdog' then
                    WatchdogCache[row.identifier] = true
                end
            end
        end
    end

    print(('[AdminCore] Cache: %d admin(s)'):format(
        #(admins or {})
    ))

    local now = os.time()
    local jails = MySQL.query.await('SELECT identifier, expire_at, release_coords FROM admin_jails')
    JailCache = {}
    if jails then
        for _, row in ipairs(jails) do
            local expireAt = tonumber(row.expire_at) or 0
            local xPlayer = ESX.GetPlayerFromIdentifier(row.identifier)
            if expireAt > now then
                JailCache[row.identifier] = { expire_at = expireAt, release_coords = row.release_coords }
                if syncJails and xPlayer then
                    TriggerClientEvent('admincore:jail', xPlayer.source, math.ceil((expireAt - now) / 60), 'Tiếp tục chấp hành án phạt cũ')
                end
            else
                MySQL.query.await('DELETE FROM admin_jails WHERE identifier = ?', { row.identifier })
                if xPlayer then
                    local coords = row.release_coords and json.decode(row.release_coords) or nil
                    TriggerClientEvent('admincore:unjail', xPlayer.source, coords)
                end
            end
        end
    end
    local activeJails = 0
    for _ in pairs(JailCache) do activeJails = activeJails + 1 end
    print(('[AdminCore] Cache: %d active jail(s)'):format(activeJails))

    if ESX and AdminFunctions and AdminFunctions.SyncPermissions then
        for _, xPlayer in ipairs(ESX.GetExtendedPlayers()) do
            local src = xPlayer.source
            local level = AdminFunctions.GetLevel(src)
            local isWatchdog = AdminFunctions.IsWatchdog(src)
            AdminFunctions.SyncPermissions(src, level)
            AdminFunctions.SetAdminStateBag(src, level)
            Player(src).state:set('isWatchdog', isWatchdog, true)
            TriggerClientEvent('admincore:setLevel', src, level)
            TriggerClientEvent('admincore:setWatchdog', src, isWatchdog)
        end
    end

    TriggerClientEvent('admincore:syncRankNames', -1, RankNameCache)
end

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(1000)
        LoadAllCaches(true)
    end)
end)

-- Refresh cache (sau khi thay đổi level / rank name)
RegisterNetEvent('admincore:refreshCache', function()
    LoadAllCaches(false)
end)

-- Lấy rank name để gửi cho client khi join (bỏ qua global rank)
RegisterNetEvent('admincore:requestRankNames', function()
    -- Gửi cache trống hoặc thay đổi logic ở client, do bây giờ tên theo user
    TriggerClientEvent('admincore:syncRankNames', source, {})
end)

-- Set Rank Name (lưu DB)
RegisterNetEvent('admincore:setRankName', function(targetId, name, color)
    if not RequireAdminDuty(source) then return end

    AdminFunctions.SetRankName(source, targetId, name, color)
end)

-- Sync Permissions khi Player Join
AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    local src = playerId
    local level = AdminFunctions.GetLevel(src)
    local isWatchdog = AdminFunctions.IsWatchdog(src)
    AdminFunctions.SetAdminStateBag(src, level)
    Player(src).state:set('isWatchdog', isWatchdog, true)
    TriggerClientEvent('admincore:setLevel', src, level)
    TriggerClientEvent('admincore:setWatchdog', src, isWatchdog)
    if level > 0 then
        AdminFunctions.SyncPermissions(src, level)
    end

    local jailData = JailCache[xPlayer.identifier]
    if jailData then
        local now = os.time()
        local expireAt = tonumber(jailData.expire_at) or 0
        if now < expireAt then
            local duration = math.ceil((expireAt - now) / 60)
            TriggerClientEvent('admincore:jail', src, duration, "Chấp hành nốt án phạt cũ")
        else
            AdminFunctions.Unjail(nil, src)
        end
    end
end)

AddEventHandler('playerDropped', function()
    FrozenPlayers[source] = nil
end)

local lastPlayersListRequest = {}
local PLAYERS_LIST_REQUEST_COOLDOWN = 1500
local playersListCache = {}
local playersListCacheAt = 0
local PLAYERS_LIST_CACHE_DURATION = 1000

local function buildPlayersList()
    local now = GetGameTimer()
    if now - playersListCacheAt < PLAYERS_LIST_CACHE_DURATION then
        return playersListCache
    end

    local players = {}
    for _, xPlayer in ipairs(ESX.GetExtendedPlayers()) do
        local pid = xPlayer.source
        local pLevel = AdminFunctions.GetLevel(xPlayer)
        local isWatchdog = AdminFunctions.IsWatchdog(xPlayer)
        local rData = PlayerRankCache[xPlayer.identifier]
        local adminName = (rData and rData.name) or (isWatchdog and (Config.Watchdog and Config.Watchdog.tag or 'Watchdog')) or Config.DefaultLevelNames[pLevel] or 'Player'
        local adminColor = (rData and rData.color) or (isWatchdog and (Config.Watchdog and Config.Watchdog.color or '#94a3b8')) or Config.AdminTagColors[pLevel] or '#ffffff'
        players[#players + 1] = {
            id = pid,
            name = GetPlayerName(pid),
            identifier = xPlayer.identifier,
            ping = GetPlayerPing(pid),
            job = xPlayer.job and xPlayer.job.name or 'unemployed',
            adminLevel = pLevel,
            isWatchdog = isWatchdog,
            adminName = adminName,
            adminColor = adminColor,
        }
    end

    playersListCache = players
    playersListCacheAt = now
    return playersListCache
end

RegisterNetEvent('admincore:getPlayers', function()
    local src = source
    if AdminFunctions.GetLevel(src) < 1 then return end
    if not RequireAdminDuty(src) then return end

    local now = GetGameTimer()
    if now - (lastPlayersListRequest[src] or 0) < PLAYERS_LIST_REQUEST_COOLDOWN then
        return
    end
    lastPlayersListRequest[src] = now

    TriggerClientEvent('admincore:updatePlayers', src, buildPlayersList())
end)

AddEventHandler('playerDropped', function()
    lastPlayersListRequest[source] = nil
end)

-- NUI: Danh sach ban (phan trang)
RegisterNetEvent('admincore:getBans', function(page)
    local src = source
    if AdminFunctions.GetLevel(src) < 2 then return end
    if not RequireAdminDuty(src) then return end

    page = math.max(1, tonumber(page) or 1)
    local offset = (page - 1) * 20

    local bans  = MySQL.query.await('SELECT id, name, reason, banned_by_name, ban_duration, expire_at, active, created_at FROM admin_bans ORDER BY created_at DESC LIMIT 20 OFFSET ?', { offset })
    local total = MySQL.scalar.await('SELECT COUNT(*) FROM admin_bans') or 0
    TriggerClientEvent('admincore:updateBans', src, bans or {}, total, page)
end)

-- Exports
exports('GetAdminLevel', function(src) return AdminFunctions.GetLevel(src) end)
exports('IsAdmin',       function(src) return AdminFunctions.GetLevel(src) >= 1 end)
exports('IsAdvisor',     function(src) return AdminFunctions.GetLevel(src) == (Config.Advisor.level or 1) end)
exports('IsWatchdog',    function(src) return AdminFunctions.IsWatchdog(src) end)
exports('SetWatchdog',   function(src, targetId, status) return AdminFunctions.SetWatchdog(src, targetId, status) end)
exports('HasPermission', function(src, action) return AdminFunctions.HasPermission(src, action) end)
exports('IsAdminDutyAllowed', function(src) return AdminFunctions.IsAdminDutyAllowed(src) end)
exports('GetRankName',   function(level)
    return Config.DefaultLevelNames[level] or ('Level ' .. level)
end)
exports('GetPlayerRankName', function(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    local level = AdminFunctions.GetLevel(src)
    if xPlayer and PlayerRankCache[xPlayer.identifier] then
        return PlayerRankCache[xPlayer.identifier].name
    end
    if AdminFunctions.IsWatchdog(src) then
        return (Config.Watchdog and Config.Watchdog.tag) or 'Watchdog'
    end
    return Config.DefaultLevelNames[level] or ('Level ' .. level)
end)

ESX.RegisterServerCallback('admincore:canUseAdminCommands', function(src, cb)
    cb(AdminFunctions.GetLevel(src) >= 1 and IsAdminDutyAllowed(src))
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(15000)
        if next(JailCache) then
            local now = os.time()
            for identifier, jailData in pairs(JailCache) do
                if now >= (tonumber(jailData.expire_at) or 0) then
                    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
                    if xPlayer then
                        AdminFunctions.Unjail(nil, xPlayer.source)
                    end
                end
            end
        end
    end
end)

-- NUI: Quan ly giftcode
RegisterNetEvent('admincore:getGiftcodes', function()
    local src = source
    if not AdminFunctions.HasPermission(src, 'managegiftcodes') then return end
    if not RequireAdminDuty(src) then return end

    local giftcodes = MySQL.query.await('SELECT id, code, reward, amount, reward_type, max_redeem, current_redeem, UNIX_TIMESTAMP(expire_at) AS expire_at FROM pg_giftcodes ORDER BY id DESC')
    if giftcodes then
        for i=1, #giftcodes do
            if giftcodes[i].expire_at then
                giftcodes[i].expire_at = giftcodes[i].expire_at * 1000
            end
        end
    end
    TriggerClientEvent('admincore:updateGiftcodes', src, giftcodes or {})
end)

RegisterNetEvent('admincore:deleteGiftcode', function(code)
    local src = source
    if not AdminFunctions.HasPermission(src, 'managegiftcodes') then return end
    if not RequireAdminDuty(src) then return end

    if not code then return end

    local rowsChanged = MySQL.update.await('DELETE FROM pg_giftcodes WHERE code = ?', { code })
    if rowsChanged > 0 then
        MySQL.update.await('DELETE FROM pg_user_giftcodes WHERE code = ?', { code })
        AdminFunctions.Notify(src, 'Đã xóa giftcode thành công.', 'success')
        -- Get updated list
        local giftcodes = MySQL.query.await('SELECT id, code, reward, amount, reward_type, max_redeem, current_redeem, UNIX_TIMESTAMP(expire_at) AS expire_at FROM pg_giftcodes ORDER BY id DESC')
        if giftcodes then
            for i=1, #giftcodes do
                if giftcodes[i].expire_at then
                    giftcodes[i].expire_at = giftcodes[i].expire_at * 1000
                end
            end
        end
        TriggerClientEvent('admincore:updateGiftcodes', src, giftcodes or {})
    else
        AdminFunctions.Notify(src, 'Không thể xóa giftcode hoặc giftcode không tồn tại.', 'error')
    end
end)

-- Ban Check on Player Connecting
AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local src = source
    deferrals.defer()
    Citizen.Wait(0)
    deferrals.update(('Xin chào %s. Đang kiểm tra trạng thái cấm...'):format(name))

    local identifier = nil
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id and string.sub(id, 1, 8) == 'license:' then
            identifier = id
            break
        end
    end

    if identifier then
        local ban = MySQL.single.await([[
            SELECT id, reason, expire_at, 
                   (expire_at IS NOT NULL AND expire_at <= NOW()) AS is_expired 
            FROM admin_bans 
            WHERE identifier = ? AND active = 1 
            ORDER BY id DESC LIMIT 1
        ]], { identifier })

        if ban then
            if ban.is_expired == 1 then
                MySQL.update.await('UPDATE admin_bans SET active = 0 WHERE id = ?', { ban.id })
            else
                local banMsg = ('[AdminCore] Bạn đang bị cấm khỏi máy chủ (Ban ID: #%s).\nLý do: %s'):format(ban.id, ban.reason)
                deferrals.done(banMsg)
                return
            end
        end
    end
    deferrals.done()
end)
