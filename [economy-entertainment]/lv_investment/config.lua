Config = {}

Config.Account = 'money'
Config.TickSeconds = 60
Config.InteractionDistance = 4.0
Config.CancelRefundPercent = 70
Config.StaticChallengeMinutes = 10
Config.ChallengeTimeoutSeconds = 75

Config.NPC =
{
    name = 'investment_advisor',
    model = `a_m_m_business_01`,
    coords = vector4(249.97, -791.53, 30.64, 65.48),
    scenario = 'WORLD_HUMAN_CLIPBOARD',
    renderDistance = 40.0,
    label = 'ĐẦU TƯ',
    labelDistance = 15.0,
    labelHeight = 2.0
}

Config.Blip =
{
    enabled = true,
    sprite = 605,
    color = 4,
    scale = 0.8,
    label = 'Investment'
}

Config.Packages =
{
    {
        id = 'package_1h',
        label = 'Gói Đầu Tư 1 Giờ',
        principal = 7500,
        payout = 18000,
        requiredMinutes = 60
    },
    {
        id = 'package_3h',
        label = 'Gói Đầu Tư 3 Giờ',
        principal = 15000,
        payout = 31500,
        requiredMinutes = 180
    },
    {
        id = 'package_4h',
        label = 'Gói Đầu Tư 4 Giờ',
        principal = 25000,
        payout = 65000,
        requiredMinutes = 240
    },
    {
        id = 'package_8h',
        label = 'Gói Đầu Tư 8 Giờ',
        principal = 125000,
        payout = 215000,
        requiredMinutes = 480
    }
}

Config.Text =
{
    npcLabel = 'Investment Center',
    title = 'Investment Center'
}
