RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking
RB.Repositories = RB.Repositories or {}

local Repository = {}
RB.Repositories.Settlements = Repository

function Repository.create(data)
    return MySQL.insert.await([=[
        INSERT INTO renewed_bank_settlements
            (group_id, framework, identifier, money_type, direction, amount, status, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE status = VALUES(status), metadata = VALUES(metadata), updated_at = CURRENT_TIMESTAMP(3)
    ]=], {
        data.groupId, data.framework, data.identifier, data.moneyType,
        data.direction, data.amount, data.status or 'pending', json.encode(data.metadata or {})
    })
end

function Repository.update(groupId, identifier, direction, status, lastError)
    return MySQL.update.await([=[
        UPDATE renewed_bank_settlements
        SET status = ?, last_error = ?, attempts = attempts + 1, updated_at = CURRENT_TIMESTAMP(3)
        WHERE group_id = ? AND identifier = ? AND direction = ?
    ]=], { status, lastError, groupId, identifier, direction }) > 0
end

function Repository.pending(limit)
    return MySQL.query.await([=[
        SELECT * FROM renewed_bank_settlements
        WHERE status IN ('pending', 'compensating', 'manual_review')
        ORDER BY created_at LIMIT ?
    ]=], { tonumber(limit) or 100 }) or {}
end
