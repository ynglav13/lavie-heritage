
local FactionData = {}
local dataRequestTimes = {}

local function publicFactionData()
    local data = json.decode(json.encode(FactionData)) or {}
    for i = 1, #data do
        data[i].budget = nil
        data[i].reserved_budget = nil
        local permissions = json.decode(data[i].permission or '[]') or {}
        for p = 1, #permissions do permissions[p].identifier = nil end
        data[i].permission = json.encode(permissions)
    end
    return data
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
    end
end)

function LoadedFactionData(playerId)
    FactionData = MySQL.query.await('SELECT * FROM faction')
    local targetId = playerId
    if not targetId or targetId == 0 or targetId == "null" or targetId == "" then
        targetId = -1
    end
    TriggerClientEvent("FactionData:client:UpdateData", targetId, publicFactionData())
end

RegisterServerEvent("FactionData:server:GetAllData", function(playerId)
    local playerId = source
    if playerId <= 0 then return end
    local now = GetGameTimer()
    if dataRequestTimes[playerId] and now - dataRequestTimes[playerId] < 2000 then return end
    dataRequestTimes[playerId] = now
    TriggerClientEvent("FactionData:client:UpdateData", playerId, publicFactionData())
end)

RegisterServerEvent("FactionData:server:UpdateData", function(playerId)
    local playerId = source
    if playerId <= 0 then return end
    local now = GetGameTimer()
    if dataRequestTimes[playerId] and now - dataRequestTimes[playerId] < 2000 then return end
    dataRequestTimes[playerId] = now
    LoadedFactionData(playerId)
end)


local function isAdmin(playerId)
    return ESX.IsPlayerAdmin and ESX.IsPlayerAdmin(playerId) == true
end

local function isAuthorizedForFactionEdit(playerId, tag)
    if isAdmin(playerId) then return true end
    return type(tag) == 'string' and exports.factionCore:HasPlayerFactionPermission(playerId, tag, 'leader') == true
end

RegisterServerEvent("FactionEdit:server:Create", function(input)
    local playerId = source
    if not isAdmin(playerId) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit Create Faction!'):format(GetPlayerName(playerId), playerId))
        return
    end
    MySQL.Async.fetchAll('INSERT INTO faction (name, tag, type) VALUES (@name, @tag, @type)', {
        ['@name'] = input.name,
        ['@tag']  = input.tags,
        ['@type'] = input.type
    })
    LoadedFactionData()
end)

RegisterServerEvent("FactionEdit:server:CreateRank", function(input, tag)
    local playerId = source
    if not isAuthorizedForFactionEdit(playerId, tag) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit CreateRank!'):format(GetPlayerName(playerId), playerId))
        return
    end
    MySQL.Async.fetchAll('SELECT rank FROM faction WHERE tag = @tag', {
        ['@tag']  = tag,
    }, function(results)
        local rank = {}
        if not results[1].rank or results[1].rank == '[]' then
            rank = {
                { ['id'] = 1, ['name'] = input }
            }
        else
            local exportRank = json.decode(results[1].rank) or {}
            rank = exportRank

            table.insert(rank, {
                ['id'] = #exportRank + 1, ['name'] = input
            })
        end
        MySQL.Async.fetchAll('UPDATE faction SET rank = @rank WHERE tag = @tag', {
            ['@rank'] = json.encode(rank),
            ['@tag']  = tag,
        })
    end)
    LoadedFactionData()
end)

RegisterServerEvent("FactionEdit:server:CreateDivision", function(input, tag)
    local playerId = source
    if not isAuthorizedForFactionEdit(playerId, tag) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit CreateDivision!'):format(GetPlayerName(playerId), playerId))
        return
    end
    MySQL.Async.fetchAll('SELECT division FROM faction WHERE tag = @tag', {
        ['@tag']  = tag,
    }, function(results)
        local division = {}
        if not results[1].division or results[1].division == '[]' then
            division = {
                { ['id'] = 1, ['name'] = input }
            }
        else
            local exportDivision = json.decode(results[1].division) or {}
            division = exportDivision

            table.insert(division, {
                ['id'] = #exportDivision + 1, ['name'] = input
            })
        end
        MySQL.Async.fetchAll('UPDATE faction SET division = @division WHERE tag = @tag', {
            ['@division'] = json.encode(division),
            ['@tag']  = tag,
        })
    end)
    LoadedFactionData()
end)

