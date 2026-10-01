lua54 'yes'
fx_version 'cerulean'
game 'gta5'

author 'Lavie'
description 'Radio animation for pma-voice'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_script 'client.lua'
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

dependencies {
   'pma-voice',
   'ox_lib',
   'oxmysql'
}
