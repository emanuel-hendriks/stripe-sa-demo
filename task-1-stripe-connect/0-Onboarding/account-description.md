# Connected Account Description -- Interview Reference

## Why Custom Accounts?

The interview brief specifies Custom account type. Here is what that means in Stripe's
controller model, and why it is the right choice for a delivery platform.

A Custom connected account sets four controller properties:

| Property                   | Value              | Meaning                                                    |
|----------------------------|--------------------|------------------------------------------------------------|
| `controller.losses.payments`       | `application`      | The platform absorbs negative balances, not Stripe         |
| `controller.fees.payer`            | `application_custom` | The platform pays Stripe processing fees                 |
| `controller.requirement_collection`| `application`      | The platform collects KYC info (not Stripe-hosted onboarding) |
| `controller.stripe_dashboard.type` | `none`             | Connected accounts have no Stripe Dashboard access         |

This is the maximum-control configuration. The platform owns the entire user experience:
onboarding UI, KYC collection, dashboard, and dispute handling. It also owns the risk --
negative balances on connected accounts are the platform's problem.

For a delivery platform this makes sense: restaurants and couriers never interact with
Stripe directly. They sign up through the platform's app, the platform collects their
identity documents and bank details, and the platform decides when and how much to pay them.

### Contrast with Express and Standard

- Express: Stripe hosts a lightweight dashboard and collects KYC. The platform still owns
  losses. Good for marketplaces that want less onboarding engineering (e.g., a ride-sharing
  app that wants Stripe to handle identity verification).

- Standard: The connected account has a full Stripe Dashboard, pays its own fees, and Stripe
  owns negative balance liability. Good for SaaS platforms where each merchant is an
  independent business (e.g., Shopify stores).

Custom is the only type where `requirement_collection = application`, meaning the platform
must build its own onboarding flow and call the Accounts API + Persons API directly.

---

## The Two Accounts in This Demo

### Restaurant -- `acct_1TE5qfAOC8AWqtZK`

| Field               | Value                          | Why                                                        |
|---------------------|--------------------------------|------------------------------------------------------------|
| `type`              | `custom`                       | Platform controls everything                               |
| `country`           | `DE`                           | DACH market, EUR currency, German KYC rules apply          |
| `business_type`     | `company`                      | A restaurant is a legal entity (GmbH, UG, etc.)            |
| `business_profile.mcc` | `5812`                      | "Eating Places, Restaurants" -- determines interchange fees and payment method eligibility |
| `capabilities`      | `card_payments`, `transfers`   | Can receive card charges and accept transfers from platform |

After KYC: `charges_enabled: true`, `payouts_enabled: true`, `requirements.currently_due: []`.

### Courier -- `acct_1TE5qpApztIe7e2w`

| Field               | Value                          | Why                                                        |
|---------------------|--------------------------------|------------------------------------------------------------|
| `type`              | `custom`                       | Platform controls everything                               |
| `country`           | `DE`                           | Same DACH market                                           |
| `business_type`     | `individual`                   | A courier is a natural person (freelancer/gig worker)      |
| `business_profile.mcc` | `4215`                      | "Courier Services" -- correct classification for delivery  |
| `capabilities`      | `card_payments`, `transfers`   | Can receive transfers from platform                        |

After KYC: `charges_enabled: true`, `payouts_enabled: true`, `requirements.currently_due: []`.

---

## KYC: Company vs Individual

This is the key architectural difference to explain in the interview.

### Individual (Courier): the person IS the account

An individual account has a 1:1 mapping between the legal entity and the natural person.
All identity fields live under `individual[...]` on the Account object itself. One API call
to `POST /v1/accounts/{id}` provides everything:

```
individual[first_name], individual[last_name]
individual[dob][day/month/year]
individual[email], individual[phone]
individual[address][line1/city/postal_code]
external_account (IBAN)
tos_acceptance[date/ip]
```

Total currently_due fields at creation: 13. Fulfilled in 1 update call.

### Company (Restaurant): the entity and its people are separate

A company account separates the legal entity from the natural persons behind it. This
reflects regulatory reality: KYC/AML rules (and the EU's 4th/5th Anti-Money Laundering
Directives) require identifying Ultimate Beneficial Owners (UBOs) separately from the
company itself.

