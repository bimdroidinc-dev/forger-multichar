fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'forger-multicharacter'
author 'Velocity Custom'
description 'Cinematic multicharacter selector for QBCore, Qbox and ESX with per-player character limits, Discord role / license slot overrides, and a pluggable clothing-resource layer.'
version '1.1.0'

-- Shared: config + locales load first so every other file can read them.
shared_scripts {
    'config.lua',
    'locales/*.lua',
}

-- Client: the clothing bridge (Appearance.*) loads before main so main can use it.
client_scripts {
    'bridge/appearance.lua',
    'client/main.lua',
}

-- Server: framework bridge (FW.*) + Discord/slot helpers load before main.
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/framework.lua',
    'server/discord.lua',
    'server/slots.lua',
    'server/main.lua',
}

ui_page 'web/index.html'

data_file 'TIMECYCLEMOD_FILE' 'timecycle_mods.xml'

files {
    'web/index.html',
    'web/css/style.css',
    'web/css/spawn.css',
    'web/js/app.js',
    'web/js/spawn.js',
    'web/fonts/*.ttf',
    'web/img/*.png',
    'web/img/*.svg',
}

dependencies {
    'oxmysql',
}
