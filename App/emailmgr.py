#! python3


import libemailmgr, configparser, argparse, sys, os.path, psycopg2
from yapsy.PluginManager import PluginManager

# TODO: remove the lines below when testing is over
# TODO: and think out a way to enable debug from outside of the source (from config)
# import logging
# logging.basicConfig(level=logging.DEBUG)

app_dir = os.path.dirname(sys.argv[0])

# Load plugins
# TODO: in case of error when loading a plugin, the PluginManager silently ignores that plugin
# TODO: this is inacceptable. We need to find a way to detect errors of plugin loadings
PM = PluginManager()
PM.setPluginPlaces((app_dir + "/Plugins",))
PM.collectPlugins()
plugin_names = tuple(sorted(plugin_info.name for plugin_info in PM.getAllPlugins()))

# Parse INI-file
handle_cfg_exception = libemailmgr.CfgGenericExceptionHandler(do_exit=True)
handle_cfg_read_exception = libemailmgr.CfgReadExceptionHandler(do_exit=True)
cfg = configparser.ConfigParser()
try:
    cfg.read_file(open(os.path.join(app_dir, libemailmgr.inifile)))
except configparser.Error:
    handle_cfg_exception(sys.exc_info())
except IOError:
    handle_cfg_read_exception(sys.exc_info())

# Connect to the DB
dbconn = None
handle_pg_exception = libemailmgr.PgGenericExceptionHandler(do_exit=True)
try:
    dbconn = psycopg2.connect(host = cfg.get("connect", "host"), database = cfg.get("connect", "database"),
                              user = cfg.get("connect", "user"), password = cfg.get("connect", "password"),
                              application_name = os.path.basename(sys.argv[0]))
except psycopg2.Error:
    handle_pg_exception(sys.exc_info())
except configparser.Error:
    handle_cfg_exception(sys.exc_info())

# Get context
cmd = argparse.ArgumentParser(description="Email system manager")
try:
    cmd.add_argument("context", help="Execution context", choices=plugin_names, nargs="?",
                     default=cfg.get("call", "context"))
    cmd.add_argument("contextargs", help="Arguments relevant in a chosen context", nargs=argparse.REMAINDER)
except configparser.Error:
    handle_cfg_exception(sys.exc_info())
args = cmd.parse_args()

# Run the plugin
PM.getPluginByName(args.context).plugin_object.configure(args.context, cfg, args.contextargs, dbconn)
PM.getPluginByName(args.context).plugin_object.process()
