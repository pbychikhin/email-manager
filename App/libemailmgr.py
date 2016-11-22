
import sys, traceback, datetime
from dateutil import tz


inifile = "emailmgr.ini"


# Routines

def GetPrettyAttrs(attrs, translations=None):
    attrs_pretty = {}
    if translations is None:
        translations = {}
    for item in attrs:
        if item in translations.keys():
            attrs_pretty[item] = translations[item]
        else:
            attrs_pretty[item] = item.capitalize()
    return attrs_pretty

def PrintPrettyAttrs(args, attrs, pretty_attrs):
    pretty_attr_len = max(map(lambda x: len(x[1]) if getattr(args, x[0]) is not None else 0, pretty_attrs.items()))
    is_attr_set = False
    for item in attrs:
        if getattr(args, item) is not None:
            is_attr_set = True
            if isinstance(getattr(args, item), bool):
                valtoprint = "Yes" if getattr(args, item) else "No"
            elif isinstance(getattr(args, item), datetime.datetime):
                valtoprint = getattr(args, item).astimezone(tz.tzlocal()).strftime("%Y-%m-%d %H:%M:%S")
            else:
                valtoprint = getattr(args, item)
            print ("{:>" + str(pretty_attr_len) + "}: {}").format(pretty_attrs[item], valtoprint)
    if not is_attr_set:
        print "{None}"


# Exceptions

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
        # TODO: simplify this handler by analogy with CfgGenericExceptionHandler (just print the exception object)
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
        # print >>sys.stderr, "Configuration error: {}".format(ex_obj.message)
        print >> sys.stderr, "Configuration error: {}".format(ex_obj)
        if self.print_traceback:
            print >>sys.stderr, "Occurred at:"
            traceback.print_tb(ex_traceback, limit=1)
        if self.do_exit:
            sys.exit(1)


class CfgReadExceptionHandler(EmailmgrBaseExceptionHandler):

    def handler(self, exception_info):
        ex_obj, ex_traceback = exception_info[1:3]
        print >>sys.stderr, "Configuration read error: {}".format(ex_obj)
        if self.print_traceback:
            print >>sys.stderr, "Occurred at:"
            traceback.print_tb(ex_traceback, limit=1)
        if self.do_exit:
            sys.exit(1)
