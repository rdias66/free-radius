-- =============================================================
-- FreeRADIUS PostgreSQL schema — init.sql
-- Runs once on first container start via docker-entrypoint-initdb.d
-- Based on FreeRADIUS 3.2.x official schema
-- Reference: /etc/raddb/mods-config/sql/main/postgresql/schema.sql
-- =============================================================

CREATE TABLE IF NOT EXISTS radcheck (
    id        SERIAL PRIMARY KEY,
    username  VARCHAR(64)  NOT NULL DEFAULT '',
    attribute VARCHAR(64)  NOT NULL DEFAULT '',
    op        VARCHAR(2)   NOT NULL DEFAULT '==',
    value     VARCHAR(253) NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS radcheck_username ON radcheck (username, attribute);

CREATE TABLE IF NOT EXISTS radreply (
    id        SERIAL PRIMARY KEY,
    username  VARCHAR(64)  NOT NULL DEFAULT '',
    attribute VARCHAR(64)  NOT NULL DEFAULT '',
    op        VARCHAR(2)   NOT NULL DEFAULT '=',
    value     VARCHAR(253) NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS radreply_username ON radreply (username, attribute);

CREATE TABLE IF NOT EXISTS radusergroup (
    id        SERIAL PRIMARY KEY,
    username  VARCHAR(64) NOT NULL DEFAULT '',
    groupname VARCHAR(64) NOT NULL DEFAULT '',
    priority  INTEGER     NOT NULL DEFAULT 1
);
CREATE INDEX IF NOT EXISTS radusergroup_username ON radusergroup (username);

CREATE TABLE IF NOT EXISTS radgroupcheck (
    id        SERIAL PRIMARY KEY,
    groupname VARCHAR(64)  NOT NULL DEFAULT '',
    attribute VARCHAR(64)  NOT NULL DEFAULT '',
    op        VARCHAR(2)   NOT NULL DEFAULT '==',
    value     VARCHAR(253) NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS radgroupcheck_groupname ON radgroupcheck (groupname, attribute);

CREATE TABLE IF NOT EXISTS radgroupreply (
    id        SERIAL PRIMARY KEY,
    groupname VARCHAR(64)  NOT NULL DEFAULT '',
    attribute VARCHAR(64)  NOT NULL DEFAULT '',
    op        VARCHAR(2)   NOT NULL DEFAULT '=',
    value     VARCHAR(253) NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS radgroupreply_groupname ON radgroupreply (groupname, attribute);

CREATE TABLE IF NOT EXISTS radacct (
    radacctid           BIGSERIAL PRIMARY KEY,
    acctsessionid       VARCHAR(64)              NOT NULL DEFAULT '',
    acctuniqueid        VARCHAR(32)              NOT NULL DEFAULT '',
    username            VARCHAR(64)              NOT NULL DEFAULT '',
    realm               VARCHAR(64)                       DEFAULT '',
    nasipaddress        INET                     NOT NULL,
    nasportid           VARCHAR(15)                       DEFAULT NULL,
    nasporttype         VARCHAR(32)                       DEFAULT NULL,
    acctstarttime       TIMESTAMP WITH TIME ZONE          DEFAULT NULL,
    acctupdatetime      TIMESTAMP WITH TIME ZONE          DEFAULT NULL,
    acctstoptime        TIMESTAMP WITH TIME ZONE          DEFAULT NULL,
    acctinterval        BIGINT                            DEFAULT NULL,
    acctsessiontime     BIGINT                            DEFAULT NULL,
    acctauthentic       VARCHAR(32)                       DEFAULT NULL,
    connectinfo_start   VARCHAR(50)                       DEFAULT NULL,
    connectinfo_stop    VARCHAR(50)                       DEFAULT NULL,
    acctinputoctets     BIGINT                            DEFAULT NULL,
    acctoutputoctets    BIGINT                            DEFAULT NULL,
    calledstationid     VARCHAR(50)              NOT NULL DEFAULT '',
    callingstationid    VARCHAR(50)              NOT NULL DEFAULT '',
    acctterminatecause  VARCHAR(32)                       DEFAULT NULL,
    servicetype         VARCHAR(32)                       DEFAULT NULL,
    framedprotocol      VARCHAR(32)                       DEFAULT NULL,
    framedipaddress     INET                              DEFAULT NULL,
    framedipv6address   INET                              DEFAULT NULL,
    framedipv6prefix    INET                              DEFAULT NULL,
    framedinterfaceid   VARCHAR(44)                       DEFAULT NULL,
    delegatedipv6prefix INET                              DEFAULT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS radacct_acctuniqueid   ON radacct (acctuniqueid);
CREATE INDEX        IF NOT EXISTS radacct_username        ON radacct (username);
CREATE INDEX        IF NOT EXISTS radacct_nasipaddress    ON radacct (nasipaddress);
CREATE INDEX        IF NOT EXISTS radacct_acctstarttime   ON radacct (acctstarttime);
CREATE INDEX        IF NOT EXISTS radacct_acctstoptime    ON radacct (acctstoptime);
CREATE INDEX        IF NOT EXISTS radacct_framedipaddress ON radacct (framedipaddress);

-- =============================================================
-- IP address pool — used by rlm_sqlippool (Phase 11)
-- FreeRADIUS reads from this table in post-auth to assign an IP
-- and in accounting to release it on Acct-Stop.
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

-- IP range seeding is handled by 02-seed-ippool.sh (also in
-- docker-entrypoint-initdb.d) so the range is configurable via
-- IPPOOL_PRESET / IPPOOL_START / IPPOOL_END without editing SQL.

CREATE TABLE IF NOT EXISTS radpostauth (
    id                BIGSERIAL PRIMARY KEY,
    username          VARCHAR(64)              NOT NULL DEFAULT '',
    pass              VARCHAR(64)              NOT NULL DEFAULT '',
    reply             VARCHAR(32)              NOT NULL DEFAULT '',
    authdate          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    class             VARCHAR(64)                       DEFAULT NULL,
    -- callingstationid captures the subscriber MAC address so auth events
    -- (both accepts and rejects) carry the same MAC visible in radacct.
    callingstationid  VARCHAR(50)              NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS radpostauth_username         ON radpostauth (username);
CREATE INDEX IF NOT EXISTS radpostauth_authdate         ON radpostauth (authdate);
CREATE INDEX IF NOT EXISTS radpostauth_callingstationid ON radpostauth (callingstationid);

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