local recoveryLocks = {}

local function sendRecoveryLog(playerId, action)
    if GetResourceState('legacyWebhook') ~= 'started' then
        return
    end

    local xPlayer = ESX.GetPlayerFromId(playerId)

    if not xPlayer then
        return
    end

    local normalizedAction = tostring(action or ''):lower()
    local isRespawn = normalizedAction == 'respawn'
    local fee = isRespawn
        and math.max(0, math.floor(tonumber(InjuryConfig.RespawnMe.Fine) or 0))
        or math.max(0, math.floor(tonumber(InjuryConfig.SkipEMS.Fine) or 0))
    local ped = GetPlayerPed(playerId)
    local coords = ped and ped > 0 and GetEntityCoords(ped) or nil
    local location = coords
        and ('%.2f, %.2f, %.2f'):format(coords.x, coords.y, coords.z)
        or 'Không xác định'
    local title = isRespawn and 'Người chơi sử dụng /respawnme' or 'Người chơi sử dụng /skipems'
    local status = isRespawn and 'Dead' or 'Injured/Helpup'
    local inventoryPolicy = isRespawn and 'Đã xóa vật phẩm theo chính sách respawn' or 'Không xóa hành trang'
    local webhook = InjuryConfig.Webhook and (InjuryConfig.Webhook.Recovery or InjuryConfig.Webhook.Kill) or nil
    local identifier = tostring(xPlayer.identifier or 'unknown')
    local playerName = xPlayer.getName and xPlayer.getName() or GetPlayerName(playerId) or 'Unknown'

    CreateThread(function()
        local payload =
        {
            title = title,
            message = ('**Người chơi:** %s\n**Identifier:** `%s`\n**Server ID:** `%s`\n**Trạng thái hợp lệ:** `%s`\n**Viện phí:** `$%s`\n**Hành trang:** %s\n**Vị trí sử dụng:** `%s`'):format(
                playerName,
                identifier,
                playerId,
                status,
                fee,
                inventoryPolicy,
                location
            ),
            color = isRespawn and 15158332 or 16753920,
            username = 'Lavie Injury Logs',
            category = 'injury',
            action = isRespawn and 'respawnme' or 'skipems',
            idempotencyKey = ('injury:recovery:%s:%s:%s'):format(identifier, normalizedAction, GetGameTimer()),
            player = playerId,
            context =
            {
                identifier = identifier,
                mode = normalizedAction,
                fee = fee,
                location = location,
            },
        }

        if type(webhook) == 'string' and webhook ~= '' then
            payload.webhook = webhook
        end

        local ok, err = pcall(function()
            return exports.legacyWebhook:SendDiscordLog(payload)
        end)

        if not ok then
            print(('[lavie_injury] Recovery log failed for player %s: %s'):format(playerId, tostring(err)))
        end
    end)
end

local respawnKeepItems =
{
    'money',
    'phone',
    'yphone_natural',
    'yphone_black',
    'yphone_white',
    'yphone_blue',
    'yflip_mint',
    'yflip_gold',
    'yflip_graphite',
    'yflip_lavender',
    'y24_black',
    'y24_silver',
    'y24_violet',
    'y24_yellow',
    'yfold_black',
    'yphone_fold_black',
    'ys_sim_card',
    'yboomer_black',
    'boombox_black',
    'boombox_red',
    'boombox_gold',
    'boombox_mini',
    'speaker_small',
    'speaker_large',
}

local respawnKeepLookup = {}

for index = 1, #respawnKeepItems do
    respawnKeepLookup[respawnKeepItems[index]] = true
end

local function response(ok, code, extra)
    local result = type(extra) == 'table' and extra or {}
    result.ok = ok == true
    result.code = code
    return result
end

local function chargeCash(playerId, amount)
    amount = tonumber(amount)

    if not amount or amount ~= amount or amount == math.huge or amount == -math.huge or amount < 0 then
        return false, 'invalid_fee'
    end

    amount = math.floor(amount)

    if amount == 0 then
        return true
    end

    local ok, count = pcall(function()
        return exports.ox_inventory:GetItemCount(playerId, 'money')
    end)

    if not ok or tonumber(count) == nil then
        return false, 'charge_failed'
    end

    count = tonumber(count)

    if count < amount then
        return false, 'insufficient_cash'
    end

    local removeOk, removed, reason = pcall(function()
        return exports.ox_inventory:RemoveItem(playerId, 'money', amount)
    end)

    if not removeOk or removed ~= true then
        return false, reason or 'charge_failed'
    end

    return true