Stripe models this with two separate API surfaces:
- `POST /v1/accounts/{id}` -- company-level data (name, tax_id, address, bank account, ToS)
- `POST /v1/accounts/{id}/persons` -- natural person data (representative, directors, executives, owners)

The `company[owners_provided]=true` flag is an attestation: the platform tells Stripe
"I have submitted all required persons." Without it, Stripe keeps the account in a
pending state waiting for more person data.

Total currently_due fields at creation: 47. Fulfilled in 2 API calls (account update + person create).

For a small restaurant, one person (the owner/CEO) typically fills all four roles:
`relationship[representative]=true`, `relationship[executive]=true`,
`relationship[director]=true`, `relationship[owner]=true`.

---

## MCC Selection Rationale

MCCs are not cosmetic. They affect:

1. Interchange fees -- card networks charge different rates per MCC
2. Payment method eligibility -- some payment methods (e.g., PayNow) exclude certain MCCs
3. Risk scoring -- Stripe and card networks use MCC for fraud detection
4. Regulatory classification -- determines which compliance rules apply

Stripe automatically evaluates MCCs but platforms can set them manually via
`business_profile.mcc` at account creation. If Stripe's review determines the MCC is
inaccurate, Stripe may override it and the platform cannot change it back.

| Party      | MCC    | Description                    |
|------------|--------|--------------------------------|
| Restaurant | `5812` | Eating Places, Restaurants     |
| Courier    | `4215` | Courier Services               |

---

## Capabilities Requested

Both accounts request `card_payments` and `transfers`:

- `card_payments` -- allows the account to be the destination of card charges. Required for
  any account that will receive funds from customer payments.
- `transfers` -- allows the platform to transfer funds to this connected account. This is
  the capability that enables the Separate Charges & Transfers (SCT) pattern used in
  Objective 3.

Capabilities start as `inactive` at creation and become `active` once all KYC requirements
are fulfilled. The `charges_enabled` and `payouts_enabled` booleans on the Account object
are the summary flags -- they reflect whether the account can actually process payments and
receive payouts.

---

## Test Mode Tokens Used

| Field              | Test Value                    | Effect                                      |
|--------------------|-------------------------------|---------------------------------------------|
| `address[line1]`   | `address_full_match`          | Bypasses address verification               |
| `dob[year]`        | `1901`                        | Triggers automatic identity verification pass |
| `phone`            | `0000000000`                  | Bypasses phone verification                 |
| `company[tax_id]`  | `HRB 1234`                    | Valid Handelsregisternummer format for DE    |
| `external_account` | `DE89370400440532013000`      | Standard IBAN test value                    |
| `tos_acceptance`   | `date=$(date +%s)`, `ip=127.0.0.1` | Platform records acceptance on behalf of connected account |

Source: https://docs.stripe.com/connect/testing-verification

---

## Interview Talking Points

1. "Why Custom and not Express?" -- Because the delivery platform owns the entire merchant
   and courier experience. Restaurants never log into Stripe. The platform collects their
   documents, builds the onboarding UI, and controls payout timing. Custom is the only
   account type where `requirement_collection = application`.

2. "Why does the company need a Persons API call but the individual doesn't?" -- Because
   EU AML regulations require identifying UBOs separately from the legal entity. Stripe's
   data model mirrors this: Account holds company data, Persons holds natural person data.
   An individual IS the account, so there is no separation needed.

3. "What happens if KYC fails?" -- The `requirements.currently_due` array repopulates with
   the failed fields, `charges_enabled` flips to false, and `requirements.disabled_reason`
   shows `requirements.past_due`. The platform must collect corrected information and
   resubmit. In production, you would listen for `account.updated` webhooks to detect this.

4. "How does this map to your AWS experience?" -- Connected account isolation is analogous
   to multi-tenant AWS account isolation. Each connected account is a security boundary with
   its own balance, capabilities, and KYC state -- similar to how each banking client at
   Prometeia gets an isolated AWS account with its own IAM policies and network boundaries.
   The platform account is the management account in an AWS Organization.
