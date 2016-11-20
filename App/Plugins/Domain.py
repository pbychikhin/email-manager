
import libemailmgr, ConfigParser, sys, argparse, os.path, psycopg2, datetime
from yapsy.IPlugin import IPlugin
from tabulate import tabulate
from dateutil import tz


handle_cfg_exception = libemailmgr.CfgGenericExceptionHandler(do_exit=True)
handle_pg_exception = libemailmgr.PgGenericExceptionHandler(do_exit=True)


class domain(IPlugin):

    def configure(self, whoami, cfg, args, db):
        """
        cfg - config from INI-file, args - rest of args in chosen context, db - database connection
        """
        self.cfg = cfg
        self.actions = ("query", "add", "del", "mod")
        cmd = argparse.ArgumentParser(prog=os.path.basename(sys.argv[0]) + " {}".format(whoami),
                                      description="Domain management")
        try:
            cmd.add_argument("action", help="Action to be performed", choices=self.actions, nargs="?",
                             default=cfg.get("domain", "action"))
        except ConfigParser.Error:
            handle_cfg_exception(sys.exc_info())
        cmd.add_argument("-name", help="Name of the domain")
        cmd.set_defaults(active=None, public=None, adsync=None)
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

    def process(self):
        self.dbc = self.db.cursor()
        exec "self.process_{}()".format(self.args.action)

    def process_query(self):
        data, data_header = [], ()
        try:
            self.dbc.execute("SELECT * FROM GetDomainData(%s)", (self.args.name,))
            data_header = tuple(item[0] for item in self.dbc.description)
            data = self.dbc.fetchall()
            self.db.commit()
        except psycopg2.Error:
            handle_pg_exception(sys.exc_info())
        data_header_pretty = {}
        for row in data_header:
            if row == "ad_sync_enabled":
                data_header_pretty[row] = "AD sync enabled"
            else:
                data_header_pretty[row] = row.capitalize()
        attr_pretty_len = max(map(len, data_header_pretty.values()))
        res_table = []
        for data_row in data:
            data_item = dict(zip(data_header, data_row))
            res_row = []
            for attr in data_header:
                attr_pretty = data_header_pretty[attr]
                if isinstance(data_item[attr], datetime.datetime):
                    valtoprint = data_item[attr].astimezone(tz.tzlocal()).strftime("%Y-%m-%d %H:%M:%S")
                elif isinstance(data_item[attr], bool):
                    valtoprint = "Yes" if data_item[attr] else "No"
                else:
                    valtoprint = data_item[attr]
                if self.args.r:
                    print ("{:>" + str(attr_pretty_len) + "}: {}").format(attr_pretty, valtoprint)
                res_row.append(valtoprint)
            if self.args.r:
                print
            res_table.append(res_row)
        if not self.args.r:
            print tabulate(res_table, headers=tuple(data_header_pretty[key] for key in data_header))
