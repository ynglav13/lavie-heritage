fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'Prime Account System'
version '1.0.0'
author 'lavie'

shared_scripts {
    '@ox_lib/init.lua'
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
    'oxmysql'
}
