#!/usr/bin/perl
use strict;

#
# $Id: Mysql.pm,v 4.17 2006/03/18 15:00:44 matt Exp $
#

package Mail::Toaster::Mysql;

use Carp;
use Getopt::Std;

use vars qw($VERSION $darwin $freebsd);
$VERSION  = '4.11';

my $os = $^O;

use lib "lib";
use lib "../../";
use Mail::Toaster::Perl;    my $perl    = Mail::Toaster::Perl->new;
use Mail::Toaster::Utility; my $utility = Mail::Toaster::Utility->new;

if    ( $os eq "freebsd" ) { require Mail::Toaster::FreeBSD; $freebsd = Mail::Toaster::FreeBSD->new; } 
elsif ( $os eq "darwin"  ) { require Mail::Toaster::Darwin;  $darwin  = Mail::Toaster::Darwin->new;  }
else  { }; #print "$os is not formally supported, but may work\n" };


=head1 NAME

Mail::Toaster::Mysql

head1 SYNOPSIS

frequently used functions for Mysql.

=head1 DESCRIPTION

I find myself using MySQL for a lot of things. Geographically distributed dns systems (MySQL replication), mail servers, and all the other fun stuff you'd use a RDBMS for. As such, I've got a growing pile of scripts that have lots of duplicated code in them. As such, the need for this Perl module grew.

       Currently used in:
  mysql_replicate_manager v1.5+
  uron.net user_*.pl
  polls.pl
  nt_export_djb_update.pl
  toaster_setup.pl 

=cut


=head1 METHODS

=head2 new

	use Mail::Toaster::Mysql;
	my $mysql = Mail::Toaster::Mysql->new();

=cut

sub new
{
	my ($class, $name) = @_;
	my $self = { name => $name };
	bless ($self, $class);
	return $self;
};


=head2 autocommit

=cut

sub autocommit 
{
	my ($dot) = @_;

	if ($dot->{'autocommit'} && $dot->{'autocommit'} ne "" ) 
	{
		return $dot->{'autocommit'};  #	SetAutocommit
	} 
	else 
	{
		return 1;                     #  Default to autocommit.
	};
};


=head2 backup

Back up your mysql databases

   $mysql->backup();

The default location for backups is /var/backups/mysql. If you want them stored elsewhere configure then set backupdir = /path/to/backups in  your .my.cnf (as shown in the FAQ) or pass it via -d on the command line.

You will need to have cronolog, gzip, and mysqldump installed in a "normal" location. Your backups will be stored in a directory based on the date, such as /var/backups/mysql/2003/09/11/mysql_full_dump.gz. Make sure that path is configured to be backed up by your backup software.

=cut

sub backup($) 
{
	my ($self, $dot) = @_;

	unless ( $utility->is_hashref($dot) ) {
		print "FATAL, you passed backup a bad argument!\n";
		return 0;
	};

	my $debug      = $dot->{'debug'};
	my $backupfile = $dot->{'backupfile'} || "mysql_full_dump";
	my $backupdir  = $dot->{'backup_dir'} || "/var/backups/mysql";

	print "backup: beginning mysql_backup.\n" if $debug;

	foreach ( qw(cronolog gzip mysqldump) ) {
		unless ( -x $utility->find_the_bin($_) ) {
			croak "You must have $_ installed with execute permissions!\n";
		};
	};

	my $gzip       = $utility->find_the_bin("gzip");
	my $cronolog   = $utility->find_the_bin("cronolog");
	my $mysqldump  = $utility->find_the_bin("mysqldump");

	my $mysqlopts = "--all-databases --opt --password=" . $dot->{'pass'};
	my ($dd, $mm, $yy) = $utility->get_the_date(undef, $debug);

	print "backup: backup root is $backupdir.\n" if $debug;
	
	$utility->chdir_source_dir("$backupdir/$yy/$mm/$dd");

	print "backup: backup file is $backupfile.\n" if $debug;

	if ( !-e "$backupdir/$yy/$mm/$dd/$backupfile" and !-e "$backupdir/$yy/$mm/$dd/$backupfile.gz" ) 
	{
		$utility->syscmd("$mysqldump $mysqlopts | $cronolog $backupdir/%Y/%m/%d/$backupfile");
		print "backup: running $gzip $backupdir/$yy/$mm/$dd/$backupfile\n" if $debug;
		$utility->syscmd("$gzip $backupdir/$yy/$mm/$dd/$backupfile");
	} 
	else 
	{ 
		print "Skipping! Backup for today is already done.\n"; 
	};
};

