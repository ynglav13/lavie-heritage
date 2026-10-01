
lua54 'yes'
fx_version 'cerulean'
game 'gta5'
author 'Lavie'
version '1.0.0'

dependencies
{
    'ox_lib',
    'oxmysql'
}

shared_scripts
{
    '@ox_lib/init.lua',
    'config.lua'
}

server_scripts
{
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

client_scripts
{
    'client/main.lua'
}
