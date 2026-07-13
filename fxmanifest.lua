fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'forger-multicharacter'
author 'Velocity Custom'
description 'Crisp cinematic multicharacter selector with per-player character limits, Discord role and license overrides.'
version '1.0.0'

shared_scripts {
    'config.lua',
    'locales/*.lua',
}

client_scripts {
    'client/main.lua',
    'client/partner.lua',
    'client/scenemaker.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/framework.lua',
    'server/discord.lua',
    'server/slots.lua',
    'server/scenemaker.lua',
    'server/main.lua',
    'server/partner.lua',
}

ui_page 'web/index.html'

data_file 'TIMECYCLEMOD_FILE' 'timecycle_mods.xml'

files {
    'web/index.html',
    'web/css/style.css',
    'web/css/spawn.css',
    'web/css/scenemaker.css',
    'web/js/app.js',
    'web/js/spawn.js',
    'web/js/scenemaker.js',
    'web/fonts/*.ttf',
    'web/img/*.png',
    'web/img/*.svg',
}

dependencies {
    'oxmysql',
}
