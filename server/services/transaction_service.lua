RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

RB.TransactionService = {}
local Accounts = RB.Repositories.Accounts
local Transactions = RB.Repositories.Transactions
local Settlements = RB.Repositories.Settlements

local function generateId(prefix)
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    local id = template:gsub('[xy]', function(char)
        local value = char == 'x' and math.random(0, 15) or math.random(8, 11)
        return string.format('%x', value)
    end)
    return prefix and (prefix .. ':' .. id) or id
end

local function actor(source)
    local player = RB.Bridge.getPlayerBySource(source)
    return player, player and RB.Bridge.getIdentifier(player), player and RB.Bridge.getCharacterName(player)
end

local function description(value)
    return RB.Validation.text(value or '', Config.security.maximumCommentLength, true) or ''
end

local function personalRef(identifier)
    return { kind = 'personal', key = identifier, identifier = identifier, accountType = RB.AccountTypes.PERSONAL }
end

local function databaseRef(account)
    return { kind = 'database', key = account.account_key, id = account.id, account = account, accountType = account.account_type }
end

local function resolveSource(source, payload, action)
    local player, identifier = actor(source)
    if not player or not identifier then return nil, RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end
    local key = type(payload.sourceKey) == 'string' and payload.sourceKey or identifier
    if key == identifier then
        local auth = RB.Authorization.authorizePersonal(source, identifier, action)
        return auth.ok and personalRef(identifier) or nil, auth
    end
    local account = Accounts.findByKey(key)
    local auth = RB.Authorization.authorize(source, account, action)
    return auth.ok and databaseRef(account) or nil, auth
end

local function resolveDestination(source, payload)
    if payload.recipientType == 'personal' then
        local identifier = RB.Validation.identifier(payload.recipientKey)
        if not identifier then return nil, RB.Result.fail(RB.Errors.RECIPIENT_NOT_FOUND) end
        local target = RB.Bridge.getOnlinePlayerByIdentifier(identifier)
        if not target then return nil, RB.Result.fail(RB.Errors.RECIPIENT_NOT_FOUND) end
        return personalRef(RB.Bridge.getIdentifier(target)), RB.Result.ok({ player = target })
    end
    local key = type(payload.recipientKey) == 'string' and payload.recipientKey:lower() or nil
    local account = key and Accounts.findByKey(key)
    if not account then return nil, RB.Result.fail(RB.Errors.RECIPIENT_NOT_FOUND) end
    if account.status == RB.AccountStatuses.CLOSED then return nil, RB.Result.fail(RB.Errors.ACCOUNT_CLOSED) end
    if account.status == RB.AccountStatuses.FROZEN then return nil, RB.Result.fail(RB.Errors.ACCOUNT_FROZEN) end
    if account.status == RB.AccountStatuses.MIGRATION_HOLD then return nil, RB.Result.fail(RB.Errors.MIGRATION_REQUIRED) end
    return databaseRef(account), RB.Result.ok(true)
end

local function beginRequest(source, operation, payload)
    local player, identifier = actor(source)
    if not player or not identifier then return nil, RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end
    local requestId, requestError = RB.Validation.requestId(payload.requestId)
    if not requestId then return nil, RB.Result.fail(requestError) end
    local claim = RB.Idempotency.claim(('player:%s:%s'):format(identifier, operation), requestId, operation, payload)
    if not claim.ok then return nil, claim end
    if claim.data.replay then return nil, claim.data.response end
    return claim.data, nil
end

local function finish(claim, response)
    if response.ok then return RB.Idempotency.complete(claim, response) end
    return RB.Idempotency.fail(claim, response)
end

local function ledgerPersonal(entry)
    return Transactions.insert(entry) ~= nil
end

local function settlement(data, errorCode)
    Settlements.create(data)
    if errorCode then Settlements.update(data.groupId, data.identifier, data.direction, data.status or 'manual_review', errorCode) end
end

local function frameworkAmount(amount)
    return RB.Money.toFramework(amount)
end

