RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking
RB.Repositories = RB.Repositories or {}
local Repository = {}
RB.Repositories.Audit = Repository

function Repository.insert(eventType, actorIdentifier, accountId, reason, metadata)
    return MySQL.insert.await([=[
        INSERT INTO renewed_bank_audit_events (event_type, actor_identifier, account_id, reason, metadata)
        VALUES (?, ?, ?, ?, ?)
    ]=], { eventType, actorIdentifier, accountId, reason, json.encode(metadata or {}) })
end
