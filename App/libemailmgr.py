
import sys
import traceback
import datetime
import psycopg2
from dateutil import tz
from tabulate import tabulate
try:
    import msvcrt
    getch = msvcrt.getwch  # Getting a unicode variant
except ImportError:
    import getch
    getch = getch.getch  # TODO: This has to be tested on Unix: will getch get a unicode char?


inifile = "emailmgr.ini"

required_db = {
    "sysname":"emailmgr",
    "vmajor":"1",
    "vminor":"0",
    "vpatch":"0"
}


# Constants
SQL_REPEATABLE_READ = "REPEATABLE READ"
SQL_SERIALIZABLE = "SERIALIZABLE"


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


def check_password_length(len_min, len_max):
    if len_min <= 0:
        len_min = 8
    if len_max <= 0:
        len_max = 8
    if len_min > len_max:
        len_tmp = len_min
        len_min = len_max
        len_max = len_tmp
    return len_min, len_max


# Classes

class BasePlugin:

    def __init__(self):
        self.handle_pg_exception = PgGenericExceptionHandler(do_exit=True)
        self.handle_cfg_exception = CfgGenericExceptionHandler(do_exit=True)
        self.process_vars = {}
        self.process_vars["query_header_translations"] = {}
        self.process_vars["action_attrs_translations"] = {}
        self.db, self.args, self.dbc = None, None, None  # get rid of warnings
        self.configured = False

    def configure(self, whoami, cfg, args, db):
        raise NotImplementedError("The method 'configure' must be implemented in '{}' plugin".format(whoami))

    def process(self):
        if not self.configured:
            raise RuntimeError("The plugin wasn't configured. Please call 'configure' before calling 'process'")
        self.dbc = self.db.cursor()
        db_info_header, db_info_data = None, None
        try:
            self.dbc.execute("SET TRANSACTION ISOLATION LEVEL {}".format(SQL_REPEATABLE_READ))
            self.dbc.execute("SELECT * from GetSystem() as (sysname TEXT, vmajor TEXT, vminor TEXT, vpatch TEXT)")
            db_info_header = [item[0] for item in self.dbc.description]
            db_info_data = self.dbc.fetchone()
            self.db.commit()
        except psycopg2.Error:
            self.handle_pg_exception(sys.exc_info())
        self.db_info = dict(zip(db_info_header, db_info_data))
        for key in required_db:
            if self.db_info[key] != required_db[key]:
                print("Incompatible DB", file=sys.stderr)
                print("Want {sysname} v{vmajor}.{vminor}.{vpatch}".format(**required_db), file=sys.stderr)
                print("Got {sysname} v{vmajor}.{vminor}.{vpatch}".format(**self.db_info), file=sys.stderr)
                sys.exit(1)
        exec("self.process_{}()".format(self.args.action))

    def process_query(self):
        data, data_header = [], []
        try:
            if "query_settrans" in self.process_vars:
                self.dbc.execute("SET TRANSACTION ISOLATION LEVEL {}".format(self.process_vars["query_settrans"]))
            self.dbc.execute(self.process_vars["query_body"], self.process_vars["query_params"])
            data_header = [item[0] for item in self.dbc.description]
            data = self.dbc.fetchall()
            self.db.commit()
        except psycopg2.Error:
            self.handle_pg_exception(sys.exc_info())
        data_header_pretty = GetPrettyAttrs(data_header, self.process_vars["query_header_translations"])
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
            self.format_query_res_table(res_table, data_header)  # This is a hook to change res_table before printing it out
            print(tabulate(res_table, headers=tuple(data_header_pretty[key] for key in data_header)))

    def format_query_res_table(self, table, header):
        pass

    def process_action(self):
        print(self.process_vars["action_msg_1"])
        PrintPrettyAttrs(self.args, self.process_vars["action_attrs"],
                         GetPrettyAttrs(self.process_vars["action_attrs"], self.process_vars["action_attrs_translations"]))
        print()
        print("Press \"y\" to continue", end=' ')  # TODO: Special cmd-line option "-y" should also be implemented
        sys.stdout.flush()
        keystroke = getch()
        if keystroke == "y" or keystroke == "Y":
            print("[Ok]")
            print(self.process_vars["action_msg_2"], end=' ')
            sys.stdout.flush()
            try:
                if "action_settrans" in self.process_vars:
                    self.dbc.execute("SET TRANSACTION ISOLATION LEVEL {}".format(self.process_vars["action_settrans"]))
                self.dbc.callproc(self.process_vars["action_proc"], self.process_vars["action_params"])
            except psycopg2.Error:
                self.handle_pg_exception(sys.exc_info())
            else:
                self.db.commit()
            print("Done")
        else:
            print("[Cancel]")


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
        print("LDAP error: {}".format(ex_obj), file=sys.stderr)
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
