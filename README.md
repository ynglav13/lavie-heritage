# Lavie Heritage (Di Sản FiveM)

[![FiveM](https://img.shields.io/badge/FiveM-FXServer-f40552?style=flat-square)](https://fivem.net/)
[![Framework](https://img.shields.io/badge/Framework-ESX%20Legacy-2f80ed?style=flat-square)](https://github.com/esx-framework/esx_core)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Author](https://img.shields.io/badge/Author-Lavie-blueviolet?style=flat-square)](https://github.com/lavie2k)

Bộ sưu tập mã nguồn 33 FiveM resources hoàn chỉnh do **Lavie** phát triển cho máy chủ **Los Santos Legacy**, nay được chính thức đóng góp hoàn toàn miễn phí cho cộng đồng FiveM mã nguồn mở dưới tên **Lavie Heritage**.

> *"Hôm nay tôi chính thức đóng cửa server và dành tặng toàn bộ mã nguồn do chính tay tôi viết lại cho cộng đồng FiveM như một món quà và một di sản gửi gắm lại."* — **Lavie**

Toàn bộ mã nguồn đã được **làm sạch 100%**:
- Loại bỏ toàn bộ hook/mã nhúng của Anticheat cũ (`@rac`).
- Làm sạch toàn bộ Discord Webhook cá nhân, Bot Token, và cấu hình nhạy cảm.
- Tổ chức lại theo từng nhóm chuyên biệt chuẩn FiveM `[category]`.

---

## Danh Mục Tài Nguyên (33 Resources)

### 1. Quản Trị & Sự Kiện (`[admin]`)
* **`aCore`**: Hệ thống Admin Core toàn diện — quản trị người chơi, phân quyền, cảnh cáo (warn), phạt tù (jail), và **hệ thống ban/unban độc lập lưu trữ trực tiếp trên database MySQL/MariaDB**.
* **`legacy_turf`**: Hệ thống quản lý zone chiếm đóng / Turf war cho admin và các băng đảng sự kiện (server-authoritative).

### 2. Vũ Khí & Combat (`[combat-weapon]`)
* **`weaponCore`**: Hệ thống độ giật súng động (dynamic recoil) & tối ưu hóa cơ chế bắn súng.
* **`lv_Magazine`**: Hệ thống băng đạn chân thực — nạp đạn, tháo đạn, quản lý độ bền băng đạn, gắn phụ kiện vũ khí.
* **`V-Firingmode`**: Chuyển đổi chế độ bắn (Bắn phát một, 3 viên burst, hoặc sấy tự động) kèm giao diện HUD NUI trực quan.
* **`lvBodyweapons`**: Hiển thị vũ khí trên lưng và hông nhân vật theo kích thước thực tế.
* **`disable_target`**: Vô hiệu hóa tính năng tự động khóa mục tiêu (aim assist/lock-on) mặc định của GTA V.

### 3. Y Tế & Sát Thương (`[healthcare-damage]`)
* **`lavie_injury`**: Hệ thống chấn thương nâng cao — chảy máu, sơ cứu, bế vác/kéo lê nạn nhân, chẩn đoán vùng bị bắn.
* **`lavie_bodydamages`**: Theo dõi và áp dụng hiệu ứng tổn thương riêng biệt cho từng bộ phận cơ thể (đầu, ngực, tay, chân).
* **`lavie_animdraw`**: Hoạt ảnh rút súng chân thực theo từng kích cỡ vũ khí (súng ngắn, súng trường, shotgun).

### 4. Phương Tiện (`[vehicles]`)
* **`vehicleCore`**: Hệ thống điều phối phương tiện — quản lý khóa xe, hư hỏng động cơ, tiêu hao nhiên liệu & trạng thái máy.
* **`V.VehicleDoor`**: Phím tắt & menu đóng/mở từng cánh cửa, cốp xe, nắp capo.
* **`lv_rentals`**: Hệ thống thuê phương tiện NPC linh hoạt kèm giao diện Admin Panel & ghi log.
* **`vehicle_persist`**: **LƯU Ý: Resource này thiết kế để hoạt động tương thích với `op-garages v2`**. Hệ thống lưu vết vị trí, biến dạng thân vỏ (deformation) và trạng thái xe OneSync giúp xe không bị biến mất đột ngột.

### 5. Cảnh Sát & Tổ Chức (`[police-faction]`)
* **`av_alpr`**: Hệ thống camera quét biển số tự động & radar đo tốc độ dành cho xe tuần tra cảnh sát.
* **`vSpike`**: Hệ thống rải bàn chông (spike strip) chặn bắt xe vi phạm khi truy đuổi.
* **`vRadioAnimation`**: Hoạt ảnh cầm bộ đàm chân thực khi nói chuyện qua pma-voice.

### 6. Tính Năng Roleplay (`[roleplay-features]`)
* **`gang_stashes`**: Kho chứa đồ bảo mật cho các băng đảng với mật mã phân quyền và log chi tiết.
* **`lv_status`**: Thanh trạng thái nhân vật: Đói, Khát, Stress kèm hiệu ứng rung lắc / chóng mặt khi stress cao.
* **`lv_backpack`**: Hệ thống vật phẩm balo mở rộng thêm slot chứa đồ và trọng lượng cho `ox_inventory`.
* **`lv_idcard`**: Giao diện thẻ Căn cước công dân & Giấy phép lái xe đẹp mắt với font chữ ký.
* **`lv_search`**: Cơ chế khám xét và lục soát đồ người chơi khác với animation tương tác.
* **`lv_tutorial`**: Hướng dẫn tân thủ tương tác từng bước cho người chơi mới tham gia máy chủ.
* **`lavie_crosshair`**: Menu tùy biến tâm ngắm bắn súng cho người chơi.
* **`prime_status`**: Hệ thống tài khoản hội viên Prime VIP với danh hiệu, quyền lợi và đồng bộ Role Discord.

### 7. Kinh Tế & Giải Trí (`[economy-entertainment]`)
* **`lv_dailyreward`**: Hệ thống điểm danh nhận thưởng hàng ngày theo chuỗi liên tục (daily login streak).
* **`lv_gacha`**: Vòng quay may mắn / mở hòm nhận quà với giao diện hiệu ứng động NUI.
* **`lv_investment`**: NPC đầu tư tài chính, mua cổ phần và nhận cổ tức theo chu kỳ.
* **`lv_advertising`**: Đặt bảng quảng cáo hiển thị thông điệp trên toàn thành phố.
* **`lv_musicbox`**: Thùng loa / boombox di động phát nhạc đồng bộ âm thanh không gian 3D.

### 8. Tiện Ích Độc Lập (`[utilities]`)
* **`connection_queue`**: Hệ thống hàng đợi vào server ưu tiên (Adaptive Queue & Whitelist).
* **`legacyWebhook`**: Quản lý hàng đợi ghi log Discord tập trung, chống quá tải rate limit và batching tối ưu.
* **`lv_notify`**: Hệ thống thông báo giao diện phẳng hiện đại, mượt mà cho cả Client & Server.

---

## Yêu Cầu Nền Tảng (Prerequisites)

Để các resource hoạt động ổn định nhất, máy chủ FiveM cần có:
- **FXServer Artifacts**: Khuyến nghị phiên bản mới nhất hỗ trợ OneSync Infinity.
- **ESX Legacy**: `es_extended`
- **Overextended Suite**:
  - `ox_lib`
  - `oxmysql`
  - `ox_inventory`
  - `ox_target` (cho các resource tương tác NPC/Target)
- **Voice**: `pma-voice` (dành cho `vRadioAnimation`)
- **Garage**: `op-garages` phiên bản **V2** (dành cho `vehicle_persist`)

---

## Hướng Dẫn Cài Đặt

### 1. Cài đặt vào thư mục server
Clone hoặc tải repository này vào thư mục `resources/` của máy chủ FiveM:

```bash
cd /path/to/server-data/resources
git clone <repository_url> [lavie-heritage]
```

### 2. Import Database (SQL)
Thực hiện import các file SQL có trong bộ sưu tập vào cơ sở dữ liệu MySQL/MariaDB của bạn:
- `[admin]/aCore/admin_core.sql`
- `[admin]/legacy_turf/legacy_turf.sql`
- `[healthcare-damage]/lavie_injury/install.sql`
- `[healthcare-damage]/lavie_animdraw/install.sql`
- `[vehicles]/lv_rentals/sql/install.sql`
- `[roleplay-features]/lv_idcard/sql/lv_idcard.sql`
- `[roleplay-features]/lv_tutorial/sql/tutorial.sql`
- `[roleplay-features]/prime_status/install.sql`
- `[economy-entertainment]/lv_dailyreward/sql.sql`
- `[economy-entertainment]/lv_gacha/sql.sql`
- `[economy-entertainment]/lv_investment/sql/install.sql`
- `[police-faction]/av_alpr/sql/optimize.sql`

### 3. Cấu hình khởi chạy trong `server.cfg`
Thêm các nhóm resource vào `server.cfg` theo thứ tự dependency:

```cfg
# === UTILITIES ===
ensure legacyWebhook
ensure lv_notify
ensure connection_queue

# === ADMIN & COMBAT ===
ensure aCore
ensure legacy_turf
ensure disable_target
ensure weaponCore
ensure lv_Magazine
ensure V-Firingmode
ensure lvBodyweapons

# === HEALTHCARE ===
ensure lavie_animdraw
ensure lavie_injury
ensure lavie_bodydamages

# === VEHICLES ===
ensure V.VehicleDoor
ensure vehicleCore
ensure lv_rentals
ensure vehicle_persist # Chạy sau op-garages v2

# === POLICE & FACTION ===
ensure av_alpr
ensure vSpike
ensure vRadioAnimation

# === ROLEPLAY FEATURES ===
ensure gang_stashes
ensure lv_status
ensure lv_backpack
ensure lv_idcard
ensure lv_search
ensure lv_tutorial
ensure lavie_crosshair
ensure prime_status

# === ECONOMY & ENTERTAINMENT ===
ensure lv_dailyreward
ensure lv_gacha
ensure lv_investment
ensure lv_advertising
ensure lv_musicbox
```

---

## Bản Quyền & Đóng Góp (License & Credits)

- Phát hành dưới giấy phép [MIT License](LICENSE). Mọi người đều có quyền tự do sử dụng, chỉnh sửa, phát triển thêm cho server cá nhân hoặc cộng đồng.
- Tác giả: **Lavie** (Los Santos Legacy Team).
- Gửi tặng toàn bộ cộng đồng FiveM Việt Nam và Quốc tế!
