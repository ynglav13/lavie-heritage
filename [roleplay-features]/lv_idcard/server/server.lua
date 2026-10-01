ESX = exports['es_extended']:getSharedObject()

MySQL.ready(function()
    pcall(function()
        MySQL.query.await("ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `nationality` VARCHAR(50) DEFAULT NULL")
    end)
    pcall(function()
        MySQL.query.await("ALTER TABLE `users` MODIFY COLUMN `nationality` VARCHAR(50) DEFAULT NULL")
    end)
    pcall(function()
        MySQL.query.await([[
            UPDATE `users`
            SET `nationality` = 'USA'
            WHERE `nationality` IS NOT NULL
              AND (LOWER(`nationality`) = 'san andreas'
               OR `nationality` NOT IN ('USA','CAN','MEX','BRA','UK','GER','FRA','ITA','ESP','POL','NED','BEL','SWE','NOR','DEN','FIN','SUI','AUT','AUS','NZ','JPN','CHN','KOR','IND','TUR','KSA','UAE','RSA','ARG','CHI','RUS','VIETNAM','VIE'))
        ]])
    end)
    pcall(function()
        MySQL.query.await([[
            UPDATE `lv_idcards`
            SET `nationality` = 'USA'
            WHERE `nationality` IS NOT NULL
              AND (LOWER(`nationality`) = 'san andreas'
               OR `nationality` NOT IN ('USA','CAN','MEX','BRA','UK','GER','FRA','ITA','ESP','POL','NED','BEL','SWE','NOR','DEN','FIN','SUI','AUT','AUS','NZ','JPN','CHN','KOR','IND','TUR','KSA','UAE','RSA','ARG','CHI','RUS','VIETNAM','VIE'))
        ]])
    end)
end)

local function isPolice(source)
    return Player(source).state.factionCategory == 'police'
end

local function isPoliceLeader(source)
    local state = Player(source).state
    if state.factionCategory ~= 'police' then return false end

    local factionTag = state.factionTag
    local playerName = state.playerName
    if not factionTag or not playerName then return false end

    local result = MySQL.query.await('SELECT permission FROM faction WHERE tag = ?', { factionTag })
    if result and result[1] and result[1].permission then
        local permission = json.decode(result[1].permission) or {}
        local normalizedPlayerName = playerName:lower():gsub('%s+', ' ')
        for i = 1, #permission do
            local permName = tostring(permission[i].name or '')
            local normalizedPermName = permName:lower():gsub('%s+', ' ')
            if normalizedPermName == normalizedPlayerName then
                return permission[i].leader == true
            end
        end
    end
    return false
end

local function sendDiscordLog(title, fields, color)
    local webhook = Config.DiscordWebhook
    if not webhook or webhook == "" then return end

    local embed = {
        {
            ["title"] = title,
            ["color"] = color or 3447003, -- Default blue
            ["fields"] = fields,
            ["footer"] = {
                ["text"] = "ID Card Logger • " .. os.date("%Y-%m-%d %H:%M:%S")
            }
        }
    }

    PerformHttpRequest(webhook, function(err, text, headers) end, 'POST', json.encode({ embeds = embed }), { ['Content-Type'] = 'application/json' })
end

local function notify(source, title, message, ntype)
    TriggerClientEvent('lv_notify:client:notify', source, { title = title, message = message, type = ntype })
end

local function generateIdNumber(id)
    local seed = (id * 135791 + 97531) % 9000000 + 1000000
    return string.format('I%d', seed)
end

local function validatePhotoUrl(url)
    if type(url) ~= 'string' or url == '' then return false end
    local host = url:match('^https?://([^/?#]+)')
    if not host then return false end
    return Config.ValidHosts[host:lower()] == true
end

local function sanitize(s, maxLen)
    if type(s) ~= 'string' then return '' end
    return s:sub(1, maxLen):gsub('[<>"\'%;%%]', '')
end

lib.callback.register('lv_idcard:getPlayerInfo', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return nil end
    local sexRaw = xPlayer.get('sex') or 'm'
    local sex
    if type(sexRaw) == 'number' then
        sex = sexRaw == 1 and 'F' or 'M'
    else
        sex = (tostring(sexRaw):lower() == 'f' or tostring(sexRaw):lower() == 'female') and 'F' or 'M'
    end

    local nationality = MySQL.scalar.await(
        'SELECT nationality FROM users WHERE identifier = ? LIMIT 1',
        { xPlayer.identifier }
    )

    return {
        firstname   = xPlayer.get('firstName') or '',
        lastname    = xPlayer.get('lastName') or '',
        dob         = xPlayer.get('dateofbirth') or '',
        sex         = sex,
        nationality = nationality or '',
        identifier  = xPlayer.identifier
    }
end)


lib.callback.register('lv_idcard:getPendingList', function(source)
    if not isPolice(source) then return nil end
    return MySQL.query.await(
        'SELECT id, identifier, firstname, lastname, dob, address, sex, hair, eyes, height, weight, nationality, photo_url, issue_date, expire_date, created_at FROM lv_idcards WHERE status = "pending" ORDER BY created_at DESC LIMIT 50'
    )
end)

