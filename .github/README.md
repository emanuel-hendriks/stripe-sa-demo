# GitHub Actions -- Stripe Demo Flow

## What it does

Runs the full Stripe Connect demo end-to-end against the live test API:

1. **Onboard** -- creates two Custom connected accounts (restaurant + courier) in DE, fulfills KYC
2. **Pay** -- creates and confirms a EUR 20.00 PaymentIntent with `transfer_group`
3. **Transfer** -- routes EUR 14.00 to restaurant and EUR 4.00 to courier via `POST /v1/transfers` with `source_transaction`
4. **Verify** -- asserts 12 checks: payment status, amounts, SCT pattern (no `on_behalf_of`, no `transfer_data`, no `destination` on charge)

## Trigger

Manual only (`workflow_dispatch`). From the CLI:

```bash
gh workflow run stripe-demo.yml
```

Or from the GitHub Actions tab: click "Run workflow".

## Secrets

| Name | Value | Where to find it |
|------|-------|------------------|
| `STRIPE_TEST_KEY` | `sk_test_...` | Stripe Dashboard > Developers > API keys |

Set via CLI:

```bash
gh secret set STRIPE_TEST_KEY
```

## Idempotency

Each run uses `GITHUB_RUN_ID` as the idempotency key suffix, so runs never collide. Locally, falls back to Unix timestamp.

## Output

All 12 checks must pass:

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
