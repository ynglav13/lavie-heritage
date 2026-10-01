local isPendingReceipt = false

local function getMyFactionId()
    local FactionData = exports.factionCore:GetFactionData()
    if not FactionData then return nil end
    for _, results in pairs(FactionData) do
        if results.tag == LocalPlayer.state.factionTag then
            return results.id
        end
    end
    return nil
end

RegisterCommand("hoadon", function()
    local myFactionTag = LocalPlayer.state.factionTag
    if not myFactionTag or myFactionTag == "" then
        ESX.ShowNotification("Bạn không thuộc tổ chức nào!")
        return
    end

    local myFactionId = getMyFactionId()
    if not myFactionId then
        ESX.ShowNotification("Không tìm thấy ID tổ chức của bạn!")
        return
    end

    ESX.TriggerServerCallback('FactionPanel:server:GetOwnFactionSummary', function(factionData)
        if not factionData then
            ESX.ShowNotification("Không thể xác minh thông tin tổ chức!")
            return
        end

        local fType = factionData.type
        if fType ~= "business" then
            ESX.ShowNotification("Lệnh này chỉ dành cho nhân viên Doanh nghiệp!")
            return
        end

        local coords = GetEntityCoords(PlayerPedId())
        local nearby = lib.getNearbyPlayers(coords, 10.0)
        local playerIds = {}
        for i = 1, #nearby do
            table.insert(playerIds, GetPlayerServerId(nearby[i].id))
        end

        ESX.TriggerServerCallback('receipts:server:GetPlayersNames', function(playersData)
            SendNUIMessage({
                action = "openReceiptCreator",
                shopName = factionData.name,
                nearbyPlayers = playersData
            })
            SetNuiFocus(true, true)
        end, playerIds)
    end)
end, false)

RegisterNUICallback("submitReceipt", function(data, cb)
    SetNuiFocus(false, false)
    TriggerServerEvent("receipts:server:CreateReceipt", tonumber(data.targetId), tonumber(data.basePrice), tostring(data.description))
    cb("ok")
end)

RegisterNUICallback("closeReceiptCreator", function(data, cb)
    SetNuiFocus(false, false)
    cb("ok")
end)

RegisterNetEvent("receipts:client:ShowReceipt", function(shopName, basePrice, vatAmount, totalAmount, description)
    isPendingReceipt = true
    SendNUIMessage({
        action = "showReceipt",
        shopName = shopName,
        basePrice = basePrice,
        vatAmount = 0,
        totalAmount = totalAmount,
        description = description
    })
    SetNuiFocus(true, true)
end)

RegisterNUICallback("payReceipt", function(data, cb)
    isPendingReceipt = false
    SetNuiFocus(false, false)
    TriggerServerEvent("receipts:server:RespondReceipt", data.method)
    cb("ok")
end)
