
## Client usage

```lua
exports['lv_notify']:Notify({
    type = 'success',
    title = 'Lavie',
    message = 'Bạn đã nhận thành công',
    duration = 4500
})
```

Short form:

```lua
exports['lv_notify']:lv_notify('Thông báo nhanh', 'info', 3500, 'Lavie')
```

Event fallback:

```lua
TriggerEvent('lv_notify:client:notify', {
    type = 'warning',
    message = 'Hay can than khu vuc phia truoc'
})
```

## Server usage

```lua
exports['lv_notify']:Notify(source, {
    type = 'success',
    title = 'He thong',
    message = 'Giao dich thanh cong',
    duration = 4500
})
```

Short form:

```lua
exports['lv_notify']:lv_notify(source, 'Bạn vừa nhận tiền', 'money', 4000, 'Tài chính')
```

Notify everyone:

```lua
exports['lv_notify']:NotifyAll({
    type = 'info',
    title = 'May chu',
    message = 'Thông báo toàn server'
})
```

## Types

Available by default: `info`, `success`, `warning`, `error`, `police`, `ambulance`, `money`.
