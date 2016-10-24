#!perl -w
#Version: 

use feature "switch";
use strict "vars";
use Config::IniFiles;
use File::Basename;
use Getopt::Long;
use DBI;
use Encode qw(decode encode);
use Data::Validate::Email qw(is_username is_domain);
use Mail::Sendmail;
use List::Util qw(min max);

@INC = (dirname($0), @INC);
require "devel_libemailmgr.pl";
our(%EXIT_CODES, %required_db);

my $ini_name = (split(/\./, basename($0)))[0].".ini";
my $cfg = Config::IniFiles->new( -file => dirname($0)."\\".$ini_name, -nocase => 1 )
	or exit_($EXIT_CODES{EXIT_INIT}, "���� ���樠����樨. �஢���� 䠩� \"$ini_name\"\n");
$cfg->val("connect", "host")
	or exit_($EXIT_CODES{EXIT_INIT}, "���� ���樠����樨: �� ��।���� ��� ��\n");
$cfg->val("connect", "database")
	or exit_($EXIT_CODES{EXIT_INIT}, "���� ���樠����樨: �� ��।����� ��\n");
$cfg->val("connect", "login")
	or exit_($EXIT_CODES{EXIT_INIT}, "���� ���樠����樨: �� ��।���� ����� ��\n");
$cfg->val("connect", "password")
	or exit_($EXIT_CODES{EXIT_INIT}, "���� ���樠����樨: �� ��।���� ��஫� ��\n");
my $dsn = "";
if ($cfg->val("connect", "port"))
	{
	$dsn = "DBI:mysql:database=".$cfg->val("connect", "database").";host=".
		$cfg->val("connect", "host").";port=".$cfg->val("connect", "port").
		";mysql_compression=1";
	}
else
	{
	$dsn = "DBI:mysql:database=".$cfg->val("connect", "database").";host=".
		$cfg->val("connect", "host").";mysql_compression=1";
	}

my %autogen_pass_len = (min => 8, max => 16);
$autogen_pass_len{min} = $cfg->val("password", "gen_min") if $cfg->val("password", "gen_min");
$autogen_pass_len{max} = $cfg->val("password", "gen_max") if $cfg->val("password", "gen_max");

my $dbh = DBI->connect($dsn, $cfg->val("connect", "login"), $cfg->val("connect", "password"), {PrintError => 0})
	or exit_($EXIT_CODES{EXIT_GENERAL}, "�訡�� ᮥ������� � ��: ".$DBI::errstr."\n");
$dbh->do("SET NAMES \'cp866\'")
	or exit_($EXIT_CODES{EXIT_SQLERROR}, "����������� �訡��: ".$dbh->errstr);
CheckDBCompat($dbh, @required_db{'name', 'vmajor', 'vminor', 'vpatch'});

#Need to rewrite with classes
my $context;
my $need_help = "";
my $need_version = "";
my @context_allowed = ("account", "domain", "acl");
my %actions = (query=>"", add=>"", del=>"", mod=>"");
my %vars = (name=>"", password=>"", password_enabled=>"", fullname=>"", domain=>"", active=>"", public=>"",
	ad_sync_enabled=>"");
my @ascii_vars = ("name", "password", "domain");
my @string_vars = ("name", "fullname", "password", "domain");
my %mods = (record_output=>"", yes_to_all=>"", show_password=>"", regen_password=>"");
sub CheckAction
	{
	my $key;
	my $keys_count = 0;
	my $action = shift;
	for $key(keys(%{$action}))
		{
		++$keys_count if $action->{$key};
		}
	return("no_action") if ($keys_count == 0);
	return("more_than_one") if ($keys_count > 1);
	for $key(keys(%{$action}))
		{
		return($key) if $action->{$key};
		}
	}

my $GetOptRes = GetOptions(
	"context|c=s"=>\$context,
	"query|q"=>\$actions{query},
	"add|a"=>\$actions{add},
	"del|d"=>\$actions{del},
	"mod|m"=>\$actions{mod},
	"name=s"=>\$vars{name},
	"password=s"=>\$vars{password},
	"fullname=s"=>\$vars{fullname},
	"domain=s"=>\$vars{domain},
	"active!"=>\$vars{active},
	"public!"=>\$vars{public},
	"passwordenabled!"=>\$vars{password_enabled},
	"adsyncenabled!"=>\$vars{ad_sync_enabled},
	"g"=>\$mods{regen_password},
	"r"=>\$mods{record_output},
	"y"=>\$mods{yes_to_all},
	"s"=>\$mods{show_password},
	"help|?"=>\$need_help,
	"v"=>\$need_version);
