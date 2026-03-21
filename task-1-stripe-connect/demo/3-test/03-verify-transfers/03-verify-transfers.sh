#!/usr/bin/env bash
# Verify transfers landed on connected accounts and platform balance is correct
set -euo pipefail

TR_RESTAURANT="tr_3TCrEaARsNxRMQkd0ObQbpZz"
TR_COURIER="tr_3TCrEaARsNxRMQkd0GVAGXwL"
CHARGE="ch_3TCrEaARsNxRMQkd0XXekMXZ"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Transfer to Restaurant ==="
curl -s https://api.stripe.com/v1/transfers/$TR_RESTAURANT \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -c "
import sys, json
t = json.load(sys.stdin)
print(json.dumps({
    'id': t['id'],
    'amount': t['amount'],
    'currency': t['currency'],
    'destination': t['destination'],
    'source_transaction': t.get('source_transaction'),
    'transfer_group': t.get('transfer_group'),
    'destination_payment': t.get('destination_payment')
}, indent=2))
" | tee "$DIR/03-transfer-restaurant.json"

echo ""
echo "=== Transfer to Courier ==="
curl -s https://api.stripe.com/v1/transfers/$TR_COURIER \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -c "
import sys, json
t = json.load(sys.stdin)
print(json.dumps({
    'id': t['id'],
    'amount': t['amount'],
    'currency': t['currency'],
    'destination': t['destination'],
    'source_transaction': t.get('source_transaction'),
    'transfer_group': t.get('transfer_group'),
    'destination_payment': t.get('destination_payment')
}, indent=2))
" | tee "$DIR/03-transfer-courier.json"

echo ""
echo "=== Charge (to compute platform fee) ==="
curl -s https://api.stripe.com/v1/charges/$CHARGE \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -c "
import sys, json
c = json.load(sys.stdin)
print(json.dumps({
    'id': c['id'],
    'amount': c['amount'],
    'currency': c['currency'],
    'balance_transaction': c['balance_transaction']
}, indent=2))
" | tee "$DIR/03-charge.json"

echo ""
echo "=== Balance Transaction (Stripe fees) ==="
BT=$(python3 -c "import json; print(json.load(open('$DIR/03-charge.json'))['balance_transaction'])")
curl -s "https://api.stripe.com/v1/balance_transactions/$BT" \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -c "
import sys, json
bt = json.load(sys.stdin)
print(json.dumps({
    'id': bt['id'],
    'amount': bt['amount'],
    'fee': bt['fee'],
    'net': bt['net'],
    'currency': bt['currency']
}, indent=2))
" | tee "$DIR/03-balance-transaction.json"

echo ""
echo "=== Verification ==="
python3 -c "
import json
tr = json.load(open('$DIR/03-transfer-restaurant.json'))
tc = json.load(open('$DIR/03-transfer-courier.json'))
bt = json.load(open('$DIR/03-balance-transaction.json'))

charge_amount = bt['amount']       # 2000
stripe_fee = bt['fee']             # ~90
net_on_platform = bt['net']        # ~1910
restaurant_amount = tr['amount']   # 1400
courier_amount = tc['amount']      # 400
platform_keeps = net_on_platform - restaurant_amount - courier_amount

checks = [
    ('Restaurant transfer = 1400 (EUR 14.00)', tr['amount'] == 1400),
    ('Courier transfer = 400 (EUR 4.00)', tc['amount'] == 400),
    ('Restaurant destination = acct_1TCrCTPIpZeThsJD', tr['destination'] == 'acct_1TCrCTPIpZeThsJD'),
    ('Courier destination = acct_1TCrCyAAxd0ePQfh', tc['destination'] == 'acct_1TCrCyAAxd0ePQfh'),
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
