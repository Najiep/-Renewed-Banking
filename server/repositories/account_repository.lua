RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking
RB.Repositories = RB.Repositories or {}

local Repository = {}
RB.Repositories.Accounts = Repository

local selectFields = [[
    id, account_key, display_name, account_type, owner_identifier, currency,
    balance, status, version, metadata, created_at, updated_at, closed_at
]]

local function decode(row)
    if not row then return nil end
    row.balance = tonumber(row.balance) or 0
    row.version = tonumber(row.version) or 0
    if type(row.metadata) == 'string' and row.metadata ~= '' then
        local ok, value = pcall(json.decode, row.metadata)
        row.metadata = ok and value or {}
    elseif type(row.metadata) ~= 'table' then
        row.metadata = {}
    end
    return row
end

function Repository.findById(id)
    return decode(MySQL.single.await(('SELECT %s FROM renewed_bank_accounts WHERE id = ? LIMIT 1'):format(selectFields), { id }))
end

function Repository.findByKey(key)
    return decode(MySQL.single.await(('SELECT %s FROM renewed_bank_accounts WHERE account_key = ? LIMIT 1'):format(selectFields), { key }))
end

function Repository.listByKeys(keys)
    if type(keys) ~= 'table' or #keys == 0 then return {} end
    local placeholders = {}
    for i = 1, #keys do placeholders[i] = '?' end
    local values = {}
    for i = 1, #keys do values[i] = keys[i] end
    values[#values + 1] = RB.AccountStatuses.CLOSED
    local rows = MySQL.query.await(('SELECT %s FROM renewed_bank_accounts WHERE account_key IN (%s) AND status <> ? ORDER BY display_name'):format(selectFields, table.concat(placeholders, ',')), values) or {}
    for i = 1, #rows do rows[i] = decode(rows[i]) end
    return rows
end

function Repository.listForMember(identifier)
    local rows = MySQL.query.await(([=[
        SELECT a.id, a.account_key, a.display_name, a.account_type, a.owner_identifier,
               a.currency, a.balance, a.status, a.version, a.metadata,
               a.created_at, a.updated_at, a.closed_at, m.role AS member_role
        FROM renewed_bank_accounts a
        INNER JOIN renewed_bank_account_members m ON m.account_id = a.id
        WHERE m.member_identifier = ? AND a.status <> ?
        ORDER BY a.display_name
    ]=]), { identifier, RB.AccountStatuses.CLOSED }) or {}
    for i = 1, #rows do rows[i] = decode(rows[i]) end
    return rows
end

function Repository.countOwned(identifier)
    return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM renewed_bank_accounts WHERE owner_identifier = ? AND account_type = ? AND status <> ?', {
        identifier, RB.AccountTypes.SHARED, RB.AccountStatuses.CLOSED
    })) or 0
end