exit_($EXIT_CODES{EXIT_INIT},
	"�訡�� � ��������� ��ப�. ������ \"".basename($0)." --help\" ��� �뢮�� ᯨ᪠ ���祩\n")
	unless ($GetOptRes);
if ($need_help)
	{
	print(
	basename($0)."\n",
	"  [--context|-c=...]\n",
	"  <--query|-q | --add|-a | --del|-d | --mod|-m>\n",
	"  [--name=...[:...]] [--password=...] [--fullname=...] [--domain=...]\n",
	"  [--[no]active] [--[no]public] [--[no]passwordenabled] [--[no]adsyncenabled]\n",
	"  [-g] [-r] [-s] [-y] [-v]\n\n",
	"--context|-c  - ���⥪�� ���饭�� � ��. ����� �ਭ����� ���祭�� account ��� domain\n",
	"--query|-q    - ������� ���ଠ�� �� ��. ����� ����� ������� 蠡���� \"%\" � \"_\"\n",
	"                ��� �� ��㯯� ���� ��� �����筮�� ᨬ���� ᮮ⢥��⢥���. ��� \n",
	"                �࠭�஢���� �ᯮ������ ᨬ��� \"\\\". ������� ࠧ�襭� ��� ��ࠬ��஢\n",
	"                \"--name\" � \"--fullname\"\n",
	"--add|-a      - �������� ����� ������ ��� �����\n",
	"--del|-d      - 㤠���� ����� ������ ��� �����\n",
	"--mod|-m      - �������� ����� ������ ��� �����\n",
	"--name        - ��� �����塞�� ��⭮� ����� ��� ������*. ����� ���� ������ � �ଥ\n",
	"                \"���:���\" ��� ��२�������� �������饩 �����\n",
	"--password    - ��஫� � ��⭮� �����. �� ���������� ����� ����� ����������, �᫨ ��\n",
	"                㪠��� �\n",
	"--fullname    - ������ ��� ��⭮� �����*\n",
	"--domain      - ����� ��⭮� �����*\n",
	"--[no]active  - ��⨢�஢���/����⨢�஢��� ����� ������ ��� �����\n",
	"--[no]public  - �㡫������� ��� ��� ����� � ��饩 ���᭮� �����\n",
	"--[no]passwordenabled\n",
	"              - �ᯮ�짮���� ��஫� �� �� (� �� ��⥭�䨪��� AD)**\n",
	"--[no]adsyncenabled\n",
	"              - ࠧ���� ᨭ�஭����� � AD**\n",
	"-g            - ॣ����஢��� ��஫� (�믮������, ���� �᫨ ����� --password)\n",
	"-r            - �뢮���� १���� ����� � ���� ����ᥩ (� �� � ���� ⠡����)\n",
	"-s            - �⮡ࠦ��� ��஫� � १����� �����\n",
	"-y            - ᮣ������� � �ᥬ (������ ०��)\n",
	"-v            - �뢮� ���ᨨ ��\n\n",
	"-----\n",
	"* ��ࠬ��� ����� ���⢮���� � ���᪮��� �����\n",
	"** ��ࠬ��� ���뢠���� ⮫쪮 � ०��� ���������\n");
	exit;
	}
if ($need_version)
	{
	PrintMyVersion($dbh);
	exit;
	}
given (my $action = CheckAction(\%actions))
	{
	exit_($EXIT_CODES{EXIT_INPUT},
		"�� ��࠭� ����⢨�. ������ \"".basename($0)." --help\" ��� �뢮�� ᯨ᪠ ���祩\n")
		when ("no_action");
	exit_($EXIT_CODES{EXIT_INPUT},
		"��࠭� ����� ������ ����⢨�. ������ \"".basename($0)." --help\" ��� �뢮�� ᯨ᪠ ���祩\n")
		when ("more_than_one");
	}