local function compensateFramework(player, moneyType, amount, reason, groupId, identifier, direction)
    local result = RB.Bridge.addMoney(player, moneyType, frameworkAmount(amount), reason)
    settlement({
        groupId = groupId, framework = RB.Bridge.getName(), identifier = identifier,
        moneyType = moneyType, direction = direction, amount = amount,
        status = result.ok and 'reversed' or 'manual_review', metadata = { reason = reason }
    }, result.ok and nil or RB.Errors.FRAMEWORK_OPERATION_FAILED)
    return result.ok
end

local function mutateDatabase(ref, delta, entry)
    local lockKey = 'db:' .. ref.id
    return RB.Locks.with(lockKey, function()
        local account = Accounts.findById(ref.id)
        if not account then return RB.Result.fail(RB.Errors.ACCOUNT_NOT_FOUND) end
        if account.status == RB.AccountStatuses.FROZEN then return RB.Result.fail(RB.Errors.ACCOUNT_FROZEN) end
        if account.status == RB.AccountStatuses.CLOSED then return RB.Result.fail(RB.Errors.ACCOUNT_CLOSED) end
        local ok, value = Accounts.applyDeltaWithLedger(account, delta, entry)
        if not ok then return RB.Result.fail(value) end
        return RB.Result.ok(value)
    end)
end

function RB.TransactionService.deposit(source, payload)
    local limit = RB.RateLimit.check(source, 'deposit'); if not limit.ok then return limit end
    if not RB.Validation.payload(payload) then return RB.Result.fail(RB.Errors.INVALID_PAYLOAD) end
    local amount, amountError = RB.Money.parse(payload.amount)
    if not amount then return RB.Result.fail(amountError) end
    local claim, early = beginRequest(source, 'deposit', payload); if early then return early end
    local sourceRef, auth = resolveSource(source, payload, RB.Actions.DEPOSIT)
    if not sourceRef then return finish(claim, auth) end
    local player, identifier, name = actor(source)
    local comment = description(payload.description)
    local groupId = generateId('deposit')
    local removeCash = RB.Bridge.removeMoney(player, 'cash', frameworkAmount(amount), comment)
    if not removeCash.ok then return finish(claim, removeCash) end

    if sourceRef.kind == 'personal' then
        local addBank = RB.Bridge.addMoney(player, 'bank', frameworkAmount(amount), comment)
        if not addBank.ok then
            compensateFramework(player, 'cash', amount, 'Deposit compensation', groupId, identifier, 'add')
            return finish(claim, RB.Result.fail(RB.Errors.FRAMEWORK_OPERATION_FAILED))
        end
        local bank = RB.Bridge.getMoney(player, 'bank')
        local ledgerOk = ledgerPersonal({
            groupId = groupId, requestId = claim.requestId, personalIdentifier = identifier,
            direction = 'credit', transactionType = 'cash_deposit', amount = amount,
            balanceAfter = bank.ok and RB.Money.fromFramework(bank.data) or nil,
            actorIdentifier = identifier, counterpartyRef = 'cash', description = comment
        })
        if not ledgerOk then
            local removeBank = RB.Bridge.removeMoney(player, 'bank', frameworkAmount(amount), 'Deposit ledger rollback')
            local restoreCash = removeBank.ok and RB.Bridge.addMoney(player, 'cash', frameworkAmount(amount), 'Deposit ledger rollback') or RB.Result.fail(RB.Errors.FRAMEWORK_OPERATION_FAILED)
            settlement({ groupId = groupId, framework = RB.Bridge.getName(), identifier = identifier, moneyType = 'cash', direction = 'add', amount = amount, status = restoreCash.ok and 'reversed' or 'manual_review' }, restoreCash.ok and nil or RB.Errors.DATABASE_OPERATION_FAILED)
            return finish(claim, RB.Result.fail(restoreCash.ok and RB.Errors.DATABASE_OPERATION_FAILED or RB.Errors.SETTLEMENT_PENDING))
        end
    else
        local result = mutateDatabase(sourceRef, amount, {
            groupId = groupId, requestId = claim.requestId, direction = 'credit',
            transactionType = 'cash_deposit', amount = amount, actorIdentifier = identifier,
            counterpartyRef = name, description = comment
        })
        if not result.ok then
            compensateFramework(player, 'cash', amount, 'Deposit compensation', groupId, identifier, 'add')
            return finish(claim, result)
        end
    end

    RB.Logger.info('transaction_committed', { operation = 'deposit', groupId = groupId, actor = identifier, account = sourceRef.key, amount = amount })
    return finish(claim, RB.Result.ok({ groupId = groupId, status = 'committed' }))
