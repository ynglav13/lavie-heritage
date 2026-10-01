fx_version 'cerulean'
game 'gta5'

version '1.0.0'

lua54 'yes'

ui_page 'web/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_script 'client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

files {
    'web/index.html',
    'web/style.css',
    'web/app.js'
}

dependencies {
    'es_extended',
    'ox_inventory',
    'oxmysql',
    'legacyWebhook',
    'aCore',
    'prime_status',
    'lv_Magazine'
}
