#!/usr/bin/perl
use strict;
use warnings;

#
# $Id: Mysql.pm, matt Exp $
#

package Mail::Toaster::Mysql;

use Carp;

#use Getopt::Std;
use Params::Validate qw( :all );
use English qw( -no_match_vars );

use vars qw($VERSION $darwin $freebsd);
$VERSION = '5.05';

use lib "lib";
use Mail::Toaster::Perl    5; my $perl = Mail::Toaster::Perl->new;
use Mail::Toaster::Utility 5; my $utility = Mail::Toaster::Utility->new;

if ( $OSNAME eq "freebsd" ) {
    require Mail::Toaster::FreeBSD;
    $freebsd = Mail::Toaster::FreeBSD->new;
}
elsif ( $OSNAME eq "darwin" ) {
    require Mail::Toaster::Darwin;
    $darwin = Mail::Toaster::Darwin->new;
}

sub new {
    my ( $class, $name ) = @_;
    my $self = { name => $name };
    bless( $self, $class );
    return $self;
}

sub autocommit {

    my ($dot) = @_;

    if ( $dot->{'autocommit'} && $dot->{'autocommit'} ne "" ) {

        return $dot->{'autocommit'};    #	SetAutocommit
    }
    else {
        return 1;                       #  Default to autocommit.
    }
}

sub backup {

    my ( $self, $dot ) = @_;

    unless ( $utility->is_hashref($dot) ) {
        print "FATAL, you passed backup a bad argument!\n";
        return 0;
    }

    my $debug      = $dot->{'debug'};
    my $backupfile = $dot->{'backupfile'} || "mysql_full_dump";
    my $backupdir  = $dot->{'backup_dir'} || "/var/backups/mysql";

    print "backup: beginning mysql_backup.\n" if $debug;

    my $cronolog  = $utility->find_the_bin( bin => "cronolog" );
    my $mysqldump = $utility->find_the_bin( bin => "mysqldump" );

    my $mysqlopts = "--all-databases --opt --password=" . $dot->{'pass'};
    my ( $dd, $mm, $yy ) = $utility->get_the_date( debug => $debug );

    print "backup: backup root is $backupdir.\n" if $debug;

    $utility->chdir_source_dir( dir => "$backupdir/$yy/$mm/$dd" );

    print "backup: backup file is $backupfile.\n" if $debug;

    if (   -e "$backupdir/$yy/$mm/$dd/$backupfile"
        || -e "$backupdir/$yy/$mm/$dd/$backupfile.gz" )
    {
        $utility->_formatted( "backup: backup for today is already done.",
            "ok (skipped)" )
          if $debug;
    }

    # dump the databases
    my $cmd =
      "$mysqldump $mysqlopts | $cronolog $backupdir/%Y/%m/%d/$backupfile";
    $utility->_formatted("backup: running $cmd") if $debug;
    $utility->syscmd( command => $cmd );

    # gzip the backup to greatly reduce its size
    my $gzip = $utility->find_the_bin( bin => "gzip" );
    $cmd = "$gzip $backupdir/$yy/$mm/$dd/$backupfile";
    $utility->_formatted("backup: running $cmd") if $debug;
    $utility->syscmd( command => $cmd );
}

sub binlog_on {

    my ( $self, $db_mv ) = @_;

    if ( $db_mv->{log_bin} ne "ON" ) {
        print <<EOBINLOG;

Hey there! In order for this server to act as a master, binary logging
must be enabled! Please edit /etc/my.cnf or $db_mv->{datadir}/my.cnf and
add "log-bin". You must also set server-id as documented at mysql.com.

EOBINLOG
        return 0;
    }

    return 1;
}

sub connect {

    my ( $self, $dot, $warn, $debug ) = @_;
    my $dbh;

    $perl->module_load(
            module      => "DBI",
            port_name  => "p5-DBI",
            port_group => "databases",
            debug       => 1,
    );
    $perl->module_load(
            module      => "DBD::mysql",
            port_name  => "p5-DBD-mysql",
            port_group => "databases",
            debug       => 1,
    );

    my $ac  = $self->autocommit($dot);
    my $dbv = $self->db_vars($dot);
    my $dsn =
"DBI:$dbv->{'driver'}:database=$dbv->{'db'};host=$dbv->{'host'};port=$dbv->{'port'}";

    $dbh =
      DBI->connect( $dsn, $dbv->{'user'}, $dbv->{'pass'},
        { RaiseError => 0, AutoCommit => $ac } );
    if ( !$dbh ) {
        carp "db connect failed: $!\n" if $debug;
        croak unless $warn;
        return $dbh;
    }

    my $drh = DBI->install_driver( $dbv->{'driver'} );

    return ( $dbh, $dsn, $drh );
}

