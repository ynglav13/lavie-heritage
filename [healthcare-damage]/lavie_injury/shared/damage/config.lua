MedicalConfig = MedicalConfig or {}
DamageConfig = {}
MedicalConfig.Damage = DamageConfig

DamageConfig.Framework = 'esx'
DamageConfig.Lib = 'ox_lib'

DamageConfig.Webhook =
{
	BotToken = "",
	Damage = ""
}

DamageConfig.Option =
{
	Debug = false,
	Bodydamages = true,
	HelpUp = true,
}

DamageConfig.HelpUp =
{
	Enable = DamageConfig.Option.HelpUp,
	Command = 'helpup',
}

DamageConfig.Bodydamages =
{
	Enable = DamageConfig.Option.Bodydamages,
	Command = 'damages',
}

DamageConfig.Runtime =
{
	DamageFlushInterval = 1000,
	DamageLoadTimeout = 5000,
	DamageViewDistance = 20.5,
	DamageRateWindow = 5000,
	DamageRateLimit = 300,
}

DamageConfig.ReduceDamage =
{
	Enable = true,
	Clothes =
	{
		HelmetIndex =
		{
			226,
			227,
			287,
			288,
			256,
			257,
			260,
			261,
			265,
			266
		}
	},
	HelmetDamageReducer = 0.5,
	minRange = 5.0,
	maxRange = 150.0,
	minDamage = 5,
	GunExplosiveArmourDamageRate = 0.80,
	MeleeArmourDamageRate = 0.90,
}

DamageConfig.Fallback =
{
	['Ammo Pistol'] = 0.005,
	['Đạn Súng Lục'] = 0.005,
	['Ammo Shotgun'] = 0.03,
	['Đạn Shotgun'] = 0.03,
	['Ammo SMG'] = 0.005,
	['Đạn Tiểu Liên'] = 0.005,
	['Ammo Rifle'] = 0.002,
	['Đạn Súng Trường'] = 0.002,
	['Ammo Sniper'] = 0.0,
	['Đạn Súng Nhắm'] = 0.0,
	['Đạn Súng Sơn'] = 0.005,
}

DamageConfig.Bodypart =
{
	['head'] =
	{
		39317,
		31086,
		12844,
		65068,
		58331,
		45750,
		25260,
		21550,
		29868,
		1356,
		43536,
		27474,
		19336,
		11174,
		37193,
		20178,
		61839,
		20279,
		17719,
		46240,
		17188,
		20623,
		47419,
		49979,
		47495,
		35731
	},
	['torso'] =
	{
		11816,
		57597,
		23553,
		24816,
		24817,
		24818,
		64729,
		10706,
		56604
	},
	['hand']  =
	{
		45509,
		61163,
		18905,
		26610,
		4089,
		4090,
		26611,
		4169,
		4170,
		26612,
		4185,
		4186,
		26613,
		4137,
		4138,
		26614,
		4153,
		4154,
		60309,
		36029,
		61007,
		5232,
		22711,
		40269,
		28252,
		57005,
		58866,
		64016,
		64017,
		58867,
		64096,
		64097,
		58868,
		64112,
		64113,
		58869,
		64064,
		64065,
		58870,
		64080,
		64081,
		28422,
		6286,
		43810,
		37119,
		2992
	},
	['leg']  =
	{
		58271,
		63931,
		14201,
		2108,
		65245,
		57717,
		46078,
		51826,
		36864,
		52301,
		20781,
		35502,
		24806,
		16335,
		23639,
		6442
	}
}