sub binlog_on 
{
	my ($self, $db_mv) = @_;

	if ( $db_mv->{log_bin} ne "ON" )
	{
		print <<EOBINLOG;

Hey there! In order for this server to act as a master, binary logging
must be enabled! Please edit /etc/my.cnf or $db_mv->{datadir}/my.cnf and
add "log-bin". You must also set server-id as documented at mysql.com.

EOBINLOG
;
		return 0;
	};
	return 1;
};


=head2 connect

    my ($dbh, $dsn, $drh) = $mysql->connect($dot, $warn, $debug);

$dot is a hashref of key/value pairs in the same format you'd find in ~/.my.cnf. Not coincidentally, that's where it expects you'll be getting them from.

$warn allows you to determine whether to die or warn on failure or error. To warn, set $warn to a non-zero value. 

$debug will print out helpful debugging messages should you be having problems.

=cut

sub connect($;$$)
{
	my ($self, $dot, $warn, $debug) = @_;
	my $dbh;

	$perl->module_load( {module=>"DBI",        ports_name=>"p5-DBI",       ports_group=>"databases", debug=>1} );
	$perl->module_load( {module=>"DBD::mysql", ports_name=>"p5-DBD-mysql", ports_group=>"databases", debug=>1} );

	my $ac  = $self->autocommit( $dot );
	my $dbv = $self->db_vars( $dot );
	my $dsn = "DBI:$dbv->{'driver'}:database=$dbv->{'db'};host=$dbv->{'host'};port=$dbv->{'port'}";

	if ($warn) 
	{
		$dbh = DBI->connect($dsn, $dbv->{'user'}, $dbv->{'pass'}, { RaiseError => 0, AutoCommit => $ac });
		unless ($dbh)
		{
			carp "db connect failed: $!\n" if $debug;
			return $dbh;
		};
	} 
	else 
	{
		$dbh = DBI->connect($dsn, $dbv->{'user'}, $dbv->{'pass'},{ RaiseError => 0, AutoCommit => $ac } ) 
				or croak "db connect failed: $!\n";
	};
	my $drh = DBI->install_driver( $dbv->{'driver'} );

	return ($dbh, $dsn, $drh);
};

=head2 db_vars

This sub is called internally by $mysql->connect and is used principally to set some reasonable defaults should you not pass along enough connection parameters in $dot. 

=cut

sub db_vars($)
{
	my ($self, $val) = @_;
	my ($driver, $db, $host, $port, $user, $pass, $dir);

	if ( $val->{'driver'} && $val->{'driver'} ne "" ) 
	{    $driver= $val->{'driver'} } else { $driver= "mysql" };

	if ( $val->{'db'}     && $val->{'db'}     ne "" ) 
	{    $db    = $val->{'db'}     } else { $db    = "mysql" };

	if ( $val->{'host'}   && $val->{'host'}   ne "" ) 
	{    $host  = $val->{'host'}   } else { $host  = "localhost" };

	if ( $val->{'port'}   && $val->{'port'}   ne "" ) 
	{    $port  = $val->{'port'}   } else { $port  = "3306" };

	if ( $val->{'user'}   && $val->{'user'}   ne "" ) 
	{    $user  = $val->{'user'}   } else { $user  = "root" };

	if ( $val->{'pass'}   && $val->{'pass'}   ne "" ) 
	{    $pass  = $val->{'pass'}   } else { $pass  = "" };

	if ( $val->{'dir_m'}  && $val->{'dir_m'}  ne "" ) 
	{    $dir ="/var/db/mysql"} else { $dir   = $val->{'dir_m'} };     
  
	my %master = ( driver  => $driver,     db      => $db,      host    => $host,
			port    => $port,       user    => $user,    pass    => $pass,
			dir     => $dir );
	return \%master;
};

