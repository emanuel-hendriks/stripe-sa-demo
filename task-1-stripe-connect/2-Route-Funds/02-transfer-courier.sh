#!/bin/bash
# Transfer EUR 4.00 to Courier
source ~/.bashrc
DIR="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p "$DIR/response"

COURIER_ACCT=$(python3 -c "import json; print(json.load(open('$DIR/../0-Onboarding/response/02-create-courier-response.json'))['id'])")
CHARGE_ID=$(python3 -c "import json; print(json.load(open('$DIR/../1-Collect-Payment/response/02-confirm-payment-intent-response.json'))['latest_charge'])")

echo "Courier: $COURIER_ACCT"
echo "Charge: $CHARGE_ID"
echo ""

curl -s https://api.stripe.com/v1/transfers \
  -u "$STRIPE_DEMO_KEY:" \
  -H "Idempotency-Key: transfer-courier-${TS}" \
  -d amount=400 \
  -d currency=eur \
  -d "destination"="$COURIER_ACCT" \
  -d "source_transaction"="$CHARGE_ID" \
  -d transfer_group="order_001" \
  -d "metadata[recipient]"="courier" \
  -d "metadata[order_id]"="order_001" \
  | python3 -m json.tool | tee "$DIR/response/02-transfer-courier-response.json"
