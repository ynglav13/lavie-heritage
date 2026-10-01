local ESX = exports.es_extended:getSharedObject()
local claiming = {}
local activity = {}
local schemaReady = false

local function requiredMinutes()
    if Config.RequireOnlineTime == false then return 0 end
    return Config.RequiredOnlineMinutes or 0
end

local function antiBotEnabled()
    return Config.AntiBot == nil or Config.AntiBot.Enabled ~= false
end

local function staticChallengeMinutes()
    return (Config.AntiBot and Config.AntiBot.StaticChallengeMinutes) or Config.StaticChallengeMinutes or 10
end

local function challengeTimeoutSeconds()
    return (Config.AntiBot and Config.AntiBot.ChallengeTimeoutSeconds) or Config.ChallengeTimeoutSeconds or 75
end

local function passDays()
    return math.max(1, math.min(30, tonumber(Config.DailyPass and Config.DailyPass.Days) or 30))
end

local function dateKey(timestamp)
    return os.date('!%Y-%m-%d', timestamp + (Config.TimezoneOffsetHours * 3600))
end

local function dayNumber(key)
    if type(key) == 'number' then
        return math.floor(key / 86400)
    end

    if type(key) ~= 'string' then return nil end
    local year, month, day = key:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    if not year then return nil end
    return os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 }) // 86400
end

local function dayBit(day)
    return 1 << (day - 1)
end

local function hasDay(mask, day)
    return ((tonumber(mask) or 0) & dayBit(day)) ~= 0
end

local function addDay(mask, day)
    return (tonumber(mask) or 0) | dayBit(day)
end

local function getOnlineMinutes(identifier, today)
    return tonumber(MySQL.scalar.await([[SELECT valid_minutes FROM lv_daily_reward_activity
        WHERE identifier = ? AND activity_date = ?]], { identifier, today })) or 0
end

local function premiumAccess(source)
    local premium = Config.DailyPass and Config.DailyPass.Premium
    if not premium or premium.Enabled == false then return 0, 'none' end

    local state = Player(source).state
    if state.isPrimePlus == true then
        return (1 << passDays()) - 1, 'prime_plus'
    end

    if state.isPrime == true then
        local mask = 0
        for _, day in ipairs(premium.PrimeRewardDays or {}) do
            day = tonumber(day)
            if day and day >= 1 and day <= passDays() then
                mask = addDay(mask, day)
            end
        end
        return mask, 'prime'
    end

    return 0, 'none'
end

local function waitForSchema()
    while not schemaReady do
        Wait(50)
    end
end

