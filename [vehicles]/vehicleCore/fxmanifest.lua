lua54 'yes'
fx_version 'cerulean'
game 'gta5'

description 'vehicleCore by lavie'
version '1.0.0'

server_exports
{
    'GiveVehicleKey',
    'RemoveVehicleKey'
}

client_scripts
{
    'client/client.lua'
}

server_scripts
{
    '@oxmysql/lib/MySQL.lua',
    'server/server.lua'
}

shared_scripts
{
    '@ox_lib/init.lua',
    'config.lua'
}

dependencies
{
    'ox_inventory',
    'ox_lib'
}

ui_page 'html/index.html'

files
{
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/bv.mp3'
}
