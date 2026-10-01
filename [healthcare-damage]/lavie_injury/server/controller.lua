InjuryServer = {}

local STATUS_HEALTHY = 0
local STATUS_HELPUP = 1
local STATUS_INJURED = 2
local STATUS_DEAD = 3
local MAX_STATUS = STATUS_DEAD
local records = {}
local loadTokens = {}
local pendingWrites = {}
local writeWorkers = {}
local latestPayloads = {}
local loadingPlayers = {}
local applyingState = {}
local recentBodyIncidents = {}
local deferredDamageContexts = {}
local auditQueue = {}
local auditHead = 1
local auditTail = 0
local auditRunning = false
local auditSequence = 0
local auditSession = ('%s-%s-%s'):format(os.time(), GetGameTimer(), math.random(100000, 999999))

local function isFiniteNumber(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local lethalWeapons =
{
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
    [`WEAPON_MICROSMG`] = true,
    [`WEAPON_SMG`] = true,
    [`WEAPON_SMG_MK2`] = true,
    [`WEAPON_ASSAULTSMG`] = true,
    [`WEAPON_COMBATPDW`] = true,
    [`WEAPON_MACHINEPISTOL`] = true,
    [`WEAPON_MINISMG`] = true,
    [`WEAPON_RAYCARBINE`] = true,
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
    [`WEAPON_M870_SHOTGUN`] = true,
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
    [`WEAPON_AR15`] = true,
    [`WEAPON_HK416`] = true,
    [`WEAPON_VFCARBINE`] = true,
    [`WEAPON_SPCARBINE`] = true,
    [`WEAPON_MILITARYRIFLE`] = true,
    [`WEAPON_HEAVYRIFLE`] = true,
    [`WEAPON_TACTICALRIFLE`] = true,
    [`WEAPON_MG`] = true,
    [`WEAPON_COMBATMG`] = true,
    [`WEAPON_COMBATMG_MK2`] = true,
    [`WEAPON_GUSENBERG`] = true,
    [`WEAPON_SNIPERRIFLE`] = true,
    [`WEAPON_HEAVYSNIPER`] = true,
    [`WEAPON_HEAVYSNIPER_MK2`] = true,
    [`WEAPON_MARKSMANRIFLE`] = true,
    [`WEAPON_MARKSMANRIFLE_MK2`] = true,
    [`WEAPON_PRECISIONRIFLE`] = true,
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
    [`WEAPON_ZN509`] = true,
    [`WEAPON_VF9C`] = true,
    [`WEAPON_VF17`] = true,
    [`WEAPON_VF18`] = true,
    [`WEAPON_TCARBINE`] = true,
    [`WEAPON_BATTLERIFLE`] = true,
    [`WEAPON_TECPISTOL`] = true,
    [`WEAPON_TEC9`] = true,
    [`WEAPON_HLCP`] = true,
    [`WEAPON_HL50E`] = true,
    [`WEAPON_PROSMG`] = true,
    [`WEAPON_870SO_SHOTGUN`] = true,
}

local nonLethalWeapons =
{
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
    [`WEAPON_LESSLAUNCHER`] = true,
    [`WEAPON_HIT_BY_WATER_CANNON`] = true,
    [`WEAPON_SNOWBALL`] = true,
    [`WEAPON_SNOWLAUNCHER`] = true,
}

local explosiveWeapons =
{
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
    [`WEAPON_EXPLOSION`] = true,
}

local fatalCauses =
{
    [`WEAPON_EXPLOSION`] = true,
    [`WEAPON_FIRE`] = true,
    [`WEAPON_DROWNING`] = true,
    [`WEAPON_DROWNING_IN_VEHICLE`] = true,
    [`WEAPON_BLEEDING`] = true,
}

local seriousMeleeWeapons =
{
    [`WEAPON_KNIFE`] = true,
    [`WEAPON_DAGGER`] = true,
    [`WEAPON_HATCHET`] = true,
    [`WEAPON_MACHETE`] = true,
    [`WEAPON_SWITCHBLADE`] = true,
    [`WEAPON_BATTLEAXE`] = true,
    [`WEAPON_STONE_HATCHET`] = true,
    [`WEAPON_KITCHENKNIFE`] = true,
    [`WEAPON_KATANA2`] = true,
    [`WEAPON_CLEAVER`] = true,
}

local seriousTraumaWeapons =
{
    [`WEAPON_RAMMED_BY_CAR`] = true,
    [`WEAPON_RUN_OVER_BY_CAR`] = true,
    [`WEAPON_VEHICLE_CRASH`] = true,
    [`WEAPON_HELI_CRASH`] = true,
    [`WEAPON_FALL`] = true,
    [`WEAPON_ANIMAL`] = true,
}

local function normalizeStatus(status)
    status = tonumber(status)

    if not status or status ~= status or status == math.huge or status == -math.huge then
        return nil
    end

    status = math.floor(status)

    if status < STATUS_HEALTHY or status > MAX_STATUS then
        return nil
    end

    return status
end

local function normalizeHash(value)
    if type(value) == 'string' then
        local numeric = tonumber(value)

        if numeric then
            value = numeric
        else
            value = joaat(value)
        end
    end

    local numeric = tonumber(value) or 0

    if numeric ~= numeric or numeric == math.huge or numeric == -math.huge then
        numeric = 0
    end

    local hash = math.floor(numeric)
    local unsigned = hash % 4294967296
    local signed = unsigned >= 2147483648 and unsigned - 4294967296 or unsigned
    return signed, unsigned
end

local function hasHash(collection, value)
    local hash, unsigned = normalizeHash(value)
    return collection[hash] == true or collection[unsigned] == true
end

local function cacheInventoryWeapons()
    if GetResourceState('ox_inventory') ~= 'started' then
        return
    end

    local ok, items = pcall(function()
        return exports.ox_inventory:Items()
    end)

    if not ok or type(items) ~= 'table' then
        return
    end

    for name, item in pairs(items) do
        if type(name) == 'string' and name:sub(1, 7) == 'WEAPON_' and type(item) == 'table' and item.ammoname then
            local hash = joaat(name)
            local unsigned = hash < 0 and hash + 4294967296 or hash

            if not nonLethalWeapons[hash] and not nonLethalWeapons[unsigned] then
                lethalWeapons[hash] = true
                lethalWeapons[unsigned] = true
            end
        end
    end
end

local function isLethal(context)
    if type(context.isLethal) == 'boolean' then
        return context.isLethal
    end

    if context.isHeavyTrauma == true then
        return true
    end

    if hasHash(nonLethalWeapons, context.weaponHash) then
        return false
    end

    if hasHash(lethalWeapons, context.weaponHash)
        or hasHash(seriousMeleeWeapons, context.weaponHash)
        or hasHash(seriousTraumaWeapons, context.weaponHash) then
        return true
    end

    return tonumber(context.damage) and tonumber(context.damage) >= 15 or false
end

local function isExplosive(context)
    if type(context.isExplosive) == 'boolean' then
        return context.isExplosive
    end

    return hasHash(explosiveWeapons, context.weaponHash)
end

local function isFatalCause(context)
    if type(context.isFatalCause) == 'boolean' then
        return context.isFatalCause
    end

    return hasHash(fatalCauses, context.weaponHash)
end

local function getDuration(status)
    if status == STATUS_DEAD then
        return math.max(0, tonumber(InjuryConfig.Cooldown.Dead) or 0)
    end

    if status == STATUS_HELPUP or status == STATUS_INJURED then
        return math.max(0, tonumber(InjuryConfig.Cooldown.Injury) or 0)
    end

    return 0
end

local function getPlayerIdentifier(playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    return xPlayer and xPlayer.identifier or nil
end

local function playerExists(playerId)
    playerId = tonumber(playerId)
    return playerId and playerId > 0 and GetPlayerName(tostring(playerId)) ~= nil
end

local function getPlayerCoords(playerId)
    local ped = GetPlayerPed(playerId)

    if ped == 0 then
        return nil
    end

    local coords = GetEntityCoords(ped)

    if not isFiniteNumber(coords.x) or not isFiniteNumber(coords.y) or not isFiniteNumber(coords.z) then
        return nil
    end

    return vector3(coords.x, coords.y, coords.z)
end

local function normalizeCoords(value, playerId)
    if type(value) == 'vector3' then
        if isFiniteNumber(value.x) and isFiniteNumber(value.y) and isFiniteNumber(value.z) then
            return value
        end

        return getPlayerCoords(playerId)
    end

    if type(value) == 'table' then
        local x = tonumber(value.x or value.X or value[1])
        local y = tonumber(value.y or value.Y or value[2])
        local z = tonumber(value.z or value.Z or value[3])

        if isFiniteNumber(x) and isFiniteNumber(y) and isFiniteNumber(z) then
            return vector3(x, y, z)
        end
    end

    return getPlayerCoords(playerId)
end

local function cloneStateData(record)
    if not record or record.status == STATUS_HEALTHY then
        return nil
    end

    local data =
    {
        Status = true,
        LeftTime = math.max(0, record.eligibleAt - os.time()),
        StartedAt = record.startedAt,
        EligibleAt = record.eligibleAt,
        Version = record.version,
    }

    if record.diedInVehicle ~= nil then
        data.DiedInVeh = record.diedInVehicle == true
    end

    return data
end

local function valuesMatch(value, expected)
    if expected == nil then
        return value == nil
    end

    if type(value) ~= 'table' then
        return false
    end

    return value.Status == expected.Status
        and tonumber(value.LeftTime) == tonumber(expected.LeftTime)
        and tonumber(value.StartedAt) == tonumber(expected.StartedAt)
        and tonumber(value.EligibleAt) == tonumber(expected.EligibleAt)
        and tonumber(value.Version) == tonumber(expected.Version)
        and value.DiedInVeh == expected.DiedInVeh
end

local function coordsMatch(value, expected)
    if expected == nil then
        return value == nil
    end

    if type(value) ~= 'table' then
        return false
    end

    local x = tonumber(value.X or value.x or value[1])
    local y = tonumber(value.Y or value.y or value[2])
    local z = tonumber(value.Z or value.z or value[3])

    if not isFiniteNumber(x) or not isFiniteNumber(y) or not isFiniteNumber(z) then
        return false
    end

    return math.abs(x - expected.x) <= 0.001
        and math.abs(y - expected.y) <= 0.001
        and math.abs(z - expected.z) <= 0.001
end

local function applyStateBags(playerId, record)
    if not playerExists(playerId) then
        return
    end

    applyingState[playerId] = true

    local activeKey
    local activeValue = cloneStateData(record)

    if record and record.status == STATUS_HELPUP then
        activeKey = 'Helpup'
    elseif record and record.status == STATUS_INJURED then
        activeKey = 'Injured'
    elseif record and record.status == STATUS_DEAD then
        activeKey = 'Dead'
    end

    local state = Player(playerId).state
    state:set('Helpup', activeKey == 'Helpup' and activeValue or nil, true)
    state:set('Injured', activeKey == 'Injured' and activeValue or nil, true)
    state:set('Dead', activeKey == 'Dead' and activeValue or nil, true)

    local downed = activeKey ~= nil
    state:set('isDead', downed, true)
    state:set('dead', downed, true)

    if downed and record.coords then
        state:set('DeadthCoords',
        {
            X = record.coords.x,
            Y = record.coords.y,
            Z = record.coords.z,
        }, true)
    else
        state:set('DeadthCoords', nil, true)
    end

    applyingState[playerId] = nil
end

local function reassertState(playerId)
    local record = records[playerId]

    if not playerExists(playerId) or applyingState[playerId] then
        return
    end

    if not record then
        if loadingPlayers[playerId] then
            applyStateBags(playerId, nil)
        end

        return
    end

    local expected = cloneStateData(record)
    local activeKey = record.status == STATUS_HELPUP and 'Helpup'
        or record.status == STATUS_INJURED and 'Injured'
        or record.status == STATUS_DEAD and 'Dead'
        or nil
    local state = Player(playerId).state
    local valid = valuesMatch(state.Helpup, activeKey == 'Helpup' and expected or nil)
        and valuesMatch(state.Injured, activeKey == 'Injured' and expected or nil)
        and valuesMatch(state.Dead, activeKey == 'Dead' and expected or nil)
        and state.isDead == (activeKey ~= nil)
        and state.dead == (activeKey ~= nil)
        and coordsMatch(state.DeadthCoords, activeKey and record.coords or nil)

    if not valid then
        applyStateBags(playerId, record)
    end
end

local function encodeRecord(record)
    local data =
    {
        s = record.status,
        v = record.version,
    }

    if record.status ~= STATUS_HEALTHY then
        data.t = record.startedAt
        data.e = record.eligibleAt

        if record.diedInVehicle ~= nil then
            data.d = record.diedInVehicle and 1 or 0
        end
    end

    return json.encode(data)
end

local function queueWrite(identifier, record)
    if type(identifier) ~= 'string' or identifier == '' then
        return
    end

    local queue = pendingWrites[identifier]

    if not queue then
        queue = {}
        pendingWrites[identifier] = queue
    end

    local payload = encodeRecord(record)
    latestPayloads[identifier] = payload

    queue[#queue + 1] =
    {
        payload = payload,
        version = record.version,
    }

    if writeWorkers[identifier] then
        return
    end

    writeWorkers[identifier] = true

    CreateThread(function()
        while true do
            local jobs = pendingWrites[identifier]
            local job = jobs and jobs[1]

            if not job then
                pendingWrites[identifier] = nil
                writeWorkers[identifier] = nil
                return
            end

            local attempt = 0
            local completed = false

            while not completed do
                attempt = attempt + 1

                local ok, result = pcall(MySQL.update.await,
                    'UPDATE users SET injury_status = ? WHERE identifier = ?',
                    {job.payload, identifier}
                )

                if ok and result ~= false then
                    completed = true
                else
                    local delay = math.min(30000, 500 * (2 ^ math.min(attempt - 1, 6)))

                    if attempt == 1 or attempt % 6 == 0 then
                        print(('[lavie_injury] Injury persistence retry identifier=%s version=%s attempt=%s'):format(identifier, job.version, attempt))
                    end

                    Wait(delay)
                end
            end

            table.remove(jobs, 1)
        end
    end)
end

local invalidWebhookWarned = false

local function isAllowedDiscordWebhook(value)
    if type(value) ~= 'string' or value == '' then
        return false
    end

    local host = value:match('^https://([^/]+)/')
    local path = value:match('^https://[^/]+(/[^%s]*)$')
    host = host and host:lower() or ''
    path = path or ''

    local allowedHost = host == 'discord.com'
        or host == 'www.discord.com'
        or host == 'discordapp.com'
        or host == 'www.discordapp.com'
        or host == 'canary.discord.com'
        or host == 'ptb.discord.com'
    local allowedPath = path:match('^/api/webhooks/%d+/[%w%._%-]+')
        or path:match('^/api/v%d+/webhooks/%d+/[%w%._%-]+')

    return allowedHost and allowedPath ~= nil
end

local function getKillWebhook()
    local configured = GetConvar('lavie_injury_kill_webhook', '')

    if configured == '' and InjuryConfig.Webhook and type(InjuryConfig.Webhook.Kill) == 'string' then
        configured = InjuryConfig.Webhook.Kill
    end

    if configured == '' then
        return ''
    end

    if isAllowedDiscordWebhook(configured) then
        return configured
    end

    if not invalidWebhookWarned then
        invalidWebhookWarned = true
        print('[lavie_injury] Invalid lavie_injury_kill_webhook; using the central default audit route')
    end

    return ''
end

local function buildAudit(playerId, previousStatus, context, transitionVersion)
    auditSequence = auditSequence + 1

    local webhook = getKillWebhook()
    local victim = ESX.GetPlayerFromId(playerId)
    local victimName = victim and victim.getName() or GetPlayerName(tostring(playerId)) or 'Không rõ'
    local victimIdentifier = victim and victim.identifier or GetPlayerIdentifierByType(playerId, 'license') or 'Không rõ'
    local killerId = tonumber(context.killerId or context.attackerId)
    local attackerIdentifier = type(context.attackerIdentifier) == 'string' and context.attackerIdentifier:sub(1, 128) or nil

    if killerId == playerId then
        killerId = nil
    end

    local killer = killerId and ESX.GetPlayerFromId(killerId) or nil

    if not attackerIdentifier or not killer or killer.identifier ~= attackerIdentifier then
        killer = nil
    end
    local fields =
    {
        {
            name = 'Nạn Nhân',
            value = ('Tên: %s\nID: %s\nIdentifier: %s'):format(victimName, playerId, victimIdentifier),
            inline = true,
        },
        {
            name = 'Trạng Thái',
            value = ('%s -> %s'):format(previousStatus, STATUS_DEAD),
            inline = true,
        },
        {
            name = 'Vũ Khí (Hash)',
            value = tostring(context.weaponHash or 0),
            inline = false,
        },
    }

    if killer then
        fields[#fields + 1] =
        {
            name = 'Kẻ Tấn Công',
            value = ('Tên: %s\nID: %s\nIdentifier: %s'):format(killer.getName(), killerId, killer.identifier),
            inline = false,
        }
    else
        fields[#fields + 1] =
        {
            name = 'Nguyên Nhân',
            value = tostring(context.reason or 'Không xác định'):sub(1, 128),
            inline = false,
        }
    end

    return
    {
        webhook = webhook,
        title = killer and 'LOG GIẾT NGƯỜI' or 'LOG TỬ VONG',
        color = 16711680,
        fields = fields,
        username = 'Lavie Kill Logs',
        idempotencyKey = ('injury-death:%s:%s:%s:%s'):format(auditSession, playerId, transitionVersion or 0, auditSequence),
        player =
        {
            id = playerId,
            name = victimName,
            identifier = victimIdentifier,
        },
        target = killer and
        {
            id = killerId,
            name = killer.getName(),
            identifier = killer.identifier,
        } or nil,
        context =
        {
            previousStatus = previousStatus,
            status = STATUS_DEAD,
            weaponHash = context.weaponHash or 0,
            fatalPart = context.fatalPart or context.bodyPart,
            diedInVehicle = context.diedInVehicle == true,
            reason = context.reason,
            coordinates = context.coords or context.deathCoords,
            claimedKillerId = context.claimedKillerId,
            claimedAttackerId = context.claimedAttackerId or not killer and killerId or nil,
            attackerIdentifier = attackerIdentifier,
            killerType = context.killerType,
            actorId = context.actorId,
        },
    }
end

local function sendDirectAudit(entry)
    local waiter = promise.new()
    local resolved = false

    local function resolve(value)
        if resolved then
            return
        end

        resolved = true
        waiter:resolve(value)
    end

    PerformHttpRequest(entry.webhook, function(status)
        resolve(type(status) == 'number' and status >= 200 and status < 300)
    end, 'POST', json.encode(
    {
        username = entry.username,
        embeds =
        {
            {
                title = entry.title,
                color = entry.color,
                fields = entry.fields,
                footer = {text = os.date('%d/%m/%Y %H:%M:%S')},
            },
        },
    }), {['Content-Type'] = 'application/json'})

    SetTimeout(15000, function()
        resolve(false)
    end)

    return Citizen.Await(waiter)
end

local function deliverAudit(entry)
    if GetResourceState('legacyWebhook') == 'started' then
        local payload =
        {
            title = entry.title,
            message = '',
            color = entry.color,
            fields = entry.fields,
            username = entry.username,
            category = 'injury',
            action = 'death_transition',
            idempotencyKey = entry.idempotencyKey,
            player = entry.player,
            target = entry.target,
            context = entry.context,
        }

        if entry.webhook ~= '' then
            payload.webhook = entry.webhook
        end

        local ok, accepted = pcall(function()
            return exports.legacyWebhook:SendDiscordLog(payload)
        end)

        if ok and accepted == true then
            return true
        end
    end

    if entry.webhook == '' then
        entry.webhook = getKillWebhook()
    end

    if entry.webhook == '' then
        return false
    end

    return sendDirectAudit(entry)
end

local function runAuditQueue()
    if auditRunning then
        return
    end

    auditRunning = true

    CreateThread(function()
        while auditHead <= auditTail do
            local entry = auditQueue[auditHead]

            if entry and deliverAudit(entry) then
                auditQueue[auditHead] = nil
                auditHead = auditHead + 1
            else
                Wait(5000)
            end
        end

        auditQueue = {}
        auditHead = 1
        auditTail = 0
        auditRunning = false
    end)
end

local function queueAudit(playerId, previousStatus, context, transitionVersion)
    local entry = buildAudit(playerId, previousStatus, context, transitionVersion)

    if not entry then
        return
    end

    auditTail = auditTail + 1
    auditQueue[auditTail] = entry
    runAuditQueue()
end

local function createRecord(playerId, status, context, previous)
    local now = os.time()
    local duration = getDuration(status)
    local version = previous and previous.version + 1 or 1
    local diedInVehicle

    if status == STATUS_DEAD then
        if type(context.diedInVehicle) == 'boolean' then
            diedInVehicle = context.diedInVehicle
        else
            local ped = GetPlayerPed(playerId)
            diedInVehicle = ped ~= 0 and GetVehiclePedIsIn(ped, false) ~= 0 or false
        end
    end

    return
    {
        playerId = playerId,
        identifier = getPlayerIdentifier(playerId),
        status = status,
        startedAt = now,
        eligibleAt = now + duration,
        version = version,
        diedInVehicle = diedInVehicle,
        coords = normalizeCoords(context.coords or context.deathCoords, playerId),
        reason = context.reason,
    }
end

local function emitStatus(playerId, record)
    if record.status == STATUS_HEALTHY then
        return
    end

    TriggerClientEvent('Injury:client:SetPlayerStatus', playerId, record.status, true, record.coords, false, cloneStateData(record))
end

local function transition(playerId, status, context)
    playerId = tonumber(playerId)
    status = normalizeStatus(status)
    context = type(context) == 'table' and context or {}

    if not playerId or not status or not playerExists(playerId) then
        return false, 'invalid_player'
    end

    local previous = records[playerId]

    if not previous then
        previous =
        {
            playerId = playerId,
            identifier = getPlayerIdentifier(playerId),
            status = STATUS_HEALTHY,
            startedAt = os.time(),
            eligibleAt = os.time(),
            version = 0,
        }
    end

    if previous.status == status then
        if not records[playerId] and status == STATUS_HEALTHY then
            loadTokens[playerId] = (loadTokens[playerId] or 0) + 1
            loadingPlayers[playerId] = nil
            deferredDamageContexts[playerId] = nil

            local record = createRecord(playerId, status, context, previous)
            records[playerId] = record
            applyStateBags(playerId, record)

            if record.identifier then
                queueWrite(record.identifier, record)
            end

            return true, status, nil
        end

        reassertState(playerId)
        return true, status, cloneStateData(previous)
    end

    loadTokens[playerId] = (loadTokens[playerId] or 0) + 1
    loadingPlayers[playerId] = nil
    deferredDamageContexts[playerId] = nil

    local record = createRecord(playerId, status, context, previous)
    records[playerId] = record
    applyStateBags(playerId, record)

    if record.identifier then
        queueWrite(record.identifier, record)
    end

    if status == STATUS_DEAD and previous.status ~= STATUS_DEAD then
        queueAudit(playerId, previous.status, context, record.version)
    end

    emitStatus(playerId, record)
    TriggerEvent('Injury:server:StatusChanged', playerId, previous.status, status, record.version, context)

    return true, status, cloneStateData(record)
end

local function decodeStored(value)
    if value == nil then
        return nil, false, false
    end

    if value == '' then
        return nil, false, false
    end

    local legacy = tonumber(value)

    if legacy ~= nil then
        if legacy ~= legacy
            or legacy == math.huge
            or legacy == -math.huge
            or legacy % 1 ~= 0
            or legacy < STATUS_HEALTHY
            or legacy > STATUS_DEAD then
            return nil, false, true
        end

        return {status = legacy}, true, false
    end

    if type(value) ~= 'string' then
        return nil, false, true
    end

    local ok, decoded = pcall(json.decode, value)

    if not ok or type(decoded) ~= 'table' then
        return nil, false, true
    end

    local storedStatus = tonumber(decoded.s or decoded.status)

    if not storedStatus
        or storedStatus ~= storedStatus
        or storedStatus == math.huge
        or storedStatus == -math.huge
        or storedStatus % 1 ~= 0
        or storedStatus < STATUS_HEALTHY
        or storedStatus > STATUS_DEAD then
        return nil, false, true
    end

    local version = tonumber(decoded.v or decoded.version)

    if not version
        or version ~= version
        or version == math.huge
        or version == -math.huge
        or version % 1 ~= 0
        or version < 1 then
        return nil, false, true
    end

    local startedAt = tonumber(decoded.t or decoded.startedAt)
    local eligibleAt = tonumber(decoded.e or decoded.eligibleAt)

    if storedStatus ~= STATUS_HEALTHY then
        if not startedAt
            or not eligibleAt
            or startedAt ~= startedAt
            or eligibleAt ~= eligibleAt
            or startedAt == math.huge
            or startedAt == -math.huge
            or eligibleAt == math.huge
            or eligibleAt == -math.huge
            or startedAt % 1 ~= 0
            or eligibleAt % 1 ~= 0
            or startedAt < 1
            or eligibleAt < startedAt then
            return nil, false, true
        end
    end

    return
    {
        status = storedStatus,
        startedAt = startedAt,
        eligibleAt = eligibleAt,
        version = version,
        diedInVehicle = decoded.d == 1 or decoded.d == true or decoded.diedInVehicle == true,
    }, false, false
end

local function installCorruptRecord(playerId, identifier)
    local now = os.time()
    local record =
    {
        playerId = playerId,
        identifier = identifier,
        status = STATUS_DEAD,
        startedAt = now,
        eligibleAt = now + getDuration(STATUS_DEAD),
        version = 1,
        diedInVehicle = false,
        coords = getPlayerCoords(playerId),
        reason = 'corrupt_storage',
        corrupt = true,
    }

    records[playerId] = record
    applyStateBags(playerId, record)
    emitStatus(playerId, record)
    print(('[lavie_injury] Corrupt injury status locked for player %s; stored value was not overwritten'):format(playerId))
end

local function installLoadedRecord(playerId, identifier, stored, legacy)
    local now = os.time()
    local status = stored and stored.status or STATUS_HEALTHY
    local duration = getDuration(status)
    local record =
    {
        playerId = playerId,
        identifier = identifier,
        status = status,
        startedAt = stored and stored.startedAt or now,
        eligibleAt = stored and stored.eligibleAt or now + duration,
        version = math.max(1, math.floor(stored and stored.version or 1)),
        diedInVehicle = status == STATUS_DEAD and stored and stored.diedInVehicle or nil,
        coords = getPlayerCoords(playerId),
        reason = 'load',
    }

    if status == STATUS_HEALTHY then
        record.startedAt = now
        record.eligibleAt = now
        record.diedInVehicle = nil
    end

    records[playerId] = record
    applyStateBags(playerId, record)
    emitStatus(playerId, record)

    if legacy then
        queueWrite(identifier, record)
    end
end

local function flushDeferredDamage(playerId)
    local contexts = deferredDamageContexts[playerId]
    deferredDamageContexts[playerId] = nil

    if not contexts or type(InjuryServer.ProcessDamage) ~= 'function' then
        return
    end

    for index = 1, #contexts do
        InjuryServer.ProcessDamage(contexts[index])
    end
end

function InjuryServer.LoadPlayer(playerId, suppliedPlayer)
    playerId = tonumber(playerId)

    if not playerId or not playerExists(playerId) then
        return
    end

    local xPlayer = suppliedPlayer or ESX.GetPlayerFromId(playerId)

    if not xPlayer or type(xPlayer.identifier) ~= 'string' then
        return
    end

    local identifier = xPlayer.identifier

    if records[playerId] and records[playerId].identifier ~= identifier then
        records[playerId] = nil
        recentBodyIncidents[playerId] = nil
        deferredDamageContexts[playerId] = nil
        applyStateBags(playerId, nil)
    end

    loadTokens[playerId] = (loadTokens[playerId] or 0) + 1

    local token = loadTokens[playerId]
    loadingPlayers[playerId] =
    {
        token = token,
        identifier = identifier,
    }

    CreateThread(function()
        local ok, value = pcall(MySQL.scalar.await,
            'SELECT injury_status FROM users WHERE identifier = ?',
            {identifier}
        )

        if loadTokens[playerId] ~= token then
            return
        end

        local currentPlayer = ESX.GetPlayerFromId(playerId)

        if not currentPlayer or currentPlayer.identifier ~= identifier then
            if loadingPlayers[playerId] and loadingPlayers[playerId].token == token then
                loadingPlayers[playerId] = nil
            end

            return
        end

        if not ok then
            print(('[lavie_injury] Failed to load injury status for player %s'):format(playerId))
            SetTimeout(2000, function()
                if loadTokens[playerId] == token then
                    InjuryServer.LoadPlayer(playerId, currentPlayer)
                end
            end)
            return
        end

        if latestPayloads[identifier] then
            value = latestPayloads[identifier]
        end

        local stored, legacy, corrupt = decodeStored(value)

        if loadingPlayers[playerId] and loadingPlayers[playerId].token == token then
            loadingPlayers[playerId] = nil
        end

        if corrupt then
            installCorruptRecord(playerId, identifier)
            flushDeferredDamage(playerId)
            return
        end

        installLoadedRecord(playerId, identifier, stored, legacy)
        flushDeferredDamage(playerId)
    end)
end

function InjuryServer.GetPlayerStatus(playerId)
    playerId = tonumber(playerId)

    if not playerId or not playerExists(playerId) then
        return STATUS_HEALTHY, nil, false, 'invalid_player'
    end

    local record = records[playerId]

    if not record then
        return STATUS_HEALTHY, nil, false, loadingPlayers[playerId] and 'loading' or 'not_loaded'
    end

    if loadingPlayers[playerId] then
        return record.status, cloneStateData(record), false, 'loading'
    end

    if record.corrupt then
        return record.status, cloneStateData(record), false, 'corrupt_storage'
    end

    return record.status, cloneStateData(record), true
end

function InjuryServer.IsPlayerReady(playerId)
    local _, _, ready, reason = InjuryServer.GetPlayerStatus(playerId)

    if ready ~= true then
        return false, reason
    end

    if DamageServer and type(DamageServer.IsPlayerReady) == 'function' then
        local damageReady, damageReason = DamageServer.IsPlayerReady(playerId)

        if damageReady ~= true then
            return false, damageReason or 'damage_loading'
        end
    end

    return true
end

function InjuryServer.GetRecord(playerId)
    return records[tonumber(playerId)]
end

function InjuryServer.SetPlayerStatus(playerId, status, context)
    playerId = tonumber(playerId)
    context = type(context) == 'table' and context or {}

    if not playerId or loadingPlayers[playerId] or not records[playerId] then
        return false, 'not_ready'
    end

    if records[playerId].corrupt and context.allowCorruptRepair ~= true then
        return false, 'corrupt_storage'
    end

    return transition(playerId, status, context)
end

function InjuryServer.ClearPlayerStatus(playerId, reason, options)
    playerId = tonumber(playerId)
    options = type(options) == 'table' and options or {}

    if not playerId or loadingPlayers[playerId] or not records[playerId] then
        return false, 'not_ready'
    end

    if records[playerId].corrupt and options.allowCorruptRepair ~= true then
        return false, 'corrupt_storage'
    end

    return transition(playerId, STATUS_HEALTHY, {reason = reason or 'clear'})
end

function InjuryServer.RevivePlayer(playerId, options)
    playerId = tonumber(playerId)
    options = type(options) == 'table' and options or {}

    if not playerId or not playerExists(playerId) then
        return false, 'invalid_player', false
    end

    local ready, readyReason = InjuryServer.IsPlayerReady(playerId)

    if not ready and not (readyReason == 'corrupt_storage' and options.allowCorruptRepair == true) then
        return false, readyReason or 'not_ready', false
    end

    local originalPlayer = ESX.GetPlayerFromId(playerId)
    local originalIdentifier = originalPlayer and originalPlayer.identifier

    if not originalIdentifier then
        return false, 'invalid_player', false
    end

    local previousStatus = InjuryServer.GetPlayerStatus(playerId)
    local previousRecord = records[playerId]

    if previousStatus == STATUS_HEALTHY and not options.allowHealthy then
        return false, 'not_downed', false
    end

    if options.expectedStatus ~= nil and previousStatus ~= normalizeStatus(options.expectedStatus) then
        return false, 'recovery_superseded', false
    end

    if options.expectedVersion ~= nil
        and (not previousRecord or previousRecord.version ~= tonumber(options.expectedVersion)) then
        return false, 'recovery_superseded', false
    end

    if type(InjuryCarryDragStopPlayer) == 'function' then
        InjuryCarryDragStopPlayer(playerId)
    end

    local cleared = InjuryServer.ClearPlayerStatus(playerId, options.reason or options.mode or 'revive',
    {
        allowCorruptRepair = options.allowCorruptRepair == true,
    })

    if not cleared then
        return false, 'clear_failed', false
    end

    local clearedRecord = records[playerId]
    local clearedVersion = clearedRecord and clearedRecord.version

    if options.clearBodyDamage ~= false
        and DamageServer
        and type(DamageServer.ClearPlayerDamages) == 'function' then
        local bodyOk, bodyCleared, bodyError = pcall(function()
            return DamageServer.ClearPlayerDamages(playerId)
        end)

        if not bodyOk or bodyCleared ~= true then
            print(('[lavie_injury] Body damage cleanup queued or failed for player %s: %s'):format(playerId, tostring(bodyError or bodyCleared)))
        end
    end

    local currentPlayer = ESX.GetPlayerFromId(playerId)

    if not currentPlayer or currentPlayer.identifier ~= originalIdentifier then
        return false, 'player_changed', true
    end

    local currentRecord = records[playerId]

    if not currentRecord
        or currentRecord ~= clearedRecord
        or currentRecord.status ~= STATUS_HEALTHY
        or currentRecord.version ~= clearedVersion then
        return false, 'recovery_superseded', true
    end

    local recoveryMode = tostring(options.mode or 'revive'):lower()
    local recoveryCoords = options.coords
    local recoveryHeading = tonumber(options.heading)
    local playerPed = GetPlayerPed(playerId)
    local resetArmor = recoveryMode == 'respawn' or recoveryMode == 'skipems'
    local recoveryArmor = resetArmor and 0
        or playerPed ~= 0 and GetPedArmour(playerPed)
        or tonumber(currentPlayer.getMeta('armor'))
        or 0
    recoveryArmor = math.min(math.max(math.floor(recoveryArmor), 0), 100)

    if recoveryMode == 'respawn' then
        recoveryCoords = recoveryCoords or InjuryConfig.RespawnMe.Coords
        recoveryHeading = recoveryHeading or tonumber(InjuryConfig.RespawnMe.Heading)
    end

    local recovery =
    {
        mode = recoveryMode,
        coords = normalizeCoords(recoveryCoords, playerId),
        heading = recoveryHeading or GetEntityHeading(GetPlayerPed(playerId)),
        health = math.max(1, math.floor(tonumber(options.health) or 200)),
        armor = recoveryArmor,
    }

    currentPlayer.setMeta('armor', recoveryArmor)
    TriggerClientEvent('lavie_injury:client:applyRecovery', playerId, recovery)
    return true, recovery, true
end

function InjuryServer.ProcessDamage(context)
    context = type(context) == 'table' and context or {}

    local playerId = tonumber(context.target or context.victim or context.victimId or context.playerId)

    if not playerId or not playerExists(playerId) then
        return STATUS_HEALTHY
    end

    if loadingPlayers[playerId] and not records[playerId] then
        local contexts = deferredDamageContexts[playerId]

        if not contexts then
            contexts = {}
            deferredDamageContexts[playerId] = contexts
        end

        local deferred = {}

        for key, value in pairs(context) do
            deferred[key] = value
        end

        deferred.victimId = playerId
        contexts[#contexts + 1] = deferred
        return STATUS_HEALTHY
    end

    local currentStatus = InjuryServer.GetPlayerStatus(playerId)

    if currentStatus == STATUS_DEAD then
        return STATUS_DEAD
    end

    local lethal = isLethal(context)
    local explosive = isExplosive(context)
    local fatalCause = isFatalCause(context)
    local fatalPart = tostring(context.fatalPart or context.bodyPart or ''):lower()
    local isHeadshot = fatalPart == 'head'
    local damage = tonumber(context.damage)
    local hasDamage = isFiniteNumber(damage) and damage > 0

    local canSetDead = explosive or fatalCause or (isHeadshot and lethal)
    local nextStatus = currentStatus

    if currentStatus == STATUS_HEALTHY and context.wouldDown == true then
        if canSetDead then
            nextStatus = STATUS_DEAD
        elseif lethal or fatalCause then
            nextStatus = STATUS_INJURED
        else
            nextStatus = STATUS_HELPUP
        end
    elseif currentStatus == STATUS_HELPUP then
        if canSetDead then
            nextStatus = STATUS_DEAD
        elseif hasDamage then
            nextStatus = STATUS_INJURED
        end
    elseif currentStatus == STATUS_INJURED and canSetDead then
        nextStatus = STATUS_DEAD
    end

    if context.wouldDown == true then
        local hash = select(2, normalizeHash(context.weaponHash))
        recentBodyIncidents[playerId] =
        {
            createdAt = GetGameTimer(),
            weaponHash = hash,
            fatalPart = fatalPart,
            consumed = false,
        }
    end

    if nextStatus ~= currentStatus then
        context.isLethal = lethal
        context.isExplosive = explosive
        context.isFatalCause = fatalCause
        transition(playerId, nextStatus, context)
    end

    local activeStatus = InjuryServer.GetPlayerStatus(playerId)
    return activeStatus
end

function InjuryServer.ConsumeBodydamageFallback(playerId, weaponHash, fatalPart)
    playerId = tonumber(playerId)

    local incident = playerId and recentBodyIncidents[playerId] or nil

    if not incident or incident.consumed or GetGameTimer() - incident.createdAt > 2500 then
        return false
    end

    local hash = select(2, normalizeHash(weaponHash))
    local part = tostring(fatalPart or ''):lower()

    if incident.weaponHash ~= hash then
        return false
    end

    if incident.fatalPart ~= '' and part ~= '' and incident.fatalPart ~= part then
        return false
    end

    incident.consumed = true
    return true
end

function InjuryServer.IsPlayerDowned(playerId)
    return InjuryServer.GetPlayerStatus(playerId) ~= STATUS_HEALTHY
end

function InjuryServer.ArePlayersNear(firstId, secondId, distance)
    firstId = tonumber(firstId)
    secondId = tonumber(secondId)

    if not playerExists(firstId) or not playerExists(secondId) then
        return false
    end

    if GetPlayerRoutingBucket(firstId) ~= GetPlayerRoutingBucket(secondId) then
        return false
    end

    local firstPed = GetPlayerPed(firstId)
    local secondPed = GetPlayerPed(secondId)

    if firstPed == 0 or secondPed == 0 then
        return false
    end

    return #(GetEntityCoords(firstPed) - GetEntityCoords(secondPed)) <= (tonumber(distance) or 5.0)
end

function InjuryServer.PlayerExists(playerId)
    return playerExists(playerId)
end

function InjuryServer.GetStateData(playerId)
    local record = records[tonumber(playerId)]
    return cloneStateData(record)
end

function InjuryServer.GetQueueStats()
    local stats =
    {
        records = 0,
        corruptRecords = 0,
        loading = 0,
        databaseIdentifiers = 0,
        databaseWrites = 0,
        databaseWorkers = 0,
        auditPending = math.max(auditTail - auditHead + 1, 0),
        auditRunning = auditRunning == true,
        centralPersistence = 0,
        centralQuarantine = 0,
        centralWebhookEntries = 0,
        centralReady = true,
    }

    for _, record in pairs(records) do
        stats.records = stats.records + 1

        if record.corrupt then
            stats.corruptRecords = stats.corruptRecords + 1
        end
    end

    for _ in pairs(loadingPlayers) do
        stats.loading = stats.loading + 1
    end

    for _, queue in pairs(pendingWrites) do
        stats.databaseIdentifiers = stats.databaseIdentifiers + 1
        stats.databaseWrites = stats.databaseWrites + #queue
    end

    for _ in pairs(writeWorkers) do
        stats.databaseWorkers = stats.databaseWorkers + 1
    end

    if GetResourceState('legacyWebhook') == 'started' then
        local ok, central = pcall(function()
            return exports.legacyWebhook:GetQueueStats()
        end)

        if ok and type(central) == 'table' then
            stats.centralPersistence = tonumber(central.persistence) or 0
            stats.centralQuarantine = tonumber(central.quarantine) or 0
            stats.centralWebhookEntries = tonumber(central.webhookEntries) or 0
            stats.centralReady = central.databaseReady ~= false
        else
            stats.centralReady = false
        end
    end

    local damageStats = DamageServer
        and type(DamageServer.GetQueueStats) == 'function'
        and DamageServer.GetQueueStats()
        or nil
    stats.damage = damageStats
    stats.damageReady = damageStats and damageStats.ready == true or false

    stats.ready = stats.loading == 0
        and stats.corruptRecords == 0
        and stats.databaseWrites == 0
        and stats.databaseWorkers == 0
        and stats.auditPending == 0
        and not stats.auditRunning
        and stats.centralPersistence == 0
        and stats.centralQuarantine == 0
        and stats.centralWebhookEntries == 0
        and stats.centralReady
        and stats.damageReady

    return stats
end

exports('ProcessDamage', function(context)
    return InjuryServer.ProcessDamage(context)
end)

exports('SetPlayerStatus', function(target, status, context)
    return InjuryServer.SetPlayerStatus(target, status, context)
end)

exports('ClearPlayerStatus', function(target, reason, options)
    return InjuryServer.ClearPlayerStatus(target, reason, options)
end)

exports('RevivePlayer', function(target, options)
    return InjuryServer.RevivePlayer(target, options)
end)

exports('GetPlayerStatus', function(target)
    return InjuryServer.GetPlayerStatus(target)
end)

exports('IsPlayerReady', function(target)
    return InjuryServer.IsPlayerReady(target)
end)

exports('GetQueueStats', function()
    return InjuryServer.GetQueueStats()
end)

exports('IsReady', function()
    local stats = InjuryServer.GetQueueStats()
    return stats.ready, stats
end)

RegisterCommand('injuryready', function(sourceId)
    if sourceId ~= 0 then
        local xPlayer = ESX.GetPlayerFromId(sourceId)
        local group = xPlayer and xPlayer.getGroup and xPlayer.getGroup() or 'user'

        if group == 'user' then
            return
        end
    end

    local stats = InjuryServer.GetQueueStats()

    local damage = stats.damage or {}

    print(('[lavie_injury] Queue status: loading=%d corrupt=%d db_identifiers=%d db_writes=%d db_workers=%d audit=%d damage_dirty=%d damage_loading=%d damage_pending=%d damage_webhook=%d central_persistence=%d central_quarantine=%d central_webhook=%d ready=%s'):format(
        stats.loading,
        stats.corruptRecords,
        stats.databaseIdentifiers,
        stats.databaseWrites,
        stats.databaseWorkers,
        stats.auditPending,
        tonumber(damage.dirty) or 0,
        tonumber(damage.loading) or 0,
        tonumber(damage.pending) or 0,
        tonumber(damage.webhookPending) or 0,
        stats.centralPersistence,
        stats.centralQuarantine,
        stats.centralWebhookEntries,
        stats.ready and 'true' or 'false'
    ))
end, false)

local watchedKeys =
{
    Helpup = true,
    Injured = true,
    Dead = true,
    isDead = true,
    dead = true,
    DeadthCoords = true,
}

for key in pairs(watchedKeys) do
    AddStateBagChangeHandler(key, nil, function(bagName)
        local playerId

        if GetPlayerFromStateBagName then
            playerId = GetPlayerFromStateBagName(bagName)
        end

        if not playerId then
            playerId = tonumber(tostring(bagName):match('^player:(%d+)$'))
        end

        if playerId and (records[playerId] or loadingPlayers[playerId]) and not applyingState[playerId] then
            SetTimeout(0, function()
                reassertState(playerId)
            end)
        end
    end)
end

function InjuryServer.ReleasePlayer(playerId)
    playerId = tonumber(playerId)

    if not playerId then
        return
    end

    loadTokens[playerId] = (loadTokens[playerId] or 0) + 1
    loadingPlayers[playerId] = nil
    records[playerId] = nil
    recentBodyIncidents[playerId] = nil
    deferredDamageContexts[playerId] = nil
    applyingState[playerId] = nil
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == 'ox_inventory' then
        cacheInventoryWeapons()
        return
    end

    if resourceName ~= GetCurrentResourceName() then
        return
    end

    cacheInventoryWeapons()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    local stats = InjuryServer.GetQueueStats()

    print(('[lavie_injury] Shutdown queue status: loading=%d db_writes=%d audit=%d ready=%s'):format(
        stats.loading,
        stats.databaseWrites,
        stats.auditPending,
        stats.ready and 'true' or 'false'
    ))
end)
