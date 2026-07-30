# Renewed Banking — Audit Findings and Rebuild Decisions

## Baseline risks found

The inherited v2 implementation combined framework logic, authorization, cache mutation, balance persistence, transaction JSON, account membership, callbacks, and compatibility exports in monolithic files. The highest-risk findings were:

- client-selected source accounts were not consistently re-authorized;
- shared account deletion lacked complete ownership safeguards;
- an ambiguous player resolver could return the caller instead of the intended recipient;
- balances, credits, and transaction history were not atomic;
- transaction history was an unbounded JSON blob;
- membership used JSON plus substring `LIKE` lookup;
- request replay, rate limiting, and durable idempotency were absent;
- frozen status was inconsistently enforced;
- amount/input validation was weak;
- Qbox was treated like QBCore rather than using native groups;
- QBCore required nonstandard `bankAuth` instead of official boss semantics;
- ESX boss permission was rigid;
- manifest `provide` declarations overpromised replacement compatibility;
- the UI shipped compiled output without maintainable source and used external runtime assets.

## v3 decisions

1. Preserve selected external APIs behind a compatibility facade, not the old internals.
2. Centralize every money mutation in one server-authoritative transaction service.
3. Use normalized accounts, members, personal status, ledger, idempotency, settlements, and audit tables.
4. Keep personal balances in the active framework and database-owned balances in v3.
5. Use explicit native ESX, QBCore, and Qbox bridges.
6. Enforce authorization, status, amount, rate, recipient, and replay checks on the server.
7. Use cursor pagination, lazy interactions, bounded runtime state, and asynchronous logging.
8. Ship source, tests, migrations, CI, release guidance, and rollback procedure.
9. Do not claim full `qb-management` or `esx_society` replacement until contract tests pass.

## Dependency guidance

Required: `ox_lib`, `oxmysql`, and exactly one supported framework. `ox_target` is optional. Pin tested versions instead of tracking moving branches directly. Use awaited prepared queries and oxmysql transactions for financial persistence. Client events are never trusted as proof of ownership, balance, group, status, or permission.

## Performance guidance

Optimization is broader than idle resmon. The rebuild removes global per-frame banking loops, full-history UI payloads, JSON history rewrites, substring membership scans, unbounded transaction cache, and blocking Discord delivery. Live benchmarks must still measure client resmon, server/database latency, 100,000-row statements, concurrent transfers, restarts, and 128-player load where practical.

## License gate

The inherited repository includes CC BY-NC-SA 4.0 material. Attribution, noncommercial, and ShareAlike obligations may affect monetized servers, Tebex distribution, escrow, or resale. Confirm separate permission from the rights holder before commercial distribution. This is a governance warning, not legal advice.

## Release decision

The v3 code is a release candidate, not an approved production cutover. Proceed only after a database backup, migration rehearsal, live ESX/QBCore/Qbox tests, concurrency and fault injection, restart/reconciliation verification, compatibility consumer tests, and a documented license decision.
