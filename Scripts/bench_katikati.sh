#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Black-box performance run for an installed KatiKati build (port plan #1, 2026-10-27).
# Adapted from Asyar's benchmarks/bench.sh (https://github.com/Xoshbin/asyar at 334c8fa, GPL-3.0):
# the same scenarios and the same powermetrics parsing, cut down to one app.
#
#   Scripts/bench_katikati.sh [--idle-only] [/path/to/KatiKati.app]
#
# Full run (needs Accessibility for the terminal, so synthetic key presses reach KatiKati):
#   1. cold start: `open` the app, press ⌥Space until the launcher shows
#   2. 15 launcher summons (⌥Space), median / p95 / p99
#   3. memory and CPU for 30 s right after that activity
#   4. 120 s settle, then 60 s deep idle: CPU, memory, and (with passwordless sudo) powermetrics
#      CPU ms/s and interrupt wakeups/s for KatiKati's process group
# --idle-only skips 1-3 and needs no permission: it launches the app if needed and measures step 4.
# CI uses it (.github/workflows/bench.yml).
#
# Results go to $BENCH_OUT (default /tmp/katikati-bench), never into the repo.
set -euo pipefail

IDLE_ONLY=0
if [[ "${1:-}" == "--idle-only" ]]; then IDLE_ONLY=1; shift; fi
APP="${1:-/Applications/KatiKati.app}"
HOTKEY="${BENCH_HOTKEY:-opt+space}"
RUNS="${BENCH_RUNS:-15}"
SETTLE_SECONDS="${BENCH_SETTLE_SECONDS:-120}"
DEEP_IDLE_SECONDS="${BENCH_DEEP_IDLE_SECONDS:-60}"
OUT="${BENCH_OUT:-/tmp/katikati-bench}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$APP" ]] || { echo "error: $APP not found" >&2; exit 1; }
mkdir -p "$OUT"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$OUT/$STAMP.log"
REPORT="$OUT/$STAMP.md"
: > "$LOG"

BENCHTOOL="$OUT/benchtool"
swiftc -O "$REPO_ROOT/Tools/Bench/benchtool.swift" -o "$BENCHTOOL"

extract() { # file key
  awk -F= -v k="$2" '$1 == k { value = $2; found = 1 } END { print found ? value : "n/a" }' "$1"
}

parse_powermetrics() { # raw-file pid...
  python3 - "$@" <<'PY'
import re
import sys

path = sys.argv[1]
pids = set(sys.argv[2:])
number = r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)"
pid_pattern = "|".join(re.escape(pid) for pid in sorted(pids, key=len, reverse=True))
row = re.compile(r"^(.+?)\s+(" + pid_pattern + r")\s+(" + number + r"(?:\s+" + number + r"){5,})\s*$")
sample_header = re.compile(r"^\*+\s*Sampled system activity")
samples = []
current = None
matched = False

with open(path, encoding="utf-8", errors="replace") as raw:
    for line in raw:
        line = line.strip()
        if sample_header.match(line):
            if current is not None:
                samples.append(current)
            current = [0.0, 0.0]
            continue
        match = row.match(line)
        if not match:
            continue
        values = [float(value) for value in match.group(3).split()]
        if current is None:
            current = [0.0, 0.0]
        current[0] += values[0]
        current[1] += values[4]
        matched = True

if current is not None:
    samples.append(current)
if not matched or not samples:
    raise SystemExit(1)

print(f"pm_cpu_ms_s={sum(sample[0] for sample in samples) / len(samples):.2f}")
print(f"pm_wakeups_s={sum(sample[1] for sample in samples) / len(samples):.2f}")
PY
}

group_pids() {
  "$BENCHTOOL" group "$APP" | sed -n 's/^pid=\([0-9]*\).*/\1/p'
}

