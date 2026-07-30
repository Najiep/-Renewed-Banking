RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

RB.RateLimit = {}
local buckets = {}

function RB.RateLimit.check(source, action)
    source = tostring(source)
    local cooldown = tonumber(Config.security.actionCooldowns[action]) or 750
    local now = GetGameTimer()
    buckets[source] = buckets[source] or {}
    local expires = buckets[source][action] or 0
    if expires > now then
        return RB.Result.fail(RB.Errors.RATE_LIMITED, nil, { retryAfterMs = expires - now })
    end
    buckets[source][action] = now + cooldown
    return RB.Result.ok(true)
end

AddEventHandler('playerDropped', function() buckets[tostring(source)] = nil end)