sub db_vars {

    my ( $self, $val ) = @_;
    my ( $driver, $db, $host, $port, $user, $pass, $dir );

    $driver = $val->{'driver'} || "mysql";
    $db     = $val->{'db'}     || "mysql";
    $host   = $val->{'host'}   || "localhost";
    $port   = $val->{'port'}   || "3306";
    $user   = $val->{'user'}   || "root";
    $pass   = $val->{'pass'}   || "";
    $dir    = $val->{'dir_m'}  || "/var/db/mysql";

    return {
        driver => $driver,
        db     => $db,
        host   => $host,
        port   => $port,
        user   => $user,
        pass   => $pass,
        dir    => $dir
    };
}

sub dbs_list {

    my ( $self, $dbh ) = @_;

    if ( my $sth = $self->query( $dbh, "SHOW DATABASES" ) ) {
        while ( my ($db_name) = $sth->fetchrow_array ) { print "$db_name "; }

        if ( $sth->err ) { print "FAILED!\n"; }
        else { $sth->finish; print "\n"; }
    }

    ### Documented (but non-working methods for listing databases ###
   # my @databases = $drh->func($db_mv->{'host'}, $db_mv->{'port'}, '_ListDBs');
   # print "mysql_info->databases:\t@databases\n";
   #
   # my @databases2 = DBI->data_sources("mysql");
   # print "mysql_info->databases2:\t@databases2\n";
}

sub defaults {

    my $self = shift;

    if ( -e "/etc/my.cnf" ) {
        $utility->_formatted( "mysql->defaults: checking my.cnf ",
            "ok (exists)" );
        return 1;
    }

    $utility->_formatted( "mysql->defaults: checking my.cnf ", "MISSING" );

    if ( -e "/usr/local/share/mysql/my-large.cnf" ) {
        use File::Copy;
        copy( "/usr/local/share/mysql/my-large.cnf", "/etc/my.cnf" );

        if ( -e "/etc/my.cnf" ) {
            $utility->_formatted( "mysql->defaults: installing my.cnf ", "ok" );
            print "\n\n\tI just installed a default /etc/my.cnf\n";
            print "\n\tPlease review it for sanity in your environment!\n\n";
            sleep 3;
        }
        else {
            $utility->_formatted( "mysql->defaults: installing my.cnf ",
                "FAILED" );
        }
    }
}

sub flush_logs {

    my ( $self, $dbh, $debug ) = @_;

    my $query = "FLUSH LOGS";
    my $sth = $self->query( $dbh, $query );
    $sth->finish;

    return { error_code => 200, error_desc => "logs flushed successfully" };
}

sub get_hashes {

    my ( $self, $dbh, $sql ) = @_;
    my @records;

    if ( my $sth = $self->query( $dbh, $sql ) ) {
        while ( my $ref = $sth->fetchrow_hashref ) {
            push @records, $ref;
        }
        $sth->finish;
    }
    return @records;
}

