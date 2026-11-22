#!/usr/bin/env bash
# Shared Splunk Synthetics API helper.
# Usage: heathrow-api-request.sh <METHOD> <PATH> [payload]
#   METHOD: GET | POST | PUT
#   PATH:   e.g. v2/synthetics/tests/browser or v2/synthetics/tests/browser/123

set -euo pipefail

REALM="${REALM:?Set REALM e.g. eu0}"
TOKEN="${TOKEN:?Set TOKEN (X-SF-TOKEN)}"
BASE_URL="${BASE_URL:-https://api.${REALM}.observability.splunkcloud.com}"

method="${1:?METHOD required (GET|POST|PUT)}"
path="${2:?PATH required}"
payload="${3:-}"

url="${BASE_URL}/${path#/}"
response_file="$(mktemp)"
trap 'rm -f "${response_file}"' EXIT

if [[ -n "${payload}" ]]; then
  http_code="$(
    curl -sS -o "${response_file}" -w "%{http_code}" -X "${method}" \
      "${url}" \
      -H "Content-Type: application/json" \
      -H "X-SF-TOKEN: ${TOKEN}" \
      -d "${payload}"
  )"
else
  http_code="$(
    curl -sS -o "${response_file}" -w "%{http_code}" -X "${method}" \
      "${url}" \
      -H "Content-Type: application/json" \
      -H "X-SF-TOKEN: ${TOKEN}"
  )"
fi

response_body="$(cat "${response_file}")"

if [[ "${http_code}" =~ ^2 ]]; then
  if [[ -n "${response_body}" ]]; then
    echo "${response_body}"
  fi
  exit 0
fi

echo "Request failed (HTTP ${http_code}) for ${method} ${url}:" >&2
if [[ -n "${response_body}" ]]; then
  if formatted="$(echo "${response_body}" | python3 -m json.tool 2>/dev/null)"; then
    echo "${formatted}" >&2
  else
    echo "${response_body}" >&2
  fi
else
  echo "(empty response body)" >&2
fi
exit 1
