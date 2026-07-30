fx_version 'cerulean'
game 'gta5'

name 'Renewed-Banking'
description 'Renewed Banking'
author 'uShifty#1733'
version '2.1.5-phase1'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/framework.lua',
    'client/main.lua',
    'client/menus.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/security.lua',
    'server/framework.lua',
    'server/main.lua'
}

ui_page 'web/public/index.html'

files {
    'web/public/index.html',
    'web/public/**/*',
    'locales/*.json'
}

provide 'qb-management'
provide 'esx_society'