sub install {

    my $self = shift;

    # parameter validation here
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'mysql'   => { type=>SCALAR,  optional=>1, },
            'site'    => { type=>SCALAR,  optional=>1, },
            'ver'     => { type=>SCALAR,  optional=>0, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $conf, $mysql, $site, $ver, $fatal, $debug )
        = ( $p{'conf'}, $p{'mysql'}, $p{'site'}, $p{'ver'}, $p{'fatal'}, $p{'debug'} );

    # only install if install_mysql is set to a value we recognize
    unless ($ver) {
        print "skipping MySQL, it's not selected!\n";
        return 0;
    }

    if ( $OSNAME eq "darwin" ) {
        print "detected OS " . $OSNAME . ", installing for Darwin.\n";
        return $self->install_darwin($mysql, $site, $debug);
    };

    # we only install using FreeBSD ports and DarwinPorts at this time
    if ( ! $OSNAME eq "freebsd" ) {
        print "\nskipping MySQL, build support on $OSNAME is not available."
            . "Please install MySQL manually.\n";
        return;
    };

    my $installed = $freebsd->is_port_installed( port => "mysql-server", debug => 0 );

    if ($installed) {
        $utility->_formatted( "mysql->install: MySQL is already installed",
            "ok ($installed)" );

        return $self->mysql_extras(conf=>$conf, debug=>$debug);
    };

    # try to speed things up by installing the package
    my $package_install = 0;
    $package_install ++ if ( $ver == 1 && !$installed);

    if ( ! $package_install ) {
        $package_install ++ if ( $utility->answer( question=>"I can save you some time by installing the precompiled mysql package instead of compiling from ports. The advantage is it will save you a lot of time building. The disadvantage is that it will likely not be the latest release of MySQL. Shall I install the package?", timeout=>60 ) );
    };

    if ( $package_install ) {

        my $package_name = $ver eq "51" ? "mysql51-server" 
                         : $ver eq "50" ? "mysql50-server"
                         : $ver eq "41" ? "mysql41-server"
                         : $ver eq "40" ? "mysql40-server"
                         : $ver eq  "4" ? "mysql41-server"
                         : "mysql50-server";

        $freebsd->package_install( port => $package_name, debug=>$debug );

        $installed = $freebsd->is_port_installed( port => "mysql-server", debug=>0 );

        if (! $installed) {
            # try this for really old freebsd ports tree
            $freebsd->package_install( port => "mysql-server", debug=>$debug );
            $installed =
                $freebsd->is_port_installed( port => "mysql-server", debug=>0 );
        }

        if ( $freebsd->is_port_installed( port => "mysql-server", debug=>0) ) {
            $utility->_formatted( "mysql->install: installing MySQL",
                "ok ($installed)" );
            return $self->mysql_extras(conf=>$conf, debug=>$debug);
        };
    }

    # MySQL is still not installed, lets do it!
    my $copts = "SKIP_DNS_CHECK";

    if ($conf) {
        $copts .= ",WITH_OPENSSL"    if $conf->{'install_mysql_ssl'};
        $copts .= ",BUILD_OPTIMIZED" if $conf->{'install_mysql_optimized'};

        $copts .= $self->with_linuxthreads($conf->{'install_mysql_linuxthreads'}, $ver);

        if (    $conf->{'install_mysql_dir'}
            and $conf->{'install_mysql_dir'} ne "/var/db/mysql" )
        {

            # the user overrode the default mysql db location
            $copts .= ",DB_DIR=" . $conf->{'install_mysql_dir'};
        }
    }

    my ( $port, $check, $dir );
    $dir = "";

    if ( $ver == 3 || $ver == 323 ) {
        $port  = "mysql323-server";
        $check = "mysql-server-3.23";
    }
    elsif ( $ver == 4 || $ver == 40 ) {
        $port  = "mysql40-server";
        $check = "mysql-server-4.0";
    }
    elsif ( $ver == 41 || $ver == 4.1 ) {
        $port  = "mysql41-server";
        $check = "mysql-server-4.1";
    }
    elsif ( $ver == 5 || $ver == 50 || $ver == 5.0 ) {
        $port  = "mysql50-server";
        $check = "mysql-server-5";
    }
    elsif ( $ver == 51 || $ver == 5.1 ) {
        $port  = "mysql51-server";
        $check = "mysql-server-5";
    }
    else {
        # default version (latest stable)
        $port  = "mysql50-server";
        $check = "mysql-server-5";
    }

    unless (
        $freebsd->port_install(
            port  => $port,
            base  => 'databases',
            dir   => $dir,
            check => $check,
            flags => $copts,
            debug => $debug,
        )
        )
    {
        $utility->_formatted( "install: installing MySQL", "FAILED" );
        return;
    }

    if ( !$freebsd->is_port_installed( port => "mysql-server", debug=>$debug ) ) {
        $utility->_formatted( "install: installing MySQL", "FAILED" );
        return;
    }

    $utility->_formatted( "install: installing MySQL", "ok" );
    return $self->mysql_extras(conf=>$conf, debug=>$debug);
};

sub install_darwin {

    my $self = shift;

    my $mysql = shift;
    my $site  = shift;
    my $debug = shift;

    if ( $OSNAME ne "darwin" ) {
        croak "you are calling this incorrectly!\n";
    };

#    if ( -d "/usr/ports/dports" || "/usr/dports" || "/usr/darwinports" ) {
    if ( $utility->find_the_bin( bin=>"port", debug=>0) ) {
        $darwin->port_install( port_name => "mysql4", debug=>$debug );
        $darwin->port_install( port_name => "p5-dbi", debug=>$debug );
        $darwin->port_install( port_name => "p5-dbd-mysql", debug=>$debug );
        return 1;
    }

    print "DarwinPorts is not installed. Attempting to fetch a binary installation.\n";
    $mysql = "mysql-standard-5.0.24-osx10.4-powerpc.dmg" unless $mysql;
    $site = "ftp://mysql.secsup.org/pub/software/mysql/Downloads/MySQL-5.0/" unless $site;

    chdir("~/Desktop/");

    unless ( -e "$mysql.tar.gz" ) {
        $utility->file_get(url=>"$site/$mysql", debug=>$debug);
    }

    print "There is a $mysql.dmg file on your Desktop. Read and follow the "
        . "readme therein to install MySQL";
}