local function getState(source, identifier)
    waitForSchema()

    local minutesRequired = requiredMinutes()
    local row = MySQL.single.await([[SELECT streak,
        DATE_FORMAT(last_claim_date, '%Y-%m-%d') AS last_claim_date,
        claimed_days, free_claimed_days, premium_claimed_days
        FROM lv_daily_rewards WHERE identifier = ?]], { identifier })
    local today = dateKey(os.time())
    local onlineMinutes = getOnlineMinutes(identifier, today)
    local days = passDays()
    local premiumAccessDays, premiumTier = premiumAccess(source)

    if not row then
        return {
            streak = 0,
            lastClaimDate = nil,
            claimedToday = false,
            canClaim = onlineMinutes >= minutesRequired,
            claimDay = 1,
            reset = false,
            completed = false,
            checkedDayBefore = false,
            claimedDays = 0,
            freeClaimedDays = 0,
            premiumClaimedDays = 0,
            onlineMinutes = onlineMinutes,
            requiredOnlineMinutes = minutesRequired,
            passDays = days,
            premiumUnlocked = premiumAccessDays ~= 0,
            premiumDayUnlocked = hasDay(premiumAccessDays, 1),
            premiumAccessDays = premiumAccessDays,
            premiumTier = premiumTier
        }
    end

    local lastDay, todayDay = dayNumber(row.last_claim_date), dayNumber(today)
    local claimedToday = row.last_claim_date == today
    local consecutive = lastDay and todayDay and todayDay - lastDay == 1
    local streak = math.max(0, math.min(days, tonumber(row.streak) or 0))
    local completed = streak >= days
    local claimDay

    if claimedToday or completed then
        claimDay = math.max(1, streak)
    else
        claimDay = consecutive and math.min(days, streak + 1) or 1
    end

    local claimedDays = tonumber(row.claimed_days) or 0
    local freeClaimedDays = tonumber(row.free_claimed_days) or 0
    local premiumClaimedDays = tonumber(row.premium_claimed_days) or 0
    local reset = not claimedToday and not completed and not consecutive and row.last_claim_date ~= nil

    if reset then
        claimedDays = 0
        freeClaimedDays = 0
        premiumClaimedDays = 0
    end

    local unclaimedPremiumDays = 0
    local unclaimedPremiumCount = 0
    for day = 1, days do
        if hasDay(claimedDays, day) and hasDay(premiumAccessDays, day) and not hasDay(premiumClaimedDays, day) then
            unclaimedPremiumDays = addDay(unclaimedPremiumDays, day)
            unclaimedPremiumCount = unclaimedPremiumCount + 1
        end
    end

    return {
        streak = streak,
        lastClaimDate = row.last_claim_date,
        claimedToday = claimedToday,
        canClaim = not claimedToday and not completed and onlineMinutes >= minutesRequired,
        claimDay = claimDay,
        reset = reset,
        completed = completed,
        checkedDayBefore = hasDay(claimedDays, claimDay),
        claimedDays = claimedDays,
        freeClaimedDays = freeClaimedDays,
        premiumClaimedDays = premiumClaimedDays,
        unclaimedPremiumDays = unclaimedPremiumDays,
        unclaimedPremiumCount = unclaimedPremiumCount,
        onlineMinutes = onlineMinutes,
        requiredOnlineMinutes = minutesRequired,
        passDays = days,
        premiumUnlocked = premiumAccessDays ~= 0,
        premiumDayUnlocked = hasDay(premiumAccessDays, claimDay),
        premiumAccessDays = premiumAccessDays,
        premiumTier = premiumTier
    }
end

local function notify(source, message, notifyType)
    TriggerClientEvent('lv_dailyreward:notify', source, message, notifyType or 'inform')
end

local function rewardDescription(reward)
    if reward.type == 'money' or reward.type == 'bank' then
        return ('$%s %s'):format(reward.amount, reward.label)
    end
    return ('%sx %s'):format(reward.amount, reward.label)
end

