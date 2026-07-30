RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

local function guarded(event, handler)
    lib.callback.register(event, function(source, payload)
        local ok, result = xpcall(function() return handler(source, payload or {}) end, debug.traceback)
        if not ok then
            RB.Logger.error('callback_failed', { event = event, source = source, error = result })
            return RB.Result.fail(RB.Errors.SERVICE_UNAVAILABLE)
        end
        return result
    end)
end

guarded('Renewed-Banking:server:v3:getSession', function(source)
    local limit = RB.RateLimit.check(source, 'session')
    if not limit.ok then return limit end
    return RB.AccountService.getSession(source)
end)

guarded('Renewed-Banking:server:v3:deposit', RB.TransactionService.deposit)
guarded('Renewed-Banking:server:v3:withdraw', RB.TransactionService.withdraw)
guarded('Renewed-Banking:server:v3:transfer', RB.TransactionService.transfer)
guarded('Renewed-Banking:server:v3:transactions', RB.StatementService.list)
