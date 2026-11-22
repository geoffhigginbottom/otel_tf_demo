#!/usr/bin/env bash
# Create Splunk Synthetics browser test for Heathrow parking staging flow.
#
# Prerequisites in the target org:
#   1. API token with Synthetics write access (X-SF-TOKEN)
#   2. Splunk global variable named in AUTH_PASSWORD (password value for the site)
#   3. A valid location ID (default public location: aws-eu-west-2)
#
# Usage:
#   export REALM="eu0"
#   export TOKEN="..."
#   export TEST_NAME="Heathrow Car Parking (Staging) T2 28 Day"
#   export AUTH_USERNAME="storefront"
#   export AUTH_PASSWORD="hw_parking_staging_password"
#   ./scripts/heathrow/create-heathrow-parking-browser-test.sh
#
# Optional:
#   LOCATION_IDS="aws-eu-west-2,aws-us-east-1"   # comma-separated
#   FREQUENCY=60
#   PARKING_URL="https://app-storefront.staging.lhr.aero/booking/parking"
#   ACTIVE=true
#   DEVICE_ID=1                                  # see LIST_DEVICES=1
#
# Dry run (print JSON only):
#   DRY_RUN=1 ./scripts/heathrow/create-heathrow-parking-browser-test.sh
#
# List org resources (requires REALM and TOKEN only):
#   LIST_LOCATIONS=1 ./scripts/heathrow/create-heathrow-parking-browser-test.sh
#   LIST_DEVICES=1 ./scripts/heathrow/create-heathrow-parking-browser-test.sh
#   LIST_VARIABLES=1 ./scripts/heathrow/create-heathrow-parking-browser-test.sh
#   LIST=1 ./scripts/heathrow/create-heathrow-parking-browser-test.sh   # all of the above

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

list_all="$([[ "${LIST:-0}" == "1" ]] && echo 1 || echo 0)"
list_locations="$([[ "${LIST_LOCATIONS:-0}" == "1" || "${list_all}" == "1" ]] && echo 1 || echo 0)"
list_devices="$([[ "${LIST_DEVICES:-0}" == "1" || "${list_all}" == "1" ]] && echo 1 || echo 0)"
list_variables="$([[ "${LIST_VARIABLES:-0}" == "1" || "${list_all}" == "1" ]] && echo 1 || echo 0)"

if [[ "${DRY_RUN:-0}" != "1" && "${list_locations}" != "1" && "${list_devices}" != "1" && "${list_variables}" != "1" ]]; then
  REALM="${REALM:?Set REALM e.g. eu0}"
  TOKEN="${TOKEN:?Set TOKEN (X-SF-TOKEN)}"
fi

REALM="${REALM:-eu0}"
TOKEN="${TOKEN:-}"

if [[ "${list_locations}" == "1" || "${list_devices}" == "1" || "${list_variables}" == "1" ]]; then
  TOKEN="${TOKEN:?Set TOKEN (X-SF-TOKEN)}"
  REALM="${REALM:?Set REALM e.g. eu0}"
fi

if [[ "${list_locations}" == "1" ]]; then
  echo "Synthetics locations in ${REALM} (use id values for LOCATION_IDS):"
  echo ""
  locations_json="$(bash "${SCRIPT_DIR}/heathrow-api-request.sh" GET "v2/synthetics/locations")"
  LOCATIONS_JSON="${locations_json}" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["LOCATIONS_JSON"])
locations = data.get("locations") or data.get("results") or []
if not locations and isinstance(data, list):
    locations = data

if not locations:
    print(json.dumps(data, indent=2))
else:
    print(f"{'ID':<24} {'TYPE':<10} {'LABEL'}")
    print("-" * 60)
    for loc in locations:
        print(f"{loc.get('id', ''):<24} {loc.get('type', ''):<10} {loc.get('label', '')}")
PY
  echo ""
fi

if [[ "${list_devices}" == "1" ]]; then
  echo "Synthetics devices in ${REALM} (use id values for DEVICE_ID):"
  echo ""
  devices_json="$(bash "${SCRIPT_DIR}/heathrow-api-request.sh" GET "v2/synthetics/devices")"
  DEVICES_JSON="${devices_json}" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["DEVICES_JSON"])
devices = data.get("devices") or data.get("results") or []
if not devices and isinstance(data, list):
    devices = data

if not devices:
    print(json.dumps(data, indent=2))
else:
    print(f"{'ID':<6} {'LABEL':<24} {'VIEWPORT':<12} {'NETWORK'}")
    print("-" * 72)
    for device in devices:
        width = device.get("viewportWidth", "")
        height = device.get("viewportHeight", "")
        viewport = f"{width}x{height}" if width and height else ""
        network = (device.get("networkConnection") or {}).get("description", "")
        print(
            f"{device.get('id', ''):<6} "
            f"{device.get('label', ''):<24} "
            f"{viewport:<12} "
            f"{network}"
        )
PY
  echo ""
fi

if [[ "${list_variables}" == "1" ]]; then
  echo "Synthetics global variables in ${REALM} (use name values for AUTH_PASSWORD):"
  echo ""
  variables_json="$(bash "${SCRIPT_DIR}/heathrow-api-request.sh" GET "v2/synthetics/variables")"
  VARIABLES_JSON="${variables_json}" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["VARIABLES_JSON"])
variables = data.get("variables") or data.get("results") or []
if not variables and isinstance(data, list):
    variables = data

if not variables:
    print(json.dumps(data, indent=2))
else:
    print(f"{'NAME':<32} {'SECRET':<8} DESCRIPTION")
    print("-" * 80)
    for var in variables:
        name = var.get("name", "")
        secret = "yes" if var.get("secret") else "no"
        description = (var.get("description") or "").replace("\n", " ")
        if len(description) > 40:
            description = description[:37] + "..."
        print(f"{name:<32} {secret:<8} {description}")
PY
  echo ""
fi

if [[ "${list_locations}" == "1" || "${list_devices}" == "1" || "${list_variables}" == "1" ]]; then
  exit 0
fi

TEST_NAME="${TEST_NAME:?Set TEST_NAME (must be unique in the org, e.g. \"Heathrow Car Parking (Staging) T2 7 Day\")}"
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

response="$(bash "${SCRIPT_DIR}/heathrow-api-request.sh" POST "v2/synthetics/tests/browser" "${payload}")"

if [[ -n "${response}" ]]; then
  echo "${response}" | python3 -m json.tool
  new_id="$(echo "${response}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('test',{}).get('id',''))" 2>/dev/null || true)"
else
  new_id=""
fi

echo ""
if [[ -n "${new_id}" ]]; then
  echo "Created browser test id: ${new_id}"
  echo "Update an existing test later with:"
  echo "  TEST_ID=${new_id} ${SCRIPT_DIR}/update-heathrow-parking-browser-test.sh"
else
  echo "Create request succeeded. Fetch test id with:"
  echo "  curl -s -H \"X-SF-TOKEN: \$TOKEN\" \"https://api.${REALM}.observability.splunkcloud.com/v2/synthetics/tests\" | python3 -m json.tool"
fi
echo "Trigger a manual run in Splunk Observability to verify."
