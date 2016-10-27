
import argparse, random, ldap, sys, traceback
from ldap.cidict import cidict
from ldap.controls.simple import ValueLessRequestControl
from uuid import UUID

cmdlnparser = argparse.ArgumentParser(description="Get users from AD")
cmdlnparser.add_argument("-c", help="AD controller(s)", action="append", required=True)
cmdlnparser.add_argument("-u", help="AD user", default="")
cmdlnparser.add_argument("-p", help="AD password", default="")
cmdlargs = cmdlnparser.parse_args()


class ldap_exception_handler:
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

handle_ldap_exception = ldap_exception_handler(do_exit=True)


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
try:
    lres = lobj.search_ext_s(base=rootDSE["defaultNamingContext"][0],
                             scope=ldap.SCOPE_SUBTREE,
                             filterstr="(&(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=512)"
                                       "(userPrincipalName=*)(!(servicePrincipalName=*)))",
                             attrlist=("userPrincipalName", "displayName", "objectGUID", "userAccountControl", "usnChanged", "whenChanged", "isDeleted"),
                             serverctrls=(ValueLessRequestControl(controlType="1.2.840.113556.1.4.417"),))
except ldap.LDAPError as lexcp:
    handle_ldap_exception(lexcp)
for lentry in lres:
    if lentry[0] is None: # 'None' DN (referral) shall be sorted out
        continue
    print "DN: {}".format(lentry[0])
    for lattrname, lattrvalue in lentry[1].items():
        if lattrname.lower() == "objectGUID".lower():
            valtoprint = str(UUID(bytes=UUID(bytes=lattrvalue[0]).bytes_le))
        else:
            valtoprint = lattrvalue[0]
        print "  {}: {}".format(lattrname, valtoprint)