ESX.RegisterServerCallback('FactionEdit:server:CreatePermission', function(src, cb, input, tag, factionType)
    if not isAuthorizedForFactionEdit(src, tag) then return cb({forbidden = true}) end
    if type(input) ~= 'table' then return cb({wrongName = true}) end
    local name = input.name
    if not name or name == "" then return cb({wrongName = true}) end

    MySQL.Async.fetchAll("SELECT identifier, faction FROM users WHERE LOWER(REPLACE(CONCAT(firstname, lastname), ' ', '')) = LOWER(REPLACE(?, ' ', ''))", {name}, function(result)
        if not result or not result[1] then return cb({wrongName = true}) end
        MySQL.Async.fetchAll('SELECT * FROM faction WHERE tag = @tag', {
            ['@tag']  = tag,
        }, function(results)
            if not results or not results[1] then return cb({wrongGroup = true}) end
            local matchingUsers = {}
            if factionType == 'gov' or factionType == 'business' then
                for i = 1, #result do
                    local decodedFaction = json.decode(result[i].faction or '{}') or {}
                    if decodedFaction.name == results[1].name then
                        matchingUsers[#matchingUsers + 1] = result[i]
                    end
                end
            end
            if #matchingUsers ~= 1 then return cb({wrongGroup = true}) end
            local identifier = matchingUsers[1].identifier

                local permission = {}
                if not results[1].permission or results[1].permission == '[]' then
                    local invite, rank, div, locker, radio = 0, 0, 0, 0, 0
                    if input.invite     == true then invite = 1 end
                    if input.rank       == true then rank   = 1 end
                    if input.division   == true then div    = 1 end
                    if input.locker     == true then locker = 1 end
                    if input.radio      == true then radio    = 1 end

                    if invite == 1 or rank == 1 or div == 1 or locker == 1 or radio == 1 then
                        permission = {
                            { ['name'] = input.name, ['identifier'] = identifier, ['invite'] = invite, ['rank'] = rank, ['division'] = div, ['locker'] = locker, ['radio'] = radio }
                        }
                    end
                else
                    local exportPermission = json.decode(results[1].permission) or {}
                    local checkCurrent = false
                    for i = 1, #exportPermission do
                        if exportPermission[i].identifier == identifier then
                            local invite, rank, div, locker, radio = 0, 0, 0, 0, 0
                            if input.invite     == true then invite = 1 end
                            if input.rank       == true then rank   = 1 end
                            if input.division   == true then div    = 1 end
                            if input.locker     == true then locker = 1 end
                            if input.radio      == true then radio  = 1 end

                            if invite == 1 or rank == 1 or div == 1 or locker == 1 or radio == 1 then
                                exportPermission[i].invite   = invite
                                exportPermission[i].rank     = rank
                                exportPermission[i].division = div
                                exportPermission[i].locker   = locker
                                exportPermission[i].radio    = radio
                            else
                                table.remove(exportPermission, i)
                            end
                            checkCurrent = true
                            permission = exportPermission
                        end
                    end
                    if checkCurrent == false then
                        permission = exportPermission
                        local invite, rank, div, locker, radio = 0, 0, 0, 0, 0
                        if input.invite     == true then invite = 1 end
                        if input.rank       == true then rank   = 1 end
                        if input.division   == true then div    = 1 end
                        if input.locker     == true then locker = 1 end
                        if input.radio      == true then radio = 1 end

                        if invite == 1 or rank == 1 or div == 1 or locker == 1 or radio == 1 then
                            table.insert(permission, {
                                ['name'] = input.name, ['identifier'] = identifier, ['invite'] = invite, ['rank'] = rank, ['division'] = div, ['locker'] = locker, ['radio'] = radio
                            })
                        end
                    
                    end
                end
                MySQL.Async.fetchAll('UPDATE faction SET permission = @permission WHERE tag = @tag', {
                    ['@permission'] = json.encode(permission),
                    ['@tag']  = tag,
                })

                LoadedFactionData()
                cb({success = true})
            end)
        end)
    end)
    LoadedFactionData()

RegisterServerEvent("FactionEdit:server:Edit", function(type, input, tag)
    local playerId = source
    if not isAuthorizedForFactionEdit(playerId, tag) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit FactionEdit:Edit!'):format(GetPlayerName(playerId), playerId))
        return
    end
    if type == 'name' then
        MySQL.Async.fetchAll('UPDATE faction SET name = @name WHERE tag = @tag', {
            ['@name'] = input,
            ['@tag']  = tag,
        })
    elseif type == 'tag' then
        MySQL.Async.fetchAll('UPDATE faction SET tag = @ntag WHERE tag = @tag', {
            ['@ntag'] = input,
            ['@tag']  = tag,
        })
    elseif type == 'colour' then
        MySQL.Async.fetchAll('UPDATE faction SET colour = @colour WHERE tag = @tag', {
            ['@colour'] = input,
            ['@tag']  = tag,
        })
    elseif type == 'type' then
        MySQL.Async.fetchAll('UPDATE faction SET type = @type WHERE tag = @tag', {
            ['@type'] = input,
            ['@tag']  = tag,
        })
    elseif type == 'category' then
        MySQL.Async.fetchAll('UPDATE faction SET category = @category WHERE tag = @tag', {
            ['@category'] = input,
            ['@tag']  = tag,
        })
    elseif type == 'rank' then
        MySQL.Async.fetchAll('SELECT rank FROM faction WHERE tag = @tag', {
            ['@tag']  = tag,
        }, function(results)
            local rank = {}
            local exportRank = json.decode(results[1].rank) or {}
            rank = exportRank
            for i = 1, #rank do
                if rank[i].id == input.id then
                    rank[i].name = input.name
                end
            end
            MySQL.Async.fetchAll('UPDATE faction SET rank = @rank WHERE tag = @tag', {
                ['@rank'] = json.encode(rank),
                ['@tag']  = tag,
            })
        end)
    elseif type == 'division' then
        MySQL.Async.fetchAll('SELECT division FROM faction WHERE tag = @tag', {
            ['@tag']  = tag,
        }, function(results)
            local division = {}
            local exportDivision = json.decode(results[1].division) or {}
            division = exportDivision
            for i = 1, #division do
                if division[i].id == input.id then
                    division[i].name = input.name
                end
            end
            MySQL.Async.fetchAll('UPDATE faction SET division = @division WHERE tag = @tag', {
                ['@division'] = json.encode(division),
                ['@tag']  = tag,
            })
        end)
    elseif type == 'permission' then
        MySQL.Async.fetchAll('SELECT permission FROM faction WHERE tag = @tag', {
            ['@tag']  = tag,
        }, function(results)
            
            local permission = {}
            local exportPermission = json.decode(results[1].permission) or {}
            permission = exportPermission
            for i = 1, #permission do
                if permission[i].name == input.name then
                    local invite, rank, div, locker, radio = 0, 0, 0, 0, 0
                    if input.invite     == true then invite = 1 end
                    if input.rank       == true then rank   = 1 end
                    if input.division   == true then div    = 1 end
                    if input.locker     == true then locker = 1 end
                    if input.radio      == true then radio = 1 end

                    if invite == 1 or rank == 1 or div == 1 or locker == 1 or radio == 1 then
                        permission[i].invite   = invite
                        permission[i].rank     = rank
                        permission[i].division = div
                        permission[i].locker   = locker
                        permission[i].radio    = radio

                    else
                        table.remove(permission, i)
                    end
                end
            end
            
            MySQL.Async.fetchAll('UPDATE faction SET permission = @permission WHERE tag = @tag', {
                ['@permission'] = json.encode(permission),
                ['@tag']  = tag,
            })
            LoadedFactionData()
        end)
    end
    LoadedFactionData()
end)

RegisterServerEvent("FactionEdit:server:Remove", function(type, input, tag)
    local playerId = source
    if not isAuthorizedForFactionEdit(playerId, tag) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit FactionEdit:Remove!'):format(GetPlayerName(playerId), playerId))
        return
    end
    if type == 'rank' then
        MySQL.Async.fetchAll('SELECT rank FROM faction WHERE tag = @tag', {
            ['@tag']  = tag,
        }, function(results)
            local rank = {}
            local exportRank = json.decode(results[1].rank) or {}
            rank = exportRank
            for i = 1, #rank do
                if rank[i].id == input then
                    table.remove(rank, i)
                end
            end
            MySQL.Async.fetchAll('UPDATE faction SET rank = @rank WHERE tag = @tag', {
                ['@rank'] = json.encode(rank),
                ['@tag']  = tag,
            })
        end)
    elseif type == 'division' then
        MySQL.Async.fetchAll('SELECT division FROM faction WHERE tag = @tag', {
            ['@tag']  = tag,
        }, function(results)
            local division = {}
            local exportDivision = json.decode(results[1].division) or {}
            division = exportDivision
            for i = 1, #division do
                if division[i].id == input then
                    table.remove(division, i)
                end
            end
            MySQL.Async.fetchAll('UPDATE faction SET division = @division WHERE tag = @tag', {
                ['@division'] = json.encode(division),
                ['@tag']  = tag,
            })
        end)
    end
    LoadedFactionData()
end)

ESX.RegisterServerCallback('FactionEdit:server:GetPlayersFaction', function(src, cb, tag, typee)
    if not isAuthorizedForFactionEdit(src, tag) then return cb({}) end
    MySQL.Async.fetchAll('SELECT * FROM faction WHERE tag = @tag', {
        ['@tag']  = tag,
    }, function(results)
        if not results or not results[1] then return cb({}) end
        local memberList = {}
        local factionName = results[1].name
        local query = ""
        if typee == 'gov' or typee == 'business' then
            query = "SELECT identifier, firstname, lastname, faction FROM users WHERE JSON_UNQUOTE(JSON_EXTRACT(faction, '$.name')) = ?"
        else
            return cb({})
        end

        MySQL.Async.fetchAll(query, {factionName}, function(players)
            for i = 1, #players do
                local faction = json.decode(players[i].faction)
                local division, rank = 'N/A', 'N/A'
                
                local div = json.decode(results[1].division)
                for d = 1, #div do
                    if tonumber(div[d].id) == tonumber(faction.division) then
                        division = div[d].name
                    end
                end

                local rankData = json.decode(results[1].rank)
                for r = 1, #rankData do
                    if rankData[r].id == faction.rank then
                        rank = rankData[r].name
                        break
                    end
                end

                table.insert(memberList, {
                    ['name'] = ('%s %s'):format(players[i].firstname, players[i].lastname),
                    ['rank'] = rank,
                    ['div']  = division,
                    ['identifier'] = players[i].identifier
                })
            end
            cb(memberList)
        end)
    end)
end)

RegisterServerEvent("FactionEdit:server:UninvitePlayer", function(identifier, type, info)
    local kickerId = source
    local xKicker = ESX.GetPlayerFromId(kickerId)
    if not xKicker then return end

    local allowed = false
    if isAdmin(kickerId) then
        allowed = true
    elseif info and info.faction then
        local factionTag = MySQL.scalar.await('SELECT tag FROM faction WHERE name = ?', {info.faction})
        allowed = factionTag and isAuthorizedForFactionEdit(kickerId, factionTag) or false
    end

    if not allowed then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit UninvitePlayer!'):format(xKicker.name, kickerId))
        return
    end

    local target = MySQL.single.await('SELECT faction FROM users WHERE identifier = ?', {identifier})
    local targetMembership = target and (json.decode(target.faction or '{}') or {}) or {}
    if not info or targetMembership.name ~= info.faction then return end

    local player = ESX.GetPlayers()
    local playerId
    for i = 1, #player do
        local xPlayer = ESX.GetPlayerFromId(player[i])
        if xPlayer and xPlayer.identifier == identifier then
                playerId = player[i]
                TriggerClientEvent('FactionEdit:client:SCM', player[i], player[i], ('~b~Faction Kicked~w~: Bạn đã bị đuổi ra khỏi tổ chức ~b~%s~w~ bởi ~b~%s~w~.'):format(info.faction, xKicker.getName()))
        end
    end
    if type == 'gov' or type == 'business' then
        RemovePlayerFactionPermissions(identifier)
        local faction = {
            ['name'] = 'Không có',
            ['rank'] = 0,
            ['division'] = 0
        }
        MySQL.update.await('UPDATE users SET faction = @faction WHERE identifier = @identifier', {
            ['@faction'] = json.encode(faction),
            ['@identifier']  = identifier,
        })
        TriggerEvent('FactionEvent:server:UpdatePlayerStatebag', playerId)
    end
end)

AddEventHandler('playerDropped', function()
    dataRequestTimes[source] = nil
end)

RegisterServerEvent("FactionEdit:server:CreateGarage", function(coords, tag)
    local playerId = source
    if not isAuthorizedForFactionEdit(playerId, tag) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit CreateGarage!'):format(GetPlayerName(playerId), playerId))
        return
    end
    MySQL.Async.fetchAll('SELECT garage FROM faction WHERE tag = @tag', {
        ['@tag']  = tag,
    }, function(results)
        local garage = {}
        if not results[1].garage or results[1].garage == '[]' then
            garage = {
                { ['id'] = 1, ['coords'] = coords }
            }
        else
            local exportGarage = json.decode(results[1].garage) or {}
            garage = exportGarage

            table.insert(garage, {
                ['id'] = #exportGarage + 1, ['coords'] = coords
            })
        end
        MySQL.Async.fetchAll('UPDATE faction SET garage = @garage WHERE tag = @tag', {
            ['@garage'] = json.encode(garage),
            ['@tag']  = tag,
        })
    end)
    LoadedFactionData()
end)

RegisterServerEvent("FactionEdit:server:EditGarage", function(coords, garageId, tag)
    local playerId = source
    if not isAuthorizedForFactionEdit(playerId, tag) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit EditGarage!'):format(GetPlayerName(playerId), playerId))
        return
    end
    MySQL.Async.fetchAll('SELECT garage FROM faction WHERE tag = @tag', {
        ['@tag']  = tag,
    }, function(results)
        local garage = json.decode(results[1].garage) or {}
        for i = 1, #garage do
            if garage[i].id == garageId then
                garage[i].coords = coords
            end
        end
        
        MySQL.Async.fetchAll('UPDATE faction SET garage = @garage WHERE tag = @tag', {
            ['@garage'] = json.encode(garage),
            ['@tag']  = tag,
        })
    end)
    LoadedFactionData()
end)

RegisterServerEvent("FactionEdit:server:RemoveGarage", function(tag, garageId)
    local playerId = source
    if not isAuthorizedForFactionEdit(playerId, tag) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit RemoveGarage!'):format(GetPlayerName(playerId), playerId))
        return
    end
    garageId = tonumber(garageId)
    if not garageId then return end

    MySQL.Async.fetchAll('SELECT garage FROM faction WHERE tag = @tag', {
        ['@tag']  = tag,
    }, function(results)
        if not results or not results[1] then return end

        local garage = json.decode(results[1].garage) or {}
        local newGarage = {}

        for i = 1, #garage do
            if tonumber(garage[i].id) ~= garageId then
                table.insert(newGarage, garage[i])
            end
        end

        MySQL.Async.fetchAll('UPDATE faction SET garage = @garage WHERE tag = @tag', {
            ['@garage'] = json.encode(newGarage),
            ['@tag']  = tag,
        }, function()
            MySQL.Async.fetchAll('DELETE FROM faction_vehicles WHERE type = @tag AND identifier = @identifier', {
                ['@tag'] = tag,
                ['@identifier'] = 'garage'..tostring(garageId)
            })
            LoadedFactionData()
        end)
    end)
end)

RegisterServerEvent("FactionEdit:server:CreateLocker", function(coords, tag)
    local playerId = source
    if not isAuthorizedForFactionEdit(playerId, tag) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit CreateLocker!'):format(GetPlayerName(playerId), playerId))
        return
    end
    MySQL.Async.fetchAll('SELECT locker FROM faction WHERE tag = @tag', {
        ['@tag']  = tag,
    }, function(results)
        local locker = {}
        if not results[1].locker or results[1].locker == '[]' then
            locker = {
                { ['id'] = 1, ['coords'] = coords }
            }
        else
            local exportLocker = json.decode(results[1].locker) or {}
            locker = exportLocker

            table.insert(locker, {
                ['id'] = #exportLocker + 1, ['coords'] = coords
            })
        end
        MySQL.Async.fetchAll('UPDATE faction SET locker = @locker WHERE tag = @tag', {
            ['@locker'] = json.encode(locker),
            ['@tag']  = tag,
        })
    end)
    LoadedFactionData()
end)

RegisterServerEvent("FactionEdit:server:EditLocker", function(coords, lockerId, tag)
    local playerId = source
    if not isAuthorizedForFactionEdit(playerId, tag) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit EditLocker!'):format(GetPlayerName(playerId), playerId))
        return
    end
    MySQL.Async.fetchAll('SELECT locker FROM faction WHERE tag = @tag', {
        ['@tag']  = tag,
    }, function(results)
        local locker = json.decode(results[1].locker) or {}
        for i = 1, #locker do
            if locker[i].id == lockerId then
                locker[i].coords = coords
            end
        end
        
        MySQL.Async.fetchAll('UPDATE faction SET locker = @locker WHERE tag = @tag', {
            ['@locker'] = json.encode(locker),
            ['@tag']  = tag,
        })
    end)
    LoadedFactionData()
end)

RegisterServerEvent("FactionEdit:server:RemoveLocker", function(tag, lockerId)
    local playerId = source
    if not isAuthorizedForFactionEdit(playerId, tag) then
        print(('[Security Warning] Player %s (ID: %s) tried to exploit RemoveLocker!'):format(GetPlayerName(playerId), playerId))
        return
    end
    MySQL.Async.fetchAll('SELECT locker FROM faction WHERE tag = @tag', {
        ['@tag']  = tag,
    }, function(results)
        if not results or not results[1] then return end
        local locker = json.decode(results[1].locker) or {}
        local newLocker = {}
        
        for i = 1, #locker do
            if locker[i].id ~= tonumber(lockerId) then
                table.insert(newLocker, locker[i])
            end
        end
        
        MySQL.Async.fetchAll('UPDATE faction SET locker = @locker WHERE tag = @tag', {
            ['@locker'] = json.encode(newLocker),
            ['@tag']  = tag,
        })
    end)
    LoadedFactionData()
end)
