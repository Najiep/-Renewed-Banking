# Performance and Stress Validation

## Implemented optimizations

- No global banking `Wait(0)` loop.
- Ped models spawn only within configured distance.
- Fallback key checks run only inside a 2.5-meter point.
- Transaction statements use indexed cursor pagination.
- UI open returns account summaries, not full history.
- Membership lookup uses an indexed relation table.
- Discord logging is asynchronous.
- Caches do not retain unbounded transaction arrays.

## Required live benchmark

Record before/after measurements for:

- idle and near-bank client resmon;
- repeated UI opens;
- statement pages with at least 100,000 rows;
- same-account concurrent debits;
- different-account transfers;
- 128 connected-player simulation where practical;
- resource restart during pending operations;
- database latency/failure injection.

## Pass conditions

- No negative account balance.
- No duplicate group/request application.
- No unbounded statement payload.
- No membership full-table scan.
- No unexplained money difference after restart or fault injection.

Live FiveM profiling cannot be completed by static repository automation; attach staging measurements to the continuation draft PR before release.