lib.callback.register('lv_idcard:getMyCard', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return nil end
    local result = MySQL.query.await(
        'SELECT * FROM lv_idcards WHERE identifier = ? AND status = "approved" LIMIT 1',
        { xPlayer.identifier }
    )
    if not result or #result == 0 then return nil end
    local card = result[1]
    card.id_number = generateIdNumber(card.id)
    return card
end)

lib.callback.register('lv_idcard:getNearbyPlayers', function(source)
    local srcCoords = GetEntityCoords(GetPlayerPed(source))
    local nearby = {}
    for _, pid in ipairs(GetPlayers()) do
        local pid = tonumber(pid)
        if pid ~= source then
            local dist = #(srcCoords - GetEntityCoords(GetPlayerPed(pid)))
            if dist <= Config.ShowProximity then
                local xp = ESX.GetPlayerFromId(pid)
                if xp then
                    nearby[#nearby + 1] = { serverId = pid, name = xp.getName() }
                end
            end
        end
    end
    return nearby
end)

RegisterNetEvent('lv_idcard:submitApplication')
AddEventHandler('lv_idcard:submitApplication', function(data)
    local src = source
    Citizen.CreateThread(function()
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return end



        local firstname   = sanitize(data.firstname, 50)
        local lastname    = sanitize(data.lastname,  50)
        local dob         = sanitize(data.dob,       20)
        local address     = sanitize(data.address,   120)
        local sex         = sanitize(data.sex,        1)
        local hair        = sanitize(data.hair,       10)
        local eyes        = sanitize(data.eyes,       10)
        local height      = sanitize(data.height,     12)
        local weight      = sanitize(data.weight,     12)
        local nationality = sanitize(data.nationality,50)
        local photo_url   = type(data.photo_url) == 'string' and data.photo_url:sub(1, 512) or ''

        if firstname == '' or lastname == '' or dob == '' or address == '' then
            notify(src, 'ID Card', 'Vui lòng điền đầy đủ thông tin bắt buộc.', 'error')
            return
        end

        local existing = MySQL.query.await(
            'SELECT id, status FROM lv_idcards WHERE identifier = ? LIMIT 1',
            { xPlayer.identifier }
        )

        if existing and #existing > 0 then
            if existing[1].status == 'approved' then
                notify(src, 'ID Card', 'Bạn đã có ID Card hợp lệ. Liên hệ LSPD để cấp lại.', 'error')
                return
            end
            MySQL.query.await(
                'UPDATE lv_idcards SET firstname=?, lastname=?, dob=?, address=?, sex=?, hair=?, eyes=?, height=?, weight=?, nationality=?, photo_url=?, issue_date=CURDATE(), expire_date=DATE_ADD(CURDATE(), INTERVAL ? YEAR), status="pending", approved_by=NULL WHERE identifier=?',
                { firstname, lastname, dob, address, sex, hair, eyes, height, weight, nationality, photo_url, Config.ExpireYears, xPlayer.identifier }
            )
        else
            MySQL.query.await(
                'INSERT INTO lv_idcards (identifier, firstname, lastname, dob, address, sex, hair, eyes, height, weight, nationality, photo_url, issue_date, expire_date, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURDATE(), DATE_ADD(CURDATE(), INTERVAL ? YEAR), "pending")',
                { xPlayer.identifier, firstname, lastname, dob, address, sex, hair, eyes, height, weight, nationality, photo_url, Config.ExpireYears }
            )
        end

        pcall(function()
            MySQL.query.await(
                'UPDATE users SET nationality = ? WHERE identifier = ?',
                { nationality, xPlayer.identifier }
            )
        end)

        notify(src, 'ID Card', 'Đơn đăng ký đã gửi thành công. Vui lòng chờ sĩ quan xét duyệt.', 'success')

        if GetResourceState('lv_tutorial') == 'started' then
            if exports.lv_tutorial:AdvanceStep(src, 5) then
                TriggerClientEvent('lv_notify:client:notify', src, {
                    title = 'Hướng dẫn',
                    message = 'Đã nộp form CID. Điểm tiếp theo: Tham quan Job rác.',
                    type = 'success',
                    duration = 5000
                })
            end
        end
    end)
end)

RegisterNetEvent('lv_idcard:approveCard')
AddEventHandler('lv_idcard:approveCard', function(appId, newPhotoUrl)
    local src = source
    if not isPolice(src) then
        notify(src, 'ID Card', 'Bạn không có quyền thực hiện thao tác này.', 'error')
        return
    end
    Citizen.CreateThread(function()
        local policePlayer = ESX.GetPlayerFromId(src)
        if not policePlayer then return end

        local result = MySQL.query.await(
            'SELECT * FROM lv_idcards WHERE id = ? AND status = "pending" LIMIT 1',
            { tonumber(appId) }
        )
        if not result or #result == 0 then
            notify(src, 'ID Card', 'Đơn không tồn tại hoặc đã được xử lý.', 'error')
            return
        end

        local app = result[1]
        local targetPlayer = ESX.GetPlayerFromIdentifier(app.identifier)

        if not targetPlayer then
            notify(src, 'ID Card', 'Người chơi không online. Vui lòng thử lại sau.', 'error')
            return
        end

        if targetPlayer.getMoney() < Config.IdCardFee then
            notify(src, 'ID Card', ('Người chơi không đủ tiền. Cần $%d.'):format(Config.IdCardFee), 'error')
            notify(targetPlayer.source, 'ID Card', ('Bạn không đủ tiền làm ID Card. Cần $%d.'):format(Config.IdCardFee), 'error')
            return
        end

        if newPhotoUrl and newPhotoUrl ~= '' then
            if not validatePhotoUrl(newPhotoUrl) then
                notify(src, 'ID Card', 'URL ảnh không hợp lệ hoặc domain không được chấp nhận.', 'error')
                return
            end
            app.photo_url = newPhotoUrl:sub(1, 512)
        end

        targetPlayer.removeMoney(Config.IdCardFee)

        MySQL.query.await(
            'UPDATE lv_idcards SET status = "approved", approved_by = ?, photo_url = ? WHERE id = ?',
            { policePlayer.identifier, app.photo_url, app.id }
        )

        local idNumber = generateIdNumber(app.id)
        local metadata = {
            label       = 'ID Card - ' .. app.firstname .. ' ' .. app.lastname,
            description = 'Quốc tịch: ' .. (app.nationality or 'Không') .. ' | DOB: ' .. (app.dob or ''),
            card_id     = app.id,
            id_number   = idNumber
        }
        exports.ox_inventory:AddItem(targetPlayer.source, 'idcard', 1, metadata)

        local reward = math.random(12000, 20000)
        exports.ox_inventory:AddItem(src, 'money', reward)

        notify(targetPlayer.source, 'ID Card', ('ID Card đã được duyệt! Đã trừ $%d tiền mặt.'):format(Config.IdCardFee), 'success')
        notify(src, 'ID Card', ('Đã duyệt ID Card cho %s %s và nhận được $%d tiền công.'):format(app.firstname, app.lastname, reward), 'success')

        sendDiscordLog("🪪 DUYỆT ĐƠN ĐĂNG KÝ ID CARD", {
            { name = "Sĩ quan duyệt", value = ("%s (ID: %s)"):format(policePlayer.getName(), src), inline = true },
            { name = "Người đăng ký", value = ("%s %s (ID: %s)"):format(app.firstname, app.lastname, targetPlayer.source), inline = true },
            { name = "Mã ID Card", value = idNumber, inline = true },
            { name = "Phí cấp", value = ("$%d"):format(Config.IdCardFee), inline = true },
            { name = "Tiền công sĩ quan", value = ("$%d"):format(reward), inline = true }
        }, 3066993)
    end)
end)

RegisterNetEvent('lv_idcard:rejectCard')
AddEventHandler('lv_idcard:rejectCard', function(appId)
    local src = source
    if not isPolice(src) then return end
    Citizen.CreateThread(function()
        local policePlayer = ESX.GetPlayerFromId(src)
        local result = MySQL.query.await(
            'SELECT * FROM lv_idcards WHERE id = ? AND status = "pending" LIMIT 1',
            { tonumber(appId) }
        )
        if not result or #result == 0 then
            notify(src, 'ID Card', 'Đơn không tồn tại hoặc đã được xử lý.', 'error')
            return
        end

        local app = result[1]
        MySQL.query.await('DELETE FROM lv_idcards WHERE id = ?', { app.id })

        local targetPlayer = ESX.GetPlayerFromIdentifier(app.identifier)
        if targetPlayer then
            notify(targetPlayer.source, 'ID Card', 'Đơn ID Card của bạn đã bị từ chối. Bạn có thể nộp lại.', 'error')
        end
        notify(src, 'ID Card', 'Đã từ chối đơn của ' .. app.firstname .. ' ' .. app.lastname .. '.', 'inform')

        sendDiscordLog("❌ TỪ CHỐI ĐƠN ID CARD", {
            { name = "Sĩ quan từ chối", value = ("%s (ID: %s)"):format(policePlayer and policePlayer.getName() or "N/A", src), inline = true },
            { name = "Người xin cấp", value = ("%s %s"):format(app.firstname, app.lastname), inline = true }
        }, 15158332)
    end)
end)

RegisterNetEvent('lv_idcard:showCardToPlayer')
AddEventHandler('lv_idcard:showCardToPlayer', function(targetId, specificCardId)
    local src   = source
    local tid   = tonumber(targetId)
    if not tid then return end
    Citizen.CreateThread(function()
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return end

        local srcCoords = GetEntityCoords(GetPlayerPed(src))
        if not DoesEntityExist(GetPlayerPed(tid)) then
            notify(src, 'ID Card', 'Người chơi không tồn tại.', 'error')
            return
        end
        if #(srcCoords - GetEntityCoords(GetPlayerPed(tid))) > Config.ShowProximity + 2.0 then
            notify(src, 'ID Card', 'Người chơi quá xa.', 'error')
            return
        end

        local card_id = specificCardId
        if not card_id then
            local cardItems = exports.ox_inventory:GetSlotsWithItem(src, 'idcard')
            if not cardItems or #cardItems == 0 then
                notify(src, 'ID Card', 'Bạn không có ID Card hợp lệ để trình.', 'error')
                return
            end
            for _, slot in ipairs(cardItems) do
                if slot.metadata and slot.metadata.card_id then
                    card_id = slot.metadata.card_id
                    break
                end
            end
        end

        local result
        if card_id then
            result = MySQL.query.await(
                'SELECT * FROM lv_idcards WHERE id = ? AND status = "approved" LIMIT 1',
                { card_id }
            )
        else
            result = MySQL.query.await(
                'SELECT * FROM lv_idcards WHERE identifier = ? AND status = "approved" LIMIT 1',
                { xPlayer.identifier }
            )
        end

        if not result or #result == 0 then
            notify(src, 'ID Card', 'Thẻ ID bạn đang giữ không hợp lệ.', 'error')
            return
        end

        local card = result[1]
        card.id_number = generateIdNumber(card.id)

        TriggerClientEvent('lv_idcard:client:showNearbyCard', tid, card)
    end)
end)

lib.callback.register('lv_idcard:getCardById', function(source, cardId)
    if not cardId then return nil end
    local result = MySQL.query.await(
        'SELECT * FROM lv_idcards WHERE id = ? AND status = "approved" LIMIT 1',
        { cardId }
    )
    if not result or #result == 0 then return nil end
    local card = result[1]
    card.id_number = generateIdNumber(card.id)
    return card
end)

lib.callback.register('lv_idcard:getPendingLicenseList', function(source)
    if not isPolice(source) then return nil end
    return MySQL.query.await(
        'SELECT id, identifier, firstname, lastname, dob, address, sex, hair, eyes, height, weight, nationality, photo_url, issue_date, expire_date, driver_license, created_at FROM lv_idcards WHERE status = "approved" AND driver_license = "PENDING" ORDER BY updated_at DESC LIMIT 50'
    )
end)

RegisterNetEvent('lv_idcard:applyDriverLicense')
AddEventHandler('lv_idcard:applyDriverLicense', function()
    local src = source
    Citizen.CreateThread(function()
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return end

        local card = MySQL.query.await(
            'SELECT id, status, driver_license FROM lv_idcards WHERE identifier = ? LIMIT 1',
            { xPlayer.identifier }
        )

        if not card or #card == 0 or card[1].status ~= 'approved' then
            notify(src, 'Bằng Lái', 'Bạn cần phải có ID Card hợp lệ và đã được duyệt trước.', 'error')
            return
        end

        local currentLicense = card[1].driver_license
        if currentLicense == 'PASS' then
            notify(src, 'Bằng Lái', 'Bạn đã tích hợp bằng lái xe rồi.', 'error')
            return
        elseif currentLicense == 'PENDING' then
            notify(src, 'Bằng Lái', 'Đơn tích hợp của bạn đang chờ duyệt.', 'error')
            return
        end

        MySQL.query.await(
            'UPDATE lv_idcards SET driver_license = "PENDING" WHERE identifier = ?',
            { xPlayer.identifier }
        )
        notify(src, 'Bằng Lái', 'Đơn xin tích hợp bằng lái đã được gửi cho Cảnh sát duyệt.', 'success')
    end)
end)

RegisterNetEvent('lv_idcard:approveDriverLicense')
AddEventHandler('lv_idcard:approveDriverLicense', function(appId)
    local src = source
    if not isPolice(src) then
        notify(src, 'Bằng Lái', 'Bạn không có quyền thực hiện thao tác này.', 'error')
        return
    end
    Citizen.CreateThread(function()
        local policePlayer = ESX.GetPlayerFromId(src)
        if not policePlayer then return end

        local result = MySQL.query.await(
            'SELECT * FROM lv_idcards WHERE id = ? AND status = "approved" AND driver_license = "PENDING" LIMIT 1',
            { tonumber(appId) }
        )
        if not result or #result == 0 then
            notify(src, 'Bằng Lái', 'Đơn không tồn tại hoặc đã được xử lý.', 'error')
            return
        end

        local app = result[1]
        local targetPlayer = ESX.GetPlayerFromIdentifier(app.identifier)

        if not targetPlayer then
            notify(src, 'Bằng Lái', 'Người chơi không online. Vui lòng thử lại sau.', 'error')
            return
        end

        if targetPlayer.getMoney() < Config.DriverLicenseFee then
            notify(src, 'Bằng Lái', ('Người chơi không đủ tiền. Cần $%d.'):format(Config.DriverLicenseFee), 'error')
            notify(targetPlayer.source, 'Bằng Lái', ('Bạn không đủ tiền tích hợp Bằng Lái. Cần $%d.'):format(Config.DriverLicenseFee), 'error')
            return
        end

        targetPlayer.removeMoney(Config.DriverLicenseFee)

        MySQL.query.await(
            'UPDATE lv_idcards SET driver_license = "PASS" WHERE id = ?',
            { app.id }
        )

        local targetInventory = exports.ox_inventory:GetSlotsWithItem(targetPlayer.source, 'idcard')
        if targetInventory and #targetInventory > 0 then
            for _, slot in ipairs(targetInventory) do
                if slot.metadata and slot.metadata.card_id == app.id then
                    slot.metadata.driver_license = 'PASS'
                    slot.metadata.label = 'ID Card - ' .. app.firstname .. ' ' .. app.lastname
                    exports.ox_inventory:SetMetadata(targetPlayer.source, slot.slot, slot.metadata)
                end
            end
        end

        notify(targetPlayer.source, 'Bằng Lái', ('Bằng lái xe đã được tích hợp thành công! Đã trừ $%d tiền mặt.'):format(Config.DriverLicenseFee), 'success')
        notify(src, 'Bằng Lái', ('Đã duyệt tích hợp bằng lái cho %s %s.'):format(app.firstname, app.lastname), 'success')

        sendDiscordLog("🚗 DUYỆT BẰNG LÁI XE", {
            { name = "Sĩ quan duyệt", value = ("%s (ID: %s)"):format(policePlayer.getName(), src), inline = true },
            { name = "Người nhận", value = ("%s %s (ID: %s)"):format(app.firstname, app.lastname, targetPlayer.source), inline = true },
            { name = "Phí tích hợp", value = ("$%d"):format(Config.DriverLicenseFee), inline = true }
        }, 3066993)
    end)
end)

RegisterNetEvent('lv_idcard:rejectDriverLicense')
AddEventHandler('lv_idcard:rejectDriverLicense', function(appId)
    local src = source
    if not isPolice(src) then return end
    Citizen.CreateThread(function()
        local policePlayer = ESX.GetPlayerFromId(src)
        local result = MySQL.query.await(
            'SELECT * FROM lv_idcards WHERE id = ? AND status = "approved" AND driver_license = "PENDING" LIMIT 1',
            { tonumber(appId) }
        )
        if not result or #result == 0 then
            notify(src, 'Bằng Lái', 'Đơn không tồn tại hoặc đã được xử lý.', 'error')
            return
        end

        local app = result[1]
        MySQL.query.await('UPDATE lv_idcards SET driver_license = "NONE" WHERE id = ?', { app.id })

        local targetPlayer = ESX.GetPlayerFromIdentifier(app.identifier)
        if targetPlayer then
            notify(targetPlayer.source, 'Bằng Lái', 'Yêu cầu tích hợp bằng lái của bạn đã bị sĩ quan từ chối.', 'error')
        end
        notify(src, 'Bằng Lái', 'Đã từ chối đơn bằng lái của ' .. app.firstname .. ' ' .. app.lastname .. '.', 'inform')

        sendDiscordLog("❌ TỪ CHỐI BẰNG LÁI XE", {
            { name = "Sĩ quan từ chối", value = ("%s (ID: %s)"):format(policePlayer and policePlayer.getName() or "N/A", src), inline = true },
            { name = "Người xin", value = ("%s %s"):format(app.firstname, app.lastname), inline = true }
        }, 15158332)
    end)
end)

lib.callback.register('lv_idcard:getPendingWeaponList', function(source)
    if not isPoliceLeader(source) then return nil end
    return MySQL.query.await(
        'SELECT id, identifier, firstname, lastname, dob, address, sex, hair, eyes, height, weight, nationality, photo_url, issue_date, expire_date, weapon_license, created_at FROM lv_idcards WHERE status = "approved" AND weapon_license = "PENDING" ORDER BY updated_at DESC LIMIT 50'
    )
end)

RegisterNetEvent('lv_idcard:applyWeaponLicense')
AddEventHandler('lv_idcard:applyWeaponLicense', function()
    local src = source
    Citizen.CreateThread(function()
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return end

        local card = MySQL.query.await(
            'SELECT id, status, weapon_license FROM lv_idcards WHERE identifier = ? LIMIT 1',
            { xPlayer.identifier }
        )

        if not card or #card == 0 or card[1].status ~= 'approved' then
            notify(src, 'Giấy Phép Vũ Khí', 'Bạn cần phải có ID Card hợp lệ và đã được duyệt trước.', 'error')
            return
        end

        local currentLicense = card[1].weapon_license
        if currentLicense == 'PASS' then
            notify(src, 'Giấy Phép Vũ Khí', 'Bạn đã tích hợp giấy phép sử dụng vũ khí rồi.', 'error')
            return
        elseif currentLicense == 'PENDING' then
            notify(src, 'Giấy Phép Vũ Khí', 'Đơn tích hợp của bạn đang chờ duyệt.', 'error')
            return
        end

        MySQL.query.await(
            'UPDATE lv_idcards SET weapon_license = "PENDING" WHERE identifier = ?',
            { xPlayer.identifier }
        )
        notify(src, 'Giấy Phép Vũ Khí', 'Đơn xin tích hợp giấy phép vũ khí đã được gửi cho Cấp trên (Leader) duyệt.', 'success')
    end)
end)

RegisterNetEvent('lv_idcard:approveWeaponLicense')
AddEventHandler('lv_idcard:approveWeaponLicense', function(appId)
    local src = source
    if not isPoliceLeader(src) then
        notify(src, 'Giấy Phép Vũ Khí', 'Chỉ có Leader LSPD / LSSD mới có quyền duyệt bằng súng.', 'error')
        return
    end
    Citizen.CreateThread(function()
        local policePlayer = ESX.GetPlayerFromId(src)
        if not policePlayer then return end

        local result = MySQL.query.await(
            'SELECT * FROM lv_idcards WHERE id = ? AND status = "approved" AND weapon_license = "PENDING" LIMIT 1',
            { tonumber(appId) }
        )
        if not result or #result == 0 then
            notify(src, 'Giấy Phép Vũ Khí', 'Đơn không tồn tại hoặc đã được xử lý.', 'error')
            return
        end

        local app = result[1]
        local targetPlayer = ESX.GetPlayerFromIdentifier(app.identifier)

        if not targetPlayer then
            notify(src, 'Giấy Phép Vũ Khí', 'Người chơi không online. Vui lòng thử lại sau.', 'error')
            return
        end

        if targetPlayer.getMoney() < Config.WeaponLicenseFee then
            notify(src, 'Giấy Phép Vũ Khí', ('Người chơi không đủ tiền. Cần $%d.'):format(Config.WeaponLicenseFee), 'error')
            notify(targetPlayer.source, 'Giấy Phép Vũ Khí', ('Bạn không đủ tiền tích hợp Giấy Phép Vũ Khí. Cần $%d.'):format(Config.WeaponLicenseFee), 'error')
            return
        end

        targetPlayer.removeMoney(Config.WeaponLicenseFee)

        MySQL.query.await(
            'UPDATE lv_idcards SET weapon_license = "PASS" WHERE id = ?',
            { app.id }
        )

        local hasLic = MySQL.scalar.await(
            'SELECT id FROM user_licenses WHERE type = "weapon" AND owner = ? LIMIT 1',
            { app.identifier }
        )
        if not hasLic then
            MySQL.query.await(
                'INSERT INTO user_licenses (type, owner) VALUES ("weapon", ?)',
                { app.identifier }
            )
        end

        local targetInventory = exports.ox_inventory:GetSlotsWithItem(targetPlayer.source, 'idcard')
        if targetInventory and #targetInventory > 0 then
            for _, slot in ipairs(targetInventory) do
                if slot.metadata and slot.metadata.card_id == app.id then
                    slot.metadata.weapon_license = 'PASS'
                    slot.metadata.label = 'ID Card - ' .. app.firstname .. ' ' .. app.lastname
                    exports.ox_inventory:SetMetadata(targetPlayer.source, slot.slot, slot.metadata)
                end
            end
        end

        notify(targetPlayer.source, 'Giấy Phép Vũ Khí', ('Giấy phép sử dụng vũ khí đã được tích hợp thành công! Đã trừ $%d tiền mặt.'):format(Config.WeaponLicenseFee), 'success')
        notify(src, 'Giấy Phép Vũ Khí', ('Đã duyệt tích hợp giấy phép vũ khí cho %s %s.'):format(app.firstname, app.lastname), 'success')

        sendDiscordLog("🔫 DUYỆT GIẤY PHÉP VŨ KHÍ (BẰNG SÚNG)", {
            { name = "Leader duyệt", value = ("%s (ID: %s)"):format(policePlayer.getName(), src), inline = true },
            { name = "Người nhận", value = ("%s %s (ID: %s)"):format(app.firstname, app.lastname, targetPlayer.source), inline = true },
            { name = "Phí tích hợp", value = ("$%d"):format(Config.WeaponLicenseFee), inline = true }
        }, 15844367)
    end)
end)

RegisterNetEvent('lv_idcard:rejectWeaponLicense')
AddEventHandler('lv_idcard:rejectWeaponLicense', function(appId)
    local src = source
    if not isPoliceLeader(src) then
        notify(src, 'Giấy Phép Vũ Khí', 'Chỉ có Leader LSPD / LSSD mới có quyền từ chối bằng súng.', 'error')
        return
    end
    Citizen.CreateThread(function()
        local policePlayer = ESX.GetPlayerFromId(src)
        local result = MySQL.query.await(
            'SELECT * FROM lv_idcards WHERE id = ? AND status = "approved" AND weapon_license = "PENDING" LIMIT 1',
            { tonumber(appId) }
        )
        if not result or #result == 0 then
            notify(src, 'Giấy Phép Vũ Khí', 'Đơn không tồn tại hoặc đã được xử lý.', 'error')
            return
        end

        local app = result[1]
        MySQL.query.await('UPDATE lv_idcards SET weapon_license = "NONE" WHERE id = ?', { app.id })

        local targetPlayer = ESX.GetPlayerFromIdentifier(app.identifier)
        if targetPlayer then
            notify(targetPlayer.source, 'Giấy Phép Vũ Khí', 'Yêu cầu tích hợp giấy phép vũ khí của bạn đã bị sĩ quan từ chối.', 'error')
        end

        sendDiscordLog("❌ TỪ CHỐI BẰNG SÚNG", {
            { name = "Leader từ chối", value = ("%s (ID: %s)"):format(policePlayer and policePlayer.getName() or "N/A", src), inline = true },
            { name = "Người xin", value = ("%s %s"):format(app.firstname, app.lastname), inline = true }
        }, 15158332)
    end)
end)

local licenseRevocationTypes = {
    driver = {
        column = 'driver_license',
        licenseType = 'drive',
        title = 'Bằng Lái',
        label = 'bằng lái xe',
        inventoryItem = 'driver_license'
    },
    weapon = {
        column = 'weapon_license',
        licenseType = 'weapon',
        title = 'Giấy Phép Vũ Khí',
        label = 'giấy phép sử dụng vũ khí'
    }
}

local function revokePlayerLicense(src, targetId, licenseKey)
    local officer = ESX.GetPlayerFromId(src)
    local targetPlayer = ESX.GetPlayerFromId(targetId)
    local officerState = Player(src).state
    local license = licenseRevocationTypes[licenseKey]

    if not officer or officerState.factionCategory ~= 'police' or officerState.factionDuty ~= true then
        notify(src, 'Tước Giấy Phép', 'Chỉ cảnh sát hoặc sheriff đang trực mới được sử dụng lệnh này.', 'error')
        return
    end

    if not targetPlayer then
        notify(src, 'Tước Giấy Phép', 'Người chơi không online.', 'error')
        return
    end

    if targetId == src then
        notify(src, 'Tước Giấy Phép', 'Bạn không thể tự tước giấy phép của mình.', 'error')
        return
    end

    local officerPed = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetId)
    if officerPed == 0 or targetPed == 0 or #(GetEntityCoords(officerPed) - GetEntityCoords(targetPed)) > 5.0 then
        notify(src, 'Tước Giấy Phép', 'Người chơi này ở quá xa bạn.', 'error')
        return
    end

    local card = MySQL.single.await(
        ('SELECT id, firstname, lastname, %s AS license_status FROM lv_idcards WHERE identifier = ? AND status = "approved" LIMIT 1'):format(license.column),
        { targetPlayer.identifier }
    )

    if not card then
        notify(src, 'Tước Giấy Phép', 'Người chơi này chưa có ID Card đã được duyệt.', 'error')
        return
    end

    if card.license_status ~= 'PASS' then
        notify(src, 'Tước Giấy Phép', ('Người chơi này không có %s hợp lệ.'):format(license.label), 'error')
        return
    end

    local success = MySQL.transaction.await({
        {
            query = ('UPDATE lv_idcards SET %s = "NONE" WHERE id = ? AND %s = "PASS"'):format(license.column, license.column),
            values = { card.id }
        },
        {
            query = 'DELETE FROM user_licenses WHERE owner = ? AND type = ?',
            values = { targetPlayer.identifier, license.licenseType }
        }
    })

    if not success then
        notify(src, 'Tước Giấy Phép', 'Không thể cập nhật dữ liệu giấy phép. Vui lòng thử lại.', 'error')
        return
    end

    local cardItems = exports.ox_inventory:GetSlotsWithItem(targetId, 'idcard') or {}
    for _, slot in ipairs(cardItems) do
        if slot.metadata and tonumber(slot.metadata.card_id) == tonumber(card.id) then
            slot.metadata[license.column] = 'NONE'
            exports.ox_inventory:SetMetadata(targetId, slot.slot, slot.metadata)
        end
    end

    if license.inventoryItem then
        local itemCount = exports.ox_inventory:Search(targetId, 'count', license.inventoryItem) or 0
        if itemCount > 0 then
            exports.ox_inventory:RemoveItem(targetId, license.inventoryItem, itemCount)
        end
    end

    local targetName = ('%s %s'):format(card.firstname, card.lastname)
    notify(src, license.title, ('Đã tước %s của %s (ID %d).'):format(license.label, targetName, targetId), 'success')
    notify(targetId, license.title, ('%s %s đã tước %s của bạn.'):format(officer.getName(), tostring(officerState.factionTag or 'Cảnh sát'), license.label), 'error')

    sendDiscordLog("⚠️ TƯỚC GIẤY PHÉP", {
        { name = "Sĩ quan thực hiện", value = ("%s (ID: %s)"):format(officer.getName(), src), inline = true },
        { name = "Người bị tước", value = ("%s (ID: %s)"):format(targetName, targetId), inline = true },
        { name = "Loại giấy phép", value = license.label, inline = true }
    }, 15158332)
