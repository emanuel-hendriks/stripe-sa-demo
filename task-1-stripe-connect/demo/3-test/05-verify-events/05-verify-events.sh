#!/usr/bin/env bash
# List all events on the sandbox in chronological order, grouped by the demo flow
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== All Events (chronological) ==="
curl -s "https://api.stripe.com/v1/events?limit=100" \
  -u "$STRIPE_DEMO_KEY:" | python3 -c "
import sys, json

data = json.load(sys.stdin)['data']
# Reverse to chronological (API returns newest first)
data.reverse()

for e in data:
    ts = e['created']
    etype = e['type']
    obj = e['data']['object']
    obj_id = obj.get('id', '')

    # Annotate with context
    label = ''
    if 'account.updated' in etype:
        label = obj.get('business_profile', {}).get('name', obj_id)
    elif 'payment_intent' in etype:
        label = f'EUR {obj.get(\"amount\",0)/100:.2f} {obj.get(\"transfer_group\",\"\")}'
    elif 'charge' in etype:
        label = f'EUR {obj.get(\"amount\",0)/100:.2f}'
    elif 'transfer' in etype:
        label = f'EUR {obj.get(\"amount\",0)/100:.2f} -> {obj.get(\"destination\",\"\")}'
    elif 'capability' in etype:
        label = f'{obj.get(\"id\",\"\")} on {obj.get(\"account\",\"\")}'
    elif 'balance' in etype:
        label = obj_id
    elif 'person' in etype:
        label = f'{obj.get(\"first_name\",\"\")} {obj.get(\"last_name\",\"\")} on {obj.get(\"account\",\"\")}'
    elif 'bank_account' in etype or 'external_account' in etype:
        label = f'{obj.get(\"bank_name\",\"\")} on {obj.get(\"account\", obj_id)}'

    print(f'  {etype:55s} {label}')

print()
print(f'Total events: {len(data)}')
" | tee "$DIR/05-events.txt"

echo ""
echo "=== Expected SCT Event Sequence ==="
curl -s "https://api.stripe.com/v1/events?limit=100" \
  -u "$STRIPE_DEMO_KEY:" | python3 -c "
import sys, json

data = json.load(sys.stdin)['data']
data.reverse()

# Filter to the core SCT flow events
sct_types = [
    'payment_intent.created',
    'payment_intent.succeeded',
    'charge.succeeded',
    'transfer.created',
]

print('  Expected for SCT:')
print('    1. payment_intent.created')
print('    2. charge.succeeded')
print('    3. payment_intent.succeeded')
print('    4. transfer.created (restaurant)')
print('    5. transfer.created (courier)')
print()

found = [e for e in data if e['type'] in sct_types]
print('  Actual:')
for i, e in enumerate(found, 1):
    obj = e['data']['object']
    label = ''
    if 'payment_intent' in e['type']:
        label = f'EUR {obj[\"amount\"]/100:.2f} {obj.get(\"transfer_group\",\"\")}'
    elif 'charge' in e['type']:
        label = f'EUR {obj[\"amount\"]/100:.2f}'
    elif 'transfer' in e['type']:
        label = f'EUR {obj[\"amount\"]/100:.2f} -> {obj.get(\"destination\",\"\")}'
    print(f'    {i}. {e[\"type\"]:40s} {label}')

print()
transfer_count = sum(1 for e in found if e['type'] == 'transfer.created')
has_pi_created = any(e['type'] == 'payment_intent.created' for e in found)
has_pi_succeeded = any(e['type'] == 'payment_intent.succeeded' for e in found)
has_charge = any(e['type'] == 'charge.succeeded' for e in found)

checks = [
    ('payment_intent.created fired', has_pi_created),
    ('charge.succeeded fired', has_charge),
    ('payment_intent.succeeded fired', has_pi_succeeded),
    ('transfer.created fired twice (2 recipients)', transfer_count == 2),
]
all_pass = True
for name, ok in checks:
    status = 'PASS' if ok else 'FAIL'
    if not ok: all_pass = False
    print(f'  [{status}] {name}')
print()
print('Events: ' + ('ALL CHECKS PASSED' if all_pass else 'SOME CHECKS FAILED'))
"
