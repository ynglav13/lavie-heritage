fx_version 'cerulean'
game 'gta5'

lua54 'yes'

author 'lavie'
description 'Dynamic vehicle rental system with admin panel, logging, op-garages and vehicleCore compatibility'
version '1.0.0'

ui_page 'web/index.html'

shared_scripts
{
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/utils.lua'
}

client_scripts
{
    'client/main.lua',
    'client/nui.lua'
}

server_scripts
{
    '@oxmysql/lib/MySQL.lua',
    'server/logging.lua',
    'server/main.lua',
    'server/admin.lua'
}

files
{
    'web/index.html',
    'web/app.js',
    'web/style.css'
}

dependencies
{
    'es_extended',
    'lv_notify',
    'ox_lib',
    'ox_target',
    'oxmysql',
    'legacyCore',
    'vehicleCore',
    'op-garages'
}
