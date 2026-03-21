#!/usr/bin/env bash
# Verify both connected accounts are fully onboarded
set -eo pipefail
source ~/.bashrc
DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO="$DIR/../.."
TS=$(date +%Y%m%d-%H%M%S)
OUT="$DIR/runs/$TS"
mkdir -p "$OUT"

RESTAURANT=$(python3 -c "import json; print(json.load(open('$DEMO/0-Onboarding/01-create-restaurant-response.json'))['id'])")
COURIER=$(python3 -c "import json; print(json.load(open('$DEMO/0-Onboarding/02-create-courier-response.json'))['id'])")

echo "=== Run: $TS ==="

echo ""
echo "=== Restaurant Account ==="
curl -s https://api.stripe.com/v1/accounts/$RESTAURANT \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -m json.tool | tee "$OUT/${TS}_restaurant-account.json"

echo ""
echo "=== Courier Account ==="
curl -s https://api.stripe.com/v1/accounts/$COURIER \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -m json.tool | tee "$OUT/${TS}_courier-account.json"

echo ""
echo "=== Verification ==="
python3 -c "
import json
r = json.load(open('$OUT/${TS}_restaurant-account.json'))
c = json.load(open('$OUT/${TS}_courier-account.json'))
checks = [
    ('Restaurant charges_enabled', r['charges_enabled'] == True),
    ('Restaurant payouts_enabled', r['payouts_enabled'] == True),
    ('Restaurant card_payments active', r['capabilities'].get('card_payments') == 'active'),
    ('Restaurant transfers active', r['capabilities'].get('transfers') == 'active'),
    ('Restaurant no outstanding requirements', r['requirements']['currently_due'] == []),
    ('Courier charges_enabled', c['charges_enabled'] == True),
    ('Courier payouts_enabled', c['payouts_enabled'] == True),
    ('Courier card_payments active', c['capabilities'].get('card_payments') == 'active'),
    ('Courier transfers active', c['capabilities'].get('transfers') == 'active'),
    ('Courier no outstanding requirements', c['requirements']['currently_due'] == []),
]
all_pass = True
for name, ok in checks:
    status = 'PASS' if ok else 'FAIL'
    if not ok: all_pass = False
    print(f'  [{status}] {name}')
print()
print('Objective 1: ' + ('ALL CHECKS PASSED' if all_pass else 'SOME CHECKS FAILED'))
"
