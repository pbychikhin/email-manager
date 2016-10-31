
import argparse, random, ldap, sys, traceback
from ldap.cidict import cidict
from ldap.controls.simple import ValueLessRequestControl
from uuid import UUID
from datetime import datetime
from dateutil import tz
from tabulate import tabulate

cmdlnparser = argparse.ArgumentParser(description="Get users from AD")
cmdlnparser.add_argument("-c", help="AD controller(s)", action="append", required=True)
cmdlnparser.add_argument("-u", help="AD user", default="")
cmdlnparser.add_argument("-p", help="AD password", default="")
cmdlargs = cmdlnparser.parse_args()


class LdapExceptionHandler:
    def __init__(self, print_traceback=True, do_exit=False):
        self.print_traceback = print_traceback
        self.do_exit = do_exit

    def __call__(self, ldap_exception, print_traceback=None, do_exit=None):
        if print_traceback is not None:
            self.print_traceback = print_traceback
        if do_exit is not None:
            self.do_exit = do_exit
        ldap_err_desc = ""
        if "desc" in ldap_exception.message:
            ldap_err_desc = ": " + ldap_exception.message["desc"]
        print >> sys.stderr, "LDAP error has happened{}".format(ldap_err_desc)
        if "info" in ldap_exception.message:
            print >> sys.stderr, "This means that:\n  {}".format(ldap_exception.message["info"])
        if self.print_traceback:
            print >> sys.stderr, "Occurred at:"
            traceback.print_tb(sys.exc_info()[2], limit=1)
        if self.do_exit:
            sys.exit(1)

handle_ldap_exception = LdapExceptionHandler(do_exit=True)


lobj = ldap.initialize("ldap://{}".format(random.choice(cmdlargs.c)))
lobj.set_option(ldap.OPT_PROTOCOL_VERSION, ldap.VERSION3)
lobj.set_option(ldap.OPT_NETWORK_TIMEOUT, 5)
lobj.set_option(ldap.OPT_REFERRALS, ldap.OPT_OFF) # Do not chase referrals, this doesn't work with AD and slows down the search
lres = None # Get rid of an IDE warning when a var can be undefined coz its first assignment is in try-block

# Get RootDSE
try:
    lres = lobj.search_s(base="",
                         scope=ldap.SCOPE_BASE,
                         attrlist=("defaultNamingContext", "configurationNamingContext", "domainFunctionality",
                                   "serverName", "dnsHostName"))
except ldap.LDAPError as lexcp:
    handle_ldap_exception(lexcp)
rootDSE = cidict(lres[0][1])

domain_functionality = {"0":"WIN2000", "1":"WIN2003 WITH MIXED DOMAINS", "2":"WIN2003", "3":"WIN2008", "4":"WIN2008R2",
                        "5":"WIN2012", "6":"WIN2012R2", "7":"WIN2016"}
current_domain_functionality = "UNKNOWN"
try:
    current_domain_functionality = domain_functionality[rootDSE["domainFunctionality"][0]]
except KeyError:
    pass
print "Connected to the LDAP at {}".format(rootDSE["dnsHostName"][0])
print "Current domain functionality is {}\n".format(current_domain_functionality)

# Bind
try:
    lobj.bind_s(cmdlargs.u, cmdlargs.p)
except ldap.LDAPError as lexcp:
    handle_ldap_exception(lexcp)

# Get domain
try:
    lres = lobj.search_s(base="CN=Partitions,{}".format(rootDSE["configurationNamingContext"][0]),
                         scope=ldap.SCOPE_ONELEVEL,
                         filterstr="(&(objectClass=crossRef)(nCName={}))".format(rootDSE["defaultNamingContext"][0]),
                         attrlist=("dnsRoot", "nETBIOSName"))
except ldap.LDAPError as lexcp:
    handle_ldap_exception(lexcp)
domainAttrs = cidict(lres[0][1])

# Get user accounts
account_attrs = ("name", "userPrincipalName", "displayName", "objectGUID", "userAccountControl", "usnChanged",
                 "whenChanged", "isDeleted")
try:
    lres = lobj.search_ext_s(base=rootDSE["defaultNamingContext"][0],
                             scope=ldap.SCOPE_SUBTREE,
                             filterstr="(&(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=512))",
                             attrlist=account_attrs,
                             serverctrls=(ValueLessRequestControl(controlType="1.2.840.113556.1.4.417"),))
except ldap.LDAPError as lexcp:
    handle_ldap_exception(lexcp)
attr_len = max(map(len, account_attrs))
attr_table = []
for lentry in lres:
    if lentry[0] is None: # 'None' DN (referral) shall be sorted out
        continue
    print "DN: {}".format(lentry[0])
    attrs = cidict(lentry[1])
    attr_row = []
    for attrname in account_attrs:
        try:
            attrvalue = attrs[attrname][0]
        except KeyError:
            attr_row.append("N/A")
            continue
        if attrname.lower() == "objectGUID".lower():
            valtoprint = str(UUID(bytes=UUID(bytes=attrvalue).bytes_le))
        elif attrname.lower() == "whenChanged".lower():
            valtoprint = datetime.strptime(attrvalue, "%Y%m%d%H%M%S.0Z")\
                .replace(tzinfo=tz.gettz('UTC'))\
                .astimezone(tz.tzlocal())\
                .strftime("%Y-%m-%d %H:%M:%S")
        else:
            valtoprint = attrvalue
        attr_row.append(valtoprint)
        print (2 * " " + "{:>" + str(attr_len) + "}: {}").format(attrname, valtoprint)
    attr_table.append(attr_row)
    print "\n"

print tabulate(attr_table, headers=account_attrs)
