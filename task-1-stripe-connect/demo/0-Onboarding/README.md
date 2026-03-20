# Objective 1: Onboarding -- Connected Account Creation & KYC

## Accounts

| Party | Account ID | Type | Business Type | MCC | Country | Status |
|-------|-----------|------|---------------|-----|---------|--------|
| Restaurant | `acct_1TCpvJA8zh16dkqQ` | custom | company | 5812 | DE | charges_enabled: true, transfers: active |
| Courier | `acct_1TCpviAfWDIIjKRu` | custom | individual | 4215 | DE | charges_enabled: true, transfers: active |

Platform: `acct_1TBwODATzSZT5qY7` ("Emanuel sandbox")

---

## Scripts

| # | Script | Output | Purpose |
|---|--------|--------|---------|
| 0 | `00-delete-existing-accounts.sh` | -- | Clean slate |
| 1a | `01-create-restaurant.sh` | `01-create-restaurant-response.json` | Create company account, MCC 5812 |
| 1b | `02-create-courier.sh` | `02-create-courier-response.json` | Create individual account, MCC 4215 |
| 2a | `03-restaurant-fulfill-kyc.sh` | `03-restaurant-kyc-response.json` | Fulfill 44 company KYC fields |
| 2b | `04-courier-fulfill-kyc.sh` | `04-courier-kyc-response.json` | Fulfill 8 individual KYC fields |

---

## Test tokens used

| Field | Token | Effect |
|-------|-------|--------|
| DOB | `1901-01-01` | Successful date of birth match |
| Address line1 | `address_full_match` | Successful address match, enables charges + payouts |
| Phone | `0000000000` | Successful phone validation |
| Tax ID (DE company) | `HRB 1234` | Valid Handelsregisternummer format |
| Bank account | `DE89370400440532013000` | Successful payout IBAN |
| ToS | `date=$(date +%s)`, `ip=127.0.0.1` | Platform records acceptance on behalf of connected account |

---

## Key difference: company vs individual KYC

**Restaurant (company)** -- 44 fields in `requirements.currently_due`:
- Company: name, tax_id (Handelsregisternummer), phone, address
- Directors: name, DOB, email, title
- Executives: name, DOB, email, address
- Owners (25%+): name, DOB, email, address
- Representative: name, DOB, email, phone, address, title
- External account (IBAN) + ToS acceptance

**Courier (individual)** -- 8 fields:
- Name, DOB, email, phone, address, external account, ToS acceptance
