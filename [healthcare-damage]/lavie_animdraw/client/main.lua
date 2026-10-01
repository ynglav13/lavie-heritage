local selectedAnimations = {}
local isDataLoaded = false
local AimAnim = 'nil'
local HoldingAnim = 'nil'
local holsterStyles = {}

local function populateAnimations(savedAnims)
    savedAnims = savedAnims or {}
    
    for _, groupName in ipairs(Config.Groups) do
        local groupHash = GetHashKey(groupName)
        local animKey = savedAnims[groupName] or Config.DefaultAnimations[groupHash]
        
        if animKey and Config.Animations[animKey] then
            selectedAnimations[groupHash] = Config.Animations[animKey].anim
        else
            selectedAnimations[groupHash] = Config.FallbackAnim
        end
    end
end

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do
        Wait(500)
    end
    
    isDataLoaded = false

    populateAnimations({}) 

    TriggerServerEvent('lavie_animdraw:server:loadAnims')
end)

RegisterNetEvent('lavie_animdraw:client:loadAnims', function(savedAnims)
    populateAnimations(savedAnims)

    savedAnims = savedAnims or {}

    AimAnim = savedAnims['aim_style'] or 'nil'
    HoldingAnim = savedAnims['holding_style'] or 'nil'

    holsterStyles = {}

    for _, groupName in ipairs(Config.Groups) do
        local groupHash = GetHashKey(groupName)

        holsterStyles[groupHash] = savedAnims['holster_style_' .. groupName] or 'nil'
    end

    isDataLoaded = true
end)

exports('getWeaponAnim', function(weaponGroup)
    local isPrime = false

    if GetResourceState('prime_status') == 'started' then
        isPrime = exports.prime_status:IsPrime()
    end

    if isPrime then
        -- Check custom holster anim for this weapon group
        local holsterAnim = holsterStyles[weaponGroup]

        if holsterAnim and holsterAnim ~= "nil" and holsterAnim ~= "" then
            if holsterAnim == "BackHolsterAnimation" then
                return
                {
                    'reaction@intimidation@1h',
                    'intro',
                    600,
                    'reaction@intimidation@1h',
                    'outro',
                    2000
                }
            elseif holsterAnim == "SideHolsterAnimation" then
                return
                {
                    'reaction@intimidation@cop@unarmed',
                    'intro',
                    200,
                    'reaction@intimidation@cop@unarmed',
                    'outro',
                    200
                }
            elseif holsterAnim == "FrontHolsterAnimation" then
                return
                {
                    'combat@combat_reactions@pistol_1h_gang',
                    '0',
                    600,
                    'combat@combat_reactions@pistol_1h_gang',
                    '0',
                    1000
                }
            elseif holsterAnim == "AgressiveFrontHolsterAnimation" then
                return
                {
                    'combat@combat_reactions@pistol_1h_hillbilly',
                    '0',
                    600,
                    'combat@combat_reactions@pistol_1h_gang',
                    '0',
                    1000
                }
            elseif holsterAnim == "SideLegHolsterAnimation" then
                return
                {
                    'reaction@male_stand@big_variations@d',
                    'react_big_variations_m',
                    500,
                    'reaction@male_stand@big_variations@d',
                    'react_big_variations_m',
                    500
                }
            end
        end
        return selectedAnimations[weaponGroup] or Config.FallbackAnim
    end

    local isPoliceOnDuty = (LocalPlayer.state.factionCategory == 'police' and LocalPlayer.state.factionDuty)

    if isPoliceOnDuty then
        if weaponGroup == GetHashKey("GROUP_PISTOL") or weaponGroup == GetHashKey("GROUP_STUNGUN") then
            return Config.Animations.police.anim
        end
    end
    return nil
end)

