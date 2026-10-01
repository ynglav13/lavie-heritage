local nuiOpen    = false
local npcEntities = {}
local currentPendingId = nil

local function notify(title, message, ntype)
    exports.lv_notify:Notify({ title = title, message = message, type = ntype })
end

local function closeNui()
    SendNUIMessage({ action = 'closeUI' })
    SetNuiFocus(false, false)
    nuiOpen = false
    currentPendingId = nil
end

local hasCard = false
local lastCheck = 0

local function checkLicenses()
    local now = GetGameTimer()
    if now - lastCheck > 5000 then
        lastCheck = now
        lib.callback('lv_idcard:checkLicensesForNPC', false, function(res)
            if res then
                hasCard = res.hasCard
            end
        end)
    end
end

local function getNpcLocations()
    local locations = { Config.NpcCoords }
    for _, coords in ipairs(Config.AdditionalNpcCoords or {}) do
        locations[#locations + 1] = coords
    end
    return locations
end

local function spawnNpc(index, coords)
    if npcEntities[index] and DoesEntityExist(npcEntities[index]) then return end
    local model = GetHashKey(Config.NpcModel)
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(100) end
    local npcEntity = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, coords.w, false, true)
    SetEntityInvincible(npcEntity, true)
    SetBlockingOfNonTemporaryEvents(npcEntity, true)
    FreezeEntityPosition(npcEntity, true)
    TaskStartScenarioInPlace(npcEntity, Config.NpcScenario, 0, true)
    SetModelAsNoLongerNeeded(model)
    npcEntities[index] = npcEntity

    exports.ox_target:addLocalEntity(npcEntity, {
        {
            label    = 'Đăng ký ID Card',
            icon     = 'fas fa-id-card',
            distance = 10.0,
            canInteract = function()
                return not hasCard
            end,
            onSelect = function()
                lib.callback('lv_idcard:getPlayerInfo', false, function(info)
                    if not info then return end
                    SendNUIMessage({ action = 'openForm', playerInfo = info })
                    SetNuiFocus(true, true)
                    nuiOpen = true
                end)
            end
        },
        {
            label    = 'Tích hợp Bằng Lái Xe',
            icon     = 'fas fa-car',
            distance = 10.0,
            canInteract = function()
                return hasCard
            end,
            onSelect = function()
                lib.callback('lv_idcard:getMyCard', false, function(card)
                    if not card then
                        notify('Bằng Lái', 'Bạn cần phải có ID Card hợp lệ và đã được duyệt trước.', 'error')
                        return
                    end
                    local license = card.driver_license or 'NONE'
                    if license == 'PASS' then
                        notify('Bằng Lái', 'Bạn đã tích hợp bằng lái xe vào ID Card rồi.', 'error')
                        return
                    elseif license == 'PENDING' then
                        notify('Bằng Lái', 'Yêu cầu tích hợp bằng lái của bạn đang chờ Sĩ quan duyệt.', 'error')
                        return
                    end

                    local alert = lib.alertDialog({
                        header = 'Tích Hợp Bằng Lái Xe',
                        content = string.format('Bạn có muốn tích hợp bằng lái xe vào ID Card của mình?\n\nPhí tích hợp: **$%d** (sẽ trừ khi Sĩ quan duyệt đơn).', Config.DriverLicenseFee),
                        centered = true,
                        cancel = true
                    })

                    if alert == 'confirm' then
                        TriggerServerEvent('lv_idcard:applyDriverLicense')
                    end
                end)
            end
        },
        {
            label    = 'Tích hợp Giấy phép Vũ khí',
            icon     = 'fas fa-shield-halved',
            distance = 10.0,
            canInteract = function()
                return hasCard
            end,
            onSelect = function()
                lib.callback('lv_idcard:getMyCard', false, function(card)
                    if not card then
                        notify('Vũ Khí', 'Bạn cần phải có ID Card hợp lệ và đã được duyệt trước.', 'error')
                        return
                    end
                    local license = card.weapon_license or 'NONE'
                    if license == 'PASS' then
                        notify('Vũ Khí', 'Bạn đã tích hợp giấy phép vũ khí vào ID Card rồi.', 'error')
                        return
                    elseif license == 'PENDING' then
                        notify('Vũ Khí', 'Yêu cầu tích hợp giấy phép vũ khí của bạn đang chờ Sĩ quan duyệt.', 'error')
                        return
                    end

                    local alert = lib.alertDialog({
                        header = 'Tích Hợp Giấy Phép Vũ Khí',
                        content = string.format('Bạn có muốn tích hợp giấy phép sử dụng vũ khí vào ID Card của mình?\n\nPhí tích hợp: **$%d** (sẽ trừ khi Sĩ quan duyệt đơn).', Config.WeaponLicenseFee),
                        centered = true,
                        cancel = true
                    })

                    if alert == 'confirm' then
                        TriggerServerEvent('lv_idcard:applyWeaponLicense')
                    end
                end)
            end
        },

        {
            label    = 'Xem ID Card của tôi',
            icon     = 'fas fa-eye',
            distance = 10.0,
            onSelect = function()
                lib.callback('lv_idcard:getMyCard', false, function(card)
                    if not card then
                        notify('ID Card', 'Bạn chưa có ID Card hợp lệ.', 'error')
                        return
                    end
                    SendNUIMessage({ action = 'showCard', card = card, isOwner = true })
                    SetNuiFocus(true, true)
                    nuiOpen = true
                end)
            end
        }
    })
