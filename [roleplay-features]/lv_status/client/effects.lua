local EffectState =
{
    hungerBlurActive = false,
    thirstFogActive = false,
    critDmgThread = false,
    speedThread = false,
    speedLevel = 0,
    wellFedThread = false,
    stressThread = false,
    addictionThread = false,
    statusGeneration = 0,
}

local function ApplyHungerWarning()
    if not EffectState.hungerBlurActive then
        EffectState.hungerBlurActive = true

        CreateThread(function()
            while EffectState.hungerBlurActive do
                SetTimecycleModifier('damage')
                SetTimecycleModifierStrength(0.12)

                Wait(500)
            end

            ClearTimecycleModifier()
        end)
    end
end

local function ClearHungerWarning()
    EffectState.hungerBlurActive = false
end

local function ApplyHungerCritical()
    AnimpostfxPlay('DrugsMichaelAliensFight', 0, true)

    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.08)
end

local function ClearHungerCritical()
    AnimpostfxStop('DrugsMichaelAliensFight')

    StopGameplayCamShaking(true)

    ClearHungerWarning()
end

local function ApplyThirstWarning()
    if not EffectState.thirstFogActive then
        EffectState.thirstFogActive = true

        CreateThread(function()
            while EffectState.thirstFogActive do
                SetTimecycleModifier('spectator3')
                SetTimecycleModifierStrength(0.10)

                Wait(500)
            end

            ClearTimecycleModifier()
        end)
    end
end

local function ClearThirstWarning()
    EffectState.thirstFogActive = false
end

local function ApplyThirstCritical()
    AnimpostfxPlay('DeathFailOut', 0, true)

    ShakeGameplayCam('HAND_SHAKE', 0.05)
end

local function ClearThirstCritical()
    AnimpostfxStop('DeathFailOut')

    StopGameplayCamShaking(true)

    ClearThirstWarning()
end

local function ApplyWellFedEffect()
    AnimpostfxPlay('Medkit', 800, false)
end

local function StartWellFedThread(getHunger, getThirst)
    if EffectState.wellFedThread then
        return
    end

    EffectState.wellFedThread = true

    CreateThread(function()
        while EffectState.wellFedThread do
            Wait(10000)

            local hunger = getHunger()
            local thirst = getThirst()

            if hunger >= Config.FullThreshold and thirst >= Config.FullThreshold then
                local ped = PlayerPedId()

                if not IsEntityDead(ped) then
                    local injuryState = LocalPlayer.state.Injured
                    local isInjured = (injuryState and injuryState.Status) or LocalPlayer.state.hasBodyDamage

                    if not isInjured then
                        local hp = GetEntityHealth(ped)
                        local maxHp = GetEntityMaxHealth(ped)
                        local targetHp = (maxHp == 200) and 150 or math.floor(maxHp / 2)

                        if hp < targetHp then
                            SetEntityHealth(ped, math.min(targetHp, hp + 1))
                        end
                    end
                end
            else
                break
            end
        end

        EffectState.wellFedThread = false
    end)
end

local function StopWellFedThread()
    EffectState.wellFedThread = false
end

local function StartCritDamageThread(getHunger, getThirst)
    if EffectState.critDmgThread then
        return
    end

    EffectState.critDmgThread = true

    CreateThread(function()
        while EffectState.critDmgThread do
            Wait(Config.CritDamageInterval)

            local hunger = getHunger()
            local thirst = getThirst()

            if (hunger < Config.CritThreshold or thirst < Config.CritThreshold) then
                local ped = PlayerPedId()

                if not IsEntityDead(ped) then
                    local helpupState = LocalPlayer.state.Helpup
                    local injuryState = LocalPlayer.state.Injured
                    local deadState = LocalPlayer.state.Dead
                    local isDown = (helpupState and helpupState.Status) or (injuryState and injuryState.Status) or (deadState and deadState.Status)

                    if not isDown then
                        if GetResourceState('lavie_injury') == 'started' then
                            TriggerEvent('lavie_injury:client:applyDamage', Config.CritDamage, 24818, GetHashKey("WEAPON_EXHAUSTION"), 0)
                        else
                            local hp = GetEntityHealth(ped)

                            SetEntityHealth(ped, math.max(100, hp - Config.CritDamage))
                        end
                    end
                end
            end
        end
    end)
end

local function StopCritDamageThread()
    EffectState.critDmgThread = false
end

local function ApplySpeedLimit(level)
    if EffectState.speedThread and EffectState.speedLevel == level then
        return
    end

    EffectState.speedThread = true
    EffectState.speedLevel  = level

    local ratio = (level == 2) and 1.0 or 1.5

    CreateThread(function()
        while EffectState.speedThread do
            local ped = PlayerPedId()

            if not IsEntityDead(ped) then
                SetPedMaxMoveBlendRatio(ped, ratio)
            end

            Wait(100)
        end

        SetPedMaxMoveBlendRatio(PlayerPedId(), 2.0)
    end)