local function openGroupAnimationMenu(group)
    local options = {}

    for animKey, animData in pairs(Config.Animations) do
        table.insert(options,
        {
            title = animData.title,
            description = animData.description,
            onSelect = function()
                local groupHash = GetHashKey(group)

                selectedAnimations[groupHash] = animData.anim
                
                TriggerServerEvent('lavie_animdraw:server:saveAnim', group, animKey)
                
                exports['lv_notify']:Notify(
                {
                    type = 'success',
                    title = 'Đã Lưu Animation',
                    message = ('Đã thiết lập Animation %s cho nhóm %s'):format(animData.title, group),
                    duration = 4500
                })
            end
        })
    end

    lib.registerContext(
    {
        id = 'group_animation_menu',
        title = 'Chọn Animation Cho ' .. group,
        options = options
    })
    lib.showContext('group_animation_menu')
end

local function openAnimationMenu()
    local options = {}

    for _, groupName in ipairs(Config.Groups) do
        table.insert(options,
        {
            title = groupName,
            description = "Chọn Animation cho nhóm vũ khí này",
            onSelect = function()
                openGroupAnimationMenu(groupName)
            end
        })
    end

    lib.registerContext(
    {
        id = 'animation_menu',
        title = 'Chọn Nhóm Vũ Khí',
        options = options
    })
    lib.showContext('animation_menu')
end

-------------------------------------------------------------------------------
-- WEAPON ANIMATION MENU (WAM) INTEGRATION (Aiming & Custom Holstering)
-------------------------------------------------------------------------------

local customPistolHashes = {}

local function updateCustomPistolHashes()
    customPistolHashes = {}
    if Config.CustomPistols then
        for _, wpn in ipairs(Config.CustomPistols) do
            local hash = type(wpn) == 'number' and wpn or GetHashKey(wpn)
            customPistolHashes[hash] = true
        end
    end
end

CreateThread(function()
    updateCustomPistolHashes()
end)

local function CheckWeaponForAim(ped)
    local hash = GetSelectedPedWeapon(ped)
    if hash and hash ~= 0 and hash ~= GetHashKey("WEAPON_UNARMED") and IsPedArmed(ped, 7) then
        return true
    end
    return false
end

local function loadAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        RequestAnimDict(dict)

        Wait(10)
    end
end

local clipsetLoaded = false

local function loadHoldingClipset()
    if not clipsetLoaded then
        RequestClipSet("move_ped_wpn_jerrycan_generic")

        while not HasClipSetLoaded("move_ped_wpn_jerrycan_generic") do
            Wait(10)
        end

        clipsetLoaded = true
    end
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local state = Entity(ped).state

        if state.aim_style ~= AimAnim then
            state:set('aim_style', AimAnim, true)
        end

        if state.holding_style ~= HoldingAnim then
            state:set('holding_style', HoldingAnim, true)
        end

        if HoldingAnim == "HoldOneArm" then
            if CheckWeaponForAim(ped) and not IsPedInAnyVehicle(ped, false) then
                loadHoldingClipset()

                SetPedWeaponMovementClipset(ped, "move_ped_wpn_jerrycan_generic", 0.50)
            else
                ResetPedWeaponMovementClipset(ped, 0.0)
            end
        end

        local sleep = 500

        if AimAnim == "GangsterAS" then
            if CheckWeaponForAim(ped) then
                local hash = GetSelectedPedWeapon(ped)

                if not IsPedInAnyVehicle(ped, false) then
                    sleep = 0

                    loadAnimDict("combat@aim_variations@1h@gang")

                    if IsControlPressed(0, 25) or IsPlayerFreeAiming(PlayerId()) or (IsControlPressed(0, 24) and GetAmmoInClip(ped, hash) > 0) then
                        if not IsEntityPlayingAnim(ped, "combat@aim_variations@1h@gang", "aim_variation_a", 3) then
                            TaskPlayAnim(ped, "combat@aim_variations@1h@gang", "aim_variation_a", 8.0, -8.0, -1, 49, 0, false, false, false)
                        end

                        SetPedCanArmIk(ped, false)
                    elseif IsEntityPlayingAnim(ped, "combat@aim_variations@1h@gang", "aim_variation_a", 3) then
                        ClearPedTasks(ped)

                        SetPedCanArmIk(ped, true)
                    end
                end
            end
        elseif AimAnim == "HillbillyAS" then
            if CheckWeaponForAim(ped) then
                local hash = GetSelectedPedWeapon(ped)

                if not IsPedInAnyVehicle(ped, false) then
                    sleep = 0

                    loadAnimDict("combat@aim_variations@1h@hillbilly")

                    if IsControlPressed(0, 25) or IsPlayerFreeAiming(PlayerId()) or (IsControlPressed(0, 24) and GetAmmoInClip(ped, hash) > 0) then
                        if not IsEntityPlayingAnim(ped, "combat@aim_variations@1h@hillbilly", "aim_variation_a", 3) then
                            TaskPlayAnim(ped, "combat@aim_variations@1h@hillbilly", "aim_variation_a", 8.0, -8.0, -1, 49, 0, false, false, false)
                        end

                        SetPedCanArmIk(ped, false)
                    elseif IsEntityPlayingAnim(ped, "combat@aim_variations@1h@hillbilly", "aim_variation_a", 3) then
                        ClearPedTasks(ped)

                        SetPedCanArmIk(ped, true)
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

