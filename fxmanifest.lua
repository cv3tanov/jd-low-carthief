fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'Randolio'
description 'Car Thief - оптимизирана версия'
version '2.1.0'

shared_scripts {
    '@ox_lib/init.lua'
}

client_scripts {
    'client/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'ox_inventory',
    'ox_target',
    'jd-core'
}
