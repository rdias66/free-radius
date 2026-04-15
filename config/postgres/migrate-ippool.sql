-- =============================================================
-- migrate-ippool.sql — adds radippool to an existing database
--
-- Use this when the Postgres volume already has data.
-- (init.sql + seed-ippool.sh only execute on first container start.)
--
-- Usage — private range (default, 10.100.0.0/24, 254 IPs):
--   psql "$SEED_DSN" \
--     -v pool_name=local \
--     -v start_ip=10.100.0.1 \
--     -v end_ip=10.100.0.254 \
--     -f config/postgres/migrate-ippool.sql
--
-- Usage — CGNAT range (RFC 6598 100.64.0.0/22, 1022 IPs):
--   psql "$SEED_DSN" \
--     -v pool_name=local \
--     -v start_ip=100.64.0.1 \
--     -v end_ip=100.64.3.254 \
--     -f config/postgres/migrate-ippool.sql
--
-- CGNAT context: 100.64.0.0/10 (RFC 6598 Shared Address Space) is
-- the range ISPs assign inside their CGNAT fabric. Subscribers get
-- addresses from this range at the NAS; the public IP is shared by
-- many sessions behind the NAT gateway. Using this range here
-- faithfully reproduces what radacct.framedipaddress looks like in
-- a resource-constrained ISP environment.
-- =============================================================

CREATE TABLE IF NOT EXISTS radippool (
    id               bigserial PRIMARY KEY,
    pool_name        varchar(64) NOT NULL,
    framedipaddress  inet        NOT NULL DEFAULT '0.0.0.0',
    nasipaddress     varchar(16) NOT NULL DEFAULT '',
    calledstationid  varchar(64) NOT NULL DEFAULT '',
    callingstationid varchar(64) NOT NULL DEFAULT '',
    expiry_time      timestamp(0) without time zone NOT NULL DEFAULT NOW(),
    username         varchar(64) NOT NULL DEFAULT '',
    pool_key         varchar(64) NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS radippool_poolname_expire  ON radippool (pool_name, expiry_time);
CREATE INDEX IF NOT EXISTS radippool_framedipaddress  ON radippool (framedipaddress);
CREATE INDEX IF NOT EXISTS radippool_nasipaddress     ON radippool (nasipaddress);
CREATE INDEX IF NOT EXISTS radippool_callingstationid ON radippool (callingstationid);

-- expiry_time = epoch means immediately available for allocation.
INSERT INTO radippool (pool_name, framedipaddress, expiry_time)
SELECT
    :'pool_name',
    (:'start_ip'::inet + (n - 1))::inet,
    'epoch'::timestamp
FROM generate_series(1, (:'end_ip'::inet - :'start_ip'::inet) + 1) AS n
ON CONFLICT DO NOTHING;

SELECT pool_name, COUNT(*) AS pool_size FROM radippool GROUP BY pool_name;
