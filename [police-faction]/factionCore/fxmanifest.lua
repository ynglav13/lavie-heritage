fx_version  'adamant'
game        'gta5'
lua54       'yes'


client_scripts {
    'client.lua',
    'data/client.lua',
    'garage_client.lua',
    'receipts_client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'data/server.lua',
    'vehicles/server.lua',
    'lockers/server.lua',
    'garage_server.lua',
    'receipts_server.lua',
    'duty_log.lua'
} 

shared_scripts {    
    '@ox_lib/init.lua',
    '@es_extended/imports.lua',
    'receipts_config.lua'
}

export {
    'GetPlayerPermission',
    'ExportFactionData',
    'GetFactionData',
}

ui_page 'NUI/index_v2.html'

files {
	'NUI/index_v2.html',
	'NUI/style.css',
	'NUI/JS/jquery.min.js',
	'NUI/JS/app.js',
	'NUI/JS/general.js',
	'NUI/JS/members.js',
	'NUI/JS/rank.js',
	'NUI/JS/division.js',
	'NUI/JS/permission.js',
	'NUI/JS/select.js',
	'NUI/JS/bizSelect.js',
	'NUI/JS/bizEdit.js',
	'NUI/JS/garage.js',
	'NUI/JS/garageVehicles.js',
	'NUI/JS/locker.js',
	'NUI/JS/armory.js',
	'NUI/JS/garageSpawn.js',
	'NUI/JS/budget.js',
	'NUI/font/JosefinSans-Bold.ttf'
}
