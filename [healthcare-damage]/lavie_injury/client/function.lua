InjuryClient = InjuryClient or
{
    visualActive = false,
    visualStatus = nil,
    visualState = nil,
    visualStartedAt = 0,
    informationGeneration = 0,
    recoveryRunning = false,
    lastRecoveryAt = 0,
    treatmentCamera = nil,
    frozen = false,
    invincible = false,
    driveByBlocked = false,
    timecycleActive = false,
    inventoryLocked = false,
    inventoryLockOwned = false,
    progressActive = false,
    fallbackCountdowns = {},
    eligibilityNotices = {},
}

local injuryControlLockUntil = 0

local function setTreatmentInvincibilityOwner(active)
    active = active == true

    if LocalPlayer.state.legacyInvInjuryTreatment ~= active then
        LocalPlayer.state:set('legacyInvInjuryTreatment', active, true)
    end
end

setTreatmentInvincibilityOwner(false)

local function stateIsDowned(state)
    return type(state) == 'table' and state.Status == true
end

local function getUnixTime()
    local ok, timestamp = pcall(GetCloudTimeAsInt)

    if ok and type(timestamp) == 'number' and timestamp > 0 then
        return timestamp
    end

    return os.time()
end

local function normalizeTimestamp(value)
    value = tonumber(value)

    if not value then
        return nil
    end

    if value > 100000000000 then
        value = value / 1000
    end

    return value
end

local function normalizeCoords(value, fallback)
    if value and tonumber(value.x) and tonumber(value.y) and tonumber(value.z) then
        return vector3(tonumber(value.x), tonumber(value.y), tonumber(value.z))
    end

    if type(value) == 'table' and tonumber(value.X) and tonumber(value.Y) and tonumber(value.Z) then
        return vector3(tonumber(value.X), tonumber(value.Y), tonumber(value.Z))
    end

    return fallback
end

local function findPedVehicleSeat(ped, vehicle)
    if vehicle == 0 then
        return nil
    end

    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if GetPedInVehicleSeat(vehicle, seat) == ped then
            return seat
        end
    end
end

local function waitForFade(predicate, timeout)
    local expiresAt = GetGameTimer() + (timeout or 3000)

    while not predicate() and GetGameTimer() < expiresAt do
        Wait(25)
    end
end

local function sendClientMessage(message)
    if GetResourceState('custom-chat') == 'started' then
        exports['custom-chat']:SendClientMessage(message)
    end
end

local function sendRecoveryMessage(message)
    local self = GetSelf()

    if vlib and message and message ~= '' then
        pcall(function()
            vlib:SendClientMessage(self.id, 255, 255, 255, message)
        end)
    end
end

local function setRecoveryNeeds()
    if GetResourceState('lv_status') == 'started' then
        pcall(function()
            exports['lv_status']:SetHunger(50)
            exports['lv_status']:SetThirst(50)
        end)
    end
end

function DrawText3D(x, y, z, text)
    local onScreen, screenX, screenY = World3dToScreen2d(x, y, z)

    if not onScreen then
        return
    end

    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 0, 0, 255)
    SetTextOutline()
    SetTextEntry('STRING')
    SetTextCentre(1)
    AddTextComponentString(text)
    DrawText(screenX, screenY)
end

function TriggerNetEvent(event, ...)
    if GetConvar('fiveguard_enable', 'false') == 'true' and GetResourceState('fiveguard') == 'started' then
        exports.fiveguard:ExecuteServerEvent(event, ...)
        return
    end

    TriggerServerEvent(event, ...)
end

function InventoryBusy(busy)
    busy = busy == true

    if busy then
        if not InjuryClient.inventoryLocked then
            InjuryClient.inventoryLocked = true
            InjuryClient.inventoryLockOwned = LocalPlayer.state.invBusy ~= true

            if InjuryClient.inventoryLockOwned then
                LocalPlayer.state:set('invBusy', true, false)
            end
        end

        if LocalPlayer.state.invOpen and GetResourceState('ox_inventory') == 'started' then
            pcall(function()
                exports.ox_inventory:closeInventory()
            end)
        end

        return
    end

    InjuryClient.inventoryLocked = false
    InjuryClient.inventoryLockOwned = false

    if not IsPlayerInjuryDowned() and not (LocalPlayer.state.cuffed or (ESX and ESX.PlayerData and ESX.PlayerData.cuffed)) then
        LocalPlayer.state:set('invBusy', false, false)
    end
