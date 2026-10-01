fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'Admin Core'
version '1.0.0'
author 'lavie'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/permissions.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/functions.lua',
    'server/logs.lua',
    'server/commands.lua',
}

client_scripts {
    'client/main.lua',
    'client/spectate.lua',
    'client/noclip.lua',
    'client/commands.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js',
    'html/js/api.js',
}

dependencies {
    'oxmysql',
    'es_extended',
}
