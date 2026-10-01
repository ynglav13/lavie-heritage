local spawnedPeds = {}
local targetZones = {}
local currentStatus
local currentControls
local statusOwner
local controlsOwner

local function notify(message, notifyType, title)
    exports.lv_notify:Notify({title = title or 'Diamond Casino', message = message, type = notifyType or 'info', duration = 4200})
end

local function showStatus(text)
    local payload = type(text) == 'table' and text or {text = tostring(text or '')}
    local encoded = json.encode(payload)
    local owner = GetInvokingResource() or GetCurrentResourceName()
    if currentStatus == encoded then
        statusOwner = owner
        return
    end
    currentStatus = encoded
    statusOwner = owner
    SendNUIMessage({action = 'status', visible = true, payload = payload})
end

local function hideStatus(force)
    if not currentStatus then return end
    local owner = GetInvokingResource() or GetCurrentResourceName()
    if force ~= true and statusOwner and owner ~= statusOwner then return end
    currentStatus = nil
    statusOwner = nil
    SendNUIMessage({action = 'status', visible = false})
end

local function showText(text)
    local payload = type(text) == 'table' and text or {hint = tostring(text or '')}
    local encoded = json.encode(payload)
    local owner = GetInvokingResource() or GetCurrentResourceName()
    if currentControls == encoded then
        controlsOwner = owner
        return
    end
    currentControls = encoded
    controlsOwner = owner
    SendNUIMessage({action = 'controls', visible = true, payload = payload})
end

local function hideText(force)
    if not currentControls then return end
    local owner = GetInvokingResource() or GetCurrentResourceName()
    if force ~= true and controlsOwner and owner ~= controlsOwner then return end
    currentControls = nil
    controlsOwner = nil
    SendNUIMessage({action = 'controls', visible = false})
end

exports('Notify', notify)
exports('ShowStatus', showStatus)
exports('HideStatus', hideStatus)
exports('ShowText', showText)
exports('HideText', hideText)

local function inputAmount(title)
    local result = lib.inputDialog(title, {{type = 'number', label = 'Amount', required = true, min = 1, max = CasinoConfig.MaxCashierAmount}})
    return result and math.floor(tonumber(result[1]) or 0) or nil
end

local function requestSelfService(action, amount)
    TriggerServerEvent('lv_casino:server:selfService', action, amount)
end

local function openChipMenu()
    local chipRate = math.floor(tonumber(CasinoConfig.ChipRate) or 0)
    lib.registerContext({
        id = 'lv_casino_chip_menu',
        title = 'Casino Chip Exchange',
        options = {
            {title = 'Buy Chips', description = ('$%s per chip'):format(chipRate), icon = 'coins', onSelect = function() local amount = inputAmount('Buy Casino Chips') if amount then requestSelfService('buy_chips', amount) end end},
            {title = 'Cash Out Chips', description = ('$%s gross per chip | Cash-out tax: %s%%'):format(chipRate, CasinoConfig.CashOutTaxPercent or 0), icon = 'money-bill-transfer', onSelect = function() local amount = inputAmount('Cash Out Casino Chips') if amount then requestSelfService('sell_chips', amount) end end}
        }
    })
    lib.showContext('lv_casino_chip_menu')
end

local function openMembershipMenu()
    lib.registerContext({
        id = 'lv_casino_membership_menu',
        title = 'Casino Membership',
        options = {
            {title = 'Buy Member Card', description = ('$%s'):format(CasinoConfig.MemberPrice), icon = 'id-card', onSelect = function() requestSelfService('buy_member') end},
            {title = 'Buy VIP Card', description = ('$%s | Existing Member card will be collected'):format(CasinoConfig.VipPrice), icon = 'star', onSelect = function() requestSelfService('buy_vip') end}
        }
    })
    lib.showContext('lv_casino_membership_menu')
end

local function nearbyPlayer()
    local player, distance = ESX.Game.GetClosestPlayer()
    if player == -1 or not distance or distance > CasinoConfig.InteractionDistance then return nil end
    return GetPlayerServerId(player)
end

local function sendStaffOffer(action, amount)
    local target = nearbyPlayer()
    if not target then return notify('Không có khách hàng ở gần.', 'error') end
    TriggerServerEvent('lv_casino:server:createOffer', target, action, amount)
end

