local MEDKIT_PRICE = 10000

local FACTION_LOCKER_WEBHOOKS = {
    ['LSPD'] = GetConvar('faction_locker_webhook_lspd', ''),
    ['LSFD'] = GetConvar('faction_locker_webhook_lsfd', ''),
    ['LSSD'] = GetConvar('faction_locker_webhook_lssd', ''),
}

local DEFAULT_LOCKER_WEBHOOK = GetConvar('faction_locker_webhook_default', '')
local lockerRequestTimes = {}
local businessPurchaseLocks = {}

local function formatNumber(number)
    local formatted = tostring(number)
    local k
    while true do
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then
            break
        end
    end
    return formatted
end

local function getPlayerFactionTag(playerId)
    local membership = exports.factionCore:GetPlayerFactionMembership(playerId)
    return membership and membership.tag or nil
end


local function getPlayerFactionCategory(identifier)
    local result = MySQL.query.await('SELECT faction FROM users WHERE identifier = ?', {identifier})
    if result and result[1] and result[1].faction and result[1].faction ~= '' then
        local factionData = json.decode(result[1].faction)
        if factionData and factionData.name and factionData.name ~= 'Không có' then
            local faction = MySQL.query.await('SELECT category FROM faction WHERE name = ?', {factionData.name})
            if faction and faction[1] then
                return faction[1].category
            end
        end
    end
    return nil
end

local function isPlayerAuthorized(playerId, category, requireLockerPermission, skipThrottle)
    local membership = exports.factionCore:GetPlayerFactionMembership(playerId)
    if not membership then return false end
    if requireLockerPermission ~= false and not exports.factionCore:HasPlayerFactionPermission(playerId, membership.tag, 'locker') and not exports.factionCore:HasPlayerFactionPermission(playerId, membership.tag, 'gun') then return false end
    local faction = MySQL.single.await('SELECT category, locker FROM faction WHERE tag = ?', {membership.tag})
    if not faction or faction.category ~= category then return false end
    local now = GetGameTimer()
    if not skipThrottle and lockerRequestTimes[playerId] and now - lockerRequestTimes[playerId] < 500 then return false end
    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 then return false end
    local position = GetEntityCoords(ped)
    local lockers = json.decode(faction.locker or '[]') or {}
    for i = 1, #lockers do
        local coords = lockers[i].coords
        if coords and #(position - vector3(tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0)) <= 4.0 then
            if not skipThrottle then lockerRequestTimes[playerId] = now end
            return true
        end
    end
    return false
end

local function chargePlayer(playerId, amount)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then return false end

    local cash = exports.ox_inventory:Search(playerId, 'count', 'money') or 0
    if cash >= amount then
        return exports.ox_inventory:RemoveItem(playerId, 'money', amount)
    end

    local bank = xPlayer.getAccount('bank').money
    if bank >= amount then
        xPlayer.removeAccountMoney('bank', amount)
        return true
    end

    return false
end

local function createPlayerStash(playerId, badgeNum)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    local membership = exports.factionCore:GetPlayerFactionMembership(playerId)
    if not xPlayer or not membership or type(badgeNum) ~= 'string' or badgeNum == '' then return false end
    local faction = MySQL.single.await('SELECT category, locker FROM faction WHERE tag = ?', {membership.tag})
    if not faction or not isPlayerAuthorized(playerId, faction.category) then
        print(("[Security Warning] Player %s (ID: %s) tried to trigger CreateStash without authority!"):format(xPlayer.name, playerId))
        return false
    end
    local safeTag = tostring(membership.tag):gsub('[^%w_-]', '')
    local safeBadge = tostring(membership.badgeNum or ''):gsub('[^%w_-]', '')
    local safeName = tostring(xPlayer.getName() or ''):gsub('%s', '_'):gsub('[^%w_-]', '')
    if badgeNum ~= ('locker_%s_%s'):format(safeTag, safeBadge) and badgeNum ~= ('locker_%s_%s'):format(safeTag, safeName) then return false end

    local label = badgeNum
    if string.match(badgeNum, '^locker_') then
        label = badgeNum:gsub('^locker_', ''):gsub('_', ' ')
    end
    local stash = {
        id = badgeNum,
        label = label,
        slots = 50,
        weight = 100000,
        owner = false,
        coords = GetEntityCoords(GetPlayerPed(playerId))
    }
    exports.ox_inventory:RegisterStash(stash.id, stash.label, stash.slots, stash.weight, stash.owner, nil, stash.coords)
    return true
