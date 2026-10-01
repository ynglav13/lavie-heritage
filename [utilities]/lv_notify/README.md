# lv_notify

UI thông báo đơn giản cho client và server.

## Client

```lua
exports['lv_notify']:Notify({
    type = 'success',
    title = 'Thông báo',
    message = 'Bạn đã nhận thành công',
    duration = 4500
})
```

Rút gọn:
```lua
exports['lv_notify']:lv_notify('Thông báo nhanh', 'info', 3500, 'Hệ thống')
```

## Server

```lua
exports['lv_notify']:Notify(source, {
    type = 'success',
    title = 'Hệ thống',
    message = 'Giao dịch thành công',
    duration = 4500
})
```

Thông báo toàn server:
```lua
exports['lv_notify']:NotifyAll({
    type = 'info',
    title = 'Máy chủ',
    message = 'Thông báo toàn server'
})
```

## Types
`info`, `success`, `warning`, `error`, `police`, `ambulance`, `money`.
