
import libemailmgr, ConfigParser, argparse, sys, os.path
plugins = ("domain", "account", "alias")


app_dir = os.path.dirname(sys.argv[0])

handle_cfg_exception = libemailmgr.CfgGenericExceptionHandler(do_exit=True)
handle_cfg_read_exception = libemailmgr.CfgReadExceptionHandler(do_exit=True)
cfg = ConfigParser.ConfigParser()
try:
    cfg.readfp(open(os.path.join(app_dir, libemailmgr.inifile)))
except ConfigParser.Error:
    handle_cfg_exception(sys.exc_info())
except IOError:
    handle_cfg_read_exception(sys.exc_info())

cmdparser = argparse.ArgumentParser(description="Email system manager")
cmdparser.add_argument("context", help="Execution context", choices=plugins)
cmdargs = cmdparser.parse_args(sys.argv[1:2])

print "Doing {}".format(cmdargs.context)