end

lib.callback.register('FactionLocker:server:CreateStash', function(source, badgeNum)
    return createPlayerStash(source, badgeNum)
end)

RegisterServerEvent('FactionLocker:server:CreateStash', function(passedPlayerId, badgeNum, tag)
    createPlayerStash(source, badgeNum)
end)

exports.ox_inventory:registerHook('openInventory', function(payload)
    local stashId = tostring(payload.inventoryId or '')
    local membership = exports.factionCore:GetPlayerFactionMembership(payload.source)
    local xPlayer = ESX.GetPlayerFromId(payload.source)
    if not membership or not xPlayer then return false end
    local safeTag = tostring(membership.tag):gsub('[^%w_-]', '')
    local safeBadge = tostring(membership.badgeNum or ''):gsub('[^%w_-]', '')
    local safeName = tostring(xPlayer.getName() or ''):gsub('%s', '_'):gsub('[^%w_-]', '')
    if stashId ~= ('locker_%s_%s'):format(safeTag, safeBadge) and stashId ~= ('locker_%s_%s'):format(safeTag, safeName) then return false end
    local faction = MySQL.single.await('SELECT category FROM faction WHERE tag = ?', {membership.tag})
    if not faction or not isPlayerAuthorized(payload.source, faction.category, true, true) then return false end
    return true
end, {inventoryFilter = {'^locker_'}, typeFilter = {stash = true}})

