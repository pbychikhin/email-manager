
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
        cmd.add_argument("-y", help="Assume \"Yes\" if confirmation is requested", action="store_true", default=False)
        self.args = cmd.parse_args(args)
        self.db = db
        self.configured = True

    def process_querydata(self):
        self.process_vars["query_body"] = "SELECT * FROM GetAliasData(%s, %s)"
        self.process_vars["query_params"] = [self.args.name, self.args.fullname]
        self.process_vars["query_header_translations"] = {"fullname": "Full name"}
        libemailmgr.BasePlugin.process_query(self)

    def process_querylist(self):
        self.process_vars["query_body"] = "SELECT * FROM GetAliasList(%s, %s)"
        self.process_vars["query_params"] = [self.args.name, self.args.value]
        libemailmgr.BasePlugin.process_query(self)

    def format_query_res_table(self, table, header):
        pr_cell = None
        counter = 0
        for row in table:
            if counter == 0:
                counter += 1
                pr_cell = row[0]
                continue
            if row[0] == pr_cell:
                row[0] = ""
            else:
                pr_cell = row[0]

    def process_add(self):
        for email_addr in self.args.name, self.args.value:
            if email_addr is not None and not validators.email(email_addr):
                print("Invalid email: \"{}\"".format(email_addr))
                sys.exit(1)
        self.process_vars["action_msg_1"] = "Adding an alias with the attributes:"
        self.process_vars["action_msg_2"] = "Adding alias... "
        self.process_vars["action_attrs"] = ["name", "value", "fullname", "active", "public"]
        self.process_vars["action_attrs_translations"] = {"fullname": "Full name"}
        self.process_vars["action_proc"] = "alias_add"
        self.process_vars["action_params"] = [self.args.name, self.args.value, self.args.fullname,
                                              self.args.active, self.args.public]
        libemailmgr.BasePlugin.process_action(self)

    def process_del(self):
        if self.args.value is None:
            self.process_vars["action_msg_1"] = "Deleting an alias (and all its values!) with the attributes:"
        else:
            self.process_vars["action_msg_1"] = "Deleting an alias with the attributes:"
        self.process_vars["action_msg_2"] = "Deleting alias... "
        self.process_vars["action_attrs"] = ["name", "value"]
        self.process_vars["action_proc"] = "alias_del"
        self.process_vars["action_params"] = [self.args.name, self.args.value]
        libemailmgr.BasePlugin.process_action(self)

    def process_mod(self):
        for email_addr in self.args.newname, self.args.newvalue:
            if email_addr is not None and not validators.email(email_addr):
                print("Invalid email: \"{}\"".format(email_addr))
                sys.exit(1)
        self.process_vars["action_msg_1"] = "Modifying an alias with the attributes:"
        self.process_vars["action_attrs"] = ["name", "newname", "fullname", "value", "newvalue", "active", "public"]
        if self.args.value is not None:
            self.process_vars["action_msg_1"] = "Modifying an alias value with the attributes:"
            self.process_vars["action_attrs"] = ["name", "value", "newvalue", "active"]
        self.process_vars["action_msg_2"] = "Modifying alias... "
        self.process_vars["action_attrs_translations"] = {"newname": "New name", "fullname": "Full name",
                                                          "newvalue":"New value"}
        self.process_vars["action_proc"] = "alias_mod"
        self.process_vars["action_params"] = [self.args.name, self.args.newname, self.args.value, self.args.newvalue,
                                              self.args.fullname, self.args.active, self.args.public]
        libemailmgr.BasePlugin.process_action(self)
