local factionData = {}
local panelAccess = nil

RegisterNetEvent('FactionPanel:client:UpdateData', function(data)
    factionData = data
end)

function ConvertStringToRGB(string)
    local r, g, b = nil, nil, nil
    local count = 0
    for value in string.gmatch(string, "[^%s]+") do
        if count == 0 then r = string.gsub(value, ',', '')
        elseif count == 1 then g = string.gsub(value, ',', '')
        else b = string.gsub(value, ',', '') end
        count = count + 1
    end
    return r, g, b
end

function RgbMaptoHex(r, g, b)
    local rgb = (r * 0x10000) + (g * 0x100) + b
    return string.format("#%x", rgb)
end

function GetPlayerPermission(playerName)
    local FactionData = exports.factionCore.ExportFactionData()
    local perms = {
        leader  = false,
        members = false,
        role    = false,
        radio   = false,
        gun     = false,
    }

    if not playerName then return perms end
    local normalizedPlayerName = playerName:lower():gsub('%s+', ' ')

    for i, results in pairs(FactionData) do
        if results.tag == LocalPlayer.state.factionTag then
            permission = json.decode(results.permission)
            for i = 1, #permission do
                local permName = tostring(permission[i].name or '')
                local normalizedPermName = permName:lower():gsub('%s+', ' ')
                if normalizedPermName == normalizedPlayerName then
                    perms = permission[i]
                end
            end
        end
    end

    if v:GetPlayerAdmin() >= 5 then
        perms = {
            leader  = true,
            members = true,
            role    = true,
            radio   = true,
            gun     = true
        }
    end

    return perms
end

RegisterCommand('fpanel', function()
    ESX.TriggerServerCallback('FactionPanel:server:GetAccess', function(access)
        if not access then return v:noAccess(5) end

        panelAccess = access
        local perm = access.permissions
        if access.admin then
            SetNuiFocus(true, true)
            SendNUIMessage({ clear = true })
            ESX.TriggerServerCallback('FactionPanel:server:GetFactionType', function(cb)
                local open = false
                for i = 1, #cb do
                    open = true
                    local data = cb[i]
                    SendNUIMessage({
                        display = true,
                        edit    = 'select',
                        type    = data.type,
                        tag     = data.tag,
                        logo    = data.image,
                        name    = data.name,
                        id      = data.id
                    })
                end
                if not open then
                    SendNUIMessage({
                        display = true,
                        edit    = 'select',
                        nonFaction = true,
                    })
                end
            end, 'gov')
        else
            local myFactionId = access.factionId
            ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(result)
                if not result or not result[1] then
                    return ESX.ShowNotification('Không thể tải dữ liệu tổ chức.')
                end
                factionData = result
                if perm.leader then
                    ShowMenuGeneral(perm, myFactionId)
                elseif perm.members then
                    ShowMenuMembers(perm, myFactionId)
                elseif perm.role then
                    ShowMenuRanks(perm, myFactionId)
                elseif result[1].type == 'business' then
                    ShowMenuGarages(perm, myFactionId)
                end
            end, myFactionId)
        end
    end)
end)

RegisterNUICallback('SelectGroupType', function(data, cb)
    local reqType = data.type
    SendNUIMessage({ clear = true })
    ESX.TriggerServerCallback('FactionPanel:server:GetFactionType', function(result)
        local open = false
        for i = 1, #result do
            open = true
            local item = result[i]
            SendNUIMessage({
                display = true,
                edit    = 'select',
                type    = item.type,
                tag     = item.tag,
                logo    = item.image,
                name    = item.name,
                id      = item.id
            })
        end
        if not open then
            SendNUIMessage({
                display = true,
                edit    = 'select',
                nonFaction = true,
                type = reqType,
            })
        end
    end, reqType)
    cb('ok')
end)


RegisterNUICallback('SelectFaction', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(result)
        if not result or not result[1] then return cb('forbidden') end
        factionData = result
        local perm = panelAccess and panelAccess.permissions or GetPlayerPermission(LocalPlayer.state.playerName)

        if panelAccess and panelAccess.admin then
            local adminPerm = {leader = true, radio = true, role = true, members = true, gun = true}
            ShowMenuGeneral(adminPerm, data.id)
        elseif perm.leader then
            ShowMenuGeneral(perm, data.id)
        elseif perm.members then
            ShowMenuMembers(perm, data.id)
        elseif perm.role then
            ShowMenuRanks(perm, data.id)
        elseif result[1].type == 'business' then
            ShowMenuGarages(perm, data.id)
        end
    end, data.id)
    cb('ok')
