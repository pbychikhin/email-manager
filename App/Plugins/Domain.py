
from yapsy.IPlugin import IPlugin
import libemailmgr, ConfigParser, sys


handle_cfg_exception = libemailmgr.CfgGenericExceptionHandler(do_exit=True)


class domain(IPlugin):

    def configure(self, cfg, cmd, db):
        """
        cfg - config from INI-file, cmd - argparse parent, db - database connection
        """
        self.cfg = cfg
        self.actions = ("query", "add", "del", "mod")
        try:
            cmd.add_argument("action", help="Action to be performed", choices=self.actions, nargs="?",
                             default=cfg.get("domain", "action"))
        except ConfigParser.Error:
            handle_cfg_exception(sys.exc_info())
        cmd.add_argument("-name", help="Name of the domain", required=True)
        cmd.set_defaults(active=None, public=None, adsync=None)
        cmdgroup = cmd.add_mutually_exclusive_group()
        cmdgroup.add_argument("-active", help="Activate the domain", dest="active", action='store_true')
        cmdgroup.add_argument("-noactive", help="Deactivate the domain", dest="active", action='store_false')
        cmdgroup = cmd.add_mutually_exclusive_group()
        cmdgroup.add_argument("-public", help="Publish the domain", dest="public", action='store_true')
        cmdgroup.add_argument("-nopublic", help="Unpublish the domain", dest="public", action='store_false')
        cmdgroup = cmd.add_mutually_exclusive_group()
        cmdgroup.add_argument("-adsync", help="Sync the domain with AD", dest="adsync", action='store_true')
        cmdgroup.add_argument("-noadsync", help="Stop syncing the domain with AD", dest="adsync", action='store_false')
        cmd.parse_args()
        self.cmd = cmd
        self.db = db
