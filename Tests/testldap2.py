#! python3

# Testing ldap interaction using ldap3 module (https://pypi.python.org/pypi/ldap3)

import ldap3
import ldap3.core.exceptions
from ldap3.utils.ciDict import CaseInsensitiveDict
import sys
import traceback
import random
import argparse
from dateutil import tz
from tabulate import tabulate

cmdlnparser = argparse.ArgumentParser(description="Get users from AD")
cmdlnparser.add_argument("-c", help="AD controller(s)", action="append", required=True)
cmdlnparser.add_argument("-u", help="AD user", default="")
cmdlnparser.add_argument("-p", help="AD password", default="")
cmdlargs = cmdlnparser.parse_args()


class LdapBaseExceptionHandler:

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


class LdapGenericExceptionHandler(LdapBaseExceptionHandler):

    def handler(self, exception_info):
        ex_obj, ex_traceback = exception_info[1:3]
        # print >>sys.stderr, "Configuration error: {}".format(ex_obj.message)
        print("LDAP error: {}".format(ex_obj), file=sys.stderr)
        if self.print_traceback:
            print("Occurred at:", file=sys.stderr)
            traceback.print_tb(ex_traceback, limit=1)
        if self.do_exit:
            sys.exit(1)

handle_ldap_exception = LdapGenericExceptionHandler(do_exit=True)
random.seed()
domain_functionality = {"0": "WIN2000",
                        "1": "WIN2003 WITH MIXED DOMAINS",
                        "2": "WIN2003",
                        "3": "WIN2008",
                        "4": "WIN2008R2",
                        "5": "WIN2012",
                        "6": "WIN2012R2",
                        "7": "WIN2016"}
current_domain_functionality = "UNKNOWN"

servers = [ldap3.Server(host=server, get_info=ldap3.ALL, allowed_referral_hosts=[("*", True)]) for server in cmdlargs.c]
random.shuffle(servers)
server_pool = ldap3.ServerPool(servers, pool_strategy=ldap3.FIRST, active=True)

lconn = None
try:
    lconn = ldap3.Connection(server=server_pool, user=cmdlargs.u, password=cmdlargs.p,
                             return_empty_attributes=True, raise_exceptions=True, auto_bind=ldap3.AUTO_BIND_NO_TLS)
except ldap3.core.exceptions.LDAPException:
    handle_ldap_exception(sys.exc_info())
rootDSE_keys = ["defaultNamingContext", "configurationNamingContext", "domainFunctionality",
                      "serverName", "dnsHostName"]
rootDSE_values = [x[0] if isinstance(x, list) else x for x in map(lambda var: lconn.server.info.other[var], rootDSE_keys)]
rootDSE = CaseInsensitiveDict(zip(rootDSE_keys, rootDSE_values))
print("Connected to the LDAP at {}".format(rootDSE["dnsHostName"]))
print("Current domain functionality is {}\n".format(domain_functionality[rootDSE["domainFunctionality"]]))

account_attrs = ["name", "userPrincipalName", "displayName", "objectGUID", "userAccountControl", "usnChanged",
                 "whenChanged", "isDeleted"]
control_showdeleted = ("1.2.840.113556.1.4.417", False, None)
try:
    lconn.search(search_base=rootDSE["defaultNamingContext"], search_scope=ldap3.SUBTREE,
                 search_filter="(&(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=512))",
                 attributes=account_attrs, controls=[control_showdeleted])
except ldap3.core.exceptions.LDAPException:
    handle_ldap_exception(sys.exc_info())
attr_len = max(map(len, account_attrs))
attr_table = []
for lentry in lconn.response:
    if lentry["type"] == "searchResRef":
        continue
    print("DN: {}".format(lentry["dn"]))
    attr_row = []
    for attrname in account_attrs:
        attrvalue = lentry["attributes"][attrname]
        if isinstance(attrvalue, list) and len(attrvalue) == 0:
            attr_row.append("N/A")
            continue
        if attrname == "whenChanged":
            valtoprint = attrvalue.astimezone(tz.tzlocal()).strftime("%Y-%m-%d %H:%M:%S")
        else:
            valtoprint = attrvalue
        attr_row.append(valtoprint)
        print((2 * " " + "{:>" + str(attr_len) + "}: {}").format(attrname, valtoprint))
    attr_table.append(attr_row)
    print("\n")
print(tabulate(attr_table, headers=account_attrs))
