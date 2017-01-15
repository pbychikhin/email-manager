
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
        self.opchain = [self.op_connect]
        self.lconn = None

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

    def op_connect(self, opseq, optotal):
        print("Conecting to the AD (operation {} of {})".format(opseq, optotal))
        try:
            servers = [ldap3.Server(host=server, get_info=ldap3.ALL)
                       for server in self.cfg.get("adsync", "host").split()]
            random.shuffle(servers)
            server_pool = ldap3.ServerPool(servers, pool_strategy=ldap3.FIRST, active=1)
            user = self.cfg.get("adsync", "user")
            password = self.cfg.get("adsync", "password")
            self.lconn = ldap3.Connection(server=server_pool, user=user, password=password,
                                     return_empty_attributes=True, raise_exceptions=True,
                                     auto_bind=ldap3.AUTO_BIND_NO_TLS)
        except configparser.Error:
            self.handle_cfg_exception(sys.exc_info())
        except LDAPException:
            self.handle_ldap_exception(sys.exc_info())
