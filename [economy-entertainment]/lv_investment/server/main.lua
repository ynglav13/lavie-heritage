local ESX = exports.es_extended:getSharedObject()
local contracts = {}
local activity = {}
local locks = {}
local requestCooldown = {}
local packages = {}

for _, package in ipairs(Config.Packages) do
    packages[package.id] = package
end

local function getIdentifier(source)
    local player = ESX.GetPlayerFromId(source)
    return player and player.identifier, player
end

local function isNearNPC(source)
    local ped = GetPlayerPed(source)

    if ped == 0 then
        return false
    end
    return #(GetEntityCoords(ped) - Config.NPC.coords.xyz) <= Config.InteractionDistance
end

local function logEvent(source, contractId, action, amount, metadata)
    local identifier, player = getIdentifier(source)

    identifier = identifier or (metadata and metadata.identifier) or 'unknown'

    MySQL.insert('INSERT INTO investment_logs (contract_id, identifier, player_name, action, amount, metadata) VALUES (?, ?, ?, ?, ?, ?)',
    {
        contractId, identifier, player and player.getName() or GetPlayerName(source) or 'offline', action, amount or 0,
        json.encode(metadata or {})
    })

    if ServerConfig.DiscordWebhook ~= '' and legacyCore and legacyCore.Discord then
        local color = 'green'

        if action:find('DENIED') or action:find('FAILED') or action:find('TIMEOUT') then
            color = 'red'
        elseif action:find('PAUSED') or action == 'CANCEL' then
            color = 'orange'
        elseif action == 'COMPLETED' or action:find('SENT') or action == 'ACTIVITY_RESUMED' then
            color = 'blue'
        end

        local details = {}

        table.insert(details, ('**Người Chơi:** %s'):format(player and player.getName() or GetPlayerName(source) or 'offline'))
        table.insert(details, ('**Identifier:** `%s`'):format(identifier))
        
        if contractId then
            table.insert(details, ('**ID Hợp Đồng:** `%s`'):format(contractId))
        end

        if action == 'PURCHASE' then
            local pkgLabel = metadata and metadata.package and packages[metadata.package] and packages[metadata.package].label or (metadata and metadata.package) or 'N/A'

            table.insert(details, ('**Gói Mua:** %s'):format(pkgLabel))
            table.insert(details, ('**Số Tiền Gốc:** $%s'):format(amount or 0))

            if metadata and metadata.balanceBefore and metadata.balanceAfter then
                table.insert(details, ('**Số Dư Tài Khoản:** $%s -> $%s'):format(metadata.balanceBefore, metadata.balanceAfter))
            end
        elseif action == 'PURCHASE_DENIED' then
            local pkgLabel = metadata and metadata.package and packages[metadata.package] and packages[metadata.package].label or (metadata and metadata.package) or 'N/A'

            table.insert(details, ('**Gói Muốn Mua:** %s'):format(pkgLabel))

            local reasonText = 'Không xác định'

            if metadata and metadata.reason then
                if metadata.reason == 'invalid_request' then reasonText = 'Yêu cầu không hợp lệ hoặc không ở gần NPC' end
            end

            table.insert(details, ('**Lý Do Từ Chối:** %s'):format(reasonText))
        elseif action == 'CLAIM' then
            table.insert(details, ('**Số Tiền Nhận Thưởng:** $%s'):format(amount or 0))
            
            if metadata and metadata.balanceBefore and metadata.balanceAfter then
                table.insert(details, ('**Số Dư Tài Khoản:** $%s -> $%s'):format(metadata.balanceBefore, metadata.balanceAfter))
            end
        elseif action == 'CANCEL' then
            table.insert(details, ('**Số Tiền Hoàn Trả (%s%%):** $%s'):format(Config.CancelRefundPercent, amount or 0))
            
            if metadata and metadata.balanceBefore and metadata.balanceAfter then
                table.insert(details, ('**Số Dư Tài Khoản:** $%s -> $%s'):format(metadata.balanceBefore, metadata.balanceAfter))
            end
        elseif action == 'COMPLETED' then
            table.insert(details, ('**Số Tiền Thưởng Chờ Nhận:** $%s'):format(amount or 0))
        elseif action == 'AFK_CHALLENGE_SENT' then
            if metadata and metadata.code then
                table.insert(details, ('**Mã Xác Thực (Captcha):** `%s`'):format(metadata.code))
            end

            if metadata and metadata.timeout then
                table.insert(details, ('**Thời Gian Chờ Phản Hồi:** %s giây'):format(metadata.timeout))
            end

            table.insert(details, '*Hệ thống phát hiện người chơi đứng im quá lâu gửi Captcha yêu cầu xác thực*')
        elseif action == 'AFK_CHALLENGE_PASSED' then
            if metadata and metadata.code then
                table.insert(details, ('**Mã xác thực đã nhập:** `%s` (Chính xác)'):format(metadata.code))
            end
        elseif action == 'AFK_CHALLENGE_FAILED' then
            if metadata and metadata.code and metadata.answer then
                table.insert(details, ('**Mã Đúng / Mã Đã Nhập:** `%s` / `%s` (Sai)'):format(metadata.code, metadata.answer))
            end

            table.insert(details, '*Người chơi nhập sai mã xác thực AFK. Bị tạm dừng tính giờ đầu tư*')
        elseif action == 'AFK_CHALLENGE_TIMEOUT' then
            table.insert(details, '*Người chơi không nhập mã xác thực AFK đúng hạn. Bị tạm dừng tính giờ đầu tư*')
        elseif action == 'ACTIVITY_PAUSED' then
            if metadata then
                local reasons = {}

                if metadata.afkState then
                    table.insert(reasons, 'Trạng thái AFK (Hệ thống)')
                end

                if metadata.pauseOpen then
                    table.insert(reasons, 'Mở menu ESC/Pause')
                end

                if not metadata.recentInput then
                    table.insert(reasons, 'Không có thao tác bàn phím')
                end

                if metadata.staticMinutes and metadata.staticMinutes >= Config.StaticChallengeMinutes then
                    table.insert(reasons, ('Đứng im quá lâu (%s phút)'):format(metadata.staticMinutes))
                end

                table.insert(details, ('**Lý Do Tạm Dừng:** %s'):format(#reasons > 0 and table.concat(reasons, ', ') or 'Không có thao tác hợp lệ'))
            end
        elseif action == 'ACTIVITY_RESUMED' then
            table.insert(details, '*Người chơi đã hoạt động trở lại. Tiếp tục tính giờ đầu tư*')
        else
            if amount and amount > 0 then
                table.insert(details, ('**Số Tiền:** $%s'):format(amount))
            end
        end

        legacyCore.Discord.Log(
        {
            webhook = ServerConfig.DiscordWebhook,
            name = ServerConfig.DiscordName,
            color = color,
            title = action,
            content = table.concat(details, '\n')
        })
    end
end


local function rateLimited(source)
    local now = GetGameTimer()

    if requestCooldown[source] and now - requestCooldown[source] < 1500 then
        return true
    end

    requestCooldown[source] = now
    return false
end

local function loadContract(source)
    local identifier = getIdentifier(source)

    if not identifier then
        return
    end

    local row = MySQL.single.await([[SELECT * FROM investment_contracts WHERE identifier = ? AND status IN ('active', 'completed') ORDER BY id DESC LIMIT 1]],
    {
        identifier
    })

    contracts[source] = row

    activity[source] = activity[source] or
    {
        active = false,
        paused = false,
        static = 0,
        lastCoords = nil
    }
end

local function response(ok, message)
    return
    {
        ok = ok,
        type = ok and 'success' or 'error',
        message = message
    }
end

lib.callback.register('lv_investment:getState', function(source)
    loadContract(source)

    local contract = contracts[source]

    if not contract then
        return
        {
            contract = nil
        }
    end

    local package = packages[contract.package_id]
    return
    {
        contract =
        {
            id = contract.id,
            label = package and package.label or contract.package_id,
            principal = contract.principal,
            payout = contract.payout,
            active_minutes = contract.active_minutes,
            required_minutes = contract.required_minutes,
            status = contract.status
        }
    }
end)

lib.callback.register('lv_investment:purchase', function(source, packageId)
    if rateLimited(source) then
        return response(false, 'Bạn thao tác quá nhanh')
    end

    if locks[source] then
        return response(false, 'Thao tác đang được xử lý')
    end

    locks[source] = true

    local identifier, player = getIdentifier(source)
    local package = packages[tostring(packageId)]

    if not player or not package or not isNearNPC(source) then
        logEvent(source, nil, 'PURCHASE_DENIED', 0,
        {
            package = packageId,
            reason = 'invalid_request'
        })

        locks[source] = nil
        return response(false, 'Yêu cầu không hợp lệ')
    end

    if contracts[source] then
        locks[source] = nil
        return response(false, 'Bạn đang có một hợp đồng đầu tư')
    end

    local account = player.getAccount(Config.Account)

    if not account or account.money < package.principal then
        locks[source] = nil

        local msg = Config.Account == 'bank' and 'Tài khoản ngân hàng không đủ tiền' or 'Bạn không đủ tiền mặt'
        return response(false, msg)
    end

    local existing = MySQL.scalar.await("SELECT id FROM investment_contracts WHERE identifier = ? AND status IN ('active', 'completed') LIMIT 1",
    {
        identifier
    })
    
    if existing then
        loadContract(source)

        locks[source] = nil
        return response(false, 'Bạn đang có một hợp đồng đầu tư')
    end

    local balanceBefore = account.money

    player.removeAccountMoney(Config.Account, package.principal, 'investment-purchase')

    local id = MySQL.insert.await([[INSERT INTO investment_contracts (identifier, package_id, principal, payout, required_minutes, active_minutes, status) VALUES (?, ?, ?, ?, ?, 0, 'active')]],
    {
        identifier,
        package.id,
        package.principal,
        package.payout,
        package.requiredMinutes
    })

    if not id then
        player.addAccountMoney(Config.Account, package.principal, 'investment-purchase-rollback')

        locks[source] = nil

        return response(false, 'Không thể tạo hợp đồng. Tiền đã được hoàn lại')
    end

    loadContract(source)

    logEvent(source, id, 'PURCHASE', package.principal,
    {
        package = package.id, balanceBefore = balanceBefore, balanceAfter = balanceBefore - package.principal
    })

    locks[source] = nil
    return response(true, ('Đã mua %s thành công. AFK không được tính giờ. Dùng lệnh /checkdautu để theo dõi tiến độ'):format(package.label))
end)

lib.callback.register('lv_investment:claim', function(source)
    if rateLimited(source) then
        return response(false, 'Bạn thao tác quá nhanh')
    end

    if locks[source] then
        return response(false, 'Thao tác đang được xử lý')
    end

    locks[source] = true

    local _, player = getIdentifier(source)
    local contract = contracts[source]

    if not player or not contract or contract.status ~= 'completed' or not isNearNPC(source) then
        locks[source] = nil
        return response(false, 'Hợp đồng chưa đủ điều kiện nhận tiền')
    end

    local changed = MySQL.update.await("UPDATE investment_contracts SET status = 'claimed', claimed_at = NOW() WHERE id = ? AND status = 'completed'",
    {
        contract.id
    })

    if changed ~= 1 then
        loadContract(source)

        locks[source] = nil
        return response(false, 'Hợp đồng đã được xử lý trước đó')
    end

    local balanceBefore = player.getAccount(Config.Account).money

    player.addAccountMoney(Config.Account, contract.payout, 'investment-payout')

    logEvent(source, contract.id, 'CLAIM', contract.payout,
    {
        balanceBefore = balanceBefore, balanceAfter = balanceBefore + contract.payout
    })

    contracts[source] = nil

    locks[source] = nil
    return response(true, ('Bạn đã nhận $%d từ hợp đồng đầu tư'):format(contract.payout))
end)

lib.callback.register('lv_investment:cancel', function(source)
    if rateLimited(source) then
        return response(false, 'Bạn thao tác quá nhanh')
    end

    if locks[source] then
        return response(false, 'Thao tác đang được xử lý')
    end

    locks[source] = true

    local _, player = getIdentifier(source)
    local contract = contracts[source]

    if not player or not contract or contract.status ~= 'active' or not isNearNPC(source) then
        locks[source] = nil
        return response(false, 'Không thể hủy hợp đồng này')
    end

    local refund = math.floor(contract.principal * Config.CancelRefundPercent / 100)
    local changed = MySQL.update.await("UPDATE investment_contracts SET status = 'cancelled', cancelled_at = NOW() WHERE id = ? AND status = 'active'",
    {
        contract.id
    })

    if changed ~= 1 then
        loadContract(source)

        locks[source] = nil
        return response(false, 'Hợp đồng đã được xử lý trước đó')
    end

    local balanceBefore = player.getAccount(Config.Account).money

    player.addAccountMoney(Config.Account, refund, 'investment-cancel-refund')

    logEvent(source, contract.id, 'CANCEL', refund,
    {
        balanceBefore = balanceBefore,
        balanceAfter = balanceBefore + refund
    })

    contracts[source] = nil

    locks[source] = nil
    return response(true, ('Đã hủy hợp đồng và hoàn $%d'):format(refund))
end)

RegisterNetEvent('lv_investment:activity', function(hasInput, pauseOpen)
    local source = source
    local state = activity[source] or
    {
        static = 0
    }

    state.active = hasInput == true
    state.paused = pauseOpen == true
    state.heartbeat = os.time()

    activity[source] = state
end)

RegisterNetEvent('lv_investment:challengeResult', function(nonce, answer)
    local state = activity[source]

    if not state or state.challengeNonce ~= nonce or os.time() > (state.challengeExpires or 0) then
        return
    end

    if tostring(answer) == tostring(state.challengeCode) then
        state.challengePassedAt = os.time()
        state.static = 0

        logEvent(source, contracts[source] and contracts[source].id, 'AFK_CHALLENGE_PASSED', 0,
        {
            code = state.challengeCode,
            answer = answer
        })
    else
        state.blockedUntilMove = true

        logEvent(source, contracts[source] and contracts[source].id, 'AFK_CHALLENGE_FAILED', 0,
        {
            code = state.challengeCode,
            answer = answer
        })
    end

    state.challengeNonce, state.challengeCode, state.challengeExpires = nil, nil, nil
end)

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS investment_contracts (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            identifier VARCHAR(80) NOT NULL,
            package_id VARCHAR(40) NOT NULL,
            principal INT UNSIGNED NOT NULL,
            payout INT UNSIGNED NOT NULL,
            required_minutes INT UNSIGNED NOT NULL,
            active_minutes INT UNSIGNED NOT NULL DEFAULT 0,
            status ENUM('active','completed','claimed','cancelled','frozen') NOT NULL DEFAULT 'active',
            started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            completed_at TIMESTAMP NULL DEFAULT NULL,
            claimed_at TIMESTAMP NULL DEFAULT NULL,
            cancelled_at TIMESTAMP NULL DEFAULT NULL,
            PRIMARY KEY (id), INDEX idx_investment_owner (identifier, status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS investment_logs (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            contract_id BIGINT UNSIGNED NULL,
            identifier VARCHAR(80) NOT NULL,
            player_name VARCHAR(100) NULL,
            action VARCHAR(40) NOT NULL,
            amount INT NOT NULL DEFAULT 0,
            metadata JSON NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id), INDEX idx_investment_log_owner (identifier, created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS investment_activity_daily (
            contract_id BIGINT UNSIGNED NOT NULL,
            activity_date DATE NOT NULL,
            valid_minutes INT UNSIGNED NOT NULL DEFAULT 0,
            afk_minutes INT UNSIGNED NOT NULL DEFAULT 0,
            suspicious_minutes INT UNSIGNED NOT NULL DEFAULT 0,
            PRIMARY KEY (contract_id, activity_date)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    for _, id in ipairs(GetPlayers()) do
        loadContract(tonumber(id))
    end
end)

AddEventHandler('esx:playerLoaded', function(playerId) loadContract(playerId) end)
AddEventHandler('playerDropped', function()
    contracts[source],
    activity[source],
    locks[source],
    requestCooldown[source] = nil, nil, nil, nil
end)

CreateThread(function()
    while true do
        Wait(Config.TickSeconds * 1000)

        for source, contract in pairs(contracts) do
            if contract.status == 'active' and GetPlayerPing(source) > 0 then
                local state = activity[source] or
                {
                    static = 0
                }
                local ped = GetPlayerPed(source)
                local coords = ped ~= 0 and GetEntityCoords(ped) or nil
                local moved = coords and state.lastCoords and #(coords - state.lastCoords) >= 1.5 or false

                if moved then
                    state.static,
                    state.blockedUntilMove = 0,
                    false
                else
                    state.static = (state.static or 0) + 1
                end

                state.lastCoords = coords

                local afkState = Player(source).state
                local valid = ped ~= 0 and GetEntityHealth(ped) > 0 and not state.paused and
                    os.time() - (state.heartbeat or 0) <= 90 and state.active and not afkState.isAFK and
                    not state.blockedUntilMove and not state.challengeNonce

                if state.static >= Config.StaticChallengeMinutes and not state.challengeNonce and
                    os.time() - (state.challengePassedAt or 0) > Config.StaticChallengeMinutes * 60 then

                    state.challengeCode = math.random(1000, 9999)
                    state.challengeNonce = ('%s:%s:%s'):format(source, os.time(), math.random(10000, 99999))
                    state.challengeExpires = os.time() + Config.ChallengeTimeoutSeconds

                    TriggerClientEvent('lv_investment:challenge', source, state.challengeNonce, state.challengeCode, Config.ChallengeTimeoutSeconds)

                    valid = false

                    logEvent(source, contract.id, 'AFK_CHALLENGE_SENT', 0,
                    {
                        code = state.challengeCode,
                        timeout = Config.ChallengeTimeoutSeconds
                    })
                elseif state.challengeNonce and os.time() > state.challengeExpires then
                    state.challengeNonce, state.challengeCode, state.challengeExpires = nil, nil, nil
                    state.blockedUntilMove = true

                    logEvent(source, contract.id, 'AFK_CHALLENGE_TIMEOUT')
                end

                local minuteColumn = valid and 'valid_minutes' or
                    ((afkState.isAFK or state.paused or not state.active) and 'afk_minutes' or 'suspicious_minutes')

                MySQL.update.await(([[INSERT INTO investment_activity_daily (contract_id, activity_date, %s)
                    VALUES (?, CURRENT_DATE(), 1) ON DUPLICATE KEY UPDATE %s = %s + 1]]):format(
                    minuteColumn, minuteColumn, minuteColumn
                ),
                {
                    contract.id
                })

                if state.wasValid ~= nil and state.wasValid ~= valid then
                    logEvent(source, contract.id, valid and 'ACTIVITY_RESUMED' or 'ACTIVITY_PAUSED', 0,
                    {
                        afkState = afkState.isAFK == true,
                        pauseOpen = state.paused == true,
                        recentInput = state.active == true,
                        staticMinutes = state.static
                    })
                end

                state.wasValid = valid

                if valid then
                    local changed = MySQL.update.await([[UPDATE investment_contracts SET active_minutes = active_minutes + 1,
                        status = IF(active_minutes >= required_minutes, 'completed', status),
                        completed_at = IF(active_minutes >= required_minutes, NOW(), completed_at)
                        WHERE id = ? AND status = 'active']],
                    {
                        contract.id
                    })
                    
                    if changed == 1 then
                        contract.active_minutes = contract.active_minutes + 1

                        if contract.active_minutes >= contract.required_minutes then
                            contract.status = 'completed'

                            logEvent(source, contract.id, 'COMPLETED', contract.payout)

                            TriggerClientEvent('ox_lib:notify', source,
                            {
                                type = 'success',
                                title = Config.Text.title,
                                description = 'Hợp đồng đã hoàn thành. Hãy đến NPC để nhận tiền'
                            })
                        end
                    end
                end

                activity[source] = state
            end
        end
    end
end)

RegisterCommand('checkdautu', function(source, args, rawCommand)
    if source == 0 then
        return
    end

    local contract = contracts[source]

    if not contract then
        TriggerClientEvent('custom-chat:addMessage', source, '{FF6347}[Đầu Tư]{FFFFFF} Bạn hiện không có hợp đồng đầu tư nào đang hoạt động')
        return
    end

    local package = packages[contract.package_id]
    local progress = math.min(100, math.floor((contract.active_minutes / contract.required_minutes) * 100))
    local statusText = contract.status == 'completed' and '{00FF00}Đã hoàn thành (Hãy gặp NPC nhận tiền){FFFFFF}' or '{33AA33}Đang Chạy{FFFFFF}'

    local message = ('{33AA33}[Investment]{FFFFFF} Gói: {33AA33}%s{FFFFFF} | Tiến Độ: {33AA33}%d/%d phút (%d%%){FFFFFF} | Trạng Thái: %s'):format(
        package and package.label or contract.package_id,
        contract.active_minutes,
        contract.required_minutes,
        progress,
        statusText
    )
    
    TriggerClientEvent('custom-chat:addMessage', source, message)
end, false)
