
import libemailmgr, ConfigParser, argparse, sys, os.path, psycopg2
plugins = ("domain", "account", "alias")


app_dir = os.path.dirname(sys.argv[0])

# Parse INI-file
handle_cfg_exception = libemailmgr.CfgGenericExceptionHandler(do_exit=True)
handle_cfg_read_exception = libemailmgr.CfgReadExceptionHandler(do_exit=True)
cfg = ConfigParser.ConfigParser()
try:
    cfg.readfp(open(os.path.join(app_dir, libemailmgr.inifile)))
except ConfigParser.Error:
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

cmdparser = argparse.ArgumentParser(description="Email system manager")
cmdparser.add_argument("context", help="Execution context", choices=plugins)
cmdargs = cmdparser.parse_args(sys.argv[1:2])

print "Doing {}".format(cmdargs.context)