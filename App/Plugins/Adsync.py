
import libemailmgr
import sys
import argparse
import configparser
import os.path
import random
import psycopg2
import ldap3
import validators
import smtplib
import email.utils
from email.message import EmailMessage
from ldap3.core.exceptions import LDAPException
from ldap3.utils.ciDict import CaseInsensitiveDict
from yapsy.IPlugin import IPlugin


class adsync(IPlugin, libemailmgr.BasePlugin):

    class OpChainStopException(Exception):
        pass

    account_control_flags = {
        "ADS_UF_ACCOUNTDISABLE": 0x00000002,
        "ADS_UF_NORMAL_ACCOUNT": 0x00000200
    }

    def __init__(self):
        IPlugin.__init__(self)
        libemailmgr.BasePlugin.__init__(self)
        self.cfg, self.actions = None, None
        self.opchain = [
            self.op_adconnect,
            self.op_adidentify,
            self.op_applock,
            self.op_syncdomain,
            self.op_inittracking,
            self.op_syncrequired,
            self.op_retrchanges,
            self.op_syncdeleted,
            self.op_syncchanged,
            self.op_sendgreetings
        ]
        self.lconn = None
        self.rootDSE = None
        self.domain_attrs = CaseInsensitiveDict()  # Domain attributes from the AD
        self.db_domain_entry = {}  # Domain data from the DB
        self.db_dit_entry = {}  # Domain DIT (Directory Information Tree) data from the DB
        self.max_oper_usn = 0  # Max USN from all operations is stored in this var and saved to the DB at the end of synchronization

    @staticmethod
    def ldapentry_mutli2singleval(entry):
        for key, val in entry.items():
            if isinstance(val, list):
                entry[key] = None if len(val) < 1 else val[0]

    @staticmethod
    def ldapresponse_removerefs(lresponse):
        ref_idxs = []
        counter = 0
        for lentry in lresponse:
            if lentry["type"] == "searchResRef":
                ref_idxs.append(counter)
            counter += 1
        ref_idxs.reverse()
        for idx in ref_idxs:
            del lresponse[idx:idx+1]

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
            try:
                opseq += 1
                oper(opseq, len(self.opchain))
            except type(self).OpChainStopException:
                self.substepmsg("the operation has requested to stop. stopping")
                break

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
                                     auto_bind=ldap3.AUTO_BIND_NO_TLS, return_empty_attributes=True)
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
                    self.dbc.execute("UPDATE domain SET ad_guid = %s, modified = CURRENT_TIMESTAMP "
                                     "WHERE id = %s",
                                     [self.domain_attrs["objectGUID_raw"], self.db_domain_entry["id"]])
                elif self.db_domain_entry["ad_guid"].tobytes() != self.domain_attrs["objectGUID_raw"]:
                    self.substepmsg("existing domain {} is already bound to a different AD - stopping here".format(
                        self.db_domain_entry["name"]
                    ))
                    raise type(self).OpChainStopException
                elif self.db_domain_entry["name"].lower() != self.domain_attrs["dnsRoot"].lower():
                    self.substepmsg("the domain seems to be renamed - updating name to {}".format(self.domain_attrs["dnsRoot"]))
                    self.dbc.execute("UPDATE domain SET name = %s, modified = CURRENT_TIMESTAMP WHERE id = %s",
                                     [self.domain_attrs["dnsRoot"], self.db_domain_entry["id"]])
            else:
                self.substepmsg("AD synchronization of the domain {} is not allowed - stopping here".format(
                    self.db_domain_entry["name"]))
                raise type(self).OpChainStopException
            self.db.commit()
        except psycopg2.Error:
            self.handle_pg_exception(sys.exc_info())

    def op_inittracking(self, opseq, optotal):
        self.stepmsg("Initializing tracking", opseq, optotal)
        try:
            self.substepmsg("retrieving DIT ID")
            self.lconn.search(search_base="CN=NTDS Settings," + self.rootDSE["serverName"],
                              search_scope=ldap3.BASE,
                              search_filter="(objectClass=*)",
                              attributes=["invocationId"])
        except LDAPException:
            self.handle_ldap_exception(sys.exc_info())
        lentry = self.lconn.response[0]["attributes"]  # invocationId is a single octet-string value. so here and below we don't need any additional checks and conversions
        DITinvocationID = lentry["invocationId"]
        try:
            self.substepmsg("checking database for the tracking record")
            self.dbc.execute("SELECT id, domain_id, dit_invocation_id, dit_usn FROM usn_tracking WHERE domain_id = %s AND dit_invocation_id = %s",
                             [self.db_domain_entry["id"], DITinvocationID])
            if self.dbc.rowcount < 1:
                self.substepmsg("no tracking record for the retrieved DIT ID - creating")
                self.dbc.execute("INSERT INTO usn_tracking(domain_id, dit_invocation_id) VALUES(%s, %s)",
                                 [self.db_domain_entry["id"], DITinvocationID])
                self.dbc.execute("SELECT id, domain_id, dit_invocation_id, dit_usn FROM usn_tracking WHERE domain_id = %s AND dit_invocation_id = %s",
                    [self.db_domain_entry["id"], DITinvocationID])
            self.db.commit()
            self.substepmsg("caching tracking record")
            self.db_dit_entry = dict(zip([item[0] for item in self.dbc.description], self.dbc.fetchone()))
        except psycopg2.Error:
            self.handle_pg_exception(sys.exc_info())

    def op_syncrequired(self, opseq, optotal):
        self.stepmsg("Synchronizing accounts with the \"required\" flag set", opseq, optotal)
        try:
            self.dbc.execute("SELECT id, name FROM account WHERE domain_id = %s AND ad_sync_required = TRUE",
                             [self.db_domain_entry["id"]])
            for db_entry in self.dbc:
                db_account = dict(zip([item[0] for item in self.dbc.description], db_entry))
                curr1 = self.db.cursor()
                try:
                    self.lconn.search(search_base=self.rootDSE["defaultNamingContext"],
                                      search_filter="(&(objectClass=user)(userPrincipalName={})"
                                                    "(userAccountControl:1.2.840.113556.1.4.803:=512)"
                                                    "(!(servicePrincipalName=*)))".format("@".join([db_account["name"], self.domain_attrs["dnsRoot"]])),
                                      attributes=["userPrincipalName", "displayName", "objectGUID", "userAccountControl", "whenChanged"])
                except LDAPException:
                    self.handle_ldap_exception(sys.exc_info())
                self.ldapresponse_removerefs(self.lconn.response)
                if len(self.lconn.response) < 1:
                    self.substepmsg("deleting {} - not found in the AD".format(db_account["name"]))
                    curr1.execute("DELETE FROM account WHERE id = %s", [db_account["id"]])
                else:
                    for entry in [self.lconn.response[0]["raw_attributes"], self.lconn.response[0]["attributes"]]:
                        self.ldapentry_mutli2singleval(entry)
                    curr1.execute("SELECT id, name FROM account WHERE ad_guid = %s",
                                  [self.lconn.response[0]["raw_attributes"]["objectGUID"]])
                    db_account_check = None
                    for db_entry1 in curr1:
                        db_account_check = dict(zip([item[0] for item in curr1.description], db_entry1))
                        break
                    if db_account_check and db_account["id"] != db_account_check["id"]:
                        self.substepmsg("deleting {} - GUID from AD conflicts with {}".format(db_account["name"], db_account_check["name"]))
                        curr1.execute("DELETE FROM account WHERE id = %s", [db_account["id"]])
                    else:
                        self.substepmsg("updating {}".format(db_account["name"]))
                        curr1.execute("UPDATE account SET name = %s, fullname = %s, modified = CURRENT_TIMESTAMP,"
                                      "active = %s, ad_guid = %s, ad_sync_enabled = TRUE, ad_sync_required = FALSE,"
                                      "ad_time_changed = %s WHERE id = %s", [
                                          self.lconn.response[0]["attributes"]["userPrincipalName"].split("@")[0],
                                          self.lconn.response[0]["attributes"]["displayName"],
                                          False if self.lconn.response[0]["attributes"]["userAccountControl"] &
                                                   type(self).account_control_flags["ADS_UF_ACCOUNTDISABLE"] else True,
                                          self.lconn.response[0]["raw_attributes"]["objectGUID"],
                                          self.lconn.response[0]["attributes"]["whenChanged"],
                                          db_account["id"]
                                      ])
            self.db.commit()
        except psycopg2.Error:
            self.handle_pg_exception(sys.exc_info())

    def op_retrchanges(self, opseq, optotal):
        self.stepmsg("Retrieving changes", opseq, optotal)
        self.substepmsg("creating temporary storage for the working set")
        try:
            self.dbc.execute("CREATE TEMPORARY TABLE tmp_ad_object ("
                             "id SERIAL PRIMARY KEY,"
                             "name TEXT DEFAULT NULL UNIQUE,"
                             "fullname TEXT DEFAULT NULL,"
                             "guid BYTEA NOT NULL UNIQUE,"
                             "guid_txt TEXT DEFAULT NULL,"
                             "control_flags INTEGER DEFAULT NULL,"
                             "time_changed TIMESTAMP(0) WITH TIME ZONE DEFAULT NULL,"
                             "deleted BOOLEAN NOT NULL DEFAULT FALSE)"
                             )
            self.dbc.execute("CREATE INDEX ON tmp_ad_object(deleted)")
            self.substepmsg("fetching changes from AD")
            try: # TODO: add an option to make full sync with AD instead with just deltas after dit_usn (use 0 instead of self.db_dit_entry["dit_usn"] in query below)
                self.lconn.search(search_base=self.rootDSE["defaultNamingContext"],
                                  search_filter="(&(objectClass=user)"
                                                "(!(uSNChanged<={}))(|(&(userAccountControl:1.2.840.113556.1.4.803:=512)"
                                                "(userPrincipalName=*)(!(servicePrincipalName=*))"
                                                "(!(isDeleted=TRUE)))(isDeleted=TRUE)))".format(self.db_dit_entry["dit_usn"]),
                                  attributes=["userPrincipalName", "displayName", "objectGUID", "userAccountControl",
                                              "usnChanged", "whenChanged", "isDeleted"],
                                  controls=[("1.2.840.113556.1.4.417", False, None)])
            except LDAPException:
                self.handle_ldap_exception(sys.exc_info())
            self.ldapresponse_removerefs(self.lconn.response)
            for lentry in self.lconn.response:
                for attrs in [lentry["raw_attributes"], lentry["attributes"]]:
                    self.ldapentry_mutli2singleval(attrs)
                if not lentry["attributes"]["isDeleted"]:
                    if not lentry["attributes"]["userPrincipalName"]:
                        self.substepmsg("could not add an entry with GUID {{{}}} to the working set: userPrincipalName is empty".
                                        format(lentry["attributes"]["objectGUID"]))
                        continue
                    user_principal_name = dict(zip(["name", "realm"], lentry["attributes"]["userPrincipalName"].split("@")))
                    if user_principal_name["realm"].lower() != self.db_domain_entry["name"].lower():
                        self.substepmsg("could not add an entry with GUID {{{}}} to the working set: realm doesn't match domain".
                                        format(lentry["attributes"]["objectGUID"]))
                        continue
                    user_email = user_principal_name["name"] + "@" + self.db_domain_entry["name"]
                    if not validators.email(user_email):
                        self.substepmsg(
                            "could not add an entry with GUID {{{}}} to the working set: \"{}\" is not a valid email address".
                                format(lentry["attributes"]["objectGUID"], user_email))
                        continue
                    self.substepmsg("adding live entry \"{}\" with GUID {{{}}} to the working set".
                                    format(user_principal_name["name"], lentry["attributes"]["objectGUID"]))
                    self.dbc.execute("INSERT INTO tmp_ad_object(name, fullname, guid, guid_txt, control_flags, time_changed) "
                                     "VALUES(%s, %s, %s, %s, %s, %s)",
                                     [user_principal_name["name"], lentry["attributes"]["displayName"],
                                      lentry["raw_attributes"]["objectGUID"], lentry["attributes"]["objectGUID"],
                                      lentry["attributes"]["userAccountControl"], lentry["attributes"]["whenChanged"]])
                else:
                    self.substepmsg("adding dead entry with GUID {{{}}} to the working set".
                                    format(lentry["attributes"]["objectGUID"]))
                    self.dbc.execute("INSERT INTO tmp_ad_object(guid, deleted) VALUES(%s, TRUE)",
                                     [lentry["raw_attributes"]["objectGUID"]])
                if self.max_oper_usn < lentry["attributes"]["usnChanged"]:
                    self.max_oper_usn = lentry["attributes"]["usnChanged"]
            self.db.commit()
        except psycopg2.Error:
            self.handle_pg_exception(sys.exc_info())

    def op_syncdeleted(self, opseq, optotal):
        self.stepmsg("Synchronizing deleted accounts", opseq, optotal)
        try:
            self.dbc.execute("DELETE FROM account USING tmp_ad_object "
                             "WHERE domain_id = %s AND ad_sync_enabled = TRUE AND ad_guid = tmp_ad_object.guid "
                             "AND tmp_ad_object.deleted = TRUE", [self.db_domain_entry["id"]])
            self.substepmsg("{} row(s) affected (deleted)".format(self.dbc.rowcount))
            self.db.commit()
        except psycopg2.Error:
            self.handle_pg_exception(sys.exc_info())

    def op_syncchanged(self, opseq, optotal):
        self.stepmsg("Synchronizing new and/or changed accounts", opseq, optotal)
        try:
            self.dbc.execute(
                "DO $$\n"
                "DECLARE\n"
                "   v_account RECORD;\n"
                "   v_account_enabled BOOLEAN;\n"
                "   v_db_account_by_name RECORD;\n"
                "   v_db_account_by_guid RECORD;\n"
                "   v_account_flag_disabled INTEGER DEFAULT %s;\n"
                "   v_domain_id INTEGER DEFAULT %s;\n"
                "BEGIN\n"
                "   CREATE TEMPORARY TABLE tmp_syncchanged_log (\n"
                "       id SERIAL PRIMARY KEY,\n"
                "       action TEXT DEFAULT 'a_generic',\n"
                "       message TEXT,\n"
                "       info1 TEXT,\n"
                "       info2 TEXT);\n"
                "   CREATE INDEX ON tmp_syncchanged_log(action);\n"
                "   FOR v_account IN SELECT id, name, fullname, guid, guid_txt, control_flags, time_changed FROM tmp_ad_object WHERE deleted = FALSE LOOP\n"
                "       IF (v_account.control_flags & v_account_flag_disabled)::BOOLEAN THEN\n"
                "           v_account_enabled = FALSE;\n"
                "       ELSE\n"
                "           v_account_enabled = TRUE;\n"
                "       END IF;\n"
                "       SELECT id, name, ad_guid, ad_sync_enabled, ad_time_changed INTO v_db_account_by_guid\n"
                "           FROM account WHERE domain_id = v_domain_id AND ad_guid = v_account.guid;\n"
                "       SELECT id, name, ad_guid, ad_sync_enabled, ad_time_changed INTO v_db_account_by_name\n"
                "           FROM account WHERE domain_id = v_domain_id AND lower(name) = lower(v_account.name);\n"
                "       IF v_db_account_by_guid.id IS NOT NULL AND (v_db_account_by_name.id IS NULL OR\n"
                "           v_db_account_by_guid.ad_guid IS NOT DISTINCT FROM v_db_account_by_name.ad_guid) THEN\n"
                "           IF v_db_account_by_guid.ad_sync_enabled AND v_account.time_changed > v_db_account_by_guid.ad_time_changed THEN\n"
                "               UPDATE account SET\n"
                "                   name = v_account.name,\n"
                "                   fullname = CASE WHEN v_account.fullname IS NOT NULL THEN v_account.fullname ELSE v_account.name END,\n"
                "                   modified = CURRENT_TIMESTAMP,\n"
                "                   active = v_account_enabled,\n"
                "                   ad_time_changed = v_account.time_changed\n"
                "                   WHERE id = v_db_account_by_guid.id;\n"
                "               INSERT INTO tmp_syncchanged_log(message) VALUES ('updated an AD-bound account ' || v_db_account_by_guid.name);\n"
                "           ELSIF v_account.time_changed <= v_db_account_by_guid.ad_time_changed THEN\n"
                "               INSERT INTO tmp_syncchanged_log(message) VALUES ('could not update an AD-bound account ' || v_db_account_by_guid.name || ' - source is out of date');\n"
                "           ELSE\n"
                "               INSERT INTO tmp_syncchanged_log(message) VALUES ('could not update an AD-bound account ' || v_db_account_by_guid.name || ' - not permitted');\n"
                "           END IF;\n"
                "       ELSIF v_db_account_by_name.id IS NOT NULL THEN\n"
                "           IF v_db_account_by_name.ad_sync_enabled THEN\n"
                "               UPDATE account SET\n"
                "                   name = v_account.name,\n"
                "                   fullname = CASE WHEN v_account.fullname IS NOT NULL THEN v_account.fullname ELSE v_account.name END,\n"
                "                   modified = CURRENT_TIMESTAMP,\n"
                "                   active = v_account_enabled,\n"
                "                   ad_time_changed = v_account.time_changed\n"
                "                   WHERE id = v_db_account_by_name.id;\n"
                "               INSERT INTO tmp_syncchanged_log(message) VALUES ('bound an account ' || v_db_account_by_name.name || ' to the AD');\n"
                "           ELSE\n"
                "               INSERT INTO tmp_syncchanged_log(message) VALUES ('could not bind an account ' || v_db_account_by_name.name || ' to the AD - not permitted');\n"
                "           END IF;\n"
                "       ELSIF v_db_account_by_guid.id IS NULL THEN\n"
                "           INSERT INTO account(domain_id, name, fullname, spooldir, created, modified, active, ad_guid, ad_time_changed) VALUES (\n"
                "               v_domain_id, v_account.name,\n"
                "               CASE WHEN v_account.fullname IS NOT NULL THEN v_account.fullname ELSE v_account.name END,\n"
                "               v_account.guid_txt || '/', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, v_account_enabled,\n"
                "               v_account.guid, v_account.time_changed);\n"
                "           INSERT INTO tmp_syncchanged_log(action, message, info1, info2) VALUES (\n"
                "               'a_insert',\n"
                "               'added new account ' || v_account.name,\n"
                "               v_account.name,\n"
                "               CASE WHEN v_account.fullname IS NOT NULL THEN v_account.fullname ELSE v_account.name END);\n"
                "       ELSE\n"
                "           INSERT INTO tmp_syncchanged_log(message) VALUES (\n"
                "               'conflict found - an account from AD, ' || v_account.name || ', {{' || v_account.guid_txt || '}}, conflicts with ' || v_db_account_by_name.name);\n"
                "       END IF;\n"
                "   END LOOP;\n"
                "END $$", [self.account_control_flags["ADS_UF_ACCOUNTDISABLE"],
                           self.db_domain_entry["id"]])
            self.dbc.execute("SELECT message FROM tmp_syncchanged_log ORDER BY id")
            for db_entry in self.dbc:
                self.substepmsg(db_entry[0])
            self.db.commit()
        except psycopg2.Error:
            self.handle_pg_exception(sys.exc_info())

    def op_sendgreetings(self, opseq, optotal):  # TODO: needs working on exeptions
        self.stepmsg("Sending greetings", opseq, optotal)
        try:
            self.dbc.execute("SELECT info1, info2 FROM tmp_syncchanged_log WHERE action = 'a_insert'")
            for db_entry in self.dbc:
                self.substepmsg("greeting {}".format(db_entry[0]))
                msg = EmailMessage()
                msg["Subject"] = "Welcome!"
                msg["From"] = "postmaster@{}".format(self.db_domain_entry["name"])
                msg["To"] = "{}@{}".format(db_entry[0], self.db_domain_entry["name"])
                msg["Date"] = email.utils.formatdate()
                msg.set_content("Hello {},\n\n"
                                "Greetings from email system at {}!\n\n"
                                "--\n"
                                "Best regards,\n"
                                "Postmaster".format(db_entry[1], self.db_domain_entry["name"]))
                s = smtplib.SMTP(self.cfg.get("adsync", "smtp"))
                s.send_message(msg)
                s.quit()
            self.db.commit()
        except psycopg2.Error:
            self.handle_pg_exception(sys.exc_info())
