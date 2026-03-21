#!/bin/bash
# Step 2: Confirm PaymentIntent with test card pm_card_bypassPending
# bypassPending makes funds immediately available for transfers in Objective 3
source ~/.bashrc
DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR/response"

PI_ID=$(python3 -c "import json; print(json.load(open('$DIR/response/01-create-payment-intent-response.json'))['id'])")
echo "Confirming PaymentIntent: $PI_ID"
echo ""

curl -s "https://api.stripe.com/v1/payment_intents/$PI_ID/confirm" \
  -u "$STRIPE_DEMO_KEY:" \
  -d payment_method=pm_card_bypassPending \
  | python3 -m json.tool | tee "$DIR/response/02-confirm-payment-intent-response.json"
