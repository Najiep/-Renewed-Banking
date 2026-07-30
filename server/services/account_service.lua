RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

RB.AccountService = {}
local Accounts = RB.Repositories.Accounts
local Members = RB.Repositories.Members

local function audit(eventType, actor, accountId, reason, metadata)
    return RB.Repositories.Audit.insert(eventType, actor, accountId, reason, metadata)
end

local function summary(account, role)
    return {
        kind = 'database',
        id = account.id,
        key = account.account_key,
        displayName = account.display_name,
        accountType = account.account_type,
        balance = account.balance,
        currency = account.currency,
        status = account.status,
        role = role,
        permissions = role == 'group' and { view = true, deposit = true, withdraw = true, transfer = true }
            or (role and Config.permissions.sharedRoles[role]) or {}
    }
end

function RB.AccountService.getSession(source)
    local player = RB.Bridge.getPlayerBySource(source)
    if not player then return RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end
    local identifier = RB.Bridge.getIdentifier(player)
    local name = RB.Bridge.getCharacterName(player)
    local bank = RB.Bridge.getMoney(player, 'bank')
    local cash = RB.Bridge.getMoney(player, 'cash')
    if not bank.ok or not cash.ok then return RB.Result.fail(RB.Errors.FRAMEWORK_OPERATION_FAILED) end
    local frozen = RB.Repositories.Players.isFrozen(identifier)
    local result = {{
        kind = 'personal',
        id = identifier,
        key = identifier,
        displayName = name,
        accountType = RB.AccountTypes.PERSONAL,
        balance = RB.Money.fromFramework(bank.data),
        cash = RB.Money.fromFramework(cash.data),
        currency = Config.currency.code,
        status = frozen and RB.AccountStatuses.FROZEN or RB.AccountStatuses.ACTIVE,
        role = 'owner',
        permissions = { view = true, deposit = true, withdraw = true, transfer = true }
    }}

    local seen = {}
    for _, account in ipairs(Accounts.listForMember(identifier)) do
        seen[account.id] = true
        result[#result + 1] = summary(account, account.member_role)
    end
    local groups = RB.Bridge.getGroups(source)
    local keys = {}
    for _, group in ipairs(groups) do keys[#keys + 1] = group.name end
    for _, account in ipairs(Accounts.listByKeys(keys)) do
        if not seen[account.id] and RB.Bridge.hasGroupAccountPermission(source, account.account_type, account.account_key, RB.Actions.VIEW) then
            result[#result + 1] = summary(account, 'group')
        end
    end

    return RB.Result.ok({
        framework = RB.Bridge.getName(),
        currency = Config.currency,
        accounts = result,
        migrationRequired = RB.State and RB.State.migrationRequired or false,
        capabilities = { sharedAccounts = not (RB.State and RB.State.migrationRequired) }
    })
end

function RB.AccountService.createShared(source, payload)
    local player = RB.Bridge.getPlayerBySource(source)
    if not player then return RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end
    local identifier = RB.Bridge.getIdentifier(player)
    local key, keyError = RB.Validation.accountKey(payload.accountKey)
    if not key then return RB.Result.fail(keyError) end
    local displayName = RB.Validation.text(payload.displayName or key, 96, false)
    if not displayName then return RB.Result.fail(RB.Errors.INVALID_PAYLOAD) end
    if RB.State and RB.State.migrationRequired then return RB.Result.fail(RB.Errors.MIGRATION_REQUIRED) end
    if Accounts.findByKey(key) then return RB.Result.fail(RB.Errors.INVALID_ACCOUNT_KEY, 'Account key already exists') end
    if Accounts.countOwned(identifier) >= Config.security.maximumSharedAccountsPerPlayer then return RB.Result.fail(RB.Errors.ACCOUNT_LIMIT_REACHED) end
    return RB.Locks.with({ 'create:' .. key, 'owner:' .. identifier }, function()
        if Accounts.findByKey(key) then return RB.Result.fail(RB.Errors.INVALID_ACCOUNT_KEY, 'Account key already exists') end
        if Accounts.countOwned(identifier) >= Config.security.maximumSharedAccountsPerPlayer then return RB.Result.fail(RB.Errors.ACCOUNT_LIMIT_REACHED) end
        local account = Accounts.create({ accountKey = key, displayName = displayName, accountType = RB.AccountTypes.SHARED, ownerIdentifier = identifier })
        if not account then return RB.Result.fail(RB.Errors.DATABASE_OPERATION_FAILED) end
        Members.upsert(account.id, identifier, RB.Roles.OWNER, identifier)
        audit('account_created', identifier, account.id, nil, { accountKey = key })
        RB.Logger.info('account_created', { actor = identifier, account = key })
        return RB.Result.ok(summary(account, RB.Roles.OWNER))
    end)
end

function RB.AccountService.listMembers(source, accountKey)
    local account = Accounts.findByKey(accountKey)
    local auth = RB.Authorization.authorize(source, account, RB.Actions.MEMBERS)
    if not auth.ok then return auth end
    return RB.Result.ok(Members.list(account.id))
end

function RB.AccountService.addMember(source, payload)
    local account = Accounts.findByKey(payload.accountKey)
    local auth = RB.Authorization.authorize(source, account, RB.Actions.MEMBERS)
    if not auth.ok then return auth end
    local member = RB.Validation.identifier(payload.identifier)
    local role = RB.Validation.role(payload.role or RB.Roles.OPERATOR)
    if not member or not role then return RB.Result.fail(RB.Errors.INVALID_PAYLOAD) end
    if role == RB.Roles.OWNER and auth.data.role ~= RB.Roles.OWNER and not RB.Authorization.isAdmin(source) then return RB.Result.fail(RB.Errors.UNAUTHORIZED) end
    if Members.exists(account.id, member) then return RB.Result.fail(RB.Errors.MEMBER_EXISTS) end
    local actor = RB.Bridge.getIdentifier(RB.Bridge.getPlayerBySource(source))
    Members.upsert(account.id, member, role, actor)
    audit('member_added', actor, account.id, nil, { memberIdentifier = member, role = role })
    return RB.Result.ok(true)
end

function RB.AccountService.removeMember(source, payload)
    local account = Accounts.findByKey(payload.accountKey)
    local auth = RB.Authorization.authorize(source, account, RB.Actions.MEMBERS)
    if not auth.ok then return auth end
    local member = RB.Validation.identifier(payload.identifier)
    if not member then return RB.Result.fail(RB.Errors.INVALID_PAYLOAD) end
    local role = Members.getRole(account.id, member)
    if not role then return RB.Result.fail(RB.Errors.MEMBER_NOT_FOUND) end
    if role == RB.Roles.OWNER and Members.countOwners(account.id) <= 1 then return RB.Result.fail(RB.Errors.LAST_OWNER) end
    local actor = RB.Bridge.getIdentifier(RB.Bridge.getPlayerBySource(source))
    Members.remove(account.id, member)
    audit('member_removed', actor, account.id, nil, { memberIdentifier = member, role = role })
    return RB.Result.ok(true)
end

function RB.AccountService.rename(source, payload)
    local account = Accounts.findByKey(payload.accountKey)
    local auth = RB.Authorization.authorize(source, account, RB.Actions.RENAME)
    if not auth.ok then return auth end
    local name = RB.Validation.text(payload.displayName, 96, false)
    if not name then return RB.Result.fail(RB.Errors.INVALID_PAYLOAD) end
    if not Accounts.rename(account.id, name) then return RB.Result.fail(RB.Errors.DATABASE_OPERATION_FAILED) end
    local actor = RB.Bridge.getIdentifier(RB.Bridge.getPlayerBySource(source))
    audit('account_renamed', actor, account.id, nil, { oldName = account.display_name, newName = name })
    return RB.Result.ok(true)
end

function RB.AccountService.close(source, payload)
    local account = Accounts.findByKey(payload.accountKey)
    local auth = RB.Authorization.authorize(source, account, RB.Actions.CLOSE)
    if not auth.ok then return auth end
    if account.account_type ~= RB.AccountTypes.SHARED then return RB.Result.fail(RB.Errors.UNAUTHORIZED) end
    if account.balance ~= 0 then return RB.Result.fail(RB.Errors.ACCOUNT_NOT_EMPTY) end
    if not Accounts.close(account.id) then return RB.Result.fail(RB.Errors.DATABASE_OPERATION_FAILED) end
    local actor = RB.Bridge.getIdentifier(RB.Bridge.getPlayerBySource(source))
    audit('account_closed', actor, account.id, payload.reason, {})
    return RB.Result.ok(true)
end

function RB.AccountService.syncFrameworkAccounts()
    if RB.State and RB.State.migrationRequired then return end
    for _, group in ipairs(RB.Bridge.getDefinedGroups()) do
        if not Accounts.findByKey(group.name) then
            local account = Accounts.create({ accountKey = group.name, displayName = group.label, accountType = group.type })
            if account then audit('framework_account_created', 'system', account.id, nil, { framework = RB.Bridge.getName() }) end
        end
    end
end
