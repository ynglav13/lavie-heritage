local LethalGunAndExplosives = {
    -- Pistols
    [`WEAPON_PISTOL`] = true,
    [`WEAPON_PISTOL_MK2`] = true,
    [`WEAPON_COMBATPISTOL`] = true,
    [`WEAPON_APPISTOL`] = true,
    [`WEAPON_PISTOL50`] = true,
    [`WEAPON_SNSPISTOL`] = true,
    [`WEAPON_SNSPISTOL_MK2`] = true,
    [`WEAPON_HEAVYPISTOL`] = true,
    [`WEAPON_VINTAGEPISTOL`] = true,
    [`WEAPON_FLAREGUN`] = true,
    [`WEAPON_MARKSMANPISTOL`] = true,
    [`WEAPON_REVOLVER`] = true,
    [`WEAPON_REVOLVER_MK2`] = true,
    [`WEAPON_DOUBLEACTION`] = true,
    [`WEAPON_RAYPISTOL`] = true,
    [`WEAPON_CERAMICPISTOL`] = true,
    [`WEAPON_NAVYREVOLVER`] = true,
    [`WEAPON_GADGETPISTOL`] = true,

    -- SMG
    [`WEAPON_MICROSMG`] = true,
    [`WEAPON_SMG`] = true,
    [`WEAPON_SMG_MK2`] = true,
    [`WEAPON_ASSAULTSMG`] = true,
    [`WEAPON_COMBATPDW`] = true,
    [`WEAPON_MACHINEPISTOL`] = true,
    [`WEAPON_MINISMG`] = true,
    [`WEAPON_RAYCARBINE`] = true,

    -- Shotguns
    [`WEAPON_PUMPSHOTGUN`] = true,
    [`WEAPON_PUMPSHOTGUN_MK2`] = true,
    [`WEAPON_SAWNOFFSHOTGUN`] = true,
    [`WEAPON_ASSAULTSHOTGUN`] = true,
    [`WEAPON_BULLPUPSHOTGUN`] = true,
    [`WEAPON_MUSKET`] = true,
    [`WEAPON_HEAVYSHOTGUN`] = true,
    [`WEAPON_DBSHOTGUN`] = true,
    [`WEAPON_AUTOSHOTGUN`] = true,
    [`WEAPON_COMBATSHOTGUN`] = true,

    -- Rifles
    [`WEAPON_ASSAULTRIFLE`] = true,
    [`WEAPON_ASSAULTRIFLE_MK2`] = true,
    [`WEAPON_CARBINERIFLE`] = true,
    [`WEAPON_CARBINERIFLE_MK2`] = true,
    [`WEAPON_ADVANCEDRIFLE`] = true,
    [`WEAPON_SPECIALCARBINE`] = true,
    [`WEAPON_SPECIALCARBINE_MK2`] = true,
    [`WEAPON_BULLPUPRIFLE`] = true,
    [`WEAPON_BULLPUPRIFLE_MK2`] = true,
    [`WEAPON_COMPACTRIFLE`] = true,
    [`WEAPON_MILITARYRIFLE`] = true,
    [`WEAPON_HEAVYRIFLE`] = true,
    [`WEAPON_TACTICALRIFLE`] = true,

    -- MG
    [`WEAPON_MG`] = true,
    [`WEAPON_COMBATMG`] = true,
    [`WEAPON_COMBATMG_MK2`] = true,
    [`WEAPON_GUSENBERG`] = true,

    -- Sniper
    [`WEAPON_SNIPERRIFLE`] = true,
    [`WEAPON_HEAVYSNIPER`] = true,
    [`WEAPON_HEAVYSNIPER_MK2`] = true,
    [`WEAPON_MARKSMANRIFLE`] = true,
    [`WEAPON_MARKSMANRIFLE_MK2`] = true,
    [`WEAPON_PRECISIONRIFLE`] = true,

    -- Heavy & Explosives
    [`WEAPON_RPG`] = true,
    [`WEAPON_GRENADELAUNCHER`] = true,
    [`WEAPON_MINIGUN`] = true,
    [`WEAPON_FIREWORK`] = true,
    [`WEAPON_RAILGUN`] = true,
    [`WEAPON_HOMINGLAUNCHER`] = true,
    [`WEAPON_COMPACTLAUNCHER`] = true,
    [`WEAPON_RAYMINIGUN`] = true,
    [`WEAPON_GRENADE`] = true,
    [`WEAPON_BZGAS`] = true,
    [`WEAPON_MOLOTOV`] = true,
    [`WEAPON_STICKYBOMB`] = true,
    [`WEAPON_PROXMINE`] = true,

    -- Addon Guns
    [`WEAPON_ZN509`] = true,
    [`WEAPON_HLCP`] = true,
    [`WEAPON_VF9C`] = true,
    [`WEAPON_VF17`] = true,
    [`WEAPON_VF18`] = true,
    [`WEAPON_TCARBINE`] = true,
    [`WEAPON_BATTLERIFLE`] = true,
    [`WEAPON_TECPISTOL`] = true,
    [`WEAPON_TEC9`] = true,
    [`WEAPON_AR15`] = true,
    [`WEAPON_HK416`] = true,
    [`WEAPON_VFCARBINE`] = true,
    [`WEAPON_SPCARBINE`] = true,
    [`WEAPON_M870_SHOTGUN`] = true,
    [`WEAPON_870SO_SHOTGUN`] = true,
    [`WEAPON_HL50E`] = true,
    [`WEAPON_PROSMG`] = true,
    [`WEAPON_HLTMP7`] = true,
    [`WEAPON_HLCP`] = true,
}