foreach(@ascii_vars)
	{
	exit_($EXIT_CODES{EXIT_INPUT},
		"��६����� \"$_\" ����᪠�� ⮫쪮 ASCII\n") if nonascii($vars{$_});
	}
foreach(@string_vars)
	{
	$vars{$_} = trim($vars{$_});
	}

$context = $context ? $context : $cfg->val("query", "context");
exit_($EXIT_CODES{EXIT_INPUT},
	"�� ��।���� ���⥪��. ������ \"".basename($0)." --help\" ��� �뢮�� ᯨ᪠ ���祩\n")
	unless ($context);
$context = lc($context);
exit_($EXIT_CODES{EXIT_INPUT},
	"��������� ���⥪��: \"$context\". ������ \"".basename($0)." --help\" ��� �뢮�� ᯨ᪠ ���祩\n")
	unless ($context ~~ @context_allowed);
	
my @default_domain = $dbh->selectrow_array("SELECT name from domain, tab_defaults WHERE
	tab_defaults.tab_name = 'domain' AND tab_defaults.tab_id = domain.id")
	or exit_($EXIT_CODES{EXIT_SQLERROR}, "����������� �訡��: ".$dbh->errstr);
$vars{domain} = $vars{domain} ? $vars{domain} : ($cfg->val("query", "domain") ? $cfg->val("query", "domain") :
	$default_domain[0]);
exit_($EXIT_CODES{EXIT_INPUT}, "�� ��।���� �����\n") unless ($vars{domain});
$vars{fullname} = encode("cp866", decode("cp1251", $vars{fullname}));

if ($actions{query})
	{
	if ($context eq "account")
		{
		my ($sth, @result, @result_maxlen);
		$vars{name} = "\%" if $vars{name} eq "";
		$vars{fullname} = "\%" if $vars{fullname} eq "";
		$dbh->do("START TRANSACTION", undef) or exit_($EXIT_CODES{EXIT_SQLERROR},
			"����������� �訡��: ".$dbh->errstr);
#TAG: SQL
		@result_maxlen = $dbh->selectrow_array("SELECT MAX(CHAR_LENGTH(name)), MAX(CHAR_LENGTH(password)),
			MAX(CHAR_LENGTH(fullname)), 4 FROM account WHERE
			name LIKE ? and (fullname LIKE ? OR fullname IS NULL) AND domain_id =
			(SELECT id FROM domain WHERE name = ?) ORDER BY modified", undef,
			$vars{name}, $vars{fullname}, $vars{domain}) or exit_($EXIT_CODES{EXIT_SQLERROR},
			"����������� �訡��: ".$dbh->errstr);
		if (!defined($result_maxlen[0]))
				{
				print("��祣� �� �������\n");
				exit;
				}
		$result_maxlen[2] = ($result_maxlen[2] // 0); # normalization (protect from NULL)
		$result_maxlen[0] = min(32, $result_maxlen[0]); # good place for constant '32' is ini-file,
		$result_maxlen[2] = min(32, $result_maxlen[2]); # rather than in code
		$result_maxlen[1] = 5 unless ($mods{show_password});
#TAG: SQL
		$sth = $dbh->prepare("SELECT name, password, fullname, spooldir,
			CASE active WHEN TRUE THEN 'A' WHEN FALSE THEN '-' END,
			CASE public WHEN TRUE THEN 'P' WHEN FALSE THEN '-' END,
			CASE password_enabled WHEN TRUE THEN 'S' WHEN FALSE THEN '-' END,
			CASE ad_sync_enabled WHEN TRUE THEN 'D' WHEN FALSE THEN '-' END,
			created, modified, accessed
			FROM account WHERE
			name LIKE ? and (fullname LIKE ? OR fullname IS NULL) AND domain_id = 
			(SELECT id FROM domain WHERE name = ?) ORDER BY modified")
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "����������� �訡��: ".$sth->errstr);
		$sth->execute($vars{name}, $vars{fullname}, $vars{domain})
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "����������� �訡��: ".$sth->errstr);
		$dbh->do("COMMIT", undef)
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "����������� �訡��: ".$dbh->errstr);
		print("�����: $vars{domain}\n\n");
		WriteResultTable(["���", "��஫�", "������ ���", "�����"],
			\@result_maxlen, undef, "HEADER") unless ($mods{record_output});
		while (@result = $sth->fetchrow_array)
			{
			$result[1] = "*****" unless ($mods{show_password});
			$result[2] = $result[2] // ""; # normalization (protect from NULL)
			if ($mods{record_output})
				{
				WriteResultRecord(["���", "��஫�", "������ ���", "��⠫��", "��⨢��", "�㡫���",
					"��஫� ������⢮���", "����஭����� � AD", "������", "�������", "���饭"], {
					"���" => $result[0]."@".$vars{domain},
					"��஫�" => $result[1],
					"������ ���" => $result[2],
					"��⠫��" => $result[3],
					"��⨢��" => ($result[4] eq "A" ? "��" : "���"),
					"�㡫���" => ($result[5] eq "P" ? "��" : "���"),
					"��஫� ������⢮���" => ($result[6] eq "S" ? "��" : "���"),
					"����஭����� � AD" => ($result[7] eq "D" ? "��" : "���"),
					"������" => $result[8],
					"�������" => $result[9],
					"���饭" => $result[10]});
				print("\n");
				}
			else
				{
				WriteResultTable(["���", "��஫�", "������ ���", "�����"],
					\@result_maxlen, [$result[0], $result[1], $result[2], $result[4].$result[5].$result[6].$result[7]], "DATA");
				}
			}
		WriteResultTable(["���", "��஫�", "������ ���", "�����"],
			\@result_maxlen, undef, "FOOTER") unless ($mods{record_output});
		}
	if ($context eq "domain")
		{
		my ($sth, @result, @result_maxlen);
		$vars{name} = "\%" if $vars{name} eq "";
		$dbh->do("START TRANSACTION", undef)
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "����������� �訡��: ".$dbh->errstr);
#TAG: SQL
		@result_maxlen = $dbh->selectrow_array("SELECT MAX(CHAR_LENGTH(name)), 3 FROM domain WHERE
			name LIKE ? ORDER BY modified", undef, $vars{name})
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "����������� �訡��: ".$dbh->errstr);
		unless (defined($result_maxlen[0]))
				{
				print("��祣� �� �������\n");
				exit;
				}
		$result_maxlen[0] = min(32, $result_maxlen[0]); # good place for constant '32' is ini-file,
                                                        # rather than in code
#TAG: SQL
		$sth = $dbh->prepare("SELECT name, spooldir,
			CASE active WHEN TRUE THEN 'A' WHEN FALSE THEN '-' END,
			CASE public WHEN TRUE THEN 'P' WHEN FALSE THEN '-' END,
			CASE ad_sync_enabled WHEN TRUE THEN 'D' WHEN FALSE THEN '-' END,
			created, modified
			FROM domain WHERE name LIKE ? ORDER BY modified")
				or exit_($EXIT_CODES{EXIT_SQLERROR}, "����������� �訡��: ".$sth->errstr);
		$sth->execute($vars{name})
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "����������� �訡��: ".$sth->errstr);
		$dbh->do("COMMIT", undef)
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "����������� �訡��: ".$dbh->errstr);
		WriteResultTable(["���", "�����"], \@result_maxlen, undef, "HEADER")
			unless ($mods{record_output});
		while (@result = $sth->fetchrow_array)
			{
			if ($mods{record_output})
				{
				WriteResultRecord(["���", "��⠫��", "��⨢��", "�㡫���", "����஭����� � AD",
					"������", "�������"], {
					"���" => $result[0],
					"��⠫��" => $result[1],
					"��⨢��" => ($result[2] eq "A" ? "��" : "���"),
					"�㡫���" => ($result[3] eq "P" ? "��" : "���"),
					"����஭����� � AD" => ($result[4] eq "D" ? "��" : "���"),
					"������" => $result[5],
					"�������" => $result[6]});
				print("\n");
				}
			else
				{
				WriteResultTable(["���", "�����"], \@result_maxlen,
					[$result[0], $result[2].$result[3].$result[4]], "DATA");
				}
			}
			WriteResultTable(["���", "�����"], \@result_maxlen, undef, "FOOTER")
				unless ($mods{record_output});
		}
	}

