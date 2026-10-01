local ox_inventory = exports.ox_inventory
local isWearingBackpack = false
local currentModelHash = nil

local function getModelKey(ped)
    local hash = GetEntityModel(ped)

    if hash == `mp_m_freemode_01` then
        return 'mp_m_freemode_01'
    elseif hash == `mp_f_freemode_01` then
        return 'mp_f_freemode_01'
    end
    return nil
end

local function applyBackpackVisual(ped, modelKey)
    local config = Config.BagDrawables[modelKey]
    
    if config then
        SetPedComponentVariation(ped, Config.BagComponentId, config.drawable, config.texture, 0)
    end
end

local function removeBackpackVisual(ped, modelKey)
    local config = Config.DefaultBag[modelKey]
    
    if config then
        SetPedComponentVariation(ped, Config.BagComponentId, config.drawable, config.texture, 0)
    else
        SetPedComponentVariation(ped, Config.BagComponentId, 0, 0, 0)
    end
end

local function checkBackpack()
    local ped = PlayerPedId()
    
    if not DoesEntityExist(ped) or IsEntityDead(ped) then
        return
    end

    local modelKey = getModelKey(ped)
    
    if not modelKey then
        return
    end

    local count = ox_inventory:Search('count', Config.ItemName) or 0
    local hasBackpack = count > 0

    if hasBackpack then
        local config = Config.BagDrawables[modelKey]
        
        if config then
            local currentDrawable = GetPedDrawableVariation(ped, Config.BagComponentId)
            local currentTexture = GetPedTextureVariation(ped, Config.BagComponentId)

            if currentDrawable ~= config.drawable or currentTexture ~= config.texture then
                applyBackpackVisual(ped, modelKey)
            end
            
            isWearingBackpack = true
        end
    else
        if isWearingBackpack then
            removeBackpackVisual(ped, modelKey)
            
            isWearingBackpack = false
        end
    end
end

CreateThread(function()
    while true do
        Wait(2000)
        
        if LocalPlayer.state.isLoggedIn then
            checkBackpack()
        end
    end
end)

RegisterNetEvent('ox_inventory:updateInventory', function()
    if LocalPlayer.state.isLoggedIn then
        checkBackpack()
    end
end)
