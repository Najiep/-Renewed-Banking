# Tests

`tests/run.lua` covers pure amount and validation behavior without an FXServer.

GitHub Actions also checks Lua syntax, migration structure, architectural boundaries, and the deterministic NUI build.

Live framework, database, concurrency, restart, and fault-injection tests require a real FiveM staging environment. Follow `docs/PERFORMANCE.md` and attach results to the draft pull request before release.
