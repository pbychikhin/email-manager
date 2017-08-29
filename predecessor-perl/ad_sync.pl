#!/usr/bin/perl -w

use feature "switch";
use strict "vars";
use Getopt::Long;
use DBI;
use Net::LDAP;
use Authen::SASL;
use Data::Validate::Email qw(is_username is_domain);
use Mail::Sendmail;
use List::Util qw(shuffle first);
use DateTime ();
use DateTime::Format::ISO8601;

sub GuidToString
{
        return sprintf "%08X-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                unpack("I", $_[0]),
                unpack("S", substr($_[0], 4, 2)),
                unpack("S", substr($_[0], 6, 2)),
                unpack("C", substr($_[0], 8, 1)),
                unpack("C", substr($_[0], 9, 1)),
                unpack("C", substr($_[0], 10, 1)),
                unpack("C", substr($_[0], 11, 1)),
                unpack("C", substr($_[0], 12, 1)),
                unpack("C", substr($_[0], 13, 1)),
                unpack("C", substr($_[0], 14, 1)),
                unpack("C", substr($_[0], 15, 1));
}

sub StringToGuid
{
        return undef
                unless $_[0] =~ 
/([0-9,a-z]{8})-([0-9,a-z]{4})-([0-9,a-z]{4})-([0-9,a-z]{2})([0-9,a-z]{2})-([0-9,a-z]{2})([0-9,a-z]{2})([0-9,a-z]{2})([0-9,a-z]{2})([0-9,a-z]{2})([0-9,a-z]{2})/i;

        return pack("I", hex $1) . pack("S", hex $2) . pack("S", hex $3) . 
pack("C", hex $4) . pack("C", hex $5) .
               pack("C", hex $6) . pack("C", hex $7) . pack("C", hex $8) . 
pack("C", hex $9) . pack("C", hex $10) . pack("C", hex $11);

        print "$1\n$2\n$3\n$4\n$5\n$6\n$7\n$8\n$9\n$10\n$11\n";
}

my (@db_hosts, @ad_controllers);
my $db_name = "";
my $db_user = "";
my $db_password = "";
my $smtp_srv = "localhost";

my $GetOptions_rv = GetOptions(
    "d=s"=>\$db_name,		#    -d for the database name
    "h=s"=>\@db_hosts,		#    -h for the database hosts, multiple is allowed, first available will be used
    "c=s"=>\@ad_controllers,	#    -c for the AD controllers, multiple is allowed, first available will be used
    "u=s"=>\$db_user,		#    -u for the database user, may be empty
    "p=s"=>\$db_password,	#    -p for the database password, may be empty
    "smtp=s"=>\$smtp_srv);	# -smtp for the smtp-server to send a greeting message, default is localhost
die("Bad command line\n") unless ($GetOptions_rv);

die("Database name is empty. Use -d to setup\n") if ($db_name eq "");
die("List of the database hosts is empty. Use -h (multiple times) to setup\n") if (scalar(@db_hosts) == 0);
die("List of the AD controllers is empty. Use -c (multiple times) to setup\n") if (scalar(@ad_controllers) == 0);

#Connect to the first available LDAP-server
print("Connecting to the AD\n");
my $ldap;
@ad_controllers = shuffle(@ad_controllers);
foreach (@ad_controllers)
    {
    print("[I] trying $_... ");
    $ldap = Net::LDAP->new($_, version=>3, timeout=>15);
    print("fail: $@\n") unless ($ldap);
    if ($ldap)
	{
	print("OK\n");
	last;
	}
    }
die("Fail to connect to AD\n") unless ($ldap);

#Cache the RootDSE object
my $dse = $ldap->root_dse(attrs=>[
	"defaultNamingContext",
	"configurationNamingContext",
	"domainFunctionality",
	"serverName",
	"dnsHostName"]);

#Check the LDAP-server
print("Checking the domain metadata\n");
my @domain_functionality_allowed = (1, 2); #May be changed in future
die("Unallowed domain functionality level\n") unless (first {$dse->get_value("domainFunctionality") == $_} @domain_functionality_allowed);

