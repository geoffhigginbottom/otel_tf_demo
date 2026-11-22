#!/bin/bash
# Install Node.js 22 LTS from NodeSource (v22.20.0 or newer).
# Ubuntu 24.04's apt nodejs package is 18.x and is not sufficient for Splunk MCP / npx.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

min_ok() {
  local ver="$1"
  python3 - "$ver" <<'PY'
import sys
ver = sys.argv[1].lstrip("v")
parts = []
for p in ver.split("."):
    try:
        parts.append(int(p))
    except ValueError:
        parts.append(0)
parts += [0, 0, 0]
sys.exit(0 if tuple(parts[:3]) >= (22, 20, 0) else 1)
PY
}

if command -v node >/dev/null 2>&1; then
  current="$(node -v 2>/dev/null || true)"
  if [ -n "$current" ] && min_ok "$current"; then
    echo "Node.js $current already meets v22.20.0+; leaving in place."
    node -v
    npm -v
    exit 0
  fi
  echo "Removing distro Node.js (${current:-unknown}) so NodeSource 22.x can be installed."
  apt-get remove -y nodejs npm libnode108 || true
  apt-get autoremove -y || true
fi

echo "Adding NodeSource 22.x repository..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -

echo "Installing Node.js 22..."
apt-get install -y nodejs

node -v
npm -v

python3 - "$(node -v)" <<'PY'
import sys
ver = sys.argv[1].lstrip("v")
parts = [int(p) if p.isdigit() else 0 for p in ver.split(".")] + [0, 0, 0]
if tuple(parts[:3]) < (22, 20, 0):
    print(f"ERROR: Node.js {ver} is below the required v22.20.0", file=sys.stderr)
    sys.exit(1)
print(f"Node.js {ver} meets v22.20.0+")
PY