end

local function deleteNpc(index)
    local npcEntity = npcEntities[index]
    if npcEntity and DoesEntityExist(npcEntity) then
        exports.ox_target:removeLocalEntity(npcEntity)
        DeleteEntity(npcEntity)
    end
    npcEntities[index] = nil
end

CreateThread(function()
    while true do
        local playerCoords = GetEntityCoords(PlayerPedId())
        local nearby = false
        for index, coords in ipairs(getNpcLocations()) do
            local dist = #(playerCoords - vector3(coords.x, coords.y, coords.z))
            if dist < 80.0 then
                nearby = true
                spawnNpc(index, coords)
                if dist < 10.0 then
                    checkLicenses()
                end
            else
                deleteNpc(index)
            end
        end
        if nearby then
            Wait(2000)
        else
            Wait(4000)
        end
    end
end)

CreateThread(function()
    while true do
        if nuiOpen then
            Wait(0)
            if IsControlJustPressed(0, 200) then
                closeNui()
            end
        else
            Wait(300)
        end
    end
end)

local function openIdCardReview()
    lib.callback('lv_idcard:getPendingList', false, function(list)
        if not list or #list == 0 then
            notify('ID Card', 'Không có đơn ID Card nào đang chờ duyệt.', 'inform')
            return
        end
        local options = {}
        for _, app in ipairs(list) do
            local appData = app
            options[#options + 1] = {
                title       = appData.firstname .. ' ' .. appData.lastname,
                description = 'DOB: ' .. (appData.dob or '') .. '  •  Nộp: ' .. (tostring(appData.created_at or '')):sub(1, 10),
                icon        = 'fas fa-id-card',
                onSelect    = function()
                    currentPendingId = appData.id
                    appData.is_license_review = false
                    SendNUIMessage({ action = 'showPendingCard', card = appData })
                    SetNuiFocus(true, true)
                    nuiOpen = true
                end
            }
        end
        lib.registerContext({ id = 'idcard_review', title = 'Đơn Chờ Duyệt ID Card', options = options })
        lib.showContext('idcard_review')
    end)
end

local function openLicenseReview()
    lib.callback('lv_idcard:getPendingLicenseList', false, function(list)
        if not list or #list == 0 then
            notify('Bằng Lái', 'Không có đơn tích hợp nào đang chờ duyệt.', 'inform')
            return
        end
        local options = {}
        for _, app in ipairs(list) do
            local appData = app
            options[#options + 1] = {
                title       = appData.firstname .. ' ' .. appData.lastname,
                description = 'DOB: ' .. (appData.dob or '') .. '  •  Gửi: ' .. (tostring(appData.created_at or '')):sub(1, 10),
                icon        = 'fas fa-car',
                onSelect    = function()
                    currentPendingId = appData.id
                    appData.is_license_review = true
                    SendNUIMessage({ action = 'showPendingCard', card = appData })
                    SetNuiFocus(true, true)
                    nuiOpen = true
                end
            }
        end
        lib.registerContext({ id = 'license_review_list', title = 'Duyệt Tích Hợp Bằng Lái', options = options })
        lib.showContext('license_review_list')
    end)
