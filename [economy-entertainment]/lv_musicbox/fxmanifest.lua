fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'lavie'
description 'SpityFork roleplay music player for speakers, boomboxes, and vehicles.'
version '1.0.0'

ui_page 'html/index.html'

files
{
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

shared_scripts
{
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/locales.lua'
}

client_scripts
{
    'client/state.lua',
    'client/utils.lua',
    'client/audio.lua',
    'client/devices.lua',
    'client/main.lua'
}

server_scripts
{
    'server/main.lua'
}

dependencies
{
    'ox_lib',
    'ox_target'
}
