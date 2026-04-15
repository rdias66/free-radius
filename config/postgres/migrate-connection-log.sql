-- =============================================================
-- migrate-connection-log.sql — adds callingstationid to radpostauth
--                              and creates v_connection_log view
--
-- Use this when the Postgres volume already has data.
-- (init.sql only executes on first container start.)
--
-- Usage:
--   psql "$SEED_DSN" -f config/postgres/migrate-connection-log.sql
-- =============================================================

-- Add callingstationid to radpostauth if not already present.
-- Existing rows get the default empty string.
ALTER TABLE radpostauth
    ADD COLUMN IF NOT EXISTS callingstationid VARCHAR(50) NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS radpostauth_callingstationid
    ON radpostauth (callingstationid);

-- =============================================================
-- v_connection_log — unified subscriber event log
--
-- Joins radpostauth (auth events) and radacct (session lifecycle)
-- into a single chronological feed per subscriber, matching the
-- format ISP management systems (IXC, SGP) present to operators.
--
-- Events:
--   Login OK          access-accept from radpostauth
--   Login incorrect   access-reject from radpostauth
--   Session start     acct-start row in radacct
--   IP released       acct-stop row in radacct
--
-- Phase 13 note: duplicate-MAC rejects will appear as
--   "Login incorrect" rows once the authorize policy sets
--   Reply-Message and the REJECT sql block writes them here.
-- =============================================================
CREATE OR REPLACE VIEW v_connection_log AS

    -- Auth events (accept + reject)
    SELECT
        authdate                                AS event_time,
        CASE reply
            WHEN 'Access-Accept' THEN 'Login OK'
            ELSE                      'Login incorrect'
        END                                     AS event,
        username,
        callingstationid                        AS mac,
        NULL::inet                              AS framed_ip,
        NULL                                    AS session_id,
        NULL::bigint                            AS session_time_s,
        NULL::bigint                            AS input_octets,
        NULL::bigint                            AS output_octets,
        NULL                                    AS terminate_cause
    FROM radpostauth

UNION ALL

    -- Session start (IP assigned)
    SELECT
        acctstarttime,
        'Session start',
        username,
        callingstationid,
        framedipaddress,
        acctsessionid,
        NULL,
        NULL,
        NULL,
        NULL
    FROM radacct
    WHERE acctstarttime IS NOT NULL

UNION ALL

    -- Session stop (IP released / disconnection)
    SELECT
        acctstoptime,
        'IP released',
        username,
        callingstationid,
        framedipaddress,
        acctsessionid,
        acctsessiontime,
        acctinputoctets,
        acctoutputoctets,
        acctterminatecause
    FROM radacct
    WHERE acctstoptime IS NOT NULL

ORDER BY event_time DESC;

-- Verify
SELECT event, COUNT(*) FROM v_connection_log GROUP BY event ORDER BY event;
