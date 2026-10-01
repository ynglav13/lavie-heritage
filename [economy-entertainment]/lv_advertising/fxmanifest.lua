fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'NPC Advertisement Center'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_script 'client/main.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'es_extended',
    'ox_lib',
    'oxmysql',
    'ox_target',
    'prime_status'
}
