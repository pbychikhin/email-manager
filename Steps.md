# Steps of the project

* Deploy the AD
    * **\[done\]** Deploy first Windows standard server
    * **\[done\]** Deploy second Windows standard server
    * **\[done\]** Promote the first host to an AD controller
    * **\[done\]** Promote the second host to a second AD controller in the existing forest

* Deploy a database host and email server
    * **\[done\]** Deploy Linux CentOS
    * **\[done\]** Install Postgres
    * **\[done\]** Install MySQL
    * **\[done\]** Install Postfix
    * **\[done\]** Install Dovecot
    
* Create the database `emailmgr`
    * **\[done\]** Re-create an SQL script for Postgres based on the dump from the MySQL `emailmgr` schema
    * **\[done\]** Add creation of roles `reader` and `writer` to read and write the DB data over procedures
    * **\[done\]** Add creation of permissions for `reader` and `writer` to corresponding procedures
    * **\[done\]** Under `root` user, run the script and create the DB
    * **\[done\]** In the DB server, create the `emailmgr` user and grant him the `writer` role
    * **\[done\]** Write out a doc, 'DB_func_ref.md', describing stored functions

* Create test scripts
    * Create load test suite:
        * **\[done\]** Create `create_accounts.py`. This will randomly create N-account in the DB.
        Names have to be human readable. N-number has to be specified as an option.
        * **\[done\]** Create `request_account.py`. This will retrieve a full list of accounts in a specified domain.
        This will then request the spool directiory of a randomly chosen account.
        Operations will be performed in randomly chosen intervals between 0.1 and 1 sec.
        All errors will be reported.
        * **\[done\]** Create `manipulate_account.py`. This will retrieve a full list of accounts in a specified domain.
        This will then add/delete/modify a randomly chosen account.
        Operations will be performed in randomly chosen intervals between 0.1 and 1 sec.
        All errors will be reported.
        * **\[done\]** Create `flush_tracking.py`. This will flush activity tracking stamps (run UpdateAccountActivity()) once per specified time interval.
        All errors will be reported.
    * **\[done\]** Create `testldap.py`. This will get user data from AD and represent it using table and record views
    * **\[done\]** Create `testsql.py`. This will get user data from DB and represent using table and record views

* Create the application
    * Create the library `libemailmgr.py`
        * **\[done\]** Add base exception handler class `EmailmgrBaseExceptionHandler`
        * **\[done\]** Add generic Postgres exception handler class `PgGenericExceptionHandler` based on the `EmailmgrBaseExceptionHandler`
        * **\[done\]** Add generic LDAP exception handler class `LdapGenericExceptionHandler` based on the `EmailmgrBaseExceptionHandler`
        * **\[done\]** Define INI-file name as `emailmgr.ini`
    * Create the main app `emailmgr.py`
        * Read INI-file.
        * Read cmd options: first option defines a working context (plugin name), other options are sent to the plugin.
        * Call a plugin: create a plugin_class instance, call a process_function, catch an exception
    * Create the plugins: `domain`, `account`, `alias`. Implement plugin interface as follows:
        * plugin_class(ini_data, cmd_data).
        * plugin_class.process_function.
        * plugin_class.exception