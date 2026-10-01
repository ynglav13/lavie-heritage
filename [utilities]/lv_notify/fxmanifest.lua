fx_version 'cerulean'
game 'gta5'

lua54 'yes'

author 'lavie'
description 'lv_notify - compact dynamic notification system for client and server'
version '1.0.0'

ui_page 'html/index.html'

shared_scripts
{
    'config.lua'
}

client_scripts
{
    'client/main.lua'
}

server_scripts
{
    'server/main.lua'
}

files
{
    'html/index.html',
    'html/css/style-v2.css',
    'html/js/app.js'
}
