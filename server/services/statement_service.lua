RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

RB.StatementService = {}

function RB.StatementService.list(source, payload)
    local limit = RB.RateLimit.check(source, 'statement')
    if not limit.ok then return limit end
    if type(payload) ~= 'table' or type(payload.accountKey) ~= 'string' then return RB.Result.fail(RB.Errors.INVALID_PAYLOAD) end
    local player = RB.Bridge.getPlayerBySource(source)
    if not player then return RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end
    local identifier = RB.Bridge.getIdentifier(player)
    if payload.accountKey == identifier then
        local auth = RB.Authorization.authorizePersonal(source, identifier, RB.Actions.VIEW)
        if not auth.ok then return auth end
        return RB.Result.ok(RB.Repositories.Transactions.listForPersonal(identifier, payload.cursor, payload.limit, payload.filters))
    end
    local account = RB.Repositories.Accounts.findByKey(payload.accountKey)
    local auth = RB.Authorization.authorize(source, account, RB.Actions.VIEW)
    if not auth.ok then return auth end
    return RB.Result.ok(RB.Repositories.Transactions.listForAccount(account.id, payload.cursor, payload.limit, payload.filters))
end