sub dbs_list($) 
{
	my ($self, $dbh) = @_;

	if ( my $sth = $self->query($dbh, "SHOW DATABASES")) 
	{
		while ( my ($db_name) = $sth->fetchrow_array ) { print "$db_name "; };

		if ($sth->err) { print "FAILED!\n";        } 
		else           { $sth->finish; print "\n"; };
	};

	### Documented (but non-working methods for listing databases ###
	# my @databases = $drh->func($db_mv->{'host'}, $db_mv->{'port'}, '_ListDBs');
	# print "mysql_info->databases:\t@databases\n";
	#
	# my @databases2 = DBI->data_sources("mysql");
	# print "mysql_info->databases2:\t@databases2\n";
};


=head2 flush_logs

	$mysql->flush_logs($dbh, $debug)

runs the mysql "FLUSH LOGS" query on the server. This commits any pending (memory cached writes) to disk.

=cut

sub flush_logs($;$)
{
	my ($self, $dbh, $debug) = @_;

	my $query  = "FLUSH LOGS";
	my $sth    = $self->query($dbh, $query);
	$sth->finish;

	return { error_code=>200, error_desc=>"logs flushed successfully" };
};

=head2 get_hashes

Gets results from a mysql query as an array of hashes

   my @r = $mysql->get_hashes($dbh, $sql);

$dbh is a database handle

$sql is query

=cut

sub get_hashes($$) 
{
	my ($self, $dbh, $sql) = @_;
	my @records;

	if (my $sth = $self->query($dbh, $sql)) 
	{
		while (my $ref = $sth->fetchrow_hashref) 
		{
			push @records, $ref;
		}
		$sth->finish;
	}
	return @records;
};



=head2 install

Installs MySQL

=cut

