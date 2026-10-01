local financeLocks = {}
local financeSchemaReady = false

local function isServerAdmin(playerId)
    return type(playerId) == 'number' and ESX.IsPlayerAdmin and ESX.IsPlayerAdmin(playerId) == true
end

local function awaitFinanceSchema()
    local timeout = GetGameTimer() + 15000
    while not financeSchemaReady and GetGameTimer() < timeout do Wait(0) end
    return financeSchemaReady
end

local function trimText(value)
    return type(value) == 'string' and value:match('^%s*(.-)%s*$') or nil
end

local function positiveInteger(value)
    value = tonumber(value)
    if not value or value <= 0 or value % 1 ~= 0 or value > 2000000000 then return nil end
    return math.floor(value)
end

local function withFinanceLock(tag, callback)
    local key = tag:lower()
    while financeLocks[key] do
        Wait(0)
    end
    financeLocks[key] = true
    local result = table.pack(xpcall(callback, debug.traceback))
    financeLocks[key] = nil
    if not result[1] then
        print(('[factionCore] finance error: %s'):format(result[2]))
        return false, 0, 0, 0
    end
    return table.unpack(result, 2, result.n)
end

local function getFactionFinancials(tag)
    if not awaitFinanceSchema() then return 0, 0, 0 end
    tag = trimText(tag)
    if not tag or tag == '' then return 0, 0, 0 end
    local row = MySQL.single.await('SELECT budget, reserved_budget FROM faction WHERE LOWER(tag) = LOWER(?)', {tag})
    if not row then return 0, 0, 0 end
    local budget = math.floor(tonumber(row.budget) or 0)
    local reserved = math.max(0, math.floor(tonumber(row.reserved_budget) or 0))
    return budget, reserved, math.max(0, budget - reserved)
end

local function applyFactionFinance(tag, payload)
    if not awaitFinanceSchema() then return false, 0, 0, 0 end
    tag = trimText(tag)
    payload = type(payload) == 'table' and payload or {}
    local budgetDelta = tonumber(payload.budgetDelta) or 0
    local reserveDelta = tonumber(payload.reserveDelta) or 0
    local requestId = trimText(payload.requestId)
    if not tag or tag == '' or budgetDelta % 1 ~= 0 or reserveDelta % 1 ~= 0 then
        return false, 0, 0, 0
    end
    budgetDelta = math.floor(budgetDelta)
    reserveDelta = math.floor(reserveDelta)
    if budgetDelta == 0 and reserveDelta == 0 then
        local budget, reserved, available = getFactionFinancials(tag)
        return true, budget, reserved, available
    end
    requestId = requestId or ('faction:%s:%s:%s:%s'):format(tag:lower(), GetGameTimer(), math.random(100000, 999999), os.time())
    return withFinanceLock(tag, function()
        local existing = MySQL.single.await('SELECT faction_tag, budget_delta, reserve_delta, applied FROM faction_finance_requests WHERE request_id = ?', {requestId})
        if existing then
            if tostring(existing.faction_tag):lower() ~= tag:lower() or tonumber(existing.budget_delta) ~= budgetDelta or tonumber(existing.reserve_delta) ~= reserveDelta then
                return false, getFactionFinancials(tag)
            end
            if tonumber(existing.applied) == 1 then
                local budget, reserved, available = getFactionFinancials(tag)
                return true, budget, reserved, available
            end
        else
            local inserted = MySQL.insert.await('INSERT INTO faction_finance_requests (request_id, faction_tag, budget_delta, reserve_delta, applied) VALUES (?, ?, ?, ?, 0)', {requestId, tag, budgetDelta, reserveDelta})
            if not inserted then return false, getFactionFinancials(tag) end
        end
        local affected = MySQL.update.await([[
            UPDATE faction f
            JOIN faction_finance_requests r ON r.request_id = ?
            SET f.budget = f.budget + r.budget_delta,
                f.reserved_budget = f.reserved_budget + r.reserve_delta,
                r.applied = 1
            WHERE r.applied = 0
              AND LOWER(f.tag) = LOWER(r.faction_tag)
              AND f.reserved_budget + r.reserve_delta >= 0
              AND f.budget + r.budget_delta >= f.reserved_budget + r.reserve_delta
        ]], {requestId})
        local budget, reserved, available = getFactionFinancials(tag)
        if not affected or affected < 1 then return false, budget, reserved, available end
        if budgetDelta ~= 0 and payload.skipLog ~= true then
            logBudgetChange(tag, budgetDelta, payload.reason or 'Finance change', payload.sourcePlayerId, requestId)
        end
        return true, budget, reserved, available
    end)
end

