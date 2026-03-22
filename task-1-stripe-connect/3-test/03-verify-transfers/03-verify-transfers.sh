#!/usr/bin/env bash
# Verify transfers landed on connected accounts and platform balance is correct
set -eo pipefail
source ~/.bashrc
DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO="$DIR/../.."
TS=$(date +%Y%m%d-%H%M%S)
OUT="$DIR/response/$TS"
mkdir -p "$OUT"

TR_RESTAURANT=$(python3 -c "import json; print(json.load(open('$DEMO/2-Route-Funds/01-transfer-restaurant-response.json'))['id'])")
TR_COURIER=$(python3 -c "import json; print(json.load(open('$DEMO/2-Route-Funds/02-transfer-courier-response.json'))['id'])")
CHARGE=$(python3 -c "import json; print(json.load(open('$DEMO/1-Collect-Payment/02-confirm-payment-intent-response.json'))['latest_charge'])")
RESTAURANT=$(python3 -c "import json; print(json.load(open('$DEMO/0-Onboarding/01-create-restaurant-response.json'))['id'])")
COURIER=$(python3 -c "import json; print(json.load(open('$DEMO/0-Onboarding/02-create-courier-response.json'))['id'])")

echo "=== Run: $TS ==="

echo ""
echo "=== Transfer to Restaurant ==="
curl -s https://api.stripe.com/v1/transfers/$TR_RESTAURANT \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -m json.tool | tee "$OUT/${TS}_transfer-restaurant.json"

echo ""
echo "=== Transfer to Courier ==="
curl -s https://api.stripe.com/v1/transfers/$TR_COURIER \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -m json.tool | tee "$OUT/${TS}_transfer-courier.json"

echo ""
echo "=== Charge (to compute platform fee) ==="
curl -s https://api.stripe.com/v1/charges/$CHARGE \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -m json.tool | tee "$OUT/${TS}_charge.json"

echo ""
echo "=== Balance Transaction (Stripe fees) ==="
BT=$(python3 -c "import json; print(json.load(open('$OUT/${TS}_charge.json'))['balance_transaction'])")
curl -s "https://api.stripe.com/v1/balance_transactions/$BT" \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -m json.tool | tee "$OUT/${TS}_balance-transaction.json"

echo ""
echo "=== Verification ==="
python3 -c "
import json
tr = json.load(open('$OUT/${TS}_transfer-restaurant.json'))
tc = json.load(open('$OUT/${TS}_transfer-courier.json'))
bt = json.load(open('$OUT/${TS}_balance-transaction.json'))

charge_amount = bt['amount']
stripe_fee = bt['fee']
net_on_platform = bt['net']
restaurant_amount = tr['amount']
courier_amount = tc['amount']
platform_keeps = net_on_platform - restaurant_amount - courier_amount

checks = [
    ('Restaurant transfer = 1400 (EUR 14.00)', tr['amount'] == 1400),
    ('Courier transfer = 400 (EUR 4.00)', tc['amount'] == 400),
    ('Restaurant destination = $RESTAURANT', tr['destination'] == '$RESTAURANT'),
    ('Courier destination = $COURIER', tc['destination'] == '$COURIER'),
    ('Both transfers in same transfer_group', tr['transfer_group'] == tc['transfer_group'] == 'order_001'),
    ('Both tied to source charge', tr['source_transaction'] == tc['source_transaction'] == '$CHARGE'),
    ('Total transferred < charge net', restaurant_amount + courier_amount <= net_on_platform),
]
all_pass = True
for name, ok in checks:
    status = 'PASS' if ok else 'FAIL'
    if not ok: all_pass = False
    print(f'  [{status}] {name}')

print()
print(f'  Charge:           EUR {charge_amount/100:.2f}')
print(f'  Stripe fee:       EUR {stripe_fee/100:.2f}')
print(f'  Net on platform:  EUR {net_on_platform/100:.2f}')
print(f'  -> Restaurant:    EUR {restaurant_amount/100:.2f}')
print(f'  -> Courier:       EUR {courier_amount/100:.2f}')
print(f'  = Platform keeps: EUR {platform_keeps/100:.2f}')
print()
print('Objective 3: ' + ('ALL CHECKS PASSED' if all_pass else 'SOME CHECKS FAILED'))
"