my $mesg; #Net::LDAP::Message
my $entry; #Net::LDAP::Entry

#Bind to LDAP
print("Logging on to the AD, server name is: ".$dse->get_value("dnsHostName")."\n");
my $sasl = Authen::SASL->new(mech=>"GSSAPI");
$mesg = $ldap->bind(sasl=>$sasl->client_new("ldap", $dse->get_value("dnsHostName")));
$mesg->code && die("LDAP operation failed: ".$mesg->error."\n");

#Check the domain
print("Identifying the domain\n");
my %domain_attributes;
$mesg = $ldap->search(
	base=>"CN=Partitions,".$dse->get_value('configurationNamingContext'),
	scope=>"one",
	filter=>"&(objectClass=crossRef)(nCName=".$dse->get_value("defaultNamingContext").")",
	attrs=>["dnsRoot", "nETBIOSName"]);
$mesg->code && die("LDAP operation failed: ".$mesg->error."\n");
$entry = $mesg->shift_entry();
$mesg->code && die("LDAP operation failed: ".$mesg->error."\n");
@domain_attributes{"dns_name", "netbios_name"} = ($entry->get_value("dnsRoot"), $entry->get_value("nETBIOSName"));
#die("The DNS domain name retrieved from AD is incorrect\n") unless (is_domain($domain_attributes{"dns_name"}));
$mesg = $ldap->search(
    base=>$dse->get_value("defaultNamingContext"),
    scope=>"base",
    filter=>"objectClass=*",
    attrs =>["objectGUID", "whenChanged"]);
$mesg->code && die("LDAP operation failed: ".$mesg->error."\n");
$entry = $mesg->shift_entry();
$mesg->code && die("LDAP operation failed: ".$mesg->error."\n");
@domain_attributes{"guid", "time_changed"} = ($entry->get_value("objectGUID"), $entry->get_value("whenChanged"));

#Connect to the first available database server
@db_hosts = shuffle(@db_hosts);
my $dbh; #Database handler
my $sth; #Statement statement handler
print("Connecting to the database\n");
foreach (@db_hosts)
    {
    print("[I] trying $_... ");
    $dbh = DBI->connect("DBI:mysql:database=".$db_name.";host=".$_.";mysql_compression=1",
	$db_user, $db_password, {PrintError => 0});
    print("fail: ".$DBI::errstr."\n") unless ($dbh);
    if ($dbh)
	{
	print("OK\n");
	last;
	}
    }
die("Fail to connect to the database\n") unless ($dbh);
print("Checking the database version\n");
my %required_db = ("name" => "emailmgr", "vmajor" => "3", "vminor" => "2", "vpatch" => "0"); #May be changed in future
my %real_db;
@real_db{"name", "vmajor", "vminor", "vpatch"} = split(":", ($dbh->selectrow_array("SELECT GetFullSysName()"))[0]);
die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
foreach (keys(%required_db))
    {
    die("Incompatible database. Parameter $_ is equal to $real_db{$_}, but must be $required_db{$_}\n") if 
	($real_db{$_} ne $required_db{$_});
    }
print("Acquiring an application lock\n");
my %db_app_lock = ("name" => $real_db{"name"}."."."ad_sync", "timeout" => 300); #May be changed in future
my $get_lock_rv = ($dbh->selectrow_array("SELECT GET_LOCK(?, ?)", undef, @db_app_lock{"name", "timeout"}))[0];
die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
die("Error occurred while locking\n") unless (defined($get_lock_rv));
print("Timeout reached while locking\n") and exit if ($get_lock_rv == 0);

#Check the domain record in the database
print("Checking the database for ".$domain_attributes{"dns_name"}."\n");
$dbh->begin_work or die("Begin work operation failed: ".$dbh->errstr."\n");
my %db_domain_entry;
## Firstly, check by GUID
@db_domain_entry{"id", "name", "ad_guid", "ad_sync_enabled"} = $dbh->selectrow_array(
    "SELECT id, name, ad_guid, ad_sync_enabled FROM domain WHERE ad_guid = ?",
    undef,
    $domain_attributes{"guid"});
