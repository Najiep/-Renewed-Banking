RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking
RB.Repositories = RB.Repositories or {}
local Repository = {}
RB.Repositories.Players = Repository

function Repository.isFrozen(identifier)
    return tonumber(MySQL.scalar.await('SELECT is_frozen FROM renewed_bank_personal_status WHERE identifier = ? LIMIT 1', { identifier })) == 1
end

function Repository.setFrozen(identifier, frozen)
    return MySQL.update.await([=[
        INSERT INTO renewed_bank_personal_status (identifier, is_frozen)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE is_frozen = VALUES(is_frozen), updated_at = CURRENT_TIMESTAMP(3)
    ]=], { identifier, frozen and 1 or 0 }) >= 0
end