end

RegisterCommand('revokelicense', function(source, args)
    local src = source
    if src == 0 then return end

    local targetId = tonumber(args[1])
    local licenseKey = tostring(args[2] or ''):lower()
    if not targetId or not licenseRevocationTypes[licenseKey] then
        notify(src, 'License Revocation', 'Sử dụng: /revokelicense [ID] [driver/weapon]', 'error')
        return
    end

    revokePlayerLicense(src, targetId, licenseKey)
end, false)

RegisterCommand('caplaithe', function(source, args, rawCommand)
    local src = source
    if src == 0 then return end
    if not isPolice(src) then
        notify(src, 'ID Card', 'Bạn không có quyền sử dụng lệnh này.', 'error')
        return
    end

    local targetId = tonumber(args[1])
    if not targetId then
        notify(src, 'ID Card', 'Sử dụng: /caplaithe [ID_Người_Chơi]', 'error')
        return
    end

    local targetPlayer = ESX.GetPlayerFromId(targetId)
    if not targetPlayer then
        notify(src, 'ID Card', 'Người chơi không online.', 'error')
        return
    end

    local srcCoords = GetEntityCoords(GetPlayerPed(src))
    local targetCoords = GetEntityCoords(GetPlayerPed(targetId))
    if #(srcCoords - targetCoords) > 5.0 then
        notify(src, 'ID Card', 'Người chơi này ở quá xa bạn.', 'error')
        return
    end

    local result = MySQL.query.await(
        'SELECT * FROM lv_idcards WHERE identifier = ? AND status = "approved" LIMIT 1',
        { targetPlayer.identifier }
    )

    if not result or #result == 0 then
        notify(src, 'ID Card', 'Người chơi này chưa có ID Card đã được duyệt.', 'error')
        return
    end

    local app = result[1]

    if targetPlayer.getMoney() < Config.ReissueFee then
        notify(src, 'ID Card', ('Người chơi không đủ tiền. Cần $%d.'):format(Config.ReissueFee), 'error')
        notify(targetPlayer.source, 'ID Card', ('Bạn không đủ tiền cấp lại ID Card. Cần $%d.'):format(Config.ReissueFee), 'error')
        return
    end

    targetPlayer.removeMoney(Config.ReissueFee)

    local idNumber = generateIdNumber(app.id)
    local metadata = {
        label       = 'ID Card - ' .. app.firstname .. ' ' .. app.lastname,
        description = 'Quốc tịch: ' .. (app.nationality or 'Không') .. ' | DOB: ' .. (app.dob or ''),
        card_id     = app.id,
        id_number   = idNumber
    }
    exports.ox_inventory:AddItem(targetPlayer.source, 'idcard', 1, metadata)

    notify(targetPlayer.source, 'ID Card', ('ID Card đã được cấp lại! Đã trừ $%d tiền mặt.'):format(Config.ReissueFee), 'success')
    notify(src, 'ID Card', ('Đã cấp lại ID Card cho %s %s.'):format(app.firstname, app.lastname), 'success')
end, false)