if ($actions{add})
	{
	exit_($EXIT_CODES{EXIT_INPUT}, "�� ������ ��� (name)\n") if ($vars{name} eq "");
	if ($context eq "account")
		{
		exit_($EXIT_CODES{EXIT_INPUT}, "\"$vars{name}\" �� ���� �����⨬� ������ ��� ��⭮� �����\n")
			unless (is_username($vars{name}));
		$vars{password} = GeneratePassword($autogen_pass_len{min}, $autogen_pass_len{max}) if ($vars{password} eq "");
		if ($vars{fullname} eq "")
			{
			print("�����: �� ������ ������ ��� (fullname). ���祭�� �� 㬮�砭��: \"$vars{name}\"\n\n")
				unless ($mods{yes_to_all});
			$vars{fullname} = $vars{name};
			}
		unless ($mods{yes_to_all})
			{
			print("����⪠ �������� ����� ����� ������ \"$vars{name}\@$vars{domain}\" � ᫥���騬� ४����⠬�:\n\n"),
			WriteResultRecord(["���", "�����", "��஫�", "������ ���", "��⨢��", "�㡫���"], {
				"���" => $vars{name},
				"�����" => $vars{domain},
				"��஫�" => $vars{password},
				"������ ���" => $vars{fullname},
				"��⨢��" => ($vars{active} ne "" ? ($vars{active} ? "��" : "���") : "�����."),
				"�㡫���" => ($vars{public} ne "" ? ($vars{public} ? "��" : "���") : "�����.")});
			print("\n");
			print("[�⬥��]\n") and exit unless(CheckYes());
			print("\n");
			print("�믮������... ");
			}
		$dbh->do("CALL account_add(?, ?, ?, ?, ?, ?)", undef,
			$vars{domain}, $vars{name}, $vars{password}, $vars{fullname},
			($vars{active} ne "" ? $vars{active} : undef), ($vars{public} ne "" ? $vars{public} : undef))
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "����������� �訡��: ".$dbh->errstr);
		given(GetSProcStatus($dbh))
			{
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "����� �� ����� � ��� ������ �� 㬮�砭��\n") when (/NODOMAIN/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "����� �� ������ � ⠡��� �������\n") when (/NXDOMAIN/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "��⭠� ������ 㦥 �������\n") when (/ACCEXISTS/i);
			}
		print("��⮢� \n���� �ਢ���⢨�... ") unless ($mods{yes_to_all});
