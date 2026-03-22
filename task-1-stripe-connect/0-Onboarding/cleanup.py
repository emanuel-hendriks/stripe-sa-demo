#!/usr/bin/env python3
"""Delete all connected accounts and wipe response JSON files."""
import stripe, json, os, sys, glob

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEMO_DIR = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, DEMO_DIR)

stripe.api_key = os.environ.get("STRIPE_MAGENTA_KEY", "")
if not stripe.api_key:
    sys.exit("Set STRIPE_MAGENTA_KEY in your environment.")

from log_util import start_log
start_log("cleanup")

# Delete connected accounts
accounts = stripe.Account.list(limit=100).data
if not accounts:
    print("No connected accounts to delete.")
for acct in accounts:
    stripe.Account.delete(acct.id)
    print(f"Deleted {acct.id}")

# Wipe response files
removed = 0
for d in ["0-Onboarding", "1-Collect-Payment", "2-Route-Funds"]:
    for f in glob.glob(f"{DEMO_DIR}/{d}/response/*.json"):
        os.remove(f)
        removed += 1
print(f"Removed {removed} response files.")