DamageConfig.ExtendedBodypart =
{
	['Xương Chậu'] = 11816,
	['Đùi Trái'] = 58271,
	['Bắp Chân Trái'] = 63931,
	['Chân Trái'] = 14201,
	['Ngón Chân Trái'] = 2108,
	['Chân Trái (IK)'] = 65245,
	['Chân Trái (PH)'] = 57717,
	['Đầu Gối Trái (MH)'] = 46078,
	['Đùi Phải'] = 51826,
	['Bắp Chân Phải'] = 36864,
	['Chân Phải'] = 52301,
	['Ngón Chân Phải'] = 20781,
	['Chân Phải (IK)'] = 35502,
	['Chân Phải (PH)'] = 24806,
	['Đầu Gối Phải (MH)'] = 16335,
	['Phía Sau Đùi Trái'] = 23639,
	['Phía Sau Đùi Phải'] = 6442,
	['Cột Sống'] = 57597,
	['Cột Sống (#0)'] = 23553,
	['Thân (#1)'] = 24816,
	['Lưng'] = 24817,
	['Thân (#2)'] = 24818,
	['Xương Quai Xanh Bên Trái'] = 64729,
	['Bắp Tay Trái Gần Vai'] = 45509,
	['Cánh Tay Trái'] = 61163,
	['Tay Trái'] = 18905,
	['Ngón Tay Trái (#0)'] = 26610,
	['Ngón Tay Trái (#1)'] = 4089,
	['Ngón Tay Trái (#2)'] = 4090,
	['Ngón Tay Trái (#10)'] = 26611,
	['Ngón Tay Trái (#11)'] = 4169,
	['Ngón Tay Trái (#12)'] = 4170,
	['Ngón Tay Trái (#20)'] = 26612,
	['Ngón Tay Trái (#21)'] = 4185,
	['Ngón Tay Trái (#22)'] = 4186,
	['Ngón Tay Trái (#30)'] = 26613,
	['Ngón Tay Trái (#31)'] = 4137,
	['Ngón Tay Trái (#32)'] = 4138,
	['Ngón Tay Trái (#40)'] = 26614,
	['Ngón Tay Trái (#41)'] = 4153,
	['Ngón Tay Trái (#42)'] = 4154,
	['Tay Trái (PH)'] = 60309,
	['Tay Trái (IK)'] = 36029,
	['Mặt Sau Cánh Tay Trái'] = 61007,
	['Mặt Sau Tay Trái'] = 5232,
	['Khuỷu Tay Trái'] = 22711,
	['Xương Quai Xanh Bên Phải'] = 10706,
	['Bắp Tay Phải Gần Vai'] = 40269,
	['Cánh Tay Phải'] = 28252,
	['Tay Phải'] = 57005,
	['Ngón'] = 58866,
	['Ngón Tay Phải (#0)'] = 64016,
	['Ngón Tay Phải (#2)'] = 64017,
	['Ngón Tay Phải (#10)'] = 58867,
	['Ngón Tay Phải (#11)'] = 64096,
	['Ngón Tay Phải (#12)'] = 64097,
	['Ngón Tay Phải (#20)'] = 58868,
	['Ngón Tay Phải (#21)'] = 64112,
	['Ngón Tay Phải (#22)'] = 64113,
	['Ngón Tay Phải (#30)'] = 58869,
	['Ngón Tay Phải (#31)'] = 64064,
	['Ngón Tay Phải (#32)'] = 64065,
	['Ngón Tay Phải (#40)'] = 58870,
	['Ngón Tay Phải (#41)'] = 64080,
	['Ngón Tay Phải (#42)'] = 64081,
	['Tay Phải (PH)'] = 28422,
	['Tay Phải (IK)'] = 6286,
	['Mặt Sau Cánh Tay Phải'] = 43810,
	['Mặt Sau Tay Phải'] = 37119,
	['Khuỷu Tay Phải'] = 2992,
	['Cổ'] = 39317,
	['Đầu'] = 31086,
	['Đầu (IK)'] = 12844,
	['Mặt'] = 65068,
	['Chân Mày Trái'] = 58331,
	['Mí Mắt Trái'] = 45750,
	['Mắt Trái'] = 25260,
	['Má Trái'] = 21550,
	['Mí Môi Trái'] = 29868,
	['Chân Mày Phải'] = 1356,
	['Mí Mắt Phải'] = 43536,
	['Mắt Phải'] = 27474,
	['Má Phải'] = 19336,
	['Mí Môi Phải'] = 11174,
	['Giữa Chân Mày'] = 37193,
	['Nhân Trung (Dưới Mũi)'] = 20178,
	['Môi Trên'] = 61839,
	['Môi Trên Bên Trái'] = 20279,
	['Môi Trên Bên Phải'] = 17719,
	['Hàm'] = 46240,
	['Cằm'] = 17188,
	['Môi Dưới'] = 20623,
	['Môi Dưới Bên Trái'] = 47419,
	['Môi Dưới Bên Phải'] = 49979,
	['Lưỡi'] = 47495,
	['Gáy Cổ'] = 35731,
	['Toàn Thân'] = 56604,
}