end

function RB.TransactionService.withdraw(source, payload)
    local limit = RB.RateLimit.check(source, 'withdraw'); if not limit.ok then return limit end
    if not RB.Validation.payload(payload) then return RB.Result.fail(RB.Errors.INVALID_PAYLOAD) end
    local amount, amountError = RB.Money.parse(payload.amount)
    if not amount then return RB.Result.fail(amountError) end
    local claim, early = beginRequest(source, 'withdraw', payload); if early then return early end
    local sourceRef, auth = resolveSource(source, payload, RB.Actions.WITHDRAW)
    if not sourceRef then return finish(claim, auth) end
    local player, identifier, name = actor(source)
    local comment = description(payload.description)
    local groupId = generateId('withdraw')

    if sourceRef.kind == 'personal' then
        local removeBank = RB.Bridge.removeMoney(player, 'bank', frameworkAmount(amount), comment)
        if not removeBank.ok then return finish(claim, removeBank) end
        local addCash = RB.Bridge.addMoney(player, 'cash', frameworkAmount(amount), comment)
        if not addCash.ok then
            compensateFramework(player, 'bank', amount, 'Withdrawal compensation', groupId, identifier, 'add')
            return finish(claim, RB.Result.fail(RB.Errors.FRAMEWORK_OPERATION_FAILED))
        end
        local bank = RB.Bridge.getMoney(player, 'bank')
        local ledgerOk = ledgerPersonal({
            groupId = groupId, requestId = claim.requestId, personalIdentifier = identifier,
            direction = 'debit', transactionType = 'cash_withdrawal', amount = amount,
            balanceAfter = bank.ok and RB.Money.fromFramework(bank.data) or nil,
            actorIdentifier = identifier, counterpartyRef = 'cash', description = comment
        })
        if not ledgerOk then
            local removeCash = RB.Bridge.removeMoney(player, 'cash', frameworkAmount(amount), 'Withdrawal ledger rollback')
            local restoreBank = removeCash.ok and RB.Bridge.addMoney(player, 'bank', frameworkAmount(amount), 'Withdrawal ledger rollback') or RB.Result.fail(RB.Errors.FRAMEWORK_OPERATION_FAILED)
            settlement({ groupId = groupId, framework = RB.Bridge.getName(), identifier = identifier, moneyType = 'bank', direction = 'add', amount = amount, status = restoreBank.ok and 'reversed' or 'manual_review' }, restoreBank.ok and nil or RB.Errors.DATABASE_OPERATION_FAILED)
            return finish(claim, RB.Result.fail(restoreBank.ok and RB.Errors.DATABASE_OPERATION_FAILED or RB.Errors.SETTLEMENT_PENDING))
        end
    else
        local result = mutateDatabase(sourceRef, -amount, {
            groupId = groupId, requestId = claim.requestId, direction = 'debit',
            transactionType = 'cash_withdrawal', amount = amount, actorIdentifier = identifier,
            counterpartyRef = name, description = comment
        })
        if not result.ok then return finish(claim, result) end
        local addCash = RB.Bridge.addMoney(player, 'cash', frameworkAmount(amount), comment)
        if not addCash.ok then
            local compensation = mutateDatabase(sourceRef, amount, {
                groupId = groupId .. ':reversal', requestId = claim.requestId .. ':reversal', direction = 'credit',
                transactionType = 'reversal', amount = amount, actorIdentifier = 'system',
                counterpartyRef = sourceRef.key, description = 'Withdrawal compensation'
            })
            settlement({ groupId = groupId, framework = RB.Bridge.getName(), identifier = identifier, moneyType = 'cash', direction = 'add', amount = amount, status = compensation.ok and 'reversed' or 'manual_review' }, compensation.ok and nil or RB.Errors.DATABASE_OPERATION_FAILED)
            return finish(claim, RB.Result.fail(compensation.ok and RB.Errors.FRAMEWORK_OPERATION_FAILED or RB.Errors.SETTLEMENT_PENDING))
        end
    end

    RB.Logger.info('transaction_committed', { operation = 'withdraw', groupId = groupId, actor = identifier, account = sourceRef.key, amount = amount })
    return finish(claim, RB.Result.ok({ groupId = groupId, status = 'committed' }))
