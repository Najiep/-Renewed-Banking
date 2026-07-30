RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking
RB.Repositories = RB.Repositories or {}

local Repository = {}
RB.Repositories.Transactions = Repository

local insertSql = [=[
    INSERT INTO renewed_bank_transactions
        (group_id, request_id, account_id, personal_identifier, direction,
         transaction_type, amount, balance_before, balance_after, actor_identifier,
         counterparty_ref, description, metadata)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
]=]

function Repository.insert(entry)
    return MySQL.insert.await(insertSql, {
        entry.groupId, entry.requestId, entry.accountId, entry.personalIdentifier,
        entry.direction, entry.transactionType, entry.amount, entry.balanceBefore,
        entry.balanceAfter, entry.actorIdentifier, entry.counterpartyRef,
        entry.description, json.encode(entry.metadata or {})
    })
end

function Repository.queryObject(entry)
    return {
        query = insertSql,
        values = {
            entry.groupId, entry.requestId, entry.accountId, entry.personalIdentifier,
            entry.direction, entry.transactionType, entry.amount, entry.balanceBefore,
            entry.balanceAfter, entry.actorIdentifier, entry.counterpartyRef,
            entry.description, json.encode(entry.metadata or {})
        }
    }
end

function Repository.countGroup(groupId)
    return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM renewed_bank_transactions WHERE group_id = ?', { groupId })) or 0
end

function Repository.listForAccount(accountId, cursor, limit, filters)
    limit = math.min(math.max(tonumber(limit) or Config.v3.statementPageSize, 1), Config.v3.maximumStatementPageSize)
    cursor = tonumber(cursor) or 9223372036854775807
    filters = type(filters) == 'table' and filters or {}
    local where = { 'account_id = ?', 'id < ?' }
    local values = { accountId, cursor }
    if filters.direction == 'debit' or filters.direction == 'credit' then where[#where + 1] = 'direction = ?'; values[#values + 1] = filters.direction end
    if type(filters.transactionType) == 'string' and filters.transactionType ~= '' then where[#where + 1] = 'transaction_type = ?'; values[#values + 1] = filters.transactionType end
    if tonumber(filters.minimumAmount) then where[#where + 1] = 'amount >= ?'; values[#values + 1] = tonumber(filters.minimumAmount) end
    if tonumber(filters.maximumAmount) then where[#where + 1] = 'amount <= ?'; values[#values + 1] = tonumber(filters.maximumAmount) end
    if type(filters.search) == 'string' and filters.search ~= '' then
        where[#where + 1] = '(description LIKE ? OR counterparty_ref LIKE ? OR group_id = ?)'
        local term = '%' .. filters.search:sub(1, 64) .. '%'
        values[#values + 1] = term; values[#values + 1] = term; values[#values + 1] = filters.search:sub(1, 80)
    end
    values[#values + 1] = limit + 1
    local rows = MySQL.query.await(('SELECT * FROM renewed_bank_transactions WHERE %s ORDER BY id DESC LIMIT ?'):format(table.concat(where, ' AND ')), values) or {}
    local hasMore = #rows > limit
    if hasMore then table.remove(rows) end
    for _, row in ipairs(rows) do
        row.amount = tonumber(row.amount) or 0
        row.balance_before = row.balance_before and tonumber(row.balance_before) or nil
        row.balance_after = row.balance_after and tonumber(row.balance_after) or nil
        if type(row.metadata) == 'string' and row.metadata ~= '' then
            local ok, decoded = pcall(json.decode, row.metadata)
            row.metadata = ok and decoded or {}
        end
    end
    return { items = rows, nextCursor = hasMore and rows[#rows] and rows[#rows].id or nil, hasMore = hasMore }
end

function Repository.listForPersonal(identifier, cursor, limit, filters)
    limit = math.min(math.max(tonumber(limit) or Config.v3.statementPageSize, 1), Config.v3.maximumStatementPageSize)
    cursor = tonumber(cursor) or 9223372036854775807
    filters = type(filters) == 'table' and filters or {}
    local where = { 'personal_identifier = ?', 'id < ?' }
    local values = { identifier, cursor }
    if filters.direction == 'debit' or filters.direction == 'credit' then where[#where + 1] = 'direction = ?'; values[#values + 1] = filters.direction end
    if type(filters.transactionType) == 'string' and filters.transactionType ~= '' then where[#where + 1] = 'transaction_type = ?'; values[#values + 1] = filters.transactionType end
    if tonumber(filters.minimumAmount) then where[#where + 1] = 'amount >= ?'; values[#values + 1] = tonumber(filters.minimumAmount) end
    if tonumber(filters.maximumAmount) then where[#where + 1] = 'amount <= ?'; values[#values + 1] = tonumber(filters.maximumAmount) end
    if type(filters.search) == 'string' and filters.search ~= '' then
        where[#where + 1] = '(description LIKE ? OR counterparty_ref LIKE ? OR group_id = ?)'
        local term = '%' .. filters.search:sub(1, 64) .. '%'
        values[#values + 1] = term; values[#values + 1] = term; values[#values + 1] = filters.search:sub(1, 80)
    end
    values[#values + 1] = limit + 1
    local rows = MySQL.query.await(('SELECT * FROM renewed_bank_transactions WHERE %s ORDER BY id DESC LIMIT ?'):format(table.concat(where, ' AND ')), values) or {}
    local hasMore = #rows > limit
    if hasMore then table.remove(rows) end
    for _, row in ipairs(rows) do
        row.amount = tonumber(row.amount) or 0
        row.balance_before = row.balance_before and tonumber(row.balance_before) or nil
        row.balance_after = row.balance_after and tonumber(row.balance_after) or nil
        if type(row.metadata) == 'string' and row.metadata ~= '' then
            local ok, decoded = pcall(json.decode, row.metadata)
            row.metadata = ok and decoded or {}
        end
    end
    return { items = rows, nextCursor = hasMore and rows[#rows] and rows[#rows].id or nil, hasMore = hasMore }
end
