
CREATE DATABASE emailmgr ENCODING = 'UTF8' LC_COLLATE = 'en_US.UTF-8' LC_CTYPE = 'en_US.UTF-8';


CREATE TABLE domain (
	id SERIAL PRIMARY KEY,
	name VARCHAR(255) NOT NULL UNIQUE,
	spooldir char(40) NOT NULL UNIQUE,
	created TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	modified TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	active BOOLEAN NOT NULL DEFAULT TRUE,
	public BOOLEAN NOT NULL DEFAULT TRUE,
	ad_guid BYTEA DEFAULT NULL UNIQUE,
	ad_sync_enabled BOOLEAN NOT NULL DEFAULT TRUE
	);


CREATE TABLE account (
	id SERIAL PRIMARY KEY,
	domain_id INTEGER,
	name VARCHAR(255) NOT NULL,
	password VARCHAR(64) NOT NULL DEFAULT '',
	password_enabled BOOLEAN NOT NULL DEFAULT FALSE,
	fullname VARCHAR(255) DEFAULT NULL,
	spooldir char(40) NOT NULL UNIQUE,
	created TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	modified TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	accessed TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	active BOOLEAN NOT NULL DEFAULT TRUE,
	public BOOLEAN NOT NULL DEFAULT TRUE,
	ad_guid BYTEA DEFAULT NULL UNIQUE,
	ad_sync_enabled BOOLEAN NOT NULL DEFAULT TRUE,
	ad_sync_required BOOLEAN NOT NULL DEFAULT FALSE,
	ad_time_changed BYTEA DEFAULT NULL,
	CONSTRAINT name_domain UNIQUE (name, domain_id),
	CONSTRAINT fk_domain_id FOREIGN KEY (domain_id) REFERENCES domain(id)
	);

CREATE INDEX idx_account_fullname ON account(fullname);
CREATE INDEX idx_account_domain_id ON account(domain_id);

CREATE TABLE alias_name (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    fullname VARCHAR(255) DEFAULT NULL,
    created TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	modified TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	active BOOLEAN NOT NULL DEFAULT TRUE,
	public BOOLEAN NOT NULL DEFAULT FALSE
    );


CREATE TABLE alias_value (
    id SERIAL PRIMARY KEY,
    name_id INTEGER,
    value VARCHAR(255) NOT NULL,
    created TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	modified TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	active BOOLEAN NOT NULL DEFAULT TRUE,
	CONSTRAINT name_value UNIQUE (name_id, value),
	CONSTRAINT fk_alias_name_id FOREIGN KEY (name_id) REFERENCES alias_name(id) ON DELETE CASCADE
    );


CREATE TABLE sysinfo (
    pname VARCHAR(64) NOT NULL UNIQUE,
    pvalue VARCHAR(64) NOT NULL
    );


CREATE TABLE tab_defaults (
    id SERIAL PRIMARY KEY,
    tab_name VARCHAR(255) NOT NULL UNIQUE,
    tab_id INTEGER
    );


CREATE TABLE usn_tracking (
    id SERIAL PRIMARY KEY,
    domain_id INTEGER NOT NULL,
    dit_invocation_id BYTEA NOT NULL,
    dit_usn BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT uk_ut_domain_dit UNIQUE (domain_id, dit_invocation_id),
    CONSTRAINT fk_ut_domain_id FOREIGN KEY (domain_id) REFERENCES domain(id) ON DELETE CASCADE
    );


CREATE TYPE client_proto AS ENUM ('smtp', 'pop', 'imap');

CREATE FUNCTION GetAccountSpoolDir(sp_name VARCHAR(510), sp_caller client_proto) RETURNS VARCHAR(255) AS $$
    DECLARE
        sp_acname VARCHAR(255) DEFAULT GetNamePart(sp_name, '@', 'name');
        sp_acdomain VARCHAR(255) DEFAULT GetNamePart(sp_name, '@', 'domain');
    BEGIN
        IF (sp_acdomain IS NULL) THEN
            SELECT name FROM domain INTO sp_acdomain WHERE id = (SELECT tab_id FROM tab_defaults WHERE tab_name = 'domain');
        END IF;
        IF (sp_caller = 'pop' OR sp_caller = 'imap') THEN
            UPDATE account SET accessed = CURRENT_TIMESTAMP WHERE name = sp_acname AND active = TRUE AND
			    domain_id = (SELECT id FROM domain WHERE name = sp_acdomain AND active = TRUE);
	    END IF;
	    RETURN
	        (SELECT CONCAT(domain.spooldir, '/', account.spooldir)
	            FROM account, domain
		        WHERE account.name = sp_acname AND account.active = TRUE AND domain.name = sp_acdomain AND
		            domain.active = TRUE AND account.domain_id = domain.id);
    END;$$
    LANGUAGE plpgsql;
