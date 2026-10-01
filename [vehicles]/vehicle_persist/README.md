# vehicle_persist (OneSync Event-Driven Persistence)

> **LƯU Ý QUAN TRỌNG / IMPORTANT NOTE:**
> Resource này được thiết kế và tối ưu hoạt động độc quyền cùng hệ thống **`op-garages v2`** (OTHERPLANET Garage V2). 
> Nếu bạn sử dụng garage khác, bạn cần tùy biến lại logic kiểm tra trạng thái lưu xe (`stored`) và lấy xe trong database `owned_vehicles`.

## Giới thiệu
`vehicle_persist` là hệ thống lưu vết trạng thái phương tiện (vị trí, biến dạng thân vỏ deformation, độ hư hại động cơ, tình trạng khóa, phụ kiện) theo cơ chế event-driven trên FiveM OneSync, giúp phương tiện không bị despawn đột ngột hoặc biến mất khi không có người lái.

## Tính năng chính
- Lưu tọa độ và hướng quay xe theo chu kỳ
- Đồng bộ biến dạng xe (`deformation_client.lua` & `deformation_shared.lua`)
- Tự động xóa xe khi chủ xe cất xe vào garage (`op-garages v2`)
- Quản lý tải / spawn xe đã lưu khi người chơi lại gần vùng tọa độ
- Tối ưu hóa OneSync server tick

## Yêu cầu (Dependencies)
- `es_extended`
- `ox_lib`
- `oxmysql`
- `op-garages` (phiên bản V2)
