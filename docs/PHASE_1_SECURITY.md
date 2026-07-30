# Phase 1 — Security Hotfix

This branch is the single continuous implementation branch for the Renewed Banking rebuild from Phase 1 through Phase 10.

## Scope completed in this phase

- Added server-side authorization for personal, shared, job, and gang accounts.
- Blocked forged `fromAccount` withdrawal, deposit, and transfer requests.
- Fixed recipient resolution so a target identifier no longer falls back to the caller.
- Enforced frozen-account checks for source and destination accounts.
- Added strict amount, account ID, and comment validation.
- Added per-action rate limiting and duplicate-request suppression.
- Added keyed account locks for concurrent operations.
- Made database-to-database balance transfer use one oxmysql transaction.
- Added compensation paths when a framework-side credit fails.
- Protected account creation, member management, rename, and deletion.
- Account deletion now requires ownership and a zero balance.
- Loaded the personal frozen flag from the database correctly.
- Replaced the outdated asynchronous `CreateJobAccount` insert with `MySQL.insert.await`.
- Changed ESX society compatibility money events to server-local handlers instead of client-triggerable network events.
- Added structured security audit output.
- Removed the hardcoded requirement that the resource folder be named `Renewed-Banking`.
- Cleaned duplicate/deprecated manifest declarations.

## Important limitations intentionally deferred

Phase 1 is a hotfix, not the final v3 architecture.

The following remain scheduled for later phases:

- normalized transaction and membership tables;
- append-only ledger;
- durable request idempotency table;
- complete Qbox native multi-group adapter;
- offline personal transfers;
- complete `qb-management` and `esx_society` contract validation;
- soft account closure instead of physical deletion;
- full UI rebuild;
- automated FiveM integration test environment;
- migration and reconciliation tooling.

## Manual security test checklist

Run on a staging server with database backup.

### Authorization

- Open an authorized personal account and perform deposit, withdrawal, and transfer.
- Open an authorized job/gang/shared account and perform allowed actions.
- Directly invoke each callback with another known account ID as `fromAccount`; verify denial and no balance change.
- Attempt rename, member change, and deletion on an account owned by another character.
- Attempt deletion of a framework job/gang account.
- Attempt deletion of a shared account with a nonzero balance.

### Amount validation

Test:

- `0`
- negative value
- decimal value
- extremely large value
- nonnumeric string
- missing amount

All must be rejected without a balance change.

### Duplicate and concurrency

- Double-click each submit button.
- Trigger the same request rapidly.
- Start two withdrawals from the same account.
- Start opposing transfers between two accounts.

No duplicate application or negative balance should occur.

### Frozen accounts

- Freeze a personal account.
- Freeze a shared/job/gang account.
- Test outgoing withdrawal/transfer.
- Test transfer into a frozen destination.

All configured frozen flows should be denied.

### Recipient resolution

- Transfer to another online character identifier.
- Transfer to an unknown identifier.
- Transfer to self.
- Transfer from a database account to another online character.

The recipient must never resolve to the sender by fallback.

### Lifecycle

- Restart the banking resource.
- Reconnect/change character.
- Verify balances remain correct and access is refreshed.

## Local validation performed before publishing

- Lua syntax parsing passed for all new/changed server files.
- Security helper unit checks passed for:
  - amount validation;
  - account ID normalization;
  - reserved IDs;
  - text length;
  - rate limiting;
  - duplicate suppression.
- Server files loaded in mocked ESX, QBCore, and Qbox environments without top-level runtime errors.

Real framework/database integration testing is still required in a FiveM staging server.
