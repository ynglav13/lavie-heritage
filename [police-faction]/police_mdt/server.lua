local ESX = exports.es_extended:getSharedObject()
local profileCache = {}
local cadUnits = {}
local codeBooks = { vehicle = {}, penal = {} }

local function loadCodeBook(fileName)
    local value = LoadResourceFile(GetCurrentResourceName(), fileName)
    if type(value) ~= 'string' then return {} end
    local ok, data = pcall(json.decode, value)
    return ok and type(data) == 'table' and data or {}
end

codeBooks.vehicle = loadCodeBook('data/vehiclecode.json')
codeBooks.penal = loadCodeBook('data/penalcode.json')

local function searchCodeBook(book, term, section)
    local query = tostring(term or ''):gsub('^%s*(.-)%s*$', '%1'):sub(1, 120):lower()
    section = tostring(section or '')
    local rows = {}
    for _, entry in ipairs(codeBooks[book] or {}) do
        local searchable = table.concat({ entry.code or '', entry.title or '', entry.category or '', entry.section or '', entry.description or '' }, ' '):lower()
        if (section == '' or entry.section == section) and (query == '' or searchable:find(query, 1, true)) then
            rows[#rows + 1] = entry
            if #rows >= MdtConfig.CodeSearchLimit then break end
        end
    end
    return rows
end

local function codeBookSections(book)
    local sections, seen = {}, {}
    for _, entry in ipairs(codeBooks[book] or {}) do
        local section = entry.section or 'San Andreas Code'
        if not seen[section] then
            seen[section] = true
            sections[#sections + 1] = section
        end
    end
    table.sort(sections)
    return sections
end

local function sendBoloLog(title, message, color)
    if type(MdtConfig.BoloWebhook) ~= 'string' or MdtConfig.BoloWebhook == '' then return false end
    if GetResourceState('legacyWebhook') ~= 'started' then return false end
    return exports.legacyWebhook:SendDiscordLog({
        webhook = MdtConfig.BoloWebhook,
        username = 'MDT',
        title = title,
        message = message,
        color = color,
        footer = os.date('%d/%m/%Y %H:%M:%S')
    })
end

local function isAuthorized(source)
    local state = Player(source).state
    return state and state.factionCategory == 'police'
end

local function isPoliceMember(source)
    local state = Player(source).state
    return state and state.factionCategory == 'police'
end

local function cadUnit(source)
    local unit = cadUnits[source]
    if unit then return unit end
    return { callsign = '', unitType = 'General Patrol', status = 'Available', location = 'Mobile' }
end

local function dutyRoster()
    local grouped = {}
    for _, playerId in ipairs(GetPlayers()) do
        local source = tonumber(playerId)
        if isAuthorized(source) and Player(source).state.factionDuty == true then
            local unit = cadUnit(source)
            if unit.callsign ~= '' then
                local xPlayer = ESX.GetPlayerFromId(source)
                local tag = Player(source).state.factionTag or 'police'
                local agency = tag:lower() == 'lssd' and 'LSSD' or 'LSPD'
                local key = unit.callsign:upper()
                grouped[key] = grouped[key] or { callsign = unit.callsign, unitType = unit.unitType, status = unit.status, location = unit.location, occupants = {}, sources = {} }
                grouped[key].occupants[#grouped[key].occupants + 1] = { name = xPlayer and xPlayer.getName() or GetPlayerName(source), agency = agency }
                grouped[key].sources[#grouped[key].sources + 1] = source
            end
        end
    end
    local roster = {}
    for _, unit in pairs(grouped) do roster[#roster + 1] = unit end
    table.sort(roster, function(a, b) return a.callsign < b.callsign end)
    return roster
end

local function notify(source, message)
    return { ok = false, message = message or 'Bạn không có quyền sử dụng MDT.' }
end

local function cleanPlate(plate)
    return tostring(plate or ''):gsub('^%s*(.-)%s*$', '%1'):upper()
end

local function cleanText(value, maxLength)
    local text = tostring(value or ''):gsub('^%s*(.-)%s*$', '%1')
    return text:sub(1, maxLength)
end

local function idCardNumber(id)
    id = tonumber(id)
    if not id then return nil end
    return ('I%d'):format((id * 135791 + 97531) % 9000000 + 1000000)
end

local function officer(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return nil end
    local state = Player(source).state
    return {
        identifier = xPlayer.identifier,
        name = xPlayer.getName(),
        factionTag = state.factionTag or 'police'
    }
end

local function decodeVehicle(value)
    local decoded = value
    if type(value) == 'string' then
        local ok, result = pcall(json.decode, value)
        decoded = ok and result or nil
    end
    if type(decoded) ~= 'table' then return {} end
    return decoded
end

local function mapVehicle(row)
    local vehicle = decodeVehicle(row.vehicle)
    return {
        plate = cleanPlate(row.plate),
        model = vehicle.model or vehicle.vehicle or 'Unknown',
        stored = tonumber(row.stored) == 1,
        towed = tonumber(row.isTowedOut) == 1,
        garage = row.vehicleGarage,
        impound = row.vehicleImpound
    }
end

local function getProfile(identifier)
    local cached = profileCache[identifier]
    if cached and cached.expiresAt > os.time() then return cached.data end
    local row = MySQL.single.await([[SELECT u.identifier, i.id AS idcard_no, COALESCE(i.firstname, u.firstname) AS firstname,
        COALESCE(i.lastname, u.lastname) AS lastname, COALESCE(i.dob, u.dateofbirth) AS dob,
        COALESCE(i.sex, u.sex) AS sex, COALESCE(i.height, u.height) AS height, i.address,
        i.photo_url, i.driver_license, i.weapon_license, i.status AS idcard_status,
        u.jail_time, u.jail_cell, u.jail_expire_at
        FROM users u LEFT JOIN lv_idcards i ON i.identifier = u.identifier AND i.status = 'approved'
        WHERE u.identifier = ? LIMIT 1]], { identifier })
    if not row then return nil end
    local data = {
        identifier = row.identifier,
        idcardNo = idCardNumber(row.idcard_no),
        name = (row.firstname or 'Unknown') .. ' ' .. (row.lastname or ''),
        firstname = row.firstname or '',
        lastname = row.lastname or '',
        dob = row.dob or '',
        sex = row.sex or '',
        height = row.height or '',
        address = row.address or '',
        photo = row.photo_url or '',
        hasIdCard = row.idcard_status == 'approved',
        driverLicense = row.driver_license or 'NONE',
        weaponLicense = row.weapon_license or 'NONE',
        jailTime = tonumber(row.jail_time) or 0,
        jailCell = tonumber(row.jail_cell) or 1,
        jailExpireAt = tonumber(row.jail_expire_at) or 0
    }
    profileCache[identifier] = { data = data, expiresAt = os.time() + MdtConfig.CacheSeconds }
    return data
end

local function activeBolos(identifier, plate, targetName)
    plate = cleanPlate(plate)
    return MySQL.query.await([[SELECT id, type, target_identifier, plate, title, reason, priority, expires_at, created_at
        FROM police_bolos WHERE status = 'active' AND (expires_at IS NULL OR expires_at > NOW())
        AND ((? <> '' AND target_identifier = ?) OR (? <> '' AND UPPER(TRIM(plate)) = ?) OR (? <> '' AND LOWER(TRIM(target_name)) = LOWER(TRIM(?))))
        ORDER BY FIELD(priority, 'critical', 'high', 'medium', 'low'), created_at DESC]], { identifier or '', identifier or '', plate, plate, targetName or '', targetName or '' }) or {}
end

local function detail(identifier)
    local profile = getProfile(identifier)
    if not profile then return nil end
    local vehicles = MySQL.query.await('SELECT plate, vehicle, stored, isTowedOut, vehicleGarage, vehicleImpound FROM owned_vehicles WHERE owner = ? ORDER BY plate LIMIT ?', { identifier, MdtConfig.DetailVehicleLimit }) or {}
    local tickets = MySQL.query.await([[SELECT id, ticket_no, violation, fine_amount, status, issued_at, due_at, officer_name, faction_tag
        FROM police_tickets WHERE target_identifier = ? ORDER BY issued_at DESC LIMIT 50]], { identifier }) or {}
    local arrests = MySQL.query.await([[SELECT id, officer_name, officer_badge, faction_tag, reason, base_minutes, extra_minutes,
        final_minutes, fine_amount, cell_index, arrested_at FROM police_arrests WHERE target_identifier = ? ORDER BY arrested_at DESC LIMIT 50]], { identifier }) or {}
    local mappedVehicles = {}
    for index, row in ipairs(vehicles) do mappedVehicles[index] = mapVehicle(row) end
    profile.vehicles = mappedVehicles
    profile.tickets = tickets
    profile.arrests = arrests
    profile.bolos = activeBolos(identifier, '', profile.name)
    local vehicleBolos = MySQL.query.await([[SELECT b.id, b.title, b.reason, b.priority, b.plate
        FROM police_bolos b INNER JOIN owned_vehicles ov ON UPPER(TRIM(ov.plate)) = UPPER(TRIM(b.plate))
        WHERE ov.owner = ? AND b.type = 'vehicle' AND b.status = 'active' AND (b.expires_at IS NULL OR b.expires_at > NOW())]], { identifier }) or {}
    for _, bolo in ipairs(vehicleBolos) do profile.bolos[#profile.bolos + 1] = bolo end
    return profile
end

local function ensureTables()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `police_arrests` (`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, `officer_identifier` VARCHAR(80) NOT NULL, `officer_name` VARCHAR(120) NOT NULL, `officer_badge` VARCHAR(32) NULL, `faction_tag` VARCHAR(32) NOT NULL, `target_identifier` VARCHAR(80) NOT NULL, `target_name` VARCHAR(120) NOT NULL, `reason` TEXT NOT NULL, `base_minutes` INT NOT NULL, `extra_minutes` INT NOT NULL DEFAULT 0, `final_minutes` INT NOT NULL, `fine_amount` INT NOT NULL DEFAULT 0, `cell_index` INT NOT NULL DEFAULT 1, `arrested_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (`id`), KEY `idx_police_arrests_target_time` (`target_identifier`, `arrested_at`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `police_bolos` (`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, `type` ENUM('person','vehicle') NOT NULL, `target_identifier` VARCHAR(80) NULL, `target_name` VARCHAR(120) NULL, `plate` VARCHAR(32) NULL, `title` VARCHAR(160) NOT NULL, `reason` TEXT NOT NULL, `priority` ENUM('low','medium','high','critical') NOT NULL DEFAULT 'medium', `status` ENUM('active','resolved','expired','cancelled') NOT NULL DEFAULT 'active', `created_by_identifier` VARCHAR(80) NOT NULL, `created_by_name` VARCHAR(120) NOT NULL, `faction_tag` VARCHAR(32) NOT NULL, `expires_at` DATETIME NULL, `resolved_at` DATETIME NULL, `resolved_by_identifier` VARCHAR(80) NULL, `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (`id`), KEY `idx_police_bolos_active_type` (`status`, `type`, `expires_at`), KEY `idx_police_bolos_identifier` (`target_identifier`, `status`), KEY `idx_police_bolos_plate` (`plate`, `status`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    pcall(function() MySQL.query.await('ALTER TABLE `police_bolos` ADD COLUMN `target_name` VARCHAR(120) NULL AFTER `target_identifier`') end)
end

MySQL.ready(ensureTables)

lib.callback.register('police_mdt:bootstrap', function(source)
    if not isPoliceMember(source) then return notify(source) end
    local user = officer(source)
    return { ok = true, data = { officer = user, onDuty = isAuthorized(source), bolos = isAuthorized(source) and (MySQL.query.await([[SELECT b.id, b.type, b.target_name, b.plate, b.title, b.reason, b.priority, b.status, b.created_by_name, b.expires_at, b.created_at, LPAD(c.id, 8, '0') AS idcard_no FROM police_bolos b LEFT JOIN lv_idcards c ON c.identifier = b.target_identifier AND c.status = 'approved' WHERE b.status = 'active' AND (b.expires_at IS NULL OR b.expires_at > NOW()) ORDER BY FIELD(b.priority, 'critical', 'high', 'medium', 'low'), b.created_at DESC LIMIT ?]], { MdtConfig.BoloListLimit }) or {}) or {} } }
end)

lib.callback.register('police_mdt:penalCodes', function(source)
    if not isAuthorized(source) then return {} end
    local rows = {}
    for _, book in ipairs({ codeBooks.penal, codeBooks.vehicle }) do
        for _, entry in ipairs(book) do
            rows[#rows + 1] = {
                code = entry.code or '',
                title = entry.title or '',
                fine = tonumber(entry.fine) or 0,
                prisonMonths = tonumber(entry.prison_months) or 0
            }
        end
    end
    return rows
end)

lib.callback.register('police_mdt:ticketCodes', function(source)
    if not isAuthorized(source) then return {} end
    local books = { penal = {}, vehicle = {} }
    for book, entries in pairs(codeBooks) do
        for _, entry in ipairs(entries) do
            books[book][#books[book] + 1] = {
                code = entry.code or '',
                    title = entry.title or '',
                    fine = tonumber(entry.fine) or 0,
                    prisonMonths = tonumber(entry.prison_months) or 0,
                    category = entry.category or '',
                section = entry.section or ''
            }
        end
    end
    return books
end)

lib.callback.register('police_mdt:request', function(source, request)
    local action = request and request.action
    if action == 'cadMyUnit' or action == 'cadSaveUnit' then
        if not isPoliceMember(source) then return notify(source) end
    elseif not isAuthorized(source) then
        return notify(source)
    end
    if action == 'searchPeople' then
        local term = cleanText(request.term, 80)
        if #term < 2 then return { ok = true, data = {} } end
        local like = '%' .. term .. '%'
        local rows = MySQL.query.await([[SELECT u.identifier, i.id AS idcard_no, COALESCE(i.firstname, u.firstname) firstname, COALESCE(i.lastname, u.lastname) lastname,
            COALESCE(i.dob, u.dateofbirth) dob, i.photo_url, i.status idcard_status FROM users u
            LEFT JOIN lv_idcards i ON i.identifier = u.identifier AND i.status = 'approved'
            WHERE CONCAT('I', ((i.id * 135791 + 97531) % 9000000) + 1000000) = ? OR CONCAT(COALESCE(i.firstname, u.firstname), ' ', COALESCE(i.lastname, u.lastname)) LIKE ?
            ORDER BY firstname, lastname LIMIT ?]], { term, like, MdtConfig.SearchLimit }) or {}
        for _, row in ipairs(rows) do row.idcard_no = idCardNumber(row.idcard_no) end
        return { ok = true, data = rows }
    end
    if action == 'cadMyUnit' then
        return { ok = true, data = cadUnit(source) }
    end
    if action == 'cadSaveUnit' then
        local current = cadUnit(source)
        local callsign = request.callsign == nil and current.callsign or cleanText(request.callsign, 20):upper()
        local statuses = { ['Available'] = true, ['Unavailable'] = true, ['Code 6'] = true, ['Code 6 ADAM'] = true, ['Code 6 CHARLES'] = true, ['Code 7'] = true, ['In TAC'] = true, ['Responding to Backup'] = true }
        local locations = { ['Mobile'] = true, ['Station'] = true, ['Unknown'] = true }
        if not statuses[request.status] or not locations[request.location] then return notify(source, 'Thông tin unit không hợp lệ.') end
        cadUnits[source] = { callsign = callsign, unitType = 'General Patrol', status = request.status, location = request.location }
        if callsign ~= '' then
            for playerId, unit in pairs(cadUnits) do
                if playerId ~= source and unit.callsign:upper() == callsign then
                    unit.status = request.status
                    unit.location = request.location
                end
            end
        end
        TriggerClientEvent('police_mdt:client:cadChanged', -1)
        return { ok = true, data = cadUnits[source] }
    end
    if action == 'cadRoster' then
        return { ok = true, data = dutyRoster() }
    end
    if action == 'cadCodeSearch' then
        local book = request.book == 'vehicle' and 'vehicle' or 'penal'
        return { ok = true, data = searchCodeBook(book, request.term, request.section), sections = codeBookSections(book), book = book }
    end
    if action == 'cadLocate' then
        local callsign = cleanText(request.callsign, 20):upper()
        for _, unit in ipairs(dutyRoster()) do
            if unit.callsign:upper() == callsign and unit.location == 'Mobile' and unit.sources[1] then
                local ped = GetPlayerPed(unit.sources[1])
                if ped ~= 0 then
                    local coords = GetEntityCoords(ped)
                    return { ok = true, data = { x = coords.x, y = coords.y } }
                end
            end
        end
        return notify(source, 'Không thể định vị unit này.')
    end
    if action == 'personDetail' then return { ok = true, data = detail(cleanText(request.identifier, 80)) } end
    if action == 'searchVehicles' then
        local plate = cleanPlate(request.term)
        if #plate < 2 then return { ok = true, data = {} } end
        local rows = MySQL.query.await([[SELECT ov.owner, ov.plate, ov.vehicle, ov.stored, ov.isTowedOut, ov.vehicleGarage, ov.vehicleImpound,
            COALESCE(i.firstname, u.firstname) firstname, COALESCE(i.lastname, u.lastname) lastname FROM owned_vehicles ov
            LEFT JOIN users u ON u.identifier = ov.owner LEFT JOIN lv_idcards i ON i.identifier = ov.owner AND i.status = 'approved'
            WHERE UPPER(TRIM(ov.plate)) LIKE ? ORDER BY ov.plate LIMIT ?]], { '%' .. plate .. '%', MdtConfig.SearchLimit }) or {}
        for index, row in ipairs(rows) do
            local mapped = mapVehicle(row)
            mapped.ownerIdentifier = row.owner
            mapped.ownerName = (row.firstname or 'Unknown') .. ' ' .. (row.lastname or '')
            mapped.bolos = activeBolos(row.owner, mapped.plate, mapped.ownerName)
            rows[index] = mapped
        end
        return { ok = true, data = rows }
    end
    if action == 'listBolos' then
        local rows = MySQL.query.await([[SELECT b.id, b.type, b.target_name, b.plate, b.title, b.reason, b.priority, b.status, b.created_by_name, b.expires_at, b.created_at, LPAD(c.id, 8, '0') AS idcard_no FROM police_bolos b
            LEFT JOIN lv_idcards c ON c.identifier = b.target_identifier AND c.status = 'approved' WHERE b.status = 'active' AND (b.expires_at IS NULL OR b.expires_at > NOW()) ORDER BY FIELD(b.priority, 'critical', 'high', 'medium', 'low'), b.created_at DESC LIMIT ?]], { MdtConfig.BoloListLimit }) or {}
        return { ok = true, data = rows }
    end
    if action == 'searchTickets' then
        local term = cleanText(request.term, 80)
        local status = cleanText(request.status, 30)
        local whereClauses = {}
        local params = {}

        if status ~= '' and status ~= 'all' then
            whereClauses[#whereClauses + 1] = "pt.status = ?"
            params[#params + 1] = status
        end

        if #term >= 2 then
            local like = '%' .. term .. '%'
            whereClauses[#whereClauses + 1] = "(pt.ticket_no LIKE ? OR card.id = ? OR pt.target_name LIKE ? OR pt.violation LIKE ?)"
            params[#params + 1] = like
            params[#params + 1] = term
            params[#params + 1] = like
            params[#params + 1] = like
        end

        local whereSql = #whereClauses > 0 and ("WHERE " .. table.concat(whereClauses, " AND ")) or ""
        params[#params + 1] = MdtConfig.SearchLimit

        local query = string.format([[SELECT pt.id, pt.ticket_no, pt.target_identifier, pt.target_name, pt.violation, pt.fine_amount, pt.status, DATE_FORMAT(pt.issued_at, '%%d/%%m/%%Y %%H:%%i') AS issued_at_text, DATE_FORMAT(pt.due_at, '%%d/%%m/%%Y %%H:%%i') AS due_at_text, pt.officer_name, pt.faction_tag, card.id AS idcard_no
            FROM police_tickets pt LEFT JOIN lv_idcards card ON card.identifier = pt.target_identifier AND card.status = 'approved'
            %s ORDER BY pt.issued_at DESC LIMIT ?]], whereSql)

        local rows = MySQL.query.await(query, params) or {}
        return { ok = true, data = rows }
    end
    if action == 'voidTicket' then
        local ticketId = tonumber(request.id)
        if not ticketId then return { ok = false, message = 'Vé phạt không hợp lệ.' } end
        local user = officer(source)
        local ticket = MySQL.single.await([[SELECT * FROM police_tickets WHERE id = ? AND status IN ('active', 'overdue')]], {ticketId})
        if not ticket then return { ok = false, message = 'Không thể hủy vé phạt này.' } end

        local success = MySQL.update.await([[UPDATE police_tickets SET status = 'void' WHERE id = ? AND status IN ('active', 'overdue')]], {ticketId})
        if success and success > 0 then
            sendBoloLog('Sĩ quan hủy vé phạt từ MDT', ('**Mã vé:** `%s`\n**Sĩ quan thao tác:** %s (%s)\n**Người vi phạm:** %s (`%s`)\n**Lỗi vi phạm:** %s\n**Tiền phạt:** `$%s`\n**Trạng thái trước khi hủy:** `%s`'):format(
                ticket.ticket_no, user.name, user.factionTag, ticket.target_name, ticket.target_identifier, ticket.violation, ticket.fine_amount, ticket.status
            ), 15548997)
            return { ok = true, message = 'Đã hủy vé phạt thành công.' }
        end
        return { ok = false, message = 'Không thể hủy vé phạt này.' }
    end
    if action == 'createBolo' then
        local user = officer(source)
        local boloType = request.type == 'vehicle' and 'vehicle' or 'person'
        local identifier = cleanText(request.identifier, 80)
        local targetName = cleanText(request.targetName, 120)
        local plate = cleanPlate(request.plate)
        local title = cleanText(request.title, 160)
        local reason = cleanText(request.reason, 2000)
        local priority = ({ low = true, medium = true, high = true, critical = true })[request.priority] and request.priority or 'medium'
        local hours = math.min(math.max(tonumber(request.hours) or 0, 0), 720)
        if boloType == 'person' then
            local card = MySQL.single.await('SELECT identifier, firstname, lastname FROM lv_idcards WHERE id = ? AND status = \'approved\' LIMIT 1', { tonumber(identifier) or 0 })
            identifier = card and card.identifier or ''
            if card then targetName = (card.firstname or '') .. ' ' .. (card.lastname or '') end
        end
        if title == '' or reason == '' or (boloType == 'person' and targetName == '') or (boloType == 'person' and cleanText(request.identifier, 80) ~= '' and identifier == '') or (boloType == 'vehicle' and plate == '') then return notify(source, 'Thông tin BOLO không hợp lệ.') end
        local expiresAt = hours > 0 and os.date('%Y-%m-%d %H:%M:%S', os.time() + hours * 3600) or nil
        local id = MySQL.insert.await([[INSERT INTO police_bolos (type, target_identifier, target_name, plate, title, reason, priority, created_by_identifier, created_by_name, faction_tag, expires_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], { boloType, identifier ~= '' and identifier or nil, targetName ~= '' and targetName or nil, plate ~= '' and plate or nil, title, reason, priority, user.identifier, user.name, user.factionTag, expiresAt })
        if not id then return notify(source, 'Không thể lưu BOLO. Vui lòng thử lại.') end
        sendBoloLog('Tạo BOLO', ('**Sĩ quan:** %s\n**Đơn vị:** %s\n**Loại:** %s\n**Mục tiêu:** %s\n**Tiêu đề:** %s\n**Lý do:** %s\n**Ưu tiên:** %s'):format(user.name, user.factionTag, boloType, boloType == 'vehicle' and plate or targetName, title, reason, priority), 3447003)
        TriggerClientEvent('police_mdt:client:boloChanged', -1)
        return { ok = true, data = { id = id } }
    end
    if action == 'resolveBolo' then
        local user = officer(source)
        local id = tonumber(request.id)
        if not id then return notify(source, 'BOLO không hợp lệ.') end
        local bolo = MySQL.single.await('SELECT type, target_name, plate, title FROM police_bolos WHERE id = ? AND status = \'active\' LIMIT 1', { id })
        local updated = MySQL.update.await([[UPDATE police_bolos SET status = 'resolved', resolved_at = NOW(), resolved_by_identifier = ? WHERE id = ? AND status = 'active']], { user.identifier, id })
        if updated and updated > 0 and bolo then sendBoloLog('Đóng BOLO', ('**Sĩ quan:** %s\n**Đơn vị:** %s\n**BOLO:** %s\n**Mục tiêu:** %s'):format(user.name, user.factionTag, bolo.title, bolo.type == 'vehicle' and bolo.plate or bolo.target_name), 3066993) end
        TriggerClientEvent('police_mdt:client:boloChanged', -1)
        return { ok = true }
    end
    return notify(source, 'Yêu cầu MDT không hợp lệ.')
end)

AddEventHandler('playerDropped', function()
    cadUnits[source] = nil
    TriggerClientEvent('police_mdt:client:cadChanged', -1)
end)

exports('RecordArrest', function(data)
    if type(data) ~= 'table' then return false end
    local inserted = MySQL.insert.await([[INSERT INTO police_arrests (officer_identifier, officer_name, officer_badge, faction_tag, target_identifier, target_name, reason, base_minutes, extra_minutes, final_minutes, fine_amount, cell_index)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], { data.officerIdentifier, data.officerName, data.officerBadge, data.factionTag or 'police', data.targetIdentifier, data.targetName, cleanText(data.reason, 2000), tonumber(data.baseMinutes) or 0, tonumber(data.extraMinutes) or 0, tonumber(data.finalMinutes) or 0, tonumber(data.fineAmount) or 0, tonumber(data.cellIndex) or 1 })
    profileCache[data.targetIdentifier] = nil
    return inserted ~= nil
end)
