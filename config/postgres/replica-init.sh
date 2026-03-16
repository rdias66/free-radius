#!/bin/sh
# =============================================================
# replica-init.sh — Bootstrap PostgreSQL streaming replica
# Runs once on first start via docker-entrypoint-initdb.d
# Reference: https://www.postgresql.org/docs/16/warm-standby.html
# =============================================================
set -e

PGDATA_DIR="/var/lib/postgresql/data/pgdata"

if [ -f "$PGDATA_DIR/PG_VERSION" ]; then
    echo "Replica already initialized. Skipping."
    exit 0
fi

echo "Bootstrapping streaming replica from primary..."

rm -rf "$PGDATA_DIR"

pg_basebackup \
    --host=postgres \
    --username="${POSTGRES_USER}" \
    --pgdata="$PGDATA_DIR" \
    --wal-method=stream \
    --progress \
    --checkpoint=fast \
    --no-password

cat >> "$PGDATA_DIR/postgresql.auto.conf" <<EOF
primary_conninfo = 'host=postgres port=5432 user=${POSTGRES_USER} password=${POSTGRES_PASSWORD} application_name=replica1'
EOF

touch "$PGDATA_DIR/standby.signal"

echo "Replica bootstrap complete."
