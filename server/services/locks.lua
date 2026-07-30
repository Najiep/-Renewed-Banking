RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

RB.Locks = {}
local locks = {}

local function now() return GetGameTimer() end

local function acquireOne(key, timeoutMs)
    local deadline = now() + timeoutMs
    while locks[key] do
        if now() >= deadline then return false end
        Wait(0)
    end
    locks[key] = true
    return true
end

function RB.Locks.with(keys, callback, timeoutMs)
    timeoutMs = timeoutMs or Config.v3.lockTimeoutMs
    if type(keys) == 'string' then keys = { keys } end
    local unique, ordered = {}, {}
    for _, key in ipairs(keys or {}) do
        key = tostring(key)
        if not unique[key] then unique[key] = true; ordered[#ordered + 1] = key end
    end
    table.sort(ordered)
    local acquired = {}
    for _, key in ipairs(ordered) do
        if not acquireOne(key, timeoutMs) then
            for i = #acquired, 1, -1 do locks[acquired[i]] = nil end
            return RB.Result.fail(RB.Errors.SERVICE_UNAVAILABLE, 'Account lock timeout')
        end
        acquired[#acquired + 1] = key
    end
    local ok, result = xpcall(callback, debug.traceback)
    for i = #acquired, 1, -1 do locks[acquired[i]] = nil end
    if not ok then
        RB.Logger.error('lock_callback_failed', { error = result, keys = ordered })
        return RB.Result.fail(RB.Errors.SERVICE_UNAVAILABLE)
    end
    return result
end
