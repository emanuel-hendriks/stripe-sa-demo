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
├── README.md
├── .github/
│   ├── README.md                            # CI documentation
│   └── workflows/
│       └── stripe-demo.yml                  # manual dispatch: Objectives 2+3
├── ci/
│   └── run-demo.sh                          # curl-based demo (used by CI)
│
├── task-1-stripe-connect/
│   └── demo/
│       ├── demo_utils.py                    # shared: stripe init, save/load, pp, banner, wait
│       ├── log_util.py                      # tee-logger (stdout + logfile)
│       ├── README.md                        # dependency chain, execution order
│       │
│       ├── 0-Onboarding/
│       │   ├── onboard.py                   # create accounts + KYC (Python)
│       │   ├── cleanup.py                   # delete accounts + response files
│       │   ├── 01-create-restaurant.sh      # curl equivalents
│       │   ├── 02-create-courier.sh
│       │   ├── 03-restaurant-fulfill-kyc.sh
│       │   ├── 04-courier-fulfill-kyc.sh
│       │   ├── 00-delete-existing-accounts.sh
│       │   ├── 00-clean-responses.sh
│       │   ├── specs.md                     # KYC requirements analysis
│       │   ├── account-analysis.md
│       │   └── response/                    # *.json (gitignored, generated)
│       │
│       ├── 1-Collect-Payment/
│       │   ├── 01-create-payment-intent.sh
│       │   ├── 02-confirm-payment-intent.sh
│       │   └── response/                    # *.json (gitignored, generated)
│       │
│       ├── 2-Route-Funds/
│       │   ├── 01-transfer-restaurant.sh
│       │   ├── 02-transfer-courier.sh
│       │   └── response/                    # *.json (gitignored, generated)
│       │
│       ├── 3-test/
│       │   ├── 01-verify-accounts/
│       │   ├── 02-verify-payment/
│       │   ├── 03-verify-transfers/
│       │   ├── 04-verify-sct-pattern/
│       │   ├── 05-verify-events/
│       │   └── 06-query-all-objects/
│       │
│       ├── python/
│       │   ├── demo.py                      # live demo: Objectives 2 & 3
│       │   ├── phases-1-to-3.py             # all 3 objectives in one script
│       │   ├── README.md
│       │   └── .venv/                       # Python 3.14, stripe SDK 14.4.1
│       │
│       └── logs/                            # timestamped run logs (gitignored)
│
└── task-2-reverse-api/
    └── deliverable-task-2.md                # reverse API design document
```

Two parallel implementations exist for the Stripe calls: `python/` (SDK, used for live demo) and the `*.sh` scripts + `ci/run-demo.sh` (curl, used for CI and step-by-step inspection). The `response/` directories are the glue -- each step writes JSON, the next step reads IDs from it.

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
