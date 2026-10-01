lua54 'yes'
fx_version 'cerulean'
game 'gta5'

description 'tutorial'
version '1.0.0'

shared_scripts
{
    '@ox_lib/init.lua',
    'shared/config.lua'
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

ui_page 'html/ui.html'

files
{
    'html/ui.html',
    'html/style.css',
    'html/script.js'
}

exports
{
    'IsTutorialDone'
}

server_exports
{
    'IsTutorialDone'
}
