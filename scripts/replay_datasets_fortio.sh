#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Defaults
# -----------------------------
CTX="kind-cluster"
NS="default"
SERVICE="cpu-nginx"
PORT="8081"
PATH_WORK="/work"

# Replay: SPEED=1 means 60s per trace-minute (real time). SPEED=60 means 1s per trace-minute (compressed).
SPEED="1"

# Fortio tuning for even distribution
KEEPALIVE="false"
CONCURRENCY_A="5"
CONCURRENCY_C="5"
MAX_QPS_A="0"   # 0 means no cap
MAX_QPS_C="0"

# Which datasets to replay (A, C, or A,C)
DATASETS="A"

# Fortio pod names
POD_A="fortio-a"
POD_C="fortio-c"
LOGLEVEL="Error"

usage() {
  cat <<EOF
Usage:
  $0 <combined_all_days.csv> --datasets A|C|A,C [options]

Options:
  --datasets      A | C | A,C      (default: A)
  --ctx           kubectl context  (default: kind-cluster)
  --ns            namespace        (default: default)
  --service       service name     (default: cpu-nginx)
  --port          service port     (default: 8081)
  --speed         replay speed     (default: 1)  # 1=real-time, 60=compressed 60x
  --conc-a        concurrency A    (default: 200)
  --conc-c        concurrency C    (default: 200)
  --maxqps-a      cap QPS A        (default: 0 = no cap)
  --maxqps-c      cap QPS C        (default: 0 = no cap)

Examples:
  # Dataset A only (real-time):
  $0 ./dataset/combined_all_days.csv --datasets A

  # Dataset C only (compressed: 1 trace-minute = 1s):
  $0 ./dataset/combined_all_days.csv --datasets C --speed 60

  # Both A and C together:
  $0 ./dataset/combined_all_days.csv --datasets A,C --speed 60 --conc-a 300 --conc-c 300
EOF
}

if [[ $# -lt 1 ]]; then usage; exit 1; fi
CSV_PATH="$1"; shift

# -----------------------------
# Parse args
# -----------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --datasets) DATASETS="$2"; shift 2;;
    --ctx) CTX="$2"; shift 2;;
    --ns) NS="$2"; shift 2;;
    --service) SERVICE="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --speed) SPEED="$2"; shift 2;;
    --conc-a) CONCURRENCY_A="$2"; shift 2;;
    --conc-c) CONCURRENCY_C="$2"; shift 2;;
    --maxqps-a) MAX_QPS_A="$2"; shift 2;;
    --maxqps-c) MAX_QPS_C="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

URL_A="http://${SERVICE}:${PORT}${PATH_WORK}?ms=1"
URL_C="http://${SERVICE}:${PORT}${PATH_WORK}?ms=2"

WANT_A=0
WANT_C=0
IFS=',' read -r -a DS_ARR <<< "$DATASETS"
for d in "${DS_ARR[@]}"; do
  d="$(echo "$d" | tr -d '[:space:]')"
  [[ "$d" == "A" ]] && WANT_A=1
  [[ "$d" == "C" ]] && WANT_C=1
done
if [[ "$WANT_A" == "0" && "$WANT_C" == "0" ]]; then
  echo "ERROR: --datasets must include A and/or C"
  exit 1
fi

# -----------------------------
# Helpers
# -----------------------------
created_a=0
created_c=0

cleanup() {
  if [[ "$created_a" == "1" ]]; then
    kubectl --context "$CTX" -n "$NS" delete pod "$POD_A" --ignore-not-found >/dev/null 2>&1 || true
  fi
  if [[ "$created_c" == "1" ]]; then
    kubectl --context "$CTX" -n "$NS" delete pod "$POD_C" --ignore-not-found >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

ensure_fortio_pod() {
  local pod="$1"
  if ! kubectl --context "$CTX" -n "$NS" get pod "$pod" >/dev/null 2>&1; then
    # fortio/fortio image has no /bin/sh, keep it alive with "fortio server"
    kubectl --context "$CTX" -n "$NS" run "$pod" --image=fortio/fortio --restart=Never --command -- \
      fortio server -loglevel "$LOGLEVEL" >/dev/null
    return 0
  fi
  return 1
}

STEP_SEC="$(python3 - <<PY
speed=float("$SPEED")
print(f"{60.0/speed:.3f}")
PY
)"

echo "[setup] ctx=$CTX ns=$NS speed=$SPEED step=${STEP_SEC}s datasets=$DATASETS"
echo "        A -> $URL_A"
echo "        C -> $URL_C"

# -----------------------------
# Start fortio pods
# -----------------------------
if [[ "$WANT_A" == "1" ]]; then
  if ensure_fortio_pod "$POD_A"; then created_a=1; fi
  kubectl --context "$CTX" -n "$NS" wait --for=condition=Ready pod/"$POD_A" --timeout=120s >/dev/null
fi
if [[ "$WANT_C" == "1" ]]; then
  if ensure_fortio_pod "$POD_C"; then created_c=1; fi
  kubectl --context "$CTX" -n "$NS" wait --for=condition=Ready pod/"$POD_C" --timeout=120s >/dev/null
fi