sub is_newer {

    my ( $self, $min, $cur ) = @_;

    $min =~ /^([0-9]+)\.([0-9]{1,})\.([0-9]{1,})$/;
    my @mins = ( $1, $2, $3 );
    $cur =~ /^([0-9]+)\.([0-9]{1,})\.([0-9]{1,})$/;
    my @curs = ( $1, $2, $3 );

    if ( $curs[0] > $mins[0] ) { return 1; }
    if ( $curs[1] > $mins[1] ) { return 1; }
    if ( $curs[2] > $mins[2] ) { return 1; }

    return 0;
}

sub mysql_extras {

    my $self = shift;

    # parameter validation here
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $conf, $fatal, $debug ) = ( $p{'conf'}, $p{'fatal'}, $p{'debug'} );

    $freebsd->rc_dot_conf_check( 
        check=>"mysql_enable",
        line=>"mysql_enable=\"YES\"", 
        debug=>$debug, );

    $self->defaults();

    $self->startup( conf=>$conf, debug=>$debug );

    $freebsd->port_install( 
        port => "p5-DBI", 
        base => "databases", 
        debug => $debug, );

    $freebsd->port_install(
        port => "p5-DBD-mysql",
        base => "databases",
        debug => $debug,
    );

    return 1;
}

sub parse_dot_file {

    my ( $self, $file, $start, $debug ) = @_;

    my ($homedir) = ( getpwuid($<) )[7];
    my $dotfile = "$homedir/$file";

    unless ( -e $dotfile ) {
        print "parse_dot_file: creating a default .my.cnf file in $dotfile.\n";
        my @lines = "[mysql]";
        push @lines, "user=root";
        push @lines, "pass=";
        $utility->file_write( file => $dotfile, lines => \@lines, debug=>$debug );
        $utility->file_chmod( file => $dotfile, mode => '0700', debug=>$debug );
    }

    if ( !-r $dotfile ) {
        carp "WARNING: parse_dot_file: can't read $dotfile!\n";
        return 0;
    }

    my %array;
    my $gotit = 0;

    print "parse_dot_file: $dotfile\n" if $debug;
    foreach ( $utility->file_read( file => $dotfile, debug=>$debug ) ) {

        next if /^#/;
        my $line = $_;
        chomp $line;
        if ($gotit) {
            if ( $line =~ /^\[/ ) { last }
            print "2. $line\n" if $debug;
            $line =~ /(\w+)\s*=\s*(.*)\s*$/;
            $array{$1} = $2 if $1;
        }
        else {
            print "1. $line\n" if $debug;
            if ( $line eq $start ) {
                $gotit = 1;
                next;
            }
        }
    }

    if ($debug) {
        foreach my $key ( keys %array ) {
            print "hash: $key\t=$array{$key}\n";
        }
    }

    return \%array;
}

sub phpmyadmin_install {

    my ( $self, $conf ) = @_;

    if ( ! $conf->{'install_phpmyadmin'} ) {
        print "phpmyadmin: install is disabled. Enable install_phpmyadmin in "
            . "toaster-watcher.conf and try again.\n";
        return;
    }

    my $dir;

    if ( $OSNAME eq "freebsd" ) {

        $freebsd->port_install(
            port  => "phpmyadmin",
            base  => "databases",
            check => "phpMyAdmin"
        );
        $dir = "/usr/local/www/data/phpMyAdmin";

        # the port moved the install location
        unless ( -d $dir ) { $dir = "/usr/local/www/phpMyAdmin"; }
    }
    elsif ( $OSNAME eq "darwin" ) {

        print
"NOTICE: the port install of phpmyadmin requires that Apache be installed in ports!\n";
        $darwin->port_install( port_name => "phpmyadmin" );
        $dir = "/Library/Webserver/Documents/phpmyadmin";
    }

    if ( !-e $dir ) {
        print "FAILURE: phpMyAdmin installation failed.\n";
        return 0;
    }

    print "installed successfully. Now configuring....";
    unless ( -e "$dir/config.inc.php" ) {

        my $user = $conf->{'phpMyAdmin_user'}      || "pma";
        my $pass = $conf->{'phpMyAdmin_pass'}      || "pmapass";
        my $auth = $conf->{'phpMyAdmin_auth_type'} || "cookie";

        $utility->syscmd(
            command => "cp $dir/config.inc.php.sample $dir/config.inc.php" );

        my @lines = $utility->file_read( file => "$dir/config.inc.php" );
        foreach (@lines) {

            chomp;
            if (/(\$cfg\['blowfish_secret'\] =) ''/) {
                $_ = "$1 'babble, babble, babble blowy fish';";
            }
            elsif (/(\$cfg\['Servers'\]\[\$i\]\['controluser'\])/) {
                $_ = "$1 = '$user';";
            }
            elsif (/(\$cfg\['Servers'\]\[\$i\]\['controlpass'\])/) {
                $_ = "$1 = '$pass';";
            }
            elsif (/(\$cfg\['Servers'\]\[\$i\]\['auth_type'\])/) {
                $_ = "$1 = '$auth';";
            }
        }
        $utility->file_write( file => "$dir/config.inc.php", lines => \@lines );

        my $dot = { user => 'root', pass => '' };
        if ( $self->connect( $dot, 1 ) ) {

            my ( $dbh, $dsn, $drh ) = $self->connect( $dot, 1 );

            my $query =
"GRANT USAGE ON mysql.* TO '$user'\@'localhost' IDENTIFIED BY '$pass'";
            my $sth = $self->query( $dbh, $query );
            $query =
"GRANT SELECT ( Host, User, Select_priv, Insert_priv, Update_priv, Delete_priv,
    Create_priv, Drop_priv, Reload_priv, Shutdown_priv, Process_priv, File_priv, Grant_priv, References_priv, Index_priv, Alter_priv, Show_db_priv, Super_priv, Create_tmp_table_priv, Lock_tables_priv, Execute_priv, Repl_slave_priv, Repl_client_priv) ON mysql.user TO '$user'\@'localhost'";
            $sth   = $self->query( $dbh, $query );
            $query = "GRANT SELECT ON mysql.db TO '$user'\@'localhost'";
            $sth   = $self->query( $dbh, $query );
            $query = "GRANT SELECT ON mysql.host TO '$user'\@'localhost'";
            $sth   = $self->query( $dbh, $query );
            $query =
"GRANT SELECT (Host, Db, User, Table_name, Table_priv, Column_priv) ON mysql.tables_priv TO '$user'\@'localhost'";
            $sth = $self->query( $dbh, $query );
            $sth->finish;

            #$dbh->close;
        }
        else {
            print <<EOGRANT;

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

EOGRANT
        }
    }
    return 1;
}

