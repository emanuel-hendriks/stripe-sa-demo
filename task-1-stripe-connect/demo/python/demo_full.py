#!/usr/bin/env python3
"""
Stripe Connect Demo -- Full End-to-End Flow
============================================
Runs all steps: cleanup, onboarding, KYC, payment, transfers.

Usage:
  python3 demo_full.py              # run all steps
  python3 demo_full.py --step 3     # start from step N (reads prior response files)
  python3 demo_full.py --interactive # pause between steps
"""
import stripe, json, os, sys, time, argparse

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEMO_DIR = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, DEMO_DIR)
stripe.api_key = os.environ.get("STRIPE_DEMO_KEY", "")
if not stripe.api_key:
    sys.exit("Set STRIPE_DEMO_KEY in your environment.")

RESP = {
    "restaurant":      f"{DEMO_DIR}/0-Onboarding/response/01-create-restaurant-response.json",
    "courier":         f"{DEMO_DIR}/0-Onboarding/response/02-create-courier-response.json",
    "restaurant_kyc":  f"{DEMO_DIR}/0-Onboarding/response/03-restaurant-kyc-response.json",
    "courier_kyc":     f"{DEMO_DIR}/0-Onboarding/response/04-courier-kyc-response.json",
    "pi_create":       f"{DEMO_DIR}/1-Collect-Payment/response/01-create-payment-intent-response.json",
    "pi_confirm":      f"{DEMO_DIR}/1-Collect-Payment/response/02-confirm-payment-intent-response.json",
    "xfer_restaurant": f"{DEMO_DIR}/2-Route-Funds/response/01-transfer-restaurant-response.json",
    "xfer_courier":    f"{DEMO_DIR}/2-Route-Funds/response/02-transfer-courier-response.json",
}

def save(key, obj):
    os.makedirs(os.path.dirname(RESP[key]), exist_ok=True)
    with open(RESP[key], "w") as f:
        json.dump(obj, f, indent=2)

def load(key):
    with open(RESP[key]) as f:
        return json.load(f)

def pp(obj, fields):
    print(json.dumps({k: obj[k] for k in fields if k in obj}, indent=2))

def banner(title):
    print(f"\n{'='*60}\n  {title}\n{'='*60}")

def pause(interactive):
    if interactive:
        input("\n  [Press Enter to continue]\n")

# -- Step 0: Cleanup -------------------------------------------------------
def step_0_cleanup():
    banner("STEP 0: Cleanup -- delete connected accounts & response files")
    accounts = stripe.Account.list(limit=100).data
    if not accounts:
        print("  No connected accounts to delete.")
    for acct in accounts:
        stripe.Account.delete(acct.id)
        print(f"  Deleted {acct.id}")
    for path in RESP.values():
        if os.path.exists(path):
            os.remove(path)
    print("  Response files cleaned.")

# -- Step 1: Onboarding ----------------------------------------------------
def step_1_onboard():
    banner("STEP 1: Onboarding -- create Custom connected accounts (DE)")

    print("\n  1a. Restaurant (company, MCC 5812 -- Eating Places)")
    restaurant = stripe.Account.create(
        type="custom", country="DE",
        capabilities={"card_payments": {"requested": True}, "transfers": {"requested": True}},
        business_type="company",
        business_profile={"mcc": "5812", "name": "Restaurant", "url": "https://restaurant-website.com"},
    )
    save("restaurant", restaurant)
    pp(restaurant, ["id", "type", "country", "business_type", "capabilities"])

    print("\n  1b. Courier (individual, MCC 4215 -- Courier Services)")
    courier = stripe.Account.create(
        type="custom", country="DE",
        capabilities={"card_payments": {"requested": True}, "transfers": {"requested": True}},
        business_type="individual",
        business_profile={"mcc": "4215", "name": "Courier", "url": "https://courier-company-website.com"},
    )
    save("courier", courier)
    pp(courier, ["id", "type", "country", "business_type", "capabilities"])

