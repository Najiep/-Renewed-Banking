BankingSecurity = BankingSecurity or {}

local rateBuckets = {}
local duplicateRequests = {}

local function getSecurityConfig()
    return Config.security or {}
end

local function getNow()
    return GetGameTimer()
end

local function trim(value)
    return value:match('^%s*(.-)%s*$')
end

local function cleanupSource(source)
    local prefix = tostring(source) .. ':'

    for key in pairs(rateBuckets) do
        if key:sub(1, #prefix) == prefix then
            rateBuckets[key] = nil
        end
    end

    for key in pairs(duplicateRequests) do
        if key:sub(1, #prefix) == prefix then
            duplicateRequests[key] = nil
        end
    end
end

function BankingSecurity.validateAmount(rawAmount)
    local config = getSecurityConfig()
    local amount = tonumber(rawAmount)

    if not amount or amount ~= amount or amount == math.huge or amount == -math.huge then
        return nil, 'INVALID_AMOUNT'
    end

    local minimum = tonumber(config.minimumTransactionAmount) or 1
    local maximum = tonumber(config.maximumTransactionAmount) or 100000000

    if amount < minimum or amount > maximum then
        return nil, 'INVALID_AMOUNT'
    end

    if config.requireWholeAmounts ~= false and amount % 1 ~= 0 then
        return nil, 'INVALID_AMOUNT'
    end

    return amount
end

function BankingSecurity.sanitizeText(value, maximumLength)
    if value == nil then return '' end

    value = tostring(value)
    value = value:gsub('[%z\1-\8\11\12\14-\31]', '')
    value = trim(value)

    local config = getSecurityConfig()
    local limit = tonumber(maximumLength) or tonumber(config.maximumCommentLength) or 160

    if #value > limit then
        value = value:sub(1, limit)
    end

    return value
end

function BankingSecurity.validateAccountId(rawAccountId)
    if type(rawAccountId) ~= 'string' then
        return nil, 'INVALID_ACCOUNT_ID'
    end

    local config = getSecurityConfig()
    local accountId = trim(rawAccountId):lower():gsub('%s+', '')
    local minimumLength = tonumber(config.minimumAccountIdLength) or 3
    local maximumLength = tonumber(config.maximumAccountIdLength) or 50
    local pattern = config.accountIdPattern or '^[a-z0-9][a-z0-9_-]*$'

    if #accountId < minimumLength or #accountId > maximumLength then
        return nil, 'INVALID_ACCOUNT_ID'
    end

    if not accountId:match(pattern) then
        return nil, 'INVALID_ACCOUNT_ID'
    end

    local reserved = config.reservedAccountIds or {}
    if reserved[accountId] then
        return nil, 'RESERVED_ACCOUNT_ID'
    end

    return accountId
end

function BankingSecurity.checkRateLimit(source, action)
    local config = getSecurityConfig()
    local cooldowns = config.actionCooldowns or {}
    local cooldown = tonumber(cooldowns[action]) or tonumber(config.defaultActionCooldown) or 750

    if cooldown <= 0 then return true end

    local key = ('%s:%s'):format(source, action)
    local now = getNow()
    local previous = rateBuckets[key]

    if previous and now - previous < cooldown then
        return false, math.max(0, cooldown - (now - previous))
    end

    rateBuckets[key] = now
    return true
end

function BankingSecurity.claimDuplicate(source, action, fingerprint)
    local config = getSecurityConfig()
    local window = tonumber(config.duplicateRequestWindow) or 1500

    if window <= 0 then return true end

    fingerprint = BankingSecurity.sanitizeText(fingerprint or 'none', 512)
    local key = ('%s:%s:%s'):format(source, action, fingerprint)
    local now = getNow()
    local expiresAt = duplicateRequests[key]

    if expiresAt and now < expiresAt then
        return false
    end

    local newExpiry = now + window
    duplicateRequests[key] = newExpiry

    SetTimeout(window + 100, function()
        if duplicateRequests[key] == newExpiry then
            duplicateRequests[key] = nil
        end
    end)

    return true
end

function BankingSecurity.redact(value)
    value = tostring(value or 'unknown')
    if #value <= 8 then return value end
    return ('%s...%s'):format(value:sub(1, 4), value:sub(-4))
end

function BankingSecurity.audit(action, source, details)
    local config = getSecurityConfig()
    if config.auditEnabled == false then return end

    details = details or {}
    local playerName = source and GetPlayerName(source) or 'server'
    local parts = {
        ('action=%s'):format(action),
        ('source=%s'):format(source or 0),
        ('player=%s'):format(playerName or 'unknown')
    }

    for key, value in pairs(details) do
        parts[#parts + 1] = ('%s=%s'):format(key, tostring(value))
    end

    print(('^6[Renewed-Banking Security]^0 %s'):format(table.concat(parts, ' ')))
end

function BankingSecurity.notify(source, description, notificationType)
    if not source or source <= 0 then return end

    if Notify then
        Notify(source, {
            title = locale('bank_name'),
            description = description,
            type = notificationType or 'error'
        })
    else
        TriggerClientEvent('ox_lib:notify', source, {
            title = locale('bank_name'),
            description = description,
            type = notificationType or 'error'
        })
    end
end

function ExportHandler(resource, name, callback)
    AddEventHandler(('__cfx_export_%s_%s'):format(resource, name), function(setCallback)
        setCallback(callback)
    end)
end

AddEventHandler('playerDropped', function()
    cleanupSource(source)
end)