end

local function refundCash(playerId, amount, expectedIdentifier)
    if amount <= 0 then
        return true
    end

    local lastError = 'refund_failed'

    for attempt = 1, 3 do
        local xPlayer = ESX.GetPlayerFromId(playerId)

        if not xPlayer or expectedIdentifier and xPlayer.identifier ~= expectedIdentifier then
            lastError = 'player_changed'
            break
        end

        local ok, added, reason = pcall(function()
            return exports.ox_inventory:AddItem(playerId, 'money', amount)
        end)

        if ok and added == true then
            return true
        end

        lastError = tostring(reason or added or 'refund_failed'):sub(1, 96)

        if attempt < 3 then
            Wait(attempt * 100)
        end
    end

    print(('[lavie_injury] Recovery refund failed for player %s: %s'):format(playerId, lastError))
    return false, lastError
end

local function failureWithRefund(playerId, identifier, amount, code, extra)
    local refunded, refundError = refundCash(playerId, amount, identifier)

    if not refunded then
        extra = type(extra) == 'table' and extra or {}
        extra.cause = code
        extra.refundError = refundError
        return response(false, 'refund_failed', extra)
    end

    return response(false, code, extra)
end

local function getInventoryItems(playerId)
    local ok, items = pcall(function()
        return exports.ox_inventory:GetInventoryItems(playerId)
    end)

    if not ok or type(items) ~= 'table' then
        return nil
    end

    return items
end

local function inventoryMatchesRespawnPolicy(playerId)
    local items = getInventoryItems(playerId)

    if not items then
        return false
    end

    for _, item in pairs(items) do
        if type(item) ~= 'table' or not respawnKeepLookup[item.name] then
            return false
        end
    end

    return true
end

local function performRecovery(playerId, action, requestOptions)
    requestOptions = type(requestOptions) == 'table' and requestOptions or {}

    local originalPlayer = ESX.GetPlayerFromId(playerId)
    local originalIdentifier = originalPlayer and originalPlayer.identifier

    if not originalIdentifier then
        return response(false, 'invalid_player')
    end

    local status, state, ready, readyReason = InjuryServer.GetPlayerStatus(playerId)
    local statusVersion = state and tonumber(state.Version)
    local now = os.time()

    if not ready then
        return response(false, readyReason or 'not_ready', {status = status})
    end

    if action == 'respawn' then
        if status ~= 3 then
            return response(false, 'requires_dead', {status = status})
        end
    elseif action == 'skipems' then
        if status ~= 1 and status ~= 2 then
            return response(false, 'requires_injury', {status = status})
        end
    else
        return response(false, 'invalid_action', {status = status})
    end

    local eligibleAt = state and tonumber(state.EligibleAt) or 0

    if not requestOptions.bypassEligibility and now < eligibleAt then
        return response(false, 'not_eligible',
        {
            status = status,
            eligibleAt = eligibleAt,
            remaining = eligibleAt - now,
        })
    end

    if action == 'respawn' and not getInventoryItems(playerId) then
        return response(false, 'inventory_clear_failed', {status = status})
    end

    local fee = action == 'respawn'
        and math.max(0, math.floor(tonumber(InjuryConfig.RespawnMe.Fine) or 0))
        or math.max(0, math.floor(tonumber(InjuryConfig.SkipEMS.Fine) or 0))
    local charged, chargeReason = chargeCash(playerId, fee)

    if not charged then
        return response(false, chargeReason,
        {
            status = status,
            fee = fee,
        })
    end

    local currentPlayer = ESX.GetPlayerFromId(playerId)

    if not currentPlayer or currentPlayer.identifier ~= originalIdentifier then
        return failureWithRefund(playerId, originalIdentifier, fee, 'player_changed', {status = status, fee = fee})
    end

    local chargedStatus, chargedState = InjuryServer.GetPlayerStatus(playerId)

    if chargedStatus ~= status or not chargedState or tonumber(chargedState.Version) ~= statusVersion then
        return failureWithRefund(playerId, originalIdentifier, fee, 'recovery_superseded', {status = chargedStatus, fee = fee})
    end

    if action == 'respawn' then
        local clearOk, clearResult = pcall(function()
            return exports.ox_inventory:ClearInventory(playerId, respawnKeepItems)
        end)

        local policyApplied = inventoryMatchesRespawnPolicy(playerId)

        if not policyApplied then
            return failureWithRefund(playerId, originalIdentifier, fee, 'inventory_clear_failed',
            {
                status = status,
                fee = fee,
                clearError = not clearOk and 'clear_failed' or clearResult == false and 'clear_rejected' or nil,
            })
        end
    end

    currentPlayer = ESX.GetPlayerFromId(playerId)

    if not currentPlayer or currentPlayer.identifier ~= originalIdentifier then
        return failureWithRefund(playerId, originalIdentifier, fee, 'player_changed', {status = status, fee = fee})
    end

    local currentStatus, currentState = InjuryServer.GetPlayerStatus(playerId)

    if currentStatus ~= status or not currentState or tonumber(currentState.Version) ~= statusVersion then
        return failureWithRefund(playerId, originalIdentifier, fee, 'recovery_superseded', {status = currentStatus, fee = fee})
    end

    local options

    if action == 'respawn' then
        options =
        {
            mode = 'respawn',
            reason = requestOptions.reason or 'self_respawn',
            coords = InjuryConfig.RespawnMe.Coords,
            heading = InjuryConfig.RespawnMe.Heading,
            health = 200,
            clearBodyDamage = true,
            allowHealthy = true,
            expectedStatus = status,
            expectedVersion = statusVersion,
        }
    else
        options =
        {
            mode = 'skipems',
            reason = requestOptions.reason or 'skip_ems',
            coords = InjuryConfig.SkipEMS.Coords,
            heading = InjuryConfig.SkipEMS.Heading,
            health = 150,
            clearBodyDamage = true,
            allowHealthy = true,
            expectedStatus = status,
            expectedVersion = statusVersion,
        }
    end

    local revived, recovery, committed = InjuryServer.RevivePlayer(playerId, options)

    if not revived then
        if committed then
            return response(false, recovery or 'recovery_failed', {status = status, fee = fee, committed = true})
        end

        return failureWithRefund(playerId, originalIdentifier, fee, recovery or 'recovery_failed', {status = status, fee = fee})
    end

    return
    {
        ok = true,
        action = action,
        coords = recovery.coords,
        heading = recovery.heading,
        health = recovery.health,
        armor = recovery.armor,
    }
