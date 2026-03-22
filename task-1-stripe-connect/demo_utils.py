"""Shared helpers for demo scripts."""
import stripe, json, os, sys

DEMO_DIR = os.path.dirname(os.path.abspath(__file__))

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

def wait():
    input("\n  [Enter to continue]\n")
