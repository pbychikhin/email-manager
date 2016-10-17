
import argparse

cmdlnparser = argparse.ArgumentParser(description="Flush activity tracking stamps")
cmdlnparser.add_argument("--dbhost", help = "DB connection host")
cmdlnparser.add_argument("--dbname", help = "DB name")
cmdlnparser.add_argument("--user", help = "DB user")
cmdlnparser.add_argument("--password", help = "DB user password")
cmdlnparser.add_argument("--tick", help = "Run interval in seconds")
cmdlargs = cmdlnparser.parse_args()

import sys
import time
import psycopg2

dbconn = psycopg2.connect(host = cmdlargs.dbhost, database = cmdlargs.dbname, user = cmdlargs.user,
                          password = cmdlargs.password)
dbcur = dbconn.cursor()
try:
    while True:
        print "It's time to flush... ",
        try:
            dbcur.callproc("UpdateAccountActivity")
            print "{} row(s) affected".format(dbcur.rowcount)
        except psycopg2.Error as pgexcept:
            if pgexcept.pgcode == "P0001":
                print "Error interacting with data"
                print pgexcept.diag.message_primary
                if pgexcept.diag.message_hint:
                    print "Hint: ", pgexcept.diag.message_hint
                sys.exit(1)
            else:
                raise
        else:
            dbconn.commit()
        time.sleep(float(cmdlargs.tick))
finally:
    dbcur.close()
    dbconn.close()
