#!/usr/bin/env python3
"""
Stripe Connect Demo -- Objectives 1, 2 & 3 (Live Presentation)
===============================================================
  Objective 1: Review onboarded accounts (read-only)
  Objective 2: Collect payment from customer (PaymentIntent, EUR 20.00)
  Objective 3: Route funds via Separate Charges & Transfers

Prereq: run onboard.py first so connected accounts exist.
"""
import stripe, time, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from demo_utils import save, load, pp, banner, wait
from log_util import start_log

# ---------------------------------------------------------------------------
# Objective 1 -- Onboard (review pre-created accounts)
# ---------------------------------------------------------------------------
def review_onboarding():
    banner("OBJECTIVE 1: Onboard -- Connected Accounts (pre-created)")

    restaurant_id = load("restaurant")["id"]
    courier_id = load("courier")["id"]

    print("\n  >> Retrieve Restaurant account")
    r = stripe.Account.retrieve(restaurant_id)
    pp(r, ["id", "type", "country", "business_type", "charges_enabled", "payouts_enabled"])

    wait()

    print("  >> Retrieve Courier account")
    c = stripe.Account.retrieve(courier_id)
    pp(c, ["id", "type", "country", "business_type", "charges_enabled", "payouts_enabled"])

# ---------------------------------------------------------------------------
# Objective 2 -- Collect Payment
# ---------------------------------------------------------------------------
def collect_payment():
    banner("OBJECTIVE 2: Collect Payment -- PaymentIntent EUR 20.00")

    restaurant_id = load("restaurant")["id"]
    courier_id = load("courier")["id"]
    ts = time.strftime("%Y%m%d-%H%M%S")

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

    wait()

    print("  >> Confirm with pm_card_bypassPending (funds immediately available)")
    pi = stripe.PaymentIntent.confirm(pi.id, payment_method="pm_card_bypassPending")
    save("pi_confirm", pi)
    pp(pi, ["id", "status", "latest_charge"])

# ---------------------------------------------------------------------------
# Objective 3 -- Route Funds
# ---------------------------------------------------------------------------
def route_funds():
    banner("OBJECTIVE 3: Route Funds -- Separate Charges & Transfers")

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

    wait()

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

# ---------------------------------------------------------------------------
if __name__ == "__main__":
    start_log("demo")
    review_onboarding()
    wait()
    collect_payment()
    wait()
    route_funds()
    banner("DONE")