die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
## Secondly, check by name if GUID is not exists in DB
if (!defined($db_domain_entry{"id"}))
    {
    @db_domain_entry{"id", "name", "ad_guid", "ad_sync_enabled"} = $dbh->selectrow_array(
	"SELECT id, name, ad_guid, ad_sync_enabled FROM domain WHERE name = ?",
	undef,
	$domain_attributes{"dns_name"});
    die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
    }
if (!defined($db_domain_entry{"id"})) #Create the domain if not exists
    {
    print("Domain seems to be new - creating\n");
    $dbh->do("INSERT INTO domain(name, spooldir, ad_guid, created, modified)
	VALUES(?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)",
	undef,
	$domain_attributes{"dns_name"}, GuidToString($domain_attributes{"guid"}), $domain_attributes{"guid"});
    die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
    @db_domain_entry{"id", "name", "ad_guid", "ad_sync_enabled"} = $dbh->selectrow_array(
	"SELECT id, name, ad_guid, ad_sync_enabled FROM domain WHERE ad_guid = ?",
	undef,
	$domain_attributes{"guid"});
    die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
    }
if ($db_domain_entry{"ad_sync_enabled"})
    {
    if (!defined($db_domain_entry{"ad_guid"})) # Seems to be found by name
	{
	print("Domain seems to be handmade - synchronizing GUID\n");
	$dbh->do("UPDATE domain SET ad_guid = ?, modified = CURRENT_TIMESTAMP WHERE name = ?", undef, $domain_attributes{"guid"}, $domain_attributes{"dns_name"});
	die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
	}
    elsif ($db_domain_entry{"ad_guid"} ne $domain_attributes{"guid"}) # Seems to be found by name
	{
	$dbh->rollback() or die("Rollback operation failed: ".$dbh->errstr."\n");
	$dbh->disconnect() or warn("Disconnect operation failed: ".$dbh->errstr."\n");
	die("{".GuidToString($db_domain_entry{"ad_guid"})."}"." from database is not equal to "."{".GuidToString($domain_attributes{"guid"})."}"." from AD\n");
	}
    elsif ($db_domain_entry{"name"} !~ /^\Q$domain_attributes{"dns_name"}\E$/i) # Seems to be found by GUID
	{
	print("Domain seems to be renamed - synchronizing name\n");
	if ($dbh->do("SELECT id FROM domain WHERE name = ?", undef, $domain_attributes{"dns_name"}) > 0)
	    {
	    die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
	    $dbh->rollback() or die("Rollback operation failed: ".$dbh->errstr."\n");
	    $dbh->disconnect() or warn("Disconnect operation failed: ".$dbh->errstr."\n");
	    die("Domain with name of ".$domain_attributes{"dns_name"}." alredy exists\n");
	    }
	$dbh->do("UPDATE domain SET name = ?, modified = CURRENT_TIMESTAMP WHERE ad_guid = ?", undef, $domain_attributes{"dns_name"}, $domain_attributes{"guid"});
	die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
	}
    }
else
    {
    $dbh->rollback() or die("Rollback operation failed: ".$dbh->errstr."\n");
    $dbh->disconnect() or warn("Disconnect operation failed: ".$dbh->errstr."\n");
    print("Database info for ".$db_domain_entry{"name"}." is not allowed to be synchronized with AD\n");
    exit;
    }
$dbh->commit or die("Commit operation failed: ".$dbh->errstr."\n");

#Check the tracking info
print("Initializing the tracking\n");
$mesg = $ldap->search(
    base=>"CN=NTDS Settings,".$dse->get_value("serverName"),
    scope=>"base",
    filter=>"objectClass=*",
    attrs => ["invocationId"]);
$mesg->code && die("LDAP operation failed: ".$mesg->error."\n");
my $dit_invocation_id = $mesg->shift_entry()->get_value("invocationId");
$mesg->code && die("LDAP operation failed: ".$mesg->error."\n");
my %db_dit_entry;
@db_dit_entry{"id", "domain_id", "dit_invocation_id", "dit_usn"} = $dbh->selectrow_array(
    "SELECT id, domain_id, dit_invocation_id, dit_usn FROM usn_tracking WHERE domain_id = ? AND dit_invocation_id = ?",
    undef,
    $db_domain_entry{"id"}, $dit_invocation_id);
