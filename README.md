# lavie-heritage

Tổng hợp các script FiveM mình tự làm cho server Los Santos Legacy. Nay server đóng cửa nên mình share lại toàn bộ mã nguồn cho anh em cộng đồng FiveM tham khảo hoặc tiếp tục phát triển.

## Danh sách resource (33 scripts)

- **[admin]**
  - `aCore`: Admin panel, cảnh cáo (warn), phạt tù (jail), ban/unban lưu trực tiếp MySQL độc lập.
  - `legacy_turf`: Chiếm đóng zone / Turf war cho admin và các gang.
- **[combat-weapon]**
  - `weaponCore`: Dynamic recoil súng.
  - `lv_Magazine`: Hệ thống băng đạn, nạp/tháo đạn, gắn phụ kiện.
  - `V-Firingmode`: Đổi chế độ bắn (đơn, 3 viên, auto) kèm HUD NUI.
  - `lvBodyweapons`: Đeo vũ khí trên lưng và hông nhân vật.
  - `disable_target`: Tắt aim assist / lock-on mặc định của GTA V.
- **[healthcare-damage]**
  - `lavie_injury`: Chấn thương, chảy máu, sơ cứu, bế/kéo nạn nhân.
  - `lavie_bodydamages`: Sát thương theo từng bộ phận cơ thể.
  - `lavie_animdraw`: Hoạt ảnh rút súng theo kích cỡ vũ khí.
- **[vehicles]**
  - `vehicleCore`: Khóa xe, hỏng máy, tiêu hao nhiên liệu.
  - `V.VehicleDoor`: Phím tắt & menu mở từng cửa xe, cốp xe, capo.
  - `lv_rentals`: Thuê xe NPC có admin panel & log.
  - `vehicle_persist`: Giữ vị trí và thân vỏ xe OneSync không bị mất (dùng chung `op-garages v2`).
- **[police-faction]**
  - `av_alpr`: Camera quét biển số & radar tốc độ cho cảnh sát.
  - `vSpike`: Rải bàn chông chặn xe khi truy đuổi.
  - `vRadioAnimation`: Hoạt ảnh cầm bộ đàm khi nói qua pma-voice.
- **[roleplay-features]**
  - `gang_stashes`: Kho đồ bảo mật cho gang có mật mã và log.
  - `lv_status`: Thanh đói, khát, stress.
  - `lv_backpack`: Balo mở rộng ô đồ và trọng lượng cho ox_inventory.
  - `lv_idcard`: Căn cước công dân & bằng lái xe.
  - `lv_search`: Khám xét, lục soát người chơi khác.
  - `lv_tutorial`: Hướng dẫn tương tác cho người chơi mới.
  - `lavie_crosshair`: Menu chỉnh tâm ngắm.
  - `prime_status`: Hệ thống hội viên VIP Prime.
- **[economy-entertainment]**
  - `lv_dailyreward`: Điểm danh nhận thưởng hàng ngày.
  - `lv_gacha`: Vòng quay / mở hòm quà NUI.
  - `lv_investment`: NPC đầu tư cổ phần, nhận cổ tức.
  - `lv_advertising`: Bảng quảng cáo toàn thành phố.
  - `lv_musicbox`: Loa phát nhạc 3D.
- **[utilities]**
  - `connection_queue`: Hàng đợi vào server ưu tiên (Adaptive Queue).
  - `legacyWebhook`: Quản lý log Discord chống rate limit.
  - `lv_notify`: Thông báo giao diện phẳng cho client & server.

## Yêu cầu

- FXServer OneSync Infinity
- ESX Legacy (`es_extended`)
- `ox_lib`, `oxmysql`, `ox_inventory`, `ox_target`
- `pma-voice`
- `op-garages v2` (nếu dùng `vehicle_persist`)

## Cài đặt

1. Copy toàn bộ vào thư mục `resources/` của server.
2. Import các file `.sql` tương ứng (trong các folder `aCore`, `legacy_turf`, `lv_idcard`, `lv_rentals`, `prime_status`, `lv_dailyreward`, `lv_gacha`, `lv_investment`, `av_alpr`, v.v.).
3. Thêm vào `server.cfg`:

```cfg
ensure legacyWebhook
ensure lv_notify
ensure connection_queue

ensure aCore
ensure legacy_turf
ensure disable_target
ensure weaponCore
ensure lv_Magazine
ensure V-Firingmode
ensure lvBodyweapons

ensure lavie_animdraw
ensure lavie_injury
ensure lavie_bodydamages

ensure V.VehicleDoor
ensure vehicleCore
ensure lv_rentals
ensure vehicle_persist

ensure av_alpr
ensure vSpike
ensure vRadioAnimation

ensure gang_stashes
ensure lv_status
ensure lv_backpack
ensure lv_idcard
ensure lv_search
ensure lv_tutorial
ensure lavie_crosshair
ensure prime_status

ensure lv_dailyreward
ensure lv_gacha
ensure lv_investment
ensure lv_advertising
ensure lv_musicbox
```

## Ghi chú

- Toàn bộ code đã gỡ hết bot token, webhook Discord cá nhân và hook anticheat cũ.
- Giấy phép MIT: Mọi người thoải mái sử dụng hoặc chỉnh sửa tùy ý.
