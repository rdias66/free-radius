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
    acctterminatecause  VARCHAR(32)              NOT NULL DEFAULT '',
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

CREATE TABLE IF NOT EXISTS radpostauth (
    id       BIGSERIAL PRIMARY KEY,
    username VARCHAR(64)              NOT NULL DEFAULT '',
    pass     VARCHAR(64)              NOT NULL DEFAULT '',
    reply    VARCHAR(32)              NOT NULL DEFAULT '',
    authdate TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    class    VARCHAR(64)                       DEFAULT NULL
);
CREATE INDEX IF NOT EXISTS radpostauth_username ON radpostauth (username);
CREATE INDEX IF NOT EXISTS radpostauth_authdate ON radpostauth (authdate);