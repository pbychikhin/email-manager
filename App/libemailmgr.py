
import sys, traceback, datetime, psycopg2
from dateutil import tz
from tabulate import tabulate


inifile = "emailmgr.ini"


# Routines

def GetPrettyAttrs(attrs, translations=None):
    """
    Makes a list of attrs suitable for representation
    :param attrs: a list of attributes
    :param translations: a dictionary of attrs as keys and
        translated attrs as values. An attr may or may not be in this list
    :return: a dictionary with attrs and their translated counterparts
    """

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
    """
    Prints a list of attrs with their values
    :param args: an object with args - result of argparser
    :param attrs: a list of attributes to be (or may be) printed
    :param pretty_attrs: a list of transtlated attrs (see GetPrettyAttrs)
    :return: none
    """

    pretty_attr_len = max([len(x[1]) if getattr(args, x[0]) is not None else 0 for x in list(pretty_attrs.items())])
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
            print(("{:>" + str(pretty_attr_len) + "}: {}").format(pretty_attrs[item], valtoprint))
    if not is_attr_set:
        print("{None}")


# Classes

class BaseProcessor:

    def __init__(self):
        self.handle_pg_exception = PgGenericExceptionHandler(do_exit=True)
        self.query = {}

    def process(self):
        self.dbc = self.db.cursor()
        exec("self.process_{}()".format(self.args.action))

    def process_query(self):
        data, data_header = [], []
        try:
            self.dbc.execute(self.query["body"], self.query["params"])
            data_header = [item[0] for item in self.dbc.description]
            data = self.dbc.fetchall()
            self.db.commit()
        except psycopg2.Error:
            self.handle_pg_exception(sys.exc_info())
        data_header_pretty = GetPrettyAttrs(data_header, self.query["header_translations"])
        attr_pretty_len = max(map(len, data_header_pretty.values()))
        res_table = []
        for data_row in data:
            data_item = dict(zip(data_header, data_row))
            res_row = []
            for attr in data_header:
                attr_pretty = data_header_pretty[attr]
                if isinstance(data_item[attr], datetime.datetime):
                    valtoprint = data_item[attr].astimezone(tz.tzlocal()).strftime("%Y-%m-%d %H:%M:%S")
                elif isinstance(data_item[attr], bool):
                    valtoprint = "Yes" if data_item[attr] else "No"
                else:
                    valtoprint = data_item[attr]
                if self.args.r:
                    print(("{:>" + str(attr_pretty_len) + "}: {}").format(attr_pretty, valtoprint))
                res_row.append(valtoprint)
            if self.args.r:
                print()
            res_table.append(res_row)
        if not self.args.r:
            print(tabulate(res_table, headers=tuple(data_header_pretty[key] for key in data_header)))


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
            raise  # PyCharm beleives this syntax is not correct, but not in this case (this is an exception handler and it is used in except block
        elif self.do_exit:
            sys.exit(1)

    def handler(self, exception_info):
        self.do_reraise = True


class PgGenericExceptionHandler(EmailmgrBaseExceptionHandler):

    def handler(self, exception_info):
        # TODO: simplify this handler by analogy with CfgGenericExceptionHandler (just print the exception object)
        ex_obj, ex_traceback = exception_info[1:3]
        if ex_obj.diag.message_primary:
            print(ex_obj.diag.message_primary, file=sys.stderr)
            if ex_obj.diag.message_hint:
                print("Hint: ", ex_obj.diag.message_hint, file=sys.stderr)
        else:
            print(ex_obj.args[0], file=sys.stderr)
        if self.print_traceback:
            print("Occurred at:", file=sys.stderr)
            traceback.print_tb(ex_traceback, limit=1)


class LdapGenericExceptionHandler(EmailmgrBaseExceptionHandler):

    def handler(self, exception_info):
        ex_obj, ex_traceback = exception_info[1:3]
        ldap_err_desc = ""
        if "desc" in ex_obj.args[0]:
            ldap_err_desc = ": " + ex_obj.args[0]["desc"]
        print("LDAP error has happened{}".format(ldap_err_desc), file=sys.stderr)
        if "info" in ex_obj.args[0]:
            print("This means that:\n  {}".format(ex_obj.args[0]["info"]), file=sys.stderr)
        if self.print_traceback:
            print("Occurred at:", file=sys.stderr)
            traceback.print_tb(ex_traceback, limit=1)
        if self.do_exit:
            sys.exit(1)


class CfgGenericExceptionHandler(EmailmgrBaseExceptionHandler):

    def handler(self, exception_info):
        ex_obj, ex_traceback = exception_info[1:3]
        # print >>sys.stderr, "Configuration error: {}".format(ex_obj.message)
        print("Configuration error: {}".format(ex_obj), file=sys.stderr)
        if self.print_traceback:
            print("Occurred at:", file=sys.stderr)
            traceback.print_tb(ex_traceback, limit=1)
        if self.do_exit:
            sys.exit(1)


class CfgReadExceptionHandler(EmailmgrBaseExceptionHandler):

    def handler(self, exception_info):
        ex_obj, ex_traceback = exception_info[1:3]
        print("Configuration read error: {}".format(ex_obj), file=sys.stderr)
        if self.print_traceback:
            print("Occurred at:", file=sys.stderr)
            traceback.print_tb(ex_traceback, limit=1)
        if self.do_exit:
            sys.exit(1)
