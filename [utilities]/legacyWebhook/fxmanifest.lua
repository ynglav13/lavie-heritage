lua54 'yes'
fx_version 'cerulean'
game 'gta5'

description 'Centralized Discord webhook log queue manager'
version '1.0.0'

server_scripts
{
    '@oxmysql/lib/MySQL.lua',
    'config.lua',
    'server.lua'
}

dependency 'oxmysql'
