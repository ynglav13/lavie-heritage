local recoveryRequestPending = false

local function notifyError(message)
    local self = GetSelf()

    vlib:Notify(self.id, 6000, 'error', 'Không Thể Thực Hiện', message)
end

local function formatRemaining(remaining)
    return ('Bạn chưa thể sử dụng lệnh này vào lúc này (Còn %d giây)'):format(math.max(0, math.ceil(tonumber(remaining) or 0)))
end

local recoveryErrors =
{
    busy = 'Yêu cầu hồi phục trước đó vẫn đang được xử lý',
    charge_failed = 'Máy chủ không thể thu viện phí vào lúc này',
    insufficient_cash = 'Bạn không có đủ tiền để thanh toán viện phí',
    insufficient_funds = 'Bạn không có đủ tiền để thanh toán viện phí',
    internal_error = 'Máy chủ gặp lỗi khi xử lý yêu cầu hồi phục',
    invalid_action = 'Hình thức hồi phục không hợp lệ',
    invalid_player = 'Máy chủ không tìm thấy dữ liệu nhân vật của bạn',
    invalid_mode = 'Hình thức hồi phục không hợp lệ',
    inventory_clear_failed = 'Máy chủ không thể xử lý hành trang khi hồi sinh',
    not_dead = 'Nhân vật của bạn chưa chết để có thể sử dụng lệnh này',
    not_downed = 'Nhân vật của bạn không ở trạng thái bị thương hoặc đã chết',
    requires_dead = 'Nhân vật của bạn chưa chết để có thể sử dụng lệnh này',
    requires_injury = 'Nhân vật của bạn không ở trạng thái bị thương phù hợp',
    wrong_status = 'Trạng thái hiện tại không phù hợp với lệnh này',
}

local function notifyRecoveryFailure(response)
    if type(response) == 'table' and tonumber(response.remaining) and tonumber(response.remaining) > 0 then
        return notifyError(formatRemaining(response.remaining))
    end

    local code = type(response) == 'table' and (response.error or response.code) or nil

    notifyError(recoveryErrors[code] or 'Máy chủ không thể xử lý yêu cầu hồi phục vào lúc này')
end

local function fallbackRecoveryPayload(mode)
    local ped = PlayerPedId()
    local coords = mode == 'respawn' and InjuryConfig.RespawnMe.Coords or InjuryConfig.SkipEMS.Coords

    return
    {
        ok = true,
        action = mode,
        coords = coords,
        heading = mode == 'respawn' and InjuryConfig.RespawnMe.Heading or InjuryConfig.SkipEMS.Heading,
        health = mode == 'skipems' and math.max(101, GetEntityMaxHealth(ped) - 50) or GetEntityMaxHealth(ped),
        armor = GetPedArmour(ped),
    }
end

local function requestRecovery(mode)
    if recoveryRequestPending or InjuryClient.recoveryRunning then
        return notifyError(recoveryErrors.busy)
    end

    recoveryRequestPending = true

    local callbackOk, response = pcall(function()
        return lib.callback.await('Injury:server:RequestRecovery', false, mode)
    end)

    recoveryRequestPending = false

    if not callbackOk then
        return notifyRecoveryFailure()
    end

    if response == true then
        response = fallbackRecoveryPayload(mode)
    end

    if type(response) ~= 'table' or response.ok ~= true then
        return notifyRecoveryFailure(response)
    end

    if type(response.recovery) == 'table' then
        response.coords = response.coords or response.recovery.coords
        response.heading = response.heading or response.recovery.heading
        response.health = response.health or response.recovery.health
        response.armor = response.armor or response.recovery.armor
        response.action = response.action or response.recovery.action or response.recovery.mode
    end

    response.action = response.action or mode
    ApplyInjuryRecovery(response)
end

if InjuryConfig.Developer.Commands then
    RegisterCommand('viset', function(_, args)
        local victim = tonumber(args[1])
        local status = args[2] and args[2]:lower() or ''
        local enabled = args[3] == 'true' or args[3] == '1'

        TriggerNetEvent('Injury:server:SetPlayerStatus', victim, tonumber(status), enabled)
    end)

    RegisterCommand('debug', function()
        CleanupInjuryVisuals(true)
    end)
