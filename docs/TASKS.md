# Renewed Banking v3 — Phase 2–10 Task Status

## Phase 2 — Foundation and tooling

- [x] Modular shared/client/server layout
- [x] Explicit framework bridge contract and loader
- [x] Modern manifest and removal of deprecated/provider declarations
- [x] Startup configuration validation
- [x] CI for Lua syntax, unit tests, architecture rules, migration structure, and UI build

## Phase 3 — Database and migration

- [x] Versioned migration runner
- [x] Normalized accounts, members, personal status, transactions, idempotency, settlements, audit tables
- [x] Legacy v2 dry-run, import, and verification
- [x] Migration hold before legacy import
- [x] Opening-balance and historical import rules
- [x] Rollback documentation

## Phase 4 — Domain and transaction services

- [x] Integer money parsing and validation
- [x] Account, membership, transaction, idempotency, settlement, audit, and personal-status repositories
- [x] Deny-by-default authorization service
- [x] Sorted keyed locks and rate limiting
- [x] Persistent idempotency and deterministic payload hash
- [x] Atomic database-account transfer with paired ledger
- [x] Framework-boundary compensation and settlement records
- [x] Cursor statements and reconciliation report

## Phase 5 — Framework adapters

- [x] Shared adapter interface and validation
- [x] ESX Legacy adapter
- [x] QBCore adapter using official boss behavior by default
- [x] Native Qbox adapter with multi-group support
- [x] Safe diagnostics for framework restart
- [ ] Live target-version contract matrix

## Phase 6 — Client and interactions

- [x] Lifecycle-safe NUI state/focus
- [x] Lazy bank peds and configurable locations
- [x] Optional `ox_target`
- [x] Nearby fallback interaction
- [x] Localized/configurable blips
- [x] Complete cleanup

## Phase 7 — UI

- [x] Source-controlled TypeScript-compatible NUI
- [x] Deterministic dependency-free build and checked-in dist output
- [x] Account overview and capability-aware actions
- [x] Deposit, withdrawal, and transfer confirmation flows
- [x] Stable request IDs and disabled duplicate submit
- [x] Cursor-paginated transactions
- [x] Shared account/member management
- [x] Responsive keyboard-close behavior and safe text escaping

## Phase 8 — Compatibility

- [x] Selected Renewed v2 exports route through v3 services
- [x] Invoking-resource allowlist
- [x] Legacy return shapes and framework-unit conversion
- [x] Unconditional provider claims removed
- [ ] Full consumer contract tests before enabling provider modes

## Phase 9 — validation

- [x] Static Lua syntax checks
- [x] Shared unit tests
- [x] Architecture regression rules
- [x] Migration structure checks
- [x] NUI build and JavaScript syntax check
- [x] Reconciliation command and 100k-row seed helper
- [ ] Real FXServer concurrency/fault-injection run
- [ ] 128-player/resmon benchmark where practical
- [ ] Restart and migration rehearsal on production-like clone

## Phase 10 — release

- [x] README, changelog, attribution, install, migration, API, security, and performance docs
- [x] Release checklist
- [ ] License/commercial-use decision
- [ ] All live gates green
- [ ] Continuation PR moved from draft
- [ ] Release tag

## Definition of done

A checkbox marked implemented means repository code, static validation, and documentation exist. It does not replace real framework/database staging evidence. No production cutover is approved until every unchecked release gate is completed and attached to the draft PR.
