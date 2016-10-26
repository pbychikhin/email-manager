# Notes on `testldap.py`

* access AD LDAP using `python-ldap` (it seems the only module for such purpose)  
Documentation on the module can be found at https://www.python-ldap.org/doc/html/index.html  
64-bit version for Windows (wheel) can be found at http://www.lfd.uci.edu/~gohlke/pythonlibs/
* user in the AD will be `email.client` with password `email.client`
* use `tabulate` to print search result as a table  
the module is at https://pypi.python.org/pypi/tabulate  
another option to consider is `texttable`  
the module is at https://pypi.python.org/pypi/texttable