local function openAimStyleMenu()
    local options =
    {
        {
            title = 'Default Aim',
            description = 'Thiết lập tư thế ngắm mặc định',
            onSelect = function()
                TriggerServerEvent('lavie_animdraw:server:saveAnim', 'aim_style', 'nil')

                AimAnim = "nil"

                exports['lv_notify']:Notify(
                {
                    type = 'success',
                    title = 'Đã Lưu Thiết Lập',
                    message = 'Đã chọn Aim Style mặc định',
                    duration = 4500
                })
            end
        },
        {
            title = 'Gangster Aim',
            description = 'Thiết lập tư thế ngắm kiểu Gangster',
            onSelect = function()
                TriggerServerEvent('lavie_animdraw:server:saveAnim', 'aim_style', 'GangsterAS')

                AimAnim = "GangsterAS"

                exports['lv_notify']:Notify(
                {
                    type = 'success',
                    title = 'Đã Lưu Thiết Lập',
                    message = 'Đã chọn Aim Style Gangster',
                    duration = 4500
                })
            end
        },
        {
            title = 'Hillbilly Aim',
            description = 'Thiết lập tư thế ngắm kiểu Hillbilly',
            onSelect = function()
                TriggerServerEvent('lavie_animdraw:server:saveAnim', 'aim_style', 'HillbillyAS')
                
                AimAnim = "HillbillyAS"
                
                exports['lv_notify']:Notify(
                {
                    type = 'success',
                    title = 'Đã Lưu Thiết Lập',
                    message = 'Đã chọn Aim Style Hillbilly',
                    duration = 4500
                })
            end
        }
    }

    lib.registerContext
    ({
        id = 'aim_style_menu',
        title = 'Chọn Tư Thế Ngắm (Aim Style)',
        menu = 'wam_main_menu',
        options = options
    })
    lib.showContext('aim_style_menu')
end

local function openHoldingStyleMenu()
    local options =
    {
        {
            title = 'Default Holding',
            description = 'Thiết lập tư thế cầm súng mặc định',
            onSelect = function()
                TriggerServerEvent('lavie_animdraw:server:saveAnim', 'holding_style', 'nil')

                HoldingAnim = "nil"
                ResetPedWeaponMovementClipset(PlayerPedId(), 0.0)

                exports['lv_notify']:Notify(
                {
                    type = 'success',
                    title = 'Đã Lưu Thiết Lập',
                    message = 'Đã chọn Holding Style mặc định',
                    duration = 4500
                })
            end
        },
        {
            title = 'Hold One Arm',
            description = 'Tư thế cầm súng bằng 1 tay (One-handed carry buông lỏng)',
            onSelect = function()
                TriggerServerEvent('lavie_animdraw:server:saveAnim', 'holding_style', 'HoldOneArm')

                HoldingAnim = "HoldOneArm"

                exports['lv_notify']:Notify(
                {
                    type = 'success',
                    title = 'Đã Lưu Thiết Lập',
                    message = 'Đã chọn Holding Style: Hold One Arm (Cầm 1 tay xuôi xuống)',
                    duration = 4500
                })
            end
        }
    }

    lib.registerContext
    ({
        id = 'holding_style_menu',
        title = 'Chọn Tư Thế Cầm Súng (Holding Style)',
        menu = 'wam_main_menu',
        options = options
    })
    lib.showContext('holding_style_menu')