end

function GetActiveInjuryState()
    local state = LocalPlayer.state

    if stateIsDowned(state.Dead) then
        return 3, 'Dead', state.Dead
    end

    if stateIsDowned(state.Injured) then
        return 2, 'Injured', state.Injured
    end

    if stateIsDowned(state.Helpup) then
        return 1, 'Helpup', state.Helpup
    end
end

function IsPlayerInjuryDowned()
    return GetActiveInjuryState() ~= nil
end

function GetInjuryRemainingSeconds(state, status)
    if type(state) ~= 'table' then
        return 0
    end

    local eligibleAt = normalizeTimestamp(state.EligibleAt)
    local startedAt = normalizeTimestamp(state.StartedAt)
    local leftTime = math.max(0, tonumber(state.LeftTime) or 0)

    if not eligibleAt and startedAt then
        eligibleAt = startedAt + leftTime
    end

    if eligibleAt then
        return math.max(0, math.ceil(eligibleAt - getUnixTime()))
    end

    local version = tostring(state.Version or 'legacy')
    local key = ('%s:%s:%s'):format(status or 'unknown', version, tostring(leftTime))
    local expiresAt = InjuryClient.fallbackCountdowns[key]

    if not expiresAt then
        expiresAt = GetGameTimer() + leftTime * 1000
        InjuryClient.fallbackCountdowns[key] = expiresAt
    end

    return math.max(0, math.ceil((expiresAt - GetGameTimer()) / 1000))
end

function LoadInjuryAnimDict(dict, timeout)
    if HasAnimDictLoaded(dict) then
        return true
    end

    RequestAnimDict(dict)

    local expiresAt = GetGameTimer() + (timeout or 5000)

    while not HasAnimDictLoaded(dict) and GetGameTimer() < expiresAt do
        Wait(10)
    end

    return HasAnimDictLoaded(dict)
end

local function disableDownedControls()
    local controls =
    {
        21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 37, 44, 45,
        59, 60, 61, 62, 63, 64, 68, 69, 70, 71, 72, 73, 74, 75, 76, 80, 86, 91, 92, 106, 114, 140, 141, 142, 157, 158,
        159, 160, 161, 162, 163, 164, 165, 257, 261, 262, 263, 264, 278, 279
    }

    for index = 1, #controls do
        DisableControlAction(0, controls[index], true)
    end

    DisablePlayerFiring(PlayerId(), true)
end

local function blockDownedWeapons()
    local playerId = PlayerId()
    local ped = PlayerPedId()

    DisablePlayerFiring(playerId, true)
    SetPlayerCanDoDriveBy(playerId, false)
    InjuryClient.driveByBlocked = true

    if GetSelectedPedWeapon(ped) ~= `WEAPON_UNARMED` then
        SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
    end
end

local function restoreDriveBy()
    if not InjuryClient.driveByBlocked then
        return
    end

    SetPlayerCanDoDriveBy(PlayerId(), true)
    InjuryClient.driveByBlocked = false
end

function ResetInjuryControlLock()
    injuryControlLockUntil = 0
    restoreDriveBy()
end

function RegisterInjuryTreatmentCamera(camera)
    if InjuryClient.treatmentCamera and DoesCamExist(InjuryClient.treatmentCamera) then
        DestroyCam(InjuryClient.treatmentCamera, false)
    end

    InjuryClient.treatmentCamera = camera
end

function ClearInjuryTreatmentCamera()
    if InjuryClient.treatmentCamera and DoesCamExist(InjuryClient.treatmentCamera) then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(InjuryClient.treatmentCamera, false)
    end

    InjuryClient.treatmentCamera = nil
end

