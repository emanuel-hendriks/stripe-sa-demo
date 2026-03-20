#!/bin/bash
# Step 1: Create PaymentIntent on the platform account (SCT pattern)
# EUR 20.00 order, linked to connected accounts via metadata
source ~/.bashrc
DIR="$(dirname "$0")"

RESTAURANT_ACCT=$(python3 -c "import json; print(json.load(open('$DIR/../0-Onboarding/01-create-restaurant-response.json'))['id'])")
COURIER_ACCT=$(python3 -c "import json; print(json.load(open('$DIR/../0-Onboarding/02-create-courier-response.json'))['id'])")

echo "Restaurant: $RESTAURANT_ACCT"
echo "Courier: $COURIER_ACCT"
echo ""

curl -s https://api.stripe.com/v1/payment_intents \
  -u "$STRIPE_DEMO_KEY:" \
  -H "Idempotency-Key: payment-order-003" \
  -d amount=2000 \
  -d currency=eur \
  -d "payment_method_types[]"=card \
  -d transfer_group="order_001" \
  -d "metadata[order_id]"="order_001" \
  -d "metadata[restaurant]"="$RESTAURANT_ACCT" \
  -d "metadata[courier]"="$COURIER_ACCT" \
  | python3 -m json.tool | tee "$DIR/01-create-payment-intent-response.json"
