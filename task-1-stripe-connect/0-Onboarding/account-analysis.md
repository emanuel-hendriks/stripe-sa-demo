# Connected Account Analysis

Analysis of the two Custom connected accounts created for the Stripe Connect demo.

---

## Restaurant (acct_1TCrCTPIpZeThsJD)

### Identity
- **type:** `custom`
- **business_type:** `company`
- **country:** DE
- **default_currency:** EUR
- **business_profile.mcc:** `5812` (Eating Places, Restaurants)
- **business_profile.name:** "Restaurant"

### Company Details
- **company.name:** "Restaurant GmbH"
- **company.address:** Berlin, 10115, `address_full_match` (Stripe test token for address verification)
- **company.tax_id_provided:** true (HRB 1234)
- **company.directors_provided / executives_provided / owners_provided:** all true
- A Person object was created as representative + executive + director + owner (100% ownership): Jenny Rosen

### Controller (defines platform-account relationship)
The `controller` block defines who does what between the platform and the connected account: who pays fees, who bears losses, who collects KYC, and whether the connected account gets a Stripe Dashboard. It's the granular version of saying "Custom account." Stripe auto-sets it when you pass `type=custom`.

- **controller.type:** `application` -- the platform controls this account
- **controller.fees.payer:** `application_custom` -- platform pays Stripe fees
- **controller.losses.payments:** `application` -- platform bears loss liability
- **controller.requirement_collection:** `application` -- platform is responsible for collecting KYC
- **controller.stripe_dashboard.type:** `none` -- no Dashboard access for the connected account

### Capabilities
Requested `card_payments` and `transfers`. Stripe auto-enabled additional capabilities for DE:
- `card_payments`: active
- `transfers`: active
- `bancontact_payments`: active
- `blik_payments`: active
- `eps_payments`: active
- `ideal_payments`: active
- `klarna_payments`: active
- `link_payments`: active

### Verification Status
- **charges_enabled:** true
- **payouts_enabled:** true
- **details_submitted:** true
- **requirements.currently_due:** [] (empty -- fully verified)
- **requirements.eventually_due:** [] (empty)
- **requirements.past_due:** [] (empty)

### External Account (Payout Destination)
- **type:** bank_account
- **country:** DE
- **currency:** EUR
- **last4:** 3000 (test IBAN DE89370400440532013000)
- **available_payout_methods:** standard, instant
- **status:** new

### Payout Schedule
- **interval:** daily
- **delay_days:** 7
- **debit_negative_balances:** false

### ToS Acceptance
- **date:** 1773967624 (Unix timestamp)
- **ip:** 127.0.0.1
- For Custom accounts, the platform must record ToS acceptance (timestamp + IP). Stripe does not collect this via hosted onboarding for Custom.

### Statement Descriptor
- **payments.statement_descriptor:** "RESTAURANT"
- **card_payments.statement_descriptor_prefix:** "RESTAURANT"

---

## Courier (acct_1TCrCyAAxd0ePQfh)

### Identity
- **type:** `custom`
- **business_type:** `individual`
- **country:** DE
- **default_currency:** EUR
- **business_profile.mcc:** `4215` (Courier Services)
- **business_profile.name:** "Courier"

