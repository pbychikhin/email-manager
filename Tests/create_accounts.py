

import argparse

cmdlnparser = argparse.ArgumentParser(description="Create some random accounts in the email DB")
cmdlnparser.add_argument("--dbhost", help = "DB connection host")
cmdlnparser.add_argument("--dbname", help = "DB name")
cmdlnparser.add_argument("--user", help = "DB user")
cmdlnparser.add_argument("--password", help = "DB user password")
cmdlnparser.add_argument("--domain", help = "Email domain to operate with")
cmdlnparser.add_argument("--num", help="Number of accounts to be created", type=int, default=100)
cmdlargs = cmdlnparser.parse_args()

import sys
import psycopg2

dbconn = psycopg2.connect(host = cmdlargs.dbhost, database = cmdlargs.dbname, user = cmdlargs.user,
                          password = cmdlargs.password)
dbcur = dbconn.cursor()
print "Cleaning up..."
try:
    print "Deleting accounts..."
    dbcur.execute("SELECT * FROM domain WHERE name = %s", (cmdlargs.domain,))
    dbcur2 = dbconn.cursor()
    if dbcur.rowcount:
        dbcur.execute("SELECT account.name FROM account, domain WHERE domain.name = %s AND account.domain_id = domain.id",
                      (cmdlargs.domain,))
        for acname in dbcur:
            print("Deleting {}".format(acname[0]))
            dbcur2.callproc("account_del", (cmdlargs.domain, acname[0],))
        print("Deleting domain {}".format(cmdlargs.domain))
        dbcur.callproc("domain_del", (cmdlargs.domain,))
    dbcur2.close()
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
finally:
    dbcur.close()


import petname

pets = {}

for i in range(cmdlargs.num):
    mypet = petname.Generate(2, ".").split(".")
    pets[".".join(mypet)] = " ".join((mypet[0].capitalize(), mypet[1].capitalize()))
print "Inserting data..."
dbcur = dbconn.cursor()
try:
    print "Adding domain {}...".format(cmdlargs.domain)
    dbcur.callproc("domain_add", (cmdlargs.domain, None, None,))
    print "Adding accounts..."
    for petshortname, petfullname in pets.items():
        print "Adding ", petfullname
        dbcur.callproc("account_add", (cmdlargs.domain, petshortname, petshortname, petfullname, None, None,))
except psycopg2.Error as pgexcept:
    if pgexcept.pgcode == "P0001":
        print "Error interacting with data"
        print pgexcept.diag.message_primary
        if pgexcept.diag.message_hint:
            print "Hint: ", pgexcept.diag.message_hint
    else:
        raise
else:
    dbconn.commit()
finally:
    dbcur.close()

dbconn.close()
