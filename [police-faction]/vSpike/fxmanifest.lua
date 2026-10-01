fx_version 'cerulean'
game 'gta5'

lua54 'yes' 

author 'Lavie'
description 'Spike Strip System'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}
