RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

RB.Reconciliation = {}

function RB.Reconciliation.report()
    local accounts = MySQL.query.await([=[
        SELECT a.id, a.account_key, a.balance, a.status,
               (SELECT t.balance_after FROM renewed_bank_transactions t WHERE t.account_id = a.id AND t.balance_after IS NOT NULL ORDER BY t.id DESC LIMIT 1) AS ledger_balance
        FROM renewed_bank_accounts a
        ORDER BY a.id
    ]=]) or {}
    local mismatches = {}
    for _, account in ipairs(accounts) do
        account.balance = tonumber(account.balance) or 0
        account.ledger_balance = account.ledger_balance and tonumber(account.ledger_balance) or nil
        if account.ledger_balance ~= nil and account.balance ~= account.ledger_balance then mismatches[#mismatches + 1] = account end
    end
    local pending = RB.Repositories.Settlements.pending(500)
    return RB.Result.ok({ accountsChecked = #accounts, balanceMismatches = mismatches, pendingSettlements = pending })
end
