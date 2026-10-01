local ESX = exports['es_extended']:getSharedObject()

AdminFunctions = {}

function AdminFunctions.GetCharacterInfo(xPlayer)
    if not xPlayer then
        return { charid = '?', icName = 'Không rõ', steamName = 'Không rõ', steamIdentifier = '?' }
    end

    local source = xPlayer.source
    local identifier = xPlayer.identifier or ''
    local row
    local ok, result = pcall(MySQL.single.await, 'SELECT identifier, firstname, lastname FROM users WHERE identifier = ?', { identifier })

    if ok then
        row = result
    end

    local charid = (row and row.identifier) or identifier
    local firstName = (row and row.firstname) or (xPlayer.get and xPlayer.get('firstName'))
    local lastName = (row and row.lastname) or (xPlayer.get and xPlayer.get('lastName'))
    local icName = ((firstName or '') .. ' ' .. (lastName or '')):gsub('^%s*(.-)%s*$', '%1')

    if icName == '' and xPlayer.getName then
        icName = xPlayer.getName()
    end

    if not icName or icName == '' then
        icName = 'Không rõ'
    end

    return {
        charid = charid,
        icName = icName,
        steamName = (source and GetPlayerName(source)) or 'Không rõ',
        steamIdentifier = (source and GetPlayerIdentifierByType(source, 'steam')) or '?',
    }
end

-- =============================================
--   IsOwner: Kiểm tra xem src có phải là Owner không
-- =============================================
---@param src number|table
---@return boolean
function AdminFunctions.IsOwner(src)
    if not src then return false end
    if src == 0 then return true end

    local xPlayer
    local playerId
    if type(src) == 'table' then
        xPlayer = src
        playerId = xPlayer.source
    else
        playerId = tonumber(src)
        xPlayer = ESX.GetPlayerFromId(playerId)
    end

    if not xPlayer then return false end

    local identifier = xPlayer.identifier
    for i = 1, #Config.Owners do
        if identifier == Config.Owners[i] then return true end
    end

    if playerId then
        for _, id in ipairs(GetPlayerIdentifiers(playerId)) do
            for i = 1, #Config.Owners do
                if id == Config.Owners[i] then return true end
            end
        end
    end

    return false
end

-- =============================================
--   GetLevel: Lấy admin level của player (theo src)
-- =============================================
---@param src number|table  player server ID or xPlayer table
---@return number
function AdminFunctions.GetLevel(src)
    if not src then return 0 end
    if src == 0 then return Config.MaxAdminLevel end

    local xPlayer
    if type(src) == 'table' then
        xPlayer = src
    else
        xPlayer = ESX.GetPlayerFromId(tonumber(src))
    end

    if not xPlayer then return 0 end

    if AdminFunctions.IsOwner(xPlayer) then return Config.MaxAdminLevel end

    return AdminCache[xPlayer.identifier] or 0
end

-- =============================================
--   SetAdminStateBag: Đồng bộ AdminRank xuống client statebag
-- =============================================
---@param targetSrc number
---@param level number
function AdminFunctions.SetAdminStateBag(targetSrc, level)
    -- Replicate = true → client có thể đọc qua LocalPlayer.state.AdminRank
    Player(targetSrc).state:set('AdminRank', level, true)
end

-- =============================================
--   SyncPermissions: Đồng bộ với ESX Group & FiveM ACE
-- =============================================
function AdminFunctions.SyncPermissions(targetSrc, level)
    local xTarget = ESX.GetPlayerFromId(targetSrc)
    local shouldGrantExternalAdmin = level >= (Config.ExternalAdminAceMinLevel or Config.MaxAdminLevel)
    local license
    for _, id in ipairs(GetPlayerIdentifiers(targetSrc)) do
        if id:match('^license:') then
            license = id
            break
        end
    end

    -- print(('[AdminCore] Syncing Permissions for Src: %s | Level: %s | HasXTarget: %s | License: %s'):format(targetSrc, level, xTarget ~= nil, license))

    if not shouldGrantExternalAdmin then
        if license then ExecuteCommand('remove_principal identifier.' .. license .. ' group.admin') end
        if xTarget then
            xTarget.setGroup('user')
            print(('[AdminCore] Set Group USER for %s'):format(GetPlayerName(targetSrc)))
        end
    else
        if license then ExecuteCommand('add_principal identifier.' .. license .. ' group.admin') end
        if xTarget then
            local esxGroup = 'admin'
            if level >= 5 then
                esxGroup = 'superadmin'
            end
            xTarget.setGroup(esxGroup)
            -- print(('[AdminCore] Set Group %s for %s'):format(esxGroup:upper(), GetPlayerName(targetSrc)))
        end
    end
end

-- =============================================
--   GetLevelByIdentifier: Dùng khi không có src
-- =============================================
---@param identifier string
---@return number
function AdminFunctions.GetLevelByIdentifier(identifier)
    return AdminCache[identifier] or 0
end

