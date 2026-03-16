#!/bin/sh
# =============================================================
# load.sh — Concurrent load test using radclient
# Sends N authentication requests across C parallel workers.
# Run from inside radtest-tool container:
#   docker compose --profile testing exec radtest-tool sh /tests/load.sh
#
# Parameters (env vars):
#   LOAD_USERS    — number of unique users to cycle through (default 100)
#   LOAD_REQS     — total requests to send (default 500)
#   LOAD_WORKERS  — parallel radclient processes (default 10)
#   LOAD_RATE     — max req/s per worker (default 0 = unlimited)
# =============================================================

HOST=${RADIUS_HOST:-freeradius}
PORT=${RADIUS_AUTH_PORT:-1812}
SECRET=${RADIUS_SECRET:-testing123}
USERS=${LOAD_USERS:-100}
TOTAL=${LOAD_REQS:-500}
WORKERS=${LOAD_WORKERS:-10}

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "=== Load test ==="
echo "  Host:    $HOST:$PORT"
echo "  Users:   $USERS"
echo "  Total:   $TOTAL requests"
echo "  Workers: $WORKERS"
echo ""

# Build request file: one Access-Request per line
REQ_FILE="$TMPDIR/requests.txt"
i=0
while [ $i -lt $TOTAL ]; do
    u=$((i % USERS + 1))
    printf "User-Name = \"loaduser%04d\"\n" $u >> "$REQ_FILE"
    printf "User-Password = \"testpass\"\n" >> "$REQ_FILE"
    printf "NAS-IP-Address = 127.0.0.1\n" >> "$REQ_FILE"
    printf "\n" >> "$REQ_FILE"
    i=$((i + 1))
done

START=$(date +%s%3N)

# Split into per-worker files and run in parallel
LINES_PER_WORKER=$(( (TOTAL + WORKERS - 1) / WORKERS ))
split -l $((LINES_PER_WORKER * 4)) "$REQ_FILE" "$TMPDIR/chunk_"

PIDS=""
ACCEPT=0
REJECT=0
ERROR=0

for chunk in "$TMPDIR"/chunk_*; do
    OUT="$chunk.out"
    radclient -f "$chunk" -x "$HOST:$PORT" auth "$SECRET" > "$OUT" 2>&1 &
    PIDS="$PIDS $!"
done

for pid in $PIDS; do
    wait $pid
done

END=$(date +%s%3N)
ELAPSED=$(( END - START ))

# Tally results
for out in "$TMPDIR"/*.out; do
    ACCEPT=$((ACCEPT + $(grep -c "Access-Accept" "$out" 2>/dev/null || echo 0)))
    REJECT=$((REJECT + $(grep -c "Access-Reject" "$out" 2>/dev/null || echo 0)))
    ERROR=$((ERROR  + $(grep -c "rad_recv: No reply"  "$out" 2>/dev/null || echo 0)))
done

echo "Results:"
echo "  Elapsed:       ${ELAPSED}ms"
echo "  Access-Accept: $ACCEPT"
echo "  Access-Reject: $REJECT"
echo "  No reply:      $ERROR"
if [ $ELAPSED -gt 0 ]; then
    RPS=$(( TOTAL * 1000 / ELAPSED ))
    echo "  Throughput:    ~${RPS} req/s"
fi
