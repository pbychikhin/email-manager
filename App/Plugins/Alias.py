
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
        cmd.add_argument("-name", help="Name of the alias", default=None)
        cmd.add_argument("-value", help="Value of the alias", default=None)
        cmd.add_argument("-fullname", help="Full name of the alias", default=None)
        cmd.add_argument("-newname", help="New name when renaming", default=None)
        cmd.add_argument("-newvalue", help="New value when changing an existing one", default=None)
        cmdgroup = cmd.add_mutually_exclusive_group()
        cmdgroup.add_argument("-active", help="Activate the alias name or value", dest="active", action='store_true',
                              default=None)
        cmdgroup.add_argument("-noactive", help="Deactivate the alias name or value", dest="active",
                              action='store_false', default=None)
        cmdgroup = cmd.add_mutually_exclusive_group()
        cmdgroup.add_argument("-public", help="Publish the alias name", dest="public", action='store_true',
                              default=None)
        cmdgroup.add_argument("-nopublic", help="Unpublish the alias name", dest="public", action='store_false',
                              default=None)
        cmd.add_argument("-r", help="Record-style view", action="store_true", default=False)
        self.args = cmd.parse_args(args)
        self.db = db
        self.configured = True

    def process_querydata(self):
        if self.args.value is None:
            self.process_vars["query_body"] = "SELECT * FROM GetAliasData(%s, %s)"
            self.process_vars["query_params"] = [self.args.name, self.args.fullname]
            self.process_vars["query_header_translations"] = {"fullname": "Full name"}
        else:
            self.process_vars["query_body"] = "SELECT * FROM GetAliasList(%s, %s)"
            self.process_vars["query_params"] = [self.args.name, self.args.value]
        libemailmgr.BasePlugin.process_query(self)