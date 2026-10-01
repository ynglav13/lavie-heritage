fx_version 'cerulean'
games { 'gta5' }
lua54 'yes'

dependencies {
    'oxmysql',
    'ox_lib',
    'es_extended',
    'ox_inventory',
    'legacyWebhook',
    'prime_status',
    'lv_gacha'
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/lsg.png',
    'web/astro.png'
}