end

local function databaseTransfer(sourceRef, destinationRef, amount, claim, actorIdentifier, comment, groupId)
    return RB.Locks.with({ 'db:' .. sourceRef.id, 'db:' .. destinationRef.id }, function()
        local sourceAccount = Accounts.findById(sourceRef.id)
        local destinationAccount = Accounts.findById(destinationRef.id)
        if not sourceAccount or not destinationAccount then return RB.Result.fail(RB.Errors.ACCOUNT_NOT_FOUND) end
        if sourceAccount.status ~= RB.AccountStatuses.ACTIVE or destinationAccount.status ~= RB.AccountStatuses.ACTIVE then
            local statusError = (sourceAccount.status == RB.AccountStatuses.FROZEN or destinationAccount.status == RB.AccountStatuses.FROZEN)
                and RB.Errors.ACCOUNT_FROZEN or RB.Errors.ACCOUNT_CLOSED
            return RB.Result.fail(statusError)
        end
        local ok, value = Accounts.transferWithLedger(sourceAccount, destinationAccount, amount, {
            groupId = groupId, requestId = claim.requestId, transactionType = 'transfer_debit',
            actorIdentifier = actorIdentifier, counterpartyRef = destinationRef.key, description = comment
        }, {
            groupId = groupId, requestId = claim.requestId, transactionType = 'transfer_credit',
            actorIdentifier = actorIdentifier, counterpartyRef = sourceRef.key, description = comment
        })
        return ok and RB.Result.ok(value) or RB.Result.fail(value)
    end)
end

