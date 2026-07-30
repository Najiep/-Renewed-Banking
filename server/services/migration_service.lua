RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

RB.Migration = {}
RB.State = RB.State or { migrationRequired = false, schemaReady = false }

local function tableExists(name)
    return tonumber(MySQL.scalar.await([=[
        SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_name = ?
    ]=], { name })) > 0
end

local function splitStatements(sql)
    sql = sql:gsub('%-%-[^\n]*', '')
    local result = {}
    for statement in sql:gmatch('([^;]+);') do
        statement = statement:match('^%s*(.-)%s*$')
        if statement ~= '' then result[#result + 1] = statement end
    end
    return result
end

function RB.Migration.runSchema()
    MySQL.query.await([=[
        CREATE TABLE IF NOT EXISTS renewed_bank_schema_migrations (
            version VARCHAR(64) NOT NULL PRIMARY KEY,
            applied_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]=])
    for _, path in ipairs(Config.v3.migrationFiles or {}) do
        local version = path:match('([^/]+)%.sql$') or path
        if not MySQL.scalar.await('SELECT 1 FROM renewed_bank_schema_migrations WHERE version = ? LIMIT 1', { version }) then
            local sql = LoadResourceFile(GetCurrentResourceName(), path)
            if not sql then error(('[Renewed-Banking] Missing migration file %s'):format(path)) end
            for _, statement in ipairs(splitStatements(sql)) do MySQL.query.await(statement) end
            MySQL.insert.await('INSERT INTO renewed_bank_schema_migrations (version) VALUES (?)', { version })
            RB.Logger.info('migration_applied', { version = version })
        end
    end
    RB.State.schemaReady = true
end

function RB.Migration.detectLegacy()
    local legacyAccounts = tableExists('bank_accounts_new') and (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM bank_accounts_new')) or 0) or 0
    local legacyPlayers = tableExists('player_transactions') and (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM player_transactions')) or 0) or 0
    local v3Accounts = tableExists('renewed_bank_accounts') and (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM renewed_bank_accounts')) or 0) or 0
    local v3Transactions = tableExists('renewed_bank_transactions') and (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM renewed_bank_transactions')) or 0) or 0
    RB.State.migrationRequired = (legacyAccounts > 0 or legacyPlayers > 0) and v3Accounts == 0 and v3Transactions == 0
    return RB.State.migrationRequired
end

local function decode(value, fallback)
    if type(value) ~= 'string' or value == '' then return fallback end
    local ok, result = pcall(json.decode, value)
    return ok and result or fallback
end

local function classify(key, creator)
    if creator and creator ~= '' then return RB.AccountTypes.SHARED end
    for _, group in ipairs(RB.Bridge.getDefinedGroups()) do
        if group.name == key then return group.type, group.label end
    end
    return RB.AccountTypes.SYSTEM
end

function RB.Migration.dryRun()
    local accountRows = tableExists('bank_accounts_new') and (MySQL.query.await('SELECT * FROM bank_accounts_new') or {}) or {}
    local playerRows = tableExists('player_transactions') and (MySQL.query.await('SELECT * FROM player_transactions') or {}) or {}
    local report = {
        legacyAccounts = #accountRows, legacyPlayers = #playerRows, totalBalance = 0,
        transactionCount = 0, personalTransactionCount = 0, memberCount = 0,
        frozenPersonalAccounts = 0, malformedTransactions = 0,
        malformedPersonalTransactions = 0, malformedMembers = 0
    }
    for _, row in ipairs(accountRows) do
        report.totalBalance = report.totalBalance + (tonumber(row.amount) or 0)
        local transactions = decode(row.transactions, nil)
        if type(transactions) == 'table' then report.transactionCount = report.transactionCount + #transactions else report.malformedTransactions = report.malformedTransactions + 1 end
        local members = decode(row.auth, nil)
        if type(members) == 'table' then report.memberCount = report.memberCount + #members else report.malformedMembers = report.malformedMembers + 1 end
    end
    for _, row in ipairs(playerRows) do
        if tonumber(row.isFrozen) == 1 then report.frozenPersonalAccounts = report.frozenPersonalAccounts + 1 end
        local transactions = decode(row.transactions, nil)
        if type(transactions) == 'table' then report.personalTransactionCount = report.personalTransactionCount + #transactions else report.malformedPersonalTransactions = report.malformedPersonalTransactions + 1 end
    end
    return RB.Result.ok(report)
end

function RB.Migration.importV2(actor)
    local hasLegacyAccounts = tableExists('bank_accounts_new')
    local hasLegacyPlayers = tableExists('player_transactions')
    if not hasLegacyAccounts and not hasLegacyPlayers then return RB.Result.fail(RB.Errors.ACCOUNT_NOT_FOUND, 'Legacy banking tables not found') end
    local existingAccounts = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM renewed_bank_accounts')) or 0
    local existingTransactions = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM renewed_bank_transactions')) or 0
    local existingPersonalStatus = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM renewed_bank_personal_status')) or 0
    if existingAccounts > 0 or existingTransactions > 0 or existingPersonalStatus > 0 then
        return RB.Result.fail(RB.Errors.INVALID_PAYLOAD, 'V3 data tables are not empty')
    end
    local rows = hasLegacyAccounts and (MySQL.query.await('SELECT * FROM bank_accounts_new') or {}) or {}
    local playerRows = hasLegacyPlayers and (MySQL.query.await('SELECT * FROM player_transactions') or {}) or {}
    local imported = { accounts = 0, personalAccounts = 0, members = 0, transactions = 0, totalBalance = 0, warnings = {} }
    for _, row in ipairs(rows) do
        local accountType, frameworkLabel = classify(row.id, row.creator)
        local status = tonumber(row.isFrozen) == 1 and RB.AccountStatuses.FROZEN or RB.AccountStatuses.ACTIVE
        local account = RB.Repositories.Accounts.create({
            accountKey = row.id,
            displayName = frameworkLabel or row.id,
            accountType = accountType,
            ownerIdentifier = row.creator,
            balance = tonumber(row.amount) or 0,
            status = status,
            metadata = { legacy = true }
        })
        if not account then error(('Failed importing legacy account %s'):format(row.id)) end
        imported.accounts = imported.accounts + 1
        imported.totalBalance = imported.totalBalance + account.balance
        local members = decode(row.auth, {})
        local seen = {}
        if row.creator and row.creator ~= '' then
            RB.Repositories.Members.upsert(account.id, row.creator, RB.Roles.OWNER, actor)
            seen[row.creator] = true; imported.members = imported.members + 1
        end
        for _, identifier in ipairs(type(members) == 'table' and members or {}) do
            if type(identifier) == 'string' and not seen[identifier] then
                RB.Repositories.Members.upsert(account.id, identifier, RB.Roles.OPERATOR, actor)
                seen[identifier] = true; imported.members = imported.members + 1
            end
        end
        if account.balance > 0 then
            RB.Repositories.Transactions.insert({
                groupId = 'migration:' .. row.id,
                requestId = 'migration:' .. row.id,
                accountId = account.id,
                direction = 'credit', transactionType = 'migration_credit', amount = account.balance,
                balanceBefore = 0, balanceAfter = account.balance, actorIdentifier = actor,
                counterpartyRef = 'legacy_v2', description = 'Imported opening balance', metadata = { legacy = true }
            })
            imported.transactions = imported.transactions + 1
        end
        local transactions = decode(row.transactions, {})
        if type(transactions) == 'table' then
            for index, tx in ipairs(transactions) do
                local amount = tonumber(tx.amount)
                if amount and amount > 0 then
                    RB.Repositories.Transactions.insert({
                        groupId = tostring(tx.trans_id or ('legacy:' .. row.id .. ':' .. index)),
                        requestId = 'legacy:' .. row.id .. ':' .. index,
                        accountId = account.id,
                        direction = tx.trans_type == 'withdraw' and 'debit' or 'credit',
                        transactionType = 'legacy_' .. tostring(tx.trans_type or 'entry'),
                        amount = amount,
                        actorIdentifier = actor,
                        counterpartyRef = tostring(tx.receiver or tx.issuer or 'legacy'),
                        description = RB.Validation.text(tostring(tx.message or 'Legacy transaction'), 255, true),
                        metadata = { legacy = true, original = tx }
                    })
                    imported.transactions = imported.transactions + 1
                end
            end
        end
    end
    for _, row in ipairs(playerRows) do
        local identifier = RB.Validation.identifier(row.id)
        if identifier then
            RB.Repositories.Players.setFrozen(identifier, tonumber(row.isFrozen) == 1)
            imported.personalAccounts = imported.personalAccounts + 1
            local transactions = decode(row.transactions, {})
            if type(transactions) == 'table' then
                for index, tx in ipairs(transactions) do
                    local amount = tonumber(tx.amount)
                    if amount and amount > 0 then
                        RB.Repositories.Transactions.insert({
                            groupId = tostring(tx.trans_id or ('legacy-personal:' .. identifier .. ':' .. index)),
                            requestId = 'legacy-personal:' .. identifier .. ':' .. index,
                            personalIdentifier = identifier,
                            direction = tx.trans_type == 'withdraw' and 'debit' or 'credit',
                            transactionType = 'legacy_' .. tostring(tx.trans_type or 'entry'),
                            amount = amount,
                            actorIdentifier = actor,
                            counterpartyRef = tostring(tx.receiver or tx.issuer or 'legacy'),
                            description = RB.Validation.text(tostring(tx.message or 'Legacy personal transaction'), 255, true),
                            metadata = { legacy = true, original = tx }
                        })
                        imported.transactions = imported.transactions + 1
                    end
                end
            end
        else
            imported.warnings[#imported.warnings + 1] = { type = 'invalid_personal_identifier', value = tostring(row.id) }
        end
    end
    RB.State.migrationRequired = false
    RB.Logger.info('legacy_import_completed', imported)
    return RB.Result.ok(imported)
end

function RB.Migration.verify()
    local result = { accountCount = 0, totalBalance = 0, memberCount = 0, transactionCount = 0, legacyTotalBalance = nil, balanceDifference = nil }
    result.accountCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM renewed_bank_accounts')) or 0
    result.totalBalance = tonumber(MySQL.scalar.await('SELECT COALESCE(SUM(balance), 0) FROM renewed_bank_accounts')) or 0
    result.memberCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM renewed_bank_account_members')) or 0
    result.personalStatusCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM renewed_bank_personal_status')) or 0
    result.frozenPersonalCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM renewed_bank_personal_status WHERE is_frozen = 1')) or 0
    result.transactionCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM renewed_bank_transactions')) or 0
    if tableExists('bank_accounts_new') then
        result.legacyTotalBalance = tonumber(MySQL.scalar.await('SELECT COALESCE(SUM(amount), 0) FROM bank_accounts_new')) or 0
        result.balanceDifference = result.totalBalance - result.legacyTotalBalance
    end
    return RB.Result.ok(result)
end
