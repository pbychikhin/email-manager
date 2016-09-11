#!/bin/sh
[ $1 ] || { echo "No database to connect"; exit; }
if [ $2 ]
then
    MYSQL="mysql -NB -D $1 -u $2 -p$3"
else
    MYSQL="mysql -NB -D $1"
fi
DB_VER_REQUIRED="emailmgr:3:0:0"
check_status()
	{
	if [ $1 -ne 0 ]
	then
		echo "Failure!"
		exit
	fi
	}

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

echo -n "Altering account... "
$MYSQL << 'SQLINPUT'
ALTER TABLE account
	MODIFY password varchar(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT '';
SQLINPUT
check_status $?
echo "Success"

echo -n "Updating system information... "
$MYSQL << 'SQLINPUT'
START TRANSACTION;
UPDATE sysinfo SET pvalue = '3' WHERE pname = 'vmajor';
UPDATE sysinfo SET pvalue = '0' WHERE pname = 'vminor';
UPDATE sysinfo SET pvalue = '1' WHERE pname = 'vpatch';
COMMIT;
SQLINPUT
check_status $?
echo "Success"

echo "Upgrade was successfull"
