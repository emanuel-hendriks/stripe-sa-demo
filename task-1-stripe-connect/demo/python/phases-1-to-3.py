#!/usr/bin/env python3
"""
Stripe Connect Demo -- Phases 1-3 (Clean Sandbox)
==================================================
  Phase 1: Onboard Restaurant (company/DE) + Courier (individual/DE) with KYC
  Phase 2: Collect payment from customer (PaymentIntent EUR 20.00)
  Phase 3: Route funds via Separate Charges & Transfers

Usage:
  python3 phases-1-to-3.py                # run straight through
  python3 phases-1-to-3.py --interactive  # pause between phases for narration
"""
import stripe, time, os, sys, argparse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from demo_utils import save, load, pp, banner, wait
from log_util import start_log

def iwait(args):
    if args.interactive:
        wait()

# -- Phase 1: Onboard ---------------------------------------------------
def onboard(args):
    banner("PHASE 1: Onboard Connected Accounts (Custom, DE)")

    print("\n  >> Create Restaurant account (company/DE)")
    restaurant = stripe.Account.create(
        type="custom", country="DE",
        capabilities={"card_payments": {"requested": True}, "transfers": {"requested": True}},
        business_type="company",
        business_profile={"mcc": "5812", "name": "Restaurant", "url": "https://restaurant-website.com"},
    )
    save("restaurant", restaurant)
    pp(restaurant, ["id", "type", "country", "business_type"])

    iwait(args)

    print("  >> Fulfill Restaurant KYC (company details, representative, bank account, ToS)")
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
    save("restaurant_kyc", r)
    pp(r, ["id", "charges_enabled", "payouts_enabled"])

    iwait(args)

    print("\n  >> Create Courier account (individual/DE)")
    courier = stripe.Account.create(
        type="custom", country="DE",
        capabilities={"card_payments": {"requested": True}, "transfers": {"requested": True}},
        business_type="individual",
        business_profile={"mcc": "4215", "name": "Courier", "url": "https://courier-company-website.com"},
    )
    save("courier", courier)
    pp(courier, ["id", "type", "country", "business_type"])

    iwait(args)

    print("  >> Fulfill Courier KYC (individual details, bank account, ToS)")
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
    save("courier_kyc", c)
    pp(c, ["id", "charges_enabled", "payouts_enabled"])

    print("\n  Both accounts onboarded. charges_enabled = true.")

# -- Phase 2: Collect Payment -------------------------------------------
def collect_payment(args):
    banner("PHASE 2: Collect Payment -- PaymentIntent EUR 20.00")
    ts = time.strftime("%Y%m%d-%H%M%S")
    restaurant_id = load("restaurant")["id"]
    courier_id = load("courier")["id"]

    print(f"\n  Restaurant: {restaurant_id}")
    print(f"  Courier:    {courier_id}")

    print("\n  >> Create PaymentIntent with transfer_group (SCT pattern)")
    pi = stripe.PaymentIntent.create(
        amount=2000, currency="eur",
        payment_method_types=["card"],
        transfer_group="order_001",
        metadata={"order_id": "order_001", "restaurant": restaurant_id, "courier": courier_id},
        idempotency_key=f"payment-order-{ts}",
    )
    save("pi_create", pi)
    pp(pi, ["id", "amount", "currency", "status", "transfer_group"])

    iwait(args)

    print("  >> Confirm with pm_card_bypassPending (funds immediately available)")
    pi = stripe.PaymentIntent.confirm(pi.id, payment_method="pm_card_bypassPending")
    save("pi_confirm", pi)
    pp(pi, ["id", "status", "latest_charge"])

# -- Phase 3: Route Funds -----------------------------------------------
def route_funds(args):
    banner("PHASE 3: Route Funds -- Separate Charges & Transfers")
    restaurant_id = load("restaurant")["id"]
    courier_id = load("courier")["id"]
    charge_id = load("pi_confirm")["latest_charge"]
    ts = time.strftime("%Y%m%d-%H%M%S")

    print(f"\n  Charge:   {charge_id}")
    print(f"  Split:    EUR 14 restaurant + EUR 4 courier + EUR 2 platform\n")

    print("  >> Transfer EUR 14.00 -> Restaurant")
    xfer_r = stripe.Transfer.create(
        amount=1400, currency="eur", destination=restaurant_id,
        source_transaction=charge_id, transfer_group="order_001",
        metadata={"recipient": "restaurant", "order_id": "order_001"},
        idempotency_key=f"transfer-restaurant-{ts}",
    )
    save("xfer_restaurant", xfer_r)
    pp(xfer_r, ["id", "amount", "currency", "destination"])

    iwait(args)

    print("  >> Transfer EUR 4.00 -> Courier")
    xfer_c = stripe.Transfer.create(
        amount=400, currency="eur", destination=courier_id,
        source_transaction=charge_id, transfer_group="order_001",
        metadata={"recipient": "courier", "order_id": "order_001"},
        idempotency_key=f"transfer-courier-{ts}",
    )
    save("xfer_courier", xfer_c)
    pp(xfer_c, ["id", "amount", "currency", "destination"])

    print(f"\n  Platform retains: EUR 2.00 (2000 - 1400 - 400 = 200 cents)")

# -----------------------------------------------------------------------
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Stripe Connect demo -- Phases 1-3")
    parser.add_argument("--interactive", action="store_true", help="Pause between phases")
    args = parser.parse_args()

    start_log("phases-1-to-3")

    onboard(args)
    iwait(args)
    collect_payment(args)
    iwait(args)
    route_funds(args)

    banner("DONE")
