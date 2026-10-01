local ESX = exports.es_extended:getSharedObject()
local processing = {}
local requestCooldown = {}
local databaseReady = false

local function response(ok, message, data)
    data = data or {}
    data.ok = ok
    data.message = message
    data.type = ok and 'success' or 'error'
    return data
end

local function isNearNPC(source)
    local playerPed = GetPlayerPed(source)

    if playerPed == 0 then
        return false
    end

    local playerCoords = GetEntityCoords(playerPed)
    local npcCoords = vector3(Config.NPC.coords.x, Config.NPC.coords.y, Config.NPC.coords.z)
    return #(playerCoords - npcCoords) <= Config.InteractionDistance
end

local function utf8Length(value)
    local ok, length = pcall(utf8.len, value)
    return ok and length or nil
end

local function normalizeField(value, label, maxLength)
    if type(value) ~= 'string' then
        return nil, ('%s không hợp lệ.'):format(label)
    end

    if #value > maxLength * 4 then
        return nil, ('%s tối đa %d ký tự.'):format(label, maxLength)
    end

    if value:find('[%z\1-\31\127]') then
        return nil, ('%s không được chứa ký tự điều khiển hoặc xuống dòng.'):format(label)
    end

    value = value:gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')

    if value == '' then
        return nil, ('Vui lòng nhập %s.'):format(label:lower())
    end

    if value:find('[<>]') or value:find('{%x%x%x%x%x%x}') or value:find('~[%w_]+~') then
        return nil, ('%s không được chứa mã định dạng chat.'):format(label)
    end

    local length = utf8Length(value)

    if not length then
        return nil, ('%s chứa dữ liệu UTF-8 không hợp lệ.'):format(label)
    end

    if length > maxLength then
        return nil, ('%s tối đa %d ký tự.'):format(label, maxLength)
    end

    return value
end

local function validatePayload(payload)
    if type(payload) ~= 'table' then
        return nil, 'Dữ liệu quảng cáo không hợp lệ.'
    end

    local content, contentError = normalizeField(payload.content, 'Nội dung', Config.MaxContentLength)

    if not content then
        return nil, contentError
    end

    local advertiserName, nameError = normalizeField(
        payload.advertiserName,
        'Tên người QC',
        Config.MaxAdvertiserNameLength
    )

    if not advertiserName then
        return nil, nameError
    end

    local phone, phoneError = normalizeField(payload.phone, 'Phone', Config.MaxPhoneLength)

    if not phone then
        return nil, phoneError
    end

    local phoneLength = utf8Length(phone)

    local digitCount = select(2, phone:gsub('%d', ''))

    if phoneLength < 3 or digitCount < 3 or not phone:match('^[%d%+%-%s]+$') then
        return nil, 'Phone phải có ít nhất 3 số và chỉ được chứa số, dấu +, dấu - hoặc khoảng trắng.'
    end

    return {
        content = content,
        advertiserName = advertiserName,
        phone = phone,
        quotedPrice = tonumber(payload.quotedPrice)
    }
end

local function getPrice(source)
    if GetResourceState('prime_status') ~= 'started' then
        return nil, nil, 'Hệ thống Prime chưa sẵn sàng. Vui lòng thử lại sau.'
    end

    local playerState = Player(source).state

    if playerState.isPrime == nil then
        return nil, nil, 'Trạng thái Prime đang đồng bộ. Vui lòng thử lại sau.'
    end

    local ok, isPrime = pcall(function()
        return exports.prime_status:IsPlayerPrime(source)
    end)

    if not ok then
        return nil, nil, 'Không thể kiểm tra trạng thái Prime. Vui lòng thử lại sau.'
    end

    isPrime = isPrime == true

    local price = Config.BasePrice

    if isPrime then
        price = math.floor(Config.BasePrice * (100 - Config.PrimeDiscountPercent) / 100)
    end

    return price, isPrime
end

local function refundPayment(player, cashPaid, bankPaid)
    local ok, err = pcall(function()
        if cashPaid > 0 then
            player.addAccountMoney('money', cashPaid, 'Advertisement posting refund')
        end

        if bankPaid > 0 then
            player.addAccountMoney('bank', bankPaid, 'Advertisement posting refund')
        end
    end)

    if not ok then
        print(('^1[lv_advertising]^7 Failed to refund %s: %s'):format(player.identifier or 'unknown', tostring(err)))
    end

    return ok
