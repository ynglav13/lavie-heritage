local FactionEdit = {}

RegisterNetEvent('FactionEdit:client:SCM', function(playerId, msg)
    TriggerEvent('chatMessage', "", {255, 255, 255}, msg)
end)

local zones = { ['AIRP'] = "Los Santos International Airport", ['ALAMO'] = "Alamo Sea", ['ALTA'] = "Alta", ['ARMYB'] = "Fort Zancudo", ['BANHAMC'] = "Banham Canyon Dr", ['BANNING'] = "Banning", ['BEACH'] = "Vespucci Beach", ['BHAMCA'] = "Banham Canyon", ['BRADP'] = "Braddock Pass", ['BRADT'] = "Braddock Tunnel", ['BURTON'] = "Burton", ['CALAFB'] = "Calafia Bridge", ['CANNY'] = "Raton Canyon", ['CCREAK'] = "Cassidy Creek", ['CHAMH'] = "Chamberlain Hills", ['CHIL'] = "Vinewood Hills", ['CHU'] = "Chumash", ['CMSW'] = "Chiliad Mountain State Wilderness", ['CYPRE'] = "Cypress Flats", ['DAVIS'] = "Davis", ['DELBE'] = "Del Perro Beach", ['DELPE'] = "Del Perro", ['DELSOL'] = "La Puerta", ['DESRT'] = "Grand Senora Desert", ['DOWNT'] = "Downtown", ['DTVINE'] = "Downtown Vinewood", ['EAST_V'] = "East Vinewood", ['EBURO'] = "El Burro Heights", ['ELGORL'] = "El Gordo Lighthouse", ['ELYSIAN'] = "Elysian Island", ['GALFISH'] = "Galilee", ['GOLF'] = "GWC and Golfing Society", ['GRAPES'] = "Grapeseed", ['GREATC'] = "Great Chaparral", ['HARMO'] = "Harmony", ['HAWICK'] = "Hawick", ['HORS'] = "Vinewood Racetrack", ['HUMLAB'] = "Humane Labs and Research", ['JAIL'] = "Bolingbroke Penitentiary", ['KOREAT'] = "Little Seoul", ['LACT'] = "Land Act Reservoir", ['LAGO'] = "Lago Zancudo", ['LDAM'] = "Land Act Dam", ['LEGSQU'] = "Legion Square", ['LMESA'] = "La Mesa", ['LOSPUER'] = "La Puerta", ['MIRR'] = "Mirror Park", ['MORN'] = "Morningwood", ['MOVIE'] = "Richards Majestic", ['MTCHIL'] = "Mount Chiliad", ['MTGORDO'] = "Mount Gordo", ['MTJOSE'] = "Mount Josiah", ['MURRI'] = "Murrieta Heights", ['NCHU'] = "North Chumash", ['NOOSE'] = "N.O.O.S.E", ['OCEANA'] = "Pacific Ocean", ['PALCOV'] = "Paleto Cove", ['PALETO'] = "Paleto Bay", ['PALFOR'] = "Paleto Forest", ['PALHIGH'] = "Palomino Highlands", ['PALMPOW'] = "Palmer-Taylor Power Station", ['PBLUFF'] = "Pacific Bluffs", ['PBOX'] = "Pillbox Hill", ['PROCOB'] = "Procopio Beach", ['RANCHO'] = "Rancho", ['RGLEN'] = "Richman Glen", ['RICHM'] = "Richman", ['ROCKF'] = "Rockford Hills", ['RTRAK'] = "Redwood Lights Track", ['SANAND'] = "San Andreas", ['SANCHIA'] = "San Chianski Mountain Range", ['SANDY'] = "Sandy Shores", ['SKID'] = "Mission Row", ['SLAB'] = "Stab City", ['STAD'] = "Maze Bank Arena", ['STRAW'] = "Strawberry", ['TATAMO'] = "Tataviam Mountains", ['TERMINA'] = "Terminal", ['TEXTI'] = "Textile City", ['TONGVAH'] = "Tongva Hills", ['TONGVAV'] = "Tongva Valley", ['VCANA'] = "Vespucci Canals", ['VESP'] = "Vespucci", ['VINE'] = "Vinewood", ['WINDF'] = "Ron Alternates Wind Farm", ['WVINE'] = "West Vinewood", ['ZANCUDO'] = "Zancudo River", ['ZP_ORT'] = "Port of South Los Santos", ['ZQ_UAR'] = "Davis Quartz" }

function draw3dText(coords, rgb, text)
    local r, g, b = nil, nil, nil
    local count = 1
    for token in string.gmatch(rgb, "[^%s]+") do
        if r == nil and count == 1 then r = token:gsub(',', '') end
        if g == nil and count == 2 then g = token:gsub(',', '') end
        if b == nil and count == 3 then b = token:gsub(',', '') end
        count = count + 1  
    end

    SetDrawOrigin(coords.x, coords.y, coords.z + 0.35, 0)
    
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextColour(255, 255, 255, 255)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(2, 0, 0, 0, 150)
    SetTextDropShadow()
    SetTextOutline()
    SetTextCentre(true)
    
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    
    ClearDrawOrigin()
end


local FactionData = {}

RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function(xPlayer)
    ESX.PlayerData = xPlayer
    ESX.PlayerLoaded = true
    TriggerServerEvent("FactionData:server:GetAllData", GetPlayerServerId(PlayerId()))
end)
local lockerZones = {}
local garageZones = {}

