
import libemailmgr
import sys
import argparse
import configparser
import os.path
import random
import ldap3
from ldap3.core.exceptions import LDAPException
from ldap3.utils.ciDict import CaseInsensitiveDict
from yapsy.IPlugin import IPlugin


class adsync(IPlugin, libemailmgr.BasePlugin):

    def __init__(self):
        IPlugin.__init__(self)
        libemailmgr.BasePlugin.__init__(self)
        self.cfg, self.actions = None, None
        self.opchain = [self.op_adconnect, self.op_adidentify]
        self.lconn = None
        self.rootDSE = None
        self.domain_attrs = CaseInsensitiveDict()

    @staticmethod
    def ldapentry_mutli2singleval(entry):
        for key, val in entry.items():
            if isinstance(val, list):
                entry[key] = val[0]

    def configure(self, whoami, cfg, args, db):
        """
        cfg - config from INI-file, args - rest of args in chosen context, db - database connection
        """
        self.cfg = cfg
        self.actions = ["sync"]
        cmd = argparse.ArgumentParser(prog=os.path.basename(sys.argv[0]) + " {}".format(whoami),
                                      description="Synchronization with AD",
                                      epilog="Only sync action is possible at the moment. And it's used by default")
        cmd.add_argument("action", help="Action to be performed", choices=self.actions, nargs="?",
                         default="sync")
        self.args = cmd.parse_args(args)
        self.db = db
        self.configured = True

    def process_sync(self):
        opseq = 0
        for oper in self.opchain:
            opseq += 1
            oper(opseq, len(self.opchain))

    def op_adconnect(self, opseq, optotal):
        print("Conecting to the AD (operation {} of {})".format(opseq, optotal))
        try:
            servers = [ldap3.Server(host=server, get_info=ldap3.ALL)
                       for server in self.cfg.get("adsync", "host").split()]
            random.shuffle(servers)
            server_pool = ldap3.ServerPool(servers, pool_strategy=ldap3.FIRST, active=1)
            user = self.cfg.get("adsync", "user")
            password = self.cfg.get("adsync", "password")
            self.lconn = ldap3.Connection(server=server_pool, user=user, password=password, raise_exceptions=True,
                                     auto_bind=ldap3.AUTO_BIND_NO_TLS)
        except configparser.Error:
            self.handle_cfg_exception(sys.exc_info())
        except LDAPException:
            self.handle_ldap_exception(sys.exc_info())
        rootDSE_keys = ["defaultNamingContext", "configurationNamingContext", "domainFunctionality",
                        "serverName", "dnsHostName"]
        rootDSE_values = [x[0] if isinstance(x, list) else x for x in
                          map(lambda var: self.lconn.server.info.other[var], rootDSE_keys)]
        self.rootDSE = CaseInsensitiveDict(zip(rootDSE_keys, rootDSE_values))

    def op_adidentify(self, opseq, optotal):
        print("Identifying the domain (operation {} of {})".format(opseq, optotal))
        dom_id = {}
        try:
            self.lconn.search(search_base="CN=Partitions," + self.rootDSE["configurationNamingContext"],
                              search_scope=ldap3.LEVEL,
                              search_filter="(&(objectClass=crossRef)(nCName={}))".format(self.rootDSE["defaultNamingContext"]),
                              attributes=["dnsRoot", "nETBIOSName"])
        except LDAPException:
            self.handle_ldap_exception(sys.exc_info())
        lentry = self.lconn.response[0]["attributes"]
        self.ldapentry_mutli2singleval(lentry)
        self.domain_attrs.update(lentry)
        try:
            self.lconn.search(search_base=self.rootDSE["defaultNamingContext"],
                              search_scope=ldap3.BASE,
                              search_filter="(objectClass=*)",
                              attributes=["objectGUID", "whenChanged"])
        except LDAPException:
            self.handle_ldap_exception(sys.exc_info())
        lentry = self.lconn.response[0]["attributes"]
        lentry_raw = self.lconn.response[0]["raw_attributes"]
        for entry in [lentry, lentry_raw]:
            self.ldapentry_mutli2singleval(entry)
        self.domain_attrs.update(lentry)
        self.domain_attrs["objectGUID_raw"] = lentry_raw["objectGUID"]
