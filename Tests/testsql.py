
import argparse, sys, os.path, psycopg2

cmdlnparser = argparse.ArgumentParser(description="Get users from DB")
cmdlnparser.add_argument("--dbhost", help="DB connection host")
cmdlnparser.add_argument("--dbname", help="DB name")
cmdlnparser.add_argument("--user", help="DB user")
cmdlnparser.add_argument("--password", help="DB user password")
cmdlnparser.add_argument("--domain", help="Email domain to operate with")
cmdlargs = cmdlnparser.parse_args()

dbconn = psycopg2.connect(host = cmdlargs.dbhost, database = cmdlargs.dbname, user = cmdlargs.user,
                          password = cmdlargs.password, application_name = os.path.basename(sys.argv[0]))
dbcur = dbconn.cursor()