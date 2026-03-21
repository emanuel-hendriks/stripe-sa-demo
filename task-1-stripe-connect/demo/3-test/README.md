# Verification: End-to-End Test Suite

All three objectives verified against live Stripe API responses. 22/22 checks passed.

## Results

| Objective | Checks | Status |
|-----------|--------|--------|
| 1 -- Onboarding | 10 | ALL PASSED |
| 2 -- Collect Payment | 5 | ALL PASSED |
| 3 -- Route Funds | 7 | ALL PASSED |

## Fund Flow Summary

```
Customer pays:      EUR 20.00
Stripe fee:         EUR  0.90
Net on platform:    EUR 19.10
  -> Restaurant:    EUR 14.00
  -> Courier:       EUR  4.00
  = Platform keeps: EUR  1.10
```

## Structure

```
3-test/
  01-verify-accounts/
    01-verify-accounts.sh        # Fetches both accounts, asserts capabilities
    01-restaurant-account.json   # Restaurant account snapshot
    01-courier-account.json      # Courier account snapshot
  02-verify-payment/
    02-verify-payment.sh         # Fetches PaymentIntent, asserts status/amount
    02-payment-intent.json       # PaymentIntent snapshot
  03-verify-transfers/
    03-verify-transfers.sh       # Fetches transfers + balance txn, asserts split
    03-transfer-restaurant.json  # Restaurant transfer snapshot
    03-transfer-courier.json     # Courier transfer snapshot
    03-charge.json               # Charge snapshot
    03-balance-transaction.json  # Balance transaction (Stripe fees)
```

## Run all

```bash
for script in demo/3-test/0*/0*.sh; do bash "$script"; echo "---"; done
```
