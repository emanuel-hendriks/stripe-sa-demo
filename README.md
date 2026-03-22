# Stripe Solutions Architect -- Technical Screen

Two tasks for the SA interview at Stripe (Dublin, EMEA/DACH).

---

## Task 1: Stripe Connect -- On-Demand Delivery Service

Design and demo a payment flow for a delivery platform with four parties: platform, customer, restaurant, courier.

### Objectives

**Objective 1: Onboard** -- Create Custom connected accounts (restaurant as company/DE, courier as individual/DE) and fulfill KYC via the API. Restaurant requires company details, representative person, and beneficial ownership declaration (EU AML). Courier requires individual identity only.

**Objective 2: Collect Payment** -- Create a EUR 20.00 PaymentIntent on the platform account using the Separate Charges and Transfers pattern (`transfer_group`, no `transfer_data`, no `on_behalf_of`). Confirm with a test card.

**Objective 3: Route Funds** -- Split the charge via two `POST /v1/transfers` calls with `source_transaction`: EUR 14.00 to restaurant, EUR 4.00 to courier, EUR 2.00 retained by platform implicitly.

### Project structure

```
.
├── README.md                                # this file
├── .gitignore                               # excludes response JSON, logs, .venv, .DS_Store
├── .github/
│   └── workflows/
│       └── stripe-demo.yml                 # GitHub Actions: manual dispatch, runs Obj 2+3
├── ci/
│   ├── run-demo.sh                          # curl-based demo script (called by CI)
│   └── README.md                            # CI workflow documentation
│
├── task-1-stripe-connect/
│   └── demo/
│       ├── demo_utils.py                    # shared helpers: stripe.api_key init, save/load JSON, pp, banner, wait
│       ├── log_util.py                      # tee-logger: writes stdout to terminal + logs/
│       ├── README.md                        # dependency chain between scripts, execution order
│       │
│       ├── 0-Onboarding/                    # Objective 1: create and verify connected accounts
│       │   ├── onboard.py                   # Python: Account.create + Account.modify + create_person (KYC)
│       │   ├── cleanup.py                   # Python: Account.delete all + wipe response files
│       │   ├── 01-create-restaurant.sh      # curl: POST /v1/accounts (company/DE, MCC 5812)
│       │   ├── 02-create-courier.sh         # curl: POST /v1/accounts (individual/DE, MCC 4215)
│       │   ├── 03-restaurant-fulfill-kyc.sh # curl: POST /v1/accounts/{id} (company + person + IBAN + ToS)
│       │   ├── 04-courier-fulfill-kyc.sh    # curl: POST /v1/accounts/{id} (individual + IBAN + ToS)
│       │   ├── 00-delete-existing-accounts.sh # curl: delete all connected accounts
│       │   ├── 00-clean-responses.sh        # rm response/*.json
│       │   ├── specs.md                     # KYC field requirements per account type
│       │   ├── account-analysis.md          # analysis of account object fields post-KYC
│       │   └── response/                    # generated: account JSON (gitignored)
│       │
│       ├── 1-Collect-Payment/               # Objective 2: create and confirm PaymentIntent
│       │   ├── 01-create-payment-intent.sh  # curl: POST /v1/payment_intents (EUR 20, transfer_group)
│       │   ├── 02-confirm-payment-intent.sh # curl: POST /v1/payment_intents/{id}/confirm (test card)
│       │   ├── README.md                    # payment flow explanation
│       │   └── response/                    # generated: PaymentIntent JSON (gitignored)
│       │
│       ├── 2-Route-Funds/                   # Objective 3: split funds via transfers
│       │   ├── 01-transfer-restaurant.sh    # curl: POST /v1/transfers (EUR 14, source_transaction)
│       │   ├── 02-transfer-courier.sh       # curl: POST /v1/transfers (EUR 4, source_transaction)
│       │   ├── README.md                    # transfer flow explanation
│       │   └── response/                    # generated: Transfer JSON (gitignored)
│       │
│       ├── 3-test/                          # post-demo verification scripts
│       │   ├── 01-verify-accounts/          # assert charges_enabled, payouts_enabled
│       │   ├── 02-verify-payment/           # assert PI status, amount, currency
│       │   ├── 03-verify-transfers/         # assert transfer amounts, destinations
│       │   ├── 04-verify-sct-pattern/       # assert no on_behalf_of, no transfer_data
│       │   ├── 05-verify-events/            # list webhook events for the demo run
│       │   ├── 06-query-all-objects/        # dump all objects for inspection
│       │   └── README.md                    # verification checklist
│       │
│       ├── python/                          # Python SDK implementation (live demo)
│       │   ├── demo.py                      # Objectives 2 & 3: 4 stripe SDK calls, interactive pauses
│       │   ├── phases-1-to-3.py             # all 3 objectives in one script, --interactive flag
│       │   ├── README.md                    # SDK method-to-endpoint mapping, objective walkthrough
│       │   └── .venv/                       # Python 3.14, stripe SDK 14.4.1
│       │
│       └── logs/                            # timestamped run logs (gitignored)
│
└── task-2-reverse-api/                      # Task 2: reverse API design
    └── deliverable-task-2.md                # API spec: Maps.co <-> Food.co partner integration
```

