# Renewed Banking v3

Renewed Banking v3 is a security-first FiveM banking resource with native adapters for **ESX Legacy**, **QBCore**, and **Qbox**. The v3 runtime replaces JSON transaction blobs and JSON membership lookup with a normalized, append-only ledger and explicit member roles.

> This branch is a release candidate. Keep the pull request in draft until the real FiveM staging matrix, migration rehearsal, and concurrency tests are complete.

## Highlights

- Server-authoritative authorization for every money action
- Atomic database-account transfers with optimistic version checks
- Durable request idempotency
- Per-account locks and per-player rate limits
- Normalized account, member, transaction, settlement, and audit tables
- Recoverable framework/database settlement boundary
- Native ESX, QBCore, and Qbox bridges
- Cursor-paginated statements
- Lazy bank peds and optional `ox_target`
- Dependency-free TypeScript-compatible NUI source and reproducible Node build
- Legacy Renewed-Banking exports routed through the v3 services
- Explicit migration, verification, reconciliation, and rollback tooling

## Required resources

1. A supported framework: `es_extended`, `qb-core`, or `qbx_core`
2. `ox_lib`
3. `oxmysql`
4. Optional: `ox_target`

Recommended start order:

```cfg
ensure oxmysql
ensure ox_lib
ensure es_extended # or qb-core / qbx_core
ensure ox_target   # optional
ensure Renewed-Banking
```

## First start with legacy data

The resource creates the v3 schema automatically. When legacy `bank_accounts_new` rows exist and the v3 account table is empty, database-owned operations are held until an administrator explicitly imports the data.

```text
banking_migrate_v3 dry-run
banking_migrate_v3 run
banking_migrate_v3 verify
banking_reconcile
```

Create a database backup before `run`. See [Migration Guide](docs/MIGRATION.md).

## Configuration

Set `Config.framework` to `esx`, `qb`, or `qbx` when multiple framework resources exist. `auto` is allowed only when exactly one supported framework is started.

The current default currency precision is `0` to preserve existing whole-unit FiveM economies. Change this only before production migration and keep framework/unit conversion consistent.

## Build the UI

```bash
cd web
npm install
npm run build
npm run check
```

The UI has no runtime CDN and no npm runtime dependencies. The build copies TypeScript-compatible source and local CSS into `web/dist` deterministically.

## Administration

Grant the configured ACE permission:

```cfg
add_ace group.admin renewedbanking.admin allow
```

Admin commands:

- `banking_migrate_v3 dry-run|run|verify`
- `banking_reconcile`
- `banking_freeze <account> <freeze|unfreeze> [reason]`
- `banking_adjust <account> <credit|debit> <amount> <reason>`

## Compatibility

Legacy exports are enabled through `Config.compatibility.renewedV2Exports`. Privileged invoking resources are denied unless allowed in configuration. The manifest no longer claims to fully provide `qb-management` or `esx_society`; those provider claims remain disabled until contract tests prove a complete replacement surface.

See [API Guide](docs/API.md) and [Security Model](docs/SECURITY.md).

## Project documents

- [Research audit](docs/RESEARCH_AUDIT.md)
- [Requirements](docs/REQUIREMENTS.md)
- [System design](docs/DESIGN.md)
- [Implementation tasks](docs/TASKS.md)
- [Phases 2–10 status](docs/PHASES_2_10.md)
- [Release checklist](docs/RELEASE_CHECKLIST.md)

## License

The inherited repository contains CC BY-NC-SA 4.0 material. Confirm your intended commercial, escrow, Tebex, or redistribution use with the rights holder before release. See [ATTRIBUTION.md](ATTRIBUTION.md).
