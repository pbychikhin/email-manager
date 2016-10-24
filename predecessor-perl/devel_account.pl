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
	or exit_($EXIT_CODES{EXIT_INIT}, "Сбой инициализации. Проверьте файл \"$ini_name\"\n");
$cfg->val("connect", "host")
	or exit_($EXIT_CODES{EXIT_INIT}, "Сбой инициализации: не определен хост БД\n");
$cfg->val("connect", "database")
	or exit_($EXIT_CODES{EXIT_INIT}, "Сбой инициализации: не определена БД\n");
$cfg->val("connect", "login")
	or exit_($EXIT_CODES{EXIT_INIT}, "Сбой инициализации: не определен логин БД\n");
$cfg->val("connect", "password")
	or exit_($EXIT_CODES{EXIT_INIT}, "Сбой инициализации: не определен пароль БД\n");
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
	or exit_($EXIT_CODES{EXIT_GENERAL}, "Ошибка соединения с БД: ".$DBI::errstr."\n");
$dbh->do("SET NAMES \'cp866\'")
	or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
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
	"Ошибка в командной строке. Введите \"".basename($0)." --help\" для вывода списка ключей\n")
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
	"--context|-c  - контекст обращения к БД. Может принимать значения account или domain\n",
	"--query|-q    - запросить информацию из БД. Запрос может включать шаблоны \"%\" и \"_\"\n",
	"                для любой группы либо любого одиночного символа соответственно. Для \n",
	"                экранирования используется символ \"\\\". Шаблоны разрешены для параметров\n",
	"                \"--name\" и \"--fullname\"\n",
	"--add|-a      - добавить учетную запись или домен\n",
	"--del|-d      - удалить учетную запись или домен\n",
	"--mod|-m      - изменить учетную запись или домен\n",
	"--name        - имя изменяемой учетной записи или домена*. Может быть задано в форме\n",
	"                \"имя:имя\" для переименовани существующей записи\n",
	"--password    - пароль к учетной записи. При добавлении новой записи генерируется, если не\n",
	"                указан явно\n",
	"--fullname    - полное имя учетной записи*\n",
	"--domain      - домен учетной записи*\n",
	"--[no]active  - активировать/деактивировать учетную запись или домен\n",
	"--[no]public  - публиковать или нет данные в общей адресной книге\n",
	"--[no]passwordenabled\n",
	"              - использовать пароль из БД (а не аутентификацию AD)**\n",
	"--[no]adsyncenabled\n",
	"              - разрешить синхронизацию с AD**\n",
	"-g            - регенерировать пароль (выполняется, даже если задан --password)\n",
	"-r            - выводить результат запроса в виде записей (а не в виде таблицы)\n",
	"-s            - отображать пароль в результатах запроса\n",
	"-y            - соглашаться со всем (пакетный режим)\n",
	"-v            - вывод версии ПО\n\n",
	"-----\n",
	"* параметр может участвовать в поисковом запросе\n",
	"** параметр учитывается только в режиме изменения\n");
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
		"Не выбрано действие. Введите \"".basename($0)." --help\" для вывода списка ключей\n")
		when ("no_action");
	exit_($EXIT_CODES{EXIT_INPUT},
		"Выбрано более одного действия. Введите \"".basename($0)." --help\" для вывода списка ключей\n")
		when ("more_than_one");
	}
foreach(@ascii_vars)
	{
	exit_($EXIT_CODES{EXIT_INPUT},
		"Переменная \"$_\" допускает только ASCII\n") if nonascii($vars{$_});
	}
foreach(@string_vars)
	{
	$vars{$_} = trim($vars{$_});
	}

$context = $context ? $context : $cfg->val("query", "context");
exit_($EXIT_CODES{EXIT_INPUT},
	"Не определен контекст. Введите \"".basename($0)." --help\" для вывода списка ключей\n")
	unless ($context);
$context = lc($context);
exit_($EXIT_CODES{EXIT_INPUT},
	"Неизвестный контекст: \"$context\". Введите \"".basename($0)." --help\" для вывода списка ключей\n")
	unless ($context ~~ @context_allowed);
	