RegisterServerEvent('FactionLocker:server:GivePlayerTaser', function(passedPlayerId, category, data)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerTaser!'):format(GetPlayerName(playerId), playerId))
        return
    end
    if type(data) ~= 'table' then return end
    local ammoCount = tonumber(data[1])
    if ammoCount and (ammoCount % 1 ~= 0 or ammoCount < 0 or ammoCount > 20) then return end

    local text = ''
    if ammoCount and ammoCount > 0 then
        exports.ox_inventory:AddItem(playerId, 'ammo-taser', ammoCount)
        text = ('**%s viên đạn** Taser'):format(ammoCount)
    end

    if not data[2] then
        exports.ox_inventory:AddItem(playerId, 'WEAPON_STUNGUN', 1)
        text = ('**1 khẩu Taser G2** & **%s hộp đạn** Taser'):format(ammoCount or 0)
    end

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy %s từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0", text)
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Taser', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerTaserY2', function(passedPlayerId, category, data)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerTaserY2!'):format(GetPlayerName(playerId), playerId))
        return
    end
    if type(data) ~= 'table' then return end
    local ammoCount = tonumber(data[1])
    if ammoCount and (ammoCount % 1 ~= 0 or ammoCount < 0 or ammoCount > 20) then return end

    local text = ''
    if ammoCount and ammoCount > 0 then
        exports.ox_inventory:AddItem(playerId, 'ammo-taser', ammoCount)
        text = ('**%s viên đạn** Taser'):format(ammoCount)
    end

    if not data[2] then
        exports.ox_inventory:AddItem(playerId, 'WEAPON_Y2', 1)
        text = ('**1 khẩu Taser Y2** & **%s hộp đạn** Taser'):format(ammoCount or 0)
    end

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy %s từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0", text)
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Taser Y2', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerArmour', function(passedPlayerId, category)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerArmour!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'armour', 1)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 Armour** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Armour', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerColbaton', function(passedPlayerId, category)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerColbaton!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'WEAPON_COLBATON', 1)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 ProLaps Telescopic Baton** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Colbaton', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerFlashlight', function(passedPlayerId, category)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerFlashlight!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'WEAPON_FLASHLIGHT', 1)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 Flashlight** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Flashlight', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerSpraycan', function(passedPlayerId, category)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerSpraycan!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'WEAPON_SPRAYCAN', 1)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 Spraycan** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Spraycan', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerHandcuffs', function(passedPlayerId, category)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerHandcuffs!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'handcuffs', 1)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 Handcuffs** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Handcuffs', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerSpikeStrip', function(passedPlayerId, category)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerSpikeStrip!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'spike_strip', 1)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 Spike Strip** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Spike Strip', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerMegaphone', function(passedPlayerId, category)
    local playerId = source
    if category ~= 'police' or not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerMegaphone!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'megaphone', 1)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 Megaphone** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or 'Member', xPlayer.getName(), Player(playerId).state.factionBadgeNum or '0')
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Megaphone', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerSpeedLidar4', function(passedPlayerId, category)
    local playerId = source
    if category ~= 'police' or not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerSpeedLidar4!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'WEAPON_SPEEDLIDAR4', 1)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 Súng bắn tốc độ SpeedLidar 4** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or 'Member', xPlayer.getName(), Player(playerId).state.factionBadgeNum or '0')
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take SpeedLidar 4', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerZN509', function(passedPlayerId, category)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerZN509!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'WEAPON_ZN509', 1)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 ZN509** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take ZN509', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerHLTMP7', function(passedPlayerId, category)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerHLTMP7!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'WEAPON_HLTMP7', 1)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 H&L TMP7** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take H&L TMP7', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerTCarbine', function(passedPlayerId, category)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerTCarbine!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'WEAPON_TCARBINE', 1)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 H&L Tactical Carbine** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Tactical Carbine', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerAR15', function(passedPlayerId, category)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerAR15!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'WEAPON_VFCARBINE', 1)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 Vom Feuer Carbine** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Vom Feuer Carbine', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerHK416', function(passedPlayerId, category)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerHK416!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'WEAPON_SPCARBINE', 1)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 Vom Feuer Special Carbine** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Vom Feuer Special Carbine', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerM870', function(passedPlayerId, category)
    local playerId = source
    if category ~= 'police' or not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerM870!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'WEAPON_M870_SHOTGUN', 1)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 Shrewsbury E870** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Shrewsbury E870', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerBeanbag', function(passedPlayerId, category)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerBeanbag!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'WEAPON_BEANBAG', 1)
    exports.ox_inventory:AddItem(playerId, 'ammo-beanbag', 10)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 Beanbag & 10 viên đạn** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Beanbag', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerYBeanbag', function(passedPlayerId, category)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerYBeanbag!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'WEAPON_YBEANBAG', 1)
    exports.ox_inventory:AddItem(playerId, 'ammo-beanbag', 10)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 Yellow Beanbag & 10 viên đạn** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Yellow Beanbag', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerLessLauncher', function(passedPlayerId, category)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerLessLauncher!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'WEAPON_LESSLAUNCHER', 1)
    exports.ox_inventory:AddItem(playerId, 'ammo-40mm', 5)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 Less Launcher & 5 viên đạn** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Less Launcher', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerYLessLauncher', function(passedPlayerId, category)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerYLessLauncher!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'WEAPON_YLESSLAUNCHER', 1)
    exports.ox_inventory:AddItem(playerId, 'ammo-40mm', 5)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 Yellow Less Launcher & 5 viên đạn** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Yellow Less Launcher', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerMagazine', function(passedPlayerId, category, magType, magLabel)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerMagazine!'):format(GetPlayerName(playerId), playerId))
        return
    end

    local magazines = {['magazine-9mm'] = '9mm', ['magazine-pdw'] = '4.6mm', ['magazine-rifle'] = '5.56mm', ['magazine-rifle2'] = '7.62mm'}
    magType = magType or 'magazine-9mm'
    magLabel = magazines[magType]
    if not magLabel then return end

    local currentCount = exports.ox_inventory:Search(playerId, 'count', magType) or 0
    if currentCount >= 3 then
        TriggerClientEvent('lv_notify:client:notify', playerId, {
            title = 'Tủ đồ',
            message = 'Bạn đã sở hữu tối đa 3 băng đạn trong người',
            type = 'error'
        })
        return
    end

    local giveAmount = 3 - currentCount
    exports.lv_Magazine:GiveMagazine(playerId, magType, giveAmount)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **%s Băng đạn %s** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0", giveAmount, magLabel)
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Magazine', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerAmmo', function(passedPlayerId, category, amount, ammoType, ammoLabel)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerAmmo!'):format(GetPlayerName(playerId), playerId))
        return
    end

    local ammo = {['ammo-9'] = '9mm', ['ammo-pdw'] = '4.6mm', ['ammo-rifle'] = '5.56mm', ['ammo-rifle2'] = '7.62mm', ['ammo-beanbag'] = 'Beanbag', ['ammo-shotgun'] = 'Shotgun', ['ammo-40mm'] = '40mm', ['ammo-taser'] = 'Taser'}
    amount = tonumber(amount)
    ammoType = ammoType or 'ammo-9'
    ammoLabel = ammo[ammoType]
    if not amount or amount % 1 ~= 0 or amount < 1 or amount > 200 or not ammoLabel then return end
    local currentAmmo = exports.ox_inventory:Search(playerId, 'count', ammoType) or 0
    if currentAmmo + amount > 400 then return end

    exports.ox_inventory:AddItem(playerId, ammoType, amount)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **%s viên đạn %s** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0", amount, ammoLabel)
    TriggerEvent('Faction:server:LockerLogs', playerId, 10236197, 'Locker - Take Ammo', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerMedkit', function(passedPlayerId, category)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerMedkit!'):format(GetPlayerName(playerId), playerId))
        return
    end

    if not chargePlayer(playerId, MEDKIT_PRICE) then
        TriggerClientEvent('lv_notify:client:notify', playerId, {
            title = 'Tủ đồ',
            message = ('Bạn không đủ tiền để lấy Medkit. Cần $%s.'):format(formatNumber(MEDKIT_PRICE)),
            type = 'error'
        })
        return
    end

    exports.ox_inventory:AddItem(playerId, 'medkit', 1)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 Medkit** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 5763719, 'Locker - Take Medkit', content)
