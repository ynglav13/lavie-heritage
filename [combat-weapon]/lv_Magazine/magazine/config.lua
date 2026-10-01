return
{
    EnableNotifications = false,
    RealisticChambering = false,
    MagazineSchema = 2,
    TransactionTimeout = 5000,
    MagazineReloadTime = 400,
    WeaponReloadStartTimeout = 1000,
    WeaponReloadTimeout = 5000,
    EnableMagazineLimit = true,
    DefaultMagLimit = 3,
    PoliceMagLimit = 5,
    UseStatusLabelPrefix = false,
    PackAnimation =
    {
        dict = 'anim@cover@weapons@reloads@pistol@gadget_pistol@',
        clip = 'reload_low_left',
        flag = 49,
        fallbackDict = 'mp_common',
        fallbackClip = 'givetake1_a'
    },
    MagazineTypes =
    {
	['magazine-50ae'] =
        {
            label = 'Băng Đạn 50AE',
            model = 'w_sb_hl50e_mag1',
            ammoType = 'ammo-50',
            magSize = 9,
            image = 'magazine_50ae',
            component = 'COMPONENT_HL50E_CLIP_01'
	},
	['magazine-46mm'] =
        {
            label = 'Băng Đạn 4.6mm',
            model = 'w_sb_tmp7_mag1',
            ammoType = 'ammo-pdw',
            magSize = 30,
            image = 'magazine_pdw',
            component = 'COMPONENT_TMP7_CLIP_01'
        },
        ['magazine-9mm'] =
        {
            label = 'Băng Đạn 9mm',
            model = 'w_pi_combatpistol_mag1',
            ammoType = 'ammo-9',
            magSize = 15,
            image = 'magazine_9mm',
            component = 'COMPONENT_PISTOL_CLIP_01'
        },
        ['magazine-45'] =
        {
            label = 'Băng Đạn .45 ACP',
            model = 'w_pi_heavypistol_mag1',
            ammoType = 'ammo-45',
            magSize = 12,
            image = 'magazine_45',
            component = 'COMPONENT_HEAVYPISTOL_CLIP_01'
        },
        ['magazine-556'] =
        {
            label = 'Băng đạn 5.56mm',
            model = 'w_ar_assaultrifle_mag1',
            ammoType = 'ammo-rifle',
            magSize = 30,
            image = 'magazine_556',
            component = 'COMPONENT_CARBINERIFLE_CLIP_01'
        },
        ['magazine-762'] =
        {
            label = 'Băng Đạn 7.62mm',
            model = 'w_ar_assaultrifle_mag1',
            ammoType = 'ammo-rifle2',
            magSize = 30,
            image = 'magazine_762',
            component = 'COMPONENT_ASSAULTRIFLE_CLIP_01'
        },
        ['magazine-smg'] =
        {
            label = 'Băng Đạn 9mm SMG',
            model = 'w_sb_smg_mag1',
            ammoType = 'ammo-9',
            magSize = 30,
            image = 'magazine_smg',
            component = 'COMPONENT_SMG_CLIP_01'
        },
        ['magazine-shotgun'] =
        {
            label = 'Hộp Đạn Shotgun',
            model = 'w_sg_pumpshotgun_mag1',
            ammoType = 'ammo-shotgun',
            magSize = 8,
            image = 'magazine_shotgun',
            component = nil
        },
        ['magazine-sniper'] =
        {
            label = 'Băng Đạn 7.62mm',
            model = 'w_sr_sniperrifle_mag1',
            ammoType = 'ammo-sniper',
            magSize = 5,
            image = 'magazine_sniper',
            component = nil
        }
    },
    WeaponProfiles =
    {
	    ['WEAPON_PROSMG'] = { magType = 'magazine-smg', component = 'COMPONENT_PROSMG_CLIP_01' },
	    ['WEAPON_HL50E'] = { magType = 'magazine-50ae', component = 'COMPONENT_HL50E_CLIP_01' },
	    ['WEAPON_HLTMP7'] = { magType = 'magazine-46mm', component = 'COMPONENT_TMP7_CLIP_01' },
        ['WEAPON_ZN509'] = { magType = 'magazine-9mm', component = 'COMPONENT_ZN509_CLIP_01' },
        ['WEAPON_VF9C'] = { magType = 'magazine-9mm', component = 'COMPONENT_VF9C_CLIP_01' },
        ['WEAPON_VF17'] = { magType = 'magazine-9mm', component = 'COMPONENT_VF17_CLIP_01' },
        ['WEAPON_VF18'] = { magType = 'magazine-9mm', component = 'COMPONENT_VF18_CLIP_01' },
        ['WEAPON_TECPISTOL'] = { magType = 'magazine-9mm', component = 'COMPONENT_TECPISTOL_CLIP_01' },
        ['WEAPON_APPISTOL'] = { magType = 'magazine-9mm', component = 'COMPONENT_APPISTOL_CLIP_01' },
        ['WEAPON_CERAMICPISTOL'] = { magType = 'magazine-9mm', component = 'COMPONENT_CERAMICPISTOL_CLIP_01' },
        ['WEAPON_PISTOLXM3'] = { magType = 'magazine-9mm', component = 'COMPONENT_PISTOLXM3_CLIP_01' },
        ['WEAPON_COMBATPISTOL'] = { magType = 'magazine-9mm', component = 'COMPONENT_COMBATPISTOL_CLIP_01' },
        ['WEAPON_PISTOL'] = { magType = 'magazine-9mm', component = 'COMPONENT_PISTOL_CLIP_01' },
        ['WEAPON_PISTOL_MK2'] = { magType = 'magazine-9mm', component = 'COMPONENT_PISTOL_MK2_CLIP_01' },

        ['WEAPON_TCARBINE'] = { magType = 'magazine-556' },
        ['WEAPON_ADVANCEDRIFLE'] = { magType = 'magazine-556', component = 'COMPONENT_ADVANCEDRIFLE_CLIP_01' },
        ['WEAPON_VFCARBINE'] = { magType = 'magazine-556', component = 'w_ar_vfcarbine_mag1' },
        ['WEAPON_SPCARBINE'] = { magType = 'magazine-556', component = 'w_ar_spcarbine_mag1' },
        ['WEAPON_BULLPUPRIFLE'] = { magType = 'magazine-556', component = 'COMPONENT_BULLPUPRIFLE_CLIP_01' },
        ['WEAPON_BULLPUPRIFLE_MK2'] = { magType = 'magazine-556', component = 'COMPONENT_BULLPUPRIFLE_MK2_CLIP_01' },
        ['WEAPON_CARBINERIFLE'] = { magType = 'magazine-556', component = 'COMPONENT_CARBINERIFLE_CLIP_01' },
        ['WEAPON_CARBINERIFLE_MK2'] = { magType = 'magazine-556', component = 'COMPONENT_CARBINERIFLE_MK2_CLIP_01' },
        ['WEAPON_SPECIALCARBINE'] = { magType = 'magazine-556', component = 'COMPONENT_SPECIALCARBINE_CLIP_01' },
        ['WEAPON_SPECIALCARBINE_MK2'] = { magType = 'magazine-556', component = 'COMPONENT_SPECIALCARBINE_MK2_CLIP_01' },

        ['WEAPON_ASSAULTRIFLE'] = { magType = 'magazine-762', component = 'COMPONENT_ASSAULTRIFLE_CLIP_01' },
        ['WEAPON_ASSAULTRIFLE_MK2'] = { magType = 'magazine-762', component = 'COMPONENT_ASSAULTRIFLE_MK2_CLIP_01' }
    }
}
