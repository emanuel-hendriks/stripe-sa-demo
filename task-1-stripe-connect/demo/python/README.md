# Stripe Connect Demo -- Objectives 2 & 3

Python script using the `stripe` SDK (v14.4.1) to demonstrate payment collection and fund routing for an on-demand delivery platform via Stripe Connect.

The script makes four Stripe API calls through the Python SDK. All calls use `stripe.api_key` set to a platform-level test secret key (`sk_test_...`), authenticated via `demo_utils.py` on import. Each call includes an `idempotency_key` derived from the current timestamp to ensure safe retries.

---

## Objective 2: Collect Payment (EUR 20.00)

### Step 1 -- `stripe.PaymentIntent.create()` -> `POST /v1/payment_intents`

```python
pi = stripe.PaymentIntent.create(
    amount=2000, currency="eur",
    payment_method_types=["card"],
    transfer_group="order_001",
    metadata={"order_id": "order_001", "restaurant": restaurant_id, "courier": courier_id},
    idempotency_key=f"payment-order-{ts}",
)
```

Creates a PaymentIntent on the platform account. The Separate Charges and Transfers pattern is established here by what is NOT passed: no `transfer_data` (would make it a Destination Charge), no `on_behalf_of` (platform is merchant of record), no `application_fee_amount` (fee is implicit in SCT).

`transfer_group="order_001"` is an organizational tag that propagates to the charge and links it to the transfers in Objective 3. `metadata` embeds both connected account IDs for traceability in the Dashboard and webhook payloads.

Returns `status: requires_payment_method` -- the PaymentIntent exists but has no card attached.

### Step 2 -- `stripe.PaymentIntent.confirm()` -> `POST /v1/payment_intents/{id}/confirm`

```python
pi = stripe.PaymentIntent.confirm(pi.id, payment_method="pm_card_bypassPending")
```

Attaches a payment method and confirms in a single SDK call. `pm_card_bypassPending` is a Stripe test token that skips 3DS authentication and makes funds immediately available (bypassing the ~2 day pending period for EU cards).

In production, this step happens client-side: `stripe.js` calls `confirmPayment()` with the `client_secret` from Step 1. EU cards would trigger SCA/3DS, moving the PI through `requires_action` before reaching `succeeded`.

Returns `status: succeeded` and `latest_charge: ch_...` -- the charge ID that anchors the transfers.

---

## Objective 3: Route Funds via Separate Charges & Transfers

The script reads `latest_charge` from the Step 2 response file, then creates two transfers against that charge. The platform retains the remainder.

### Step 3 -- `stripe.Transfer.create()` -> `POST /v1/transfers` (Restaurant)

```python
xfer_r = stripe.Transfer.create(
    amount=1400, currency="eur", destination=restaurant_id,
    source_transaction=charge_id, transfer_group="order_001",
    metadata={"recipient": "restaurant", "order_id": "order_001"},
    idempotency_key=f"transfer-restaurant-{ts}",
)
```

Moves EUR 14.00 from the platform balance to the restaurant's connected account. `source_transaction=charge_id` ties the transfer to the original charge: the transfer succeeds immediately even if the charge funds are still pending, but funds only become available on the connected account when the source charge settles. This also enables Stripe to auto-reverse the transfer if the charge is disputed.

### Step 4 -- `stripe.Transfer.create()` -> `POST /v1/transfers` (Courier)

```python
xfer_c = stripe.Transfer.create(
    amount=400, currency="eur", destination=courier_id,
    source_transaction=charge_id, transfer_group="order_001",
    metadata={"recipient": "courier", "order_id": "order_001"},
    idempotency_key=f"transfer-courier-{ts}",
)
```

Same pattern, EUR 4.00 to the courier. Both transfers reference the same `source_transaction`. Stripe allows multiple transfers against one charge as long as their sum does not exceed the charge amount.

### Platform revenue (implicit)

```
Platform retains: EUR 2.00 (2000 - 1400 - 400 = 200 cents)
```

The platform's 10% commission stays in its Stripe balance automatically. In SCT, the platform fee is `charge - sum(transfers)`. No API call needed.

---

## SDK method summary

| SDK call | REST endpoint | Object created | Key parameter |
|----------|--------------|----------------|---------------|
| `stripe.PaymentIntent.create()` | `POST /v1/payment_intents` | `pi_...` | `transfer_group` (SCT pattern) |
| `stripe.PaymentIntent.confirm()` | `POST /v1/payment_intents/{id}/confirm` | `ch_...` (via `latest_charge`) | `payment_method` (test card) |
| `stripe.Transfer.create()` x2 | `POST /v1/transfers` | `tr_...` | `source_transaction`, `destination` |

## Why SCT over Destination Charges

Destination Charges (`transfer_data[destination]`) only support a single recipient per charge. This delivery platform needs to split one payment across two connected accounts (restaurant + courier), which requires Separate Charges and Transfers. SCT also decouples transfers from the charge, allowing the courier transfer to be created later when a driver accepts the delivery.