local function isNearFactionLocker(maxDistance)
    local factionTag = LocalPlayer.state.factionTag
    if not factionTag then return false end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local allowedDistance = tonumber(maxDistance) or 2.5
    local normalizedTag = factionTag:lower():gsub('%s+', '')

    for i = 1, #FactionData do
        local faction = FactionData[i]
        if faction.tag
            and faction.tag:lower():gsub('%s+', '') == normalizedTag
            and faction.locker and faction.locker ~= '[]' then
            local lockers = json.decode(faction.locker) or {}

            for j = 1, #lockers do
                local locker = lockers[j]
                local coords = vector3(locker.coords.x, locker.coords.y, locker.coords.z)
                if #(playerCoords - coords) <= allowedDistance then return true end
            end
        end
    end

    return false
end

exports('IsNearFactionLocker', isNearFactionLocker)

function RefreshLockerZones()
    for _, id in pairs(lockerZones) do
        exports.ox_target:removeZone(id)
    end
    lockerZones = {}

    for i = 1, #FactionData do
        if FactionData[i].locker and FactionData[i].locker ~= '[]' then
            local locker = json.decode(FactionData[i].locker) or {}
            for g = 1, #locker do
                local coords = vector3(locker[g].coords.x, locker[g].coords.y, locker[g].coords.z)
                local id = exports.ox_target:addSphereZone({
                    coords = coords,
                    radius = 1.5,
                    debug = false,
                    options = {
                        {
                            name = 'locker_'..FactionData[i].tag..'_'..locker[g].id,
                            icon = 'fas fa-box-open',
                            label = 'Mở Tủ Đồ',
                            distance = 2.5,
                            onSelect = function()
                                local myTag = LocalPlayer.state.factionTag
                                local myFaction = LocalPlayer.state.factionName
                                local normalizedMyTag = myTag and myTag:lower():gsub('%s+', '') or ""
                                local normalizedTargetTag = FactionData[i].tag:lower():gsub('%s+', '')
                                
                                local normalizedMyFaction = myFaction and myFaction:lower():gsub('%s+', '') or ""
                                local normalizedTargetFaction = FactionData[i].name:lower():gsub('%s+', '')

                                if normalizedMyTag == normalizedTargetTag or normalizedMyFaction == normalizedTargetFaction then
                                    ShowPlayerLocker(cache.serverId, FactionData[i].tag, FactionData[i].category, locker[g].id, FactionData[i].type)
                                else
                                    ESX.ShowNotification('Bạn không thuộc tổ chức này!')
                                end
                            end
                        }
                    }
                })
                table.insert(lockerZones, id)
            end
        end
    end
end

function RefreshGarageZones()
    for _, id in pairs(garageZones) do
        exports.ox_target:removeZone(id)
    end
    garageZones = {}

    for i = 1, #FactionData do
        if FactionData[i].garage and FactionData[i].garage ~= '[]' then
            local garage = json.decode(FactionData[i].garage) or {}
            for g = 1, #garage do
                local coords = vector3(garage[g].coords.x, garage[g].coords.y, garage[g].coords.z)
                local id = exports.ox_target:addSphereZone({
                    coords = coords,
                    radius = 2.0,
                    debug = false,
                    options = {
                        {
                            name = 'garage_'..FactionData[i].tag..'_'..garage[g].id,
                            icon = 'fas fa-car',
                            label = 'Mở Garage',
                            distance = 3.0,
                            onSelect = function()
                                local myTag = LocalPlayer.state.factionTag
                                local myFaction = LocalPlayer.state.factionName
                                local normalizedMyTag = myTag and myTag:lower():gsub('%s+', '') or ''
                                local normalizedTargetTag = FactionData[i].tag:lower():gsub('%s+', '')
                                local normalizedMyFaction = myFaction and myFaction:lower():gsub('%s+', '') or ''
                                local normalizedTargetFaction = FactionData[i].name:lower():gsub('%s+', '')

                                if normalizedMyTag == normalizedTargetTag or normalizedMyFaction == normalizedTargetFaction then
                                    TriggerEvent('VehicleFaction:client:ShowVehicleMenu', garage[g].id, 0)
                                else
                                    ESX.ShowNotification('Bạn không thuộc tổ chức này!')
                                end
                            end
                        }
                    }
                })
                table.insert(garageZones, id)
            end
        end
    end
end

RegisterNetEvent('FactionData:client:UpdateData', function(data)
    FactionData = data
    RefreshLockerZones()
    RefreshGarageZones()
end)

TriggerEvent('chat:addSuggestion', '/fpanel', 'Dùng để điều chỉnh Faction')


function ExportFactionData()
    TriggerServerEvent("FactionData:server:UpdateData", GetPlayerServerId(PlayerId()))
    Wait(100)
    return FactionData
end


function GetFactionData()
    return FactionData
end

local Keys = {
	["ESC"] = 322, ["F1"] = 288, ["F2"] = 289, ["F3"] = 170, ["F5"] = 166, ["F6"] = 167, ["F7"] = 168, ["F8"] = 169, ["F9"] = 56, ["F10"] = 57,
	["~"] = 243, ["1"] = 157, ["2"] = 158, ["3"] = 160, ["4"] = 164, ["5"] = 165, ["6"] = 159, ["7"] = 161, ["8"] = 162, ["9"] = 163, ["-"] = 84, ["="] = 83, ["BACKSPACE"] = 177,
	["TAB"] = 37, ["Q"] = 44, ["W"] = 32, ["E"] = 38, ["R"] = 45, ["T"] = 245, ["Y"] = 246, ["U"] = 303, ["P"] = 199, ["["] = 39, ["]"] = 40, ["ENTER"] = 18,
	["CAPS"] = 137, ["A"] = 34, ["S"] = 8, ["D"] = 9, ["F"] = 23, ["G"] = 47, ["H"] = 74, ["K"] = 311, ["L"] = 182,
	["LEFTSHIFT"] = 21, ["Z"] = 20, ["X"] = 73, ["C"] = 26, ["V"] = 0, ["B"] = 29, ["N"] = 249, ["M"] = 244, [","] = 82, ["."] = 81,
	["LEFTCTRL"] = 36, ["LEFTALT"] = 19, ["SPACE"] = 22, ["RIGHTCTRL"] = 70,
	["HOME"] = 213, ["PAGEUP"] = 10, ["PAGEDOWN"] = 11, ["DELETE"] = 178,
	["LEFT"] = 174, ["RIGHT"] = 175, ["TOP"] = 27, ["DOWN"] = 173,
	["NENTER"] = 201, ["N4"] = 108, ["N5"] = 60, ["N6"] = 107, ["N+"] = 96, ["N-"] = 97, ["N7"] = 117, ["N8"] = 61, ["N9"] = 118
}

