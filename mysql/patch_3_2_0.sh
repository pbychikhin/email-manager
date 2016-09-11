#!/bin/sh
[ $1 ] || { echo "No database to connect"; exit; }
if [ $2 ]
then
    MYSQL="mysql -NB -D $1 -u $2 -p$3"
else
    MYSQL="mysql -NB -D $1"
fi
DB_VER_REQUIRED="emailmgr:3:1:0"
check_status()
	{
	if [ $1 -ne 0 ]
	then
		echo "Failure!"
		exit
	else
		echo "Success"
	fi
	}

echo -n "Retrieving system version... "
DB_VER="`$MYSQL << SQLINPUT
SELECT GetFullSysName();
SQLINPUT
`"
check_status $?

if [ x$DB_VER = x$DB_VER_REQUIRED ]
then
	echo "System version is OK"
else
	echo "System version mismatch"
	exit
fi

echo "Begin upgrade procedure"

echo -n "Dropping v_user_pass... "
$MYSQL << 'SQLINPUT'
DROP VIEW v_user_pass;
SQLINPUT
check_status $?

echo -n "Creating get_apache_digauth... "
$MYSQL << 'SQLINPUT'
CREATE
	DEFINER=root@localhost
	FUNCTION get_apache_digauth(sp_name VARCHAR(255), sp_realm VARCHAR(255))
	RETURNS CHAR(32) CHARSET ascii
	READS SQL DATA
	SQL SECURITY DEFINER
	RETURN(SELECT MD5(CONCAT(sp_name, ':', sp_realm, ':', account.password))
		FROM account, domain
		WHERE domain.active = 1 AND account.name = sp_name AND domain.name = sp_realm AND
			account.domain_id = domain.id AND account.active = 1);
SQLINPUT
check_status $?

echo -n "Updating system information... "
$MYSQL << 'SQLINPUT'
START TRANSACTION;
UPDATE sysinfo SET pvalue = '3' WHERE pname = 'vmajor';
UPDATE sysinfo SET pvalue = '2' WHERE pname = 'vminor';
UPDATE sysinfo SET pvalue = '0' WHERE pname = 'vpatch';
COMMIT;
SQLINPUT
check_status $?

echo "Upgrade was successfull"
