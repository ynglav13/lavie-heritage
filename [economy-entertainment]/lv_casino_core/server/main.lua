local offers = {}
local requestTimes = {}
local requestSequence = 0
local playerLocks = {}
local casinoDuty = {}
local economyReady = false
local economyUnavailableMessage = 'Kinh tế casino chưa sẵn sàng. Vui lòng liên hệ quản lý.'

local function withPlayerLock(playerId, callback)
    if playerLocks[playerId] then return false, 'Giao dịch trước đang được xử lý.' end
    playerLocks[playerId] = true
    local result = table.pack(pcall(callback))
    playerLocks[playerId] = nil
    if not result[1] then
        print(('[lv_casino_core] Transaction error for player %s: %s'):format(playerId, tostring(result[2])))
        return false, 'Không thể xử lý giao dịch.'
    end
    return table.unpack(result, 2, result.n)
end

local function secureRandomInt(minimum, maximum)
    minimum = tonumber(minimum)
    maximum = tonumber(maximum)
    if not minimum or not maximum or minimum % 1 ~= 0 or maximum % 1 ~= 0 or maximum < minimum then return nil end
    local range = maximum - minimum + 1
    if range > 4294967296 then return nil end
    local limit = 4294967296 - 4294967296 % range
    for _ = 1, 16 do
        local file = io.open('/dev/urandom', 'rb')
        local bytes
        if file then
            bytes = file:read(4)
            file:close()
        else
            local ok, hex = pcall(function() return MySQL.scalar.await('SELECT HEX(RANDOM_BYTES(4))') end)
            if ok and type(hex) == 'string' and #hex == 8 then
                local value = tonumber(hex, 16)
                if value and value < limit then return minimum + value % range end
            end
        end
        if bytes and #bytes == 4 then
            local a, b, c, d = bytes:byte(1, 4)
            local value = ((a * 256 + b) * 256 + c) * 256 + d
            if value < limit then return minimum + value % range end
        end
    end
end

local function integer(value, minimum, maximum)
    value = tonumber(value)
    if not value or value % 1 ~= 0 then return nil end
    value = math.floor(value)
    if minimum and value < minimum then return nil end
    if maximum and value > maximum then return nil end
    return value
end

local function chipCashValue(chipAmount)
    chipAmount = integer(chipAmount)
    local chipRate = integer(CasinoConfig.ChipRate, 1)
    if not chipAmount or not chipRate or math.abs(chipAmount) > math.floor(9007199254740991 / chipRate) then return nil end
    return chipAmount * chipRate
end

local function notify(playerId, message, notifyType)
    TriggerClientEvent('lv_notify:client:notify', playerId, {title = 'Diamond Casino', message = message, type = notifyType or 'info', duration = 4200})
end

local function throttled(playerId, key, delay)
    local now = GetGameTimer()
    local token = ('%s:%s'):format(playerId, key)
    if requestTimes[token] and now - requestTimes[token] < delay then return true end
    requestTimes[token] = now
    return false
end

local function playerByIdentifier(identifier)
    for _, playerId in ipairs(GetPlayers()) do
        local xPlayer = ESX.GetPlayerFromId(tonumber(playerId))
        if xPlayer and xPlayer.identifier == identifier then return xPlayer end
    end
end

local function ownedItemSlot(playerId, itemName)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then return nil end
    local slots = exports.ox_inventory:GetSlotsWithItem(playerId, itemName) or {}
    for i = 1, #slots do
        local metadata = slots[i].metadata or {}
        if metadata.identifier == xPlayer.identifier then return slots[i] end
    end
end

local function hasAccess(playerId, tier)
    if tier == 'vip' then return ownedItemSlot(playerId, CasinoConfig.VipItem) ~= nil end
    return ownedItemSlot(playerId, CasinoConfig.MemberItem) ~= nil or ownedItemSlot(playerId, CasinoConfig.VipItem) ~= nil
end

local function chipBalance(playerId)
    return integer(exports.ox_inventory:Search(playerId, 'count', CasinoConfig.ChipItem), 0) or 0
end

local function bankBalance(xPlayer)
    local account = xPlayer and xPlayer.getAccount('bank')
    return account and math.floor(tonumber(account.money) or 0) or 0
end

local function cashOutAmounts(chipAmount)
    local gross = chipCashValue(tonumber(chipAmount) or 0)
    if not gross then return nil end
    local taxPercent = math.max(0, math.min(100, tonumber(CasinoConfig.CashOutTaxPercent) or 0))
    local tax = math.floor(gross * taxPercent / 100)
    return gross, tax, gross - tax, taxPercent
end

local function requestId(prefix, playerId)
    requestSequence = requestSequence + 1
    return ('casino:%s:%s:%s:%s'):format(prefix, playerId or 0, os.time(), requestSequence)
end

local function applyFinance(budgetDelta, reserveDelta, reason, playerId, id)
    if not economyReady then return false end
    return exports.factionCore:ApplyFactionFinance(CasinoConfig.BusinessTag, {
        budgetDelta = budgetDelta,
        reserveDelta = reserveDelta,
        reason = reason,
        sourcePlayerId = playerId,
        requestId = id
    })
end

local function serviceStaffOnDuty()
    for _, playerId in ipairs(GetPlayers()) do
        playerId = tonumber(playerId)
        if casinoDuty[playerId] == true then
            if exports.factionCore:HasPlayerBusinessPermission(playerId, CasinoConfig.BusinessTag, CasinoConfig.Permissions.cashier)
                or exports.factionCore:HasPlayerBusinessPermission(playerId, CasinoConfig.BusinessTag, CasinoConfig.Permissions.membership) then
                return true
            end
        end
    end
    return false
end

local function ledger(playerId, action, amount, status, game, roundId, context)
    context = context or {}
    local xPlayer = playerId and ESX.GetPlayerFromId(playerId) or nil
    local identifier = xPlayer and xPlayer.identifier or context and context.identifier or nil
    local ledgerRequestId = context.requestId or roundId or requestId(action, playerId)
    MySQL.insert.await('INSERT INTO casino_transactions (request_id, identifier, source_id, action, game, amount, status, round_id, context) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        ledgerRequestId,
        identifier,
        playerId,
        action,
        game,
        math.floor(tonumber(amount) or 0),
        status,
        roundId,
        json.encode(context)
    })
    if GetResourceState('legacyWebhook') == 'started' then
        local ok, accepted = pcall(function()
            return exports.legacyWebhook:AuditTransaction({
                username = 'Diamond Casino Logs',
                route = 'casino',
                category = 'casino',
                action = action,
                status = status,
                sourceResource = GetCurrentResourceName(),
                requestId = ledgerRequestId,
                idempotencyKey = ledgerRequestId,
                player = xPlayer and {
                    id = playerId,
                    name = xPlayer.getName(),
                    identifier = xPlayer.identifier,
                    license = GetPlayerIdentifierByType(playerId, 'license')
                } or nil,
                account = context.account,
                itemName = context.itemName,
                amount = math.floor(tonumber(amount) or 0),
                delta = context.delta,
                balanceBefore = context.balanceBefore,
                balanceAfter = context.balanceAfter,
                reason = game or action,
                title = 'DIAMOND CASINO • ' .. string.upper(action),
                message = context.auditMessage,
                context = context
            })
        end)
        if not ok or accepted ~= true then
            print(('[lv_casino_core] legacyWebhook từ chối audit %s (%s).'):format(ledgerRequestId, tostring(accepted)))
        end
    else
        print(('[lv_casino_core] Không thể ghi audit %s: legacyWebhook chưa chạy.'):format(ledgerRequestId))
    end
