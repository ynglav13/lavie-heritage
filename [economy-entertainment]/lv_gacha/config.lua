Config = {}

Config.Command = 'gacha'
Config.Logo = 'https://i.ibb.co/Z16v0MCD/lsg.png'
Config.HistoryLimit = 30
Config.SpinCooldownMs = 1000
Config.DefaultGarage = 1
Config.CrateItem = 'gacha_crate'
Config.KeyItem = 'gacha_key'
Config.AdminMaxGive = 500
Config.AdminGiveMinLevel = 5
Config.NotifyEvent = 'lv_notify:client:notify'


Config.Log = { Enabled=true, Webhook='', Username='Gacha Logs', Title='Case Opening', ColorSuccess=16753920, ColorRare=16766720, ColorError=15158332 }

Config.Rarities = {
 common={label='Common',color='#4b8cff',rank=1}, uncommon={label='Uncommon',color='#4bf36f',rank=2},
 rare={label='Rare',color='#d946ef',rank=3}, epic={label='Epic',color='#ef4444',rank=4},
 legendary={label='Legendary',color='#f5b942',rank=5}
}

Config.Cases = {
 legacycrate = {
  label='Legacy Case', description='Bộ sưu tập Legacy với xe, vũ khí, vật phẩm và Prime.',
  inventoryIcon='knife_case.png',
  keyInventoryIcon='key.png',
  boxItem=Config.CrateItem, keyItem=Config.KeyItem, keyAmount=1, image='https://cfx-nui-ox_inventory/web/images/knife_case.png', pity={enabled=true,at=50,minimumRarity='legendary'},
  rewards={
    {id='tap_water',name='Nước x5',type='item',item='nuoc_suoi',amount=5,rarity='common',chance=20.00},
    {id='bread',name='Bánh mì x5',type='item',item='banh_mi',amount=5,rarity='common',chance=19.00},
    {id='money_70000',name='$70.000',type='item',item='money',amount=70000,rarity='common',chance=12.00},
    {id='burrito',name='Burrito',type='item',item='burrito',amount=5,rarity='common',chance=10.00},
    {id='suatuoi',name='Sữa Tươi Chú Dâu',type='item',item='sua_tuoi',amount=5,rarity='common',chance=10.00},
    {id='money_100000',name='$100.000',type='item',item='money',amount=100000,rarity='uncommon',chance=8.00},
    {id='money_150000',name='$150.000',type='item',item='money',amount=150000,rarity='uncommon',chance=5.00},
    {id='V15',name='Voucher 15%',type='item',item='v15',amount=1,rarity='uncommon',chance=5.00},
    {id='V25',name='Voucher 25%',type='item',item='v25',amount=1,rarity='rare',chance=3.00},
    {id='magazine_9mm',name='Băng đạn 9mm',type='magazine',magType='magazine-9mm',amount=1,image='https://cfx-nui-ox_inventory/web/images/magazine_9mm.png',rarity='rare',chance=3.00},
    {id='vehicleboxa_crate',name='Vehicle Box A',type='crate',caseId='vehicleboxa',amount=1,rarity='legendary',chance=1.00},
    {id='prime7',name='Prime 7 ngày',type='prime',days=7,rarity='rare',chance=2.00},
    {id='prime30',name='Prime 30 ngày',type='prime',days=30,rarity='epic',chance=0.70},
    {id='VF17',name='VF17',type='item',item='WEAPON_VF17',amount=1,rarity='epic',chance=0.80},
    {id='dominator',name='Dominator ASP',type='vehicle',model='dominator7',image='https://docs-backend.fivem.net/vehicles/dominator7.webp',rarity='legendary',chance=0.50},
  }
 },
 vehicleboxa = {
  label='Vehicle Box A', description='Bộ sưu tập xe Muscle.',
  inventoryIcon='knife_case.png',
  keyInventoryIcon='key.png',
  boxItem=Config.CrateItem, keyItem=Config.KeyItem, keyAmount=1, image='https://cfx-nui-ox_inventory/web/images/knife_case.png', pity={enabled=true,at=40,minimumRarity='legendary'},
  rewards={
    {id='blade',name='Blade',type='vehicle',model='blade',image='https://docs-backend.fivem.net/vehicles/blade.webp',rarity='common',chance=10.0},
    {id='buccaneer',name='Buccaneer',type='vehicle',model='buccaneer',image='https://docs-backend.fivem.net/vehicles/buccaneer.webp',rarity='common',chance=10.0},
    {id='chino',name='Chino',type='vehicle',model='chino',image='https://docs-backend.fivem.net/vehicles/chino.webp',rarity='common',chance=10.0},
    {id='dukes',name='Dukes',type='vehicle',model='dukes',image='https://docs-backend.fivem.net/vehicles/dukes.webp',rarity='common',chance=10.0},
    {id='phoenix',name='Phoenix',type='vehicle',model='phoenix',image='https://docs-backend.fivem.net/vehicles/phoenix.webp',rarity='common',chance=10.0},
    {id='ruiner',name='Ruiner',type='vehicle',model='ruiner',image='https://docs-backend.fivem.net/vehicles/ruiner.webp',rarity='common',chance=10.0},
    {id='moonbeam2',name='Moonbeam Custom',type='vehicle',model='moonbeam2',image='https://docs-backend.fivem.net/vehicles/moonbeam2.webp',rarity='uncommon',chance=7.00},
    {id='deviant',name='Deviant',type='vehicle',model='deviant',image='https://docs-backend.fivem.net/vehicles/deviant.webp',rarity='uncommon',chance=7.00},
    {id='gauntlet',name='Gauntlet',type='vehicle',model='gauntlet',image='https://docs-backend.fivem.net/vehicles/gauntlet.webp',rarity='uncommon',chance=7.00},
    {id='dominatorgtt',name='Dominator GTT',type='vehicle',model='dominator8',image='https://docs-backend.fivem.net/vehicles/dominator8.webp',rarity='rare',chance=4.50},
    {id='vigerozx',name='Vigero ZX',type='vehicle',model='vigero2',image='https://docs-backend.fivem.net/vehicles/vigero2.webp',rarity='rare',chance=4.50},
    {id='money_1000000',name='$1.000.000',type='item',item='money',amount=1000000,rarity='rare',chance=3.50},
    {id='gauntlethellfire',name='Gauntlet Hellfire',type='vehicle',model='gauntlet4',image='https://docs-backend.fivem.net/vehicles/gauntlet4.webp',rarity='epic',chance=2.75},
    {id='money_2000000',name='$2.000.000',type='item',item='money',amount=2000000,rarity='epic',chance=2.75},
    {id='buffaloctx',name='Buffalo CTX',type='vehicle',model='buffaloctx',image='',rarity='legendary',chance=1.00},
  }
 },
}