-- =============================================
--   IsWatchdog: Kiểm tra xem src có role Watchdog không
-- =============================================
---@param src number|table  player server ID or xPlayer table
---@return boolean
function AdminFunctions.IsWatchdog(src)
    if not src then return false end
    if src == 0 then return false end

    local xPlayer
    if type(src) == 'table' then
        xPlayer = src
    else
        xPlayer = ESX.GetPlayerFromId(tonumber(src))
    end

    if not xPlayer then return false end

    local identifier = xPlayer.identifier
    if not identifier then return false end

    if WatchdogCache and WatchdogCache[identifier] then
        return true
    end

    local rData = PlayerRankCache and PlayerRankCache[identifier]
    if rData and rData.name and rData.name:lower() == 'watchdog' then
        return true
    end

    return false
end

-- =============================================
--   HasPermission
-- =============================================
---@param src number
---@param action string
---@return boolean
function AdminFunctions.HasPermission(src, action)
    if AdminFunctions.IsWatchdog(src) then return false end
    local lvl = AdminFunctions.GetLevel(src)
    return Permissions.Has(lvl, action)
end

-- =============================================
--   IsAdminDutyAllowed & RequireAdminDuty
--   Admin level <= 4 phải On Duty mới dùng được lệnh admin
-- =============================================
---@param src number|table
---@return boolean
function AdminFunctions.IsAdminDutyAllowed(src)
    if not src or src == 0 then return true end
    if AdminFunctions.IsWatchdog(src) then return false end
    if AdminFunctions.IsOwner(src) then return true end

    local level = AdminFunctions.GetLevel(src)
    if level > 4 then return true end

    if level >= 1 and level <= 4 then
        local xPlayer = type(src) == 'table' and src or ESX.GetPlayerFromId(tonumber(src))
        if not xPlayer then return false end
        local pid = xPlayer.source
        if level == 1 then
            return Player(pid).state.adminDutyName ~= nil or Player(pid).state.advisorDutyName ~= nil
        end
        return Player(pid).state.adminDutyName ~= nil
    end

    return false
end

---@param src number|table
---@return boolean
function AdminFunctions.RequireAdminDuty(src)
    if AdminFunctions.IsWatchdog(src) then
        AdminFunctions.Notify(src, 'Role Watchdog không có quyền thực hiện hành động này.', 'error')
        return false
    end

    if AdminFunctions.IsAdminDutyAllowed(src) then return true end

    local level = AdminFunctions.GetLevel(src)
    if level >= 1 and level <= 4 then
        AdminFunctions.Notify(src, 'Bạn phải On Duty (/aduty) mới có thể sử dụng lệnh admin.', 'error')
    else
        AdminFunctions.Notify(src, 'Bạn không có quyền thực hiện hành động này.', 'error')
    end
    return false
end


-- =============================================
--   SetLevel: Đặt level admin
-- =============================================
---@param src number       Admin thực hiện
---@param targetSrc number Target player
---@param level number     Level mới (0-6, không được đặt 7 qua command)
---@return boolean, string
function AdminFunctions.SetLevel(src, targetSrc, level)
    local adminLevel  = AdminFunctions.GetLevel(src)
    local targetLevel = AdminFunctions.GetLevel(targetSrc)
    level = tonumber(level) or 0

    if level < 0 or level > Config.MaxAdminLevel then
        return false, ('Level phải từ 0 đến %d.'):format(Config.MaxAdminLevel)
    end

    if AdminFunctions.IsOwner(targetSrc) and src ~= 0 and src ~= targetSrc then
        return false, 'Bạn không thể thay đổi level của Owner.'
    end

    local isOwner = AdminFunctions.IsOwner(src)
    if not isOwner then
        if level >= adminLevel then
            return false, 'Bạn không thể đặt level bằng hoặc cao hơn level của mình.'
        end
        if targetLevel >= adminLevel then
            return false, 'Bạn không thể thay đổi level của người có level bằng hoặc cao hơn bạn.'
        end
    end

    local xTarget = ESX.GetPlayerFromId(targetSrc)
    if not xTarget then return false, 'Không tìm thấy người chơi.' end

    local identifier = xTarget.identifier
    local name       = GetPlayerName(targetSrc)
    local xAdmin     = ESX.GetPlayerFromId(src)
    local adminId    = xAdmin and xAdmin.identifier or 'console'

    if level <= 0 then
        MySQL.query.await('DELETE FROM admin_levels WHERE identifier = ?', { identifier })
        AdminCache[identifier] = nil
        PlayerRankCache[identifier] = nil
        if WatchdogCache then WatchdogCache[identifier] = nil end
        Player(targetSrc).state:set('isWatchdog', false, true)
        TriggerClientEvent('admincore:setWatchdog', targetSrc, false)
    else
        MySQL.query.await(
            'INSERT INTO admin_levels (identifier, level, name, added_by) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE level = ?, name = ?, added_by = ?',
            { identifier, level, name, adminId, level, name, adminId }
        )
        AdminCache[identifier] = level
        if WatchdogCache then WatchdogCache[identifier] = nil end
        Player(targetSrc).state:set('isWatchdog', false, true)
        TriggerClientEvent('admincore:setWatchdog', targetSrc, false)
    end
    AdminFunctions.SetAdminStateBag(targetSrc, level)
    AdminFunctions.SyncPermissions(targetSrc, level)
    TriggerClientEvent('admincore:setLevel', targetSrc, level)

    local rankData  = PlayerRankCache[identifier]
    local rankLabel = (rankData and rankData.name) or Config.DefaultLevelNames[level] or 'Player'
    AdminFunctions.Notify(targetSrc, ('Cấp bậc của bạn đã được đặt thành: %s'):format(rankLabel), 'info')
    AdminLogger.Log(src, 'setlevel', targetSrc, ('Level: %d -> %d (%s)'):format(targetLevel, level, rankLabel))
    TriggerEvent('admincore:refreshCache')
    return true, 'Đã đặt level thành công.'