end

local function pendingCredit(identifier, itemName, amount, metadata, reason, creditKey)
    creditKey = type(creditKey) == 'string' and creditKey:sub(1, 191) or requestId('credit', 0)
    return MySQL.insert.await('INSERT IGNORE INTO casino_pending_credits (credit_key, identifier, item_name, amount, metadata, reason, status) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        creditKey,
        identifier,
        itemName,
        amount,
        json.encode(metadata or {}),
        reason,
        'pending'
    })
end

local function deliverPending(playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then return end
    local rows = MySQL.query.await('SELECT id, item_name, amount, metadata FROM casino_pending_credits WHERE identifier = ? AND status = ? ORDER BY id', {xPlayer.identifier, 'pending'}) or {}
    for i = 1, #rows do
        local claimed = MySQL.update.await('UPDATE casino_pending_credits SET status = ? WHERE id = ? AND status = ?', {'delivering', rows[i].id, 'pending'})
        if claimed and claimed > 0 then
        local metadata = json.decode(rows[i].metadata or '{}') or {}
        local delivered = rows[i].item_name == '__bank__' and pcall(function() xPlayer.addAccountMoney('bank', rows[i].amount) end)
            or exports.ox_inventory:AddItem(playerId, rows[i].item_name, rows[i].amount, metadata) == true
        if delivered then
            MySQL.update.await('UPDATE casino_pending_credits SET status = ?, delivered_at = CURRENT_TIMESTAMP WHERE id = ? AND status = ?', {'delivered', rows[i].id, 'delivering'})
            notify(playerId, ('Đã nhận khoản casino còn thiếu: %s x%s.'):format(rows[i].item_name, rows[i].amount), 'success')
        else
            MySQL.update.await('UPDATE casino_pending_credits SET status = ? WHERE id = ? AND status = ?', {'pending', rows[i].id, 'delivering'})
        end
        end
    end
end

local function addChips(playerId, amount, reason, id, reserveAlreadyApplied)
    amount = integer(amount, 1, 2000000000)
    local cashValue = amount and chipCashValue(amount) or nil
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not economyReady or not amount or not cashValue or not xPlayer then return false end
    if not reserveAlreadyApplied then
        local changed = applyFinance(0, cashValue, reason, playerId, id)
        if not changed then return false end
    end
    local added = exports.ox_inventory:AddItem(playerId, CasinoConfig.ChipItem, amount)
    if not added then pendingCredit(xPlayer.identifier, CasinoConfig.ChipItem, amount, {}, reason, id and id .. ':credit') end
    return true
end

local function removeChips(playerId, amount, reason, id, reserveAlreadyApplied)
    amount = integer(amount, 1, 2000000000)
    local cashValue = amount and chipCashValue(amount) or nil
    if not economyReady or not amount or not cashValue or not hasAccess(playerId, 'member') or chipBalance(playerId) < amount then return false end
    if not exports.ox_inventory:RemoveItem(playerId, CasinoConfig.ChipItem, amount) then return false end
    if not reserveAlreadyApplied then
        local changed = applyFinance(0, -cashValue, reason, playerId, id)
        if not changed then
            exports.ox_inventory:AddItem(playerId, CasinoConfig.ChipItem, amount)
            return false
        end
    end
    return true
end

local function performMembership(playerId, vip, staffId)
    if not economyReady then return false, economyUnavailableMessage end
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then return false, 'Không tìm thấy người chơi.' end
    local currentVip = ownedItemSlot(playerId, CasinoConfig.VipItem)
    local currentMember = ownedItemSlot(playerId, CasinoConfig.MemberItem)
    if vip and currentVip then return false, 'Bạn đã có thẻ VIP.' end
    if not vip and (currentMember or currentVip) then return false, 'Bạn đã có thẻ thành viên.' end
    local price = vip and CasinoConfig.VipPrice or CasinoConfig.MemberPrice
    if bankBalance(xPlayer) < price then return false, 'Tài khoản ngân hàng không đủ tiền.' end
    local itemName = vip and CasinoConfig.VipItem or CasinoConfig.MemberItem
    local metadata = {identifier = xPlayer.identifier, holder = xPlayer.getName(), issuedAt = os.date('%Y-%m-%d'), description = vip and 'Thẻ VIP Diamond Casino' or 'Thẻ thành viên Diamond Casino'}
    local canCarry = currentMember and vip
        and exports.ox_inventory:CanSwapItem(playerId, CasinoConfig.MemberItem, 1, CasinoConfig.VipItem, 1)
        or exports.ox_inventory:CanCarryItem(playerId, itemName, 1, metadata)
    if not canCarry then return false, 'Túi đồ không đủ chỗ.' end
    xPlayer.removeAccountMoney('bank', price)
    if currentMember and vip and not exports.ox_inventory:RemoveItem(playerId, CasinoConfig.MemberItem, 1, currentMember.metadata, currentMember.slot) then
        xPlayer.addAccountMoney('bank', price)
        return false, 'Không thể thu hồi thẻ Member.'
    end
    local id = requestId(vip and 'vip' or 'member', playerId)
    local changed = applyFinance(price, 0, vip and 'VIP membership sale' or 'Membership sale', staffId or playerId, id)
    if not changed then
        if currentMember and vip then exports.ox_inventory:AddItem(playerId, CasinoConfig.MemberItem, 1, currentMember.metadata, currentMember.slot) end
        xPlayer.addAccountMoney('bank', price)
        return false, 'Không thể cập nhật quỹ doanh nghiệp.'
    end
    if not exports.ox_inventory:AddItem(playerId, itemName, 1, metadata) then
        pendingCredit(xPlayer.identifier, itemName, 1, metadata, 'Casino membership delivery', id .. ':credit')
    end
    ledger(playerId, vip and 'membership_vip' or 'membership_member', price, 'committed', nil, nil, {requestId = id, staffId = staffId, replacedMember = vip and currentMember ~= nil or nil})
    if vip and currentMember then return true, ('Đã thu hồi thẻ Member và cấp thẻ VIP Diamond Casino với giá $%s.'):format(CasinoConfig.VipPrice) end
    return true, vip and ('Đã cấp thẻ VIP Diamond Casino với giá $%s.'):format(CasinoConfig.VipPrice) or 'Đã cấp thẻ thành viên Diamond Casino.'
end

local function performChipExchange(playerId, buying, amount, staffId)
    if not economyReady then return false, economyUnavailableMessage end
    amount = integer(amount, 1, CasinoConfig.MaxCashierAmount)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not amount or not xPlayer then return false, 'Số lượng không hợp lệ.' end
    if not hasAccess(playerId, 'member') then return false, 'Bạn cần thẻ thành viên hợp lệ.' end
    local grossValue, taxAmount, netValue, taxPercent = cashOutAmounts(amount)
    if not grossValue then return false, 'Số lượng chip vượt giới hạn an toàn.' end
    local balanceBefore = bankBalance(xPlayer)
    local id = requestId(buying and 'buy-chips' or 'sell-chips', playerId)
    if buying then
        if bankBalance(xPlayer) < grossValue then return false, 'Tài khoản ngân hàng không đủ tiền.' end
        if not exports.ox_inventory:CanCarryItem(playerId, CasinoConfig.ChipItem, amount) then return false, 'Túi đồ không đủ chỗ.' end
        xPlayer.removeAccountMoney('bank', grossValue)
        local changed = applyFinance(grossValue, grossValue, 'Casino chip sale', staffId or playerId, id)
        if not changed then
            xPlayer.addAccountMoney('bank', grossValue)
            return false, 'Không thể cập nhật quỹ doanh nghiệp.'
        end
        if not exports.ox_inventory:AddItem(playerId, CasinoConfig.ChipItem, amount) then
            pendingCredit(xPlayer.identifier, CasinoConfig.ChipItem, amount, {}, 'Casino chip delivery', id .. ':credit')
        end
    else
        if chipBalance(playerId) < amount then return false, 'Bạn không có đủ chip.' end
        if not exports.ox_inventory:RemoveItem(playerId, CasinoConfig.ChipItem, amount) then return false, 'Không thể thu hồi chip.' end
        local changed = applyFinance(-netValue, -grossValue, 'Casino chip redemption', staffId or playerId, id)
        if not changed then
            exports.ox_inventory:AddItem(playerId, CasinoConfig.ChipItem, amount)
            return false, 'Quỹ khả dụng không đủ để đổi chip.'
        end
        xPlayer.addAccountMoney('bank', netValue)
    end
    ledger(playerId, buying and 'chips_buy' or 'chips_sell', amount, 'committed', nil, nil, {
        requestId = id,
        account = 'bank',
        itemName = CasinoConfig.ChipItem,
        grossCashValue = grossValue,
        taxPercent = buying and 0 or taxPercent,
        taxAmount = buying and 0 or taxAmount,
        netCashValue = buying and grossValue or netValue,
        delta = buying and -grossValue or netValue,
        balanceBefore = balanceBefore,
        balanceAfter = bankBalance(xPlayer),
        staffId = staffId,
        auditMessage = buying
            and ('Mua %s chip với giá $%s.'):format(amount, grossValue)
            or ('Đổi %s chip: tổng $%s, thuế %s%% ($%s), thực nhận $%s.'):format(amount, grossValue, taxPercent, taxAmount, netValue)
    })
    return true, buying and ('Đã mua %s chip với giá $%s.'):format(amount, grossValue)
        or ('Đã đổi %s chip, nhận $%s sau thuế %s%% ($%s).'):format(amount, netValue, taxPercent, taxAmount)
end

local function performAction(playerId, action, amount, staffId)
    if action == 'buy_chips' then return performChipExchange(playerId, true, amount, staffId) end
    if action == 'sell_chips' then return performChipExchange(playerId, false, amount, staffId) end
    if action == 'buy_member' then return performMembership(playerId, false, staffId) end
    if action == 'buy_vip' then return performMembership(playerId, true, staffId) end
    return false, 'Giao dịch không hợp lệ.'
end

local function openRoundUnsafe(playerId, game, roundId, bet, maxPayout)
    if not economyReady then return false end
    bet = integer(bet, 1, 2000000000)
    maxPayout = integer(maxPayout, 0, 2000000000)
    roundId = type(roundId) == 'string' and roundId:sub(1, 191) or nil
    game = type(game) == 'string' and game:sub(1, 40) or nil
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer or not bet or not maxPayout or not roundId or not game or not hasAccess(playerId, 'member') then return false end
    if MySQL.scalar.await('SELECT 1 FROM casino_rounds WHERE round_id = ?', {roundId}) then return false end
    if chipBalance(playerId) < bet then return false end
    local inserted = MySQL.insert.await('INSERT INTO casino_rounds (round_id, game, identifier, source_id, bet, max_payout, status) VALUES (?, ?, ?, ?, ?, ?, ?)', {roundId, game, xPlayer.identifier, playerId, bet, maxPayout, 'preparing'})
    if not inserted then return false end
    if not exports.ox_inventory:RemoveItem(playerId, CasinoConfig.ChipItem, bet) then
        MySQL.update.await('UPDATE casino_rounds SET status = ? WHERE round_id = ?', {'rejected', roundId})
        return false
    end
    MySQL.update.await('UPDATE casino_rounds SET status = ? WHERE round_id = ? AND status = ?', {'debited', roundId, 'preparing'})
    local id = 'round-open:' .. roundId
    local reserveDelta = chipCashValue(maxPayout - bet)
    if not reserveDelta then
        pendingCredit(xPlayer.identifier, CasinoConfig.ChipItem, bet, {}, 'Casino round conversion rollback', 'round:' .. roundId .. ':conversion-rollback')
        deliverPending(playerId)
        MySQL.update.await('UPDATE casino_rounds SET status = ? WHERE round_id = ?', {'rejected', roundId})
        return false
    end
    local changed = applyFinance(0, reserveDelta, ('Open %s round'):format(game), playerId, id)
    if not changed then
        pendingCredit(xPlayer.identifier, CasinoConfig.ChipItem, bet, {}, 'Casino round open rollback', 'round:' .. roundId .. ':open-rollback')
        deliverPending(playerId)
        MySQL.update.await('UPDATE casino_rounds SET status = ? WHERE round_id = ?', {'rejected', roundId})
        return false
    end
    MySQL.update.await('UPDATE casino_rounds SET status = ?, opened_at = CURRENT_TIMESTAMP WHERE round_id = ?', {'active', roundId})
    ledger(playerId, 'round_open', bet, 'committed', game, roundId, {requestId = id, maxPayout = maxPayout})
    return true
end

local function openRound(playerId, game, roundId, bet, maxPayout)
    return withPlayerLock(playerId, function()
        return openRoundUnsafe(playerId, game, roundId, bet, maxPayout)
    end)
end

local function settleRound(roundId, payout)
    payout = integer(payout, 0, 2000000000)
    if type(roundId) ~= 'string' or not payout then return false end
    local round = MySQL.single.await('SELECT * FROM casino_rounds WHERE round_id = ? AND status IN (?, ?, ?)', {roundId, 'active', 'settling', 'settled'})
    if not round or payout > tonumber(round.max_payout) then return false end
    if round.status == 'settled' then
        return tonumber(round.payout) == payout
    elseif round.status == 'active' then
        local claimed = MySQL.update.await('UPDATE casino_rounds SET status = ?, payout = ? WHERE round_id = ? AND status = ?', {'settling', payout, roundId, 'active'})
        if not claimed or claimed < 1 then return false end
    elseif tonumber(round.payout) ~= payout then
        return false
    end
    local xPlayer = playerByIdentifier(round.identifier)
    local playerId = xPlayer and xPlayer.source or tonumber(round.source_id)
    local id = 'round-settle:' .. roundId
    local reserveDelta = chipCashValue(payout - tonumber(round.max_payout))
    if not reserveDelta then return false end
    local changed = applyFinance(0, reserveDelta, ('Settle %s round'):format(round.game), playerId, id)
    if not changed then
        MySQL.update.await('UPDATE casino_rounds SET status = ? WHERE round_id = ? AND status = ?', {'active', roundId, 'settling'})
        return false
    end
    if payout > 0 then
        pendingCredit(round.identifier, CasinoConfig.ChipItem, payout, {}, 'Casino round payout', 'round:' .. roundId .. ':payout')
    end
    local affected = MySQL.update.await('UPDATE casino_rounds SET status = ?, settled_at = CURRENT_TIMESTAMP WHERE round_id = ? AND status = ?', {'settled', roundId, 'settling'})
    if not affected or affected < 1 then return false end
    if xPlayer and payout > 0 then deliverPending(xPlayer.source) end
    ledger(playerId, 'round_settle', payout, 'committed', round.game, roundId, {requestId = id, identifier = round.identifier, bet = round.bet})
    return true
end

local function cancelRound(roundId, restoreDailySpin)
    if type(roundId) ~= 'string' then return false end
    local round = MySQL.single.await('SELECT * FROM casino_rounds WHERE round_id = ? AND status IN (?, ?)', {roundId, 'active', 'cancelling'})
    if not round then return false end
    if round.status == 'active' then
        local claimed = MySQL.update.await('UPDATE casino_rounds SET status = ? WHERE round_id = ? AND status = ?', {'cancelling', roundId, 'active'})
        if not claimed or claimed < 1 then return false end
    end
    local player = playerByIdentifier(round.identifier)
    local playerId = player and player.source or tonumber(round.source_id)
    local id = 'round-cancel:' .. roundId
    local reserveDelta = tonumber(round.bet) - tonumber(round.max_payout)
    if round.game ~= 'wheel' then reserveDelta = chipCashValue(reserveDelta) end
    if not reserveDelta then return false end
    local changed = applyFinance(0, reserveDelta, ('Cancel %s round'):format(round.game), playerId, id)
    if not changed then
        MySQL.update.await('UPDATE casino_rounds SET status = ? WHERE round_id = ? AND status = ?', {'active', roundId, 'cancelling'})
        return false
    end
    if tonumber(round.bet) > 0 then
        pendingCredit(round.identifier, CasinoConfig.ChipItem, round.bet, {}, 'Casino round refund', 'round:' .. roundId .. ':refund')
    end
    local affected = MySQL.update.await('UPDATE casino_rounds SET status = ?, payout = bet, settled_at = CURRENT_TIMESTAMP WHERE round_id = ? AND status = ?', {'cancelled', roundId, 'cancelling'})
    if not affected or affected < 1 then return false end
    if player and tonumber(round.bet) > 0 then deliverPending(player.source) end
    if restoreDailySpin == true and round.game == 'wheel' then
        MySQL.update.await('DELETE FROM casino_daily_spins WHERE identifier = ? AND spin_date = DATE(?)', {round.identifier, round.created_at})
    end
    ledger(playerId, 'round_cancel', round.bet, 'rolled_back', round.game, roundId, {requestId = id, identifier = round.identifier})
    return true
end

local function weightedReward()
    local roll = secureRandomInt(1, 10000)
    if not roll then return nil end
    local cursor = 0
    for i = 1, #CasinoConfig.Wheel.Rewards do
        cursor = cursor + CasinoConfig.Wheel.Rewards[i].weight
        if roll <= cursor then return i, CasinoConfig.Wheel.Rewards[i] end
    end
    return #CasinoConfig.Wheel.Rewards, CasinoConfig.Wheel.Rewards[#CasinoConfig.Wheel.Rewards]
end

local function generatePlate()
    if GetResourceState('jg-dealerships') == 'started' then
        local ok, plate = pcall(function() return exports['jg-dealerships']:generatePlate('AAA 111', true) end)
        if ok and plate then return plate end
    end
    for _ = 1, 20 do
        local suffix = secureRandomInt(0, 99999)
        if not suffix then return nil end
        local plate = ('CAS%05d'):format(suffix)
        if not MySQL.scalar.await('SELECT plate FROM owned_vehicles WHERE plate = ?', {plate}) then return plate end
    end
end

local function ensureVehicleKey(playerId, plate)
    if GetResourceState('vehicleCore') ~= 'started' then return end
    local slots = exports.ox_inventory:GetSlotsWithItem(playerId, 'vehicle_key') or {}
    for i = 1, #slots do
        if tostring(slots[i].metadata and slots[i].metadata.plate or ''):upper() == plate:upper() then return end
    end
    exports.vehicleCore:GiveVehicleKey(playerId, plate)
end

local function grantVehicle(playerId, fixedPlate)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    local plate = xPlayer and (fixedPlate or generatePlate()) or nil
    if not plate then return false end
    local owner = MySQL.scalar.await('SELECT owner FROM owned_vehicles WHERE plate = ?', {plate})
    if owner then
        if owner ~= xPlayer.identifier then return false end
        ensureVehicleKey(playerId, plate)
        return true, plate
    end
    local properties = {model = joaat(CasinoConfig.Wheel.VehicleModel), plate = plate}
    local inserted = MySQL.insert.await('INSERT INTO owned_vehicles (owner, plate, vehicle, type, vehicleGarage, stored) VALUES (?, ?, ?, ?, ?, 1)', {xPlayer.identifier, plate, json.encode(properties), 'car', CasinoConfig.DefaultGarage})
    if not inserted then return false end
    ensureVehicleKey(playerId, plate)
    return true, plate
end

local function startWheel(playerId)
    if not economyReady then return false, economyUnavailableMessage end
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer or not hasAccess(playerId, 'member') then return false, 'Bạn cần thẻ thành viên hợp lệ.' end
    local spinDate = os.date('%Y-%m-%d')
    local claimed = MySQL.update.await('INSERT IGNORE INTO casino_daily_spins (identifier, spin_date) VALUES (?, ?)', {xPlayer.identifier, spinDate})
    if (tonumber(claimed) or 0) < 1 then return false, 'Bạn đã quay hôm nay. Hãy quay lại sau 00:00.' end
    local spinId = requestId('wheel', playerId)
    local rewardIndex, reward = weightedReward()
    if not rewardIndex or not reward then
        MySQL.update.await('DELETE FROM casino_daily_spins WHERE identifier = ? AND spin_date = ?', {xPlayer.identifier, spinDate})
        return false, 'Không thể tạo kết quả vòng quay an toàn.'
    end
    if reward.type == 'vehicle' then
        reward = {type = reward.type, amount = reward.amount, weight = reward.weight, sound = reward.sound, plate = generatePlate()}
        if not reward.plate then
            MySQL.update.await('DELETE FROM casino_daily_spins WHERE identifier = ? AND spin_date = ?', {xPlayer.identifier, spinDate})
            return false, 'Không thể chuẩn bị phần thưởng xe.'
        end
    end
    local reserved = CasinoConfig.Wheel.MaxBusinessFundedReward
    local changed = applyFinance(0, reserved, 'Lucky Wheel reserve', playerId, 'wheel-open:' .. spinId)
    if not changed then
        MySQL.update.await('DELETE FROM casino_daily_spins WHERE identifier = ? AND spin_date = ?', {xPlayer.identifier, spinDate})
        return false, 'Quỹ casino chưa đủ dự phòng để mở vòng quay.'
    end
    local inserted = MySQL.insert.await('INSERT INTO casino_rounds (round_id, game, identifier, source_id, bet, max_payout, status, context) VALUES (?, ?, ?, ?, 0, ?, ?, ?)', {spinId, 'wheel', xPlayer.identifier, playerId, reserved, 'active', json.encode({rewardIndex = rewardIndex, reward = reward})})
    if not inserted then
        applyFinance(0, -reserved, 'Lucky Wheel reserve rollback', playerId, 'wheel-open-rollback:' .. spinId)
        MySQL.update.await('DELETE FROM casino_daily_spins WHERE identifier = ? AND spin_date = ?', {xPlayer.identifier, spinDate})
        return false, 'Không thể khởi tạo vòng quay.'
    end
    return true, spinId, rewardIndex, {type = reward.type, amount = reward.amount, sound = reward.sound}
end

local function finishWheel(playerId, spinId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    local round = type(spinId) == 'string' and MySQL.single.await('SELECT * FROM casino_rounds WHERE round_id = ? AND game = ? AND status IN (?, ?)', {spinId, 'wheel', 'active', 'settling'}) or nil
    if not xPlayer or not round or round.identifier ~= xPlayer.identifier then return false end
    if round.status == 'active' then
        local claimed = MySQL.update.await('UPDATE casino_rounds SET status = ? WHERE round_id = ? AND status = ?', {'settling', spinId, 'active'})
        if not claimed or claimed < 1 then return false end
    end
    local context = json.decode(round.context or '{}') or {}
    local reward = context.reward or {}
    local reserved = tonumber(round.max_payout) or 0
    local budgetDelta = reward.type == 'bank' and -(tonumber(reward.amount) or 0) or 0
    local chipLiability = reward.type == 'chips' and chipCashValue(tonumber(reward.amount) or 0) or 0
    if reward.type == 'chips' and not chipLiability then return false end
    local reserveDelta = reward.type == 'chips' and chipLiability - reserved or -reserved
    local id = 'wheel-settle:' .. spinId
    local changed = applyFinance(budgetDelta, reserveDelta, 'Lucky Wheel reward', playerId, id)
    if not changed then
        MySQL.update.await('UPDATE casino_rounds SET status = ? WHERE round_id = ? AND status = ?', {'active', spinId, 'settling'})
        return false
    end
    local vehiclePlate
    if reward.type == 'vehicle' then
        local granted
        granted, vehiclePlate = grantVehicle(playerId, reward.plate)
        if not granted then return false end
    end
    local message = 'Chúc bạn may mắn lần sau.'
    if reward.type == 'bank' then
        pendingCredit(xPlayer.identifier, '__bank__', reward.amount, {}, 'Lucky Wheel bank reward', 'wheel:' .. spinId .. ':reward')
        message = ('Bạn nhận được $%s vào ngân hàng.'):format(reward.amount)
    elseif reward.type == 'chips' then
        pendingCredit(xPlayer.identifier, CasinoConfig.ChipItem, reward.amount, {}, 'Lucky Wheel chips', 'wheel:' .. spinId .. ':reward')
        message = ('Bạn nhận được %s chip.'):format(reward.amount)
    elseif reward.type == 'item' then
        pendingCredit(xPlayer.identifier, reward.item, reward.amount, {}, 'Lucky Wheel item', 'wheel:' .. spinId .. ':reward')
        message = reward.item == 'sandwich' and ('Bạn nhận được %s phần snack.'):format(reward.amount)
            or reward.item == 'ecola' and ('Bạn nhận được %s chai eCola.'):format(reward.amount)
            or ('Bạn nhận được %s x %s.'):format(reward.amount, reward.item)
    elseif reward.type == 'vehicle' then
        message = ('Bạn đã trúng xe %s, biển số %s.'):format(CasinoConfig.Wheel.VehicleModel, vehiclePlate)
    end
    local affected = MySQL.update.await('UPDATE casino_rounds SET status = ?, payout = ?, settled_at = CURRENT_TIMESTAMP WHERE round_id = ? AND status = ?', {'settled', tonumber(reward.amount) or 0, spinId, 'settling'})
    if not affected or affected < 1 then return false end
    if reward.type == 'bank' or reward.type == 'chips' or reward.type == 'item' then deliverPending(playerId) end
    notify(playerId, message, reward.type == 'none' and 'info' or 'success')
    ledger(playerId, 'wheel_reward', tonumber(reward.amount) or 0, 'committed', 'wheel', spinId, {
        requestId = id,
        account = reward.type == 'bank' and 'bank' or nil,
        itemName = reward.type == 'chips' and CasinoConfig.ChipItem or reward.type == 'item' and reward.item or nil,
        reward = reward,
        auditMessage = message
    })
    return true
end

local function resumeWheelRewards(playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then return end
    local rounds = MySQL.query.await('SELECT round_id FROM casino_rounds WHERE identifier = ? AND game = ? AND status = ?', {xPlayer.identifier, 'wheel', 'settling'}) or {}
    for i = 1, #rounds do finishWheel(playerId, rounds[i].round_id) end
end

local function logCasinoFinancialPosition()
    local financials = exports.factionCore:GetFactionFinancials(CasinoConfig.BusinessTag) or {}
    local budget = math.floor(tonumber(financials.budget) or 0)
    local reserved = math.floor(tonumber(financials.reserved) or 0)
    local shortfall = math.max(0, reserved - budget)
    print(('[lv_casino_core] Quỹ Casino: budget=$%s, reserve=$%s, shortfall=$%s.'):format(budget, reserved, shortfall))
    if shortfall > 0 then
        print('[lv_casino_core] Casino đang thiếu vốn. Giao dịch tài chính và lượt chơi sẽ fail closed cho đến khi budget được cấp đủ.')
    end
end

local function prepareChipLiabilityMigration()
    local definition = CasinoConfig.ChipLiabilityMigration
    local migrationId = type(definition) == 'table' and tostring(definition.key or ''):sub(1, 191) or ''
    local fromRate = type(definition) == 'table' and integer(definition.fromRate, 1) or nil
    local toRate = integer(CasinoConfig.ChipRate, 1)
    if migrationId == '' or not fromRate or not toRate or toRate % fromRate ~= 0 then
        print('[lv_casino_core] Chip liability migration config không hợp lệ; khóa kinh tế casino.')
        return false
    end

    local marker = MySQL.single.await('SELECT from_rate, to_rate, applied FROM casino_economy_migrations WHERE migration_id = ?', {migrationId})
    if marker then
        if tonumber(marker.from_rate) ~= fromRate or tonumber(marker.to_rate) ~= toRate or tonumber(marker.applied) ~= 1 then
            print(('[lv_casino_core] Migration %s có trạng thái hoặc tỷ giá không khớp; khóa kinh tế casino.'):format(migrationId))
            return false
        end
        economyReady = true
        logCasinoFinancialPosition()
        return true
    end

    if #GetPlayers() > 0 then
        print('[lv_casino_core] Migration tỷ giá yêu cầu full maintenance với toàn bộ người chơi đã thoát; khóa kinh tế casino.')
        return false
    end

    local unresolved = tonumber(MySQL.scalar.await([[
        SELECT COUNT(*) FROM casino_rounds
        WHERE status IN ('preparing', 'debited', 'active', 'settling', 'cancelling', 'review')
    ]])) or 0
    if unresolved > 0 then
        print(('[lv_casino_core] Còn %s casino round chưa đối soát; chưa áp migration và khóa kinh tế casino.'):format(unresolved))
        return false
    end

    local multiplier = toRate // fromRate
    local ok, committed = pcall(function()
        return MySQL.transaction.await({
            {
                query = [[
                    INSERT IGNORE INTO casino_economy_migrations (migration_id, from_rate, to_rate, applied)
                    VALUES (?, ?, ?, 0)
                ]],
                values = {migrationId, fromRate, toRate}
            },
            {
                query = [[
                    UPDATE faction f
                    JOIN casino_economy_migrations m ON m.migration_id = ?
                    SET f.reserved_budget = f.reserved_budget * ?,
                        m.applied = 1,
                        m.applied_at = CURRENT_TIMESTAMP
                    WHERE LOWER(f.tag) = LOWER(?)
                      AND m.from_rate = ?
                      AND m.to_rate = ?
                      AND m.applied = 0
                      AND f.reserved_budget <= FLOOR(9223372036854775807 / ?)
                ]],
                values = {migrationId, multiplier, CasinoConfig.BusinessTag, fromRate, toRate, multiplier}
            }
        })
    end)
    marker = MySQL.single.await('SELECT from_rate, to_rate, applied FROM casino_economy_migrations WHERE migration_id = ?', {migrationId})
    if not ok or committed ~= true or not marker or tonumber(marker.from_rate) ~= fromRate or tonumber(marker.to_rate) ~= toRate or tonumber(marker.applied) ~= 1 then
        print(('[lv_casino_core] Không thể áp migration %s an toàn; kiểm tra overflow/schema và khóa kinh tế casino.'):format(migrationId))
        return false
    end

    economyReady = true
    print(('[lv_casino_core] Đã đổi reserve Casino từ $%s/chip sang $%s/chip; budget không bị thay đổi.'):format(fromRate, toRate))
    logCasinoFinancialPosition()
    return true
end

MySQL.ready(function()
    MySQL.query.await('ALTER TABLE faction ADD COLUMN IF NOT EXISTS reserved_budget BIGINT NOT NULL DEFAULT 0')
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS casino_transactions (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            request_id VARCHAR(191) NOT NULL UNIQUE,
            identifier VARCHAR(80) NULL,
            source_id INT NULL,
            action VARCHAR(50) NOT NULL,
            game VARCHAR(40) NULL,
            amount BIGINT NOT NULL DEFAULT 0,
            status VARCHAR(20) NOT NULL,
            round_id VARCHAR(191) NULL,
            context LONGTEXT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_casino_identifier (identifier, created_at),
            INDEX idx_casino_round (round_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS casino_rounds (
            round_id VARCHAR(191) PRIMARY KEY,
            game VARCHAR(40) NOT NULL,
            identifier VARCHAR(80) NOT NULL,
            source_id INT NULL,
            bet BIGINT NOT NULL DEFAULT 0,
            max_payout BIGINT NOT NULL DEFAULT 0,
            payout BIGINT NOT NULL DEFAULT 0,
            status VARCHAR(20) NOT NULL,
            context LONGTEXT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            opened_at TIMESTAMP NULL,
            settled_at TIMESTAMP NULL,
            INDEX idx_casino_round_status (status, created_at),
            INDEX idx_casino_round_player (identifier, created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS casino_daily_spins (
            identifier VARCHAR(80) NOT NULL,
            spin_date DATE NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (identifier, spin_date)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS casino_pending_credits (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            credit_key VARCHAR(191) NOT NULL,
            identifier VARCHAR(80) NOT NULL,
            item_name VARCHAR(80) NOT NULL,
            amount BIGINT NOT NULL,
            metadata LONGTEXT NULL,
            reason VARCHAR(191) NULL,
            status VARCHAR(20) NOT NULL DEFAULT 'pending',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            delivered_at TIMESTAMP NULL,
            UNIQUE KEY uq_casino_credit_key (credit_key),
            INDEX idx_casino_pending (identifier, status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS casino_economy_migrations (
            migration_id VARCHAR(191) PRIMARY KEY,
            from_rate BIGINT NOT NULL,
            to_rate BIGINT NOT NULL,
            applied TINYINT(1) NOT NULL DEFAULT 0,
            applied_at TIMESTAMP NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await('ALTER TABLE casino_pending_credits ADD COLUMN IF NOT EXISTS credit_key VARCHAR(191) NULL')
    MySQL.query.await('UPDATE casino_pending_credits SET credit_key = CONCAT(?, id) WHERE credit_key IS NULL OR credit_key = ?', {'legacy:', ''})
    MySQL.query.await('ALTER TABLE casino_pending_credits MODIFY credit_key VARCHAR(191) NOT NULL')
    local creditIndex = MySQL.scalar.await('SELECT 1 FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = ? AND index_name = ? LIMIT 1', {'casino_pending_credits', 'uq_casino_credit_key'})
    if not creditIndex then MySQL.query.await('ALTER TABLE casino_pending_credits ADD UNIQUE INDEX uq_casino_credit_key (credit_key)') end
    MySQL.update.await('UPDATE casino_pending_credits SET status = ? WHERE status = ?', {'review', 'delivering'})
    local reviewCredits = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM casino_pending_credits WHERE status = ?', {'review'})) or 0
    if reviewCredits > 0 then print(('[lv_casino_core] Có %s khoản thưởng cần đối soát thủ công trước khi cấp lại.'):format(reviewCredits)) end
    MySQL.update.await([[
        INSERT INTO faction (type, tag, category, colour, image, name, rank, division, permission, locker, garage, data, items, budget, reserved_budget)
        SELECT 'business', ?, 'business', '212, 175, 55', '', ?, ?, ?, '[]', '[]', '[]', '[]', '[]', 0, 0
        WHERE NOT EXISTS (SELECT 1 FROM faction WHERE LOWER(tag) = LOWER(?))
    ]], {
        CasinoConfig.BusinessTag,
        CasinoConfig.BusinessName,
        json.encode({{id = 1, name = 'Giám đốc'}, {id = 2, name = 'Quản lý'}, {id = 3, name = 'Thu ngân'}, {id = 4, name = 'Nhân viên'}}),
        json.encode({{id = 1, name = 'Sảnh chính'}, {id = 2, name = 'Khu VIP'}, {id = 3, name = 'Tài chính'}}),
        CasinoConfig.BusinessTag
    })
    if not prepareChipLiabilityMigration() then return end
    local settling = MySQL.query.await('SELECT round_id, payout FROM casino_rounds WHERE status = ? AND game <> ?', {'settling', 'wheel'}) or {}
    for i = 1, #settling do settleRound(settling[i].round_id, settling[i].payout) end
    local cancelling = MySQL.query.await('SELECT round_id FROM casino_rounds WHERE status = ?', {'cancelling'}) or {}
    for i = 1, #cancelling do cancelRound(cancelling[i].round_id) end
    local preparing = MySQL.query.await('SELECT round_id FROM casino_rounds WHERE status = ?', {'preparing'}) or {}
    for i = 1, #preparing do
        local applied = MySQL.scalar.await('SELECT applied FROM faction_finance_requests WHERE request_id = ?', {'round-open:' .. preparing[i].round_id})
        if tonumber(applied) == 1 then
            MySQL.update.await('UPDATE casino_rounds SET status = ? WHERE round_id = ? AND status = ?', {'active', preparing[i].round_id, 'preparing'})
            cancelRound(preparing[i].round_id, true)
        else
            MySQL.update.await('UPDATE casino_rounds SET status = ? WHERE round_id = ? AND status = ?', {'review', preparing[i].round_id, 'preparing'})
        end
    end
    local debited = MySQL.query.await('SELECT round_id, game, source_id, max_payout, bet FROM casino_rounds WHERE status = ?', {'debited'}) or {}
    for i = 1, #debited do
        local reserveDelta = chipCashValue(tonumber(debited[i].max_payout) - tonumber(debited[i].bet))
        local changed = reserveDelta and applyFinance(0, reserveDelta, ('Recover %s round'):format(debited[i].game), tonumber(debited[i].source_id), 'round-open:' .. debited[i].round_id)
        if changed then
            MySQL.update.await('UPDATE casino_rounds SET status = ? WHERE round_id = ? AND status = ?', {'active', debited[i].round_id, 'debited'})
            cancelRound(debited[i].round_id, true)
        end
    end
    local active = MySQL.query.await('SELECT round_id FROM casino_rounds WHERE status = ?', {'active'}) or {}
    for i = 1, #active do
        cancelRound(active[i].round_id, true)
    end
    for _, playerId in ipairs(GetPlayers()) do
        playerId = tonumber(playerId)
        deliverPending(playerId)
        resumeWheelRewards(playerId)
    end
end)

exports('HasAccess', hasAccess)
exports('GetChipBalance', chipBalance)
exports('OpenRound', openRound)
exports('SettleRound', settleRound)
exports('CancelRound', cancelRound)
exports('AddChips', addChips)
exports('RemoveChips', removeChips)
exports('StartWheel', startWheel)
exports('FinishWheel', finishWheel)
exports('SecureRandomInt', secureRandomInt)

lib.callback.register('lv_casino:server:balance', function(source) return chipBalance(source) end)
lib.callback.register('lv_casino:server:access', function(source, tier) return hasAccess(source, tier) end)
lib.callback.register('lv_casino:server:ledger', function(source)
    if throttled(source, 'ledger', 1000) then return {throttled = true} end
    local state = Player(source).state
    if not state or tostring(state.factionTag or ''):lower() ~= CasinoConfig.BusinessTag:lower() or not exports.factionCore:HasPlayerBusinessPermission(source, CasinoConfig.BusinessTag, CasinoConfig.Permissions.ledger) then return {denied = true} end
    return {
        financials = exports.factionCore:GetFactionFinancials(CasinoConfig.BusinessTag),
        transactions = MySQL.query.await('SELECT action, amount, status, DATE_FORMAT(created_at, ?) AS created_at FROM casino_transactions ORDER BY id DESC LIMIT 30', {'%d/%m/%Y %H:%i'}) or {}
    }
end)

RegisterNetEvent('lv_casino:server:selfService', function(action, amount)
    local playerId = source
    if throttled(playerId, 'self', 750) then return end
    local interaction = (action == 'buy_member' or action == 'buy_vip') and CasinoConfig.MembershipDesk.coords.xyz or CasinoConfig.Cashier.coords.xyz
    local ped = GetPlayerPed(playerId)
    if ped == 0 or #(GetEntityCoords(ped) - interaction) > 4.0 then return end
    if serviceStaffOnDuty() then return notify(playerId, 'Đang có nhân viên trực. Vui lòng giao dịch tại quầy.', 'warning') end
    local success, message = withPlayerLock(playerId, function() return performAction(playerId, action, amount) end)
    notify(playerId, message, success and 'success' or 'error')
end)

RegisterNetEvent('lv_casino:server:createOffer', function(targetId, action, amount)
    local staffId = source
    targetId = integer(targetId, 1)
    if not targetId or targetId == staffId or not ({buy_chips = true, sell_chips = true, buy_member = true, buy_vip = true})[action] or throttled(staffId, 'offer', 750) then return end
    if action == 'buy_chips' or action == 'sell_chips' then
        amount = integer(amount, 1, CasinoConfig.MaxCashierAmount)
        if not amount then return notify(staffId, 'Số lượng chip không hợp lệ.', 'error') end
    end
    local permission = (action == 'buy_member' or action == 'buy_vip') and CasinoConfig.Permissions.membership or CasinoConfig.Permissions.cashier
    if casinoDuty[staffId] ~= true or not exports.factionCore:HasPlayerBusinessPermission(staffId, CasinoConfig.BusinessTag, permission) then return notify(staffId, 'Bạn không có quyền thực hiện giao dịch này.', 'error') end
    local staffPed = GetPlayerPed(staffId)
    local targetPed = GetPlayerPed(targetId)
    if staffPed == 0 or targetPed == 0 or #(GetEntityCoords(staffPed) - CasinoConfig.Cashier.coords.xyz) > 4.0 or #(GetEntityCoords(staffPed) - GetEntityCoords(targetPed)) > CasinoConfig.InteractionDistance then return end
    requestSequence = requestSequence + 1
    local id = ('offer:%s:%s:%s'):format(staffId, targetId, requestSequence)
    local grossValue, taxAmount, netValue, taxPercent = cashOutAmounts(amount)
    local description = action == 'buy_chips' and ('Mua %s chip casino với giá $%s?'):format(amount, grossValue)
        or action == 'sell_chips' and ('Đổi %s chip, nhận $%s sau thuế %s%% ($%s)?'):format(amount, netValue, taxPercent, taxAmount)
        or action == 'buy_member' and ('Mua thẻ Member giá $%s?'):format(CasinoConfig.MemberPrice)
        or ('Mua thẻ VIP giá $%s? Thẻ Member hiện có sẽ bị thu hồi.'):format(CasinoConfig.VipPrice)
    offers[id] = {id = id, staffId = staffId, targetId = targetId, action = action, amount = amount, expires = os.time() + 30}
    TriggerClientEvent('lv_casino:client:offer', targetId, {id = id, message = description})
    SetTimeout(31000, function()
        if offers[id] and offers[id].expires < os.time() then offers[id] = nil end
    end)
end)

RegisterNetEvent('lv_casino:server:respondOffer', function(id, accepted)
    local playerId = source
    if type(id) ~= 'string' then return end
    local offer = offers[id]
    offers[id] = nil
    if not offer or offer.targetId ~= playerId or offer.expires < os.time() then return end
    if accepted ~= true then
        notify(playerId, 'Bạn đã từ chối giao dịch.', 'info')
        return notify(offer.staffId, 'Khách hàng đã từ chối giao dịch.', 'warning')
    end
    local staffPed = GetPlayerPed(offer.staffId)
    local targetPed = GetPlayerPed(playerId)
    if staffPed == 0 or targetPed == 0 or #(GetEntityCoords(staffPed) - CasinoConfig.Cashier.coords.xyz) > 4.0 or #(GetEntityCoords(staffPed) - GetEntityCoords(targetPed)) > CasinoConfig.InteractionDistance then return notify(playerId, 'Giao dịch bị hủy vì khoảng cách không hợp lệ.', 'error') end
    local permission = (offer.action == 'buy_member' or offer.action == 'buy_vip') and CasinoConfig.Permissions.membership or CasinoConfig.Permissions.cashier
    if casinoDuty[offer.staffId] ~= true or not exports.factionCore:HasPlayerBusinessPermission(offer.staffId, CasinoConfig.BusinessTag, permission) then return notify(playerId, 'Giao dịch bị hủy vì nhân viên không còn đủ quyền.', 'error') end
    local success, message = withPlayerLock(playerId, function() return performAction(playerId, offer.action, offer.amount, offer.staffId) end)
    notify(playerId, message, success and 'success' or 'error')
    notify(offer.staffId, success and 'Giao dịch đã hoàn tất.' or message, success and 'success' or 'error')
end)

RegisterNetEvent('lv_casino:server:toggleDuty', function()
    local playerId = source
    local state = Player(playerId).state
    if not state then return end
    local ped = GetPlayerPed(playerId)
    if ped == 0 or #(GetEntityCoords(ped) - CasinoConfig.DutyDesk.coords) > 4.0 then return end
    local canWork = exports.factionCore:HasPlayerBusinessPermission(playerId, CasinoConfig.BusinessTag, CasinoConfig.Permissions.cashier)
        or exports.factionCore:HasPlayerBusinessPermission(playerId, CasinoConfig.BusinessTag, CasinoConfig.Permissions.membership)
    if not canWork then return notify(playerId, 'Bạn không có quyền bắt đầu ca casino.', 'error') end
    casinoDuty[playerId] = casinoDuty[playerId] ~= true
    state:set('factionDuty', casinoDuty[playerId], true)
    notify(playerId, casinoDuty[playerId] and 'Bạn đã bắt đầu ca làm việc.' or 'Bạn đã kết thúc ca làm việc.', casinoDuty[playerId] and 'success' or 'info')
end)

RegisterNetEvent('lv_casino:server:requestPenthouse', function(entering)
    local playerId = source
    if entering and not hasAccess(playerId, 'vip') then return notify(playerId, 'Bạn cần thẻ VIP chính chủ để vào Penthouse.', 'error') end
    local ped = GetPlayerPed(playerId)
    local origin = entering and CasinoConfig.Penthouse.lobby.xyz or CasinoConfig.Penthouse.exit.xyz
    if ped == 0 or #(GetEntityCoords(ped) - origin) > 5.0 then return end
    TriggerClientEvent('lv_casino:client:teleport', playerId, entering and CasinoConfig.Penthouse.penthouse or CasinoConfig.Penthouse.lobby, entering and 'Chào mừng đến Penthouse.' or 'Bạn đã trở về sảnh casino.')
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    SetTimeout(2000, function()
        deliverPending(playerId)
        resumeWheelRewards(playerId)
    end)
end)

AddEventHandler('playerDropped', function()
    requestTimes[source .. ':self'] = nil
    requestTimes[source .. ':offer'] = nil
    playerLocks[source] = nil
    casinoDuty[source] = nil
    for id, offer in pairs(offers) do
        if offer.staffId == source or offer.targetId == source then offers[id] = nil end
    end
end)