sub install($$$$)
{
	my ($self, $mysql, $site, $ver, $conf) = @_;

	if ( $utility->is_hashref($conf) ) {
		$ver = $conf->{'install_mysql'};
	};

	unless ( $ver ) {
		print "skipping MySQL, it's not selected!\n";
		return 0;
	};

	if ( $os eq "freebsd" ) 
	{
		my $installed = $freebsd->is_port_installed( "mysql-server");
		if ($installed) {
			print "MySQL is already installed as $installed.\n";
			$freebsd->rc_dot_conf_check("mysql_enable", "mysql_enable=\"YES\"");
		};

		my $copts = "SKIP_DNS_CHECK";

		if ( $conf ) {
			$copts .= ",WITH_OPENSSL"      if $conf->{'install_mysql_ssl'};
			$copts .= ",BUILD_OPTIMIZED"   if $conf->{'install_mysql_optimized'};

			if ( $conf->{'install_mysql_linuxthreads'} ) {
				$copts .= ",WITH_LINUXTHREADS" 
			} 
			else {
				if ( $ver =~ /^4/ && `uname -r` =~ /^4/ ) # FreeBSD 4 & MySQL 4
				{
					if ( $utility->yes_or_no("\n\nHEY!!  You are installing MySQL v4.x on FreeBSD 4. In this configuration, it is recommended that you compile MySQL with linuxthreads. Please see: http://www.tnpi.biz/internet/mail/toaster/faq/programs/mysql.shtml for more detailed information. Trust us, you really should. Shall I enable linuxthreads for you?") ) 
					{

						$copts .= ",WITH_LINUXTHREADS";
						print " Excellent choice!\n. Now, don't forget to update toaster-watcher.conf and set install_mysql_linuxthreads.\n";
					};
			
				};
			};

			if ( $conf->{'install_mysql_dir'} and $conf->{'install_mysql_dir'} ne "/var/db/mysql" ) 
			{
				$copts .= ",DB_DIR=" . $conf->{'install_mysql_dir'} 
			};
		};

		my @port_args;

		if ($ver == 1 && ! $installed) 
		{
			$freebsd->package_install("mysql41-server", "databases");
			$installed = $freebsd->is_port_installed( "mysql-server");

			unless ( $installed ) {
				# use this for really old freebsd ports tree
				$freebsd->package_install("mysql-server", "databases");
				$installed = $freebsd->is_port_installed( "mysql-server");
			};
		};

		if ($ver== 3 || $ver== 323 ) 
		{
			@port_args = qw(mysql323-server databases mysql323-server mysql-server-3.23);
		}
		elsif ($ver== 4 || $ver== 40 ) 
		{
			@port_args = qw(mysql40-server databases mysql40-server mysql-server-4.0);
		}
		elsif ($ver == 41 || $ver == 4.1) 
		{
			@port_args = qw(mysql41-server databases mysql41-server mysql-server-4.1);
		}
		elsif ($ver == 5 || $ver == 50 || $ver == 5.0) 
		{
			@port_args = qw(mysql50-server databases mysql50-server mysql-server-5.0);
		} 
		else {
			# default version (latest stable)
			@port_args = qw(mysql41-server databases mysql41-server mysql-server-4.1);
		}; 

		push @port_args, $copts;

		unless ( $installed ) 
		{
			unless ( $freebsd->port_install(@port_args) ) {
				print "Bummer, MySQL install failed!\n";
				return 0;
			};
		};

		$freebsd->rc_dot_conf_check("mysql_enable", "mysql_enable=\"YES\"");

		$freebsd->port_install("p5-DBI",       "databases");
		$freebsd->port_install("p5-DBD-mysql", "databases");

		$installed = $freebsd->is_port_installed( "mysql-server");
		if ( $installed ) {
			print "MySQL is now installed as $installed.\n";
		} else {
			print "MySQL install FAILED!\n";
			return 0;
		};

		unless ( -e "/etc/my.cnf" ) {
			if ( -e "/usr/local/share/mysql/my-large.cnf") {
				use File::Copy;
				print "installing a default /etc/my.cnf\n";
				copy("/usr/local/share/mysql/my-large.cnf", "/etc/my.cnf");
			};
		};

		unless ( -e "/tmp/mysql.sock" ) 
		{
			print "Starting up MySQL.\n";
			if ( -x "/usr/local/etc/rc.d/mysqld.sh" ) {
				$utility->syscmd("sh /usr/local/etc/rc.d/mysqld.sh start");
			};
		};

		return 1;
	}
	elsif ( $os eq "darwin" ) 
	{
		if ( -d "/usr/ports/dports" || "/usr/dports" || "/usr/darwinports" )
		{
			$darwin->port_install("mysql4");
			$darwin->port_install("p5-dbi");
			$darwin->port_install("p5-dbd-mysql");
		}
		else
		{
			$mysql = "mysql-standard-4.0.18" unless $mysql;
			$site  = "ftp://mysql.secsup.org/pub/software/mysql/Downloads/MySQL-5.0/" unless $site;

			chdir("~/Desktop/");

			unless ( -e "$mysql.tar.gz") {
				$utility->get_file("$site/$mysql.dmg");
			};

			print "There is a $mysql.dmg file in ~/Desktop/. Read and follow the readme
therein to install MySQL";	
		}
	}
}

=head2	is_newer

	my $ver   = $mysql->version($dbh);
	my $newer = $mysql->is_newer("4.1.0", $ver);

if ($newer) { print "you are brave!" };

As you can see, is_newer can be very useful, especially when you need to execute queries with syntax differences between versions of Mysql.

=cut

sub is_newer($$)
{
	my ($self, $min, $cur) = @_;

	$min =~ /^([0-9]+)\.([0-9]{1,})\.([0-9]{1,})$/;
	my @mins = ( $1, $2, $3 );
	$cur =~ /^([0-9]+)\.([0-9]{1,})\.([0-9]{1,})$/;
	my @curs = ( $1, $2, $3 );

	if ( $curs[0] > $mins[0] ) { return 1; };
	if ( $curs[1] > $mins[1] ) { return 1; };
	if ( $curs[2] > $mins[2] ) { return 1; };

	return 0;
};



=head2 parse_dot_file

 $mysql->parse_dot_file ($file, $start, $debug)

Example: 

 my $dot = $mysql->parse_dot_file(".my.cnf", "[mysql_replicate_manager]", 0);

 $file is the file to be parsed.