DamageConfig.WeaponDefault =
{
	['WEAPON_UNARMED'] = 0.01,
	['WEAPON_SNOWBALL'] = 0.01,
	['WEAPON_FLASHLIGHT'] = 0.01,
	['WEAPON_KNIFE'] = 0.01,
	['WEAPON_KNUCKLE'] = 0.01,
	['WEAPON_NIGHTSTICK'] = 0.01,
	['WEAPON_COLBATON'] = 0.01,
	['WEAPON_STUNGUN'] = 0.01,
	['WEAPON_STUNGUN_MP'] = 0.01,
	['WEAPON_HAMMER'] = 0.01,
	['WEAPON_BAT'] = 0.01,
	['WEAPON_GOLFCLUB'] = 0.01,
	['WEAPON_CROWBAR'] = 0.01,
	['WEAPON_BOTTLE'] = 0.01,
	['WEAPON_DAGGER'] = 0.01,
	['WEAPON_HATCHET'] = 0.01,
	['WEAPON_MACHETE'] = 0.01,
	['WEAPON_SWITCHBLADE'] = 0.01,
	['WEAPON_PROXMINE'] = 0.01,
	['WEAPON_BZGAS'] = 0.01,
	['WEAPON_SMOKEGRENADE'] = 0.01,
	['WEAPON_MOLOTOV'] = 0.01,
	['WEAPON_REVOLVER'] = 0.01,
	['WEAPON_POOLCUE'] = 0.01,
	['WEAPON_PIPEWRENCH'] = 0.01,
	['WEAPON_PISTOL'] = 0.01,
	['WEAPON_PISTOL_MK2'] = 0.01,
	['WEAPON_COMBATPISTOL'] = 0.01,
	['WEAPON_APPISTOL'] = 0.01,
	['WEAPON_PISTOL50'] = 0.01,
	['WEAPON_SNSPISTOL'] = 0.01,
	['WEAPON_HEAVYPISTOL'] = 0.01,
	['WEAPON_VINTAGEPISTOL'] = 0.01,
	['WEAPON_FLAREGUN'] = 0.01,
	['WEAPON_MARKSMANPISTOL'] = 0.01,
	['WEAPON_MICROSMG'] = 0.01,
	['WEAPON_MINISMG'] = 0.01,
	['WEAPON_SMG'] = 0.01,
	['WEAPON_SMG_MK2'] = 0.01,
	['WEAPON_ASSAULTSMG'] = 0.01,
	['WEAPON_MG'] = 0.01,
	['WEAPON_COMBATMG'] = 0.01,
	['WEAPON_COMBATMG_MK2'] = 0.01,
	['WEAPON_COMBATPDW'] = 0.01,
	['WEAPON_SAWNOFFSHOTGUN'] = 0.01,
	['WEAPON_PUMPSHOTGUN'] = 0.01,
	['WEAPON_TEC9'] = 0.01,
	['WEAPON_ACIDPACKAGE'] = 0.01,
	['WEAPON_RAMMED_BY_CAR'] = 0.2,
	['WEAPON_RUN_OVER_BY_CAR'] = 0.2,
	['WEAPON_VEHICLE_CRASH'] = 0.2,
	['WEAPON_ASSAULTRIFLE'] = 0.01,
	['WEAPON_ASSAULTRIFLE_MK2'] = 0.01,
	['WEAPON_CARBINERIFLE'] = 0.01,
	['WEAPON_AR15'] = 0.01,
	['WEAPON_HK416'] = 0.01,
	['WEAPON_VFCARBINE'] = 0.01,
	['WEAPON_SPCARBINE'] = 0.01,
	['WEAPON_CARBINERIFLE_MK2'] = 0.01,
	['WEAPON_COMPACTRIFLE'] = 0.01,
	['WEAPON_ADVANCEDRIFLE'] = 0.01,
	['WEAPON_SPECIALCARBINE'] = 0.01,
	['WEAPON_SPECIALCARBINE_MK2'] = 0.01,
	['WEAPON_BULLPUPRIFLE'] = 0.01,
	['WEAPON_BULLPUPRIFLE_MK2'] = 0.01,
	['WEAPON_SNIPERRIFLE'] = 0.01,
	['WEAPON_HEAVYSNIPER'] = 0.01,
	['WEAPON_HEAVYSNIPER_MK2'] = 0.01,
	['WEAPON_MARKSMANRIFLE'] = 0.01,
	['WEAPON_MARKSMANRIFLE_MK2'] = 0.01,
}

