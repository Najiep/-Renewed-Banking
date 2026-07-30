from __future__ import annotations
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
errors: list[str] = []

# Controllers may orchestrate services but must not mutate money or execute SQL.
for path in (root / 'server' / 'controllers').glob('*.lua'):
    text = path.read_text(encoding='utf-8')
    for pattern in (r'\bMySQL\.', r'\.addMoney\(', r'\.removeMoney\(', r'UPDATE\s+renewed_bank_accounts'):
        if re.search(pattern, text, re.IGNORECASE):
            errors.append(f'{path.relative_to(root)} violates controller boundary: {pattern}')

# Canonical membership/history must not regress to JSON blob lookup.
for path in (root / 'server').rglob('*.lua'):
    text = path.read_text(encoding='utf-8')
    if "auth LIKE" in text or "transactions = json.encode(cached" in text:
        errors.append(f'{path.relative_to(root)} contains a legacy blob pattern')

manifest = (root / 'fxmanifest.lua').read_text(encoding='utf-8')
for forbidden in ("provide 'qb-management'", "provide 'esx_society'", "lua54 'yes'"):
    if forbidden in manifest:
        errors.append(f'fxmanifest contains forbidden compatibility/deprecated declaration: {forbidden}')

if errors:
    print('\n'.join(errors), file=sys.stderr)
    raise SystemExit(1)
print('Architecture checks passed.')
