RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

if not Config.compatibility.renewedV2Exports then return end

local function invokingAllowed()
    local resource = GetInvokingResource()
    if not resource or resource == GetCurrentResourceName() then return true, resource or GetCurrentResourceName() end
    if Config.compatibility.allowAnyInvokingResource then return true, resource end
    return Config.compatibility.allowedResources[resource] == true, resource
end

local function requestId(resource, operation, account)
    return ('legacy:%s:%s:%s:%s'):format(resource or 'unknown', operation, account or 'none', math.random(100000, 999999))
end

exports('getAccountMoney', function(accountKey)
    local account = RB.Repositories.Accounts.findByKey(accountKey)
    return account and RB.Money.toFramework(account.balance) or false
end)

exports('addAccountMoney', function(accountKey, amount, reason, suppliedRequestId)
    local allowed, resource = invokingAllowed(); if not allowed then return false end
    local parsed = RB.Money.parse(tostring(amount)); if not parsed then return false end
    local result = RB.TransactionService.adjustDatabaseAccount(accountKey, parsed, 'credit', {
        actor = 'resource:' .. resource, resource = resource, reason = reason or 'Legacy credit', requestId = suppliedRequestId or requestId(resource, 'credit', accountKey)
    })
    return result.ok
end)

exports('removeAccountMoney', function(accountKey, amount, reason, suppliedRequestId)
    local allowed, resource = invokingAllowed(); if not allowed then return false end
    local parsed = RB.Money.parse(tostring(amount)); if not parsed then return false end
    local result = RB.TransactionService.adjustDatabaseAccount(accountKey, parsed, 'debit', {
        actor = 'resource:' .. resource, resource = resource, reason = reason or 'Legacy debit', requestId = suppliedRequestId or requestId(resource, 'debit', accountKey)
    })
    return result.ok
end)

exports('handleTransaction', function(account, title, amount, message, issuer, receiver, transactionType, transactionId)
    local allowed, resource = invokingAllowed(); if not allowed then return false end
    local parsed = RB.Money.parse(tostring(amount)); if not parsed then return false end
    local direction = transactionType == 'withdraw' and 'debit' or 'credit'
    local result = RB.TransactionService.appendExternalTransaction(account, {
        groupId = transactionId, requestId = requestId(resource, 'transaction', account), direction = direction,
        transactionType = 'legacy_' .. tostring(transactionType or 'entry'), amount = parsed,
        actor = issuer, counterparty = receiver, description = message or title, resource = resource,
        metadata = { title = title, invokingResource = resource }
    })
    if not result.ok then return false end
    return {
        trans_id = result.data.groupId,
        title = title,
        amount = amount,
        trans_type = transactionType,
        receiver = receiver,
        message = message,
        issuer = issuer,
        time = os.time()
    }
end)

local function legacyTransaction(row)
    return {
        trans_id = row.group_id,
        title = row.metadata and row.metadata.title or row.transaction_type,
        amount = RB.Money.toFramework(row.amount),
        trans_type = row.direction == 'debit' and 'withdraw' or 'deposit',
        receiver = row.counterparty_ref,
        message = row.description,
        issuer = row.actor_identifier,
        time = row.created_at
    }
end

exports('getAccountTransactions', function(accountKey, cursor, limit)
    local account = RB.Repositories.Accounts.findByKey(accountKey)
    if not account then return false end
    local page = RB.Repositories.Transactions.listForAccount(account.id, cursor, limit or 100, {})
    local items = {}
    for index, row in ipairs(page.items or {}) do items[index] = legacyTransaction(row) end
    return items
end)

exports('GetJobAccount', function(jobName)
    local shape = RB.Repositories.Accounts.legacyShape(RB.Repositories.Accounts.findByKey(jobName))
    if shape then shape.amount = RB.Money.toFramework(shape.amount) end
    return shape
end)

exports('CreateJobAccount', function(job, initialBalance)
    local allowed, resource = invokingAllowed(); if not allowed then return false end
    if type(job) ~= 'table' or not RB.Validation.accountKey(job.name) then return false end
    local account = RB.Repositories.Accounts.findByKey(job.name)
    if not account then
        account = RB.Repositories.Accounts.create({ accountKey = job.name, displayName = job.label or job.name, accountType = RB.AccountTypes.JOB, balance = RB.Money.fromFramework(tonumber(initialBalance) or 0) or 0 })
    end
    return RB.Repositories.Accounts.legacyShape(account)
end)

exports('changeAccountName', function(accountKey, newName)
    local allowed = invokingAllowed(); if not allowed then return false end
    local account = RB.Repositories.Accounts.findByKey(accountKey)
    local displayName = RB.Validation.text(newName, 96, false)
    return account and displayName and RB.Repositories.Accounts.rename(account.id, displayName) or false
end)

exports('addAccountMember', function(accountKey, identifier, role)
    local allowed, resource = invokingAllowed(); if not allowed then return false end
    local account = RB.Repositories.Accounts.findByKey(accountKey)
    identifier = RB.Validation.identifier(identifier)
    role = RB.Validation.role(role or RB.Roles.OPERATOR)
    return account and identifier and role and RB.Repositories.Members.upsert(account.id, identifier, role, 'resource:' .. resource) or false
end)

exports('removeAccountMember', function(accountKey, identifier)
    local allowed = invokingAllowed(); if not allowed then return false end
    local account = RB.Repositories.Accounts.findByKey(accountKey)
    identifier = RB.Validation.identifier(identifier)
    return account and identifier and RB.Repositories.Members.remove(account.id, identifier) or false
end)

if Config.compatibility.esxSocietyProvider then
    AddEventHandler('esx_society:depositMoney', function(society, amount, reason)
        exports[GetCurrentResourceName()]:addAccountMoney(society, amount, reason)
    end)
    AddEventHandler('esx_society:withdrawMoney', function(society, amount, reason)
        exports[GetCurrentResourceName()]:removeAccountMoney(society, amount, reason)
    end)
end