#		my %mail = (smtp => $cfg->val("connect", "host"), To => "$vars{name}\@$vars{domain}",
#			From => "postmaster\@$vars{domain}", Subject => "Welcome!",
#			Message => "Hello, $vars{name}\@$vars{domain}!\nWelcome to e-mail system.");
#		sendmail(%mail)
#			or exit_($EXIT_CODES{EXIT_GENERAL}, "Error sending welcome message: ".$Mail::Sendmail::error);
		print("��⮢� \n") unless ($mods{yes_to_all});
		}
	if ($context eq "domain")
		{
		exit_($EXIT_CODES{EXIT_INPUT}, "\"$vars{name}\" �� ���� �����⨬� ������ ��� ������\n")
			unless (is_domain($vars{name}));
		unless ($mods{yes_to_all})
			{
			print("����⪠ �������� ���� ����� \"$vars{name}\" � ᫥���騬� ४����⠬�:\n\n"),
			WriteResultRecord(["���", "��⨢��", "�㡫���"], {
				"���" => $vars{name},
				"��⨢��" => ($vars{active} ne "" ? ($vars{active} ? "��" : "���") : "�����."),
				"�㡫���" => ($vars{public} ne "" ? ($vars{public} ? "��" : "���") : "�����.")});
			print("\n");
			print("[�⬥��]\n") and exit unless(CheckYes());
			print("\n");
			print("�믮������... ");
			}
		$dbh->do("CALL domain_add(?, ?, ?)", undef, $vars{name},
			($vars{active} ne "" ? $vars{active} : undef), ($vars{public} ne "" ? $vars{public} : undef))
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "����������� �訡��: ".$dbh->errstr);
		given(GetSProcStatus($dbh))
			{
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "����� 㦥 �������\n") when (/DOMAINEXISTS/i);
			}
		print("��⮢� \n") unless ($mods{yes_to_all});
		}
	}