end


---@param src number
---@param msg string
---@param msgType string 'success'|'error'|'info'|'warning'
function AdminFunctions.Notify(src, msg, msgType)
    if src ~= 0 and GetResourceState('lv_notify') == 'started' then
        exports['lv_notify']:Notify(src, {
            type = msgType or 'info',
            title = 'AdminCore',
            message = msg,
            duration = 4500
        })
        return
    end

    TriggerClientEvent('admincore:notify', src, msg, msgType or 'info')
end


---@param src number  admin
---@param targetSrc number
function AdminFunctions.GetInfo(src, targetSrc)
    local xTarget = ESX.GetPlayerFromId(targetSrc)
    if not xTarget then
        AdminFunctions.Notify(src, 'Không tìm thấy người chơi.', 'error')
        return
    end

    local identifier = xTarget.identifier
    local warnCount  = MySQL.scalar.await('SELECT COUNT(*) FROM admin_warns WHERE identifier = ?', { identifier }) or 0
    local banCount   = MySQL.scalar.await('SELECT COUNT(*) FROM admin_bans WHERE identifier = ?', { identifier }) or 0
    local adminLevel = AdminFunctions.GetLevelByIdentifier(identifier)
    local coords     = GetEntityCoords(GetPlayerPed(targetSrc))

    local bankAcc = xTarget.getAccount and xTarget.getAccount('bank')
    local info = {
        id         = targetSrc,
        name       = GetPlayerName(targetSrc),
        identifier = identifier,
        job        = xTarget.job and xTarget.job.label or 'N/A',
        jobGrade   = xTarget.job and xTarget.job.grade_label or 'N/A',
        money      = xTarget.getMoney and xTarget.getMoney() or 0,
        bank       = bankAcc and bankAcc.money or 0,
        warns      = warnCount,
        bans       = banCount,
        adminLevel = adminLevel,
        adminName  = (PlayerRankCache[identifier] and PlayerRankCache[identifier].name) or Config.DefaultLevelNames[adminLevel] or 'Player',
        adminColor = (PlayerRankCache[identifier] and PlayerRankCache[identifier].color) or Config.AdminTagColors[adminLevel] or '#ffffff',
        coords     = { x = math.floor(coords.x), y = math.floor(coords.y), z = math.floor(coords.z) },
        ping       = GetPlayerPing(targetSrc),
    }

    TriggerClientEvent('admincore:showInfo', src, info)
    AdminLogger.Log(src, 'getinfo', targetSrc, 'Xem thông tin người chơi')
end

-- =============================================
--   Teleport: Goto / GetHere
-- =============================================
function AdminFunctions.Goto(src, targetSrc)
    local coords = GetEntityCoords(GetPlayerPed(targetSrc))
    TriggerClientEvent('admincore:teleport', src, coords.x, coords.y, coords.z + 1.0)
    AdminLogger.Log(src, 'goto', targetSrc, nil)
end

function AdminFunctions.GotoCoords(src, coords)
    TriggerClientEvent('admincore:teleport', src, coords.x, coords.y, coords.z, coords.heading)
    AdminLogger.Log(src, 'goto', nil, ('Teleport tới tọa độ: %.4f, %.4f, %.4f%s'):format(
        coords.x,
        coords.y,
        coords.z,
        coords.heading and (', heading %.4f'):format(coords.heading) or ''
    ))
end

function AdminFunctions.GetHere(src, targetSrc)
    local coords = GetEntityCoords(GetPlayerPed(src))
    TriggerClientEvent('admincore:teleport', targetSrc, coords.x, coords.y, coords.z + 1.0)
    AdminFunctions.Notify(targetSrc, 'Admin đã teleport bạn đến vị trí của họ.', 'warning')
    AdminLogger.Log(src, 'gethere', targetSrc, nil)
end