sub query {

    my ( $self, $dbh, $query, $warn ) = @_;

    my $sth;
    if ( $sth = $dbh->prepare($query) ) {
        $sth->execute or carp "couldn't execute: $sth->errstr\n";

        #$dbh->commit  or carp "couldn't commit: $sth->errstr\n";
        return $sth;
    }

    carp "couldn't prepare: $dbh::errstr\n";    # maybe this
        #carp "couldn't prepare: DBI::errstr\n";     # or this
        #carp "couldn't prepare: $DBI::errstr\n";   # probably not right
    croak "\n" unless $warn;
    return $sth;
}

sub query_confirm {

    my ( $self, $dbh, $query, $debug ) = @_;

    if ( $utility->yes_or_no("\n\t$query \n\n Does this query look correct? ") )
    {
        my $sth;
        if ( $sth = $self->query( $dbh, $query ) ) {
            $sth->finish;
            print "\nQuery executed successfully.\n" if $debug;
        }
        print "\nQuery execute FAILED.\n";
        return 0;
    }
}

sub sanity {

    my ( $self, $dot ) = @_;

    if ( !$dot->{'user'} ) {
        croak
"\n\nYou have not configured ~/.my.cnf. Read the FAQ before proceeding.\n\n";
    }

    if ( length( $dot->{'user'} ) > 16 ) {
        croak
"\n\nUsername cannot exceed 16 characters. Edit user in ~/.my.cnf\n\n";
    }

    if ( !$dot->{'pass'} ) {
        croak
"\nYou have not configured ~/.my.cnf properly. Read the FAQ before proceeding.\n\n";
    }

    if ( length( $dot->{'pass'} ) > 32 ) {
        croak
          "\nPassword cannot exceed 16 characters. Edit pass in ~/.my.cnf\n\n";
    }
}

