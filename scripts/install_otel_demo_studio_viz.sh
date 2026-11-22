#!/bin/bash
# Install the Boat Electrical Splunk app (KPI viz, Studio dashboard, glass table)
# and optional SIM modular inputs for Tessa Jane.
#
# Usage:
#   sudo SIM_REALM=<realm> SIM_ACCESS_TOKEN=<token> \
#     /tmp/install_otel_demo_studio_viz.sh <splunk_admin_password> [sim_org_id]
#   sudo SIM_REALM=<realm> SIM_ACCESS_TOKEN=<token> \
#     /tmp/install_otel_demo_studio_viz.sh --configure-sim-account <splunk_admin_password> <sim_org_id>
#
# The access token and realm are the Observability values already used by the
# collector (access_token and realm). They are read from the environment and
# are not written into this script.
#
# Expects:
#   /tmp/otel_demo_studio_viz/                 exploded app
#   /tmp/splunk_ta_sim_tessa_jane_inputs.conf   optional SIM inputs template
set -euo pipefail

CONFIGURE_ONLY=0
if [ "${1:-}" = "--configure-sim-account" ]; then
  CONFIGURE_ONLY=1
  shift
fi

PASSWORD="${1:-}"
if [ -n "${2:-}" ]; then
  SIM_ORG_ID="${2}"
fi
SIM_ORG_ID="${SIM_ORG_ID:-}"
SIM_REALM="${SIM_REALM:-}"
SIM_ACCESS_TOKEN="${SIM_ACCESS_TOKEN:-}"
APP_SRC="${APP_SRC:-/tmp/otel_demo_studio_viz}"
APP_DST="/opt/splunk/etc/apps/otel_demo_studio_viz"
INPUTS_TMP="${INPUTS_TMP:-/tmp/splunk_ta_sim_tessa_jane_inputs.conf}"
TA_APP="/opt/splunk/etc/apps/splunk_ta_sim"
S_CLI="sudo -u splunk LD_LIBRARY_PATH=/opt/splunk/lib /opt/splunk/bin/splunk"

if [ -z "$PASSWORD" ]; then
  echo "Usage: $0 <splunk_admin_password> [sim_org_id]" >&2
  exit 1
fi

wait_for_splunk_api() {
  echo "Waiting for Splunk API..."
  for i in {1..30}; do
    if curl -k -s https://localhost:8089/services/server/info >/dev/null; then
      echo "Splunk API is UP"
      return 0
    fi
    echo "Still waiting for API... ($i/30)"
    sleep 5
  done
  echo "Splunk API did not become ready" >&2
  return 1
}