end)

RegisterNUICallback('SelectMenu', function(data, cb)
    local perm = GetPlayerPermission(LocalPlayer.state.playerName)
    SendNUIMessage({ clear = true })

    if data.type == 'general' then
        ShowMenuGeneral(perm, data.id)
    elseif data.type == 'members' then
        ShowMenuMembers(perm, data.id)
    elseif data.type == 'permission' then
        ShowMenuPermission(perm, data.id)
    elseif data.type == 'rank' then
        ShowMenuRanks(perm, data.id)
    elseif data.type == 'division' then
        ShowMenuDivisions(perm, data.id)
    elseif data.type == 'garage' then
        ShowMenuGarages(perm, data.id)
    elseif data.type == 'locker' then
        ShowMenuLockers(perm, data.id)
    elseif data.type == 'budget' then
        ShowMenuBudget(perm, data.id)
    end

    cb('ok')
end)

RegisterNUICallback('DepositBudget', function(data, cb)
    local amount = tonumber(data.amount)
    if amount and amount > 0 then
        ESX.TriggerServerCallback('FactionPanel:server:DepositBudget', function(success, newBudget)
            if success then
                SendNUIMessage({
                    action = 'updateBudget',
                    budget = newBudget
                })
                exports.lv_notify:Notify({
                    title = 'Tổ chức',
                    message = ('Đã nộp $%s vào ngân quỹ.'):format(amount),
                    type = 'success'
                })
            else
                exports.lv_notify:Notify({
                    title = 'Tổ chức',
                    message = newBudget or 'Lỗi khi nộp tiền.',
                    type = 'error'
                })
            end
        end, data.id, amount)
    else
        exports.lv_notify:Notify({
            title = 'Tổ chức',
            message = 'Số tiền không hợp lệ.',
            type = 'error'
        })
    end
    cb('ok')
end)

RegisterNUICallback('WithdrawBudget', function(data, cb)
    local amount = tonumber(data.amount)
    if amount and amount > 0 then
        ESX.TriggerServerCallback('FactionPanel:server:WithdrawBudget', function(success, newBudget)
            if success then
                SendNUIMessage({
                    action = 'updateBudget',
                    budget = newBudget
                })
                exports.lv_notify:Notify({
                    title = 'Tổ chức',
                    message = ('Đã rút $%s từ ngân quỹ.'):format(amount),
                    type = 'success'
                })
            else
                exports.lv_notify:Notify({
                    title = 'Tổ chức',
                    message = newBudget or 'Lỗi khi rút tiền.',
                    type = 'error'
                })
            end
        end, data.id, amount)
    else
        exports.lv_notify:Notify({
            title = 'Tổ chức',
            message = 'Số tiền không hợp lệ.',
            type = 'error'
        })
    end
    cb('ok')
end)

RegisterNUICallback('EditFaction', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:EditFaction', function(cb)
        if cb then
            ShowMenuGeneral(GetPlayerPermission(LocalPlayer.state.playerName), data.id)
            TriggerServerEvent('FactionPanel:server:UpdateStateBag', data)
        end
    end, data)
    cb('ok')
end)

RegisterNUICallback('ResetFactionVehicles', function(data, cb)
    TriggerServerEvent('VehicleFaction:server:RestartVehicles', data.tag)
    exports.lv_notify:Notify({
        title = 'Tổ chức',
        message = 'Đã gửi yêu cầu reset phương tiện tổ chức ' .. data.tag,
        type = 'success'
    })
    cb('ok')
end)

RegisterNUICallback('EditMembers', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:EditMembers', function(cb)
        if cb then
            ShowMenuMembers(GetPlayerPermission(LocalPlayer.state.playerName), data.id)
            TriggerServerEvent('FactionPanel:server:UpdateStateBag', data)
        end
    end, data)
    cb('ok')
end)

