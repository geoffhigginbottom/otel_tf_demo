#!/usr/bin/env python3
"""One-shot backfill of Tessa Jane SIM metrics into sim_metrics for the last 7 days.

Reads the Splunk admin password from /tmp/splunk_password on the Splunk Enterprise host.
Does not print credentials.
"""
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone

ORG = "EEVC06HAAAA"
INDEX = "sim_metrics"
RESOLUTION_MS = "300000"  # 5 minutes; glass table uses 15m buckets
PASSWORD_FILE = "/tmp/splunk_password"
SPLUNK = "/opt/splunk/bin/splunk"

FILTER = "filter=filter('vessel', 'Tessa Jane')"
METRICS = [
    "solar.voltage.bow",
    "solar.voltage.mid",
    "solar.voltage.stern",
    "solar.power.bow",
    "solar.power.mid",
    "solar.power.stern",
    "solar.max.charge.today.bow",
    "solar.max.charge.today.mid",
    "solar.max.charge.today.stern",
    "solar.max.charge.yesterday.bow",
    "solar.max.charge.yesterday.mid",
    "solar.max.charge.yesterday.stern",
    "solar.max.yield.today.bow",
    "solar.max.yield.today.mid",
    "solar.yield.yesterday.bow",
    "solar.yield.yesterday.mid",
    "solar.yield.yesterday.stern",
    "battery.voltage.house",
    "battery.voltage.starter",
    "battery.soc.house",
    "battery.current.bow",
    "battery.current.mid",
    "battery.current.stern",
    "bmv.relay.state",
    "cabin.temp",
    "cabin.humidity",
    "cabin.pressure",
    "venus.cpu.temp",
    "openplotter.cpu.temperature",
]


def load_password() -> str:
    try:
        with open(PASSWORD_FILE, encoding="utf-8") as fh:
            password = fh.read().strip()
    except OSError as exc:
        raise SystemExit(f"Cannot read {PASSWORD_FILE}: {exc}") from exc
    if not password:
        raise SystemExit(f"{PASSWORD_FILE} is empty")
    return password


def build_search() -> str:
    program = "; ".join(f"data('{metric}', {FILTER}).publish()" for metric in METRICS)
    return (
        f'| sim flow org_id={ORG} resolution={RESOLUTION_MS} query="{program}" '
        r"| rename _value as sim_value "
        r"| eval {metric_name}=tonumber(sim_value) "
        r"| fields - _raw sim_value metric_name computationId sf_organizationID sf_realm sf_resolutionMs "
        f"| mcollect index={INDEX} split=t vessel host"
    )


def run_chunk(search: str, password: str, start: datetime, stop: datetime) -> None:
    label = f"{start.strftime('%Y-%m-%d %H:%M')} -> {stop.strftime('%Y-%m-%d %H:%M')} UTC"
    print(f"Chunk {label}", flush=True)
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/opt/splunk/lib"
    cmd = [
        "sudo",
        "-u",
        "splunk",
        "env",
        "LD_LIBRARY_PATH=/opt/splunk/lib",
        SPLUNK,
        "search",
        search,
        "-earliest_time",
        start.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "-latest_time",
        stop.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "-auth",
        f"admin:{password}",
        "-maxout",
        "0",
    ]
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)
    combined = f"{result.stdout or ''}{result.stderr or ''}"
    for line in combined.splitlines():
        lowered = line.lower()
        if "password" in lowered or "token" in lowered or "authorization" in lowered:
            continue
        if (
            line.startswith("INFO:")
            or line.startswith("FATAL:")
            or line.startswith("ERROR:")
            or "metric data points" in line
        ):
            print(line, flush=True)
    if result.returncode != 0:
        tail = [
            line
            for line in combined.splitlines()
            if "password" not in line.lower() and "token" not in line.lower()
        ][-20:]
        print("\n".join(tail), flush=True)
        raise SystemExit(f"chunk failed rc={result.returncode}")


def main() -> int:
    password = load_password()
    search = build_search()
    now = datetime.now(timezone.utc)
    latest = now.replace(hour=11, minute=40, second=0, microsecond=0)
    if latest >= now:
        latest = now - timedelta(minutes=30)
    earliest = latest - timedelta(days=7)
    print(f"Backfill window UTC: {earliest.isoformat()} -> {latest.isoformat()}", flush=True)

    cursor = earliest
    while cursor < latest:
        nxt = min(cursor + timedelta(days=1), latest)
        run_chunk(search, password, cursor, nxt)
        cursor = nxt

    print("Backfill searches complete.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
