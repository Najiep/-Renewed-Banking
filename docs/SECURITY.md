# Security Model

## Trust boundary

NUI and client events submit requests only. The server resolves the caller, account, groups, memberships, status, balance, limits, and recipient independently.

## Authorization

- Personal: caller identifier must equal the account identifier.
- Shared: explicit member role/action matrix.
- Job/gang: framework-native group permission policy.
- System/admin: denied to normal players.
- Frozen/closed/migration-held accounts: action-specific denial.

## Replay and concurrency

Every mutation uses a request ID and persistent idempotency record. Account locks are acquired in sorted order. Database account mutations use version checks and ledger rows inside the same oxmysql transaction.

## Framework settlement boundary

Framework balances and v3 database balances are independent persistence systems. Cross-boundary operations use compensation and settlement records. Failed compensation becomes `manual_review` and appears in reconciliation.

## Logging

Identifiers are redacted by default. Discord delivery is queued and never blocks a committed transaction.

## Operational rules

- Keep privileged export allowlists narrow.
- Do not enable provider claims until contract tests pass.
- Never repair balances by direct SQL without an adjustment ledger entry.
- Review `banking_reconcile` after crashes, framework restarts, or database outages.