local function openLedger()
    local response = lib.callback.await('lv_casino:server:ledger', false) or {}
    if response.denied then return notify('Bạn không có quyền xem sổ giao dịch.', 'error') end
    local rows = response.transactions or {}
    local financials = response.financials or {}
    local options = {{title = ('Total Funds: $%s'):format(financials.budget or 0), description = ('Reserved: $%s | Available: $%s'):format(financials.reserved or 0, financials.available or 0), icon = 'building-columns'}}
    local actionLabels = {chips_buy = 'Chip Sale', chips_sell = 'Chip Cash Out', membership_member = 'Member Card Sale', membership_vip = 'VIP Card Sale', round_open = 'Round Opened', round_settle = 'Round Settled', round_cancel = 'Round Refunded', wheel_reward = 'Lucky Wheel Reward'}
    local statusLabels = {committed = 'Completed', rolled_back = 'Rolled Back', rejected = 'Rejected'}
    for i = 1, #rows do
        options[#options + 1] = {title = ('%s | %s'):format(actionLabels[rows[i].action] or 'Casino Transaction', rows[i].amount), description = ('%s | %s'):format(statusLabels[rows[i].status] or 'Recorded', rows[i].created_at)}
    end
    if #rows == 0 then options[#options + 1] = {title = 'No Transactions'} end
    lib.registerContext({id = 'lv_casino_ledger', title = 'Casino Ledger', options = options})
    lib.showContext('lv_casino_ledger')
end

local function openStaffPos()
    local chipRate = math.floor(tonumber(CasinoConfig.ChipRate) or 0)
    lib.registerContext({
        id = 'lv_casino_staff_pos',
        title = 'Casino Staff POS',
        options = {
            {title = 'Sell Chips', description = ('$%s per chip'):format(chipRate), icon = 'coins', onSelect = function() local amount = inputAmount('Chips to Sell') if amount then sendStaffOffer('buy_chips', amount) end end},
            {title = 'Cash Out Chips', description = ('$%s gross per chip | Cash-out tax: %s%%'):format(chipRate, CasinoConfig.CashOutTaxPercent or 0), icon = 'money-bill-transfer', onSelect = function() local amount = inputAmount('Chips to Cash Out') if amount then sendStaffOffer('sell_chips', amount) end end},
            {title = 'Sell Member Card', icon = 'id-card', onSelect = function() sendStaffOffer('buy_member') end},
            {title = 'Sell VIP Card', icon = 'star', onSelect = function() sendStaffOffer('buy_vip') end},
            {title = 'View Casino Ledger', icon = 'book', onSelect = openLedger}
        }
    })
    lib.showContext('lv_casino_staff_pos')
end

RegisterNetEvent('lv_casino:client:offer', function(offer)
    local accepted = exports.lv_notify:Confirm({title = 'Xác nhận giao dịch', message = offer.message, yesLabel = 'Đồng ý', noLabel = 'Từ chối'})
    TriggerServerEvent('lv_casino:server:respondOffer', offer.id, accepted == true)
end)

RegisterNetEvent('lv_casino:client:teleport', function(coords, message)
    SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z, false, false, false, true)
    SetEntityHeading(PlayerPedId(), coords.w or 0.0)
    notify(message, 'success')
end)

local function spawnPed(definition, options)
    local model = joaat(definition.model)
    lib.requestModel(model)
    local ped = CreatePed(4, model, definition.coords.x, definition.coords.y, definition.coords.z - 1.0, definition.coords.w, false, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    if definition.scenario then TaskStartScenarioInPlace(ped, definition.scenario, 0, true) end
    exports.ox_target:addLocalEntity(ped, options)
    spawnedPeds[#spawnedPeds + 1] = ped
    SetModelAsNoLongerNeeded(model)
end

CreateThread(function()
    spawnPed(CasinoConfig.Cashier, {
        {name = 'lv_casino_chip_self', icon = 'fa-solid fa-coins', label = 'Exchange Casino Chips', distance = 4.5, onSelect = openChipMenu},
        {name = 'lv_casino_staff_pos', icon = 'fa-solid fa-cash-register', label = 'Open Staff POS', distance = 4.5, canInteract = function() return LocalPlayer.state.factionTag == CasinoConfig.BusinessTag and LocalPlayer.state.factionDuty == true end, onSelect = openStaffPos}
    })
    spawnPed(CasinoConfig.MembershipDesk, {
        {name = 'lv_casino_membership_self', icon = 'fa-solid fa-id-card', label = 'Buy Casino Membership', distance = 4.5, onSelect = openMembershipMenu}
    })
    targetZones[#targetZones + 1] = exports.ox_target:addSphereZone({
        coords = CasinoConfig.DutyDesk.coords,
        radius = CasinoConfig.DutyDesk.radius,
        options = {
            {name = 'lv_casino_duty', icon = 'fa-solid fa-user-clock', label = 'Clock In or Out', canInteract = function() return LocalPlayer.state.factionTag == CasinoConfig.BusinessTag end, onSelect = function() TriggerServerEvent('lv_casino:server:toggleDuty') end},
            {name = 'lv_casino_ledger_desk', icon = 'fa-solid fa-book', label = 'View Casino Ledger', canInteract = function() return LocalPlayer.state.factionTag == CasinoConfig.BusinessTag end, onSelect = openLedger}
        }
    })
    spawnPed(CasinoConfig.Penthouse.attendant, {
        {name = 'lv_casino_penthouse', icon = 'fa-solid fa-elevator', label = 'Enter Penthouse', distance = 4.5, onSelect = function() TriggerServerEvent('lv_casino:server:requestPenthouse', true) end}
    })
    targetZones[#targetZones + 1] = exports.ox_target:addSphereZone({
        coords = CasinoConfig.Penthouse.exit.xyz,
        radius = 1.2,
        options = {{name = 'lv_casino_lobby', icon = 'fa-solid fa-elevator', label = 'Return to Casino Lobby', onSelect = function() TriggerServerEvent('lv_casino:server:requestPenthouse', false) end}}
    })
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    hideStatus(true)
    hideText(true)
    for i = 1, #spawnedPeds do
        if DoesEntityExist(spawnedPeds[i]) then DeleteEntity(spawnedPeds[i]) end
    end
    for i = 1, #targetZones do exports.ox_target:removeZone(targetZones[i]) end
end)