MySQL.ready(function()
    MySQL.query.await('ALTER TABLE faction ADD COLUMN IF NOT EXISTS reserved_budget BIGINT NOT NULL DEFAULT 0')
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS faction_finance_requests (
            request_id VARCHAR(191) PRIMARY KEY,
            faction_tag VARCHAR(50) NOT NULL,
            budget_delta BIGINT NOT NULL DEFAULT 0,
            reserve_delta BIGINT NOT NULL DEFAULT 0,
            applied TINYINT(1) NOT NULL DEFAULT 0,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_faction_finance_tag (faction_tag, created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    financeSchemaReady = true
end)

local function normalizePlayerName(name)
    return tostring(name or ''):lower():gsub('%s+', ' '):match('^%s*(.-)%s*$')
end

local function getIdentifier(identifierOrSource)
    if type(identifierOrSource) == 'number' then
        local xPlayer = ESX.GetPlayerFromId(identifierOrSource)
        return xPlayer and xPlayer.identifier or nil
    end
    return type(identifierOrSource) == 'string' and identifierOrSource or nil
end

local function permissionEntryMatches(entry, identifier)
    return type(entry) == 'table' and type(identifier) == 'string' and entry.identifier == identifier
end

local function getFactionMembership(identifierOrSource, expectedTag)
    local identifier = getIdentifier(identifierOrSource)
    if not identifier then return nil end
    local user = MySQL.single.await('SELECT firstname, lastname, faction FROM users WHERE identifier = ?', {identifier})
    if not user then return nil end
    local membership = json.decode(user.faction or '{}') or {}
    if not membership.name or membership.name == 'Không có' then return nil end
    local faction = MySQL.single.await('SELECT id, name, tag, type, permission FROM faction WHERE name = ?', {membership.name})
    if not faction or expectedTag and tostring(faction.tag):lower() ~= tostring(expectedTag):lower() then return nil end
    faction.identifier = identifier
    faction.playerName = normalizePlayerName(('%s %s'):format(user.firstname or '', user.lastname or ''))
    faction.rank = tonumber(membership.rank) or 0
    faction.division = tonumber(membership.division) or 0
    faction.badgeNum = membership.badgeNum
    return faction
end

local function hasFactionPermission(identifierOrSource, expectedTag, permissionName)
    local membership = getFactionMembership(identifierOrSource, expectedTag)
    if not membership then return false end
    local permissions = json.decode(membership.permission or '[]') or {}
    for i = 1, #permissions do
        if permissionEntryMatches(permissions[i], membership.identifier) then
            return permissions[i].leader == true or permissions[i].leader == 1
                or permissionName and (permissions[i][permissionName] == true or permissions[i][permissionName] == 1) or false
        end
    end
    return false
end

local function getBusinessByTag(tag)
    if not tag or tag == '' then return nil end
    return MySQL.single.await('SELECT id, name, tag, type FROM faction WHERE LOWER(tag) = LOWER(?) AND type = ?', {tag, 'business'})
end

local function getPlayerBusiness(identifierOrSource)
    local membership = getFactionMembership(identifierOrSource)
    if not membership or membership.type ~= 'business' then return nil end
    membership.permission = nil
    membership.identifier = nil
    membership.playerName = nil
    return membership
end

local function setPlayerBusiness(identifierOrSource, tag, rank)
    local identifier = identifierOrSource
    local playerId
    if type(identifierOrSource) == 'number' then
        playerId = identifierOrSource
        local xPlayer = ESX.GetPlayerFromId(playerId)
        identifier = xPlayer and xPlayer.identifier or nil
    else
        for _, id in ipairs(GetPlayers()) do
            local xPlayer = ESX.GetPlayerFromId(id)
            if xPlayer and xPlayer.identifier == identifier then
                playerId = tonumber(id)
                break
            end
        end
    end
    if not identifier then return false end

    local user = MySQL.single.await('SELECT faction FROM users WHERE identifier = ?', {identifier})
    if not user then return false end
    local current = json.decode(user.faction or '{}') or {}

    if not tag or tag == '' or tag == 'unemployed' then
        if current.name and current.name ~= 'Không có' then
            local currentType = MySQL.scalar.await('SELECT type FROM faction WHERE name = ?', {current.name})
            if currentType ~= 'business' then return false end
            RemovePlayerFactionPermissions(identifier, current.name)
        end
        current = {name = 'Không có', rank = 0, division = 0}
    else
        local business = getBusinessByTag(tag)
        if not business then return false end
        if current.name and current.name ~= 'Không có' and current.name ~= business.name then
            RemovePlayerFactionPermissions(identifier, current.name)
        end
        current.name = business.name
        current.rank = tonumber(rank) or 0
        current.division = current.division or 0
    end

    MySQL.update.await('UPDATE users SET faction = ? WHERE identifier = ?', {json.encode(current), identifier})
    if playerId then TriggerEvent('FactionEvent:server:UpdatePlayerStatebag', playerId) end
    LoadedFactionData(playerId or -1)
    return true
end

exports('GetPlayerBusiness', getPlayerBusiness)
exports('IsBusinessTag', function(tag) return getBusinessByTag(tag) ~= nil end)

exports('GetFactionOnDutyCount', function(faction)
    if type(faction) ~= 'string' or faction == '' then return 0 end

    local target = faction:lower()
    local count = 0

    for _, playerId in ipairs(GetPlayers()) do
        local state = Player(tonumber(playerId)).state
        if state and state.factionDuty == true then
            local tag = type(state.factionTag) == 'string' and state.factionTag:lower() or nil
            local category = type(state.factionCategory) == 'string' and state.factionCategory:lower() or nil
            if tag == target or category == target then
                count = count + 1
            end
        end
    end

    return count
end)
exports('IsPlayerBusinessLeader', function(identifierOrSource, expectedTag)
    if not expectedTag then return false end
    return hasFactionPermission(identifierOrSource, expectedTag, 'leader')
end)
exports('HasPlayerBusinessPermission', function(identifierOrSource, expectedTag, permissionName)
    return expectedTag ~= nil and permissionName ~= nil and hasFactionPermission(identifierOrSource, expectedTag, permissionName) or false
end)
exports('GetPlayerFactionMembership', getFactionMembership)
exports('HasPlayerFactionPermission', hasFactionPermission)
exports('SetPlayerBusiness', setPlayerBusiness)
exports('RemovePlayerBusiness', function(identifierOrSource, expectedTag)
    local business = getPlayerBusiness(identifierOrSource)
    if not business then return false end
    if expectedTag and tostring(business.tag):lower() ~= tostring(expectedTag):lower() then return false end
    return setPlayerBusiness(identifierOrSource, 'unemployed', 0)
end)

function RemovePlayerFactionPermissions(identifier, factionName)
    if not identifier then return false end

    local user = MySQL.single.await('SELECT firstname, lastname, faction FROM users WHERE identifier = ?', {identifier})
    if not user then return false end

    local oldFaction = json.decode(user.faction or '{}') or {}
    factionName = factionName or oldFaction.name
    if not factionName or factionName == 'Không có' then return true end

    local faction = MySQL.single.await('SELECT id, permission FROM faction WHERE name = ?', {factionName})
    if not faction then return true end

    local permissions = json.decode(faction.permission or '[]') or {}
    local removed = false

    for i = #permissions, 1, -1 do
        if permissionEntryMatches(permissions[i], identifier) then
            table.remove(permissions, i)
            removed = true
        end
    end

    if removed then
        MySQL.update.await('UPDATE faction SET permission = ? WHERE id = ?', {json.encode(permissions), faction.id})
    end

    return true
end

exports('RemovePlayerFactionPermissions', RemovePlayerFactionPermissions)

local function cleanupStaleFactionPermissions()
    local users = MySQL.query.await('SELECT identifier, firstname, lastname, faction FROM users') or {}
    local usersByIdentifier = {}
    local candidatesByFactionAndName = {}
    for i = 1, #users do
        local membership = json.decode(users[i].faction or '{}') or {}
        usersByIdentifier[users[i].identifier] = membership.name
        if membership.name and membership.name ~= 'Không có' then
            local key = membership.name .. '\0' .. normalizePlayerName(('%s %s'):format(users[i].firstname or '', users[i].lastname or ''))
            candidatesByFactionAndName[key] = candidatesByFactionAndName[key] or {}
            candidatesByFactionAndName[key][#candidatesByFactionAndName[key] + 1] = users[i].identifier
        end
    end
    local factions = MySQL.query.await('SELECT id, name, permission FROM faction') or {}
    local removedCount = 0
    local migratedCount = 0
    for i = 1, #factions do
        local permissions = json.decode(factions[i].permission or '[]') or {}
        local changed = false
        local seen = {}
        for p = #permissions, 1, -1 do
            local entry = permissions[p]
            if not entry.identifier then
                local candidates = candidatesByFactionAndName[factions[i].name .. '\0' .. normalizePlayerName(entry.name)] or {}
                if #candidates == 1 then
                    entry.identifier = candidates[1]
                    migratedCount = migratedCount + 1
                    changed = true
                end
            end
            if not entry.identifier or usersByIdentifier[entry.identifier] ~= factions[i].name or seen[entry.identifier] then
                table.remove(permissions, p)
                removedCount = removedCount + 1
                changed = true
            else
                seen[entry.identifier] = true
            end
        end
        if changed then
            MySQL.update.await('UPDATE faction SET permission = ? WHERE id = ?', {json.encode(permissions), factions[i].id})
        end
    end
    if migratedCount > 0 or removedCount > 0 then
        print(('[factionCore] permission identifiers migrated=%s removed=%s'):format(migratedCount, removedCount))
    end
end

local function migrateLegacyBusinessJobs()
    local businesses = MySQL.query.await("SELECT name, tag FROM faction WHERE type = 'business'") or {}
    local migrated = 0

    for i = 1, #businesses do
        local users = MySQL.query.await([[
            SELECT identifier, faction, job_grade
            FROM users
            WHERE LOWER(job) = LOWER(?)
        ]], {businesses[i].tag}) or {}

        for u = 1, #users do
            local membership = json.decode(users[u].faction or '{}') or {}
            if not membership.name or membership.name == 'Không có' then
                membership.name = businesses[i].name
                membership.rank = tonumber(users[u].job_grade) or 0
                membership.division = membership.division or 0
                MySQL.update.await('UPDATE users SET faction = ? WHERE identifier = ?', {json.encode(membership), users[u].identifier})
                migrated = migrated + 1
            end
        end
    end

    if migrated > 0 then
        print(('[factionCore] Migrated %s legacy business job memberships without changing player jobs.'):format(migrated))
        for _, playerId in ipairs(GetPlayers()) do
            TriggerEvent('FactionEvent:server:UpdatePlayerStatebag', tonumber(playerId))
        end
    end
end

CreateThread(function()
    Wait(1000)
    migrateLegacyBusinessJobs()
    cleanupStaleFactionPermissions()
    LoadedFactionData(-1)
end)

local function getPanelAccess(src, factionId, requiredPermission)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false end

    if isServerAdmin(src) then
        return true, { leader = true, members = true, role = true, radio = true, gun = true }, true
    end

    local user = MySQL.single.await('SELECT firstname, lastname, faction FROM users WHERE identifier = ?', {xPlayer.identifier})
    if not user then return false end

    local playerFaction = json.decode(user.faction or '{}') or {}
    if not playerFaction.name or playerFaction.name == 'Không có' then return false end

    local faction = MySQL.single.await('SELECT id, name, tag, permission FROM faction WHERE name = ?', {playerFaction.name})
    if not faction or tonumber(faction.id) ~= tonumber(factionId) then return false end

    local permissions = json.decode(faction.permission or '[]') or {}
    for i = 1, #permissions do
        if permissionEntryMatches(permissions[i], xPlayer.identifier) then
            local perm = permissions[i]
            local allowed = perm.leader == true or perm.leader == 1
            if requiredPermission then
                allowed = allowed or perm[requiredPermission] == true or perm[requiredPermission] == 1
            else
                allowed = allowed or perm.members == true or perm.members == 1
                    or perm.role == true or perm.role == 1 or perm.radio == true or perm.radio == 1
                    or perm.gun == true or perm.gun == 1
            end
            return allowed, perm, false
        end
    end

    return false
end

local function isPanelAdmin(src)
    return isServerAdmin(src)
end

local function resolveFactionMemberByName(factionName, playerName)
    if type(factionName) ~= 'string' or type(playerName) ~= 'string' then return nil end
    local rows = MySQL.query.await("SELECT identifier, firstname, lastname, faction FROM users WHERE LOWER(REPLACE(CONCAT(firstname, lastname), ' ', '')) = LOWER(REPLACE(?, ' ', ''))", {playerName}) or {}
    local match
    for i = 1, #rows do
        local membership = json.decode(rows[i].faction or '{}') or {}
        if membership.name == factionName then
            if match then return nil end
            match = rows[i]
        end
    end
    return match
end

local function clientFactionRows(rows)
    local data = json.decode(json.encode(rows or {})) or {}
    for i = 1, #data do
        local permissions = json.decode(data[i].permission or '[]') or {}
        for p = 1, #permissions do permissions[p].identifier = nil end
        data[i].permission = json.encode(permissions)
    end
    return data
end

ESX.RegisterServerCallback('FactionPanel:server:GetAccess', function(src, cb)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return cb(false) end
    if isPanelAdmin(src) then
        return cb({ admin = true, permissions = { leader = true, members = true, role = true, radio = true, gun = true } })
    end

    local user = MySQL.single.await('SELECT faction FROM users WHERE identifier = ?', {xPlayer.identifier})
    local playerFaction = user and (json.decode(user.faction or '{}') or {}) or {}
    local faction = playerFaction.name and MySQL.single.await('SELECT id FROM faction WHERE name = ?', {playerFaction.name}) or nil
    if not faction then return cb(false) end

    local allowed, permissions = getPanelAccess(src, faction.id)
    if not allowed then return cb(false) end
    cb({ admin = false, factionId = faction.id, permissions = permissions })
end)

ESX.RegisterServerCallback('FactionPanel:server:GetFactionType', function(src, cb, type)
    if not isPanelAdmin(src) then return cb({}) end
    FactionData = MySQL.query.await('SELECT * FROM faction WHERE type = ?', {type})
    cb(clientFactionRows(FactionData))
end)

ESX.RegisterServerCallback('FactionPanel:server:GetFactionFromId', function(src, cb, id)
    if not getPanelAccess(src, id) then return cb({}) end
    FactionData = MySQL.query.await('SELECT * FROM faction WHERE id = ?', {id})
    cb(clientFactionRows(FactionData))
end)

ESX.RegisterServerCallback('FactionPanel:server:GetOwnFactionSummary', function(src, cb)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return cb(false) end

    local user = MySQL.single.await('SELECT faction FROM users WHERE identifier = ?', {xPlayer.identifier})
    local playerFaction = user and (json.decode(user.faction or '{}') or {}) or {}
    if not playerFaction.name or playerFaction.name == 'Không có' then return cb(false) end

    local faction = MySQL.single.await('SELECT id, name, tag, type FROM faction WHERE name = ?', {playerFaction.name})
    cb(faction or false)
end)

ESX.RegisterServerCallback('FactionPanel:server:GetPlayerData', function(src, cb, id)
    if not getPanelAccess(src, id, 'members') then return cb({}) end
    local faction = MySQL.query.await('SELECT name, type FROM faction WHERE id = ?', {id})
    if faction and faction[1] then
        local factionName = faction[1].name
        local factionType = faction[1].type
        local data = {}
        if factionType == 'gov' or factionType == 'business' then
            data = MySQL.query.await("SELECT identifier, firstname, lastname, faction FROM users WHERE JSON_UNQUOTE(JSON_EXTRACT(faction, '$.name')) = ?", {factionName})
        end
        cb(data)
    else
        cb({})
    end
end)

ESX.RegisterServerCallback('FactionPanel:server:EditMembers', function(src, cb, data)
    if not data or not getPanelAccess(src, data.id, 'members') then return cb(false) end
    if data and data.playerName then
        local factionRow = MySQL.single.await('SELECT name FROM faction WHERE id = ?', {data.id})
        local target = factionRow and resolveFactionMemberByName(factionRow.name, data.playerName) or nil
        local user = target and {target} or {}
        if user and user[1] then
            local playerData = user[1]
            local FactionData = MySQL.query.await('SELECT * FROM faction WHERE id = ?', {data.id})
            if FactionData and FactionData[1] then
                local groupData = {}
                if FactionData[1].type == 'gov' or FactionData[1].type == 'business' then
                    groupData = json.decode(playerData.faction) or {}
                    if groupData.name ~= FactionData[1].name then return cb(false) end
                end

                if data.type == 'rank' then
                    groupData.rank = data.value
                elseif data.type == 'division' then
                    groupData.division = data.value
                elseif data.type == 'badge' then
                    local newBadge = tostring(data.value or ''):gsub('%s+', '')
                    if newBadge ~= '' and newBadge ~= '0' then
                        local allFactionUsers = MySQL.query.await("SELECT identifier, faction FROM users WHERE JSON_UNQUOTE(JSON_EXTRACT(faction, '$.name')) = ?", {FactionData[1].name})
                        for _, u in ipairs(allFactionUsers or {}) do
                            if u.identifier ~= playerData.identifier then
                                local uFaction = json.decode(u.faction or '{}') or {}
                                if tostring(uFaction.badgeNum or ''):gsub('%s+', '') == newBadge then
                                    TriggerClientEvent('esx:showNotification', src, ('Số hiệu/Mã %s đã được sử dụng bởi một thành viên khác trong %s!'):format(newBadge, FactionData[1].name))
                                    return cb(false)
                                end
                            end
                        end
                    end
                    groupData.badgeNum = data.value
                elseif data.type == 'kick' then
                    RemovePlayerFactionPermissions(playerData.identifier, FactionData[1].name)
                    groupData.name = "Không có"
                    groupData.rank = 0
                    groupData.division = 0
                end

                if FactionData[1].type == 'gov' or FactionData[1].type == 'business' then
                    MySQL.query.await('UPDATE users SET faction = ? WHERE identifier = ?', {json.encode(groupData), playerData.identifier})
                end

                for _, v in pairs(GetPlayers()) do
                    local xPlayer = ESX.GetPlayerFromId(v)
                    if xPlayer and xPlayer.identifier == playerData.identifier then
                            TriggerEvent('FactionEvent:server:UpdatePlayerStatebag', v)
                    end
                end

                cb(true)
                return
            end
        end
    end
    cb(false)
end)

function HexMaptoRGB(hex)
    hex = hex:gsub("#","")
    return tonumber("0x"..hex:sub(1,2)), tonumber("0x"..hex:sub(3,4)), tonumber("0x"..hex:sub(5,6))
end

ESX.RegisterServerCallback('FactionPanel:server:EditFaction', function(src, cb, data)
    if not data or not getPanelAccess(src, data.id, 'leader') then return cb(false) end
    local results = ''
    local value = data.value
    if data.type == 'name' then
        results = 'UPDATE faction SET name = ? WHERE id = ?'
    elseif data.type == 'tag' then
        results = 'UPDATE faction SET tag = ? WHERE id = ?'
    elseif data.type == 'type' then
        if data.value == 'gov' then
            results = 'UPDATE faction SET type = ?, category = "police" WHERE id = ?'
        elseif data.value == 'business' then
            results = 'UPDATE faction SET type = ?, category = "business" WHERE id = ?'
        end
    elseif data.type == 'logo' then
        results = 'UPDATE faction SET image = ? WHERE id = ?'
    elseif data.type == 'category' then
        results = 'UPDATE faction SET category = ? WHERE id = ?'
    elseif data.type == 'sirenbox' then
        results = 'UPDATE faction SET sirenbox = ? WHERE id = ?'
    elseif data.type == 'color' then
        results = 'UPDATE faction SET colour = ? WHERE id = ?'
        r, g, b = HexMaptoRGB(data.value)
        value = ('%s, %s, %s'):format(r, g, b)
    end

    if results == '' then return cb(false) end
    MySQL.query.await(results, {value, data.id})
    cb(true)
end)

ESX.RegisterServerCallback('FactionPanel:server:EditRank', function(src, cb, type, data)
    if not data or not getPanelAccess(src, data.id, 'role') then return cb(false) end
    if type == 'create' then
        FactionData = MySQL.query.await('SELECT * FROM faction WHERE id = ?', {data.id})

        local rank = {}
        if json.encode(FactionData[1].rank) == '[]' then
            rank = {
                { id = 1, name = data.rankName }
            }
        else
            rank = json.decode(FactionData[1].rank)
            table.insert(rank, { id = #rank + 1, name = data.rankName })
        end
        MySQL.query.await('UPDATE faction SET rank = ? WHERE id = ?', {json.encode(rank), data.id})
        cb(true)
    elseif type == 'update' then
        FactionData = MySQL.query.await('SELECT * FROM faction WHERE id = ?', {data.id})
        local rank = json.decode(FactionData[1].rank)
        for i = 1, #rank do
            if tonumber(data.rankId) == tonumber(rank[i].id) then
                rank[i].name = data.value
            end
        end
        MySQL.query.await('UPDATE faction SET rank = ? WHERE id = ?', {json.encode(rank), data.id})
        cb(true)
    elseif type == 'remove' then
        FactionData = MySQL.query.await('SELECT * FROM faction WHERE id = ?', {data.id})
        local rank = json.decode(FactionData[1].rank)
        for i = 1, #rank do
            if tonumber(data.rankId) == tonumber(rank[i].id) then
                table.remove(rank, i)
                break
            end
        end
        MySQL.query.await('UPDATE faction SET rank = ? WHERE id = ?', {json.encode(rank), data.id})
        cb(true)
    end
end)

ESX.RegisterServerCallback('FactionPanel:server:EditDivision', function(src, cb, type, data)
    if not data or not getPanelAccess(src, data.id, 'role') then return cb(false) end
    if type == 'create' then
        FactionData = MySQL.query.await('SELECT * FROM faction WHERE id = ?', {data.id})

        local division = {}
        if json.encode(FactionData[1].division) == '[]' then
            division = {
                { id = 1, name = data.divisionName }
            }
        else
            division = json.decode(FactionData[1].division)
            table.insert(division, { id = #division + 1, name = data.divisionName })
        end
        MySQL.query.await('UPDATE faction SET division = ? WHERE id = ?', {json.encode(division), data.id})
        cb(true)
    elseif type == 'update' then
        FactionData = MySQL.query.await('SELECT * FROM faction WHERE id = ?', {data.id})
        local division = json.decode(FactionData[1].division)
        for i = 1, #division do
            if tonumber(data.divisionId) == tonumber(division[i].id) then
                division[i].name = data.value
            end
        end

        MySQL.query.await('UPDATE faction SET division = ? WHERE id = ?', {json.encode(division), data.id})
        cb(true)
    elseif type == 'remove' then
        FactionData = MySQL.query.await('SELECT * FROM faction WHERE id = ?', {data.id})
        local division = json.decode(FactionData[1].division)
        for i = 1, #division do
            if tonumber(data.divisionId) == tonumber(division[i].id) then
                table.remove(division, i)
                break
            end
        end
        MySQL.query.await('UPDATE faction SET division = ? WHERE id = ?', {json.encode(division), data.id})
        cb(true)
    end
end)

ESX.RegisterServerCallback('FactionPanel:server:EditPermission', function(src, cb, type, data)
    if not data or not getPanelAccess(src, data.id, 'leader') then return cb(false) end
    if type == 'create' then
        FactionData = MySQL.query.await('SELECT * FROM faction WHERE id = ?', {data.id})
        if not FactionData or not FactionData[1] then return cb(false) end
        local target = resolveFactionMemberByName(FactionData[1].name, data.name)
        if not target then return cb(false) end

        local permission = json.decode(FactionData[1].permission)
        table.insert(permission, {
            name = ('%s %s'):format(target.firstname or '', target.lastname or ''), identifier = target.identifier, leader = false, members = false, role = false, radio = false, gun = false,
            dealer_manage_employees = false, dealer_manage_inventory = false, dealer_manage_finances = false,
            dealer_sell = false, dealer_deliver = false, dealer_view_records = false,
            casino_cashier = false, casino_membership = false, casino_ledger = false
        })

        MySQL.query.await('UPDATE faction SET permission = ? WHERE id = ?', {json.encode(permission), data.id})
        cb(true)
    elseif type == 'update' then

        FactionData = MySQL.query.await('SELECT * FROM faction WHERE id = ?', {data.id})
        if not FactionData or not FactionData[1] then return cb(false) end
        local target = resolveFactionMemberByName(FactionData[1].name, data.playerName)
        if not target then return cb(false) end
        local permission = json.decode(FactionData[1].permission)
        for i = 1, #permission do
            if permissionEntryMatches(permission[i], target.identifier) then
                permission[i].leader    = data.leader
                permission[i].members   = data.members
                permission[i].role      = data.role
                permission[i].radio     = data.radio
                permission[i].gun       = data.gun
                if tostring(FactionData[1].tag or ''):lower() == 'cardealer' then
                    permission[i].dealer_manage_employees = data.dealer_manage_employees == true
                    permission[i].dealer_manage_inventory = data.dealer_manage_inventory == true
                    permission[i].dealer_manage_finances = data.dealer_manage_finances == true
                    permission[i].dealer_sell = data.dealer_sell == true
                    permission[i].dealer_deliver = data.dealer_deliver == true
                    permission[i].dealer_view_records = data.dealer_view_records == true
                end
                if tostring(FactionData[1].tag or ''):lower() == 'casino' then
                    permission[i].casino_cashier = data.casino_cashier == true
                    permission[i].casino_membership = data.casino_membership == true
                    permission[i].casino_ledger = data.casino_ledger == true
                end
            end
        end
        MySQL.query.await('UPDATE faction SET permission = ? WHERE id = ?', {json.encode(permission), data.id})
        cb(true)
    elseif type == 'remove' then
        FactionData = MySQL.query.await('SELECT * FROM faction WHERE id = ?', {data.id})
        if not FactionData or not FactionData[1] then return cb(false) end
        local target = resolveFactionMemberByName(FactionData[1].name, data.playerName)
        if not target then return cb(false) end
        local permission = json.decode(FactionData[1].permission)
        for i = 1, #permission do
            if permissionEntryMatches(permission[i], target.identifier) then
                table.remove(permission, i)
                break
            end
        end
        MySQL.query.await('UPDATE faction SET permission = ? WHERE id = ?', {json.encode(permission), data.id})
        cb(true)
    end
end)

RegisterServerEvent('FactionPanel:server:UpdateStateBag', function(data)
    local src = source
    if not data or not getPanelAccess(src, data.id, 'members') then return end
    FactionData = MySQL.query.await('SELECT * FROM faction WHERE id = ?', {data.id})
    if not FactionData or not FactionData[1] then return end
    local target = resolveFactionMemberByName(FactionData[1].name, data.playerName)
    if not target then return end
    for _, playerId in pairs(GetPlayers()) do
        local xPlayer = ESX.GetPlayerFromId(tonumber(playerId))
        if xPlayer and xPlayer.identifier == target.identifier then
            TriggerEvent('FactionEvent:server:UpdatePlayerStatebag', tonumber(playerId))
            break
        end
    end
end)

ESX.RegisterServerCallback('FactionPanel:server:CreateFaction', function(src, cb, data)
    if not isPanelAdmin(src) then return cb(false) end
    local result = MySQL.query.await('INSERT INTO faction (name, type) VALUES (?, ?)', {data.name, data.type})
    cb(result ~= nil)
end)

ESX.RegisterServerCallback('FactionPanel:server:DeleteFaction', function(src, cb, data)
    if not isPanelAdmin(src) then return cb(false) end
    local factionId = tonumber(data.id)
    local faction = MySQL.query.await('SELECT type FROM faction WHERE id = ?', {factionId})
    if faction and faction[1] then
        local factionType = faction[1].type
        MySQL.query.await('DELETE FROM faction WHERE id = ?', {factionId})
        cb(factionType)
    else
        cb(false)
    end
end)

ESX.RegisterCommand('makeleader', 'admin', function(xPlayer, args, showError)
    local targetId = tonumber(args.playerId)
    local tag = args.tag

    if not targetId or not tag then
        return xPlayer.showNotification("Sử dụng: /makeleader [ID] [Faction Tag]")
    end

    local xTarget = ESX.GetPlayerFromId(targetId)
    if not xTarget then
        return xPlayer.showNotification("Người chơi không tồn tại.")
    end

    local factionData = MySQL.query.await('SELECT * FROM faction WHERE tag = ?', {tag})
    if not factionData[1] then
        return xPlayer.showNotification("Tag Faction không tồn tại.")
    end

    local userData = MySQL.query.await('SELECT firstname, lastname FROM users WHERE identifier = ?', {xTarget.identifier})
    local playerName = ('%s %s'):format(userData[1].firstname, userData[1].lastname)

    local factionType = factionData[1].type
    local factionTag = tostring(factionData[1].tag or '')
    local leaderRank = factionType == 'business' and factionTag:lower() == 'pearls' and 5 or 1
    local groupData = { name = factionData[1].name, rank = leaderRank, division = 1 }

    if factionType == 'gov' or factionType == 'business' then
        RemovePlayerFactionPermissions(xTarget.identifier)
        MySQL.query.await('UPDATE users SET faction = ? WHERE identifier = ?', {json.encode(groupData), xTarget.identifier})
    end

    local permission = json.decode(factionData[1].permission) or {}
    local found = false
    local dedupedPermission = {}
    local seenPermissionIdentifiers = {}

    for i = 1, #permission do
        if permission[i].identifier == xTarget.identifier then
            permission[i].name = playerName
            permission[i].identifier = xTarget.identifier
            permission[i].leader = true
            permission[i].members = true
            permission[i].role = true
            permission[i].radio = true
            permission[i].gun = true
            found = true

            if not seenPermissionIdentifiers[xTarget.identifier] then
                table.insert(dedupedPermission, permission[i])
                seenPermissionIdentifiers[xTarget.identifier] = true
            end
        elseif permission[i].identifier and not seenPermissionIdentifiers[permission[i].identifier] then
            table.insert(dedupedPermission, permission[i])
            seenPermissionIdentifiers[permission[i].identifier] = true
        end
    end

    permission = dedupedPermission

    if not found then
        table.insert(permission, {
            name = playerName,
            identifier = xTarget.identifier,
            leader = true,
            members = true,
            role = true,
            radio = true,
            gun = true
        })
    end

    MySQL.query.await('UPDATE faction SET permission = ? WHERE id = ?', {json.encode(permission), factionData[1].id})

    if factionType == 'business' and factionTag:lower() == 'pearls' then
        MySQL.query.await([[
            INSERT INTO pearls_employees (identifier, fullname, imagelink, gradelevel)
            VALUES (?, ?, '', 5)
            ON DUPLICATE KEY UPDATE fullname = VALUES(fullname), gradelevel = 5
        ]], {xTarget.identifier, playerName})
    end

    TriggerEvent('FactionEvent:server:UpdatePlayerStatebag', xTarget.source)
    LoadedFactionData(xTarget.source)
    xPlayer.showNotification(("Đã set %s làm leader của %s."):format(playerName, tag))
    xTarget.showNotification(("Bạn đã được thăng chức làm leader của %s."):format(tag))
end, true, {help = 'Set a player as faction leader', validate = false, arguments = {
    {name = 'playerId', help = 'ID của người chơi', type = 'number'},
    {name = 'tag', help = 'Tag của faction (VD: LSPD)', type = 'string'}
}})


local function IsPlayerLeader(source)
    local membership = getFactionMembership(source)
    return membership ~= nil and hasFactionPermission(source, membership.tag, 'leader') or false
end

local function getLeaderFaction(source)
    local membership = getFactionMembership(source)
    if not membership or not hasFactionPermission(source, membership.tag, 'leader') then return nil end
    return membership
end

-- Commands for leader to manage budget
RegisterCommand("fbudget", function(source, args)
    if source == 0 then return end
    local membership = getLeaderFaction(source)
    if not membership then
        TriggerClientEvent('esx:showNotification', source, "Bạn không ở trong tổ chức nào.")
        return
    end
    local budget, reserved, available = getFactionFinancials(membership.tag)
    TriggerClientEvent('esx:showNotification', source, ("Quỹ %s: tổng $%s, dự phòng $%s, khả dụng $%s"):format(membership.tag, budget, reserved, available))
end, false)

RegisterCommand("fwithdraw", function(source, args)
    if source == 0 then return end
    local amount = positiveInteger(args[1])
    if not amount then
        TriggerClientEvent('esx:showNotification', source, "Sử dụng: /fwithdraw [số tiền]")
        return
    end

    local membership = getLeaderFaction(source)
    if not membership then
        TriggerClientEvent('esx:showNotification', source, "Bạn không ở trong tổ chức nào.")
        return
    end

    local result = MySQL.query.await('SELECT budget FROM faction WHERE tag = ?', {membership.tag})
    if not result or not result[1] then
        TriggerClientEvent('esx:showNotification', source, "Không tìm thấy dữ liệu tổ chức.")
        return
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    if GetResourceState('ox_inventory') == 'started' and not exports.ox_inventory:CanCarryItem(source, 'money', amount) then
        TriggerClientEvent('esx:showNotification', source, 'Túi đồ không đủ chỗ.')
        return
    end
    local requestId = ('command-withdraw:%s:%s:%s'):format(xPlayer.identifier, os.time(), math.random(100000, 999999))
    local changed = applyFactionFinance(membership.tag, {budgetDelta = -amount, reason = 'Budget withdrawal', sourcePlayerId = source, requestId = requestId})
    if not changed then
        TriggerClientEvent('esx:showNotification', source, 'Số dư khả dụng của quỹ không đủ do đang có khoản dự phòng.')
        return
    end
    local paid = true
    if GetResourceState('ox_inventory') == 'started' then
        paid = exports.ox_inventory:AddItem(source, 'money', amount) == true
    else
        xPlayer.addMoney(amount)
    end
    if not paid then
        applyFactionFinance(membership.tag, {budgetDelta = amount, reason = 'Budget withdrawal rollback', sourcePlayerId = source, requestId = requestId .. ':rollback'})
        TriggerClientEvent('esx:showNotification', source, 'Không thể nhận tiền, giao dịch đã được hoàn tác.')
        return
    end

    TriggerClientEvent('esx:showNotification', source, ("Bạn đã rút $%s từ quỹ ngân sách tổ chức."):format(amount))
end, false)

RegisterCommand("fdeposit", function(source, args)
    if source == 0 then return end
    local amount = positiveInteger(args[1])
    if not amount then
        TriggerClientEvent('esx:showNotification', source, "Sử dụng: /fdeposit [số tiền]")
        return
    end

    local membership = getLeaderFaction(source)
    if not membership then
        TriggerClientEvent('esx:showNotification', source, "Bạn không ở trong tổ chức nào.")
        return
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local playerMoney = 0
    if GetResourceState("ox_inventory") == "started" then
        playerMoney = exports.ox_inventory:GetItemCount(source, 'money') or 0
    else
        playerMoney = xPlayer.getMoney()
    end

    if playerMoney < amount then
        TriggerClientEvent('esx:showNotification', source, "Bạn không có đủ tiền mặt.")
        return
    end

    local removed
    if GetResourceState("ox_inventory") == "started" then
        removed = exports.ox_inventory:RemoveItem(source, 'money', amount) == true
    else
        xPlayer.removeMoney(amount)
        removed = true
    end
    if not removed then return end
    local requestId = ('command-deposit:%s:%s:%s'):format(xPlayer.identifier, os.time(), math.random(100000, 999999))
    local changed = applyFactionFinance(membership.tag, {budgetDelta = amount, reason = 'Budget deposit', sourcePlayerId = source, requestId = requestId})
    if not changed then
        if GetResourceState('ox_inventory') == 'started' then exports.ox_inventory:AddItem(source, 'money', amount) else xPlayer.addMoney(amount) end
        TriggerClientEvent('esx:showNotification', source, 'Không thể cập nhật quỹ, tiền đã được hoàn lại.')
        return
    end
    TriggerClientEvent('esx:showNotification', source, ("Bạn đã nộp $%s vào quỹ ngân sách tổ chức."):format(amount))
end, false)

RegisterCommand("quitgroup", function(source, args)
    if source == 0 then return end
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local results = MySQL.query.await('SELECT faction FROM users WHERE identifier = ?', {xPlayer.identifier})
    if not results or not results[1] then
        TriggerClientEvent('esx:showNotification', source, "Không thể lấy thông tin tổ chức của bạn.")
        return
    end

    local playerFaction = json.decode(results[1].faction)
    if not playerFaction or playerFaction.name == 'Không có' then
        TriggerClientEvent('esx:showNotification', source, "Bạn không ở trong tổ chức nào.")
        return
    end

    local factionName = playerFaction.name
    RemovePlayerFactionPermissions(xPlayer.identifier, factionName)

    -- Update user faction to default
    local defaultFaction = { name = "Không có", rank = 0, division = 0 }
    MySQL.query.await('UPDATE users SET faction = ? WHERE identifier = ?', {json.encode(defaultFaction), xPlayer.identifier})

    -- Sync state bag
    TriggerEvent('FactionEvent:server:UpdatePlayerStatebag', source)

    TriggerClientEvent('esx:showNotification', source, ("Bạn đã rời khỏi tổ chức %s."):format(factionName))
end, false)

local BUDGET_LOG_WEBHOOK = GetConvar('faction_budget_webhook', '')

function logBudgetChange(factionTag, amount, reason, sourcePlayerId, requestId)
    local factionName = "Unknown"
    local factionType = "Unknown"
    local currentBudget = 0
    local result = MySQL.query.await('SELECT name, type, budget FROM faction WHERE tag = ?', {factionTag})
    if result and result[1] then
        factionName = result[1].name
        factionType = result[1].type
        currentBudget = tonumber(result[1].budget) or 0
    end

    local action = amount >= 0 and "Cộng tiền (+)" or "Trừ tiền (-)"
    local absAmount = math.abs(amount)
    local balanceBefore = currentBudget - amount
    local playerInfo = "Hệ thống"
    local player
    if sourcePlayerId and sourcePlayerId > 0 then
        local xPlayer = ESX.GetPlayerFromId(sourcePlayerId)
        if xPlayer then
            playerInfo = ("%s (%s)"):format(xPlayer.getName(), xPlayer.identifier)
            player = {
                id = sourcePlayerId,
                name = xPlayer.getName(),
                identifier = xPlayer.identifier,
                license = GetPlayerIdentifierByType(sourcePlayerId, 'license')
            }
        end
    end

    local color = amount >= 0 and 65280 or 16711680
    local embed = {
        {
            ["color"] = color,
            ["title"] = "Faction/Business Budget Log",
            ["description"] = string.format(
                "**Tổ chức:** %s (%s) | **Loại:** %s\n**Hành động:** %s\n**Số tiền:** $%s\n**Tổng ngân quỹ hiện tại:** $%s\n**Lý do:** %s\n**Thực hiện:** %s",
                factionName, factionTag, factionType == 'gov' and 'Chính phủ (Gov)' or 'Doanh nghiệp (Business)',
                action, absAmount, currentBudget, reason or "Không có lý do", playerInfo
            ),
            ["footer"] = {
                ["text"] = os.date("%c") .. " (Server Time).",
            },
        }
    }

    local centralLogged = false
    if GetResourceState('legacyWebhook') == 'started' then
        local success, accepted = pcall(function()
            return exports['legacyWebhook']:AuditTransaction({
                webhook = BUDGET_LOG_WEBHOOK,
                username = "Faction Budget Logs",
                category = "faction_budget",
                action = amount >= 0 and "budget_credit" or "budget_debit",
                status = "committed",
                sourceResource = GetInvokingResource() or GetCurrentResourceName(),
                reason = reason or "Không có lý do",
                requestId = requestId,
                player = player,
                account = "faction_budget",
                amount = absAmount,
                delta = amount,
                balanceBefore = balanceBefore,
                balanceAfter = currentBudget,
                title = "Faction/Business Budget Log",
                message = ("**Tổ chức:** %s (%s) | **Loại:** %s\n**Hành động:** %s\n**Thực hiện:** %s"):format(
                    factionName,
                    factionTag,
                    factionType == 'gov' and 'Chính phủ (Gov)' or 'Doanh nghiệp (Business)',
                    action,
                    playerInfo
                ),
                color = color,
                context = {
                    factionTag = factionTag,
                    factionName = factionName,
                    factionType = factionType,
                    source = sourcePlayerId,
                    action = action
                }
            })
        end)
        centralLogged = success and accepted == true
    end

    if centralLogged then
        return
    end

    if BUDGET_LOG_WEBHOOK ~= '' then
        PerformHttpRequest(BUDGET_LOG_WEBHOOK, function() end, 'POST', json.encode({
            username = "Faction Budget Logs",
            embeds = embed
        }), { ['Content-Type'] = 'application/json' })
    end
end

ESX.RegisterServerCallback('FactionPanel:server:DepositBudget', function(src, cb, factionId, amount)
    if not getPanelAccess(src, factionId, 'leader') then
        return cb(false, "Bạn không có quyền truy cập quỹ của tổ chức này.")
    end
    local xPlayer = ESX.GetPlayerFromId(src)
    amount = positiveInteger(amount)
    if not xPlayer or not amount then
        cb(false, "Số tiền không hợp lệ.")
        return
    end

    local faction = MySQL.query.await('SELECT tag, budget FROM faction WHERE id = ?', {factionId})
    if not faction or not faction[1] then
        cb(false, "Không tìm thấy dữ liệu tổ chức.")
        return
    end
    local factionTag = faction[1].tag

    local playerMoney = 0
    if GetResourceState("ox_inventory") == "started" then
        playerMoney = exports.ox_inventory:GetItemCount(src, 'money') or 0
    else
        playerMoney = xPlayer.getMoney()
    end

    if playerMoney < amount then
        cb(false, "Bạn không có đủ tiền mặt.")
        return
    end

    local removed
    if GetResourceState("ox_inventory") == "started" then
        removed = exports.ox_inventory:RemoveItem(src, 'money', amount) == true
    else
        xPlayer.removeMoney(amount)
        removed = true
    end
    if not removed then return cb(false, 'Không thể trừ tiền mặt.') end
    local requestId = ('panel-deposit:%s:%s:%s'):format(xPlayer.identifier, os.time(), math.random(100000, 999999))
    local changed, newBudget = applyFactionFinance(factionTag, {budgetDelta = amount, reason = 'Panel budget deposit', sourcePlayerId = src, requestId = requestId})
    if not changed then
        if GetResourceState('ox_inventory') == 'started' then exports.ox_inventory:AddItem(src, 'money', amount) else xPlayer.addMoney(amount) end
        return cb(false, 'Không thể cập nhật quỹ, tiền đã được hoàn lại.')
    end

    cb(true, newBudget)
end)

ESX.RegisterServerCallback('FactionPanel:server:WithdrawBudget', function(src, cb, factionId, amount)
    if not getPanelAccess(src, factionId, 'leader') then
        return cb(false, "Bạn không có quyền truy cập quỹ của tổ chức này.")
    end
    local xPlayer = ESX.GetPlayerFromId(src)
    amount = positiveInteger(amount)
    if not xPlayer or not amount then
        cb(false, "Số tiền không hợp lệ.")
        return
    end

    local faction = MySQL.query.await('SELECT tag, budget FROM faction WHERE id = ?', {factionId})
    if not faction or not faction[1] then
        cb(false, "Không tìm thấy dữ liệu tổ chức.")
        return
    end
    local factionTag = faction[1].tag
    if GetResourceState('ox_inventory') == 'started' and not exports.ox_inventory:CanCarryItem(src, 'money', amount) then
        return cb(false, 'Túi đồ không đủ chỗ.')
    end
    local requestId = ('panel-withdraw:%s:%s:%s'):format(xPlayer.identifier, os.time(), math.random(100000, 999999))
    local changed, newBudget = applyFactionFinance(factionTag, {budgetDelta = -amount, reason = 'Panel budget withdrawal', sourcePlayerId = src, requestId = requestId})
    if not changed then return cb(false, 'Số dư khả dụng của quỹ không đủ do đang có khoản dự phòng.') end
    local paid = true
    if GetResourceState('ox_inventory') == 'started' then
        paid = exports.ox_inventory:AddItem(src, 'money', amount) == true
    else
        xPlayer.addMoney(amount)
    end
    if not paid then
        applyFactionFinance(factionTag, {budgetDelta = amount, reason = 'Panel budget withdrawal rollback', sourcePlayerId = src, requestId = requestId .. ':rollback'})
        return cb(false, 'Không thể nhận tiền, giao dịch đã được hoàn tác.')
    end

    cb(true, newBudget)
end)

exports('AddFactionBudget', function(factionTag, amount, reason, sourcePlayerId, skipLog)
    amount = tonumber(amount)
    if not amount or amount == 0 or amount % 1 ~= 0 then return false end
    local success = applyFactionFinance(factionTag, {
        budgetDelta = amount,
        reserveDelta = 0,
        reason = reason or 'System change',
        sourcePlayerId = sourcePlayerId,
        skipLog = skipLog == true
    })
    return success == true
end)

exports('ChangeFactionBudget', function(factionTag, amount, reason, sourcePlayerId, requestId)
    amount = tonumber(amount)
    if not amount or amount == 0 or amount % 1 ~= 0 then return false, 0 end
    local success, budget = applyFactionFinance(factionTag, {
        budgetDelta = amount,
        reserveDelta = 0,
        reason = reason or 'System change',
        sourcePlayerId = sourcePlayerId,
        requestId = requestId
    })
    return success, budget
end)

exports('ApplyFactionFinance', applyFactionFinance)

exports('GetFactionFinancials', function(factionTag)
    local budget, reserved, available = getFactionFinancials(factionTag)
    return {budget = budget, reserved = reserved, available = available}
end)

exports('GetFactionBudget', function(factionTag)
    local budget = getFactionFinancials(factionTag)
    return budget
end)

exports('GetConfig', function()
    return Config
end)
