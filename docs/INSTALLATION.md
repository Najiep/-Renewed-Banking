# Installation and Configuration

## 1. Back up

Back up the entire database and the current resource before replacing an existing banking installation.

## 2. Dependencies

Start `oxmysql`, `ox_lib`, one framework, optional `ox_target`, then Renewed-Banking.

## 3. Framework selection

Use `Config.framework = 'esx'`, `'qb'`, or `'qbx'` in production. `auto` fails safely when zero or multiple supported frameworks are detected.

## 4. ACE

```cfg
add_ace group.admin renewedbanking.admin allow
```

## 5. Legacy migration

Do not manually insert the old SQL into v3 tables. Start the resource, run the dry run, inspect its counts, then run and verify the import.

## 6. Compatibility allowlist

Add only trusted server resources to `Config.compatibility.allowedResources`. `allowAnyInvokingResource` should remain false.

## 7. UI

Checked-in `web/dist` files are ready to use. Rebuild after editing `web/src`:

```bash
cd web
npm install
npm run build
```

## 8. Production gate

Keep the continuation pull request draft until the live framework matrix, restart test, fault injection, migration rehearsal, and balance reconciliation all pass.
