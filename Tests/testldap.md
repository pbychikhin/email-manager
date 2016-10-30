# Notes on `testldap.py`

* access AD LDAP using `python-ldap` (it seems the only module for such purpose)  
Documentation on the module can be found at https://www.python-ldap.org/doc/html/index.html  
64-bit version for Windows (wheel) can be found at http://www.lfd.uci.edu/~gohlke/pythonlibs/
* user in the AD will be `email.client` with password `email.client`
* use `tabulate` to print search result as a table  
the module is at https://pypi.python.org/pypi/tabulate  
another option to consider is `texttable`  
the module is at https://pypi.python.org/pypi/texttable
* In order to search `Deleted objects`, we need to set read permissions for our user  
In recent versions of Windows this object may not be fully managed by Administrator  
Only Local system may happen to have full access  
In order to check permissions:  
`PsExec.exe -s dsacls.exe "CN=Deleted Objects,DC=emailmgr,DC=local"`  
In order to change them (get read access for `email.client`):
`PsExec.exe -s dsacls.exe "CN=Deleted Objects,DC=emailmgr,DC=local" /G email.client:LCRP`