local NonLethalWeapons = {
    [`WEAPON_UNARMED`] = true,
    [`WEAPON_KNUCKLE`] = true,
    [`WEAPON_NIGHTSTICK`] = true,
    [`WEAPON_COLBATON`] = true,
    [`WEAPON_FLASHLIGHT`] = true,
    [`WEAPON_BAT`] = true,
    [`WEAPON_GOLFCLUB`] = true,
    [`WEAPON_HAMMER`] = true,
    [`WEAPON_STUNGUN`] = true,
    [`WEAPON_STUNGUN_MP`] = true,
    [`WEAPON_Y2`] = true,
    [`WEAPON_C9`] = true,
    [`WEAPON_BEANBAG`] = true,
    [`WEAPON_YBEANBAG`] = true,
    [`WEAPON_LESSLAUNCHER`] = true,
    [`WEAPON_YLESSLAUNCHER`] = true,
    [`WEAPON_SNOWBALL`] = true,
    [`WEAPON_SNOWLAUNCHER`] = true,
}

local IncapacitationWeapons = {
    [`WEAPON_STUNGUN`] = true,
    [`WEAPON_STUNGUN_MP`] = true,
    [`WEAPON_Y2`] = true,
    [`WEAPON_C9`] = true,
}

local LethalWeaponGroups = {}

for _, groupName in ipairs({
    'GROUP_PISTOL',
    'GROUP_SMG',
    'GROUP_SHOTGUN',
    'GROUP_RIFLE',
    'GROUP_MG',
    'GROUP_SNIPER',
    'GROUP_HEAVY',
    'GROUP_THROWN'
}) do
    local signedGroup, unsignedGroup = DamageUtil.Function.NormalizeWeaponHash(groupName)

    if signedGroup then
        LethalWeaponGroups[signedGroup] = true
        LethalWeaponGroups[unsignedGroup] = true
    end
end

local MeleeWeaponGroupSigned, MeleeWeaponGroupUnsigned = DamageUtil.Function.NormalizeWeaponHash('GROUP_MELEE')

