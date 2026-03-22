#!/bin/bash
# Step 1a: Create Restaurant connected account (company, DE, MCC 5812)
source ~/.bashrc
DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR/response"

curl -s https://api.stripe.com/v1/accounts \
  -u "$STRIPE_DEMO_KEY:" \
  -d type=custom \
  -d country=DE \
  -d "capabilities[card_payments][requested]"=true \
  -d "capabilities[transfers][requested]"=true \
  -d business_type=company \
  -d "business_profile[mcc]"=5812 \
  -d "business_profile[name]"="Restaurant" \
  -d "business_profile[url]"="https://restaurant-website.com" \
  | python3 -m json.tool | tee "$DIR/response/01-create-restaurant-response.json"