Citizen.CreateThread(function()
    while ESX == nil or not ESX.PlayerLoaded do
        Wait(100)
    end
    TriggerServerEvent("FactionData:server:UpdateData", GetPlayerServerId(PlayerId()))
end)

Citizen.CreateThread(function()
    while true do
        local Sleep = 10000
        local IsLoaded = ESX.IsPlayerLoaded()
        if IsLoaded then
            if json.encode(FactionData) == '[]' then
                TriggerServerEvent("FactionData:server:UpdateData", GetPlayerServerId(PlayerId()))
                Wait(1000)
            end
            
            Sleep = 1000
            local playerPed = PlayerPedId()
            local coords = GetEntityCoords(playerPed)

            for i=1, #FactionData, 1 do
                if FactionData[i].locker and FactionData[i].locker ~= '[]' then
                    local locker = json.decode(FactionData[i].locker) or {}
                    for g = 1, #locker do
                        local lockerCoords = vector3(locker[g].coords.x, locker[g].coords.y, locker[g].coords.z)
                        local distance = #(coords - lockerCoords)
                        if distance < 10 then
                            Sleep = 0
                            draw3dText(lockerCoords, FactionData[i].colour, ('%s~w~ Locker (#%s)'):format(FactionData[i].tag, locker[g].id))
                        end
                    end
                end
                
                if LocalPlayer.state.factionType == 'gov' or LocalPlayer.state.factionType == 'business' then
                    if FactionData[i].garage and FactionData[i].garage ~= '[]' then
                        local garage = json.decode(FactionData[i].garage) or {}
                        for g = 1, #garage do
                            local garageCoords = vector3(garage[g].coords.x, garage[g].coords.y, garage[g].coords.z)
                            local distance = #(coords - garageCoords)
                            if distance < 10 then
                                Sleep = 0
                                draw3dText(garageCoords, FactionData[i].colour, ('%s~w~ Garage (#%s)'):format(FactionData[i].tag, garage[g].id))
                            end
                        end
                    end
                end
            end

        end
        Citizen.Wait(Sleep)
    end
end)




function ShowLockerPoliceGear(playerId, category)
    local options = {
        { title = 'Áo giáp (Armour)', icon = 'shield', onSelect = function() SetEntityHealth(PlayerPedId(), GetEntityMaxHealth(PlayerPedId())); TriggerServerEvent('FactionLocker:server:GivePlayerArmour', playerId, category) end },
        { title = 'Taser G2', icon = 'bolt', onSelect = function()
            local input = lib.inputDialog("25' Taser Cartridges", {
                {type = 'number', label = 'Nhập số lượng đạn cần lấy', description = '1 hộp có trọng lượng là 200 gram.', icon = 'hashtag'},
                {type = 'checkbox', label = 'Chỉ lấy đạn'},
            })
            if input then TriggerServerEvent('FactionLocker:server:GivePlayerTaser', playerId, category, input) end
        end },
        { title = 'Taser Y2', icon = 'bolt', onSelect = function()
            local input = lib.inputDialog("25' Taser Cartridges", {
                {type = 'number', label = 'Nhập số lượng đạn cần lấy', description = '1 hộp có trọng lượng là 200 gram.', icon = 'hashtag'},
                {type = 'checkbox', label = 'Chỉ lấy đạn'},
            })
            if input then TriggerServerEvent('FactionLocker:server:GivePlayerTaserY2', playerId, category, input) end
        end },
        { title = 'Baton rút ProLaps', icon = 'shield', onSelect = function() TriggerServerEvent('FactionLocker:server:GivePlayerColbaton', playerId, category) end },
        { title = 'Đèn pin (Flashlight)', icon = 'lightbulb', onSelect = function() TriggerServerEvent('FactionLocker:server:GivePlayerFlashlight', playerId, category) end },
        { title = 'Bình xịt (Spraycan)', icon = 'spray-can', onSelect = function() TriggerServerEvent('FactionLocker:server:GivePlayerSpraycan', playerId, category) end },
        { title = 'Còng tay (Handcuffs)', icon = 'link', onSelect = function() TriggerServerEvent('FactionLocker:server:GivePlayerHandcuffs', playerId, category) end },
        { title = 'Spike Strip', icon = 'road-spikes', onSelect = function() TriggerServerEvent('FactionLocker:server:GivePlayerSpikeStrip', playerId, category) end },
        { title = 'Megaphone', description = 'Loa phát thanh cầm tay', icon = 'bullhorn', onSelect = function() TriggerServerEvent('FactionLocker:server:GivePlayerMegaphone', playerId, category) end },
    }
    lib.registerContext({ id = 'faction_locker_police_gear', title = 'Trang bị Đặc nhiệm', menu = 'faction_locker_main', options = options })
    lib.showContext('faction_locker_police_gear')
end

