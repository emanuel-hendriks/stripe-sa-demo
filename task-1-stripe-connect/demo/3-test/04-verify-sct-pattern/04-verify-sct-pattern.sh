#!/usr/bin/env bash
# Verify the fund flow is SCT (Separate Charges and Transfers), not Destination Charges
set -euo pipefail

PI="pi_3TCrEaARsNxRMQkd0CmwllS8"
CHARGE="ch_3TCrEaARsNxRMQkd0XXekMXZ"
TR_RESTAURANT="tr_3TCrEaARsNxRMQkd0ObQbpZz"
TR_COURIER="tr_3TCrEaARsNxRMQkd0GVAGXwL"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== 1. PaymentIntent: charge lands on PLATFORM ==="
curl -s "https://api.stripe.com/v1/payment_intents/$PI" \
  -u "$STRIPE_DEMO_KEY:" | python3 -c "
import sys, json; pi=json.load(sys.stdin)
print(json.dumps({
    'on_behalf_of': pi.get('on_behalf_of'),
    'transfer_data': pi.get('transfer_data'),
    'transfer_group': pi.get('transfer_group'),
    'application_fee_amount': pi.get('application_fee_amount'),
}, indent=2))
" | tee "$DIR/04-payment-intent-sct.json"

echo ""
echo "=== 2. Charge: no destination (rules out Destination Charges) ==="
curl -s "https://api.stripe.com/v1/charges/$CHARGE" \
  -u "$STRIPE_DEMO_KEY:" | python3 -c "
import sys, json; c=json.load(sys.stdin)
print(json.dumps({
    'destination': c.get('destination'),
    'on_behalf_of': c.get('on_behalf_of'),
    'transfer_group': c.get('transfer_group'),
    'application_fee_amount': c.get('application_fee_amount'),
}, indent=2))
" | tee "$DIR/04-charge-sct.json"

echo ""
echo "=== 3. Transfers: separate POST /v1/transfers calls ==="
for tr in $TR_RESTAURANT $TR_COURIER; do
  curl -s "https://api.stripe.com/v1/transfers/$tr" -u "$STRIPE_DEMO_KEY:" | python3 -c "
import sys, json; t=json.load(sys.stdin)
print(json.dumps({
    'id': t['id'],
    'destination': t['destination'],
    'amount': t['amount'],
    'source_transaction': t.get('source_transaction'),
    'transfer_group': t.get('transfer_group'),
}, indent=2))
"
done | tee "$DIR/04-transfers-sct.json"

echo ""
echo "=== SCT Verification ==="
python3 -c "
import json

pi = json.load(open('$DIR/04-payment-intent-sct.json'))
ch = json.load(open('$DIR/04-charge-sct.json'))

checks = [
    ('No on_behalf_of on PaymentIntent', pi['on_behalf_of'] is None),
    ('No transfer_data on PaymentIntent', pi['transfer_data'] is None),
    ('No application_fee_amount', pi['application_fee_amount'] is None),
    ('transfer_group is set', pi['transfer_group'] is not None),
    ('No destination on Charge', ch['destination'] is None),
    ('No on_behalf_of on Charge', ch['on_behalf_of'] is None),
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
