
import libemailmgr
import configparser
import sys
import argparse
import os.path
import validators  # TODO: we might need to find some other validation tool (email validation results can be arguable)
from yapsy.IPlugin import IPlugin


class alias(IPlugin, libemailmgr.BasePlugin):

    def __init__(self):
        IPlugin.__init__(self)
        libemailmgr.BasePlugin.__init__(self)
        self.cfg, self.actions = None, None

    def configure(self, whoami, cfg, args, db):
        """
        cfg - config from INI-file, args - rest of args in chosen context, db - database connection
        """
        self.cfg = cfg
        self.actions = ("querydata", "querylist", "add", "del", "mod")
        cmd = argparse.ArgumentParser(prog=os.path.basename(sys.argv[0]) + " {}".format(whoami),
                                      description="Alias management")
        try:
            cmd.add_argument("action", help="Action to be performed", choices=self.actions, nargs="?",
                             default=cfg.get("alias", "action"))
        except configparser.Error:
            self.handle_cfg_exception(sys.exc_info())
        cmd.add_argument("-name", help="Name of the alias")

