Config = {}

Config.EnableQueue = true

-- Discord Whitelist Check
Config.CheckDiscordWhitelist = true

-- Maintenance Mode Settings
Config.MaintenanceMode = false
Config.MaintenancePassword = "matkhausieumanh"
Config.AdminBypassMaintenance = true
Config.MaintenanceBypassRole = "1542150491826552893"

-- Priority Points
Config.Points =
{
    Admin = 100,
    Prime = 50,
    Normal = 0
}

Config.QueueSpeed = 1
Config.ReservedSlots = 4

-- Messages
Config.Messages =
{
    NoSteam = "Bạn chưa mở Steam. Vui lòng mở Steam trước khi tham gia máy chủ.",
    NoDiscord = "Bạn chưa mở Discord hoặc chưa liên kết Discord với FiveM. Vui lòng mở Discord app.",
    DiscordNotMatching = "Tài khoản Discord đang mở không khớp với tài khoản Discord đã được duyệt Whitelist.",
    NotWhitelisted = "Tài khoản Steam %s chưa được duyệt Whitelist. Hãy nộp đơn Whitelist tại Discord máy chủ.",
    CheckingAccount = "Đang kiểm tra thông tin tài khoản của bạn...",
    CheckingWhitelist = "Đang kiểm tra Whitelist tại Discord...",
    QueueMessage = "HÀNG CHỜ KẾT NỐI\n\nVị Trí Của Bạn: %d / %d\n\nHãy Chờ Đợi Đến Lượt",

    MaintenanceTitle = "MÁY CHỦ ĐANG BẢO TRÌ",
    MaintenanceDesc = "Vui lòng nhập mật khẩu bảo trì để tham gia máy chủ:",
    MaintenancePlaceholder = "Nhập mật khẩu tại đây...",
    MaintenanceSubmitBtn = "Xác nhận",
    MaintenanceIncorrectPass = "Mật khẩu bảo trì không chính xác!",
    MaintenanceCanceled = "Đã hủy nhập mật khẩu bảo trì."
}
