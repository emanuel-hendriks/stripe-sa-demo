#!/bin/bash
# Step 1b: Create Courier connected account (individual, DE, MCC 4215)
source ~/.bashrc
DIR="$(dirname "$0")"

curl -s https://api.stripe.com/v1/accounts \
  -u "$STRIPE_DEMO_KEY:" \
  -d type=custom \
  -d country=DE \
  -d "capabilities[card_payments][requested]"=true \
  -d "capabilities[transfers][requested]"=true \
  -d business_type=individual \
  -d "business_profile[mcc]"=4215 \
  -d "business_profile[name]"="Courier" \
  -d "business_profile[url]"="https://courier-company-website.com" \
  | python3 -m json.tool | tee "$DIR/02-create-courier-response.json"