local function IsLethalGunOrExplosive(weaponHash)
    local signedHash, unsignedHash = DamageUtil.Function.NormalizeWeaponHash(weaponHash)

    if not signedHash or signedHash == 0 then
        return false
    end

    if NonLethalWeapons[signedHash] or NonLethalWeapons[unsignedHash] then
        return false
    end

    if LethalGunAndExplosives[signedHash] or LethalGunAndExplosives[unsignedHash] then
        return true
    end

    if GetWeaponDamageType then
        local dmgType = GetWeaponDamageType(signedHash)
        if dmgType == 3 then
            return true
        end
    end

    if GetWeapontypeGroup then
        local group = GetWeapontypeGroup(signedHash)
        local signedGroup, unsignedGroup = DamageUtil.Function.NormalizeWeaponHash(group)

        if signedGroup and (LethalWeaponGroups[signedGroup] or LethalWeaponGroups[unsignedGroup]) then
            return true
        end
    end

    return false
end

local function IsExplosive(weaponHash)
    local signedHash, unsignedHash = DamageUtil.Function.NormalizeWeaponHash(weaponHash)

    if not signedHash or signedHash == 0 then
        return false
    end

    if signedHash == `WEAPON_EXPLOSION` or unsignedHash == (`WEAPON_EXPLOSION` & 0xFFFFFFFF) then
        return true
    end

    if GetWeaponDamageType then
        local dmgType = GetWeaponDamageType(signedHash)
        if dmgType == 5 then
            return true
        end
    end

    return false
end

local function IsMeleeWeapon(weaponHash)
    local signedHash = DamageUtil.Function.NormalizeWeaponHash(weaponHash)

    if not signedHash or signedHash == 0 then
        return false
    end

    if GetWeapontypeGroup then
        local groupSigned, groupUnsigned = DamageUtil.Function.NormalizeWeaponHash(GetWeapontypeGroup(signedHash))

        if groupSigned == MeleeWeaponGroupSigned or groupUnsigned == MeleeWeaponGroupUnsigned then
            return true
        end
    end

    return GetWeaponDamageType and GetWeaponDamageType(signedHash) == 2 or false
end

if DamageConfig.Bodydamages.Enable then
    TriggerEvent('chat:addSuggestion', '/' .. DamageConfig.Bodydamages.Command, 'Kiểm tra cơ thể người chơi khác',
    {
        {
            name = "playerId",
            help = "Nhập ID của người chơi (Bỏ trống để kiểm tra người chơi đứng gần nhất)"
        },
    })

    RegisterCommand(DamageConfig.Bodydamages.Command, function(source, args)
        local serverId = tonumber(args[1])

        if not serverId then
            local myPed = PlayerPedId()
            local myCoords = GetEntityCoords(myPed)
            local closestPlayer, closestDistance = nil, 3.5

            for _, player in ipairs(GetActivePlayers()) do
                if player ~= PlayerId() then
                    local targetPed = GetPlayerPed(player)
                    if DoesEntityExist(targetPed) then
                        local dist = #(myCoords - GetEntityCoords(targetPed))
                        if dist < closestDistance then
                            closestPlayer = player
                            closestDistance = dist
                        end
                    end
                end
            end

            if closestPlayer then
                serverId = GetPlayerServerId(closestPlayer)
            else
                serverId = GetPlayerServerId(PlayerId())
            end
        end

        if serverId == GetPlayerServerId(PlayerId()) then
            ShowPlayerDamages(serverId)
            return
        end

        local targetPlayer = GetPlayerFromServerId(serverId)
        if targetPlayer and targetPlayer ~= -1 then
            local targetPed = GetPlayerPed(targetPlayer)
            if DoesEntityExist(targetPed) then
                local dist = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(targetPed))
                if dist <= 20.0 then
                    ShowPlayerDamages(serverId)
                    return
                end
            end
        end

        local pOnline = false

        if DamageConfig.Lib == 'ox_lib' then
            local players = lib.getNearbyPlayers(GetEntityCoords(PlayerPedId()), 20, true)

            for _, pData in pairs(players) do
                if GetPlayerServerId(pData.id) == serverId then
                    pOnline = true

                    ShowPlayerDamages(serverId)
                    break
                end
            end

            if not pOnline then
                lib.notify(
                {
                    title = 'Lỗi',
                    description = 'Người chơi không tồn tại hoặc không ở gần bạn',
                    type = 'error',
                    duration = 6000
                })
            end
        elseif DamageConfig.Lib == 'esx' then
            local players = ESX.Game.GetPlayersInArea(GetEntityCoords(PlayerPedId()), 20.0)

            for _, playerId in pairs(players) do
                if GetPlayerServerId(playerId) == serverId then
                    pOnline = true
                    ShowPlayerDamages(serverId)
                    break
                end
            end

            if not pOnline then
                ESX.ShowNotification('Người chơi không tồn tại hoặc không ở gần bạn')
            end
        end
    end)
