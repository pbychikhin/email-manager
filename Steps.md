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
    * Write out a doc, 'DB_func_ref.md', describing stored functions

* Create test scripts
    * Create load test suite:
        * Create `create_accounts.py`. This will randomly create N-account in the DB.  
        Names have to be human readable. N-number has to be specified as an option.
    * Create `testldap.py`
        * Get user data from AD
        * Represent user data using table and record views
    * Create `testsql.py`
        * Get user data from DB
        * Represent user data using table and record views