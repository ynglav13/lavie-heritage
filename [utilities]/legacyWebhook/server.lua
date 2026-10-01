local webhookQueues = {}
local pausedRoutes = {}
local routes = {}
local queuedParts = {}
local finalizedParts = {}
local loadingRoutes = {}
local clientRateLimits = {}
local persistenceQueue = { items = {}, head = 1, tail = 0 }
local quarantineQueue = { items = {}, head = 1, tail = 0 }
local databaseReady = false
local databaseBusy = false
local databasePausedUntil = 0
local eventSequence = 0
local eventSession = tostring(GetHashKey(('%s:%s:%s'):format(os.time(), GetGameTimer(), tostring({}))))
local lastRawServerTick = GetGameTimer()
local serverTickEpoch = 0
local wallClockOffset = os.time() * 1000 - lastRawServerTick
local loadPendingRoute

local function getServerTick()
    local rawTick = GetGameTimer()

    if rawTick < lastRawServerTick - 1000000 then
        serverTickEpoch = serverTickEpoch + 4294967296
    end

    lastRawServerTick = rawTick
    return serverTickEpoch + rawTick
end

local function newQueue()
    return {
        items = {},
        head = 1,
        tail = 0,
        inFlight = false
    }
end

local function queueSize(queue)
    return math.max(0, queue.tail - queue.head + 1)
end

local function enqueue(queue, entry)
    queue.tail = queue.tail + 1
    queue.items[queue.tail] = entry
end

local function dequeue(queue, maximum)
    local available = queueSize(queue)

    if available == 0 then
        return nil
    end

    local count = math.min(available, maximum)
    local entries = {}

    for index = 1, count do
        local queueIndex = queue.head + index - 1
        entries[index] = queue.items[queueIndex]
        queue.items[queueIndex] = nil
    end

    queue.head = queue.head + count
    return entries
end

local function requeueFront(queue, entries)
    local newHead = queue.head - #entries

    for index = 1, #entries do
        queue.items[newHead + index - 1] = entries[index]
    end

    queue.head = newHead
end

local function compactQueue(queue)
    if queue.head <= 10000 then
        return
    end

    local items = {}
    local count = 0

    for queueIndex = queue.head, queue.tail do
        count = count + 1
        items[count] = queue.items[queueIndex]
    end

    queue.items = items
    queue.head = 1
    queue.tail = count
end

local function getWebhookQueue(routeKey)
    local queue = webhookQueues[routeKey]

    if queue then
        return queue
    end

    queue = newQueue()
    webhookQueues[routeKey] = queue
    return queue
end