local function sendDiscordLog(source, rewards, streak, claimDay, onlineMinutes, repeatedDay)
    if Config.Webhook == '' or GetResourceState('legacyWebhook') ~= 'started' then return end

    local xPlayer = ESX.GetPlayerFromId(source)
    local rewardLines = {}
    for _, entry in ipairs(rewards) do
        rewardLines[#rewardLines + 1] = ('**%s:** %s'):format(entry.track, rewardDescription(entry.reward))
    end
    if #rewardLines == 0 then
        rewardLines[1] = '**Phần thưởng:** Không nhận lại vì mốc này đã từng điểm danh'
    end

    exports['legacyWebhook']:SendDiscordLog({
        webhook = Config.Webhook,
        username = Config.WebhookName,
        title = 'Nhận Daily Pass',
        message = ('**Người chơi:** %s\n**Identifier:** `%s`\n**Server ID:** `%s`\n**Ngày pass:** %s/%s\n%s\n**Tiến độ hiện tại:** %s ngày\n**Mốc cũ:** %s\n**Online hợp lệ hôm nay:** %s/%s phút'):format(
            xPlayer and xPlayer.getName() or GetPlayerName(source) or 'Unknown',
            xPlayer and xPlayer.identifier or 'unknown',
            source,
            claimDay,
            passDays(),
            table.concat(rewardLines, '\n'),
            streak,
            repeatedDay and 'Có' or 'Không',
            onlineMinutes,
            requiredMinutes()
        ),
        color = 16750877,
        footer = os.date('%d/%m/%Y %H:%M:%S')
    })
end

local function giveRewards(source, xPlayer, rewards)
    local inventoryRewards = {}
    local accountRewards = {}
    local magazineRewards = {}

    for _, entry in ipairs(rewards) do
        local reward = entry.reward
        local amount = tonumber(reward and reward.amount)
        if not reward or not amount or amount <= 0 then
            return false, 'Phần thưởng cấu hình không hợp lệ.'
        end

        if reward.type == 'item' then
            if not reward.item then return false, 'Phần thưởng item chưa có tên vật phẩm.' end
            inventoryRewards[#inventoryRewards + 1] = { item = reward.item, amount = amount, metadata = reward.metadata }
        elseif reward.type == 'magazine' then
            if GetResourceState('lv_Magazine') ~= 'started' then return false, 'Hệ thống băng đạn (lv_Magazine) chưa hoạt động.' end
            magazineRewards[#magazineRewards + 1] = reward
        elseif reward.type == 'gacha_crate' then
            if GetResourceState('lv_gacha') ~= 'started' then return false, 'Hệ thống gacha chưa hoạt động.' end
            local caseInfo = exports.lv_gacha:GetCaseInfo(reward.caseId)
            if not caseInfo then return false, 'Case ID trong Daily Pass không hợp lệ.' end
            inventoryRewards[#inventoryRewards + 1] = { item = caseInfo.boxItem, amount = amount, metadata = caseInfo.metadata }
        elseif reward.type == 'money' and Config.Inventory == 'ox_inventory' then
            inventoryRewards[#inventoryRewards + 1] = { item = 'money', amount = amount }
        elseif reward.type == 'money' or reward.type == 'bank' then
            accountRewards[#accountRewards + 1] = reward
        else
            return false, 'Phần thưởng cấu hình không hợp lệ.'
        end
    end

    for _, inventoryReward in ipairs(inventoryRewards) do
        if not exports.ox_inventory:CanCarryItem(source, inventoryReward.item, inventoryReward.amount, inventoryReward.metadata) then
            return false, 'Túi đồ không đủ chỗ cho phần thưởng hôm nay.'
        end
    end

    for _, magReward in ipairs(magazineRewards) do
        if not exports.ox_inventory:CanCarryItem(source, 'magazine', magReward.amount or 1) then
            return false, 'Túi đồ không đủ chỗ chứa băng đạn.'
        end
    end

    for _, inventoryReward in ipairs(inventoryRewards) do
        local success = exports.ox_inventory:AddItem(source, inventoryReward.item, inventoryReward.amount, inventoryReward.metadata)
        if not success then
            return false, 'Không thể thêm phần thưởng vào túi đồ.'
        end
    end

    for _, magReward in ipairs(magazineRewards) do
        local magType = magReward.magType or magReward.item or 'magazine-9mm'
        local ok = exports.lv_Magazine:GiveMagazine(source, magType, magReward.amount or 1, magReward.metadata)
        if not ok then
            return false, 'Không thể phát băng đạn.'
        end
    end

    for _, reward in ipairs(accountRewards) do
        if reward.type == 'bank' then
            xPlayer.addAccountMoney('bank', reward.amount)
        else
            xPlayer.addMoney(reward.amount)
        end
    end

    return true
end

ESX.RegisterServerCallback('lv_dailyreward:getState', function(source, cb)
    if Config.Enabled == false then return cb(nil) end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return cb(nil) end
    cb(getState(source, xPlayer.identifier))
end)

RegisterNetEvent('lv_dailyreward:activity', function(hasInput, pauseOpen)
    if Config.Enabled == false or Config.RequireOnlineTime == false then return end

    local source = source
    local state = activity[source] or { static = 0 }
    state.active = hasInput == true
    state.paused = pauseOpen == true
    state.heartbeat = os.time()
    activity[source] = state
end)

RegisterNetEvent('lv_dailyreward:challengeResult', function(nonce, answer)
    local source = source
    local state = activity[source]
    if not state or state.challengeNonce ~= nonce or os.time() > (state.challengeExpires or 0) then return end

    local expectedAnswer = state.challengeAnswer
    state.challengeNonce, state.challengeCode, state.challengeExpires = nil, nil, nil
    state.challengeAnswer = nil
    if tostring(answer) == tostring(expectedAnswer) then
        state.challengePassedAt = os.time()
        state.static = 0
        state.blockedUntilMove = false
    else
        state.blockedUntilMove = true
    end
end)

RegisterNetEvent('lv_dailyreward:claim', function()
    if Config.Enabled == false then
        notify(source, 'Hệ thống điểm danh đang tắt.', 'error')
        return
    end

    local source = source
    if claiming[source] then return end
    claiming[source] = true

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then claiming[source] = nil return end

    local state = getState(source, xPlayer.identifier)
    if not state.canClaim then
        if state.completed then
            notify(source, 'Bạn đã hoàn thành Daily Pass 30 ngày.', 'error')
        elseif state.claimedToday then
            notify(source, 'Bạn đã điểm danh hôm nay rồi.', 'error')
        else
            notify(source, ('Bạn cần online hợp lệ %s/%s phút trước khi điểm danh.'):format(
                state.onlineMinutes, state.requiredOnlineMinutes), 'error')
        end
        claiming[source] = nil
        return
    end

    local claimDay = state.claimDay
    local repeatedDay = state.checkedDayBefore
    local grantedRewards = {}
    local pastPrimeDaysToClaim = {}

    if not repeatedDay then
        local freeReward = Config.DailyPass.FreeRewards[claimDay]
        if freeReward then
            grantedRewards[#grantedRewards + 1] = { track = 'Miễn phí', reward = freeReward }
        end

        if state.premiumDayUnlocked then
            local premiumReward = Config.DailyPass.PrimeRewards[claimDay]
            if premiumReward then
                grantedRewards[#grantedRewards + 1] = { track = 'Prime', reward = premiumReward }
            end
        end
    end

    -- Automatically include any past missed Prime rewards for previously checked-in days
    for day = 1, passDays() do
        if day ~= claimDay and hasDay(state.unclaimedPremiumDays, day) then
            local pastReward = Config.DailyPass.PrimeRewards[day]
            if pastReward then
                grantedRewards[#grantedRewards + 1] = {
                    track = ('Prime (Bù Ngày %s)'):format(day),
                    reward = pastReward,
                    day = day
                }
                pastPrimeDaysToClaim[#pastPrimeDaysToClaim + 1] = day
            end
        end
    end

    if #grantedRewards > 0 then
        local given, errorMessage = giveRewards(source, xPlayer, grantedRewards)
        if not given then
            notify(source, errorMessage, 'error')
            claiming[source] = nil
            return
        end
    end

    local today = dateKey(os.time())
    local nextStreak = state.reset and 1 or math.min(passDays(), state.streak + 1)
    local claimedDays = addDay(state.claimedDays, claimDay)
    local freeClaimedDays = state.freeClaimedDays
    local premiumClaimedDays = state.premiumClaimedDays

    if not repeatedDay then
        freeClaimedDays = addDay(freeClaimedDays, claimDay)
        if state.premiumDayUnlocked then
            premiumClaimedDays = addDay(premiumClaimedDays, claimDay)
        end
    end

    for _, pastDay in ipairs(pastPrimeDaysToClaim) do
        premiumClaimedDays = addDay(premiumClaimedDays, pastDay)
    end

    MySQL.prepare.await([[INSERT INTO lv_daily_rewards
        (identifier, streak, last_claim_date, claimed_days, free_claimed_days, premium_claimed_days)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            streak = VALUES(streak),
            last_claim_date = VALUES(last_claim_date),
            claimed_days = VALUES(claimed_days),
            free_claimed_days = VALUES(free_claimed_days),
            premium_claimed_days = VALUES(premium_claimed_days)]], {
        xPlayer.identifier,
        nextStreak,
        today,
        claimedDays,
        freeClaimedDays,
        premiumClaimedDays
    })

    if #grantedRewards == 0 then
        notify(source, ('Đã điểm danh Ngày %s. Mốc này đã nhận trước đó nên không phát lại quà.'):format(claimDay), 'success')
    else
        local descriptions = {}
        for _, entry in ipairs(grantedRewards) do
            descriptions[#descriptions + 1] = ('%s: %s'):format(entry.track, rewardDescription(entry.reward))
        end
        notify(source, 'Đã nhận ' .. table.concat(descriptions, ' | '), 'success')
    end

    sendDiscordLog(source, grantedRewards, nextStreak, claimDay, state.onlineMinutes, repeatedDay)
    TriggerClientEvent('lv_dailyreward:claimed', source, getState(source, xPlayer.identifier))
    claiming[source] = nil
end)

RegisterNetEvent('lv_dailyreward:claimPastPremium', function(targetDay)
    if Config.Enabled == false then
        notify(source, 'Hệ thống điểm danh đang tắt.', 'error')
        return
    end

    local source = source
    if claiming[source] then return end
    claiming[source] = true

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then claiming[source] = nil return end

    local state = getState(source, xPlayer.identifier)
    if state.unclaimedPremiumCount <= 0 then
        notify(source, 'Bạn không có quà Prime nào cần nhận bù.', 'error')
        claiming[source] = nil
        return
    end

    local daysToClaim = {}
    targetDay = tonumber(targetDay)

    if targetDay and targetDay >= 1 and targetDay <= state.passDays then
        if hasDay(state.unclaimedPremiumDays, targetDay) then
            daysToClaim[#daysToClaim + 1] = targetDay
        else
            notify(source, ('Ngày %s không có quà Prime bù để nhận.'):format(targetDay), 'error')
            claiming[source] = nil
            return
        end
    else
        for day = 1, state.passDays do
            if hasDay(state.unclaimedPremiumDays, day) then
                daysToClaim[#daysToClaim + 1] = day
            end
        end
    end

    if #daysToClaim == 0 then
        notify(source, 'Không tìm thấy quà Prime bù hợp lệ.', 'error')
        claiming[source] = nil
        return
    end

    local grantedRewards = {}
    for _, day in ipairs(daysToClaim) do
        local reward = Config.DailyPass.PrimeRewards[day]
        if reward then
            grantedRewards[#grantedRewards + 1] = {
                track = ('Prime (Bù Ngày %s)'):format(day),
                reward = reward,
                day = day
            }
        end
    end

    if #grantedRewards == 0 then
        notify(source, 'Cấu hình quà Prime không hợp lệ.', 'error')
        claiming[source] = nil
        return
    end

    local given, errorMessage = giveRewards(source, xPlayer, grantedRewards)
    if not given then
        notify(source, errorMessage, 'error')
        claiming[source] = nil
        return
    end

    local newPremiumClaimedDays = state.premiumClaimedDays
    for _, entry in ipairs(grantedRewards) do
        newPremiumClaimedDays = addDay(newPremiumClaimedDays, entry.day)
    end

    MySQL.prepare.await([[UPDATE lv_daily_rewards
        SET premium_claimed_days = ?
        WHERE identifier = ?]], {
        newPremiumClaimedDays,
        xPlayer.identifier
    })

    local descriptions = {}
    for _, entry in ipairs(grantedRewards) do
        descriptions[#descriptions + 1] = ('%s: %s'):format(entry.track, rewardDescription(entry.reward))
    end
    notify(source, 'Đã nhận bù ' .. table.concat(descriptions, ' | '), 'success')

    sendDiscordLog(source, grantedRewards, state.streak, state.claimDay, state.onlineMinutes, true)
    TriggerClientEvent('lv_dailyreward:claimed', source, getState(source, xPlayer.identifier))
    claiming[source] = nil
end)

AddEventHandler('playerDropped', function()
    claiming[source] = nil
    activity[source] = nil
end)

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS lv_daily_rewards (
        identifier VARCHAR(80) NOT NULL,
        streak INT UNSIGNED NOT NULL DEFAULT 0,
        last_claim_date DATE DEFAULT NULL,
        claimed_days BIGINT UNSIGNED NOT NULL DEFAULT 0,
        free_claimed_days BIGINT UNSIGNED NOT NULL DEFAULT 0,
        premium_claimed_days BIGINT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (identifier)
    )]])
    MySQL.query.await([[ALTER TABLE lv_daily_rewards
        ADD COLUMN IF NOT EXISTS claimed_days BIGINT UNSIGNED NOT NULL DEFAULT 0]])
    MySQL.query.await([[ALTER TABLE lv_daily_rewards
        ADD COLUMN IF NOT EXISTS free_claimed_days BIGINT UNSIGNED NOT NULL DEFAULT 0]])
    MySQL.query.await([[ALTER TABLE lv_daily_rewards
        ADD COLUMN IF NOT EXISTS premium_claimed_days BIGINT UNSIGNED NOT NULL DEFAULT 0]])
    MySQL.update.await([[UPDATE lv_daily_rewards
        SET claimed_days = CAST(POW(2, LEAST(streak, 30)) - 1 AS UNSIGNED),
            free_claimed_days = CAST(POW(2, LEAST(streak, 30)) - 1 AS UNSIGNED)
        WHERE streak > 0 AND claimed_days = 0 AND free_claimed_days = 0]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS lv_daily_reward_activity (
        identifier VARCHAR(80) NOT NULL,
        activity_date DATE NOT NULL,
        valid_minutes SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (identifier, activity_date)
    )]])
    schemaReady = true
end)

CreateThread(function()
    waitForSchema()

    while true do
        Wait((Config.ActivityTickSeconds or 60) * 1000)
        if Config.Enabled == false or Config.RequireOnlineTime == false then goto continue end

        for _, playerId in ipairs(GetPlayers()) do
            local source = tonumber(playerId)
            local xPlayer = ESX.GetPlayerFromId(source)
            local state = activity[source] or { static = 0 }
            local ped = GetPlayerPed(source)
            local coords = ped ~= 0 and GetEntityCoords(ped) or nil
            local moved = coords and state.lastCoords and #(coords - state.lastCoords) >= 1.5 or false
            if moved then
                state.static, state.blockedUntilMove = 0, false
            else
                state.static = (state.static or 0) + 1
            end
            state.lastCoords = coords

            local playerState = Player(source).state
            local valid = xPlayer and ped ~= 0 and GetEntityHealth(ped) > 0 and not state.paused and
                os.time() - (state.heartbeat or 0) <= 90 and state.active and not playerState.isAFK and
                not state.blockedUntilMove and not state.challengeNonce

            local challengeMinutes = staticChallengeMinutes()
            if antiBotEnabled() and state.static >= challengeMinutes and not state.challengeNonce and
                os.time() - (state.challengePassedAt or 0) > challengeMinutes * 60 then
                state.challengeAnswer = math.random(1000, 9999)
                state.challengeNonce = ('%s:%s:%s'):format(source, os.time(), math.random(10000, 99999))
                state.challengeExpires = os.time() + challengeTimeoutSeconds()
                TriggerClientEvent('lv_dailyreward:challenge', source, state.challengeNonce, state.challengeAnswer)
                valid = false
            elseif state.challengeNonce and os.time() > state.challengeExpires then
                state.challengeNonce, state.challengeAnswer, state.challengeExpires = nil, nil, nil
                state.blockedUntilMove = true
            end

            if valid then
                local today = dateKey(os.time())
                MySQL.update.await([[INSERT INTO lv_daily_reward_activity (identifier, activity_date, valid_minutes)
                    VALUES (?, ?, 1) ON DUPLICATE KEY UPDATE valid_minutes = valid_minutes + 1]], {
                    xPlayer.identifier,
                    today
                })
                TriggerClientEvent('lv_dailyreward:progress', source)
            end
            activity[source] = state
        end

        ::continue::
    end
end)
