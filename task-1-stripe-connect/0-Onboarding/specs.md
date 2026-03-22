# Onboarding Spec: Company vs Individual Connected Accounts

Source: Stripe API Reference — `POST /v1/accounts` and `POST /v1/accounts/{id}/persons`

---

## Key Difference

A **courier** (`business_type=individual`) can be fully onboarded in a single `POST /v1/accounts` update call. All identity fields live under the `individual[...]` hash on the Account object itself.

A **restaurant** (`business_type=company`) requires a minimum of **two API calls**: one to update the Account (company details, external account, ToS acceptance), and a separate call to `POST /v1/accounts/{id}/persons` to create the representative/owner/director. The Persons API is a separate endpoint — person data cannot be inlined in the account create or update call.

---

## Courier (individual) — Single Update Call

After creating the account (`POST /v1/accounts` with `business_type=individual`), one `POST /v1/accounts/{id}` call provides everything Stripe needs:

```
POST /v1/accounts/{id}

individual[first_name]       # identity
individual[last_name]
individual[dob][day]
individual[dob][month]
individual[dob][year]
individual[email]
individual[phone]
individual[address][line1]   # address (use "address_full_match" in test mode)
individual[address][city]
individual[address][postal_code]

external_account[object]     # bank account for payouts
external_account[country]
external_account[currency]
external_account[account_number]

tos_acceptance[date]         # legal acceptance
tos_acceptance[ip]
```

Result: `charges_enabled=true`, `payouts_enabled=true` immediately in test mode.

---

## Restaurant (company) — Two API Calls Required

### Call 1: Update Account — company details + bank + ToS

```
POST /v1/accounts/{id}

company[name]                # company identity
company[tax_id]
company[phone]
company[address][line1]
company[address][city]
company[address][postal_code]

company[directors_provided]  # attestations (tells Stripe: "I've provided all required persons")
company[executives_provided]
company[owners_provided]

external_account[object]     # bank account for payouts
external_account[country]
external_account[currency]
external_account[account_number]

tos_acceptance[date]         # legal acceptance
tos_acceptance[ip]
```

### Call 2: Create Person — representative/owner/director

```
POST /v1/accounts/{id}/persons

first_name                   # person identity
last_name
email
phone
dob[day]
dob[month]
dob[year]
address[line1]
address[city]
address[postal_code]

relationship[representative] # roles this person fills
relationship[executive]
relationship[director]
relationship[owner]
relationship[percent_ownership]
relationship[title]
```

The `relationship` hash is critical — it tells Stripe which KYC roles this person satisfies. For a small restaurant, one person (the owner) typically fills all four roles: representative, executive, director, owner.

Result: `charges_enabled=true`, `payouts_enabled=true` after both calls complete in test mode.

---

## Why the Difference Matters (Interview Talking Point)

For an individual, the person IS the account — there's a 1:1 mapping, so Stripe puts the identity fields directly on the Account object under `individual[...]`.

For a company, the legal entity and the natural persons behind it are separate concepts. A GmbH can have multiple owners, directors, and executives. Stripe models this correctly: the Account holds company-level data, and the Persons API holds the natural persons. This is also why `company[owners_provided]=true` exists — it's an attestation that the platform has submitted all required persons, not just one.

This maps cleanly to KYC/AML requirements: regulators need to know the Ultimate Beneficial Owners (UBOs) of a company, which are separate from the company itself. Stripe's data model reflects this regulatory reality.

---

## Demo Script Mapping

| Script | API Calls | What It Does |
|--------|-----------|--------------|
| `01-create-restaurant.sh` | 1 (create) | Creates Custom account with `business_type=company`, MCC 5812 |
| `02-create-courier.sh` | 1 (create) | Creates Custom account with `business_type=individual`, MCC 4215 |
| `03-restaurant-fulfill-kyc.sh` | 3 (update + create person + retrieve) | Updates company details, creates person, verifies final state |
| `04-courier-fulfill-kyc.sh` | 1 (update) | Updates individual details + bank + ToS in single call |

Total API calls to fully onboard:
- Courier: 2 (create + update)
- Restaurant: 4 (create + update + create person + verify)

---

## Test Mode Shortcuts

- `address[line1]="address_full_match"` — bypasses address verification
- `dob[year]=1901` — triggers automatic identity verification pass
- `account_number="DE89370400440532013000"` — standard IBAN test value
- `phone="0000000000"` — bypasses phone verification
