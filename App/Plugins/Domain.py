
import libemailmgr, configparser, sys, argparse, os.path, psycopg2, datetime, validators
from yapsy.IPlugin import IPlugin
from tabulate import tabulate
from dateutil import tz
try:
    import msvcrt
    getch = msvcrt.getwch  # Getting a unicode variant
except ImportError:
    import getch
    getch = getch.getch  # TODO: This has to be tested on Unix: will getch get a unicode char?


handle_cfg_exception = libemailmgr.CfgGenericExceptionHandler(do_exit=True)
handle_pg_exception = libemailmgr.PgGenericExceptionHandler(do_exit=True)


class domain(IPlugin):

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
            handle_cfg_exception(sys.exc_info())
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

    def process(self):
        self.dbc = self.db.cursor()
        exec("self.process_{}()".format(self.args.action))

    def process_query(self):
        data, data_header = [], ()
        try:
            self.dbc.execute("SELECT * FROM GetDomainData(%s)", (self.args.name,))
            data_header = tuple(item[0] for item in self.dbc.description)
            data = self.dbc.fetchall()
            self.db.commit()
        except psycopg2.Error:
            handle_pg_exception(sys.exc_info())
        data_header_pretty = libemailmgr.GetPrettyAttrs(data_header, {"ad_sync_enabled":"AD sync"})
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
                    print(("{:>" + str(attr_pretty_len) + "}: {}").format(attr_pretty, valtoprint))
                res_row.append(valtoprint)
            if self.args.r:
                print()
            res_table.append(res_row)
        if not self.args.r:
            print(tabulate(res_table, headers=tuple(data_header_pretty[key] for key in data_header)))

    def process_add(self):
        attrs = ("name", "active", "public")
        if self.args.name and not validators.domain(self.args.name):
            print("Invalid domain name: \"{}\"".format(self.args.name))
            sys.exit(1)
        print("Adding a domain with the attributes:")
        libemailmgr.PrintPrettyAttrs(self.args, attrs, libemailmgr.GetPrettyAttrs(attrs))
        print()
        print("Press \"y\" to continue", end=' ')
        sys.stdout.flush()
        keystroke = getch()
        if keystroke == "y" or keystroke == "Y":
            print("[Ok]")
            print("Adding domain... ", end=' ')
            sys.stdout.flush()
            try:
                self.dbc.callproc("domain_add", (self.args.name, self.args.active, self.args.public))
            except psycopg2.Error:
                handle_pg_exception(sys.exc_info())
            else:
                self.db.commit()
            print("Done")
        else:
            print("[Cancel]")

    def process_del(self):
        attrs = ("name",)
        print("Deleting a domain with the attributes:")
        libemailmgr.PrintPrettyAttrs(self.args, attrs, libemailmgr.GetPrettyAttrs(attrs))
        print()
        print("Press \"y\" to continue", end=' ')
        sys.stdout.flush()
        keystroke = getch()
        if keystroke == "y" or keystroke == "Y":
            print("[Ok]")
            print("Deleting domain... ", end=' ')
            sys.stdout.flush()
            try:
                self.dbc.callproc("domain_del", (self.args.name,))
            except psycopg2.Error:
                handle_pg_exception(sys.exc_info())
            else:
                self.db.commit()
            print("Done")
        else:
            print("[Cancel]")

    def process_mod(self):
        attrs = ("name", "newname", "active", "public", "adsync")
        if self.args.newname and not validators.domain(self.args.newname):
            print("Invalid domain name: \"{}\"".format(self.args.newname))
            sys.exit(1)
        print("Modifying a domain with the attributes:")
        libemailmgr.PrintPrettyAttrs(self.args, attrs,
                                     libemailmgr.GetPrettyAttrs(attrs,{"newname":"New name", "adsync":"AD sync"}))
        print()
        print("Press \"y\" to continue", end=' ')
        sys.stdout.flush()
        keystroke = getch()
        if keystroke == "y" or keystroke == "Y":
            print("[Ok]")
            print("Modifying domain... ", end=' ')
            sys.stdout.flush()
            try:
                self.dbc.callproc("domain_mod", (self.args.name, self.args.newname, self.args.active, self.args.public,
                                                 self.args.adsync))
            except psycopg2.Error:
                handle_pg_exception(sys.exc_info())
            else:
                self.db.commit()
            print("Done")
        else:
            print("[Cancel]")

    def process_getdefault(self):
        data = []
        try:
            self.dbc.execute("SELECT * FROM GetDefaultDomain()")
            data_header = tuple(item[0] for item in self.dbc.description)
            data = self.dbc.fetchall()
            self.db.commit()
        except psycopg2.Error:
            handle_pg_exception(sys.exc_info())
        for row in data:
            print("Default domain: {}".format(row[0]))

    def process_setdefault(self):
        attrs = ("name",)
        print("Setting the default domain to the domain with the attributes:")
        libemailmgr.PrintPrettyAttrs(self.args, attrs, libemailmgr.GetPrettyAttrs(attrs))
        print()
        print("Press \"y\" to continue", end=' ')
        sys.stdout.flush()
        keystroke = getch()
        if keystroke == "y" or keystroke == "Y":
            print("[Ok]")
            print("Modifying defaults... ", end=' ')
            sys.stdout.flush()
            try:
                self.dbc.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
                self.dbc.callproc("SetDefaultDomain", (self.args.name,))
            except psycopg2.Error:
                handle_pg_exception(sys.exc_info())
            else:
                self.db.commit()
            print("Done")
        else:
            print("[Cancel]")