function ShowLockerWeapons(playerId, category)
    local perm = GetPlayerPermission(LocalPlayer.state.playerName)
    local options = {}

    if perm.leader or perm.gun then
        table.insert(options, { title = 'Nhận súng ZN509', icon = 'gun', onSelect = function() TriggerServerEvent('FactionLocker:server:GivePlayerZN509', playerId, category) end })
    end

    table.insert(options, { title = 'Nhận băng đạn 9mm', icon = 'box', onSelect = function()
        TriggerServerEvent('FactionLocker:server:GivePlayerMagazine', playerId, category, 'magazine-9mm', '9mm')
    end })

    table.insert(options, { title = 'Nhận đạn 9mm', icon = 'box', onSelect = function()
        local input = lib.inputDialog("Đạn 9mm", {
            {type = 'number', label = 'Nhập số lượng đạn cần lấy', icon = 'hashtag', default = 30, min = 1}
        })
        if input and input[1] and input[1] > 0 then
            TriggerServerEvent('FactionLocker:server:GivePlayerAmmo', playerId, category, input[1], 'ammo-9', '9mm')
        end
    end })

    if perm.leader or perm.gun then
        table.insert(options, { title = 'Nhận súng H&L TMP7', icon = 'gun', onSelect = function() TriggerServerEvent('FactionLocker:server:GivePlayerHLTMP7', playerId, category) end })
        table.insert(options, { title = 'Nhận súng Tactical Carbine', icon = 'gun', onSelect = function() TriggerServerEvent('FactionLocker:server:GivePlayerTCarbine', playerId, category) end })
        table.insert(options, { title = 'Nhận súng AR-15', icon = 'gun', onSelect = function() TriggerServerEvent('FactionLocker:server:GivePlayerAR15', playerId, category) end })
        table.insert(options, { title = 'Nhận súng HK416', icon = 'gun', onSelect = function() TriggerServerEvent('FactionLocker:server:GivePlayerHK416', playerId, category) end })
        table.insert(options, { title = 'Nhận súng Shrewsbury E870', icon = 'gun', onSelect = function() TriggerServerEvent('FactionLocker:server:GivePlayerM870', playerId, category) end })
    end

    table.insert(options, { title = 'Nhận băng đạn 4.6mm', icon = 'box', onSelect = function()
        TriggerServerEvent('FactionLocker:server:GivePlayerMagazine', playerId, category, 'magazine-46mm', '4.6mm')
    end })

    table.insert(options, { title = 'Nhận đạn 4.6mm', icon = 'box', onSelect = function()
        local input = lib.inputDialog("Đạn 4.6mm", {
            {type = 'number', label = 'Nhập số lượng đạn cần lấy', icon = 'hashtag', default = 30, min = 1}
        })
        if input and input[1] and input[1] > 0 then
            TriggerServerEvent('FactionLocker:server:GivePlayerAmmo', playerId, category, input[1], 'ammo-pdw', '4.6mm')
        end
    end })

    table.insert(options, { title = 'Nhận băng đạn 5.56mm', icon = 'box', onSelect = function()
        TriggerServerEvent('FactionLocker:server:GivePlayerMagazine', playerId, category, 'magazine-556', '5.56mm')
    end })

    table.insert(options, { title = 'Nhận đạn 5.56mm', icon = 'box', onSelect = function()
        local input = lib.inputDialog("Đạn 5.56mm", {
            {type = 'number', label = 'Nhập số lượng đạn cần lấy', icon = 'hashtag', default = 30, min = 1}
        })
        if input and input[1] and input[1] > 0 then
            TriggerServerEvent('FactionLocker:server:GivePlayerAmmo', playerId, category, input[1], 'ammo-rifle', '5.56mm')
        end
    end })

    table.insert(options, { title = 'Nhận băng đạn 7.62mm', icon = 'box', onSelect = function()
        TriggerServerEvent('FactionLocker:server:GivePlayerMagazine', playerId, category, 'magazine-762', '7.62mm')
    end })

    table.insert(options, { title = 'Nhận đạn 7.62mm', icon = 'box', onSelect = function()
        local input = lib.inputDialog("Đạn 7.62mm", {
            {type = 'number', label = 'Nhập số lượng đạn cần lấy', icon = 'hashtag', default = 30, min = 1}
        })
        if input and input[1] and input[1] > 0 then
            TriggerServerEvent('FactionLocker:server:GivePlayerAmmo', playerId, category, input[1], 'ammo-rifle2', '7.62mm')
        end
    end })

    if perm.leader or perm.gun then
        table.insert(options, { title = 'Nhận súng Beanbag (Kèm đạn)', icon = 'gun', onSelect = function() TriggerServerEvent('FactionLocker:server:GivePlayerBeanbag', playerId, category) end })
        table.insert(options, { title = 'Nhận đạn Beanbag', icon = 'box', onSelect = function()
            local input = lib.inputDialog("Đạn Beanbag", {
                {type = 'number', label = 'Nhập số lượng đạn cần lấy', icon = 'hashtag', default = 10, min = 1}
            })
            if input and input[1] and input[1] > 0 then
                TriggerServerEvent('FactionLocker:server:GivePlayerAmmo', playerId, category, input[1], 'ammo-beanbag', 'Beanbag')
            end
        end })
        table.insert(options, { title = 'Nhận súng Less Launcher 40mm (Kèm đạn)', icon = 'gun', onSelect = function() TriggerServerEvent('FactionLocker:server:GivePlayerLessLauncher', playerId, category) end })
        table.insert(options, { title = 'Nhận đạn Shotgun', icon = 'box', onSelect = function()
            local input = lib.inputDialog("Đạn Shotgun", {
                {type = 'number', label = 'Nhập số lượng đạn cần lấy', icon = 'hashtag', default = 16, min = 1}
            })
            if input and input[1] and input[1] > 0 then
                TriggerServerEvent('FactionLocker:server:GivePlayerAmmo', playerId, category, input[1], 'ammo-shotgun', 'Shotgun')
            end
        end })
        table.insert(options, { title = 'Nhận đạn 40mm', icon = 'box', onSelect = function()
            local input = lib.inputDialog("Đạn 40mm", {
                {type = 'number', label = 'Nhập số lượng đạn cần lấy', icon = 'hashtag', default = 5, min = 1}
            })
            if input and input[1] and input[1] > 0 then
                TriggerServerEvent('FactionLocker:server:GivePlayerAmmo', playerId, category, input[1], 'ammo-40mm', '40mm')
            end
        end })
        table.insert(options, { title = 'Nhận đạn Taser', icon = 'box', onSelect = function()
            local input = lib.inputDialog("Đạn Taser", {
                {type = 'number', label = 'Nhập số lượng đạn cần lấy', icon = 'hashtag', default = 5, min = 1}
            })
            if input and input[1] and input[1] > 0 then
                TriggerServerEvent('FactionLocker:server:GivePlayerAmmo', playerId, category, input[1], 'ammo-taser', 'Taser')
            end
        end })
    end

    lib.registerContext({ id = 'faction_locker_weapons', title = 'Vũ khí & Đạn dược', menu = 'faction_locker_main', options = options })
    lib.showContext('faction_locker_weapons')
