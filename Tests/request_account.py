
import argparse

cmdlnparser = argparse.ArgumentParser(description="Request account's data in a random (msec) interval")
cmdlnparser.add_argument("--dbhost", help = "DB connection host")
cmdlnparser.add_argument("--dbname", help = "DB name")
cmdlnparser.add_argument("--user", help = "DB user")
cmdlnparser.add_argument("--password", help = "DB user password")
cmdlnparser.add_argument("--domain", help = "Email domain to operate with")
cmdlargs = cmdlnparser.parse_args()

import sys
import os.path
import time
import psycopg2

import random
from random import randint
random.seed()

dbconn = psycopg2.connect(host = cmdlargs.dbhost, database = cmdlargs.dbname, user = cmdlargs.user,
                          password = cmdlargs.password, application_name = os.path.basename(sys.argv[0]))
dbcur = dbconn.cursor()
print "Start requesting..."
try:
    while True:
        print "It's time to request..."
        try:
            print "Retrieving accounts..."
            dbcur.execute("SELECT account.name FROM account, domain WHERE domain.name = %s AND account.domain_id = domain.id",
                          (cmdlargs.domain,))
            accounts = dbcur.fetchall()
            dbconn.commit()
            account = "@".join((accounts[randint(0, len(accounts) - 1)][0], cmdlargs.domain))
            dbcur.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
            dbcur.callproc("GetAccountSpoolDir", (account, "imap",))
            accdata = dbcur.fetchone()[0]
            dbconn.commit()
            print("{}'s data is {}".format(account, accdata,))
        except psycopg2.Error as pgexcept:
            if pgexcept.pgcode == "P0001":
                print "Error interacting with data"
                print pgexcept.diag.message_primary
                if pgexcept.diag.message_hint:
                    print "Hint: ", pgexcept.diag.message_hint
                sys.exit(1)
            else:
                raise
        time.sleep(randint(1, 1000) / 1000.0)
finally:
    dbcur.close()
    dbconn.close()