-- =============================================
--   Freeze / Unfreeze
-- =============================================
function AdminFunctions.Freeze(src, targetSrc)
    if FrozenPlayers[targetSrc] then
        FrozenPlayers[targetSrc] = nil
        TriggerClientEvent('admincore:setFrozen', targetSrc, false)
        AdminFunctions.Notify(targetSrc, 'Bạn đã được bỏ đóng băng.', 'info')
        AdminFunctions.Notify(src, ('Đã bỏ đóng băng: %s'):format(GetPlayerName(targetSrc)), 'success')
        AdminLogger.Log(src, 'unfreeze', targetSrc, nil)
    else
        FrozenPlayers[targetSrc] = true
        TriggerClientEvent('admincore:setFrozen', targetSrc, true)
        AdminFunctions.Notify(targetSrc, 'Bạn đã bị đóng băng bởi admin.', 'error')
        AdminFunctions.Notify(src, ('Đã đóng băng: %s'):format(GetPlayerName(targetSrc)), 'success')
        AdminLogger.Log(src, 'freeze', targetSrc, nil)
    end
end

-- =============================================
--   Revive
-- =============================================
function AdminFunctions.Revive(src, targetSrc)
    targetSrc = tonumber(targetSrc)
    local xTarget = targetSrc and ESX.GetPlayerFromId(targetSrc) or nil

    if not xTarget then
        AdminFunctions.Notify(src, 'Không tìm thấy người chơi cần hồi sinh.', 'error')
        return false, 'invalid_player'
    end

    if GetResourceState('lavie_injury') == 'started' then
        local readyInvoked, injuryReady, injuryReadyError = pcall(function()
            return exports.lavie_injury:IsPlayerReady(targetSrc)
        end)

        if not readyInvoked or injuryReady ~= true then
            AdminFunctions.Notify(src, ('Dữ liệu thương tích của người chơi chưa sẵn sàng (%s).'):format(tostring(injuryReadyError or 'readiness_check_failed')), 'error')
            return false, injuryReadyError or 'injury_not_ready'
        end

        local invoked, revived, reviveError = pcall(function()
            return exports.lavie_injury:RevivePlayer(targetSrc,
            {
                mode = 'revive',
                reason = 'admin_revive',
                health = 200,
                clearBodyDamage = true,
                allowHealthy = true,
            })
        end)

        if not invoked or revived ~= true then
            AdminFunctions.Notify(src, ('Không thể hồi sinh người chơi lúc này (%s).'):format(tostring(reviveError or revived or 'recovery_failed')), 'error')
            return false, reviveError or 'recovery_failed'
        end
    else
        TriggerClientEvent('admincore:revive', targetSrc)
    end

    AdminFunctions.Notify(targetSrc, 'Bạn đã được hồi sinh bởi admin.', 'success')
    AdminLogger.Log(src, 'revive', targetSrc, nil)

    if GetResourceState('lv_status') == 'started' then
        local hungerOk = pcall(function()
            exports['lv_status']:SetPlayerHunger(targetSrc, 100)
        end)
        local thirstOk = pcall(function()
            exports['lv_status']:SetPlayerThirst(targetSrc, 100)
        end)
        local stressOk = pcall(function()
            exports['lv_status']:SetPlayerStress(targetSrc, 0)
        end)

        if not hungerOk or not thirstOk or not stressOk then
            print(('[AdminCore] Revive status reset was incomplete for player %s'):format(targetSrc))
        end
    end

    return true
end

-- =============================================
--   Kick
-- =============================================
function AdminFunctions.Kick(src, targetSrc, reason)
    local adminName = GetPlayerName(src)
    reason = reason or 'Không có lý do'

    TriggerClientEvent('admincore:notify', targetSrc, ('Bạn đã bị kick bởi %s.\nLý do: %s'):format(adminName, reason), 'error')

    Citizen.SetTimeout(1000, function()
        DropPlayer(targetSrc, ('[AdminCore] Bạn đã bị kick.\nLý do: %s'):format(reason))
    end)

    AdminFunctions.Notify(src, ('Đã kick: %s - %s'):format(GetPlayerName(targetSrc), reason), 'success')
    AdminLogger.Log(src, 'kick', targetSrc, ('Lý do: %s'):format(reason))
end