DamageConfig.WeaponAddon =
{
	['WEAPON_ZN509'] = 0.01,
	['WEAPON_VF9C'] = 0.01,
	['WEAPON_VF17'] = 0.01,
	['WEAPON_VF18'] = 0.01,
	['WEAPON_TCARBINE'] = 0.01,
	['WEAPON_BEANBAG'] = 0.01,
	['WEAPON_YBEANBAG'] = 0.01,
	['WEAPON_LESSLAUNCHER'] = 0.01,
	['WEAPON_YLESSLAUNCHER'] = 0.01,
	['WEAPON_BATTLERIFLE'] = 0.01,
	['WEAPON_TECPISTOL'] = 0.01,
	['WEAPON_SNOWLAUNCHER'] = 0.01,
	['WEAPON_Y2'] = 0.01,
	['WEAPON_C9'] = 0.01,
	['WEAPON_M870_SHOTGUN'] = 0.01,
	['WEAPON_870SO_SHOTGUN'] = 0.01,
	['WEAPON_PROSMG'] = 0.01,
	['WEAPON_HL50E'] = 0.01,
	[`WEAPON_ZN509`] = 0.01,
	['WEAPON_HLTMP7'] = 0.01,
	[`WEAPON_HLCP`] = 0.01,
}

DamageConfig.WeaponDamages =
{
	[`WEAPON_RAMMED_BY_CAR`] =
	{
		['name'] = 'Tông Bởi Phương Tiện'
	},
	[`WEAPON_EXHAUSTION`] =
	{
		['name'] = 'Kiệt Sức (Đói/Khát)'
	},
	[`WEAPON_BLEEDING`] =
	{
		['name'] = 'Mất Máu'
	},
	[-1553120962] =
	{
		['name'] = 'Tông Bởi Phương Tiện'
	},
	[2741846334] =
	{
		['name'] = 'Tông Bởi Phương Tiện'
	},
	[`WEAPON_VEHICLE_CRASH`] =
	{
		['name'] = 'Chấn thương khi điều khiển phương tiện'
	},
	[`WEAPON_FALL`] =
	{
		['name'] = 'Té/Ngã'
	},
	[`WEAPON_ELECTRIC_FENCE`] =
	{
		['name'] = 'Giật Điện'
	},
	[`WEAPON_DROWNING_IN_VEHICLE`] =
	{
		['name'] = 'Chết Đuối'
	},
	[`WEAPON_DROWNING`] =
	{
		['name'] = 'Chết Đuối'
	},
	[`WEAPON_HIT_BY_WATER_CANNON`] =
	{
		['name'] = 'Vòi Rồng'
	},
	[`WEAPON_EXPLOSION`] =
	{
		['name'] = 'Vụ Nổ'
	},
	[`WEAPON_FIRE`] =
	{
		['name'] = 'Vụ Cháy'
	},
	[`WEAPON_MOLOTOV`] =
	{
		['name'] = 'Bom Xăng'
	},
	[`WEAPON_SMOKEGRENADE`] =
	{
		['name'] = 'Ngạt Khói'
	},
	[`WEAPON_BZGAS`] =
	{
		['name'] = 'Ngạt Khói Độc'
	},
	[`WEAPON_ANIMAL`] =
	{
		['name'] = 'Cắn'
	},

	[`WEAPON_STUNGUN`] =
	{
		['name'] = 'Súng Điện Taser',
		['head'] = 0,
		['torso'] = 0,
		['hand'] = 0,
		['leg'] = 0
	},
	[`WEAPON_STUNGUN_MP`] =
	{
		['name'] = 'Súng Điện Taser',
		['head'] = 0,
		['torso'] = 0,
		['hand'] = 0,
		['leg'] = 0
	},
	[`WEAPON_Y2`] =
	{
		['name'] = 'Súng Điện Taser Y2',
		['head'] = 0,
		['torso'] = 0,
		['hand'] = 0,
		['leg'] = 0
	},
	[`WEAPON_ACIDPACKAGE`] =
	{
		['name'] = 'Báo',
		['head'] = 0,
		['torso'] = 0,
		['hand'] = 0,
		['leg'] = 0
	},
	[`WEAPON_C9`] =
	{
		['name'] = 'Súng Điện C9',
		['head'] = 10,
		['torso'] = 10,
		['hand'] = 10,
		['leg'] = 10
	},
	[`WEAPON_BEANBAG`] =
	{
		['name'] = 'Súng Beanbag',
		['head'] = 5,
		['torso'] = 5,
		['hand'] = 5,
		['leg'] = 5
	},
	[`WEAPON_YBEANBAG`] =
	{
		['name'] = 'Súng Beanbag',
		['head'] = 5,
		['torso'] = 5,
		['hand'] = 5,
		['leg'] = 5
	},
	[`WEAPON_LESSLAUNCHER`] =
	{
		['name'] = 'Súng 40mm',
		['head'] = 10,
		['torso'] = 5,
		['hand'] = 5,
		['leg'] = 5
	},
	[`WEAPON_YLESSLAUNCHER`] =
	{
		['name'] = 'Súng 40mm',
		['head'] = 10,
		['torso'] = 5,
		['hand'] = 5,
		['leg'] = 5
	},
	-- Melee
	[`WEAPON_UNARMED`] =
	{
		['name'] = 'Nắm Đấm',
		['head'] = 6,
		['torso'] = 4,
		['hand'] = 3,
		['leg'] = 3
	},
	[`WEAPON_FLASHLIGHT`] =
	{
		['name'] = 'Đèn Pin',
		['head'] = 15,
		['torso'] = 10,
		['hand'] = 7,
		['leg'] = 7
	},
	[`WEAPON_KNIFE`] =
	{
		['name'] = 'Dao Găm',
		['head'] = 28,
		['torso'] = 23,
		['hand'] = 18,
		['leg'] = 18
	},
	[`WEAPON_KNUCKLE`] =
	{
		['name'] = 'Nắm Đấm Gấu',
		['head'] = 12,
		['torso'] = 8,
		['hand'] = 6,
		['leg'] = 6
	},
	[`WEAPON_NIGHTSTICK`] =
	{
		['name'] = 'Gậy Baton',
		['head'] = 20,
		['torso'] = 12,
		['hand'] = 8,
		['leg'] = 8
	},
	[`WEAPON_COLBATON`] =
	{
		['name'] = 'ProLaps Telescopic Baton',
		['head'] = 20,
		['torso'] = 12,
		['hand'] = 8,
		['leg'] = 8
	},
	[`WEAPON_HAMMER`] =
	{
		['name'] = 'Búa',
		['head'] = 22,
		['torso'] = 15,
		['hand'] = 10,
		['leg'] = 10
	},
	[`WEAPON_BAT`] =
	{
		['name'] = 'Gậy Bóng Chày',
		['head'] = 20,
		['torso'] = 12,
		['hand'] = 8,
		['leg'] = 8
	},
	[`WEAPON_GOLFCLUB`] =
	{
		['name'] = 'Gậy Đánh Golf',
		['head'] = 20,
		['torso'] = 14,
		['hand'] = 8,
		['leg'] = 8
	},
	[`WEAPON_CROWBAR`] =
	{
		['name'] = 'Xà Beng',
		['head'] = 28,
		['torso'] = 20,
		['hand'] = 12,
		['leg'] = 12
	},
	[`WEAPON_BOTTLE`] =
	{
		['name'] = 'Miểng Chai',
		['head'] = 10,
		['torso'] = 8,
		['hand'] = 8,
		['leg'] = 8
	},
	[`WEAPON_DAGGER`] =
	{
		['name'] = 'Dao Găm',
		['head'] = 45,
		['torso'] = 35,
		['hand'] = 20,
		['leg'] = 20
	},
	[`WEAPON_SWITCHBLADE`] =
	{
		['name'] = 'Dao Bấm',
		['head'] = 23,
		['torso'] = 20,
		['hand'] = 18,
		['leg'] = 18
	},
	[`WEAPON_MACHETE`] =
	{
		['name'] = 'Mã Tấu',
		['head'] = 30,
		['torso'] = 25,
		['hand'] = 21,
		['leg'] = 21
	},
	[`WEAPON_KITCHENKNIFE`] =
	{
		['name'] = 'Dao Bếp',
		['head'] = 25,
		['torso'] = 22,
		['hand'] = 18,
		['leg'] = 18
	},
	[`WEAPON_BATON`] =
	{
		['name'] = 'Baton',
		['head'] = 18,
		['torso'] = 12,
		['hand'] = 8,
		['leg'] = 8
	},
	[`WEAPON_KATANA2`] =
	{
		['name'] = 'Katana',
		['head'] = 45,
		['torso'] = 30,
		['hand'] = 20,
		['leg'] = 20
	},
	[`WEAPON_CLEAVER`] =
	{
		['name'] = 'Cận Chiến',
		['head'] = 25,
		['torso'] = 15,
		['hand'] = 10,
		['leg'] = 10
	},
	-- Handguns
	[`WEAPON_VF17`] =
	{
		name = 'Đạn Súng Lục',
		head  = 43,
		torso = 32,
		hand = 25,
		leg = 25,
	},
	[`WEAPON_VF18`] =
	{
		name = 'Đạn Súng Lục',
		head  = 36,
		torso = 32,
		hand = 25,
		leg = 25,
	},
	[`WEAPON_VF9C`] =
	{
		name = 'Đạn Súng Lục',
		head  = 43,
		torso = 32,
		hand = 25,
		leg = 25,
	},
	[`WEAPON_ZN509`] =
	{
		name = 'Đạn Súng Lục',
		head  = 43,
		torso = 32,
		hand = 25,
		leg = 25,
	},
	[`WEAPON_HL50E`] =
	{
		name = 'Đạn Súng Lục',
		head  = 81,
		torso = 47,
		hand = 30,
		leg = 30,
	},
	[`WEAPON_HLCP`] =
	{
		name = 'Đạn Súng Lục',
		head  = 65,
		torso = 40,
		hand = 28,
		leg = 28,
	},
	[`WEAPON_PISTOL_MK2`] =
	{
		name = 'Đạn Súng Lục',
		head = 10,
		torso = 10,
		hand = 10,
		leg = 10,
	},

	-- Rifles
	[`WEAPON_ASSAULTRIFLE`] =
	{
		name = 'Ammo Rifle',
		head = 2,
		torso = 2,
		hand = 2,
		leg = 2
	},
	[`WEAPON_ASSAULTRIFLE_MK2`] =
	{
		name = 'Ammo Rifle',
		head = 2,
		torso = 2,
		hand = 2,
		leg = 2
	},
	[`WEAPON_TCARBINE`] =
	{
		name = 'Ammo Rifle',
		head = 70,
		torso = 35,
		hand = 30,
		leg = 30
	},
	[`WEAPON_BATTLERIFLE`] =
	{
		name = 'Ammo Rifle',
		head = 110,
		torso = 45,
		hand = 20,
		leg = 20
	},
	[`WEAPON_CARBINERIFLE`] =
	{
		name = 'Ammo Rifle',
		head = 2,
		torso = 2,
		hand = 2,
		leg = 2
	},
	[`WEAPON_AR15`] =
	{
		name = 'AR-15 Rifle',
		head = 70,
		torso = 35,
		hand = 30,
		leg = 30
	},
	[`WEAPON_HK416`] =
	{
		name = 'HK416 Rifle',
		head = 70,
		torso = 35,
		hand = 30,
		leg = 30
	},
	[`WEAPON_VFCARBINE`] =
	{
		name = 'Vom Feuer Carbine',
		head = 70,
		torso = 35,
		hand = 30,
		leg = 30
	},
	[`WEAPON_SPCARBINE`] =
	{
		name = 'Vom Feuer Special Carbine',
		head = 70,
		torso = 35,
		hand = 30,
		leg = 30
	},
	[`WEAPON_CARBINERIFLE_MK2`] =
	{
		name = 'Ammo Rifle',
		head = 2,
		torso = 2,
		hand = 2,
		leg = 2
	},
	[`WEAPON_COMPACTRIFLE`] =
	{
		name = 'Ammo Rifle',
		head = 40,
		torso = 28,
		hand = 20,
		leg = 20
	},
	[`WEAPON_ADVANCEDRIFLE`] =
	{
		name = 'Ammo Rifle',
		head = 2,
		torso = 2,
		hand = 2,
		leg = 2
	},
	[`WEAPON_SPECIALCARBINE`] =
	{
		name = 'Ammo Rifle',
		head = 2,
		torso = 2,
		hand = 2,
		leg = 2
	},
	[`WEAPON_SPECIALCARBINE_MK2`] =
	{
		name = 'Ammo Rifle',
		head = 2,
		torso = 2,
		hand = 2,
		leg = 2
	},
	[`WEAPON_BULLPUPRIFLE`] =
	{
		name = 'Ammo Rifle',
		head = 2,
		torso = 2,
		hand = 2,
		leg = 2
	},
	[`WEAPON_BULLPUPRIFLE_MK2`] =
	{
		name = 'Ammo Rifle',
		head = 2,
		torso = 2,
		hand = 2,
		leg = 2
	},
	[`WEAPON_SNIPERRIFLE`] =
	{
		name = 'Ammo Rifle',
		head = 50,
		torso = 30,
		hand = 30,
		leg = 30
	},
	[`WEAPON_HEAVYSNIPER`] =
	{
		name = 'Ammo Rifle',
		head = 150,
		torso = 150,
		hand = 150,
		leg = 150
	},
	[`WEAPON_HEAVYSNIPER_MK2`] =
	{
		name = 'Ammo Rifle',
		head = 2,
		torso = 2,
		hand = 2,
		leg = 2
	},
	[`WEAPON_MARKSMANRIFLE`] =
	{
		name = 'Ammo Rifle',
		head = 2,
		torso = 2,
		hand = 2,
		leg = 2
	},
	[`WEAPON_MARKSMANRIFLE_MK2`] =
	{
		name = 'Ammo Rifle',
		head = 2,
		torso = 2,
		hand = 2,
		leg = 2
	},
	-- Shotguns
	[`WEAPON_M870_SHOTGUN`] =
	{
		name = 'Ammo Shotgun',
		head = 80,
		torso = 45,
		hand = 15,
		leg = 25
	},
	[`WEAPON_870SO_SHOTGUN`] =
	{
		name = 'Ammo Shotgun',
		head = 80,
		torso = 45,
		hand = 15,
		leg = 25
	},
	[`WEAPON_MB500`] =
	{
		name = 'Ammo Shotgun',
		head = 120,
		torso = 45,
		hand = 15,
		leg = 15
	},
	[`WEAPON_MB590`] =
	{
		name = 'Ammo Shotgun',
		head = 120,
		torso = 45,
		hand = 15,
		leg = 15
	},
	[`WEAPON_RMT590`] =
	{
		name = 'Ammo Shotgun',
		head = 120,
		torso = 45,
		hand = 15,
		leg = 15
	},
	[`WEAPON_PUMPSHOTGUN`] =
	{
		name = 'Ammo Shotgun',
		head = 120,
		torso = 45,
		hand = 15,
		leg = 15
	},
	[`WEAPON_PUMPSHOTGUN_MK2`] =
	{
		name = 'Ammo Shotgun',
		head = 120,
		torso = 45,
		hand = 15,
		leg = 15
	},
	[`WEAPON_SAWNOFFSHOTGUN`] =
	{
		name = 'Ammo Shotgun',
		head = 120,
		torso = 45,
		hand = 15,
		leg = 15
	},
	[`WEAPON_ASSAULTSHOTGUN`] =
	{
		name = 'Ammo Shotgun',
		head = 120,
		torso = 45,
		hand = 15,
		leg = 15
	},
	[`WEAPON_BULLPUPSHOTGUN`] =
	{
		name = 'Ammo Shotgun',
		head = 120,
		torso = 45,
		hand = 15,
		leg = 15
	},
	[`WEAPON_HEAVYSHOTGUN`] =
	{
		name = 'Ammo Shotgun',
		head = 120,
		torso = 45,
		hand = 15,
		leg = 15
	},
	[`WEAPON_AUTOSHOTGUN`] =
	{
		name = 'Ammo Shotgun',
		head = 120,
		torso = 45,
		hand = 15,
		leg = 15
	},
	[`WEAPON_DBSHOTGUN`] =
	{
		name = 'Ammo Shotgun',
		head = 120,
		torso = 45,
		hand = 15,
		leg = 15
	},
	[`WEAPON_MUSKET`] =
	{
		name = 'Ammo Shotgun',
		head = 120,
		torso = 45,
		hand = 15,
		leg = 15
	},
	-- Machine guns
	[`WEAPON_MG`] =
	{
		name = 'Ammo Machine Guns',
		head = 110,
		torso = 40,
		hand = 15,
		leg = 15
	},
	[`WEAPON_COMBATMG`] =
	{
		name = 'Ammo Machine Guns',
		head = 110,
		torso = 40,
		hand = 15,
		leg = 15
	},
	[`WEAPON_COMBATMG_MK2`] =
	{
		name = 'Ammo Machine Guns',
		head = 110,
		torso = 40,
		hand = 15,
		leg = 15
	},
	[`WEAPON_GUSENBERG`] =
	{
		name = 'Ammo Machine Guns',
		head = 110,
		torso = 40,
		hand = 15,
		leg = 15
	},
	-- Submachine guns
	[`WEAPON_PROSMG`] =
	{
		name = 'Đạn Tiểu Liên',
		head  = 43,
		torso = 32,
		hand = 25,
		leg = 25,
	},
	[`WEAPON_SMG`] =
	{
		name = 'Ammo Rifle',
		head = 30,
		torso = 20,
		hand = 15,
		leg = 15,
	},
	[`WEAPON_HLTMP7`] =
	{
		name = 'Đạn Tiểu Liên',
		head = 45,
		torso = 35,
		hand = 25,
		leg = 25,
	},
}
