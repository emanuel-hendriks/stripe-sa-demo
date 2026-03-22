#!/bin/bash
# Remove all response JSON files from runs/ directories
DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO="$DIR/.."

for folder in 0-Onboarding 1-Collect-Payment 2-Route-Funds; do
  rm -f "$DEMO/$folder/response/"*.json
done

echo "All response files cleaned."
