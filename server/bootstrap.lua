RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

local function validateConfig()
    local errors = {}
    if not Config.currency or type(Config.currency.code) ~= 'string' then errors[#errors + 1] = 'Config.currency.code is required' end
    if not Config.v3 or Config.v3.enabled ~= true then errors[#errors + 1] = 'Config.v3.enabled must be true for the v3 runtime' end
    if not Config.security or tonumber(Config.security.maximumTransactionAmount) == nil then errors[#errors + 1] = 'Config.security.maximumTransactionAmount is required' end
    if #errors > 0 then error('[Renewed-Banking] Invalid configuration: ' .. table.concat(errors, '; ')) end
end

CreateThread(function()
    validateConfig()
    if Config.v3.autoMigrateSchema then RB.Migration.runSchema() end
    RB.Migration.detectLegacy()
    if RB.State.migrationRequired then
        RB.Logger.warn('legacy_migration_required', { command = 'banking_migrate_v3 dry-run' })
        if Config.v3.autoImportV2 then
            local result = RB.Migration.importV2('automatic')
            if not result.ok then error('[Renewed-Banking] Automatic v2 import failed: ' .. json.encode(result)) end
        end
    end
    RB.AccountService.syncFrameworkAccounts()
    RB.Logger.info('resource_ready', {
        version = RB.VERSION,
        framework = RB.Bridge.getName(),
        migrationRequired = RB.State.migrationRequired
    })
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == 'es_extended' or resource == 'qb-core' or resource == 'qbx_core' then
        RB.Logger.warn('framework_restarted', { resource = resource, message = 'Restart Renewed-Banking to reload the framework bridge safely.' })
    end
end)
