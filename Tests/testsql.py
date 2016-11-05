
import argparse, sys, os.path, psycopg2, traceback

cmdlnparser = argparse.ArgumentParser(description="Get users from DB")
cmdlnparser.add_argument("--dbhost", help="DB connection host")
cmdlnparser.add_argument("--dbname", help="DB name")
cmdlnparser.add_argument("--user", help="DB user")
cmdlnparser.add_argument("--password", help="DB user password")
cmdlnparser.add_argument("--domain", help="Email domain to operate with")
cmdlargs = cmdlnparser.parse_args()


class PgExceptionHandler:

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
        pass


class PgUserExceptionHandler(PgExceptionHandler):

    def handler(self, pg_exception_info):
        pg_ex_obj = pg_exception_info[1]
        pg_ex_traceback = pg_exception_info[2]
        if pg_ex_obj.pgcode == "P0001":
            print >>sys.stderr, "Error interacting with data"
            print pg_ex_obj.diag.message_primary
            if pg_ex_obj.diag.message_hint:
                print >>sys.stderr, "Hint: ", pg_ex_obj.diag.message_hint
        else:
            self.do_reraise = True


handle_pg_exception = PgUserExceptionHandler(do_exit=True)

dbconn = psycopg2.connect(host = cmdlargs.dbhost, database = cmdlargs.dbname, user = cmdlargs.user,
                          password = cmdlargs.password, application_name = os.path.basename(sys.argv[0]))
dbcur = dbconn.cursor()