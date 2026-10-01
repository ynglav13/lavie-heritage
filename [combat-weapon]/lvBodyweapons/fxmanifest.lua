fx_version  'adamant'
game        'gta5'
ui_page     'ui/index.html'
lua54       'yes'

client_scripts {
    'cl.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'sv.lua'
}

shared_scripts {
    '@ox_lib/init.lua',
    '@es_extended/imports.lua',
    'config.lua'
}

files {
    'ui/index.html',
    'ui/style.css',
    'ui/script.js'
}
