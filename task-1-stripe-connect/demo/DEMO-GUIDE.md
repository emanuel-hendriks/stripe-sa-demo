# Live Demo Guide -- Stripe Connect (Part 1)

Sandbox: **Magenta Rings** (`acct_1TDXnmPBb8eoHLwA`)
Script: `python/phases-1-to-3.py --interactive`
Env var: `STRIPE_MAGENTA_KEY`
Time budget: 15 minutes total

---

## Pre-demo checklist (do this 5 minutes before)

1. Open a terminal, `cd` into the `demo/` directory.
2. Confirm the env var is loaded:
   ```
   echo $STRIPE_MAGENTA_KEY | head -c 20
   ```
   Should print `sk_test_51TDXnmPBb8e`.
3. Open the Stripe Dashboard in a browser tab:
   - **Home**: https://dashboard.stripe.com/test/dashboard
   - **Connect > Accounts**: https://dashboard.stripe.com/test/connect/accounts/overview
   - **Payments**: https://dashboard.stripe.com/test/payments
   - **Balance**: https://dashboard.stripe.com/test/balance/overview
   - **Events**: https://dashboard.stripe.com/test/events
4. Confirm the sandbox is clean -- no connected accounts, no payments, no events.
   The dashboard should be empty. This is the whole point of the fresh sandbox.
5. Have your architecture diagram ready (the four-party diagram: Platform, Customer,
   Restaurant, Courier) either on a slide or whiteboard.
6. Have the Stripe docs open in a background tab:
   - https://docs.stripe.com/connect/separate-charges-and-transfers
   - https://docs.stripe.com/connect/custom/onboarding

---

## Narrative arc

The presentation tells a story in three acts. Each act maps to one objective from
the brief. The script pauses between acts (`--interactive` flag) so you control
the pacing.

### Opening (1 minute)

Say something like:

> "I'm going to walk through a food delivery platform built on Stripe Connect.
> Four parties: the platform -- that's us -- a restaurant, a courier, and a
> customer. I'll show the full lifecycle: onboarding the merchant and courier,
> collecting a payment, and splitting the funds. Everything runs against a live
> test-mode sandbox, and I'll show the dashboard alongside the API calls."

Point to your architecture diagram. Name the pattern: Separate Charges and
Transfers. Explain in one sentence why SCT fits: the charge lands on the platform
account, and we control when and how much goes to each connected account. This
decoupling is what lets us split one payment across multiple recipients.

### Phase 1 -- Onboard (4 minutes)

Press Enter to start. The script creates two Custom connected accounts in Germany.

What to narrate as each block runs:

**Restaurant (company/DE)**
- "Custom account type gives us full control over the UX -- the merchant never
  sees Stripe branding. In production we'd use hosted onboarding or embedded
  components, but for the demo I'm fulfilling KYC via the API directly."
- "Company account in Germany requires: legal entity details, a representative
  person with ownership info, an IBAN for payouts, and ToS acceptance."
- "MCC 5812 is 'Eating Places, Restaurants' -- this matters for card network
  categorization and interchange."
- When `charges_enabled: true` prints: "That confirms Stripe has verified the
  account. In production this can take minutes to days depending on the
  jurisdiction and risk signals."

**Courier (individual/DE)**
- "Individual account is simpler -- no company structure, no directors. Just
  personal details, IBAN, and ToS."
- "MCC 4215 is 'Courier Services'."
- When `charges_enabled: true` prints: "Both accounts are live. Let me show
  them on the dashboard."

**Dashboard moment**: Switch to the Connect > Accounts tab. Refresh. Show the
two accounts. Click into one to show the KYC status, capabilities, and external
account. This is a strong visual beat -- it proves the API calls are real.

### Phase 2 -- Collect Payment (4 minutes)

Press Enter. The script creates and confirms a PaymentIntent for EUR 20.00.

What to narrate:

**PaymentIntent creation**
- "The customer places an order for EUR 20. We create a PaymentIntent on the
  platform account -- not on a connected account. This is the 'separate' in
  Separate Charges and Transfers."
- "The `transfer_group` is a correlation key. It ties this charge to the
  transfers we'll create next. It's a string we control -- here it's
  `order_001`."
