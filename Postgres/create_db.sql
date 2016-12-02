
DROP DATABASE IF EXISTS emailmgr;
CREATE DATABASE emailmgr ENCODING = 'UTF8' LC_COLLATE = 'en_US.UTF-8' LC_CTYPE = 'en_US.UTF-8';


\c emailmgr


DROP ROLE IF EXISTS emailmgr_writer, emailmgr_reader;

CREATE ROLE emailmgr_writer;
CREATE ROLE emailmgr_reader;


CREATE TABLE domain (
	id SERIAL PRIMARY KEY,
	name TEXT NOT NULL,
	spooldir TEXT NOT NULL UNIQUE,
	created TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	modified TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	active BOOLEAN NOT NULL DEFAULT TRUE,
	public BOOLEAN NOT NULL DEFAULT TRUE,
	ad_guid BYTEA DEFAULT NULL UNIQUE,
	ad_sync_enabled BOOLEAN NOT NULL DEFAULT TRUE
	);

CREATE UNIQUE INDEX idx_domain_name_lower ON domain(lower(name));


CREATE TABLE account (
	id SERIAL PRIMARY KEY,
	domain_id INTEGER,
	name TEXT NOT NULL,
	password TEXT NOT NULL DEFAULT '',
	password_enabled BOOLEAN NOT NULL DEFAULT FALSE,
	fullname TEXT DEFAULT NULL CHECK (CHAR_LENGTH(fullname) > 0),
	spooldir TEXT NOT NULL UNIQUE,
	created TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	modified TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	accessed TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	active BOOLEAN NOT NULL DEFAULT TRUE,
	public BOOLEAN NOT NULL DEFAULT TRUE,
	ad_guid BYTEA DEFAULT NULL UNIQUE,
	ad_sync_enabled BOOLEAN NOT NULL DEFAULT TRUE,
	ad_sync_required BOOLEAN NOT NULL DEFAULT FALSE,
	ad_time_changed BYTEA DEFAULT NULL,
	CONSTRAINT fk_domain_id FOREIGN KEY (domain_id) REFERENCES domain(id)
	);

CREATE INDEX idx_account_domain_id ON account(domain_id);
CREATE UNIQUE INDEX idx_account_fullname_lower ON account(lower(fullname));
CREATE UNIQUE INDEX idx_account_name_domain_lower ON account(lower(name), domain_id);


CREATE TABLE alias_name (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    fullname TEXT DEFAULT NULL,
    created TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	modified TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	active BOOLEAN NOT NULL DEFAULT TRUE,
	public BOOLEAN NOT NULL DEFAULT FALSE
    );

CREATE UNIQUE INDEX idx_alias_name_name_lower ON alias_name(lower(name));


CREATE TABLE alias_value (
    id SERIAL PRIMARY KEY,
    name_id INTEGER,
    value TEXT NOT NULL,
    created TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	modified TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	active BOOLEAN NOT NULL DEFAULT TRUE,
	CONSTRAINT fk_alias_name_id FOREIGN KEY (name_id) REFERENCES alias_name(id) ON DELETE CASCADE
    );

CREATE UNIQUE INDEX idx_alias_value_name_value ON alias_value(name_id, lower(value));


CREATE TABLE sysinfo (
    pname TEXT NOT NULL UNIQUE,
    pvalue TEXT NOT NULL
    );


