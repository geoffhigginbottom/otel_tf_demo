#!/usr/bin/env bash
# Update an existing Splunk Synthetics browser test (Heathrow parking staging flow).
#
# Usage:
#   export REALM="eu0"
#   export TOKEN="..."
#   export TEST_ID="37709"
#   export TEST_NAME="Heathrow Car Parking (Test Site) T2 7 Day"
#   export AUTH_USERNAME="storefront"
#   export AUTH_PASSWORD="hw_parking_staging_password"
#   ./scripts/heathrow/update-heathrow-parking-browser-test.sh
#
# Dry run (print JSON only):
#   DRY_RUN=1 ./scripts/heathrow/update-heathrow-parking-browser-test.sh
#
# See create-heathrow-parking-browser-test.sh for optional env vars (LOCATION_IDS,
# PARKING_URL, DEVICE_ID, etc.) and LIST_* commands to discover org resources.
# TEST_NAME, AUTH_USERNAME, and AUTH_PASSWORD are required.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${DRY_RUN:-0}" != "1" ]]; then
  REALM="${REALM:?Set REALM e.g. eu0}"
  TOKEN="${TOKEN:?Set TOKEN (X-SF-TOKEN)}"
  TEST_ID="${TEST_ID:?Set TEST_ID of the browser test to update}"
else
  TEST_ID="${TEST_ID:-37709}"
fi

REALM="${REALM:-eu0}"
TOKEN="${TOKEN:-}"

TEST_NAME="${TEST_NAME:?Set TEST_NAME (e.g. \"Heathrow Car Parking (Test Site) T2 7 Day\")}"
AUTH_USERNAME="${AUTH_USERNAME:?Set AUTH_USERNAME (HTTP basic auth username for the target site)}"
AUTH_PASSWORD="${AUTH_PASSWORD:?Set AUTH_PASSWORD (Splunk global variable name, e.g. hw_parking_staging_password)}"

payload="$(python3 "${SCRIPT_DIR}/heathrow-parking-browser-test-payload.py")"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "${payload}"
  exit 0
fi

if [[ -z "${payload}" ]]; then
  echo "Error: generated payload is empty" >&2
  exit 1
fi

response="$(bash "${SCRIPT_DIR}/heathrow-api-request.sh" PUT "v2/synthetics/tests/browser/${TEST_ID}" "${payload}")"

if [[ -n "${response}" ]]; then
  echo "${response}" | python3 -m json.tool
  echo ""
  echo "Updated test ${TEST_ID}."
else
  echo "Updated test ${TEST_ID} (empty response body)."
fi

echo "Trigger a manual run in Splunk Observability to verify."