my @default_domain = $dbh->selectrow_array("SELECT name from domain, tab_defaults WHERE
	tab_defaults.tab_name = 'domain' AND tab_defaults.tab_id = domain.id")
	or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
$vars{domain} = $vars{domain} ? $vars{domain} : ($cfg->val("query", "domain") ? $cfg->val("query", "domain") :
	$default_domain[0]);
exit_($EXIT_CODES{EXIT_INPUT}, "Не определен домен\n") unless ($vars{domain});
$vars{fullname} = encode("cp866", decode("cp1251", $vars{fullname}));

if ($actions{query})
	{
	if ($context eq "account")
		{
		my ($sth, @result, @result_maxlen);
		$vars{name} = "\%" if $vars{name} eq "";
		$vars{fullname} = "\%" if $vars{fullname} eq "";
		$dbh->do("START TRANSACTION", undef) or exit_($EXIT_CODES{EXIT_SQLERROR},
			"Неожиданная ошибка: ".$dbh->errstr);
#TAG: SQL
		@result_maxlen = $dbh->selectrow_array("SELECT MAX(CHAR_LENGTH(name)), MAX(CHAR_LENGTH(password)),
			MAX(CHAR_LENGTH(fullname)), 4 FROM account WHERE
			name LIKE ? and (fullname LIKE ? OR fullname IS NULL) AND domain_id =
			(SELECT id FROM domain WHERE name = ?) ORDER BY modified", undef,
			$vars{name}, $vars{fullname}, $vars{domain}) or exit_($EXIT_CODES{EXIT_SQLERROR},
			"Неожиданная ошибка: ".$dbh->errstr);
		if (!defined($result_maxlen[0]))
				{
				print("Ничего не найдено\n");
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
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$sth->errstr);
		$sth->execute($vars{name}, $vars{fullname}, $vars{domain})
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$sth->errstr);
		$dbh->do("COMMIT", undef)
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
		print("Домен: $vars{domain}\n\n");
		WriteResultTable(["Имя", "Пароль", "Полное имя", "Флаги"],
			\@result_maxlen, undef, "HEADER") unless ($mods{record_output});
		while (@result = $sth->fetchrow_array)
			{
			$result[1] = "*****" unless ($mods{show_password});
			$result[2] = $result[2] // ""; # normalization (protect from NULL)
			if ($mods{record_output})
				{
				WriteResultRecord(["Имя", "Пароль", "Полное имя", "Каталог", "Активный", "Публичный",
					"Пароль задействован", "Синхронизация с AD", "Создан", "Изменен", "Посещен"], {
					"Имя" => $result[0]."@".$vars{domain},
					"Пароль" => $result[1],
					"Полное имя" => $result[2],
					"Каталог" => $result[3],
					"Активный" => ($result[4] eq "A" ? "Да" : "Нет"),
					"Публичный" => ($result[5] eq "P" ? "Да" : "Нет"),
					"Пароль задействован" => ($result[6] eq "S" ? "Да" : "Нет"),
					"Синхронизация с AD" => ($result[7] eq "D" ? "Да" : "Нет"),
					"Создан" => $result[8],
					"Изменен" => $result[9],
					"Посещен" => $result[10]});
				print("\n");
				}
			else
				{
				WriteResultTable(["Имя", "Пароль", "Полное имя", "Флаги"],
					\@result_maxlen, [$result[0], $result[1], $result[2], $result[4].$result[5].$result[6].$result[7]], "DATA");
				}
			}
		WriteResultTable(["Имя", "Пароль", "Полное имя", "Флаги"],
			\@result_maxlen, undef, "FOOTER") unless ($mods{record_output});
		}
	if ($context eq "domain")
		{
		my ($sth, @result, @result_maxlen);
		$vars{name} = "\%" if $vars{name} eq "";
		$dbh->do("START TRANSACTION", undef)
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
#TAG: SQL
		@result_maxlen = $dbh->selectrow_array("SELECT MAX(CHAR_LENGTH(name)), 3 FROM domain WHERE
			name LIKE ? ORDER BY modified", undef, $vars{name})
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
		unless (defined($result_maxlen[0]))
				{
				print("Ничего не найдено\n");
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
				or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$sth->errstr);
		$sth->execute($vars{name})
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$sth->errstr);
		$dbh->do("COMMIT", undef)
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
		WriteResultTable(["Имя", "Флаги"], \@result_maxlen, undef, "HEADER")
			unless ($mods{record_output});
		while (@result = $sth->fetchrow_array)
			{
			if ($mods{record_output})
				{
				WriteResultRecord(["Имя", "Каталог", "Активный", "Публичный", "Синхронизация с AD",
					"Создан", "Изменен"], {
					"Имя" => $result[0],
					"Каталог" => $result[1],
					"Активный" => ($result[2] eq "A" ? "Да" : "Нет"),
					"Публичный" => ($result[3] eq "P" ? "Да" : "Нет"),
					"Синхронизация с AD" => ($result[4] eq "D" ? "Да" : "Нет"),
					"Создан" => $result[5],
					"Изменен" => $result[6]});
				print("\n");
				}
			else
				{
				WriteResultTable(["Имя", "Флаги"], \@result_maxlen,
					[$result[0], $result[2].$result[3].$result[4]], "DATA");
				}
			}
			WriteResultTable(["Имя", "Флаги"], \@result_maxlen, undef, "FOOTER")
				unless ($mods{record_output});
		}
	}

