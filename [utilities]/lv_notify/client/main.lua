local defaults = LVNotify.Defaults or {}
local validPositions =
{
    ['top-right'] = true,
    ['top-left'] = true,
    ['top-center'] = true,
    ['bottom-right'] = true,
    ['bottom-left'] = true,
    ['bottom-center'] = true,
    ['middle-right'] = true,
    ['middle-left'] = true
}

local function trim(value)
    if type(value) ~= 'string' then
        return value
    end
    return value:match('^%s*(.-)%s*$')
end

local function cleanText(value, fallback)
    if value == nil then
        return fallback
    end

    value = tostring(value)
    value = value:gsub('~br~', '\n')
    value = trim(value)

    if value == '' then
        return fallback
    end
    return value
end

local function normalize(input, notifyType, duration, title)
    local payload = {}

    if type(input) == 'table' then
        payload = input
    else
        payload.message = input
        payload.type = notifyType
        payload.duration = duration
        payload.title = title
    end

    local nType = tostring(payload.type or payload.status or defaults.type or 'info'):lower()
    local typeConfig = (LVNotify.Types or {})[nType] or (LVNotify.Types or {}).info or {}
    local length = tonumber(payload.duration or payload.length or payload.time or defaults.duration) or 4200
    local position = tostring(payload.position or defaults.position or 'top-right'):lower()

    if not validPositions[position] then
        position = 'top-right'
    end

    if length < 1200 then
        length = 1200
    elseif length > 30000 then
        length = 30000
    end
    return
    {
        id = ('lv-%s-%s'):format(GetGameTimer(), math.random(1000, 9999)),
        title = cleanText(payload.title, typeConfig.title or defaults.title or 'Lavie'),
        message = cleanText(payload.message or payload.description or payload.text, 'Thông Báo Mới'),
        type = nType,
        duration = length,
        position = position,
        icon = cleanText(payload.icon, typeConfig.icon or defaults.icon),
        accent = payload.accent or typeConfig.accent,
        sound = payload.sound == true or defaults.sound == true,
        maxVisible = tonumber(LVNotify.MaxVisible) or 5
    }
end

local function Notify(input, notifyType, duration, title)
    local payload = normalize(input, notifyType, duration, title)

    SendNUIMessage(
    {
        action = 'notify',
        data = payload
    })
    return payload.id
end

exports('Notify', Notify)
exports('lv_notify', Notify)

RegisterNetEvent('lv_notify:client:notify', Notify)

if LVNotify.DebugCommand then
    RegisterCommand('lvnotify', function(_, args)
        local nType = args[1] or 'info'
        local message = table.concat(args, ' ', 2)

        Notify(
        {
            type = nType,
            title = 'Lavie Notify',
            message = message ~= '' and message or 'Thông Báo Mẫu Từ lv_notify',
            duration = 4500
        })
    end, false)
end

local confirmPromise = nil
local function Confirm(input)
    if confirmPromise then
        return false
    end
    
    confirmPromise = promise.new()
    
    SetNuiFocus(true, true)
    
    local payload = {}
    
    if type(input) == 'table' then
        payload = input
    else
        payload.message = input
    end
    
    SendNUIMessage(
    {
        action = 'confirm',
        data =
        {
            title = payload.title or 'Xác Nhận',
            message = payload.message or 'Bạn Có Đồng Ý Không?',
            yesLabel = payload.yesLabel or payload.confirm or 'Đồng Ý',
            noLabel = payload.noLabel or payload.cancel or 'Từ Chối'
        }
    })
    
    local result = Citizen.Await(confirmPromise)

    confirmPromise = nil

    SetNuiFocus(false, false)
    return result
end

exports('Confirm', Confirm)

RegisterNUICallback('confirm_callback', function(data, cb)
    cb(1)

    if confirmPromise then
        confirmPromise:resolve(data.status)
    end
end)

