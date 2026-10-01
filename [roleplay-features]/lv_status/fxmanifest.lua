fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'lavie'
version '1.0.0'

shared_scripts {
    'shared/config.lua',
    '@ox_lib/init.lua',
    '@es_extended/imports.lua',
}

client_scripts {
    'client/notify.lua',
    'client/effects.lua',
    'client/stress.lua',
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/main.lua',
}