$start is the [identifier] where we begin looking for settings.  This expects the format used in .my.cnf MySQL configuration files.

A hashref is returned wih key value pairs

=cut

sub parse_dot_file($$;$)
{
	my ($self, $file, $start, $debug) = @_;

	my ($homedir) = (getpwuid ($<))[7];
	my $dotfile   = "$homedir/$file";

	unless ( -e $dotfile ) {
		print "parse_dot_file: creating a default .my.cnf file in $dotfile.\n";
		my @lines = "[mysql]";
		push @lines, "user=root";
		push @lines, "pass=";
		$utility->file_write($dotfile, @lines);
		chmod 00700, $dotfile;
	};

	if (-r $dotfile) 
	{
		my (%array);
		my $gotit = 0;
	
		print "parse_dot_file: $dotfile\n" if ($debug);
		open(DOT, $dotfile) or carp "WARNING: Can't open $dotfile: $!";
		while ( <DOT> ) 
		{
			next if /^#/;
			my $line = $_; chomp $line;
			unless ( $gotit ) 
			{
				print "1. $line\n" if $debug;
				if ($line eq $start) 
				{
					$gotit = 1; 
					next;
				};
			} 
			else 
			{
				if ( $line =~ /^\[/ ) { last };
				print "2. $line\n" if $debug;
				$line =~ /(\w+)\s*=\s*(.*)\s*$/;
				$array{$1} = $2 if $1;
			};
		};
	
		if ($debug) 
		{
			foreach my $key ( keys %array ) 
			{
				print "hash: $key\t=$array{$key}\n";
			};
		};
		close(DOT);
		return \%array;
	} else 
	{
		carp "WARNING: parse_dot_file: can't read $dotfile!\n";
		return 0;
	};
};


=head2 phpmyadmin_install

Install PhpMyAdmin from FreeBSD ports.

	$mysql->phpmyadmin_install($conf);

$conf is a hash of configuration values. See toaster-watcher.conf for configuring the optional values to pass along.

=cut

sub phpmyadmin_install
{
	my ($self, $conf) = @_;

	unless ( $conf->{'install_phpmyadmin'} ) {
		print "phpmyadmin: install is disabled. Enable install_phpmyadmin in toaster-watcher.conf and try again.\n";
		return 0;
	}

	my $dir;

	if ( $os eq "freebsd" )
	{
		$freebsd->port_install("phpmyadmin", "databases", "", "phpMyAdmin");
		$dir = "/usr/local/www/data/phpMyAdmin";
		# the port moved the install location
		unless (-d $dir ) { $dir = "/usr/local/www/phpMyAdmin"; };
	} 
	elsif ( $os eq "darwin") 
	{
		print "NOTICE: the port install of phpmyadmin requires that Apache be installed in ports!\n";
		$darwin->port_install("phpmyadmin");
		$dir = "/Library/Webserver/Documents/phpmyadmin";
	};

	if ( -e $dir )
	{
		print "installed successfully. Now configuring....";
		unless ( -e "$dir/config.inc.php" ) {

			my $user = $conf->{'phpMyAdmin_user'};      $user ||= "pma";
			my $pass = $conf->{'phpMyAdmin_pass'};      $pass ||= "pmapass";
			my $auth = $conf->{'phpMyAdmin_auth_type'}; $auth ||= "cookie";

			$utility->syscmd("cp $dir/config.inc.php.sample $dir/config.inc.php");

			my @lines = $utility->file_read("$dir/config.inc.php");
			foreach (@lines) 
			{
				chomp;
				if    ( /(\$cfg\['blowfish_secret'\] =) ''/            ) { $_ = "$1 'babble, babble, babble blowy fish';" }
				elsif ( /(\$cfg\['Servers'\]\[\$i\]\['controluser'\])/ ) { $_ = "$1   = '$user';"   }
				elsif ( /(\$cfg\['Servers'\]\[\$i\]\['controlpass'\])/ ) { $_ = "$1   = '$pass';"   }
				elsif ( /(\$cfg\['Servers'\]\[\$i\]\['auth_type'\])/   ) { $_ = "$1     = '$auth';" };
			};
			$utility->file_write("$dir/config.inc.php", @lines);

			my $dot = { user => 'root', pass => '' };
			if ( $self->connect( $dot, 1) )
			{
				my ($dbh, $dsn, $drh) = $self->connect($dot, 1);

				my $query = "GRANT USAGE ON mysql.* TO '$user'\@'localhost' IDENTIFIED BY '$pass'";
				my $sth = $self->query ($dbh, $query);
				$query = "GRANT SELECT ( Host, User, Select_priv, Insert_priv, Update_priv, Delete_priv,
    Create_priv, Drop_priv, Reload_priv, Shutdown_priv, Process_priv, File_priv, Grant_priv, References_priv, Index_priv, Alter_priv, Show_db_priv, Super_priv, Create_tmp_table_priv, Lock_tables_priv, Execute_priv, Repl_slave_priv, Repl_client_priv) ON mysql.user TO '$user'\@'localhost'";
				$sth = $self->query ($dbh, $query);
				$query = "GRANT SELECT ON mysql.db TO '$user'\@'localhost'";
				$sth = $self->query ($dbh, $query);
				$query = "GRANT SELECT ON mysql.host TO '$user'\@'localhost'";
				$sth = $self->query ($dbh, $query);
				$query = "GRANT SELECT (Host, Db, User, Table_name, Table_priv, Column_priv) ON mysql.tables_priv TO '$user'\@'localhost'";
				$sth = $self->query ($dbh, $query);
				$sth->finish;
				#$dbh->close;
			} else {
				print <<EOGRANT
\n\n
   NOTICE: You need to log into MySQL and run the following comands:

GRANT USAGE ON mysql.* TO '$user'\@'localhost' IDENTIFIED BY '$pass';
GRANT SELECT (
    Host, User, Select_priv, Insert_priv, Update_priv, Delete_priv,
    Create_priv, Drop_priv, Reload_priv, Shutdown_priv, Process_priv,
    File_priv, Grant_priv, References_priv, Index_priv, Alter_priv,
    Show_db_priv, Super_priv, Create_tmp_table_priv, Lock_tables_priv,
    Execute_priv, Repl_slave_priv, Repl_client_priv
    ) ON mysql.user TO '$user'\@'localhost';
GRANT SELECT ON mysql.db TO '$user'\@'localhost';
GRANT SELECT ON mysql.host TO '$user'\@'localhost';
GRANT SELECT (Host, Db, User, Table_name, Table_priv, Column_priv)
    ON mysql.tables_priv TO '$user'\@'localhost';

\n\n
EOGRANT
;
			};
		};
	} 
	else { print "FAILURE: phpMyAdmin installation failed.\n"; };

	return 1;
};


