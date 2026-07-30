local cachedAccounts = {}
local cachedPlayers = {}
local accountLocks = {}
local resourceName = GetCurrentResourceName()

local createTables = {
    {
        query = "CREATE TABLE IF NOT EXISTS `bank_accounts_new` (`id` varchar(50) NOT NULL, `amount` int(11) DEFAULT 0, `transactions` longtext DEFAULT '[]', `auth` longtext DEFAULT '[]', `isFrozen` int(11) DEFAULT 0, `creator` varchar(50) DEFAULT NULL, PRIMARY KEY (`id`));",
        values = nil
    },
    {
        query = "CREATE TABLE IF NOT EXISTS `player_transactions` (`id` varchar(50) NOT NULL, `isFrozen` int(11) DEFAULT 0, `transactions` longtext DEFAULT '[]', PRIMARY KEY (`id`));",
        values = nil
    }
}

assert(MySQL.transaction.await(createTables), 'Failed to create Renewed-Banking tables')

local function notifyError(source, message)
    BankingSecurity.notify(source, message, 'error')
end

local function safeDecode(value, fallback)
    if type(value) ~= 'string' or value == '' then return fallback end

    local success, decoded = pcall(json.decode, value)
    if not success or type(decoded) ~= 'table' then
        return fallback
    end

    return decoded
end

local function isFrozen(value)
    return value == true or value == 1 or value == '1'
end

local function isAccountFrozen(accountId, identifier)
    local account = cachedAccounts[accountId]
    if account then return isFrozen(account.frozen) end

    local playerAccount = identifier and cachedPlayers[identifier]
    return playerAccount and isFrozen(playerAccount.isFrozen) or false
end

local function playerHasJobAccess(Player, accountId)
    local jobs = GetJobs(Player)
    if type(jobs) ~= 'table' then return false end

    if jobs.name then
        return jobs.name == accountId and IsJobAuth(jobs.name, jobs.grade)
    end

    for index = 1, #jobs do
        local job = jobs[index]
        if job and job.name == accountId and IsJobAuth(job.name, job.grade) then
            return true
        end
    end

    return false
end

local function playerHasGangAccess(Player, accountId)
    local gang = GetGang(Player)
    return gang and gang == accountId and IsGangAuth(Player, gang) or false
end

local function canAccessAccount(source, accountId, action)
    local Player = GetPlayerObject(source)
    if not Player then return false, 'PLAYER_NOT_FOUND' end

    local identifier = GetIdentifier(Player)
    if not identifier then return false, 'IDENTIFIER_NOT_FOUND' end

    if accountId == identifier then
        if action == 'manage' then return false, 'UNAUTHORIZED' end
        return true, 'personal', Player, identifier
    end

    local account = cachedAccounts[accountId]
    if not account then return false, 'ACCOUNT_NOT_FOUND' end

    if account.creator then
        local authorized = account.creator == identifier or account.auth[identifier] == true
        if not authorized then return false, 'UNAUTHORIZED' end

        if action == 'manage' and account.creator ~= identifier then
            return false, 'UNAUTHORIZED'
        end

        return true, 'shared', Player, identifier
    end

    if account.auth[identifier] == true
        or playerHasJobAccess(Player, accountId)
        or playerHasGangAccess(Player, accountId) then
        if action == 'manage' then return false, 'UNAUTHORIZED' end
        return true, 'organization', Player, identifier
    end

    return false, 'UNAUTHORIZED'
end

local function auditRejected(action, source, accountId, reason)
    BankingSecurity.audit('rejected_' .. action, source, {
        account = tostring(accountId),
        reason = reason
    })
end

local function authorizeOrNotify(source, accountId, action)
    local allowed, accountType, Player, identifier = canAccessAccount(source, accountId, action)
    if allowed then return accountType, Player, identifier end

    auditRejected(action, source, accountId, accountType)
    if accountType == 'ACCOUNT_NOT_FOUND' then
        notifyError(source, 'The selected bank account could not be found.')
    else
        notifyError(source, 'You are not authorized to use this bank account.')
    end

    return nil
end

local function guardRequest(source, action, fingerprint)
    local allowed, retryAfter = BankingSecurity.checkRateLimit(source, action)
    if not allowed then
        BankingSecurity.audit('rate_limited', source, {
            action = action,
            retryAfter = retryAfter
        })
        notifyError(source, 'Please wait before trying that banking action again.')
        return false
    end

    if fingerprint and not BankingSecurity.claimDuplicate(source, action, fingerprint) then
        BankingSecurity.audit('duplicate_request', source, { action = action })
        notifyError(source, 'This banking request was already submitted.')
        return false
    end

    return true
end

local function buildFingerprint(data)
    if type(data) ~= 'table' then return tostring(data) end

    return table.concat({
        tostring(data.fromAccount or ''),
        tostring(data.stateid or ''),
        tostring(data.amount or ''),
        tostring(data.comment or '')
    }, '|')
end