end

local function runRecovery(playerId, action, requestOptions)
    playerId = tonumber(playerId)

    local xPlayer = playerId and ESX.GetPlayerFromId(playerId) or nil

    if not xPlayer then
        return response(false, 'invalid_player')
    end

    if recoveryLocks[playerId] then
        return response(false, 'busy')
    end

    local lock =
    {
        identifier = xPlayer.identifier,
    }

    recoveryLocks[playerId] = lock

    local ok, result = xpcall(function()
        return performRecovery(playerId, tostring(action or ''):lower(), requestOptions)
    end, debug.traceback)

    if recoveryLocks[playerId] == lock then
        recoveryLocks[playerId] = nil
    end

    if not ok then
        print(('[lavie_injury] Recovery request failed for player %s'):format(playerId))
        return response(false, 'internal_error')
    end

    return result
end

lib.callback.register('Injury:server:RequestRecovery', function(source, action)
    local normalizedAction = tostring(action or ''):lower()
    local result = runRecovery(source, normalizedAction)

    if result and result.ok == true and (normalizedAction == 'respawn' or normalizedAction == 'skipems') then
        sendRecoveryLog(source, normalizedAction)
    end

    return result
end)

exports('ForceRespawnPlayer', function(target, reason)
    return runRecovery(target, 'respawn',
    {
        bypassEligibility = true,
        reason = tostring(reason or 'trusted_force_respawn'):sub(1, 96),
    })
end)

lib.callback.register('Injury:callback:GetPlayerDamages', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)

    if not xPlayer then
        return
    end

    local damages = {}

    if DamageServer and type(DamageServer.GetPlayerDamages) == 'function' then
        local ok, responseData = pcall(function()
            return DamageServer.GetPlayerDamages(source)
        end)

        if ok and type(responseData) == 'table' then
            damages = responseData
        end
    else
        local value = MySQL.scalar.await('SELECT bodydamages FROM users WHERE identifier = ?', {xPlayer.identifier})

        if type(value) == 'string' and value ~= '' then
            local ok, decoded = pcall(json.decode, value)

            if ok and type(decoded) == 'table' then
                damages = decoded
            end
        end
    end

    return xPlayer.getName(), os.time(), damages
end)
