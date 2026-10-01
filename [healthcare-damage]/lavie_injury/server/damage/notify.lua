if DamageClient.Function.HasResource(DamageConfig.Lib) and DamageConfig.Lib == 'ox_lib' then
    function Notify(serverId, duration, type, title, message)
        TriggerClientEvent('lavie_injury:client:Notify', serverId or source, duration, type, title, message)
    end
end
