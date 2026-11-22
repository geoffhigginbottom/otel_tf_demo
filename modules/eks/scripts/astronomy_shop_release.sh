#!/usr/bin/env bash
# Download and apply a splunk/opentelemetry-demo GitHub release.
# Usage:
#   astronomy_shop_release.sh fetch <version>
#   astronomy_shop_release.sh chart-version
#   astronomy_shop_release.sh apply <version>
#   astronomy_shop_release.sh delete
set -euo pipefail

REPO="splunk/opentelemetry-demo"
DEST="${ASTRONOMY_SHOP_DIR:-/home/ubuntu/astronomy-shop}"
CORE_NAME="splunk-astronomy-shop.yaml"
SHIM_NAME="splunk-astronomy-shop-dc-shim.yaml"
VALUES_NAME="collector-values.yaml"

usage() {
  echo "Usage: $(basename "$0") <fetch|chart-version|apply|delete> [version]" >&2
  exit 1
}

normalize_version() {
  local tag="${1:-}"
  tag="${tag#v}"
  tag="${tag#V}"
  if [[ ! "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)*$ ]]; then
    echo "Unsupported Astronomy Shop release: ${tag}" >&2
    exit 1
  fi
  printf '%s' "$tag"
}

download() {
  local url="$1"
  local dest="$2"
  local optional="${3:-false}"
  local code
  code="$(curl -fsSL -o "$dest" -w "%{http_code}" -H "User-Agent: astronomy-shop-release" "$url" || true)"
  if [[ "$code" == "200" ]]; then
    return 0
  fi
  rm -f "$dest"
  if [[ "$optional" == "true" && ( "$code" == "404" || -z "$code" ) ]]; then
    return 0
  fi
  echo "Download failed (${code:-curl error}): $url" >&2
  exit 1
}

fetch_release() {
  local version
  version="$(normalize_version "${1:-}")"
  mkdir -p "$DEST"
  local base="https://github.com/${REPO}/releases/download/v${version}"
  echo "Fetching Astronomy Shop ${version}"
  download "${base}/splunk-astronomy-shop-${version}.yaml" "${DEST}/${CORE_NAME}"
  download "${base}/splunk-astronomy-shop-${version}-dc-shim.yaml" "${DEST}/${SHIM_NAME}" true
  download "${base}/splunk-astronomy-shop-${version}-values.yaml" "${DEST}/${VALUES_NAME}"
  printf '%s\n' "$version" > "${DEST}/version"
  if ! grep -q "Splunk Astronomy Shop" "${DEST}/${CORE_NAME}"; then
    echo "Downloaded manifest is not a Splunk Astronomy Shop release" >&2
    exit 1
  fi
}

chart_version() {
  local values="${DEST}/${VALUES_NAME}"
  local parsed=""
  if [[ -f "$values" ]]; then
    parsed="$(grep -E 'splunk-otel-collector-chart >= [0-9]+\.[0-9]+\.[0-9]+' "$values" | head -n 1 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' || true)"
  fi
  if [[ -z "$parsed" ]]; then
    parsed="0.157.0"
  fi
  printf '%s\n' "$parsed"
}

patch_sql_server_permissions() {
  # SQL Server 2022 runs as uid 10001. An EBS volume is root-owned until fsGroup
  # is set, and sqlservr then exits trying to create its system directory.
  # A crash-looping pod keeps the old template, so replace it when needed.
  if ! kubectl get sts sql-server-fraud >/dev/null 2>&1; then
    return 0
  fi
  kubectl patch sts sql-server-fraud --type merge \
    -p '{"spec":{"template":{"spec":{"securityContext":{"fsGroup":10001}}}}}'
  local current
  current="$(kubectl get pod sql-server-fraud-0 -o jsonpath='{.spec.securityContext.fsGroup}' 2>/dev/null || true)"
  if [[ "$current" != "10001" ]]; then
    kubectl delete pod sql-server-fraud-0 --wait=false || true
  fi
}

patch_frontend_proxy() {
  # The Terraform ALB registers EC2 nodes on 30080. Fargate uses pod port 8080 and ignores this node port.
  kubectl patch svc frontend-proxy --type merge -p '{"spec":{"type":"NodePort","ports":[{"name":"tcp-service","port":8080,"targetPort":8080,"nodePort":30080}]}}'
}

ensure_ebs_storage_class() {
  # The release manifest asks for the k3s/Rancher local-path class. EKS has the
  # EBS CSI driver, and the in-tree kubernetes.io/aws-ebs class cannot provision.
  if ! kubectl get csidriver ebs.csi.aws.com >/dev/null 2>&1; then
    return 0
  fi
  kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
parameters:
  type: gp3
  fsType: ext4
  encrypted: "true"
EOF
}

prepare_manifest_storage() {
  local manifest="${DEST}/${CORE_NAME}"
  if ! kubectl get csidriver ebs.csi.aws.com >/dev/null 2>&1; then
    return 0
  fi
  if grep -q 'storageClassName: local-path' "$manifest"; then
    local rewritten="${manifest}.storage"
    sed 's/storageClassName: local-path/storageClassName: gp3/' "$manifest" > "$rewritten"
    mv "$rewritten" "$manifest"
  fi
  # storageClassName is immutable, so a pending local-path claim must be removed
  # before apply recreates it on gp3. Pods that mount it hold the PVC finalizer.
  python3 - <<'PY'
import json, subprocess

claims = json.loads(subprocess.check_output(["kubectl", "get", "pvc", "-A", "-o", "json"]))
for claim in claims.get("items", []):
    if claim.get("spec", {}).get("storageClassName") != "local-path":
        continue
    if claim.get("status", {}).get("phase") == "Bound":
        continue
    namespace = claim["metadata"]["namespace"]
    name = claim["metadata"]["name"]
    pods = json.loads(subprocess.check_output(["kubectl", "get", "pods", "-n", namespace, "-o", "json"]))
    for pod in pods.get("items", []):
        volumes = pod.get("spec", {}).get("volumes") or []
        mounted = any(
            (volume.get("persistentVolumeClaim") or {}).get("claimName") == name
            for volume in volumes
        )
        if mounted:
            subprocess.check_call([
                "kubectl", "delete", "pod", "-n", namespace, pod["metadata"]["name"], "--wait=false",
            ])
    subprocess.check_call(["kubectl", "delete", "pvc", "-n", namespace, name, "--wait=true"])
PY
}

require_secrets() {
  python3 - "$DEST" <<'PY'
import glob, json, os, re, subprocess, sys

dest = sys.argv[1]
missing = []
seen = set()
for path in sorted(glob.glob(os.path.join(dest, "*.yaml"))):
    text = open(path, encoding="utf-8", errors="replace").read()
    for block in re.findall(r"(?m)^[ \t]+secretKeyRef:\n(?:[ \t]+.+\n){1,8}", text):
        if re.search(r"optional:\s*true", block):
            continue
        name = re.search(r"name:\s*(\S+)", block)
        key = re.search(r"key:\s*(\S+)", block)
        if not name or not key:
            continue
        secret, item = name.group(1), key.group(1)
        ident = (secret, item)
        if ident in seen:
            continue
        seen.add(ident)
        proc = subprocess.run(
            ["kubectl", "get", "secret", secret, "-o", "json"],
            capture_output=True, text=True,
        )
        data = {}
        if proc.returncode == 0 and proc.stdout.strip():
            data = json.loads(proc.stdout).get("data") or {}
        if not data.get(item):
            missing.append(f"{secret}/{item}")

if missing:
    sys.stderr.write("Astronomy Shop is missing required secrets:\n")
    for item in missing:
        sys.stderr.write(f"  {item}\n")
    sys.exit(1)
print(json.dumps({"required_secrets": len(seen)}))
PY
}

apply_release() {
  local version
  version="$(normalize_version "${1:-}")"
  fetch_release "$version"
  if [[ -f /home/ubuntu/secrets.yaml ]]; then
    kubectl apply -f /home/ubuntu/secrets.yaml
  fi
  ensure_ebs_storage_class
  prepare_manifest_storage
  kubectl apply -f "${DEST}/${CORE_NAME}"
  if [[ -f "${DEST}/${SHIM_NAME}" ]]; then
    kubectl apply -f "${DEST}/${SHIM_NAME}"
  fi
  patch_frontend_proxy
  patch_sql_server_permissions
  require_secrets
  echo "Astronomy Shop ${version} applied"
}

delete_release() {
  if [[ -f "${DEST}/${SHIM_NAME}" ]]; then
    kubectl delete -f "${DEST}/${SHIM_NAME}" --ignore-not-found --wait=false || true
  fi
  if [[ -f "${DEST}/${CORE_NAME}" ]]; then
    kubectl delete -f "${DEST}/${CORE_NAME}" --ignore-not-found --wait=false || true
  fi
}

command="${1:-}"
shift || true

case "$command" in
  fetch) fetch_release "${1:-}" ;;
  chart-version) chart_version ;;
  apply) apply_release "${1:-}" ;;
  delete) delete_release ;;
  *) usage ;;
esac