### Individual Details
- **individual.first_name:** "Max"
- **individual.last_name:** "Mustermann"
- **individual.dob:** 1901-01-01
- **individual.email:** max@courier-company-website.com
- **individual.address:** Berlin, 10115, `address_full_match`
- **individual.verification.status:** `verified`
- **individual.relationship.representative:** true (all other roles false -- individuals don't need director/owner/executive)

### Controller
Identical to restaurant:
- **controller.type:** `application`
- **controller.fees.payer:** `application_custom`
- **controller.losses.payments:** `application`
- **controller.requirement_collection:** `application`
- **controller.stripe_dashboard.type:** `none`

### Capabilities
Same as restaurant -- Stripe auto-enabled DE payment methods:
- `card_payments`, `transfers`, `bancontact_payments`, `blik_payments`, `eps_payments`, `ideal_payments`, `klarna_payments`, `link_payments`: all active

### Verification Status
- **charges_enabled:** true
- **payouts_enabled:** true
- **details_submitted:** true
- **requirements.currently_due:** [] (empty)
- **requirements.eventually_due:** [] (empty)

### External Account
Identical setup to restaurant:
- DE bank account, EUR, last4 3000, standard + instant payout methods

### Payout Schedule
- **interval:** daily
- **delay_days:** 7

### ToS Acceptance
- **date:** 1773967637
- **ip:** 127.0.0.1

### Statement Descriptor
- **payments.statement_descriptor:** "COURIER"

---

## Key Differences: Restaurant vs Courier

| Field | Restaurant | Courier |
|-------|-----------|---------|
| business_type | company | individual |
| MCC | 5812 (Restaurants) | 4215 (Courier Services) |
| KYC entity | company + Person (Jenny Rosen, 100% owner, CEO) | individual (Max Mustermann) |
| tax_id_provided | true | false (not required for individuals) |
| Person roles | representative + executive + director + owner | representative only |

## Key Observations

1. **controller block** confirms this is a platform-controlled Custom account: platform pays fees, bears losses, collects requirements, no Stripe Dashboard access for the connected account.

2. **Auto-enabled capabilities:** We only requested `card_payments` and `transfers`, but Stripe auto-enabled 6 additional payment methods for DE (bancontact, blik, eps, ideal, klarna, link). This is Stripe optimizing for the connected account's country.

3. **address_full_match** is a Stripe test token that simulates a successful address verification. In production, Stripe verifies the actual address.

4. **debit_negative_balances: false** means Stripe will not automatically debit the connected account's bank account to cover negative balances. The platform bears this risk (consistent with `controller.losses.payments: application`).

5. **delay_days: 7** is the default for DE. Funds from a charge become available for payout 7 days after the charge succeeds. This is separate from `source_transaction` behavior (which allows transfers before settlement).

---

## Destination Payment (py_1TDDVpAAxd0ePQfh5YLW81J9)

A `py_` object is a charge that Stripe automatically creates on the connected account's ledger when a transfer lands. It's the connected account's view of the incoming funds. You don't create it -- Stripe does, as a side effect of `POST /v1/transfers`.

- **amount:** 400 (EUR 4.00) -- matches the courier transfer
- **payment_method_details.type:** `stripe_account` -- internal Stripe ledger move, not a card payment
- **source.id:** `acct_1TCr2XARsNxRMQkd` -- the platform account (where the funds came from)
- **source_transfer:** `tr_3TDDVmARsNxRMQkd2L6rhqA1` -- the Transfer object that triggered this payment
- **application_fee_amount:** null -- SCT doesn't use application fees; the platform keeps what it doesn't transfer
- **payment_intent:** null -- the PaymentIntent lives on the platform, not on the connected account

This is the link between the platform's Transfer and the connected account's balance. The Transfer object has a `destination_payment` field pointing to this `py_` object, and this `py_` object has a `source_transfer` field pointing back to the Transfer.

## Destination Payment (py_1TDDVoPIpZeThsJDaQhsTQLs)

Restaurant's side of the transfer. Same structure as the courier's `py_` object.

- **amount:** 1400 (EUR 14.00) -- matches the restaurant transfer
- **payment_method_details.type:** `stripe_account` -- internal ledger move
- **source.id:** `acct_1TCr2XARsNxRMQkd` -- platform account
- **source_transfer:** `tr_3TDDVmARsNxRMQkd2DDm6dTx` -- the Transfer that created this
- **application_fee_amount:** null
- **payment_intent:** null

Both `py_` objects share the same `source.id` (the platform) and the same `application` (the Connect app). The only differences are `amount` and `source_transfer`, which point to their respective Transfer objects.
