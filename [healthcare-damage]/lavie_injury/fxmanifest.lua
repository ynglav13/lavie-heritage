fx_version 'cerulean'
game 'gta5'
lua54 'yes'

version '2.0.0'

dependencies
{
    '/onesync',
    'baseevents',
    'es_extended',
    'legacyWebhook',
    'legacyCore',
    'lv_notify',
    'custom-chat',
    'ox_inventory',
    'ox_lib',
    'ox_target',
    'oxmysql',
}

shared_scripts
{
    '@ox_lib/init.lua',
    '@es_extended/imports.lua',
    'shared/config.lua',
    'shared/function.lua',
    'shared/damage/config.lua',
    'shared/damage/function.lua',
}

client_scripts
{
    'client/function.lua',
    'client/diagnostic_invincibility.lua',
    'client/main.lua',
    'client/event.lua',
    'client/carry_drag.lua',
    'client/commands.lua',
    'client/target.lua',
    'client/damage/notify.lua',
    'client/damage/nui.lua',
    'client/damage/event.lua',
    'client/damage/main.lua',
}

server_scripts
{
    '@oxmysql/lib/MySQL.lua',
    'server/controller.lua',
    'server/diagnostic_invincibility.lua',
    'server/callback.lua',
    'server/event.lua',
    'server/carry_drag.lua',
    'server/target.lua',
    'server/damage/main.lua',
    'server/lifecycle.lua',
    'server/damage/callback.lua',
    'server/damage/notify.lua',
}

ui_page 'html/index.html'

files
{
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/damage/style.css',
    'html/damage/app.js',
    'html/images/body-xray.png',
}
