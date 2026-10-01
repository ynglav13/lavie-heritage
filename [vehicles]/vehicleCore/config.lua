Config = Config or {}

Config.CrashStressEnabled = true -- Bat/tat stress khi xe va cham manh
Config.CrashStressChance = 15 -- Phan tram co hoi tang stress sau va cham (giam xuong 15%)
Config.CrashStressAmount = 1 -- So diem stress tang (giam xuong 1 diem)
Config.CrashStressClientCooldown = 15000 -- Thoi gian cho giua hai lan roll, tinh bang ms (15s)
Config.CrashStressServerCooldown = 12000 -- Cooldown server chong spam event, tinh bang ms

Config.CrashMinimumSeverity = 10.0 -- Muc giam toc toi thieu de dong bo hieu ung va cham
Config.CrashMaximumSeverity = 100.0 -- Gioi han du lieu severity client gui len server
Config.CrashMaximumVelocity = 150.0 -- Gioi han tung thanh phan velocity gui qua network
Config.CrashSyncCooldown = 1500 -- Chong lap cung mot cu va cham tren mot phuong tien
Config.CrashRecentOccupantGrace = 1000 -- Cho phep nguoi vua bi hat khoi xe van nhan crash event
Config.CrashSyncRadius = 25.0 -- Ban kinh fallback cho nguoi vua bi hat khoi xe truoc khi server nhan event

Config.CrashBlackoutThreshold = 30.0 -- Muc giam toc toi thieu de ngat tam thoi
Config.CrashBlackoutFadeOut = 350 -- Thoi gian man hinh toi dan, tinh bang ms
Config.CrashBlackoutFadeIn = 2500 -- Thoi gian man hinh hien dan, tinh bang ms
Config.CrashBlackoutMinDuration = 6000 -- Tong thoi gian ngat toi thieu tai nguong, tinh bang ms
Config.CrashBlackoutMaxDuration = 10000 -- Tong thoi gian ngat toi da khi va cham rat nang, tinh bang ms
Config.CrashSoundVolume = 0.15 -- Am luong bv.mp3 khi ngat tam thoi