end

local BoneCache = {}

for partName, bones in pairs(DamageConfig.Bodypart) do
    for _, boneId in ipairs(bones) do
        BoneCache[boneId] = partName
    end
end

if DamageConfig.Bodydamages.Enable then
    local weaponModifiers = {}

    local function SetConfiguredModifier(weapon, value, onlyIfMissing)
        local signedHash, unsignedHash = DamageUtil.Function.NormalizeWeaponHash(weapon)

        if signedHash then
            if not onlyIfMissing or weaponModifiers[signedHash] == nil then
                weaponModifiers[signedHash] = value
            end

            if not onlyIfMissing or weaponModifiers[unsignedHash] == nil then
                weaponModifiers[unsignedHash] = value
            end
        end
    end

    local function BuildWeaponModifiers()
        weaponModifiers = {}

        for WeaponName, Value in pairs(DamageConfig.WeaponDefault) do
            SetConfiguredModifier(WeaponName, Value)
        end

        for WeaponName, Value in pairs(DamageConfig.WeaponAddon) do
            SetConfiguredModifier(WeaponName, Value)
        end

        for WeaponHash in pairs(DamageConfig.WeaponDamages) do
            SetConfiguredModifier(WeaponHash, 0.0, true)
        end

        if GetResourceState('ox_inventory') == 'started' then
            local ok, items = pcall(function()
                return exports.ox_inventory:Items()
            end)

            if ok and type(items) == 'table' then
                for name, item in pairs(items) do
                    if type(name) == 'string' and name:sub(1, 7) == 'WEAPON_' and type(item) == 'table' and item.ammoname then
                        SetConfiguredModifier(name, 0.0, true)
                    end
                end
            end
        end

        SetConfiguredModifier('WEAPON_LESSLAUNCHER', 0.0001)
        SetConfiguredModifier('WEAPON_BEANBAG', 0.0001)
    end

    local function ApplyWeaponModifiers()
        for hash, value in pairs(weaponModifiers) do
            SetWeaponDamageModifier(hash, value)
        end
    end

    local trackedHealth = nil
    local modifiersDirty = true

    RegisterNetEvent('esx:onPlayerLogout', function()
        trackedHealth = nil
        modifiersDirty = true
    end)

    RegisterNetEvent('esx:onPlayerSpawn', function()
        trackedHealth = nil
        modifiersDirty = true
    end)

    AddEventHandler('onClientResourceStart', function(resourceName)
        if resourceName == 'ox_inventory' then
            modifiersDirty = true
        end
    end)

    CreateThread(function()
        local lastPed = 0
        local nextRefresh = 0

        while true do
            local ped = PlayerPedId()
            local now = GetGameTimer()

            if ped ~= lastPed or modifiersDirty or now >= nextRefresh then
                BuildWeaponModifiers()
                ApplyWeaponModifiers()
                SetPedSuffersCriticalHits(ped, false)
                SetPlayerMeleeWeaponDamageModifier(PlayerId(), 0.0)
                SetPlayerMeleeWeaponDefenseModifier(PlayerId(), 0.0)

                lastPed = ped
                modifiersDirty = false
                nextRefresh = now + 30000
            end

            if DoesEntityExist(ped) then
                local hp = GetEntityHealth(ped)
                if trackedHealth == nil or hp > trackedHealth then
                    trackedHealth = hp
                end
            end

            Wait(250)
        end
    end)