-- =============================================
--   Ban
-- =============================================
function AdminFunctions.Ban(src, targetSrc, reason, duration)
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not GetPlayerName(targetSrc) then
        AdminFunctions.Notify(src, 'Người chơi không tồn tại.', 'error')
        return false
    end

    local xTarget    = ESX.GetPlayerFromId(targetSrc)
    local xAdmin     = src ~= 0 and ESX.GetPlayerFromId(src) or nil
    local adminId    = xAdmin and xAdmin.identifier or 'console'
    local adminName  = src ~= 0 and GetPlayerName(src) or 'Console'
    local targetName = GetPlayerName(targetSrc)
    local identifier = xTarget and xTarget.identifier

    if not identifier then
        for i = 0, GetNumPlayerIdentifiers(targetSrc) - 1 do
            local id = GetPlayerIdentifier(targetSrc, i)
            if id and string.sub(id, 1, 8) == 'license:' then
                identifier = id
                break
            end
        end
    end
    identifier = identifier or ('license:' .. tostring(targetSrc))
    reason = reason or 'Bị cấm bởi Admin'

    local expireAt = nil
    if duration and tonumber(duration) and tonumber(duration) > 0 then
        duration = tonumber(duration)
        expireAt = os.date('!%Y-%m-%d %H:%M:%S', os.time() + (duration * 60))
    end

    MySQL.query.await([[
        INSERT INTO admin_bans (identifier, name, reason, banned_by, banned_by_name, ban_duration, expire_at, active)
        VALUES (?, ?, ?, ?, ?, ?, ?, 1)
    ]], { identifier, targetName, reason, adminId, adminName, duration, expireAt })

    Citizen.SetTimeout(500, function()
        DropPlayer(targetSrc, ('[AdminCore] Bạn đã bị cấm khỏi máy chủ.\nLý do: %s'):format(reason))
    end)

    AdminFunctions.Notify(src, ('Đã ban %s.'):format(targetName), 'success')
    AdminLogger.Log(src, 'ban', targetSrc, ('Lý do: %s'):format(reason))
    return true
end

-- =============================================
--   Unban
-- =============================================
function AdminFunctions.Unban(src, banId, reason)
    local xAdmin = src ~= 0 and ESX.GetPlayerFromId(src) or nil
    local adminId = xAdmin and xAdmin.identifier or 'console'

    if not banId or banId == '' then
        AdminFunctions.Notify(src, 'Ban ID hoặc Identifier không hợp lệ.', 'error')
        return false
    end

    local rowsChanged = MySQL.update.await('UPDATE admin_bans SET active = 0, unbanned_by = ? WHERE (id = ? OR identifier = ?) AND active = 1', { adminId, banId, banId })
    if rowsChanged and rowsChanged > 0 then
        AdminFunctions.Notify(src, ('Đã unban thành công cho %s.'):format(banId), 'success')
        AdminLogger.Log(src, 'unban', nil, ('Ban ID: %s | Lý do: %s'):format(banId, reason or 'Không có lý do'))
        return true
    else
        AdminFunctions.Notify(src, 'Không tìm thấy Ban ID hoặc đã được unban trước đó.', 'error')
        return false
    end
end

-- Backward compatibility aliases
AdminFunctions.RavenBan   = AdminFunctions.Ban
AdminFunctions.RavenKick  = AdminFunctions.Kick
AdminFunctions.RavenUnban = AdminFunctions.Unban

-- =============================================
--   Warn
-- =============================================
function AdminFunctions.Warn(src, targetSrc, reason)
    local xTarget    = ESX.GetPlayerFromId(targetSrc)
    local xAdmin     = ESX.GetPlayerFromId(src)
    if not xTarget then return end

    local identifier = xTarget.identifier
    local adminId    = xAdmin and xAdmin.identifier or 'console'
    local adminName  = GetPlayerName(src)

    MySQL.query.await(
        'INSERT INTO admin_warns (identifier, name, reason, warned_by, warned_by_name) VALUES (?, ?, ?, ?, ?)',
        { identifier, GetPlayerName(targetSrc), reason, adminId, adminName }
    )

    TriggerClientEvent('admincore:notify', targetSrc,
        ('⚠ Bạn đã nhận cảnh cáo từ %s.\nLý do: %s'):format(adminName, reason), 'warning')
    AdminFunctions.Notify(src, ('Đã cảnh cáo: %s'):format(GetPlayerName(targetSrc)), 'success')
    AdminLogger.Log(src, 'warn', targetSrc, ('Lý do: %s'):format(reason))

    local warnMsg = ("{FF0000}Admin %s đã cảnh cáo %s. Lý do: %s"):format(adminName, GetPlayerName(targetSrc), reason or "")
    TriggerClientEvent('custom-chat:addMessage', -1, warnMsg)

    if Config.AutoBan.enabled then
        local warnCount = MySQL.scalar.await('SELECT COUNT(*) FROM admin_warns WHERE identifier = ?', { identifier }) or 0
        if warnCount >= Config.AutoBan.warnLimit then
            AdminFunctions.Ban(
                0,
                targetSrc,
                Config.AutoBan.reason:format(warnCount),
                Config.AutoBan.banDuration
            )
        end
    end
end


-- =============================================
--   SetJob
-- =============================================
function AdminFunctions.SetJob(src, targetSrc, job, grade)
    local xTarget = ESX.GetPlayerFromId(targetSrc)
    if not xTarget then
        AdminFunctions.Notify(src, 'Không tìm thấy người chơi.', 'error')
        return
    end
    xTarget.setJob(job, grade or 0)
    AdminFunctions.Notify(targetSrc, ('Job của bạn đã được đổi thành: %s (grade %d)'):format(job, grade or 0), 'info')
    AdminFunctions.Notify(src, 'Đã đổi job thành công.', 'success')
    AdminLogger.Log(src, 'setjob', targetSrc, ('Job: %s | Grade: %d'):format(job, grade or 0))