if ($actions{add})
	{
	exit_($EXIT_CODES{EXIT_INPUT}, "Не задано имя (name)\n") if ($vars{name} eq "");
	if ($context eq "account")
		{
		exit_($EXIT_CODES{EXIT_INPUT}, "\"$vars{name}\" не является допустимым именем для учетной записи\n")
			unless (is_username($vars{name}));
		$vars{password} = GeneratePassword($autogen_pass_len{min}, $autogen_pass_len{max}) if ($vars{password} eq "");
		if ($vars{fullname} eq "")
			{
			print("Важно: не задано полное имя (fullname). Значение по умолчанию: \"$vars{name}\"\n\n")
				unless ($mods{yes_to_all});
			$vars{fullname} = $vars{name};
			}
		unless ($mods{yes_to_all})
			{
			print("Попытка добавить новую учетную запись \"$vars{name}\@$vars{domain}\" со следующими реквизитами:\n\n"),
			WriteResultRecord(["Имя", "Домен", "Пароль", "Полное имя", "Активный", "Публичный"], {
				"Имя" => $vars{name},
				"Домен" => $vars{domain},
				"Пароль" => $vars{password},
				"Полное имя" => $vars{fullname},
				"Активный" => ($vars{active} ne "" ? ($vars{active} ? "Да" : "Нет") : "Умолч."),
				"Публичный" => ($vars{public} ne "" ? ($vars{public} ? "Да" : "Нет") : "Умолч.")});
			print("\n");
			print("[Отмена]\n") and exit unless(CheckYes());
			print("\n");
			print("Выполнение... ");
			}
		$dbh->do("CALL account_add(?, ?, ?, ?, ?, ?)", undef,
			$vars{domain}, $vars{name}, $vars{password}, $vars{fullname},
			($vars{active} ne "" ? $vars{active} : undef), ($vars{public} ne "" ? $vars{public} : undef))
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
		given(GetSProcStatus($dbh))
			{
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Домен не задан и нет домена по умолчанию\n") when (/NODOMAIN/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Домен не найден в таблице доменов\n") when (/NXDOMAIN/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Учетная запись уже существует\n") when (/ACCEXISTS/i);
			}
		print("готово \nШлем приветствие... ") unless ($mods{yes_to_all});
#		my %mail = (smtp => $cfg->val("connect", "host"), To => "$vars{name}\@$vars{domain}",
#			From => "postmaster\@$vars{domain}", Subject => "Welcome!",
#			Message => "Hello, $vars{name}\@$vars{domain}!\nWelcome to e-mail system.");
#		sendmail(%mail)
#			or exit_($EXIT_CODES{EXIT_GENERAL}, "Error sending welcome message: ".$Mail::Sendmail::error);
		print("готово \n") unless ($mods{yes_to_all});
		}
	if ($context eq "domain")
		{
		exit_($EXIT_CODES{EXIT_INPUT}, "\"$vars{name}\" не является допустимым именем для домена\n")
			unless (is_domain($vars{name}));
		unless ($mods{yes_to_all})
			{
			print("Попытка добавить новый домен \"$vars{name}\" со следующими реквизитами:\n\n"),
			WriteResultRecord(["Имя", "Активный", "Публичный"], {
				"Имя" => $vars{name},
				"Активный" => ($vars{active} ne "" ? ($vars{active} ? "Да" : "Нет") : "Умолч."),
				"Публичный" => ($vars{public} ne "" ? ($vars{public} ? "Да" : "Нет") : "Умолч.")});
			print("\n");
			print("[Отмена]\n") and exit unless(CheckYes());
			print("\n");
			print("Выполнение... ");
			}
		$dbh->do("CALL domain_add(?, ?, ?)", undef, $vars{name},
			($vars{active} ne "" ? $vars{active} : undef), ($vars{public} ne "" ? $vars{public} : undef))
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
		given(GetSProcStatus($dbh))
			{
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Домен уже существует\n") when (/DOMAINEXISTS/i);
			}
		print("готово \n") unless ($mods{yes_to_all});
		}
	}

