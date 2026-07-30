RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

local function guarded(event, action, handler, idempotent)
    lib.callback.register(event, function(source, payload)
        payload = payload or {}
        local limit = RB.RateLimit.check(source, action)
        if not limit.ok then return limit end
        local ok, result = xpcall(function()
            if not idempotent then return handler(source, payload) end
            local player = RB.Bridge.getPlayerBySource(source)
            local identifier = player and RB.Bridge.getIdentifier(player)
            if not identifier then return RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end
            local claim = RB.Idempotency.claim(('player:%s:%s'):format(identifier, action), payload.requestId, action, payload)
            if not claim.ok then return claim end
            if claim.data.replay then return claim.data.response end
            local response = handler(source, payload)
            return response.ok and RB.Idempotency.complete(claim.data, response) or RB.Idempotency.fail(claim.data, response)
        end, debug.traceback)
        if not ok then
            RB.Logger.error('account_callback_failed', { event = event, source = source, error = result })
            return RB.Result.fail(RB.Errors.SERVICE_UNAVAILABLE)
        end
        return result
    end)
end

guarded('Renewed-Banking:server:v3:createAccount', 'createAccount', RB.AccountService.createShared, true)
guarded('Renewed-Banking:server:v3:listMembers', 'listMembers', function(source, payload) return RB.AccountService.listMembers(source, payload.accountKey) end, false)
guarded('Renewed-Banking:server:v3:addMember', 'addMember', RB.AccountService.addMember, true)
guarded('Renewed-Banking:server:v3:removeMember', 'removeMember', RB.AccountService.removeMember, true)
guarded('Renewed-Banking:server:v3:renameAccount', 'renameAccount', RB.AccountService.rename, true)
guarded('Renewed-Banking:server:v3:closeAccount', 'closeAccount', RB.AccountService.close, true)