end

local function escapeChatText(value)
    return value:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;'):gsub("'", '&#39;')
end

local function broadcastAdvertisement(content, phone)
    local message = ('[QC] %s (%s)'):format(escapeChatText(content), escapeChatText(phone))

    if GetResourceState('custom-chat') == 'started' then
        TriggerClientEvent('custom-chat:addMessage', -1, '{19AE61}' .. message)
        return
    end

    TriggerClientEvent('chat:addMessage', -1, {
        color = { 25, 174, 97 },
        multiline = true,
        args = { message }
    })
end

lib.callback.register('lv_advertising:getQuote', function(source)
    if not databaseReady then
        return response(false, 'Hệ thống quảng cáo đang khởi tạo. Vui lòng thử lại sau.')
    end

    if not isNearNPC(source) then
        return response(false, 'Bạn không ở gần Advertisement Center.')
    end

    local price, isPrime, priceError = getPrice(source)

    if not price then
        return response(false, priceError)
    end

    return response(true, 'Đã tải giá quảng cáo.', {
        price = price,
        isPrime = isPrime
    })
end)

lib.callback.register('lv_advertising:getActive', function(source)
    if not databaseReady then
        return response(false, 'Hệ thống quảng cáo đang khởi tạo. Vui lòng thử lại sau.')
    end

    if not isNearNPC(source) then
        return response(false, 'Bạn không ở gần Advertisement Center.')
    end

    local now = os.time()
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT id, advertiser_name, phone, content, created_at, expires_at
        FROM lv_advertisements
        WHERE expires_at > ?
        ORDER BY created_at DESC, id DESC
    ]], { now })

    if not ok then
        print(('^1[lv_advertising]^7 Failed to load advertisements: %s'):format(tostring(rows)))
        return response(false, 'Không thể tải danh sách quảng cáo.')
    end

    local advertisements = {}

    for i = 1, #(rows or {}) do
        local row = rows[i]

        advertisements[#advertisements + 1] = {
            id = row.id,
            advertiserName = row.advertiser_name,
            phone = row.phone,
            content = row.content,
            createdAt = tonumber(row.created_at),
            expiresAt = tonumber(row.expires_at),
            remainingSeconds = math.max(0, tonumber(row.expires_at) - now)
        }
    end

    return response(true, 'Đã tải danh sách quảng cáo.', {
        ads = advertisements
    })
end)

