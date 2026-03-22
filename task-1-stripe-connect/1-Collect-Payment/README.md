# Objective 2: Collect Payment from Customer

## Result

| Field | Value |
|-------|-------|
| PaymentIntent | `pi_3TCq6RATzSZT5qY73A3IbhVq` |
| Charge | `ch_3TCq6RATzSZT5qY73QX3CITT` |
| Amount | 2000 (EUR 20.00) |
| Status | `succeeded` |
| Transfer group | `order_001` |
| Payment method | `pm_card_bypassPending` |

## Scripts

| # | Script | Output |
|---|--------|--------|
| 1 | `01-create-payment-intent.sh` | `01-create-payment-intent-response.json` |
| 2 | `02-confirm-payment-intent.sh` | `02-confirm-payment-intent-response.json` |

## Why `pm_card_bypassPending`

Makes funds immediately available in the platform balance, so transfers in Objective 3 succeed without needing `source_transaction`. In production, funds go through a pending period before becoming available.
