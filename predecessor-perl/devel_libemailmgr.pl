#!perl -w

use feature "switch";
use Term::ReadKey;
use Crypt::GeneratePassword ();

%required_db = (name => 'emailmgr', vmajor => '3', vminor => '2', vpatch => '0');
%my_version = (vmajor => '2', vminor => '2', vpatch => '3');

%EXIT_CODES =
	(
	EXIT_NOERROR		=> 0, # Finished without errors
	EXIT_INIT			=> 1, # Initialization problem
	EXIT_INPUT			=> 2, # Bad input data
	EXIT_SQLNOERROR		=> 3, # No error on SQL stage but further execution is not possible
							  # (DBI method succeeded and SQL server returns error in @last_proc_state)
	EXIT_SQLERROR		=> 4, # Unexpected error on SQL stage (error after calling DBI method)
	EXIT_GENERAL		=> 5, # General runtime error
	EXIT_DBINCOMPAT		=> 6  # Incompatible database
	);
	
sub exit_	#"exit"-wrapper, (exit_code, message)
	{
	$exit_code = shift;
	my ($package, $file, $line) = caller;
	if ($exit_code == $EXIT_CODES{EXIT_SQLERROR})
		{
		print("File \"$file\", line $line, ", shift);
		}
	else
		{
		print(shift);
		}
	exit($exit_code);
	}

sub CheckYes
	{
	print("Нажмите \"y\" (лат.), если согласны... ");
	ReadMode("cbreak");
	my $var = ReadKey;
	ReadMode("restore");
	return "" if ($var ne "y" and $var ne "Y");
	return "YES";
	}

sub isAllEmptyStr
	{
	foreach(@_)
		{
		return(0) if ($_ ne "");
		}
	return(1);
	}

sub trim	# Trim function to remove whitespace from the start and end of the string
	{
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
	}
	
sub nonascii	# Check whether the string consist of a non-ascii characters
	{
	local $_ = shift;
	/[^[:ascii:]]/
	}

sub WriteResultTable    # Writes result in table format
                        # (Header, Header lengths, Data, Type (header, data, footer))
                        # Warning: this sub may modify data in input variables
	{
	my $pheader = shift;
	my $pheader_lengths = shift;
	my $pdata = shift;
	my $type = shift;
	my $i = 0;
	my $cell;
	for $cell(@{$pheader})
		{
		my $len = length($cell);
		${$pheader_lengths}[$i] = $len if ($len > ${$pheader_lengths}[$i]);
		${$pheader_lengths}[$i] = 3 if (${$pheader_lengths}[$i] < 3); #minimum for cell length is 3
		$i++;
		}
	$i = 0;
	given($type)
		{
		when(/^HEADER$/i)
			{
			print("+");
			foreach(@{$pheader_lengths})
				{
				print("-" x ($_ + 2), "+");
				}
			print("\n");
			print("|");
			foreach(@{$pheader_lengths})
				{
				print(" ", ${$pheader}[$i], " " x (${$pheader_lengths}[$i] - length(${$pheader}[$i])), " ", "|");
				$i++;
				}
			print("\n");
			print("+");
			foreach(@{$pheader_lengths})
				{
				print("-" x ($_ + 2), "+");
				}
			print("\n");
			}
		when(/^DATA$/i)
			{
			print("|");
			foreach(@{$pheader_lengths})
				{
				if (length(${$pdata}[$i]) > ${$pheader_lengths}[$i])
					{
					${$pdata}[$i] = substr(${$pdata}[$i], 0, ${$pheader_lengths}[$i] - 3) . "...";
					}
				print(" ", ${$pdata}[$i], " " x (${$pheader_lengths}[$i] - length(${$pdata}[$i])), " ", "|");
				$i++;
				}
			print("\n");
			}
		when(/^FOOTER$/i)
			{
			print("+");
			foreach(@{$pheader_lengths})
				{
				print("-" x ($_ + 2), "+");
				}
			print("\n");
			}
		default
			{
			print("WriteResultTable: unknown type\n");
			}
		}
	}

sub WriteResultRecord # Writes the result in record format, (pointer_to_ordered_set_of_keys, pointer_to_result_hash)
	{
	my $p_keys_ordered = shift;
	my $p_res_hash = shift;
	my $max_key_length = 0;
	foreach(@{$p_keys_ordered})
		{
		$max_key_length = length($_) if (length($_) > $max_key_length);
		}
	foreach(@{$p_keys_ordered})
		{
		print(" " x ($max_key_length - length($_)), $_, ": ", ${$p_res_hash}{$_}, "\n")
		}
	}

sub GetSProcStatus # Returns @last_proc_state from connection identified by parameter
	{
	my $dbh = shift;
	my @result = $dbh->selectrow_array("SELECT \@last_proc_state");
	exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr) if ($dbh->err);
	return("") if (!defined($result[0]) or $result[0] =~ /NOPROBLEM/i);
	return($result[0]);
	}

sub GetDBSysName
	{
	my $dbh = shift;
	my @result = $dbh->selectrow_array("SELECT GetFullSysName()");
	exit_($EXIT_CODES{EXIT_SQLERROR}, "Неожиданная ошибка: ".$dbh->errstr) if ($dbh->err);
	return(split(/:/, $result[0]));
	}

sub CheckDBCompat
	{
	my $dbh = shift;
	my $required_str = lc(join(':', @_));
	my $current_str = lc(join(':', GetDBSysName($dbh)));
	exit_($EXIT_CODES{EXIT_DBINCOMPAT}, "Работа с несовместимой БД. ".
		"Требуется \"$required_str\". "."Текущая \"$current_str\"\n")
		if ($required_str ne $current_str);
	}

sub PrintMyVersion
	{
	my $dbh = shift;
	my $db_str = lc(join(':', GetDBSysName($dbh)));
	print("Менеджер почтовой системы версии ", lc(join('.', @my_version{'vmajor', 'vminor', 'vpatch'})), "\n",
		"Работа с БД \"$db_str\"\n");
	}

sub GeneratePassword # Generates a random password, (min pass len, max pass len)
	{
	my %pass_len;
	$pass_len{min} = shift;
	$pass_len{max} = shift;
	my $ascii_start = 33;
	my $ascii_end = 126;
	my %ascii_exclude_chars=(34=>"", 39=>"");
	my @ascii_arr;
	my $ascii_arr_index = 0;
	for (my $i = $ascii_start; $i <= $ascii_end; $i++)
		{
		next if exists($ascii_exclude_chars{$i});
		$ascii_arr[$ascii_arr_index] = chr($i);
		$ascii_arr_index++;
		}
	return(Crypt::GeneratePassword::chars($pass_len{min}, $pass_len{max}, \@ascii_arr));
	}

1;