=head2 query

    my $sth = $mysql->query ($dbh, $query, $warn)

$dbh is the database handle you've already acquired via $mysql->connect.

$query is the SQL statement to execute.

If $warn is set, we don't die if the query fails. This way you can decide when you call the sub whether you want it to die or return a failed $sth (and likely an error message).

 execute performs whats necessary to execute a statement
 Always returns true regardless of # of rows affected.
 For non-Select, returns # of rows affected: No rows = 0E0
 For Select, simply starts query. Follow with fetch_*

=cut

sub query($$;$)
{
	my ($self, $dbh, $query, $warn) = @_;

	if ($warn)
	{
		if ( my $sth = $dbh->prepare($query) ) 
		{
			$sth->execute or carp "couldn't execute: $sth->errstr\n";
			#$dbh->commit  or carp "couldn't commit: $sth->errstr\n";
			return $sth;
		} 
		else
		{
			carp "couldn't prepare: $DBI::errstr\n";
			return $sth;
		};
	} 
	else 
	{
		if ( my $sth = $dbh->prepare($query) ) 
		{
			$sth->execute or croak "couldn't execute: $sth->errstr\n";
			#$dbh->commit  or croak "couldn't commit: $sth->errstr\n";
			return $sth;
		} 
		else 
		{
			croak "couldn't prepare: $DBI::errstr\n";
		};
	};
};

