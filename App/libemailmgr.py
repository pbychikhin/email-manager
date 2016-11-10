
import sys, traceback


class EmailmgrBaseExceptionHandler:

    def __init__(self, print_traceback=True, do_exit=False):
        self.print_traceback = print_traceback
        self.do_exit = do_exit
        self.do_reraise = False

    def __call__(self, exception_info, print_traceback=None, do_exit=None):
        """exception_info is a sys.exc_info() return value"""
        if print_traceback is not None:
            self.print_traceback = print_traceback
        if do_exit is not None:
            self.do_exit = do_exit
        self.handler(exception_info)
        if self.do_reraise:
            raise
        elif self.do_exit:
            sys.exit(1)

    def handler(self, exception_info):
        self.do_reraise = True


class PgGenericExceptionHandler(EmailmgrBaseExceptionHandler):

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


class LdapGenericExceptionHandler(EmailmgrBaseExceptionHandler):

    def handler(self, ldap_exception_info):
        ldap_ex_obj, ldap_ex_traceback = ldap_exception_info[1:3]
        ldap_err_desc = ""
        if "desc" in ldap_ex_obj.args[0]:
            ldap_err_desc = ": " + ldap_ex_obj.args[0]["desc"]
        print >> sys.stderr, "LDAP error has happened{}".format(ldap_err_desc)
        if "info" in ldap_ex_obj.args[0]:
            print >> sys.stderr, "This means that:\n  {}".format(ldap_ex_obj.args[0]["info"])
        if self.print_traceback:
            print >> sys.stderr, "Occurred at:"
            traceback.print_tb(ldap_ex_traceback, limit=1)
        if self.do_exit:
            sys.exit(1)