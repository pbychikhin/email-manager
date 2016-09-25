
CREATE DATABASE emailmgr ENCODING = 'UTF8' LC_COLLATE = 'en_US.UTF-8' LC_CTYPE = 'en_US.UTF-8';


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
	fullname TEXT DEFAULT NULL,
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


CREATE FUNCTION GetNamePart(sp_name TEXT, sp_delim TEXT, sp_partname TEXT) RETURNS TEXT AS $$
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


CREATE TYPE client_proto AS ENUM ('smtp', 'pop', 'imap');

CREATE FUNCTION GetAccountSpoolDir(sp_name TEXT, sp_caller client_proto) RETURNS TEXT AS $$
    DECLARE
        sp_acname TEXT DEFAULT GetNamePart(sp_name, '@', 'name');
        sp_acdomain TEXT DEFAULT GetNamePart(sp_name, '@', 'domain');
    BEGIN
        IF (sp_acdomain IS NULL) THEN
            SELECT name FROM domain INTO sp_acdomain WHERE id = (SELECT tab_id FROM tab_defaults WHERE tab_name = 'domain') FOR SHARE;
        END IF;
        IF (sp_caller = 'pop' OR sp_caller = 'imap') THEN
            UPDATE account SET accessed = CURRENT_TIMESTAMP WHERE lower(name) = lower(sp_acname) AND active = TRUE AND
			    domain_id = (SELECT id FROM domain WHERE lower(name) = lower(sp_acdomain) AND active = TRUE);
	    END IF;
	    RETURN
	        (SELECT CONCAT(domain.spooldir, '/', account.spooldir)
	            FROM account, domain
		        WHERE lower(account.name) = lower(sp_acname) AND account.active = TRUE AND lower(domain.name) = lower(sp_acdomain) AND
		            domain.active = TRUE AND account.domain_id = domain.id);
    END;$$
    LANGUAGE plpgsql;


CREATE FUNCTION GetFullSysName() RETURNS TEXT AS $$
    DECLARE
        sysname TEXT;
        vmajor TEXT;
        vminor TEXT;
        vpatch TEXT;
    BEGIN
        LOCK TABLE sysinfo IN SHARE MODE; -- We do need a shared lock here coz we're selecting several rows from a table
        SELECT pvalue INTO sysname FROM sysinfo WHERE pname = 'sysname';
		SELECT pvalue INTO vmajor FROM sysinfo WHERE pname = 'vmajor';
		SELECT pvalue INTO vminor FROM sysinfo WHERE pname = 'vminor';
		SELECT pvalue INTO vpatch FROM sysinfo WHERE pname = 'vpatch';
		RETURN(LOWER(CONCAT(sysname, ':', vmajor, ':', vminor, ':', vpatch)));
	END;$$
	LANGUAGE plpgsql;


CREATE FUNCTION GetApacheDigAuth(sp_name TEXT, sp_realm TEXT) RETURNS TEXT AS $$
    BEGIN
        RETURN
            (SELECT MD5(CONCAT(sp_name, ':', sp_realm, ':', account.password))
                FROM account, domain
		        WHERE domain.active = TRUE AND lower(account.name) = lower(sp_name) AND
		            lower(domain.name) = lower(sp_realm) AND
			        account.domain_id = domain.id AND account.active = TRUE);
	END;$$
	LANGUAGE plpgsql;


CREATE FUNCTION sasl_getlogin(sp_name TEXT) RETURNS TEXT AS $$
    DECLARE
        sp_acname TEXT DEFAULT GetNamePart(sp_name, '@', 'name');
        sp_acdomain TEXT DEFAULT GetNamePart(sp_name, '@', 'domain');
        sp_defaultdomain TEXT DEFAULT (SELECT name FROM domain WHERE id = (SELECT tab_id
		    FROM tab_defaults WHERE tab_name = 'domain') FOR SHARE);
		sp_logins TEXT DEFAULT NULL;
    BEGIN
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


CREATE FUNCTION sasl_getpass(sp_name TEXT) RETURNS TEXT AS $$
    DECLARE
        sp_acname TEXT DEFAULT GetNamePart(sp_name, '@', 'name');
        sp_acdomain TEXT DEFAULT GetNamePart(sp_name, '@', 'domain');
    BEGIN
        IF (sp_acdomain IS NULL) THEN
        	SELECT name INTO sp_acdomain
		        FROM domain
		        WHERE id = (SELECT tab_id FROM tab_defaults WHERE tab_name = 'domain') FOR SHARE;
		END IF;
		RETURN(SELECT CONCAT('PLAIN', password)
		    FROM account, domain
		    WHERE lower(account.name) = lower(sp_acname) AND lower(domain.name) = lower(sp_acdomain) AND
		        domain.active = TRUE AND account.domain_id = domain.id AND account.active = TRUE AND
		        account.password_enabled = TRUE);
    END;$$
    LANGUAGE plpgsql;


CREATE FUNCTION VALUE_OR_DEFAULT(sp_var BOOLEAN) RETURNS TEXT AS $$
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


CREATE FUNCTION GetDomain(sp_domain TEXT) RETURNS RECORD AS $$
    DECLARE
        sp_domain_id INTEGER DEFAULT NULL;
        sp_domain_name TEXT DEFAULT NULL;
    BEGIN
        IF (sp_domain IS NULL) THEN
            SELECT d.id, d.name INTO sp_domain_id, sp_domain_name FROM tab_defaults td, domain d
                WHERE td.tab_name = 'domain' AND d.id = td.tab_id FOR SHARE OF d;
            IF (sp_domain_id IS NULL) THEN
                RAISE 'Domain isn''t specified (no default exists)' USING
                    HINT = 'Please set up a default domain in `tab_defaults`';
            END IF;
        ELSE
            SELECT d.id, d.name INTO sp_domain_id, sp_domain_name FROM domain d WHERE
                lower(name) = lower(sp_domain) FOR SHARE;
            IF (sp_domain_id IS NULL) THEN
                RAISE 'Domain % not found', sp_domain;
            END IF;
        END IF;
        IF (lower(sp_domain) = lower(sp_domain_name)) THEN
            sp_domain_name = sp_domain; -- We should not change the string case when it is returned to a user
        END IF;
        RETURN(sp_domain_id, sp_domain_name);
    END;$$
    LANGUAGE plpgsql;


