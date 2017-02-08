
import libemailmgr
import sys
import argparse
import configparser
import os.path
import random
import psycopg2
import ldap3
from ldap3.core.exceptions import LDAPException
from ldap3.utils.ciDict import CaseInsensitiveDict
from yapsy.IPlugin import IPlugin


class adsync(IPlugin, libemailmgr.BasePlugin):

    def __init__(self):
        IPlugin.__init__(self)
        libemailmgr.BasePlugin.__init__(self)
        self.cfg, self.actions = None, None
        self.opchain = [self.op_adconnect, self.op_adidentify, self.op_applock, self.op_syncdomain]
        self.opstatus_stop = False  # if an operation sets this to True, the whole process must stop
        self.lconn = None
        self.rootDSE = None
        self.domain_attrs = CaseInsensitiveDict()  # Domain attributes from the AD
        self.db_domain_entry = {}  # Domain data from the DB

    @staticmethod
    def ldapentry_mutli2singleval(entry):
        for key, val in entry.items():
            if isinstance(val, list):
                entry[key] = val[0]

    @staticmethod
    def stepmsg(msg, opseq, optotal):
        print("{} (operation {} of {})".format(msg, opseq, optotal))

    @staticmethod
    def substepmsg(msg):
        print("  + {}".format(msg))

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
            if self.opstatus_stop:
                self.substepmsg("the operation has requested to stop. stopping")
                break
            else:
                opseq += 1
                oper(opseq, len(self.opchain))

    def op_adconnect(self, opseq, optotal):
        self.stepmsg("Conecting to the AD", opseq, optotal)
        self.substepmsg("connecting to the first available LDAP server")
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
        self.substepmsg("processing root DSE")
        rootDSE_keys = ["defaultNamingContext", "configurationNamingContext", "domainFunctionality",
                        "serverName", "dnsHostName"]
        rootDSE_values = [x[0] if isinstance(x, list) else x for x in
                          map(lambda var: self.lconn.server.info.other[var], rootDSE_keys)]
        self.rootDSE = CaseInsensitiveDict(zip(rootDSE_keys, rootDSE_values))

    def op_adidentify(self, opseq, optotal):
        self.stepmsg("Identifying the domain", opseq, optotal)
        self.substepmsg("retrieving name")
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
        self.substepmsg("retrieving additional attributes")
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

    def op_applock(self, opseq, optotal):
        self.stepmsg("Obtaining an application lock", opseq, optotal)
        try:
            self.dbc.execute("SELECT pg_advisory_lock(%s)", [libemailmgr.SQL_ADV_LOCK_GENERAL])
            self.db.commit()
        except psycopg2.Error:
            self.handle_pg_exception(sys.exc_info())

    def op_syncdomain(self, opseq, optotal):
        self.stepmsg("Synchronizing the domain", opseq, optotal)
        try:
            self.substepmsg("checking by GUID, {{{}}}".format(self.domain_attrs["objectGUID"]))
            self.dbc.execute("SELECT id, name, ad_guid, ad_sync_enabled FROM domain WHERE ad_guid = %s",
                             [self.domain_attrs["objectGUID_raw"]])
            if self.dbc.rowcount < 1:
                self.substepmsg("checking by name, {}".format(self.domain_attrs["dnsRoot"]))
                self.dbc.execute("SELECT id, name, ad_guid, ad_sync_enabled FROM domain WHERE LOWER(name) = LOWER(%s)",
                                 [self.domain_attrs["dnsRoot"]])
            if self.dbc.rowcount < 1:
                self.substepmsg("the domain seems to be new - creating")
                self.dbc.execute("INSERT INTO domain(name, spooldir, ad_guid, created, modified)"
                                 "VALUES(%s, %s, %s, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)",
                                 [self.domain_attrs["dnsRoot"], self.domain_attrs["objectGUID"],
                                 self.domain_attrs["objectGUID_raw"]])
                self.dbc.execute("SELECT id, name, ad_guid, ad_sync_enabled FROM domain WHERE ad_guid = %s",
                                 [self.domain_attrs["objectGUID_raw"]])
            self.db_domain_entry = dict(zip([item[0] for item in self.dbc.description], self.dbc.fetchone()))
            if self.db_domain_entry["ad_sync_enabled"]:
                if self.db_domain_entry["ad_guid"] is None:
                    self.substepmsg("binding existing domain {} to the AD (updating GUID)".format(
                        self.domain_attrs["dnsRoot"]))
                    self.dbc.execute("UPDATE domain SET ad_guid = %s, modified = CURRENT_TIMESTAMP"
                                     "WHERE id = %s",
                                     [self.domain_attrs["objectGUID_raw"], self.db_domain_entry["id"]])
                elif self.db_domain_entry["ad_guid"].tobytes() != self.domain_attrs["objectGUID_raw"]:
                    self.substepmsg("existing domain {} is already bound to a different AD - stopping here".format(
                        self.db_domain_entry["name"]
                    ))
                    self.opstatus_stop = True
                elif self.db_domain_entry["name"].lower() != self.domain_attrs["dnsRoot"].lower():
                    self.substepmsg("the domain seems to be renamed - updating name to {}".format(self.domain_attrs["dnsRoot"]))
                    self.dbc.execute("UPDATE domain SET name = %s, modified = CURRENT_TIMESTAMP WHERE id = %s",
                                     [self.domain_attrs["dnsRoot"], self.db_domain_entry["id"]])
            else:
                self.substepmsg("AD synchronization of the domain {} is not allowed - stopping here".format(
                    self.db_domain_entry["name"]))
                self.opstatus_stop = True
            self.db.commit()
        except psycopg2.Error:
            self.handle_pg_exception(sys.exc_info())