configure_sim_account() {
  if [ -z "$SIM_ORG_ID" ]; then
    echo "No SIM org ID provided; skipping SIM account configuration"
    return 0
  fi
  if [ ! -d "$TA_APP" ]; then
    echo "splunk_ta_sim is not installed; skipping SIM account configuration" >&2
    return 1
  fi
  if [ -z "$SIM_REALM" ] || [ -z "$SIM_ACCESS_TOKEN" ]; then
    echo "SIM realm or access token missing; skipping SIM account configuration" >&2
    return 1
  fi
  if ! [[ "$SIM_ORG_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "SIM org ID contains unsupported characters" >&2
    return 1
  fi
  if ! [[ "$SIM_REALM" =~ ^[a-z0-9]+$ ]]; then
    echo "SIM realm contains unsupported characters" >&2
    return 1
  fi

  wait_for_splunk_api
  echo "Configuring Splunk Infrastructure Monitoring account for org ${SIM_ORG_ID} in realm ${SIM_REALM}"
  SPLUNK_ADMIN_PASSWORD="$PASSWORD" \
  SIM_ORG_ID="$SIM_ORG_ID" \
  SIM_REALM="$SIM_REALM" \
  SIM_ACCESS_TOKEN="$SIM_ACCESS_TOKEN" \
  python3 - <<'PY'
import base64
import json
import os
import re
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request

org_id = os.environ["SIM_ORG_ID"]
realm = os.environ["SIM_REALM"]
token = os.environ["SIM_ACCESS_TOKEN"]
admin_password = os.environ["SPLUNK_ADMIN_PASSWORD"]

if not re.fullmatch(r"[A-Za-z0-9_-]+", org_id):
    raise SystemExit("SIM org ID contains unsupported characters")
if not re.fullmatch(r"[a-z0-9]+", realm):
    raise SystemExit("SIM realm contains unsupported characters")
if not token or any(ch in token for ch in "\r\n"):
    raise SystemExit("SIM access token is empty or contains a newline")

org_url = f"https://api.{realm}.signalfx.com/v2/organization"
org_request = urllib.request.Request(
    org_url,
    headers={"X-SF-Token": token, "Accept": "application/json"},
)
try:
    with urllib.request.urlopen(org_request, timeout=20) as response:
        organization = json.load(response)
except urllib.error.HTTPError as exc:
    raise SystemExit(f"Observability organization lookup failed with HTTP {exc.code}") from None

actual_org_id = organization.get("id")
if actual_org_id != org_id:
    raise SystemExit(
        f"Observability token belongs to org {actual_org_id}, not {org_id}"
    )
org_name = organization.get("organizationName") or org_id

# The demo management port uses the certificate generated on the instance.
splunk_context = ssl._create_unverified_context()
# Credentials are supplied per request so they are not written to a log.
basic = base64.b64encode(f"admin:{admin_password}".encode()).decode("ascii")

def splunk(method, path, payload=None, form=None):
    data = None
    headers = {"Authorization": f"Basic {basic}", "Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    elif form is not None:
        data = urllib.parse.urlencode(form).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    request = urllib.request.Request(
        f"https://127.0.0.1:8089{path}",
        data=data,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(request, context=splunk_context, timeout=30) as response:
            body = response.read().decode()
            status = response.status
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        status = exc.code
    if body:
        try:
            parsed = json.loads(body)
        except json.JSONDecodeError:
            parsed = None
    else:
        parsed = None
    return status, parsed

def kvstore_ready():
    status, body = splunk("GET", "/services/kvstore/status?output_mode=json")
    if status != 200 or not isinstance(body, dict):
        return False
    content = ((body.get("entry") or [{}])[0]).get("content") or {}
    current = content.get("current") or {}
    return (current.get("status") or content.get("status")) == "ready"

# The management port answers before KV store does. A write in that window
# returns success and then disappears when Splunk finishes starting.
for _ in range(36):
    if kvstore_ready():
        break
    time.sleep(5)
else:
    raise SystemExit("KV store did not become ready")

collection_path = "/servicesNS/nobody/splunk_ta_sim/storage/collections/data/sim_api_config"
status, existing = splunk("GET", collection_path)
if status != 200 or not isinstance(existing, list):
    raise SystemExit(f"Unable to read sim_api_config (HTTP {status})")

already = next((item for item in existing if item.get("org_id") == org_id), None)
if already is None:
    record = {
        "realm": realm,
        "org_id": org_id,
        "org_name": org_name,
        "default": len(existing) == 0,
        "enable": True,
    }
    status, _ = splunk("POST", collection_path, payload=record)
    if status not in (200, 201):
        raise SystemExit(f"Unable to create SIM account record (HTTP {status})")
    status, existing = splunk("GET", collection_path)
    if status != 200 or not any(
        isinstance(item, dict) and item.get("org_id") == org_id for item in existing or []
    ):
        raise SystemExit(f"SIM account record was not readable after create (HTTP {status})")
    print(f"Created SIM account {org_name} ({org_id})")
else:
    print(f"SIM account {org_id} already exists")

status, passwords = splunk(
    "GET",
    "/servicesNS/nobody/splunk_ta_sim/storage/passwords?output_mode=json&count=0",
)
if status != 200:
    raise SystemExit(f"Unable to read Splunk password store (HTTP {status})")
entries = (passwords or {}).get("entry", []) if isinstance(passwords, dict) else []
token_stored = False
for entry in entries:
    content = entry.get("content", {})
    if content.get("realm") == "splunk_ta_sim" and content.get("username") == org_id:
        token_stored = True
        break
if not token_stored:
    status, _ = splunk(
        "POST",
        "/servicesNS/nobody/splunk_ta_sim/storage/passwords?output_mode=json",
        form={"name": org_id, "realm": "splunk_ta_sim", "password": token},
    )
    if status not in (200, 201):
        raise SystemExit(f"Unable to store SIM access token (HTTP {status})")
    print(f"Stored SIM access token for org {org_id}")
else:
    print(f"SIM access token for org {org_id} already stored")

status, _ = splunk(
    "POST",
    "/servicesNS/nobody/splunk_ta_sim/data/inputs/sim_modular_input/_reload",
)
if status not in (200, 201):
    raise SystemExit(f"Unable to reload SIM modular inputs (HTTP {status})")
print("Reloaded SIM modular inputs")

status, _ = splunk(
    "POST",
    "/services/apps/local/splunk_ta_sim",
    form={"configured": "1"},
)
if status not in (200, 201):
    raise SystemExit(f"Unable to mark splunk_ta_sim configured (HTTP {status})")
print("Marked splunk_ta_sim configured")
PY

  local_app="$TA_APP/local/app.conf"
  mkdir -p "$TA_APP/local"
  if [ -f "$local_app" ] && grep -q '^is_configured' "$local_app"; then
    sed -i 's/^is_configured.*/is_configured = 1/' "$local_app"
  else
    printf '\n[install]\nis_configured = 1\n' >> "$local_app"
  fi
  chown -R splunk:splunk "$TA_APP/local"
}

if [ "$CONFIGURE_ONLY" -eq 1 ]; then
  configure_sim_account
  exit 0
fi

if [ ! -d "$APP_SRC" ]; then
  echo "Missing app source directory: $APP_SRC" >&2
  exit 1
fi

echo "Creating sim_metrics metric index if needed..."
if ! $S_CLI list index sim_metrics -auth "admin:${PASSWORD}" >/dev/null 2>&1; then
  $S_CLI add index sim_metrics -datatype metric -auth "admin:${PASSWORD}"
else
  echo "Index sim_metrics already exists"
fi

echo "Installing otel_demo_studio_viz app..."
rm -rf "$APP_DST"
mkdir -p /opt/splunk/etc/apps
cp -a "$APP_SRC" "$APP_DST"
chown -R splunk:splunk "$APP_DST"

if [ -n "$SIM_ORG_ID" ] && [ -f "$INPUTS_TMP" ]; then
  if ! [[ "$SIM_ORG_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "SIM org ID contains unsupported characters" >&2
    exit 1
  fi
  TA_LOCAL="$TA_APP/local"
  if [ -d "$TA_APP" ]; then
    echo "Installing Tessa Jane SIM modular inputs..."
    mkdir -p "$TA_LOCAL"
    INPUTS_OUT="$TA_LOCAL/inputs.conf"
    rendered="$(sed "s/__SIM_ORG_ID__/${SIM_ORG_ID}/g" "$INPUTS_TMP")"
    if [ -f "$INPUTS_OUT" ] && grep -q '\[sim_modular_input://TESSA_JANE_SOLAR\]' "$INPUTS_OUT"; then
      echo "TESSA_JANE SIM inputs already present; leaving existing inputs.conf"
    else
      printf '\n%s\n' "$rendered" >> "$INPUTS_OUT"
      chown -R splunk:splunk "$TA_LOCAL"
    fi
  else
    echo "splunk_ta_sim is not installed; skipping SIM inputs"
  fi
else
  echo "No SIM org ID provided; skipping SIM input creation"
fi

echo "Restarting Splunk to load the Boat Electrical app..."
systemctl restart Splunkd
wait_for_splunk_api

if [ -n "$SIM_ORG_ID" ]; then
  configure_sim_account
fi

echo "Boat Electrical app installed at $APP_DST"