lib.callback.register('lv_idcard:checkLicensesForNPC', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return { hasCard = false, drive = false, weapon = false } end

    local userLicenses = MySQL.query.await(
        'SELECT type FROM user_licenses WHERE owner = ? AND type IN ("drive", "weapon")',
        { xPlayer.identifier }
    )

    local hasDrive = false
    local hasWeapon = false
    for _, lic in ipairs(userLicenses) do
        if lic.type == 'drive' then hasDrive = true end
        if lic.type == 'weapon' then hasWeapon = true end
    end

    local card = MySQL.query.await(
        'SELECT status FROM lv_idcards WHERE identifier = ? LIMIT 1',
        { xPlayer.identifier }
    )

    local hasCard = false
    if card and #card > 0 and card[1].status == 'approved' then
        hasCard = true
    end

    return { hasCard = hasCard, drive = hasDrive, weapon = hasWeapon }
end)

local function syncPlayerIDCard(source, newPhotoUrl)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local identifier = xPlayer.identifier
    local firstname = xPlayer.get('firstName') or ''
    local lastname = xPlayer.get('lastName') or ''
    local dob = xPlayer.get('dateofbirth') or ''
    local sexRaw = xPlayer.get('sex') or 'm'
    local sex
    if type(sexRaw) == 'number' then
        sex = sexRaw == 1 and 'F' or 'M'
    else
        sex = (tostring(sexRaw):lower() == 'f' or tostring(sexRaw):lower() == 'female') and 'F' or 'M'
    end

    local result = MySQL.query.await(
        'SELECT * FROM lv_idcards WHERE identifier = ? AND status = "approved" LIMIT 1',
        { identifier }
    )

    if result and #result > 0 then
        local card = result[1]
        local photoToSet = card.photo_url

        if newPhotoUrl and newPhotoUrl ~= '' then
            if validatePhotoUrl(newPhotoUrl) then
                photoToSet = newPhotoUrl:sub(1, 512)
            else
                notify(source, 'ID Card', 'URL ảnh không hợp lệ hoặc domain không được chấp nhận.', 'error')
                return
            end
        end

        if card.firstname ~= firstname or card.lastname ~= lastname or card.dob ~= dob or card.sex ~= sex or card.photo_url ~= photoToSet then
            MySQL.query.await(
                'UPDATE lv_idcards SET firstname = ?, lastname = ?, dob = ?, sex = ?, photo_url = ? WHERE identifier = ?',
                { firstname, lastname, dob, sex, photoToSet, identifier }
            )

            local items = exports.ox_inventory:GetSlotsWithItem(source, 'idcard')
            if items and #items > 0 then
                for _, slot in ipairs(items) do
                    if slot.metadata and slot.metadata.card_id == card.id then
                        slot.metadata.label = 'ID Card - ' .. firstname .. ' ' .. lastname
                        slot.metadata.description = 'Quốc tịch: ' .. (card.nationality or 'Không') .. ' | DOB: ' .. dob
                        exports.ox_inventory:SetMetadata(source, slot.slot, slot.metadata)
                    end
                end
            end
        end
    end
end

RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function(src)
    local playerId = src or source
    Citizen.CreateThread(function()
        Citizen.Wait(5000)
        syncPlayerIDCard(playerId)
    end)
end)

RegisterCommand('syncidcard', function(source, args)
    local src = source
    if src == 0 then return end

    local arg1 = args[1]
    local arg2 = args[2]

    local targetId = tonumber(arg1)
    local newPhotoUrl = nil

    if targetId then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer and xPlayer.getGroup() ~= 'user' then
            if arg2 and arg2 ~= "" then
                newPhotoUrl = arg2
            end
            syncPlayerIDCard(targetId, newPhotoUrl)
            notify(src, 'ID Card', ('Đã đồng bộ ID Card cho ID %d.'):format(targetId), 'success')
        else
            notify(src, 'ID Card', 'Bạn không có quyền đồng bộ cho người khác.', 'error')
        end
    else
        if arg1 and arg1 ~= "" then
            newPhotoUrl = arg1
        end
        syncPlayerIDCard(src, newPhotoUrl)
        notify(src, 'ID Card', 'Đã đồng bộ thông tin ID Card mới nhất của bạn.', 'success')
    end
end, false)
