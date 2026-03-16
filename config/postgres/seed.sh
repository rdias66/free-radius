#!/bin/bash
# seed.sh — seeds initial data using env vars
# Runs after init.sql via docker-entrypoint-initdb.d (alphabetical order)
# 01-schema.sql runs first, then 02-seed.sh

set -e

# RADIUS_HEALTH_SECRET comes from the compose environment.
# This is why seed data is a shell script not pure SQL —
# pure SQL cannot read environment variables.
HEALTH_SECRET="${RADIUS_HEALTH_SECRET:-CHANGE_ME_health_secret}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" << SQL
-- Healthcheck user — password matches RADIUS_HEALTH_SECRET in .env
INSERT INTO radcheck (username, attribute, op, value)
VALUES ('healthcheck', 'Cleartext-Password', ':=', '${HEALTH_SECRET}')
ON CONFLICT DO NOTHING;

-- Test user — remove before production
INSERT INTO radcheck (username, attribute, op, value)
VALUES ('testuser', 'Cleartext-Password', ':=', 'testpass')
ON CONFLICT DO NOTHING;

INSERT INTO radreply (username, attribute, op, value)
VALUES ('testuser', 'Reply-Message', '=', 'Welcome'),
       ('testuser', 'Session-Timeout', '=', '3600')
ON CONFLICT DO NOTHING;
SQL