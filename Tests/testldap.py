
import argparse, random, ldap, sys
from ldap.cidict import cidict

cmdlnparser = argparse.ArgumentParser(description="Get users from AD")
cmdlnparser.add_argument("-c", help="AD controller(s)", action="append", required=True)
cmdlnparser.add_argument("-u", help="AD user", default="")
cmdlnparser.add_argument("-p", help="AD password", default="")
cmdlargs = cmdlnparser.parse_args()

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
except ldap.INVALID_CREDENTIALS:
    print "The credentials supplied are invalid"
    sys.exit(1)

# Get domain
try:
    lres = lobj.search_s(base="CN=Partitions,{}".format(rootDSE["configurationNamingContext"][0]),
                         scope=ldap.SCOPE_ONELEVEL,
                         filterstr="(&(objectClass=crossRef)(nCName={}))".format(rootDSE["defaultNamingContext"][0]),
                         attrlist=("dnsRoot", "nETBIOSName"))
    domainAttrs = cidict(lres[0][1])
except ldap.OPERATIONS_ERROR as lexcp:
    print "Error in ldap operation: {}".format(lexcp.args[0]["info"])
    sys.exit(1)

print "Domain attrs:"
for name, val in domainAttrs.items():
    print "Attr {}: {}".format(name, val[0])
