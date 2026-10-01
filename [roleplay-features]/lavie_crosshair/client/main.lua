local function GetDefaultSettings()
    return {
        type = Config.DefaultType or 'cross',
        color = Config.DefaultColor or {255, 255, 255, 255},
        outline = Config.DefaultOutline or false,
        outlineColor = Config.DefaultOutlineColor or {0, 0, 0, 255},
        size = Config.Size or 0.0038,
        thickness = Config.Thickness or 0.0015,
        gap = Config.Gap or 0,
        dotSize = Config.DotSize or 0.003,
        radius = 0.6,
        outlineWidth = 0.8
    }
end

local currentSettings = GetDefaultSettings()

local shouldDraw = false
local blacklistSet = {}

for _, hash in ipairs(Config.BlacklistedWeapons) do
    blacklistSet[hash] = true
    blacklistSet[hash & 0xFFFFFFFF] = true
end

local lastVisibility = false

local function UpdateNuiSettings()
    SendNUIMessage({
        action = "updateSettings",
        settings = {
            type = currentSettings.type or Config.DefaultType,
            color = currentSettings.color or Config.DefaultColor,
            outline = currentSettings.outline or false,
            outlineColor = currentSettings.outlineColor or Config.DefaultOutlineColor or {0, 0, 0, 255},
            size = currentSettings.size or Config.Size,
            thickness = currentSettings.thickness or Config.Thickness,
            gap = Config.Gap or 0,
            dotSize = currentSettings.dotSize or Config.DotSize,
            radius = currentSettings.radius or 0.6,
            outlineWidth = currentSettings.outlineWidth or 0.8
        }
    })
end

local function UpdateNuiVisibility(visible)
    if lastVisibility ~= visible then
        lastVisibility = visible
        SendNUIMessage({
            action = "updateVisibility",
            visible = visible
        })
    end
end

CreateThread(function()
    local ped, weapon
    while true do
        ped = PlayerPedId()
        _, weapon = GetCurrentPedWeapon(ped, true)

        if Config.OnlyWithWeapon then
            local uWeapon = weapon and (weapon & 0xFFFFFFFF)
            shouldDraw = weapon ~= nil and weapon ~= 0 and not blacklistSet[weapon] and not blacklistSet[uWeapon]
        else
            shouldDraw = true
        end

        Wait(200)
    end
end)

CreateThread(function()
    while true do
        HideHudComponentThisFrame(14) 
        Wait(0)
    end
end)

CreateThread(function()
    while true do
        if shouldDraw then
            local isAiming = not Config.OnlyWhenAiming or (IsPlayerFreeAiming(PlayerId()) or IsControlPressed(0, 25))
            UpdateNuiVisibility(isAiming)
        else
            UpdateNuiVisibility(false)
        end
        Wait(50) 
    end
end)


RegisterNetEvent('lavie_crosshair:setCrosshair', function(settings)
    if type(settings) == 'table' then
        currentSettings = {
            type = settings.type or Config.DefaultType,
            color = settings.color or Config.DefaultColor,
            outline = settings.outline ~= nil and settings.outline or (Config.DefaultOutline or false),
            outlineColor = settings.outlineColor or Config.DefaultOutlineColor or {0, 0, 0, 255},
            size = settings.size or Config.Size,
            thickness = settings.thickness or Config.Thickness,
            gap = settings.gap or Config.Gap or 0,
            dotSize = settings.dotSize or Config.DotSize,
            radius = settings.radius or 0.6,
            outlineWidth = settings.outlineWidth or 0.8
        }
        UpdateNuiSettings()
    end
end)

RegisterNetEvent('lavie_crosshair:notify', function(notifyType, message)
    if GetResourceState('lv_notify') == 'started' then
        exports['lv_notify']:lv_notify(message, notifyType, 3000, 'Crosshair')
        return
    end

    lib.notify({
        title = 'Crosshair',
        description = message,
        type = notifyType
    })
end)

local predefinedColors = {
    { label = 'Trắng', value = {255, 255, 255, 255} },
    { label = 'Đỏ', value = {255, 0, 0, 255} },
    { label = 'Xanh Lá', value = {0, 255, 0, 255} },
    { label = 'Xanh Dương', value = {0, 0, 255, 255} },
    { label = 'Vàng', value = {255, 255, 0, 255} },
    { label = 'Hồng', value = {255, 105, 180, 255} },
    { label = 'Xanh Lơ (Cyan)', value = {0, 255, 255, 255} }
}

local function HexToRGB(hex)
    hex = hex:gsub("#","")
    if #hex == 3 then
        return {
            tonumber("0x"..hex:sub(1,1)) * 17,
            tonumber("0x"..hex:sub(2,2)) * 17,
            tonumber("0x"..hex:sub(3,3)) * 17,
            255
        }
    elseif #hex == 6 then
        return {
            tonumber("0x"..hex:sub(1,2)),
            tonumber("0x"..hex:sub(3,4)),
            tonumber("0x"..hex:sub(5,6)),
            255
        }
    end
    return nil