if ($actions{del})
	{
	exit_($EXIT_CODES{EXIT_INPUT}, "Не задано имя (name)\n") if ($vars{name} eq "");
	if ($context eq "account")
		{
		unless ($mods{yes_to_all})
			{
			print("Попытка удаления учетной записи \"$vars{name}\@$vars{domain}\" со следующими реквизитами:\n\n"),
			WriteResultRecord(["Имя", "Домен"], {
				"Имя" => $vars{name},
				"Домен" => $vars{domain}});
			print("\n");
			print("[Отмена]\n") and exit unless(CheckYes());
			print("\n");
			print("Выполнение... ");
			}
		$dbh->do("CALL account_del(?, ?)", undef, $vars{domain}, $vars{name})
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
		given(GetSProcStatus($dbh))
			{
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Домен не задан и нет домена по умолчанию\n") when (/NODOMAIN/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Домен не найден в таблице доменов\n") when (/NXDOMAIN/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Учетная запись не существует\n") when (/NXACCOUNT/i);
			}
		print("готово \n") unless ($mods{yes_to_all});
		}
	if ($context eq "domain")
		{
		unless ($mods{yes_to_all})
			{
			print("Попытка удаления домена со следующими реквизитами:\n\n");
			WriteResultRecord(["Имя"], {
				"Имя" => $vars{name}});
			print("\n");
			print("[Отмена]\n") and exit unless(CheckYes());
			print("\n");
			print("Выполнение... ");
			}
		$dbh->do("CALL domain_del(?)", undef, $vars{name})
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
		given(GetSProcStatus($dbh))
			{
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Домен не существует\n") when (/NXDOMAIN/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "В домене все еще существуют учетные записи\n") when (/ACCEXISTS/i);
			}		
		print("готово \n") unless ($mods{yes_to_all});
		}
	}

