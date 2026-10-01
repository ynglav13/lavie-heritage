local advertisementPed
local advertisementPoint
local advertisementBlip

local function drawNpcLabel(ped, label)
    if not ped or not DoesEntityExist(ped) then
        return
    end

    local coords = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.35)
    local onScreen, screenX, screenY = World3dToScreen2d(coords.x, coords.y, coords.z)

    if not onScreen then
        return
    end

    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 255)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandDisplayText(screenX, screenY)
end

local function formatMoney(value)
    local formatted = tostring(math.floor(tonumber(value) or 0)):reverse():gsub('(%d%d%d)', '%1.'):reverse()
    return formatted:gsub('^%.', '')
end

local function formatRemaining(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    if hours > 0 then
        return ('%d giờ %d phút'):format(hours, minutes)
    end

    if minutes > 0 then
        return ('%d phút'):format(minutes)
    end

    return 'Dưới 1 phút'
end

local function notify(result)
    if not result then
        lib.notify({
            title = 'Advertisement Center',
            description = 'Không nhận được phản hồi từ máy chủ.',
            type = 'error'
        })
        return
    end

    lib.notify({
        title = 'Advertisement Center',
        description = result.message or 'Đã xử lý yêu cầu.',
        type = result.type or (result.ok and 'success' or 'error')
    })
end

local function openAdvertisementForm()
    local quote = lib.callback.await('lv_advertising:getQuote', false)

    if not quote or not quote.ok then
        notify(quote)
        return
    end

    local priceDescription = quote.isPrime
        and ('Prime giảm %d%% • Phí: $%s'):format(Config.PrimeDiscountPercent, formatMoney(quote.price))
        or ('Phí quảng cáo: $%s'):format(formatMoney(quote.price))

    local input = lib.inputDialog('Treo quảng cáo', {
        {
            type = 'textarea',
            label = 'Nội dung',
            description = ('Tối đa %d ký tự'):format(Config.MaxContentLength),
            required = true,
            min = 1,
            max = Config.MaxContentLength
        },
        {
            type = 'input',
            label = 'Tên người QC',
            required = true,
            min = 1,
            max = Config.MaxAdvertiserNameLength
        },
        {
            type = 'input',
            label = 'Phone',
            description = priceDescription,
            required = true,
            min = 3,
            max = Config.MaxPhoneLength
        }
    })

    if not input then
        return
    end

    local confirmation = lib.alertDialog({
        header = 'Xác nhận treo quảng cáo',
        content = ('Phí: **$%s**\n\nTiền mặt sẽ được dùng trước, phần thiếu sẽ trừ từ ngân hàng.'):format(formatMoney(quote.price)),
        centered = true,
        cancel = true
    })

    if confirmation ~= 'confirm' then
        return
    end

    local result = lib.callback.await('lv_advertising:create', false, {
        content = input[1],
        advertiserName = input[2],
        phone = input[3],
        quotedPrice = quote.price
    })

    notify(result)
end

local function openAdvertisementList()
    local result = lib.callback.await('lv_advertising:getActive', false)

    if not result or not result.ok then
        notify(result)
        return
    end

    local options = {}

    for i = 1, #result.ads do
        local advertisement = result.ads[i]

        options[#options + 1] = {
            title = ('[QC] %s'):format(advertisement.content),
            description = ('Người QC: %s\nPhone: %s\nCòn lại: %s'):format(
                advertisement.advertiserName,
                advertisement.phone,
                formatRemaining(advertisement.remainingSeconds)
            ),
            icon = 'rectangle-ad',
            disabled = true
        }
    end

    if #options == 0 then
        options[1] = {
            title = 'Chưa có quảng cáo',
            description = 'Hiện không có quảng cáo nào đang hoạt động.',
            icon = 'circle-info',
            disabled = true
        }
    end

    lib.registerContext({
        id = 'lv_advertising_active_ads',
        title = 'Xem quảng cáo',
        options = options
    })
    lib.showContext('lv_advertising_active_ads')
end

local function deleteAdvertisementPed()
    if advertisementPed and DoesEntityExist(advertisementPed) then
        pcall(function()
            exports.ox_target:removeLocalEntity(advertisementPed, {
                'lv_advertising_post',
                'lv_advertising_view'
            })
        end)
        DeleteEntity(advertisementPed)
    end

    advertisementPed = nil
end

local function createAdvertisementPed()
    if advertisementPed and DoesEntityExist(advertisementPed) then
        return
    end

    local model = joaat(Config.NPC.model)

    if not IsModelInCdimage(model) or not IsModelValid(model) or not IsModelAPed(model) then
        return
    end

    lib.requestModel(model)

    local coords = Config.NPC.coords
    local seatZ = coords.z - (Config.NPC.seatZOffset or 0.0)
    local ped = CreatePed(4, model, coords.x, coords.y, seatZ, coords.w, false, false)

    if not DoesEntityExist(ped) then
        SetModelAsNoLongerNeeded(model)
        return
    end

    SetEntityAsMissionEntity(ped, true, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)

    SetEntityCollision(ped, false, false)
    SetEntityHeading(ped, coords.w)
    SetEntityCoords(ped, coords.x, coords.y, seatZ, false, false, false, false)

    Wait(50)

    TaskStartScenarioInPlace(ped, Config.NPC.scenario, 0, true)
    SetEntityCollision(ped, true, true)
    SetModelAsNoLongerNeeded(model)

    exports.ox_target:addLocalEntity(ped, {
        {
            name = 'lv_advertising_post',
            label = 'Treo quảng cáo',
            icon = 'fa-solid fa-rectangle-ad',
            distance = 2.5,
            onSelect = openAdvertisementForm
        },
        {
            name = 'lv_advertising_view',
            label = 'Xem quảng cáo',
            icon = 'fa-solid fa-list',
            distance = 2.5,
            onSelect = openAdvertisementList
        }
    })

    advertisementPed = ped
end

local function createAdvertisementBlip()
    if not Config.Blip.enabled or advertisementBlip then
        return
    end

    local coords = Config.NPC.coords
    advertisementBlip = AddBlipForCoord(coords.x, coords.y, coords.z)

    SetBlipSprite(advertisementBlip, Config.Blip.sprite)
    SetBlipDisplay(advertisementBlip, 4)
    SetBlipScale(advertisementBlip, Config.Blip.scale)
    SetBlipColour(advertisementBlip, Config.Blip.color)
    SetBlipAsShortRange(advertisementBlip, false)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(Config.Blip.label)
    EndTextCommandSetBlipName(advertisementBlip)
end

CreateThread(function()
    createAdvertisementBlip()

    advertisementPoint = lib.points.new({
        coords = Config.NPC.coords.xyz,
        distance = Config.NPC.renderDistance
    })

    function advertisementPoint:onEnter()
        createAdvertisementPed()
    end

    function advertisementPoint:onExit()
        deleteAdvertisementPed()
    end

    function advertisementPoint:nearby()
        if self.currentDistance <= (Config.NPC.labelDistance or 15.0) then
            drawNpcLabel(advertisementPed, Config.NPC.label)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    deleteAdvertisementPed()

    if advertisementBlip then
        RemoveBlip(advertisementBlip)
        advertisementBlip = nil
    end
end)
