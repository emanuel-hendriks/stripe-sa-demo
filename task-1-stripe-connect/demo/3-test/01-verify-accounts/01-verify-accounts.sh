#!/usr/bin/env bash
# Verify both connected accounts are fully onboarded
set -euo pipefail

RESTAURANT="acct_1TCrCTPIpZeThsJD"
COURIER="acct_1TCrCyAAxd0ePQfh"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Restaurant Account ==="
curl -s https://api.stripe.com/v1/accounts/$RESTAURANT \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -c "
import sys, json
a = json.load(sys.stdin)
print(json.dumps({
    'id': a['id'],
    'business_type': a['business_type'],
    'charges_enabled': a['charges_enabled'],
    'payouts_enabled': a['payouts_enabled'],
    'capabilities': {k: v for k, v in a['capabilities'].items()},
    'currently_due': a['requirements']['currently_due'],
    'country': a['country']
}, indent=2))
" | tee "$DIR/01-restaurant-account.json"

echo ""
echo "=== Courier Account ==="
curl -s https://api.stripe.com/v1/accounts/$COURIER \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -c "
import sys, json
a = json.load(sys.stdin)
print(json.dumps({
    'id': a['id'],
    'business_type': a['business_type'],
    'charges_enabled': a['charges_enabled'],
    'payouts_enabled': a['payouts_enabled'],
    'capabilities': {k: v for k, v in a['capabilities'].items()},
    'currently_due': a['requirements']['currently_due'],
    'country': a['country']
}, indent=2))
" | tee "$DIR/01-courier-account.json"

echo ""
echo "=== Verification ==="
python3 -c "
import json
r = json.load(open('$DIR/01-restaurant-account.json'))
c = json.load(open('$DIR/01-courier-account.json'))
checks = [
    ('Restaurant charges_enabled', r['charges_enabled'] == True),
    ('Restaurant payouts_enabled', r['payouts_enabled'] == True),
    ('Restaurant card_payments active', r['capabilities'].get('card_payments') == 'active'),
    ('Restaurant transfers active', r['capabilities'].get('transfers') == 'active'),
    ('Restaurant no outstanding requirements', r['currently_due'] == []),
    ('Courier charges_enabled', c['charges_enabled'] == True),
    ('Courier payouts_enabled', c['payouts_enabled'] == True),
    ('Courier card_payments active', c['capabilities'].get('card_payments') == 'active'),
    ('Courier transfers active', c['capabilities'].get('transfers') == 'active'),
    ('Courier no outstanding requirements', c['currently_due'] == []),
]
all_pass = True
for name, ok in checks:
    status = 'PASS' if ok else 'FAIL'
    if not ok: all_pass = False
    print(f'  [{status}] {name}')
print()
print('Objective 1: ' + ('ALL CHECKS PASSED' if all_pass else 'SOME CHECKS FAILED'))
"