end

RegisterCommand('respawnme', function()
    local state = LocalPlayer.state.Dead

    if not state or state.Status ~= true then
        return notifyError('Nhân vật của bạn chưa chết để có thể sử dụng lệnh này')
    end

    local remaining = GetInjuryRemainingSeconds(state, 'Dead')

    if remaining > 0 then
        return notifyError(formatRemaining(remaining))
    end

    local alert = lib.alertDialog(
    {
        header = 'Bạn Có Chắc Chắn Muốn Respawn?',
        content = ('Trong một tình huống vẫn đang diễn ra nếu bạn sử dụng lệnh này sẽ có khả năng bị kiện vì trốn tránh tình huống\n\nViệc sử dụng lệnh này sẽ khiến nhân vật bạn chết hoàn toàn và sẽ không còn nhớ những gì diễn ra trước đó\n\nChi phí sử dụng lệnh này là: $%s'):format(InjuryConfig.RespawnMe.Fine),
        centered = true,
        cancel = true,
        labels =
        {
            confirm = 'Xác Nhận',
            cancel = 'Hủy Bỏ'
        }
    })

    if alert == 'confirm' then
        requestRecovery('respawn')
    end
end)

RegisterCommand('skipems', function()
    local dead = LocalPlayer.state.Dead

    if dead and dead.Status == true then
        return notifyError('Bạn không thể sử dụng lệnh này khi nhân vật đã chết. Vui lòng dùng lệnh /respawnme')
    end

    local injured = LocalPlayer.state.Injured
    local helpup = LocalPlayer.state.Helpup
    local state = injured and injured.Status == true and injured or helpup and helpup.Status == true and helpup

    if not state then
        return notifyError('Bạn không bị thương để có thể sử dụng lệnh này')
    end

    local remaining = GetInjuryRemainingSeconds(state, injured and injured.Status == true and 'Injured' or 'Helpup')

    if remaining > 0 then
        return notifyError(formatRemaining(remaining))
    end

    requestRecovery('skipems')
end)

RegisterCommand('helpup', function(_, args)
    local self = GetSelf()
    local targetId = tonumber(args[1])

    if not targetId then
        return notifyError('ID người chơi không hợp lệ')
    end

    if self.id == targetId then
        return notifyError('Bạn không thể tự kéo dậy chính mình')
    end

    if IsPlayerInjuryDowned() then
        return notifyError('Bạn đang bị thương hoặc đã chết nên không thể kéo người khác dậy')
    end

    local targetPlayer

    for _, player in ipairs(GetActivePlayers()) do
        if GetPlayerServerId(player) == targetId then
            targetPlayer = player
            break
        end
    end

    if not targetPlayer then
        return notifyError('Người chơi không hợp lệ hoặc không ở gần bạn')
    end

    local targetPed = GetPlayerPed(targetPlayer)

    if not DoesEntityExist(targetPed) then
        return notifyError('Người chơi không hợp lệ hoặc không ở gần bạn')
    end

    if #(GetEntityCoords(targetPed) - GetEntityCoords(PlayerPedId())) >= 5.0 then
        return notifyError('Bạn không ở gần người chơi này')
    end

    local targetState = Player(targetId).state
    local canHelp = targetState.Helpup and targetState.Helpup.Status == true
        and not (targetState.Injured and targetState.Injured.Status == true)
        and not (targetState.Dead and targetState.Dead.Status == true)

    if not canHelp then
        return notifyError('Người chơi này không bị thương nhẹ để có thể kéo dậy')
    end

    TriggerNetEvent('Injury:server:RequestHelpUp', targetId)
end)

CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/respawnme', 'Tự hồi sinh về bệnh viện khi đã chết (Mất ký ức)')
    TriggerEvent('chat:addSuggestion', '/skipems', 'Bỏ qua sơ cứu khi bị thương để về bệnh viện')
    TriggerEvent('chat:addSuggestion', '/helpup', 'Kéo một người chơi đang bị thương nhẹ đứng dậy',
    {
        {
            name = 'id',
            help = 'ID của người chơi cần cứu'
        }
    })
end)