lib.callback.register('lv_advertising:create', function(source, payload)
    local nowMs = GetGameTimer()

    if requestCooldown[source] and nowMs < requestCooldown[source] then
        return response(false, 'Bạn thao tác quá nhanh. Vui lòng chờ một chút.')
    end

    requestCooldown[source] = nowMs + Config.RequestCooldownMs

    if processing[source] then
        return response(false, 'Quảng cáo trước của bạn đang được xử lý.')
    end

    processing[source] = true

    local function finish(result)
        processing[source] = nil
        return result
    end

    if not databaseReady then
        return finish(response(false, 'Hệ thống quảng cáo đang khởi tạo. Vui lòng thử lại sau.'))
    end

    if not isNearNPC(source) then
        return finish(response(false, 'Bạn không ở gần Advertisement Center.'))
    end

    local advertisement, validationError = validatePayload(payload)

    if not advertisement then
        return finish(response(false, validationError))
    end

    local price, isPrime, priceError = getPrice(source)

    if not price then
        return finish(response(false, priceError))
    end

    if advertisement.quotedPrice ~= price then
        return finish(response(false, 'Giá quảng cáo đã thay đổi. Vui lòng mở lại biểu mẫu để xác nhận giá mới.'))
    end

    local player = ESX.GetPlayerFromId(source)

    if not player then
        return finish(response(false, 'Không tìm thấy dữ liệu người chơi.'))
    end

    local cashAccount = player.getAccount('money')
    local bankAccount = player.getAccount('bank')
    local cashBalance = math.max(0, cashAccount and tonumber(cashAccount.money) or 0)
    local bankBalance = math.max(0, bankAccount and tonumber(bankAccount.money) or 0)

    if cashBalance + bankBalance < price then
        return finish(response(false, ('Bạn không đủ $%d để treo quảng cáo.'):format(price)))
    end

    local cashPaid = math.min(cashBalance, price)
    local bankPaid = price - cashPaid
    local chargedCash = 0
    local chargedBank = 0

    local charged, chargeError = pcall(function()
        if cashPaid > 0 then
            player.removeAccountMoney('money', cashPaid, 'Advertisement posting')
            chargedCash = cashPaid
        end

        if bankPaid > 0 then
            player.removeAccountMoney('bank', bankPaid, 'Advertisement posting')
            chargedBank = bankPaid
        end
    end)

    if not charged then
        refundPayment(player, chargedCash, chargedBank)
        print(('^1[lv_advertising]^7 Failed to charge %s: %s'):format(player.identifier or 'unknown', tostring(chargeError)))
        return finish(response(false, 'Không thể xử lý thanh toán quảng cáo.'))
    end

    local createdAt = os.time()
    local expiresAt = createdAt + Config.AdDurationSeconds
    local inserted, advertisementId = pcall(MySQL.insert.await, [[
        INSERT INTO lv_advertisements
            (identifier, advertiser_name, phone, content, price_paid, cash_paid, bank_paid, is_prime, created_at, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        player.identifier,
        advertisement.advertiserName,
        advertisement.phone,
        advertisement.content,
        price,
        cashPaid,
        bankPaid,
        isPrime and 1 or 0,
        createdAt,
        expiresAt
    })

    if not inserted or not advertisementId then
        local refunded = refundPayment(player, cashPaid, bankPaid)
        print(('^1[lv_advertising]^7 Failed to persist advertisement for %s: %s'):format(
            player.identifier or 'unknown',
            tostring(advertisementId)
        ))
        return finish(response(
            false,
            refunded
                and 'Không thể lưu quảng cáo. Tiền đã được hoàn lại.'
                or 'Không thể lưu quảng cáo và hoàn tiền tự động. Vui lòng liên hệ quản trị viên.'
        ))
    end

    broadcastAdvertisement(advertisement.content, advertisement.phone)

    return finish(response(true, ('Đã treo quảng cáo trong 2 giờ với phí $%d.'):format(price), {
        id = advertisementId,
        price = price,
        expiresAt = expiresAt
    }))
end)

CreateThread(function()
    local ok, err = pcall(MySQL.query.await, [[
        CREATE TABLE IF NOT EXISTS lv_advertisements (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            identifier VARCHAR(80) NOT NULL,
            advertiser_name VARCHAR(100) NOT NULL,
            phone VARCHAR(32) NOT NULL,
            content VARCHAR(255) NOT NULL,
            price_paid INT UNSIGNED NOT NULL,
            cash_paid INT UNSIGNED NOT NULL DEFAULT 0,
            bank_paid INT UNSIGNED NOT NULL DEFAULT 0,
            is_prime TINYINT(1) NOT NULL DEFAULT 0,
            created_at BIGINT UNSIGNED NOT NULL,
            expires_at BIGINT UNSIGNED NOT NULL,
            PRIMARY KEY (id),
            INDEX idx_lv_advertisements_expiry (expires_at),
            INDEX idx_lv_advertisements_owner (identifier, expires_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    if not ok then
        print(('^1[lv_advertising]^7 Failed to initialize database: %s'):format(tostring(err)))
        return
    end

    databaseReady = true

    local cleanupOk, cleanupError = pcall(
        MySQL.query.await,
        'DELETE FROM lv_advertisements WHERE expires_at <= ?',
        { os.time() }
    )

    if not cleanupOk then
        print(('^1[lv_advertising]^7 Initial cleanup failed: %s'):format(tostring(cleanupError)))
    end

    print('^2[lv_advertising]^7 Advertisement database ready.')
end)

CreateThread(function()
    while true do
        Wait(Config.CleanupIntervalSeconds * 1000)

        if databaseReady then
            local ok, err = pcall(
                MySQL.query.await,
                'DELETE FROM lv_advertisements WHERE expires_at <= ?',
                { os.time() }
            )

            if not ok then
                print(('^1[lv_advertising]^7 Failed to clean expired advertisements: %s'):format(tostring(err)))
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    processing[source] = nil
    requestCooldown[source] = nil
end)
