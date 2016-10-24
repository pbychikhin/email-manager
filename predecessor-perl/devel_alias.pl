#!perl -w
#Version:

use feature "switch";
use strict "vars";
use Config::IniFiles;
use File::Basename;
use Getopt::Long;
use DBI;
use Encode qw(decode encode);
use Data::Validate::Email qw(is_email);
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

my $dbh = DBI->connect($dsn, $cfg->val("connect", "login"), $cfg->val("connect", "password"))
	or exit_($EXIT_CODES{EXIT_GENERAL}, "Ошибка соединения с БД: ".$DBI::errstr."\n");
$dbh->do("SET NAMES \'cp866\'")
	or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
CheckDBCompat($dbh, @required_db{'name', 'vmajor', 'vminor', 'vpatch'});

#Need to rewrite with classes
my $need_help = "";
my $need_version = "";
my %actions = (query=>"", add=>"", del=>"", mod=>"");
my %vars = (name=>"", fullname=>"", value=>"", active=>"", public=>"", checknames=>1);
my @ascii_vars = ("name", "value");
my @string_vars = ("name", "value", "fullname");
my %mods = (record_output=>"", yes_to_all=>"");
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
	"query|q"=>\$actions{query},
	"add|a"=>\$actions{add},
	"del|d"=>\$actions{del},
	"mod|m"=>\$actions{mod},
	"name=s"=>\$vars{name},
	"fullname=s"=>\$vars{fullname},
	"value=s"=>\$vars{value},
	"active!"=>\$vars{active},
	"public!"=>\$vars{public},
	"checknames!"=>\$vars{checknames},
	"r"=>\$mods{record_output},
	"y"=>\$mods{yes_to_all},
	"help|?"=>\$need_help,
	"v"=>\$need_version);
exit_($EXIT_CODES{EXIT_INIT},
	"Ошибка в командной строке. Введите \"".basename($0)." --help\" для вывода списка ключей\n")
	unless ($GetOptRes);
if ($need_help)
	{
	print(
	basename($0)."\n",
	"  <--query|-q | --add|-a | --del|-d | --mod|-m>\n",
	"  [--name=...[:...]] [--value=...[:...]] [--fullname=...]\n",
	"  [--[no]active] [--[no]checknames]\n",
	"  [-r] [-y]\n\n",
	"--query|-q\n",
	"   Запросить информацию из БД. Запрос может включать шаблоны \"%\" и \"_\"\n",
	"   для любой группы либо любого одиночного символа соответственно. Для \n",
	"   экранирования используется символ \"\\\". Шаблоны разрешены для параметров\n",
	"   \"--name\" и \"--value\"\n",
	"--add|-a\n",
	"   Добавить алиас\n",
	"--del|-d\n",
	"   Удалить алиас\n",
	"--mod|-m\n",
	"   Изменить алиас\n",
	"--name\n",
	"   Имя алиаса*. Может быть задано в форме \"имя:имя\" для переименования\n",
	"   существующего\n",
	"--value\n",
	"   Значение алиаса*. Может быть задано в форме \"значение:значение\" для\n",
	"   переименования существующего\n",
	"--fullname\n",
	"   Полное имя алиаса\n",
	"--[no]active\n",
	"   Активировать/деактивировать алиас\n",
	"--[no]public\n",
	"   Публиковать алиас в адресной книге\n",
	"--[no]checknames\n",
	"   Проверять адреса электронной почты на корректность\n",
	"-r\n",
	"   Выводить результат запроса в виде записей (а не в виде таблицы)\n",
	"-y\n",
	"   Ответ \"да\" на все вопросы (пакетный режим)\n",
	"-v\n",
	"   Вывод версии ПО\n\n",
	"-----\n",
	"* Параметр может участвовать в поисковом запросе\n");
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
	exit_($EXIT_CODES{EXIT_INPUT}, "Переменная \"$_\" допускает только ASCII\n") if nonascii($vars{$_});
	}
foreach(@string_vars)
	{
	$vars{$_} = trim($vars{$_});
	}
$vars{fullname} = encode("cp866", decode("cp1251", $vars{fullname}));
	