end

function ProcessDamage(attackerId, weaponHash, bone, customDamage, dist)
    if not DamageConfig.Bodydamages.Enable then
        return
    end

    local weaponData = DamageUtil.Function.GetWeaponData(weaponHash)
    local bodyPart = BoneCache[bone] or 'torso'
    local damage = customDamage ~= nil and tonumber(customDamage) or nil
    dist = math.max(tonumber(dist) or 0.0, 0.0)

    local signedHash, unsignedHash = DamageUtil.Function.NormalizeWeaponHash(weaponHash)

    if not signedHash then
        return
    end

    local isIncapacitation = IncapacitationWeapons[signedHash] or IncapacitationWeapons[unsignedHash]

    if unsignedHash == (`WEAPON_LESSLAUNCHER` & 0xFFFFFFFF) or unsignedHash == (`WEAPON_BEANBAG` & 0xFFFFFFFF) then
        damage = (bodyPart == 'head') and 10 or 5
    elseif not damage then
        local partDamage = weaponData and (
            weaponData[bodyPart]
            or (bodyPart == 'leftArm' or bodyPart == 'rightArm') and (weaponData['hand'] or weaponData['arm'] or weaponData['leftArm'] or weaponData['rightArm'])
            or (bodyPart == 'leftLeg' or bodyPart == 'rightLeg') and (weaponData['leg'] or weaponData['leftLeg'] or weaponData['rightLeg'])
            or (bodyPart == 'neck') and (weaponData['head'] or weaponData['neck'])
            or weaponData['torso']
        )

        if partDamage then
            damage = tonumber(partDamage)
        else
            damage = GetWeaponDamage(unsignedHash, 0)

            if not damage or damage == 0 then
                damage = 15
            end
        end
    end

    if not damage or damage ~= damage or damage < 0 then
        return
    end

    local minDis, maxDis, minDamage = DamageConfig.ReduceDamage.minRange, DamageConfig.ReduceDamage.maxRange, DamageConfig.ReduceDamage.minDamage

    if damage > 0 and dist > minDis then
        local decay

        if weaponData then
            decay = weaponData.decay or DamageConfig.Fallback[weaponData.name]
        end

        damage = DamageUtil.Function.CalculateDamageFalloff(damage, dist, minDis, maxDis, minDamage, decay)
    end

    local reduce = math.min(math.max(tonumber(LocalPlayer.state.reduceDamage) or 0, 0), 100)

    if reduce > 0 and not IsLethalGunOrExplosive(weaponHash) then
        damage = damage * (1 - reduce / 100)
    end

    local ped = PlayerPedId()
    local realHp = GetEntityHealth(ped)
    local nativeWouldDown = realHp <= 100 or IsEntityDead(ped) or IsPedDeadOrDying(ped, true)
    local health = trackedHealth or realHp
    if health < realHp then health = realHp end
    local armor  = GetPedArmour(ped)
    local hasHelmet = false
    local dmgApply = damage
    local isGunOrExplosive = IsLethalGunOrExplosive(weaponHash) or IsExplosive(weaponHash)
    local isMelee = IsMeleeWeapon(weaponHash)

    if DamageConfig.ReduceDamage.Enable and isGunOrExplosive and armor > 0 then
        local armourRate = math.min(math.max(tonumber(DamageConfig.ReduceDamage.GunExplosiveArmourDamageRate) or 0.80, 0.0), 1.0)
        local armourDamage = math.min(armor, damage * armourRate)
        armor = math.max(math.floor(armor - armourDamage + 0.5), 0)
        dmgApply = damage - armourDamage
        SetPedArmour(ped, armor)
    end

    if DamageConfig.ReduceDamage.Enable and bodyPart == 'head' and isGunOrExplosive then
        local helmet = GetPedPropIndex(ped, 0)

        for _, idx in ipairs(DamageConfig.ReduceDamage.Clothes.HelmetIndex) do
            if helmet == idx or (helmet + 1) == idx then
                hasHelmet = true
                break
            end
        end

        if hasHelmet then
            local helmetReducer = DamageConfig.ReduceDamage.HelmetDamageReducer or 0.5
            dmgApply = dmgApply * helmetReducer
        end
    end

    if DamageConfig.ReduceDamage.Enable and isMelee and armor > 0 then
        local meleeArmourRate = math.min(math.max(tonumber(DamageConfig.ReduceDamage.MeleeArmourDamageRate) or 0.90, 0.0), 1.0)
        local armourDamage = math.min(armor, damage * meleeArmourRate)
        armor = math.max(math.floor(armor - armourDamage + 0.5), 0)
        dmgApply = damage - armourDamage
        SetPedArmour(ped, armor)
    end

    dmgApply = math.max(dmgApply, 0.0)
    dmgApply = math.floor(dmgApply + 0.5)

    local finalHealth = math.floor(health - dmgApply)
    local wouldDown = (nativeWouldDown or finalHealth <= 100) and not isIncapacitation

    local isHeadshot = bodyPart == 'head'
    local isDeadlyHit = IsExplosive(weaponHash) or (isHeadshot and IsLethalGunOrExplosive(weaponHash))

    if not isDeadlyHit then
        if wouldDown then
            finalHealth = 101
            SetEntityHealth(ped, finalHealth)
        elseif not isIncapacitation then
            SetEntityHealth(ped, finalHealth)
        end
    else
        SetEntityHealth(ped, finalHealth)
    end

    trackedHealth = isIncapacitation and (trackedHealth or health) or finalHealth

    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle ~= 0 and (GetVehicleClass(vehicle) == 8 or GetVehicleClass(vehicle) == 13 or GetEntityModel(vehicle) == GetHashKey("lapdr1200")) then
        if unsignedHash == (`WEAPON_UNARMED` & 0xFFFFFFFF)
            or unsignedHash == (`WEAPON_RAMMED_BY_CAR` & 0xFFFFFFFF)
            or unsignedHash == (`WEAPON_RUN_OVER_BY_CAR` & 0xFFFFFFFF) then
            ClearPedTasksImmediately(ped)

            SetPedCanRagdoll(ped, true)
            SetPedToRagdoll(ped, 2000, 2000, 0, 0, 0, 0)
        end
    end

    local victimId = GetPlayerServerId(PlayerId())

    TriggerServerEvent(
        'lavie_injury:server:SetPlayerDamages',
        victimId,
        attackerId,
        unsignedHash,
        bone,
        dmgApply,
        dist,
        wouldDown,
        bodyPart,
        vehicle ~= 0,
        isIncapacitation and 'incapacitation' or nil
    )

    if DamageConfig.Option.Debug then
        local basedDamage = damage
        print(string.format('^1[lavie_injury:damage HIT]^0 Part: %s | Wep: %s | Attacker: %s | BaseDmg: %s | ApplyDmg: %s | Bone: %s | Dist: %.1f | FinalHealth: %s',
            tostring(bodyPart), tostring(unsignedHash), tostring(attackerId), tostring(basedDamage), tostring(dmgApply), tostring(bone), dist or 0.0, tostring(finalHealth)))
    end