end

local function openHolsterStyleSelectMenu(groupName)
    local options =
    {
        {
            title = 'Default Holster',
            description = 'Thiết lập rút súng mặc định',
            onSelect = function()
                local groupHash = GetHashKey(groupName)

                TriggerServerEvent('lavie_animdraw:server:saveAnim', 'holster_style_' .. groupName, 'nil')

                holsterStyles[groupHash] = "nil"

                exports['lv_notify']:Notify(
                {
                    type = 'success',
                    title = 'Đã Lưu Thiết Lập',
                    message = ('Đã chọn Holster Style mặc định cho %s'):format(groupName),
                    duration = 4500
                })
            end
        },
        {
            title = 'Back Holster',
            description = 'Rút súng từ phía sau lưng',
            onSelect = function()
                local groupHash = GetHashKey(groupName)

                TriggerServerEvent('lavie_animdraw:server:saveAnim', 'holster_style_' .. groupName, 'BackHolsterAnimation')

                holsterStyles[groupHash] = "BackHolsterAnimation"

                exports['lv_notify']:Notify(
                {
                    type = 'success',
                    title = 'Đã Lưu Thiết Lập',
                    message = ('Đã chọn Holster Style: Back Holster cho %s'):format(groupName),
                    duration = 4500
                })
            end
        },
        {
            title = 'Cop Holster',
            description = 'Rút súng kiểu cảnh sát (Bên hông)',
            onSelect = function()
                local groupHash = GetHashKey(groupName)

                TriggerServerEvent('lavie_animdraw:server:saveAnim', 'holster_style_' .. groupName, 'SideHolsterAnimation')

                holsterStyles[groupHash] = "SideHolsterAnimation"

                exports['lv_notify']:Notify(
                {
                    type = 'success',
                    title = 'Đã Lưu Thiết Lập',
                    message = ('Đã chọn Holster Style: Cop Holster cho %s'):format(groupName),
                    duration = 4500
                })
            end
        },
        {
            title = 'Front Holster',
            description = 'Rút súng từ phía trước',
            onSelect = function()
                local groupHash = GetHashKey(groupName)

                TriggerServerEvent('lavie_animdraw:server:saveAnim', 'holster_style_' .. groupName, 'FrontHolsterAnimation')

                holsterStyles[groupHash] = "FrontHolsterAnimation"

                exports['lv_notify']:Notify(
                {
                    type = 'success',
                    title = 'Đã Lưu Thiết Lập',
                    message = ('Đã chọn Holster Style: Front Holster cho %s'):format(groupName),
                    duration = 4500
                })
            end
        },
        {
            title = 'Aggressive Front Holster',
            description = 'Rút súng kiểu phía trước nhanh/mạnh mẽ',
            onSelect = function()
                local groupHash = GetHashKey(groupName)

                TriggerServerEvent('lavie_animdraw:server:saveAnim', 'holster_style_' .. groupName, 'AgressiveFrontHolsterAnimation')

                holsterStyles[groupHash] = "AgressiveFrontHolsterAnimation"

                exports['lv_notify']:Notify(
                {
                    type = 'success',
                    title = 'Đã Lưu Thiết Lập',
                    message = ('Đã chọn Holster Style: Aggressive Front cho %s'):format(groupName),
                    duration = 4500
                })
            end
        },
        {
            title = 'Side Leg Holster',
            description = 'Rút súng từ bao da đùi',
            onSelect = function()
                local groupHash = GetHashKey(groupName)

                TriggerServerEvent('lavie_animdraw:server:saveAnim', 'holster_style_' .. groupName, 'SideLegHolsterAnimation')

                holsterStyles[groupHash] = "SideLegHolsterAnimation"

                exports['lv_notify']:Notify(
                {
                    type = 'success',
                    title = 'Đã Lưu Thiết Lập',
                    message = ('Đã chọn Holster Style: Side Leg Holster cho %s'):format(groupName),
                    duration = 4500
                })
            end
        }
    }

    lib.registerContext(
    {
        id = 'holster_style_select_menu',
        title = 'Chọn Kiểu Rút: ' .. groupName,
        menu = 'holster_style_group_menu',
        options = options
    })
    lib.showContext('holster_style_select_menu')
