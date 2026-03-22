#!/usr/bin/env bash
# Query destination payments (py_) on connected accounts
# These are charges Stripe auto-creates on the connected account's ledger when a transfer lands.
# The py_ object lives on the connected account, not the platform.
# You MUST pass -H "Stripe-Account: acct_xxx" to query it.
# Without it, Stripe looks on the platform account and returns 404.
source ~/.bashrc
DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO="$DIR/../.."
TS=$(date +%Y%m%d-%H%M%S)
OUT="$DIR/response/destination-payments/$TS"
mkdir -p "$OUT"

RESTAURANT=$(python3 -c "import json; print(json.load(open('$DEMO/0-Onboarding/01-create-restaurant-response.json'))['id'])")
COURIER=$(python3 -c "import json; print(json.load(open('$DEMO/0-Onboarding/02-create-courier-response.json'))['id'])")
PY_RESTAURANT=$(python3 -c "import json; print(json.load(open('$DEMO/2-Route-Funds/01-transfer-restaurant-response.json'))['destination_payment'])")
PY_COURIER=$(python3 -c "import json; print(json.load(open('$DEMO/2-Route-Funds/02-transfer-courier-response.json'))['destination_payment'])")

echo "=== Run: $TS ==="
echo "=== Output: $OUT ==="

echo ""
echo "=== Restaurant destination payment ($PY_RESTAURANT) ==="
echo "curl -s /v1/charges/$PY_RESTAURANT -H 'Stripe-Account: $RESTAURANT'"
echo ""
curl -s "https://api.stripe.com/v1/charges/$PY_RESTAURANT" \
  -u "$STRIPE_DEMO_KEY:" \
  -H "Stripe-Account: $RESTAURANT" \
  | python3 -m json.tool | tee "$OUT/${TS}_restaurant.json"

echo ""
echo "=== Courier destination payment ($PY_COURIER) ==="
echo "curl -s /v1/charges/$PY_COURIER -H 'Stripe-Account: $COURIER'"
echo ""
curl -s "https://api.stripe.com/v1/charges/$PY_COURIER" \
  -u "$STRIPE_DEMO_KEY:" \
  -H "Stripe-Account: $COURIER" \
  | python3 -m json.tool | tee "$OUT/${TS}_courier.json"

echo ""
echo "=== All responses saved to $OUT ==="
