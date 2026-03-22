#!/usr/bin/env python3
"""
Onboard Restaurant + Courier connected accounts (DE) and fulfill KYC.
Run once before the demo. Not part of the live presentation.
"""
import stripe, json, os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEMO_DIR = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, DEMO_DIR)

stripe.api_key = os.environ.get("STRIPE_MAGENTA_KEY", "")
if not stripe.api_key:
    sys.exit("Set STRIPE_MAGENTA_KEY in your environment.")

from log_util import start_log
start_log("onboard")

RESP_DIR = f"{SCRIPT_DIR}/response"
os.makedirs(RESP_DIR, exist_ok=True)

def save(name, obj):
    with open(f"{RESP_DIR}/{name}", "w") as f:
        json.dump(obj, f, indent=2)

def pp(obj, fields):
    print(json.dumps({k: obj[k] for k in fields if k in obj}, indent=2))

# --- Restaurant (company, MCC 5812) ---
print("Creating Restaurant account (company/DE)...")
restaurant = stripe.Account.create(
    type="custom", country="DE",
    capabilities={"card_payments": {"requested": True}, "transfers": {"requested": True}},
    business_type="company",
    business_profile={"mcc": "5812", "name": "Restaurant", "url": "https://restaurant-website.com"},
)
save("01-create-restaurant-response.json", restaurant)

print("Fulfilling Restaurant KYC...")
stripe.Account.modify(restaurant.id,
    company={
        "name": "Restaurant GmbH", "tax_id": "HRB 1234", "phone": "0000000000",
        "address": {"line1": "address_full_match", "city": "Berlin", "postal_code": "10115"},
        "directors_provided": True, "executives_provided": True, "owners_provided": True,
    },
    external_account={
        "object": "bank_account", "country": "DE", "currency": "eur",
        "account_number": "DE89370400440532013000",
    },
    tos_acceptance={"date": int(time.time()), "ip": "127.0.0.1"},
)
stripe.Account.create_person(restaurant.id,
    first_name="Jenny", last_name="Rosen", email="jenny@restaurant-website.com",
    phone="0000000000", dob={"day": 1, "month": 1, "year": 1901},
    address={"line1": "address_full_match", "city": "Berlin", "postal_code": "10115"},
    relationship={"representative": True, "executive": True, "director": True,
                   "owner": True, "percent_ownership": 100, "title": "CEO"},
)
r = stripe.Account.retrieve(restaurant.id)
save("03-restaurant-kyc-response.json", r)
pp(r, ["id", "charges_enabled", "payouts_enabled"])

# --- Courier (individual, MCC 4215) ---
print("\nCreating Courier account (individual/DE)...")
courier = stripe.Account.create(
    type="custom", country="DE",
    capabilities={"card_payments": {"requested": True}, "transfers": {"requested": True}},
    business_type="individual",
    business_profile={"mcc": "4215", "name": "Courier", "url": "https://courier-company-website.com"},
)
save("02-create-courier-response.json", courier)

print("Fulfilling Courier KYC...")
c = stripe.Account.modify(courier.id,
    individual={
        "first_name": "Max", "last_name": "Mustermann",
        "dob": {"day": 1, "month": 1, "year": 1901},
        "email": "max@courier-company-website.com", "phone": "0000000000",
        "address": {"line1": "address_full_match", "city": "Berlin", "postal_code": "10115"},
    },
    external_account={
        "object": "bank_account", "country": "DE", "currency": "eur",
        "account_number": "DE89370400440532013000",
    },
    tos_acceptance={"date": int(time.time()), "ip": "127.0.0.1"},
)
save("04-courier-kyc-response.json", c)
pp(c, ["id", "charges_enabled", "payouts_enabled"])

print("\nOnboarding complete. Both accounts ready for demo.")