function EffectUpdate(forceAnimation)
    if not InjuryClient.visualActive and not IsPlayerInjuryDowned() then
        return
    end

    InventoryBusy(true)
    disableDownedControls()
    blockDownedWeapons()

    local ped = PlayerPedId()

    if IsPedInAnyVehicle(ped, false) then
        return
    end

    if (type(IsInjuryCarryDragTarget) == 'function' and IsInjuryCarryDragTarget())
        or LocalPlayer.state.InjuryCarryDrag
        or IsEntityAttached(ped) then
        return
    end

    if LocalPlayer.state.isBeingHelpedUp then
        return
    end

    local dict = 'missarmenian2'
    local anim = 'corpse_search_exit_ped'

    if not LoadInjuryAnimDict(dict, 5000) then
        return
    end

    if not IsEntityPlayingAnim(ped, dict, anim, 3) then
        SetPedCanRagdoll(ped, false)
        TaskPlayAnim(ped, dict, anim, 8.0, 8.0, -1, 1, 1.0, false, false, false)
    end
end

local function resurrectDownedPed(status, deathCoords)
    local ped = PlayerPedId()
    local coords = normalizeCoords(deathCoords, GetEntityCoords(ped))
    local heading = GetEntityHeading(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)
    local seat = findPedVehicleSeat(ped, vehicle)

    if IsPedDeadOrDying(ped, true) or GetEntityHealth(ped) <= 0 then
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
        ped = PlayerPedId()

        if vehicle ~= 0 and seat then
            TaskWarpPedIntoVehicle(ped, vehicle, seat)
        end
    end

    local maximumHealth = GetEntityMaxHealth(ped)
    local targetHealth = status == 3 and maximumHealth or math.max(101, maximumHealth - 50)

    SetEntityHealth(ped, targetHealth)
end

local function announceDowned(status)
    sendClientMessage('{FF6347}(( Nhân vật của bạn đang bị thương/đã chết hãy /911 [Lý Do] để gọi EMT ))')

    if status == 3 then
        local minutes = string.format('%.1f', InjuryConfig.Cooldown.Dead / 60):gsub('%.0', '')

        sendClientMessage(('{FF6347}(( Nếu không có bác sĩ trong %s phút bạn có thể /respawnme để tự hồi sinh về bệnh viện ))'):format(minutes))
        sendClientMessage('{FF6347}(( Nếu bạn đang trong tình huống bất lợi và /respawnme bạn sẽ vi phạm luật lệ của máy chủ ))')
        return
    end

    local minutes = string.format('%.1f', InjuryConfig.Cooldown.Injury / 60):gsub('%.0', '')

    sendClientMessage(('{FF6347}(( Nếu không có bác sĩ trong %s phút bạn có thể /skipems để tự về bệnh viện ))'):format(minutes))
    sendClientMessage('{FF6347}(( Nếu bạn đang trong tình huống bất lợi và /skipems bạn sẽ vi phạm luật lệ của máy chủ ))')
end

function SetPlayerStatus(status, enabled, deathCoords, forceStatus, stateData)
    status = tonumber(status)

    if status ~= 1 and status ~= 2 and status ~= 3 then
        return false
    end

    if enabled ~= true then
        if not IsPlayerInjuryDowned() then
            CleanupInjuryVisuals(true)
        end

        return false
    end

    stateData = type(stateData) == 'table' and stateData or select(3, GetActiveInjuryState()) or
    {
        Status = true,
        LeftTime = status == 3 and InjuryConfig.Cooldown.Dead or InjuryConfig.Cooldown.Injury,
    }

    local wasActive = InjuryClient.visualActive

    InjuryClient.visualActive = true
    InjuryClient.visualStatus = status
    InjuryClient.visualState = stateData
    InjuryClient.visualStartedAt = GetGameTimer()
    injuryControlLockUntil = math.max(injuryControlLockUntil, GetGameTimer() + 9000)

    if ESX and ESX.SetPlayerData then
        ESX.SetPlayerData('dead', true)
    end

    InventoryBusy(true)
    resurrectDownedPed(status, deathCoords)

    if not IsPedInAnyVehicle(PlayerPedId(), false) then
        EffectUpdate(true)
    end

    TriggerEvent('Injury:client:ShowInformation')

    if not wasActive then
        announceDowned(status)
    end

    return true
end