if ($actions{del})
	{
	exit_($EXIT_CODES{EXIT_INPUT}, "�� ������ ��� (name)\n") if ($vars{name} eq "");
	if ($context eq "account")
		{
		unless ($mods{yes_to_all})
			{
			print("����⪠ 㤠����� ��⭮� ����� \"$vars{name}\@$vars{domain}\" � ᫥���騬� ४����⠬�:\n\n"),
			WriteResultRecord(["���", "�����"], {
				"���" => $vars{name},
				"�����" => $vars{domain}});
			print("\n");
			print("[�⬥��]\n") and exit unless(CheckYes());
			print("\n");
			print("�믮������... ");
			}
		$dbh->do("CALL account_del(?, ?)", undef, $vars{domain}, $vars{name})
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "����������� �訡��: ".$dbh->errstr);
		given(GetSProcStatus($dbh))
			{
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "����� �� ����� � ��� ������ �� 㬮�砭��\n") when (/NODOMAIN/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "����� �� ������ � ⠡��� �������\n") when (/NXDOMAIN/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "��⭠� ������ �� �������\n") when (/NXACCOUNT/i);
			}
		print("��⮢� \n") unless ($mods{yes_to_all});
		}
	if ($context eq "domain")
		{
		unless ($mods{yes_to_all})
			{
			print("����⪠ 㤠����� ������ � ᫥���騬� ४����⠬�:\n\n");
			WriteResultRecord(["���"], {
				"���" => $vars{name}});
			print("\n");
			print("[�⬥��]\n") and exit unless(CheckYes());
			print("\n");
			print("�믮������... ");
			}
		$dbh->do("CALL domain_del(?)", undef, $vars{name})
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "����������� �訡��: ".$dbh->errstr);
		given(GetSProcStatus($dbh))
			{
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "����� �� �������\n") when (/NXDOMAIN/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "� ������ �� �� �������� ���� �����\n") when (/ACCEXISTS/i);
			}		
		print("��⮢� \n") unless ($mods{yes_to_all});
		}
	}

