Config = {}
Config.Debug = false


Config.DecayInterval = 1 * 60 * 1000 -- 1 phut / tick
Config.HungerDecay = 0.7 -- -2.5%/phut → het doi ~40 phut
Config.ThirstDecay = 0.85 -- -4.0%/phut → het khat ~25 phut
Config.SaveInterval = 1 * 60 * 1000

Config.WarnThreshold = 30 -- canh bao vang
Config.CritThreshold = 10 -- canh bao do
Config.FullThreshold = 80 -- no (buff)

Config.CritDamage = 3 -- HP mat moi lan
Config.CritDamageInterval = 30 * 1000 -- 30 giây / lần

Config.Items =
{
    ['banh_mi'] =
    {
        label = 'Bánh Mì',
        type = 'food',
        hunger = 20,
        thirst = -5,
    },
    ['burrito'] =
    {
        label = 'Burrito',
        type = 'food',
        hunger = 80,
        thirst = -25,
    },
    ['burger'] =
    {
        label = 'Hamburger',
        type = 'food',
        hunger = 70,
        thirst = -50,
    },
    ['sandwich'] =
    {
        label = 'Sandwich',
        type = 'food',
        hunger = 60,
        thirst = -50,
    },
    ['ecola'] =
    {
        label = 'eCola',
        type = 'drink',
        hunger = 0,
        thirst = 80,
    },
    ['lemon'] =
    {
        label = 'Lemon',
        type = 'drink',
        hunger = 0,
        thirst = 60,
    },
    ['nuoc_suoi'] =
    {
        label = 'Nước Suối',
        type = 'drink',
        hunger = 0,
        thirst = 30,
    },
    ['sua_tuoi'] =
    {
        label = 'Sữa Tươi Chú Dâu',
        type = 'drink',
        hunger = 15,
        thirst = 30,
    },
}

Config.Notifications =
{
    ate = function(label, hunger) return
        ('Bạn vừa ăn %s'):format(label, hunger)
    end,
    drank = function(label, thirst) return
        ('Bạn vừa uống %s'):format(label, thirst)
    end,
    hunger_warn = 'Bạn đang đói. Hãy ăn gì đó',
    hunger_crit = 'Bạn rất đói. Cơ thể đang rơi vào trạng thái suy nhược',
    thirst_warn = 'Bạn đang khát. Hãy uống nước',
    thirst_crit = 'Bạn rất khát. Cơ thể đang rơi vào trạng thái mất nước',
    well_fed = 'Bạn đang khỏe mạnh',
}

Config.SaveOnDisconnect = true   
Config.DefaultHunger = 100   
Config.DefaultThirst = 100  
Config.DefaultStress = 0
Config.DefaultAddiction = 0

Config.StressBlurThreshold = 70 -- stress tu muc nay tro len moi tinh thoi gian gay mo man hinh
Config.StressDebuffDelay = 5 * 60 -- so giay phai giu stress cao lien tuc truoc khi bi mo
Config.StressBlurInterval = 30 * 1000 -- khoang cach giua hai lan mo man hinh tinh bang ms
Config.StressBlurDuration = 5 * 1000 -- thoi gian moi lan mo man hinh tinh bang ms
Config.StressDecayDelay = 5 * 60
Config.StressDecayInterval = 1 * 60
Config.StressDecayAmount = 1 -- so diem stress giam trong moi lan

Config.AddictionDamageThreshold = 70 -- addiction tu muc nay tro len moi co trieu chung cai nghien
Config.AddictionWithdrawalDelay = 15 * 60 -- so phut khong dung chat truoc khi bat dau mat mau
Config.AddictionDamage = 2 -- so mau mat trong moi lan withdrawal
Config.AddictionDamageInterval = 60 * 1000 -- khoang cach giua hai lan mat mau tinh bang ms

Config.AddictionDecayDelay = 30 * 60 -- sau bay nhieu giay khong dung chat thi addiction bat dau giam
Config.AddictionDecayInterval = 10 * 60 -- moi bao nhieu giay se giam addiction mot lan
Config.AddictionDecayAmount = 1 -- so diem addiction giam trong moi lan
Config.AddictionTouchCooldown = 10 -- chong spam cap nhat moc dung chat tinh bang giay

Config.StressSystem =
{
    Enabled = true,
    StackMax = 3, -- Giới hạn stack tối đa 3
    StackMultiplierPerLevel = 0.02, -- Mỗi stack chỉ tăng +2% stress (1.0x -> 1.04x)
    ResetStackAfterInactive = 10, -- Sau 10 giây nghỉ ngơi sẽ reset stack về 0
    Speeding =
    {
        Enabled = true,
        MinSpeedMph = 110.0, -- 110 mph (~177 km/h) mới bắt đầu tính
        CheckIntervalMs = 12000, -- 12 giây kiểm tra 1 lần
        Chance = 10, -- 10% tỷ lệ tăng stress
        MinStress = 1,
        MaxStress = 1,
    },
    Combat =
    {
        Enabled = true,
        CheckIntervalMs = 6000, -- 6 giây kiểm tra 1 lần
        Chance = 15, -- 15% tỷ lệ tăng stress khi bắn súng
        MinStress = 1,
        MaxStress = 1,
    },
    Jobs =
    {
        Enabled = true,
        Clean =
        {
            Chance = 8, -- 8% tỷ lệ tăng stress
            MinStress = 1,
            MaxStress = 1,
        },
        Dirty =
        {
            Chance = 15, -- 15% tỷ lệ tăng stress
            MinStress = 1, -- Lượng stress
            MaxStress = 1,
        }
    }
}