sub shutdown_mysqld {

    my ( $self, $db_v, $drh, $debug ) = @_;
    my $rc;

    print "shutdown: shutting down mysqld $db_v->{'host'}..." if $debug;

    if ($drh) {
        $rc = $drh->func(
            'shutdown',      $db_v->{'host'},
            $db_v->{'user'}, $db_v->{'pass'},
            'admin'
        );
    }
    else {
        ( my $dbh, my $dsn, $drh ) = $self->connect( $db_v, 1 );
        unless ($drh) {
            print "shutdown_mysqld: FAILED: couldn't connect.\n";
            return 0;
        }
        $rc = $drh->func(
            'shutdown',      $db_v->{'host'},
            $db_v->{'user'}, $db_v->{'pass'},
            'admin'
        );
    }

    if ($debug) {
        print "shutdown->rc: $rc\n";
        $rc ? print "success.\n" : print "failed.\n";
    }

    if ($rc) {
        return {
            error_code => 200,
            error_desc => "$db_v->{'host'} shutdown successful"
        };
    }
    else {
        return { error_code => 500, error_desc => "$drh->err, $drh->errstr" };
    }
}

sub startup {

    my $self = shift;
    my %p = validate(@_, { 
            'conf'=> {type=>HASHREF, optional=>1},
            'debug'=> {type=>BOOLEAN, optional=>1, default=>1},
        }
    );
    my $conf = $p{'conf'};
    my $debug = $p{'debug'};

    if ( -e "/tmp/mysql.sock" || -e "/opt/local/var/run/mysqld/mysqld.sock" ) {
        $utility->_formatted( "mysql->startup: starting MySQL ",
            "ok (already started)" );
        return 1;
    }

    my $etc = $conf->{'system_config_dir'} || "/usr/local/etc";

    my $start = "$etc/rc.d/mysql-server";
    if ( !-e $start && -e "$etc/rc.d/mysql-server.sh" ) {
        $start = "$etc/rc.d/mysql-server.sh";
    }
    if ( !-e $start && -e "$etc/init.d/mysql" ) { $start = "$etc/init.d/mysql" }
    if ( !-e $start && -e "$etc/init.d/mysql-server" ) {
        $start = "$etc/init.d/mysql-server";
    }
    if ( !-e $start && -e "$etc/rc.d/mysql" ) { $start = "$etc/rc.d/mysql" }
    if ( !-e $start && -e "$etc/rc.d/mysql.sh" ) {
        $start = "$etc/rc.d/mysql.sh";
    }

    if ( -x $start ) {
        $utility->syscmd( command => "sh $start start", debug=>0 );
        $utility->_formatted( "mysql->startup: starting MySQL ", "ok" );
    }
    else {
        $utility->_formatted( "mysql->startup: starting MySQL ", "FAILED" );
        print "\t\tcould not find startup file.\n";
        return 0;
    }

    return 1;
}

sub status {


    my ( $self, $dbh ) = @_;

    unless ($dbh) {
        print "FAILED: no database handle passed to status()!\n";
        return 0;
    }

    if ( my $sth = $self->query( $dbh, "SHOW STATUS" ) ) {
        while ( my $r = $sth->fetchrow_arrayref ) {
            print "\t\t\t  $r->[0] \t $r->[1]\n";
        }
        $sth->finish;
    }
}

sub tables_lock {

    my ( $self, $dbh, $debug ) = @_;

    # Table locking is done at the per-thread level. If we did a $sth->finish
    # the thread would end and we'd lose our lock. So, instead we pass the $sth
    # handle back and close it after we've done our deeds.

    print "lock_tables: locking tables.\n" if $debug;

    if ( my $sth = $self->query( $dbh, "FLUSH TABLES WITH READ LOCK" ) ) {
        return $sth;
    }
}

sub tables_unlock {

    my ( $self, $dbh, $sth, $debug ) = @_;

    print "tables_unlock: unlocking mysql tables.\n" if $debug;

    my $query = "UNLOCK TABLES";  # unnecessary, simply calling finish does this

    $sth = $self->query( $dbh, $query )
      or croak "FATAL: couldn't unlock tables: $sth->errstr\n";

    $sth->finish;
}