RegisterNUICallback('InvitePlayer', function(data, cb)
    local targetId = tonumber(data.targetId)
    if targetId then
        ESX.TriggerServerCallback('FactionEvent:server:InvitePlayerToFaction', function(cbData)
            if cbData == 'Không tồn tại' then
                ESX.ShowNotification('Người chơi này không tồn tại trong máy chủ.')
            elseif cbData == 'inFaction' then
                ESX.ShowNotification('Người này đang trong 1 tổ chức chính phủ khác.')
            elseif cbData.name ~= nil then
                ESX.ShowNotification('Bạn đã gửi lời mời cho ' .. cbData.name .. ' tham gia vào tổ chức.')
            end
        end, targetId, LocalPlayer.state.factionName)
    end
    cb('ok')
end)

RegisterNUICallback('EditRank', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:EditRank', function(result)
        if result then
            ShowMenuRanks(GetPlayerPermission(LocalPlayer.state.playerName), data.id)
            TriggerServerEvent('FactionPanel:server:UpdateStateBag', data)
        end
    end, data.type, data)
    cb('ok')
end)

RegisterNUICallback('CreateRank', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:EditRank', function(cb)
        if cb then
            ShowMenuRanks(GetPlayerPermission(LocalPlayer.state.playerName), data.id)
        end
    end, 'create', data)
    cb('ok')
end)

RegisterNUICallback('EditDivision', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:EditDivision', function(cb)
        if cb then
            ShowMenuDivisions(GetPlayerPermission(LocalPlayer.state.playerName), data.id)
            TriggerServerEvent('FactionPanel:server:UpdateStateBag', data)
        end
    end, data.type, data)
    cb('ok')
end)

RegisterNUICallback('CreateDivision', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:EditDivision', function(cb)
        if cb then
            ShowMenuDivisions(GetPlayerPermission(LocalPlayer.state.playerName), data.id)
        end
    end, 'create', data)
    cb('ok')
end)

RegisterNUICallback('EditPermission', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:EditPermission', function(cb)
        if cb then
            ShowMenuPermission(GetPlayerPermission(LocalPlayer.state.playerName), data.id)
        end
    end, data.type, data)
    cb('ok')
end)

RegisterNUICallback('CreatePermission', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:EditPermission', function(cb)
        if cb then
            ShowMenuPermission(GetPlayerPermission(LocalPlayer.state.playerName), data.id)
        end
    end, 'create', data)
    cb('ok')
end)

RegisterNUICallback('CloseMenu', function(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({
        display = false,
        clear = true
    })
    cb('ok')
end)

function ShowMenuBudget(perm, id)
    ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(cb)
        SetNuiFocus(true, true)
        local data = cb[1]
        SendNUIMessage({
            display = true,
            edit = 'budget',
            permission = perm,
            id          = data.id,
            name        = data.name,
            tag         = data.tag,
            type        = data.type,
            budget      = data.budget
        })
    end, id)
end

function ShowMenuGeneral(perm, id)
    ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(cb)
        SetNuiFocus(true, true)
        local data = cb[1]
        SendNUIMessage({
            display = true,
            edit = 'general',
            permission = perm,
            id          = data.id,
            name        = data.name,
            tag         = data.tag,
            type        = data.type,
            logo        = data.image,
            category    = data.category,
            sirenbox    = data.sirenbox,
            colour      = RgbMaptoHex(ConvertStringToRGB(data.colour)),
        })
    end, id)
end

function ShowMenuMembers(perm, id)
    SetNuiFocus(true, true)
    SendNUIMessage({
        display = true,
        edit = 'members',
        update = false,
        id = id,
        permission = perm,
        type = factionData[1] and factionData[1].type or 'gov'
    })

    ESX.TriggerServerCallback('FactionPanel:server:GetPlayerData', function(data)        
        playerData = data
        for i = 1, #playerData do
            local groupData = {}
            if factionData[1].type == 'gov' or factionData[1].type == 'business' then 
                groupData = json.decode(playerData[i].faction)
            end
            if groupData then
                if groupData.name == factionData[1].name then
                    SendNUIMessage({
                        display = true,
                        edit = 'members',
                        update = true,
                        name = ('%s %s'):format(playerData[i].firstname, playerData[i].lastname),
                        rank = groupData.rank,
                        division = groupData.division,
                        badge = groupData.badgeNum or ""
                    })

                    local rankData = json.decode(factionData[1].rank)
                    for r = 1, #rankData do
                        SendNUIMessage({
                            display = true,
                            edit = 'members',
                            updateRank = true,
                            name = ('%s %s'):format(playerData[i].firstname, playerData[i].lastname),
                            rankId = rankData[r].id,
                            rankName = rankData[r].name,
                        })
                    end

                    local divisionData = json.decode(factionData[1].division)
                    for d = 1, #divisionData do
                        SendNUIMessage({
                            display = true,
                            edit = 'members',
                            updateDivision = true,
                            name = ('%s %s'):format(playerData[i].firstname, playerData[i].lastname),
                            divisionId = divisionData[d].id,
                            divisionName = divisionData[d].name,
                        })
                    end

                    SendNUIMessage({
                        display = true,
                        edit = 'members',
                        updateValue = true,
                        name = ('%s %s'):format(playerData[i].firstname, playerData[i].lastname),
                        rank = groupData.rank,
                        division = groupData.division,
                        badge = groupData.badgeNum or ""
                    })
                end
            end
        end
    end, id)