end

local function openWeaponReview()
    lib.callback('lv_idcard:getPendingWeaponList', false, function(list)
        if not list or #list == 0 then
            notify('Vũ Khí', 'Không có đơn tích hợp nào đang chờ duyệt.', 'inform')
            return
        end
        local options = {}
        for _, app in ipairs(list) do
            local appData = app
            options[#options + 1] = {
                title       = appData.firstname .. ' ' .. appData.lastname,
                description = 'DOB: ' .. (appData.dob or '') .. '  •  Gửi: ' .. (tostring(appData.created_at or '')):sub(1, 10),
                icon        = 'fas fa-shield-halved',
                onSelect    = function()
                    currentPendingId = appData.id
                    appData.is_weapon_review = true
                    SendNUIMessage({ action = 'showPendingCard', card = appData })
                    SetNuiFocus(true, true)
                    nuiOpen = true
                end
            }
        end
        lib.registerContext({ id = 'weapon_review_list', title = 'Duyệt Giấy Phép Vũ Khí', options = options })
        lib.showContext('weapon_review_list')
    end)
end

RegisterCommand('idcard-review', function()
    if LocalPlayer.state.factionCategory ~= 'police' then
        notify('ID Card', 'Bạn không có quyền truy cập tính năng này.', 'error')
        return
    end

    lib.registerContext({
        id = 'idcard_police_menu',
        title = 'Quản Lý Giấy Tờ LSPD',
        options = {
            {
                title = 'Duyệt đơn ID Card',
                description = 'Danh sách các đơn xin cấp ID Card mới',
                icon = 'fas fa-id-card',
                onSelect = function()
                    openIdCardReview()
                end
            },
            {
                title = 'Duyệt tích hợp Bằng Lái Xe',
                description = 'Danh sách các đơn xin tích hợp bằng lái xe',
                icon = 'fas fa-car',
                onSelect = function()
                    openLicenseReview()
                end
            },
            {
                title = 'Duyệt tích hợp Giấy phép Vũ khí',
                description = 'Danh sách các đơn xin tích hợp giấy phép sử dụng vũ khí',
                icon = 'fas fa-shield-halved',
                onSelect = function()
                    openWeaponReview()
                end
            }
        }
    })
    lib.showContext('idcard_police_menu')
end, false)

RegisterCommand('showid', function()
    local myCards = exports.ox_inventory:Search('slots', 'idcard')
    if not myCards or #myCards == 0 then
        notify('ID Card', 'Bạn không có ID Card trong người.', 'error')
        return
    end

    lib.callback('lv_idcard:getNearbyPlayers', false, function(players)
        if not players or #players == 0 then
            notify('ID Card', 'Không có người chơi nào ở gần.', 'error')
            return
        end
        local options = {}
        for _, p in ipairs(players) do
            local player = p
            options[#options + 1] = {
                title       = player.name,
                description = 'Server ID: ' .. player.serverId,
                icon        = 'fas fa-user',
                onSelect    = function()
                    if #myCards == 1 then
                        local cardId = myCards[1].metadata and myCards[1].metadata.card_id
                        local ped = PlayerPedId()
                        RequestAnimDict('mp_common')
                        while not HasAnimDictLoaded('mp_common') do Wait(50) end
                        TaskPlayAnim(ped, 'mp_common', 'givetake1_a', 8.0, -8.0, 2500, 0, 0, false, false, false)
                        TriggerServerEvent('lv_idcard:showCardToPlayer', player.serverId, cardId)
                        notify('ID Card', 'Đã trình ID Card cho ' .. player.name .. '.', 'success')
                    else
                        local cardOptions = {}
                        for _, c in ipairs(myCards) do
                            local label = (c.metadata and c.metadata.label) or 'ID Card'
                            local desc = (c.metadata and c.metadata.description) or ''
                            local cardId = c.metadata and c.metadata.card_id
                            cardOptions[#cardOptions + 1] = {
                                title = label,
                                description = desc,
                                icon = 'fas fa-id-card',
                                onSelect = function()
                                    local ped = PlayerPedId()
                                    RequestAnimDict('mp_common')
                                    while not HasAnimDictLoaded('mp_common') do Wait(50) end
                                    TaskPlayAnim(ped, 'mp_common', 'givetake1_a', 8.0, -8.0, 2500, 0, 0, false, false, false)
                                    TriggerServerEvent('lv_idcard:showCardToPlayer', player.serverId, cardId)
                                    notify('ID Card', 'Đã trình ' .. label .. ' cho ' .. player.name .. '.', 'success')
                                end
                            }
                        end
                        lib.registerContext({ id = 'showid_select_card', title = 'Chọn thẻ ID để trình', options = cardOptions })
                        lib.showContext('showid_select_card')
                    end
                end
            }
        end
        lib.registerContext({ id = 'showid_select', title = 'Chọn người để trình ID Card', options = options })
        lib.showContext('showid_select')
    end)
end, false)

