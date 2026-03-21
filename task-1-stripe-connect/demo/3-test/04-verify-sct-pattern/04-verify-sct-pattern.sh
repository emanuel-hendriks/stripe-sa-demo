#!/usr/bin/env bash
# Verify the fund flow is SCT (Separate Charges and Transfers), not Destination Charges
set -eo pipefail
source ~/.bashrc
DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO="$DIR/../.."
TS=$(date +%Y%m%d-%H%M%S)
OUT="$DIR/response/$TS"
mkdir -p "$OUT"

PI=$(python3 -c "import json; print(json.load(open('$DEMO/1-Collect-Payment/02-confirm-payment-intent-response.json'))['id'])")
CHARGE=$(python3 -c "import json; print(json.load(open('$DEMO/1-Collect-Payment/02-confirm-payment-intent-response.json'))['latest_charge'])")
TR_RESTAURANT=$(python3 -c "import json; print(json.load(open('$DEMO/2-Route-Funds/01-transfer-restaurant-response.json'))['id'])")
TR_COURIER=$(python3 -c "import json; print(json.load(open('$DEMO/2-Route-Funds/02-transfer-courier-response.json'))['id'])")

echo "=== Run: $TS ==="

echo ""
echo "=== 1. PaymentIntent: charge lands on PLATFORM ==="
curl -s "https://api.stripe.com/v1/payment_intents/$PI" \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -m json.tool | tee "$OUT/${TS}_payment-intent.json"

echo ""
echo "=== 2. Charge: no destination (rules out Destination Charges) ==="
curl -s "https://api.stripe.com/v1/charges/$CHARGE" \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -m json.tool | tee "$OUT/${TS}_charge.json"

echo ""
echo "=== 3. Transfers: separate POST /v1/transfers calls ==="
curl -s "https://api.stripe.com/v1/transfers/$TR_RESTAURANT" \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -m json.tool | tee "$OUT/${TS}_transfer-restaurant.json"

curl -s "https://api.stripe.com/v1/transfers/$TR_COURIER" \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -m json.tool | tee "$OUT/${TS}_transfer-courier.json"

echo ""
echo "=== SCT Verification ==="
python3 -c "
import json

pi = json.load(open('$OUT/${TS}_payment-intent.json'))
ch = json.load(open('$OUT/${TS}_charge.json'))

checks = [
    ('No on_behalf_of on PaymentIntent', pi.get('on_behalf_of') is None),
    ('No transfer_data on PaymentIntent', pi.get('transfer_data') is None),
    ('No application_fee_amount', pi.get('application_fee_amount') is None),
    ('transfer_group is set', pi.get('transfer_group') is not None),
    ('No destination on Charge', ch.get('destination') is None),
    ('No on_behalf_of on Charge', ch.get('on_behalf_of') is None),
]
all_pass = True
for name, ok in checks:
    status = 'PASS' if ok else 'FAIL'
    if not ok: all_pass = False
    print(f'  [{status}] {name}')

print()
if all_pass:
    print('SCT confirmed: charge on platform, no destination, separate transfers')
else:
    print('WARNING: some checks suggest this is NOT pure SCT')
"
