local stashes =
{
    ['140_gang'] =
    {
        id = 'gang_stash_a8f34c1e',
        label = '140 GANG',
        password = 'teamk84teamk84',
        coords = vec3(456.92, -1747.40, 28.69),
        slots = 128,
        maxWeight = 200000,
        managementWebhook = ''
    },
    ['wah_chong'] =
    {
        id = 'gang_stash_d27b905a',
        label = 'Wah Chong',
        password = '020303',
        coords = vec3(465.19, -750.57, 27.36),
        slots = 64,
        maxWeight = 100000,
        managementWebhook = ''
    },
    ['rancho_13'] =
    {
        id = 'gang_stash_61ce7d42',
        label = 'Rancho 13',
        password = 'rancho1331',
        coords = vector3(287.85, -1775.10, 28.43),
        slots = 64,
        maxWeight = 100000,
        managementWebhook = ''
    },
    ['mechanic'] =
    {
        id = 'gang_stash_b49e2c71',
        label = 'Mechanic',
        password = 'Rancho13fromstreet',
        coords = vec3(-224.29, -1320.06, 30.89),
        slots = 30,
        maxWeight = 50000,
        managementWebhook = ''
    },
    ['parkside_real_13'] =
    {
        id = 'gang_stash_e05c7a92',
        label = 'Parkside Real 13',
        password = 'PR26943',
        coords = vec3(386.05, -2025.63, 22.98),
        slots = 64,
        maxWeight = 100000,
        managementWebhook = ''
    },
    ['southside_18'] =
    {
        id = 'gang_stash_b3f91a82',
        label = 'SouthSide 18',
        password = 'SouthSide182026@',
        coords = vec3(-159.85, -1636.40, 37.25),
        slots = 64,
        maxWeight = 100000,
        managementWebhook = ''
    },
    ['lspd'] =
    {
        id = 'gang_stash_lspd_6398',
        label = 'LSPD',
        password = 'gangdetails',
        coords = vec3(63.98, -340.45, 45.07),
        slots = 64,
        maxWeight = 100000,
        managementWebhook = ''
    },
    ['rextune_1'] =
    {
        id = 'gang_stash_rextune_1',
        label = 'Rex Tune 1',
        password = 'Rextune303097',
        coords = vec3(-319.69, -136.63, 39.02),
        slots = 500,
        maxWeight = 5000000,
        managementWebhook = ''
    },
    ['rextune_2'] =
    {
        id = 'gang_stash_rextune_2',
        label = 'Rex Tune 2',
        password = 'Rextune303097',
        coords = vec3(-311.25, -114.26, 39.02),
        slots = 500,
        maxWeight = 5000000,
        managementWebhook = ''
    },
    ['rextune_3'] =
    {
        id = 'gang_stash_rextune_3',
        label = 'Rex Tune 3',
        password = 'Rextune303097',
        coords = vec3(-350.09, -86.56, 39.02),
        slots = 500,
        maxWeight = 5000000,
        managementWebhook = ''
    }
}

local discordWebhook = ""
local failedAttemptCooldown = {}
local stashById = {}

local function getPlayerDescription(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    local name = xPlayer and xPlayer.getName() or 'Unknown'
    local identifiers = GetPlayerIdentifiers(source)
    local identifier = identifiers[1] or 'unknown'

    for i = 1, #identifiers do
        if identifiers[i]:sub(1, 8) == 'license:' then
            identifier = identifiers[i]
            break
        end
    end
    return ('%s (`%s`, ID: %s)'):format(name, identifier, source)
end

local function sendWebhook(webhook, username, title, description, color)
    exports['legacyWebhook']:SendDiscordLog(
    {
        webhook = webhook,
        username = username,
        title = title,
        message = description,
        color = color,
        footer = os.date('%d/%m/%Y %H:%M:%S')
    })
end

local function sendDiscordLog(stash, title, description, color)
    sendWebhook(discordWebhook, 'Gang Stash Logs', title, description, color)

    local managementWebhook = stash and stash.managementWebhook

    if type(managementWebhook) == 'string'
        and managementWebhook ~= ''
        and managementWebhook ~= discordWebhook then
        sendWebhook(
            managementWebhook,
            ('%s Stash Logs'):format(stash.label),
            title,
            description,
            color
        )
    end
end

CreateThread(function()
    for _, stash in pairs(stashes) do
        stashById[stash.id] = stash

        exports.ox_inventory:RegisterStash(
            stash.id,
            stash.label,
            stash.slots,
            stash.maxWeight,
            false,
            nil,
            stash.coords
        )
    end
end)

lib.callback.register('gang_stashes:authorize', function(source, stashKey, password)
    local stash = stashes[stashKey]

    if not stash or type(password) ~= 'string' or password ~= stash.password then
        local now = os.time()

        if not failedAttemptCooldown[source] or now - failedAttemptCooldown[source] >= 10 then
            failedAttemptCooldown[source] = now

            sendDiscordLog(
                stash,
                'Sai Mật Khẩu Kho',
                ('**Người Chơi:** %s\n**Kho:** %s'):format(
                    getPlayerDescription(source),
                    stash and stash.label or tostring(stashKey)
                ),
                15158332
            )
        end
        return false
    end

    local playerPed = GetPlayerPed(source)

    if playerPed <= 0 then
        return false
    end

    local playerCoords = GetEntityCoords(playerPed)

    if #(playerCoords - stash.coords) > 3.0 then
        return false
    end

    sendDiscordLog(
        stash,
        'Mở Kho Gang',
        ('**Người chơi:** %s\n**Kho:** %s'):format(getPlayerDescription(source), stash.label),
        3066993
    )
    return stash.id
end)

exports.ox_inventory:registerHook('swapItems', function(payload)
    local fromId = tostring(payload.fromInventory)
    local toId = tostring(payload.toInventory)
    local stash = stashById[fromId] or stashById[toId]

    if not stash or fromId == toId then
        return
    end

    local depositing = toId == stash.id
    local item = payload.fromSlot
    local itemName = type(item) == 'table' and (item.label or item.name) or 'Không Xác Định'
    local count = tonumber(payload.count) or 0

    sendDiscordLog(
        stash,
        depositing and 'Gửi Vật Phẩm Vào Kho' or 'Rút Vật Phẩm Khỏi Kho',
        ('**Người Chơi:** %s\n**Kho:** %s\n**Vật Phẩm:** %s\n**Số Lượng:** %s'):format(
            getPlayerDescription(payload.source),
            stash.label,
            itemName,
            count
        ),
        depositing and 3447003 or 15105570
    )
end,
{
    inventoryFilter =
    {
        '^gang_stash_'
    }
})

AddEventHandler('playerDropped', function()
    failedAttemptCooldown[source] = nil
end)