end

function ShowMenuPermission(perm, id)
    ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(cb)        
        local data = cb
        if not data or not data[1] then return end
        SetNuiFocus(true, true)
        SendNUIMessage({
            display = true,
            edit = 'permission',
            update = false,
            id = id,
            permission = perm,
            isCarDealer = tostring(data[1].tag or ''):lower() == 'cardealer',
            isCasino = tostring(data[1].tag or ''):lower() == 'casino',
        })
        local permission = json.decode(data[1].permission)
        for i = 1, #permission do
            SendNUIMessage({
                display = true,
                edit = 'permission',
                update = true,
                name = permission[i].name,
                leader = permission[i].leader,
                members = permission[i].members,
                role = permission[i].role,
                radio = permission[i].radio,
                gun = permission[i].gun,
                dealer_manage_employees = permission[i].dealer_manage_employees,
                dealer_manage_inventory = permission[i].dealer_manage_inventory,
                dealer_manage_finances = permission[i].dealer_manage_finances,
                dealer_sell = permission[i].dealer_sell,
                dealer_deliver = permission[i].dealer_deliver,
                dealer_view_records = permission[i].dealer_view_records,
                casino_cashier = permission[i].casino_cashier,
                casino_membership = permission[i].casino_membership,
                casino_ledger = permission[i].casino_ledger,
            })
        end
    end, id)
end

function ShowMenuRanks(perm, id)
    SetNuiFocus(true, true)
    SendNUIMessage({
        display = true,
        edit = 'rank',
        update = false,
        id = id,
        permission = perm,
        reset = true,
    })

    ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(cb)        
        local data = cb
        local rankData = json.decode(data[1].rank)
        for i = 1, #rankData do
            if i == #rankData then
                SendNUIMessage({
                    display = true,
                    edit = 'rank',
                    update = true,
                    rankId = rankData[i].id,
                    rankName = rankData[i].name,
                    canRemove = true,
                })
            else
                SendNUIMessage({
                    display = true,
                    edit = 'rank',
                    update = true,
                    rankId = rankData[i].id,
                    rankName = rankData[i].name
                }) 
            end
        end
    end, id)
end

function ShowMenuDivisions(perm, id)
    SetNuiFocus(true, true)
    SendNUIMessage({
        display = true,
        edit = 'division',
        update = false,
        id = id,
        permission = perm,
        reset = true,
    }) 
    ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(cb)        
        local data = cb
        local divisionData = json.decode(data[1].division)
        for i = 1, #divisionData do
            if i == #divisionData then
                SendNUIMessage({
                    display = true,
                    edit = 'division',
                    update = true,
                    divisionId = divisionData[i].id,
                    divisionName = divisionData[i].name,
                    canRemove = true,
                })
            else
                SendNUIMessage({
                    display = true,
                    edit = 'division',
                    update = true,
                    divisionId = divisionData[i].id,
                    divisionName = divisionData[i].name
                }) 
            end
        end
    end, id)
end

RegisterNUICallback('CreateFaction', function(data, cb)
    SendNUIMessage({
        clear = true,
    })
    ESX.TriggerServerCallback('FactionPanel:server:CreateFaction', function(success)
        if success then
            ESX.TriggerServerCallback('FactionPanel:server:GetFactionType', function(result)
                local open = false
                for i = 1, #result do
                    open = true
                    local item = result[i]
                    SendNUIMessage({
                        display = true,
                        edit    = 'select',
                        type    = item.type,
                        tag     = item.tag,
                        logo    = item.image,
                        name    = item.name,
                        id      = item.id
                    })
                end
                if not open then
                    SendNUIMessage({
                        display = true,
                        edit    = 'select',
                        nonFaction = true,
                        type = data.type,
                    })
                end
            end, data.type)
        end
    end, data)
    cb('ok')
end)

