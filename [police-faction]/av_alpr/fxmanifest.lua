lua54 'yes'
fx_version 'cerulean'
game 'gta5'

author 'lavie'
description 'Advanced ALPR System'
version '1.0.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/utils.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/script.js',
    'nui/lsg.png',
    'nui/fonts/*.ttf',
    'nui/fonts/*.otf',
    'nui/plates/*.png'
}
