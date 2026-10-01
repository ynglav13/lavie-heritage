MedicalClient = MedicalClient or {}
DamageClient = {}
MedicalClient.Damage = DamageClient
DamageClient.Function = {}

MedicalShared = MedicalShared or {}
DamageUtil = {}
MedicalShared.Damage = DamageUtil
DamageUtil.Function = {}

---@param name string resource name
---@return boolean
DamageClient.Function.HasResource = function(name)
    return GetResourceState(name):find("start") ~= nil
end

---@param value any
---@return string
DamageUtil.Function.FirstToUpper = function(value)
    if type(value) ~= 'string' then
        value = tostring(value) or ""
    end
    if value == "" then return "" end
    return (value:gsub("^%l", string.upper))
end

DamageUtil.Function.NormalizeWeaponHash = function(hash)
    if type(hash) == 'string' then
        local numericHash = tonumber(hash)

        if numericHash then
            hash = numericHash
        elseif hash ~= '' then
            hash = joaat(hash)
        else
            return nil, nil
        end
    end

    local numericHash = tonumber(hash)

    if not numericHash
        or numericHash ~= numericHash
        or numericHash <= -math.huge
        or numericHash >= math.huge
        or numericHash % 1 ~= 0
        or numericHash < -2147483648
        or numericHash > 4294967295 then
        return nil, nil
    end

    if numericHash > 2147483647 then
        return numericHash - 4294967296, numericHash
    end

    if numericHash < 0 then
        return numericHash, numericHash + 4294967296
    end

    return numericHash, numericHash
end

DamageUtil.Function.GetWeaponData = function(hash)
    if not hash then
        return nil
    end

    local signedHash, unsignedHash = DamageUtil.Function.NormalizeWeaponHash(hash)
    local weaponData = DamageConfig.WeaponDamages[hash]
        or (signedHash and DamageConfig.WeaponDamages[signedHash])
        or (unsignedHash and DamageConfig.WeaponDamages[unsignedHash])
        or (signedHash and DamageConfig.WeaponDamages[tostring(signedHash)])
        or (unsignedHash and DamageConfig.WeaponDamages[tostring(unsignedHash)])
    return weaponData
end

DamageUtil.Function.CalculateDamageFalloff = function(damage, distance, minimumDistance, maximumDistance, minimumDamage, decay)
    damage = math.max(tonumber(damage) or 0.0, 0.0)
    distance = math.max(tonumber(distance) or 0.0, 0.0)
    minimumDistance = math.max(tonumber(minimumDistance) or 0.0, 0.0)
    maximumDistance = math.max(tonumber(maximumDistance) or minimumDistance, minimumDistance)
    minimumDamage = math.max(tonumber(minimumDamage) or 0.0, 0.0)

    if damage <= 0 or distance <= minimumDistance then
        return damage
    end

    local damageFloor = math.min(minimumDamage, damage)

    if distance >= maximumDistance then
        return damageFloor
    end

    decay = tonumber(decay)

    if decay and decay > 0 then
        return math.max(damageFloor, damage * math.exp(-(decay * distance)))
    end

    local factor = (distance - minimumDistance) / (maximumDistance - minimumDistance)
    local calculated = damage - (factor * (damage - damageFloor))
    return math.max(damageFloor, calculated)
end
