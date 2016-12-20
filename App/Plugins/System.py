
import libemailmgr
import sys
import argparse
import os.path
from yapsy.IPlugin import IPlugin


class system(IPlugin, libemailmgr.BasePlugin):

    def __init__(self):
        IPlugin.__init__(self)
        libemailmgr.BasePlugin.__init__(self)
        self.cfg, self.actions = None, None

    def configure(self, whoami, cfg, args, db):
        """
        cfg - config from INI-file, args - rest of args in chosen context, db - database connection
        """
        self.cfg = cfg
        self.actions = ["version"]
        cmd = argparse.ArgumentParser(prog=os.path.basename(sys.argv[0]) + " {}".format(whoami),
                                      description="System maintenance")
        cmd.add_argument("action", help="Action to be performed", choices=self.actions, nargs="?")
        self.args = cmd.parse_args(args)
        self.db = db
        self.configured = True

    def process_None(self):  # We'll just run 'process' function and that's it
        print("The system is up and running. No maintenance requested")

    def process_version(self):
        print("The DB backend is {sysname} v{vmajor}.{vminor}.{vpatch}".format(**self.db_info))