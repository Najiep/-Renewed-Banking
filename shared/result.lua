RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking
RB.Result = {}
function RB.Result.ok(data) return { ok = true, data = data } end
function RB.Result.fail(code, message, details) return { ok = false, error = { code = code or RB.Errors.SERVICE_UNAVAILABLE, message = message, details = details } } end
