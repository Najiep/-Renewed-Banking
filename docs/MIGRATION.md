# v2 to v3 Migration Guide

## Safety model

The v3 runtime detects legacy rows. When v3 is empty, it sets a migration hold instead of creating zero-balance organization accounts over existing legacy balances.

## Procedure

1. Stop public access or enable maintenance mode.
2. Back up the database.
3. Start the v3 resource.
4. Run `banking_migrate_v3 dry-run`.
5. Compare account count, total balance, member count, transaction count, and malformed JSON counts.
6. Run `banking_migrate_v3 run` once.
7. Run `banking_migrate_v3 verify`.
8. Require `balanceDifference = 0` before cutover.
9. Run `banking_reconcile`.
10. Test personal, job/gang, and shared account operations.

## Import behavior

- Legacy current balance becomes the authoritative opening balance.
- A `migration_credit` entry records a nonzero opening balance.
- Legacy organization and personal history are imported for display with legacy metadata but are not used to recompute current balance.
- Creator becomes owner; other legacy `auth` entries become operators.
- Organization and personal frozen state are preserved.

## Rollback

The importer does not delete old tables. To roll back before public writes:

1. Stop Renewed-Banking.
2. Restore the previous resource version.
3. Restore the database snapshot if any v3 writes occurred.
4. Preserve v3 tables for incident analysis, but do not merge both histories blindly.

After public v3 writes, rollback requires an approved delta/reconciliation plan rather than a simple code downgrade.
