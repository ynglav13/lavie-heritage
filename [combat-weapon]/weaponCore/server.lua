local LastStressUpdate = {}

RegisterNetEvent('weaponCore:server:addShootingStress', function()
    if not Config.StressOnShooting then
        return
    end

    if GetResourceState('lv_status') ~= 'started' then
        return
    end

    local src = source
    local now = GetGameTimer()
    local lastUpdate = LastStressUpdate[src] or 0

    if now - lastUpdate < Config.StressServerCooldown then
        return
    end
    
    LastStressUpdate[src] = now

    exports.lv_status:AddStress(src, Config.StressAmount)
end)

AddEventHandler('playerDropped', function()
    LastStressUpdate[source] = nil
end)
