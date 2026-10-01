fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'NPC investment'

shared_scripts
{
    '@ox_lib/init.lua',
    '@legacyCore/shared/init.lua',
    'config.lua'
}

client_script 'client/main.lua'

server_scripts
{
    '@oxmysql/lib/MySQL.lua',
    'server_config.lua',
    'server/main.lua'
}

dependencies
{
    'es_extended',
    'ox_lib',
    'oxmysql',
    'ox_target',
    'legacyCore'
}
