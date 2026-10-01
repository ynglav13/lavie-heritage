lua54 'yes'
fx_version 'cerulean'
game 'gta5'

author 'lavie'
description 'Connection Queue System with Whitelist & Priority'
version '1.0.0'

shared_script 'config.lua'

server_scripts
{
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

dependencies
{
    'es_extended',
    'oxmysql'
}
