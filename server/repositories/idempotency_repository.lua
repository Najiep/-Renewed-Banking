RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking
RB.Repositories = RB.Repositories or {}

local Repository = {}
RB.Repositories.Idempotency = Repository

function Repository.claim(scopeKey, requestId, operation, payloadHash, ttlSeconds)
    local affected = MySQL.update.await([=[
        INSERT IGNORE INTO renewed_bank_idempotency
            (scope_key, request_id, operation, payload_hash, status, expires_at)
        VALUES (?, ?, ?, ?, 'processing', DATE_ADD(CURRENT_TIMESTAMP(3), INTERVAL ? SECOND))
    ]=], { scopeKey, requestId, operation, payloadHash, ttlSeconds })
    return affected > 0
end

function Repository.get(scopeKey, requestId)
    local row = MySQL.single.await('SELECT * FROM renewed_bank_idempotency WHERE scope_key = ? AND request_id = ? LIMIT 1', { scopeKey, requestId })
    if row and type(row.response) == 'string' and row.response ~= '' then
        local ok, decoded = pcall(json.decode, row.response)
        row.response = ok and decoded or nil
    end
    return row
end

function Repository.complete(scopeKey, requestId, response)
    return MySQL.update.await([=[
        UPDATE renewed_bank_idempotency
        SET status = 'committed', response = ?, updated_at = CURRENT_TIMESTAMP(3)
        WHERE scope_key = ? AND request_id = ?
    ]=], { json.encode(response), scopeKey, requestId }) > 0
end

function Repository.fail(scopeKey, requestId, response)
    return MySQL.update.await([=[
        UPDATE renewed_bank_idempotency
        SET status = 'failed', response = ?, updated_at = CURRENT_TIMESTAMP(3)
        WHERE scope_key = ? AND request_id = ?
    ]=], { json.encode(response), scopeKey, requestId }) > 0
end

function Repository.takeOverExpired(scopeKey, requestId, payloadHash, ttlSeconds)
    return MySQL.update.await([=[
        UPDATE renewed_bank_idempotency
        SET status = 'processing', payload_hash = ?, response = NULL,
            expires_at = DATE_ADD(CURRENT_TIMESTAMP(3), INTERVAL ? SECOND), updated_at = CURRENT_TIMESTAMP(3)
        WHERE scope_key = ? AND request_id = ? AND status = 'processing' AND expires_at < CURRENT_TIMESTAMP(3)
    ]=], { payloadHash, ttlSeconds, scopeKey, requestId }) > 0
end

function Repository.cleanup()
    return MySQL.update.await('DELETE FROM renewed_bank_idempotency WHERE expires_at IS NOT NULL AND expires_at < DATE_SUB(CURRENT_TIMESTAMP(3), INTERVAL 1 DAY)')
end
