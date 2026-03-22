#!/bin/bash
# Step 0: Delete existing connected accounts
source ~/.bashrc

echo "=== Listing existing accounts ==="
ACCOUNTS=$(curl -s https://api.stripe.com/v1/accounts -u "$STRIPE_MAGENTA_KEY:" -G -d limit=100 \
  | python3 -c "import json,sys; [print(a['id']) for a in json.load(sys.stdin)['data']]")

if [ -z "$ACCOUNTS" ]; then
  echo "No accounts to delete"
else
  for acct in $ACCOUNTS; do
    echo "Deleting $acct..."
    curl -s -X DELETE "https://api.stripe.com/v1/accounts/$acct" -u "$STRIPE_MAGENTA_KEY:" \
      | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'  deleted={d.get(\"deleted\")} id={d.get(\"id\")}')"
  done
fi

echo ""
echo "=== Verification: remaining accounts ==="
curl -s https://api.stripe.com/v1/accounts -u "$STRIPE_MAGENTA_KEY:" -G -d limit=100 \
  | python3 -c "import json,sys; d=json.load(sys.stdin)['data']; print('None - clean' if not d else d)"
