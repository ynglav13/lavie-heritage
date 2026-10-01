Config = Config or {}

Config.Receipts = {
    GovTaxPercent = 5,
    MaxPrice = 2000000000,
    DiscordWebhook = GetConvar('faction_receipts_webhook_default', ''),

    Businesses = {
        ['PEARLS'] = {
            GovTaxPercent = 5,
            MinPrice = 280,
            MaxPrice = 40000,
            RequireDuty = true,
            DiscordWebhook = ""
        },
        ['TACO'] = {
            GovTaxPercent = 3,
            DiscordWebhook = GetConvar('faction_receipts_webhook_taco', '')
        },
        ['MECHANIC'] = {
            GovTaxPercent = 5,
            DiscordWebhook = GetConvar('faction_receipts_webhook_mechanic', '')
        },
        ['DEALERSHIP'] = {
            GovTaxPercent = 5,
            DiscordWebhook = GetConvar('faction_receipts_webhook_dealership', '')
        }
    }
}

Config.BusinessLocker = {
    ['TACO'] = {
        { item = 'burger', label = 'Bánh Hamburger', price = 800 },
        { item = 'nuoc_suoi', label = 'Nước lọc', price = 400 },
        { item = 'burrito', label = 'Burrito', price = 800 },
        { item = 'sandwich', label = 'Sandwich', price = 700 },
        { item = 'ecola', label = 'eCola', price = 600 },
        { item = 'lemon', label = 'Lemon', price = 500 }
    },
    ['MECHANIC'] = {
        { item = 'engine_oil', label = 'Engine Oil', price = 2000 },
        { item = 'tyre_replacement', label = 'Tyre Replacement', price = 2500 },
        { item = 'clutch_replacement', label = 'Clutch Replacement', price = 3000 },
        { item = 'air_filter', label = 'Air Filter', price = 5000 },
        { item = 'spark_plug', label = 'Spark Plug', price = 2000 },
        { item = 'brakepad_replacement', label = 'Brakepad Replacement', price = 1500 },
        { item = 'suspension_parts', label = 'Suspension Parts', price = 4000 },
        { item = 'cleaning_kit', label = 'Cleaning Kit', price = 2000 },
        { item = 'repair_kit', label = 'Repair Kit', price = 5000 },
        { item = 'duct_tape', label = 'Duct Tape', price = 2000 },
        { item = 'mechanic_tablet', label = 'Mechanic Tablet', price = 1000 },
        { item = 'ev_motor', label = 'ev motor', price = 1000 },
        { item = 'ev_battery', label = 'ev battery', price = 1000 },
        { item = 'ev_coolant', label = 'ev coolant', price = 1000 },
    }
}