RegisterNUICallback('DeleteFaction', function(data, cb)
    SendNUIMessage({
        clear = true,
    })
    ESX.TriggerServerCallback('FactionPanel:server:DeleteFaction', function(factionType)
        if factionType then
            ESX.TriggerServerCallback('FactionPanel:server:GetFactionType', function(result)
                local open = false
                for i = 1, #result do
                    open = true
                    local item = result[i]
                    SendNUIMessage({
                        display = true,
                        edit    = 'select',
                        type    = item.type,
                        tag     = item.tag,
                        logo    = item.image,
                        name    = item.name,
                        id      = item.id
                    })
                end
                if not open then
                    SendNUIMessage({
                        display = true,
                        edit    = 'select',
                        nonFaction = true,
                        type = factionType,
                    })
                end
            end, factionType)
        end
    end, data)
    cb('ok')
end)

local zones = { ['AIRP'] = "Los Santos International Airport", ['ALAMO'] = "Alamo Sea", ['ALTA'] = "Alta", ['ARMYB'] = "Fort Zancudo", ['BANHAMC'] = "Banham Canyon Dr", ['BANNING'] = "Banning", ['BEACH'] = "Vespucci Beach", ['BHAMCA'] = "Banham Canyon", ['BRADP'] = "Braddock Pass", ['BRADT'] = "Braddock Tunnel", ['BURTON'] = "Burton", ['CALAFB'] = "Calafia Bridge", ['CANNY'] = "Raton Canyon", ['CCREAK'] = "Cassidy Creek", ['CHAMH'] = "Chamberlain Hills", ['CHIL'] = "Vinewood Hills", ['CHU'] = "Chumash", ['CMSW'] = "Chiliad Mountain State Wilderness", ['CYPRE'] = "Cypress Flats", ['DAVIS'] = "Davis", ['DELBE'] = "Del Perro Beach", ['DELPE'] = "Del Perro", ['DELSOL'] = "La Puerta", ['DESRT'] = "Grand Senora Desert", ['DOWNT'] = "Downtown", ['DTVINE'] = "Downtown Vinewood", ['EAST_V'] = "East Vinewood", ['EBURO'] = "El Burro Heights", ['ELGORL'] = "El Gordo Lighthouse", ['ELYSIAN'] = "Elysian Island", ['GALFISH'] = "Galilee", ['GOLF'] = "GWC and Golfing Society", ['GRAPES'] = "Grapeseed", ['GREATC'] = "Great Chaparral", ['HARMO'] = "Harmony", ['HAWICK'] = "Hawick", ['HORS'] = "Vinewood Racetrack", ['HUMLAB'] = "Humane Labs and Research", ['JAIL'] = "Bolingbroke Penitentiary", ['KOREAT'] = "Little Seoul", ['LACT'] = "Land Act Reservoir", ['LAGO'] = "Lago Zancudo", ['LDAM'] = "Land Act Dam", ['LEGSQU'] = "Legion Square", ['LMESA'] = "La Mesa", ['LOSPUER'] = "La Puerta", ['MIRR'] = "Mirror Park", ['MORN'] = "Morningwood", ['MOVIE'] = "Richards Majestic", ['MTCHIL'] = "Mount Chiliad", ['MTGORDO'] = "Mount Gordo", ['MTJOSE'] = "Mount Josiah", ['MURRI'] = "Murrieta Heights", ['NCHU'] = "North Chumash", ['NOOSE'] = "N.O.O.S.E", ['OCEANA'] = "Pacific Ocean", ['PALCOV'] = "Paleto Cove", ['PALETO'] = "Paleto Bay", ['PALFOR'] = "Paleto Forest", ['PALHIGH'] = "Palomino Highlands", ['PALMPOW'] = "Palmer-Taylor Power Station", ['PBLUFF'] = "Pacific Bluffs", ['PBOX'] = "Pillbox Hill", ['PROCOB'] = "Procopio Beach", ['RANCHO'] = "Rancho", ['RGLEN'] = "Richman Glen", ['RICHM'] = "Richman", ['ROCKF'] = "Rockford Hills", ['RTRAK'] = "Redwood Lights Track", ['SANAND'] = "San Andreas", ['SANCHIA'] = "San Chianski Mountain Range", ['SANDY'] = "Sandy Shores", ['SKID'] = "Mission Row", ['SLAB'] = "Stab City", ['STAD'] = "Maze Bank Arena", ['STRAW'] = "Strawberry", ['TATAMO'] = "Tataviam Mountains", ['TERMINA'] = "Terminal", ['TEXTI'] = "Textile City", ['TONGVAH'] = "Tongva Hills", ['TONGVAV'] = "Tongva Valley", ['VCANA'] = "Vespucci Canals", ['VESP'] = "Vespucci", ['VINE'] = "Vinewood", ['WINDF'] = "Ron Alternates Wind Farm", ['WVINE'] = "West Vinewood", ['ZANCUDO'] = "Zancudo River", ['ZP_ORT'] = "Port of South Los Santos", ['ZQ_UAR'] = "Davis Quartz" }

