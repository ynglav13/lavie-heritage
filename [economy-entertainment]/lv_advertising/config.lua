Config = {}

Config.InteractionDistance = 4.0
Config.RequestCooldownMs = 3000
Config.AdDurationSeconds = 2 * 60 * 60
Config.CleanupIntervalSeconds = 60
Config.BasePrice = 200000
Config.PrimeDiscountPercent = 30
Config.MaxContentLength = 60
Config.MaxAdvertiserNameLength = 40
Config.MaxPhoneLength = 15

Config.NPC = {
    model = 'a_m_m_business_01',
    coords = vector4(227.92, -762.93, 31.03, 123.83),
    scenario = 'PROP_HUMAN_SEAT_BENCH',
    seatZOffset = 1.5,
    renderDistance = 40.0,
    label = 'QUẢNG CÁO',
    labelDistance = 15.0
}

Config.Blip = {
    enabled = true,
    sprite = 374,
    color = 2,
    scale = 0.8,
    label = 'Advertisement Center'
}
