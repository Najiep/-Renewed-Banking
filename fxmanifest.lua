fx_version 'cerulean'
game 'gta5'

name 'Renewed-Banking'
description 'Secure, framework-native banking with an append-only ledger'
author 'uShifty#1733 / Renewed Banking contributors'
version '3.0.0-rc.1'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/constants.lua',
    'shared/result.lua',
    'shared/money.lua',
    'shared/validation.lua'
}

client_scripts {
    'client/state.lua',
    'client/nui.lua',
    'client/interactions.lua',
    'client/bootstrap.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/observability/logger.lua',
    'server/bridge/interface.lua',
    'server/bridge/esx.lua',
    'server/bridge/qb.lua',
    'server/bridge/qbx.lua',
    'server/bridge/loader.lua',
    'server/repositories/account_repository.lua',
    'server/repositories/member_repository.lua',
    'server/repositories/transaction_repository.lua',
    'server/repositories/idempotency_repository.lua',
    'server/repositories/settlement_repository.lua',
    'server/repositories/audit_repository.lua',
    'server/repositories/player_repository.lua',
    'server/services/rate_limit.lua',
    'server/services/locks.lua',
    'server/services/migration_service.lua',
    'server/services/authorization_service.lua',
    'server/services/account_service.lua',
    'server/services/idempotency_service.lua',
    'server/services/transaction_service.lua',
    'server/services/statement_service.lua',
    'server/services/reconciliation_service.lua',
    'server/controllers/banking_controller.lua',
    'server/controllers/account_controller.lua',
    'server/controllers/admin_controller.lua',
    'server/compatibility/renewed_v2.lua',
    'server/bootstrap.lua'
}

ui_page 'web/dist/index.html'

files {
    'web/dist/index.html',
    'web/dist/assets/**/*',
    'locales/*.json',
    'migrations/*.sql'
}

dependencies {
    'ox_lib',
    'oxmysql'
}