end

function ShowLockerMedicGear(playerId, category)
    local options = {
        { title = 'Hộp sơ cứu (Medkit)', description = 'Giá: $10,000', icon = 'kit-medical', onSelect = function() TriggerServerEvent('FactionLocker:server:GivePlayerMedkit', playerId, category) end },
        { title = 'Bình chữa cháy (Fire Extinguisher)', icon = 'fire-extinguisher', onSelect = function() TriggerServerEvent('FactionLocker:server:GivePlayerFireExtinguisher', playerId, category) end },
        { title = 'Đèn pin (Flashlight)', icon = 'lightbulb', onSelect = function() TriggerServerEvent('FactionLocker:server:GivePlayerFlashlight', playerId, category) end },
    }
    lib.registerContext({ id = 'faction_locker_medic_gear', title = 'Trang bị Y tế & Cứu hộ', menu = 'faction_locker_main', options = options })
    lib.showContext('faction_locker_medic_gear')
end

function ShowLockerBusinessGear(playerId, category)
    local options = {}
    local myTag = LocalPlayer.state.factionTag
    local upperTag = myTag and string.upper(myTag) or ""
    local itemsList = Config.BusinessLocker[upperTag] or Config.BusinessLocker[myTag] or Config.BusinessLocker['DEFAULT'] or {}
    
    for i = 1, #itemsList do
        local itemInfo = itemsList[i]
        table.insert(options, {
            title = itemInfo.label,
            description = ('Giá: $%s'):format(itemInfo.price),
            icon = 'shopping-basket',
            onSelect = function()
                local input = lib.inputDialog('Nhập số lượng', {
                    {type = 'number', label = 'Số lượng', default = 1, min = 1, icon = 'hashtag'}
                })
                if input and input[1] and input[1] > 0 then
                    TriggerServerEvent('FactionLocker:server:BuyBusinessItem', itemInfo.item, itemInfo.price, itemInfo.label, input[1])
                end
            end
        })
    end
    lib.registerContext({ id = 'faction_locker_business_gear', title = 'Nhập hàng hoá', menu = 'faction_locker_main', options = options })
    lib.showContext('faction_locker_business_gear')
end

local currentLockerContext = {}