CREATE EXTENSION "uuid-ossp";


CREATE FUNCTION domain_add(sp_name TEXT, sp_active BOOLEAN, sp_public BOOLEAN) RETURNS VOID AS $$
    BEGIN
        LOCK TABLE domain IN SHARE ROW EXCLUSIVE MODE; -- We need locking because after checking for existence we have to rely on results of that check
		IF (EXISTS(SELECT * FROM domain WHERE lower(name) = lower(sp_name))) THEN
		    RAISE 'The domain % already exists', sp_name;
		END IF;
		EXECUTE FORMAT('INSERT INTO domain(name, spooldir, created, modified, active, public, ad_sync_enabled) '
                    'VALUES ($1, UUID_GENERATE_V1(), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, '
                    '%s, %s, FALSE);',  VALUE_OR_DEFAULT(sp_active), VALUE_OR_DEFAULT(sp_public)) USING sp_name;
	END;$$
	LANGUAGE plpgsql;


CREATE FUNCTION domain_del(sp_name TEXT) RETURNS VOID AS $$
    BEGIN
		IF (NOT EXISTS(SELECT * FROM domain WHERE lower(name) = lower(sp_name) FOR UPDATE)) THEN
		    RAISE 'The domain % does not exist', sp_name;
		END IF;
		IF (EXISTS(SELECT * FROM account WHERE domain_id = (SELECT id FROM domain WHERE lower(name) = lower(sp_name)))) THEN
            RAISE 'The domain % still has linked accounts', sp_name USING
                HINT = 'Please delete all linked accounts one by one before deleting a domain';
		END IF;
		DELETE FROM domain WHERE lower(name) = lower(sp_name);
	END;$$
	LANGUAGE plpgsql;


CREATE FUNCTION domain_mod(sp_name TEXT, sp_newname TEXT, sp_active BOOLEAN, sp_public BOOLEAN,
    sp_ad_sync_enabled BOOLEAN) RETURNS VOID AS $$
    DECLARE
        DECLARE old_name TEXT;
        DECLARE old_active BOOLEAN;
        DECLARE old_public BOOLEAN;
        DECLARE old_ad_sync_enabled BOOLEAN;
    BEGIN
        IF (COALESCE(sp_newname, sp_active, sp_public, sp_ad_sync_enabled) IS NULL) THEN
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


CREATE FUNCTION account_add(sp_domain TEXT, sp_name TEXT, sp_password TEXT, sp_fullname TEXT,
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
				            '%s, %s, TRUE, FALSE);', VALUE_OR_DEFAULT(sp_active), VALUE_OR_DEFAULT(sp_public)) USING
				            sp_domain_id, sp_name, sp_password, sp_fullname;
	    END;$$
	    LANGUAGE plpgsql;


CREATE FUNCTION account_del(sp_domain TEXT, sp_name TEXT) RETURNS VOID AS $$
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


CREATE FUNCTION account_mod(sp_domain TEXT, sp_name TEXT, sp_newname TEXT, sp_password TEXT, sp_fullname TEXT,
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
		IF (COALESCE(sp_newname, sp_password, sp_password_enabled, sp_fullname, sp_active, sp_public,
			sp_ad_sync_enabled) IS NULL) THEN
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
			WHERE name = sp_name AND domain_id = (SELECT id FROM domain WHERE name = sp_domain);
	END;$$
	LANGUAGE plpgsql;


CREATE FUNCTION alias_add(sp_name TEXT, sp_value TEXT, sp_fullname TEXT, sp_active BOOLEAN, sp_public BOOLEAN)
    RETURNS VOID AS $$
    DECLARE
        new_alias_name_created BOOLEAN DEFAULT FALSE;
    BEGIN
        LOCK TABLE alias_name, alias_value IN SHARE ROW EXCLUSIVE MODE;
		IF (EXISTS(SELECT * FROM alias_value WHERE lower(value) = lower(sp_value) AND name_id =
                (SELECT id FROM alias_name WHERE lower(name) = lower(sp_name)))) THEN
            RAISE 'An alias % for name % already exists', sp_name, sp_value;
		END IF;
		IF (NOT EXISTS(SELECT * FROM alias_name WHERE name = sp_name)) THEN
			EXECUTE FORMAT('INSERT INTO alias_name(name, fullname, created, modified, active, public) '
			    'VALUES ($1, $2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, %s, %s);',
			    VALUE_OR_DEFAULT(sp_active), VALUE_OR_DEFAULT(sp_public)) USING sp_name, sp_fullname;
			new_alias_name_created = TRUE;
		END IF;
		EXECUTE FORMAT('INSERT INTO alias_value(name_id, value, created, modified, active) '
		    'VALUES($1, $2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, %s);',
			CASE WHEN sp_active IS NOT NULL AND new_alias_name_created = FALSE THEN QUOTE_LITERAL(sp_active)
			    ELSE 'DEFAULT' END)
			USING (SELECT id FROM alias_name WHERE lower(name) = lower(sp_name)), sp_value;
    END;$$
    LANGUAGE plpgsql;
