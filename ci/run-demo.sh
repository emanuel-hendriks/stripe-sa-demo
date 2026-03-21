#!/usr/bin/env bash
# Self-contained Stripe Connect demo: onboard, pay, transfer, verify.
# Uses unique idempotency keys per run to avoid collisions with local demo.
set -euo pipefail

RUN_ID="${GITHUB_RUN_ID:-$(date +%s)}"
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/.ci-output"
mkdir -p "$OUT"

echo "=== Run ID: $RUN_ID ==="

# --- Objective 1: Onboard ---

echo ""
echo "=== 1a. Create Restaurant account ==="
curl -s https://api.stripe.com/v1/accounts \
  -u "$STRIPE_DEMO_KEY:" \
  -d type=custom \
  -d country=DE \
  -d "capabilities[card_payments][requested]"=true \
  -d "capabilities[transfers][requested]"=true \
  -d business_type=company \
  -d "business_profile[mcc]"=5812 \
  -d "business_profile[name]"="CI Restaurant $RUN_ID" \
  -d "business_profile[url]"="https://restaurant-website.com" \
  | python3 -m json.tool | tee "$OUT/restaurant.json"

RESTAURANT=$(python3 -c "import json; print(json.load(open('$OUT/restaurant.json'))['id'])")
echo "Restaurant: $RESTAURANT"

echo ""
echo "=== 1b. Create Courier account ==="
curl -s https://api.stripe.com/v1/accounts \
  -u "$STRIPE_DEMO_KEY:" \
  -d type=custom \
  -d country=DE \
  -d "capabilities[card_payments][requested]"=true \
  -d "capabilities[transfers][requested]"=true \
  -d business_type=individual \
  -d "business_profile[mcc]"=4215 \
  -d "business_profile[name]"="CI Courier $RUN_ID" \
  -d "business_profile[url]"="https://courier-company-website.com" \
  | python3 -m json.tool | tee "$OUT/courier.json"

COURIER=$(python3 -c "import json; print(json.load(open('$OUT/courier.json'))['id'])")
echo "Courier: $COURIER"

echo ""
echo "=== 1c. Fulfill Restaurant KYC ==="
curl -s "https://api.stripe.com/v1/accounts/$RESTAURANT" \
  -u "$STRIPE_DEMO_KEY:" \
  -d "company[name]"="Restaurant GmbH" \
  -d "company[tax_id]"="HRB 1234" \
  -d "company[phone]"="0000000000" \
  -d "company[address][line1]"="address_full_match" \
  -d "company[address][city]"="Berlin" \
  -d "company[address][postal_code]"="10115" \
  -d "company[directors_provided]"=true \
  -d "company[executives_provided]"=true \
  -d "company[owners_provided]"=true \
  -d "external_account[object]"="bank_account" \
  -d "external_account[country]"="DE" \
  -d "external_account[currency]"="eur" \
  -d "external_account[account_number]"="DE89370400440532013000" \
  -d "tos_acceptance[date]"="$(date +%s)" \
  -d "tos_acceptance[ip]"="127.0.0.1" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps({k: d.get(k) for k in ['id','charges_enabled','payouts_enabled']}, indent=2))"

curl -s "https://api.stripe.com/v1/accounts/$RESTAURANT/persons" \
  -u "$STRIPE_DEMO_KEY:" \
  -d "first_name"="Jenny" -d "last_name"="Rosen" \
  -d "email"="jenny@restaurant-website.com" -d "phone"="0000000000" \
  -d "dob[day]"=1 -d "dob[month]"=1 -d "dob[year]"=1901 \
  -d "address[line1]"="address_full_match" -d "address[city]"="Berlin" -d "address[postal_code]"="10115" \
  -d "relationship[representative]"=true -d "relationship[executive]"=true \
  -d "relationship[director]"=true -d "relationship[owner]"=true \
  -d "relationship[percent_ownership]"=100 -d "relationship[title]"="CEO" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps({k: d.get(k) for k in ['id','first_name','last_name']}, indent=2))"

echo ""
echo "=== 1d. Fulfill Courier KYC ==="
curl -s "https://api.stripe.com/v1/accounts/$COURIER" \
  -u "$STRIPE_DEMO_KEY:" \
  -d "individual[first_name]"="Max" -d "individual[last_name]"="Mustermann" \
  -d "individual[dob][day]"=1 -d "individual[dob][month]"=1 -d "individual[dob][year]"=1901 \
  -d "individual[email]"="max@courier-company-website.com" -d "individual[phone]"="0000000000" \
  -d "individual[address][line1]"="address_full_match" -d "individual[address][city]"="Berlin" -d "individual[address][postal_code]"="10115" \
  -d "external_account[object]"="bank_account" -d "external_account[country]"="DE" \
  -d "external_account[currency]"="eur" -d "external_account[account_number]"="DE89370400440532013000" \
  -d "tos_acceptance[date]"="$(date +%s)" -d "tos_acceptance[ip]"="127.0.0.1" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps({k: d.get(k) for k in ['id','charges_enabled','payouts_enabled']}, indent=2))"

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
