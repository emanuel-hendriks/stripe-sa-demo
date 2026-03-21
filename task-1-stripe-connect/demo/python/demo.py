#!/usr/bin/env python3
"""
Stripe Connect Demo -- Objectives 2 & 3 (Live Presentation)
============================================================
  Objective 2: Collect payment from customer (PaymentIntent, EUR 20.00)
  Objective 3: Route funds via Separate Charges & Transfers

Prereq: run onboard.py first so connected accounts exist.

Usage:
  python3 demo.py                # run straight through
  python3 demo.py --interactive  # pause between steps for narration
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

def wait(args):
    if args.interactive:
        input("\n  [Enter to continue]\n")

# ---------------------------------------------------------------------------
# Objective 2 -- Collect Payment
# ---------------------------------------------------------------------------
def collect_payment(args):
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

    wait(args)

    print("  >> Confirm with pm_card_bypassPending (funds immediately available)")
    pi = stripe.PaymentIntent.confirm(pi.id, payment_method="pm_card_bypassPending")
    save("pi_confirm", pi)
    pp(pi, ["id", "status", "latest_charge"])

# ---------------------------------------------------------------------------
# Objective 3 -- Route Funds
# ---------------------------------------------------------------------------
def route_funds(args):
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

    wait(args)

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
    parser = argparse.ArgumentParser(description="Stripe Connect demo -- Objectives 2 & 3")
    parser.add_argument("--interactive", action="store_true", help="Pause between steps")
    args = parser.parse_args()

    from log_util import start_log
    start_log("demo")

    collect_payment(args)
    wait(args)
    route_funds(args)

    banner("DONE")