function ShowMenuGarages(perm, id)
    SetNuiFocus(true, true)
    SendNUIMessage({
        display = true,
        edit = 'garage',
        update = false,
        id = id,
        permission = perm,
        reset = true,
        type = factionData[1] and factionData[1].type or 'gov'
    }) 
    ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(cb)        
        local data = cb
        local garageData = json.decode(data[1].garage) or {}
        for i = 1, #garageData do
            local zoneName = zones[GetNameOfZone(garageData[i].coords.x, garageData[i].coords.y, garageData[i].coords.z)]
            local streetName = GetStreetNameFromHashKey(GetStreetNameAtCoord(garageData[i].coords.x, garageData[i].coords.y, garageData[i].coords.z))
            local locName = ('%s, %s'):format(streetName, zoneName)

            if i == #garageData then
                SendNUIMessage({
                    display = true,
                    edit = 'garage',
                    update = true,
                    garageId = garageData[i].id,
                    locationName = locName,
                    canRemove = true,
                    permission = perm,
                })
            else
                SendNUIMessage({
                    display = true,
                    edit = 'garage',
                    update = true,
                    garageId = garageData[i].id,
                    locationName = locName,
                    permission = perm,
                }) 
            end
        end
    end, id)
end

function ShowMenuLockers(perm, id)
    SetNuiFocus(true, true)
    SendNUIMessage({
        display = true,
        edit = 'locker',
        update = false,
        id = id,
        permission = perm,
        reset = true,
        type = factionData[1] and factionData[1].type or 'gov'
    }) 
    ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(cb)        
        local data = cb
        local lockerData = json.decode(data[1].locker) or {}
        for i = 1, #lockerData do
            local zoneName = zones[GetNameOfZone(lockerData[i].coords.x, lockerData[i].coords.y, lockerData[i].coords.z)]
            local streetName = GetStreetNameFromHashKey(GetStreetNameAtCoord(lockerData[i].coords.x, lockerData[i].coords.y, lockerData[i].coords.z))
            local locName = ('%s, %s'):format(streetName, zoneName)

            if i == #lockerData then
                SendNUIMessage({
                    display = true,
                    edit = 'locker',
                    update = true,
                    lockerId = lockerData[i].id,
                    locationName = locName,
                    canRemove = true,
                })
            else
                SendNUIMessage({
                    display = true,
                    edit = 'locker',
                    update = true,
                    lockerId = lockerData[i].id,
                    locationName = locName
                }) 
            end
        end
    end, id)
end

RegisterNUICallback('CreateGarage', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(cbData)
        if cbData and cbData[1] then
            TriggerServerEvent('FactionEdit:server:CreateGarage', GetEntityCoords(PlayerPedId()), cbData[1].tag)
            Wait(300)
            ShowMenuGarages(GetPlayerPermission(LocalPlayer.state.playerName), data.id)
            TriggerServerEvent('FactionData:server:UpdateData', GetPlayerServerId(PlayerId()))
        end
    end, data.id)
    cb('ok')
end)

RegisterNUICallback('EditGarage', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(cbData)
        if cbData and cbData[1] then
            TriggerServerEvent('FactionEdit:server:EditGarage', GetEntityCoords(PlayerPedId()), tonumber(data.garageId), cbData[1].tag)
            Wait(300)
            ShowMenuGarages(GetPlayerPermission(LocalPlayer.state.playerName), data.id)
            TriggerServerEvent('FactionData:server:UpdateData', GetPlayerServerId(PlayerId()))
        end
    end, data.id)
    cb('ok')
