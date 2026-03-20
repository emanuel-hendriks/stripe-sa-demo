#!/bin/bash
# Transfer EUR 14.00 to Restaurant
source ~/.bashrc
DIR="$(dirname "$0")"

RESTAURANT_ACCT=$(python3 -c "import json; print(json.load(open('$DIR/../0-Onboarding/01-create-restaurant-response.json'))['id'])")
CHARGE_ID=$(python3 -c "import json; print(json.load(open('$DIR/../1-Collect-Payment/02-confirm-payment-intent-response.json'))['latest_charge'])")

echo "Restaurant: $RESTAURANT_ACCT"
echo "Charge: $CHARGE_ID"
echo ""

curl -s https://api.stripe.com/v1/transfers \
  -u "$STRIPE_DEMO_KEY:" \
  -H "Idempotency-Key: transfer-order-003-restaurant" \
  -d amount=1400 \
  -d currency=eur \
  -d "destination"="$RESTAURANT_ACCT" \
  -d "source_transaction"="$CHARGE_ID" \
  -d transfer_group="order_001" \
  -d "metadata[recipient]"="restaurant" \
  -d "metadata[order_id]"="order_001" \
  | python3 -m json.tool | tee "$DIR/01-transfer-restaurant-response.json"
