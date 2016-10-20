
import argparse, random, ldap

cmdlnparser = argparse.ArgumentParser(description="Get users from AD")
cmdlnparser.add_argument("-c", help="AD controller(s)", action="append")
cmdlnparser.add_argument("-u", help="AD user")
cmdlnparser.add_argument("-p", help="AD password")
cmdlargs = cmdlnparser.parse_args()

lobj = ldap.initialize("ldap://{}".format(random.choice(cmdlargs.c)))
lobj.set_option(ldap.OPT_PROTOCOL_VERSION, ldap.VERSION3)

lres = lobj.search_s(base="", scope=ldap.SCOPE_BASE,
                     attrlist=("defaultNamingContext", "configurationNamingContext",
                               "domainFunctionality", "serverName",
                               "dnsHostName"))
rootDSE = lres[0][1].items()
for attrname, attrvalue in rootDSE:
    print "Attr {} is {}".format(attrname, attrvalue[0])
