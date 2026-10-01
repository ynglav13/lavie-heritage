exports('IsPrime', function()
    return LocalPlayer.state.isPrime == true
end)

exports('IsPrimePlus', function()
    return LocalPlayer.state.isPrimePlus == true
end)

local function TogglePrimeChat()
    TriggerServerEvent('prime_status:togglePcChat')
end

RegisterCommand('tooglepc', TogglePrimeChat, false)