local function acquireLocks(keys)
    local unique = {}

    for index = 1, #keys do
        local key = tostring(keys[index])
        unique[key] = true
    end

    local ordered = {}
    for key in pairs(unique) do
        ordered[#ordered + 1] = key
    end
    table.sort(ordered)

    for index = 1, #ordered do
        if accountLocks[ordered[index]] then
            return nil
        end
    end

    for index = 1, #ordered do
        accountLocks[ordered[index]] = true
    end

    return ordered
end

local function releaseLocks(keys)
    if not keys then return end

    for index = 1, #keys do
        accountLocks[keys[index]] = nil
    end
end

local function withLocks(keys, callback)
    local acquired = acquireLocks(keys)
    if not acquired then return false, 'ACCOUNT_BUSY' end

    local success, resultA, resultB = xpcall(callback, debug.traceback)
    releaseLocks(acquired)

    if not success then
        print(('^1[Renewed-Banking]^0 Protected operation failed: %s'):format(resultA))
        return false, 'INTERNAL_ERROR'
    end

    return resultA, resultB
end

function UpdatePlayerAccount(identifier)
    if type(identifier) ~= 'string' or identifier == '' then return false end

    local account = MySQL.single.await(
        'SELECT `isFrozen`, `transactions` FROM `player_transactions` WHERE `id` = ? LIMIT 1',
        { identifier }
    )

    local query = '%' .. identifier .. '%'
    local possibleShared = MySQL.query.await(
        'SELECT `id`, `auth` FROM `bank_accounts_new` WHERE `auth` LIKE ?',
        { query }
    ) or {}

    local sharedAccounts = {}
    for index = 1, #possibleShared do
        local row = possibleShared[index]
        local members = safeDecode(row.auth, {})

        for memberIndex = 1, #members do
            if members[memberIndex] == identifier then
                sharedAccounts[#sharedAccounts + 1] = row.id
                break
            end
        end
    end

    cachedPlayers[identifier] = {
        isFrozen = account and account.isFrozen or 0,
        transactions = account and safeDecode(account.transactions, {}) or {},
        accounts = sharedAccounts
    }

    return true
end

local function addAccountToPlayerCache(identifier, accountId)
    if not cachedPlayers[identifier] then return end

    for index = 1, #cachedPlayers[identifier].accounts do
        if cachedPlayers[identifier].accounts[index] == accountId then return end
    end

    cachedPlayers[identifier].accounts[#cachedPlayers[identifier].accounts + 1] = accountId
end

local function removeAccountFromPlayerCache(identifier, accountId)
    local playerCache = cachedPlayers[identifier]
    if not playerCache then return end

    local accounts = {}
    for index = 1, #playerCache.accounts do
        if playerCache.accounts[index] ~= accountId then
            accounts[#accounts + 1] = playerCache.accounts[index]
        end
    end

    playerCache.accounts = accounts
end

local function getBankData(source)
    local Player = GetPlayerObject(source)
    if not Player then return false end

    local identifier = GetIdentifier(Player)
    if not identifier then return false end

    if not cachedPlayers[identifier] then
        UpdatePlayerAccount(identifier)
    end

    local funds = GetFunds(Player)
    if not funds then return false end

    local bankData = {
        {
            id = identifier,
            type = locale('personal'),
            name = GetCharacterName(Player),
            frozen = cachedPlayers[identifier].isFrozen,
            amount = funds.bank,
            cash = funds.cash,
            transactions = cachedPlayers[identifier].transactions
        }
    }

    local included = { [identifier] = true }
    local jobs = GetJobs(Player)

    local function includeOrganization(accountId, authorized)
        if authorized and cachedAccounts[accountId] and not included[accountId] then
            bankData[#bankData + 1] = cachedAccounts[accountId]
            included[accountId] = true
        end
    end

    if type(jobs) == 'table' and jobs.name then
        includeOrganization(jobs.name, IsJobAuth(jobs.name, jobs.grade))
    elseif type(jobs) == 'table' then
        for index = 1, #jobs do
            local job = jobs[index]
            if job then
                includeOrganization(job.name, IsJobAuth(job.name, job.grade))
            end
        end
    end

    local gang = GetGang(Player)
    if gang and gang ~= 'none' then
        includeOrganization(gang, IsGangAuth(Player, gang))
    end

    local sharedAccounts = cachedPlayers[identifier].accounts
    for index = 1, #sharedAccounts do
        local accountId = sharedAccounts[index]
        local account = cachedAccounts[accountId]

        if account and account.auth[identifier] and not included[accountId] then
            bankData[#bankData + 1] = account
            included[accountId] = true
        end
    end

    return bankData
end

CreateThread(function()
    Wait(500)

    if not LoadResourceFile(resourceName, 'web/public/build/bundle.js') then
        error(locale('ui_not_built'))
        return StopResource(resourceName)
    end

    local accounts = MySQL.query.await('SELECT * FROM `bank_accounts_new`') or {}

    for index = 1, #accounts do
        local row = accounts[index]
        local members = safeDecode(row.auth, {})
        local auth = {}

        for memberIndex = 1, #members do
            auth[members[memberIndex]] = true
        end

        cachedAccounts[row.id] = {
            id = row.id,
            type = locale('org'),
            name = GetSocietyLabel(row.id),
            frozen = row.isFrozen == 1,
            amount = tonumber(row.amount) or 0,
            transactions = safeDecode(row.transactions, {}),
            auth = auth,
            creator = row.creator
        }
    end

    local jobs, gangs = GetFrameworkGroups()
    local queries = {}

    local function stageFrameworkAccount(group)
        if cachedAccounts[group] then return end

        cachedAccounts[group] = {
            id = group,
            type = locale('org'),
            name = GetSocietyLabel(group),
            frozen = false,
            amount = 0,
            transactions = {},
            auth = {},
            creator = nil
        }

        queries[#queries + 1] = {
            'INSERT INTO `bank_accounts_new` (`id`, `amount`, `transactions`, `auth`, `isFrozen`, `creator`) VALUES (?, ?, ?, ?, ?, NULL)',
            { group, 0, '[]', '[]', 0 }
        }
    end

    for job in pairs(jobs or {}) do
        stageFrameworkAccount(job)
    end

    for gang in pairs(gangs or {}) do
        stageFrameworkAccount(gang)
    end

    if #queries > 0 and not MySQL.transaction.await(queries) then
        error('Failed to initialize framework bank accounts')
    end
end)

lib.callback.register('renewed-banking:server:initalizeBanking', function(source)
    if not guardRequest(source, 'initialize') then return false end
    return getBankData(source)
end)

local function generateTransactionId()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'

    return template:gsub('[xy]', function(character)
        local value = character == 'x' and math.random(0, 0xf) or math.random(8, 0xb)
        return ('%x'):format(value)
    end)
end

local function handleTransaction(account, title, amount, message, issuer, receiver, transactionType, transactionId)
    if type(account) ~= 'string' or account == '' then
        print(locale('err_trans_account', account))
        return false
    end
    if type(title) ~= 'string' or title == '' then
        print(locale('err_trans_title', title))
        return false
    end

    local validatedAmount = BankingSecurity.validateAmount(amount)
    if not validatedAmount then
        print(locale('err_trans_amount', amount))
        return false
    end

    if type(issuer) ~= 'string' or issuer == '' then
        print(locale('err_trans_issuer', issuer))
        return false
    end
    if type(receiver) ~= 'string' or receiver == '' then
        print(locale('err_trans_receiver', receiver))
        return false
    end
    if type(transactionType) ~= 'string' or transactionType == '' then
        print(locale('err_trans_type', transactionType))
        return false
    end
    if transactionId and type(transactionId) ~= 'string' then
        print(locale('err_trans_transID', transactionId))
        return false
    end

    local transaction = {
        trans_id = transactionId or generateTransactionId(),
        title = BankingSecurity.sanitizeText(title, 160),
        amount = validatedAmount,
        trans_type = transactionType,
        receiver = BankingSecurity.sanitizeText(receiver, 96),
        message = BankingSecurity.sanitizeText(message, Config.security.maximumCommentLength),
        issuer = BankingSecurity.sanitizeText(issuer, 96),
        time = os.time()
    }

    local target = cachedAccounts[account] or cachedPlayers[account]
    if not target then
        print(locale('invalid_account', account))
        return false
    end

    table.insert(target.transactions, 1, transaction)
    local transactions = json.encode(target.transactions)
    local success

    if cachedAccounts[account] then
        success = MySQL.prepare.await(
            'INSERT INTO `bank_accounts_new` (`id`, `transactions`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `transactions` = ?',
            { account, transactions, transactions }
        )
    else
        success = MySQL.prepare.await(
            'INSERT INTO `player_transactions` (`id`, `transactions`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `transactions` = ?',
            { account, transactions, transactions }
        )
    end

    if success == nil then
        table.remove(target.transactions, 1)
        return false
    end

    return transaction
end
exports('handleTransaction', handleTransaction)

function GetAccountMoney(account)
    return cachedAccounts[account] and cachedAccounts[account].amount or false
end
exports('getAccountMoney', GetAccountMoney)

local function updateBalance(account, newBalance)
    local changed = MySQL.update.await(
        'UPDATE `bank_accounts_new` SET `amount` = ? WHERE `id` = ?',
        { newBalance, account }
    )

    return changed and changed > 0
end

function AddAccountMoney(account, rawAmount)
    local amount = BankingSecurity.validateAmount(rawAmount)
    local bankAccount = cachedAccounts[account]

    if not amount or not bankAccount then
        return false
    end

    local newBalance = bankAccount.amount + amount
    if not updateBalance(account, newBalance) then
        return false
    end

    bankAccount.amount = newBalance
    return true
end
exports('addAccountMoney', AddAccountMoney)

function RemoveAccountMoney(account, rawAmount)
    local amount = BankingSecurity.validateAmount(rawAmount)
    local bankAccount = cachedAccounts[account]

    if not amount or not bankAccount or bankAccount.amount < amount then
        return false
    end

    local newBalance = bankAccount.amount - amount
    if not updateBalance(account, newBalance) then
        return false
    end

    bankAccount.amount = newBalance
    return true
end
exports('removeAccountMoney', RemoveAccountMoney)

local function transferDatabaseBalances(sourceAccountId, destinationAccountId, amount)
    local sourceAccount = cachedAccounts[sourceAccountId]
    local destinationAccount = cachedAccounts[destinationAccountId]

    if not sourceAccount or not destinationAccount or sourceAccount.amount < amount then
        return false
    end

    local sourceBalance = sourceAccount.amount - amount
    local destinationBalance = destinationAccount.amount + amount

    local success = MySQL.transaction.await({
        {
            'UPDATE `bank_accounts_new` SET `amount` = ? WHERE `id` = ?',
            { sourceBalance, sourceAccountId }
        },
        {
            'UPDATE `bank_accounts_new` SET `amount` = ? WHERE `id` = ?',
            { destinationBalance, destinationAccountId }
        }
    })

    if not success then return false end

    sourceAccount.amount = sourceBalance
    destinationAccount.amount = destinationBalance
    return true
end

local function getPlayerByIdentifier(identifier, notifySource)
    if type(identifier) ~= 'string' or identifier == '' then return nil end

    local Player = GetPlayerObjectFromID(identifier)
    if not Player and notifySource then
        notifyError(notifySource, locale('unknown_player', identifier))
    end

    return Player
end

local function checkSourceAccount(source, accountId, action)
    if type(accountId) ~= 'string' or accountId == '' then
        notifyError(source, 'A valid source account is required.')
        return nil
    end

    local accountType, Player, identifier = authorizeOrNotify(source, accountId, action)
    if not accountType then return nil end

    if isAccountFrozen(accountId, identifier) then
        BankingSecurity.audit('frozen_account_rejected', source, {
            action = action,
            account = accountId
        })
        notifyError(source, 'This bank account is frozen.')
        return nil
    end

    return {
        type = accountType == 'personal' and 'personal' or 'database',
        id = accountId,
        player = Player,
        identifier = identifier
    }
end

lib.callback.register('Renewed-Banking:server:deposit', function(source, data)
    if type(data) ~= 'table' or not guardRequest(source, 'deposit', buildFingerprint(data)) then
        return false
    end

    local amount = BankingSecurity.validateAmount(data.amount)
    if not amount then
        notifyError(source, locale('invalid_amount', 'deposit'))
        return false
    end

    local sourceAccount = checkSourceAccount(source, data.fromAccount, 'deposit')
    if not sourceAccount then return false end

    local lockKey = sourceAccount.type == 'database'
        and 'account:' .. sourceAccount.id
        or 'personal:' .. sourceAccount.identifier

    local completed, reason = withLocks({ lockKey }, function()
        local Player = sourceAccount.player
        local name = GetCharacterName(Player)
        local comment = BankingSecurity.sanitizeText(data.comment, Config.security.maximumCommentLength)
        if comment == '' then
            comment = locale('comp_transaction', name, 'deposited', amount)
        end

        if not RemoveMoney(Player, amount, 'cash', comment) then
            return false, 'INSUFFICIENT_FUNDS'
        end

        local credited
        local receiverName

        if sourceAccount.type == 'database' then
            credited = AddAccountMoney(sourceAccount.id, amount)
            receiverName = cachedAccounts[sourceAccount.id].name
        else
            credited = AddMoney(Player, amount, 'bank', comment)
            receiverName = name
        end

        if not credited then
            AddMoney(Player, amount, 'cash', 'Renewed-Banking deposit compensation')
            return false, 'CREDIT_FAILED'
        end

        handleTransaction(
            sourceAccount.id,
            locale('personal_acc') .. sourceAccount.id,
            amount,
            comment,
            name,
            receiverName,
            'deposit'
        )

        BankingSecurity.audit('deposit_completed', source, {
            account = sourceAccount.id,
            amount = amount
        })

        return true
    end)

    if not completed then
        if reason == 'ACCOUNT_BUSY' then
            notifyError(source, 'This account is processing another transaction.')
        elseif reason == 'INSUFFICIENT_FUNDS' then
            notifyError(source, locale('not_enough_money'))
        else
            notifyError(source, 'The deposit could not be completed.')
        end
        return false
    end

    return getBankData(source)
end)

lib.callback.register('Renewed-Banking:server:withdraw', function(source, data)
    if type(data) ~= 'table' or not guardRequest(source, 'withdraw', buildFingerprint(data)) then
        return false
    end

    local amount = BankingSecurity.validateAmount(data.amount)
    if not amount then
        notifyError(source, locale('invalid_amount', 'withdraw'))
        return false
    end

    local sourceAccount = checkSourceAccount(source, data.fromAccount, 'withdraw')
    if not sourceAccount then return false end

    local lockKey = sourceAccount.type == 'database'
        and 'account:' .. sourceAccount.id
        or 'personal:' .. sourceAccount.identifier

    local completed, reason = withLocks({ lockKey }, function()
        local Player = sourceAccount.player
        local name = GetCharacterName(Player)
        local comment = BankingSecurity.sanitizeText(data.comment, Config.security.maximumCommentLength)
        if comment == '' then
            comment = locale('comp_transaction', name, 'withdrew', amount)
        end

        local debited
        local issuerName

        if sourceAccount.type == 'database' then
            debited = RemoveAccountMoney(sourceAccount.id, amount)
            issuerName = cachedAccounts[sourceAccount.id].name
        else
            debited = RemoveMoney(Player, amount, 'bank', comment)
            issuerName = name
        end

        if not debited then
            return false, 'INSUFFICIENT_FUNDS'
        end

        if not AddMoney(Player, amount, 'cash', comment) then
            if sourceAccount.type == 'database' then
                AddAccountMoney(sourceAccount.id, amount)
            else
                AddMoney(Player, amount, 'bank', 'Renewed-Banking withdrawal compensation')
            end
            return false, 'CREDIT_FAILED'
        end

        handleTransaction(
            sourceAccount.id,
            locale('personal_acc') .. sourceAccount.id,
            amount,
            comment,
            issuerName,
            name,
            'withdraw'
        )

        BankingSecurity.audit('withdraw_completed', source, {
            account = sourceAccount.id,
            amount = amount
        })

        return true
    end)

    if not completed then
        if reason == 'ACCOUNT_BUSY' then
            notifyError(source, 'This account is processing another transaction.')
        elseif reason == 'INSUFFICIENT_FUNDS' then
            notifyError(source, locale('not_enough_money'))
        else
            notifyError(source, 'The withdrawal could not be completed.')
        end
        return false
    end

    return getBankData(source)
end)

lib.callback.register('Renewed-Banking:server:transfer', function(source, data)
    if type(data) ~= 'table' or not guardRequest(source, 'transfer', buildFingerprint(data)) then
        return false
    end

    local amount = BankingSecurity.validateAmount(data.amount)
    if not amount then
        notifyError(source, locale('invalid_amount', 'transfer'))
        return false
    end

    local sourceAccount = checkSourceAccount(source, data.fromAccount, 'transfer')
    if not sourceAccount then return false end

    if type(data.stateid) ~= 'string' or data.stateid == '' then
        notifyError(source, locale('fail_transfer'))
        return false
    end

    local destinationAccount = cachedAccounts[data.stateid]
    local destinationPlayer
    local destinationIdentifier
    local destinationType

    if destinationAccount then
        destinationType = 'database'
        if isFrozen(destinationAccount.frozen) then
            notifyError(source, 'The destination account is frozen.')
            return false
        end
    else
        destinationPlayer = getPlayerByIdentifier(data.stateid, source)
        if not destinationPlayer then return false end

        destinationIdentifier = GetIdentifier(destinationPlayer)
        destinationType = 'personal'

        if not cachedPlayers[destinationIdentifier] then
            UpdatePlayerAccount(destinationIdentifier)
        end

        if isAccountFrozen(destinationIdentifier, destinationIdentifier) then
            notifyError(source, 'The destination account is frozen.')
            return false
        end
    end

    if sourceAccount.type == destinationType then
        if sourceAccount.type == 'database' and sourceAccount.id == data.stateid then
            notifyError(source, 'You cannot transfer money to the same account.')
            return false
        elseif sourceAccount.type == 'personal' and sourceAccount.identifier == destinationIdentifier then
            notifyError(source, 'You cannot transfer money to your own account.')
            return false
        end
    end

    local sourceLock = sourceAccount.type == 'database'
        and 'account:' .. sourceAccount.id
        or 'personal:' .. sourceAccount.identifier
    local destinationLock = destinationType == 'database'
        and 'account:' .. data.stateid
        or 'personal:' .. destinationIdentifier

    local completed, reason = withLocks({ sourceLock, destinationLock }, function()
        local senderName = GetCharacterName(sourceAccount.player)
        local receiverName = destinationType == 'database'
            and destinationAccount.name
            or GetCharacterName(destinationPlayer)
        local comment = BankingSecurity.sanitizeText(data.comment, Config.security.maximumCommentLength)

        if comment == '' then
            comment = locale('comp_transaction', senderName, 'transferred', amount)
        end

        local moved = false

        if sourceAccount.type == 'database' and destinationType == 'database' then
            moved = transferDatabaseBalances(sourceAccount.id, data.stateid, amount)
        elseif sourceAccount.type == 'database' then
            moved = RemoveAccountMoney(sourceAccount.id, amount)
            if moved and not AddMoney(destinationPlayer, amount, 'bank', comment) then
                AddAccountMoney(sourceAccount.id, amount)
                moved = false
            end
        elseif destinationType == 'database' then
            moved = RemoveMoney(sourceAccount.player, amount, 'bank', comment)
            if moved and not AddAccountMoney(data.stateid, amount) then
                AddMoney(sourceAccount.player, amount, 'bank', 'Renewed-Banking transfer compensation')
                moved = false
            end
        else
            moved = RemoveMoney(sourceAccount.player, amount, 'bank', comment)
            if moved and not AddMoney(destinationPlayer, amount, 'bank', comment) then
                AddMoney(sourceAccount.player, amount, 'bank', 'Renewed-Banking transfer compensation')
                moved = false
            end
        end

        if not moved then
            return false, 'INSUFFICIENT_FUNDS'
        end

        local transactionTitle = sourceAccount.type == 'database'
            and ('%s / %s'):format(cachedAccounts[sourceAccount.id].name, sourceAccount.id)
            or locale('personal_acc') .. sourceAccount.identifier

        local debitTransaction = handleTransaction(
            sourceAccount.id,
            transactionTitle,
            amount,
            comment,
            senderName,
            receiverName,
            'withdraw'
        )

        if debitTransaction then
            local destinationId = destinationType == 'database' and data.stateid or destinationIdentifier
            handleTransaction(
                destinationId,
                transactionTitle,
                amount,
                comment,
                senderName,
                receiverName,
                'deposit',
                debitTransaction.trans_id
            )
        end

        BankingSecurity.audit('transfer_completed', source, {
            from = sourceAccount.id,
            to = destinationType == 'database' and data.stateid or BankingSecurity.redact(destinationIdentifier),
            amount = amount
        })

        return true
    end)

    if not completed then
        if reason == 'ACCOUNT_BUSY' then
            notifyError(source, 'One of the selected accounts is processing another transaction.')
        elseif reason == 'INSUFFICIENT_FUNDS' then
            notifyError(source, locale('not_enough_money'))
        else
            notifyError(source, 'The transfer could not be completed.')
        end
        return false
    end

    return getBankData(source)
end)

RegisterNetEvent('Renewed-Banking:server:createNewAccount', function(rawAccountId)
    local sourceId = source
    if not guardRequest(sourceId, 'createAccount', tostring(rawAccountId)) then return end

    local Player = GetPlayerObject(sourceId)
    if not Player then return end

    local identifier = GetIdentifier(Player)
    if not identifier then return end

    if not cachedPlayers[identifier] then
        UpdatePlayerAccount(identifier)
    end

    local accountId, validationError = BankingSecurity.validateAccountId(rawAccountId)
    if not accountId then
        BankingSecurity.audit('rejected_create_account', sourceId, { reason = validationError })
        notifyError(sourceId, 'Use 3-50 lowercase letters, numbers, dashes, or underscores for the account ID.')
        return
    end

    if cachedAccounts[accountId] then
        notifyError(sourceId, locale('account_taken'))
        return
    end

    local ownedCount = 0
    for _, account in pairs(cachedAccounts) do
        if account.creator == identifier then
            ownedCount = ownedCount + 1
        end
    end

    local maximumAccounts = tonumber(Config.security.maximumSharedAccountsPerPlayer) or 5
    if ownedCount >= maximumAccounts then
        notifyError(sourceId, ('You can only create %s shared bank accounts.'):format(maximumAccounts))
        return
    end

    local inserted = MySQL.insert.await(
        'INSERT INTO `bank_accounts_new` (`id`, `amount`, `transactions`, `auth`, `isFrozen`, `creator`) VALUES (?, ?, ?, ?, ?, ?)',
        { accountId, 0, '[]', json.encode({ identifier }), 0, identifier }
    )

    if inserted == nil then
        notifyError(sourceId, 'The account could not be created.')
        return
    end

    cachedAccounts[accountId] = {
        id = accountId,
        type = locale('org'),
        name = accountId,
        frozen = false,
        amount = 0,
        transactions = {},
        auth = { [identifier] = true },
        creator = identifier
    }

    addAccountToPlayerCache(identifier, accountId)
    BankingSecurity.audit('account_created', sourceId, { account = accountId })
end)

RegisterNetEvent('Renewed-Banking:server:getPlayerAccounts', function()
    local sourceId = source
    if not guardRequest(sourceId, 'manageAccount') then return end

    local Player = GetPlayerObject(sourceId)
    if not Player then return end

    local identifier = GetIdentifier(Player)
    if not identifier then return end

    if not cachedPlayers[identifier] then
        UpdatePlayerAccount(identifier)
    end

    local data = {}
    for accountId, account in pairs(cachedAccounts) do
        if account.creator == identifier then
            data[#data + 1] = accountId
        end
    end
    table.sort(data)

    TriggerClientEvent('Renewed-Banking:client:accountsMenu', sourceId, data)
end)

RegisterNetEvent('Renewed-Banking:server:viewMemberManagement', function(data)
    local sourceId = source
    if type(data) ~= 'table' or not guardRequest(sourceId, 'manageAccount') then return end

    local accountId = data.account
    local accountType, _, identifier = authorizeOrNotify(sourceId, accountId, 'manage')
    if not accountType then return end

    local account = cachedAccounts[accountId]
    if not account then return end

    local response = {
        account = accountId,
        members = {}
    }

    for memberIdentifier in pairs(account.auth) do
        if memberIdentifier ~= identifier then
            local memberPlayer = getPlayerByIdentifier(memberIdentifier)
            response.members[memberIdentifier] = memberPlayer
                and GetCharacterName(memberPlayer)
                or memberIdentifier
        end
    end

    TriggerClientEvent('Renewed-Banking:client:viewMemberManagement', sourceId, response)
end)

local function persistMembers(accountId)
    local account = cachedAccounts[accountId]
    if not account then return false end

    local members = {}
    for identifier in pairs(account.auth) do
        members[#members + 1] = identifier
    end
    table.sort(members)

    local changed = MySQL.update.await(
        'UPDATE `bank_accounts_new` SET `auth` = ? WHERE `id` = ?',
        { json.encode(members), accountId }
    )

    return changed and changed > 0
end

RegisterNetEvent('Renewed-Banking:server:addAccountMember', function(accountId, memberIdentifier)
    local sourceId = source
    if not guardRequest(sourceId, 'manageAccount', tostring(accountId) .. '|' .. tostring(memberIdentifier)) then return end

    local accountType = authorizeOrNotify(sourceId, accountId, 'manage')
    if not accountType then return end

    local account = cachedAccounts[accountId]
    local memberPlayer = getPlayerByIdentifier(memberIdentifier, sourceId)
    if not account or not memberPlayer then return end

    local targetIdentifier = GetIdentifier(memberPlayer)
    if not targetIdentifier or account.auth[targetIdentifier] then
        notifyError(sourceId, 'That character is already an account member.')
        return
    end

    account.auth[targetIdentifier] = true
    if not persistMembers(accountId) then
        account.auth[targetIdentifier] = nil
        notifyError(sourceId, 'The account member could not be added.')
        return
    end

    if not cachedPlayers[targetIdentifier] then
        UpdatePlayerAccount(targetIdentifier)
    end
    addAccountToPlayerCache(targetIdentifier, accountId)

    BankingSecurity.audit('account_member_added', sourceId, {
        account = accountId,
        member = BankingSecurity.redact(targetIdentifier)
    })
end)

RegisterNetEvent('Renewed-Banking:server:removeAccountMember', function(data)
    local sourceId = source
    if type(data) ~= 'table'
        or not guardRequest(sourceId, 'manageAccount', tostring(data.account) .. '|' .. tostring(data.cid)) then
        return
    end

    local accountType = authorizeOrNotify(sourceId, data.account, 'manage')
    if not accountType then return end

    local account = cachedAccounts[data.account]
    if not account then return end

    local targetIdentifier = tostring(data.cid or '')
    if targetIdentifier == '' or targetIdentifier == account.creator then
        notifyError(sourceId, 'The account owner cannot be removed.')
        return
    end

    if not account.auth[targetIdentifier] then
        notifyError(sourceId, 'That character is not an account member.')
        return
    end

    account.auth[targetIdentifier] = nil
    if not persistMembers(data.account) then
        account.auth[targetIdentifier] = true
        notifyError(sourceId, 'The account member could not be removed.')
        return
    end

    removeAccountFromPlayerCache(targetIdentifier, data.account)
    BankingSecurity.audit('account_member_removed', sourceId, {
        account = data.account,
        member = BankingSecurity.redact(targetIdentifier)
    })
end)

RegisterNetEvent('Renewed-Banking:server:deleteAccount', function(data)
    local sourceId = source
    if type(data) ~= 'table' or not guardRequest(sourceId, 'manageAccount', tostring(data.account)) then return end

    local accountType = authorizeOrNotify(sourceId, data.account, 'manage')
    if not accountType then return end

    local account = cachedAccounts[data.account]
    if not account then return end

    if account.amount ~= 0 then
        notifyError(sourceId, 'The account balance must be zero before it can be deleted.')
        return
    end

    local deleted = MySQL.update.await(
        'DELETE FROM `bank_accounts_new` WHERE `id` = ? AND `creator` IS NOT NULL',
        { data.account }
    )

    if not deleted or deleted < 1 then
        notifyError(sourceId, 'The account could not be deleted.')
        return
    end

    cachedAccounts[data.account] = nil
    for identifier in pairs(cachedPlayers) do
        removeAccountFromPlayerCache(identifier, data.account)
    end

    BankingSecurity.audit('account_deleted', sourceId, { account = data.account })
end)

local function updateAccountName(accountId, rawNewName, sourceId)
    local newName, validationError = BankingSecurity.validateAccountId(rawNewName)
    if not newName then
        if sourceId then
            notifyError(sourceId, 'Use 3-50 lowercase letters, numbers, dashes, or underscores for the account ID.')
        end
        return false, validationError
    end

    local account = cachedAccounts[accountId]
    if not account then return false, 'ACCOUNT_NOT_FOUND' end
    if cachedAccounts[newName] then return false, 'ACCOUNT_EXISTS' end

    if sourceId then
        local accountType = authorizeOrNotify(sourceId, accountId, 'manage')
        if not accountType then return false, 'UNAUTHORIZED' end
    elseif not account.creator then
        return false, 'FRAMEWORK_ACCOUNT_RENAME_DENIED'
    end

    local changed = MySQL.update.await(
        'UPDATE `bank_accounts_new` SET `id` = ? WHERE `id` = ? AND `creator` IS NOT NULL',
        { newName, accountId }
    )

    if not changed or changed < 1 then return false, 'DATABASE_ERROR' end

    cachedAccounts[newName] = account
    cachedAccounts[newName].id = newName
    cachedAccounts[newName].name = newName
    cachedAccounts[accountId] = nil

    for identifier in pairs(cachedPlayers) do
        local playerCache = cachedPlayers[identifier]
        for index = 1, #playerCache.accounts do
            if playerCache.accounts[index] == accountId then
                playerCache.accounts[index] = newName
            end
        end
    end

    if sourceId then
        BankingSecurity.audit('account_renamed', sourceId, {
            account = accountId,
            newAccount = newName
        })
    end

    return true
end

RegisterNetEvent('Renewed-Banking:server:changeAccountName', function(accountId, newName)
    local sourceId = source
    if not guardRequest(sourceId, 'manageAccount', tostring(accountId) .. '|' .. tostring(newName)) then return end

    local success, reason = updateAccountName(accountId, newName, sourceId)
    if not success then
        if reason == 'ACCOUNT_EXISTS' then
            notifyError(sourceId, locale('account_taken'))
        elseif reason ~= 'UNAUTHORIZED' then
            notifyError(sourceId, 'The account name could not be changed.')
        end
    end
end)
exports('changeAccountName', updateAccountName)

function GetJobAccount(jobName)
    if type(jobName) ~= 'string' or jobName == '' then
        error(('[%s] Invalid job name: expected a non-empty string'):format(GetInvokingResource() or resourceName))
    end

    return cachedAccounts[jobName]
end
exports('GetJobAccount', GetJobAccount)

local function createJobAccount(job, initialBalance)
    local invokingResource = GetInvokingResource() or resourceName

    if type(job) ~= 'table'
        or type(job.name) ~= 'string'
        or job.name == ''
        or type(job.label) ~= 'string'
        or job.label == '' then
        error(('[%s] Invalid job account data'):format(invokingResource))
    end

    if cachedAccounts[job.name] then
        return cachedAccounts[job.name]
    end

    local balance = tonumber(initialBalance) or 0
    if balance < 0 or balance ~= balance or balance == math.huge then
        error(('[%s] Invalid initial balance'):format(invokingResource))
    end

    local insertId = MySQL.insert.await(
        'INSERT INTO `bank_accounts_new` (`id`, `amount`, `transactions`, `auth`, `isFrozen`, `creator`) VALUES (?, ?, ?, ?, ?, NULL)',
        { job.name, balance, '[]', '[]', 0 }
    )

    if insertId == nil then
        error(('[%s] Database error while creating job account'):format(invokingResource))
    end

    cachedAccounts[job.name] = {
        id = job.name,
        type = locale('org'),
        name = job.label,
        frozen = false,
        amount = balance,
        transactions = {},
        auth = {},
        creator = nil
    }

    return cachedAccounts[job.name]
end
exports('CreateJobAccount', createJobAccount)

local function addAccountMember(accountId, memberIdentifier)
    local account = cachedAccounts[accountId]
    local Player = getPlayerByIdentifier(memberIdentifier)

    if not account or not Player then return false end

    local targetIdentifier = GetIdentifier(Player)
    if not targetIdentifier or account.auth[targetIdentifier] then return false end

    account.auth[targetIdentifier] = true
    if not persistMembers(accountId) then
        account.auth[targetIdentifier] = nil
        return false
    end

    if not cachedPlayers[targetIdentifier] then
        UpdatePlayerAccount(targetIdentifier)
    end
    addAccountToPlayerCache(targetIdentifier, accountId)

    return true
end
exports('addAccountMember', addAccountMember)

local function removeAccountMember(accountId, memberIdentifier)
    local account = cachedAccounts[accountId]
    if not account or memberIdentifier == account.creator or not account.auth[memberIdentifier] then
        return false
    end

    account.auth[memberIdentifier] = nil
    if not persistMembers(accountId) then
        account.auth[memberIdentifier] = true
        return false
    end

    removeAccountFromPlayerCache(memberIdentifier, accountId)
    return true
end
exports('removeAccountMember', removeAccountMember)

local function getAccountTransactions(account)
    if cachedAccounts[account] then
        return cachedAccounts[account].transactions
    elseif cachedPlayers[account] then
        return cachedPlayers[account].transactions
    end

    return false
end
exports('getAccountTransactions', getAccountTransactions)

lib.addCommand('givecash', {
    help = 'Give cash to a nearby player',
    params = {
        {
            name = 'target',
            type = 'playerId',
            help = locale('cmd_plyr_id')
        },
        {
            name = 'amount',
            type = 'number',
            help = locale('cmd_amount')
        }
    }
}, function(source, arguments)
    if not guardRequest(source, 'giveCash', tostring(arguments.target) .. '|' .. tostring(arguments.amount)) then return end

    local amount = BankingSecurity.validateAmount(arguments.amount)
    if not amount then
        notifyError(source, locale('invalid_amount', 'give'))
        return
    end

    if source == arguments.target then
        notifyError(source, 'You cannot give cash to yourself.')
        return
    end

    local Player = GetPlayerObject(source)
    local targetPlayer = GetPlayerObject(arguments.target)
    if not Player or not targetPlayer then
        notifyError(source, locale('unknown_player', arguments.target))
        return
    end

    if IsDead(Player) then
        notifyError(source, locale('dead'))
        return
    end

    local sourcePed = GetPlayerPed(source)
    local targetPed = GetPlayerPed(arguments.target)
    if sourcePed <= 0 or targetPed <= 0
        or #(GetEntityCoords(sourcePed) - GetEntityCoords(targetPed)) > 10.0 then
        notifyError(source, locale('too_far_away'))
        return
    end

    local completed, reason = withLocks({
        'cash:' .. tostring(GetIdentifier(Player)),
        'cash:' .. tostring(GetIdentifier(targetPlayer))
    }, function()
        if not RemoveMoney(Player, amount, 'cash', 'givecash') then
            return false, 'INSUFFICIENT_FUNDS'
        end

        if not AddMoney(targetPlayer, amount, 'cash', 'givecash') then
            AddMoney(Player, amount, 'cash', 'Renewed-Banking givecash compensation')
            return false, 'CREDIT_FAILED'
        end

        return true
    end)

    if not completed then
        notifyError(source, reason == 'INSUFFICIENT_FUNDS' and locale('not_enough_money') or 'Cash transfer failed.')
        return
    end

    local sourceName = GetCharacterName(Player)
    local targetName = GetCharacterName(targetPlayer)

    Notify(source, {
        title = locale('bank_name'),
        description = ('Successfully gave $%s to %s'):format(amount, targetName),
        type = 'success'
    })
    Notify(arguments.target, {
        title = locale('bank_name'),
        description = ('Successfully received $%s from %s'):format(amount, sourceName),
        type = 'success'
    })

    BankingSecurity.audit('givecash_completed', source, {
        target = arguments.target,
        amount = amount
    })
end)