function Repository.create(data)
    local id = MySQL.insert.await([=[
        INSERT INTO renewed_bank_accounts
            (account_key, display_name, account_type, owner_identifier, currency, balance, status, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]=], {
        data.accountKey, data.displayName, data.accountType, data.ownerIdentifier,
        data.currency or Config.currency.code, data.balance or 0,
        data.status or RB.AccountStatuses.ACTIVE, json.encode(data.metadata or {})
    })
    return id and Repository.findById(id) or nil
end

function Repository.rename(id, displayName)
    return MySQL.update.await('UPDATE renewed_bank_accounts SET display_name = ?, version = version + 1 WHERE id = ? AND status <> ?', {
        displayName, id, RB.AccountStatuses.CLOSED
    }) > 0
end

function Repository.setStatus(id, status)
    return MySQL.update.await('UPDATE renewed_bank_accounts SET status = ?, version = version + 1 WHERE id = ?', { status, id }) > 0
end

function Repository.close(id)
    return MySQL.update.await('UPDATE renewed_bank_accounts SET status = ?, closed_at = CURRENT_TIMESTAMP(3), version = version + 1 WHERE id = ? AND balance = 0 AND status <> ?', {
        RB.AccountStatuses.CLOSED, id, RB.AccountStatuses.CLOSED
    }) > 0
end

function Repository.deleteById(id)
    return MySQL.update.await('DELETE FROM renewed_bank_accounts WHERE id = ?', { id }) > 0
end

function Repository.updateBalanceOptimistic(id, expectedVersion, amountDelta)
    return MySQL.update.await([=[
        UPDATE renewed_bank_accounts
        SET balance = balance + ?, version = version + 1
        WHERE id = ? AND version = ? AND balance + ? >= 0 AND status = ?
    ]=], { amountDelta, id, expectedVersion, amountDelta, RB.AccountStatuses.ACTIVE })
end

function Repository.legacyShape(account)
    if not account then return nil end
    return {
        id = account.account_key,
        name = account.display_name,
        type = account.account_type,
        amount = account.balance,
        frozen = account.status == RB.AccountStatuses.FROZEN,
        creator = account.owner_identifier,
        auth = {},
        transactions = {}
    }
end

function Repository.applyDeltaWithLedger(account, delta, entry, additionalEntries)
    local newBalance = account.balance + delta
    if newBalance < 0 then return false, RB.Errors.INSUFFICIENT_FUNDS end
    local newVersion = account.version + 1
    local transaction = {
        {
            query = [=[
                UPDATE renewed_bank_accounts
                SET balance = ?, version = ?
                WHERE id = ? AND version = ? AND status = ? AND ? >= 0
            ]=],
            values = { newBalance, newVersion, account.id, account.version, RB.AccountStatuses.ACTIVE, newBalance }
        },
        {
            query = [=[
                INSERT INTO renewed_bank_transactions
                    (group_id, request_id, account_id, personal_identifier, direction,
                     transaction_type, amount, balance_before, balance_after, actor_identifier,
                     counterparty_ref, description, metadata)
                SELECT ?, ?, id, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?
                FROM renewed_bank_accounts
                WHERE id = ? AND version = ? AND balance = ?
            ]=],
            values = {
                entry.groupId, entry.requestId, entry.direction, entry.transactionType,
                entry.amount, account.balance, newBalance, entry.actorIdentifier,
                entry.counterpartyRef, entry.description, json.encode(entry.metadata or {}),
                account.id, newVersion, newBalance
            }
        }
    }
    for _, extra in ipairs(additionalEntries or {}) do
        transaction[#transaction + 1] = {
            query = [=[
                INSERT INTO renewed_bank_transactions
                    (group_id, request_id, account_id, personal_identifier, direction,
                     transaction_type, amount, balance_before, balance_after, actor_identifier,
                     counterparty_ref, description, metadata)
                SELECT ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
                FROM renewed_bank_accounts
                WHERE id = ? AND version = ? AND balance = ?
            ]=],
            values = {
                extra.groupId, extra.requestId, extra.personalIdentifier, extra.direction,
                extra.transactionType, extra.amount, extra.balanceBefore, extra.balanceAfter,
                extra.actorIdentifier, extra.counterpartyRef, extra.description,
                json.encode(extra.metadata or {}), account.id, newVersion, newBalance
            }
        }
    end
    local ok = MySQL.transaction.await(transaction)
    if not ok then return false, RB.Errors.DATABASE_OPERATION_FAILED end
    local current = Repository.findById(account.id)
    local expectedEntries = 1 + #(additionalEntries or {})
    if not current or current.version ~= newVersion or current.balance ~= newBalance
        or RB.Repositories.Transactions.countGroup(entry.groupId) < expectedEntries then
        return false, RB.Errors.SERVICE_UNAVAILABLE
    end
    return true, current
end

function Repository.transferWithLedger(source, destination, amount, debitEntry, creditEntry)
    if source.balance < amount then return false, RB.Errors.INSUFFICIENT_FUNDS end
    local sourceAfter = source.balance - amount
    local destinationAfter = destination.balance + amount
    local sourceVersion = source.version + 1
    local destinationVersion = destination.version + 1
    local transactions = {
        {
            query = [=[
                UPDATE renewed_bank_accounts AS source
                INNER JOIN renewed_bank_accounts AS destination ON destination.id = ?
                SET source.balance = ?, source.version = ?,
                    destination.balance = ?, destination.version = ?
                WHERE source.id = ? AND source.version = ? AND destination.version = ?
                  AND source.status = ? AND destination.status = ? AND source.balance >= ?
            ]=],
            values = {
                destination.id, sourceAfter, sourceVersion, destinationAfter, destinationVersion,
                source.id, source.version, destination.version,
                RB.AccountStatuses.ACTIVE, RB.AccountStatuses.ACTIVE, amount
            }
        },
        {
            query = [=[
                INSERT INTO renewed_bank_transactions
                    (group_id, request_id, account_id, direction, transaction_type, amount,
                     balance_before, balance_after, actor_identifier, counterparty_ref, description, metadata)
                SELECT ?, ?, source.id, 'debit', ?, ?, ?, ?, ?, ?, ?, ?
                FROM renewed_bank_accounts source
                INNER JOIN renewed_bank_accounts destination ON destination.id = ?
                WHERE source.id = ? AND source.version = ? AND destination.version = ?
                  AND source.balance = ? AND destination.balance = ?
            ]=],
            values = {
                debitEntry.groupId, debitEntry.requestId, debitEntry.transactionType, amount,
                source.balance, sourceAfter, debitEntry.actorIdentifier, debitEntry.counterpartyRef,
                debitEntry.description, json.encode(debitEntry.metadata or {}),
                destination.id, source.id, sourceVersion, destinationVersion, sourceAfter, destinationAfter
            }
        },
        {
            query = [=[
                INSERT INTO renewed_bank_transactions
                    (group_id, request_id, account_id, direction, transaction_type, amount,
                     balance_before, balance_after, actor_identifier, counterparty_ref, description, metadata)
                SELECT ?, ?, destination.id, 'credit', ?, ?, ?, ?, ?, ?, ?, ?
                FROM renewed_bank_accounts source
                INNER JOIN renewed_bank_accounts destination ON destination.id = ?
                WHERE source.id = ? AND source.version = ? AND destination.version = ?
                  AND source.balance = ? AND destination.balance = ?
            ]=],
            values = {
                creditEntry.groupId, creditEntry.requestId, creditEntry.transactionType, amount,
                destination.balance, destinationAfter, creditEntry.actorIdentifier, creditEntry.counterpartyRef,
                creditEntry.description, json.encode(creditEntry.metadata or {}),
                destination.id, source.id, sourceVersion, destinationVersion, sourceAfter, destinationAfter
            }
        }
    }
    local ok = MySQL.transaction.await(transactions)
    if not ok then return false, RB.Errors.DATABASE_OPERATION_FAILED end
    local sourceCurrent = Repository.findById(source.id)
    local destinationCurrent = Repository.findById(destination.id)
    if not sourceCurrent or not destinationCurrent
        or sourceCurrent.version ~= sourceVersion or destinationCurrent.version ~= destinationVersion
        or sourceCurrent.balance ~= sourceAfter or destinationCurrent.balance ~= destinationAfter
        or RB.Repositories.Transactions.countGroup(debitEntry.groupId) < 2 then
        return false, RB.Errors.SERVICE_UNAVAILABLE
    end
    return true, { source = sourceCurrent, destination = destinationCurrent }
end
