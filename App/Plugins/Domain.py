
import libemailmgr
import configparser
import sys
import argparse
import os.path
import validators
from yapsy.IPlugin import IPlugin


class domain(IPlugin, libemailmgr.BasePlugin):

    def __init__(self):
        IPlugin.__init__(self)
        libemailmgr.BasePlugin.__init__(self)
        self.cfg, self.actions = None, None

    def configure(self, whoami, cfg, args, db):
        """
        cfg - config from INI-file, args - rest of args in chosen context, db - database connection
        """
        self.cfg = cfg
        self.actions = ("query", "add", "del", "mod", "getdefault", "setdefault")
        cmd = argparse.ArgumentParser(prog=os.path.basename(sys.argv[0]) + " {}".format(whoami),
                                      description="Domain management")
        try:
            cmd.add_argument("action", help="Action to be performed", choices=self.actions, nargs="?",
                             default=cfg.get("domain", "action"))
        except configparser.Error:
            self.handle_cfg_exception(sys.exc_info())
        cmd.add_argument("-name", help="Name of the domain")
        cmd.add_argument("-newname", help="New name when renaming")
        cmd.set_defaults(name=None, newname=None, active=None, public=None, adsync=None)
        cmd.add_argument("-r", help="Record-style view", action="store_true", default=False)
        cmdgroup = cmd.add_mutually_exclusive_group()
        cmdgroup.add_argument("-active", help="Activate the domain", dest="active", action='store_true')
        cmdgroup.add_argument("-noactive", help="Deactivate the domain", dest="active", action='store_false')
        cmdgroup = cmd.add_mutually_exclusive_group()
        cmdgroup.add_argument("-public", help="Publish the domain", dest="public", action='store_true')
        cmdgroup.add_argument("-nopublic", help="Unpublish the domain", dest="public", action='store_false')
        cmdgroup = cmd.add_mutually_exclusive_group()
        cmdgroup.add_argument("-adsync", help="Sync the domain with AD", dest="adsync", action='store_true')
        cmdgroup.add_argument("-noadsync", help="Stop syncing the domain with AD", dest="adsync", action='store_false')
        self.args = cmd.parse_args(args)
        self.db = db
        self.configured = True

    def process_query(self):
        self.process_vars["query_body"] = "SELECT * FROM GetDomainData(%s)"
        self.process_vars["query_params"] = [self.args.name]
        self.process_vars["query_header_translations"] = {"ad_sync_enabled":"AD sync"}
        libemailmgr.BasePlugin.process_query(self)

    def process_add(self):
        self.process_vars["action_msg_1"] = "Adding a domain with the attributes:"
        self.process_vars["action_msg_2"] = "Adding domain... "
        self.process_vars["action_attrs"] = ["name", "active", "public"]
        self.process_vars["action_proc"] = "domain_add"
        self.process_vars["action_params"] = [self.args.name, self.args.active, self.args.public]
        if self.args.name and not validators.domain(self.args.name):
            print("Invalid domain name: \"{}\"".format(self.args.name))
            sys.exit(1)
        libemailmgr.BasePlugin.process_action(self)

    def process_del(self):
        self.process_vars["action_msg_1"] = "Deleting a domain with the attributes:"
        self.process_vars["action_msg_2"] = "Deleting domain... "
        self.process_vars["action_attrs"] = ["name"]
        self.process_vars["action_proc"] = "domain_del"
        self.process_vars["action_params"] = [self.args.name]
        libemailmgr.BasePlugin.process_action(self)

    def process_mod(self):
        self.process_vars["action_msg_1"] = "Modifying a domain with the attributes:"
        self.process_vars["action_msg_2"] = "Modifying domain... "
        self.process_vars["action_attrs"] = ["name", "newname", "active", "public", "adsync"]  # TODO: add translation for 'adsync' attr
        self.process_vars["action_proc"] = "domain_mod"
        self.process_vars["action_params"] = [self.args.name, self.args.newname, self.args.active, self.args.public,
                                              self.args.adsync]
        if self.args.newname and not validators.domain(self.args.newname):
            print("Invalid domain name: \"{}\"".format(self.args.newname))
            sys.exit(1)
        libemailmgr.BasePlugin.process_action(self)

    def process_getdefault(self):
        self.process_vars["query_body"] = "SELECT * FROM GetDefaultDomain()"
        self.process_vars["query_params"] = []
        self.process_vars["query_header_translations"] = {"getdefaultdomain":"Default domain"}
        libemailmgr.BasePlugin.process_query(self)

    def process_setdefault(self):
        self.process_vars["action_msg_1"] = "Setting the default domain to the domain with the attributes:"
        self.process_vars["action_msg_2"] = "Modifying defaults... "
        self.process_vars["action_attrs"] = ["name"]
        self.process_vars["action_proc"] = "SetDefaultDomain"
        self.process_vars["action_params"] = [self.args.name]
        self.process_vars["action_settrans"] = libemailmgr.SQL_REPEATABLE_READ
        libemailmgr.BasePlugin.process_action(self)
