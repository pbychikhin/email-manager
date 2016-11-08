
import argparse, sys, os.path, psycopg2, traceback

cmdlnparser = argparse.ArgumentParser(description="Get users from DB")
cmdlnparser.add_argument("--dbhost", help="DB connection host")
cmdlnparser.add_argument("--dbname", help="DB name")
cmdlnparser.add_argument("--user", help="DB user")
cmdlnparser.add_argument("--password", help="DB user password")
cmdlnparser.add_argument("--domain", help="Email domain to operate with")
cmdlargs = cmdlnparser.parse_args()


class PgBaseExceptionHandler:

    def __init__(self, print_traceback=True, do_exit=False):
        self.print_traceback = print_traceback
        self.do_exit = do_exit
        self.do_reraise = False

    def __call__(self, pg_exception_info, print_traceback=None, do_exit=None):
        """pg_exception_info is a sys.exc_info() return value"""
        if print_traceback is not None:
            self.print_traceback = print_traceback
        if do_exit is not None:
            self.do_exit = do_exit
        self.handler(pg_exception_info)
        if self.do_reraise:
            raise
        elif self.do_exit:
            sys.exit(1)

    def handler(self, pg_exception_info):
        self.do_reraise = True


class PgGenericExceptionHandler(PgBaseExceptionHandler):

    def handler(self, pg_exception_info):
        pg_ex_obj, pg_ex_traceback = pg_exception_info[1:3]
        if pg_ex_obj.diag.message_primary:
            print >>sys.stderr, pg_ex_obj.diag.message_primary
            if pg_ex_obj.diag.message_hint:
                print >>sys.stderr, "Hint: ", pg_ex_obj.diag.message_hint
        else:
            print >> sys.stderr, pg_ex_obj.args[0]
        if self.print_traceback:
            print >> sys.stderr, "Occurred at:"
            traceback.print_tb(pg_ex_traceback, limit=1)


handle_pg_exception = PgGenericExceptionHandler(do_exit=True)

dbconn = None
try:
    dbconn = psycopg2.connect(host = cmdlargs.dbhost, database = cmdlargs.dbname, user = cmdlargs.user,
                              password = cmdlargs.password, application_name = os.path.basename(sys.argv[0]))
except psycopg2.Error as pgex:
    handle_pg_exception(sys.exc_info())
dbcur = dbconn.cursor()

accounts_header = ()  # get rid of warnings
accounts_data = []  # get rid of warnings
try:
    dbcur.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
    dbcur.execute("SELECT * FROM GetAccountData(%s, %s, %s)", (cmdlargs.domain, None, None))
    accounts_header = tuple(item[0] for item in dbcur.description)
    accounts_data = dbcur.fetchall()
    dbconn.commit()
except psycopg2.Error as pgex:
    handle_pg_exception(sys.exc_info())

attr_len = max(map(len, accounts_header))
for item in accounts_data:
    account = dict(zip(accounts_header, item))
    for attr in accounts_header:
        print ("{:>" + str(attr_len) + "}: {}").format(attr, account[attr])
    print