if ($actions{query})
	{
	my($sth, @result, @result_maxlen);
	my $query_type = "DEFAULT"; #NAME or VALUE or DEFAULT
	$query_type = "NAME" if ($vars{name} ne "" and $vars{value} eq "");
	$query_type = "VALUE" if ($vars{value} ne "" and $vars{name} eq "");
	given ($query_type)
		{
		when (/^NAME$/i) # query name only (all names)
			{
			$dbh->do("START TRANSACTION", undef)
				or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
#TAG: SQL
			@result_maxlen = $dbh->selectrow_array("SELECT MAX(CHAR_LENGTH(name)), MAX(CHAR_LENGTH(fullname)), 2
				FROM alias_name WHERE name LIKE ?",	undef, $vars{name})
				or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ", $dbh->errstr);
			unless (defined($result_maxlen[0]))
				{
				print("Ничего не найдено\n");
				exit;
				}
			$result_maxlen[0] = min(32, $result_maxlen[0]); # good place for constant '32' is ini-file,
			$result_maxlen[1] = min(32, $result_maxlen[1]); # rather than in code
#TAG: SQL
			$sth = $dbh->prepare("SELECT name, fullname,
				CASE active WHEN TRUE THEN 'A' WHEN FALSE THEN '-' END,
				CASE public WHEN TRUE THEN 'P' WHEN FALSE THEN '-' END,
				created, modified
				FROM alias_name WHERE
				name LIKE ? order by name")
				or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
			$sth->execute($vars{name})
				or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$sth->errstr);
			$dbh->do("COMMIT", undef)
				or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
			WriteResultTable(["Имя", "Полное имя", "Флаги"], \@result_maxlen, undef, "HEADER")
				unless ($mods{record_output});
			while (@result = $sth->fetchrow_array)
				{
				if ($mods{record_output})
					{
					WriteResultRecord(["Имя", "Полное имя", "Активный", "Публичный",
						"Создан", "Изменен"], {
						"Имя" => $result[0],
						"Полное имя" => $result[1],
						"Активный" => ($result[2] eq "A" ? "Да" : "Нет"),
						"Публичный" => ($result[3] eq "P" ? "Да" : "Нет"),
						"Создан" => $result[4],
						"Изменен" => $result[5]});
					print("\n");
					}
				else
					{
					WriteResultTable(["Имя", "Полное имя", "Флаги"], \@result_maxlen,
						[$result[0], $result[1], $result[2].$result[3]], "DATA");
					}
				}
			WriteResultTable(["Имя", "Полное имя", "Флаги"], \@result_maxlen, undef, "FOOTER")
				unless ($mods{record_output});
			}
		when (/^VALUE$/i) # query value only (all names and values with given value)
			{
			$dbh->do("START TRANSACTION", undef)
				or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
#TAG: SQL
			@result_maxlen = $dbh->selectrow_array("SELECT MAX(CHAR_LENGTH(value)), MAX(CHAR_LENGTH(name)), 1
				FROM alias_value, alias_name WHERE value LIKE ? AND alias_value.name_id = alias_name.id", undef,
				$vars{value} )
				or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ", $dbh->errstr);
			unless (defined($result_maxlen[0]))
				{
				print("Ничего не найдено\n");
				exit;
				}
			$result_maxlen[0] = min(32, $result_maxlen[0]); # good place for constant '32' is ini-file,
			$result_maxlen[1] = min(32, $result_maxlen[1]); # rather than in code
#TAG: SQL
			$sth = $dbh->prepare("SELECT value, name,
				CASE alias_value.active WHEN TRUE THEN 'A' WHEN FALSE THEN '-' END,
				alias_value.created, alias_value.modified
				FROM alias_value, alias_name WHERE value LIKE ? AND alias_value.name_id = alias_name.id
				ORDER BY value, name")
				or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
			$sth->execute($vars{value})
				or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$sth->errstr);
			$dbh->do("COMMIT", undef)
				or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
			WriteResultTable(["Значение", "Имя", "Флаги"], \@result_maxlen, undef, "HEADER")
				unless ($mods{record_output});
			my $old_result_value = "";
			while (@result = $sth->fetchrow_array)
				{
				if ($mods{record_output})
					{
					WriteResultRecord(["Значение", "Имя", "Активный", "Создан", "Изменен"], {
						"Значение" => $result[0],
						"Имя" => $result[1],
						"Активный" => ($result[2] eq "A" ? "Да" : "Нет"),
						"Создан" => $result[3],
						"Изменен" => $result[4]});
					print("\n");
					}
				else
					{
					WriteResultTable(["Значение", "Имя", "Флаги"], \@result_maxlen,
						[$result[0] eq $old_result_value ? "" : $result[0], $result[1], $result[2]], "DATA");
					}
				$old_result_value = $result[0];
				}
			WriteResultTable(["Значение", "Имя", "Флаги"], \@result_maxlen, undef, "FOOTER")
				unless ($mods{record_output});
			}
		default #Name and value defined, or both undefined
			{
			$vars{name} = "%" if ($vars{name} eq "");
			$vars{value} = "%" if ($vars{value} eq "");
			$dbh->do("START TRANSACTION", undef)
				or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
#TAG: SQL
			@result_maxlen = $dbh->selectrow_array("SELECT MAX(CHAR_LENGTH(name)), MAX(CHAR_LENGTH(value)), 1
				FROM alias_name, alias_value WHERE name LIKE ? AND value LIKE ? AND 
				alias_name.id = alias_value.name_id", undef,
				($vars{name}, $vars{value}))
				or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ", $dbh->errstr);
			unless (defined($result_maxlen[0]))
				{
				print("Ничего не найдено\n");
				exit;
				}
			$result_maxlen[0] = min(32, $result_maxlen[0]); # good place for constant '32' is ini-file,
			$result_maxlen[1] = min(32, $result_maxlen[1]); # rather than in code
#TAG: SQL
			$sth = $dbh->prepare("SELECT name, value,
				CASE alias_value.active WHEN TRUE THEN 'A' WHEN FALSE THEN '-' END,
				alias_value.created, alias_value.modified
				FROM alias_name, alias_value WHERE name LIKE ? AND value LIKE ? AND 
				alias_name.id = alias_value.name_id
				ORDER BY name, value")
				or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
			$sth->execute(($vars{name}, $vars{value}))
				or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$sth->errstr);
			$dbh->do("COMMIT", undef)
				or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
			WriteResultTable(["Имя", "Значение", "Флаги"], \@result_maxlen, undef, "HEADER")
				unless ($mods{record_output});
			my $old_result_value = "";
			while (@result = $sth->fetchrow_array)
				{
				if ($mods{record_output})
					{
					WriteResultRecord(["Имя", "Значение", "Активный", "Создан", "Изменен"], {
						"Имя" => $result[0],
						"Значение" => $result[1],
						"Активный", ($result[2] eq "A" ? "Да" : "Нет"),
						"Создан" => $result[3],
						"Изменен" => $result[4]});
					print("\n");
					}
				else
					{
					WriteResultTable(["Имя", "Значение", "Флаги"], \@result_maxlen,
						[$result[0] eq $old_result_value ? "" : $result[0], $result[1], $result[2]], "DATA");
					}
				$old_result_value = $result[0];
				}
			WriteResultTable(["Имя", "Значение", "Флаги"], \@result_maxlen, undef, "FOOTER")
				unless ($mods{record_output});
			}
		}
	}

if ($actions{add})
	{
	exit_($EXIT_CODES{EXIT_INPUT}, "Не задано имя (name)\n") if ($vars{name} eq "");
	exit_($EXIT_CODES{EXIT_INPUT}, "Не задано значение (value)\n") if ($vars{value} eq "");
	if ($vars{checknames})
		{
		exit_($EXIT_CODES{EXIT_INPUT}, "\"$vars{name}\" не является допустимым именем для алиаса\n")
			unless (is_email($vars{name}));
		exit_($EXIT_CODES{EXIT_INPUT}, "\"$vars{value}\" не является допустимым значением для алиаса\n")
			unless (is_email($vars{value}));
		}
	if ($vars{fullname} eq "")
		{
		print("Важно: не задано полное имя (fullname). Значение по умолчанию: \"$vars{name}\"\n\n")
			unless ($mods{yes_to_all});
		$vars{fullname} = $vars{name};
		}
	unless ($mods{yes_to_all})
		{
		print("Попытка добавить новый алиас \"$vars{name}\" со следующими реквизитами:\n\n");
		WriteResultRecord(["Имя", "Значение", "Полное имя", "Активный", "Публичный"], {
			"Имя" => $vars{name},
			"Значение" => $vars{value},
			"Полное имя" => $vars{fullname},
			"Активный" => ($vars{active} ne "" ? ($vars{active} ? "Да" : "Нет") : "Умолч."),
			"Публичный" => ($vars{public} ne "" ? ($vars{public} ? "Да" : "Нет") : "Умолч.")});
		print("\n");
		print("[Отмена]\n") and exit unless(CheckYes());
		print("\n");
		print("Выполнение... ");
		}
	$dbh->do("CALL alias_add(?, ?, ?, ?, ?)", undef, $vars{name}, $vars{value}, $vars{fullname},
		($vars{active} ne "" ? $vars{active} : undef), ($vars{public} ne "" ? $vars{public} : undef))
		or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
	given(GetSProcStatus($dbh))
		{
		exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Алиас уже существует\n") when (/ALIEXISTS/i);
		}
	print("готово \n") unless ($mods{yes_to_all});
	}

if ($actions{del})
	{
	exit_($EXIT_CODES{EXIT_INPUT}, "Не задано имя (name)\n") if ($vars{name} eq "");
	if ($vars{value} eq "")
		{
		print("Не задано значение алиаса: будут удалены все записи с соответствующим именем\n");
		print("[Отмена]\n") and exit unless(CheckYes());
		print("\n");
		}
	unless ($mods{yes_to_all})
		{
		print("Попытка удалить алиас \"$vars{name}\" со следующими реквизитами:\n\n");
		my @rqs_all_names = ("Имя", "Значение");
		my %rqs_values = (
			"Имя" => $vars{name},
			"Значение" => $vars{value});
		my @rqs_names;
		foreach(keys(%rqs_values))
			{
			delete($rqs_values{$_}) if ($rqs_values{$_} eq "");
			}
		foreach(@rqs_all_names)
			{
			push(@rqs_names, $_) if exists($rqs_values{$_});
			}
		WriteResultRecord(\@rqs_names, \%rqs_values);
		print("\n");
		print("[Отмена]\n") and exit unless(CheckYes());
		print("\n");
		print("Выполнение... ");
		}
#TAG: SQL
	$dbh->do("CALL alias_del(?, ?)", undef, $vars{name}, $vars{value} ne "" ? $vars{value} : undef)
		or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
	given(GetSProcStatus($dbh))
		{
		exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Алиас не существует\n") when (/NXALIAS/i);
		}
	print("готово \n") unless ($mods{yes_to_all});
	}

if ($actions{mod})
	{
	my @name_parts = split(/:/, $vars{name}, 2);
	$name_parts[0] //= "";
	$name_parts[1] //= "";
	exit_($EXIT_CODES{EXIT_INPUT}, "Не задано имя (name)\n") if ($name_parts[0] eq "");
	my @value_parts = split(/:/, $vars{value}, 2);
	$value_parts[0] //= "";
	$value_parts[1] //= "";
	@name_parts = (trim($name_parts[0]), trim($name_parts[1]));
	@value_parts = (trim($value_parts[0]), trim($value_parts[1]));
	foreach($name_parts[1], $value_parts[1])
		{
		exit_($EXIT_CODES{EXIT_INPUT}, "Некорректный адрес электронной почты: \"$_\"\n")
			if ($_ ne "" and $vars{checknames} and !is_email($_));
		}
	unless ($mods{yes_to_all})
		{
		if ($value_parts[0] eq "")
			{
			my @rqs_all_names = ("Имя", "Полное имя", "Активный", "Публичный");
			my %rqs_values = (
				"Имя" => $name_parts[1],
				"Полное имя" => $vars{fullname},
				"Активный" => $vars{active} ne "" ? ($vars{active} ? "Да" : "Нет") : $vars{active},
				"Публичный" => $vars{public} ne "" ? ($vars{public} ? "Да" : "Нет") : $vars{public});
			my @rqs_names; # Ordered list of names of requisites to be changed
			foreach(keys(%rqs_values))
				{
				delete($rqs_values{$_}) if ($rqs_values{$_} eq "");
				}
			foreach(@rqs_all_names)
				{
				push(@rqs_names, $_) if exists($rqs_values{$_});
				}
			print("Попытка изменить алиас \"$name_parts[0]\". Новые реквизиты:\n\n");
			if (scalar(@rqs_names))
				{
				WriteResultRecord(\@rqs_names, \%rqs_values);
				}
			else
				{
				print("[Пусто]\n");
				}
			}
		else
			{
			my @rqs_all_names = ("Значение", "Активный");
			my %rqs_values = (
				"Значение" => $value_parts[1],
				"Активный" => $vars{active} ne "" ? ($vars{active} ? "Да" : "Нет") : $vars{active});
			my @rqs_names; # Ordered list of names of requisites to be changed
			foreach(keys(%rqs_values))
				{
				delete($rqs_values{$_}) if ($rqs_values{$_} eq "");
				}
			foreach(@rqs_all_names)
				{
				push(@rqs_names, $_) if exists($rqs_values{$_});
				}
			print(
			"Попытка изменить алиас \"$name_parts[0]\" со значением \"$value_parts[0]\".\n",
			"Новые реквизиты:\n\n");
			if (scalar(@rqs_names))
				{
				WriteResultRecord(\@rqs_names, \%rqs_values);
				}
			else
				{
				print("[Пусто]\n");
				}
			}
		print("\n");
		print("[Отмена]\n") and exit unless(CheckYes());
		print("\n");
		print("Выполнение... ");
		}
#TAG: SQL
	$dbh->do('CALL alias_mod(?, ?, ?, ?, ?, ?, ?)', undef,
		$name_parts[0],
		$name_parts[1] ne "" ? $name_parts[1] : undef,
		$value_parts[0] ne "" ? $value_parts[0] : undef,
		$value_parts[1] ne "" ? $value_parts[1] : undef,
		$vars{fullname} ne "" ? $vars{fullname} : undef,
		$vars{active} ne "" ? $vars{active} : undef,
		$vars{public} ne "" ? $vars{public} : undef)
		or exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr);
	given(GetSProcStatus($dbh))
		{
		exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Нечего менять\n") when (/NONEWDATA/i);
		exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Алиас не существует\n") when (/NXALIAS/i);
		exit_($EXIT_CODES{EXIT_SQLNOERROR}, "Алиас уже существует\n") when (/ALIEXISTS/i);
		}
	print("готово \n") unless ($mods{yes_to_all});
	}
