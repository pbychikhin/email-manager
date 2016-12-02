
import libemailmgr
import configparser
import sys
import argparse
import os.path
import validators  # TODO: we might need to find some other validation tool (email validation results can be arguable)
import password_generator
import random
from yapsy.IPlugin import IPlugin


class account(IPlugin, libemailmgr.BasePlugin):

    def __init__(self):
        IPlugin.__init__(self)
        libemailmgr.BasePlugin.__init__(self)
        self.cfg, self.actions = None, None

    def configure(self, whoami, cfg, args, db):
        """
        cfg - config from INI-file, args - rest of args in chosen context, db - database connection
        """
        self.cfg = cfg
        self.actions = ("query", "add", "del", "mod")
        cmd = argparse.ArgumentParser(prog=os.path.basename(sys.argv[0]) + " {}".format(whoami),
                                      description="Account management")
        try:
            cmd.add_argument("action", help="Action to be performed", choices=self.actions, nargs="?",
                             default=cfg.get("account", "action"))
        except configparser.Error:
            self.handle_cfg_exception(sys.exc_info())
        cmd.add_argument("-domain", help="Domain of the account")
        cmd.add_argument("-name", help="Name of the account")
        cmd.add_argument("-password", help="Password of the account")
        cmd.add_argument("-fullname", help="Full name of the account")
        cmd.add_argument("-newname", help="New name when renaming")
        cmd.set_defaults(domain=None, name=None, fullname=None, newname=None, password=None, active=None, public=None, adsync=None)
        cmd.add_argument("-r", help="Record-style view", action="store_true", default=False)
        cmdgroup = cmd.add_mutually_exclusive_group()
        cmdgroup.add_argument("-active", help="Activate the account", dest="active", action='store_true')
        cmdgroup.add_argument("-noactive", help="Deactivate the account", dest="active", action='store_false')
        cmdgroup = cmd.add_mutually_exclusive_group()
        cmdgroup.add_argument("-public", help="Publish the account", dest="public", action='store_true')
        cmdgroup.add_argument("-nopublic", help="Unpublish the account", dest="public", action='store_false')
        cmdgroup = cmd.add_mutually_exclusive_group()
        cmdgroup.add_argument("-adsync", help="Sync the account with AD", dest="adsync", action='store_true')
        cmdgroup.add_argument("-noadsync", help="Stop syncing the account with AD", dest="adsync", action='store_false')
        self.args = cmd.parse_args(args)
        self.db = db
        self.configured = True

    def process_query(self):
        self.process_vars["query_body"] = "SELECT * FROM GetAccountData(%s, %s, %s)"
        self.process_vars["query_params"] = [self.args.domain, self.args.name, self.args.fullname]
        self.process_vars["query_header_translations"] = {"password_enabled": "Use password", "ad_sync_enabled": "AD sync"}
        self.process_vars["query_settrans"] = libemailmgr.SQL_REPEATABLE_READ
        libemailmgr.BasePlugin.process_query(self)

    def process_add(self):
        self.process_vars["action_msg_1"] = "Adding an account with the attributes:"
        self.process_vars["action_msg_2"] = "Adding account... "
        self.process_vars["action_attrs"] = ["domain", "name", "password", "fullname", "active", "public"]
        self.process_vars["action_attrs_translations"] = {"fullname": "Full name"}
        self.process_vars["action_proc"] = "account_add"
        email_addr = self.args.name + "@" + (self.args.domain if self.args.domain is not None else "DEFAULT.DOMAIN")
        if self.args.name and not validators.email(email_addr):
            print("Invalid email: \"{}\"".format(email_addr))
            sys.exit(1)
        if self.args.password is None:
            password_gen_min = self.cfg.getint("account", "password_gen_min", fallback=8)
            password_gen_max = self.cfg.getint("account", "password_gen_max", fallback=8)
            password_gen_min, password_gen_max = libemailmgr.check_password_length(password_gen_min, password_gen_max)
            self.args.password = password_generator.generate(length=random.randint(password_gen_min, password_gen_max))
        self.process_vars["action_params"] = [self.args.domain, self.args.name, self.args.password, self.args.fullname,
                                              self.args.active, self.args.public]
        libemailmgr.BasePlugin.process_action(self)

    def process_del(self):
        self.process_vars["action_msg_1"] = "Deleting an account with the attributes:"
        self.process_vars["action_msg_2"] = "Deleting account... "
        self.process_vars["action_attrs"] = ["domain", "name"]
        self.process_vars["action_proc"] = "account_del"
        self.process_vars["action_params"] = [self.args.domain, self.args.name]
        libemailmgr.BasePlugin.process_action(self)