CREATE TABLE tab_defaults (
    id SERIAL PRIMARY KEY,
    tab_name TEXT NOT NULL UNIQUE,
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


-- activity_tracking seems not to keep any sensitive data so that's a point to have it unlogged
CREATE UNLOGGED TABLE activity_tracking (
    tab_name TEXT,
    row_id INTEGER,
    oper_name TEXT,
    oper_time TIMESTAMP(0) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

CREATE INDEX idx_activity_tracking_tab_oper_time ON activity_tracking(tab_name, oper_name, oper_time);


CREATE OR REPLACE FUNCTION UpdateAccountActivity() RETURNS VOID AS $$
    DECLARE
        acc_id INTEGER DEFAULT NULL;
        acc_time TIMESTAMP(0) WITH TIME ZONE DEFAULT NULL;
    BEGIN
        FOR acc_id, acc_time IN SELECT row_id, MAX(oper_time) AS accessed FROM activity_tracking WHERE
            tab_name = 'account' AND oper_name IN ('imap', 'pop') GROUP BY row_id
        LOOP
            UPDATE account SET accessed = acc_time WHERE id = acc_id;
            DELETE FROM activity_tracking WHERE tab_name = 'account' AND oper_name IN ('imap', 'pop') AND
                oper_time <= acc_time;
        END LOOP;
    END;
    $$
    LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION GetNamePart(sp_name TEXT, sp_delim TEXT, sp_partname TEXT) RETURNS TEXT AS $$
    DECLARE
        sp_delim_pos INTEGER DEFAULT POSITION(sp_delim IN sp_name);
    BEGIN
        IF (sp_partname = 'domain')
        THEN
            IF (sp_delim_pos = 0) THEN RETURN(NULL); END IF;
            IF (CHAR_LENGTH(sp_name) = sp_delim_pos) THEN RETURN(NULL); END IF;
            RETURN(SUBSTRING(sp_name FROM sp_delim_pos + 1));
        END IF;
        IF (sp_partname = 'name')
        THEN
            IF (sp_delim_pos = 1) THEN RETURN(NULL); END IF;
            IF (sp_delim_pos = 0) THEN RETURN(sp_name); END IF;
            RETURN(SUBSTRING(sp_name FROM 1 FOR sp_delim_pos - 1));
        END IF;
        RETURN(NULL);
    END;
    $$
    LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION CheckTransactionIsolation(sp_action_name TEXT, sp_levels_allowed TEXT[]) RETURNS VOID AS $$
    -- Unfortunately, the only way to set the isolation level is to perform it outside the function
    -- So we can only check the current level and stop if it doesn't meet requirements
    BEGIN
        IF (NOT (SELECT lower(CURRENT_SETTING('transaction_isolation')) = ANY (sp_levels_allowed))) THEN
            RAISE 'Cannot % with the current isolation level', sp_action_name USING
                HINT = FORMAT('Please set the transaction isolation level to %s', array_to_string(sp_levels_allowed, ' or '));
        END IF;
    END; $$
    LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION GetDomain(sp_domain TEXT, sp_isolated BOOLEAN DEFAULT FALSE,
    sp_silent BOOLEAN DEFAULT FALSE) RETURNS RECORD AS $$
    DECLARE
        sp_domain_id INTEGER DEFAULT NULL;
        sp_domain_name TEXT DEFAULT NULL;
    BEGIN
        -- If we need to lock rows we need to have write privs. So we'll use repeatable read instead.
        IF (sp_isolated) THEN
            PERFORM CheckTransactionIsolation('get domain data', '{"repeatable read", "serializable"}');
        END IF;
        IF (sp_domain IS NULL) THEN
            EXECUTE FORMAT('SELECT d.id, d.name FROM tab_defaults td, domain d '
                'WHERE td.tab_name = ''domain'' AND d.id = td.tab_id %s',
                CASE sp_isolated WHEN FALSE THEN 'FOR SHARE' ELSE '' END) INTO sp_domain_id, sp_domain_name;
            IF (sp_domain_id IS NULL AND NOT sp_silent) THEN
                RAISE 'Domain isn''t specified (no default exists)' USING
                    HINT = 'Please set up a default domain in `tab_defaults`';
            END IF;
        ELSE
            EXECUTE FORMAT('SELECT d.id, d.name FROM domain d WHERE lower(name) = lower($1) %s',
                CASE sp_isolated WHEN FALSE THEN 'FOR SHARE' ELSE '' END) INTO sp_domain_id, sp_domain_name USING
                sp_domain;
            IF (sp_domain_id IS NULL AND NOT sp_silent) THEN
                RAISE 'Domain % not found', sp_domain;
            END IF;
        END IF;
        IF (lower(sp_domain) = lower(sp_domain_name)) THEN
            sp_domain_name = sp_domain; -- We should not change the string case when it is returned to a user
        END IF;
        RETURN(sp_domain_id, sp_domain_name);
    END;$$
    LANGUAGE plpgsql;


CREATE TYPE client_proto AS ENUM ('smtp', 'pop', 'imap');

CREATE OR REPLACE FUNCTION GetAccountSpoolDir(sp_name TEXT, sp_caller client_proto) RETURNS TEXT AS $$
    DECLARE
        sp_acname TEXT DEFAULT GetNamePart(sp_name, '@', 'name');
        sp_acdomain TEXT DEFAULT GetNamePart(sp_name, '@', 'domain');
        sp_domain_id INTEGER DEFAULT NULL;
        sp_spool_dir TEXT DEFAULT NULL;
        sp_acc_id INTEGER DEFAULT NULL;
    BEGIN
        PERFORM CheckTransactionIsolation('get account spool directory', '{"repeatable read", "serializable"}');
        SELECT * FROM GetDomain(sp_acdomain, TRUE, TRUE) AS (id INTEGER, name TEXT) INTO sp_domain_id, sp_acdomain;
        SELECT account.id, CONCAT (domain.spooldir, '/', account.spooldir) FROM account, domain INTO
            sp_acc_id, sp_spool_dir WHERE
            lower(account.name) = lower(sp_acname) AND account.active = TRUE AND
            domain.id = sp_domain_id AND
            domain.active = TRUE AND account.domain_id = sp_domain_id;
        IF (sp_acc_id IS NOT NULL AND sp_caller IN ('imap', 'pop')) THEN
			INSERT INTO activity_tracking(tab_name, row_id, oper_name) VALUES ('account', sp_acc_id, sp_caller);
	    END IF;
	    RETURN(sp_spool_dir);
    END;$$
    LANGUAGE plpgsql;

ALTER FUNCTION GetAccountSpoolDir(TEXT, client_proto) OWNER TO emailmgr_writer;
ALTER FUNCTION GetAccountSpoolDir(TEXT, client_proto) SECURITY DEFINER;


CREATE OR REPLACE FUNCTION GetFullSysName() RETURNS TEXT AS $$
    DECLARE
        sysname TEXT;
        vmajor TEXT;
        vminor TEXT;
        vpatch TEXT;
    BEGIN
        -- If we need to lock rows we need to have write privs. So we'll use repeatable read instead.
        PERFORM CheckTransactionIsolation( 'get system name', '{"repeatable read", "serializable"}');
        SELECT pvalue INTO sysname FROM sysinfo WHERE pname = 'sysname';
		SELECT pvalue INTO vmajor FROM sysinfo WHERE pname = 'vmajor';
		SELECT pvalue INTO vminor FROM sysinfo WHERE pname = 'vminor';
		SELECT pvalue INTO vpatch FROM sysinfo WHERE pname = 'vpatch';
		RETURN(LOWER(CONCAT_WS(':', sysname, vmajor, vminor, vpatch)));
	END;$$
	LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION GetApacheDigAuth(sp_name TEXT, sp_realm TEXT) RETURNS TEXT AS $$
    BEGIN
        RETURN
            (SELECT MD5(CONCAT(sp_name, ':', sp_realm, ':', account.password))
                FROM account, domain
		        WHERE domain.active = TRUE AND lower(account.name) = lower(sp_name) AND
		            lower(domain.name) = lower(sp_realm) AND
			        account.domain_id = domain.id AND account.active = TRUE);
	END;$$
	LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION sasl_getlogin(sp_name TEXT) RETURNS TEXT AS $$
    DECLARE
        sp_acname TEXT DEFAULT GetNamePart(sp_name, '@', 'name');
        sp_acdomain TEXT DEFAULT GetNamePart(sp_name, '@', 'domain');
        sp_defaultdomain TEXT DEFAULT (SELECT d.name FROM domain d, tab_defaults td WHERE td.tab_name = 'domain' AND
            d.id = td.tab_id);
		sp_logins TEXT DEFAULT NULL;
    BEGIN
        PERFORM CheckTransactionIsolation( 'get login for SASL', '{"repeatable read", "serializable"}');
        IF (sp_acname IS NULL OR sp_acdomain IS NULL) THEN
		    RETURN(NULL);
		END IF;
		SELECT CONCAT(account.name, '@', domain.name) INTO sp_logins
		    FROM account, domain
		    WHERE lower(account.name) = lower(sp_acname) AND account.active = TRUE AND
		        lower(domain.name) = lower(sp_acdomain) AND domain.active = TRUE AND
		        account.domain_id = domain.id;
		IF (sp_logins IS NOT NULL AND lower(sp_acdomain) = lower(sp_defaultdomain)) THEN
		    sp_logins = CONCAT(sp_logins, ',', GetNamePart(sp_logins, '@', 'name'));
	    END IF;
	    RETURN(sp_logins);
	END;$$
	LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION sasl_getpass(sp_name TEXT) RETURNS TEXT AS $$
    DECLARE
        sp_acname TEXT DEFAULT GetNamePart(sp_name, '@', 'name');
        sp_acdomain TEXT DEFAULT GetNamePart(sp_name, '@', 'domain');
    BEGIN
        PERFORM CheckTransactionIsolation('get password for SASL', '{"repeatable read", "serializable"}');
        IF (sp_acdomain IS NULL) THEN
            SELECT d.name INTO sp_acdomain FROM domain d, tab_defaults td WHERE
                td.tab_name = 'domain' AND d.id = td.tab_id;
		END IF;
		RETURN(SELECT CONCAT('PLAIN', password)
		    FROM account, domain
		    WHERE lower(account.name) = lower(sp_acname) AND lower(domain.name) = lower(sp_acdomain) AND
		        domain.active = TRUE AND account.domain_id = domain.id AND account.active = TRUE AND
		        account.password_enabled = TRUE);
    END;$$
    LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION GetDomainData(sp_name TEXT) RETURNS TABLE (name TEXT, spooldir TEXT, active BOOLEAN,
                    public BOOLEAN, ad_sync_enabled BOOLEAN, created TIMESTAMP(0) WITH TIME ZONE,
                    modified TIMESTAMP(0) WITH TIME ZONE) AS $$
    SELECT name, spooldir, active, public, ad_sync_enabled, created, modified
        FROM domain WHERE lower(name) LIKE CASE WHEN sp_name IS NOT NULL THEN lower(sp_name) ELSE '%' END ORDER BY name; $$
    LANGUAGE sql;


CREATE OR REPLACE FUNCTION GetAccountData(sp_domain TEXT, sp_name TEXT, sp_fullname TEXT) RETURNS TABLE (
                    name TEXT, password TEXT, fullname TEXT, spooldir TEXT, active BOOLEAN, public BOOLEAN,
                    password_enabled BOOLEAN, ad_sync_enabled BOOLEAN, created TIMESTAMP(0) WITH TIME ZONE,
                    modified TIMESTAMP(0) WITH TIME ZONE, accessed TIMESTAMP(0) WITH TIME ZONE) AS $$
    SELECT name, password, fullname, spooldir, active, public, password_enabled, ad_sync_enabled,
        created, modified, accessed
        FROM account, GetDomain(sp_domain, TRUE, TRUE) AS (d_id INTEGER, d_name TEXT)
        WHERE
            lower(name) LIKE CASE WHEN sp_name IS NOT NULL THEN lower(sp_name) ELSE '%' END AND
            CASE WHEN sp_fullname IS NOT NULL THEN lower(fullname) LIKE lower(sp_fullname) ELSE fullname LIKE '%' OR fullname IS NULL END AND
            domain_id = d_id
        ORDER BY name; $$
    LANGUAGE sql;


CREATE OR REPLACE FUNCTION VALUE_OR_DEFAULT(sp_var BOOLEAN) RETURNS TEXT AS $$
    BEGIN
        IF (sp_var IS NOT NULL) THEN
            IF (sp_var = TRUE) THEN
                RETURN('TRUE');
            ELSE
                RETURN('FALSE');
            END IF;
        ELSE
            RETURN('DEFAULT');
        END IF;
    END;$$
    LANGUAGE plpgsql;


CREATE EXTENSION "uuid-ossp";


CREATE OR REPLACE FUNCTION domain_add(sp_name TEXT, sp_active BOOLEAN, sp_public BOOLEAN) RETURNS VOID AS $$
    BEGIN
        LOCK TABLE domain IN SHARE ROW EXCLUSIVE MODE; -- We need locking because after checking for existence we have to rely on results of that check
		IF (EXISTS(SELECT * FROM domain WHERE lower(name) = lower(sp_name))) THEN
		    RAISE 'The domain % already exists', sp_name;
		END IF;
		EXECUTE FORMAT('INSERT INTO domain(name, spooldir, created, modified, active, public, ad_sync_enabled) '
                    'VALUES ($1, UUID_GENERATE_V1(), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, '
                    '%s, %s, FALSE)',  VALUE_OR_DEFAULT(sp_active), VALUE_OR_DEFAULT(sp_public)) USING sp_name;
	END;$$
	LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION domain_del(sp_name TEXT) RETURNS VOID AS $$
    BEGIN
		IF (NOT EXISTS(SELECT * FROM domain WHERE lower(name) = lower(sp_name) FOR UPDATE)) THEN
		    RAISE 'The domain % does not exist', sp_name;
		END IF;
		IF (EXISTS(SELECT * FROM tab_defaults, domain WHERE lower(domain.name) = lower(sp_name) AND
		    tab_defaults.tab_name = 'domain' AND tab_defaults.tab_id = domain.id)) THEN
		    RAISE 'The domain % is a default domain - may not be deleted', sp_name USING
		        HINT = 'Make some other domain default first';
		END IF;
		IF (EXISTS(SELECT * FROM account WHERE domain_id = (SELECT id FROM domain WHERE lower(name) = lower(sp_name)))) THEN
            RAISE 'The domain % still has linked accounts', sp_name USING
                HINT = 'Please delete all linked accounts one by one before deleting a domain';
		END IF;
		DELETE FROM domain WHERE lower(name) = lower(sp_name);
	END;$$
	LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION domain_mod(sp_name TEXT, sp_newname TEXT, sp_active BOOLEAN, sp_public BOOLEAN,
    sp_ad_sync_enabled BOOLEAN) RETURNS VOID AS $$
    DECLARE
        DECLARE old_name TEXT;
        DECLARE old_active BOOLEAN;
        DECLARE old_public BOOLEAN;
        DECLARE old_ad_sync_enabled BOOLEAN;
    BEGIN
        IF (num_nonnulls(sp_newname, sp_active, sp_public, sp_ad_sync_enabled) = 0) THEN
            RAISE 'Nothing to change';
		END IF;
		IF (NOT EXISTS(SELECT * FROM domain WHERE lower(name) = lower(sp_name) FOR UPDATE)) THEN
		    RAISE 'The domain % does not exist', sp_name;
		END IF;
		IF (lower(sp_name) <> lower(sp_newname) AND
		    EXISTS(SELECT * FROM domain WHERE lower(name) = lower(sp_newname))) THEN
		    RAISE 'The domain % already exists', sp_newname;
		END IF;
		SELECT name, active, public, ad_sync_enabled INTO old_name, old_active, old_public, old_ad_sync_enabled
			FROM domain WHERE lower(name) = lower(sp_name);
		UPDATE domain SET
			name = COALESCE(sp_newname, old_name),
			active = COALESCE(sp_active, old_active),
			public = COALESCE(sp_public, old_public),
			ad_sync_enabled = COALESCE(sp_ad_sync_enabled, old_ad_sync_enabled),
			modified = CURRENT_TIMESTAMP
			WHERE lower(name) = lower(sp_name);
    END;$$
    LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION account_add(sp_domain TEXT, sp_name TEXT, sp_password TEXT, sp_fullname TEXT,
    sp_active BOOLEAN, sp_public BOOLEAN) RETURNS VOID AS $$
    DECLARE
        sp_domain_id INTEGER DEFAULT NULL;
        sp_domain_name TEXT DEFAULT NULL;
    BEGIN
        SELECT * FROM GetDomain(sp_domain) AS (id INTEGER, name TEXT) INTO sp_domain_id, sp_domain_name;
        LOCK TABLE account IN SHARE ROW EXCLUSIVE MODE; -- We need locking because after checking for existence we have to rely on results of that check
        IF (EXISTS(SELECT * FROM account WHERE lower(name) = lower(sp_name) AND domain_id = sp_domain_id)) THEN
			RAISE 'The account %@% already exists', sp_name, sp_domain_name;
		END IF;
		EXECUTE FORMAT('INSERT INTO account(domain_id, name, password, fullname, spooldir, created, modified, active, public, '
		                    'password_enabled, ad_sync_enabled) '
			                'VALUES ($1, $2, $3, $4, '
				            'CONCAT(UUID_GENERATE_V1(), ''/''), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, '
				            '%s, %s, TRUE, FALSE)', VALUE_OR_DEFAULT(sp_active), VALUE_OR_DEFAULT(sp_public)) USING
				            sp_domain_id, sp_name, sp_password, sp_fullname;
	    END;$$
	    LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION account_del(sp_domain TEXT, sp_name TEXT) RETURNS VOID AS $$
    DECLARE
        sp_domain_id INTEGER DEFAULT NULL;
        sp_domain_name TEXT DEFAULT NULL;
    BEGIN
        SELECT * FROM GetDomain(sp_domain) AS (id INTEGER, name TEXT) INTO sp_domain_id, sp_domain_name;
		IF (NOT EXISTS(SELECT * FROM account WHERE lower(name) = lower(sp_name) AND
			domain_id = sp_domain_id FOR UPDATE)) THEN
			RAISE 'The account %@% does not exist', sp_name, sp_domain_name;
		END IF;
		DELETE FROM account WHERE lower(name) = lower(sp_name) AND
		    domain_id = sp_domain_id;
	END;$$
	LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION account_mod(sp_domain TEXT, sp_name TEXT, sp_newname TEXT, sp_password TEXT, sp_fullname TEXT,
                    sp_active BOOLEAN, sp_public BOOLEAN, sp_password_enabled BOOLEAN, sp_ad_sync_enabled BOOLEAN)
                    RETURNS VOID AS $$
    DECLARE
        old_name TEXT;
        old_password TEXT;
        old_fullname TEXT;
        old_active BOOLEAN;
        old_public BOOLEAN;
        old_password_enabled BOOLEAN;
        old_ad_sync_enabled BOOLEAN;
        old_ad_sync_required BOOLEAN;
        sp_domain_id INTEGER DEFAULT NULL;
        sp_domain_name TEXT DEFAULT NULL;
    BEGIN
        SELECT * FROM GetDomain(sp_domain) AS (id INTEGER, name TEXT) INTO sp_domain_id, sp_domain_name;
		IF (num_nonnulls(sp_newname, sp_password, sp_password_enabled, sp_fullname, sp_active, sp_public,
			sp_ad_sync_enabled) = 0) THEN
			RAISE 'Nothing to change';
		END IF;
		IF (NOT EXISTS(SELECT * FROM account WHERE lower(name) = lower(sp_name) AND
			domain_id = sp_domain_id FOR UPDATE)) THEN
			RAISE 'The account %@% does not exist', sp_name, sp_domain_name;
		END IF;
		IF (lower(sp_name) <> lower(sp_newname) AND EXISTS(SELECT * FROM account WHERE name = sp_newname AND
		    domain_id = sp_domain_id)) THEN
		    RAISE 'The account %@% already exists', sp_newname, sp_domain_name; -- Cannot rename to an existing one
		END IF;
		SELECT name, password, password_enabled, fullname, active, public, ad_sync_enabled, ad_sync_required
			INTO old_name, old_password, old_password_enabled, old_fullname, old_active, old_public,
				old_ad_sync_enabled, old_ad_sync_required
			FROM account WHERE lower(name) = lower(sp_name) AND domain_id = sp_domain_id;
		UPDATE account SET
			name = COALESCE(sp_newname, old_name),
			password = COALESCE(sp_password, old_password),
			fullname = COALESCE(sp_fullname, old_fullname),
			active = COALESCE(sp_active, old_active),
			public = COALESCE(sp_public, old_public),
			password_enabled = COALESCE(sp_password_enabled, old_password_enabled),
			ad_sync_enabled = COALESCE(sp_ad_sync_enabled, old_ad_sync_enabled),
			ad_sync_required = CASE
			    WHEN sp_ad_sync_enabled = TRUE AND sp_ad_sync_enabled <> old_ad_sync_enabled THEN TRUE
				ELSE old_ad_sync_required END,
			modified = CURRENT_TIMESTAMP
			WHERE name = sp_name AND domain_id = sp_domain_id;
	END;$$
	LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION alias_add(sp_name TEXT, sp_value TEXT, sp_fullname TEXT, sp_active BOOLEAN, sp_public BOOLEAN)
    RETURNS VOID AS $$
    DECLARE
        new_alias_name_created BOOLEAN DEFAULT FALSE;
    BEGIN
        LOCK TABLE alias_name, alias_value IN SHARE ROW EXCLUSIVE MODE;
		IF (EXISTS(SELECT * FROM alias_value WHERE lower(value) = lower(sp_value) AND name_id =
                (SELECT id FROM alias_name WHERE lower(name) = lower(sp_name)))) THEN
            RAISE 'The alias % referencing % already exists', sp_name, sp_value;
		END IF;
		IF (NOT EXISTS(SELECT * FROM alias_name WHERE lower(name) = lower(sp_name))) THEN
			EXECUTE FORMAT('INSERT INTO alias_name(name, fullname, created, modified, active, public) '
			    'VALUES ($1, $2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, %s, %s)',
			    VALUE_OR_DEFAULT(sp_active), VALUE_OR_DEFAULT(sp_public)) USING sp_name, sp_fullname;
			new_alias_name_created = TRUE;
		END IF;
		EXECUTE FORMAT('INSERT INTO alias_value(name_id, value, created, modified, active) '
		    'VALUES($1, $2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, %s)',
			CASE WHEN sp_active IS NOT NULL AND new_alias_name_created = FALSE THEN QUOTE_LITERAL(sp_active)
			    ELSE 'DEFAULT' END)
			USING (SELECT id FROM alias_name WHERE lower(name) = lower(sp_name)), sp_value;
    END;$$
    LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION alias_del(sp_name TEXT, sp_value TEXT) RETURNS VOID AS $$
    BEGIN
		IF (sp_value IS NULL) THEN
			IF (NOT EXISTS(SELECT * FROM alias_name WHERE lower(name) = lower(sp_name) FOR UPDATE)) THEN
				RAISE 'The alias % does not exist', sp_name;
			END IF;
			DELETE FROM alias_name WHERE lower(name) = lower(sp_name);
		ELSE
			IF (NOT EXISTS(SELECT * FROM alias_value WHERE lower(value) = lower(sp_value) AND
				name_id = (SELECT id FROM alias_name WHERE lower(name) = lower(sp_name) FOR UPDATE) FOR UPDATE)) THEN
				RAISE 'The alias % does not reference %', sp_name, sp_value;
			END IF;
			DELETE FROM alias_value WHERE lower(value) = lower(sp_value) AND name_id = (SELECT id FROM alias_name
				WHERE lower(name) = lower(sp_name));
			IF (NOT EXISTS(SELECT * FROM alias_value WHERE name_id = (SELECT id FROM alias_name
				WHERE lower(name) = lower(sp_name)))) THEN
				DELETE FROM alias_name WHERE lower(name) = lower(sp_name);
			END IF;
		END IF;
    END;$$
    LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION alias_mod(sp_name TEXT, sp_newname TEXT, sp_value TEXT, sp_newvalue TEXT, sp_fullname TEXT,
    sp_active BOOLEAN, sp_public BOOLEAN) RETURNS VOID AS $$
    DECLARE
        old_name TEXT;
        old_value TEXT;
        old_fullname TEXT;
        old_active BOOLEAN;
        old_public BOOLEAN;
    BEGIN
		IF (sp_value IS NULL) THEN
			IF (num_nonnulls(sp_newname, sp_fullname, sp_active, sp_public) = 0) THEN
				RAISE 'Nothing to change';
			END IF;
			IF (NOT EXISTS(SELECT * FROM alias_name WHERE lower(name) = lower(sp_name) FOR UPDATE)) THEN
				RAISE 'The alias % does not exist', sp_name;
			END IF;
			IF (lower(sp_name) <> lower(sp_newname) AND
			    EXISTS(SELECT * FROM alias_name WHERE lower(name) = lower(sp_newname))) THEN
                RAISE 'The alias % already exists', sp_newname;
			END IF;
			SELECT name, fullname, active, public INTO old_name, old_fullname, old_active, old_public
				FROM alias_name WHERE lower(name) = lower(sp_name);
			UPDATE alias_name SET
				name = COALESCE(sp_newname, old_name),
				fullname = COALESCE(sp_fullname, old_fullname),
				active = COALESCE(sp_active, old_active),
				public = COALESCE(sp_public, old_public),
				modified = CURRENT_TIMESTAMP
			    WHERE lower(name) = lower(sp_name);
	    ELSE
			IF (num_nonnulls(sp_newvalue, sp_active) = 0) THEN
				RAISE 'Nothing to change';
			END IF;
			IF (NOT EXISTS(SELECT * FROM alias_value WHERE lower(value) = lower(sp_value) AND
				name_id = (SELECT id FROM alias_name WHERE lower(name) = lower(sp_name) FOR SHARE) FOR UPDATE)) THEN
				RAISE 'The alias % referencing % does not exist', sp_name, sp_value;
			END IF;
			IF (lower(sp_value) <> lower(sp_newvalue) AND EXISTS(SELECT * FROM alias_value
				WHERE lower(value) = lower(sp_newvalue) AND name_id = (SELECT id FROM alias_name WHERE
				lower(name) = lower(sp_name)))) THEN
				RAISE 'The alias % already references %', sp_name, sp_newvalue;
			END IF;
			SELECT value, active INTO old_value, old_active FROM alias_value WHERE
				lower(value) = lower(sp_value) AND
				name_id = (SELECT id FROM alias_name WHERE lower(name) = lower(sp_name));
			UPDATE alias_value SET
				value = COALESCE(sp_newvalue, old_value),
				active = COALESCE(sp_active, old_active),
				modified = CURRENT_TIMESTAMP
			    WHERE lower(value) = lower(sp_value) AND
			    name_id = (SELECT id FROM alias_name WHERE lower(name) = lower(sp_name));
        END IF;
    END;$$
    LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION GetDefaultDomain() RETURNS TEXT AS $$
    SELECT name from domain, tab_defaults WHERE tab_name = 'domain' AND domain.id = tab_id; $$
    LANGUAGE sql;


CREATE OR REPLACE FUNCTION SetDefaultDomain(sp_name TEXT) RETURNS VOID AS $$
    BEGIN
        PERFORM CheckTransactionIsolation('set default domain', '{"repeatable read", "serializable"}');
        IF (NOT EXISTS(SELECT * FROM domain WHERE lower(name) = lower(sp_name))) THEN
            RAISE 'The domain % does not exist',sp_name;
        END IF;
        IF (EXISTS(SELECT * FROM tab_defaults WHERE tab_name = 'domain')) THEN
            UPDATE tab_defaults SET tab_id = (SELECT id FROM domain WHERE lower(name) = lower(sp_name)) WHERE
                tab_name = 'domain';
        ELSE
            INSERT INTO tab_defaults(tab_name, tab_id) VALUES
                ('domain', (SELECT id FROM domain WHERE lower(name) = lower(sp_name)));
        END IF;
    END;$$
    LANGUAGE plpgsql;



-- Populate table `sysinfo`
INSERT INTO sysinfo(pname, pvalue) VALUES('sysname', 'emailmgr');
INSERT INTO sysinfo(pname, pvalue) VALUES('vmajor', '1');
INSERT INTO sysinfo(pname, pvalue) VALUES('vminor', '0');
INSERT INTO sysinfo(pname, pvalue) VALUES('vpatch', '0');

-- Populate table `tab_defaults`
SELECT domain_add('testdomain.org', TRUE, TRUE);
INSERT INTO tab_defaults(tab_name, tab_id) VALUES('domain', (SELECT MIN(id) FROM domain));


-- It seems that CONNECT and TEMPLATE are granted to PUBLIC by default
--GRANT CONNECT ON DATABASE emailmgr TO emailmgr_writer, emailmgr_reader;

-- We don't want for PUBLIC to create objects
REVOKE CREATE ON SCHEMA PUBLIC FROM PUBLIC;

-- Security policy will be simple. Writers can read and write, and readers can only read
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO emailmgr_writer;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO emailmgr_reader;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO emailmgr_writer;

-- And we finally add two accounts for a client and a manager
DROP ROLE IF EXISTS emailmgr_manager, emailmgr_client;
CREATE ROLE emailmgr_manager WITH LOGIN PASSWORD 'emailmgr_manager' IN ROLE emailmgr_writer;
CREATE ROLE emailmgr_client WITH LOGIN PASSWORD 'emailmgr_client' IN ROLE emailmgr_reader;
