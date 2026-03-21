#!/usr/bin/env bash
# Verify PaymentIntent succeeded and charge is on the platform
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PI=$(python3 -c "import json; print(json.load(open('$DIR/../../1-Collect-Payment/02-confirm-payment-intent-response.json'))['id'])")

echo "=== PaymentIntent ==="
curl -s https://api.stripe.com/v1/payment_intents/$PI \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -c "
import sys, json
pi = json.load(sys.stdin)
print(json.dumps({
    'id': pi['id'],
    'amount': pi['amount'],
    'currency': pi['currency'],
    'status': pi['status'],
    'transfer_group': pi.get('transfer_group'),
    'latest_charge': pi['latest_charge']
}, indent=2))
" | tee "$DIR/02-payment-intent.json"

echo ""
echo "=== Verification ==="
python3 -c "
import json
pi = json.load(open('$DIR/02-payment-intent.json'))
checks = [
    ('Status is succeeded', pi['status'] == 'succeeded'),
    ('Amount is 2000 (EUR 20.00)', pi['amount'] == 2000),
    ('Currency is EUR', pi['currency'] == 'eur'),
    ('Transfer group is order_001', pi['transfer_group'] == 'order_001'),
    ('Charge exists', pi['latest_charge'] is not None),
]
all_pass = True
for name, ok in checks:
    status = 'PASS' if ok else 'FAIL'
    if not ok: all_pass = False
    print(f'  [{status}] {name}')
print()
print('Objective 2: ' + ('ALL CHECKS PASSED' if all_pass else 'SOME CHECKS FAILED'))
"
