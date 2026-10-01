
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

version '2.0.0'

dependencies
{
    'ox_lib',
    'ox_inventory',
}

shared_scripts
{
    '@ox_lib/init.lua',
    'magazine/config.lua'
}

files
{
    'magazine/weaponcomponents.meta'
}

data_file 'WEAPONCOMPONENTSINFO_FILE' 'magazine/weaponcomponents.meta'

client_scripts
{
    'magazine/client.lua'
}

server_scripts
{
    'magazine/server.lua'
}
