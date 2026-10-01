local npcCreated = false
local lastCoords
local lastInputAt = 0
local challengeOpen = false
local investmentLabelPoint

local function drawNpcLabel(coords, label)
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

local function money(value)
    local formatted = tostring(math.floor(value)):reverse():gsub('(%d%d%d)', '%1.'):reverse()
    return formatted:gsub('^%.', '')
end

local function notify(data)
    lib.notify(
    {
        title = Config.Text.title,
        description = data.message,
        type = data.type or 'inform'
    })
end

local function refreshMenu()
    local state = lib.callback.await('lv_investment:getState', false)

    if not state then
        return
    end

    local options = {}

    if state.contract then
        local contract = state.contract
        local progress = math.min(100, math.floor((contract.active_minutes / contract.required_minutes) * 100))
        
        options[#options + 1] =
        {
            title = contract.label,
            description = ('Tiến Độ: %d/%d phút (%d%%)'):format(contract.active_minutes, contract.required_minutes, progress),
            icon = contract.status == 'completed' and 'circle-check' or 'clock',
            progress = progress,
            colorScheme = contract.status == 'completed' and 'green' or 'blue',
            disabled = true
        }

        if contract.status == 'completed' then
            options[#options + 1] =
            {
                title = ('Nhận $%s'):format(money(contract.payout)),
                description = 'Nhận lại vốn và lợi nhuận',
                icon = 'money-bill-transfer',
                onSelect = function()
                    local result = lib.callback.await('lv_investment:claim', false)

                    if result then
                        notify(result)
                    end
                end
            }
        else
            options[#options + 1] =
            {
                title = 'Hủy Hợp Đồng',
                description = ('Chỉ hoàn %d%% vốn'):format(Config.CancelRefundPercent),
                icon = 'ban',
                iconColor = '#ef4444',
                onSelect = function()
                    local confirm = lib.alertDialog(
                    {
                        header = 'Hủy Đầu Tư',
                        content = ('Bạn chỉ nhận lại %d%% vốn. Thao tác không thể hoàn tác'):format(Config.CancelRefundPercent),
                        centered = true,
                        cancel = true
                    })

                    if confirm == 'confirm' then
                        local result = lib.callback.await('lv_investment:cancel', false)

                        if result then
                            notify(result)
                        end
                    end
                end
            }
        end
    else
        for _, package in ipairs(Config.Packages) do
            options[#options + 1] =
            {
                title = package.label,
                description = ('Vốn $%s • Nhận $%s • Online Hợp Lệ %d Phút'):format(
                    money(package.principal), money(package.payout), package.requiredMinutes
                ),
                icon = 'chart-line',
                onSelect = function()
                    local confirm = lib.alertDialog(
                    {
                        header = package.label,
                        content = ('Đầu tư **$%s** và khi hoàn thành nhận **$%s**\n\nAFK/Treo Máy sẽ không được tính thời gian'):format(
                            money(package.principal), money(package.payout)
                        ),
                        centered = true,
                        cancel = true
                    })

                    if confirm == 'confirm' then
                        local result = lib.callback.await('lv_investment:purchase', false, package.id)

                        if result then
                            notify(result)
                        end
                    end
                end
            }
        end
    end

    lib.registerContext(
    {
        id = 'lv_investment_menu',
        title = Config.Text.title,
        options = options
    })
    lib.showContext('lv_investment_menu')
end

local activeBlip = nil

local function createBlip()
    if Config.Blip and Config.Blip.enabled then
        local blip = AddBlipForCoord(Config.NPC.coords.x, Config.NPC.coords.y, Config.NPC.coords.z)

        SetBlipSprite(blip, Config.Blip.sprite or 605)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, Config.Blip.scale or 0.8)
        SetBlipColour(blip, 0)
        SetBlipAsShortRange(blip, true)

        BeginTextCommandSetBlipName("STRING")

        AddTextComponentString(Config.Blip.label or Config.Text.title or "Investment Center")

        EndTextCommandSetBlipName(blip)

        activeBlip = blip
    end
end

local function createNPC()
    if npcCreated then
        return
    end

    npcCreated = true

    exports.legacyCore:CreateActor(
    {
        name = Config.NPC.name,
        model = Config.NPC.model,
        coords = Config.NPC.coords,
        scenario = Config.NPC.scenario,
        renderDistance = Config.NPC.renderDistance,
        options =
        {
            {
                name = 'lv_investment_open',
                label = Config.Text.npcLabel,
                icon = 'fa-solid fa-chart-line',
                distance = 2.5,
                onSelect = refreshMenu
            }
        }
    })

    local npcCoords = Config.NPC.coords
    local labelCoords = vector3(
        npcCoords.x,
        npcCoords.y,
        npcCoords.z + (Config.NPC.labelHeight or 2.0)
    )

    investmentLabelPoint = lib.points.new({
        coords = Config.NPC.coords.xyz,
        distance = Config.NPC.labelDistance or 15.0
    })

    function investmentLabelPoint:nearby()
        drawNpcLabel(labelCoords, Config.NPC.label)
    end
end

CreateThread(function()
    Wait(1000)

    createNPC()
    createBlip()

    while true do
        Wait(1000)

        local ped = PlayerPedId()

        if DoesEntityExist(ped) and not IsEntityDead(ped) then
            local coords = GetEntityCoords(ped)
            local moved = lastCoords and #(coords - lastCoords) >= 1.0 or false
            local input = IsControlPressed(0, 30) or IsControlPressed(0, 31) or
                IsControlJustPressed(0, 24) or IsControlJustPressed(0, 38) or IsControlJustPressed(0, 51)

            if moved or input then
                lastInputAt = GetGameTimer()
            end

            lastCoords = coords
        end
    end
end)

CreateThread(function()
    while true do
        Wait(30000)

        TriggerServerEvent('lv_investment:activity', GetGameTimer() - lastInputAt <= 90000, IsPauseMenuActive())
    end
end)

RegisterNetEvent('lv_investment:challenge', function(nonce, code, timeout)
    challengeOpen = true

    local result = lib.inputDialog('Xác Minh Hoạt Động',
    {
        {
            type = 'input',
            label = ('Nhập mã %s để tiếp tục tính giờ'):format(code), required = true
        }
    },
    {
        allowCancel = false
    })

    challengeOpen = false

    TriggerServerEvent('lv_investment:challengeResult', nonce, result and tostring(result[1]) or '')
end)

CreateThread(function()
    local nextFocusRefresh = 0

    while true do
        if not challengeOpen then
            Wait(250)

            nextFocusRefresh = 0
        else
            Wait(0)

            DisableControlAction(0, 199, true)
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 322, true)

            if IsPauseMenuActive() then
                SetPauseMenuActive(false)
            end

            local now = GetGameTimer()

            if now >= nextFocusRefresh then
                SetNuiFocus(true, true)

                SetNuiFocusKeepInput(false)
                
                nextFocusRefresh = now + 250
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        if investmentLabelPoint then
            investmentLabelPoint:remove()
            investmentLabelPoint = nil
        end

        if activeBlip and DoesBlipExist(activeBlip) then
            RemoveBlip(activeBlip)
        end
    end
end)
