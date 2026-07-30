# Renewed Banking v3 — System Design

## Architecture

```text
NUI / client interaction
        ↓
server controllers
        ↓
payload validation + rate limit + authorization
        ↓
account / transaction / statement services
        ├── normalized oxmysql repositories
        └── ESX / QBCore / Qbox bridge
        ↓
append-only ledger, idempotency, settlements, audit
```

Controllers never execute SQL or call framework money methods directly. Repositories own SQL. Framework bridges own identity, lifecycle, groups, notifications, and personal cash/bank mutations. Compatibility exports are facades over the same services.

## Data model

- `renewed_bank_accounts`: stable key, display name, type, owner, currency, integer balance, status, version, timestamps
- `renewed_bank_account_members`: indexed `(account_id, member_identifier)` role relation
- `renewed_bank_personal_status`: personal freeze state
- `renewed_bank_transactions`: append-only debit/credit statement rows with group/request IDs
- `renewed_bank_idempotency`: request claim, payload hash, processing/committed/failed response
- `renewed_bank_settlements`: framework/database compensation and manual review
- `renewed_bank_audit_events`: administrative and membership changes
- `renewed_bank_schema_migrations`: applied schema versions

Personal balances remain canonical in the active framework. Organization/shared balances are canonical in v3 tables.

## Concurrency and idempotency

Lock keys are stable (`db:<id>`, `personal:<identifier>`) and sorted before multi-account acquisition. Application locks prevent overlapping service work; SQL version checks and constraints provide the authoritative concurrency guard.

A request claim is scoped by actor and operation. The canonical payload is hashed deterministically. A committed/failed request replays its saved response, an active request returns `REQUEST_IN_PROGRESS`, and reuse with another payload returns `IDEMPOTENCY_CONFLICT`.

## Transaction flows

Database→database transfer acquires both locks, rereads both accounts, conditionally updates both balances with version checks, and appends debit/credit rows in one oxmysql transaction. Post-commit verification confirms versions, balances, and paired ledger rows.

Framework-boundary flows cannot be represented as one ACID transaction. The service performs the framework mutation, commits the v3 side and ledger, and compensates on failure. Failed compensation is persisted as `manual_review` and surfaced by reconciliation.

## Framework bridges

The shared contract provides player lookup, identifier/name, cash/bank read/add/remove, groups, group-account permission, notifications, load/death state, offline capability, and defined groups.

- ESX: xPlayer account APIs and configurable boss grade mode
- QBCore: Player money methods and official `isboss` default
- Qbox: native `qbx_core` groups, boss, and money exports with compatibility fallback only where necessary

Core services contain no framework-specific imports.

## Migration

Startup applies versioned schema files. Legacy rows plus empty v3 tables trigger `migration_hold`. The operator runs dry-run, import, verify, and reconciliation after backup. Current legacy balance becomes the opening authority; old history is imported for display and not trusted to recompute balance. Old tables remain for rollback.

## Client and UI

Bank peds spawn through `lib.points` only near configured locations. ATM and teller capabilities differ by config. `ox_target` is optional; fallback text interaction is proximity-bound. Resource stop, unload, logout, and character state changes close NUI and remove targets, peds, points, text UI, and blips.

The NUI uses checked-in TypeScript-compatible source and deterministic build output without runtime CDN dependencies. It renders user content as escaped text, paginates statements, reuses request IDs during retries, and always expects a stable `{ok,data}` or `{ok:false,error}` envelope.

## Deployment

Phase 1 was merged first. Phases 2–10 continue on the same `agent/renewed-banking-v3` branch. The continuation PR remains draft until live framework, fault-injection, migration, restart, compatibility, license, and release gates are complete.