function OpenArmoryNUI(category)
    if not currentLockerContext.tag then return end
    currentLockerContext.category = category or 'main'

    local playerId = currentLockerContext.playerId
    local tag = currentLockerContext.tag
    local categoryType = currentLockerContext.categoryType
    local lockerId = currentLockerContext.id
    local fType = currentLockerContext.fType
    local perm = GetPlayerPermission(LocalPlayer.state.playerName)

    local categories = {}
    if fType ~= 'business' then
        table.insert(categories, { id = 'personal', label = 'Tủ đồ cá nhân', sublabel = 'Kho đồ cá nhân', icon = 'fa-solid fa-box-open' })
    end
    if categoryType == 'police' then
        table.insert(categories, { id = 'weapons', label = 'Vũ khí & Đạn', sublabel = 'Kho vũ khí tổ chức', icon = 'fa-solid fa-gun' })
        table.insert(categories, { id = 'police_gear', label = 'Trang bị Đặc nhiệm', sublabel = 'Giáp, Taser, Còng...', icon = 'fa-solid fa-shield-halved' })
    elseif categoryType == 'medic' then
        table.insert(categories, { id = 'medic_gear', label = 'Trang bị Y tế', sublabel = 'Cứu hộ & Y tế', icon = 'fa-solid fa-kit-medical' })
    end
    if fType == 'business' then
        table.insert(categories, { id = 'business_gear', label = 'Nhập hàng hoá', sublabel = 'Vật phẩm kinh doanh', icon = 'fa-solid fa-cart-shopping' })
    end

    if #categories > 0 and currentLockerContext.category == 'main' then
        currentLockerContext.category = categories[1].id
    end

    local items = {}
    local activeCat = currentLockerContext.category

    if activeCat == 'personal' then
        table.insert(items, {
            label = 'Tủ đồ cá nhân (Equipment)',
            desc = 'Mở kho lưu trữ đồ đạc cá nhân của bạn',
            icon = 'box-open',
            action = 'open_stash',
            stashInfo = { tag = tag, badge = LocalPlayer.state.factionBadgeNum, name = LocalPlayer.state.playerName }
        })
    elseif activeCat == 'weapons' then
        if perm.leader or perm.gun then
            table.insert(items, { label = 'Súng ZN509', desc = 'Cấp phát súng ZN509', icon = 'WEAPON_ZN509', action = 'give_zn509' })
            table.insert(items, { label = 'Súng H&L TMP7', desc = 'Cấp phát súng H&L TMP7', icon = 'WEAPON_HLTMP7', action = 'give_hltmp7' })
            table.insert(items, { label = 'Súng Vom Feuer Carbine', desc = 'Cấp phát súng Vom Feuer Carbine', icon = 'WEAPON_VFCARBINE', action = 'give_ar15' })
            table.insert(items, { label = 'Súng Vom Feuer Special Carbine', desc = 'Cấp phát súng Vom Feuer Special Carbine', icon = 'WEAPON_SPCARBINE', action = 'give_hk416' })
            table.insert(items, { label = 'Súng Shrewsbury E870', desc = 'Cấp phát shotgun Shrewsbury E870', icon = 'WEAPON_M870_SHOTGUN', action = 'give_m870' })
            table.insert(items, { label = 'Súng Beanbag (Kèm đạn)', desc = 'Súng đạn cao su không gây sát thương', icon = 'WEAPON_BEANBAG', action = 'give_beanbag' })
            table.insert(items, { label = 'Súng Less Launcher 40mm (Kèm đạn)', desc = 'Súng phóng lựu giải tán đám đông', icon = 'WEAPON_LESSLAUNCHER', action = 'give_lesslauncher' })
        end
        table.insert(items, { label = 'Băng đạn 9mm', desc = 'Băng đạn súng ngắn', icon = 'magazine_9mm', action = 'give_mag_9mm' })
        table.insert(items, { label = 'Đạn 9mm', desc = 'Đạn rời 9mm', icon = 'ammo-9', action = 'input_ammo_9mm' })
        table.insert(items, { label = 'Băng đạn 4.6mm', desc = 'Băng đạn súng H&L TMP7', icon = 'magazine_pdw', action = 'give_mag_46mm' })
        table.insert(items, { label = 'Đạn 4.6mm', desc = 'Đạn rời 4.6mm', icon = 'ammo-pdw', action = 'input_ammo_46mm' })
        table.insert(items, { label = 'Băng đạn 5.56mm', desc = 'Băng đạn tiểu liên / rifle', icon = 'magazine_556', action = 'give_mag_556' })
        table.insert(items, { label = 'Đạn 5.56mm', desc = 'Đạn rời 5.56mm', icon = 'ammo-rifle', action = 'input_ammo_556' })
        table.insert(items, { label = 'Băng đạn 7.62mm', desc = 'Băng đạn súng trường', icon = 'magazine_762', action = 'give_mag_762' })
        table.insert(items, { label = 'Đạn 7.62mm', desc = 'Đạn rời 7.62mm', icon = 'ammo-rifle2', action = 'input_ammo_762' })
        if perm.leader or perm.gun then
            table.insert(items, { label = 'Đạn Beanbag', desc = 'Đạn cao su', icon = 'ammo-beanbag', action = 'input_ammo_beanbag' })
            table.insert(items, { label = 'Đạn Shotgun', desc = 'Đạn rời dành cho shotgun', icon = 'ammo-shotgun', action = 'input_ammo_shotgun' })
            table.insert(items, { label = 'Đạn 40mm', desc = 'Đạn phóng lựu 40mm', icon = 'ammo-40mm', action = 'input_ammo_40mm' })
            table.insert(items, { label = 'Đạn Taser', desc = 'Đạn điện Taser', icon = 'ammo-taser', action = 'input_ammo_taser' })
        end
    elseif activeCat == 'police_gear' then
        table.insert(items, { label = 'Áo giáp (Armour)', desc = 'Phôi giáp chống đạn tiêu chuẩn', icon = 'armour', action = 'give_armour' })
        table.insert(items, { label = 'Taser G2', desc = 'Súng điện Taser G2', icon = 'WEAPON_STUNGUN', action = 'input_taser' })
        table.insert(items, { label = 'Taser Y2', desc = 'Súng điện Taser Y2', icon = 'WEAPON_Y2', action = 'input_tasery2' })
        table.insert(items, { label = 'Baton rút ProLaps', desc = 'Gậy baton chuyên dụng cảnh sát', icon = 'WEAPON_COLBATON', action = 'give_colbaton' })
        table.insert(items, { label = 'Đèn pin (Flashlight)', desc = 'Đèn pin siêu sáng', icon = 'WEAPON_FLASHLIGHT', action = 'give_flashlight' })
        table.insert(items, { label = 'Bình xịt (Spraycan)', desc = 'Bình xịt cay', icon = 'WEAPON_SPRAYCAN', action = 'give_spraycan' })
        table.insert(items, { label = 'Còng tay (Handcuffs)', desc = 'Còng tay khống chế', icon = 'handcuffs', action = 'give_handcuffs' })
        table.insert(items, { label = 'Spike Strip', desc = 'Dải đinh chặn xe', icon = 'spike_strip', action = 'give_spikestrip' })
        table.insert(items, { label = 'Megaphone', desc = 'Loa phát thanh cầm tay', icon = 'megaphone', action = 'give_megaphone' })
        table.insert(items, { label = 'Súng Vapid SpeedLidar 4', desc = 'Súng bắn tốc độ Vapid SpeedLidar 4', icon = 'WEAPON_SPEEDLIDAR4', action = 'give_speedlidar4' })
    elseif activeCat == 'medic_gear' then
        table.insert(items, { label = 'Hộp sơ cứu (Medkit)', desc = 'Hộp sơ cứu khẩn cấp', price = 10000, icon = 'medkit', action = 'give_medkit' })
        table.insert(items, { label = 'Bình chữa cháy', desc = 'Bình chữa cháy dập lửa', icon = 'WEAPON_FIREEXTINGUISHER', action = 'give_fireextinguisher' })
        table.insert(items, { label = 'Đèn pin (Flashlight)', desc = 'Đèn pin soi cứu hộ', icon = 'WEAPON_FLASHLIGHT', action = 'give_flashlight' })
    elseif activeCat == 'business_gear' then
        local myTag = LocalPlayer.state.factionTag
        local upperTag = myTag and string.upper(myTag) or ""
        local itemsList = Config.BusinessLocker[upperTag] or Config.BusinessLocker[myTag] or Config.BusinessLocker['DEFAULT'] or {}
        for i = 1, #itemsList do
            local itemInfo = itemsList[i]
            table.insert(items, {
                label = itemInfo.label,
                desc = ('Nhập hàng hoá %s'):format(itemInfo.label),
                price = itemInfo.price,
                icon = itemInfo.item,
                action = 'buy_business_item',
                rawItem = itemInfo
            })
        end
    end

    SetNuiFocus(true, true)
    SendNUIMessage({
        display = true,
        edit = 'armoryMenu',
        reset = true,
        tag = tag,
        lockerId = lockerId,
        category = activeCat,
        categories = categories,
        results = #items > 0,
        nomore = #items == 0,
        items = items
    })
