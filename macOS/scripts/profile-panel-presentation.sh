#!/usr/bin/env bash
set -euo pipefail

ITEMS=50
CYCLES=12
TIME_LIMIT=20s

while [[ $# -gt 0 ]]; do
  case "$1" in
    --items)
      ITEMS="${2:?missing value for --items}"
      shift 2
      ;;
    --cycles)
      CYCLES="${2:?missing value for --cycles}"
      shift 2
      ;;
    --time-limit)
      TIME_LIMIT="${2:?missing value for --time-limit}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

STAMP="$(date '+%Y%m%d-%H%M%S')"
OUT_DIR=".codex/artifacts/perf/${STAMP}-panel-presentation"
TRACE_PATH="${OUT_DIR}/clipdock-panel-presentation.trace"
BENCHMARK_JSON="${OUT_DIR}/benchmark.json"
HITCHES_XML="${OUT_DIR}/hitches.xml"
XCTRACE_LOG="${OUT_DIR}/xctrace.log"
TARGET_LOG="${OUT_DIR}/target.log"
SUMMARY_JSON="${OUT_DIR}/summary.json"
ARTIFACTS_JSON="${OUT_DIR}/artifacts.json"

mkdir -p "$OUT_DIR"

swift build
CLIPDOCK_BINARY="${ROOT_DIR}/.build/debug/ClipDock"

"$CLIPDOCK_BINARY" \
  --panel-presentation-benchmark \
  --items "$ITEMS" \
  --cycles "$CYCLES" \
  --start-delay-ms 1200 \
  > "$BENCHMARK_JSON" \
  2> "$TARGET_LOG" &
target_pid=$!

set +e
xcrun xctrace record \
  --template "Animation Hitches" \
  --output "$TRACE_PATH" \
  --time-limit "$TIME_LIMIT" \
  --attach "$target_pid" \
  2>&1 | tee "$XCTRACE_LOG"
record_status=${PIPESTATUS[0]}
wait "$target_pid"
target_status=$?
set -e

if [[ "$record_status" -ne 0 ]]; then
  echo "xctrace record failed with status ${record_status}; log: ${XCTRACE_LOG}" >&2
  exit "$record_status"
fi

if [[ "$target_status" -ne 0 ]]; then
  echo "ClipDock benchmark failed with status ${target_status}; log: ${TARGET_LOG}" >&2
  exit "$target_status"
fi

xcrun xctrace export \
  --input "$TRACE_PATH" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="hitches"]' \
  --output "$HITCHES_XML"

python3 - "$BENCHMARK_JSON" "$HITCHES_XML" "$XCTRACE_LOG" "$TARGET_LOG" "$SUMMARY_JSON" "$ARTIFACTS_JSON" "$TRACE_PATH" <<'PY'
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

benchmark_path, hitches_path, xctrace_log_path, target_log_path, summary_path, artifacts_path, trace_path = map(Path, sys.argv[1:])

with benchmark_path.open("r", encoding="utf-8") as handle:
    report = json.load(handle)

tree = ET.parse(hitches_path)
refs = {}
for element in tree.getroot().iter():
    ref_id = element.attrib.get("id")
    if ref_id:
        refs[ref_id] = element.attrib.get("fmt", "")
durations_ms = []
for duration in tree.findall(".//duration"):
    formatted = duration.attrib.get("fmt", "")
    if not formatted and "ref" in duration.attrib:
        formatted = refs.get(duration.attrib["ref"], "")
    match = re.match(r"([0-9]+(?:\.[0-9]+)?) ms", formatted)
    if match:
        durations_ms.append(float(match.group(1)))

hitches_over_33 = [value for value in durations_ms if value > 33.0]

log_text = (
    xctrace_log_path.read_text(encoding="utf-8", errors="replace")
    + "\n"
    + target_log_path.read_text(encoding="utf-8", errors="replace")
)
warning_patterns = [
    "Invalid view geometry",
    "UICollectionViewFlowLayout",
    "layoutSubtreeIfNeeded on a view which is already being laid out",
]
warning_count = sum(log_text.count(pattern) for pattern in warning_patterns)

report["hitchCountOver33ms"] = len(hitches_over_33)
report["maxHitchMs"] = max(durations_ms, default=0)
report["appKitWarningCount"] = warning_count

artifacts = {
    "tracePath": str(trace_path),
    "benchmarkPath": str(benchmark_path),
    "hitchesPath": str(hitches_path),
    "xctraceLogPath": str(xctrace_log_path),
    "targetLogPath": str(target_log_path),
}

summary_path.write_text(
    json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
artifacts_path.write_text(
    json.dumps(artifacts, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
print(summary_path.read_text(encoding="utf-8"), end="")

if report["hitchCountOver33ms"] > 0 or report["appKitWarningCount"] > 0:
    sys.exit(2)
PY