local function sanitizeText(value)
    if value == nil then
        return nil
    end

    local text = tostring(value)
    local output = {}
    local index = 1
    local length = #text

    while index <= length do
        local first = string.byte(text, index)
        local width = 1
        local valid = first <= 127

        if first >= 194 and first <= 223 then
            width = 2
            local second = string.byte(text, index + 1)
            valid = second ~= nil and second >= 128 and second <= 191
        elseif first >= 224 and first <= 239 then
            width = 3
            local second = string.byte(text, index + 1)
            local third = string.byte(text, index + 2)
            valid = second ~= nil and third ~= nil
                and second >= 128 and second <= 191
                and third >= 128 and third <= 191
                and (first ~= 224 or second >= 160)
                and (first ~= 237 or second <= 159)
        elseif first >= 240 and first <= 244 then
            width = 4
            local second = string.byte(text, index + 1)
            local third = string.byte(text, index + 2)
            local fourth = string.byte(text, index + 3)
            valid = second ~= nil and third ~= nil and fourth ~= nil
                and second >= 128 and second <= 191
                and third >= 128 and third <= 191
                and fourth >= 128 and fourth <= 191
                and (first ~= 240 or second >= 144)
                and (first ~= 244 or second <= 143)
        end

        if valid then
            output[#output + 1] = string.sub(text, index, index + width - 1)
            index = index + width
        else
            output[#output + 1] = '\239\191\189'
            index = index + 1
        end
    end

    return table.concat(output)
end

local function boundedText(value, maximum)
    local text = sanitizeText(value)

    if text == nil then
        return nil
    end

    if not maximum then
        return text
    end

    local length = utf8.len(text)

    if length and length > maximum then
        local nextByte = utf8.offset(text, maximum + 1)
        return string.sub(text, 1, nextByte and nextByte - 1 or #text)
    end

    return text
end

local sensitiveKeys = {
    authorization = true,
    password = true,
    passwd = true,
    secret = true,
    token = true,
    webhook = true,
    webhook_url = true,
    webhookurl = true,
    api_key = true,
    apikey = true,
    access_token = true,
    bot_token = true,
    dsn = true
}

local function sanitizeStringSecret(value)
    local text = sanitizeText(value)
    text = text:gsub('https://[%w%.%-]+/api/v%d+/webhooks/%d+/[%w%._%-]+', '[REDACTED_WEBHOOK]')
    return text:gsub('https://[%w%.%-]+/api/webhooks/%d+/[%w%._%-]+', '[REDACTED_WEBHOOK]')
end

local function sanitizePayload(value, seen, depth)
    local valueType = type(value)

    if valueType == 'string' then
        return sanitizeStringSecret(value)
    end

    if valueType == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then
            return tostring(value)
        end

        return value
    end

    if valueType == 'boolean' or valueType == 'nil' then
        return value
    end

    if valueType ~= 'table' then
        return sanitizeText(value)
    end

    if depth >= 16 or seen[value] then
        return '[CIRCULAR_OR_MAX_DEPTH]'
    end

    seen[value] = true
    local output = {}

    for key, item in pairs(value) do
        if type(key) == 'string' then
            local keyText = sanitizeText(key)
            local normalizedKey = string.lower(keyText):gsub('[^%w_]', '')

            if sensitiveKeys[normalizedKey] then
                output[keyText] = '[REDACTED_SECRET]'
            else
                output[keyText] = sanitizePayload(item, seen, depth + 1)
            end
        elseif type(key) == 'number' then
            output[key] = sanitizePayload(item, seen, depth + 1)
        else
            output[sanitizeText(key)] = sanitizePayload(item, seen, depth + 1)
        end
    end

    seen[value] = nil
    return output
end

local function safeJson(value)
    local success, encoded = pcall(json.encode, sanitizePayload(value, {}, 0))

    if success then
        return encoded
    end

    return json.encode({ value = sanitizeText(value) })
end

local function splitText(value, maximum)
    local text = sanitizeText(value or '')

    if text == '' then
        return {}
    end

    local parts = {}
    local valid, length = pcall(utf8.len, text)

    if valid and length then
        local position = 1

        while position <= length do
            local firstByte = utf8.offset(text, position)
            local nextByte = utf8.offset(text, math.min(position + maximum, length + 1))
            parts[#parts + 1] = string.sub(text, firstByte, nextByte and nextByte - 1 or #text)
            position = position + maximum
        end
    else
        local position = 1

        while position <= #text do
            parts[#parts + 1] = string.sub(text, position, position + maximum - 1)
            position = position + maximum
        end
    end

    return parts
end

local function limitText(value, maximum)
    local parts = splitText(value, maximum)
    return parts[1] or ''
end

local function copyEmbedBase(embed)
    local copied = {}

    for key, value in pairs(embed) do
        if key ~= 'description' and key ~= 'fields' and key ~= 'footer' and key ~= 'title' then
            copied[key] = value
        end
    end

    copied.title = limitText(embed.title or 'Discord Log', 220)
    copied.color = tonumber(embed.color) and math.floor(tonumber(embed.color)) or Config.DefaultColor

    if type(embed.footer) == 'table' then
        copied.footer = {
            text = limitText(embed.footer.text or '', 1800),
            icon_url = embed.footer.icon_url
        }
    else
        copied.footer = {
            text = limitText(embed.footer or '', 1800)
        }
    end

    return copied
end

local function normalizeFields(fields)
    local normalized = {}

    if type(fields) ~= 'table' then
        return normalized
    end

    for index = 1, #fields do
        local field = fields[index]

        if type(field) == 'table' then
            local name = limitText(field.name or ('Field ' .. index), 200)
            local values = splitText(field.value or '', 900)

            if #values == 0 then
                values[1] = ' '
            end

            for part = 1, #values do
                local suffix = #values > 1 and (' (%s/%s)'):format(part, #values) or ''
                normalized[#normalized + 1] = {
                    name = limitText(name .. suffix, 256),
                    value = values[part],
                    inline = field.inline == true
                }
            end
        end
    end

    return normalized
end

local function expandEmbed(embed)
    local base = copyEmbedBase(type(embed) == 'table' and embed or {})
    local descriptions = splitText(type(embed) == 'table' and embed.description or '', 3000)
    local fields = normalizeFields(type(embed) == 'table' and embed.fields or nil)
    local parts = {}

    if #descriptions == 0 then
        parts[1] = copyEmbedBase(base)
    else
        for index = 1, #descriptions do
            local part = copyEmbedBase(base)
            part.description = descriptions[index]
            parts[#parts + 1] = part
        end
    end

    for index = 1, #fields do
        local field = fields[index]
        local part = parts[#parts]
        local currentFields = part.fields or {}
        local currentSize = #safeJson(part)
        local fieldSize = #field.name + #field.value

        if #currentFields >= 20 or currentSize + fieldSize > 5000 then
            part = copyEmbedBase(base)
            parts[#parts + 1] = part
            currentFields = {}
        end

        currentFields[#currentFields + 1] = field
        part.fields = currentFields
    end

    return parts
end

local function normalizeEmbeds(embeds, eventId)
    local normalized = {}

    if type(embeds) == 'table' then
        for index = 1, #embeds do
            local parts = expandEmbed(embeds[index])

            for part = 1, #parts do
                normalized[#normalized + 1] = parts[part]
            end
        end
    end

    if #normalized == 0 then
        normalized[1] = expandEmbed({})[1]
    end

    for index = 1, #normalized do
        local embed = normalized[index]
        local title = embed.title or 'Discord Log'

        if #normalized > 1 then
            title = ('%s (%s/%s)'):format(title, index, #normalized)
        end

        embed.title = limitText(title, 256)
        embed.footer = type(embed.footer) == 'table' and embed.footer or {}
        local footer = embed.footer.text
        embed.footer.text = limitText(((footer and footer ~= '') and (footer .. ' • ') or '') .. eventId, 2048)
    end

    return normalized
end

local function isAllowedWebhook(webhook)
    if type(webhook) ~= 'string' or webhook == '' then
        return false
    end

    local host = string.lower(webhook:match('^https://([^/]+)/') or '')
    local path = webhook:match('^https://[^/]+(/[^%s]*)$') or ''
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

local function routeKeyFor(webhook)
    return ('%s:%s:%s'):format(tostring(GetHashKey(webhook)), tostring(GetHashKey(string.reverse(webhook))), #webhook)
end

local function registerRoute(webhook)
    if not isAllowedWebhook(webhook) then
        return nil
    end

    local routeKey = routeKeyFor(webhook)
    local isNew = routes[routeKey] == nil
    routes[routeKey] = webhook

    if isNew and databaseReady and loadPendingRoute then
        loadPendingRoute(routeKey)
    end

    return routeKey
end

local function nextEventId()
    eventSequence = eventSequence + 1

    if eventSequence > 999999 then
        eventSequence = 1
    end

    return ('AUD-%s-%s-%s-%06d-%09d'):format(os.time(), getServerTick(), eventSession, eventSequence, math.random(0, 999999999))
end

local function resolveWebhook(data, fallback)
    if type(data) ~= 'table' then
        return nil
    end

    if data.webhook ~= nil then
        if type(data.webhook) ~= 'string' then
            return nil
        end

        if data.webhook == '' then
            return fallback
        end

        return data.webhook
    end

    if data.route ~= nil then
        if type(data.route) ~= 'string' then
            return false
        end

        local namedWebhook = type(Config.NamedWebhooks) == 'table' and Config.NamedWebhooks[data.route] or nil

        if type(namedWebhook) ~= 'string' or namedWebhook == '' then
            return false
        end

        return namedWebhook
    end

    return fallback
end

local function getHeader(headers, name)
    if type(headers) ~= 'table' then
        return nil
    end

    local target = string.lower(name)

    for key, value in pairs(headers) do
        if type(key) == 'string' and string.lower(key) == target then
            if type(value) == 'table' then
                return value[1]
            end

            return value
        end
    end

    return nil
end

local function parseRetryAfter(headers, body)
    local retryAfter = tonumber(getHeader(headers, 'Retry-After'))

    if not retryAfter and type(body) == 'string' and body ~= '' then
        local decodedSuccessfully, decoded = pcall(json.decode, body)

        if decodedSuccessfully and type(decoded) == 'table' then
            retryAfter = tonumber(decoded.retry_after)
        end
    end

    if not retryAfter or retryAfter <= 0 then
        return Config.RetryBase
    end

    return math.max(1, math.ceil(retryAfter * 1000))
end

local function pauseRoute(routeKey, duration)
    local token = (pausedRoutes[routeKey] or 0) + 1
    pausedRoutes[routeKey] = token

    SetTimeout(duration, function()
        if pausedRoutes[routeKey] == token then
            pausedRoutes[routeKey] = nil
        end
    end)
end

local function finiteDecimal(value)
    local number = tonumber(value)

    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end

    if math.abs(number) > 999999999999999999 then
        return nil
    end

    return number
end

local function finiteInteger(value)
    local number = finiteDecimal(value)

    if not number then
        return nil
    end

    number = math.floor(number)

    if number < -2147483648 or number > 2147483647 then
        return nil
    end

    return number
end

local function normalizeOccurredAt(value, fallback)
    local milliseconds = finiteDecimal(value)

    if not milliseconds or milliseconds < 0 or milliseconds > 253402300799999 then
        milliseconds = fallback
    end

    milliseconds = math.floor(milliseconds)
    local success, occurredAt = pcall(os.date, '%Y-%m-%d %H:%M:%S', math.floor(milliseconds / 1000))

    if not success or type(occurredAt) ~= 'string' then
        milliseconds = math.floor(fallback)
        occurredAt = os.date('%Y-%m-%d %H:%M:%S', math.floor(milliseconds / 1000))
    end

    return ('%s.%03d'):format(occurredAt, milliseconds % 1000), milliseconds
end

local function buildAuditRecord(data, eventId, callerResource, routeKey, discordStatus)
    local player = type(data.player) == 'table' and data.player or {}
    local target = type(data.target) == 'table' and data.target or {}
    local context = data.context

    if context == nil then
        context = data.metadata
    end

    local serverTick = getServerTick()
    local occurredAt, occurredAtMs = normalizeOccurredAt(data.occurredAtMs, wallClockOffset + serverTick)

    return {
        eventId = eventId,
        occurredAt = occurredAt,
        occurredAtMs = occurredAtMs,
        serverTick = serverTick,
        category = boundedText(data.category or 'general', 48) or 'general',
        action = boundedText(data.action or data.title or 'log', 96) or 'log',
        status = boundedText(data.status or 'committed', 32) or 'committed',
        callerResource = boundedText(callerResource or 'server', 96) or 'server',
        originResource = boundedText(data.sourceResource or data.originResource, 96),
        reason = boundedText(data.reason, 255),
        requestId = boundedText(data.requestId or data.idempotencyKey, 128),
        idempotencyKey = boundedText(data.idempotencyKey, 128),
        relatedEventId = boundedText(data.relatedEventId, 64),
        playerId = finiteInteger(player.id or data.playerId),
        playerName = boundedText(player.name or data.playerName, 128),
        identifier = boundedText(player.identifier or data.identifier, 128),
        license = boundedText(player.license or data.license, 128),
        targetId = finiteInteger(target.id or data.targetId),
        targetName = boundedText(target.name or data.targetName, 128),
        targetIdentifier = boundedText(target.identifier or data.targetIdentifier, 128),
        account = boundedText(data.account, 48),
        itemName = boundedText(data.itemName, 96),
        amount = finiteDecimal(data.amount),
        delta = finiteDecimal(data.delta),
        balanceBefore = finiteDecimal(data.balanceBefore),
        balanceAfter = finiteDecimal(data.balanceAfter),
        coordinates = data.coordinates and safeJson(data.coordinates) or nil,
        context = context ~= nil and safeJson(context) or nil,
        rawPayload = safeJson(data),
        routeKey = routeKey,
        discordStatus = discordStatus,
        discordAttempts = 0,
        discordError = nil
    }
end

local function buildGenericRecord(data, eventId, callerResource, routeKey)
    local record = buildAuditRecord({
        category = data.category or 'discord',
        action = data.action or data.title or 'log',
        status = data.status or 'committed',
        sourceResource = data.sourceResource,
        reason = data.reason,
        requestId = data.requestId,
        idempotencyKey = data.idempotencyKey,
        relatedEventId = data.relatedEventId,
        player = data.player,
        playerId = data.playerId,
        playerName = data.playerName,
        identifier = data.identifier,
        license = data.license,
        target = data.target,
        targetId = data.targetId,
        targetName = data.targetName,
        targetIdentifier = data.targetIdentifier,
        account = data.account,
        itemName = data.itemName,
        amount = data.amount,
        delta = data.delta,
        balanceBefore = data.balanceBefore,
        balanceAfter = data.balanceAfter,
        coordinates = data.coordinates,
        context = {
            title = data.title,
            message = data.message,
            fields = data.fields,
            embeds = data.embeds,
            content = data.content,
            username = data.username
        }
    }, eventId, callerResource, routeKey, routeKey and 'queued' or 'disabled')

    record.rawPayload = safeJson(data)
    return record
end

local function formatAmount(value)
    local amount = tonumber(value)

    if not amount then
        return 'N/A'
    end

    if amount == math.floor(amount) then
        return tostring(math.floor(amount))
    end

    return ('%.2f'):format(amount)
end

local function buildAuditEmbed(data, eventId, callerResource)
    local player = type(data.player) == 'table' and data.player or {}
    local target = type(data.target) == 'table' and data.target or {}
    local fields = {
        {
            name = 'Transaction ID',
            value = eventId,
            inline = false
        },
        {
            name = 'Resource quan sát',
            value = tostring(data.sourceResource or data.originResource or callerResource or 'server'),
            inline = true
        },
        {
            name = 'Cầu nối',
            value = tostring(callerResource or 'server'),
            inline = true
        },
        {
            name = 'Trạng thái',
            value = tostring(data.status or 'committed'),
            inline = true
        }
    }

    if data.reason then
        fields[#fields + 1] = {
            name = 'Lý do',
            value = tostring(data.reason),
            inline = false
        }
    end

    if player.name or data.playerName then
        fields[#fields + 1] = {
            name = 'Người chơi',
            value = ('%s (ID: %s)'):format(tostring(player.name or data.playerName), tostring(player.id or data.playerId or 'N/A')),
            inline = false
        }
    end

    if player.identifier or data.identifier then
        fields[#fields + 1] = {
            name = 'Character',
            value = tostring(player.identifier or data.identifier),
            inline = false
        }
    end

    if target.name or data.targetName then
        fields[#fields + 1] = {
            name = 'Đối tượng liên quan',
            value = ('%s (ID: %s)'):format(tostring(target.name or data.targetName), tostring(target.id or data.targetId or 'N/A')),
            inline = false
        }
    end

    if data.account then
        fields[#fields + 1] = {
            name = 'Tài khoản',
            value = tostring(data.account),
            inline = true
        }
    end

    if data.itemName then
        fields[#fields + 1] = {
            name = 'Vật phẩm',
            value = tostring(data.itemName),
            inline = true
        }
    end

    if data.amount ~= nil or data.delta ~= nil then
        fields[#fields + 1] = {
            name = 'Thay đổi',
            value = formatAmount(data.delta ~= nil and data.delta or data.amount),
            inline = true
        }
    end

    if data.balanceBefore ~= nil then
        fields[#fields + 1] = {
            name = 'Trước',
            value = formatAmount(data.balanceBefore),
            inline = true
        }
    end

    if data.balanceAfter ~= nil then
        fields[#fields + 1] = {
            name = 'Sau',
            value = formatAmount(data.balanceAfter),
            inline = true
        }
    end

    if data.requestId or data.idempotencyKey then
        fields[#fields + 1] = {
            name = 'Request ID',
            value = tostring(data.requestId or data.idempotencyKey),
            inline = false
        }
    end

    local action = string.upper(tostring(data.action or 'AUDIT'))
    local category = string.upper(tostring(data.category or 'GENERAL'))
    local occurredAtMs = math.floor(finiteDecimal(data.occurredAtMs) or (wallClockOffset + getServerTick()))

    return {
        title = data.title or ('%s • %s'):format(category, action),
        description = data.message,
        color = tonumber(data.color) or ((data.status == 'rejected' or data.status == 'failed') and 15158332 or 3066993),
        fields = fields,
        footer = {
            text = ('%s.%03d'):format(os.date('%d/%m/%Y %H:%M:%S', math.floor(occurredAtMs / 1000)), occurredAtMs % 1000)
        }
    }
end

local function makeParts(data, embeds, eventId, routeKey)
    if not routeKey then
        return {}
    end

    local normalized = normalizeEmbeds(embeds, eventId)
    local contentParts = splitText(data.content or '', 1800)
    local total = math.max(#normalized, #contentParts)
    local parts = {}

    for index = 1, total do
        local payload = {
            username = boundedText(data.username or Config.DefaultName, 80),
            avatar_url = boundedText(data.avatar or data.avatar_url or Config.DefaultAvatar, 2048),
            content = contentParts[index],
            embed = normalized[index],
            allowed_mentions = data.allowed_mentions or {
                parse = {}
            }
        }

        parts[index] = {
            eventId = eventId,
            routeKey = routeKey,
            partIndex = index,
            partTotal = total,
            attempts = 0,
            isolate = false,
            payload = payload
        }
    end

    return parts
end

local function queuePersistence(record, parts)
    enqueue(persistenceQueue, {
        record = record,
        parts = parts
    })
end

local function partKey(entry)
    return ('%s:%s'):format(entry.eventId, entry.partIndex)
end

local function enqueueWebhookPart(entry)
    local key = partKey(entry)
    local finalizedUntil = finalizedParts[key]

    if finalizedUntil and finalizedUntil > getServerTick() then
        return
    end

    finalizedParts[key] = nil

    if queuedParts[key] then
        return
    end

    queuedParts[key] = true
    enqueue(getWebhookQueue(entry.routeKey), entry)
end

local auditColumns = {
    'event_id',
    'occurred_at',
    'occurred_at_ms',
    'server_tick',
    'category',
    'action',
    'status',
    'caller_resource',
    'origin_resource',
    'reason',
    'request_id',
    'idempotency_key',
    'related_event_id',
    'player_id',
    'player_name',
    'identifier',
    'license',
    'target_id',
    'target_name',
    'target_identifier',
    'account',
    'item_name',
    'amount',
    'delta',
    'balance_before',
    'balance_after',
    'coordinates',
    'context',
    'raw_payload',
    'route_key',
    'discord_status',
    'discord_attempts',
    'discord_error'
}

local function appendAuditValues(parameters, record, offset)
    local values = {
        record.eventId,
        record.occurredAt,
        record.occurredAtMs,
        record.serverTick,
        record.category,
        record.action,
        record.status,
        record.callerResource,
        record.originResource,
        record.reason,
        record.requestId,
        record.idempotencyKey,
        record.relatedEventId,
        record.playerId,
        record.playerName,
        record.identifier,
        record.license,
        record.targetId,
        record.targetName,
        record.targetIdentifier,
        record.account,
        record.itemName,
        record.amount,
        record.delta,
        record.balanceBefore,
        record.balanceAfter,
        record.coordinates,
        record.context,
        record.rawPayload,
        record.routeKey,
        record.discordStatus,
        record.discordAttempts,
        record.discordError
    }

    offset = offset or 0

    for index = 1, #auditColumns do
        -- Keep the numeric position aligned with the SQL placeholder. Missing
        -- numeric keys are converted to SQL NULL by oxmysql. Do not use
        -- json.null here: on the CFX Lua runtime it is a function reference,
        -- which oxmysql serializes as the function body instead of NULL.
        parameters[offset + index] = values[index]
    end

    return offset + #auditColumns
end

local function buildPersistenceQueries(batch)
    local auditRows = {}
    -- The string marker keeps this sparse Lua table encoded as an object.
    -- oxmysql then rebuilds the positional array and fills absent keys with
    -- JavaScript null, including trailing NULL columns.
    local auditParameters = { __legacySparseParameters = true }
    local outboxRows = {}
    local outboxParameters = {}
    local auditPlaceholder = '(' .. string.rep('?,', #auditColumns - 1) .. '?)'
    local auditParameterCount = 0

    for index = 1, #batch do
        local event = batch[index]

        if event.record then
            auditRows[#auditRows + 1] = auditPlaceholder
            auditParameterCount = appendAuditValues(auditParameters, event.record, auditParameterCount)
        end

        for part = 1, #event.parts do
            local entry = event.parts[part]
            local prefix = #outboxRows == 0 and 'SELECT ? AS `event_id`, ? AS `route_key`, ? AS `part_index`, ? AS `part_total`, ? AS `payload`, ? AS `state`, ? AS `require_audit`'
                or 'UNION ALL SELECT ?,?,?,?,?,?,?'
            outboxRows[#outboxRows + 1] = prefix
            outboxParameters[#outboxParameters + 1] = entry.eventId
            outboxParameters[#outboxParameters + 1] = entry.routeKey
            outboxParameters[#outboxParameters + 1] = entry.partIndex
            outboxParameters[#outboxParameters + 1] = entry.partTotal
            outboxParameters[#outboxParameters + 1] = safeJson(entry.payload)
            outboxParameters[#outboxParameters + 1] = 'pending'
            outboxParameters[#outboxParameters + 1] = event.record and 1 or 0
        end
    end

    local queries = {}

    if #auditRows > 0 then
        queries[#queries + 1] = {
            query = ('INSERT INTO `legacy_audit_events` (`%s`) VALUES %s ON DUPLICATE KEY UPDATE `event_id` = `legacy_audit_events`.`event_id`'):format(table.concat(auditColumns, '`,`'), table.concat(auditRows, ',')),
            values = auditParameters
        }
    end

    if #outboxRows > 0 then
        queries[#queries + 1] = {
            query = ([[
                INSERT INTO `legacy_audit_outbox`
                    (`event_id`,`route_key`,`part_index`,`part_total`,`payload`,`state`,`next_attempt_at`)
                SELECT
                    `source`.`event_id`,
                    `source`.`route_key`,
                    `source`.`part_index`,
                    `source`.`part_total`,
                    `source`.`payload`,
                    `source`.`state`,
                    CURRENT_TIMESTAMP(3)
                FROM (%s) AS `source`
                LEFT JOIN `legacy_audit_events` AS `audit` ON `audit`.`event_id` = `source`.`event_id`
                WHERE `source`.`require_audit` = 0 OR `audit`.`event_id` IS NOT NULL
                ON DUPLICATE KEY UPDATE `event_id` = VALUES(`event_id`)
            ]]):format(table.concat(outboxRows, ' ')),
            values = outboxParameters
        }
    end

    return queries
end

local function persistenceEventSize(event)
    local size = event.record and #(event.record.rawPayload or '') or 0

    for index = 1, #event.parts do
        size = size + #safeJson(event.parts[index].payload)
    end

    return size
end

local function takePersistenceBatch()
    local batch = {}
    local size = 0
    local maximumCount = math.max(1, Config.DatabaseBatchSize)
    local maximumBytes = math.max(65536, Config.DatabaseBatchBytes)

    while #batch < maximumCount and queueSize(persistenceQueue) > 0 do
        local dequeued = dequeue(persistenceQueue, 1)
        local event = dequeued[1]
        local eventSize = persistenceEventSize(event)

        if #batch > 0 and size + eventSize > maximumBytes then
            requeueFront(persistenceQueue, { event })
            break
        end

        batch[#batch + 1] = event
        size = size + eventSize
    end

    return batch
end

local function enqueuePersisted(batch)
    local routesToLoad = {}

    for index = 1, #batch do
        local event = batch[index]
        local loadFromDatabase = event.record and event.record.idempotencyKey ~= nil

        for part = 1, #event.parts do
            local entry = event.parts[part]

            if loadFromDatabase then
                routesToLoad[entry.routeKey] = true
            else
                enqueueWebhookPart(entry)
            end
        end
    end

    for routeKey in pairs(routesToLoad) do
        local pendingRoute = routeKey

        SetTimeout(250, function()
            loadPendingRoute(pendingRoute)
        end)
    end
end

local function persistBatch(batch)
    local queries = buildPersistenceQueries(batch)
    local success, committed = pcall(function()
        return MySQL.transaction.await(queries)
    end)

    if success and committed then
        enqueuePersisted(batch)
        return true
    end

    return false, boundedText(committed or 'transaction_failed', 255)
end

local function databaseHealthy()
    local success, result = pcall(function()
        return MySQL.scalar.await('SELECT 1')
    end)

    return success and tonumber(result) == 1
end

local function quarantineEvent(event, errorText)
    local failurePayload = safeJson({
        record = event.record,
        parts = event.parts
    })

    pcall(function()
        MySQL.query.await([[
            INSERT INTO `legacy_audit_ingest_failures`
                (`event_id`,`failure`,`payload`,`attempts`,`next_attempt_at`)
            VALUES (?, ?, ?, 1, DATE_ADD(CURRENT_TIMESTAMP(3), INTERVAL ? MICROSECOND))
            ON DUPLICATE KEY UPDATE
                `failure` = VALUES(`failure`),
                `payload` = VALUES(`payload`),
                `attempts` = `attempts` + 1,
                `next_attempt_at` = VALUES(`next_attempt_at`)
        ]], {
            event.record and event.record.eventId or event.parts[1] and event.parts[1].eventId or nextEventId(),
            boundedText(errorText, 255),
            failurePayload,
            math.max(1, Config.RetryBase) * 1000
        })
    end)

    enqueue(quarantineQueue, {
        event = event,
        attempts = 1,
        nextAttempt = getServerTick() + Config.RetryBase
    })
end

local function persistIsolated(batch)
    local persisted, errorText = persistBatch(batch)

    if persisted then
        return
    end

    if #batch == 1 then
        quarantineEvent(batch[1], errorText)
        return
    end

    local middle = math.floor(#batch / 2)
    local left = {}
    local right = {}

    for index = 1, #batch do
        if index <= middle then
            left[#left + 1] = batch[index]
        else
            right[#right + 1] = batch[index]
        end
    end

    persistIsolated(left)
    persistIsolated(right)
end

local function flushPersistence()
    if not databaseReady or databaseBusy or queueSize(persistenceQueue) == 0 then
        return
    end

    if getServerTick() < databasePausedUntil then
        return
    end

    local batch = takePersistenceBatch()
    databaseBusy = true

    CreateThread(function()
        local persisted, errorText = persistBatch(batch)

        if not persisted then
            if databaseHealthy() then
                if #batch == 1 then
                    quarantineEvent(batch[1], errorText)
                else
                    local middle = math.floor(#batch / 2)
                    local left = {}
                    local right = {}

                    for index = 1, #batch do
                        if index <= middle then
                            left[#left + 1] = batch[index]
                        else
                            right[#right + 1] = batch[index]
                        end
                    end

                    persistIsolated(left)
                    persistIsolated(right)
                end
            else
                requeueFront(persistenceQueue, batch)
                databasePausedUntil = getServerTick() + Config.RetryBase
            end
        end

        compactQueue(persistenceQueue)
        databaseBusy = false
    end)
end

local function flushQuarantine()
    if not databaseReady or databaseBusy or queueSize(quarantineQueue) == 0 then
        return
    end

    local entry
    local available = queueSize(quarantineQueue)
    local now = getServerTick()

    for _ = 1, available do
        local candidate = dequeue(quarantineQueue, 1)[1]

        if not entry and candidate.nextAttempt <= now then
            entry = candidate
        else
            enqueue(quarantineQueue, candidate)
        end
    end

    if not entry then
        return
    end

    databaseBusy = true

    CreateThread(function()
        local persisted = persistBatch({ entry.event })

        if persisted then
            local eventId = entry.event.record and entry.event.record.eventId
                or entry.event.parts[1] and entry.event.parts[1].eventId

            if eventId then
                pcall(function()
                    MySQL.update.await('DELETE FROM `legacy_audit_ingest_failures` WHERE `event_id` = ?', { eventId })
                end)
            end
        else
            entry.attempts = entry.attempts + 1
            local delay = math.min(Config.RetryMaximum, Config.RetryBase * (2 ^ math.min(8, entry.attempts - 1)))
            entry.nextAttempt = getServerTick() + delay
            enqueue(quarantineQueue, entry)
        end

        compactQueue(quarantineQueue)
        databaseBusy = false
    end)
end

local function buildOutboxTransition(group)
    local entries = group.entries
    local state = group.state
    local clauses = {}
    local parameters = { __legacySparseParameters = true }
    parameters[1] = state
    parameters[2] = tonumber(group.statusCode)
    parameters[3] = boundedText(group.errorText, 255)
    local parameterCount = 3

    for index = 1, #entries do
        local entry = entries[index]
        clauses[#clauses + 1] = '(`event_id` = ? AND `part_index` = ?)'
        parameters[parameterCount + 1] = entry.eventId
        parameters[parameterCount + 2] = entry.partIndex
        parameterCount = parameterCount + 2
    end

    local nextAttempt

    if group.retryDelay then
        nextAttempt = ('DATE_ADD(CURRENT_TIMESTAMP(3), INTERVAL %d MICROSECOND)'):format(math.max(1, group.retryDelay) * 1000)
    else
        nextAttempt = '`next_attempt_at`'
    end

    local deliveredAt = state == 'delivered' and 'CURRENT_TIMESTAMP(3)' or '`delivered_at`'
    local attemptIncrement = group.incrementAttempt == false and 0 or 1
    local queries = {
        {
            query = ('UPDATE `legacy_audit_outbox` SET `state` = ?, `attempts` = `attempts` + %d, `http_status` = ?, `last_error` = ?, `next_attempt_at` = %s, `delivered_at` = %s WHERE %s'):format(attemptIncrement, nextAttempt, deliveredAt, table.concat(clauses, ' OR ')),
            values = parameters
        }
    }
    local eventIds = {}
    local seen = {}

    for index = 1, #entries do
        local eventId = entries[index].eventId

        if not seen[eventId] then
            seen[eventId] = true
            eventIds[#eventIds + 1] = eventId
        end
    end

    local placeholders = string.rep('?,', #eventIds - 1) .. '?'

    if state == 'delivered' then
        queries[#queries + 1] = {
            query = ('UPDATE `legacy_audit_events` AS `event` SET `discord_status` = \'delivered\', `discord_attempts` = `discord_attempts` + %d, `delivered_at` = CURRENT_TIMESTAMP(3), `discord_error` = NULL WHERE `event_id` IN (%s) AND NOT EXISTS (SELECT 1 FROM `legacy_audit_outbox` AS `outbox` WHERE `outbox`.`event_id` = `event`.`event_id` AND `outbox`.`state` <> \'delivered\')'):format(attemptIncrement, placeholders),
            values = eventIds
        }
    else
        local auditParameters = { __legacySparseParameters = true }
        auditParameters[1] = state == 'dead' and 'failed' or 'retrying'
        auditParameters[2] = boundedText(group.errorText, 255)

        for index = 1, #eventIds do
            auditParameters[index + 2] = eventIds[index]
        end

        queries[#queries + 1] = {
            query = ('UPDATE `legacy_audit_events` SET `discord_status` = ?, `discord_attempts` = `discord_attempts` + %d, `discord_error` = ? WHERE `event_id` IN (%s)'):format(attemptIncrement, placeholders),
            values = auditParameters
        }
    end

    return queries
end

local function finishWebhookRequest(routeKey, queue)
    queue.inFlight = false

    if queueSize(queue) == 0 then
        webhookQueues[routeKey] = nil
        return
    end

    compactQueue(queue)
end

local function dequeueWebhookBatch(queue)
    local entries = {}
    local size = 0
    local maximum = math.max(1, math.min(10, Config.DiscordBatchSize))
    local first

    while #entries < maximum and queue.head <= queue.tail do
        local entry = queue.items[queue.head]
        local payload = entry.payload
        local entrySize = #safeJson(payload)

        if first then
            if entry.isolate
                or first.isolate
                or payload.username ~= first.payload.username
                or payload.avatar_url ~= first.payload.avatar_url
                or payload.content ~= first.payload.content
                or size + entrySize > Config.DiscordPayloadLimit then
                break
            end
        end

        queue.items[queue.head] = nil
        queue.head = queue.head + 1
        entries[#entries + 1] = entry
        size = size + entrySize
        first = first or entry
    end

    return entries
end

local function markEntriesReleased(entries)
    for index = 1, #entries do
        local key = partKey(entries[index])
        queuedParts[key] = nil
        finalizedParts[key] = getServerTick() + 30000
    end
end

local function transitionWebhook(routeKey, queue, groups)
    local queries = {}

    for index = 1, #groups do
        local groupQueries = buildOutboxTransition(groups[index])

        for queryIndex = 1, #groupQueries do
            queries[#queries + 1] = groupQueries[queryIndex]
        end
    end

    CreateThread(function()
        local attempt = 0

        while true do
            local success, committed = pcall(function()
                return MySQL.transaction.await(queries)
            end)

            if success and committed then
                local pauseDuration = 0

                for index = #groups, 1, -1 do
                    local group = groups[index]

                    if group.requeue then
                        requeueFront(queue, group.entries)
                    else
                        markEntriesReleased(group.entries)
                    end

                    pauseDuration = math.max(pauseDuration, group.retryDelay or 0)
                end

                if pauseDuration > 0 then
                    pauseRoute(routeKey, pauseDuration)
                end

                finishWebhookRequest(routeKey, queue)
                return
            end

            attempt = attempt + 1
            Wait(math.min(Config.RetryMaximum, Config.RetryBase * (2 ^ math.min(8, attempt - 1))))
        end
    end)
end

local function retryEntries(entries, statusCode, errorText, retryDelay)
    local retry = {}
    local dead = {}
    local groups = {}
    local maximumAttempts = math.max(1, Config.MaxDeliveryAttempts)

    for index = 1, #entries do
        local entry = entries[index]
        entry.attempts = entry.attempts + 1

        if entry.attempts >= maximumAttempts then
            dead[#dead + 1] = entry
        else
            retry[#retry + 1] = entry
        end
    end

    if #retry > 0 then
        groups[#groups + 1] = {
            entries = retry,
            state = 'pending',
            statusCode = statusCode,
            errorText = errorText,
            retryDelay = retryDelay,
            requeue = true
        }
    end

    if #dead > 0 then
        groups[#groups + 1] = {
            entries = dead,
            state = 'dead',
            statusCode = statusCode,
            errorText = errorText
        }
    end

    return groups
end

local function processWebhook(routeKey, queue)
    if queue.inFlight or pausedRoutes[routeKey] then
        return
    end

    local webhook = routes[routeKey]

    if not webhook then
        return
    end

    local batch = dequeueWebhookBatch(queue)

    if #batch == 0 then
        webhookQueues[routeKey] = nil
        return
    end

    local embeds = {}

    for index = 1, #batch do
        if batch[index].payload.embed then
            embeds[#embeds + 1] = batch[index].payload.embed
        end
    end

    local payload = {
        username = batch[1].payload.username,
        content = batch[1].payload.content,
        allowed_mentions = batch[1].payload.allowed_mentions or {
            parse = {}
        }
    }

    if batch[1].payload.avatar_url and batch[1].payload.avatar_url ~= '' then
        payload.avatar_url = batch[1].payload.avatar_url
    end

    if #embeds > 0 then
        payload.embeds = embeds
    end

    queue.inFlight = true

    PerformHttpRequest(webhook, function(statusCode, body, headers)
        local code = tonumber(statusCode) or 0
        local groups

        if code >= 200 and code < 300 then
            groups = {
                {
                    entries = batch,
                    state = 'delivered',
                    statusCode = code
                }
            }
        elseif code == 429 then
            local retryDelay = parseRetryAfter(headers, body)
            groups = {
                {
                    entries = batch,
                    state = 'pending',
                    statusCode = code,
                    errorText = 'rate_limited',
                    retryDelay = retryDelay,
                    incrementAttempt = false,
                    requeue = true
                }
            }
        elseif code == 400 and #batch > 1 then
            for index = 1, #batch do
                batch[index].isolate = true
            end

            groups = {
                {
                    entries = batch,
                    state = 'pending',
                    statusCode = code,
                    errorText = 'payload_rejected',
                    retryDelay = Config.RetryBase,
                    incrementAttempt = false,
                    requeue = true
                }
            }
        elseif code == 401 or code == 403 or code == 404 then
            groups = retryEntries(batch, code, 'route_unavailable', Config.RetryMaximum)
        elseif code == 0 or code >= 500 then
            local highestAttempt = 0

            for index = 1, #batch do
                highestAttempt = math.max(highestAttempt, batch[index].attempts)
            end

            local retryDelay = math.min(Config.RetryMaximum, Config.RetryBase * (2 ^ math.min(8, highestAttempt)))
            groups = retryEntries(batch, code, code == 0 and 'network_error' or 'server_error', retryDelay)
        else
            groups = {
                {
                    entries = batch,
                    state = 'dead',
                    statusCode = code,
                    errorText = 'delivery_rejected'
                }
            }
        end

        transitionWebhook(routeKey, queue, groups)
    end, 'POST', safeJson(payload), {
        ['Content-Type'] = 'application/json'
    })
end

loadPendingRoute = function(routeKey)
    if not databaseReady or not routes[routeKey] or loadingRoutes[routeKey] then
        return
    end

    loadingRoutes[routeKey] = true

    CreateThread(function()
        local success, rows = pcall(function()
            return MySQL.query.await([[
                SELECT `event_id`, `route_key`, `part_index`, `part_total`, `payload`, `attempts`
                FROM `legacy_audit_outbox`
                WHERE `route_key` = ? AND `state` = 'pending' AND `next_attempt_at` <= CURRENT_TIMESTAMP(3)
                ORDER BY `next_attempt_at`, `id`
                LIMIT 500
            ]], { routeKey })
        end)

        loadingRoutes[routeKey] = nil

        if not success or type(rows) ~= 'table' then
            return
        end

        for index = 1, #rows do
            local row = rows[index]
            local success, payload = pcall(json.decode, row.payload)

            if success and type(payload) == 'table' then
                enqueueWebhookPart({
                    eventId = row.event_id,
                    routeKey = row.route_key,
                    partIndex = tonumber(row.part_index) or 1,
                payload = payload
                })
            end
        end
    end)
end

local adminSpawnedItems = {}

local function recordAdminSpawn(key)
    adminSpawnedItems[key] = os.time()
end

local function isRecentAdminSpawn(key)
    local timestamp = adminSpawnedItems[key]
    if not timestamp then
        return false
    end

    local window = Config.AdminItemSmuggleWindowSeconds or 600
    if os.time() - timestamp <= window then
        return true
    end

    adminSpawnedItems[key] = nil
    return false
end

local function isAbnormalOrTransaction(data, embeds)
    local alertWebhook = Config.AlertWebhook
    if not alertWebhook or alertWebhook == '' then
        return false
    end

    local category = data.category and string.lower(tostring(data.category)) or ''
    local action = data.action and string.lower(tostring(data.action)) or ''
    local account = data.account and string.lower(tostring(data.account)) or ''
    local status = data.status and string.lower(tostring(data.status)) or ''
    local itemName = data.itemName and tostring(data.itemName) or nil
    local amount = math.abs(tonumber(data.amount) or tonumber(data.delta) or tonumber(data.count) or 0)

    local player = type(data.player) == 'table' and data.player or {}
    local target = type(data.target) == 'table' and data.target or {}
    local playerKey = tostring(player.identifier or player.license or player.id or player.name or data.sourceResource or 'unknown')

    local textBuffer = {}
    if data.title then table.insert(textBuffer, tostring(data.title)) end
    if data.message then table.insert(textBuffer, tostring(data.message)) end
    if data.reason then table.insert(textBuffer, tostring(data.reason)) end
    if data.content then table.insert(textBuffer, tostring(data.content)) end
    if category ~= '' then table.insert(textBuffer, category) end
    if action ~= '' then table.insert(textBuffer, action) end

    if type(data.fields) == 'table' then
        for _, field in ipairs(data.fields) do
            if type(field) == 'table' then
                if field.name then table.insert(textBuffer, tostring(field.name)) end
                if field.value then table.insert(textBuffer, tostring(field.value)) end
            end
        end
    end

    if type(embeds) == 'table' then
        for _, embed in ipairs(embeds) do
            if type(embed) == 'table' then
                if embed.title then table.insert(textBuffer, tostring(embed.title)) end
                if embed.description then table.insert(textBuffer, tostring(embed.description)) end
                if type(embed.fields) == 'table' then
                    for _, field in ipairs(embed.fields) do
                        if type(field) == 'table' then
                            if field.name then table.insert(textBuffer, tostring(field.name)) end
                            if field.value then table.insert(textBuffer, tostring(field.value)) end
                        end
                    end
                end
            end
        end
    end

    local combinedText = string.lower(table.concat(textBuffer, ' '))

    local isMoneyLog = (category == 'money' or category == 'cash' or category == 'bank' or category == 'banking' 
        or category == 'black_money' or category == 'economy'
        or account == 'money' or account == 'cash' or account == 'bank' or account == 'banking' 
        or account == 'black_money' or account == 'black' or account == 'savings' or account == 'crypto')

    if not isMoneyLog then
        local moneyKeywords = { 'money', 'cash', 'black_money', 'tiền', 'tiền mặt', 'tiền bẩn', 'addmoney', 'givemoney', 'bank', 'banking', 'ngân hàng', 'chuyển khoản', 'rút tiền', 'gửi tiền' }
        for _, kw in ipairs(moneyKeywords) do
            if string.find(combinedText, kw, 1, true) then
                isMoneyLog = true
                break
            end
        end
    end

    if isMoneyLog then
        if amount >= (Config.LargeMoneyThreshold or 500000) then
            return true, true
        end
        return false, false
    end

    local isScriptAddItem = string.find(combinedText, 'inventory.additem', 1, true) ~= nil

    local isAdminGive = not isScriptAddItem and (category == 'admin'
        or string.find(combinedText, 'admincore', 1, true)
        or string.find(combinedText, 'txadmin', 1, true)
        or string.find(combinedText, '/giveitem', 1, true)
        or string.find(combinedText, '/additem', 1, true)
        or string.find(combinedText, 'command: giveitem', 1, true)
        or string.find(combinedText, 'command: additem', 1, true)
        or string.find(combinedText, 'tạo vật phẩm admin', 1, true)
        or string.find(combinedText, 'cho vật phẩm admin', 1, true))

    if isAdminGive then
        recordAdminSpawn(playerKey)
        if target.id or target.name or target.identifier then
            recordAdminSpawn(tostring(target.identifier or target.id or target.name))
        end
        return true, false
    end

    local isTransferAction = (string.find(action, 'give', 1, true)
        or string.find(action, 'transfer', 1, true)
        or string.find(action, 'trade', 1, true)
        or string.find(action, 'drop', 1, true)
        or string.find(combinedText, 'giveitem', 1, true)
        or string.find(combinedText, 'chuyển đồ', 1, true)
        or string.find(combinedText, 'cho đồ', 1, true)
        or string.find(combinedText, 'đóng hòm', 1, true))

    if isTransferAction and isRecentAdminSpawn(playerKey) then
        return true, false
    end

    local isAdminAddCar = (string.find(combinedText, 'addcar', 1, true)
        or string.find(combinedText, 'givecar', 1, true)
        or string.find(combinedText, 'admincar', 1, true)
        or string.find(combinedText, 'garageadmin', 1, true)
        or string.find(combinedText, 'garage_admin', 1, true)
        or string.find(combinedText, 'garage admin', 1, true)
        or string.find(combinedText, 'admin garage', 1, true)
        or string.find(combinedText, 'cấp xe', 1, true)
        or string.find(combinedText, 'thêm xe', 1, true)
        or string.find(combinedText, 'tạo xe vào garage', 1, true))

    if isAdminAddCar then
        return true, false
    end

    if status == 'flagged' or status == 'suspicious' or status == 'abnormal' then
        if string.find(combinedText, 'dupe', 1, true) or string.find(combinedText, 'exploit', 1, true) then
            return true, false
        end
    end

    return false, false
end

local function submit(data, rawEmbeds, audit)
    if type(data) ~= 'table' then
        return false
    end

    local callerResource = GetInvokingResource() or GetCurrentResourceName()
    local fallback = audit and Config.AuditWebhook or Config.DefaultWebhook
    local webhook = resolveWebhook(data, fallback)
    local routeKey = webhook and registerRoute(webhook) or nil
    local invalidWebhook = webhook ~= nil and routeKey == nil

    local eventId = nextEventId()
    local embeds = rawEmbeds

    if audit then
        local _, occurredAtMs = normalizeOccurredAt(data.occurredAtMs, wallClockOffset + getServerTick())
        data.occurredAtMs = occurredAtMs
        embeds = { buildAuditEmbed(data, eventId, callerResource) }
    elseif not embeds then
        embeds = {
            {
                title = type(data.title) == 'string' and data.title or 'Discord Log',
                description = type(data.message) == 'string' and data.message ~= '' and data.message or nil,
                color = type(data.color) == 'number' and math.floor(data.color) or Config.DefaultColor,
                fields = data.fields,
                thumbnail = data.image and { url = data.image } or data.thumbnail,
                author = data.author,
                timestamp = data.timestamp,
                footer = {
                    text = type(data.footer) == 'string' and data.footer or os.date('%H:%M:%S - %d/%m/%Y'),
                    icon_url = data.footerIcon
                }
            }
        }
    end

    local discordEnabled = not invalidWebhook and routeKey and data.discord ~= false and (not audit or Config.AuditDiscord)
    local parts = discordEnabled and makeParts(data, embeds, eventId, routeKey) or {}
    local record

    if audit then
        record = buildAuditRecord(data, eventId, callerResource, routeKey, invalidWebhook and 'invalid' or discordEnabled and 'queued' or 'disabled')
    elseif Config.StoreDiscordLogs then
        record = buildGenericRecord(data, eventId, callerResource, routeKey)
    end

    if record and invalidWebhook then
        record.discordStatus = 'invalid'
        record.discordError = 'invalid_webhook'
    elseif record and not discordEnabled then
        record.discordStatus = 'disabled'
    end

    if not record and #parts == 0 then
        return false, eventId
    end

    queuePersistence(record, parts)
    SetTimeout(0, flushPersistence)

    local isAbnormal, shouldPingEveryone = isAbnormalOrTransaction(data, embeds)

    if not data._isAlertExtra and isAbnormal then
        local alertData = {}
        for k, v in pairs(data) do
            alertData[k] = v
        end
        alertData._isAlertExtra = true
        alertData.webhook = Config.AlertWebhook
        alertData.content = shouldPingEveryone and '@everyone' or nil
        alertData.allowed_mentions = {
            parse = shouldPingEveryone and { 'everyone' } or {}
        }
        submit(alertData, embeds, false)
    end

    return audit or not invalidWebhook, eventId
end

local function SendDiscordLog(data)
    return submit(data, nil, false)
end

local function SendDiscordEmbeds(data)
    if type(data) ~= 'table' or type(data.embeds) ~= 'table' then
        return false
    end

    return submit(data, data.embeds, false)
end

local function AuditTransaction(data)
    return submit(data, nil, true)
end

local function GetQueueStats()
    local webhookCount = 0
    local webhookEntries = 0

    for _, queue in pairs(webhookQueues) do
        webhookCount = webhookCount + 1
        webhookEntries = webhookEntries + queueSize(queue)
    end

    return {
        databaseReady = databaseReady,
        persistence = queueSize(persistenceQueue),
        quarantine = queueSize(quarantineQueue),
        webhookRoutes = webhookCount,
        webhookEntries = webhookEntries
    }
end

exports('SendDiscordLog', SendDiscordLog)
exports('SendDiscordEmbeds', SendDiscordEmbeds)
exports('AuditTransaction', AuditTransaction)
exports('GetQueueStats', GetQueueStats)
exports('RegisterWebhook', registerRoute)

RegisterNetEvent('nWebhook:server:SendLog', function(data)
    if source ~= 0 then
        if not Config.AllowClientEvents or type(data) ~= 'table' then
            return
        end

        local now = os.time()
        local rate = clientRateLimits[source]

        if not rate or now - rate.startedAt >= 60 then
            rate = {
                startedAt = now,
                count = 0
            }
            clientRateLimits[source] = rate
        end

        if rate.count >= 5 then
            return
        end

        rate.count = rate.count + 1
        data.webhook = nil
        data.sourceResource = 'client'
        data.player = {
            id = source,
            name = GetPlayerName(source),
            license = GetPlayerIdentifierByType(source, 'license')
        }
    end

    SendDiscordLog(data)
end)

AddEventHandler('playerDropped', function()
    clientRateLimits[source] = nil
end)

local function ensureColumn(tableName, columnName, definition)
    local exists = MySQL.scalar.await([[
        SELECT COUNT(*)
        FROM `information_schema`.`COLUMNS`
        WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = ? AND `COLUMN_NAME` = ?
    ]], { tableName, columnName })

    if tonumber(exists) == 0 then
        MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, columnName, definition))
    end
end

local function ensureIndex(tableName, indexName, definition)
    local exists = MySQL.scalar.await([[
        SELECT COUNT(*)
        FROM `information_schema`.`STATISTICS`
        WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = ? AND `INDEX_NAME` = ?
    ]], { tableName, indexName })

    if tonumber(exists) == 0 then
        MySQL.query.await(('ALTER TABLE `%s` ADD %s'):format(tableName, definition))
    end
end

CreateThread(function()
    MySQL.ready.await()

    local ready = false
    local lastSchemaFailurePrint = 0

    while not ready do
        local success = pcall(function()
            MySQL.query.await([[
                CREATE TABLE IF NOT EXISTS `legacy_audit_events` (
                    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                    `event_id` VARCHAR(64) NOT NULL,
                    `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
                    `occurred_at` DATETIME(3) NOT NULL,
                    `occurred_at_ms` BIGINT NOT NULL,
                    `server_tick` BIGINT NOT NULL,
                    `category` VARCHAR(48) NOT NULL,
                    `action` VARCHAR(96) NOT NULL,
                    `status` VARCHAR(32) NOT NULL,
                    `caller_resource` VARCHAR(96) NOT NULL,
                    `origin_resource` VARCHAR(96) NULL,
                    `reason` VARCHAR(255) NULL,
                    `request_id` VARCHAR(128) NULL,
                    `idempotency_key` VARCHAR(128) COLLATE utf8mb4_bin NULL,
                    `related_event_id` VARCHAR(64) NULL,
                    `player_id` INT NULL,
                    `player_name` VARCHAR(128) NULL,
                    `identifier` VARCHAR(128) NULL,
                    `license` VARCHAR(128) NULL,
                    `target_id` INT NULL,
                    `target_name` VARCHAR(128) NULL,
                    `target_identifier` VARCHAR(128) NULL,
                    `account` VARCHAR(48) NULL,
                    `item_name` VARCHAR(96) NULL,
                    `amount` DECIMAL(20,2) NULL,
                    `delta` DECIMAL(20,2) NULL,
                    `balance_before` DECIMAL(20,2) NULL,
                    `balance_after` DECIMAL(20,2) NULL,
                    `coordinates` LONGTEXT NULL,
                    `context` LONGTEXT NULL,
                    `raw_payload` LONGTEXT NULL,
                    `route_key` VARCHAR(64) NULL,
                    `discord_status` VARCHAR(24) NOT NULL DEFAULT 'disabled',
                    `discord_attempts` INT UNSIGNED NOT NULL DEFAULT 0,
                    `discord_error` VARCHAR(255) NULL,
                    `delivered_at` DATETIME(3) NULL,
                    PRIMARY KEY (`id`),
                    UNIQUE KEY `uq_legacy_audit_event_id` (`event_id`),
                    UNIQUE KEY `uq_legacy_audit_idempotency` (`caller_resource`, `idempotency_key`),
                    KEY `idx_legacy_audit_occurred` (`occurred_at`),
                    KEY `idx_legacy_audit_identifier_time` (`identifier`, `created_at`),
                    KEY `idx_legacy_audit_resource_time` (`origin_resource`, `created_at`),
                    KEY `idx_legacy_audit_category_time` (`category`, `created_at`),
                    KEY `idx_legacy_audit_status_time` (`status`, `created_at`),
                    KEY `idx_legacy_audit_request` (`request_id`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]])

            MySQL.query.await([[
                CREATE TABLE IF NOT EXISTS `legacy_audit_outbox` (
                    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                    `event_id` VARCHAR(64) NOT NULL,
                    `route_key` VARCHAR(64) NOT NULL,
                    `part_index` SMALLINT UNSIGNED NOT NULL,
                    `part_total` SMALLINT UNSIGNED NOT NULL,
                    `payload` LONGTEXT NOT NULL,
                    `state` VARCHAR(16) NOT NULL DEFAULT 'pending',
                    `attempts` INT UNSIGNED NOT NULL DEFAULT 0,
                    `next_attempt_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
                    `http_status` SMALLINT NULL,
                    `last_error` VARCHAR(255) NULL,
                    `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
                    `delivered_at` DATETIME(3) NULL,
                    PRIMARY KEY (`id`),
                    UNIQUE KEY `uq_legacy_outbox_part` (`event_id`, `part_index`),
                    KEY `idx_legacy_outbox_pending_v2` (`route_key`, `state`, `next_attempt_at`, `id`),
                    KEY `idx_legacy_outbox_event` (`event_id`),
                    KEY `idx_legacy_outbox_cleanup` (`state`, `delivered_at`, `created_at`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]])

            MySQL.query.await([[
                CREATE TABLE IF NOT EXISTS `legacy_audit_ingest_failures` (
                    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                    `event_id` VARCHAR(64) NOT NULL,
                    `failure` VARCHAR(255) NULL,
                    `payload` LONGTEXT NOT NULL,
                    `attempts` INT UNSIGNED NOT NULL DEFAULT 0,
                    `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
                    `next_attempt_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
                    PRIMARY KEY (`id`),
                    UNIQUE KEY `uq_legacy_ingest_failure_event` (`event_id`),
                    KEY `idx_legacy_ingest_failure_retry` (`next_attempt_at`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]])

            ensureColumn('legacy_audit_events', 'occurred_at', 'DATETIME(3) NULL AFTER `created_at`')
            ensureColumn('legacy_audit_events', 'occurred_at_ms', 'BIGINT NULL AFTER `occurred_at`')
            ensureColumn('legacy_audit_events', 'server_tick', 'BIGINT NULL AFTER `occurred_at_ms`')
            ensureColumn('legacy_audit_events', 'idempotency_key', 'VARCHAR(128) COLLATE utf8mb4_bin NULL AFTER `request_id`')
            ensureColumn('legacy_audit_events', 'raw_payload', 'LONGTEXT NULL AFTER `context`')
            MySQL.update.await([[
                UPDATE `legacy_audit_events`
                SET
                    `occurred_at` = COALESCE(`occurred_at`, `created_at`),
                    `occurred_at_ms` = COALESCE(`occurred_at_ms`, UNIX_TIMESTAMP(`created_at`) * 1000),
                    `server_tick` = COALESCE(`server_tick`, 0)
                WHERE `occurred_at` IS NULL OR `occurred_at_ms` IS NULL OR `server_tick` IS NULL
            ]])
            ensureIndex('legacy_audit_events', 'uq_legacy_audit_idempotency', 'UNIQUE KEY `uq_legacy_audit_idempotency` (`caller_resource`, `idempotency_key`)')
            ensureIndex('legacy_audit_events', 'idx_legacy_audit_occurred', 'KEY `idx_legacy_audit_occurred` (`occurred_at`)')
            ensureIndex('legacy_audit_outbox', 'idx_legacy_outbox_pending_v2', 'KEY `idx_legacy_outbox_pending_v2` (`route_key`, `state`, `next_attempt_at`, `id`)')
            ensureIndex('legacy_audit_outbox', 'idx_legacy_outbox_cleanup', 'KEY `idx_legacy_outbox_cleanup` (`state`, `delivered_at`, `created_at`)')
        end)

        if success then
            ready = true
        else
            local now = os.time()

            if now - lastSchemaFailurePrint >= 60 then
                lastSchemaFailurePrint = now
                print('^1[legacyWebhook] khởi tạo schema audit thất bại; hệ thống sẽ tự thử lại.^0')
            end

            Wait(math.max(1000, Config.RetryBase))
        end
    end

    databaseReady = true

    if Config.DefaultWebhook ~= '' then
        if not registerRoute(Config.DefaultWebhook) then
            print('^1[legacyWebhook] default webhook không hợp lệ; DB audit vẫn hoạt động.^0')
        end
    end

    if Config.AuditWebhook ~= '' then
        if not registerRoute(Config.AuditWebhook) then
            print('^1[legacyWebhook] audit webhook không hợp lệ; DB audit vẫn hoạt động.^0')
        end
    end

    if type(Config.NamedWebhooks) == 'table' then
        for routeName, webhook in pairs(Config.NamedWebhooks) do
            if webhook ~= '' and not registerRoute(webhook) then
                print(('^1[legacyWebhook] named webhook %s không hợp lệ; DB audit vẫn hoạt động.^0'):format(tostring(routeName)))
            end
        end
    end

    if Config.AlertWebhook and Config.AlertWebhook ~= '' then
        if not registerRoute(Config.AlertWebhook) then
            print('^1[legacyWebhook] alert webhook không hợp lệ.^0')
        end
    end

    local failures = MySQL.query.await([[
        SELECT `payload`, `attempts`
        FROM `legacy_audit_ingest_failures`
        ORDER BY `id`
    ]])

    if type(failures) == 'table' then
        for index = 1, #failures do
            local decoded, payload = pcall(json.decode, failures[index].payload)

            if decoded and type(payload) == 'table' and type(payload.parts) == 'table' then
                enqueue(quarantineQueue, {
                    event = {
                        record = payload.record,
                        parts = payload.parts
                    },
                    attempts = tonumber(failures[index].attempts) or 1,
                    nextAttempt = getServerTick() + Config.RetryBase
                })
            end
        end
    end

    print('^2[legacyWebhook] audit database và outbox đã sẵn sàng.^0')
end)

CreateThread(function()
    while true do
        Wait(math.max(50, Config.DatabaseFlushInterval))
        flushQuarantine()
        flushPersistence()
    end
end)

CreateThread(function()
    while true do
        Wait(math.max(100, Config.Interval))

        for routeKey, queue in pairs(webhookQueues) do
            processWebhook(routeKey, queue)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(10000)

        if databaseReady then
            for routeKey in pairs(routes) do
                loadPendingRoute(routeKey)
            end
        end

        local now = getServerTick()

        for key, expiresAt in pairs(finalizedParts) do
            if expiresAt <= now then
                finalizedParts[key] = nil
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(math.max(1000, Config.OutboxCleanupInterval))

        if databaseReady and Config.OutboxRetentionDays > 0 then
            pcall(function()
                MySQL.update.await(([[
                    DELETE FROM `legacy_audit_outbox`
                    WHERE `state` IN ('delivered', 'dead')
                        AND `delivered_at` < DATE_SUB(CURRENT_TIMESTAMP(3), INTERVAL %d DAY)
                    LIMIT %d
                ]]):format(Config.OutboxRetentionDays, math.max(1, Config.OutboxCleanupBatchSize)))

                MySQL.update.await(([[
                    DELETE FROM `legacy_audit_outbox`
                    WHERE `state` IN ('delivered', 'dead')
                        AND `delivered_at` IS NULL
                        AND `created_at` < DATE_SUB(CURRENT_TIMESTAMP(3), INTERVAL %d DAY)
                    LIMIT %d
                ]]):format(Config.OutboxRetentionDays, math.max(1, Config.OutboxCleanupBatchSize)))
            end)
        end
    end
end)