die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
if (!defined($db_dit_entry{"id"})) #Create a tracking record if not exists
    {
    print("DIT instance seems to be new - creating a tracking record\n");
    $dbh->do("INSERT INTO usn_tracking(domain_id, dit_invocation_id) VALUES(?, ?)", undef, $db_domain_entry{"id"}, $dit_invocation_id);
    die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
    @db_dit_entry{"id", "domain_id", "dit_invocation_id", "dit_usn"} = $dbh->selectrow_array(
	"SELECT id, domain_id, dit_invocation_id, dit_usn FROM usn_tracking WHERE domain_id = ? AND dit_invocation_id = ?",
	undef,
	$db_domain_entry{"id"}, $dit_invocation_id);
    die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
    }
my $max_oper_usn = 0; #Max USN from all operations should be stored in this var. It will be saved in DB at the end of a synchronization


#Do real synchronization

$dbh->do("SET NAMES \'utf8\'");
die("SET NAMES failed: ".$dbh->errstr."\n") if ($dbh->state);

my $current_stage = 0;
my $max_stage = 3; #May be changed in future
my %account_control_flags = (
    "ADS_UF_ACCOUNTDISABLE"=>0x00000002,
    "ADS_UF_NORMAL_ACCOUNT"=>0x00000200,
    );
my %db_account_entry;
my %db_ad_cache_entry;

#Synchronize with ad_sync_required = TRUE
print("Synchronizing accounts (stage ".++$current_stage." of ".$max_stage.")\n");
$dbh->begin_work or die("Begin work operation failed: ".$dbh->errstr."\n");
$sth = $dbh->prepare("SELECT id, name FROM account WHERE domain_id = ? AND ad_sync_required = TRUE");
die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
$sth->execute($db_domain_entry{"id"});
die("SQL operation failed: ".$sth->errstr."\n") if ($sth->state);
while (@db_account_entry{"id", "name"} = $sth->fetchrow_array)
    {
    $mesg = $ldap->search(
	base=>$dse->get_value("defaultNamingContext"),
	filter=>"&(objectClass=user)(userPrincipalName=".
	    $db_account_entry{"name"}."@".$domain_attributes{"dns_name"}.
	    ")(userAccountControl:1.2.840.113556.1.4.803:=512)(!(servicePrincipalName=*))",
	attrs=>["userPrincipalName", "displayName", "objectGUID", "userAccountControl", "whenChanged"]
	);
    $mesg->code && die("LDAP operation failed: ".$mesg->error."\n");
    $entry = $mesg->shift_entry();
    $mesg->code && die("LDAP operation failed: ".$mesg->error."\n");
    my $delete_this = 0;
    if (defined($entry))
	{
	my %ad_account_entry;
	@ad_account_entry{"name", "fullname", "guid", "control_flags", "time_changed"} = (
	    (split("@", $entry->get_value("userPrincipalName")))[0], $entry->get_value("displayName") // undef,
	    $entry->get_value("objectGUID"), $entry->get_value("userAccountControl"),
	    $entry->get_value("whenChanged"));
	my %db_account_entry_check; #Check entry by GUID
	$db_account_entry_check{"id", "name"} = $dbh->selectrow_array(
	    "SELECT id, name FROM account WHERE ad_guid = ?",
	    undef,
	    $ad_account_entry{"guid"});
	die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
	if (defined($db_account_entry_check{"id"}) and $db_account_entry{"id"} != $db_account_entry_check{"id"})
	    {
	    print("[X] deleting ".$db_account_entry{"name"}.", reason: GUID from AD conflicts with ".$db_account_entry_check{"name"}."\n");
	    $delete_this = 1;
	    }
	else
	    {
	    print("[I] updating ".$db_account_entry{"name"}."\n");
	    my $is_enabled = 1;
	    $is_enabled = 0 if ($ad_account_entry{"control_flags"} & $account_control_flags{"ADS_UF_ACCOUNTDISABLE"});
	    $dbh->do(
		"UPDATE account SET name = ?, fullname = ?, modified = CURRENT_TIMESTAMP, active = ?, ad_guid = ?,
		    ad_sync_enabled = 1, ad_sync_required = 0, ad_time_changed = ? WHERE id = ?",
		undef,
		$ad_account_entry{"name"}, $ad_account_entry{"fullname"}, $is_enabled, $ad_account_entry{"guid"},
		$ad_account_entry{"time_changed"}, $db_account_entry{"id"});
	    die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
	    }
	}
    else
	{
	print("[X] deleting ".$db_account_entry{"name"}.", reason: not found in AD\n");
	$delete_this = 1;
	}
    if ($delete_this)
	{
	$dbh->do("DELETE FROM account WHERE id = ?", undef, $db_account_entry{"id"});
	die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
	}
    }