end

local function ClearSpeedLimit()
    EffectState.speedThread = false
    EffectState.speedLevel  = 0
end


function UpdateEffects(hunger, thirst, getHungerFn, getThirstFn)
    local needCritDmg   = false
    local worstLevel    = 0 

    if hunger < Config.CritThreshold then
        ApplyHungerWarning()
        ApplyHungerCritical()

        needCritDmg = true

        worstLevel  = 2
    elseif hunger < Config.WarnThreshold then
        ApplyHungerWarning()

        ClearHungerCritical()

        if worstLevel < 1 then
            worstLevel = 1
        end
    else
        ClearHungerCritical()
        ClearHungerWarning()
    end

    if thirst < Config.CritThreshold then
        ApplyThirstWarning()
        ApplyThirstCritical()

        needCritDmg = true

        worstLevel  = 2
    elseif thirst < Config.WarnThreshold then
        ApplyThirstWarning()

        ClearThirstCritical()

        if worstLevel < 1 then
            worstLevel = 1
        end
    else
        ClearThirstCritical()
        ClearThirstWarning()
    end

    if worstLevel == 2 then
        ApplySpeedLimit(2)
    elseif worstLevel == 1 then
        ApplySpeedLimit(1)
    else
        ClearSpeedLimit()
    end

    if needCritDmg then
        StartCritDamageThread(getHungerFn, getThirstFn)
    else
        StopCritDamageThread()
    end
end

function TriggerWellFedEffect()
    ApplyWellFedEffect()
end

function StartStatusDebuffs(getStress, getAddiction, getLastAddictionAt)
    if not EffectState.stressThread then
        EffectState.stressThread = true

        local generation = EffectState.statusGeneration

        CreateThread(function()
            local stressHighSince = nil
            local nextBlurAt = 0

            while EffectState.stressThread and generation == EffectState.statusGeneration do
                if getStress() >= Config.StressBlurThreshold then
                    local now = math.floor(GetGameTimer() / 1000)

                    stressHighSince = stressHighSince or now

                    if now - stressHighSince >= Config.StressDebuffDelay
                        and GetGameTimer() >= nextBlurAt
                    then
                        local ped = PlayerPedId()

                        if not IsEntityDead(ped) and not IsPauseMenuActive() then
                            TriggerScreenblurFadeIn(1000)

                            Wait(Config.StressBlurDuration)

                            TriggerScreenblurFadeOut(1000)

                            nextBlurAt = GetGameTimer() + Config.StressBlurInterval
                        end
                    end
                else
                    stressHighSince = nil

                    nextBlurAt = 0

                    TriggerScreenblurFadeOut(500)
                end

                Wait(1000)
            end

            TriggerScreenblurFadeOut(500)
        end)
    end

    if not EffectState.addictionThread then
        EffectState.addictionThread = true

        local generation = EffectState.statusGeneration

        CreateThread(function()
            local nextDamageAt = 0

            while EffectState.addictionThread and generation == EffectState.statusGeneration do
                local isWithdrawal = getAddiction() >= Config.AddictionDamageThreshold
                    and os.time() - getLastAddictionAt() >= Config.AddictionWithdrawalDelay

                if isWithdrawal and GetGameTimer() >= nextDamageAt then
                    local ped = PlayerPedId()
                    local helpupState = LocalPlayer.state.Helpup
                    local injuryState = LocalPlayer.state.Injured
                    local deadState = LocalPlayer.state.Dead
                    local isDown = (helpupState and helpupState.Status)
                        or (injuryState and injuryState.Status)
                        or (deadState and deadState.Status)

                    if not IsEntityDead(ped) and not isDown then
                        local health = GetEntityHealth(ped)

                        SetEntityHealth(ped, math.max(100, health - Config.AddictionDamage))

                        nextDamageAt = GetGameTimer() + Config.AddictionDamageInterval
                    end
                elseif not isWithdrawal then
                    nextDamageAt = 0
                end

                Wait(1000)
            end
        end)
    end
end

local function StopStatusDebuffs()
    EffectState.statusGeneration = EffectState.statusGeneration + 1
    EffectState.stressThread = false
    EffectState.addictionThread = false

    TriggerScreenblurFadeOut(500)
end

function ClearAllEffects()
    ClearHungerCritical()
    ClearHungerWarning()
    ClearThirstCritical()
    ClearThirstWarning()

    StopCritDamageThread()
    StopWellFedThread()

    ClearSpeedLimit()
    
    StopStatusDebuffs()
end