end

-- =============================================
--   SetMoney
-- =============================================
function AdminFunctions.SetMoney(src, targetSrc, accountType, amount)
    local xTarget = ESX.GetPlayerFromId(targetSrc)
    if not xTarget then
        AdminFunctions.Notify(src, 'Không tìm thấy người chơi.', 'error')
        return
    end

    if accountType == 'cash' then
        xTarget.setMoney(amount)
    elseif accountType == 'bank' then
        xTarget.setAccountMoney('bank', amount)
    else
        AdminFunctions.Notify(src, 'Loại tiền không hợp lệ (cash/bank).', 'error')
        return
    end

    AdminFunctions.Notify(targetSrc, ('Số tiền %s của bạn đã được đặt thành: $%s'):format(accountType, amount), 'info')
    AdminFunctions.Notify(src, 'Đã đặt tiền thành công.', 'success')
    AdminLogger.Log(src, 'setmoney', targetSrc, ('%s = %d'):format(accountType, amount))
end

-- =============================================
--   GiveItem
-- =============================================
function AdminFunctions.GiveItem(src, targetSrc, item, amount)
    local xTarget = ESX.GetPlayerFromId(targetSrc)
    if not xTarget then
        AdminFunctions.Notify(src, 'Không tìm thấy người chơi.', 'error')
        return
    end
    xTarget.addInventoryItem(item, amount)
    AdminFunctions.Notify(targetSrc, ('Bạn đã nhận được %dx %s từ admin.'):format(amount, item), 'info')
    AdminFunctions.Notify(src, 'Đã cho item thành công.', 'success')
    AdminLogger.Log(src, 'giveitem', targetSrc, ('%dx %s'):format(amount, item))
end

-- =============================================
--   Jail / Unjail
-- =============================================
function AdminFunctions.Jail(src, targetSrc, duration, reason)
    local expireAt = os.time() + (duration or Config.DefaultJailDuration) * 60
    local xTarget  = ESX.GetPlayerFromId(targetSrc)
    if not xTarget then return end

    local jailerIdentifier = "System"
    local adminName = "Hệ thống"
    if src and src > 0 then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then jailerIdentifier = xPlayer.identifier end
        adminName = GetPlayerName(src)
    end

    local targetPed = GetPlayerPed(targetSrc)
    local targetCoords = GetEntityCoords(targetPed)
    local targetHeading = GetEntityHeading(targetPed)
    local coordsJson = json.encode({x = targetCoords.x, y = targetCoords.y, z = targetCoords.z, h = targetHeading})

    JailCache[xTarget.identifier] = { expire_at = expireAt, release_coords = coordsJson }
    
    MySQL.query.await('INSERT INTO admin_jails (identifier, reason, jailer, expire_at, release_coords) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE reason = ?, jailer = ?, expire_at = ?, release_coords = ?', {
        xTarget.identifier, reason or '', jailerIdentifier, expireAt, coordsJson,
        reason or '', jailerIdentifier, expireAt, coordsJson
    })

    TriggerClientEvent('admincore:jail', targetSrc, duration, reason)
    if src and src > 0 then
        AdminFunctions.Notify(src, ('Đã nhốt: %s (%d phút)'):format(GetPlayerName(targetSrc), duration), 'success')
    end
    AdminLogger.Log(src, 'jail', targetSrc, ('%d phút | %s'):format(duration, reason or ''))

    local msg = ("{FF0000} Admin %s đã phạt tù %s %d phút. Lý do: %s"):format(adminName, GetPlayerName(targetSrc), duration, reason or "")
    TriggerClientEvent('custom-chat:addMessage', -1, msg)
end

function AdminFunctions.Unjail(src, targetSrc)
    local xTarget = ESX.GetPlayerFromId(targetSrc)
    if not xTarget then return end

    local coords = nil
    local jailData = JailCache[xTarget.identifier]
    if jailData and jailData.release_coords then
        print("DEBUG UNJAIL RAW COORDS:", jailData.release_coords)
        coords = json.decode(jailData.release_coords)
        print("DEBUG UNJAIL DECODED:", json.encode(coords))
    else
        print("DEBUG UNJAIL NO COORDS FOUND")
    end

    JailCache[xTarget.identifier] = nil

    MySQL.query('DELETE FROM admin_jails WHERE identifier = ?', { xTarget.identifier })

    TriggerClientEvent('admincore:unjail', targetSrc, coords)
    AdminFunctions.Notify(targetSrc, 'Bạn đã được thả tự do.', 'success')
    if src and src > 0 then
        AdminFunctions.Notify(src, 'Đã thả tù thành công.', 'success')
    end
    AdminLogger.Log(src, 'unjail', targetSrc, nil)
end