Two parallel implementations exist for the Stripe calls: `python/` uses the SDK for the live demo, `*.sh` scripts + `ci/run-demo.sh` use curl for CI and step-by-step inspection. The `response/` directories chain the steps -- each script writes JSON, the next reads IDs from it.

### Stripe SDK methods used

| Script | SDK method | REST endpoint | Purpose |
|--------|-----------|---------------|---------|
| `onboard.py` | `stripe.Account.create()` | `POST /v1/accounts` | Create Custom connected account |
| `onboard.py` | `stripe.Account.modify()` | `POST /v1/accounts/{id}` | Submit KYC data + bank account |
| `onboard.py` | `stripe.Account.create_person()` | `POST /v1/accounts/{id}/persons` | Add representative/owner (company) |
| `onboard.py` | `stripe.Account.retrieve()` | `GET /v1/accounts/{id}` | Verify charges_enabled/payouts_enabled |
| `demo.py` | `stripe.PaymentIntent.create()` | `POST /v1/payment_intents` | EUR 20.00 charge with `transfer_group` |
| `demo.py` | `stripe.PaymentIntent.confirm()` | `POST /v1/payment_intents/{id}/confirm` | Attach test card, move to `succeeded` |
| `demo.py` | `stripe.Transfer.create()` x2 | `POST /v1/transfers` | Route funds to restaurant and courier |

### Run locally

```bash
export STRIPE_DEMO_KEY="sk_test_..."
cd task-1-stripe-connect/demo/python
source .venv/bin/activate

# one-time setup
python3 ../0-Onboarding/onboard.py

# live demo
python3 demo.py
```

---

## Task 2: Reverse API -- Maps.co / Food.co Integration

Design a reverse API that delivery partners (Food.co) implement so Maps.co can offer food ordering within its maps app. Covers restaurant selection, menu viewing, order placement, and order tracking.

Deliverable: `task-2-reverse-api/deliverable-task-2.md`

---

## CI

GitHub Actions workflow (`stripe-demo.yml`) runs Objectives 2 and 3 against the Stripe test API on manual dispatch. Uses `curl` against the REST API directly (no SDK dependency in CI).

```bash
gh workflow run stripe-demo.yml
```

### Secrets

| Name | Description |
|------|-------------|
| `STRIPE_TEST_KEY` | `sk_test_...` from Stripe Dashboard |
| `RESTAURANT_ACCT` | Pre-created connected account ID |
| `COURIER_ACCT` | Pre-created connected account ID |

### Verification

12 assertions: payment status, amounts, currency, `transfer_group` propagation, `source_transaction` linkage, SCT pattern confirmation (no `on_behalf_of`, no `transfer_data`).
