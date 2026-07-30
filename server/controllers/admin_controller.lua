RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

local function requireAdmin(source)
    if not RB.Authorization.isAdmin(source) then
        if source ~= 0 then RB.Bridge.notify(source, { type = 'error', description = 'Unauthorized.' }) end
        return false
    end
    return true
end

lib.addCommand('banking_migrate_v3', {
    help = 'Dry-run, import, or verify the Renewed Banking v3 migration.',
    params = {{ name = 'action', type = 'string', help = 'dry-run | run | verify' }},
    restricted = Config.permissions.adminAce
}, function(source, args)
    if not requireAdmin(source) then return end
    local action = tostring(args.action or 'dry-run')
    local result
    if action == 'run' then result = RB.Migration.importV2(source == 0 and 'console' or RB.Bridge.getIdentifier(RB.Bridge.getPlayerBySource(source)))
    elseif action == 'verify' then result = RB.Migration.verify()
    else result = RB.Migration.dryRun() end
    print(('[Renewed-Banking] Migration %s: %s'):format(action, json.encode(result)))
    if source ~= 0 then RB.Bridge.notify(source, { type = result.ok and 'success' or 'error', description = json.encode(result) }) end
end)

lib.addCommand('banking_reconcile', {
    help = 'Report balance/ledger mismatches and pending settlements.',
    restricted = Config.permissions.adminAce
}, function(source)
    if not requireAdmin(source) then return end
    local result = RB.Reconciliation.report()
    print(('[Renewed-Banking] Reconciliation: %s'):format(json.encode(result)))
    if source ~= 0 then RB.Bridge.notify(source, { type = result.ok and 'success' or 'error', description = ('Checked %s accounts; %s mismatch(es), %s pending settlement(s).'):format(result.data.accountsChecked, #result.data.balanceMismatches, #result.data.pendingSettlements) }) end
end)

lib.addCommand('banking_freeze', {
    help = 'Freeze or unfreeze a database-owned bank account.',
    params = {
        { name = 'account', type = 'string' },
        { name = 'state', type = 'string', help = 'freeze | unfreeze' },
        { name = 'reason', type = 'longString', optional = true }
    },
    restricted = Config.permissions.adminAce
}, function(source, args)
    if not requireAdmin(source) then return end
    if args.state ~= 'freeze' and args.state ~= 'unfreeze' then
        return print('[Renewed-Banking] State must be freeze or unfreeze.')
    end
    local state = args.state == 'freeze' and RB.AccountStatuses.FROZEN or RB.AccountStatuses.ACTIVE
    local actor = source == 0 and 'console' or RB.Bridge.getIdentifier(RB.Bridge.getPlayerBySource(source))
    local account = RB.Repositories.Accounts.findByKey(args.account)
    if account then
        RB.Repositories.Accounts.setStatus(account.id, state)
        RB.Repositories.Audit.insert(
            state == RB.AccountStatuses.FROZEN and 'account_frozen' or 'account_unfrozen',
            actor, account.id, RB.Validation.text(args.reason or '', 255, true),
            { previous = account.status, current = state }
        )
        return
    end
    local identifier = RB.Validation.identifier(args.account)
    if not identifier then return print('[Renewed-Banking] Account or character identifier not found.') end
    local previous = RB.Repositories.Players.isFrozen(identifier)
    RB.Repositories.Players.setFrozen(identifier, state == RB.AccountStatuses.FROZEN)
    RB.Repositories.Audit.insert(
        state == RB.AccountStatuses.FROZEN and 'personal_account_frozen' or 'personal_account_unfrozen',
        actor, nil, RB.Validation.text(args.reason or '', 255, true),
        { identifier = identifier, previous = previous, current = state }
    )
end)

lib.addCommand('banking_adjust', {
    help = 'Create an audited credit or debit adjustment.',
    params = {
        { name = 'account', type = 'string' },
        { name = 'direction', type = 'string', help = 'credit | debit' },
        { name = 'amount', type = 'string' },
        { name = 'reason', type = 'longString' }
    },
    restricted = Config.permissions.adminAce
}, function(source, args)
    if not requireAdmin(source) then return end
    if args.direction ~= 'credit' and args.direction ~= 'debit' then
        return print('[Renewed-Banking] Adjustment direction must be credit or debit.')
    end
    local amount, errorCode = RB.Money.parse(args.amount)
    if not amount then return print(('[Renewed-Banking] Adjustment rejected: %s'):format(errorCode)) end
    local actor = source == 0 and 'console' or RB.Bridge.getIdentifier(RB.Bridge.getPlayerBySource(source))
    local result = RB.TransactionService.adjustDatabaseAccount(args.account, amount, args.direction, {
        actor = actor, reason = args.reason, requestId = ('admin:%s:%s'):format(os.time(), math.random(1000, 9999)), resource = 'admin_command'
    })
    print(('[Renewed-Banking] Adjustment result: %s'):format(json.encode(result)))
end)
