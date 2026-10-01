
fx_version 'cerulean'
game 'gta5'

lua54 'yes'

dependencies
{
    'es_extended',
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'legacyWebhook'
}

shared_scripts
{
    '@ox_lib/init.lua',
    '@es_extended/imports.lua'
}

client_script 'client.lua'
server_script 'server.lua'
