from pathlib import Path
import sys
root = Path(__file__).resolve().parents[1]
required = {
    'renewed_bank_schema_migrations', 'renewed_bank_accounts',
    'renewed_bank_account_members', 'renewed_bank_transactions',
    'renewed_bank_idempotency', 'renewed_bank_settlements'
}
text = '\n'.join(path.read_text(encoding='utf-8') for path in (root / 'migrations').glob('*.sql'))
missing = sorted(name for name in required if name not in text)
if missing:
    print('Missing migration tables: ' + ', '.join(missing), file=sys.stderr)
    raise SystemExit(1)
print('Migration structure checks passed.')