if ($actions{mod})
	{
	my @name_parts = split(/:/, $vars{name}, 2);
	$name_parts[0] //= "";
	$name_parts[1] //= "";
	exit_($EXIT_CODES{EXIT_INPUT}, "�� ������ ��� (name)\n") if ($name_parts[0] eq "");
	@name_parts = (trim($name_parts[0]), trim($name_parts[1]));
	if ($context eq "account")
		{
		exit_($EXIT_CODES{EXIT_INPUT}, "\"$name_parts[1]\" �� ���� �����⨬� ������ ��� ��⭮� �����\n")
			if ($name_parts[1] ne "" and !is_username($name_parts[1]));
		$vars{password} = GeneratePassword($autogen_pass_len{min}, $autogen_pass_len{max}) if ($mods{regen_password});
		unless ($mods{yes_to_all})
			{
			my @rqs_all_names = ("���", "��஫�", "������ ���", "��⨢��", "�㡫���",
				"��஫� ������⢮���", "����஭����� � AD"); # Ordered list of names of all requisites
			my %rqs_values = (
				"���" => $name_parts[1],
				"��஫�" => $vars{password},
				"������ ���" => $vars{fullname},
				"��⨢��" => $vars{active} ne "" ? ($vars{active} ? "��" : "���") : $vars{active},
				"�㡫���" => $vars{public} ne "" ? ($vars{public} ? "��" : "���") : $vars{public},
				"��஫� ������⢮���" => $vars{password_enabled} ne "" ? ($vars{password_enabled} ? "��" : "���") : "",
				"����஭����� � AD" => $vars{ad_sync_enabled} ne "" ? ($vars{ad_sync_enabled} ? "��" : "���") : ""
				); # Hash of requisites (name => value)
			my @rqs_names; # Ordered list of names of requisites to be changed
			foreach(keys(%rqs_values))
				{
				delete($rqs_values{$_}) if ($rqs_values{$_} eq "");
				}
			foreach(@rqs_all_names)
				{
				push(@rqs_names, $_) if exists($rqs_values{$_});
				}				
			print("����⪠ �������� ����� ������ \"$name_parts[0]\@$vars{domain}\". ���� ४������:\n\n");
			if (scalar(@rqs_names))
				{
				WriteResultRecord(\@rqs_names, \%rqs_values);
				}
			else
				{
				print("[����]\n");
				}
			print("\n");
			print("[�⬥��]\n") and exit unless(CheckYes());
			print("\n");
			print("�믮������... ");
			}
		$dbh->do("CALL account_mod(?, ?, ?, ?, ?, ?, ?, ?, ?)", undef,
			$vars{domain},
			$name_parts[0],
			$name_parts[1] ne "" ? $name_parts[1] : undef,
			$vars{password} ne "" ? $vars{password} : undef,
			$vars{fullname} ne "" ? $vars{fullname} : undef,
			$vars{active} ne "" ? $vars{active} : undef,
			$vars{public} ne "" ? $vars{public} : undef,
			$vars{password_enabled} ne "" ? $vars{password_enabled} : undef,
			$vars{ad_sync_enabled} ne "" ? $vars{ad_sync_enabled} : undef)
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "����������� �訡��: ".$dbh->errstr);
		given(GetSProcStatus($dbh))
			{
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "����� �� ����� � ��� ������ �� 㬮�砭��\n") when (/NODOMAIN/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "����� �� ������ � ⠡��� �������\n") when (/NXDOMAIN/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "��祣� ������\n") when (/NONEWDATA/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "��⭠� ������ �� �������\n") when (/NXACCOUNT/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "��⭠� ������ � ⠪�� ������ 㦥 �������\n") when (/ACCEXISTS/i);
			}
		print("��⮢� \n") unless ($mods{yes_to_all});
		}
	if ($context eq "domain")
		{
		exit_($EXIT_CODES{EXIT_INPUT}, "\"$name_parts[1]\" �� ���� �����⨬� ������ ��� ������\n")
			if ($name_parts[1] ne "" and !is_domain($name_parts[1]));
		unless ($mods{yes_to_all})
			{
			my @rqs_all_names = ("���", "��⨢��", "�㡫���", "����஭����� � AD"); # Ordered list of names of all requisites
			my %rqs_values = (
				"���" => $name_parts[1],
				"��⨢��" => $vars{active} ne "" ? ($vars{active} ? "��" : "���") : $vars{active},
				"�㡫���" => $vars{public} ne "" ? ($vars{public} ? "��" : "���") : $vars{public},
				"����஭����� � AD" => $vars{ad_sync_enabled} ne "" ? ($vars{ad_sync_enabled} ? "��" : "���") : ""
				); # Hash of requisites (name => value)
			my @rqs_names; # Ordered list of names of requisites to be changed
			foreach(keys(%rqs_values))
				{
				delete($rqs_values{$_}) if ($rqs_values{$_} eq "");
				}
			foreach(@rqs_all_names)
				{
				push(@rqs_names, $_) if exists($rqs_values{$_});
				}
			print("����⪠ �������� ����� \"$name_parts[0]\". ���� ४������:\n\n");
			if (scalar(@rqs_names))
				{
				WriteResultRecord(\@rqs_names, \%rqs_values);
				}
			else
				{
				print("[����]\n");
				}
			print("\n");
			print("[�⬥��]\n") and exit unless(CheckYes());
			print("\n");
			print("�믮������... ");
			}
		$dbh->do("CALL domain_mod(?, ?, ?, ?, ?)", undef,
			$name_parts[0],
			$name_parts[1] ne "" ? $name_parts[1] : undef,
			$vars{active} ne "" ? $vars{active} : undef,
			$vars{public} ne "" ? $vars{public} : undef,
			$vars{ad_sync_enabled} ne "" ? $vars{ad_sync_enabled} : undef)
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "����������� �訡��: ".$dbh->errstr);
		given(GetSProcStatus($dbh))
			{
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "��祣� ������\n") when (/NONEWDATA/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "����� �� �������\n") when (/NXDOMAIN/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "����� � ⠪�� ������ 㦥 �������\n") when (/DOMAINEXISTS/i);
			}
		print("��⮢� \n") unless ($mods{yes_to_all});
		}
	}
