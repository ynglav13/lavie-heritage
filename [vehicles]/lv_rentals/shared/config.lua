Config = {}

Config.Locale = 'vi'
Config.AdminCommand = 'rentaladmin'
Config.MemberCommand = 'rentals'
Config.StatusCommand = 'rentalstatus'

Config.DefaultMaxHours = 6
Config.HardMaxHours = 24
Config.MinHours = 1
Config.PlatePrefix = 'RENT'
Config.ServerPlateVerifyTimeoutMs = 1000
Config.PlateVerificationDebug = false
Config.CurrencyAccount = 'money'
Config.DeleteExpiredEveryMinutes = 1
Config.ExpiryWarningMinutes =
{
    10,
    5,
    1
}
Config.TargetDistance = 2.0
Config.PointRenderDistance = 60.0
Config.RentDistance = 25.0
Config.ReturnStationDistance = 18.0
Config.ReturnVehicleDistance = 8.0
Config.RecoverAtStationOnly = true

Config.ExpireForceExitDelayMs = 2500
Config.ExpiredClearTimeoutMs = 45000
Config.ExpiredExitRetryMs = 2000
Config.ExpiredMaxExitWaitMs = 30000
Config.ExpiredDeleteMaxSpeed = 1.5
Config.ExpiredExitMaxSpeed = 2.2
Config.ExpiredSlowdownStep = 0.92
Config.DeleteVehicleRetries = 8
Config.DeleteVehicleRetryDelayMs = 350

Config.Npc =
{
    enabled = true,
    model = 'a_m_y_business_03',
    scenario = 'WORLD_HUMAN_CLIPBOARD'
}

Config.Admin =
{
    UseACore = true,
    AcePermission = 'lv_rentals.admin',
    Groups =
    {
        admin = true,
        superadmin = true
    }
}

Config.Webhook =
{
    enabled = true,
    url = '',
    username = 'LV Rentals',
    avatar = ''
}

Config.DefaultStations =
{
    {
        code = 'LegionRental',
        label = 'Vehicle Rental',
        coords = vec3(215.74, -810.12, 30.73),
        heading = 157.0,
        blip = true,
        maxHours = 6,
        deposit = 250,
        spawnPoints =
        {
            vec4(229.56, -800.12, 30.57, 159.0),
            vec4(232.74, -808.02, 30.55, 159.0)
        },
        vehicles =
        {
            {
                model = 'blista',
                label = 'Blista',
                pricePerHour = 120,
                deposit = 150,
                image = ''
            },
            {
                model = 'faggio',
                label = 'Faggio',
                pricePerHour = 45,
                deposit = 50,
                image = ''
            }
        }
    }
}

Config.Text =
{
    openRental = 'Thuê Phương Tiện',
    openAdmin = 'Rental Management',
    noPermission = 'Bạn không đủ quyền hạn để có thể sử dụng lệnh này',
    invalidRequest = 'Yêu cầu không hợp lệ',
    tooFar = 'Bạn ở quá xa điểm thuê phương tiện',
    tooFarReturn = 'Bạn cần phải mang phương tiện về gần điểm thuê để trả phương tiện',
    tooFarVehicle = 'Bạn không ở gần phương tiện thuê để có thể trả',
    spawnFailed = 'Không thể tạo phương tiện hãy kiểm tra lại Model và điểm Spawn',
    vehicleNetFailed = 'Không thể đồng bộ phương tiện',
    notEnoughMoney = 'Bạn không đủ tiền để có thể thuê phương tiện',
    noSpawn = 'Không còn chỗ trống để tạo phương tiện thuê hãy thử lại sau',
    rented = 'Bạn đã thuê phương tiện thành công',
    returned = 'Bạn đã trả phương tiện thuê và nhận lại $%s tiền cọc',
    expired = 'Phương tiện thuê của bạn đã hết hạn',
    expiresSoon = '%s đang thuê sẽ hết hạn sau %s',
    activeRental = 'Phương Tiện Thuê: %s | Thời Gian Còn Lại: %s | Tiền Cọc: $%s',
    disconnectForfeit = 'Bạn đã thoát khỏi máy chủ nên phương tiện %s đang thuê sẽ bị thu hồi',
    expiredAutoReturn = 'Phương tiện %s đang thuê của bạn đã hết hạn và đã bị thu hồi',
    rentalWarning = 'Lưu Ý: Nếu bạn thoát khỏi máy chủ phương tiện sẽ bị thu hồi và không hoàn tiền cọc',
    noActiveRental = 'Bạn hiện không thuê phương tiện nào',
    alreadyRenting = 'Bạn hiện đang thuê một phương tiện và chưa được trả lại',
    stationDisabled = 'Điểm thuê phương tiện này hiện không khả dụng hãy thử lại sau',
    vehicleUnavailable = 'Phương tiện này không khả dụng tại điểm thuê'
}
