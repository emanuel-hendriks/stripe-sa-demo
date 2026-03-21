#!/usr/bin/env bash
# Stripe Connect demo: pay, transfer, verify.
# Accounts are pre-created. This script runs Objectives 2 and 3 only.
set -euo pipefail

RUN_ID="${GITHUB_RUN_ID:-$(date +%s)}"
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/.ci-output"
mkdir -p "$OUT"

RESTAURANT="$RESTAURANT_ACCT"
COURIER="$COURIER_ACCT"

echo "=== Run ID: $RUN_ID ==="
echo "Restaurant: $RESTAURANT"
echo "Courier: $COURIER"

# --- Objective 2: Collect Payment ---

echo ""
echo "=== 2a. Create PaymentIntent ==="
curl -s https://api.stripe.com/v1/payment_intents \
  -u "$STRIPE_DEMO_KEY:" \
  -H "Idempotency-Key: ci-payment-$RUN_ID" \
  -d amount=2000 \
  -d currency=eur \
  -d "payment_method_types[]"=card \
  -d transfer_group="ci_order_$RUN_ID" \
  -d "metadata[order_id]"="ci_order_$RUN_ID" \
  -d "metadata[restaurant]"="$RESTAURANT" \
  -d "metadata[courier]"="$COURIER" \
  | python3 -m json.tool | tee "$OUT/payment-intent.json"

PI=$(python3 -c "import json; print(json.load(open('$OUT/payment-intent.json'))['id'])")
echo "PaymentIntent: $PI"

echo ""
echo "=== 2b. Confirm PaymentIntent ==="
curl -s "https://api.stripe.com/v1/payment_intents/$PI/confirm" \
  -u "$STRIPE_DEMO_KEY:" \
  -d payment_method=pm_card_bypassPending \
  | python3 -m json.tool | tee "$OUT/confirm.json"

CHARGE=$(python3 -c "import json; print(json.load(open('$OUT/confirm.json'))['latest_charge'])")
echo "Charge: $CHARGE"

# --- Objective 3: Route Funds ---

echo ""
echo "=== 3a. Transfer to Restaurant ==="
curl -s https://api.stripe.com/v1/transfers \
  -u "$STRIPE_DEMO_KEY:" \
  -H "Idempotency-Key: ci-transfer-restaurant-$RUN_ID" \
  -d amount=1400 \
  -d currency=eur \
  -d "destination"="$RESTAURANT" \
  -d "source_transaction"="$CHARGE" \
  -d transfer_group="ci_order_$RUN_ID" \
  | python3 -m json.tool | tee "$OUT/transfer-restaurant.json"

echo ""
echo "=== 3b. Transfer to Courier ==="
curl -s https://api.stripe.com/v1/transfers \
  -u "$STRIPE_DEMO_KEY:" \
  -H "Idempotency-Key: ci-transfer-courier-$RUN_ID" \
  -d amount=400 \
  -d currency=eur \
  -d "destination"="$COURIER" \
  -d "source_transaction"="$CHARGE" \
  -d transfer_group="ci_order_$RUN_ID" \
  | python3 -m json.tool | tee "$OUT/transfer-courier.json"

# --- Verify ---

echo ""
echo "=== Verification ==="
python3 -c "
import json

pi = json.load(open('$OUT/confirm.json'))
tr = json.load(open('$OUT/transfer-restaurant.json'))
tc = json.load(open('$OUT/transfer-courier.json'))

checks = [
    ('PaymentIntent succeeded', pi['status'] == 'succeeded'),
    ('Amount is 2000', pi['amount'] == 2000),
    ('Currency is EUR', pi['currency'] == 'eur'),
    ('transfer_group set', pi['transfer_group'] == 'ci_order_$RUN_ID'),
    ('Restaurant transfer = 1400', tr['amount'] == 1400),
    ('Courier transfer = 400', tc['amount'] == 400),
    ('Restaurant source_transaction matches charge', tr['source_transaction'] == '$CHARGE'),
    ('Courier source_transaction matches charge', tc['source_transaction'] == '$CHARGE'),
    ('Same transfer_group on restaurant', tr['transfer_group'] == 'ci_order_$RUN_ID'),
    ('Same transfer_group on courier', tc['transfer_group'] == 'ci_order_$RUN_ID'),
    ('No on_behalf_of (SCT)', pi.get('on_behalf_of') is None),
    ('No transfer_data (SCT)', pi.get('transfer_data') is None),
]

all_pass = True
for name, ok in checks:
    status = 'PASS' if ok else 'FAIL'
    if not ok: all_pass = False
    print(f'  [{status}] {name}')

print()
if all_pass:
    print('ALL 12 CHECKS PASSED')
else:
    print('SOME CHECKS FAILED')
    exit(1)
"
