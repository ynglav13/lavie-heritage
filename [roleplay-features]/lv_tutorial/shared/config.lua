Config = {}

Config.NewbieBone = 31086
Config.NewbieText = "~g~NEWBIE"
Config.NewbieDrawDistance = 25.0

Config.Marker =
{
    type = 1,
    color =
    {
        r = 59,
        g = 130,
        b = 246,
        a = 150
    },
    bounce = false,
    faceCamera = false
}

Config.Steps =
{
    [1] =
    {
        name = "Thuê Phương Tiện",
        desc = "Đến khu vực thuê phương tiện (Checkpoint) và chọn thuê một phương tiện",
        coords = vector3(-311.68, -968.17, 31.08),
        icon = "fas fa-car",
        notify = "Bạn đã hoàn thành nhiệm vụ thuê phương tiện. Hãy đi đến điểm tiếp theo",
        notifyType = "success",
        type = "action"
    },
    [2] =
    {
        name = "Mua Sim/Điện Thoại",
        desc = "Đến cửa hàng điện thoại để mua điện thoại và Sim",
        coords = vector3(-45.7825, -1034.6962, 28.4981),
        icon = "fas fa-phone",
        notify = "Đã mua điện thoại và Sim. Hãy đi đến điểm tiếp theo",
        notifyType = "success",
        type = "action"
    },
    [3] =
    {
        name = "Mua Đồ Ăn Và Thức Uống",
        desc = "Hãy đi đến cửa hàng tiện lợi và mua một ít đồ ăn và thức uống phòng thân",
        coords = vector3(25.75, -1347.02, 29.50),
        icon = "fas fa-hamburger",
        notify = "Tuyệt vời. Hãy đi đến điểm tiếp theo",
        notifyType = "success",
        type = "action"
    },
    [4] =
    {
        name = "Thi Bằng Lái",
        desc = "Đến trường lái và hoàn thành thi bằng lái (Lý thuyết & Thực hành)",
        coords = vector3(-327.06, -711.52, 32.84),
        icon = "fas fa-id-card",
        notify = "Thi bằng lái hoàn tất. Hãy đi đến điểm tiếp theo",
        notifyType = "success",
        type = "action"
    },
    [5] =
    {
        name = "Làm ID Card & Tích Hợp Bằng Lái",
        desc = "Đến sở cảnh sát (Checkpoint) để nhận ID Card và tích hợp bằng lái",
        coords = vector3(148.42, -349.49, 45.07),
        icon = "fas fa-building-shield",
        notify = "Làm giấy tờ thành công. Hãy đi đến điểm tiếp theo",
        notifyType = "success",
        type = "action"
    },
    [6] =
    {
        name = "Tham Quan Công Việc",
        desc = "Ghé thăm khu vực công việc dọn rác nơi để kiếm thêm thu nhập",
        coords = vector3(-336.98, -1531.55, 27.72),
        radius = 5.0,
        icon = "fas fa-trash",
        notify = "Đã tham quan. Hãy đi đến điểm cuối cùng",
        notifyType = "success",
        type = "checkpoint"
    },
    [7] =
    {
        name = "Bệnh Viện Pillbox",
        desc = "Đến bệnh viện tại Pillbox Hill (Checkpoint) để biết nơi chữa trị khi bị thương",
        coords = vector3(292.85, -583.69, 43.20),
        radius = 8.0,
        icon = "fas fa-hospital",
        notify = "Chúc mừng bạn đã hoàn thành hướng dẫn tân thủ",
        notifyType = "success",
        type = "checkpoint"
    }
}
