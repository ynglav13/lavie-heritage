fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'vehicle_persist'
description 'Event-driven vehicle persistence for OneSync'
version '2.0.0'

shared_scripts
{
    '@ox_lib/init.lua',
    '@es_extended/imports.lua',
    'config.lua',
    'deformation_shared.lua'
}

client_scripts
{
    'deformation_client.lua',
    'client_v2.lua'
}

server_scripts
{
    '@oxmysql/lib/MySQL.lua',
    'server_v2.lua'
}

dependencies
{
    '/onesync',
    'es_extended',
    'ox_lib',
    'oxmysql'
}