die("SQL operation failed: ".$sth->errstr."\n") if ($sth->state);
$dbh->commit or die("Commit operation failed: ".$dbh->errstr."\n");

#Retrieve account records that has been changed
print("Retrieving deltas\n");
$dbh->do("
    CREATE TEMPORARY TABLE tmp_ad_object (
	id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	name VARCHAR(255) DEFAULT NULL,
	fullname VARCHAR(255) CHARACTER SET utf8 DEFAULT NULL,
	guid BINARY(16) NOT NULL,
	control_flags INT DEFAULT NULL,
	time_changed VARBINARY(32) DEFAULT NULL,
	deleted TINYINT NOT NULL DEFAULT 0,
	PRIMARY KEY (id),
	UNIQUE KEY (name),
	UNIQUE KEY (guid),
	KEY (deleted)
    ) ENGINE=InnoDB DEFAULT CHARSET=ascii");
die("1 SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
$mesg = $ldap->search(
    base=>$dse->get_value("defaultNamingContext"),
    filter=>"&(objectClass=user)(!(uSNChanged<=".$db_dit_entry{"dit_usn"}."))
	(|(&(userAccountControl:1.2.840.113556.1.4.803:=512)(userPrincipalName=*)(!(servicePrincipalName=*))(!(isDeleted=TRUE)))
	(isDeleted=TRUE))",
    attrs=>["userPrincipalName", "displayName", "objectGUID", "userAccountControl", "usnChanged", "whenChanged", "isDeleted"],
    control=>{"type"=>"1.2.840.113556.1.4.417", "critical"=>0} # Show deleted objects
    );
$mesg->code && die("LDAP operation failed: ".$mesg->error."\n");
foreach($mesg->entries())
    {
    if (!defined($_->get_value("isDeleted")) or $_->get_value("isDeleted") !~ /^TRUE$/i)
	{
	my %user_principal_name;
	if (!defined($_->get_value("userPrincipalName")))
	    {
	    print("[!] user principal is empty (looks weird!), skipping\n");
	    next;
	    }
	@user_principal_name{"name", "realm"} = split("@", $_->get_value("userPrincipalName"));
	if ($user_principal_name{"realm"} !~ /^\Q$db_domain_entry{"name"}\E$/i)
	    {
	    print("[!] realm ".$user_principal_name{"realm"}." not matched the domain, skipping\n");
	    next;
	    }
	if (!is_username($user_principal_name{"name"}))
	    {
	    print("[!] ".$user_principal_name{"name"}." is not a valid email user name, skipping\n");
	    next;
	    }
	$dbh->do("INSERT INTO tmp_ad_object(name, fullname, guid, control_flags, time_changed) VALUES(?, ?, ?, ?, ?)",
	    undef,
	    $user_principal_name{"name"}, $_->get_value("displayName") // undef, $_->get_value("objectGUID"),
	    $_->get_value("userAccountControl"), $_->get_value("whenChanged"));
	die("3 SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
	}
    elsif ($_->get_value("isDeleted") =~ /^TRUE$/i)
	{
	$dbh->do("INSERT INTO tmp_ad_object(guid, deleted) VALUES(?, 1)",
	    undef,
	    $_->get_value("objectGUID"));
	}
    $max_oper_usn = $_->get_value("usnChanged") if ($max_oper_usn < $_->get_value("usnChanged"));
    }
$mesg->code && die("LDAP operation failed: ".$mesg->error."\n");

#Synchronize deleted
print("Synchronizing accounts (stage ".++$current_stage." of ".$max_stage.")\n");
$sth = $dbh->prepare("SELECT id, guid FROM tmp_ad_object WHERE deleted = 1");
die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
$sth->execute();
die("SQL operation failed: ".$sth->errstr."\n") if ($sth->state);
while (@db_ad_cache_entry{"id", "guid"} = $sth->fetchrow_array())
    {
    my $deleted = $dbh->do("DELETE FROM account WHERE domain_id = ? AND ad_guid = ? AND ad_sync_enabled = 1",
	undef,
	$db_domain_entry{"id"}, $db_ad_cache_entry{"guid"});
    die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
    if ($deleted > 0)
	{
	print("[X] an account with GUID {".GuidToString($db_ad_cache_entry{"guid"})."} has been deleted\n");
	}
    else
	{
	print("[I] an account with GUID {".GuidToString($db_ad_cache_entry{"guid"})."} was not deleted: not exists or not permitted\n");
	}
    }
die("SQL operation failed: ".$sth->errstr."\n") if ($sth->state);

#Synchronize changed
print("Synchronizing accounts (stage ".++$current_stage." of ".$max_stage.")\n");
$sth = $dbh->prepare(
    "SELECT id, name, fullname, guid, control_flags, time_changed FROM tmp_ad_object
	WHERE deleted = 0");
die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
$sth->execute();
die("SQL operation failed: ".$sth->errstr."\n") if ($sth->state);
while (@db_ad_cache_entry{"id", "name", "fullname", "guid", "control_flags", "time_changed"} =
    $sth->fetchrow_array())
    {
    my $is_enabled = 1;
    $is_enabled = 0 if ($db_ad_cache_entry{"control_flags"} & $account_control_flags{"ADS_UF_ACCOUNTDISABLE"});
    $dbh->begin_work or die("Begin work operation failed: ".$dbh->errstr."\n");
    my %db_account_entry_by_name;
    @db_account_entry_by_name{"id", "name", "ad_guid", "ad_sync_enabled", "ad_time_changed"} =
	$dbh->selectrow_array(
	    "SELECT id, name, ad_guid, ad_sync_enabled, ad_time_changed FROM account WHERE
		domain_id = ? AND name = ?",
	    undef,
	    $db_domain_entry{"id"}, $db_ad_cache_entry{"name"});
    die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
    my %db_account_entry_by_guid;
    @db_account_entry_by_guid{"id", "name", "ad_guid", "ad_sync_enabled", "ad_time_changed"} =
	$dbh->selectrow_array(
	    "SELECT id, name, ad_guid, ad_sync_enabled, ad_time_changed FROM account WHERE
		domain_id = ? AND ad_guid = ?",
	    undef,
	    $db_domain_entry{"id"}, $db_ad_cache_entry{"guid"});
    die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
    my %parsed_time_changed;
    $parsed_time_changed{"db"} = defined($db_account_entry_by_guid{"ad_time_changed"}) ?
	DateTime::Format::ISO8601->parse_datetime($db_account_entry_by_guid{"ad_time_changed"}) : undef;
    $parsed_time_changed{"ad"} = DateTime::Format::ISO8601->parse_datetime($db_ad_cache_entry{"time_changed"});
    my $account_is_new = 0;
    if (defined($db_account_entry_by_guid{"ad_sync_enabled"}) and !$db_account_entry_by_guid{"ad_sync_enabled"})
	{
	print("[I] can't modify ".$db_account_entry_by_guid{"name"}.": not permitted\n");
	}
    elsif (defined($parsed_time_changed{"db"}) and
	DateTime::compare($parsed_time_changed{"db"}, $parsed_time_changed{"ad"}) >= 0)
	{
	print("[I] won't modify ".$db_account_entry_by_guid{"name"}.": source out of date\n");
	}
    else
	{
	my $dup_exists = 0;
	$dup_exists = 1 if (defined($db_account_entry_by_name{"name"}) and
	    (!defined($db_account_entry_by_name{"ad_guid"}) or
	    $db_account_entry_by_name{"ad_guid"} !~ /^\Q$db_ad_cache_entry{"guid"}\E$/));
	if (defined($db_account_entry_by_guid{"id"}))
	    {
	    if ($dup_exists)
		{
		print("[!] can't modify ".$db_account_entry_by_guid{"name"}.": duplicate exists\n");
		}
	    else
		{
		print("[U] modifying ".$db_account_entry_by_guid{"name"}.", GUID {".
		    GuidToString($db_account_entry_by_guid{"ad_guid"})."}\n");
		$dbh->do("UPDATE account SET name = ?, fullname = ?, modified = CURRENT_TIMESTAMP,
		    active = ?, ad_time_changed = ? WHERE id = ?",
		    undef,
		    $db_ad_cache_entry{"name"}, $db_ad_cache_entry{"fullname"} // $db_ad_cache_entry{"name"},
		    $is_enabled, $db_ad_cache_entry{"time_changed"}, $db_account_entry_by_guid{"id"});
		die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
		}
	    }
	elsif (defined($db_account_entry_by_name{"id"}))
	    {
	    if (!defined($db_account_entry_by_name{"ad_guid"}))
		{
		if ($db_account_entry_by_name{"ad_sync_enabled"})
		    {
		    print("[U] binding ".$db_account_entry_by_name{"name"}." to GUID {".
		    $db_ad_cache_entry{"guid"}."}\n");
		    $dbh->do("UPDATE account SET name = ?, fullname = ?, modified = CURRENT_TIMESTAMP,
			active = ?, ad_guid = ?, ad_time_changed = ? WHERE id = ?",
			undef,
			$db_ad_cache_entry{"name"}, $db_ad_cache_entry{"fullname"} // $db_ad_cache_entry{"name"},
			$is_enabled, $db_ad_cache_entry{"guid"}, $db_ad_cache_entry{"time_changed"},
			$db_account_entry_by_name{"id"});
		    die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
		    }
		else
		    {
		    print("[I] can't bind ".$db_account_entry_by_name{"name"}." to GUID: not permitted\n");
		    }
		}
	    else
		{
		print("[!] can't modify ".$db_account_entry_by_name{"name"}.": duplicate exists\n");
		}
	    }
	else
	    {
	    print("[A] adding ".$db_ad_cache_entry{"name"}."\n");
	    $dbh->do("INSERT INTO account(domain_id, name, fullname, spooldir, created, modified, active,
		ad_guid, ad_time_changed) VALUES(?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, ?, ?, ?)",
		undef,
		$db_domain_entry{"id"}, $db_ad_cache_entry{"name"},
		$db_ad_cache_entry{"fullname"} // $db_ad_cache_entry{"name"}, GuidToString($db_ad_cache_entry{"guid"})."/",
		$is_enabled, $db_ad_cache_entry{"guid"}, $db_ad_cache_entry{"time_changed"});
	    die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
	    $account_is_new = 1;
	    }
	}
    $dbh->commit or die("Commit operation failed: ".$dbh->errstr."\n");
    if ($account_is_new)
	{
	my %mail = (smtp=>$smtp_srv, To=>$db_ad_cache_entry{"name"}."@".$db_domain_entry{"name"},
	    From=>"postmaster@".$db_domain_entry{"name"}, Subject=>"Welcome!",
	    Message=>"Hello, ".$db_ad_cache_entry{"name"}."@".$db_domain_entry{"name"}."!\nWelcome to e-mail system.");
	sendmail(%mail) or print("[!] can't send a greeting message: ".$Mail::Sendmail::error."\n");
	}
    }

#Update the tracking info only if we need it
if ($max_oper_usn > $db_dit_entry{"dit_usn"})
    {
    print("Saving the tracking state\n");
    $dbh->do("UPDATE usn_tracking SET dit_usn = ? WHERE id = ?", undef, $max_oper_usn, $db_dit_entry{"id"});
    die("SQL operation failed: ".$dbh->errstr."\n") if ($dbh->state);
    }

exit(0); # The End