function CleanupInjuryVisuals(clearTasks)
    local ownsPedState = InjuryClient.visualActive
        or InjuryClient.recoveryRunning
        or InjuryClient.progressActive
        or IsPlayerInjuryDowned()
        or (type(IsInjuryCarryDragTarget) == 'function' and IsInjuryCarryDragTarget())

    InjuryClient.visualActive = false
    InjuryClient.visualStatus = nil
    InjuryClient.visualState = nil
    InjuryClient.visualStartedAt = 0
    InjuryClient.informationGeneration = InjuryClient.informationGeneration + 1
    InjuryClient.fallbackCountdowns = {}
    InjuryClient.eligibilityNotices = {}

    ClearInjuryTreatmentCamera()

    local ped = PlayerPedId()

    if InjuryClient.frozen then
        FreezeEntityPosition(ped, false)
        InjuryClient.frozen = false
    end

    if InjuryClient.invincible then
        SetPlayerInvincible(PlayerId(), false)
        SetEntityInvincible(ped, false)
        InjuryClient.invincible = false
    end

    setTreatmentInvincibilityOwner(false)

    if InjuryClient.timecycleActive then
        ClearTimecycleModifier()
        ClearExtraTimecycleModifier()
        InjuryClient.timecycleActive = false
    end

    if type(CloseInjurySeatSelection) == 'function' then
        CloseInjurySeatSelection()
    end

    if ownsPedState and lib and lib.progressActive and lib.progressActive() then
        lib.cancelProgress()
    end

    InjuryClient.progressActive = false

    ResetInjuryControlLock()
    InventoryBusy(false)
    if ownsPedState then
        SetEntityCollision(ped, true, true)
        SetPedCanRagdoll(ped, true)
    end

    if ownsPedState and IsEntityAttached(ped) then
        DetachEntity(ped, true, false)
    end

    if clearTasks and ownsPedState then
        ClearPedTasksImmediately(ped)
    end
end

function AwaitCanonicalInjuryClear(timeout)
    local expiresAt = GetGameTimer() + (timeout or 1000)

    while IsPlayerInjuryDowned() and GetGameTimer() < expiresAt do
        Wait(25)
    end

    return not IsPlayerInjuryDowned()
end

local function triggerSpawnResetSequence()
    TriggerServerEvent('esx:onPlayerSpawn')
    TriggerEvent('esx:onPlayerSpawn')
    TriggerEvent('playerSpawned')
end

local function performRecoverySpawn(payload, resetSpawn)
    local ped = PlayerPedId()
    local currentArmor = math.min(math.max(math.floor(tonumber(payload.armor) or GetPedArmour(ped)), 0), 100)
    local coords = normalizeCoords(payload.coords, GetEntityCoords(ped))
    local heading = tonumber(payload.heading) or GetEntityHeading(ped)

    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)

    ped = PlayerPedId()

    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(ped, heading)
    SetEntityHealth(ped, math.max(101, tonumber(payload.health) or GetEntityMaxHealth(ped)))
    SetPedArmour(ped, currentArmor)
    if ESX and ESX.PlayerData then
        ESX.PlayerData.metadata = ESX.PlayerData.metadata or {}
        ESX.PlayerData.metadata.armor = currentArmor
    end
    TriggerServerEvent('esx:updateArmor', currentArmor)
    SetPlayerInvincible(PlayerId(), false)
    SetEntityInvincible(ped, false)
    SetEntityCollision(ped, true, true)
    SetPedCanRagdoll(ped, true)
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)
    SetEnableHandcuffs(ped, false)

    if ESX and ESX.SetPlayerData then
        ESX.SetPlayerData('dead', false)
    end

    if resetSpawn ~= false then
        triggerSpawnResetSequence()
    end
end

local function beginTreatmentCamera(coords)
    local camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

    if not camera or camera == 0 then
        return
    end

    SetCamCoord(camera, coords.x - 3.0, coords.y - 5.0, coords.z + 3.0)
    PointCamAtCoord(camera, coords.x, coords.y, coords.z + 0.5)
    RegisterInjuryTreatmentCamera(camera)
    RenderScriptCams(true, false, 0, true, true)
end

