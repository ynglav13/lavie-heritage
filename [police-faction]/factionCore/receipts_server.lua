local PendingReceipts = {}
local receiptRequests = {}
local receiptSequence = 0

local function SendChatMessage(target, message, colorCode)
    if GetResourceState('custom-chat') == 'started' then
        TriggerClientEvent('custom-chat:addMessage', target, (colorCode or "{FFA500}") .. "[HÓA ĐƠN] " .. message)
        return
    end

    local r, g, b = 255, 165, 0
    if colorCode == "{3498DB}" then r, g, b = 52, 152, 219
    elseif colorCode == "{E74C3C}" then r, g, b = 231, 76, 60
    elseif colorCode == "{E67E22}" then r, g, b = 230, 126, 34
    elseif colorCode == "{2ECC71}" then r, g, b = 46, 204, 113
    end

    TriggerClientEvent('chat:addMessage', target, {
        color = { r, g, b },
        multiline = true,
        args = { "[HÓA ĐƠN]", message }
    })
end

local function FormatMoney(amount)
    if ESX and ESX.Math and ESX.Math.GroupDigits then
        return ESX.Math.GroupDigits(amount)
    end
    local formatted = tostring(math.floor(tonumber(amount) or 0))
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

AddEventHandler("onResourceStart", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        MySQL.query([[
            CREATE TABLE IF NOT EXISTS `business_receipts` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `business_tag` VARCHAR(50) NOT NULL,
                `business_name` VARCHAR(100) NOT NULL,
                `issuer_identifier` VARCHAR(50) NOT NULL,
                `issuer_name` VARCHAR(100) NOT NULL,
                `customer_identifier` VARCHAR(50) NOT NULL,
                `customer_name` VARCHAR(100) NOT NULL,
                `description` TEXT NOT NULL,
                `base_price` BIGINT NOT NULL,
                `vat_amount` BIGINT NOT NULL,
                `tax_amount` BIGINT NOT NULL,
                `net_received` BIGINT NOT NULL,
                `total_amount` BIGINT NOT NULL,
                `status` VARCHAR(20) NOT NULL,
                `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]], {}, function()
            MySQL.query([[
                ALTER TABLE `business_receipts`
                MODIFY COLUMN `base_price` BIGINT NOT NULL,
                MODIFY COLUMN `vat_amount` BIGINT NOT NULL,
                MODIFY COLUMN `tax_amount` BIGINT NOT NULL,
                MODIFY COLUMN `net_received` BIGINT NOT NULL,
                MODIFY COLUMN `total_amount` BIGINT NOT NULL;
            ]], {})
            print("[factionCore] Bảng business_receipts đã sẵn sàng.")
        end)
    end
end)

local function SendDiscordLog(status, data, dbId, paymentMethod)
    local upperTag = string.upper(data.businessTag)
    local bizConfig = Config.Receipts.Businesses and Config.Receipts.Businesses[upperTag]
    local webhook = bizConfig and bizConfig.DiscordWebhook or Config.Receipts.DiscordWebhook
    local hasWebhook = webhook and webhook ~= "" and webhook ~= "YOUR_DISCORD_WEBHOOK_HERE"

    local color = (status == "paid") and 3066993 or 15158332
    if status == "insufficient_funds" then color = 15105570 end

    local statusText = "🟢 THÀNH CÔNG"
    if status == "declined" then statusText = "🔴 BỊ TỪ CHỐI" end
    if status == "insufficient_funds" then statusText = "⚠️ KHÔNG ĐỦ TIỀN" end

    local paymentMethodText = "N/A"
    if status == "paid" then
        if paymentMethod == "cash" then
            paymentMethodText = "💵 Tiền mặt"
        elseif paymentMethod == "bank" then
            paymentMethodText = "💳 Tài khoản ngân hàng"
        else
            paymentMethodText = tostring(paymentMethod)
        end
    end

    local descText = ""
    local success, items = pcall(json.decode, data.description)
    if success and type(items) == "table" then
        local itemStrings = {}
        for i = 1, #items do
            local qty = tonumber(items[i].qty) or 1
            local price = tonumber(items[i].price) or 0
            table.insert(itemStrings, ("- %s x%d: **$%s** (Đơn giá: $%s)"):format(items[i].name, qty, price * qty, price))
        end
        descText = table.concat(itemStrings, "\n")
    else
        descText = data.description
    end

    local taxAmountText = (status == "paid") and ("$" .. FormatMoney(data.taxAmount)) or "$0"
    local netReceivedText = (status == "paid") and ("$" .. FormatMoney(data.netReceived)) or "$0"

    local titleText = "🧾 BÁO CÁO HÓA ĐƠN - " .. data.businessName
    if dbId then
        titleText = ("🧾 BÁO CÁO HÓA ĐƠN #%s - %s"):format(dbId, data.businessName)
    end

    local embeds = {
        {
            ["title"] = titleText,
            ["color"] = color,
            ["fields"] = {
                { ["name"] = "🏢 Doanh nghiệp", ["value"] = ("%s (%s)"):format(data.businessName, data.businessTag), ["inline"] = true },
                { ["name"] = "📊 Trạng thái", ["value"] = statusText, ["inline"] = true },
                { ["name"] = "💳 Phương thức", ["value"] = paymentMethodText, ["inline"] = true },
                { ["name"] = "💼 Người xuất hóa đơn", ["value"] = ("**%s** (ID: %s)\n`%s`"):format(data.issuerName, data.issuerSrc, data.issuerIdentifier), ["inline"] = false },
                { ["name"] = "👤 Khách hàng", ["value"] = ("**%s** (ID: %s)\n`%s`"):format(data.customerName, data.customerSrc, data.customerIdentifier), ["inline"] = false },
                { ["name"] = "📝 Chi tiết hóa đơn", ["value"] = descText, ["inline"] = false },
                { ["name"] = "💰 Tổng khách trả", ["value"] = "$" .. FormatMoney(data.totalAmount), ["inline"] = true },
                { ["name"] = "🏛️ Thuế DN (" .. (data.govTaxPercent or 5) .. "%)", ["value"] = taxAmountText .. " (Thu hồi về Server)", ["inline"] = true },
                { ["name"] = "📈 Doanh thu thực nhận", ["value"] = netReceivedText .. " (Cộng vào quỹ DN)", ["inline"] = true }
            },
            ["footer"] = {
                ["text"] = "factionCore Receipts • " .. os.date("%Y-%m-%d %H:%M:%S")
            }
        }
    }

    local account = (paymentMethod == "cash" and "money") or (paymentMethod == "bank" and "bank") or nil
    local balanceAfter
    local balanceBefore
    if account then
        local xCustomer = ESX.GetPlayerFromId(data.customerSrc)
        local customerAccount = xCustomer and xCustomer.getAccount(account)
        balanceAfter = customerAccount and tonumber(customerAccount.money) or nil
        if balanceAfter then
            balanceBefore = status == "paid" and balanceAfter + data.totalAmount or balanceAfter
        end
    end

    local reason = "Khách hàng từ chối thanh toán hóa đơn"
    if status == "paid" then
        reason = "Khách hàng thanh toán hóa đơn thành công"
    elseif status == "insufficient_funds" then
        reason = "Khách hàng không đủ tiền thanh toán hóa đơn"
    end

    local requestId = dbId and ("receipt:%s:%s"):format(data.businessTag, dbId) or nil
    local centralLogged = false
    if GetResourceState('legacyWebhook') == 'started' then
        local success, accepted = pcall(function()
            return exports['legacyWebhook']:AuditTransaction({
                webhook = hasWebhook and webhook or nil,
                username = "Receipts Bot",
                category = "faction_receipt",
                action = "receipt_" .. status,
                status = status == "paid" and "committed" or "rejected",
                sourceResource = GetCurrentResourceName(),
                reason = reason,
                requestId = requestId,
                player = {
                    id = data.customerSrc,
                    name = data.customerName,
                    identifier = data.customerIdentifier,
                    license = GetPlayerIdentifierByType(data.customerSrc, 'license')
                },
                target = {
                    id = data.issuerSrc,
                    name = data.issuerName,
                    identifier = data.issuerIdentifier,
                    license = GetPlayerIdentifierByType(data.issuerSrc, 'license')
                },
                account = account,
                amount = data.totalAmount,
                delta = status == "paid" and -data.totalAmount or 0,
                balanceBefore = balanceBefore,
                balanceAfter = balanceAfter,
                title = titleText,
                message = ("**Doanh nghiệp:** %s (%s)\n**Trạng thái:** %s\n**Phương thức:** %s\n**Chi tiết:**\n%s\n**Tổng khách trả:** $%s\n**Thuế:** $%s\n**Doanh thu thực nhận:** $%s"):format(
                    data.businessName,
                    data.businessTag,
                    statusText,
                    paymentMethodText,
                    descText,
                    data.totalAmount,
                    status == "paid" and data.taxAmount or 0,
                    status == "paid" and data.netReceived or 0
                ),
                color = color,
                context = {
                    factionTag = data.businessTag,
                    source = data.customerSrc,
                    action = status,
                    receiptId = dbId,
                    issuerSource = data.issuerSrc,
                    paymentMethod = paymentMethod,
                    basePrice = data.basePrice,
                    taxAmount = data.taxAmount,
                    netReceived = data.netReceived,
                    description = data.description
                }
            })
        end)
        centralLogged = success and accepted == true
    end

    if centralLogged or not hasWebhook then
        return
    end

    PerformHttpRequest(webhook, function(err, text, headers) end, 'POST', json.encode({username = "Receipts Bot", embeds = embeds}), { ['Content-Type'] = 'application/json' })
end

local function getCharacterName(identifier)
    local result = MySQL.query.await("SELECT firstname, lastname FROM users WHERE identifier = ?", {identifier})
    if result and result[1] then
        return ("%s %s"):format(result[1].firstname, result[1].lastname)
    end
    return "Không rõ"
end

RegisterNetEvent("receipts:server:CreateReceipt", function(targetId, basePrice, description)
    local src = source
    local now = GetGameTimer()
    if receiptRequests[src] and now - receiptRequests[src] < 1000 then return end
    receiptRequests[src] = now
    targetId = tonumber(targetId)
    basePrice = tonumber(basePrice)
    description = tostring(description or ''):sub(1, 2000)
    local xPlayer = ESX.GetPlayerFromId(src)
    local xTarget = ESX.GetPlayerFromId(targetId)

    if not xPlayer or not xTarget then
        TriggerClientEvent("esx:showNotification", src, "Người chơi không tồn tại trực tuyến!")
        return
    end

    local pedIssuer = GetPlayerPed(src)
    local pedCustomer = GetPlayerPed(targetId)
    local coordsIssuer = GetEntityCoords(pedIssuer)
    local coordsCustomer = GetEntityCoords(pedCustomer)
    local distance = #(coordsIssuer - coordsCustomer)

    if distance > 5.0 then
        TriggerClientEvent("esx:showNotification", src, "Khách hàng quá xa để nhận hóa đơn!")
        return
    end

    local maxGlobalPrice = (Config.Receipts and tonumber(Config.Receipts.MaxPrice)) or 2000000000
    if not basePrice or basePrice <= 0 or basePrice > maxGlobalPrice or basePrice % 1 ~= 0 then
        TriggerClientEvent("esx:showNotification", src, "Số tiền không hợp lệ!")
        return
    end

    if src == targetId then
        TriggerClientEvent("esx:showNotification", src, "Bạn không thể tự xuất hóa đơn cho mình!")
        return
    end

    if PendingReceipts[targetId] then
        TriggerClientEvent("esx:showNotification", src, "Khách hàng đang có một hóa đơn chờ xử lý!")
        return
    end

    local state = Player(src).state
    local membership = exports.factionCore:GetPlayerFactionMembership(src)
    if not membership then
        TriggerClientEvent("esx:showNotification", src, "Bạn không ở trong tổ chức nào!")
        return
    end

    local factionData = MySQL.query.await("SELECT name, type, tag FROM faction WHERE tag = ?", {membership.tag})
    if not factionData or not factionData[1] or factionData[1].type ~= "business" then
        TriggerClientEvent("esx:showNotification", src, "Chỉ có nhân viên Doanh nghiệp mới có thể xuất hóa đơn!")
        return
    end

    local businessTag = factionData[1].tag
    local businessName = factionData[1].name

    local upperTag = string.upper(businessTag)
    local bizConfig = Config.Receipts.Businesses and Config.Receipts.Businesses[upperTag]
    if bizConfig then
        local minPrice = tonumber(bizConfig.MinPrice)
        local maxPrice = tonumber(bizConfig.MaxPrice)
        if (minPrice and basePrice < minPrice) or (maxPrice and basePrice > maxPrice) then
            TriggerClientEvent("esx:showNotification", src, "Số tiền hóa đơn nằm ngoài giới hạn doanh nghiệp!")
            return
        end
        if bizConfig.RequireDuty and state.factionDuty ~= true then
            TriggerClientEvent("esx:showNotification", src, "Bạn phải on duty để xuất hóa đơn!")
            return
        end
    end
    local govTaxPercent = bizConfig and bizConfig.GovTaxPercent or Config.Receipts.GovTaxPercent or 5

    local vatAmount = 0
    local taxAmount = math.floor(basePrice * (govTaxPercent / 100))
    local totalAmount = basePrice
    local netReceived = totalAmount - taxAmount

    local issuerName = getCharacterName(xPlayer.identifier)
    local customerName = getCharacterName(xTarget.identifier)

    receiptSequence = receiptSequence + 1
    PendingReceipts[targetId] = {
        requestId = ('receipt:%s:%s:%s:%s'):format(xPlayer.identifier, xTarget.identifier, os.time(), receiptSequence),
        businessTag = businessTag,
        businessName = businessName,
        issuerIdentifier = xPlayer.identifier,
        issuerName = issuerName,
        issuerSrc = src,
        customerIdentifier = xTarget.identifier,
        customerName = customerName,
        customerSrc = targetId,
        description = description,
        basePrice = basePrice,
        vatAmount = vatAmount,
        taxAmount = taxAmount,
        netReceived = netReceived,
        totalAmount = totalAmount,
        vatPercent = 0,
        govTaxPercent = govTaxPercent
    }

    TriggerClientEvent("receipts:client:ShowReceipt", targetId, businessName, basePrice, vatAmount, totalAmount, description)
    
    local descText = ""
    local success, items = pcall(json.decode, description)
    if success and type(items) == "table" then
        local itemStrings = {}
        for i = 1, #items do
            local qty = tonumber(items[i].qty) or 1
            if qty > 1 then
                table.insert(itemStrings, ("%s (x%d)"):format(items[i].name, qty))
            else
                table.insert(itemStrings, items[i].name)
            end
        end
        descText = table.concat(itemStrings, ", ")
    else
        descText = description
    end

    SendChatMessage(src, ("Đã xuất hóa đơn trị giá $%s cho khách hàng %s (Dịch vụ: %s)."):format(FormatMoney(totalAmount), customerName, descText), "{3498DB}")
    SendChatMessage(targetId, ("Bạn nhận được hóa đơn trị giá $%s từ %s (%s - Dịch vụ: %s)."):format(FormatMoney(totalAmount), businessName, issuerName, descText), "{3498DB}")
end)

RegisterNetEvent("receipts:server:RespondReceipt", function(method)
    local src = source
    local receipt = PendingReceipts[src]

    if not receipt then return end
    if receipt.processing then return end
    receipt.processing = true

    local xCustomer = ESX.GetPlayerFromId(src)
    local xIssuer = ESX.GetPlayerFromId(receipt.issuerSrc)
    if not xCustomer or xCustomer.identifier ~= receipt.customerIdentifier then PendingReceipts[src] = nil return end

    if method == "decline" then
        local dbId = MySQL.insert.await([[
            INSERT INTO business_receipts 
            (business_tag, business_name, issuer_identifier, issuer_name, customer_identifier, customer_name, description, base_price, vat_amount, tax_amount, net_received, total_amount, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {receipt.businessTag, receipt.businessName, receipt.issuerIdentifier, receipt.issuerName, receipt.customerIdentifier, receipt.customerName, receipt.description, receipt.basePrice, receipt.vatAmount, receipt.taxAmount, receipt.netReceived, receipt.totalAmount, "declined"})

        if xIssuer then
            SendChatMessage(receipt.issuerSrc, ("Khách hàng %s đã TỪ CHỐI thanh toán hóa đơn $%s."):format(receipt.customerName, FormatMoney(receipt.totalAmount)), "{E74C3C}")
        end
        SendChatMessage(src, ("Bạn đã TỪ CHỐI thanh toán hóa đơn $%s của %s."):format(FormatMoney(receipt.totalAmount), receipt.businessName), "{E74C3C}")

        SendDiscordLog("declined", receipt, dbId, method)
        PendingReceipts[src] = nil
        return
    end

    if method ~= 'cash' and method ~= 'bank' then
        PendingReceipts[src] = nil
        return
    end

    local account = (method == "cash") and "money" or "bank"
    local playerBalance = xCustomer.getAccount(account).money

    if playerBalance < receipt.totalAmount then
        local dbId = MySQL.insert.await([[
            INSERT INTO business_receipts 
            (business_tag, business_name, issuer_identifier, issuer_name, customer_identifier, customer_name, description, base_price, vat_amount, tax_amount, net_received, total_amount, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {receipt.businessTag, receipt.businessName, receipt.issuerIdentifier, receipt.issuerName, receipt.customerIdentifier, receipt.customerName, receipt.description, receipt.basePrice, receipt.vatAmount, receipt.taxAmount, receipt.netReceived, receipt.totalAmount, "insufficient_funds"})

        if xIssuer then
            SendChatMessage(receipt.issuerSrc, ("Giao dịch thất bại: Khách hàng %s KHÔNG ĐỦ TIỀN thanh toán hóa đơn $%s."):format(receipt.customerName, FormatMoney(receipt.totalAmount)), "{E67E22}")
        end
        SendChatMessage(src, ("Giao dịch thất bại: Bạn KHÔNG ĐỦ TIỀN để thanh toán hóa đơn $%s của %s."):format(FormatMoney(receipt.totalAmount), receipt.businessName), "{E67E22}")

        SendDiscordLog("insufficient_funds", receipt, dbId, method)
        PendingReceipts[src] = nil
        return
    end

    xCustomer.removeAccountMoney(account, receipt.totalAmount)
    local credited = exports.factionCore:ChangeFactionBudget(receipt.businessTag, receipt.netReceived, ("Khách hàng %s thanh toán hóa đơn: %s"):format(receipt.customerName, receipt.description or "Không có mô tả"), src, receipt.requestId)
    if not credited then
        xCustomer.addAccountMoney(account, receipt.totalAmount)
        if xIssuer then
            SendChatMessage(receipt.issuerSrc, "Không thể ghi nhận doanh thu vào quỹ doanh nghiệp. Hóa đơn đã hủy.", "{E74C3C}")
        end
        SendChatMessage(src, "Hóa đơn đã hủy vì quỹ doanh nghiệp không khả dụng.", "{E74C3C}")
        PendingReceipts[src] = nil
        return
    end

    local dbId = MySQL.insert.await([[
        INSERT INTO business_receipts 
        (business_tag, business_name, issuer_identifier, issuer_name, customer_identifier, customer_name, description, base_price, vat_amount, tax_amount, net_received, total_amount, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {receipt.businessTag, receipt.businessName, receipt.issuerIdentifier, receipt.issuerName, receipt.customerIdentifier, receipt.customerName, receipt.description, receipt.basePrice, receipt.vatAmount, receipt.taxAmount, receipt.netReceived, receipt.totalAmount, "paid"})

    if xIssuer then
        SendChatMessage(receipt.issuerSrc, ("Khách hàng %s đã THANH TOÁN THÀNH CÔNG hóa đơn $%s. Quỹ DN nhận $%s (sau khi trừ $%s thuế)."):format(receipt.customerName, FormatMoney(receipt.totalAmount), FormatMoney(receipt.netReceived), FormatMoney(receipt.taxAmount)), "{2ECC71}")
    end
    SendChatMessage(src, ("Bạn đã THANH TOÁN THÀNH CÔNG hóa đơn $%s của %s bằng %s."):format(FormatMoney(receipt.totalAmount), receipt.businessName, (method == "cash" and "tiền mặt" or "tài khoản ngân hàng")), "{2ECC71}")

    SendDiscordLog("paid", receipt, dbId, method)
    PendingReceipts[src] = nil
end)

ESX.RegisterServerCallback('receipts:server:GetPlayersNames', function(src, cb, playerIds)
    local membership = exports.factionCore:GetPlayerFactionMembership(src)
    if not membership or membership.type ~= 'business' or type(playerIds) ~= 'table' or #playerIds > 32 then return cb({}) end
    local playersData = {}
    for i = 1, #playerIds do
        local targetId = tonumber(playerIds[i])
        local xTarget = ESX.GetPlayerFromId(targetId)
        if xTarget then
            local charName = getCharacterName(xTarget.identifier)
            table.insert(playersData, {
                id = targetId,
                name = charName
            })
        end
    end
    cb(playersData)
end)

AddEventHandler('playerDropped', function()
    receiptRequests[source] = nil
    PendingReceipts[source] = nil
end)
