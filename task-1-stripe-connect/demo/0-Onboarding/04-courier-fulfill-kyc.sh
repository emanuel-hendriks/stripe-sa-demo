#!/bin/bash
# Step 2b: Fulfill Courier KYC (individual, DE) using Stripe test tokens
source ~/.bashrc
DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR/response"

ACCT=$(python3 -c "import json; print(json.load(open('$DIR/response/02-create-courier-response.json'))['id'])")
echo "Courier account: $ACCT"

echo ""
echo "=== Updating individual details + external account + ToS ==="
curl -s "https://api.stripe.com/v1/accounts/$ACCT" \
  -u "$STRIPE_DEMO_KEY:" \
  -d "individual[first_name]"="Max" \
  -d "individual[last_name]"="Mustermann" \
  -d "individual[dob][day]"=1 \
  -d "individual[dob][month]"=1 \
  -d "individual[dob][year]"=1901 \
  -d "individual[email]"="max@courier-company-website.com" \
  -d "individual[phone]"="0000000000" \
  -d "individual[address][line1]"="address_full_match" \
  -d "individual[address][city]"="Berlin" \
  -d "individual[address][postal_code]"="10115" \
  -d "external_account[object]"="bank_account" \
  -d "external_account[country]"="DE" \
  -d "external_account[currency]"="eur" \
  -d "external_account[account_number]"="DE89370400440532013000" \
  -d "tos_acceptance[date]"="$(date +%s)" \
  -d "tos_acceptance[ip]"="127.0.0.1" \
  | python3 -m json.tool | tee "$DIR/response/04-courier-kyc-response.json"
