#!/bin/bash
# Step 2a: Fulfill Restaurant KYC (company, DE) using Stripe test tokens
source ~/.bashrc
DIR="$(dirname "$0")"

ACCT=$(python3 -c "import json; print(json.load(open('$DIR/01-create-restaurant-response.json'))['id'])")
echo "Restaurant account: $ACCT"

echo ""
echo "=== Updating company details + external account + ToS ==="
curl -s "https://api.stripe.com/v1/accounts/$ACCT" \
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
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps({k: d.get(k) for k in ['id','charges_enabled','payouts_enabled','capabilities']}, indent=2))"

echo ""
echo "=== Creating representative/director/owner person ==="
curl -s "https://api.stripe.com/v1/accounts/$ACCT/persons" \
  -u "$STRIPE_DEMO_KEY:" \
  -d "first_name"="Jenny" \
  -d "last_name"="Rosen" \
  -d "email"="jenny@restaurant-website.com" \
  -d "phone"="0000000000" \
  -d "dob[day]"=1 \
  -d "dob[month]"=1 \
  -d "dob[year]"=1901 \
  -d "address[line1]"="address_full_match" \
  -d "address[city]"="Berlin" \
  -d "address[postal_code]"="10115" \
  -d "relationship[representative]"=true \
  -d "relationship[executive]"=true \
  -d "relationship[director]"=true \
  -d "relationship[owner]"=true \
  -d "relationship[percent_ownership]"=100 \
  -d "relationship[title]"="CEO" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps({k: d.get(k) for k in ['id','first_name','last_name']}, indent=2))"

echo ""
echo "=== Final account status ==="
curl -s "https://api.stripe.com/v1/accounts/$ACCT" \
  -u "$STRIPE_DEMO_KEY:" \
  | python3 -m json.tool | tee "$DIR/03-restaurant-kyc-response.json"