end

local function applyDamageEvent(damage, bone, weaponHash, attackerId)
    ProcessDamage(attackerId, weaponHash or `WEAPON_VEHICLE_CRASH`, bone or 0, damage, 0.0)
end

RegisterNetEvent('lavie_injury:client:applyDamage', applyDamageEvent)
RegisterNetEvent('lavie_bodydamages:client:applyDamage', applyDamageEvent)

local lastDamageTime = 0
local lastAttackerId = nil
local lastWeaponHash = nil
local lastBone = nil

AddEventHandler('gameEventTriggered', function(name, args)
    if not DamageConfig.Bodydamages.Enable or name ~= 'CEventNetworkEntityDamage' then
        return
    end

    local victimPed = args[1]
    local attackerPed = args[2]

    if not DoesEntityExist(victimPed) or victimPed ~= PlayerPedId() then
        return
    end

    local attackerId = nil

    if DoesEntityExist(attackerPed) and IsPedAPlayer(attackerPed) then
        attackerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(attackerPed))
    end

    local weaponHash = args[7]

    if weaponHash then
        weaponHash = weaponHash & 0xFFFFFFFF
    end

    local customDamage = nil

    if weaponHash == `WEAPON_RAMMED_BY_CAR` or weaponHash == `WEAPON_RUN_OVER_BY_CAR` then
        local speed = 0

        if DoesEntityExist(attackerPed) then
            if IsEntityAVehicle(attackerPed) then
                speed = GetEntitySpeed(attackerPed)
            elseif IsPedInAnyVehicle(attackerPed, false) then
                local veh = GetVehiclePedIsIn(attackerPed, false)

                if veh ~= 0 then
                    speed = GetEntitySpeed(veh)
                end
            end
        end

        customDamage = math.floor(speed * 2.0)

        if customDamage < 5 then
            customDamage = 5
        end
    elseif DoesEntityExist(attackerPed) then
        if IsEntityAVehicle(attackerPed) then
            weaponHash = `WEAPON_RAMMED_BY_CAR`

            customDamage = math.floor(GetEntitySpeed(attackerPed) * 2.0)

            if customDamage < 5 then
                customDamage = 5
            end
        elseif IsPedInAnyVehicle(attackerPed, false) then
            local veh = GetVehiclePedIsIn(attackerPed, false)

            if veh ~= 0 and (not weaponHash or weaponHash == 0 or weaponHash == `WEAPON_UNARMED` or weaponHash == GetEntityModel(veh)) then
                weaponHash = `WEAPON_RAMMED_BY_CAR`

                customDamage = math.floor(GetEntitySpeed(veh) * 2.0)

                if customDamage < 5 then
                    customDamage = 5
                end
            end
        end
    end

    local hit, bone = GetPedLastDamageBone(victimPed)

    if not hit then
        bone = 0
    end

    if not weaponHash or weaponHash == 0 then
        if DoesEntityExist(attackerPed) then
            weaponHash = GetSelectedPedWeapon(attackerPed)
        else
            return -- Natural terrain/physics contact, ignore
        end
    end

    if (weaponHash == `WEAPON_FALL` or weaponHash == 3452007600 or weaponHash == -842959696) and not DoesEntityExist(attackerPed) then
        local curHp = GetEntityHealth(victimPed)
        if not trackedHealth or curHp >= trackedHealth then
            return
        end
    end

    local now = GetGameTimer()
    local isFireOrExplosive = weaponHash == `WEAPON_FIRE` or weaponHash == `WEAPON_PETROLCAN` or IsExplosive(weaponHash)
    local minInterval = isFireOrExplosive and 50 or 30

    if attackerId == lastAttackerId and weaponHash == lastWeaponHash and bone == lastBone and (now - lastDamageTime) < minInterval then
        return
    end

    lastDamageTime = now
    lastAttackerId = attackerId
    lastWeaponHash = weaponHash
    lastBone = bone

    local dist = 0.0

    if DoesEntityExist(attackerPed) then
        local victimCoords = GetEntityCoords(victimPed)
        local attackerCoords = GetEntityCoords(attackerPed)

        dist = #(victimCoords - attackerCoords)
    end

    ProcessDamage(attackerId, weaponHash, bone, customDamage, dist)
end)
