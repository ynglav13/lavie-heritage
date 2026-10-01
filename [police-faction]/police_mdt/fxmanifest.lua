fx_version 'cerulean'
game 'gta5'
lua54 'yes'

dependencies {
    'ox_lib',
    'es_extended',
    'oxmysql'
}

shared_scripts {
    '@ox_lib/init.lua',
    '@es_extended/imports.lua',
    'config.lua'
}

client_script 'client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/app.js',
    'web/style.css',
    'web/ct.webp',
    'data/vehiclecode.json',
    'data/penalcode.json'
}
