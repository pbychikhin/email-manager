
import argparse, random, ldap, sys, traceback
from ldap.cidict import cidict

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
        print >> sys.stderr, "LDAP error has happened: {}".format(ldap_exception.message["desc"])
        print >> sys.stderr, "This means that: {}".format(ldap_exception.message["info"])
        if self.print_traceback:
            print >> sys.stderr, "Traceback (no more than 1 line):"
            traceback.print_tb(sys.exc_info()[2], limit=1)
        if self.do_exit:
            sys.exit(1)

handle_ldap_exception = ldap_exception_handler(do_exit=True)


lobj = ldap.initialize("ldap://{}".format(random.choice(cmdlargs.c)))
lobj.set_option(ldap.OPT_PROTOCOL_VERSION, ldap.VERSION3)

# Get RootDSE
lres = lobj.search_s(base="",
                     scope=ldap.SCOPE_BASE,
                     attrlist=("defaultNamingContext", "configurationNamingContext", "domainFunctionality",
                               "serverName", "dnsHostName"))
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

print "Domain attrs:"
for name, val in domainAttrs.items():
    print "Attr {}: {}".format(name, val[0])