end

local function openHolsterStyleGroupMenu()
    local options = {}

    for _, groupName in ipairs(Config.Groups) do
        table.insert(options,
        {
            title = groupName,
            description = "Chọn Holster Style cho nhóm vũ khí này",
            onSelect = function()
                openHolsterStyleSelectMenu(groupName)
            end
        })
    end

    lib.registerContext(
    {
        id = 'holster_style_group_menu',
        title = 'Chọn Nhóm Vũ Khí',
        menu = 'wam_main_menu',
        options = options
    })
    lib.showContext('holster_style_group_menu')
end

local function openWamMainMenu()
    lib.registerContext(
    {
        id = 'wam_main_menu',
        title = 'Weapon Animation Menu',
        options =
        {
            {
                title = 'Aim Animations',
                description = 'Cấu hình tư thế ngắm bắn súng của bạn',
                onSelect = function()
                    openAimStyleMenu()
                end
            },
            {
                title = 'Holding Animations',
                description = 'Cấu hình tư thế cầm súng của bạn',
                onSelect = function()
                    openHoldingStyleMenu()
                end
            },
            {
                title = 'Holster Animations',
                description = 'Cấu hình tư thế rút súng của từng loại vũ khí',
                onSelect = function()
                    openHolsterStyleGroupMenu()
                end
            }
        }
    })
    lib.showContext('wam_main_menu')
end

RegisterCommand('wam', function()
    local isPrime = false

    if GetResourceState('prime_status') == 'started' then
        isPrime = exports.prime_status:IsPrime()
    end

    if not isPrime then
        exports['lv_notify']:Notify(
        {
            type = 'error',
            title = 'Lỗi',
            message = 'Tính năng chọn Animation chỉ dành cho Prime',
            duration = 4500
        })
        return
    end

    openWamMainMenu()
end, false)

local aimingPeds = {}

AddStateBagChangeHandler('aim_style', nil, function(bagName, key, value, _reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)
    
    if entity and DoesEntityExist(entity) and IsEntityAPed(entity) then
        if value == "GangsterAS" or value == "HillbillyAS" then
            aimingPeds[entity] = true
        else
            aimingPeds[entity] = nil
            
            SetPedCanArmIk(entity, true)
        end
    end
end)

AddStateBagChangeHandler('holding_style', nil, function(bagName, key, value, _reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)

    if entity and DoesEntityExist(entity) and IsEntityAPed(entity) then
        if value == "HoldOneArm" then
            RequestClipSet("move_ped_wpn_jerrycan_generic")

            CreateThread(function()
                while not HasClipSetLoaded("move_ped_wpn_jerrycan_generic") do
                    Wait(10)
                end

                SetPedWeaponMovementClipset(entity, "move_ped_wpn_jerrycan_generic", 0.50)
            end)
        else
            ResetPedWeaponMovementClipset(entity, 0.0)
        end
    end
end)

CreateThread(function()
    while true do
        local sleep = 500
        
        if next(aimingPeds) then
            sleep = 0
            
            for ped, _ in pairs(aimingPeds) do
                if DoesEntityExist(ped) then
                    SetPedCanArmIk(ped, false)
                else
                    aimingPeds[ped] = nil
                end
            end
        end

        Wait(sleep)
    end
end)