- "Status is `requires_payment_method` -- in production, Stripe.js or Checkout
  would collect the card. For the demo I'll confirm with a test card."

**PaymentIntent confirmation**
- "`pm_card_bypassPending` is a special test payment method that makes funds
  immediately available in the platform balance. In production, funds land after
  the standard settlement period."
- "Status is now `succeeded`. The charge ID is what we'll reference in the
  transfers."

**Dashboard moment**: Switch to Payments tab. Show the EUR 20.00 charge.
Click into it -- show the charge detail, the metadata, the transfer_group.
Switch to Events tab -- show the `payment_intent.created`,
`payment_intent.succeeded`, `charge.succeeded` events. This is clean because
the sandbox was fresh.

### Phase 3 -- Route Funds (4 minutes)

Press Enter. The script creates two transfers.

What to narrate:

**Transfer to Restaurant (EUR 14)**
- "Now we split the funds. EUR 14 goes to the restaurant. This is a Transfer
  object -- it moves money on Stripe's internal ledger from the platform
  balance to the connected account's balance. No money leaves Stripe yet."
- "`source_transaction` links this transfer to the specific charge. This is
  important: it means the transfer can't exceed the charge amount, and if the
  charge is refunded, Stripe can automatically reverse the transfer."
- "The restaurant will receive this as a payout to their IBAN on the next
  payout cycle."

**Transfer to Courier (EUR 4)**
- "EUR 4 to the courier. Same pattern."

**Platform remainder**
- "The platform retains EUR 2. That's our take rate -- 10% in this example.
  We never explicitly create a 'platform fee' object. The platform simply
  keeps whatever isn't transferred. This is a key advantage of SCT over
  Destination Charges: we have full flexibility on the split."

**Dashboard moment**: Switch to Balance tab. Show the platform balance.
Switch to Connect > Accounts, click into the restaurant account, show
the balance there. Go to Events -- show the `transfer.created` events.

### Closing -- Edge Cases (2 minutes)

Don't wait for them to ask. Proactively raise these:

1. **Partial refund**: "If the customer disputes the order and we refund
   EUR 10, we need to decide how to claw back from each connected account.
   We can create transfer reversals proportionally -- EUR 7 from restaurant,
   EUR 2 from courier, EUR 1 from platform. Or we can absorb it on the
   platform side. SCT gives us that flexibility."

2. **Insufficient balance on connected account**: "If the restaurant has
   already been paid out and we try to reverse the transfer, the connected
   account goes negative. We're liable for that as the platform -- that's
   the tradeoff of Custom accounts. In production, we'd configure a payout
   delay to keep a buffer."

3. **KYC delays**: "If verification is pending, `charges_enabled` stays
   false. We can still create the account and collect the payment on the
   platform, but we can't transfer until the account is verified. The
   `account.updated` webhook tells us when status changes."

4. **Currency**: "Both accounts are in DE/EUR, so no conversion needed.
   Cross-border transfers within EEA/CH/UK/US are supported. Outside that,
   platform and connected account must be in the same region."

5. **Idempotency**: "Every API call in the script uses an idempotency key
   based on a timestamp. If the network drops mid-call, we can safely retry
   without creating duplicate charges or transfers."

---

## If something goes wrong

- **Script fails mid-run**: The response JSON files are written after each
  successful call. You can inspect them in `0-Onboarding/response/`,
  `1-Collect-Payment/response/`, `2-Route-Funds/response/`. Fix the issue
  and re-run -- idempotency keys use timestamps so a new run won't collide.

- **Account already exists**: If you need to re-run on the same sandbox,
  use `cleanup.py` first (it deletes connected accounts and wipes response
  files). But for the interview, the plan is: fresh sandbox, one clean run.

- **Wrong env var**: If you see "Set STRIPE_MAGENTA_KEY in your environment",
  run `source ~/.bashrc` and try again.

---

## Command to run

```bash
cd /path/to/demo
source ~/.bashrc
python3 python/phases-1-to-3.py --interactive
```

Each `[Enter to continue]` prompt is your cue to narrate, switch to the
dashboard, or draw on the whiteboard. Take your time. The script waits.