function RB.TransactionService.transfer(source, payload)
    local limit = RB.RateLimit.check(source, 'transfer'); if not limit.ok then return limit end
    if not RB.Validation.payload(payload) then return RB.Result.fail(RB.Errors.INVALID_PAYLOAD) end
    local amount, amountError = RB.Money.parse(payload.amount)
    if not amount then return RB.Result.fail(amountError) end
    local claim, early = beginRequest(source, 'transfer', payload); if early then return early end
    local sourceRef, sourceAuth = resolveSource(source, payload, RB.Actions.TRANSFER)
    if not sourceRef then return finish(claim, sourceAuth) end
    local destinationRef, destinationResult = resolveDestination(source, payload)
    if not destinationRef then return finish(claim, destinationResult) end
    if sourceRef.kind == destinationRef.kind and sourceRef.key == destinationRef.key then return finish(claim, RB.Result.fail(RB.Errors.SAME_ACCOUNT)) end

    local player, identifier = actor(source)
    local targetPlayer = destinationRef.kind == 'personal' and RB.Bridge.getOnlinePlayerByIdentifier(destinationRef.identifier) or nil
    local comment = description(payload.description)
    local groupId = generateId('transfer')
    local result

    if sourceRef.kind == 'database' and destinationRef.kind == 'database' then
        result = databaseTransfer(sourceRef, destinationRef, amount, claim, identifier, comment, groupId)
    elseif sourceRef.kind == 'personal' and destinationRef.kind == 'personal' then
        local lockResult = RB.Locks.with({ 'personal:' .. identifier, 'personal:' .. destinationRef.identifier }, function()
            local removed = RB.Bridge.removeMoney(player, 'bank', frameworkAmount(amount), comment)
            if not removed.ok then return removed end
            local added = RB.Bridge.addMoney(targetPlayer, 'bank', frameworkAmount(amount), comment)
            if not added.ok then
                compensateFramework(player, 'bank', amount, 'Transfer compensation', groupId, identifier, 'add')
                return RB.Result.fail(RB.Errors.FRAMEWORK_OPERATION_FAILED)
            end
            local sourceBalance = RB.Bridge.getMoney(player, 'bank')
            local targetBalance = RB.Bridge.getMoney(targetPlayer, 'bank')
            local ok = MySQL.transaction.await({
                RB.Repositories.Transactions.queryObject({ groupId = groupId, requestId = claim.requestId, personalIdentifier = identifier, direction = 'debit', transactionType = 'transfer_debit', amount = amount, balanceAfter = sourceBalance.ok and RB.Money.fromFramework(sourceBalance.data) or nil, actorIdentifier = identifier, counterpartyRef = destinationRef.identifier, description = comment }),
                RB.Repositories.Transactions.queryObject({ groupId = groupId, requestId = claim.requestId, personalIdentifier = destinationRef.identifier, direction = 'credit', transactionType = 'transfer_credit', amount = amount, balanceAfter = targetBalance.ok and RB.Money.fromFramework(targetBalance.data) or nil, actorIdentifier = identifier, counterpartyRef = identifier, description = comment })
            })
            if not ok then
                local rollbackTarget = RB.Bridge.removeMoney(targetPlayer, 'bank', frameworkAmount(amount), 'Ledger failure rollback')
                local rollbackSource = rollbackTarget.ok and RB.Bridge.addMoney(player, 'bank', frameworkAmount(amount), 'Ledger failure rollback') or RB.Result.fail(RB.Errors.FRAMEWORK_OPERATION_FAILED)
                settlement({ groupId = groupId, framework = RB.Bridge.getName(), identifier = identifier, moneyType = 'bank', direction = 'add', amount = amount, status = rollbackSource.ok and 'reversed' or 'manual_review' }, rollbackSource.ok and nil or RB.Errors.DATABASE_OPERATION_FAILED)
                return RB.Result.fail(rollbackSource.ok and RB.Errors.DATABASE_OPERATION_FAILED or RB.Errors.SETTLEMENT_PENDING)
            end
            return RB.Result.ok(true)
        end)
        result = lockResult
    elseif sourceRef.kind == 'personal' and destinationRef.kind == 'database' then
        result = RB.Locks.with({ 'personal:' .. identifier, 'db:' .. destinationRef.id }, function()
            local removed = RB.Bridge.removeMoney(player, 'bank', frameworkAmount(amount), comment)
            if not removed.ok then return removed end
            local sourceBalance = RB.Bridge.getMoney(player, 'bank')
            local currentDestination = Accounts.findById(destinationRef.id)
            local ok, value = Accounts.applyDeltaWithLedger(currentDestination, amount, {
                groupId = groupId, requestId = claim.requestId, direction = 'credit', transactionType = 'transfer_credit', amount = amount,
                actorIdentifier = identifier, counterpartyRef = identifier, description = comment, metadata = { personalSource = identifier }
            }, {{
                groupId = groupId, requestId = claim.requestId, personalIdentifier = identifier,
                direction = 'debit', transactionType = 'transfer_debit', amount = amount,
                balanceAfter = sourceBalance.ok and RB.Money.fromFramework(sourceBalance.data) or nil,
                actorIdentifier = identifier, counterpartyRef = destinationRef.key, description = comment
            }})
            if not ok then
                local compensated = compensateFramework(player, 'bank', amount, 'Transfer compensation', groupId, identifier, 'add')
                return RB.Result.fail(compensated and value or RB.Errors.SETTLEMENT_PENDING)
            end
            return RB.Result.ok(value)
        end)
    else
        result = RB.Locks.with({ 'db:' .. sourceRef.id, 'personal:' .. destinationRef.identifier }, function()
            local currentSource = Accounts.findById(sourceRef.id)
            if not currentSource then return RB.Result.fail(RB.Errors.ACCOUNT_NOT_FOUND) end
            if currentSource.balance < amount then return RB.Result.fail(RB.Errors.INSUFFICIENT_FUNDS) end
            if currentSource.status ~= RB.AccountStatuses.ACTIVE then
                return RB.Result.fail(currentSource.status == RB.AccountStatuses.FROZEN and RB.Errors.ACCOUNT_FROZEN or RB.Errors.ACCOUNT_CLOSED)
            end
            local added = RB.Bridge.addMoney(targetPlayer, 'bank', frameworkAmount(amount), comment)
            if not added.ok then return added end
            local targetBalance = RB.Bridge.getMoney(targetPlayer, 'bank')
            local ok, value = Accounts.applyDeltaWithLedger(currentSource, -amount, {
                groupId = groupId, requestId = claim.requestId, direction = 'debit', transactionType = 'transfer_debit', amount = amount,
                actorIdentifier = identifier, counterpartyRef = destinationRef.identifier, description = comment
            }, {{
                groupId = groupId, requestId = claim.requestId, personalIdentifier = destinationRef.identifier,
                direction = 'credit', transactionType = 'transfer_credit', amount = amount,
                balanceAfter = targetBalance.ok and RB.Money.fromFramework(targetBalance.data) or nil,
                actorIdentifier = identifier, counterpartyRef = sourceRef.key, description = comment
            }})
            if not ok then
                local rollback = RB.Bridge.removeMoney(targetPlayer, 'bank', frameworkAmount(amount), 'Transfer database rollback')
                settlement({ groupId = groupId, framework = RB.Bridge.getName(), identifier = destinationRef.identifier, moneyType = 'bank', direction = 'remove', amount = amount, status = rollback.ok and 'reversed' or 'manual_review' }, rollback.ok and nil or RB.Errors.FRAMEWORK_OPERATION_FAILED)
                return RB.Result.fail(rollback.ok and value or RB.Errors.SETTLEMENT_PENDING)
            end
            return RB.Result.ok(value)
        end)
    end

    if not result.ok then return finish(claim, result) end
    RB.Logger.info('transaction_committed', { operation = 'transfer', groupId = groupId, actor = identifier, sourceAccount = sourceRef.key, destinationAccount = destinationRef.key, amount = amount })
    return finish(claim, RB.Result.ok({ groupId = groupId, status = 'committed' }))