RegisterNUICallback('submitForm', function(data, cb)
    TriggerServerEvent('lv_idcard:submitApplication', data)
    closeNui()
    cb('ok')
end)

RegisterNUICallback('approveCard', function(data, cb)
    if data.isLicenseReview then
        TriggerServerEvent('lv_idcard:approveDriverLicense', data.id)
        closeNui()
    elseif data.isWeaponReview then
        TriggerServerEvent('lv_idcard:approveWeaponLicense', data.id)
        closeNui()
    else
        closeNui()
        local input = lib.inputDialog('Duyệt ID Card', {
            { type = 'input', label = 'Ảnh 3x4', default = data.photo_url or '', description = 'Dán link ảnh cho member tại đây' }
        })
        if input then
            if not input[1] or input[1] == '' then
                notify('ID Card', 'Vui lòng cung cấp link ảnh 3x4', 'error')
                cb('ok')
                return
            end
            TriggerServerEvent('lv_idcard:approveCard', data.id, input[1])
        end
    end
    cb('ok')
end)

RegisterNUICallback('rejectCard', function(data, cb)
    if data.isLicenseReview then
        TriggerServerEvent('lv_idcard:rejectDriverLicense', data.id)
    elseif data.isWeaponReview then
        TriggerServerEvent('lv_idcard:rejectWeaponLicense', data.id)
    else
        TriggerServerEvent('lv_idcard:rejectCard', data.id)
    end
    closeNui()
    cb('ok')
end)

RegisterNUICallback('closeUI', function(_, cb)
    closeNui()
    cb('ok')
end)

exports('UseIdCard', function(...)
    local args = {...}
    local cardId = nil
    
    for _, arg in ipairs(args) do
        if type(arg) == 'table' and arg.metadata and arg.metadata.card_id then
            cardId = arg.metadata.card_id
            break
        end
    end

    if not cardId then
        lib.callback('lv_idcard:getMyCard', false, function(card)
            if not card then
                notify('ID Card', 'ID Card của bạn không hợp lệ hoặc chưa được cấp.', 'error')
                return
            end
            SendNUIMessage({ action = 'showCard', card = card, isOwner = true })
            SetNuiFocus(true, true)
            nuiOpen = true
        end)
        return
    end

    lib.callback('lv_idcard:getCardById', false, function(card)
        if not card then
            notify('ID Card', 'Thẻ ID này không hợp lệ hoặc đã bị lỗi.', 'error')
            return
        end
        SendNUIMessage({ action = 'showCard', card = card, isOwner = true })
        SetNuiFocus(true, true)
        nuiOpen = true
    end, cardId)
end)

RegisterNetEvent('lv_idcard:client:showNearbyCard')
AddEventHandler('lv_idcard:client:showNearbyCard', function(card)
    SendNUIMessage({ action = 'showCard', card = card, isOwner = false })
    SetNuiFocus(true, true)
    nuiOpen = true
end)