end

function ShowPlayerLocker(playerId, tag, category, id, fType)
    TriggerServerEvent("FactionData:server:UpdateData", GetPlayerServerId(PlayerId()))
    currentLockerContext = {
        playerId = playerId,
        tag = tag,
        categoryType = category,
        id = id,
        fType = fType,
        category = 'main'
    }
    OpenArmoryNUI('main')
end

RegisterNUICallback('SwitchArmoryCategory', function(data, cb)
    if data.category then
        OpenArmoryNUI(data.category)
    end
    cb('ok')
end)

RegisterNUICallback('ArmoryAction', function(data, cb)
    local action = data.action
    local itemData = data.data or {}
    local playerId = currentLockerContext.playerId or GetPlayerServerId(PlayerId())
    local category = currentLockerContext.categoryType or LocalPlayer.state.factionCategory

    if action == 'open_stash' then
        SetNuiFocus(false, false)
        SendNUIMessage({ display = false })
        local stashInfo = itemData.stashInfo or {}
        local badge = stashInfo.badge
        local tag = stashInfo.tag or 'GOV'
        local stashId = nil
        if badge and badge ~= 0 and badge ~= '' then
            stashId = ('locker_%s_%s'):format(tag, badge)
        else
            stashId = ('locker_%s_%s'):format(tag, (stashInfo.name or ''):gsub('%s', '_'))
        end
        local registered = lib.callback.await('FactionLocker:server:CreateStash', false, stashId)
        if registered then
            exports.ox_inventory:openInventory('stash', stashId)
        else
            lib.notify({ type = 'error', description = 'Không thể mở tủ đồ cá nhân' })
        end

    elseif action == 'give_zn509' then
        TriggerServerEvent('FactionLocker:server:GivePlayerZN509', playerId, category)
    elseif action == 'give_hltmp7' then
        TriggerServerEvent('FactionLocker:server:GivePlayerHLTMP7', playerId, category)
    elseif action == 'give_tcarbine' then
        TriggerServerEvent('FactionLocker:server:GivePlayerTCarbine', playerId, category)
    elseif action == 'give_ar15' then
        TriggerServerEvent('FactionLocker:server:GivePlayerAR15', playerId, category)
    elseif action == 'give_hk416' then
        TriggerServerEvent('FactionLocker:server:GivePlayerHK416', playerId, category)
    elseif action == 'give_m870' then
        TriggerServerEvent('FactionLocker:server:GivePlayerM870', playerId, category)
    elseif action == 'give_beanbag' then
        TriggerServerEvent('FactionLocker:server:GivePlayerBeanbag', playerId, category)
    elseif action == 'give_lesslauncher' then
        TriggerServerEvent('FactionLocker:server:GivePlayerLessLauncher', playerId, category)

    elseif action == 'give_mag_9mm' then
        TriggerServerEvent('FactionLocker:server:GivePlayerMagazine', playerId, category, 'magazine-9mm', '9mm')
    elseif action == 'give_mag_46mm' then
        TriggerServerEvent('FactionLocker:server:GivePlayerMagazine', playerId, category, 'magazine-46mm', '4.6mm')
    elseif action == 'give_mag_556' then
        TriggerServerEvent('FactionLocker:server:GivePlayerMagazine', playerId, category, 'magazine-556', '5.56mm')
    elseif action == 'give_mag_762' then
        TriggerServerEvent('FactionLocker:server:GivePlayerMagazine', playerId, category, 'magazine-762', '7.62mm')

    elseif action == 'input_ammo_9mm' then
        SetNuiFocus(false, false)
        SendNUIMessage({ display = false })
        local input = lib.inputDialog("Đạn 9mm", {
            {type = 'number', label = 'Nhập số lượng đạn cần lấy', icon = 'hashtag', default = 30, min = 1}
        })
        if input and input[1] and input[1] > 0 then
            TriggerServerEvent('FactionLocker:server:GivePlayerAmmo', playerId, category, input[1], 'ammo-9', '9mm')
        end
    elseif action == 'input_ammo_46mm' then
        SetNuiFocus(false, false)
        SendNUIMessage({ display = false })
        local input = lib.inputDialog("Đạn 4.6mm", {
            {type = 'number', label = 'Nhập số lượng đạn cần lấy', icon = 'hashtag', default = 30, min = 1}
        })
        if input and input[1] and input[1] > 0 then
            TriggerServerEvent('FactionLocker:server:GivePlayerAmmo', playerId, category, input[1], 'ammo-pdw', '4.6mm')
        end
    elseif action == 'input_ammo_556' then
        SetNuiFocus(false, false)
        SendNUIMessage({ display = false })
        local input = lib.inputDialog("Đạn 5.56mm", {
            {type = 'number', label = 'Nhập số lượng đạn cần lấy', icon = 'hashtag', default = 30, min = 1}
        })
        if input and input[1] and input[1] > 0 then
            TriggerServerEvent('FactionLocker:server:GivePlayerAmmo', playerId, category, input[1], 'ammo-rifle', '5.56mm')
        end
    elseif action == 'input_ammo_762' then
        SetNuiFocus(false, false)
        SendNUIMessage({ display = false })
        local input = lib.inputDialog("Đạn 7.62mm", {
            {type = 'number', label = 'Nhập số lượng đạn cần lấy', icon = 'hashtag', default = 30, min = 1}
        })
        if input and input[1] and input[1] > 0 then
            TriggerServerEvent('FactionLocker:server:GivePlayerAmmo', playerId, category, input[1], 'ammo-rifle2', '7.62mm')
        end
    elseif action == 'input_ammo_beanbag' then
        SetNuiFocus(false, false)
        SendNUIMessage({ display = false })
        local input = lib.inputDialog("Đạn Beanbag", {
            {type = 'number', label = 'Nhập số lượng đạn cần lấy', icon = 'hashtag', default = 10, min = 1}
        })
        if input and input[1] and input[1] > 0 then
            TriggerServerEvent('FactionLocker:server:GivePlayerAmmo', playerId, category, input[1], 'ammo-beanbag', 'Beanbag')
        end
    elseif action == 'input_ammo_shotgun' then
        SetNuiFocus(false, false)
        SendNUIMessage({ display = false })
        local input = lib.inputDialog("Đạn Shotgun", {
            {type = 'number', label = 'Nhập số lượng đạn cần lấy', icon = 'hashtag', default = 16, min = 1}
        })
        if input and input[1] and input[1] > 0 then
            TriggerServerEvent('FactionLocker:server:GivePlayerAmmo', playerId, category, input[1], 'ammo-shotgun', 'Shotgun')
        end
    elseif action == 'input_ammo_40mm' then
        SetNuiFocus(false, false)
        SendNUIMessage({ display = false })
        local input = lib.inputDialog("Đạn 40mm", {
            {type = 'number', label = 'Nhập số lượng đạn cần lấy', icon = 'hashtag', default = 5, min = 1}
        })
        if input and input[1] and input[1] > 0 then
            TriggerServerEvent('FactionLocker:server:GivePlayerAmmo', playerId, category, input[1], 'ammo-40mm', '40mm')
        end
    elseif action == 'input_ammo_taser' then
        SetNuiFocus(false, false)
        SendNUIMessage({ display = false })
        local input = lib.inputDialog("Đạn Taser", {
            {type = 'number', label = 'Nhập số lượng đạn cần lấy', icon = 'hashtag', default = 5, min = 1}
        })
        if input and input[1] and input[1] > 0 then
            TriggerServerEvent('FactionLocker:server:GivePlayerAmmo', playerId, category, input[1], 'ammo-taser', 'Taser')
        end

    elseif action == 'give_armour' then
        SetEntityHealth(PlayerPedId(), GetEntityMaxHealth(PlayerPedId()))
        TriggerServerEvent('FactionLocker:server:GivePlayerArmour', playerId, category)
    elseif action == 'input_taser' then
        SetNuiFocus(false, false)
        SendNUIMessage({ display = false })
        local input = lib.inputDialog("25' Taser Cartridges", {
            {type = 'number', label = 'Nhập số lượng đạn cần lấy', description = '1 hộp có trọng lượng là 200 gram.', icon = 'hashtag'},
            {type = 'checkbox', label = 'Chỉ lấy đạn'},
        })
        if input then TriggerServerEvent('FactionLocker:server:GivePlayerTaser', playerId, category, input) end
    elseif action == 'input_tasery2' then
        SetNuiFocus(false, false)
        SendNUIMessage({ display = false })
        local input = lib.inputDialog("25' Taser Cartridges", {
            {type = 'number', label = 'Nhập số lượng đạn cần lấy', description = '1 hộp có trọng lượng là 200 gram.', icon = 'hashtag'},
            {type = 'checkbox', label = 'Chỉ lấy đạn'},
        })
        if input then TriggerServerEvent('FactionLocker:server:GivePlayerTaserY2', playerId, category, input) end
    elseif action == 'give_colbaton' then
        TriggerServerEvent('FactionLocker:server:GivePlayerColbaton', playerId, category)
    elseif action == 'give_flashlight' then
        TriggerServerEvent('FactionLocker:server:GivePlayerFlashlight', playerId, category)
    elseif action == 'give_spraycan' then
        TriggerServerEvent('FactionLocker:server:GivePlayerSpraycan', playerId, category)
    elseif action == 'give_handcuffs' then
        TriggerServerEvent('FactionLocker:server:GivePlayerHandcuffs', playerId, category)
    elseif action == 'give_spikestrip' then
        TriggerServerEvent('FactionLocker:server:GivePlayerSpikeStrip', playerId, category)
    elseif action == 'give_megaphone' then
        TriggerServerEvent('FactionLocker:server:GivePlayerMegaphone', playerId, category)
    elseif action == 'give_speedlidar4' then
        TriggerServerEvent('FactionLocker:server:GivePlayerSpeedLidar4', playerId, category)
    elseif action == 'give_medkit' then
        TriggerServerEvent('FactionLocker:server:GivePlayerMedkit', playerId, category)
    elseif action == 'give_fireextinguisher' then
        TriggerServerEvent('FactionLocker:server:GivePlayerFireExtinguisher', playerId, category)

    elseif action == 'buy_business_item' then
        SetNuiFocus(false, false)
        SendNUIMessage({ display = false })
        local rawItem = itemData.rawItem or {}
        local input = lib.inputDialog('Nhập số lượng', {
            {type = 'number', label = 'Số lượng', default = 1, min = 1, icon = 'hashtag'}
        })
        if input and input[1] and input[1] > 0 then
            TriggerServerEvent('FactionLocker:server:BuyBusinessItem', rawItem.item, rawItem.price, rawItem.label, input[1])
        end
    end

    cb('ok')
end)
