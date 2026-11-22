#!/usr/bin/env bash
# Prints {"version":"<tag>"} for Terraform data.external.
# "latest" follows the current splunk/opentelemetry-demo GitHub release.
set -euo pipefail

requested="${1:-latest}"

if [[ "$requested" == "latest" ]]; then
  # The releases/latest URL redirects to /releases/tag/vX.Y.Z.
  effective="$(curl -fsSL -o /dev/null -w "%{url_effective}" \
    -H "User-Agent: astronomy-shop-release" \
    "https://github.com/splunk/opentelemetry-demo/releases/latest")"
  tag="${effective##*/}"
else
  tag="$requested"
fi

tag="${tag#v}"
tag="${tag#V}"

if [[ ! "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)*$ ]]; then
  echo "Unsupported Astronomy Shop release: ${tag}" >&2
  exit 1
fi

python3 -c 'import json,sys; print(json.dumps({"version": sys.argv[1]}))' "$tag"
