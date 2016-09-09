# Steps of the project

* Deploy the AD
    * Deploy Windows standard server
    * Clone it so there will be more than one AD host
    * Promote the first host to an AD controller
    * Promote the second host to a second AD controller in the existing forest

* Deploy a database host and email server
    * Deploy Linux CentOS
    * Install Postgres
    * Install Postfix
    * Install Dovecot

* Create the database `emailmgr`
    * Re-create an SQL script for Postgres based on the dump from the MySQL `emailmgr` schema
    * Add creation of roles `reader` and `writer` to read and write the DB data over procedures
    * Add creation of permissions for `reader` and `writer` to corresponding procedures
    * Under `root` user, run the script and create the DB
    * In the DB server, create the `emailmgr` user and grant him the `writer` role

* Create test scripts
    * Create `testldap.py`
        * Get user data from AD
        * Represent user data using table and record views
    * Create `testsql.py`
        * Get user data from DB
        * Represent user data using table and record views