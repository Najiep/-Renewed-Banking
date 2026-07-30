# Changelog

## 3.0.0-rc.1 — 2026-07-30

### Security
- Enforced server-side account authorization.
- Added persistent idempotency and replay handling.
- Added action rate limits and stable multi-account lock ordering.
- Removed client-selectable authorization assumptions.
- Added invoking-resource controls for privileged legacy exports.

### Data
- Added normalized v3 accounts, members, transactions, settlements, idempotency, audit, and migration tables.
- Replaced transaction JSON rewrites with append-only statement rows.
- Replaced membership `LIKE` scans with indexed membership rows.
- Added explicit v2 dry-run/import/verify and reconciliation commands.

### Frameworks
- Added isolated ESX Legacy, QBCore, and Qbox bridge implementations.
- QBCore defaults to official `isboss` behavior.
- Qbox uses native group and money exports with compatibility fallback.

### Client/UI
- Replaced the old compiled-only NUI runtime with checked-in source and deterministic build output.
- Added lazy ped lifecycle, optional `ox_target`, fallback text interaction, localized blips, and complete cleanup.
- Added typed result envelopes, cursor statements, shared account management, and duplicate-submit protection.

### Compatibility
- Preserved selected Renewed-Banking exports through the v3 service facade.
- Removed unconditional `provide 'qb-management'` and `provide 'esx_society'` declarations.