if ($actions{mod})
	{
	my @name_parts = split(/:/, $vars{name}, 2);
	$name_parts[0] //= "";
	$name_parts[1] //= "";
	exit_($EXIT_CODES{EXIT_INPUT}, "Не задано имя (name)\n") if ($name_parts[0] eq "");
	@name_parts = (trim($name_parts[0]), trim($name_parts[1]));
	if ($context eq "account")
		{
		exit_($EXIT_CODES{EXIT_INPUT}, "\"$name_parts[1]\" не является допустимым именем для учетной записи\n")
			if ($name_parts[1] ne "" and !is_username($name_parts[1]));
		$vars{password} = GeneratePassword($autogen_pass_len{min}, $autogen_pass_len{max}) if ($mods{regen_password});
		unless ($mods{yes_to_all})
			{
			my @rqs_all_names = ("Имя", "Пароль", "Полное имя", "Активный", "Публичный",
				"Пароль задействован", "Синхронизация с AD"); # Ordered list of names of all requisites
			my %rqs_values = (
				"Имя" => $name_parts[1],
				"Пароль" => $vars{password},
				"Полное имя" => $vars{fullname},
				"Активный" => $vars{active} ne "" ? ($vars{active} ? "Да" : "Нет") : $vars{active},
				"Публичный" => $vars{public} ne "" ? ($vars{public} ? "Да" : "Нет") : $vars{public},
				"Пароль задействован" => $vars{password_enabled} ne "" ? ($vars{password_enabled} ? "Да" : "Нет") : "",
				"Синхронизация с AD" => $vars{ad_sync_enabled} ne "" ? ($vars{ad_sync_enabled} ? "Да" : "Нет") : ""
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
			print("Попытка изменить учетную запись \"$name_parts[0]\@$vars{domain}\". Новые реквизиты:\n\n");
			if (scalar(@rqs_names))
				{
				WriteResultRecord(\@rqs_names, \%rqs_values);
				}
			else
				{
				print("[Пусто]\n");
				}
			print("\n");
			print("[Отмена]\n") and exit unless(CheckYes());
			print("\n");
			print("Выполнение... ");
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
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
		given(GetSProcStatus($dbh))
			{
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Домен не задан и нет домена по умолчанию\n") when (/NODOMAIN/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Домен не найден в таблице доменов\n") when (/NXDOMAIN/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Нечего менять\n") when (/NONEWDATA/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Учетная запись не существует\n") when (/NXACCOUNT/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Учетная запись с таким именем уже существует\n") when (/ACCEXISTS/i);
			}
		print("готово \n") unless ($mods{yes_to_all});
		}
	if ($context eq "domain")
		{
		exit_($EXIT_CODES{EXIT_INPUT}, "\"$name_parts[1]\" не является допустимым именем для домена\n")
			if ($name_parts[1] ne "" and !is_domain($name_parts[1]));
		unless ($mods{yes_to_all})
			{
			my @rqs_all_names = ("Имя", "Активный", "Публичный", "Синхронизация с AD"); # Ordered list of names of all requisites
			my %rqs_values = (
				"Имя" => $name_parts[1],
				"Активный" => $vars{active} ne "" ? ($vars{active} ? "Да" : "Нет") : $vars{active},
				"Публичный" => $vars{public} ne "" ? ($vars{public} ? "Да" : "Нет") : $vars{public},
				"Синхронизация с AD" => $vars{ad_sync_enabled} ne "" ? ($vars{ad_sync_enabled} ? "Да" : "Нет") : ""
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
			print("Попытка изменить домен \"$name_parts[0]\". Новые реквизиты:\n\n");
			if (scalar(@rqs_names))
				{
				WriteResultRecord(\@rqs_names, \%rqs_values);
				}
			else
				{
				print("[Пусто]\n");
				}
			print("\n");
			print("[Отмена]\n") and exit unless(CheckYes());
			print("\n");
			print("Выполнение... ");
			}
		$dbh->do("CALL domain_mod(?, ?, ?, ?, ?)", undef,
			$name_parts[0],
			$name_parts[1] ne "" ? $name_parts[1] : undef,
			$vars{active} ne "" ? $vars{active} : undef,
			$vars{public} ne "" ? $vars{public} : undef,
			$vars{ad_sync_enabled} ne "" ? $vars{ad_sync_enabled} : undef)
			or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
		given(GetSProcStatus($dbh))
			{
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Нечего менять\n") when (/NONEWDATA/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Домен не существует\n") when (/NXDOMAIN/i);
			exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Домен с таким именем уже существует\n") when (/DOMAINEXISTS/i);
			}
		print("готово \n") unless ($mods{yes_to_all});
		}
	}
