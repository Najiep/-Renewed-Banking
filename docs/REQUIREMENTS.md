# Renewed Banking v3 — Requirements Baseline

This repository implements the approved v3 requirements for a secure, auditable, performant FiveM banking resource supporting ESX Legacy, QBCore, and Qbox.

## Core invariants

1. Clients submit requests only; the server resolves identity, account, role, status, balance, recipient, limits, and final result.
2. Every money mutation routes through the transaction service.
3. Database-owned balances and transaction amounts use integer minor units in `BIGINT` columns.
4. Database-account transfers must debit, credit, and append both ledger rows atomically.
5. Cross-boundary framework/database operations must compensate or enter a recoverable settlement state.
6. Repeated request IDs must never apply a mutation twice.
7. Transaction history and memberships must be normalized and indexed, never canonical JSON blobs.
8. Closed accounts retain audit history.
9. `qb-management` and `esx_society` provider claims remain disabled until contract tests prove a complete replacement surface.
10. The release remains blocked until live framework, migration, restart, concurrency, and reconciliation gates pass.

## Supported account types

- `personal`: framework-owned character bank balance
- `job`: organization/society account
- `gang`: framework-supported gang account
- `shared`: user-created account with explicit roles
- `system`: controlled source/sink
- `admin`: internal audited adjustment account

Statuses: `active`, `frozen`, `closed`, `migration_hold`.

Shared roles: `owner`, `admin`, `operator`, `viewer`. Authorization denies by default and uses an action matrix for view, deposit, withdrawal, transfer, members, rename, close, freeze, and admin adjustment.

## Platform and dependencies

- Current FiveM Lua 5.4 runtime
- Required: `ox_lib`, `oxmysql`
- Optional: `ox_target`
- Exactly one active framework bridge: `esx`, `qb`, or `qbx`
- Explicit framework selection takes precedence over auto detection
- Startup fails safely on invalid configuration, missing migrations, unsupported framework state, or missing UI output

## Financial operations

Deposit, withdrawal, and transfer must validate payload shape, request ID, finite positive amount, configured maximum, account status, authorization, sufficient funds, and recipient. Transfers support personal↔personal, personal↔database, and database↔database routes. Offline personal money routes are unsupported unless a framework adapter explicitly implements and tests them.

Each committed operation records a unique group ID, request ID, direction, type, amount, balances where reliable, actor, counterparty, description, metadata, and timestamp. Corrections use reversal/adjustment entries instead of destructive edits.

## Shared accounts and administration

Creation validates key format, reserved names, uniqueness, cooldown, and per-owner limit. Member changes support offline identifiers and are audited. The final owner cannot be removed. Closing requires owner permission, shared-account type, zero balance, and soft closure.

Freeze/unfreeze and balance adjustment require configured ACE permission and always create audit/ledger records. Webhook failures must never roll back a committed bank transaction.

## Query, UI, and performance

UI opening returns account summaries only. Statements use bounded cursor pagination and indexed filters. The client has no permanent global per-frame banking loop; peds are lazy, cleanup is deterministic, and a non-`ox_target` fallback is available. The repository includes complete NUI source, deterministic build output, local assets, stable result envelopes, duplicate-submit protection, and safe text rendering.

## Required release tests

- forged foreign account withdrawal/transfer
- unauthorized close/member actions
- duplicate and conflicting request IDs
- concurrent debits and opposing transfers
- frozen/closed/migration-held account behavior
- forced DB/framework failure and compensation
- resource restart and pending settlement recovery
- migration dry-run/import/verify/rollback
- 100,000-row statement pagination
- live ESX, QBCore, and Qbox matrix
- zero unexplained balance difference after reconciliation

The complete approved requirements supplied for this project remain the acceptance authority when a detail is not repeated in this repository summary.
