
import libemailmgr
import sys
import argparse
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
