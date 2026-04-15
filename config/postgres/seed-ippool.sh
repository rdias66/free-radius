#!/bin/sh
# =============================================================
# seed-ippool.sh — populates radippool with a configurable
# IP address range for rlm_sqlippool (Phase 11).
#
# Executed automatically by the PostgreSQL entrypoint from
# docker-entrypoint-initdb.d/ on the first container start
# (after 01-schema.sql has created the table).
#
# Environment variables (set in docker-compose.yml):
#
#   IPPOOL_PRESET   "private" (default) or "cgnat"
#                   "cgnat" models an ISP with a small shared-
#                   address-space pool (RFC 6598 100.64.0.0/10).
#                   When set, IPPOOL_START/END defaults change
#                   to the CGNAT range unless overridden.
#
#   IPPOOL_NAME     Pool name written to radippool.pool_name
#                   and matched by mods-enabled/sqlippool.
#                   Default: local
#
#   IPPOOL_START    First address in the range (inclusive).
#                   Default (private):  10.100.0.1
#                   Default (cgnat):    100.64.0.1
#
#   IPPOOL_END      Last address in the range (inclusive).
#                   Default (private):  10.100.0.254   (/24,  254 IPs)
#                   Default (cgnat):    100.64.3.254   (/22, 1022 IPs)
#
# Preset sizing rationale:
#   private  — /24 is sufficient for dev/test load (< 200 concurrent sessions)
#   cgnat    — /22 (~1 k IPs) simulates a resource-constrained ISP NAS pool;
#              a real CGNAT pool is typically /20–/16 but that is unnecessary
#              for functional testing
# =============================================================

set -e

POOL_NAME="${IPPOOL_NAME:-local}"

case "${IPPOOL_PRESET:-private}" in
    cgnat)
        START_IP="${IPPOOL_START:-100.64.0.1}"
        END_IP="${IPPOOL_END:-100.64.3.254}"
        ;;
    *)
        START_IP="${IPPOOL_START:-10.100.0.1}"
        END_IP="${IPPOOL_END:-10.100.0.254}"
        ;;
esac

echo "seed-ippool: pool='${POOL_NAME}' preset='${IPPOOL_PRESET:-private}' range=${START_IP}–${END_IP}"

psql -v ON_ERROR_STOP=1 \
     --username "$POSTGRES_USER" \
     --dbname   "$POSTGRES_DB" \
     -v pool_name="${POOL_NAME}" \
     -v start_ip="${START_IP}" \
     -v end_ip="${END_IP}" <<-'EOSQL'
-- expiry_time = epoch means all IPs are immediately available for allocation.
-- rlm_sqlippool treats any row where expiry_time < NOW() as a free lease.
INSERT INTO radippool (pool_name, framedipaddress, expiry_time)
SELECT
    :'pool_name',
    (:'start_ip'::inet + (n - 1))::inet,
    'epoch'::timestamp
FROM generate_series(1, (:'end_ip'::inet - :'start_ip'::inet) + 1) AS n
ON CONFLICT DO NOTHING;

SELECT pool_name, COUNT(*) AS pool_size FROM radippool GROUP BY pool_name;
EOSQL