sub InstallMysqlTool {

    # deprecated, can likely be removed (11/5/2004) - mps

    my ( $package, $httpdir, $confdir ) = @_;

    my $site = "http://www.dajoba.com/projects/mysqltool";
    $httpdir = "/usr/local/www" unless ($httpdir);
    $confdir = "/usr/local/etc" unless ($confdir);

    if ( $OSNAME eq "freebsd" ) {
        $freebsd->port_install(
            port => "p5-Crypt-Blowfish",
            base => "security"
        );
        $freebsd->port_install( port => "p5-DBI", base => "databases" );
        $freebsd->port_install(
            port  => "p5-Apache-DBI",
            base  => "www",
            flags => "WITH_MODPERL2=yes"
        );
        $freebsd->port_install( port => "p5-DBD-mysql", base => "databases" );
        $freebsd->port_install( port => "p5-SOAP-Lite", base => "net" );
    }
    else {
        use CPAN qw();
        CPAN::Shell->install("Crypt::Blowfish");
        CPAN::Shell->install("DBI");
        CPAN::Shell->install("Apache::DBI");
        CPAN::Shell->install("DBD::mysql");
        CPAN::Shell->install("SOAP::Lite");
    }

    $utility->chdir_source_dir( dir => "/usr/local/www" );

    unless ( -e "$package.tar.gz" ) {
        $utility->get_file("$site/$package.tar.gz");
    }

    if ( -d "$package" ) {
        my $r = $utility->source_warning( $package, 1 );
        unless ($r) { croak "sorry, I can't continue.\n"; }
    }

    my $tar = $utility->find_the_bin( bin => "tar" );
    $utility->syscmd( command => "$tar -xzf $package.tar.gz" );
    chdir($package);
    $utility->syscmd( command => "perl Makefile.PL" );
    $utility->syscmd( command => "make" );
    $utility->syscmd( command => "make install clean" );

    unless ( -e "$confdir/apache/mysqltool.conf" ) {
        move( "htdocs/mysqltool.conf", "$confdir/apache" )
          or croak "move failed: $!\n";
    }

    unless ( -e "$httpdir/data/mysqltool" ) {
        $utility->get_file(
            "http://matt.simerson.net/computing/sql/mysqltool.index.txt");
        move( "mysqltool.index.txt", "htdocs/index.cgi" );
        move( "htdocs",              "$httpdir/data/mysqltool" )
          or croak "move failed: $!\n";
    }
}

sub version {

    my ( $self, $dbh ) = @_;
    my ( $sth, $minor );

    if ( $sth = $self->query( $dbh, "SELECT VERSION()" ) ) {
        my $r = $sth->fetchrow_arrayref;
        ($minor) = split( /-/, $r->[0] );
        $sth->finish;
    }

    return $minor;
}

sub with_linuxthreads {
    my $self = shift;
    my $linuxthreads = shift;
    my $ver  = shift;

    if ( $linuxthreads ) {
        return ",WITH_LINUXTHREADS";
    };

    if ( $ver =~ /^4/ && `uname -r` =~ /^4/ )  # FreeBSD 4 & MySQL 4
    {
        if ( $utility->yes_or_no( "\n\nHEY!!  You are installing MySQL v4.x on FreeBSD 4. " 
    . "In this configuration, it is recommended that you compile MySQL with linuxthreads. Please see: http://mail-toaster.org/faq/programs/mysql.shtml for more detailed information. You probably should. Shall I enable linuxthreads for you?"
            )
            )
        {
            print " Excellent choice!\n. Now, don't forget to update toaster-watcher.conf and set install_mysql_linuxthreads.\n";
            return ",WITH_LINUXTHREADS";
        }
    }

    return "";
};

1;
__END__


=head1 NAME

Mail::Toaster::Mysql - so much more than just installing mysql

head1 SYNOPSIS

Functions for installing, starting, stopping, querying, and otherwise interacting with MySQL.


=head1 DESCRIPTION

I find myself using MySQL for a lot of things. Geographically distributed dns systems (MySQL replication), mail servers, and all the other fun stuff you'd use a RDBMS for. As such, I've got a growing pile of scripts that have lots of duplicated code in them. As such, the need for this Perl module grew.

       Currently used in:
  mysql_replicate_manager v1.5+
  uron.net user_*.pl
  polls.pl
  nt_export_djb_update.pl
  toaster_setup.pl 


=head1 SUBROUTINES

=over

=item new

	use Mail::Toaster::Mysql;
	my $mysql = Mail::Toaster::Mysql->new();


=item autocommit


=item backup

Back up your mysql databases

   $mysql->backup( $dot );

The default location for backups is /var/backups/mysql. If you want them stored elsewhere, set backupdir = /path/to/backups in your .my.cnf (as shown in the FAQ) or pass it via -d on the command line.

