LVNotify = LVNotify or {}

LVNotify.Defaults =
{
    title = 'Lavie',
    type = 'info',
    duration = 3600,
    position = 'top-right',
    icon = nil,
    sound = false
}

LVNotify.Types =
{
    info =
    {
        title = 'Thông Báo',
        icon = 'info',
        accent = '#60a5fa'
    },
    success =
    {
        title = 'Thành Công',
        icon = 'success',
        accent = '#34d399'
    },
    warning =
    {
        title = 'Chú Ý',
        icon = 'warning',
        accent = '#fbbf24'
    },
    error =
    {
        title = 'Lỗi',
        icon = 'error',
        accent = '#fb7185'
    },
    police =
    {
        title = 'Cảnh Sát',
        icon = 'police',
        accent = '#38bdf8'
    },
    ambulance =
    {
        title = 'Y Tế',
        icon = 'ambulance',
        accent = '#f87171'
    },
    money =
    {
        title = 'Tài Chính',
        icon = 'money',
        accent = '#4ade80'
    }
}

LVNotify.MaxVisible = 4
LVNotify.DebugCommand = true
