vlib = exports.legacyCore
MedicalConfig = MedicalConfig or {}

Config = {}
MedicalConfig.Injury = Config
InjuryConfig = Config

Config.Framework = 'esx'
Config.Lib = 'ox_lib'
Config.Inventory = 'ox_inventory'
Config.TriggerSecurity = 'fiveguard'

Config.Developer =
{
    Debug = false,
    Commands = false,
}

Config.Cooldown =
{
    Injury = 500,
    Dead = 600,
}

Config.RespawnMe =
{
    Fine = 5000,
    Coords = vector3(319.75, -580.89, 28.78),
    Heading = 155.16,
    Message = '~r~NHÂN VẬT CỦA BẠN ĐÃ ĐƯỢC HỒI SINH LẠI VÀ BẠN ĐÃ BỊ MẤT TOÀN BỘ TRÍ NHỚ'
}

Config.SkipEMS =
{
    Fine = 4000,
    Coords = vector3(319.75, -580.89, 28.78),
    Heading = 155.16,
    TreatmentTime = 15000,
    Message = '~r~[Skip EMS]~s~ Nhân vật bạn đang được các bác sĩ điều trị hãy chờ trong giây lát',
    FineMessage = '~s~(( Bạn đã phải trả ~g~$%s~s~ tiền viện phí ))'
}


Config.CarryDrag =
{
    Enabled = true,
    Distance = 3.0,
    BackpedalSpeed = 1.3,
    Commands =
    {
        Carry = 'carry',
        Drag = 'drag',
        Drop = 'dropbody',
    },
    Controls =
    {
        Drop = 73,
    },
    Modes =
    {
        carry =
        {
            label = 'vác',
            carrier =
            {
                dict = 'missfinale_c2mcs_1',
                anim = 'fin_c2_mcs_1_camman',
                flag = 49,
            },
            target =
            {
                dict = 'nm',
                anim = 'firemans_carry',
                flag = 33,
                attach =
                {
                    bone = 0,
                    offset = vec3(0.27, -0.02, 0.63),
                    rotation = vec3(0.5, 0.5, 180.0),
                },
            },
        },
        drag =
        {
            label = 'kéo',
            carrier =
            {
                dict = 'combat@drag_ped@',
                anim = 'injured_drag_plyr',
                intro = 'injured_pickup_back_plyr',
                introDuration = 5700,
                flag = 1,
            },
            target =
            {
                dict = 'combat@drag_ped@',
                anim = 'injured_drag_ped',
                intro = 'injured_pickup_back_ped',
                introDuration = 5700,
                flag = 33,
                attach =
                {
                    bone = 11816,
                    offset = vec3(0.0, 0.5, 0.0),
                    rotation = vec3(0.0, 0.0, 0.0),
                },
            },
        },
    },
}

Config.Webhook =
{
    BotToken = "", 
    Kill = ""
}
