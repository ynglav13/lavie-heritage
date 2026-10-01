fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'lavie'
description 'Server-authoritative admin event turf zones'
version '1.0.0'

shared_scripts {
    'config.lua',
    'shared/geometry.lua',
}

client_scripts {
    '@PolyZone/client.lua',
    '@PolyZone/CircleZone.lua',
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

dependencies {
    'es_extended',
    'oxmysql',
    'PolyZone',
    'aCore',
    'lv_notify',
}