end

local function OpenColorPicker(title, cb)
    local options = {}
    for i, colorData in ipairs(predefinedColors) do
        options[#options + 1] = {
            title = colorData.label,
            onSelect = function()
                cb(colorData.value)
            end
        }
    end

    options[#options + 1] = {
        title = 'Tự nhập mã màu HEX',
        onSelect = function()
            local dialog = lib.inputDialog('Mã Màu HEX', {
                { type = 'input', label = 'Nhập mã HEX (Ví dụ: #FF5500 hoặc FF5500)', placeholder = '#FFFFFF' }
            })
            if dialog and dialog[1] then
                local rgb = HexToRGB(dialog[1])
                if rgb then
                    cb(rgb)
                else
                    lib.notify({ title = 'Lỗi', description = 'Mã màu HEX không hợp lệ!', type = 'error' })
                end
            end
        end
    }

    lib.registerContext({
        id = 'lavie_crosshair_color_menu',
        title = title,
        menu = 'lavie_crosshair_menu',
        options = options
    })
    lib.showContext('lavie_crosshair_color_menu')
end

RegisterCommand('crosshair', function()
    local isPrime = LocalPlayer.state.isPrime == true
    if not isPrime then
        TriggerEvent('lavie_crosshair:notify', 'error', 'Bạn cần có Prime để sử dụng tùy chỉnh Crosshair!')
        return
    end
    local options = {}

    options[#options + 1] = {
        title = 'Chọn Kiểu Tâm',
        description = 'Thay đổi hình dạng tâm ngắm',
        icon = 'crosshairs',
        onSelect = function()
            local typeOptions = {}
            local sorted = {}
            for key, data in pairs(Config.Crosshairs) do
                sorted[#sorted + 1] = { key = key, data = data }
            end
            table.sort(sorted, function(a, b) return a.data.order < b.data.order end)

            for _, item in ipairs(sorted) do
                local key = item.key
                local data = item.data

                if not data.prime or isPrime then
                    local isSelected = (currentSettings.type == key)
                    typeOptions[#typeOptions + 1] = {
                        title = data.label,
                        description = isSelected and '✓ Đang sử dụng' or (data.prime and '⭐ Yêu cầu Prime' or nil),
                        icon = isSelected and 'check' or 'circle',
                        onSelect = function()
                            if currentSettings.type ~= key then
                                currentSettings.type = key
                                TriggerServerEvent('lavie_crosshair:save', currentSettings)
                            end
                        end
                    }
                end
            end

            lib.registerContext({
                id = 'lavie_crosshair_type_menu',
                title = 'Chọn Kiểu Tâm',
                menu = 'lavie_crosshair_menu',
                options = typeOptions
            })
            lib.showContext('lavie_crosshair_type_menu')
        end
    }


    options[#options + 1] = {
        title = 'Đổi Màu Tâm',
        description = isPrime and 'Chọn màu sắc cho tâm ngắm' or '⭐ Chỉ dành cho Prime',
        icon = 'palette',
        disabled = not isPrime,
        onSelect = function()
            OpenColorPicker('Đổi Màu Tâm', function(color)
                currentSettings.color = color
                TriggerServerEvent('lavie_crosshair:save', currentSettings)
            end)
        end
    }

    options[#options + 1] = {
        title = 'Bật/Tắt Viền Tâm',
        description = isPrime and ('Trạng thái hiện tại: ' .. (currentSettings.outline and 'BẬT' or 'TẮT')) or '⭐ Chỉ dành cho Prime',
        icon = 'circle-half-stroke',
        disabled = not isPrime,
        onSelect = function()
            currentSettings.outline = not currentSettings.outline
            TriggerServerEvent('lavie_crosshair:save', currentSettings)
        end
    }

    options[#options + 1] = {
        title = 'Đổi Màu Viền Tâm',
        description = isPrime and 'Chọn màu viền bao quanh tâm' or '⭐ Chỉ dành cho Prime',
        icon = 'adjust',
        disabled = not isPrime,
        onSelect = function()
            OpenColorPicker('Đổi Màu Viền Tâm', function(color)
                currentSettings.outlineColor = color
                TriggerServerEvent('lavie_crosshair:save', currentSettings)
            end)
        end
    }

    options[#options + 1] = {
        title = 'Chỉnh Kích Thước & Tỷ Lệ',
        description = 'Độ dài dấu +, bán kính tròn, cỡ chấm và độ dày viền',
        icon = 'maximize',
        onSelect = function()
            local sizeOptions = {}


            sizeOptions[#sizeOptions + 1] = {
                title = 'Chỉnh Độ Dài Tâm (Dấu +)',
                description = ('Độ dài hiện tại: %s'):format(math.floor((currentSettings.size or Config.Size) * 10000)),
                icon = 'arrows-left-right',
                onSelect = function()
                    local dialog = lib.inputDialog('Chỉnh Độ Dài Tâm', {
                        { type = 'number', label = 'Nhập độ dài mong muốn (Mặc định: 38, Khoảng: 5 - 200)', default = math.floor((currentSettings.size or Config.Size) * 10000), min = 5, max = 200 }
                    })
                    if dialog and dialog[1] then
                        currentSettings.size = dialog[1] / 10000
                        TriggerServerEvent('lavie_crosshair:save', currentSettings)
                    end
                end
            }

            -- Bán Kính Tâm Tròn
            sizeOptions[#sizeOptions + 1] = {
                title = 'Chỉnh Bán Kính Tâm Tròn',
                description = ('Bán kính hiện tại: %s%%'):format(math.floor((currentSettings.radius or 0.6) * 100)),
                icon = 'circle-dot',
                onSelect = function()
                    local dialog = lib.inputDialog('Chỉnh Bán Kính Vòng Tròn', {
                        { type = 'number', label = 'Nhập bán kính mong muốn (Mặc định: 60, Khoảng: 10 - 300)', default = math.floor((currentSettings.radius or 0.6) * 100), min = 10, max = 300 }
                    })
                    if dialog and dialog[1] then
                        currentSettings.radius = dialog[1] / 100
                        TriggerServerEvent('lavie_crosshair:save', currentSettings)
                    end
                end
            }

            -- Cỡ Dấu Chấm
            sizeOptions[#sizeOptions + 1] = {
                title = 'Chỉnh Cỡ Dấu Chấm (Tâm Dấu Chấm)',
                description = ('Kích thước hiện tại: %s'):format(math.floor((currentSettings.dotSize or Config.DotSize) * 10000)),
                icon = 'circle',
                onSelect = function()
                    local dialog = lib.inputDialog('Kích Thước Dấu Chấm', {
                        { type = 'number', label = 'Nhập kích thước mong muốn (Mặc định: 30, Khoảng: 5 - 150)', default = math.floor((currentSettings.dotSize or Config.DotSize) * 10000), min = 5, max = 150 }
                    })
                    if dialog and dialog[1] then
                        currentSettings.dotSize = dialog[1] / 10000
                        TriggerServerEvent('lavie_crosshair:save', currentSettings)
                    end
                end
            }

            -- Độ Dày Viền
            sizeOptions[#sizeOptions + 1] = {
                title = 'Chỉnh Độ Dày Viền',
                description = ('Độ dày viền hiện tại: %s'):format(math.floor((currentSettings.outlineWidth or 0.8) * 10)),
                icon = 'border-style',
                onSelect = function()
                    local dialog = lib.inputDialog('Độ Dày Viền Tâm', {
                        { type = 'number', label = 'Nhập độ dày viền (Mặc định: 8, Khoảng: 1 - 30)', default = math.floor((currentSettings.outlineWidth or 0.8) * 10), min = 1, max = 30 }
                    })
                    if dialog and dialog[1] then
                        currentSettings.outlineWidth = dialog[1] / 10
                        TriggerServerEvent('lavie_crosshair:save', currentSettings)
                    end
                end
            }


            sizeOptions[#sizeOptions + 1] = {
                title = 'Chỉnh Độ Mập (Dấu +)',
                description = ('Độ mập hiện tại: %s'):format(math.floor((currentSettings.thickness or Config.Thickness) * 10000)),
                icon = 'arrows-up-down-left-right',
                onSelect = function()
                    local dialog = lib.inputDialog('Độ Mập Tâm Ngắm', {
                        { type = 'number', label = 'Nhập độ mập mong muốn (Mặc định: 15, Khoảng: 5 - 100)', default = math.floor((currentSettings.thickness or Config.Thickness) * 10000), min = 5, max = 100 }
                    })
                    if dialog and dialog[1] then
                        currentSettings.thickness = dialog[1] / 10000
                        TriggerServerEvent('lavie_crosshair:save', currentSettings)
                    end
                end
            }


            lib.registerContext({
                id = 'lavie_crosshair_size_menu',
                title = 'Kích Thước & Tỷ Lệ',
                menu = 'lavie_crosshair_menu',
                options = sizeOptions
            })
            lib.showContext('lavie_crosshair_size_menu')
        end
    }




    lib.registerContext({
        id = 'lavie_crosshair_menu',
        title = 'Tùy Chỉnh Crosshair',
        options = options
    })

    lib.showContext('lavie_crosshair_menu')
end, false)

exports('GetCurrentCrosshair', function()
    return currentSettings.type
end)


AddEventHandler('onClientResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        Wait(1000)
        TriggerServerEvent('lavie_crosshair:requestSettings')
    end
end)

AddStateBagChangeHandler('isPrime', ('player:%s'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
    if value == false then
        currentSettings = GetDefaultSettings()
        UpdateNuiSettings()
        if lib.getOpenContextMenu and lib.getOpenContextMenu() and string.find(lib.getOpenContextMenu(), 'lavie_crosshair') then
            lib.hideContext()
        end
    end
end)