# -- Step 2: KYC ------------------------------------------------------------
def step_2_kyc():
    banner("STEP 2: KYC -- fulfill verification with test data")
    restaurant_id = load("restaurant")["id"]
    courier_id = load("courier")["id"]

    print(f"\n  2a. Restaurant KYC ({restaurant_id})")
    stripe.Account.modify(restaurant_id,
        company={
            "name": "Restaurant GmbH", "tax_id": "HRB 1234", "phone": "0000000000",
            "address": {"line1": "address_full_match", "city": "Berlin", "postal_code": "10115"},
            "directors_provided": True, "executives_provided": True, "owners_provided": True,
        },
        external_account={"object": "bank_account", "country": "DE", "currency": "eur", "account_number": "DE89370400440532013000"},
        tos_acceptance={"date": int(time.time()), "ip": "127.0.0.1"},
    )
    stripe.Account.create_person(restaurant_id,
        first_name="Jenny", last_name="Rosen", email="jenny@restaurant-website.com",
        phone="0000000000", dob={"day": 1, "month": 1, "year": 1901},
        address={"line1": "address_full_match", "city": "Berlin", "postal_code": "10115"},
        relationship={"representative": True, "executive": True, "director": True,
                       "owner": True, "percent_ownership": 100, "title": "CEO"},
    )
    acct = stripe.Account.retrieve(restaurant_id)
    save("restaurant_kyc", acct)
    pp(acct, ["id", "charges_enabled", "payouts_enabled", "capabilities"])

    print(f"\n  2b. Courier KYC ({courier_id})")
    acct = stripe.Account.modify(courier_id,
        individual={
            "first_name": "Max", "last_name": "Mustermann",
            "dob": {"day": 1, "month": 1, "year": 1901},
            "email": "max@courier-company-website.com", "phone": "0000000000",
            "address": {"line1": "address_full_match", "city": "Berlin", "postal_code": "10115"},
        },
        external_account={"object": "bank_account", "country": "DE", "currency": "eur", "account_number": "DE89370400440532013000"},
        tos_acceptance={"date": int(time.time()), "ip": "127.0.0.1"},
    )
    save("courier_kyc", acct)
    pp(acct, ["id", "charges_enabled", "payouts_enabled", "capabilities"])

# -- Step 3: Collect Payment ------------------------------------------------
def step_3_payment():
    banner("STEP 3: Collect Payment -- PaymentIntent EUR 20.00 (SCT pattern)")
    restaurant_id, courier_id = load("restaurant")["id"], load("courier")["id"]
    ts = time.strftime("%Y%m%d-%H%M%S")

    print("\n  3a. Create PaymentIntent with transfer_group")
    pi = stripe.PaymentIntent.create(
        amount=2000, currency="eur", payment_method_types=["card"],
        transfer_group="order_001",
        metadata={"order_id": "order_001", "restaurant": restaurant_id, "courier": courier_id},
        idempotency_key=f"payment-order-{ts}",
    )
    save("pi_create", pi)
    pp(pi, ["id", "amount", "currency", "status", "transfer_group"])

    print("\n  3b. Confirm with pm_card_bypassPending (funds immediately available)")
    pi = stripe.PaymentIntent.confirm(pi.id, payment_method="pm_card_bypassPending")
    save("pi_confirm", pi)
    pp(pi, ["id", "status", "latest_charge"])

# -- Step 4: Route Funds ----------------------------------------------------
def step_4_transfers():
    banner("STEP 4: Route Funds -- Separate Charges & Transfers")
    restaurant_id, courier_id = load("restaurant")["id"], load("courier")["id"]
    charge_id = load("pi_confirm")["latest_charge"]
    ts = time.strftime("%Y%m%d-%H%M%S")

    print(f"\n  Charge: {charge_id}")
    print(f"  Split: EUR 14 restaurant + EUR 4 courier + EUR 2 platform fee\n")

    print("  4a. Transfer EUR 14.00 -> Restaurant")
    xfer_r = stripe.Transfer.create(
        amount=1400, currency="eur", destination=restaurant_id,
        source_transaction=charge_id, transfer_group="order_001",
        metadata={"recipient": "restaurant", "order_id": "order_001"},
        idempotency_key=f"transfer-restaurant-{ts}",
    )
    save("xfer_restaurant", xfer_r)
    pp(xfer_r, ["id", "amount", "currency", "destination", "source_transaction"])

    print("\n  4b. Transfer EUR 4.00 -> Courier")
    xfer_c = stripe.Transfer.create(
        amount=400, currency="eur", destination=courier_id,
        source_transaction=charge_id, transfer_group="order_001",
        metadata={"recipient": "courier", "order_id": "order_001"},
        idempotency_key=f"transfer-courier-{ts}",
    )
    save("xfer_courier", xfer_c)
    pp(xfer_c, ["id", "amount", "currency", "destination", "source_transaction"])

    print(f"\n  Platform retains: EUR 2.00 (2000 - 1400 - 400 = 200 cents)")

# -- Main -------------------------------------------------------------------
STEPS = [
    (0, step_0_cleanup),
    (1, step_1_onboard),
    (2, step_2_kyc),
    (3, step_3_payment),
    (4, step_4_transfers),
]

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Stripe Connect delivery demo (full)")
    parser.add_argument("--step", type=int, default=0, help="Start from step N (0-4)")
    parser.add_argument("--interactive", action="store_true", help="Pause between steps")
    args = parser.parse_args()

    from log_util import start_log
    start_log("demo_full")

    for num, fn in STEPS:
        if num < args.step:
            continue
        fn()
        pause(args.interactive)

    banner("DONE")
    print("  All response files written. Run test scripts to verify.")