if [[ $IDLE_ONLY == 0 ]]; then
  if [[ -n "$(group_pids 2>/dev/null || true)" ]]; then
    echo "Quitting the running KatiKati for a cold start..."
    osascript -e 'tell application id "com.katikati.app" to quit' || true
    sleep 3
  fi
  echo "== cold start" | tee -a "$LOG"
  "$BENCHTOOL" coldstart "$APP" "$HOTKEY" | tee -a "$LOG"
  sleep 2
  echo "== launcher hotkey ($HOTKEY x $RUNS)" | tee -a "$LOG"
  "$BENCHTOOL" hotkey "$APP" "$HOTKEY" "$RUNS" | tee -a "$LOG"
  echo "== after activity (30 s)" | tee -a "$LOG"
  "$BENCHTOOL" mem "$APP" | sed 's/^total_mb=/active_total_mb=/' | tee -a "$LOG"
  "$BENCHTOOL" cpu "$APP" 30 | sed -e 's/^cpu_pct=/active_cpu_pct=/' -e 's/^cpu_proc /active_cpu_proc /' | tee -a "$LOG"
else
  if [[ -z "$(group_pids 2>/dev/null || true)" ]]; then
    open "$APP"
    sleep 5
  fi
fi

echo "== settling ${SETTLE_SECONDS} s" | tee -a "$LOG"
sleep "$SETTLE_SECONDS"

echo "== deep idle (${DEEP_IDLE_SECONDS} s)" | tee -a "$LOG"
PIDS=()
while IFS= read -r pid; do PIDS+=("$pid"); done < <(group_pids)
[[ ${#PIDS[@]} -gt 0 ]] || { echo "error: KatiKati is not running" >&2; exit 1; }
PM_RAW="$OUT/$STAMP-powermetrics.txt"
PM_JOB=""
if command -v sudo >/dev/null && sudo -n /usr/bin/powermetrics --samplers cpu_power -i 100 -n 1 >/dev/null 2>&1; then
  sudo -n powermetrics --samplers tasks --show-process-energy -i 1000 -n "$DEEP_IDLE_SECONDS" > "$PM_RAW" 2>&1 &
  PM_JOB=$!
fi
"$BENCHTOOL" cpu "$APP" "$DEEP_IDLE_SECONDS" | sed -e 's/^cpu_pct=/idle_cpu_pct=/' -e 's/^cpu_proc /idle_cpu_proc /' | tee -a "$LOG"
"$BENCHTOOL" mem "$APP" | sed 's/^total_mb=/idle_total_mb=/' | tee -a "$LOG"
if [[ -n "$PM_JOB" ]] && wait "$PM_JOB" && parse_powermetrics "$PM_RAW" "${PIDS[@]}" >> "$LOG"; then
  :
else
  printf 'pm_cpu_ms_s=n/a\npm_wakeups_s=n/a\n' >> "$LOG"
fi
SIZE_MB="$(du -sm "$APP" | awk '{print $1}')"

{
  echo "## KatiKati benchmark ($STAMP)"
  echo
  echo "| Metric | Value |"
  echo "| --- | ---: |"
  if [[ $IDLE_ONLY == 0 ]]; then
    echo "| Cold start → launcher usable | $(extract "$LOG" coldstart_ms) ms |"
    echo "| ⌥Space → launcher visible, median | $(extract "$LOG" median_ms) ms |"
    echo "| ⌥Space → launcher visible, p95 | $(extract "$LOG" p95_ms) ms |"
    echo "| ⌥Space → launcher visible, p99 | $(extract "$LOG" p99_ms) ms |"
    echo "| CPU after activity (30 s) | $(extract "$LOG" active_cpu_pct) % |"
    echo "| Memory after activity | $(extract "$LOG" active_total_mb) MB |"
  fi
  echo "| CPU, deep idle (${DEEP_IDLE_SECONDS} s after ${SETTLE_SECONDS} s settle) | $(extract "$LOG" idle_cpu_pct) % |"
  echo "| CPU ms/s, deep idle (powermetrics) | $(extract "$LOG" pm_cpu_ms_s) |"
  echo "| Interrupt wakeups/s, deep idle | $(extract "$LOG" pm_wakeups_s) |"
  echo "| Memory, deep idle | $(extract "$LOG" idle_total_mb) MB |"
  echo "| App size on disk | $SIZE_MB MB |"
  echo
  echo "Who spent the idle CPU (top 3, % of one core):"
  echo
  { grep '^idle_cpu_proc ' "$LOG" || true; } | head -3 | sed 's/^idle_cpu_proc /- /'
  echo
  echo "<sub>$(sw_vers -productName) $(sw_vers -productVersion), $(sysctl -n machdep.cpu.brand_string). CPU % is of one core.</sub>"
} > "$REPORT"

cat "$REPORT"
echo
echo "Raw log: $LOG"
