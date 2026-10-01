Config = {}

Config.Enabled = true
Config.Command = 'daily'
Config.TimezoneOffsetHours = 7
Config.Inventory = 'ox_inventory'
Config.Title = 'Điểm danh hằng ngày'
Config.RequireOnlineTime = true
Config.RequiredOnlineMinutes = 60
Config.ActivityTickSeconds = 60
Config.AntiBot = {
    Enabled = true,
    StaticChallengeMinutes = 10,
    ChallengeTimeoutSeconds = 75
}
Config.Webhook = ''
Config.WebhookName = 'Daily Reward Logs'

local function GachaBox(caseId, amount, accent)
    return { label = caseId, type = 'gacha_crate', caseId = caseId, amount = amount, accent = accent }
end

Config.DailyPass = {
    Days = 30,
    Milestones = { 10, 20, 30 },

    Premium = {
        Enabled = true,
        PrimeRewardDays = { 5, 15, 20, 25 },
        Label = 'PRIME REWARDS'
    },

    Free = {
        Label = 'FREE REWARDS'
    },

    FreeRewards = {
        [1] = { label = 'Tiền mặt', type = 'money', amount = 15000, accent = 'cash' },
        [2] = { label = 'Tiền mặt', type = 'money', amount = 15000, accent = 'cash' },
        [3] = { label = 'Nước uống', type = 'item', item = 'nuoc_suoi', amount = 2, accent = 'cash' },
        [4] = { label = 'Sandwich', type = 'sandwich', amount = 2, accent = 'cash' },
        [5] = { label = 'Tiền mặt', type = 'money', amount = 15000, accent = 'cash' },
        [6] = { label = 'Tiền mặt', type = 'money', amount = 15000, accent = 'cash' },
        [7] = { label = 'Tiền mặt', type = 'money', amount = 15000, accent = 'cash' },
        [8] = { label = 'Tiền mặt', type = 'money', amount = 15000, accent = 'cash' },
        [9] = { label = 'Tiền mặt', type = 'money', amount = 15000, accent = 'cash' },
        [10] = { label = 'Đồng hồ cũ', type = 'item', item = 'old_pocket_watch', amount = 1, accent = 'gold' },
        [11] = { label = 'Tiền mặt', type = 'money', amount = 25000, accent = 'cash' },
        [12] = { label = 'Tiền mặt', type = 'money', amount = 25000, accent = 'cash' },
        [13] = { label = 'Sữa tươi chú Dâu', type = 'item', item = 'sua_tuoi', amount = 5, accent = 'cash' },
        [14] = { label = 'Tiền mặt', type = 'money', amount = 25000, accent = 'cash' },
        [15] = { label = 'Sandwich', type = 'item', item = 'sandwich', amount = 5, accent = 'cash' },
        [16] = { label = 'Tiền mặt', type = 'money', amount = 25000, accent = 'cash' },
        [17] = { label = 'Tiền mặt', type = 'money', amount = 25000, accent = 'cash' },
        [18] = { label = 'Tiền mặt', type = 'money', amount = 25000, accent = 'cash' },
        [19] = { label = 'Tiền mặt', type = 'money', amount = 25000, accent = 'cash' },
        [20] = { label = 'Thỏi vàng nguyên chất', type = 'item', item = 'goldbar', amount = 3, accent = 'gold' },
        [21] = { label = 'Tiền mặt', type = 'money', amount = 25000, accent = 'cash' },
        [22] = { label = 'Tiền mặt', type = 'money', amount = 25000, accent = 'cash' },
        [23] = { label = 'Tiền mặt', type = 'money', amount = 25000, accent = 'cash' },
        [24] = { label = 'Nước ngọt có Gas', type = 'item', item = 'ecola', amount = 5, accent = 'cash' },
        [25] = { label = 'Tiền mặt', type = 'money', amount = 25000, accent = 'cash' },
        [26] = { label = 'Burrito', type = 'item', item = 'burrito', amount = 5, accent = 'cash' },
        [27] = { label = 'Tiền mặt', type = 'money', amount = 25000, accent = 'cash' },
        [28] = { label = 'Tiền mặt', type = 'money', amount = 25000, accent = 'cash' },
        [29] = { label = 'Nước chanh có vị', type = 'item', item = 'lemon', amount = 5, accent = 'cash' },
        [30] = { label = 'Voucher giảm giá', type = 'item', item = 'v10', amount = 1, accent = 'gold' },
    },

    PrimeRewards = {
        [1] = { label = 'Prime Cash', type = 'money', amount = 25000, accent = 'cash' },
        [2] = { label = 'Prime Cash', type = 'money', amount = 25000, accent = 'cash' },
        [3] = { label = 'Kim cương', type = 'item', item = 'uncutted_diamond', amount = 3, accent = 'gold' },
        [4] = { label = 'Prime Cash', type = 'money', amount = 25000, accent = 'cash' },
        [5] = { label = 'Voucher giảm giá', type = 'money', amount = 25000, accent = 'gold' },
        [6] = { label = 'Prime Cash', type = 'money', amount = 25000, accent = 'cash' },
        [7] = { label = 'Prime Cash', type = 'money', amount = 25000, accent = 'cash' },
        [8] = { label = 'Prime Cash', type = 'money', amount = 25000, accent = 'cash' },
        [9] = { label = 'Prime Cash', type = 'money', amount = 25000, accent = 'cash' },
        [10] = { label = 'Legacy Crate', type = 'item', item = 'legacycrate', amount = 1, accent = 'gold' },
        [11] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [12] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [13] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [14] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [15] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [16] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [17] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [18] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [19] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [20] = GachaBox('legacycrate', 2, 'prime'),
        [21] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [22] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [23] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [24] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [25] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [26] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [27] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [28] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [29] = { label = 'Prime Cash', type = 'money', amount = 40000, accent = 'cash' },
        [30] = GachaBox('legacycrate', 3, 'prime')
    }
}
