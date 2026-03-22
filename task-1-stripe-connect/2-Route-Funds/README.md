# Objective 3: Route Funds

## Result

| Transfer | Recipient | Amount | ID | destination_payment |
|----------|-----------|--------|-----|---------------------|
| Restaurant | `acct_1TCpvJA8zh16dkqQ` | EUR 14.00 | `tr_3TCq6RATzSZT5qY73yBJMDTj` | `py_1TCqAKA8zh16dkqQZibz39ny` |
| Courier | `acct_1TCpviAfWDIIjKRu` | EUR 4.00 | `tr_3TCq6RATzSZT5qY73Qo4do6c` | `py_1TCqAYAfWDIIjKRuQw0u53vz` |
| Platform | (keeps remainder) | ~EUR 1.10 | -- | -- |

Source charge: `ch_3TCq6RATzSZT5qY73QX3CITT` (EUR 20.00)

## Scripts

| # | Script | Output |
|---|--------|--------|
| 1 | `01-transfer-restaurant.sh` | `01-transfer-restaurant-response.json` |
| 2 | `02-transfer-courier.sh` | `02-transfer-courier-response.json` |

## Key parameters

- `source_transaction` -- ties transfer availability to the charge; transfer can't exceed charge amount
- `transfer_group=order_001` -- organizational link between charge and transfers; not enforced by Stripe
- `destination_payment` -- Stripe auto-creates a `py_` object on the connected account's balance
