# Stored routines reference


## Data query

* _GetAccountSpoolDir(sp_name TEXT, sp_caller client_proto) RETURNS TEXT_  
`sp_name` is an email address. It can be given with or without a domain part. If one is absent, it will be added automatically.  
`sp_caller` is a caller protocol. It can be any of 'smtp', 'pop', 'imap'.  
Requires at least repeatable read isolation level.  
Returns a relative path to an account maildir (or NULL).

* _GetFullSysName() RETURNS TEXT_  
Requires at least repeatable read isolation level.  
Returns concatenated system name, major ver., minor ver., patch ver., separated by ':'.

* _GetApacheDigAuth(sp_name TEXT, sp_realm TEXT) RETURNS TEXT_  
`sp_name` is a name part from email address.  
`sp_realm` is a domain part from email address.  
Returns an MD5-encoded string (or NULL) constructed from both parameters and account password, the one which can be later used in HTTP digest auth.

* _sasl_getlogin(sp_name TEXT) RETURNS TEXT_  
`sp_name` is an email address. It can be given with or without a domain part. If one is absent, it will be added automatically.  
Requires at least repeatable read isolation level.  
Returns a string (or NULL) of login names for postfix when it's checking for matching the SASL login and MAIL FROM.

* _sasl_getpass(sp_name TEXT) RETURNS TEXT_  
`sp_name` is an email address. It can be given with or without a domain part. If one is absent, it will be added automatically.  
Requires at least repeatable read isolation level.  
Returns an account password (or NULL) in clear text for SASL auth.


## Utility

* _GetNamePart(sp_name TEXT, sp_delim TEXT, sp_partname TEXT) RETURNS TEXT_  
`sp_name` is an email address.  
`sp_delim` is a delimiter. For email addresses, this is '@' symbol.  
`sp_partname` is the name of the part. Can be any of 'name', 'domain'.  
Returns a name or domain part of an email address (or NULL).

* _CheckTransactionIsolation(sp_action_name TEXT, sp_levels_allowed TEXT[]) RETURNS VOID_  
`sp_action_name` is a string describing the action is being performed so the control process can get sensible diagnostic message.  
`sp_levels_allowed` is an array or isolation levels allowed.  
Does not return.  
Raises an exception with hint which has to be caught by the control process.

* _GetDomain(sp_domain TEXT, sp_isolated BOOLEAN DEFAULT FALSE, sp_silent BOOLEAN DEFAULT FALSE) RETURNS RECORD_  
`sp_domain` is a domain name. Can be NULL. In this case the default will be looked up.  
`sp_isolated` is a flag indicating that the query shall run with at least repeatable read isolation level.  
`sp_silent` is a flag indication that the routing shall not raise exceptions in case it can't find data.  
Both `sp_isolated` and `sp_silent` default to FALSE which means the routine sets up explicit locks and raises exceptions. So it is convenient for data changing utilities.  
Returns a record of an integer domain ID and a textual domain name. Both default to NULL.  
May rise an exception with hint which has to be caught by the control process.

* _VALUE_OR_DEFAULT(sp_var BOOLEAN) RETURNS TEXT_  
`sp_var` - a boolean var which can either be null or not null.  
Returns a string which can either be 'TRUE' or 'FALSE' in case sp_var isn't NULL, or 'NULL' otherwise.  
The use of this proc is arguable. It's just a shortcut for CASE ... WHEN ... THEN ...


## Miscellaneous

* _UpdateAccountActivity() RETURNS VOID_  
Updates account's `accessed` field and clears activity_tracking.  
Should be called by a scheduler reasonably frequently so the tracking table will not inflate.  
Does not return.
