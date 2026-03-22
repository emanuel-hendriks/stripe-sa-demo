#!/usr/bin/env bash
# Query objects across platform and connected accounts
# Demonstrates the Stripe-Account header for cross-account queries
# Saves full JSON responses to a timestamped run folder with subfolders per type
set -eo pipefail
source ~/.bashrc
DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO="$DIR/../.."
TS=$(date +%Y%m%d-%H%M%S)
OUT="$DIR/response/all-objects/$TS"
mkdir -p "$OUT/payment" "$OUT/transfers" "$OUT/destination-payments" "$OUT/balances"

# Read IDs from response files
PI=$(python3 -c "import json; print(json.load(open('$DEMO/1-Collect-Payment/02-confirm-payment-intent-response.json'))['id'])")
CHARGE=$(python3 -c "import json; print(json.load(open('$DEMO/1-Collect-Payment/02-confirm-payment-intent-response.json'))['latest_charge'])")
TR_RESTAURANT=$(python3 -c "import json; print(json.load(open('$DEMO/2-Route-Funds/01-transfer-restaurant-response.json'))['id'])")
TR_COURIER=$(python3 -c "import json; print(json.load(open('$DEMO/2-Route-Funds/02-transfer-courier-response.json'))['id'])")
RESTAURANT=$(python3 -c "import json; print(json.load(open('$DEMO/0-Onboarding/01-create-restaurant-response.json'))['id'])")
COURIER=$(python3 -c "import json; print(json.load(open('$DEMO/0-Onboarding/02-create-courier-response.json'))['id'])")
PY_RESTAURANT=$(python3 -c "import json; print(json.load(open('$DEMO/2-Route-Funds/01-transfer-restaurant-response.json'))['destination_payment'])")
PY_COURIER=$(python3 -c "import json; print(json.load(open('$DEMO/2-Route-Funds/02-transfer-courier-response.json'))['destination_payment'])")

echo "=== Run: $TS ==="
echo "=== Output: $OUT ==="

echo ""
echo "=== Platform objects (no Stripe-Account header needed) ==="

echo ""
echo "--- PaymentIntent ($PI) ---"
curl -s "https://api.stripe.com/v1/payment_intents/$PI" \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -m json.tool | tee "$OUT/payment/${TS}_payment-intent.json"

echo ""
echo "--- Charge ($CHARGE) ---"
curl -s "https://api.stripe.com/v1/charges/$CHARGE" \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -m json.tool | tee "$OUT/payment/${TS}_charge.json"

echo ""
echo "--- Transfer to Restaurant ($TR_RESTAURANT) ---"
curl -s "https://api.stripe.com/v1/transfers/$TR_RESTAURANT" \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -m json.tool | tee "$OUT/transfers/${TS}_transfer-restaurant.json"

echo ""
echo "--- Transfer to Courier ($TR_COURIER) ---"
curl -s "https://api.stripe.com/v1/transfers/$TR_COURIER" \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -m json.tool | tee "$OUT/transfers/${TS}_transfer-courier.json"

echo ""
echo "=== Connected account objects (requires Stripe-Account header) ==="

echo ""
echo "--- Restaurant destination payment ($PY_RESTAURANT) ---"
echo "    curl -s /v1/charges/$PY_RESTAURANT -H 'Stripe-Account: $RESTAURANT'"
curl -s "https://api.stripe.com/v1/charges/$PY_RESTAURANT" \
  -u "$STRIPE_DEMO_KEY:" \
  -H "Stripe-Account: $RESTAURANT" \
  | python3 -m json.tool | tee "$OUT/destination-payments/${TS}_restaurant.json"

echo ""
echo "--- Courier destination payment ($PY_COURIER) ---"
echo "    curl -s /v1/charges/$PY_COURIER -H 'Stripe-Account: $COURIER'"
curl -s "https://api.stripe.com/v1/charges/$PY_COURIER" \
  -u "$STRIPE_DEMO_KEY:" \
  -H "Stripe-Account: $COURIER" \
  | python3 -m json.tool | tee "$OUT/destination-payments/${TS}_courier.json"

echo ""
echo "--- Restaurant balance ---"
curl -s "https://api.stripe.com/v1/balance" \
  -u "$STRIPE_DEMO_KEY:" \
  -H "Stripe-Account: $RESTAURANT" \
  | python3 -m json.tool | tee "$OUT/balances/${TS}_restaurant.json"

echo ""
echo "--- Courier balance ---"
curl -s "https://api.stripe.com/v1/balance" \
  -u "$STRIPE_DEMO_KEY:" \
  -H "Stripe-Account: $COURIER" \
  | python3 -m json.tool | tee "$OUT/balances/${TS}_courier.json"

echo ""
echo "=== All responses saved to $OUT ==="
