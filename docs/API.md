# Server API and Compatibility Exports

All exports below are server-side. Money-changing calls are audited and use the same v3 mutation path as banking actions.

## `getAccountMoney(accountKey)`
Returns the database-owned account balance in configured framework units, or `false`.

## `addAccountMoney(accountKey, amount, reason?, requestId?)`
Credits a database-owned account. The invoking resource must be allowlisted unless `allowAnyInvokingResource` is enabled.

## `removeAccountMoney(accountKey, amount, reason?, requestId?)`
Debits only when sufficient funds exist.

## `handleTransaction(account, title, amount, message, issuer, receiver, type, transactionId?)`
Appends an external statement entry. This does **not** alter balance; the calling resource remains responsible for invoking an audited balance mutation separately when appropriate.

## `getAccountTransactions(accountKey, cursor?, limit?)`
Returns a bounded transaction page in the legacy transaction shape.

## `GetJobAccount(jobName)`
Returns a legacy-shaped summary for a database-owned account.

## `CreateJobAccount(job, initialBalance?)`
Creates a missing job account. Restrict the invoking resource.

## `changeAccountName(accountKey, displayName)`
Changes only the display name. The stable account key does not change.

## `addAccountMember(accountKey, identifier, role?)`
Adds or updates an offline-capable membership row.

## `removeAccountMember(accountKey, identifier)`
Removes a membership row. UI owner invariants are stricter than this privileged compatibility function; use only from trusted resources.

## Result behavior

Legacy boolean exports return `true`/`false`. New NUI callbacks return:

```json
{ "ok": true, "data": {} }
```

or:

```json
{ "ok": false, "error": { "code": "UNAUTHORIZED" } }
```