-- =============================================
--   Announce
-- =============================================
function AdminFunctions.Announce(src, message)
    local adminName = GetPlayerName(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    local rankName = nil
    if xPlayer then
        local rData = PlayerRankCache[xPlayer.identifier]
        if rData and rData.name then
            rankName = rData.name
        else
            local level = AdminFunctions.GetLevel(src)
            rankName = Config.DefaultLevelNames[level] or ('Level ' .. level)
        end
    end
    local formattedName = rankName and ('%s %s'):format(rankName, adminName) or adminName
    TriggerClientEvent('admincore:announce', -1, message, formattedName)
    AdminLogger.Log(src, 'announce', nil, message)
end

-- =============================================
--   ClearWarns
-- =============================================
function AdminFunctions.ClearWarns(src, targetSrc)
    local xTarget = ESX.GetPlayerFromId(targetSrc)
    if not xTarget then return end
    MySQL.query.await('DELETE FROM admin_warns WHERE identifier = ?', { xTarget.identifier })
    AdminFunctions.Notify(src, ('Đã xóa tất cả cảnh cáo của: %s'):format(GetPlayerName(targetSrc)), 'success')
    AdminFunctions.Notify(targetSrc, 'Tất cả cảnh cáo của bạn đã được xóa.', 'info')
    AdminLogger.Log(src, 'clearwarns', targetSrc, nil)
end

-- =============================================
--   SpawnVehicle (server-side trigger)
-- =============================================
function AdminFunctions.SpawnVehicle(src, model)
    TriggerClientEvent('admincore:spawnVehicle', src, model)
    AdminLogger.Log(src, 'spawnveh', nil, ('Model: %s'):format(model))
end

-- =============================================
--   DeleteVehicle
-- =============================================
function AdminFunctions.DeleteVehicle(src, targetSrc)
    TriggerClientEvent('admincore:deleteVehicle', targetSrc or src)
    AdminLogger.Log(src, 'deleteveh', targetSrc, nil)
end

-- =============================================
--   FixVehicle
-- =============================================
function AdminFunctions.FixVehicle(src, targetSrc)
    TriggerClientEvent('admincore:fixVehicle', targetSrc)

    if src ~= targetSrc then
        AdminFunctions.Notify(src, ('Đã sửa xe cho: %s'):format(GetPlayerName(targetSrc)), 'success')
    end
    
    AdminLogger.Log(src, 'fixveh', targetSrc, nil)
end

-- =============================================
--   FixVehicleByPlate
-- =============================================
function AdminFunctions.FixVehicleByPlate(src, plate)
    local normalizedPlate = tostring(plate or ''):upper():gsub('%s+', '')
    if normalizedPlate == '' then
        AdminFunctions.Notify(src, 'Biển số xe không hợp lệ.', 'error')
        return
    end

    for _, vehicle in ipairs(GetAllVehicles()) do
        local vehiclePlate = GetVehicleNumberPlateText(vehicle)
        if vehiclePlate and vehiclePlate:upper():gsub('%s+', '') == normalizedPlate then
            local owner = NetworkGetEntityOwner(vehicle)
            if not owner or owner <= 0 then
                AdminFunctions.Notify(src, 'Xe này chưa có chủ mạng để thực hiện sửa chữa.', 'error')
                return
            end

            TriggerClientEvent('admincore:fixVehicleByNetId', owner, NetworkGetNetworkIdFromEntity(vehicle), normalizedPlate)
            AdminFunctions.Notify(src, ('Đã gửi yêu cầu sửa xe biển số: %s'):format(plate), 'success')
            AdminLogger.Log(src, 'fixveh', owner, ('Plate: %s'):format(plate))
            return
        end
    end

    AdminFunctions.Notify(src, ('Không tìm thấy xe đang tồn tại có biển số: %s'):format(plate), 'error')
end

-- =============================================
--   SetRankName: Dat ten rank cho level
-- =============================================
function AdminFunctions.SetRankName(src, targetSrc, name, color)
    if not AdminFunctions.HasPermission(src, 'setrankname') then
        AdminFunctions.Notify(src, 'Bạn không có quyền thực hiện lệnh này.', 'error')
        return
    end

    local xTarget = ESX.GetPlayerFromId(targetSrc)
    if not xTarget then
        AdminFunctions.Notify(src, 'Không tìm thấy người chơi.', 'error')
        return
    end

    local identifier = xTarget.identifier
    local adminLevel = AdminFunctions.GetLevel(targetSrc)
    local isWatchdog = AdminFunctions.IsWatchdog(targetSrc)
    if adminLevel < 1 and not isWatchdog and name:lower() ~= 'watchdog' then
        AdminFunctions.Notify(src, 'Người chơi này không phải là Admin hoặc Watchdog.', 'error')
        return
    end

    name  = tostring(name):sub(1, 64)
    color = color or (isWatchdog and (Config.Watchdog and Config.Watchdog.color or '#94a3b8')) or Config.AdminTagColors[adminLevel] or '#ffffff'

    local xAdmin = ESX.GetPlayerFromId(src)
    local adminId = xAdmin and xAdmin.identifier or 'console'

    MySQL.query.await(
        'INSERT INTO admin_levels (identifier, level, name, added_by, rank_name, rank_color) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE rank_name = ?, rank_color = ?',
        { identifier, adminLevel, GetPlayerName(targetSrc), adminId, name, color, name, color }
    )

    PlayerRankCache[identifier] = { name = name, color = color }
    if name:lower() == 'watchdog' then
        if WatchdogCache then WatchdogCache[identifier] = true end
        Player(targetSrc).state:set('isWatchdog', true, true)
        TriggerClientEvent('admincore:setWatchdog', targetSrc, true)
    elseif isWatchdog and name:lower() ~= 'watchdog' then
        -- Updated custom rank name for watchdog, keep watchdog flag
    end

    AdminFunctions.Notify(src, ('Đã đổi tên rank của %s thành: [%s]'):format(GetPlayerName(targetSrc), name), 'success')
    AdminLogger.Log(src, 'setrankname', targetSrc, ('Rank -> %s (%s)'):format(name, color))
    TriggerEvent('admincore:refreshCache')
end

-- =============================================
--   SetWatchdog: Cấp hoặc xóa role Watchdog
-- =============================================
---@param src number       Admin thực hiện (0 = console)
---@param targetSrc number Target player server ID
---@param status boolean|nil true = cấp, false = xóa, nil = toggle
---@return boolean, string
function AdminFunctions.SetWatchdog(src, targetSrc, status)
    if src ~= 0 and not AdminFunctions.HasPermission(src, 'setlevel') and AdminFunctions.GetLevel(src) < 4 then
        return false, 'Bạn không có quyền thực hiện lệnh này.'
    end

    local xTarget = ESX.GetPlayerFromId(targetSrc)
    if not xTarget then return false, 'Không tìm thấy người chơi.' end

    local identifier = xTarget.identifier
    local currentWatchdog = AdminFunctions.IsWatchdog(targetSrc)
    if status == nil then
        status = not currentWatchdog
    else
        status = (status == true or status == 1 or status == '1' or status == 'on' or status == 'true')
    end

    local name = GetPlayerName(targetSrc)
    local xAdmin = src ~= 0 and ESX.GetPlayerFromId(src) or nil
    local adminId = xAdmin and xAdmin.identifier or 'console'
    local tag = (Config.Watchdog and Config.Watchdog.tag) or 'Watchdog'
    local color = (Config.Watchdog and Config.Watchdog.color) or '#94a3b8'

    if status then
        MySQL.query.await(
            'INSERT INTO admin_levels (identifier, level, name, added_by, rank_name, rank_color) VALUES (?, 0, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE level = 0, name = ?, rank_name = ?, rank_color = ?, added_by = ?',
            { identifier, name, adminId, tag, color, name, tag, color, adminId }
        )
        if WatchdogCache then WatchdogCache[identifier] = true end
        AdminCache[identifier] = nil
        PlayerRankCache[identifier] = { name = tag, color = color }
        AdminFunctions.SetAdminStateBag(targetSrc, 0)
        Player(targetSrc).state:set('isWatchdog', true, true)
        TriggerClientEvent('admincore:setLevel', targetSrc, 0)
        TriggerClientEvent('admincore:setWatchdog', targetSrc, true)
        AdminFunctions.SyncPermissions(targetSrc, 0)

        AdminFunctions.Notify(targetSrc, 'Bạn đã được cấp role Watchdog (chỉ có thể sử dụng lệnh /c).', 'info')
        AdminLogger.Log(src, 'setwatchdog', targetSrc, 'Cap role Watchdog')
        TriggerEvent('admincore:refreshCache')
        return true, ('Đã cấp role Watchdog cho %s (ID: %d).'):format(name, targetSrc)
    else
        local currentLevel = AdminCache[identifier] or 0
        if currentLevel <= 0 then
            MySQL.query.await('DELETE FROM admin_levels WHERE identifier = ?', { identifier })
            PlayerRankCache[identifier] = nil
        else
            MySQL.query.await('UPDATE admin_levels SET rank_name = NULL, rank_color = NULL WHERE identifier = ?', { identifier })
            PlayerRankCache[identifier] = nil
        end
        if WatchdogCache then WatchdogCache[identifier] = nil end
        Player(targetSrc).state:set('isWatchdog', false, true)
        TriggerClientEvent('admincore:setWatchdog', targetSrc, false)

        AdminFunctions.Notify(targetSrc, 'Role Watchdog của bạn đã bị xóa.', 'warning')
        AdminLogger.Log(src, 'setwatchdog', targetSrc, 'Xoa role Watchdog')
        TriggerEvent('admincore:refreshCache')
        return true, ('Đã xóa role Watchdog của %s (ID: %d).'):format(name, targetSrc)
    end
end