end

function RB.TransactionService.adjustDatabaseAccount(accountKey, amount, direction, context)
    context = context or {}
    if direction ~= 'credit' and direction ~= 'debit' then return RB.Result.fail(RB.Errors.INVALID_PAYLOAD) end
    local account = Accounts.findByKey(accountKey)
    if not account then return RB.Result.fail(RB.Errors.ACCOUNT_NOT_FOUND) end
    local parsed = type(amount) == 'number' and amount or RB.Money.parse(amount)
    if not parsed or parsed <= 0 then return RB.Result.fail(RB.Errors.INVALID_AMOUNT) end
    local groupId = generateId('adjustment')
    local delta = direction == 'debit' and -parsed or parsed
    return mutateDatabase(databaseRef(account), delta, {
        groupId = groupId, requestId = context.requestId or groupId,
        direction = direction, transactionType = direction == 'debit' and 'admin_debit' or 'admin_credit',
        amount = parsed, actorIdentifier = context.actor or 'system', counterpartyRef = context.resource or 'server',
        description = description(context.reason)
    })
end

function RB.TransactionService.appendExternalTransaction(accountKey, data)
    local account = Accounts.findByKey(accountKey)
    local entry = {
        groupId = data.groupId or generateId('external'), requestId = data.requestId or generateId('external-request'),
        accountId = account and account.id or nil, personalIdentifier = account and nil or accountKey,
        direction = data.direction, transactionType = data.transactionType or 'external', amount = data.amount,
        actorIdentifier = data.actor or data.resource, counterpartyRef = data.counterparty, description = description(data.description), metadata = data.metadata
    }
    local id = Transactions.insert(entry)
    return id and RB.Result.ok({ id = id, groupId = entry.groupId }) or RB.Result.fail(RB.Errors.DATABASE_OPERATION_FAILED)
end