end)

RegisterNUICallback('RemoveGarage', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(cbData)
        if cbData and cbData[1] then
            TriggerServerEvent('FactionEdit:server:RemoveGarage', cbData[1].tag, data.garageId)
            Wait(300)
            ShowMenuGarages(GetPlayerPermission(LocalPlayer.state.playerName), data.id)
            TriggerServerEvent('FactionData:server:UpdateData', GetPlayerServerId(PlayerId()))
        end
    end, data.id)
    cb('ok')
end)

function ShowMenuGarageVehicles(id, tag, garageId)
    SetNuiFocus(true, true)
    SendNUIMessage({
        display = true,
        edit = 'garage_vehicles',
        update = false,
        id = id,
        garageId = garageId
    })

    ESX.TriggerServerCallback('FactionPanel:server:GetGarageVehicles', function(vehicles)
        if vehicles then
            for i = 1, #vehicles do
                SendNUIMessage({
                    display = true,
                    edit = 'garage_vehicles',
                    update = true,
                    plate = vehicles[i].plate,
                    name = vehicles[i].name,
                    lastDriver = vehicles[i].lastDriver
                })
            end
        end
    end, tag, garageId)
end

RegisterNUICallback('ManageGarageVehicles', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(cbData)
        if cbData and cbData[1] then
            ShowMenuGarageVehicles(data.id, cbData[1].tag, data.garageId)
        end
    end, data.id)
    cb('ok')
end)

RegisterNUICallback('CreateGarageVehicle', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(cbData)
        if cbData and cbData[1] then
            local vehicleHash = GetHashKey(tostring(data.model))
            if GetDisplayNameFromVehicleModel(vehicleHash) ~= 'CARNOTFOUND' then
                TriggerServerEvent('FactionVehicle:server:CreateVehicle', data.model, cbData[1].tag, data.garageId, data.plate, data.chooseColor)
                Wait(300)
                ShowMenuGarageVehicles(data.id, cbData[1].tag, data.garageId)
            else
                ESX.ShowNotification(('~r~Warning~w~: Phương tiện ~r~%s~w~ không hợp lệ, hãy kiểm tra lại.'):format(data.model))
            end
        end
    end, data.id)
    cb('ok')
end)

RegisterNUICallback('RemoveGarageVehicle', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(cbData)
        if cbData and cbData[1] then
            TriggerServerEvent('FactionVehicle:server:RemoveVehicle', data.plate, cbData[1].tag)
            Wait(300)
            ShowMenuGarageVehicles(data.id, cbData[1].tag, data.garageId)
        end
    end, data.id)
    cb('ok')
end)

RegisterNUICallback('CreateLocker', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(cbData)
        if cbData and cbData[1] then
            TriggerServerEvent('FactionEdit:server:CreateLocker', GetEntityCoords(PlayerPedId()), cbData[1].tag)
            Wait(300)
            ShowMenuLockers(GetPlayerPermission(LocalPlayer.state.playerName), data.id)
            TriggerServerEvent('FactionData:server:UpdateData', GetPlayerServerId(PlayerId()))
        end
    end, data.id)
    cb('ok')
end)

RegisterNUICallback('EditLocker', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(cbData)
        if cbData and cbData[1] then
            TriggerServerEvent('FactionEdit:server:EditLocker', GetEntityCoords(PlayerPedId()), tonumber(data.lockerId), cbData[1].tag)
            Wait(300)
            ShowMenuLockers(GetPlayerPermission(LocalPlayer.state.playerName), data.id)
            TriggerServerEvent('FactionData:server:UpdateData', GetPlayerServerId(PlayerId()))
        end
    end, data.id)
    cb('ok')
end)

RegisterNUICallback('RemoveLocker', function(data, cb)
    ESX.TriggerServerCallback('FactionPanel:server:GetFactionFromId', function(cbData)
        if cbData and cbData[1] then
            TriggerServerEvent('FactionEdit:server:RemoveLocker', cbData[1].tag, data.lockerId)
            Wait(300)
            ShowMenuLockers(GetPlayerPermission(LocalPlayer.state.playerName), data.id)
            TriggerServerEvent('FactionData:server:UpdateData', GetPlayerServerId(PlayerId()))
        end
    end, data.id)
    cb('ok')
end)
