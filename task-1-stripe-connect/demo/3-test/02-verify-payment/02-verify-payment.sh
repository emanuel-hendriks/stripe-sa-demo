#!/usr/bin/env bash
# Verify PaymentIntent succeeded and charge is on the platform
set -eo pipefail
source ~/.bashrc
DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO="$DIR/../.."
TS=$(date +%Y%m%d-%H%M%S)
OUT="$DIR/runs/$TS"
mkdir -p "$OUT"

PI=$(python3 -c "import json; print(json.load(open('$DEMO/1-Collect-Payment/02-confirm-payment-intent-response.json'))['id'])")

echo "=== Run: $TS ==="

echo ""
echo "=== PaymentIntent ==="
curl -s https://api.stripe.com/v1/payment_intents/$PI \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -m json.tool | tee "$OUT/${TS}_payment-intent.json"

echo ""
echo "=== Verification ==="
python3 -c "
import json
pi = json.load(open('$OUT/${TS}_payment-intent.json'))
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