=head2 query_confirm

	$mysql->query_confirm($dbh, $query, $debug);

Use this if you want to interactively get user confirmation before executing a query.

=cut

sub query_confirm
{
	my ($self, $dbh, $query, $debug) = @_;

	if ( $utility->yes_or_no("\n\t$query \n\n Does this query look correct? ") )
	{
		my $sth = $self->query($dbh, $query);
		$sth->finish;
		print "\nQuery executed successfully.\n" if $debug;
	};
};

=head2 sanity

A place to do validation tests on values to make sure they're reasonable

Currently we only check to assure the password is less than 32 characters and the username is less than 16. Many more tests will come.

=cut

sub sanity($)
{
	my ($self, $dot) = @_;

	if ( $dot->{'user'} )
	{
		if ( length($dot->{'user'}) > 16 )
		{
			croak "\n\nUsername cannot exceed 16 characters. Edit user in ~/.my.cnf\n\n"
		};
	}
	else
	{ 
		croak "\n\nYou have not configured ~/.my.cnf. Read the FAQ before proceeding.\n\n";
	};

	if ( $dot->{'pass'} )
	{
		if ( length($dot->{'pass'}) > 32 )
		{
			croak "\nPassword cannot exceed 16 characters. Edit pass in ~/.my.cnf\n\n"
		};
	}
	else
	{
		croak "\nYou have not configured ~/.my.cnf properly. Read the FAQ before proceeding.\n\n";
	};
};


=head2 shutdown_mysqld

Shuts down mysql using a $drh handle.

   my $rc = $mysql->shutdown_mysqld($dbvs, $drh);

$dbvs is a hashref containing: host, user, pass

returns error_code 200 on success, 500 on error. See error_desc for details.

=cut

sub shutdown_mysqld($$;$)
{
	my ($self, $db_v, $drh, $debug) = @_;
	my $rc;

	print "shutdown: shutting down mysqld $db_v->{'host'}..." if $debug;

	if ( $drh ) {
		$rc = $drh->func('shutdown', $db_v->{'host'}, $db_v->{'user'}, $db_v->{'pass'}, 'admin');
	} else {
		(my $dbh, my $dsn, $drh) = $self->connect($db_v, 1);
		unless ( $drh ) {
			print "shutdown_mysqld: FAILED: couldn't connect.\n";
			return 0;
		};
		$rc = $drh->func('shutdown', $db_v->{'host'}, $db_v->{'user'}, $db_v->{'pass'}, 'admin');
	};

	if ($debug) 
	{
		print "shutdown->rc: $rc\n";
		$rc ? print "success.\n" : print "failed.\n";
	};

	if ($rc) {
		return { error_code=>200, error_desc=>"$db_v->{'host'} shutdown successful" };
	} else {
		return { error_code=>500, error_desc=>"$drh->err, $drh->errstr" };
	};
};


=head2 status

=cut

sub status($)
{
	my ($self, $dbh) = @_;

	unless ($dbh) { print "FAILED: no database handle passed to status()!\n"; return 0; };

	if (my $sth = $self->query($dbh, "SHOW STATUS"))
	{
		while ( my $r = $sth->fetchrow_arrayref ) {
			print "\t\t\t  $r->[0] \t $r->[1]\n";
		};
		$sth->finish;
	}
}

=head2	tables_lock

	my $sth = $mysql->tables_lock($dbh, $debug);
	# do some mysql stuff
	$mysql->tables_unlock($dbh, $sth);

Takes a statement handle and does a global lock on all tables.  Quite useful when you want do do things like make a tarball of the database directory, back up the server, etc.

=cut

sub tables_lock($;$)
{
	my ($self, $dbh, $debug) = @_;

	# Table locking is done at the per-thread level. If we did a $sth->finish
	# the thread would end and we'd lose our lock. So, instead we pass the $sth
	# handle back and close it after we've done our deeds.

	print "lock_tables: locking tables.\n" if $debug;

	if (my $sth = $self->query($dbh, "FLUSH TABLES WITH READ LOCK")) 
	{
		return $sth;
	};
};

