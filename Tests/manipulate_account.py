
import argparse, sys, os.path, time, psycopg2, random, petname, string

cmdlnparser = argparse.ArgumentParser(description=
                                      "Manipulate (add/delete/modify) account's data in a random (msec) interval")
cmdlnparser.add_argument("--dbhost", help="DB connection host")
cmdlnparser.add_argument("--dbname", help="DB name")
cmdlnparser.add_argument("--user", help="DB user")
cmdlnparser.add_argument("--password", help="DB user password")
cmdlnparser.add_argument("--domain", help="Email domain to operate with")
cmdlargs = cmdlnparser.parse_args()

random.seed()

manip_types = ("add", "delete", "modify")
mod_types = ("rename", "password", "active", "public")
alphabet = string.ascii_letters + string.digits

dbconn = psycopg2.connect(host = cmdlargs.dbhost, database = cmdlargs.dbname, user = cmdlargs.user,
                          password = cmdlargs.password, application_name = os.path.basename(sys.argv[0]))
dbcur = dbconn.cursor()
print "Start manipulating..."
try:
    while True:
        print "\nIt's time to manipulate..."
        try:
            print "Retrieving accounts"
            dbcur.execute("SELECT account.name FROM account, domain WHERE domain.name = %s AND account.domain_id = domain.id",
                          (cmdlargs.domain,))
            accounts = dbcur.fetchall()
            account = random.choice(accounts)[0]
            dbconn.commit()
            manip_type = random.choice(manip_types)
            mod_type = random.choice(mod_types)
            pet = petname.Generate(2, ".")
            (petfirstname, petlastname) = pet.split(".")
            if manip_type == "add":
                print "Adding account {}".format("@".join((pet, cmdlargs.domain)))
                dbcur.callproc("account_add", (cmdlargs.domain, pet, pet,
                                               " ".join((petfirstname.capitalize(), petlastname.capitalize())),
                                               None, None))
            elif manip_type == "delete":
                print "Deleting account {}".format("@".join((account, cmdlargs.domain)))
                dbcur.callproc("account_del", (cmdlargs.domain, account))
            elif manip_type == "modify":
                print "Modifying account {}: ".format("@".join((account, cmdlargs.domain))),
                if mod_type == "rename":
                    print "renaming"
                    dbcur.callproc("account_mod", (cmdlargs.domain, account, pet, None,
                                                   " ".join((petfirstname.capitalize(), petlastname.capitalize())),
                                                   None, None, None, None))
                elif mod_type == "password":
                    print "changing password"
                    password = ''.join(random.choice(alphabet) for _ in range(8))
                    dbcur.callproc("account_mod", (cmdlargs.domain, account, None, password, None, None, None,
                                                   None, None))
                elif mod_type == "active":
                    print "(de)activating"
                    dbcur.callproc("account_mod", (cmdlargs.domain, account, None, None, None,
                                                   random.choice((True, False)), None, None, None))
                elif mod_type == "public":
                    print "(un)publishing"
                    dbcur.callproc("account_mod", (cmdlargs.domain, account, None, None, None, None,
                                                   random.choice((True, False)), None, None))
            dbconn.commit()
        except psycopg2.Error as pgexcept:
            if pgexcept.pgcode == "P0001":
                print "Error interacting with data"
                print pgexcept.diag.message_primary
                if pgexcept.diag.message_hint:
                    print "Hint: ", pgexcept.diag.message_hint
                dbconn.commit()
                time.sleep(5.0)
            else:
                raise
        time.sleep(random.randint(1, 1000) / 1000.0)
finally:
    dbcur.close()
    dbconn.close()
