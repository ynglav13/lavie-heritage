local ESX = exports['es_extended']:getSharedObject()
local activeNewbies = {}
local playerSteps = {}

local function SetNewbieStatus(playerId, enabled)
    playerId = tonumber(playerId)

    if not playerId then
        return
    end

    local wasEnabled = activeNewbies[playerId] == true

    if enabled then
        activeNewbies[playerId] = true
    else
        activeNewbies[playerId] = nil
    end

    if wasEnabled ~= enabled then
        TriggerClientEvent('lv_tutorial:setNewbieTag', -1, playerId, enabled)
    end
end

local function SyncNewbieTags(playerId)
    TriggerClientEvent('lv_tutorial:syncNewbieTags', playerId, activeNewbies)
end

local function GetPlayerStep(source)
    if playerSteps[source] then
        return playerSteps[source]
    end

    local xPlayer = ESX.GetPlayerFromId(source)

    if not xPlayer then
        return 1
    end

    local result = MySQL.single.await('SELECT tutorial_step FROM users WHERE identifier = ?',
    {
        xPlayer.identifier
    })
    local step = 1

    if result and result.tutorial_step then
        step = result.tutorial_step
    end

    playerSteps[source] = step

    SetNewbieStatus(source, step <= #Config.Steps)

    SyncNewbieTags(source)
    return step
end

ESX.RegisterServerCallback('lv_tutorial:getStep', function(source, cb)
    local step = GetPlayerStep(source)

    cb(step)
end)

local function AdvanceStepInternal(source, expectedStep)
    local currentStep = GetPlayerStep(source)

    if currentStep == expectedStep then
        local nextStep = currentStep + 1

        playerSteps[source] = nextStep
        
        local xPlayer = ESX.GetPlayerFromId(source)

        if xPlayer then
            MySQL.update('UPDATE users SET tutorial_step = ? WHERE identifier = ?',
            {
                nextStep,
                xPlayer.identifier
            })

            TriggerClientEvent('lv_tutorial:updateStep', source, nextStep)

            SetNewbieStatus(source, nextStep <= #Config.Steps)
            
            if nextStep > #Config.Steps then
                xPlayer.addMoney(20000)

                TriggerClientEvent('lv_notify:client:notify', source,
                {
                    title = 'Phần Thưởng',
                    message = 'Hoàn thành hướng dẫn tân thủ. Bạn đã nhận được $20,000 tiền mặt để khởi nghiệp',
                    type = 'success',
                    duration = 10000
                })
            end
        end
        return true
    end
    return false
end

RegisterNetEvent('lv_tutorial:advanceStep')
AddEventHandler('lv_tutorial:advanceStep', function(expectedStep)
    AdvanceStepInternal(source, expectedStep)
end)

AddEventHandler('playerDropped', function()
    SetNewbieStatus(source, false)
    playerSteps[source] = nil
end)

exports('AdvanceStep', function(source, expectedStep)
    return AdvanceStepInternal(source, expectedStep)
end)

exports('IsTutorialDone', function(source)
    local step = GetPlayerStep(source)
    return step > #Config.Steps
end)

local function SkipTutorial(source)
    local xPlayer = ESX.GetPlayerFromId(source)

    if not xPlayer then
        return false
    end
    
    local nextStep = #Config.Steps + 1

    playerSteps[source] = nextStep

    MySQL.update('UPDATE users SET tutorial_step = ? WHERE identifier = ?',
    {
        nextStep, xPlayer.identifier
    })

    TriggerClientEvent('lv_tutorial:updateStep', source, nextStep)

    SetNewbieStatus(source, false)
    return true
end

exports('SkipTutorial', function(source)
    return SkipTutorial(source)
end)

local function SetPlayerStep(source, step)
    local xPlayer = ESX.GetPlayerFromId(source)

    if not xPlayer then
        return false
    end
    
    playerSteps[source] = step

    MySQL.update('UPDATE users SET tutorial_step = ? WHERE identifier = ?',
    {
        step, xPlayer.identifier
    })

    TriggerClientEvent('lv_tutorial:updateStep', source, step)

    SetNewbieStatus(source, step <= #Config.Steps)
    return true
end

exports('SetPlayerStep', function(source, step)
    return SetPlayerStep(source, step)
end)

ESX.RegisterCommand('setsteptutorial', 'admin', function(xPlayer, args, showError)
    local targetPlayer = args.playerId
    local step = args.step

    if targetPlayer and step then
        local success = SetPlayerStep(targetPlayer.source, step)

        if success then
            if xPlayer then
                xPlayer.showNotification(string.format("Đã đặt bước Tutorial của %s thành %s", targetPlayer.name, step))
            else
                print(string.format("Đã đặt bước Tutorial của %s thành %s", targetPlayer.name, step))
            end
        else
            if xPlayer then
                xPlayer.showNotification("Có lỗi xảy ra khi đặt bước Tutorial")
            else
                print("Có lỗi xảy ra khi đặt bước Tutorial")
            end
        end
    end
end, true,
{
    help = 'Đặt bước tutorial cho người chơi',
    validate = true,
    arguments =
    {
        {
            name = 'playerId',
            help = '',
            type = 'player'
        },
        {
            name = 'step',
            help = '',
            type = 'number'
        }
    }
})
