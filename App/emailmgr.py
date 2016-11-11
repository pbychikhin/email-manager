
import libemailmgr, ConfigParser, sys, os.path


app_dir = os.path.dirname(sys.argv[0])

handle_cfg_exception = libemailmgr.CfgGenericExceptionHandler(do_exit=True)
cfg = ConfigParser.ConfigParser()
try:
    cfg.read(app_dir + "/" +libemailmgr.inifile)
    print cfg.get("connect", "passwords")
except ConfigParser.Error:
    handle_cfg_exception(sys.exc_info())