You will need to have cronolog, gzip, and mysqldump installed in a "normal" location. Your backups will be stored in a directory based on the date, such as /var/backups/mysql/2003/09/11/mysql_full_dump.gz. Make sure that path is configured to be backed up by your backup software.

 arguments required:
    dot - a hashref of values from a .my.cnf file


=item connect

    my ($dbh, $dsn, $drh) = $mysql->connect($dot, $warn, $debug);

$dot is a hashref of key/value pairs in the same format you'd find in ~/.my.cnf. Not coincidentally, that's where it expects you'll be getting them from.

$warn allows you to determine whether to die or warn on failure or error. To warn, set $warn to a non-zero value. 

$debug will print out helpful debugging messages should you be having problems.


=item db_vars

This sub is called internally by $mysql->connect and is used principally to set some reasonable defaults should you not pass along enough connection parameters in $dot. 


=item flush_logs

	$mysql->flush_logs($dbh, $debug)

runs the mysql "FLUSH LOGS" query on the server. This commits any pending (memory cached writes) to disk.


=item get_hashes

Gets results from a mysql query as an array of hashes

   my @r = $mysql->get_hashes($dbh, $sql);

$dbh is a database handle

$sql is query


=item install

Installs MySQL


=item	is_newer

	my $ver   = $mysql->version($dbh);
	my $newer = $mysql->is_newer("4.1.0", $ver);

if ($newer) { print "you are brave!" };

As you can see, is_newer can be very useful, especially when you need to execute queries with syntax differences between versions of Mysql.


=item parse_dot_file

 $mysql->parse_dot_file ($file, $start, $debug)

Example: 

 my $dot = $mysql->parse_dot_file(".my.cnf", "[mysql_replicate_manager]", 0);

 $file is the file to be parsed.

$start is the [identifier] where we begin looking for settings.  This expects the format used in .my.cnf MySQL configuration files.

A hashref is returned wih key value pairs


=item phpmyadmin_install

Install PhpMyAdmin from FreeBSD ports.

	$mysql->phpmyadmin_install($conf);

$conf is a hash of configuration values. See toaster-watcher.conf for configuring the optional values to pass along.


=item query

    my $sth = $mysql->query ($dbh, $query, $warn)

$dbh is the database handle you've already acquired via $mysql->connect.

$query is the SQL statement to execute.

If $warn is set, we don't die if the query fails. This way you can decide when you call the sub whether you want it to die or return a failed $sth (and likely an error message).

 execute performs whats necessary to execute a statement
 Always returns true regardless of # of rows affected.
 For non-Select, returns # of rows affected: No rows = 0E0
 For Select, simply starts query. Follow with fetch_*


=item query_confirm

	$mysql->query_confirm($dbh, $query, $debug);

Use this if you want to interactively get user confirmation before executing a query.


=item sanity

A place to do validation tests on values to make sure they are reasonable

Currently we only check to assure the password is less than 32 characters and the username is less than 16. More tests will come.


=item shutdown_mysqld

Shuts down mysql using a $drh handle.

   my $rc = $mysql->shutdown_mysqld($dbvs, $drh);

$dbvs is a hashref containing: host, user, pass

returns error_code 200 on success, 500 on error. See error_desc for details.


=item	tables_lock

	my $sth = $mysql->tables_lock($dbh, $debug);
	# do some mysql stuff
	$mysql->tables_unlock($dbh, $sth);

Takes a statement handle and does a global lock on all tables.  Quite useful when you want do do things like make a tarball of the database directory, back up the server, etc.


=item tables_unlock

	$mysql->tables_unlock($dbh, $sth, $debug);

Takes a statement handle and does a global unlock on all tables.  Quite useful after you've used $mysql->tables_lock, done your deeds and wish to release your lock.


=item status


=item version

	my $ver = $mysql->version($dbh);

Returns a string representing the version of MySQL running.


=back

=head1 DEPENDENCIES

   DBI.pm     - /usr/ports/databases/p5-DBI
   DBD::mysql - /usr/ports/databases/p5-DBD-mysql

In order to use this module, you must have DBI.pm and DBD::Mysql installed. If they are not installed and you attempt to use this module, you should get some helpful error messages telling you how to install them.

=head1 AUTHOR

Matt Simerson <matt@tnpi.net>

=head1 BUGS

None known. Report any to author.

=head1 TODO

=head1 SEE ALSO

The following are all man/perldoc pages: 

 Mail::Toaster 
 Mail::Toaster::Conf
 toaster.conf
 toaster-watcher.conf

 http://www.mail-toaster.com/


=head1 COPYRIGHT


Copyright (c) 2003-2006, The Network People, Inc. All Rights Reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut
