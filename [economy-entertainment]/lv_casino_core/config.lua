CasinoConfig = {
    BusinessTag = 'CASINO',
    BusinessName = 'Diamond Casino & Resort',
    DefaultGarage = 'A',
    ChipItem = 'casino_chip',
    MemberItem = 'casino_member',
    VipItem = 'casino_vip',
    MemberPrice = 5000,
    VipPrice = 500000,
    ChipRate = 10000,
    ChipLiabilityMigration = {
        key = 'chip-liability-rate-1-to-10000',
        fromRate = 1
    },
    CashOutTaxPercent = 10,
    MaxCashierAmount = 10000000,
    InteractionDistance = 3.0,
    Cashier = {
        model = 'U_F_M_CasinoCash_01',
        coords = vec4(950.78, 33.56, 71.84, 50.0)
    },
    MembershipDesk = {
        model = 'u_f_m_casinoshop_01',
        coords = vec4(920.85, 45.75, 72.07, 270.0)
    },
    DutyDesk = {
        coords = vec3(926.12, 48.73, 81.1),
        radius = 1.2
    },
    Penthouse = {
        lobby = vec4(929.01, 34.93, 81.09, 325.0),
        attendant = {
            model = 'S_M_Y_Casino_01',
            coords = vec4(929.01, 34.93, 81.09, 325.0),
            scenario = 'WORLD_HUMAN_CLIPBOARD'
        },
        penthouse = vec4(963.62, 59.29, 111.55, 60.0),
        exit = vec4(963.79, 57.18, 111.55, 60.0)
    },
    Permissions = {
        cashier = 'casino_cashier',
        membership = 'casino_membership',
        ledger = 'casino_ledger'
    },
    Wheel = {
        MaxBusinessFundedReward = 250000000,
        VehicleModel = 'xa21',
        Rewards = {

            {type = 'vehicle', amount = 1, weight = 10, sound = 'car'},                  -- 01 CAR
            {type = 'item', item = 'sandwich', amount = 1, weight = 40, sound = 'win'}, -- 02 SNACK
            {type = 'none', amount = 0, weight = 50, sound = 'win'},                    -- 03 RANDOM WEAPONS (disabled)
            {type = 'chips', amount = 25000, weight = 100, sound = 'chips'},            -- 04 25,000 chips
            {type = 'bank', amount = 40000, weight = 200, sound = 'cash'},              -- 05 $40,000
            {type = 'item', item = 'ecola', amount = 1, weight = 200, sound = 'win'},    -- 06 SNACK
            {type = 'none', amount = 0, weight = 200, sound = 'win'},                   -- 07 RANDOM WEAPONS (disabled)
            {type = 'none', amount = 0, weight = 400, sound = 'mystery'},               -- 08 MYSTERY (disabled)
            {type = 'chips', amount = 20000, weight = 500, sound = 'chips'},            -- 09 20,000 chips
            {type = 'item', item = 'sandwich', amount = 1, weight = 500, sound = 'win'},-- 10 SNACK
            {type = 'none', amount = 0, weight = 600, sound = 'win'},                   -- 11 RANDOM WEAPONS (disabled)
            {type = 'chips', amount = 15000, weight = 600, sound = 'chips'},            -- 12 15,000 chips
            {type = 'bank', amount = 30000, weight = 700, sound = 'cash'},              -- 13 $30,000
            {type = 'item', item = 'ecola', amount = 1, weight = 700, sound = 'win'},   -- 14 SNACK
            {type = 'none', amount = 0, weight = 800, sound = 'win'},                   -- 15 DISCOUNT (disabled)
            {type = 'chips', amount = 10000, weight = 800, sound = 'chips'},            -- 16 10,000 chips
            {type = 'bank', amount = 20000, weight = 800, sound = 'cash'},              -- 17 $20,000
            {type = 'item', item = 'sandwich', amount = 1, weight = 900, sound = 'win'},-- 18 SNACK
            {type = 'none', amount = 0, weight = 900, sound = 'win'},                   -- 19 RANDOM WEAPONS (disabled)
            {type = 'bank', amount = 50000, weight = 1000, sound = 'cash'}              -- 20 $50,000
        }
    }
}
