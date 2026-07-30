RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

RB.Idempotency = {}
local Repository = RB.Repositories.Idempotency

local function fnv1a(value)
    local hash = 2166136261
    for i = 1, #value do
        hash = ((hash ~ value:byte(i)) * 16777619) & 0xffffffff
    end
    return string.format('%08x', hash)
end

local function canonical(value, seen)
    local valueType = type(value)
    if valueType == 'nil' then return 'null' end
    if valueType == 'boolean' or valueType == 'number' then return tostring(value) end
    if valueType == 'string' then return json.encode(value) end
    if valueType ~= 'table' then return json.encode(tostring(value)) end

    seen = seen or {}
    if seen[value] then return '"<cycle>"' end
    seen[value] = true

    local isArray = true
    local count, maximum = 0, 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then isArray = false break end
        count = count + 1
        if key > maximum then maximum = key end
    end
    if isArray and maximum ~= count then isArray = false end

    local parts = {}
    if isArray then
        for index = 1, maximum do parts[#parts + 1] = canonical(value[index], seen) end
        seen[value] = nil
        return '[' .. table.concat(parts, ',') .. ']'
    end

    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = json.encode(key) .. ':' .. canonical(value[key], seen)
    end
    seen[value] = nil
    return '{' .. table.concat(parts, ',') .. '}'
end

function RB.Idempotency.hash(payload)
    return fnv1a(canonical(payload or {}))
end

function RB.Idempotency.claim(scopeKey, requestId, operation, payload)
    local validId, errorCode = RB.Validation.requestId(requestId)
    if not validId then return RB.Result.fail(errorCode) end
    local hash = RB.Idempotency.hash(payload)
    local ttl = Config.v3.idempotencyTtlSeconds
    if Repository.claim(scopeKey, validId, operation, hash, ttl) then
        return RB.Result.ok({ owner = true, scopeKey = scopeKey, requestId = validId, payloadHash = hash })
    end
    local existing = Repository.get(scopeKey, validId)
    if not existing then return RB.Result.fail(RB.Errors.DATABASE_OPERATION_FAILED) end
    if existing.payload_hash ~= hash then return RB.Result.fail(RB.Errors.IDEMPOTENCY_CONFLICT) end
    if existing.status == 'committed' and existing.response then return RB.Result.ok({ replay = true, response = existing.response }) end
    if existing.status == 'failed' and existing.response then return RB.Result.ok({ replay = true, response = existing.response }) end
    if Repository.takeOverExpired(scopeKey, validId, hash, ttl) then
        return RB.Result.ok({ owner = true, scopeKey = scopeKey, requestId = validId, payloadHash = hash })
    end
    return RB.Result.fail(RB.Errors.REQUEST_IN_PROGRESS)
end

function RB.Idempotency.complete(claim, response)
    Repository.complete(claim.scopeKey, claim.requestId, response)
    return response
end

function RB.Idempotency.fail(claim, response)
    Repository.fail(claim.scopeKey, claim.requestId, response)
    return response
end

CreateThread(function()
    while true do
        Wait(3600000)
        local ok, err = pcall(Repository.cleanup)
        if not ok then RB.Logger.warn('idempotency_cleanup_failed', { error = tostring(err) }) end
    end
end)