end)

RegisterServerEvent('FactionLocker:server:GivePlayerFireExtinguisher', function(passedPlayerId, category)
    local playerId = source
    if not isPlayerAuthorized(playerId, category) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit GivePlayerFireExtinguisher!'):format(GetPlayerName(playerId), playerId))
        return
    end

    exports.ox_inventory:AddItem(playerId, 'WEAPON_FIREEXTINGUISHER', 1)

    local xPlayer = ESX.GetPlayerFromId(playerId)
    local content = ('%s **%s** (#%s) đã lấy **1 Bình Chữa Cháy (Fire Extinguisher)** từ trong tủ đồ.'):format(Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0")
    TriggerEvent('Faction:server:LockerLogs', playerId, 5763719, 'Locker - Take Fire Extinguisher', content)
end)

AddEventHandler('Faction:server:LockerLogs', function(playerId, color, title, content)
    local factionTag = getPlayerFactionTag(playerId)
    local webhook = nil

    if factionTag then
        local upperTag = string.upper(factionTag)
        local configuredWebhook = FACTION_LOCKER_WEBHOOKS[upperTag] or FACTION_LOCKER_WEBHOOKS[factionTag]
        if configuredWebhook and configuredWebhook ~= '' and not string.find(configuredWebhook, 'YOUR_') then
            webhook = configuredWebhook
        else
            local factionResult = MySQL.query.await('SELECT type FROM faction WHERE tag = ?', {factionTag})
            if factionResult and factionResult[1] and factionResult[1].type == 'business' then
                local bizConfig = Config.Receipts.Businesses and Config.Receipts.Businesses[upperTag]
                webhook = bizConfig and bizConfig.DiscordWebhook or Config.Receipts.DiscordWebhook
            end
        end
    end


    if not webhook then
        local xPlayer = ESX.GetPlayerFromId(playerId)
        local category = xPlayer and getPlayerFactionCategory(xPlayer.identifier) or nil
        if category == 'police' then
            webhook = DEFAULT_LOCKER_WEBHOOK
        elseif category == 'medic' then
            if GetResourceState('medic') == 'started' then
                local medicWebhook = exports['medic']:GetLockerWebhook()
                if medicWebhook and medicWebhook ~= '' then
                    webhook = medicWebhook
                end
            end
        end
    end

    if not webhook then
        webhook = DEFAULT_LOCKER_WEBHOOK
    end

    if webhook and webhook ~= '' then
        local embed = {
            {
                ['color'] = color,
                ['title'] = title,
                ['description'] = content,
                ['footer'] = {
                    ['text'] = os.date('%Y-%m-%d %H:%M:%S')
                }
            }
        }

        if GetResourceState('legacyWebhook') == 'started' then
            local invoked, accepted = pcall(function()
                return exports['legacyWebhook']:SendDiscordEmbeds({
                    webhook = webhook,
                    username = 'Faction Locker',
                    category = 'faction_locker',
                    action = title,
                    playerId = playerId,
                    embeds = embed
                })
            end)

            if invoked then
                return
            end
        end

        PerformHttpRequest(webhook, function(err, text, headers) end, 'POST', json.encode({username = "Faction Locker", embeds = embed}), { ['Content-Type'] = 'application/json' })
    end
end)

RegisterServerEvent('FactionLocker:server:BuyBusinessItem', function(itemName, price, itemLabel, count)
    local playerId = source
    if businessPurchaseLocks[playerId] then return end
    businessPurchaseLocks[playerId] = true
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then businessPurchaseLocks[playerId] = nil return end

    count = tonumber(count)
    if not count or count % 1 ~= 0 or count < 1 or count > 100 then businessPurchaseLocks[playerId] = nil return end

    local factionTag = getPlayerFactionTag(playerId)
    if not factionTag then
        TriggerClientEvent('lv_notify:client:notify', playerId, {
            title = 'Tủ đồ',
            message = 'Bạn không thuộc bất kỳ tổ chức nào!',
            type = 'error'
        })
        businessPurchaseLocks[playerId] = nil
        return
    end

    local factionResult = MySQL.query.await('SELECT name, type, category FROM faction WHERE tag = ?', {factionTag})
    if not factionResult or not factionResult[1] or factionResult[1].type ~= 'business' then
        TriggerClientEvent('lv_notify:client:notify', playerId, {
            title = 'Tủ đồ',
            message = 'Tổ chức của bạn không phải Doanh nghiệp để sử dụng chức năng này!',
            type = 'error'
        })
        businessPurchaseLocks[playerId] = nil
        return
    end
    if not isPlayerAuthorized(playerId, factionResult[1].category, false) then businessPurchaseLocks[playerId] = nil return end
    local businessName = factionResult[1].name or factionTag
    local upperTag = factionTag and string.upper(factionTag) or ""
    local itemsList = Config.BusinessLocker[upperTag] or Config.BusinessLocker[factionTag] or Config.BusinessLocker['DEFAULT'] or {}

    local validItem = nil
    for i = 1, #itemsList do
        if itemsList[i].item == itemName then
            validItem = itemsList[i]
            break
        end
    end

    if not validItem then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit BuyBusinessItem with invalid item/price!'):format(xPlayer.name, playerId))
        businessPurchaseLocks[playerId] = nil
        return
    end

    price = tonumber(validItem.price)
    itemLabel = validItem.label
    local totalPrice = price * count
    if exports.ox_inventory:CanCarryItem(playerId, itemName, count) ~= true then businessPurchaseLocks[playerId] = nil return end
    local budget = exports.factionCore:GetFactionBudget(factionTag)
    if budget < totalPrice then
        TriggerClientEvent('lv_notify:client:notify', playerId, {
            title = 'Nhập hàng hoá',
            message = ('Ngân sách doanh nghiệp không đủ để nhập %s %s. Cần $%s (Ngân quỹ có: $%s).'):format(count, itemLabel, formatNumber(totalPrice), formatNumber(budget)),
            type = 'error'
        })
        businessPurchaseLocks[playerId] = nil
        return
    end

    local requestId = ('locker:%s:%s:%s:%s'):format(factionTag, xPlayer.identifier, os.time(), GetGameTimer())
    local changed = exports.factionCore:ChangeFactionBudget(factionTag, -totalPrice, ("Nhập hàng hóa từ Locker: %sx %s"):format(count, itemLabel), playerId, requestId)
    if not changed then businessPurchaseLocks[playerId] = nil return end
    if exports.ox_inventory:AddItem(playerId, itemName, count) ~= true then
        exports.factionCore:ChangeFactionBudget(factionTag, totalPrice, 'Hoàn tiền nhập hàng thất bại', playerId, requestId .. ':rollback')
        businessPurchaseLocks[playerId] = nil
        return
    end

    TriggerClientEvent('lv_notify:client:notify', playerId, {
        title = 'Nhập hàng hoá',
        message = ('Đã nhập thành công %s %s với tổng giá $%s từ ngân quỹ doanh nghiệp.'):format(count, itemLabel, formatNumber(totalPrice)),
        type = 'success'
    })

    local content = ('Doanh nghiệp: **%s** (%s)\nNgười thực hiện: %s **%s** (#%s)\nĐã nhập: **%s %s** với tổng giá $%s (Đã trừ vào ngân quỹ doanh nghiệp).'):format(businessName, factionTag, Player(playerId).state.factionRank or "Member", xPlayer.getName(), Player(playerId).state.factionBadgeNum or "0", count, itemLabel, formatNumber(totalPrice))
    TriggerEvent('Faction:server:LockerLogs', playerId, 4620411, 'Locker - Buy Item', content)
    businessPurchaseLocks[playerId] = nil
end)

AddEventHandler('playerDropped', function()
    lockerRequestTimes[source] = nil
    businessPurchaseLocks[source] = nil
end)
