
import sys, traceback


inifile = "emailmgr.ini"


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

    def handler(self, exception_info):
        ex_obj, ex_traceback = exception_info[1:3]
        if ex_obj.diag.message_primary:
            print >>sys.stderr, ex_obj.diag.message_primary
            if ex_obj.diag.message_hint:
                print >>sys.stderr, "Hint: ", ex_obj.diag.message_hint
        else:
            print >>sys.stderr, ex_obj.args[0]
        if self.print_traceback:
            print >>sys.stderr, "Occurred at:"
            traceback.print_tb(ex_traceback, limit=1)


class LdapGenericExceptionHandler(EmailmgrBaseExceptionHandler):

    def handler(self, exception_info):
        ex_obj, ex_traceback = exception_info[1:3]
        ldap_err_desc = ""
        if "desc" in ex_obj.args[0]:
            ldap_err_desc = ": " + ex_obj.args[0]["desc"]
        print >>sys.stderr, "LDAP error has happened{}".format(ldap_err_desc)
        if "info" in ex_obj.args[0]:
            print >>sys.stderr, "This means that:\n  {}".format(ex_obj.args[0]["info"])
        if self.print_traceback:
            print >>sys.stderr, "Occurred at:"
            traceback.print_tb(ex_traceback, limit=1)
        if self.do_exit:
            sys.exit(1)


class CfgGenericExceptionHandler(EmailmgrBaseExceptionHandler):

    def handler(self, exception_info):
        ex_obj, ex_traceback = exception_info[1:3]
        print >>sys.stderr, "Configuration error: {}".format(ex_obj.message)
        if self.print_traceback:
            print >>sys.stderr, "Occurred at:"
            traceback.print_tb(ex_traceback, limit=1)
        if self.do_exit:
            sys.exit(1)