sub tables_unlock($$;$)
{

=head2	tables_unlock

	$mysql->tables_unlock($dbh, $sth, $debug);

Takes a statement handle and does a global unlock on all tables.  Quite useful after you've used $mysql->tables_lock, done your deeds and wish to release your lock.

=cut
	
	my ($self, $dbh, $sth, $debug) = @_;

	print "tables_unlock: unlocking mysql tables.\n" if $debug;

	my $query = "UNLOCK TABLES";  # unnecessary, simply calling finish does this

	$sth = $self->query($dbh, $query)
		or croak "FATAL: couldn't unlock tables: $sth->errstr\n";

	$sth->finish;
}

sub InstallMysqlTool($;$$)
{

	# deprecated, can likely be removed (11/5/2004) - mps

	my ($package, $httpdir, $confdir) = @_;

	my $site = "http://www.dajoba.com/projects/mysqltool";
	$httpdir = "/usr/local/www" unless ($httpdir);
	$confdir = "/usr/local/etc" unless ($confdir);

	if ( $os eq "freebsd" ) 
	{
		$freebsd->port_install("p5-Crypt-Blowfish", "security");
		$freebsd->port_install("p5-DBI",            "databases");
		$freebsd->port_install("p5-Apache-DBI",     "www", undef, undef, "WITH_MODPERL2=yes");
		$freebsd->port_install("p5-DBD-mysql",      "databases");
		$freebsd->port_install("p5-SOAP-Lite",      "net");
	} 
	else 
	{
		use CPAN qw();
		CPAN::Shell->install("Crypt::Blowfish");
		CPAN::Shell->install("DBI");
		CPAN::Shell->install("Apache::DBI");
		CPAN::Shell->install("DBD::mysql");
		CPAN::Shell->install("SOAP::Lite");
	};

	$utility->chdir_source_dir("/usr/local/www");

	unless (-e "$package.tar.gz" ) {
		$utility->get_file("$site/$package.tar.gz");
	};

	if ( -d "$package" )
	{
		my $r = $utility->source_warning($package, 1);
		unless ($r) { croak "sorry, I can't continue.\n"; };
	};

	my $tar = $utility->find_the_bin("tar");
	$utility->syscmd("$tar -xzf $package.tar.gz");
	chdir($package);
	$utility->syscmd( "perl Makefile.PL");
	$utility->syscmd( "make");
	$utility->syscmd( "make install clean");

	unless ( -e "$confdir/apache/mysqltool.conf" ) 
	{
		move("htdocs/mysqltool.conf", "$confdir/apache") or croak "move failed: $!\n";
	};

	unless ( -e "$httpdir/data/mysqltool" ) 
	{
		$utility->get_file("http://matt.simerson.net/computing/sql/mysqltool.index.txt");
		move("mysqltool.index.txt", "htdocs/index.cgi");
		move("htdocs", "$httpdir/data/mysqltool") or croak "move failed: $!\n";
	};
};

=head2	version
	
	my $ver = $mysql->version($dbh);

Returns a string representing the version of MySQL running.

=cut

sub version($)
{
	my ($self, $dbh) = @_;
	my ($sth, $minor);

	if ( $sth = $self->query($dbh, "SELECT VERSION()") )
	{
		my $r = $sth->fetchrow_arrayref;
		($minor) = split(/-/, $r->[0]);
		$sth->finish;
	};

	return $minor;
};


1;
__END__


=head1 Dependencies

   DBI.pm     - /usr/ports/databases/p5-DBI
   DBD::mysql - /usr/ports/databases/p5-DBD-mysql

In order to use this module, you must have DBI.pm and DBD::Mysql installed. If they are not installed and you attempt to use this module, you should get some helpful error messages telling you how to install them.

=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>

=head1 BUGS

None known. Report any to author.

=head1 TODO

=head1 SEE ALSO

The following are all man/perldoc pages: 

 Mail::Toaster 
 Mail::Toaster::Conf
 toaster.conf
 toaster-watcher.conf

 http://matt.simerson.net/computing/mail/toaster/


=head1 COPYRIGHT


Copyright (c) 2003-2005, The Network People, Inc. All Rights Reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut
