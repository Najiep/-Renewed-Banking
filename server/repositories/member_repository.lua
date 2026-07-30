RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking
RB.Repositories = RB.Repositories or {}

local Repository = {}
RB.Repositories.Members = Repository

function Repository.getRole(accountId, identifier)
    return MySQL.scalar.await('SELECT role FROM renewed_bank_account_members WHERE account_id = ? AND member_identifier = ? LIMIT 1', {
        accountId, identifier
    })
end

function Repository.list(accountId)
    return MySQL.query.await([=[
        SELECT member_identifier, role, added_by, created_at, updated_at
        FROM renewed_bank_account_members
        WHERE account_id = ?
        ORDER BY FIELD(role, 'owner', 'admin', 'operator', 'viewer'), created_at
    ]=], { accountId }) or {}
end

function Repository.exists(accountId, identifier)
    return MySQL.scalar.await('SELECT 1 FROM renewed_bank_account_members WHERE account_id = ? AND member_identifier = ? LIMIT 1', {
        accountId, identifier
    }) ~= nil
end

function Repository.upsert(accountId, identifier, role, addedBy)
    return MySQL.update.await([=[
        INSERT INTO renewed_bank_account_members (account_id, member_identifier, role, added_by)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE role = VALUES(role), added_by = VALUES(added_by), updated_at = CURRENT_TIMESTAMP(3)
    ]=], { accountId, identifier, role, addedBy }) >= 0
end

function Repository.remove(accountId, identifier)
    return MySQL.update.await('DELETE FROM renewed_bank_account_members WHERE account_id = ? AND member_identifier = ?', {
        accountId, identifier
    }) > 0
end

function Repository.countOwners(accountId)
    return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM renewed_bank_account_members WHERE account_id = ? AND role = ?', {
        accountId, RB.Roles.OWNER
    })) or 0
end
