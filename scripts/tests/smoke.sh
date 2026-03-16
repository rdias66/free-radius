#!/bin/sh
# =============================================================
# smoke.sh — Basic smoke test: one auth + one accounting packet
# Run from inside radtest-tool container:
#   docker compose --profile testing exec radtest-tool sh /tests/smoke.sh
# =============================================================

HOST=${RADIUS_HOST:-freeradius}
PORT=${RADIUS_AUTH_PORT:-1812}
SECRET=${RADIUS_SECRET:-testing123}
USER=${TEST_USER:-testuser}
PASS=${TEST_PASS:-testpass}

echo "=== Smoke test: single auth ==="
result=$(radtest "$USER" "$PASS" "$HOST" 0 "$SECRET" 2>&1)
echo "$result"

if echo "$result" | grep -q "Access-Accept"; then
    echo "PASS: Access-Accept received"
else
    echo "FAIL: Access-Accept not received"
    exit 1
fi

echo ""
echo "=== Smoke test: reject (wrong password) ==="
result=$(radtest "$USER" "wrongpassword" "$HOST" 0 "$SECRET" 2>&1)
echo "$result"

if echo "$result" | grep -q "Access-Reject"; then
    echo "PASS: Access-Reject received"
else
    echo "FAIL: Access-Reject not received"
    exit 1
fi

echo ""
echo "All smoke tests passed."
