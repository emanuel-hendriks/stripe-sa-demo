# GitHub Actions -- Stripe Demo Flow

## What it does

Mirrors the live interview demo against the Stripe test API. Accounts are pre-created; the workflow runs Objectives 2 and 3 only:

1. **Objective 2: Pay** -- creates and confirms a EUR 20.00 PaymentIntent with `transfer_group`
2. **Objective 3: Transfer** -- routes EUR 14.00 to restaurant and EUR 4.00 to courier via `POST /v1/transfers` with `source_transaction`
3. **Verify** -- asserts 12 checks: payment status, amounts, SCT pattern (no `on_behalf_of`, no `transfer_data`)

## Trigger

Manual only (`workflow_dispatch`):

```bash
gh workflow run stripe-demo.yml
```

## Secrets

| Name | Description |
|------|-------------|
| `STRIPE_TEST_KEY` | `sk_test_...` from Stripe Dashboard |
| `RESTAURANT_ACCT` | Connected account ID for the restaurant |
| `COURIER_ACCT` | Connected account ID for the courier |

Set via CLI:

```bash
gh secret set STRIPE_TEST_KEY
gh secret set RESTAURANT_ACCT --body "acct_..."
gh secret set COURIER_ACCT --body "acct_..."
```

## Idempotency

Each run uses `GITHUB_RUN_ID` as the idempotency key suffix. Runs never collide. Locally, falls back to Unix timestamp.

## Expected output

```
[PASS] PaymentIntent succeeded
[PASS] Amount is 2000
[PASS] Currency is EUR
[PASS] transfer_group set
[PASS] Restaurant transfer = 1400
[PASS] Courier transfer = 400
[PASS] Restaurant source_transaction matches charge
[PASS] Courier source_transaction matches charge
[PASS] Same transfer_group on restaurant
[PASS] Same transfer_group on courier
[PASS] No on_behalf_of (SCT)
[PASS] No transfer_data (SCT)
ALL 12 CHECKS PASSED
```