local function runRespawnTreatment(payload)
    DoScreenFadeOut(800)
    waitForFade(IsScreenFadedOut, 2500)
    performRecoverySpawn(payload, true)
    setRecoveryNeeds()
    sendRecoveryMessage(InjuryConfig.RespawnMe.Message)
    DoScreenFadeIn(800)
end

local function runSkipEmsTreatment(payload)
    ExecuteCommand('me đang được bác sĩ đưa lên phương tiện và chở về bệnh viện')
    DoScreenFadeOut(1000)
    waitForFade(IsScreenFadedOut, 3000)
    performRecoverySpawn(payload, true)

    local ped = PlayerPedId()
    local coords = normalizeCoords(payload.coords, GetEntityCoords(ped))

    FreezeEntityPosition(ped, true)
    InjuryClient.frozen = true
    SetPlayerInvincible(PlayerId(), true)
    SetEntityInvincible(ped, true)
    InjuryClient.invincible = true
    setTreatmentInvincibilityOwner(true)
    beginTreatmentCamera(coords)
    DoScreenFadeIn(1000)
    Wait(math.max(0, tonumber(InjuryConfig.SkipEMS.TreatmentTime) or 15000))
    DoScreenFadeOut(800)
    waitForFade(IsScreenFadedOut, 2500)
    ClearInjuryTreatmentCamera()
    FreezeEntityPosition(ped, false)
    InjuryClient.frozen = false
    SetPlayerInvincible(PlayerId(), false)
    SetEntityInvincible(ped, false)
    InjuryClient.invincible = false
    setTreatmentInvincibilityOwner(false)
    setRecoveryNeeds()
    ExecuteCommand('me đang được bác sĩ đưa lên giường và kiểm tra cơ thể')
    sendRecoveryMessage(InjuryConfig.SkipEMS.Message)
    sendRecoveryMessage(InjuryConfig.SkipEMS.FineMessage:format(InjuryConfig.SkipEMS.Fine))
    DoScreenFadeIn(1000)
end

function ApplyInjuryRecovery(payload)
    payload = type(payload) == 'table' and payload or {}

    if payload.ok == false or InjuryClient.recoveryRunning then
        return false
    end

    if not AwaitCanonicalInjuryClear(1000) then
        return false
    end

    local now = GetGameTimer()

    if now - InjuryClient.lastRecoveryAt < 2000 then
        return false
    end

    InjuryClient.recoveryRunning = true
    InjuryClient.lastRecoveryAt = now

    if type(StopInjuryCarryDrag) == 'function' then
        StopInjuryCarryDrag(true, true)
    end

    CleanupInjuryVisuals(true)

    local ok, errorMessage = xpcall(function()
        local mode = payload.action or payload.mode or 'revive'

        if mode == 'respawn' then
            runRespawnTreatment(payload)
        elseif mode == 'skipems' then
            runSkipEmsTreatment(payload)
        else
            performRecoverySpawn(payload, mode ~= 'helpup')
        end
    end, debug.traceback)

    CleanupInjuryVisuals(false)
    InjuryClient.recoveryRunning = false

    if IsScreenFadedOut() then
        DoScreenFadeIn(0)
    end

    if not ok then
        print(('[lavie_injury] Recovery visuals failed: %s'):format(errorMessage))
    end

    local activeStatus, _, activeState = GetActiveInjuryState()

    if activeStatus then
        SetPlayerStatus(activeStatus, true, LocalPlayer.state.DeadthCoords, false, activeState)
    else
        InventoryBusy(false)
        if not (LocalPlayer.state.cuffed or (ESX and ESX.PlayerData and ESX.PlayerData.cuffed)) then
            LocalPlayer.state:set('invBusy', false, false)
        end
    end

    return ok
end

CreateThread(function()
    while true do
        if GetGameTimer() < injuryControlLockUntil or IsPlayerInjuryDowned() or InjuryClient.visualActive then
            disableDownedControls()
            blockDownedWeapons()
            Wait(0)
        else
            restoreDriveBy()
            Wait(350)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    local restoreScreen = InjuryClient.recoveryRunning
        or InjuryClient.treatmentCamera ~= nil
        or InjuryClient.frozen

    CleanupInjuryVisuals(true)

    if restoreScreen and IsScreenFadedOut() then
        DoScreenFadeIn(0)
    end
end)