# -----------------------------
# Build schedule: for each (day, minute) -> calls_A, calls_C
# Only sum rows whose HashFunction is in dataset A/C lists.
# -----------------------------
SCHEDULE_FILE="/tmp/schedule_ac.txt"
python3 - "$CSV_PATH" > "$SCHEDULE_FILE" <<'PY'
import csv, re, sys, collections

csv_path = sys.argv[1]

A = {
"711b0aab9f246bb310c8d45af460620555a3c0fb469dbb2783c47533cfdb8df4",
"5336bda8faa5d11baac08b366930d5a0f89d37430f6df30028d75e7fb9724b3e",
}
C = {
"491772fa2fe199e3466a538d2c7da90471af914c937d5217ee8bc71d935d28ac",
"f52f01e691fcba131ff92a9fab3323c3ad2298c48d81050996bbd82a94187e75",
"6eee87a877e771a68c848b1e4d84bc40851e6071218c0b16014ae575d2e998b1",
}

with open(csv_path, newline="") as f:
    r = csv.DictReader(f)
    cols = r.fieldnames or []
    minute_cols = [c for c in cols if re.fullmatch(r"\d+", c)]
    minute_cols.sort(key=lambda x: int(x))

    # totals[day] = (arrA, arrC)
    totals = collections.defaultdict(lambda: ([0]*len(minute_cols), [0]*len(minute_cols)))

    for row in r:
        day = str(row.get("day", "1"))
        hf = row.get("HashFunction", "")
        arrA, arrC = totals[day]

        target = None
        if hf in A: target = "A"
        elif hf in C: target = "C"
        else: continue

        for i, m in enumerate(minute_cols):
            v = row.get(m, "")
            if not v:
                continue
            try:
                val = int(float(v))
            except:
                continue
            if target == "A":
                arrA[i] += val
            else:
                arrC[i] += val

def day_key(d):
    try: return int(d)
    except: return d

for day in sorted(totals.keys(), key=day_key):
    arrA, arrC = totals[day]
    for i, m in enumerate(minute_cols):
        print(day, m, arrA[i], arrC[i])
PY

# -----------------------------
# Replay loop
# -----------------------------
while read -r day minute callsA callsC; do
  # Convert calls/minute -> QPS (scaled by SPEED to preserve totals under compression)
  qpsA="$(python3 - <<PY
calls=float("$callsA"); speed=float("$SPEED")
print(f"{(calls/60.0)*speed:.6f}")
PY
)"
  qpsC="$(python3 - <<PY
calls=float("$callsC"); speed=float("$SPEED")
print(f"{(calls/60.0)*speed:.6f}")
PY
)"

  # Apply caps if configured
  if [[ "$MAX_QPS_A" != "0" ]]; then
    qpsA="$(python3 - <<PY
q=float("$qpsA"); cap=float("$MAX_QPS_A")
print(f"{min(q, cap):.6f}")
PY
)"
  fi
  if [[ "$MAX_QPS_C" != "0" ]]; then
    qpsC="$(python3 - <<PY
q=float("$qpsC"); cap=float("$MAX_QPS_C")
print(f"{min(q, cap):.6f}")
PY
)"
  fi

  echo "[day $day min $minute] A_calls=$callsA A_qps=$qpsA | C_calls=$callsC C_qps=$qpsC (dur=${STEP_SEC}s)"

  start_ts="$(python3 - <<PY
import time; print(time.time())
PY
)"

  pids=()

  if [[ "$WANT_A" == "1" ]] && python3 - <<PY >/dev/null; then
import sys
sys.exit(0 if float("$qpsA") > 1e-9 else 1)
PY
    kubectl --context "$CTX" -n "$NS" exec "$POD_A" -- \
      fortio load -t "${STEP_SEC}s" -c "$CONCURRENCY_A" -qps "$qpsA" -loglevel "$LOGLEVEL" \
      -uniform -nocatchup -keepalive=false "$URL_A" >/dev/null &
    pids+=($!)
  fi

  if [[ "$WANT_C" == "1" ]] && python3 - <<PY >/dev/null; then
import sys
sys.exit(0 if float("$qpsC") > 1e-9 else 1)
PY
    kubectl --context "$CTX" -n "$NS" exec "$POD_C" -- \
      fortio load -t "${STEP_SEC}s" -c "$CONCURRENCY_C" -qps "$qpsC" -loglevel "$LOGLEVEL" \
      -uniform -nocatchup -keepalive=false "$URL_C" >/dev/null &
    pids+=($!)
  fi

  # Wait for any loads started this minute
  for pid in "${pids[@]:-}"; do
    wait "$pid"
  done

  # Optional alignment: if overhead made this minute shorter than STEP_SEC, sleep the remainder
  end_ts="$(python3 - <<PY
import time; print(time.time())
PY
)"
  elapsed="$(python3 - <<PY
start=float("$start_ts"); end=float("$end_ts")
print(end-start)
PY
)"
  rem="$(python3 - <<PY
elapsed=float("$elapsed"); step=float("$STEP_SEC")
r=step-elapsed
print(r if r>0 else 0)
PY
)"
  python3 - <<PY >/dev/null && sleep "$rem" || true
import sys
sys.exit(0 if float("$rem") > 0.001 else 1)
PY

done < "$SCHEDULE_FILE"

echo "Done."
