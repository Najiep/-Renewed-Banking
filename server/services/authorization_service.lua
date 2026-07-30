RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

RB.Authorization = {}
local Accounts = RB.Repositories.Accounts
local Members = RB.Repositories.Members

local function statusAllows(account, action)
    if account.status == RB.AccountStatuses.CLOSED then return false, RB.Errors.ACCOUNT_CLOSED end
    if account.status == RB.AccountStatuses.MIGRATION_HOLD then return false, RB.Errors.MIGRATION_REQUIRED end
    if account.status == RB.AccountStatuses.FROZEN and action ~= RB.Actions.VIEW then return false, RB.Errors.ACCOUNT_FROZEN end
    return true
end

function RB.Authorization.isAdmin(source)
    return source == 0 or IsPlayerAceAllowed(tostring(source), Config.permissions.adminAce)
end

function RB.Authorization.authorize(source, account, action)
    if not account then return RB.Result.fail(RB.Errors.ACCOUNT_NOT_FOUND) end
    local allowed, statusError = statusAllows(account, action)
    if not allowed then return RB.Result.fail(statusError) end
    if RB.Authorization.isAdmin(source) then return RB.Result.ok({ role = 'admin_override' }) end
    local player = RB.Bridge.getPlayerBySource(source)
    if not player then return RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end
    local identifier = RB.Bridge.getIdentifier(player)
    if not identifier then return RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end

    if account.account_type == RB.AccountTypes.SHARED then
        local role = Members.getRole(account.id, identifier)
        local roleRules = role and Config.permissions.sharedRoles[role]
        if roleRules and roleRules[action] == true then return RB.Result.ok({ role = role, identifier = identifier }) end
        return RB.Result.fail(RB.Errors.UNAUTHORIZED)
    end

    if account.account_type == RB.AccountTypes.JOB or account.account_type == RB.AccountTypes.GANG then
        if RB.Bridge.hasGroupAccountPermission(source, account.account_type, account.account_key, action) then
            return RB.Result.ok({ role = 'group', identifier = identifier })
        end
        return RB.Result.fail(RB.Errors.UNAUTHORIZED)
    end

    if account.account_type == RB.AccountTypes.SYSTEM or account.account_type == RB.AccountTypes.ADMIN then
        return RB.Result.fail(RB.Errors.UNAUTHORIZED)
    end

    return RB.Result.fail(RB.Errors.UNAUTHORIZED)
end

function RB.Authorization.authorizePersonal(source, identifier, action)
    local player = RB.Bridge.getPlayerBySource(source)
    if not player then return RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end
    local caller = RB.Bridge.getIdentifier(player)
    if caller ~= identifier and not RB.Authorization.isAdmin(source) then return RB.Result.fail(RB.Errors.UNAUTHORIZED) end
    local frozen = RB.Repositories.Players.isFrozen(identifier)
    if frozen and action ~= RB.Actions.VIEW then return RB.Result.fail(RB.Errors.ACCOUNT_FROZEN) end
    return RB.Result.ok({ identifier = caller, role = 'owner' })
end
