fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'Custom Crosshair System'
version '1.0.0'
author 'lavie'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}

dependencies {
    'es_extended',
    'oxmysql',
    'ox_lib',
    'prime_status'
}
