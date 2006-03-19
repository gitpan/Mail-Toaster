#!/usr/bin/perl
use strict;

#
# $Id: Setup.pm,v 4.67 2006/03/19 18:43:13 matt Exp $
#

package Mail::Toaster::Setup;

use Carp;
use Config;
use File::Copy;
use vars qw($VERSION $toaster $freebsd $darwin);

$VERSION  = '4.48';

=head1 NAME

Mail::Toaster::Setup

=head1 DESCRIPTION

The meat and potatoes of toaster_setup.pl. This is where the majority of the work gets done. Big chunks of the code got moved here, mainly because toaster_setup.pl was getting rather unwieldly. The biggest benefit requiring me to clean up the code considerably. It's now in nice tidy little subroutines that are pretty easy to read and understand.

=cut 

use lib "lib";
use lib "../..";

use Mail::Toaster;              my $toaster = Mail::Toaster->new;
use Mail::Toaster::Utility 4.0; my $utility = Mail::Toaster::Utility->new;
use Mail::Toaster::Perl    4.0; my $perl    = Mail::Toaster::Perl->new;
use Mail::Toaster::Qmail   4.0; my $qmail = Mail::Toaster::Qmail->new();
use Mail::Toaster::Logs;

my $os = $^O;

if    ( $os eq "freebsd" ) { use Mail::Toaster::FreeBSD; $freebsd = Mail::Toaster::FreeBSD->new; } 
elsif ( $os eq "darwin"  ) { use Mail::Toaster::Darwin;  $darwin  = Mail::Toaster::Darwin->new; }
else  { }; # print "$os is not formally supported, but may work\n" };


1;

=head1 METHODS

=head2 new

To use any methods in Mail::Toaster::Setup, you must create a setup object: 

  use Mail::Toaster::Setup;
  my $setup = Mail::Toaster::Setup->new;

From there you can run any of the following methods via $setup->method as documented below.

Many of the methods require $conf, which is a hashref containing the contents of toaster-watcher.conf. 

=cut

sub new 
{
	my ($class, $name) = @_;
	my $self = { name => $name };
	bless ($self, $class);
	return $self;
}


=head2 apache

Calls $apache->install[1|2] which then builds and install Apache for you based on how it was called. See Mail::Toaster::Apache for more details.

  $setup->apache($conf, $version);

=cut

sub apache($;$)
{
	my ($self, $conf, $ver) = @_;

	my $src = $conf->{'toaster_src_dir'} || "/usr/local/src";
	$ver ||= $conf->{'install_apache'};

	use Mail::Toaster::Apache; my $apache = new Mail::Toaster::Apache;

	unless ($ver) {
		print "apache: skipping because not enabled!\n";
		return 0;
	};

	if ( lc($ver) eq "apache" or lc($ver) eq "apache1" or $ver == 1) 
	{ 
		$apache->install_apache1($src, $conf); 
	} 
	elsif ( $ver eq "ssl" )
	{
		$apache->install_ssl_certs("rsa");
	}
	else { $apache->install_apache2($conf); };

	if ( $os eq "freebsd") 
	{
		$freebsd->rc_dot_conf_check("apache2_enable", "apache2_enable=\"YES\"");
		$freebsd->rc_dot_conf_check("apache2ssl_enable", "apache2ssl_enable=\"YES\"");

		$self->apache_conf_fixup($conf);

		unless ( $utility->is_process_running("httpd") )
		{
			my $etcdir = $conf->{'system_config_dir'} || "/usr/local/etc";
			if    ( -x "$etcdir/rc.d/apache.sh"  ) { $utility->syscmd("$etcdir/rc.d/apache.sh start" ) }
			elsif ( -x "$etcdir/rc.d/apache2.sh" ) { $utility->syscmd("$etcdir/rc.d/apache2.sh start") }
			elsif ( -x "$etcdir/rc.d/apache22.sh" ) { $utility->syscmd("$etcdir/rc.d/apache22.sh start") };
		};
	};

	unless ( -e "/var/run/httpd.pid")
	{
		my $apachectl = $utility->find_the_bin("apachectl");
		if ( -x $apachectl ) 
		{
			if    ( $os eq "freebsd" ) { $utility->syscmd("$apachectl startssl");   # if this one doesn't work
			                             $utility->syscmd("$apachectl start"   ) }  # this one will
			elsif ( $os eq "darwin" )  { $utility->syscmd("$apachectl start")    } 
			else                       { $utility->syscmd("$apachectl start")    };
		};
	};
};


sub apache_conf_fixup($)
{
	my ($self, $conf) = @_;

	use Mail::Toaster::Apache; my $apache = new Mail::Toaster::Apache;
	my $apa_conf  = $apache->conf_get_dir($conf);
	my $httpdconf = "$apa_conf/httpd.conf";

	unless ( -e $httpdconf ) {
		print "Could not find your httpd.conf file!  FAILED!\n";
		return 0;
	}

	unless (`hostname` =~ /^jail/ ) {   # we're running in a jail
		return 0;
	}

	my @lines = $utility->file_read($httpdconf);
	foreach my $line (@lines)
	{
		if ($line =~ /^Listen 80/ ){    # this is only tested on FreeBSD
			my @ips = `ifconfig | grep inet | cut -d " " -f 2`;
			$line = "Listen $ips[0]:80";
		}
	}

	$utility->file_write("/var/tmp/httpd.conf", @lines);
	my $r = $utility->install_if_changed("/var/tmp/httpd.conf", $httpdconf, {clean=>1, notify=>1});

	return 0 unless $r;
	if ($r==1) { $r = "ok" } else { $r = "ok (current)"};
}


=head2 autorespond

Install autorespond. Fetches sources from Inter7 web site and installs it.

  $setup->autorespond($conf);

=cut

sub autorespond
{
	my ($self, $conf) = @_;

	if ( -x $utility->find_the_bin("autorespond") )
	{
		$self->_formatted("autorespond: installing", "ok (exists)");
		return 2;
	}

	my $vals = { 
		package => "autorespond-2.0.5",
		site    => 'http://www.inter7.com',
		url     => '/devel',
		targets => ['make', 'make install'],
		patches => '',
		bintest => 'autorespond',
		debug   => 1,
		source_sub_dir => 'mail',
	};

	$utility->install_from_source($conf, $vals);

	if ( -x $utility->find_the_bin("autorespond") )
	{
		$self->_formatted("autorespond: installing", "ok (exists)");
		return 1;
	}

	return 0;
}



=head2 clamav

Install ClamAV, configure the startup and config files, download the latest virus definitions, and start up the daemons.

  $setup->clamav($conf);

=cut

sub clamav
{
	my ($self, $conf) = @_;

	my $prefix  = $conf->{'toaster_prefix'}    || "/usr/local";
	my $confdir = $conf->{'system_config_dir'} || "/usr/local/etc";
	my $installed;

	my $ver = $conf->{'install_clamav'};

	unless ( $ver ) {
		print "clamav install disabled, skipping.\n";
		return 0;
	};

	if ( $os eq "freebsd" && $ver eq "port" ) 
	{
		$installed ++ if ( $freebsd->port_install ("clamav", "security", undef, undef, "BATCH=yes WITHOUT_LDAP=1", 1 ) );
	} 
	elsif ( $os eq "darwin" ) 
	{
		unless ( getpwuid("clamav") ) {
			$perl->module_load( {module=>"Mail::Toaster::Passwd"} );
			my $passwd = Mail::Toaster::Passwd->new();
			$passwd->creategroup("clamav", "90");
			$passwd->user_add( {user=>"clamav", uid=>"90", debug=>1 } );
		};
		$installed ++ if ( $darwin->port_install ("clamav") );

		chown "90", "90", "$prefix/share/clamav" if ( -e "$prefix/share/clamav");
		chown "90", "90", "$prefix/share/clamav/daily.cvd" if ( -e "$prefix/share/clamav/daily.cvd");
		chown "90", "90", "$prefix/share/clamav/main.cvd" if ( -e "$prefix/share/clamav/main.cvd");
	};

	unless ( getpwnam("clamav") ) 
	{
		require Mail::Toaster::Passwd; 
		my $passwd = Mail::Toaster::Passwd->new;

		$passwd->creategroup("clamav", "90");
		$passwd->user_add( { user=>"clamav", uid=>"90" } );

		unless ( getpwnam("clamav") ) { 
			print "User clamav installation FAILED, I cannot continue!\n";
			return 0; 
		};
	};

	if ( $ver eq "1" ) { $ver = "0.84"; };  # latest as of 5/2/05

	unless ($installed) 
	{
		$utility->install_from_source($conf, 
			{
				package=> 'clamav-'.$ver, 
				site   => 'http://'.$conf->{'toaster_sf_mirror'}, 
				url    => '/clamav', 
				targets=> ['./configure', 'make', 'make install'],
				bintest=> 'clamdscan',
				source_sub_dir=>'mail',
			} 
		);
	
		if ( -x $utility->find_the_bin("clamdscan") ) 
		{ 
			print "clamav source install success.\n" 
		} else { 
			print "clamav source install failed.\n";  
			exit 0; 
		};
	};

	#clamav_run($confdir);

	my $uid = getpwnam("clamav");
	my $gid = getgrnam("clamav");

	my $logfile = "/var/log/freshclam.log";
	unless ( -e $logfile )
	{
		$utility->syscmd("touch $logfile");
		chmod 00644, $logfile;
		chown $uid, $gid, $logfile;
	};

	if ( -e "$prefix/share/clamav" ) {
		chown $uid, $gid, "$prefix/share/clamav" if ( -e "$prefix/share/clamav");
		chown $uid, $gid, "$prefix/share/clamav/daily.cvd" if ( -e "$prefix/share/clamav/daily.cvd");
		chown $uid, $gid, "$prefix/share/clamav/main.cvd" if ( -e "$prefix/share/clamav/main.cvd");
	};

	my $freshclam = $utility->find_the_bin("freshclam");

	if ( -x $freshclam ) {
		$utility->syscmd("$freshclam --verbose");
	} 
	else { print "couldn't find freshclam!\n"; };

	chown($uid, $gid, "$prefix/share/clamav") or carp "FAILURE: $!";
	if ( -e "$prefix/share/clamav/daily.cvd") {
		chown($uid, $gid, "$prefix/share/clamav/daily.cvd");
	};
	if ( -e "$prefix/share/clamav/main.cvd") {
		chown($uid, $gid, "$prefix/share/clamav/main.cvd");
	};
	if ( -e "$prefix/share/clamav/viruses.db") {
		chown($uid, $gid, "$prefix/share/clamav/viruses.db");
	};
	if ( -e "$prefix/share/clamav/viruses.db2") {
		chown($uid, $gid, "$prefix/share/clamav/viruses.db2");
	};

	if ( $os eq "freebsd" ) 
	{
		$freebsd->rc_dot_conf_check("clamav_clamd_enable", "clamav_clamd_enable=\"YES\"");
		$freebsd->rc_dot_conf_check("clamav_freshclam_enable", "clamav_freshclam_enable=\"YES\"");

		print "(Re)starting ClamAV's clamd...";
		$utility->syscmd("/usr/local/etc/rc.d/clamav-freshclam.sh restart"); 
		print "done.\n";

		print "(Re)starting ClamAV's freshclam...";
		$utility->syscmd("/usr/local/etc/rc.d/clamav-clamd.sh restart"); 
		print "done.\n";

		# These are no longer required as the FreeBSD ports now installs
		# startup files of it's own.

		if ( -e "/usr/local/etc/rc.d/clamav.sh") { 
			unlink("/usr/local/etc/rc.d/clamav.sh");
		};

		if ( -e "/usr/local/etc/rc.d/freshclam.sh") { 
			unlink("/usr/local/etc/rc.d/freshclam.sh");
		};
	};
};

sub clamav_run
{
	my ($confdir) = @_;

	my $run_f   = "$confdir/rc.d/clamav.sh";

	unless ( -s $run_f ) 
	{
		print "Creating $confdir/rc.d/clamav.sh startup file.\n";
		open(RUN, ">$run_f") or croak "clamav: couldn't open $run_f for write: $!";

		print RUN <<EORUN
#!/bin/sh

case "\$1" in
    start)
        /usr/local/bin/freshclam -d -c 2 -l /var/log/freshclam.log
        echo -n ' freshclam'
        ;;

    stop)
        /usr/bin/killall freshclam > /dev/null 2>&1
        echo -n ' freshclam'
        ;;

    *)
        echo ""
        echo "Usage: `basename \$0` { start | stop }"
        echo ""
        exit 64
        ;;
esac
EORUN
;
		chmod 00755, "$confdir/rc.d/freshclam.sh";
		chmod 00755, "$confdir/rc.d/clamav.sh";
	};
};



=head2 config

=cut


sub config
{
	my ($self, $conf) = @_;

	my $confdir = $conf->{'system_config_dir'};

	unless ($confdir) {
		if ( $os eq "darwin" ) { $confdir = "/opt/local/etc"; }
		else                   { $confdir = "/usr/local/etc"; };
	} else {
		if ( $os eq "darwin" && ! -e "/usr/local/etc/toaster-watcher.conf" ) { $confdir = "/opt/local/etc"; };
	};

	my $file = "$confdir/toaster-watcher.conf";

	unless ( -e $file ) {
		$self->_formatted("config: $file is missing!", "FAILED");
		return 0;
	};

	if ($os eq "darwin") {
		# have we patched it yet & is the patch available?
		my $patch = "toaster-watcher.conf.darwin.patch";

		if ( $conf->{'freebsd_os_release'} ne "darwin" ) {   # patch is not applied
			if ( "darwin" && -e "contrib/$patch") {
				$self->_formatted("checking for darwin patch", "found");
				if ($utility->yes_or_no("I notice that you are running this on Darwin (Mac OS X) but have not applied the darwin patch yet. The darwin patch is suggested. Shall I apply it now?") ) {
					copy("contrib/$patch", $confdir);
					chdir($confdir);
					$utility->syscmd("patch < $patch");
				};
			} else {
				print "I notice that you are running this on Darwin (Mac OS X) but have not applied the darwin patch yet. The darwin patch is suggested. Please find it in the contrib directory of the Mail::Toaster distribution and apply it to your toaster-watcher.conf file. If you change to the MT directory and re-run this script, it will apply for you automatically.";
			}
		} else {
			$self->_formatted("checking for darwin patch", "ok (applied)");
		};
	};

	if (`hostname` =~ /^jail/ && $conf->{'toaster_hostname'} !~ /^jail/ ) {
		$self->_formatted("checking for testing patch", "ok (applied)");
		my $patch = "toaster-watcher.conf.testing.patch";
		if ($utility->yes_or_no("I notice that you are running this on FreeBSD with a jail hostname but have not applied the testing patch yet. Shall I apply it now?") ) {
			copy("contrib/$patch", $confdir);
			chdir($confdir);
			$utility->syscmd("patch < $patch");
		};
	};

	if ( ! $conf->{'toaster_hostname'} || $conf->{'toaster_hostname'} eq "mail.example.com" )  # set hostname
	{
		my $hostname = `hostname`; chomp $hostname;
		$conf->{'toaster_hostname'} = 
			$utility->answer("What should the hostname of this mail server be?", $hostname);
		$self->_formatted("toaster hostname set to ". $conf->{'toaster_hostname'}, "ok");
	} else {
		$self->_formatted("toaster hostname set to ". $conf->{'toaster_hostname'}, "ok");
	};

	# set postmaster email
	if ( ! $conf->{'toaster_admin_email'} || $conf->{'toaster_admin_email'} eq "postmaster\@example.com" )  
	{
		$conf->{'toaster_admin_email'} = 
			$utility->answer("What email address should administrative emails and notices for this server be sent to? (probably yours!)");
		$self->_formatted("toaster admin emails sent to ". $conf->{'toaster_admin_email'}, "ok");
	} else {
		$self->_formatted("toaster admin emails sent to ". $conf->{'toaster_admin_email'}, "ok");
	};


	# set test email account
	if ( $conf->{'toaster_test_email'} eq "test\@example.com" )  
	{
		$conf->{'toaster_test_email'} = 
			$utility->answer("We need an email account for running tests to determine if everything works. What email address should be used for this purpose?", "test\@$conf->{'toaster_hostname'}");
		$self->_formatted("toaster test account set to ". $conf->{'toaster_test_email'}, "ok");
	} else {
		$self->_formatted("toaster test account set to ". $conf->{'toaster_test_email'}, "ok");
	};

	# set test email password
	if ( !$conf->{'toaster_test_email_pass'} || $conf->{'toaster_test_email_pass'} eq "cHanGeMe" )  
	{
		$conf->{'toaster_test_email_pass'} = 
			$utility->answer("The test email account needs a password. What would you like to use?");
		$self->_formatted("toaster test password set to ". $conf->{'toaster_test_email_pass'}, "ok");
	} else {
		$self->_formatted("toaster test password set to ". $conf->{'toaster_test_email_pass'}, "ok");
	};

	if ( $conf->{'vpopmail_mysql'} ) {
		# set vpopmail MySQL password
		if ( ! $conf->{'vpopmail_mysql_repl_pass'} || $conf->{'vpopmail_mysql_repl_pass'} eq "supersecretword" )  
		{
			$conf->{'vpopmail_mysql_repl_pass'} = 
				$utility->answer("Vpopmail needs access to a MySQL database. That connection should be password protected with a secure password. You MUST enter a non-default password here! Please choose a secure password now");
			$self->_formatted("vpopmail MySQL password set to ". $conf->{'vpopmail_mysql_repl_pass'}, "ok");
		} else {
			$self->_formatted("vpopmail MySQL password set to ". $conf->{'vpopmail_mysql_repl_pass'}, "ok");
		};
	};

	
	my @lines = $utility->file_read($file);
	foreach my $line (@lines)
	{
		if ($line =~ /^toaster_hostname / ){
			$line = "toaster_hostname               = " .$conf->{'toaster_hostname'};
		}

		if ($line =~ /^toaster_admin_email / ){
			$line = "toaster_admin_email            = " .$conf->{'toaster_admin_email'};
		}

		if ($line =~ /^toaster_test_email / ){
			$line = "toaster_test_email             = " .$conf->{'toaster_test_email'};
		}

		if ($line =~ /^toaster_test_email_pass / ){
			$line = "toaster_test_email_pass        = " .$conf->{'toaster_test_email_pass'};
		}

		if ( $conf->{'vpopmail_mysql'} ) {
			if ($line =~ /^vpopmail_mysql_repl_pass / ){
				$line = "vpopmail_mysql_repl_pass       = " .$conf->{'vpopmail_mysql_repl_pass'};
			}
		};
		
	}

	$utility->file_write("/tmp/toaster-watcher.conf", @lines);
	my $r = $utility->install_if_changed("/tmp/toaster-watcher.conf", $file, {clean=>1, notify=>1});

	return 0 unless $r;
	if ($r==1) { $r = "ok" } else { $r = "ok (current)"};
	$self->_formatted("config: update $file", $r);
}


=head2 courier

  $setup->courier($conf);

Installs courier imap based on your settings in toaster-watcher.conf.

=cut

sub courier($)
{
	my ($self, $conf)  = @_;

	my $ver = $conf->{'install_courier_imap'}; 

	unless ( $ver ) {
		print "Skipping install because courier-imap isn't enabled.\n";
		return 0;
	};

	my $debug   = $conf->{'debug'};


	$self->courier_authlib($conf);

	if ( $os eq "freebsd" ) 
	{
		unless (  $freebsd->is_port_installed("courier-imap") )
		{
			my @defs = "WITH_VPOPMAIL=1";
			push @defs, "WITHOUT_AUTHDAEMON=1";
			push @defs, "WITH_CRAM=1";
			push @defs, "AUTHMOD=authvchkpw";
			#push @defs, "BATCH=yes";  # if only this worked <sigh>
			$freebsd->port_install("courier-imap", "mail", undef, undef, join(",", @defs), 1 );
		};
		$self->courier_config($conf);
	};

	if ( $os eq "darwin" ) 
	{
		$darwin->port_install("courier-imap");
		return 1;
	};

	if ( -e "/usr/local/etc/pkgtools.conf" ) 
	{
		unless ( `grep courier /usr/local/etc/pkgtools.conf` ) 
		{
			print "\n\nYou should add this line to MAKE_ARGS in /usr/local/etc/pkgtools.conf:\n\n
	'mail/courier-imap' => 'WITHOUT_AUTHDAEMON=1 WITH_CRAM=1 WITH_VPOPMAIL=1',\n\n";
			sleep 3;
		};
	};

	if ( $os eq "freebsd" && $ver eq "port" && $freebsd->is_port_installed("courier-imap") ) 
	{
		$self->courier_config($conf);
		return 1 
	};

	# if a specific version has been requested, install it from sources
	# but first, a default for lazy folks who didn't edit toaster-watcher.conf
	$ver        = "3.0.8" if ($ver eq "port");

	my $site    = "http://" . $conf->{'toaster_sf_mirror'};
	my $confdir = $conf->{'system_config_dir'}  || "/usr/local/etc";
	my $prefix  = $conf->{'toaster_prefix'}     || "/usr/local";

	$ENV{"HAVE_OPEN_SMTP_RELAY"} = 1;  # circumvent bug in courier


	my $conf_args = "--prefix=$prefix --exec-prefix=$prefix --without-authldap --without-authshadow --with-authvchkpw --sysconfdir=/usr/local/etc/courier-imap --datadir=$prefix/share/courier-imap --libexecdir=$prefix/libexec/courier-imap --enable-workarounds-for-imap-client-bugs --disable-root-check --without-authdaemon";

	print "./configure $conf_args\n";
	my $make = $utility->find_the_bin("gmake"); $make ||= $utility->find_the_bin("make");
	my @targets = ("./configure " . $conf_args, $make, "$make install");
	my @patches = 0; # "$package-patch.txt";

	$utility->install_from_source($conf, 
		{
			package=> "courier-imap-$ver", 	
			site   => $site, 
			url    => "/courier",
			targets=> \@targets, 
			patches=> \@patches, 
			bintest=> "imapd",
			source_sub_dir => 'mail',
			debug  => $debug
		} 
	);

	$self->courier_config($conf);
};

sub courier_authlib
{
	my ($self, $conf)  = @_;

	my $prefix = $conf->{'toaster_prefix'} || "/usr/local";

	if ( $os eq "freebsd" ) 
	{
		unless ( $freebsd->is_port_installed("libltdl") )  {
			$freebsd->port_install("libltdl15", "devel", undef, "libltdl", undef, 1 );
		};

		unless (  $freebsd->is_port_installed("sysconftool") ) {
			$freebsd->port_install("sysconftool", "devel", undef, undef, undef, 1 );
		};

		unless ( $freebsd->is_port_installed("courier-authlib") ) 
		{
			if ( -d "/var/db/ports/courier-authlib" ) {   #it's not installed, clean up previous
				$utility->syscmd("rm -rf /var/db/ports/courier-authlib");	
			};
			print "\n\nYou may be prompted to select authentication types. If so, select only vpopmail (AUTH_VCHKPW)\n\n";
			sleep 5;
			print "\n";
			if    ( -d "/usr/ports/mail/courier-authlib-vchkpw" ) {
				$freebsd->port_install("courier-authlib-vchkpw", "mail", undef, undef, undef, 1 );
				$freebsd->port_install("courier-authlib-base", "security", undef, undef, undef, 1 );
				#$freebsd->port_install("courier-authlib-base", "security", undef, "AUTHMOD=authvchkpw", undef, 1 );
			}
			elsif ( -d "/usr/ports/security/courier-authlib" ) {  # they moved the port!
				$freebsd->port_install("courier-authlib", "security", undef, undef, undef, 1 );
				#$freebsd->port_install("courier-authlib", "security", undef, undef, "AUTHMOD=authvchkpw", 1 );
			} 
			else {
				$freebsd->port_install("courier-authlib", "mail", undef, undef, "WITH_VPOPMAIL=1,WITHOUT_PAM=1,USE_RC_SUBR=no", 1 );
			};
		}

		unless ( -e "$prefix/etc/authlib/authdaemonrc" ) 
		{
			if ( "$prefix/etc/authlib/authdaemonrc.dist") {
				print "installing default authdaemonrc.\n";
				$utility->syscmd("cp $prefix/etc/authlib/authdaemonrc.dist $prefix/etc/authlib/authdaemonrc");
			}
		};

		$freebsd->rc_dot_conf_check("courier_authdaemond_enable", "courier_authdaemond_enable=\"YES\"");
		my $start = "$prefix/etc/rc.d/courier-authdaemond";
		if ( -x  $start    ) { $utility->syscmd("$start start")    };   # the new way
		if ( -x "$start.sh") { $utility->syscmd("$start.sh start") };   # the way it used to be
	} 
	else 
	{
		print "courier-authlib build support is not available for $os yet.\n";
		return 0;
	}
}

=head2 courier_config

  $setup->courier_config($conf);

Does all the post-install configuration of Courier IMAP.

=cut

sub courier_config($)
{
	my ($self, $conf) = @_;

	my $prefix  = $conf->{'toaster_prefix'}    || "/usr/local";
	my $confdir = $conf->{'system_config_dir'} || "/usr/local/etc";
	chdir("$confdir/courier-imap");

	copy("pop3d.cnf.dist", "pop3d.cnf" ) if ( ! -e "pop3d.cnf" );
	copy("pop3d.dist",     "pop3d"     ) if ( ! -e "pop3d"     );
	copy("pop3d-ssl.dist", "pop3d-ssl" ) if ( ! -e "pop3d-ssl" );
	copy("imapd.cnf.dist", "imapd.cnf" ) if ( ! -e "imapd.cnf" );
	copy("imapd.dist",     "imapd"     ) if ( ! -e "imapd"     );
	copy("imapd-ssl.dist", "imapd-ssl" ) if ( ! -e "imapd-ssl" );
	copy("quotawarnmsg.example", "quotawarnmsg") if (!-e "quotawarnmsg");

#   The courier port *finally* has working startup files installed
#         this stuff is no longer necessary
#	unless ( -e "$confdir/rc.d/imapd.sh" ) 
#	{
#		my $libe = "/usr/local/libexec/courier-imap";
#		copy("$libe/imapd.rc",     "$confdir/rc.d/imapd.sh");
#		chmod 00755, "$confdir/rc.d/imapd.sh";
#
#		if ( $conf->{'pop3_daemon'} eq "courier" )
#		{
#			copy("$libe/pop3d.rc",     "$confdir/rc.d/pop3d.sh");
#			chmod 00755, "$confdir/rc.d/pop3d.sh";
#		};
#
#		copy("$libe/imapd-ssl.rc", "$confdir/rc.d/imapd-ssl.sh");
#		chmod 00755, "$confdir/rc.d/imapd-ssl.sh";
#		copy("$libe/pop3d-ssl.rc", "$confdir/rc.d/pop3d-ssl.sh");
#		chmod 00755, "$confdir/rc.d/pop3d-ssl.sh";
#	};

	unless ( -e "$prefix/share/courier-imap/pop3d.pem" ) 
	{
		chdir "$prefix/share/courier-imap";
		$utility->syscmd("./mkpop3dcert");
	};

	unless ( -e "$prefix/share/courier-imap/imapd.pem" ) 
	{
		chdir "$prefix/share/courier-imap";
		$utility->syscmd("./mkimapdcert");
	};

	if ( $os eq "freebsd" ) {
		unless ( -e "$prefix/sbin/imap" ) 
		{
			symlink("$confdir/rc.d/courier-imap-imapd.sh",     "$prefix/sbin/imap");
			symlink("$confdir/rc.d/courier-imap-pop3d.sh",     "$prefix/sbin/pop3");
			symlink("$confdir/rc.d/courier-imap-imapd-ssl.sh", "$prefix/sbin/imapssl");
			symlink("$confdir/rc.d/courier-imap-pop3d-ssl.sh", "$prefix/sbin/pop3ssl");
		};

		$freebsd->rc_dot_conf_check("courier_imap_imapd_enable",    "courier_imap_imapd_enable=\"YES\"");
		$freebsd->rc_dot_conf_check("courier_imap_imapdssl_enable", "courier_imap_imapdssl_enable=\"YES\"");
		$freebsd->rc_dot_conf_check("courier_imap_imapd_ssl_enable", "courier_imap_imapd_ssl_enable=\"YES\"");
		if ( $conf->{'pop3_daemon'} eq "courier" ) {
			$freebsd->rc_dot_conf_check("courier_imap_pop3d_enable",    "courier_imap_pop3d_enable=\"YES\"");
		};
		$freebsd->rc_dot_conf_check("courier_imap_pop3dssl_enable", "courier_imap_pop3dssl_enable=\"YES\"");
		$freebsd->rc_dot_conf_check("courier_imap_pop3d_ssl_enable", "courier_imap_pop3d_ssl_enable=\"YES\"");

	} 
	else 
	{
		my $courier_conf = "$prefix/libexec/courier-imap";
		if ( -e "$courier_conf/imapd.rc" ) {
			print "creating symlinks in /usr/local/sbin for courier daemons\n";
			symlink("$courier_conf/imapd.rc",     "$prefix/sbin/imap");
			symlink("$courier_conf/pop3d.rc",     "$prefix/sbin/pop3");
			symlink("$courier_conf/imapd-ssl.rc", "$prefix/sbin/imapssl");
			symlink("$courier_conf/pop3d-ssl.rc", "$prefix/sbin/pop3ssl");
		} else {
			print "FAILURE: sorry, I can't find the courier rc files on $os.\n";
		};
	};

	unless ( -e "/var/run/imapd-ssl.pid" ) {
		$utility->syscmd("$prefix/sbin/imapssl start") if ( -x "$prefix/sbin/imapssl");
	};

	unless ( -e "/var/run/imapd.pid" ) {
		$utility->syscmd("$prefix/sbin/imap start") if ( -x "$prefix/sbin/imapssl");
	};

	unless ( -e "/var/run/pop3d-ssl.pid" ) {
		$utility->syscmd("$prefix/sbin/pop3ssl start") if ( -x "$prefix/sbin/pop3ssl");
	};

	if ( $conf->{'pop3_daemon'} eq "courier" )
	{
		unless ( -e "/var/run/pop3d.pid" ) {
			$utility->syscmd("$prefix/sbin/pop3 start") if ( -x "$prefix/sbin/pop3");
		};
	};
};


sub cronolog
{
	my ($self, $conf) = @_;

	if ( $os eq "freebsd") {
		if ( $freebsd->is_port_installed("cronolog") ) {
			$self->_formatted("maillogs: install cronolog", "ok (exists)");
			return 2;
		};

		$freebsd->port_install("cronolog", "sysutils", undef, undef, undef, 1 );

		if ( $freebsd->is_port_installed("cronolog") ) {
			$self->_formatted("maillogs: install cronolog", "ok");
			return 1;
		};

		print "NOTICE: port install of cronolog failed!\n";

	} else {
		if ( $utility->find_the_bin("cronolog") ) {
			$self->_formatted("maillogs: install cronolog", "ok (exists)");
			return 2;
		};
		print "attempting to install cronolog from sources!\n";
	};

	my $vals = { 
		package=> "cronolog-1.6.2",
		site   => 'http://www.cronolog.org',
		url    => '/download',
		targets=> ['./configure', 'make', 'make install'],
		patches=> '',
		bintest=> 'cronolog',
		debug  => 1,
	};

	$utility->install_from_source($conf, $vals);

	if ( $utility->find_the_bin("cronolog") ) {
		$self->_formatted("maillogs: install cronolog", "ok");
		return 1;
	};

	return 0;
}



=head2 daemontools

Fetches sources from DJB's web site and installs daemontools, per his instructions.

  $setup->daemontools($conf);

=cut

sub daemontools
{
	my ($self, $conf) = @_;

	if ( $os eq "freebsd" ) {
		return 1 if $freebsd->is_port_installed("daemontools");
		$freebsd->port_install("daemontools", "sysutils", undef, undef, undef, 1);
		return 1 if $freebsd->is_port_installed("daemontools");
		print "NOTICE: port install of daemontools failed!\n";
	} 
	elsif ( $os eq "darwin") 
	{
		$darwin->port_install("daemontools");
		
		print "\n\nWARNING: there is a bug in the OS 10.4 kernel that requires daemontools to be built with a special tweak. This must be done once. You will be prompted to install daemontools now. If you haven't already allowed this script to build daemontools from source, please do so now!\n\n";
		#sleep 3;
	};

	my $package = "daemontools-0.76";
	my $prefix  = $conf->{'toaster_prefix'} || "/usr/local";

	my $vals = { 
		package=> $package,
		site   => 'http://cr.yp.to',
		url    => '/daemontools',
#		targets=> [$confcmd, 'make', 'make install-strip'],
		targets=> ['package/install'],
		patches=> '',
		bintest=> 'svscan',
		debug  => 1,
	};

	if ($os eq "darwin") 
	{
		print "daemontools: applying fixups for Darwin.\n";
		$vals->{'targets'} = [ 
			"echo cc -Wl,-x > src/conf-ld", 
			"echo $prefix/bin > src/home",
			"echo x >> src/trypoll.c",
			"cd src; make", 
		];
	}
	elsif ($os eq "linux") 
	{
		print "daemontools: applying fixups for Linux.\n";
		$vals->{'patches'}    = ['daemontools-0.76.errno.patch'];
		$vals->{'patch_args'} = "-p0";
	} 
	elsif ($os eq "freebsd") 
	{
		$vals->{'targets'} = [ 
			'echo '.$conf->{'toaster_prefix'}.' > src/home',
			'cd src; make', 
		];
	};

	$utility->install_from_source($conf, $vals);

	if ( $os eq "darwin" or $os eq "freebsd" ) 
	{
		# manually install the daemontools binaries in $prefix/local/bin
		chdir "$conf->{'toaster_src_dir'}/admin/$package";
		foreach ( $utility->file_read("package/commands") ) {
			$utility->syscmd("install src/$_ $prefix/bin");
		}
	}
}

sub daemontools_test
{
	my ($self) = @_;

	print "checking daemontools binaries...\n";
	foreach ( qw(multilog softlimit setuidgid supervise svok svscan tai64nlocal) ) 
	{
		-x $utility->find_the_bin($_) ? $self->_formatted("\t$_", "ok") : $self->_formatted("\t$_", "FAILED");
	};
}

=head2 dependencies

  $setup->dependencies($conf, $debug);

Installs a bunch of programs that are needed by subsequent programs we'll be installing. You can install these yourself if you'd like, this doesn't do anything special beyond installing them:

ispell, gdbm, setquota, expect, maildrop, autorespond, qmail, qmailanalog, daemontools, openldap-client, Compress::Zlib, Crypt::PasswdMD5, HTML::Template, Net::DNS, Crypt::OpenSSL-RSA, DBI, DBD::mysql, TimeDate.

=cut

sub dependencies 
{
	my ($self, $conf, $debug) = @_;

	if ( $os eq "freebsd" )
	{
		my $package = $conf->{'package_install_method'} || "packages";

		unless ( $Config{d_dosuid} ) {
			if ( $conf->{'install_qmailscanner'} )
			{
				if ( $utility->yes_or_no("You have chosen to install qmail-scanner but the version of perl you have installed does not have setuid enabled. Since Qmail-Scanner requires it, you must either install perl suid, or use the qmail-scanner C wrapper. Would you like me to install a setuid perl (5.8) for you now? ", 300) ) {
					unless ( $freebsd->port_install("perl5.8", "lang", undef, undef, "ENABLE_SUIDPERL=1", 1) ) {
						print "Yikes, I couldn't install! You might need to deinstall the installed version of perl before the 'make install' can complete successfully. After deinstalling, cd to /usr/ports/lang/perl5.8 and do a 'make install'\n\n";
					};
				} else {
					print "\n\nYou have been warned. Qmail-Scanner will not work unless you use the C wrapper.\n\n";
					sleep 5;
				};
			};
		};

		unless ( -e "/etc/periodic.conf" ) {
			open (PERIODIC, ">/etc/periodic.conf");
			print PERIODIC <<EOPER
#--periodic.conf--
# 210.backup-aliases
daily_backup_aliases_enable="NO"                       # Backup mail aliases

# 440.status-mailq
daily_status_mailq_enable="YES"                         # Check mail status
daily_status_mailq_shorten="NO"                         # Shorten output
daily_status_include_submit_mailq="NO"                 # Also submit queue

# 460.status-mail-rejects
daily_status_mail_rejects_enable="NO"                  # Check mail rejects
daily_status_mail_rejects_logs=3                        # How many logs to check
#-- end --
EOPER
;
			close PERIODIC;
		}

		$freebsd->port_install("p5-TimeDate",   "devel",          undef, undef, undef, 1);
		$freebsd->port_install("p5-HTML-Template",   "www",       undef, undef, undef, 1);
		$freebsd->port_install("portaudit",     "security",       undef, undef, undef, 1) if $conf->{'install_portaudit'};

		if ( $package eq "packages" ) 
		{
			$freebsd->package_install("openssl")  if $conf->{'install_openssl_port'};
			$freebsd->package_install("ispell")   if $conf->{'install_ispell'};
			$freebsd->package_install("gdbm")     or $freebsd->port_install("gdbm",    "databases", undef, undef, undef, 1 );
			if ( $conf->{'install_quota_tools'} ) {
			$freebsd->package_install("setquota") or $freebsd->port_install("setquota", "sysutils", undef, undef, undef, 1 );
			};
			$freebsd->package_install("gmake")    or $freebsd->port_install("gmake",    "devel",    undef, undef, undef, 1 );
			$freebsd->package_install("cronolog") or $freebsd->port_install("cronolog", "sysutils", undef, undef, undef, 1 );
		};

		if ( $conf->{'install_openssl_port'} && ! $freebsd->is_port_installed("openssl") ) {
			$freebsd->port_install ("openssl", "security", undef, undef, undef, 1) 
		};

		$freebsd->port_install("gettext",  "devel", undef, undef, "BATCH=yes WITHOUT_GETTEXT_OPTIONS=1", 1 ) 
			unless $freebsd->is_port_installed("gettext");
		$freebsd->port_install("gmake",    "devel",    undef, undef, undef, 1 ) 
			unless $freebsd->is_port_installed("gmake");

		if ( $conf->{'install_ispell'} && ! $freebsd->is_port_installed("ispell") ) {
			$freebsd->port_install("ispell",  "textproc",  undef, undef, undef, 1 );
		};
		if ( $conf->{'install_quota_tools'} ) {
			$freebsd->port_install("setquota", "sysutils", undef, undef, undef, 1 ) unless $freebsd->is_port_installed("setquota");
			$freebsd->port_install("p5-Quota", "sysutils", undef, undef, undef, 0);
		};
		$freebsd->port_install("gdbm",    "databases", undef, undef, undef, 1 ) unless $freebsd->is_port_installed("gdbm");
		$freebsd->port_install("cronolog", "sysutils", undef, undef, undef, 1 ) unless $freebsd->is_port_installed("cronolog");
		$freebsd->port_install("qmail",        "mail", undef, undef, "BATCH=yes", 1) unless $freebsd->is_port_installed("qmail");
		$freebsd->port_install("autorespond",  "mail", undef, undef, undef, 1 ) unless $freebsd->is_port_installed("autorespond");
		$freebsd->port_install("qmailanalog",  "mail", undef, undef, undef, 0)  unless $freebsd->is_port_installed("qmailanalog");
		$freebsd->port_install("qmail-notify", "mail", undef, undef, undef, 0) if $conf->{'install_qmail_notify'};
		$freebsd->port_install("openldap-client", "net", "openldap22-client")  if $conf->{'install_openldap_client'};
		$freebsd->port_install("p5-Compress-Zlib", "archivers",   undef, undef, undef, 1);
		$freebsd->port_install("p5-Crypt-PasswdMD5", "security",  undef, undef, undef, 1);

		$self->daemontools($conf);

		unless ($conf->{'pop3d_ssl_daemon'} eq "courier") {
			$freebsd->port_install("stunnel", "security", undef, undef, undef, 1);
		}
	}
    elsif ( $os eq "darwin"  )
	{
		$self->autorespond($conf);

		unless ( -x "/var/qmail/bin/qmail-queue" ) {
			$conf->{'qmail_chk_usr_patch'} = 0;
			$perl->module_load( {module=>"Mail::Toaster::Qmail"} );
			$qmail->netqmail_virgin($conf);
		};

		my  @dports = qw( cronolog gdbm gmake gnupg ucspi-tcp daemontools DarwinPortsStartup );
		if ($conf->{'install_aspell'}) {
			push @dports, qw/aspell aspell-dict-en/;
		};
		push @dports, "ispell"   if $conf->{'install_ispell'};
		push @dports, "maildrop" if $conf->{'install_maildrop'};
		push @dports, "openldap" if $conf->{'install_openldap_client'};

		foreach (@dports) { $darwin->port_install($_) };

		@dports = qw( p5-net-dns p5-html-template p5-compress-zlib p5-timedate );
		foreach (@dports) { $darwin->port_install($_) };
	} 
	else 
	{
		print "no ports for $os, installing from sources.\n";

		if ($os eq "linux") 
		{
			$utility->syscmd("groupadd qnofiles");
			$utility->syscmd("groupadd qmail");
			$utility->syscmd("groupadd -g 89 vchkpw");
			$utility->syscmd("groupadd -g 89 vchkpw");
			$utility->syscmd("useradd -g qnofiles -d /var/qmail/alias alias");
			$utility->syscmd("useradd -g qnofiles -d /var/qmail qmaild");
			$utility->syscmd("useradd -g qnofiles -d /var/qmail qmaill");
			$utility->syscmd("useradd -g qnofiles -d /var/qmail qmailp");
			$utility->syscmd("useradd -g qmail    -d /var/qmail qmailq");
			$utility->syscmd("useradd -g qmail    -d /var/qmail qmailr");
			$utility->syscmd("useradd -g qmail    -d /var/qmail qmails");
			$utility->syscmd("groupadd clamav");
			$utility->syscmd("useradd -g clamav clamav");
		}

		my @progs = qw(setquota gmake expect gnupg cronolog autorespond );
		push @progs, "ispell" if $conf->{'install_ispell'};

		foreach ( @progs )
		{
			if ( $utility->find_the_bin($_) ) { print "$_..ok.\n"; } 
			else {
				print "$_ not installed. FAILED, please install.\n";
			}
		}

		$self->daemontools($conf);
		$self->ucspi_tcp  ($conf);
		$self->autorespond($conf);

		$perl->module_load( {module=>"Compress::Zlib"}   );
		$perl->module_load( {module=>"Crypt::PasswdMD5"} );
		$perl->module_load( {module=>"HTML::Template"}   );
		$perl->module_load( {module=>"Net::DNS"}         );
		$perl->module_load( {module=>"Date::Format"}     );
		$perl->module_load( {module=>"Date::Parse"}      );
		$perl->module_load( {module=>"Quota"}            ) if $conf->{'install_p5_quota'};

		unless ( -x "/var/qmail/bin/qmail-queue" ) {
			$conf->{'qmail_chk_usr_patch'} = 0;
			$perl->module_load( {module=>"Mail::Toaster::Qmail"} );
			$qmail->netqmail_virgin($conf);
		};
	}
};

=head2 djbdns

Fetches djbdns, compiles and installs it.

  $setup->djbdns($conf);

=cut

sub djbdns
{
	my ($self, $conf) = @_;

	$self->daemontools($conf);
	$self->ucspi_tcp  ($conf);

	if ( $os eq "freebsd" ) 
	{
		$freebsd->port_install("djbdns",      "dns", undef, undef, "", 1 );
	} 
	else 
	{
		my $vals = { package => "djbdns-1.05",
			site    => 'http://cr.yp.to',
			url     => '/djbdns',
			targets => ['make', 'make setup check'],
			patches => '',
			bintest => 'tinydns',
			debug   => 1,
		};
	
		if ($os eq "linux") 
		{
			$vals->{'targets'} = [ 
				'echo gcc -O2 -include /usr/include/errno.h > conf-cc', 
				'make', 
				'make setup check'
			];
		};

		$utility->install_from_source($conf, $vals);
	};
}

sub expat
{
	my ($self, $conf, $debug) = @_;

	if    ( $os eq "freebsd" ) 
	{
		$freebsd->port_install("expat", "textproc", undef, undef, "", 1 );
	} 
	elsif ( $os eq "darwin")  
	{
		$darwin->port_install("expat");
	}
	else 
	{ 
		print "Sorry, build support for expat on $os unfinished.\n";
	};
}

sub expect
{
	my ($self, $conf) = @_;

	if ( $os eq "freebsd" ) 
	{
		$freebsd->port_install("expect", "lang", undef, undef, "WITHOUT_X11=yes");
	};
}

=head2 ezmlm

Installs Ezmlm-idx. This also tweaks the port Makefile so that it'll build against MySQL 4.0 libraries as if you don't have MySQL 3 installed. It also copies the sample config files into place so that you have some default settings.

  $setup->ezmlm($conf);

=cut


sub ezmlm($;$)
{
	my ($self, $conf, $debug) = @_;

	my $confdir = $conf->{'system_config_dir'} || "/usr/local/etc";

	unless ( $conf->{'install_ezmlm'} ) {
		print "Skipping Ezmlm install...not selected..\n";
		return 0;
	}

	if ( -x "/usr/local/bin/ezmlm-sub" || -x "/usr/local/bin/ezmlm/ezmlm-sub" ) {
		print "Ezmlm is already installed, skipping.\n";
		
		if ($conf->{'install_ezmlm_cgi'} ) 
		{
			$perl->module_load( {module=>"Mail::Ezmlm"} );
			$perl->module_load( {module=>"Email::Valid"} );
		};
		return 0;
	};

	if ( $os eq "freebsd" )
	{
		my $file = "/usr/ports/mail/ezmlm-idx/Makefile";

		my $mysql = $conf->{'install_mysql'};
		if ( $mysql != 323 || $mysql != 3 ) {
			if ( `grep mysql323 $file` ) {
				my @lines = $utility->file_read($file);
				foreach ( @lines ) {
					if ( $_ =~ /^LIB_DEPENDS\+\=\s+mysqlclient.10/ ) {
						$_ = "LIB_DEPENDS+=  mysqlclient.12:\${PORTSDIR}/databases/mysql40-client";
					};
				};
				$utility->file_write($file, @lines);
			};
		};

		my $defs;
		$defs .= "WITH_MYSQL=yes" if ($conf->{'install_mysql'});

		if ( $freebsd->port_install("ezmlm-idx", "mail", undef,  undef, $defs, 1) )
		{
			chdir("$confdir/ezmlm");
			copy("ezmlmglrc.sample",  "ezmlmglrc" ) or croak "ezmlm: copy ezmlmglrc failed: $!";
			copy("ezmlmrc.sample",    "ezmlmrc"   ) or croak "ezmlm: copy ezmlmrc failed: $!";
			copy("ezmlmsubrc.sample", "ezmlmsubrc") or croak "ezmlm: copy ezmlmsubrc failed: $!";

			$freebsd->port_install("p5-Email-Valid", "mail");
			$freebsd->port_install("p5-Mail-Ezmlm", "mail");
		} 
		else { print "\n\nFAILURE: ezmlm-idx install failed!\n\n"; };
	} 
	else 
	{
		print "ezmlm: attemping to install ezmlm from sources.\n";

		my $ver = $conf->{'install_ezmlm'}; $ver ||= "0.42";

		my $ezmlm   = "ezmlm-0.53";
		my $idx     = "ezmlm-idx-$ver";
		my $site    = "http://www.ezmlm.org";
		my $src     = $conf->{'toaster_src_dir'}   || "/usr/local/src/mail";
		my $httpdir = $conf->{'toaster_http_base'} || "/usr/local/www";

		my $cgi = $conf->{'qmailadmin_cgi-bin_dir'};
		unless ($cgi && -e $cgi) 
		{
			if ( $conf->{'toaster_cgi-bin'} ) { $cgi = $conf->{'toaster_cgi-bin'}; } 
			else 
			{
				if ( -d "/usr/local/www/cgi-bin.mail") { $cgi = "/usr/local/www/cgi-bin.mail"; } 
				else                                   { $cgi = "/usr/local/www/cgi-bin"; };
				unless ( -d $cgi ) {
					$cgi = "/var/www/cgi-bin" if ( -d "/var/www/cgi-bin"); # linux
				};
			};
		};

		$utility->chdir_source_dir($src);

		if ( -d $ezmlm ) {
			unless ( $utility->source_warning($ezmlm, 1, $src) )
			{
				carp "\nezmlm: OK then, skipping install.\n";
				return 0;
			} else {
				print "ezmlm: removing any previous build sources.\n";
				$utility->syscmd("rm -rf $ezmlm");   # nuke any old versions
			};
		};

		unless ( -e "$ezmlm.tar.gz" ) { $utility->get_file("$site/archive/$ezmlm.tar.gz");    };
		unless ( -e "$idx.tar.gz"   ) { $utility->get_file("$site/archive/0.42/$idx.tar.gz"); };

		$utility->archive_expand("$ezmlm.tar.gz", 1) or croak "Couldn't expand $ezmlm.tar.gz: $!\n";
		$utility->archive_expand("$idx.tar.gz", 1) or croak "Couldn't expand $idx.tar.gz: $!\n";
		$utility->syscmd("mv $idx/* $ezmlm/");
		$utility->syscmd("rm -rf $idx");
		chdir($ezmlm);

		$utility->syscmd("patch < idx.patch");

		if ( $os eq "darwin" ) {
			if ( -d "/usr/local/mysql" ) {
				$utility->file_write("sub_mysql/conf-sqlcc", "-I/usr/local/mysql/include");
				$utility->file_write("sub_mysql/conf-sqlld", "-L/usr/local/mysql/lib -lmysqlclient -lm");
			} else {
				$utility->file_write("sub_mysql/conf-sqlcc", "-I/opt/local/include/mysql");
				$utility->file_write("sub_mysql/conf-sqlld", "-L/opt/local/lib/mysql -lmysqlclient -lm");
			};
		} elsif ( $os eq "freebsd" ) {
			$utility->file_write("sub_mysql/conf-sqlcc", "-I/usr/local/include/mysql");
			$utility->file_write("sub_mysql/conf-sqlld", "-L/usr/local/lib/mysql -lmysqlclient -lnsl -lm");
		};

		$utility->syscmd("chmod 775 makelang");
		#$utility->syscmd("make mysql");  # haven't figured this out yet (compile problems)
		$utility->syscmd("make");
		$utility->syscmd("make man");
		$utility->syscmd("make setup");
	};

	if ($conf->{'install_ezmlm_cgi'} ) 
	{
		$perl->module_load( {module=>"Email::Valid"} );
		$perl->module_load( {module=>"Mail::Ezmlm"} );
	};
};



=head2 filtering

Installs SpamAssassin, ClamAV, simscan, QmailScanner, maildrop, procmail, and programs that support the aforementioned ones. See toaster-watcher.conf for options that allow you to customize which programs are installed and any options available.

  $setup->filtering($conf);

=cut

sub filtering($)
{
	my ($self, $conf) = @_;

	my $debug = $conf->{'debug'};

	if ( $os eq "freebsd" ) 
	{
		if ( $conf->{'install_maildrop'} ) 
		{
			$freebsd->port_install("maildrop", "mail" , undef, undef, undef, 1 );
			$self->maildrop($conf);
		};
		$freebsd->port_install ("p5-Mail-Audit", "mail" , undef, undef, undef, 1 );
		$freebsd->port_install ("unzip","archivers" );
		$self->razor        ($conf);
		$freebsd->port_install ("pyzor", "mail", undef, undef, undef, 1)        if $conf->{'install_pyzor'};
		$freebsd->port_install ("bogofilter", "mail",undef,undef,undef,1)       if $conf->{'install_bogofilter'};
		$freebsd->port_install ("dcc-dccd", "mail", undef, undef, "WITHOUT_SENDMAIL=1", 1 )    if $conf->{'install_dcc'};
		$freebsd->port_install ("procmail", "mail")                             if $conf->{'install_procmail'};

		# Stupid broken ports fix (expects Net::DNS to be installed in mach)
#		unless ( -e "/usr/local/lib/perl5/site_perl/5.8.2/mach/Net" ) {
#			print "filtering: fixing that infernal broken p5-Email-Valid port dependency on Net::DNS\n";
#			symlink("/usr/local/lib/perl5/site_perl/5.8.2/Net", "/usr/local/lib/perl5/site_perl/5.8.2/mach/Net");
#		};

		$freebsd->port_install ("p5-Email-Valid", "mail", undef, undef, undef, 1);
	}

	$self->spamassassin ($conf);
	$self->razor        ($conf);
	$self->clamav       ($conf);
	$self->qmail_scanner($conf);
	$self->simscan      ($conf);
};

sub filtering_test
{
	my ($self, $conf) = @_;

	$self->qmail_scanner_test($conf);

	$self->simscan_test($conf);

	print "\n\nFor more ways to test your Virus scanner, go here: 
\n\t http://www.testvirus.org/\n\n";
}

sub horde
{
	my ($self, $conf) = @_;

	
}

sub imap_test_auth
{
	my ($self, $conf) = @_;

	my $debug = 0;

	print "imap_test_auth: checking Mail::IMAPClient ........................ ";
	$perl->module_load( {module=>"Mail::IMAPClient", ports_name=>'p5-Mail-IMAPClient', ports_group=>'mail'} );
	print "ok\n";
	print "imap_test_auth: checking IO::Socket::SSL ......................... ";
	$perl->module_load( {module=>"IO::Socket::SSL", ports_name=>'p5-IO-Socket-SSL', ports_group=>'security'} );
	print "ok\n";

	my $user = $conf->{'toaster_test_email'}      || 'test2@example.com';
	my $pass = $conf->{'toaster_test_email_pass'} || 'cHanGeMe';

	# test a plain password auth
	my $mess = "imap_test_auth: authenticate IMAP user with plain passwords";
	my $imap = Mail::IMAPClient->new( User=>$user, Password=>$pass, Server=>'localhost');
	if ( defined $imap ) 
	{
		$imap->IsAuthenticated() ? $self->_formatted($mess, "ok") : $self->_formatted($mess, "FAILED");

		my @features = $imap->capability or warn "Couldn't determine capability: $@\n";
		print "Your IMAP server supports: " . join(",", @features) . "\n\n" if $debug;
		$imap->logout;
	} 
	else {
		$self->_formatted($mess, "FAILED");
	}
	

	# an authentication that should fail
	$mess = "testing an authentication that should fail";
	$imap = Mail::IMAPClient->new( Server=>'localhost', User=>'no_such_user',Pass=>'hi_there_log_watcher');
	$imap->IsConnected() or warn "couldn't connect!\n";
	$imap->IsAuthenticated() ? $self->_formatted($mess, "FAILED") : $self->_formatted($mess, "ok");
	$imap->logout;

	$mess = "imap_test_auth: authenticate IMAP SSL user with plain password...";
	if ( eval "require IO::Socket::SSL" ) {
		my $socket = IO::Socket::SSL->new( PeerAddr => 'localhost', PeerPort => 993, Proto => 'tcp') or warn "couldn't connect.\n";
		if (defined $socket) {
			print $socket->get_cipher() . "...";
			print $socket ". login $user $pass\n";
			my $r = $socket->peek;
			print "server returned: $r\n";
			$r =~ /OK/  ?
				$self->_formatted($mess, "ok") : $self->_formatted($mess, "FAILED");
			print $socket ". logout\n";
			close $socket;
#  no idea why this doesn't work, so I just forge an authentication by printing directly to the socket
#			my $imapssl = Mail::IMAPClient->new( Socket=>$socket, User=>$user, Password=>$pass) or warn "new IMAP failed: ($@)\n";
#			$imapssl->IsAuthenticated() ? print "ok\n" : print "FAILED.\n";
		} 
		else {
			$self->_formatted($mess."(couldn't get SSL connection to localhost:993)", "FAILED")
		}
	} else {
		$self->_formatted($mess."skipping (IO::Socket::SSL not found)", "FAILED")
	}

	# doesn't work yet because courier doesn't support CRAM-MD5 via the vchkpw auth module
#	print "authenticating IMAP user with CRAM-MD5...";
#	$imap->connect;
#	$imap->authenticate();
#	$imap->IsAuthenticated() ? print "ok\n" : print "FAILED.\n";
#
#	print "logging out...";
#	$imap->logout;
#	$imap->IsAuthenticated() ? print "FAILED.\n" : print "ok.\n";
#	$imap->IsConnected() ? print "connection open.\n" : print "connection closed.\n";

};


=head2 is_newer

Checks a three place version string like 5.3.24 to see if the current version is newer than some value. Useful when you have various version of a program like vpopmail or mysql and the syntax you need to use for building it is different for differing version of the software.

=cut

sub is_newer($$)
{
	my ($min, $cur) = @_;

	my @mins = split(/\./, $min);
	my @curs = split(/\./, $cur);

	if ( $curs[0] > $mins[0] ) { return 1; };
	if ( $curs[1] > $mins[1] ) { return 1; };            
	if ( $curs[2] > $mins[2] ) { return 1; };
	if ( $curs[3] > $mins[3] ) { return 1; };

	return 0;
}       
        

=head2 isoqlog

Installs isoqlog.

  $setup->isoqlog($conf);

=cut


sub isoqlog
{
	my ($self, $conf) = @_;

	my $ver = $conf->{'install_isoqlog'};

	unless ( $ver )
	{
		$self->_formatted("isoqlog: ERROR: install_isoqlog is not set!", "FAILED");
		return 0;
	};

	my $return = 0;

	if ( $ver eq "port" )
	{
		if ( $os eq "freebsd" )
		{
			if ($freebsd->is_port_installed("isoqlog")) {
				$self->_formatted("isoqlog: installing.", "ok (exists)");
				$return = 2;
			} else {
				$freebsd->port_install("isoqlog", "mail");
				if ($freebsd->is_port_installed("isoqlog")) {
					$self->_formatted("isoqlog: installing.", "ok");
					$return = 1;
				}
			}
		} else {
			$self->_formatted("isoqlog: install_isoqlog = port is not valid for $os!", "FAILED");
			return 0;
		};
	} 
	else {
		if ( -x $utility->find_the_bin("isoqlog") ) {
			$self->_formatted("isoqlog: installing.", "ok (exists)");
			$return = 2;
		}
	};

	unless ( -x $utility->find_the_bin("isoqlog") )
	{
		print "\nIsoqlog not found. Trying to install v$ver from sources for $os!\n\n";

		if ( $ver eq "port" || $ver == 1) { $ver = 2.2; };

		my $configure = "./configure ";

		if ( $conf->{'toaster_prefix'} ) {
			$configure .= "--prefix=" . $conf->{'toaster_prefix'} . " ";
			$configure .= "--exec-prefix=" . $conf->{'toaster_prefix'} . " ";
		};

		if ($conf->{'system_config_dir'} ) {
			$configure .= "--sysconfdir=" . $conf->{'system_config_dir'} . " ";
		};

		my $vals = { package => "isoqlog-$ver",
			site    => 'http://www.enderunix.org',
			url     => '/isoqlog',
			targets => [$configure, 'make', 'make install', 'make clean'],
			patches => '',
			bintest => 'isoqlog',
			debug   => 1,
			source_sub_dir=>'mail',
		};
		print "isoqlog: building with $configure.\n";

		$utility->install_from_source($conf, $vals);
	};

	if ( $conf->{'toaster_prefix'} ne "/usr/local" ) {
		symlink("/usr/local/share/isoqlog",  $conf->{'toaster_prefix'} . "/share/isoqlog");
	};
	$return = 1 if ( -x $utility->find_the_bin("isoqlog") );

	$self->isoqlog_conf($conf);
	return $return;
}


sub isoqlog_conf($)
{
	my ($self, $conf) = @_;

	#my $etc = $conf->{'system_config_dir'} || "/usr/local/etc";
	my $etc = "/usr/local/etc";   # isoqlog doesn't honor --sysconfdir yet
	my $file = "$etc/isoqlog.conf";
	if ( -e $file) { 
		$self->_formatted("isoqlog_conf: creating $file", "ok (exists)");
		return 2; 
	};

	my @lines;

	my $htdocs = $conf->{'toaster_http_docs'} || "/usr/local/www/data";
	my $hostn  = $conf->{'toaster_hostname'}  || `hostname`;
	my $logdir = $conf->{'qmail_log_base'}    || "/var/log/mail";
	my $qmaild = $conf->{'qmail_dir'}         || "/var/qmail";
	my $prefix = $conf->{'toaster_prefix'}    || "/usr/local";

	push @lines, "#isoqlog Configuration file";
	push @lines, "";
	push @lines, 'logtype = "qmail-multilog"';
	push @lines, 'logstore = "'. $logdir . '/send"';
	push @lines, 'domainsfile = "'. $qmaild . '/control/rcpthosts"';
	push @lines, 'outputdir = "' . $htdocs . '/isoqlog"';
	push @lines, 'htmldir = "'.$prefix.'/share/isoqlog/htmltemp"';
	push @lines, 'langfile = "'.$prefix.'/share/isoqlog/lang/english"';
	push @lines, 'hostname = "' . $hostn . '"';
	push @lines, "";
	push @lines, "maxsender   = 100";
	push @lines, "maxreceiver = 100";
	push @lines, "maxtotal    = 100";
	push @lines, "maxbyte     = 100";

	$utility->file_write($file, @lines) or croak "couldn't write $file: $!\n";
	$self->_formatted("isoqlog_conf: creating $file", "ok");

	$utility->syscmd( $utility->find_the_bin("isoqlog") );

	unless ( -e "$htdocs/isoqlog" ) 
	{
		mkdir(0755, "$htdocs/isoqlog");
	};

	# what follows is one way to fix the missing images problem. The better
	# way is with an apache alias directive such as:
	# Alias /isoqlog/images/ "/usr/local/share/isoqlog/htmltemp/images/"
	# that is now included in the Apache 2.0 patch

	unless ( -e "$htdocs/isoqlog/images" ) 
	{
		$utility->syscmd("cp -r /usr/local/share/isoqlog/htmltemp/images $htdocs/isoqlog/images");
	};
};


sub logmonster(;$)
{
	my ($self, $debug) = @_;

	my $perlbin = $utility->find_the_bin("perl");

	my  @targets = ("$perlbin Makefile.PL", "make", "make install");
	push @targets, "make test" if $debug;

	my $vals = {
		module   => 'Apache-Logmonster',
		archive  => 'Logmonster.tar.gz',
		url      => '/internet/www/logmonster',
		targets  => \@targets,
	};

	$perl->module_install($vals);
};



=head2 maildrop

Installs a maildrop filter in $prefix/etc/mail/mailfilter, a script for use with Courier-IMAP in $prefix/sbin/subscribeIMAP.sh, and sets up a filter debugging file in /var/log/mail/maildrop.log.

  $setup->maildrop($conf, $debug);

=cut

sub maildrop($)
{
	my ($self, $conf) = @_;

	unless ($conf->{'install_maildrop'}) {
		print "skipping maildrop install because it's not enabled!\n";
		return 0;
	};

	my $prefix = $conf->{'toaster_prefix'} || "/usr/local";
	my $ver    = $conf->{'install_maildrop'};

	if ( $ver eq "port" || $ver eq "1" ) {
		if    ( $os eq "freebsd") { $freebsd->port_install ("maildrop", "mail", undef, undef, "WITH_MAILDIRQUOTA=1", 1) }
		elsif ( $os eq "darwin" ) { $darwin->port_install("maildrop") };
		$ver = "2.0.2";
	};

	unless ( -x $utility->find_the_bin("maildrop") ) 
	{
		$utility->install_from_source($conf, 
			{
				package=> 'maildrop-'.$ver, 
				site   => 'http://'.$conf->{'toaster_sf_mirror'}, 
				url    => '/courier', 
				targets=> ['./configure --prefix='.$prefix.' --exec-prefix='.$prefix, 'make', 'make install-strip', 'make install-man'],
				source_sub_dir => 'mail',
			} 
		);
	};

	my $uid = getpwnam("vpopmail");
	my $gid = getgrnam("vchkpw");
	croak "maildrop: didn't get uid or gid for vpopmail:vchkpw!\n" unless ($uid && $gid);

	my $etcmail = "$prefix/etc/mail";
	mkdir($etcmail, 0755) unless ( -d $etcmail );

	$self->maildrop_filter($conf);

	my $imap = "$prefix/sbin/subscribeIMAP.sh";
	unless ( -e $imap )
	{
		my $chown = $utility->find_the_bin("chown");
		my $chmod = $utility->find_the_bin("chmod");

		my @lines;
		push @lines, '#!/bin/sh';
		push @lines, '#';
		push @lines, '# This subscribes the folder passed as $1 to courier imap';
		push @lines, '# so that Maildir reading apps (Sqwebmail, Courier-IMAP) and';
		push @lines, '# IMAP clients (squirrelmail, Mailman, etc) will recognize the';
		push @lines, '# extra mail folder.';
		push @lines, '';
		push @lines, '# Matt Simerson - 12 June 2003';
		push @lines, '';
		push @lines, 'LIST="$2/Maildir/courierimapsubscribed"';
		push @lines, '';
		push @lines, 'if [ -f "$LIST" ]; then';
		push @lines, '	# if the file exists, check it for the new folder';
		push @lines, '	TEST=`cat "$LIST" | grep "INBOX.$1"`';
		push @lines, '';
		push @lines, '	# if it is not there, add it';
		push @lines, '	if [ "$TEST" = "" ]; then';
		push @lines, '		echo "INBOX.$1" >> $LIST';
		push @lines, '	fi';
		push @lines, 'else';
		push @lines, '	# the file does not exist so we define the full list';
		push @lines, '	# and then create the file.';
		push @lines, '	FULL="INBOX\nINBOX.Sent\nINBOX.Trash\nINBOX.Drafts\nINBOX.$1"';
		push @lines, '';
		push @lines, '	echo -e $FULL > $LIST';
		push @lines, '	' . $chown . ' vpopmail:vchkpw $LIST';
		push @lines, '	' . $chmod . ' 644 $LIST';
		push @lines, 'fi';
		push @lines, '';

		$utility->file_write($imap, @lines) 
			or croak "maildrop: FAILED: couldn't write $imap: $!\n";
		chmod 00555, $imap;
	};

	my $log = $conf->{'qmail_log_base'} || "/var/log/mail";
	unless ( -d $log ) 
	{ 
		$utility->syscmd("mkdir -p $log"); 
		chown( getpwnam($conf->{'qmail_log_user'}), getgrnam($conf->{'qmail_log_group'}), $log) 
			or croak "maildrop: chown $log failed!";
	};

	my $logf = "$log/maildrop.log";

	unless ( -e $logf ) 
	{
		$utility->file_write($logf, "begin");
		chown($uid, $gid, $logf) or croak "maildrop: chown $logf failed!";
	};
};


=head2 maillogs

Installs the maillogs script, creates the logging directories (toaster_log_dir/*), creates the qmail supervise dirs, installs maillogs as a log post-processor and then builds the corresponding service/log/run file to use with each post-processor.

  $setup->maillogs($conf);

=cut


sub maillogs($)
{
	my ($self, $conf) = @_;

	my $debug = $conf->{'debug'};
	my $user  = $conf->{'qmail_log_user'}  || "qmaill";
	my $group = $conf->{'qmail_log_group'} || "qnofiles";

	my $uid = getpwnam($user);
	my $gid = getgrnam($group);

	unless ( $uid && $gid ) {
		print "\nFAILED! The user $user or group $group does not exist.\n";
		return 0;
	};

	$toaster->supervise_dirs_create($conf, $debug);

	# if it exists, make sure it's owned by qmail:qnofiles
	my $log   = $conf->{'qmail_log_base'}  || "/var/log/mail";
	if ( -w $log ) {
		chown($uid, $gid, $log) or carp "Couldn't chown $log to $uid: $!\n";
		$self->_formatted("maillogs: setting ownership of $log", "ok");
	};

	unless ( -d $log ) 
	{ 
		mkdir($log, 0755) or croak "maillogs: couldn't create $log: $!";
		chown($uid, $gid, $log) or croak "maillogs: couldn't chown $log: $!";
		$self->_formatted("maillogs: creating $log", "ok");
	};

	foreach my $prot ( qw/ send smtp pop3 submit / )
	{
		unless ( -d "$log/$prot" ) 
		{
			$self->_formatted("maillogs: creating $log/$prot", "ok");
			mkdir("$log/$prot", 0755) or croak "maillogs: couldn't create: $!";
		} 
		else 
		{
			$self->_formatted("maillogs: create $log/$prot", "ok (exists)");
		};
		chown($uid, $gid, "$log/$prot") or croak "maillogs: chown $log/$prot failed: $!";
	};


	my $maillogs = "/usr/local/sbin/maillogs";

	croak "maillogs FAILED: couldn't find maillogs!\n" unless (-e $maillogs);

	my $r = $utility->install_if_changed($maillogs, "$log/send/sendlog", 
		{uid=>$uid, $gid=>$gid, mode=>00755}, $debug);
	return 0 unless $r;
	if ($r==1) { $r = "ok" } else { $r = "ok (current)"};
	$self->_formatted("maillogs: update $log/send/sendlog", $r);

	$r = $utility->install_if_changed($maillogs, "$log/smtp/smtplog", 
		{uid=>$uid, $gid=>$gid, mode=>00755}, $debug);
	if ($r==1) { $r = "ok" } else { $r = "ok (current)"};
	$self->_formatted("maillogs: update $log/smtp/smtplog", $r);

	$utility->install_if_changed($maillogs, "$log/pop3/pop3log", 
		{uid=>$uid, $gid=>$gid, mode=>00755}, $debug);
	if ($r==1) { $r = "ok" } else { $r = "ok (current)"};
	$self->_formatted("maillogs: update $log/pop3/pop3log", $r);

	$self->cronolog ($conf);
	$self->isoqlog  ($conf);

	$perl->module_load( {module=>'Mail::Toaster::Logs'} );
	my $logs = new Mail::Toaster::Logs;
	$logs->CheckSetup($conf);

};


=head2 mattbundle

Downloads and installs the latest version of MATT::Bundle.

  $setup->mattbundle($debug);

=cut


sub mattbundle(;$)
{
	my ($self, $debug) = @_;

	my $perlbin = $utility->find_the_bin("perl");

	my  @targets = ("$perlbin Makefile.PL", "make", "make install");
	push @targets, "make test" if $debug;

	my $vals = {
		module   => 'MATT-Bundle',
		archive  => 'MATT-Bundle.tar.gz',
		url      => '/computing/perl/MATT-Bundle',
		targets  => \@targets,
	};

	$perl->module_install($vals);
};


=head2 maildrop_filter

Creates and installs the maildrop mailfilter file.

  $setup->maildrop_filter($conf);

=cut


sub maildrop_filter($)
{
	my ($self, $conf) = @_;

	my $prefix  = $conf->{'toaster_prefix'} || "/usr/local";
	my $logbase = $conf->{'qmail_log_base'};

	unless ( $logbase )
	{
		if    (-d "/var/log/mail" ) { $logbase = "/var/log/mail"  } 
		elsif (-d "/var/log/qmail") { $logbase = "/var/log/qmail" } 
		else                        { $logbase = "/var/log/mail"  };
	};

	my $debug = $conf->{'toaster_debug'};
	$debug ||= $conf->{'filtering_debug'};

	my @lines = 'SHELL="/bin/sh"';
	push @lines, 'import EXT
import HOST
VHOME=`pwd`
TIMESTAMP=`date "+%b %d %H:%M:%S"`
MAILDROP_OLD_REGEXP="1"

##
#  title:  mailfilter-site
#  author: Matt Simerson
#  version 2.11
#
#  This file is automatically generated by toaster_setup.pl, 
#  DO NOT HAND EDIT, your changes may get overwritten!
#
#  Make changes to toaster-watcher.conf, and run 
#  toaster_setup.pl -s maildrop to rebuild this file. Old versions
#  are preserved as $NAME.timestamp
#
#  Usage: Install this file in your local etc/mail/mailfilter. On 
#  FreeBSD, this would be $prefix/etc/mail/mailfilter
#
#  Create a .qmail file in each users Maildir as follows:
#  echo "| $prefix/bin/maildrop '.$prefix.'/etc/mail/mailfilter" \
#      > ~vpopmail/domains/example.com/user/.qmail
#
#  You can also use qmailadmin v1.0.26 or higher to do that for you
#  via it is --enable-modify-spam and --enable-spam-command options.
#  This is the default behavior for your Mail::Toaster.
#
# Environment Variables you can import from qmail-local:
#  SENDER  is  the envelope sender address
#  NEWSENDER is the forwarding envelope sender address
#  RECIPIENT is the envelope recipient address, local@domain
#  USER is user
#  HOME is your home directory
#  HOST  is the domain part of the recipient address
#  LOCAL is the local part
#  EXT  is  the  address extension, ext.
#  HOST2 is the portion of HOST preceding the last dot
#  HOST3 is the portion of HOST preceding the second-to-last dot
#  HOST4 is the portion of HOST preceding the third-to-last dot
#  EXT2 is the portion of EXT following the first dash
#  EXT3 is the portion following the second dash; 
#  EXT4 is the portion following the third dash.
#  DEFAULT  is  the  portion corresponding to the default part of the .qmail-... file name
#  DEFAULT is not set if the file name does not end with default
#  DTLINE  and  RPLINE are the usual Delivered-To and Return-Path lines, including newlines
#
# qmail-local will be calling maildrop. The exit codes that qmail-local
# understands are:
#     0 - delivery is complete
#   111 - temporary error
#   xxx - unknown failure
##
';

	if ($debug) { push @lines,  'logfile "' . $logbase . '/maildrop.log"'  } 
	else        { push @lines, '#logfile "' . $logbase . '/maildrop.log"'  };

	push @lines, 'log "$TIMESTAMP - BEGIN maildrop processing for $EXT@$HOST ==="

# I have seen cases where EXT or HOST is unset. This can be caused by 
# various blunders committed by the sysadmin so we should test and make
# sure things are not too messed up.
#
# By exiting with error 111, the error will be logged, giving an admin
# the chance to notice and fix the problem before the message bounces.

if ( $EXT eq "" )
{ 
        log "  FAILURE: EXT is not a valid value ($EXT)"
        log "=== END ===  $EXT@$HOST failure (EXT variable not imported)"
        EXITCODE=111
        exit
}

if ( $HOST eq "" )
{ 
        log "  FAILURE: HOST is not a valid value ($HOST)"
        log "=== END ===  $EXT@$HOST failure (HOST variable not imported)"
        EXITCODE=111
        exit
}

';

	my $spamass_method = $conf->{'filtering_spamassassin_method'};

	if ( $spamass_method eq "user" || $spamass_method eq "domain" ) 
	{
		push @lines, '##
# Note that if you want to pass a message larger than 250k to spamd
# and have it processed, you will need to also set spamc -s. See the
# spamc man page for more details.
##

exception {
	if ( /^X-Spam-Status: /:h )
	{
		# do not pass through spamassassin if the message already
		# has an X-Spam-Status header. 

		log "Message already has X-Spam-Status header, skipping spamc"
	}
	else
	{
		if ( $SIZE < 256000 ) # Filter if message is less than 250k
		{
			`test -x '.$prefix.'/bin/spamc`
			if ( $RETURNCODE == 0 )
			{
				log "   running message through spamc"
				exception {
					xfilter \''.$prefix.'/bin/spamc -u "$EXT@$HOST"\'
				}
			}
			else
			{
				log "   WARNING: no '.$prefix.'/bin/spamc binary!"
			}
		}
	}
}
';

	};

	push @lines, '##
# Include any rules set up for the user - this gives the 
# administrator a way to override the sitewide mailfilter file
#
# this is also the "suggested" way to set individual values
# for maildrop such as quota.
##

`test -r $VHOME/.mailfilter`
if( $RETURNCODE == 0 )
{
	log "   including $VHOME/.mailfilter"
	exception {
		include $VHOME/.mailfilter
	}
}

## 
# create the maildirsize file if it does not already exist
# (could also be done via "deliverquota user@dom.com 10MS,1000C)
##

`test -e $VHOME/Maildir/maildirsize`
if( $RETURNCODE == 1)
{
VUSERINFO=`'.$prefix.'/vpopmail/bin/vuserinfo`
	`test -x $VUSERINFO`
	if ( $RETURNCODE == 0)
	{
		log "   creating $VHOME/Maildir/maildirsize for quotas"
		`$VUSERINFO -Q $EXT@$HOST`

		`test -s "$VHOME/Maildir/maildirsize"`
   		if ( $RETURNCODE == 0 )
   		{
     			`/usr/sbin/chown vpopmail:vchkpw $VHOME/Maildir/maildirsize`
				`/bin/chmod 640 $VHOME/Maildir/maildirsize`
		}
	}
	else
	{
		log "   WARNING: cannot find vuserinfo! Please edit mailfilter"
	}
}
';

	push @lines, '##
# Set MAILDIRQUOTA. If this is not set, maildrop and deliverquota
# will not enforce quotas for message delivery.
#
# I find this much easier than creating yet another config file
# to store this in. This way, any time the quota is changed in
# vpopmail, it will get noticed by maildrop immediately.
##

`test -e $VHOME/Maildir/maildirsize`
if( $RETURNCODE == 0)
{
	MAILDIRQUOTA=`/usr/bin/head -n1 $VHOME/Maildir/maildirsize`
}

##
# The message should be tagged, so lets bag it.
##
# HAM:  X-Spam-Status: No, score=-2.6 required=5.0
# SPAM: X-Spam-Status: Yes, score=8.9 required=5.0
#
# Note: SA < 3.0 uses "hits" instead of "score"
#
# if ( /^X-Spam-Status: *Yes/)  # test if spam status is yes
# The following regexp matches any spam message and sets the
# variable $MATCH2 to the spam score.

if ( /X-Spam-Status: Yes, (hits|score)=![0-9]+\.[0-9]+! /:h)
{';

	my $score     = $conf->{'filtering_spama_discard_score'};
	my $pyzor     = $conf->{'filtering_report_spam_pyzor'};
	my $sa_report = $conf->{'filtering_report_spam_spamassassin'};

	if ($score)
	{
		push @lines, '
	# if the message scored a '.$score.' or higher, then there is no point in
	# keeping it around. SpamAssassin already knows it as spam, and
	# has already "autolearned" from it if you have that enabled. The
	# end user likely does not want it. If you wanted to cc it, or
	# deliver it elsewhere for inclusion in a spam corpus, you could
	# easily do so with a cc or xfilter command

	if ( $MATCH2 >= ' . $score . ' )   # from Adam Senuik post to mail-toasters
	{';

		if ( $pyzor && ! $sa_report )
		{
			push @lines, '
		`test -x '.$prefix.'/bin/pyzor`
		if( $RETURNCODE == 0 )
		{
			# if the pyzor binary is installed, report all messages with
			# high spam scores to the pyzor servers
		
			log "   SPAM: score $MATCH2: reporting to Pyzor"
			exception {
				xfilter "'.$prefix.'/bin/pyzor report"
			}
		}';
		};

		if ( $sa_report )
		{
			push @lines, '

		# new in version 2.5 of Mail::Toaster mailfiter
		`test -x '.$prefix.'/bin/spamassassin`
		if( $RETURNCODE == 0 )
		{
			# if the spamassassin binary is installed, report messages with
			# high spam scores to spamassassin (and consequently pyzor, dcc,
			# razor, and SpamCop)
		
			log "   SPAM: score $MATCH2: reporting spam via spamassassin -r"
			exception {
				xfilter "'.$prefix.'/bin/spamassassin -r"
			}
		}';
		};

		push @lines, '		log "   SPAM: score $MATCH2 exceeds '. $score .': nuking message!"
		log "=== END === $EXT@$HOST success (discarded)"
		EXITCODE=0
		exit
	}
';
	};

	push @lines, '
	# if the user does not have a Spam folder, we create it.

	`test -d $VHOME/Maildir/.Spam`
	if( $RETURNCODE == 1 )
	{
		log "   creating $VHOME/Maildir/.Spam "
		`maildirmake -f Spam $VHOME/Maildir`
		`$prefix/sbin/subscribeIMAP.sh Spam $VHOME`
	}

	log "   SPAM: score $MATCH2: delivering to $VHOME/Maildir/.Spam"

	# make sure the deliverquota binary exists and is executable
	# if not, then we cannot enforce quotas. If you do not check
	# for this, and the binary is missing, maildrop silently
	# discards mail. Do not ask how I know this.

	`test -x '.$prefix.'/bin/deliverquota`
	if ( $RETURNCODE == 1 )
	{
		log "   WARNING: no deliverquota!"
		log "=== END ===  $EXT@$HOST success"
		exception {
			to "$VHOME/Maildir/.Spam"
		}
	}
	else
	{
		exception {
			xfilter "'.$prefix.'/bin/deliverquota -w 90 $VHOME/Maildir/.Spam"
		}

		if ( $RETURNCODE == 0 )
		{
			log "=== END ===  $EXT@$HOST  success (quota)"
			EXITCODE=0
			exit
		}
		else
		{
			if( $RETURNCODE == 77)
			{
				log "=== END ===  $EXT@$HOST  bounced (quota)"
				to "|/var/qmail/bin/bouncesaying \'$EXT@$HOST is over quota\'"
			}
			else
			{
				log "=== END ===  $EXT@$HOST failure (unknown deliverquota error)"
				to "$VHOME/Maildir/.Spam"
			}
		}
	}
}

if ( /^X-Spam-Status: No, hits=![\-]*[0-9]+\.[0-9]+! /:h)
{
	log "   message is clean ($MATCH2)"
}

##
# Include any other rules that the user might have from
# sqwebmail or other compatible program
##

`test -r $VHOME/Maildir/.mailfilter`
if( $RETURNCODE == 0 )
{
	log "   including $VHOME/Maildir/.mailfilter"
	exception {
		include $VHOME/Maildir/.mailfilter
	}
}

log "   delivering to $VHOME/Maildir"

`test -x '.$prefix.'/bin/deliverquota`
if ( $RETURNCODE == 1 )
{
	log "   WARNING: no deliverquota!"
	log "=== END ===  $EXT@$HOST success"
	exception {
		to "$VHOME/Maildir"
	}
}
else
{
	exception {
		xfilter "'.$prefix.'/bin/deliverquota -w 90 $VHOME/Maildir"
	}

	##
	# check to make sure the message was delivered
	# returncode 77 means that out maildir was overquota - bounce mail
	##
	if( $RETURNCODE == 77)
	{
		#log "   BOUNCED: bouncesaying \'$EXT@$HOST is over quota\'"
		log "=== END ===  $EXT@$HOST  bounced"
		to "|/var/qmail/bin/bouncesaying \'$EXT@$HOST is over quota\'"
	}
	else
	{
		log "=== END ===  $EXT@$HOST  success (quota)"
		EXITCODE=0
		exit
	}
}

log "WARNING: This message should never be printed!"

# Another way of getting the EXT and HOST although I am not
# sure why this would ever be beneficial
#
#USERNAME=`echo ${VHOME##*/}`
#USERHOST=`PWDTMP=${VHOME%/*}; echo ${PWDTMP##*/}`
#log "  VARS: USERNAME: $USERNAME, USERHOST: $USERHOST"';

	my $filterfile = $conf->{'filtering_maildrop_filter_file'}
		|| "$prefix/etc/mail/mailfilter";

	my ($path, $file) = $utility->path_parse($filterfile);
	unless ( -d $path) { $utility->syscmd("mkdir -p $path"); };
	unless ( -d $path) { carp "Sorry, $path doesn't exist and I couldn't create it.\n"; return 0;};

	$utility->file_write("$filterfile.new", @lines);

	! -e $filterfile ? $utility->file_write($filterfile, @lines) : print "installing $filterfile\n";

	if ( $utility->files_diff($filterfile, "$filterfile.new") ) 
	{
		my $old = $utility->file_archive($filterfile);
		if ( $old && -e $old ) {
			print "\n\nNOTICE: a previous maildrop filter was installed. I have backed it up as $old. A new filterfile has been installed as $filterfile. If you had any customizations in the old file, you'll need to merge them into the new one.\n\n"; sleep 10;
			$utility->file_write($filterfile, @lines);
		};
	};

	my $user = $conf->{'vpopmail_user'};   $user  ||= "vpopmail";
	my $group = $conf->{'vpopmail_group'}; $group ||= "vchkpw";

	my $uid = getpwnam($user);
	my $gid = getgrnam($group);

	chmod 00600, "$filterfile";
	chmod 00600, "$filterfile.new";
	chown($uid, $gid, "$filterfile") or carp "Couldn't chown $filterfile to $uid: $!\n";
	chown($uid, $gid, "$filterfile.new") or carp "Couldn't chown $filterfile.new to $uid: $!\n";

	$file = "/etc/newsyslog.conf";
	if ( -e $file ) {
		unless ( `grep maildrop $file` )
		{
			$utility->file_append($file, ["/var/log/mail/maildrop.log $user:$group 644	3	1000 *	Z"]);
		};
	};
};

sub mrm(;$)
{
	my ($self, $debug) = @_;

	my $perlbin = $utility->find_the_bin("perl");

	my  @targets = ("$perlbin Makefile.PL", "make", "make install");
	push @targets, "make test" if $debug;

	my $vals = {
		module   => 'Mysql-Replication',
		archive  => 'Mysql-Replication.tar.gz',
		url      => '/internet/sql/mrm',
		targets  => \@targets,
	};

	$perl->module_install($vals);
};


sub rsync
{
	my ($self, $conf, $debug) = @_;

	if    ( $os eq "freebsd") { $freebsd->port_install("rsync", "net", undef, undef, "", 1 ) } 
	elsif ( $os eq "darwin" ) { $darwin->port_install("rsync")  } 
	else 
	{
		print "please install rsync manually. Support for $os isn't vailable yet.\n";
		exit 0;
	}
}

sub nictool
{
	my ($self, $conf, $debug) = @_;

	$self->expat($conf);

	unless ( -x $utility->find_the_bin("rsync") ) {
		$self->rsync($conf);
	};

	unless ( -x $utility->find_the_bin("tinydns") ) {
		$self->djbdns($conf);
	};

	unless ( -x $utility->find_the_bin("mysql") ) {
		$self->mysqld($conf);
	};

	if ( $os eq "freebsd" ) 
	{
		$perl->module_load( {module=>"LWP::UserAgent", ports_name=>'p5-libwww',  ports_group=>'www'} );
		$perl->module_load( {module=>"SOAP::Lite",   ports_name=>'p5-SOAP-Lite', ports_group=>'net'} );
		$perl->module_load( {module=>"RPC::XML",     ports_name=>'p5-RPC-XML',   ports_group=>'net'} );
		$perl->module_load( {module=>"DBI",          ports_name=>'p5-DBI',       ports_group=>'databases'} );
		$perl->module_load( {module=>"DBD::mysql",   ports_name=>'p5-DBD-mysql', ports_group=>'databases'} );

		if ($conf->{'install_apache'} == 2 ) {
			$freebsd->port_install("p5-Apache-DBI", "www", undef, undef, "WITH_MODPERL2=yes", 1 );
		} else {
			$freebsd->port_install("p5-Apache-DBI", "www", undef, undef, "", 1 );
		};
	} 
	elsif ( $os eq "darwin")  
	{
		$perl->module_load( {module=>"LWP::UserAgent"} );
		$perl->module_load( {module=>"SOAP::Lite"} );
		$perl->module_load( {module=>"RPC::XML"} );
		$perl->module_load( {module=>"Apache::DBI"} );
	};

	# install NicTool Server
	my $perlbin   = $utility->find_the_bin("perl");
	my $version   = "NicToolServer-2.03";
	my $http_base = $conf->{'toaster_http_base'};

	my  @targets  = ("$perlbin Makefile.PL", "make", "make install");
	push @targets, "make test" if $debug;
	push @targets, "mv ../$version $http_base" unless ( -d "$http_base/$version");
	push @targets, "ln -s $http_base/$version $http_base/NicToolServer" unless ( -l "$http_base/NicToolServer");

	my $vals = {
		module   => $version,
		archive  => "$version.tar.gz",
		site     => 'http://www.nictool.com',
		url      => '/download/',
		targets  => \@targets,
	};

	$perl->module_install($vals);

	# install NicTool Client
	$version   = "NicToolClient-2.03";
	@targets = ("$perlbin Makefile.PL", "make", "make install");
	push @targets, "make test" if $debug;

	push @targets, "mv ../$version $http_base" unless ( -d "$http_base/$version" );
	push @targets, "ln -s $http_base/$version $http_base/NicToolClient" unless ( -l "$http_base/NicToolClient" );

	$vals = {
		module   => $version,
		archive  => "$version.tar.gz",
		site     => 'http://www.nictool.com',
		url      => '/download/',
		targets  => \@targets,
	};

	$perl->module_install($vals);
};

sub pop3_test_auth
{
	my ($self, $conf) = @_;

	my $debug = 0;
	my @features;

	$| = 1;

	print "pop3_test_auth: checking Mail::POP3Client ........................ ";
	$perl->module_load( {module=>"Mail::POP3Client", ports_name=>'p5-Mail-POP3Client', ports_group=>'mail'} );
	print "ok\n";

	my $user = $conf->{'toaster_test_email'}        || 'test2@example.com';
	my $pass = $conf->{'toaster_test_email_pass'}   || 'cHanGeMe';
	my $host = $conf->{'pop3_ip_address_listen_on'} || 'localhost';
	if ($host eq "system" || $host eq "qmail" || $host eq "all") { $host = "localhost" };

	my $mess = "pop3_test_auth: POP3 server with plain text password";
	my $pop = Mail::POP3Client->new( HOST => $host, AUTH_MODE => 'PASS' );
	$pop->User($user);
	$pop->Pass($pass);
	$pop->Connect() >= 0 || warn $pop->Message();
	$pop->State() eq "TRANSACTION" ? $self->_formatted($mess, "ok") : $self->_formatted($mess, "FAILED");
	if ( @features = $pop->Capa() ) {
		print "\nYour POP3 server supports: " . join(",", @features) . "\n";
	};
	$pop->Close;

	$mess = "pop3_test_auth: POP3 server with APOP password";
	$pop = Mail::POP3Client->new( HOST => $host, AUTH_MODE => 'APOP' );
	$pop->User($user);
	$pop->Pass($pass);
	$pop->Connect() >= 0 || warn $pop->Message();
	$pop->State() eq "TRANSACTION" ? $self->_formatted($mess, "ok") : $self->_formatted($mess, "FAILED (normal)");
	$pop->Close;

	if ( eval "require Digest::HMAC_MD5" ) 
	{
		$mess = "pop3_test_auth: POP3 server with CRAM-MD5 password";
		$pop = Mail::POP3Client->new( HOST => $host, AUTH_MODE => 'CRAM-MD5' );
		$pop->User($user);
		$pop->Pass($pass);
		$pop->Connect() >= 0 || warn $pop->Message();
		$pop->State() eq "TRANSACTION" ?  $self->_formatted($mess, "ok") : $self->_formatted($mess, "FAILED (normal)");
		$pop->Close;
	};

	$mess = "pop3_test_auth: POP3 SSL server with PLAIN password";
	$pop = Mail::POP3Client->new( HOST => $host, AUTH_MODE => 'PASS', USESSL=>1);
	$pop->User($user);
	$pop->Pass($pass);
	$pop->Connect();
	$pop->State() eq "TRANSACTION" ? $self->_formatted($mess, "ok") : $self->_formatted($mess, "FAILED");
	if ( @features = $pop->Capa() ) {
		print "Your POP3 server supports: " . join(",", @features) . "\n";
	};
	$pop->Close;


	$mess = "pop3_test_auth: POP3 SSL server with APOP password";
	$pop = Mail::POP3Client->new( HOST => $host, AUTH_MODE => 'APOP', USESSL=>1);
	$pop->User($user);
	$pop->Pass($pass);
	$pop->Connect();
	$pop->State() eq "TRANSACTION" ? $self->_formatted($mess, "ok") : $self->_formatted($mess, "FAILED (normal)");
	$pop->Close;


	if ( eval "require Digest::HMAC_MD5" ) 
	{
		$mess = "pop3_test_auth: POP3 SSL server with CRAM-MD5 password";
		$pop = Mail::POP3Client->new( HOST => $host, AUTH_MODE => 'CRAM-MD5' );
		$pop->User($user);
		$pop->Pass($pass);
		$pop->Connect() >= 0 || print $pop->Message();
		$pop->State() eq "TRANSACTION" ? $self->_formatted($mess, "ok") : $self->_formatted($mess, "FAILED (normal)");
		$pop->Close;
	};

};


=head2 phpmyadmin

Installs PhpMyAdmin for you, based on your settings in toaster-watcher.conf. The actual code that does the work is in Mail::Toaster::Mysql (part of Mail::Toaster::Bundle) so read the man page for Mail::Toaster::Mysql for more info.

  $setup->phpmyadmin($conf);

=cut


sub phpmyadmin($)
{
	my ($self, $conf) = @_;

	unless ( $conf->{'install_phpmyadmin'} ) 
	{
		print "phpMyAdmin install disabled. Set install_phpmyadmin in toaster-watcher.conf if you want to install it.\n";
		return 0;
	};

	# prevent t1lib from installing X11
	if ( $os eq "freebsd" ) {
		$freebsd->port_install("t1lib", "devel", undef, undef, "WITHOUT_X11=yes", 1 );
		if ( $utility->yes_or_no("I'm about to install php4-gd, which requires x11 libraries. Shall I try installing the xorg-libraries package?") ) 
		{
			$freebsd->package_install("xorg-libraries") unless $freebsd->is_port_installed("xorg-libraries");
		};

		if ( ! $freebsd->is_port_installed("xorg-libraries") && ! $freebsd->is_port_installed("XFree86-Libraries") ) {
			if ( $utility->yes_or_no("I'm about to install php4-gd, which requires x11 libraries. Shall I try installing the XFree86-Libraries package?") ) 
			{
				$freebsd->package_install("XFree86-Libraries");
			};
		};
		$freebsd->port_install("php4-gd", "graphics", undef, undef, "", 1 );
	};

	$perl->module_load( {module=>"Mail::Toaster::Mysql"} );
	my $mysql = Mail::Toaster::Mysql->new();
	$mysql->phpmyadmin_install();
};


=head2 mysqld

Installs mysql server for you, based on your settings in toaster-watcher.conf. The actual code that does the work is in Mail::Toaster::Mysql so read the man page for Mail::Toaster::Mysql for more info.

  $setup->mysqld($conf);

=cut


sub mysqld($;$)
{
	my ($self, $conf, $debug) = @_;

	unless ( $conf->{'install_mysql'} ) {
		$self->_formatted("mysql: install not selected!", "FAILED");
		return 0;
	};

	$perl->module_load( {module=>"Mail::Toaster::Mysql"} );
	my $mysql = Mail::Toaster::Mysql->new();
	$mysql->install(undef,undef,$conf->{'install_mysql'}, $conf);

	if ( -e "/tmp/mysql.sock" || -e "/opt/local/var/run/mysqld/mysqld.sock" )
	{
		print "mysqld: already running.\n";
		return 1;
	};

	print "Starting mysql:  ";
	my $etc   = $conf->{'system_config_dir'} || "/usr/local/etc";
	my $start = "$etc/rc.d/mysql-server";

	if    ( -x "$start.sh" ) { $utility->syscmd("$start.sh start"); } 
	if    ( -x  $start     ) { $utility->syscmd("$start    start"); } 
	else {
		print "\n\n\tI could not find your MySQL startup file, and so I couldn't start up MySQL for you. Please start MySQL manually.\n\n";
	}
};


=head2 ports

Install the ports tree on FreeBSD or Darwin and update it with cvsup. 

On FreeBSD, it optionally uses cvsup_fastest to choose the fastest cvsup server to mirror from. Configure toaster-watch.conf to adjust it's behaviour. It can also install the portupgrade port to use for updating your legacy installed ports. Portupgrade is very useful, but be very careful about using portupgrade -a. I always use portupgrade -ai and skip the toaster related ports such as qmail since we have customized version(s) of them installed.

  $setup->ports($conf);

=cut


sub ports($;$)
{
	my ($self, $conf) = @_;

	if ( $os eq "freebsd") 
	{
		$freebsd->ports_update($conf);
	} 
	elsif ( $os eq "darwin" ) 
	{
		$darwin->ports_update();
	} 
	else 
	{ 
		print "Sorry, no ports support for $os yet.\n";
	};
};


=head2 qmailadmin

Install qmailadmin based on your settings in toaster-watcher.conf.

  $setup->qmailadmin($conf, $debug);

=cut

sub qmailadmin($)
{
	my ($self, $conf)  = @_;

	unless ( $conf->{'install_qmailadmin'} ) {
		print "skipping qmailadmin install, it's not selected!\n";
		return 0;
	};

	my $debug = $conf->{'debug'};
	my $ver   = $conf->{'install_qmailadmin'}  || "1.2.7";

	my $package = "qmailadmin-$ver";
	my $site    = "http://" . $conf->{'toaster_sf_mirror'};
	my $url     = "/qmailadmin";

	my $toaster = "$conf->{'toaster_dl_site'}$conf->{'toaster_dl_url'}";
	$toaster ||= "http://www.tnpi.biz/internet/mail/toaster";

	my $src     = $conf->{'toaster_src_dir'} || "/usr/local/src";
	$src       .= "/mail";
	my $httpdir = $conf->{'toaster_http_base'} || "/usr/local/www";

	my $cgi = $conf->{'qmailadmin_cgi-bin_dir'};
	unless ($cgi && -e $cgi) 
	{
		if ( $conf->{'toaster_cgi-bin'} ) { $cgi = $conf->{'toaster_cgi-bin'}; } 
		else 
		{
			if ( -d "/usr/local/www/cgi-bin.mail") { $cgi = "/usr/local/www/cgi-bin.mail"; } 
			else                                   { $cgi = "/usr/local/www/cgi-bin"; };
		};
	};

	my $docroot = $conf->{'qmailadmin_http_docroot'};
	unless ( $docroot && -e $docroot ) 
	{
		if ( $conf->{'toaster_http_docs'} ) 
		{
			$docroot = $conf->{'toaster_http_docs'};
		} 
		else {
			if    ( -d "/usr/local/www/data/mail") { $docroot = "/usr/local/www/data/mail"; } 
			elsif ( -d "/usr/local/www/mail")      { $docroot = "/usr/local/www/mail";      } 
			else                                   { $docroot = "/usr/local/www/data";      };
		};
	};

	my ($help, $helpfile);
	if ( $conf->{'qmailadmin_help_links'} )
	{
		$help = 1;
		$helpfile = "qmailadmin-help-" . $conf->{'qmailadmin_help_links'};
	};

	if ( $package eq "ports" || $conf->{'install_qmailadmin'} eq "port" ) 
	{
		if ( $os ne "freebsd" ) {
			print "FAILURE: Sorry, no port install of qmailadmin (yet). Please edit
toaster-watcher.conf and select a version of qmailadmin to install.\n";
			return 0;
		};

		my @args;

		push @args, "WITH_DOMAIN_AUTOFILL=yes" if ( $conf->{'qmailadmin_domain_autofill'} );
		push @args, "WITH_MODIFY_QUOTA=yes"    if ( $conf->{'qmailadmin_modify_quotas'} );
		push @args, "WITH_HELP=yes" if $help;
		push @args, 'CGIBINSUBDIR=""';

		if ( $cgi =~ /\/usr\/local\/(.*)$/ ) { $cgi = $1; };
		push @args, 'CGIBINDIR="' . $cgi . '"';

		if ( $docroot =~ /\/usr\/local\/(.*)$/ ) { $docroot = $1; };
		push @args, 'WEBDATADIR="' . $docroot . '"';
#		push @args, 'WEBDATASUBDIR=""';
#		push @args, 'IMAGEDIR="' . $docroot . '/images/qmailadmin"';

		if ( $conf->{'qmail_dir'} ne "/var/qmail" ) {
			push @args, 'QMAIL_DIR="' . $conf->{'qmail_dir'} . '"';
		};

		if ( $conf->{'qmailadmin_spam_option'} ) { 
			push @args, "WITH_SPAM_DETECTION=yes";
			if ( $conf->{'qmailadmin_spam_command'} ) {
				push @args, 'SPAM_COMMAND="' . $conf->{'qmailadmin_spam_command'} . '"';
			};
		};
		
		$freebsd->port_install("qmailadmin", "mail", undef, undef, join(",", @args), 1);

		if ( $conf->{'qmailadmin_install_as_root'} ) { 
			my $gid = getgrnam("vchkpw");
			chown(0, $gid, "/usr/local/$cgi/qmailadmin");
		};
	} 
	else 
	{
		my $conf_args;

		if ( -x "$cgi/qmailadmin" ) {
			return 0 unless $utility->yes_or_no("qmailadmin is installed, do you want to reinstall?", 60);
		};

		if ( defined $conf->{'qmailadmin_domain_autofill'} ) 
		{
			unless ( $conf->{'qmailadmin_domain_autofill'} == 0 ) { 
				$conf_args = " --enable-domain-autofill=Y";
				print "domain autofill: yes\n";
			};
		} else {
			$conf_args = " --enable-domain-autofill=Y";
			print "domain autofill: yes\n";
		};

		unless ( defined $conf->{'qmailadmin_spam_option'} ) {
			if ( $utility->yes_or_no("\nDo you want spam options? ") ) 
			{ 
				$conf_args .= " --enable-modify-spam=Y" .
				" --enable-spam-command=\"" . $conf->{'qmailadmin_spam_command'} . "\"";
			};
		} else {
			if ( $conf->{'qmailadmin_spam_option'} ) {
				$conf_args .= " --enable-modify-spam=Y" .
				" --enable-spam-command=\"" . $conf->{'qmailadmin_spam_command'} . "\"";
				print "modify spam: yes\n";
			};
		};

		unless ( defined $conf->{'qmailadmin_modify_quotas'} ) {
			if ( $utility->yes_or_no("\nDo you want user quotas to be modifiable? ") ) 
			{ $conf_args .= " --enable-modify-quota=y"; };
		} else {
			if ( $conf->{'qmailadmin_modify_quotas'} ) {
				$conf_args .= " --enable-modify-quota=y";
				print "modify quotas: yes\n";
			};
		};
	
		unless ( defined $conf->{'qmailadmin_install_as_root'} ) 
		{
			if ( $utility->yes_or_no("\nShould qmailadmin be installed as root? ") ) 
			{ $conf_args .= " --enable-vpopuser=root"; };
		} else {
			if ( $conf->{'qmailadmin_install_as_root'} ) {
				$conf_args .= " --enable-vpopuser=root";
				print "install as root: yes\n";
			};
		};

		$conf_args .= " --enable-htmldir=" . $docroot . "/qmailadmin";
		$conf_args .= " --enable-imagedir=" . $docroot . "/qmailadmin/images";
		$conf_args .= " --enable-imageurl=/qmailadmin/images";
		$conf_args .= " --enable-cgibindir=" . $cgi;

		unless ( defined $conf->{'qmailadmin_help_links'} ) 
		{
			$help = $utility->yes_or_no("Would you like help links on the qmailadmin login page? ");
			$conf_args .= " --enable-help=y" if $help;
		} else {
			if ( $conf->{'qmailadmin_help_links'} ) {
				$conf_args .= " --enable-help=y"; $help = 1;
			};
		};

		if ( $os eq "darwin" ) 
		{
			$conf_args .= " --build=ppc";
			my $vpopdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";
			$utility->syscmd("ranlib $vpopdir/lib/libvpopmail.a");
		};

		my $make = $utility->find_the_bin("gmake");
		unless ( -x $make ) { $make = $utility->find_the_bin("make"); };

		$utility->install_from_source($conf, 
			{
				package=> $package, 
				site   => $site, 
				url    => $url, 
				targets=> ["./configure " . $conf_args, "$make", "$make install-strip"],
				debug  => $debug,
				source_sub_dir=> 'mail',
			} 
		);
	};

	if ($help) 
	{
		my $helpdir;
		if ( $package eq "ports" || $conf->{'install_qmailadmin'} eq "port" ) 
		{
			$helpdir = "/usr/local/$docroot/qmailadmin/images/help";
		} else {
			$helpdir = "$docroot/qmailadmin/images/help";
		};

		if ( -d $helpdir ) 
		{
			print "qmailadmin: help files already installed $helpdir.\n";
		} 
		else 
		{
			print "qmailadmin: Installing help files\n";
			$utility->chdir_source_dir($src);
			unless ( -e "$helpfile.tar.gz" ) { $utility->get_file("$site/qmailadmin/$helpfile.tar.gz"); };
			if ( -e "$helpfile.tar.gz" ) 
			{
				$utility->archive_expand("$helpfile.tar.gz", $debug);
				move("$helpfile", "$helpdir") or carp "FAILED: Couldn't move $helpfile to $helpdir";
			} 
			else {
				carp "qmailadmin: FAILED: help files couldn't be downloaded!\n";
			};
		};
	};

	if ( $conf->{'qmailadmin_return_to_mailhome'} )
	{
		my $file  = "/usr/local/share/qmailadmin/html/show_login.html";
		return unless ( -e $file );

		print "qmailadmin: Adjusting login to return to Mail Center page\n";

		my $tmp   = "/tmp/show_login.html";
		$utility->file_write($tmp, '<META http-equiv="refresh" content="0;URL=https://'. $conf->{'toaster_hostname'} . '/">');
		$utility->syscmd("cat $file >> $tmp");
		move($tmp, $file) or carp "qmailadmin: FAILURE: couldn't move $tmp to $file: $!";

# here's another way:
#  <body onload="redirect();">
#  <script language="Javascript" type="text/javascript">
#    <!--
#      function redirect () { setTimeout("go_now()",1); }
#      function go_now () { window.location.href = "https://jail10.cadillac.net/"; }
#    //-->
#  </script>

	};

	return 1;
};


=head2 qmail_scanner

Installs qmail_scanner and configures it for use.

  $setup->qmail_scanner($conf, $debug);

=cut


sub qmail_scanner($)
{
	my ($self, $conf) = @_;


	if ( $conf->{'install_qmailscanner'} ) 
	{
		if ( ! $Config{d_dosuid} && ! $conf->{'qmail_scanner_suid_wrapper'} ) {
			croak "qmail_scanner requires that perl be installed with setuid enabled or with the suid C wrapper. Please enable one or the other.\n";
		};
	} else {
		print "skipping qmailscanner install. It's not enabled in toaster-watcher.conf.\n";
		return 0;
	};


	my $debug    = $conf->{'debug'};
	my $ver      = $conf->{'install_qmailscanner'};
	my $src      = $conf->{'toaster_src_dir'}  || "/usr/local/src";
	my $package  = "qmail-scanner-$ver";
	my $site     = "http://" . $conf->{'toaster_sf_mirror'} . "/qmail-scanner";

	unless ($ver) {
		print "\n\nFATAL: qmail_scanner is disabled in toaster-watcher.conf.\n";
		return 0;
	};

	if ( $os eq "freebsd" ) 
	{
		$freebsd->port_install ("p5-Time-HiRes", "devel" );
		$freebsd->port_install ("tnef", "converters");
		$freebsd->port_install("maildrop", "mail" , undef, undef, undef, 1 );
#		 should we be using this?
#		$freebsd->port_install("qmail-scanner", "mail" , undef, undef, undef, 1 );
	};

	# verify that setuid perl is installed
	# add 'lang/perl5.8'		=> 'ENABLE_SUIDPERL=yes',
	# to /usr/local/etc/pkgtools.conf (MAKE_ARGS)
	# or make port with -DENABLE_SUIDPERL

	if ( -e "/var/qmail/bin/qmail-scanner-queue.pl") {
		print "QmailScanner is already Installed!\n";
		unless ( $utility->yes_or_no("Would you like to reinstall it?", 60) ) { return };
	};

	if ( -d "$src/mail/filter" ) 
	{
		$utility->chdir_source_dir("$src/mail/filter");
	} else 
	{
		$utility->syscmd("mkdir -p $src/mail/filter");
		$utility->chdir_source_dir("$src/mail/filter");
	};

	unless ( -e "$package.tgz" ) 
	{
		$utility->get_file("$site/$package.tgz");
		unless ( -e "$package.tgz" ) {
			croak "qmail_scanner FAILED: couldn't fetch $package.tgz\n";
		};
	};

	if ( -d $package )
	{
		unless ( $utility->source_warning($package, 1, $src) )
		{ 
			carp "qmail_scanner: OK, skipping install.\n"; 
			return 0;
		};
	};

	$utility->archive_expand("$package.tgz", $debug);
	chdir($package) or croak "qmail_scanner: couldn't chdir $package.\n";

	my $user = $conf->{'qmail_scanner_user'}; $user ||= "qscand";

	unless ( getpwuid($user) ) {
		$perl->module_load( {module=>"Mail::Toaster::Passwd"} );
		my $passwd = Mail::Toaster::Passwd->new();

		$passwd->creategroup($user);
		$passwd->user_add( {user=>$user, debug=>1} );
	};

	my $confcmd = "./configure ";

	$confcmd .= "--qs-user $user " if ( $user ne "qscand" );

	unless ( defined $conf->{'qmail_scanner_logging'} ) 
	{
		if ( $utility->yes_or_no("Do you want QS logging enabled?") )
			{ $confcmd .= "--log-details syslog " };
	} 
	else 
	{
		if ( $conf->{'qmail_scanner_logging'} ) 
		{
			$confcmd .= "--log-details syslog ";
			print "logging: yes\n";
		};
	};

	unless ( defined $conf->{'qmail_scanner_debugging'} ) 
	{
		unless ( $utility->yes_or_no("Do you want QS debugging enabled?") )
			{ $confcmd .= "--debug no " };
	} 
	else 
	{
		unless ( $conf->{'qmail_scanner_debugging'} ) 
		{
			$confcmd .= "--debug no ";
			print "debugging: no\n";
		};
	};

	my $email = $conf->{'qmail_scanner_postmaster'};
	unless ( $email ) 
	{
		$email = $conf->{'toaster_admin_email'};
		unless ($email) {
			$email = $utility->answer("What is the email address for postmaster mail?");
		};
	} 
	else 
	{
		if ($email eq "postmaster\@example.com" ) 
		{
			if ( $conf->{'toaster_admin_email'} ne "postmaster\@example.com" )
			{
				$email = $conf->{'toaster_admin_email'};
			} else {
				$email = $utility->answer("What is the email address for postmaster mail?");
			};
		};
	};

	my ($u, $d) = $email =~ /^(.*)@(.*)$/;
	$confcmd .= "--admin $u --domain $d ";

	if ( $conf->{'qmail_scanner_notify'} ) {
		$confcmd .= '--notify "' . $conf->{'qmail_scanner_notify'} . '" ';
	};

	if ( $conf->{'qmail_scanner_localdomains'} ) 
	{
		$confcmd .= '--local-domains "' . $conf->{'qmail_scanner_localdomains'} . '" ';
	};

	if ( $ver gt 1.20 ) {
		if ( $conf->{'qmail_scanner_block_pass_zips'} ) {
			$confcmd .= '--block-password-protected yes ';
		};
	};

	if ( $ver gt 1.21 ) {
		if ( $conf->{'qmail_scanner_eol_disable'} ) 
		{
			$confcmd .= '--ignore-eol-check ';
		};
	};

	if ( $conf->{'qmail_scanner_fix_mime'} ) 
	{
		$confcmd .= '--fix-mime ' . $conf->{'qmail_scanner_fix_mime'} . ' ';
	};

	if ( $conf->{'qmail_dir'} && $conf->{'qmail_dir'} ne "/var/qmail" ) 
	{
		$confcmd .= "--qmaildir " . $conf->{'qmail_dir'} . " ";
		$confcmd .= "--bindir " . $conf->{'qmail_dir'} . "/bin ";
	};

	my $tmp;

	unless ( $conf->{'qmail_scanner_scanners'} ) {
		$tmp = qmail_scanner_old_method($conf, $ver);
		print "Using Scanners: $tmp\n";
		$confcmd .= "$tmp ";
	} else {
		# remove any spaces
		print "Checking Scanners: " . $conf->{'qmail_scanner_scanners'} . "\n";
		$tmp = $conf->{'qmail_scanner_scanners'};   # get the list of scanners
		$tmp =~ s/\s+//;                            # clean out any spaces
		print "Using Scanners: $tmp\n";
		$confcmd .= "--scanners $tmp ";
	};

	print "OK, running qmail-scanner configure to test options.\n";
	$utility->syscmd( $confcmd );

	if ( $utility->yes_or_no("OK, ready to install it now?") ) 
		{ $utility->syscmd( $confcmd . " --install" ); };

	my $c_file = "/var/qmail/bin/qmail-scanner-queue";

	if ( $conf->{'qmail_scanner_suid_wrapper'} ) {
		chdir("contrib");
		$utility->syscmd("make");
		copy("qmail-scanner-queue", $c_file);
		chmod 04755, $c_file;
		my $uid = getpwnam($user);
		my $gid = getgrnam($user);
		chown($uid, $gid, $c_file);
		chmod 00755, "$c_file.pl";
	} else {
		chmod 04755, "$c_file.pl";
	};

	$self->qmail_scanner_config($conf);

	if ( $conf->{'install_qmailscanner_stats'} ) {
		$self->qs_stats($conf);
	};
}

=head2 qmail_scanner_config

prints out a note telling you how to enable qmail-scanner.

  $setup->qmail_scanner_config;

=cut

sub qmail_scanner_config
{
	my ($self, $conf) = @_;

	my $service = $conf->{'qmail_service'};

	# We want qmail-scanner to process emails so we add an ENV to the SMTP server:
	print "To enable qmail-scanner, see the instructions on the filtering page
of the web site: http://www.tnpi.biz/internet/mail/toaster/

";

};


sub qmail_scanner_old_method
{
	my ($conf, $ver) = @_;

	my ($verb, $clam, $spam, $fprot, $uvscan);

	my $confcmd = "--scanners ";

	if ( defined $conf->{'qmail_scanner_clamav'} ) {
		$clam = $conf->{'qmail_scanner_clamav'};
	} else {
		$clam = $utility->yes_or_no("Do you want ClamAV enabled?");
	};

	if ( defined $conf->{'qmail_scanner_spamassassin'} ) {
		$spam = $conf->{'qmail_scanner_spamassassin'};
	} else {
		$spam = $utility->yes_or_no("Do you want SpamAssassin enabled?");
	};

	if ( defined $conf->{'qmail_scanner_fprot'} ) {
		$fprot = $conf->{'qmail_scanner_fprot'};
	};

	if ( defined $conf->{'qmail_scanner_uvscan'} ) {
		$uvscan = $conf->{'qmail_scanner_uvscan'};
	};

	if ( $spam ) 
	{
		if ( defined $conf->{'qmail_scanner_spamass_verbose'} ) {
			$verb = $conf->{'qmail_scanner_spamass_verbose'};
		} else {
			$verb = $utility->yes_or_no("Do you want SA verbose logging (n)?");
		};
	};

	if ( $clam || $spam || $verb || $fprot || $uvscan ) 
	{
		my $first = 0;

		if ( $clam ) { 
			if ($ver eq "1.20") {
				$confcmd .= "clamscan,clamuko"; $first++; 
			} elsif ($ver eq "1.21") {
				$confcmd .= "clamdscan,clamscan"; $first++; 
			} else {
				$confcmd .= "clamscan"; $first++; 
			};
		};

		if ( $fprot ) { 
			if ( $first ) { $confcmd .= "," };
			$confcmd .= "fprot"; $first++; 
		};

		if ( $uvscan ) {
			if ( $first ) { $confcmd .= "," };
			$confcmd .= "uvscan"; $first++;
		};

		if ( $spam && $verb )
		{
			if ( $first ) { $confcmd .= "," };
			$confcmd .= "verbose_spamassassin";
		}
		elsif ( $spam ) 
		{
			if ( $first ) { $confcmd .= "," };
			$confcmd .= "fast_spamassassin"; 
		};
	} 
	else { croak "qmail_scanner: No scanners?"; };

	return $confcmd;
};
	
=head2 qmail_scanner_test

Send several test messages via qmail-scanner to test it. Sends a clean message, an attachment, a virus, and spam message.

  $setup->qmail_scanner_test($conf);

=cut


sub qmail_scanner_test
{
	my ($self, $conf) = @_;

	# test Qmail-Scanner
	unless ( $conf->{'install_qmailscanner'} ) 
	{
		print "qmail-scanner disabled, skipping test.\n";
		return 0;
	};

	print "testing qmail-scanner...";
	my $qdir = $conf->{'qmail_dir'}; $qdir ||= "/var/qmail";

	my $scan = "$qdir/bin/qmail-scanner-queue";
	if ( -x $scan ) {
		print "Qmail Scanner C wrapper was found at $scan, testing... \n";
		$ENV{"QMAILQUEUE"} = $scan;
		$toaster->email_send($conf, "clean");
		$toaster->email_send($conf, "attach");
		$toaster->email_send($conf, "virus");
		$toaster->email_send($conf, "clam");
		$toaster->email_send($conf, "spam");
	} 
	else 
	{
		$scan = "$qdir/bin/qmail-scanner-queue.pl";
		unless ( -x $scan ) {
			print "FAILURE: Qmail Scanner could not be found at $scan!\n";
			return 0;
		}
		else {
			print "Qmail Scanner was found at $scan, testing... \n";
			$ENV{"QMAILQUEUE"} = $scan;
			$toaster->email_send($conf, "clean");
			$toaster->email_send($conf, "attach");
			$toaster->email_send($conf, "virus");
			$toaster->email_send($conf, "clam");
			$toaster->email_send($conf, "spam");
		};
	};
}

=head2 qs_stats

Install qmail-scanner stats

  $setup->qs_stats($conf);

=cut

sub qs_stats($)
{
	my ($self, $conf) = @_;
	my ($line, @lines);

	my $debug    = $conf->{'debug'};
	my $ver      = $conf->{'install_qmailscanner_stats'}; $ver ||= "2.0.2";
	my $package  = "qss-$ver";
	my $site     = "http://" . $conf->{'toaster_sf_mirror'} . "/qss";
	my $htdocs   = $conf->{'toaster_http_docs'} || "/usr/local/www/data";

	unless ( -d "$htdocs/qss" ) {
		mkdir("$htdocs/qss", 0755) or croak "qs_stats: couldn't create $htdocs/qss: $!\n";
	};

	chdir "$htdocs/qss";
	unless ( -e "$package.tar.gz" ) 
	{
		$utility->get_file("$site/$package.tar.gz");
		unless ( -e "$package.tar.gz" ) {
			croak "qs_stats: FAILED: couldn't fetch $package.tar.gz\n";
		};
	} 
	else 
	{
		print "qs_stats: sources already downloaded!\n";
	};

	my $quarantinelog = "/var/spool/qmailscan/quarantine.log";

	unless ( -e "$htdocs/qss/index.php")
	{
		$utility->archive_expand("$package.tar.gz", $debug);
	
		if ( -d "/var/spool/qmailscan") {
			chmod 00771, "/var/spool/qmailscan";
		} 
		else { croak "I can't find qmail-scanner's quarantine!\n"; };

		if ( -e $quarantinelog ) {
			chmod 00664, $quarantinelog;
		} else {
			@lines = 'Fri, 12 Jan 2004 15:09:00 -0500	w.diep\@hetnet.nl	matt\@tnpi.biz	Advice  Worm.Gibe.F       clamuko: 0.67.';
			push @lines,'Fri, 12 Feb 2004 10:34:16 -0500	yykk62\@hotmail.com	mike\@example.net	Re: Your product	Worm.SomeFool.I	clamuko: 0.67. ';
			push @lines, 'Fri, 12 Mar 2004 15:06:04 -0500	w.diep\@hetnet.nl	matt\@tnpi.biz	Last Microsoft Critical Patch	Worm.Gibe.F	clamuko: 0.67.';
			$utility->file_write($quarantinelog, @lines);
			chmod 00664, $quarantinelog;
		};

		my $dos2unix = $utility->find_the_bin("dos2unix");
		unless ($dos2unix) {
			$freebsd->port_install("unix2dos", "converters");
			$dos2unix = $utility->find_the_bin("dos2unix");
		};
	
		chdir "$htdocs/qss";
		$utility->syscmd("$dos2unix \*.php");

		my $file = "config.php";
		@lines = $utility->file_read($file);
		foreach $line ( @lines ) 
		{
			if ( $line =~ /logFile/ ) {
				$line = '$config["logFile"] = "/var/spool/qmailscan/quarantine.log";';
			};
			if ( $line =~ /startYear/ ) {
				$line = '$config["startYear"]  = 2004;';
			};
		};
		$utility->file_write($file, @lines);

		$file = "getGraph.php";
		@lines = $utility->file_read($file);
		foreach $line ( @lines ) 
		{
			if ( $line =~ /^\$data = explode/ ) {
				$line = '$data = explode(",",rawurldecode($_GET[\'data\']));';
			};
			if ( $line =~ /^\$t = explode/ ) {
				$line = '$t = explode(",",rawurldecode($_GET[\'t\']));';
			};
		};
		$utility->file_write($file, @lines);

		$file = "getGraph1.php";
		@lines = $utility->file_read($file);
		foreach $line ( @lines ) 
		{
			if ( $line =~ /^\$points = explode/ ) {
				$line = '$points = explode(",",$_GET[\'data\']);';
			};
			if ( $line =~ /^\$config = array/ ) {
				$line = '$config = array("startHGrad" => $_GET[\'s\'], "minInter" => 2, "maxInter" => 20, "minColsWidth" => 15, "imageHeight" => 200, "imageWidth" => 500, "startCount" => 0, "stopCount" => $stopCount, "maxGrad" => 10);';
			};
			if ( $line =~ /^"imageWidth/ ) { $line = ""; };
		};
		$utility->file_write($file, @lines);

		$file = "index.php";
		@lines = $utility->file_read($file);
		foreach $line ( @lines ) 
		{
			if ( $line =~ /^\s+\$date = strtotime/ ) {
				$line = 'if ( eregi("(^[0-9]+)", $val[0]) ) { $date = explode("/",$val[0]); $dateT = $date[0]; $date[0] = $date[1]; $date[1] = $dateT; $date = strtotime(implode("/",$date)); } else { $date = strtotime ($val[0]); }; ';
			};
			if ( $line =~ /^\s+\$date/ ) {
				$line = '';
			};
		};
		$utility->file_write($file, @lines);
	} 
	else 
	{
		print "qs_stats: already installed, skipping.\n";
	};

	unless ( -s $quarantinelog ) {
		@lines = 'Fri, 12 Jan 2004 15:09:00 -0500	w.diep\@hetnet.nl	matt\@tnpi.biz	Advice  Worm.Gibe.F	clamuko: 0.67.';
		push @lines,'Fri, 12 Feb 2004 10:34:16 -0500	yykk62\@hotmail.com	mike\@example.net	Re: Your product	Worm.SomeFool.I	clamuko: 0.67. ';
		push @lines, 'Fri, 12 Mar 2004 15:06:04 -0500	w.diep\@hetnet.nl	matt\@tnpi.biz	Last Microsoft Critical Patch	Worm.Gibe.F	clamuko: 0.67.';
		$utility->file_write($quarantinelog, @lines);
	};
};


=head2 razor

Install Vipul's Razor2

  $setup->razor($conf);

=cut

sub razor
{
	my ($self, $conf) = @_;

	unless ( $conf->{'install_razor'} ) 
	{
		print "Razor install disabled, skipping.\n";
		return 0;
	};

	if ( $conf->{'install_razor'} eq "port" ) {
		if ( $os eq "freebsd" ) {
			$freebsd->port_install ("razor-agents", "mail", undef, undef, undef, 1);
		} 
		elsif ( $os eq "darwin") 
		{
			$darwin->port_install("razor");            # old ports tree, deprecated
			$darwin->port_install("p5-razor-agents");
		} 
	};

	$perl->module_load( {module=>"Digest::Nilsimsa"} );
	$perl->module_load( {module=>"Digest::SHA1"} );

	if ( -d "/etc/razor" ) {
		print "It appears you have razor installed, skipping manual build.\n";
		return 0;
	};

	if ( $utility->find_the_bin("razor-client") ) 
	{
		print "It appears you have razor installed, skipping manual build.\n";
	} 
	else 
	{
		my $ver = $conf->{'install_razor'};
		$ver = "2.80" if ($ver == 1 || $ver eq "port");

		$perl->module_install( { 
				module   => 'razor-agents-'.$ver, 
				archive  => 'razor-agents-'.$ver.'.tar.gz', 
				site     => 'http://umn.dl.sourceforge.net/sourceforge', 
				url=>'/razor',
			}, $conf 
		);
	};

	my $client = $utility->find_the_bin("razor-client");
	my $admin  = $utility->find_the_bin("razor-admin");

	print "razor: beginning configuration.\n";

	if ( -x $client && ! -x $admin ) 
	{
		$utility->syscmd($client);
	};

	unless ( -d "/etc/razor" )
	{
		unless ( -x $admin ) 
		{
			print "FAILED: couldn't find $admin!\n";
		};

		$utility->syscmd("$admin -home=/etc/razor -create -d");
		$utility->syscmd("$admin -home=/etc/razor -register -d");

		my $file = "/etc/razor/razor-agent.conf";
		if ( -e $file ) {
		my @lines = $utility->file_read($file);
			foreach my $line ( @lines ) 
			{
				if ( $line =~ /^logfile/ ) {
					$line = 'logfile                = /var/log/razor-agent.log';
				};
			};
			$utility->file_write($file, @lines);
		};

		$file = "/etc/newsyslog.conf";
		if ( -e $file ) {
			unless ( `grep razor-agent $file` )
			{
				$utility->file_append($file, ["/var/log/razor-agent.log	600	5	1000 *	Z"]);
			};
		};
	};

	print "razor: configuration completed.\n";
}


=head2 ripmime

Installs ripmime

  $setup->ripmime($conf);

=cut

sub ripmime
{
	my ($self, $conf) = @_;

	unless ($conf->{'install_ripmime'}) {
		print "ripmime install not selected.\n";
	} else {
		print "rimime: installing...\n";
	};

	my $ver = $conf->{'install_ripmime'};

	if ( $ver eq "port" || $ver eq "1" ) 
	{
		if ( $utility->find_the_bin("ripmime") ) {
			print "ripmime: is already installed...done.\n\n";
			return 1;
		};

		if ( $os eq "freebsd" )
		{
			$freebsd->port_install("ripmime", "mail" );
			$freebsd->is_port_installed("ripmime") ? return 1 : return 0;
		} 
		elsif ( $os eq "darwin" ) 
		{
			$darwin->port_install("ripmime");
		};

		if ( $utility->find_the_bin("ripmime") ) {
			print "ripmime: ripmime has been installed successfully.\n";
			return 0;
		};

		$ver = "1.4.0.6";
	} else {
		$ver = "1.4.0.6";
	};

	if ( my $ripmime = $utility->find_the_bin("ripmime") ) {
		my $installed = `$ripmime -V`;
		($installed) = $installed =~ /v(.*) - /;

		if ( $ver eq $installed ) {
			print "ripmime: the selected version ($ver) is already installed!\n";
			return 0;
		};
	};

	my $vals = { package => "ripmime-$ver",
			site    => 'http://www.pldaniels.com',
			url     => '/ripmime',
			targets => ['make', 'make install'],
			patches => '',
			bintest => 'ripmime',
			debug   => 1,
			source_sub_dir=>'mail',
	};

	$utility->install_from_source($conf, $vals);
};

sub rrdtool
{
	my ($self, $conf, $fatal) = @_;

	if ( $os eq "freebsd" )
	{
		$freebsd->port_install("rrdtool", "net", undef, undef, undef, $fatal );
		#$freebsd->port_install("rrdtool10", "net", undef, "rrdtool-1.0", undef, $fatal );
		$freebsd->is_port_installed("rrdtool") ? return 1 : return 0;
	}
	elsif ( $os eq "darwin" ) 
	{
		$darwin->port_install("rrdtool") 
	} 

	return 1 if ( -x $utility->find_the_bin("rrdtool"));

	my $ver = "1.0.49";

	my $vals = { package => "rrdtool-$ver",
			site    => 'http://people.ee.ethz.ch',
			url     => '/~oetiker/webtools/rrdtool/pub',
			targets => ['./configure', 'make', 'make install'],
			patches => '',
			bintest => 'rrdtool',
			debug   => 1,
	};

	$utility->install_from_source($conf, $vals);
};



=head2 rrdutil

Checks for and installs any missing programs upon which RRDutil depends (rrdtool, net-snmp, Net::SNMP, Time::Date) and then downloads and installs the latest version of RRDutil. 

If upgrading, it is wise to check for differences in your installed rrdutil.conf and the latest rrdutil.conf-dist included in the RRDutil distribution.

  $setup->rrdutil;

=cut

sub rrdutil($)
{
	my ($self, $conf) = @_;

	my $debug = $conf->{'debug'};
	my $ver   = $conf->{'install_net_snmpd'} || 4;

	unless ( $conf->{'install_rrdutil'} ) { 
		print "install_rrdutil is not set in toaster-watcher.conf! Skipping install.\n";
		return 0; 
	};

	my $rrdtool = $utility->find_the_bin("rrdtool");
	$self->rrdtool($conf, 1) unless -x $rrdtool;
	$rrdtool = $utility->find_the_bin("rrdtool");

	unless ( -x $rrdtool ) {
		print "FAILED rrdtool install.\n";
		exit 0;
	};

	my $snmpdir;
	if ( $os eq "darwin" ) { $snmpdir = "/usr/share/snmp"        }
	else                   { $snmpdir = "/usr/local/share/snmp"  };

	# a file is getting installed here causing an error. This'll check for and fix it.
	if ( -e $snmpdir ) {
		unlink $snmpdir unless ( -d $snmpdir );
	};

	if ( $os eq "freebsd" ) 
	{
		if ( $ver == 4 ) 
		{
			if ( $conf->{'package_install_method'} eq "packages" )
			{
				$freebsd->package_install("net-snmp", "ucd-snmp-4"); 
			};

			if ( -d "/usr/ports/net-mgmt" ) 
			{
				$freebsd->port_install("net-snmp4",   "net-mgmt",  undef, "ucd-snmp-4", undef, 1 );
				$freebsd->port_install("p5-Net-SNMP", "net-mgmt",  undef, undef, undef, 1 );
			} 
			else 
			{
				unless ( -d "/usr/ports/net/net-snmp" ) 
				{
					carp "FAILURE: the port directory for net-snmp4 is missing. If your ports tree is up to date, you might want to check your ports supfile and make sure net-mgmt is listed in there!\n\n";
				} 
				else 
				{
					$freebsd->port_install("net-snmp",    "net",  undef, undef, undef, 1 );
					$freebsd->port_install("p5-Net-SNMP", "net",  undef, undef, undef, 1 );
				};
			};
		} 
		elsif ( $ver == 5 ) 
		{
			if ( $conf->{'package_install_method'} eq "packages" )
			{
				$freebsd->package_install("net-snmp"); 
			};

			if ( -d "/usr/ports/net-mgmt" ) 
			{
				$freebsd->port_install("net-snmp",    "net-mgmt",  undef, undef, undef, 1 );
				$freebsd->port_install("p5-Net-SNMP", "net-mgmt",  undef, undef, undef, 1 );
			} 
			else 
			{
				$freebsd->port_install("net-snmp",    "net",  undef, undef, undef, 1 );
				$freebsd->port_install("p5-Net-SNMP", "net",  undef, undef, undef, 1 );
			};
		} 
		else 
		{
			print "\n\nrrdutil: WARNING:  not installing snmpd! RRDutil isn't going to work very well without it!\n\n";
			sleep 5;
		};

		$freebsd->port_install("p5-TimeDate", "devel",     undef, undef, undef, 1 );
	} 
	elsif ( $os eq "darwin") 
	{
		$darwin->port_install("net-snmp");
	};

	my $perlbin = $utility->find_the_bin("perl");

	my  @targets = ("$perlbin Makefile.PL", "make", "make install", "make cgi");
	push @targets, "make test" if $debug;

	if ( -e "/usr/local/etc/rrdutil.conf") { push @targets, "make conf"    }
	else                                   { push @targets, "make newconf" };

	#push @targets, "make cgi";

	my $snmpconf = "$snmpdir/snmpd.conf";
	unless ( -e $snmpconf ) { push @targets, "make snmp"; };

	my $vals = {
		module   => 'RRDutil',
		archive  => 'RRDutil.tar.gz',
		url      => '/internet/manage/rrdutil',
		targets  => \@targets,
	};

	eval { require Mail::Toaster::Perl }; my $perl = Mail::Toaster::Perl->new;

	$perl->module_install($vals);

	if ( $os eq "freebsd") 
	{
		my $start = "start";
		if ( $ver == 5 ) { $start = "restart"; };

		unless ( `grep snmpd_enable /etc/rc.conf` )
		{
			$freebsd->rc_dot_conf_check("snmpd_enable", "snmpd_enable=\"YES\"");
			print "\n\nNOTICE:  I added snmpd_enable=\"YES\" to /etc/rc.conf!\n\n";
		};
		$utility->syscmd("/usr/local/etc/rc.d/snmpd.sh $start");
	};
};

sub rrdutil_test
{
	my ($self, $conf) = @_;

	my $snmpdir;
	if ( $os eq "darwin" ) { $snmpdir = "/usr/share/snmp"        }
	else                   { $snmpdir = "/usr/local/share/snmp"  };

	unless ( $conf->{'install_net_snmpd'} ) {
		$self->_formatted("rrdutil_test: SNMP is not selected, skipping", "FAILED");
		return 0;
	};

	unless ( $conf->{'install_rrdutil'} ) {
		$self->_formatted("rrdutil_test: rrdutil not selected, skipping", "FAILED");
		return 0;
	};

	if ( -e "$snmpdir/snmpd.conf" ) {
		$self->_formatted("rrdutil_test: checking snmpd.conf", "ok");
	}
	else {
		$self->_formatted("rrdutil_test: checking snmpd.conf", "FAILED");
		print "\n\nYou need to install snmpd.conf. You can do this in one of three ways:

  1. run \"make snmp\" in the rrdutil source directory
  2. copy the snmpd.conf file from the rrdutil/contrib to /usr/local/share/snmp/snmpd.conf
  3. run snmpconf and manually configure.

The latter should only be done by those quite familiar with SNMP, and then you should reference the contrib/snmpd.conf file to see the OIDs that need to be defined for RRDutil to work properly.";
	};

	if ( -e "/usr/local/etc/rrdutil.conf" ) {
		$self->_formatted("rrdutil_test: checking rrdutil.conf", "ok");
	} 
	else {
		$self->_formatted("rrdutil_test: checking rrdutil.conf", "FAILED");
		"\nWhere's your rrdutil.conf file? It should be in /usr/local/etc. You can install one by running 'make newconf' in the RRDutil source directory.\n";
	}
}


=head2 simscan

Install simscan from Inter7.

  $setup->simscan($conf);

See toaster-watcher.conf to see how these settings affect the build and operations of simscan.

=cut

sub simscan
{
	my ($self, $conf) = @_;
	my ($bin);

	unless ( $conf->{'install_simscan'} )
	{
		print "skipping. Simscan install not enabled in toaster-watcher.conf.\n";
		return 0;
	};

	unless ( $utility->is_hashref($conf) ) 
	{
		my ($package, $filename, $line) = caller;
		carp "WARNING: $filename passed install_from_source an invalid argument \n";
		return 0;
	};

	my $user     = $conf->{'simscan_user'}; $user ||= "clamav";
	my $reje     = $conf->{'simscan_spam_hits_reject'};
	my $quarant  = $conf->{'simscan_quarantine'};
	my $qdir     = $conf->{'qmail_dir'};
	my $ver      = $conf->{'install_simscan'};
	my $args     = $conf->{'simscan_spamc_args'};
	my $custom   = $conf->{'simscan_custom_smtp_reject'};

	if ( -x "$qdir/bin/simscan" ) {
		return 0 unless $utility->yes_or_no("simscan is already installed, do you want to reinstall?", 60);
	};

	$self->ripmime($conf) if $conf->{'simscan_ripmime'};

	my $confcmd = "./configure ";
	$confcmd .= "--enable-user=$user ";
	if ( is_newer( "1.0.7", $ver) ) # added in 1.0.8
	{  
		if ( $conf->{'simscan_ripmime'} ) 
		{
			$bin = $utility->find_the_bin("ripmime");
			unless (-x $bin) { croak "couldn't find $bin, install ripmime!\n" };
			$confcmd .= "--enable-ripmime=$bin ";
		} else {
			$confcmd .= "--disable-ripmime ";   
		}
	} else {
		print "simscan: ripmime doesn't work with simcan 1.0.7 and older and you have selected $ver!\n";
	};

	if ($conf->{'simscan_clamav'} ) 
	{
		$bin = $utility->find_the_bin("clamdscan"); 
		unless (-x $bin) { croak "couldn't find $bin, install ClamAV!\n" };
		$confcmd .= "--enable-clamdscan=$bin ";

		if ( -d "/var/db/clamav" ) {
			$confcmd .= "--enable-clamavdb-path=/var/db/clamav ";
		} elsif ( -d "/usr/local/share/clamav") {
			$confcmd .= "--enable-clamavdb-path=/usr/local/share/clamav ";
		} elsif ( -d "/opt/local/share/clamav") {
			$confcmd .= "--enable-clamavdb-path=/opt/local/share/clamav ";
		} else {
			croak "clamav support is specified but I can't find the ClamAV db path!";
		};

		$bin = $utility->find_the_bin("sigtool"); 
		unless (-x $bin) { croak "couldn't find $bin, install ClamAV!\n" };
		$confcmd .= "--enable-sigtool-path=$bin ";
	};

	if ($conf->{'simscan_spamassassin'}) 
	{
		my $spamc = $utility->find_the_bin("spamc");
		$confcmd .= "--enable-spam=y --enable-spamc-user=y --enable-spamc=$spamc ";
		if ($conf->{'simscan_received'} ) {
			$bin = $utility->find_the_bin("spamassassin");
			unless (-x $bin) { croak "couldn't find $bin, install SpamAssassin!\n" };
			$confcmd .= "--enable-spamassassin-path=$bin " 
		};
	};

	$confcmd .= "--enable-received=y " if $conf->{'simscan_received'};
	$confcmd .= "--enable-spam-hits=$reje " if ($reje);
	$confcmd .= "--enable-spamc-args=$args " if ($args);
	$confcmd .= "--enable-attach=y " if $conf->{'simscan_block_attachments'};
	$confcmd .= "--enable-qmaildir=$qdir " if $qdir;
	$confcmd .= "--enable-qmail-queue=$qdir/bin/qmail-queue " if $qdir;
	$confcmd .= "--enable-per-domain=y " if $conf->{'simscan_per_domain'};
	$confcmd .= "--enable-custom-smtp-reject=y " if ($custom);
	$confcmd .= "--enable-spam-passthru=y " if ($conf->{'simscan_spam_passthru'});
	
	if ( $conf->{'simscan_regex_scanner'} )
	{
		if ($os eq "freebsd") {
			$freebsd->port_install("pcre", "devel");
		} else {
			print "\n\nNOTICE: Be sure to install pcre!!\n\n";
		};
		$confcmd .= "--enable-regex=y " 
	};

	if ( $quarant && -d $quarant ) { 
		$confcmd .= "--enable-quarantinedir=$quarant ";
	};

	print "configure: $confcmd\n";

	my $vals = { package => "simscan-$ver",
			site    => 'http://www.inter7.com',
			url     => '/simscan',
#			targets => [$confcmd, 'make'],   # use this for testing
			targets => [$confcmd, 'make', 'make install-strip'],
			patches => '',
			bintest => '/var/qmail/bin/simscan',
			debug   => 1,
			source_sub_dir => 'mail',
	};

	$utility->install_from_source($conf, $vals);

	$self->simscan_conf($conf);
};

=head2 simscan_conf

Build the simcontrol and ssattach config files based on toaster-watcher.conf settings.

=cut

sub simscan_conf
{
	my ($self, $conf) = @_;
	my ($file, @lines);

	my $user = $conf->{'simscan_user'}; $user ||= "clamav";
	my $reje = $conf->{'simscan_spam_hits_reject'};

	my $group = $conf->{'smtpd_run_as_group'}; $group ||= "vchkpw";
	my $uid  = getpwnam($user);
	my $gid  = getgrnam($group);
	chown($uid, $gid, "/var/qmail/simscan") or carp "ERROR: chown /var/qmail/simscan: $!\n";

#	if ( $conf->{'simscan_per_domain'} ) {
#		$file = "/var/qmail/control/simcontrol";

	my @attach;
	if ( $conf->{'simscan_block_attachments'} ) 
	{
		$file = "/var/qmail/control/ssattach";
		foreach ( split(/,/, $conf->{'simscan_block_types'} ) ) {
			push @attach, ".$_";
		};
		$utility->file_write($file, @attach);
	};

	$file = "/var/qmail/control/simcontrol";
	unless ( -e $file ) {
		my @opts;
		$conf->{'simscan_clamav'}       ? push @opts, "clam=yes" : push @opts, "clam=no";
		$conf->{'simscan_spamassassin'} ? push @opts, "spam=yes" : push @opts, "spam=no";
		$conf->{'simscan_trophie'}      ? push @opts, "trophie=yes" : push @opts, "trophie=no";
		$reje                           ? push @opts, "spam_hits=$reje" : print "no reject.\n";
		if (@attach > 0) {
			my $line = "attach="; my $first = shift @attach; $line .= "$first";
			foreach (@attach) { $line .= ":$_"; };
			push @opts, $line;
		};

		@lines = "#postmaster\@example.com:" . join(",", @opts);
		push @lines, "#example.com:" . join(",", @opts);
		push @lines, "#";
		push @lines, ":" . join(",", @opts);
		if ( -e $file ) {
			$utility->file_write("$file.new", @lines);
			print "\nNOTICE: simcontrol written to $file.new. You need to review and install it!\n";
		} else {
			$utility->file_write($file, @lines);
		};
	};

	if ( -x "/var/qmail/bin/simscanmk" ) { 
		$utility->syscmd("/var/qmail/bin/simscanmk");
		$utility->syscmd("/var/qmail/bin/simscanmk -g");
	}
}

=head2 simscan_test

Send some test messages to the mail admin using simscan as a message scanner.

    $setup->simscan_test($conf);

=cut

sub simscan_test($)
{
	my ($self, $conf) = @_;

	unless ( $utility->is_hashref($conf) ) {
		print "FATAL: the \$conf wasn't passed in correctly!\n";
		return 0;
	};

	my $qdir = $conf->{'qmail_dir'};

	if ( $conf->{'install_simscan'} ) {
		print "testing simscan...";
		my $scan = "$qdir/bin/simscan";
		unless ( -x $scan ) {
			print "FAILURE: Simscan could not be found at $scan!\n";
			return 0;
		}
		else {
			$ENV{"QMAILQUEUE"} = $scan;
			$toaster->email_send($conf, "clean");
			$toaster->email_send($conf, "attach");
			$toaster->email_send($conf, "virus");
			$toaster->email_send($conf, "clam");
			$toaster->email_send($conf, "spam");
		}
	}
}

sub spamassassin
{
	my ($self, $conf) = @_;
	
	if ( $os eq "freebsd" ) 
	{
		if ( $conf->{'install_spamassassin'} ) 
		{
			$freebsd->port_install ("p5-Mail-SPF-Query", "mail");
			$freebsd->port_install ("p5-Mail-SpamAssassin", "mail", undef, undef, "WITHOUT_SSL=1 BATCH=yes", 1);

			# the old port didn't install the spamd.sh file
			# new versions install sa-spamd.sh and require the rc.conf flag
			my $start = "/usr/local/etc/rc.d/spamd.sh";      # old location
			if ( ! -e $start && -e "$start-dist" ) {
				$utility->syscmd("cp $start-dist $start");
			}
			else {
				$start = "/usr/local/etc/rc.d/sa-spamd.sh";  # newer locations
			};

			my $flags = $conf->{'install_spamassassin_flags'} || "-d -v -q -x -r /var/run/spamd.pid";

			$freebsd->rc_dot_conf_check("spamd_enable", "spamd_enable=\"YES\"");
			$freebsd->rc_dot_conf_check("spamd_flags",  "spamd_flags=\"$flags\"");

			unless ( $utility->is_process_running("spamd") ) 
			{
				if ( -x $start ) 
				{
					print "Starting SpamAssassin...";
					$utility->syscmd("$start restart");
					print "done.\n";
				} 
				else { print "WARN: couldn't start SpamAssassin's spamd.\n"; };
			};
		};
	}
	elsif ( $os eq "darwin")
	{
		$perl->module_load( {module=>"Time::HiRes"} );
		$darwin->port_install("procmail") if $conf->{'install_procmail'};
		$darwin->port_install("unzip");

		if ( $conf->{'install_spamassassin'} ) {
			$darwin->port_install("p5-mail-audit");
			$darwin->port_install("p5-mail-spamassassin");
		};

		$darwin->port_install("bogofilter") if ( $conf->{'install_bogofilter'} );
	}
	else {
		$perl->module_load( {module=>"Time::HiRes"} );
		$perl->module_load( {module=>"Mail::Audit"} );
		$perl->module_load( {module=>"Mail::SpamAssassin"} ) if ( $conf->{'install_spamassassin'} );
		$self->maildrop($conf);
	};

	$self->spamassassin_sql($conf);
}

sub spamassassin_sql
{
	# set up the mysql database for use with SpamAssassin
	# http://svn.apache.org/repos/asf/spamassassin/branches/3.0/sql/README

	my ($self, $conf) = @_;

	unless ( $conf->{'install_spamassassin_sql'} ) {
		print "SpamAssasin MySQL integration not selected. skipping.\n";
		return 0;
	}

	if ( $os eq "freebsd" ) {
		if ( $freebsd->is_port_installed("p5-Mail-SpamAssassin") ) # is SpamAssassin installed
		{   
			print "SpamAssassin is installed, setting up MySQL databases\n";

			#create the database!

			my $user = $conf->{'install_spamassassin_dbuser'};
			my $pass = $conf->{'install_spamassassin_dbpass'};

			$perl->module_load( {module=>"Mail::Toaster::Mysql"} );
			my $mysql = Mail::Toaster::Mysql->new();
			my $dot = $mysql->parse_dot_file(".my.cnf", "[mysql]", 0);
			my ($dbh, $dsn, $drh) = $mysql->connect( $dot, 1);
			if ( $dbh )
			{
				my $query = "use spamassassin";
				my $sth = $mysql->query($dbh, $query, 1);
				if ( $sth->errstr ) 
				{
					print "vpopmail: oops, no spamassassin database.\n";
					print "vpopmail: creating MySQL spamassassin database.\n";
					$query = "CREATE DATABASE spamassassin";
					$sth = $mysql->query($dbh, $query);
					$query = "GRANT ALL PRIVILEGES ON spamassassin.* TO $user\@'localhost' IDENTIFIED BY '$pass'";
					$sth = $mysql->query($dbh, $query);
					$sth = $mysql->query($dbh, "flush privileges");
					$sth->finish;
				} else {
					print "spamassassin: spamassassin database exists!\n";
					$sth->finish;
				};
			} 

			my $mysqlbin = $utility->find_the_bin("mysql");
			my $sqldir = "/usr/local/share/doc/p5-Mail-SpamAssassin/sql";
			foreach ( qw/bayes_mysql.sql awl_mysql.sql userpref_mysql.sql/ ) {
				$utility->syscmd("$mysqlbin spamassassin < $sqldir/$_") if ( -f "$sqldir/$_" );
			};

			my $file = "/usr/local/etc/mail/spamassassin/sql.cf";
			unless ( -f $file ) {
				my @lines = "user_scores_dsn                 DBI:mysql:spamassassin:localhost";
				push @lines, "user_scores_sql_username        $conf->{'install_spamassassin_dbuser'}";
				push @lines, "user_scores_sql_password        $conf->{'install_spamassassin_dbpass'}";
				push @lines, "#user_scores_sql_table           userpref\n";
				push @lines, "bayes_store_module              Mail::SpamAssassin::BayesStore::SQL";
				push @lines, "bayes_sql_dsn                   DBI:mysql:spamassassin:localhost";
				push @lines, "bayes_sql_username              $conf->{'install_spamassassin_dbuser'}";
				push @lines, "bayes_sql_password              $conf->{'install_spamassassin_dbpass'}";
				push @lines, "#bayes_sql_override_username    someusername\n";
				push @lines, "auto_whitelist_factory       Mail::SpamAssassin::SQLBasedAddrList";
				push @lines, "user_awl_dsn                 DBI:mysql:spamassassin:localhost";
				push @lines, "user_awl_sql_username        $conf->{'install_spamassassin_dbuser'}";
				push @lines, "user_awl_sql_password        $conf->{'install_spamassassin_dbpass'}";
				push @lines, "user_awl_sql_table           awl";
				$utility->file_write($file, @lines);
			};
		} else {
			print "skipping MySQL SpamAssassin database setup, as SpamAssassin doesn't appear to be installed.\n";
		}
	} else {
		print "Sorry, automatic MySQL SpamAssassin setup is not available on $os yet. You must
do this process manually by locating the *_mysql.sql files that arrived with SpamAssassin. Run
each one like this:
	mysql spamassassin < awl_mysql.sql
	mysql spamassassin < bayes_mysql.sql
	mysql spamassassin < userpref_mysql.sql

Then configure SpamAssassin to use them by creating a sql.cf file in SpamAssassin's etc dir with
the following contents:

	user_scores_dsn                 DBI:mysql:spamassassin:localhost
	user_scores_sql_username        $conf->{'install_spamassassin_dbuser'}
	user_scores_sql_password        $conf->{'install_spamassassin_dbpass'}

	# default query
	#SELECT preference, value FROM _TABLE_ WHERE username = _USERNAME_ OR username = '\@GLOBAL' ORDER BY username ASC
	# global, then domain level
	#SELECT preference, value FROM _TABLE_ WHERE username = _USERNAME_ OR username = '\@GLOBAL' OR username = '@~'||_DOMAIN_ ORDER BY username ASC
	# global overrides user prefs
	#SELECT preference, value FROM _TABLE_ WHERE username = _USERNAME_ OR username = '\@GLOBAL' ORDER BY username DESC
	# from the SA SQL README
	#user_scores_sql_custom_query     SELECT preference, value FROM _TABLE_ WHERE username = _USERNAME_ OR username = '\$GLOBAL' OR username = CONCAT('%',_DOMAIN_) ORDER BY username ASC

	bayes_store_module              Mail::SpamAssassin::BayesStore::SQL
	bayes_sql_dsn                   DBI:mysql:spamassassin:localhost
	bayes_sql_username              $conf->{'install_spamassassin_dbuser'}
	bayes_sql_password              $conf->{'install_spamassassin_dbpass'}
	#bayes_sql_override_username    someusername

	auto_whitelist_factory       Mail::SpamAssassin::SQLBasedAddrList
	user_awl_dsn                 DBI:mysql:spamassassin:localhost
	user_awl_sql_username        $conf->{'install_spamassassin_dbuser'}
	user_awl_sql_password        $conf->{'install_spamassassin_dbpass'}
	user_awl_sql_table           awl
";
	};
}

sub smtp_test_auth
{
	my ($self, $conf) = @_;

	print "smtp_test_auth: checking Net::SMTP_auth .......................... ";
	$perl->module_load( {module=>"Net::SMTP_auth"} );
	print "ok\n";

	my $user = $conf->{'toaster_test_email'}      || 'test2@example.com';
	my $pass = $conf->{'toaster_test_email_pass'} || 'cHanGeMe';
	my $host = $conf->{'smtpd_listen_on_address'} || 'localhost';
	if ($host eq "system" || $host eq "qmail" || $host eq "all" ) { $host = "localhost" };

	print "getting a list of SMTP AUTH methods...";
	my $smtp = Net::SMTP_auth->new($host);
	unless  ( defined $smtp ) {
		$self->_formatted("smtp_test_auth: (couldn't connect to smtp port on $host!)", "FAILED");
	};

	my @auths = $smtp->auth_types();
	print "done.\n";
	$smtp->quit;

	# test each authentication method the server advertises
	foreach (@auths) 
	{
		$smtp = Net::SMTP_auth->new($host);
		if ( $smtp->auth($_, $user, $pass) ) {
			$smtp->mail( $conf->{'toaster_admin_email'} );
			$smtp->to('postmaster');
			$smtp->data();
			$smtp->datasend("To: postmaster\n");
			$smtp->datasend("\n");
			$smtp->datasend("A simple test message\n");
			$smtp->dataend();
	
			$smtp->quit;
			$self->_formatted("smtp_test_auth: sending with $_ authentication", "ok");
		} else {
			$self->_formatted("smtp_test_auth: sending with $_ authentication", "FAILED");
		}
	}
}


=head2 socklog

	$setup->socklog($conf, $ip);

If you need to use socklog, then you'll appreciate how nicely this configures it. :)  $ip is the IP address of the socklog master server.

=cut

sub socklog($$)
{
	my ($self, $conf, $ip) = @_;

	my $user  = $conf->{'qmail_log_user'};  $user  ||= "qmaill";
	my $group = $conf->{'qmail_log_group'}; $group ||= "qnofiles";

	my $uid = getpwnam($user);
	my $gid = getgrnam($group);

	my $log = $conf->{'qmail_log_base'};
	unless ( -d $log ) { $log = "/var/log/mail" };

	if ($os eq "freebsd") {
		$freebsd->port_install("socklog", "sysutils");
	} else {
		print "\n\nNOTICE: Be sure to install socklog!!\n\n";
	};
	socklog_qmail_control("send", $ip, $user,  undef, $log);
	socklog_qmail_control("smtp", $ip, $user,  undef, $log);
	socklog_qmail_control("pop3", $ip, $user,  undef, $log);

	unless ( -d $log ) 
	{ 
		mkdir($log, 0755) or croak "socklog: couldn't create $log: $!";
		chown($uid, $gid, $log) or croak "socklog: couldn't chown $log: $!";
	};

	foreach my $prot ( qw/ send smtp pop3 / )
	{
		unless ( -d "$log/$prot" ) {
			mkdir("$log/$prot", 0755) or croak "socklog: couldn't create $log/$prot: $!";
		};
		chown($uid, $gid, "$log/$prot") or croak "socklog: couldn't chown $log/$prot: $!";
	};
};


=head2 socklog_qmail_control

	socklog_qmail_control($service, $ip, $user, $supervisedir);

Builds a service/log/run file for use with socklog.

=cut

sub socklog_qmail_control 
{
	my ($serv, $ip, $user, $supervise, $log)  = @_;

	$ip        ||= "192.168.2.9";
	$user      ||= "qmaill";
	$supervise ||= "/var/qmail/supervise";
	$log       ||= "/var/log/mail";

	my $run_f   = "$supervise/$serv/log/run";

	unless ( -s $run_f ) 
	{
		print "socklog_qmail_control creating: $run_f...";
		open(RUN, ">$run_f") or croak "socklog_qmail_control: couldn't open for write: $!";
		print RUN "#!/bin/sh\n";
		print RUN "LOGDIR=$log\n";
		print RUN "LOGSERVERIP=$ip\n";
		print RUN "PORT=10116\n";
		print RUN "PATH=/var/qmail/bin:/usr/local/bin:/usr/bin:/bin\n";
		print RUN "export PATH\n";
		print RUN "exec setuidgid $user multilog t s4096 n20 \\\n";
		print RUN "  !\"tryto -pv tcpclient -v \$LOGSERVERIP \$PORT sh -c 'cat >&7'\" \\\n";
		print RUN "  \${LOGDIR}/$serv\n";
		close RUN;
		chmod 00755, $run_f or croak "socklog: couldn't chmod $run_f: $!";
		print "done.\n";
	} else {
		print "socklog_qmail_control skipping: $run_f exists!\n";
	};
};


=head2 config_spamassassin

	$setup->config_spamassassin();

Shows this URL: http://www.yrex.com/spam/spamconfig.php

=cut

sub config_spamassassin()
{
	print	"Visit http://www.yrex.com/spam/spamconfig.php \n";
};



=head2 squirrelmail

	$setup->squirrelmail

Installs Squirrelmail using FreeBSD ports. Adjusts the FreeBSD port by passing along WITH_APACHE2 if you have Apache2 selected in your toaster-watcher.conf.

=cut

sub squirrelmail($)
{
	my ($self, $conf) = @_;

	my $debug = $conf->{'debug'};

	my $ver = $conf->{'install_squirrelmail'};

	unless ( $ver ) {
		print "skipping SquirrelMail install because it's not enabled!\n";
		return 0;
	};

	if ( $os eq "freebsd" && $ver eq "port" )
	{
		if ( $freebsd->is_port_installed("squirrelmail") )
		{
			print "Squirrelmail is already installed, skipping!\n";
			return 0;
		};

		$freebsd->port_install("php4-mbstring", "converters", undef, undef, "BATCH=yes", 1);

		if ($conf->{'install_apache'} == 2) 
		{
			$freebsd->port_install("squirrelmail", "mail", undef, undef, "WITH_APACHE2=yes", 1);
		} 
		else 
		{ 
			$freebsd->port_install("squirrelmail", "mail", undef, undef, undef, 1); 
		};

		if ( -d "/usr/local/www/squirrelmail" )
		{
			unless ( -e "/usr/local/www/squirrelmail/config/config.php")
			{
				chdir("/usr/local/www/squirrelmail/config");
				print "squirrelmail: installing a default config.php";
	
				$utility->file_write("config.php", squirrelmail_config($conf) );
			};
		};

		if ( $freebsd->is_port_installed("squirrelmail") ) {
			$self->squirrelmail_mysql($conf);
			return 1;
		};
	};

	$ver = "1.4.6" if ( $ver eq "port" );

	print "squirrelmail: attempting to install from sources.\n";

	my $htdocs = $conf->{'toaster_http_docs'} || "/usr/local/www/data";
	my $srcdir = $conf->{'toaster_src_dir'}   || "/usr/local/src";
	$srcdir .= "/mail";

	unless ( -d $htdocs) {
		$htdocs = "/var/www/data" if ( -d "/var/www/data" );   # linux
		$htdocs = "/Library/Webserver/Documents" if (-d "/Library/Webserver/Documents"); # OS X
	};

	if ( -d "$htdocs/squirrelmail" ) {
		print "Squirrelmail is already installed, I won't install it again!\n";
		return 0;
	};

	$utility->install_from_source($conf, 
		{ 
			package=> "squirrelmail-$ver", 
			site   => "http://" . $conf->{'toaster_sf_mirror'},
			url    => "/squirrelmail", 
			targets=> ["mv $srcdir/squirrelmail-$ver $htdocs/squirrelmail"],
			source_sub_dir => 'mail',
			debug  => $debug,
		}
	);
	chdir("$htdocs/squirrelmail/config");
	print "squirrelmail: installing a default config.php";
	$utility->file_write("config.php", squirrelmail_config($conf) );

	$self->squirrelmail_mysql($conf);
};

sub squirrelmail_mysql($)
{
	my ($self, $conf) = @_;

	return 0 unless $conf->{'install_squirrelmail_sql'};

	if ( $os eq "freebsd") {
		$freebsd->port_install("pear-DB", "databases", undef, undef, undef, 1);
		print '\nHEY!  You need to add include_path = ".:/usr/local/share/pear" to php.ini.\n\n';
	};

	my $db   = "squirrelmail";
	my $user = "squirrel";
	my $pass = "secret";
	my $host = "localhost";

	$perl->module_load( {module=>"Mail::Toaster::Mysql"} );
	my $mysql = Mail::Toaster::Mysql->new();

	my $dot = $mysql->parse_dot_file(".my.cnf", "[mysql]", 0);
	my ($dbh, $dsn, $drh) = $mysql->connect( $dot, 1);

	if ( $dbh )
	{
		my $query = "use squirrelmail";
		my $sth = $mysql->query($dbh, $query, 1);
		if ( $sth->errstr ) 
		{
			print "squirrelmail: creating MySQL database for squirrelmail.\n";
			$query = "CREATE DATABASE squirrelmail";
			$sth = $mysql->query($dbh, $query);
			$query = "GRANT ALL PRIVILEGES ON $db.* TO $user\@'$host' IDENTIFIED BY '$pass'";
			$sth = $mysql->query($dbh, $query);
			$query = "CREATE TABLE squirrelmail.address ( owner varchar(128) DEFAULT '' NOT NULL,
nickname varchar(16) DEFAULT '' NOT NULL, firstname varchar(128) DEFAULT '' NOT NULL,
lastname varchar(128) DEFAULT '' NOT NULL, email varchar(128) DEFAULT '' NOT NULL,
label varchar(255), PRIMARY KEY (owner,nickname), KEY firstname (firstname,lastname));
";
			$sth = $mysql->query($dbh, $query);
			$query = "CREATE TABLE squirrelmail.global_abook ( owner varchar(128) DEFAULT '' NOT NULL,
nickname varchar(16) DEFAULT '' NOT NULL, firstname varchar(128) DEFAULT '' NOT NULL,
lastname varchar(128) DEFAULT '' NOT NULL, email varchar(128) DEFAULT '' NOT NULL,
label varchar(255), PRIMARY KEY (owner,nickname), KEY firstname (firstname,lastname));";

			$sth = $mysql->query($dbh, $query);
			$query = "CREATE TABLE squirrelmail.userprefs ( user varchar(128) DEFAULT '' NOT NULL,
prefkey varchar(64) DEFAULT '' NOT NULL, prefval BLOB DEFAULT '' NOT NULL, PRIMARY KEY (user,prefkey))";
			$sth = $mysql->query ($dbh, $query);
			$sth->finish;
		} else {
			print "squirrelmail: squirrelmail database already exists.\n";
			$sth->finish;
		};
	} 
	else
	{
		print <<EOSQUIRRELGRANT

WARNING: I couldn't connect to your database server!  If this is a new install, 
you will need to connect to your database server and run this command manually:

mysql -u root -h $host -p
CREATE DATABASE squirrelmail;
GRANT ALL PRIVILEGES ON $db.* TO $user\@'$host' IDENTIFIED BY '$pass';
CREATE TABLE squirrelmail.address (
owner varchar(128) DEFAULT '' NOT NULL,
nickname varchar(16) DEFAULT '' NOT NULL,
firstname varchar(128) DEFAULT '' NOT NULL,
lastname varchar(128) DEFAULT '' NOT NULL,
email varchar(128) DEFAULT '' NOT NULL,
label varchar(255),
PRIMARY KEY (owner,nickname),
KEY firstname (firstname,lastname)
);
CREATE TABLE squirrelmail.global_abook (
owner varchar(128) DEFAULT '' NOT NULL,
nickname varchar(16) DEFAULT '' NOT NULL,
firstname varchar(128) DEFAULT '' NOT NULL,
lastname varchar(128) DEFAULT '' NOT NULL,
email varchar(128) DEFAULT '' NOT NULL,
label varchar(255),
PRIMARY KEY (owner,nickname),
KEY firstname (firstname,lastname)
);
CREATE TABLE squirrelmail.userprefs (
user varchar(128) DEFAULT '' NOT NULL,
prefkey varchar(64) DEFAULT '' NOT NULL,
prefval BLOB DEFAULT '' NOT NULL,
PRIMARY KEY (user,prefkey)
);
quit;

If this is an upgrade, you can probably ignore this warning.

EOSQUIRRELGRANT
	};
};


sub squirrelmail_config($)
{
	my ($conf) = @_;

	my $mailhost = $conf->{'toaster_hostname'};
	my $dsn      = "";

	if ( $conf->{'install_squirrelmail_sql'} ) 
	{
		$dsn = 'mysql://squirrel:secret@localhost/squirrelmail';
	};

	my $string =  <<EOCONFIG
<?php

/**
 * SquirrelMail Configuration File
 * Created by Mail::Toaster http://www.tnpi.biz/internet/mail/toaster/
 */

global \$version;
\$config_version = '1.4.2';
\$config_use_color = 2;

\$org_name      = "SquirrelMail";
\$org_logo      = SM_PATH . 'images/tnpi_logo.jpg';
\$org_logo_width  = '308';
\$org_logo_height = '111';
\$org_title     = "SquirrelMail \$version";
\$signout_page  = 'https://$mailhost/';
\$frame_top     = '_top';

\$provider_uri     = 'http://www.tnpi.biz/internet/mail/toaster/docs/';
\$provider_name     = 'The Network People';

\$motd = "";

\$squirrelmail_default_language = 'en_US';

\$domain                 = '$mailhost';
\$imapServerAddress      = 'localhost';
\$imapPort               = 143;
\$useSendmail            = true;
\$smtpServerAddress      = 'localhost';
\$smtpPort               = 25;
\$sendmail_path          = '/usr/sbin/sendmail';
\$pop_before_smtp        = false;
\$imap_server_type       = 'courier';
\$invert_time            = false;
\$optional_delimiter     = 'detect';

\$default_folder_prefix          = '';
\$trash_folder                   = 'INBOX.Trash';
\$sent_folder                    = 'INBOX.Sent';
\$draft_folder                   = 'INBOX.Drafts';
\$default_move_to_trash          = true;
\$default_move_to_sent           = true;
\$default_save_as_draft          = true;
\$show_prefix_option             = false;
\$list_special_folders_first     = true;
\$use_special_folder_color       = true;
\$auto_expunge                   = true;
\$default_sub_of_inbox           = true;
\$show_contain_subfolders_option = false;
\$default_unseen_notify          = 2;
\$default_unseen_type            = 1;
\$auto_create_special            = true;
\$delete_folder                  = false;
\$noselect_fix_enable            = false;

\$default_charset          = 'iso-8859-1';
\$data_dir                 = '/var/spool/squirrelmail/pref/';
\$attachment_dir           = '/var/spool/squirrelmail/attach/';
\$dir_hash_level           = 0;
\$default_left_size        = '150';
\$force_username_lowercase = false;
\$default_use_priority     = true;
\$hide_sm_attributions     = false;
\$default_use_mdn          = true;
\$edit_identity            = true;
\$edit_name                = true;
\$allow_thread_sort        = false;
\$allow_server_sort        = false;
\$allow_charset_search     = true;
\$uid_support              = true;


\$theme_css = '';
\$theme_default = 0;
\$theme[0]['PATH'] = SM_PATH . 'themes/default_theme.php';
\$theme[0]['NAME'] = 'Default';
\$theme[1]['PATH'] = SM_PATH . 'themes/plain_blue_theme.php';
\$theme[1]['NAME'] = 'Plain Blue';
\$theme[2]['PATH'] = SM_PATH . 'themes/sandstorm_theme.php';
\$theme[2]['NAME'] = 'Sand Storm';
\$theme[3]['PATH'] = SM_PATH . 'themes/deepocean_theme.php';
\$theme[3]['NAME'] = 'Deep Ocean';
\$theme[4]['PATH'] = SM_PATH . 'themes/slashdot_theme.php';
\$theme[4]['NAME'] = 'Slashdot';
\$theme[5]['PATH'] = SM_PATH . 'themes/purple_theme.php';
\$theme[5]['NAME'] = 'Purple';
\$theme[6]['PATH'] = SM_PATH . 'themes/forest_theme.php';
\$theme[6]['NAME'] = 'Forest';
\$theme[7]['PATH'] = SM_PATH . 'themes/ice_theme.php';
\$theme[7]['NAME'] = 'Ice';
\$theme[8]['PATH'] = SM_PATH . 'themes/seaspray_theme.php';
\$theme[8]['NAME'] = 'Sea Spray';
\$theme[9]['PATH'] = SM_PATH . 'themes/bluesteel_theme.php';
\$theme[9]['NAME'] = 'Blue Steel';
\$theme[10]['PATH'] = SM_PATH . 'themes/dark_grey_theme.php';
\$theme[10]['NAME'] = 'Dark Grey';
\$theme[11]['PATH'] = SM_PATH . 'themes/high_contrast_theme.php';
\$theme[11]['NAME'] = 'High Contrast';
\$theme[12]['PATH'] = SM_PATH . 'themes/black_bean_burrito_theme.php';
\$theme[12]['NAME'] = 'Black Bean Burrito';
\$theme[13]['PATH'] = SM_PATH . 'themes/servery_theme.php';
\$theme[13]['NAME'] = 'Servery';
\$theme[14]['PATH'] = SM_PATH . 'themes/maize_theme.php';
\$theme[14]['NAME'] = 'Maize';
\$theme[15]['PATH'] = SM_PATH . 'themes/bluesnews_theme.php';
\$theme[15]['NAME'] = 'BluesNews';
\$theme[16]['PATH'] = SM_PATH . 'themes/deepocean2_theme.php';
\$theme[16]['NAME'] = 'Deep Ocean 2';
\$theme[17]['PATH'] = SM_PATH . 'themes/blue_grey_theme.php';
\$theme[17]['NAME'] = 'Blue Grey';
\$theme[18]['PATH'] = SM_PATH . 'themes/dompie_theme.php';
\$theme[18]['NAME'] = 'Dompie';
\$theme[19]['PATH'] = SM_PATH . 'themes/methodical_theme.php';
\$theme[19]['NAME'] = 'Methodical';
\$theme[20]['PATH'] = SM_PATH . 'themes/greenhouse_effect.php';
\$theme[20]['NAME'] = 'Greenhouse Effect (Changes)';
\$theme[21]['PATH'] = SM_PATH . 'themes/in_the_pink.php';
\$theme[21]['NAME'] = 'In The Pink (Changes)';
\$theme[22]['PATH'] = SM_PATH . 'themes/kind_of_blue.php';
\$theme[22]['NAME'] = 'Kind of Blue (Changes)';
\$theme[23]['PATH'] = SM_PATH . 'themes/monostochastic.php';
\$theme[23]['NAME'] = 'Monostochastic (Changes)';
\$theme[24]['PATH'] = SM_PATH . 'themes/shades_of_grey.php';
\$theme[24]['NAME'] = 'Shades of Grey (Changes)';
\$theme[25]['PATH'] = SM_PATH . 'themes/spice_of_life.php';
\$theme[25]['NAME'] = 'Spice of Life (Changes)';
\$theme[26]['PATH'] = SM_PATH . 'themes/spice_of_life_lite.php';
\$theme[26]['NAME'] = 'Spice of Life - Lite (Changes)';
\$theme[27]['PATH'] = SM_PATH . 'themes/spice_of_life_dark.php';
\$theme[27]['NAME'] = 'Spice of Life - Dark (Changes)';
\$theme[28]['PATH'] = SM_PATH . 'themes/christmas.php';
\$theme[28]['NAME'] = 'Holiday - Christmas';
\$theme[29]['PATH'] = SM_PATH . 'themes/darkness.php';
\$theme[29]['NAME'] = 'Darkness (Changes)';
\$theme[30]['PATH'] = SM_PATH . 'themes/random.php';
\$theme[30]['NAME'] = 'Random (Changes every login)';
\$theme[31]['PATH'] = SM_PATH . 'themes/midnight.php';
\$theme[31]['NAME'] = 'Midnight';
\$theme[32]['PATH'] = SM_PATH . 'themes/alien_glow.php';
\$theme[32]['NAME'] = 'Alien Glow';
\$theme[33]['PATH'] = SM_PATH . 'themes/dark_green.php';
\$theme[33]['NAME'] = 'Dark Green';
\$theme[34]['PATH'] = SM_PATH . 'themes/penguin.php';
\$theme[34]['NAME'] = 'Penguin';
\$theme[35]['PATH'] = SM_PATH . 'themes/minimal_bw.php';
\$theme[35]['NAME'] = 'Minimal BW';

\$default_use_javascript_addr_book = false;
\$addrbook_dsn = '$dsn';
\$addrbook_table = 'address';

\$prefs_dsn = '$dsn';
\$prefs_table = 'userprefs';
\$prefs_user_field = 'user';
\$prefs_key_field = 'prefkey';
\$prefs_val_field = 'prefval';
\$no_list_for_subscribe = false;
\$smtp_auth_mech = 'none';
\$imap_auth_mech = 'login';
\$use_imap_tls = false;
\$use_smtp_tls = false;
\$session_name = 'SQMSESSID';

\@include SM_PATH . 'config/config_local.php';

?>
EOCONFIG
;
	chomp $string;
	return $string;
};


=head2 sqwebmail

	$setup->sqwebmail($conf);

install sqwebmail based on your settings in toaster-watcher.conf.

=cut

sub sqwebmail($)
{
	my ($self, $conf)  = @_;

	my $ver = $conf->{'install_sqwebmail'};

	unless ( $ver ) {
		print "Sqwebmail installation is disabled!\n";
		return 0;
	}

	$self->courier_authlib($conf);

	my $debug   = $conf->{'debug'};
	my $httpdir = $conf->{'toaster_http_base'} || "/usr/local/www";
	my $cgi     = $conf->{'toaster_cgi-bin'};
	my $prefix = $conf->{'toaster_prefix'} || "/usr/local";

	unless ( $cgi && -d $cgi ) { $cgi  = "$httpdir/cgi-bin" };

	my $datadir = $conf->{'toaster_http_docs'};
	unless ( -d $datadir ) {
		if    ( -d "$httpdir/data/mail") { $datadir = "$httpdir/data/mail"; } 
		elsif ( -d "$httpdir/mail")      { $datadir = "$httpdir/mail";      }
		else                             { $datadir = "$httpdir/data";      };
	};

	my $mime   = "$prefix/etc/apache2/mime.types";
	   $mime   = "$prefix/etc/apache/mime.types" unless (-e $mime);

	my $cachedir = "/var/run/sqwebmail";

	if ( $os eq "freebsd" && $ver eq "port" ) 
	{
		$self->expect($conf);

		unless ($freebsd->is_port_installed("gnupg")) {
			$freebsd->package_install("gnupg") or $freebsd->port_install("gnupg", "security");
		};

		if ( $cgi     =~ /\/usr\/local\/(.*)$/ ) { $cgi = $1; };
		if ( $datadir =~ /\/usr\/local\/(.*)$/ ) { $datadir = $1; };

		my @args = "WITHOUT_AUTHDAEMON=yes";
		push @args, "WITH_HTTPS=yes";
		push @args, "WITH_VCHKPW=yes";
		push @args, "WITH_ISPELL=yes";
		push @args, "WITHOUT_IMAP=yes";
#		push @args, "WITH_MIMETYPES";
		push @args, "CGIBINDIR=$cgi";
		push @args, "CGIBINSUBDIR=''";
		push @args, "WEBDATADIR=$datadir";
		push @args, "CACHEDIR=$cachedir";
		$freebsd->port_install("sqwebmail", "mail",undef,undef,join(",", @args), 1);

		$freebsd->rc_dot_conf_check("sqwebmaild_enable",    "sqwebmaild_enable=\"YES\"");

		print "sqwebmail: starting sqwebmaild.\n";
		my $start = "$prefix/etc/rc.d/sqwebmail-sqwebmaild";
		if ( -x $start      ) { $utility->syscmd("$start    start"); };
		if ( -x "$start.sh" ) { $utility->syscmd("$start.sh start"); };
	}; 

	if ( $os eq "freebsd" && $ver eq "port" && $freebsd->is_port_installed("sqwebmail") )
	{
		$self->sqwebmail_conf($conf);
		return 1;
	};

	$ver = "4.0.7" if ($ver eq "port");

	if ( -x "$prefix/libexec/sqwebmail/authlib/authvchkpw" ) 
	{
		unless ( $utility->yes_or_no("Sqwebmail is already installed, re-install it?", 300) ) {
			print "ok, skipping out.\n";
			return 0;
		};
	};

	my $package = "sqwebmail-$ver";
	my $site    = "http://" . $conf->{'toaster_sf_mirror'} . "/courier";
	my $src     = $conf->{'toaster_src_dir'} || "/usr/local/src";

	$utility->chdir_source_dir("$src/mail");

	if ( -d "$package" )
	{
		unless ( $utility->source_warning($package, 1, $src) ) 
		{ 
			carp "sqwebmail: OK, skipping sqwebmail.\n"; 
			return 0;
		};
	};

	unless ( -e "$package.tar.bz2" ) 
	{
		$utility->get_file("$site/$package.tar.bz2");
		unless ( -e "$package.tar.bz2" ) {
			croak "sqwebmail FAILED: coudn't fetch $package\n";
		};
	};

	$utility->archive_expand("$package.tar.bz2", $debug);

	chdir($package) or croak "sqwebmail FAILED: coudn't chdir $package\n";

	my $cmd = "./configure --prefix=$prefix --with-htmldir=$prefix/share/sqwebmail --with-cachedir=/var/run/sqwebmail --enable-webpass=vpopmail --with-module=authvchkpw --enable-https --enable-logincache --enable-imagedir=$datadir/webmail --without-authdaemon --enable-mimetypes=$mime";
	$cmd .= " --enable-cgibindir=" . $cgi;
	if ($os eq "darwin") { $cmd .= " --with-cacheowner=daemon"; };
	$utility->syscmd( $cmd );
	$utility->syscmd( "make configure-check");
	$utility->syscmd( "make check");
	$utility->syscmd( "make");

	my $share = "$prefix/share/sqwebmail";
	if ( -d $share ) {
		$utility->syscmd( "make install-exec");
		print "\n\nWARNING: I have only installed the $package binaries, thus\n";
		print "preserving any custom settings you might have in $share.\n";
		print "If you wish to do a full install, overwriting any customizations\n";
		print "you might have, then do this:\n\n";
		print "\tcd $src/mail/$package; make install\n";
	} 
	else {
		$utility->syscmd( "make install");
		chmod 00755, $share;
		chmod 00755, "$datadir/sqwebmail";
		copy("$share/ldapaddressbook.dist", "$share/ldapaddressbook") or croak "copy failed: $!";
	};

	$utility->syscmd("gmake install-configure");

	$self->sqwebmail_conf($conf);
}

sub sqwebmail_conf 
{
	my ($self, $conf) = @_;

	my $cachedir = "/var/run/sqwebmail";
	my $prefix = $conf->{'toaster_prefix'} || "/usr/local";

	unless ( -e $cachedir ) {
		my $uid = getpwnam("bin");
		my $gid = getgrnam("bin");
		mkdir($cachedir, 0755);
		chown($uid, $gid, $cachedir);
	};

	if ( $conf->{'qmailadmin_return_to_mailhome'} )
	{
		my $file = "$prefix/share/sqwebmail/html/en-us/login.html";
		return unless ( -e $file );
		print "sqwebmail: Adjusting login to return to Mail Center page\n";

		my @lines = $utility->file_read($file);
		my $newline = '<META http-equiv="refresh" content="1;URL=https://'. $conf->{'toaster_hostname'} . '/">';
		foreach my $line (@lines) {
			if ( $line =~ /meta name="GENERATOR"/ ) {
				$line = $newline;
			};
		};
		$utility->file_write($file, @lines);
	}
}



=head2 supervise

	$setup->supervise($conf);

One stop shopping: calls the following subs:

  $qmail->control_create($conf);
  $setup->service_dir_create($conf);
  $toaster->supervise_dirs_create($conf);
  $qmail->install_qmail_control_files($conf);
  $qmail->install_qmail_control_log_files($conf);
  $setup->service_symlinks($conf, $debug);

=cut


sub supervise($;$)
{
	my ($self, $conf, $debug) = @_;

	$debug = $conf->{'debug'} if $conf->{'debug'};
	my $supervise = $conf->{'qmail_supervise'} || "/var/qmail/supervise";
	my $prefix    = $conf->{'toaster_prefix'}  || "/usr/local";

	$perl->module_load( {module=>"Mail::Toaster::Qmail"} );

	$qmail->control_create($conf, $debug);

	$toaster->service_dir_create($conf, $debug);
	$toaster->supervise_dirs_create($conf, $debug);

	$qmail->install_qmail_control_files($conf, $debug);
	$qmail->install_qmail_control_log_files($conf, undef, $debug);

	$self->startup_script($conf, $debug);
	$self->service_symlinks($conf, $debug);

	my $start = "$prefix/sbin/services";

	print "\n\nStarting up services (Ctrl-C to cancel). 

If there's any problems, you can stop all supervised services by running:

          $start stop\n
If you get a not found error, you need to refresh your shell. Tcsh users 
do this with the command 'rehash'.\n\nStarting in 5 seconds: ";
	foreach ( 1..5) { 
		print ".";
		sleep 1;
	}
	print "\n";

	if ( -x $start )
	{
		$utility->syscmd("$start start");
	};
};


=head2 service_symlinks

Sets up the supervised mail services for Mail::Toaster

	$setup->service_symlinks($conf, $debug);

This populates the supervised service directory (default: /var/service) with symlinks to the supervise control directories (typically /var/qmail/supervise/*). Creates and sets permissions on the following directories and files:

  /var/service/pop3
  /var/service/smtp
  /var/service/send
  /var/service/submit

=cut

sub service_symlinks($;$)
{
	my ($self, $conf, $debug) = @_;

	$perl->module_load( {module=>"Mail::Toaster::Qmail"} );

	my $pop_service_dir   = $qmail->service_dir_get  ($conf, "pop3");
	my $pop_supervise_dir = $qmail->supervise_dir_get($conf, "pop3");

	unless ( $conf->{'pop3_daemon'} eq "qpop3d" ) 
	{
		if ( -e $pop_service_dir ) {
			print "Deleting $pop_service_dir because we aren't using qpop3d!\n" if $debug;
			unlink($pop_service_dir);
		} else {
			print "NOTICE: Not enabled due to configuration settings.\n";
		};
	}
	else
	{
		if ( -e $pop_service_dir ) 
		{
			print "service_symlinks: $pop_service_dir already exists.\n" if $debug;
		} 
		else 
		{
			print "service_symlinks: creating symlink from $pop_supervise_dir to $pop_service_dir\n" if $debug;
			symlink($pop_supervise_dir, $pop_service_dir) or croak "couldn't symlink: $!";
		};
	};

	foreach my $prot ("smtp", "send", "submit")
	{
		my $svcdir = $qmail->service_dir_get  ($conf, $prot);
		my $supdir = $qmail->supervise_dir_get($conf, $prot);

		if ( -e $svcdir ) 
		{
			print "service_symlinks: $svcdir already exists.\n" if $debug;
		}
		else
		{
			print "service_symlinks: creating symlink from $supdir to $svcdir\n";
			symlink($supdir, $svcdir) or croak "couldn't symlink: $!";
		};
	};

	return 1;
};


=head2 startup_script

Sets up the supervised mail services for Mail::Toaster

	$setup->startup_script($conf, $debug);

If they don't already exist, this sub will create:

	daemontools service directory (default /var/service) 
	symlink to the services script

The services script allows you to run "services stop" or "services start" on your system to control the supervised daemons (qmail-smtpd, qmail-pop3, qmail-send, qmail-submit). It affects the following files:

  $prefix/etc/rc.d/[svscan|services].sh
  /usr/local/sbin/services

=cut

sub startup_script($;$)
{
	my ($self, $conf, $debug) = @_;
	my $r;

	my $dl_site  = $conf->{'toaster_dl_site'}   || "http://www.tnpi.biz";
	my $confdir  = $conf->{'system_config_dir'} || "/usr/local/etc";
	my $dl_url   = "$dl_site/internet/mail/toaster";
	my $start    = "$confdir/rc.d/services.sh";

	# make sure the service dir is set up
	unless ( $toaster->service_dir_test($conf, $debug) ) {
		print "FATAL: the service directories don't appear to be set up. I refuse to configure them to start up until this is fixed.\n";
		return 0;
	}

	# how we configure each startup file depends on what platform we're operating on

	if ( $os eq "freebsd" ) 
	{
		# The FreeBSD port for daemontools includes rc.d/svscan.sh so we use it
		$start = "$confdir/rc.d/svscan.sh";
		unless ( -f $start ) {
			print "WARNING: no svscan.sh, is daemontools installed and up-to-date?\n";
			print "\n\nInstalling a default version....";

			$utility->get_file("$dl_url/start/services.txt");
			$r = $utility->install_if_changed("services.txt", $start, {mode=>00751, clean=>1});
			return 0 unless $r;
			$r == 1 ? $r = "ok" : $r = "ok (current)";

			$self->_formatted("startup_script: updating $start", $r);
		}

		$freebsd->rc_dot_conf_check("svscan_enable", "svscan_enable=\"YES\"");

		# if the qmail start file is installed, nuke it
		if ( -e "$confdir/rc.d/qmail.sh" )
		{
			unlink("$confdir/rc.d/qmail.sh") or croak "couldn't delete $confdir/rc.d/qmail.sh: $!";
			print "startup_script: removing $confdir/rc.d/qmail.sh\n";
		};
	}
	elsif ( $os eq "darwin" ) 
	{
		$start = "/Library/LaunchDaemons/to.yp.cr.daemontools-svscan.plist";
		unless ( -e $start ) {
			$utility->get_file("$dl_url/start/to.yp.cr.daemontools-svscan.plist");
			$r = $utility->install_if_changed("to.yp.cr.daemontools-svscan.plist", $start, {mode=>00551, clean=>1});
			return 0 unless $r;
			$r == 1 ? $r = "ok" : $r = "ok (current)";
			$self->_formatted("startup_script: updating $start", $r);
		}

		my $prefix = $conf->{'toaster_prefix'} || "/usr/local";
		$start = "$prefix/sbin/services";
		$utility->get_file("$dl_url/start/services-darwin.txt");
		$r = $utility->install_if_changed("services-darwin.txt", $start, {mode=>00551, clean=>1});
		return 0 unless $r;
		$r == 1 ? $r = "ok" : $r = "ok (current)";
		$self->_formatted("startup_script: updating $start", $r);
	}
	else {
		print "SORRY: I don't know how to set up the startup script on $os. If you know the proper method of doing so, please have a look at $dl_url/start/services.txt and adapt it to $os and send it to matt\@tnpi.biz for inclusion.\n";
	}

	my $sym = "/usr/local/sbin/services";
	if ( $os eq "freebsd") 
	{
		return 1 if ( -l $sym && -x $sym );

		if ( -e $sym ) 
		{
			unlink $sym or carp "couldn't remove existing $sym. please re(move) it and run this again!\n";
		}
		else
		{
			print "startup_script: adding $sym...";
			symlink($start, $sym);
			-e $sym ? print "done.\n" : print "FAILED.\n";
		};
	}
};


=head2 test

Run a variety of tests to verify that your Mail::Toaster installation is working correctly.

=cut

sub test
{
	my ($self, $conf) = @_;
	my @tests;

	print "testing...\n";

	my $qdir = $conf->{'qmail_dir'};
	print "does qmail's home directory exist?\n";
	-d $qdir ? $self->_formatted("\t$qdir", "ok") : $self->_formatted("\t$qdir","FAILED");

	print "checking qmail directory contents\n";
	@tests = qw(alias boot control man users bin doc queue);
	push @tests, "configure" if ($os eq "freebsd"); # added by the port
	foreach ( @tests ) {
		-d "$qdir/$_" ? $self->_formatted("\t$qdir/$_", "ok") : $self->_formatted("    $qdir/$_", "FAILED");
	};

	print "is the qmail rc file executable?\n";
	-x "$qdir/rc" ? $self->_formatted("\t$qdir/rc", "ok") : $self->_formatted("\t$qdir/rc","FAILED");
	
	$perl->module_load( {module=>"Mail::Toaster::Passwd"} );
	my $passwd = Mail::Toaster::Passwd->new();

	print "do the qmail users exist?\n";
	foreach ( ( 
			$conf->{'qmail_user_alias'}, 
			$conf->{'qmail_user_daemon'}, 
			$conf->{'qmail_user_passwd'}, 
			$conf->{'qmail_user_queue'}, 
			$conf->{'qmail_user_remote'}, 
			$conf->{'qmail_user_send'},      ) ) 
	{
		$passwd->exist($_) ? $self->_formatted("\t$_", "ok") : $self->_formatted("\t$_", "FAILED");
	};

	print "do the qmail groups exist?\n";
	foreach ( ( 
			$conf->{'qmail_group'}, 
			$conf->{'qmail_log_group'},   ) ) 
	{
		getgrnam($_) ? $self->_formatted("\t$_", "ok") : $self->_formatted("\t$_", "FAILED");
	};

	print "do the qmail alias files have contents?\n";
	my $q_alias = "$qdir/alias";
	foreach ( (
			"$q_alias/.qmail-postmaster",
			"$q_alias/.qmail-root",
			"$q_alias/.qmail-mailer-daemon",
		) )
	{
		-s $_ ? $self->_formatted("\t$_", "ok") : $self->_formatted("\t$_", "FAILED");
	};

	$self->daemontools_test();
	$self->ucspi_test($conf);

	$perl->module_load( {module=>"Mail::Toaster::Qmail"} );

	print "does supervise directory exist?\n";
	my $q_sup = $conf->{'qmail_supervise'} || "/var/qmail/supervise";
	-d $q_sup ? $self->_formatted("\t$q_sup", "ok") : $self->_formatted("\t$q_sup", "FAILED");

	# check each supervised directory
	foreach ( qw/smtp send pop3 submit/ ) 
	{
		$toaster->supervised_dir_test($conf, $_) ? 
			$self->_formatted("\t$q_sup/$_", "ok") : $self->_formatted("\t$q_sup/$_", "FAILED");
	}

	print "do service directories exist?\n";
	my $q_ser = $conf->{'qmail_service'};
	foreach ( ( $q_ser, 
		$qmail->service_dir_get($conf, "smtp"),
		$qmail->service_dir_get($conf, "send"),
		$qmail->service_dir_get($conf, "pop3"),
		$qmail->service_dir_get($conf, "submit"),  ) )
	{
		-d $_ ?  $self->_formatted("\t$_", "ok") : $self->_formatted("\t$_", "FAILED");
	};

	print "are the supervised services running?\n";
	my $svok = $utility->find_the_bin("svok");
	foreach ( ( 
		$qmail->service_dir_get($conf, "smtp"),
		$qmail->service_dir_get($conf, "send"),
		$qmail->service_dir_get($conf, "pop3"),
		$qmail->service_dir_get($conf, "submit"),  ) )
	{
		$utility->syscmd("$svok $_") ? 
			$self->_formatted("\t$_", "FAILED") : $self->_formatted("\t$_", "ok");
	};

	print "do the logging directories exist?\n";
	my $q_log = $conf->{'qmail_log_base'};
	foreach ( ( $q_log, 
		"$q_log/pop3",
		"$q_log/send",
		"$q_log/smtp",
		"$q_log/submit",
		))
	{
		-d $_ ?  $self->_formatted("\t$_", "ok") : $self->_formatted("\t$_", "FAILED");
	};

	print "checking log files?\n";
	foreach ( ( 
		"$q_log/clean.log", 
		"$q_log/maildrop.log",
		"$q_log/watcher.log",
		"$q_log/send/current",
		"$q_log/smtp/current",
		"$q_log/submit/current",
		"$q_log/pop3/current",
		))
	{
		-f $_ ?  $self->_formatted("\t$_", "ok") : $self->_formatted("\t$_", "FAILED");
	};

	$self->vpopmail_test($conf);

	$toaster->test_processes($conf);

	unless ( $utility->yes_or_no("skip the network listener tests?", 10) ) 
	{
		my $netstat = $utility->find_the_bin("netstat");
		if ( $os eq "freebsd" ) { $netstat .= " -aS " }
		if ( $os eq "darwin"  ) { $netstat .= " -a "  }
		if ( $os eq "linux"   ) { $netstat .= " -an " } 
		else                    { $netstat .= " -a "  };  # should be pretty safe

		print "checking for listening tcp ports\n";
		foreach ( qw( smtp http pop3 imap https submission pop3s imaps ) )
		{
			`$netstat | grep $_ | grep -i listen` ?
				$self->_formatted("\t$_", "ok") : $self->_formatted("\t$_", "FAILED");
		};

		print "checking for udp listeners\n";
		foreach ( qw( snmp ) )
		{
			`$netstat | grep $_` ?
				$self->_formatted("\t$_", "ok") : $self->_formatted("\t$_", "FAILED");
		};
	}

	$self->test_crons($conf);
	$self->rrdutil_test($conf);
	$qmail->check_rcpthosts();

	unless ( $utility->yes_or_no("skip the mail scanner tests?", 10) ) {
		$self->filtering_test($conf);
	};

	unless ( $utility->yes_or_no("skip the authentication tests?", 10) ) {
		$self->test_auth($conf);
	};

	# there's plenty more room here for more tests.

	# test DNS!
	# make sure primary IP is not reserved IP space
	# test reverse address for this machines IP
	# test resulting hostname and make sure it matches
	# make sure server's domain name has NS records
	# test MX records for server name
	# test for SPF records for server name

	# test for low disk space on /, qmail, and vpopmail partitions

	print "\ntesting complete.\n";
};

sub test_auth
{
	my ($self, $conf) = @_;

	my $email = $conf->{'toaster_test_email'};
	my $pass  = $conf->{'toaster_test_email_pass'};

	my $domain = (split('@', $email))[1];
	print "test_auth: testing domain is: $domain.\n";

	my $qmaildir = $conf->{'qmail_dir'};
	unless ( -e "$qmaildir/users/assign" && `grep $domain $qmaildir/users/assign` ) 
	{
		print "domain $domain is not set up.\n";
		unless ( $utility->yes_or_no("shall I add it for you?", 30) ) {
			return 0;
		}

		my $vpdir = $conf->{'vpopmail_home_dir'};
		$utility->syscmd("$vpdir/bin/vadddomain $domain $pass");
		$utility->syscmd("$vpdir/bin/vadduser $email $pass");
	};

	return 0 unless ( -e "$qmaildir/users/assign" && `grep $domain $qmaildir/users/assign` );

	if ($os eq "freebsd") {
		$freebsd->port_install("p5-Mail-POP3Client", "mail"     ) unless $freebsd->is_port_installed("p5-Mail-POP3Client");
		$freebsd->port_install("p5-Mail-IMAPClient", "mail"     ) unless $freebsd->is_port_installed("p5-Mail-IMAPClient");
		$freebsd->port_install("p5-IO-Socket-SSL",   "security" ) unless $freebsd->is_port_installed("p5-IO-Socket-SSL");
	};

	$self->imap_test_auth($conf); # test imap auth
	$self->pop3_test_auth($conf); # test pop3 auth
	$self->smtp_test_auth($conf); # test smtp auth

	print "\n\nNOTICE: It is normal for some of the tests to fail. This test suite is useful for any mail server, not just a Mail::Toaster. \n\n";

	# webmail auth
	# other ? 
}

sub test_crons
{
	my ($self, $conf) = @_;

	my @crons = (
		"/usr/local/vpopmail/bin/clearopensmtp",
		"/usr/local/sbin/toaster-watcher.pl",
	);

	push @crons, "/usr/local/share/sqwebmail/cleancache.pl"     if $conf->{'install_sqwebmail'};
	push @crons, "/usr/local/www/cgi-bin/rrdutil.cgi -a update" if $conf->{'install_rrdutil'};

	print "checking cron processes\n";

	foreach ( @crons )
	{
		$utility->syscmd($_) ?
			$self->_formatted("\t$_", "FAILED") : $self->_formatted("\t$_", "ok");
	}
}

sub test_dns
{

	print <<EODNS
People forget to even have DNS setup on their Toaster, as Matt has said before.  If someone forgot to configure DNS, chances are, little or nothing will work -- from port fetching to timely mail delivery.

How about adding a simple DNS check to the Toaster Setup's test suite? And in the meantime, you could give some sort of crude benchmark, depending on the circumstances of the test data.  I'm not looking for something too hefty, but something small and sturdy to make sure there's a good DNS server around answering queries reasonably fast.

Here's a sample of some DNS lookups you could perform.  What I would envision is that there were around 20 to 100 forward and reverse lookups, and that the lookups were timed.  I guess you could look them up in parallel, and wait a maximum of around 15 seconds for all of the replies.  The interesting thing about a lot of reverse lookups is that they often fail because no one has published them.

Iteration 1: lookup A records.
Iteration 2: lookup NS records.
Iteration 3: lookup MX records.
Iteration 4: lookup TXT records.
Iteration 5: Repeat step 1, observe the faster response time due to caching.

Here's a sample output!  Wow.

#toaster_setup.pl -s dnstest
Would you like to enter a local domain so I can test it in detail?
testmydomain-local.net
Would you like to test domains with underscores in them? (y/n)n
Testing /etc/rc.conf for a hostname= line...
This box is known as smtp.testmydomain-local.net
Verifying /etc/hosts exists ... Okay
Verifying /etc/host.conf exists ... Okay
Verifying /etc/nsswitch.conf exists ... Okay
Doing reverse lookups in in-addr.arpa using default name service....
Doing forward A lookups using default name service....
Doing forward NS lookups using default name service....
Doing forward MX lookups using default name service....
Doing forward TXT lookups using default name service....
Results:
[Any errors, like...]
Listing Reverses Not found:
10.120.187.45 (normal)
169.254.89.123 (normal)
Listing A Records Not found:
example.impossible.nonexistent.bogus.co.nl (normal)
Listing TXT Records Not found:
Attempting to lookup the same A records again....  Hmmm. much faster!
Your DNS Server (or its forwarder) seems to be caching responses. (Good)

Checking local domain known as testmydomain-local.net
Checking to see if I can query the testmydomain-local.net NS servers and retrieve the entire DNS record...
ns1.testmydomain-local.net....yes.
ns256.backup-dns.com....yes.
ns13.ns-ns-ns.net...no.
Do DNS records agree on all DNS servers?  Yes. identical.
Skipping SOA match.

I have discovered that testmydomain-local.net has no MX records.  Shame on you, this is a mail server!  Please fix this issue and try again.

I have discovered that testmydomain-local.net has no TXT records.  You may need to consider an SPF v1 TXT record.

Here is a dump of your domain records I dug up for you:
xoxoxoxox

Does hostname agree with DNS?  Yes. (good).

Is this machine a CNAME for something else in DNS?  No.

Does this machine have any A records in DNS?  Yes.
smtp.testmydomain-local.net is 192.168.41.19.  This is a private IP.

Round-Robin A Records in DNS pointing to another machine/interface?
No.

Does this machine have any CNAME records in DNS?  Yes. aka
box1.testmydomain-local.net
pop.testmydomain-local.net
webmail.testmydomain-local.net

***************DNS Test Output complete

Sample Forwards:
The first few may be cached, and the last one should fail.  Some will have no MX server, some will have many.  (The second to last entry has an interesting mail exchanger and priority.)  Many of these will (hopefully) not be found in even a good sized DNS cache.

I have purposely listed a few more obscure entries to try to get the DNS server to do a full lookup.
localhost
<vpopmail_default_domain if set>
www.google.com
yahoo.com
nasa.gov
sony.co.jp
ctr.columbia.edu
time.nrc.ca
distancelearning.org
www.vatican.va
klipsch.com
simerson.net
warhammer.mcc.virginia.edu
example.net
foo.com
example.impossible.nonexistent.bogus.co.nl

[need some obscure ones that are probably always around, plus some non-US sample domains.]

Sample Reverses:
Most of these should be pretty much static.  Border routers, nics and such.  I was looking for a good range of IP's from different continents and providers.  Help needed in some networks.  I didn't try to include many that don't have a published reverse name, but many examples exist in case you want to purposely have some.
127.0.0.1
224.0.0.1
198.32.200.50	(the big daddy?!)
209.197.64.1
4.2.49.2
38.117.144.45
64.8.194.3
72.9.240.9
128.143.3.7
192.228.79.201
192.43.244.18
193.0.0.193
194.85.119.131
195.250.64.90
198.32.187.73
198.41.3.54
198.32.200.157
198.41.0.4
198.32.187.58
198.32.200.148
200.23.179.1
202.11.16.169
202.12.27.33
204.70.25.234
207.132.116.7
212.26.18.3
10.120.187.45
169.254.89.123

[Looking to fill in some of the 12s, 50s and 209s better.  Remove some 198s]

Just a little project.  I'm not sure how I could code it, but it's a little snippet I've been thinking about.  I figure that if you write the code once, it would be quite a handy little feature to try on a server you're new to.

Billy

EODNS
;
}

=head2 ucspi_tcp

Installs ucspi-tcp with my (Matt Simerson) MySQL patch.

	$setup->ucspi_tcp($conf);

=cut

sub ucspi_tcp($)
{
	my ($self, $conf) = @_;

	my $vals = { 
		package => "ucspi-tcp-0.88",
		site    => 'http://cr.yp.to',
		url     => '/ucspi-tcp',
		targets => ['make', 'make setup check'],
		debug   => $conf->{'toaster_debug'},
	};

	$vals->{'patches'} = ["ucspi-tcp-0.88-mysql+rss.patch"] if $conf->{'install_mysql'};

	if ( $os eq "freebsd" )
	{
		# we install it from ports first so that's its registered in the ports
		# database. Otherwise, installing other ports in the future may overwrite
		# our customized version. (don't forget to install pkgtools.conf from
		# the contrib directory!

		unless ( $freebsd->is_port_installed("ucspi-tcp") ) {
			$freebsd->port_install("ucspi-tcp", "sysutils", undef,  undef, "BATCH=yes WITH_RSS_DIFF=1");
			# if that didn't work..
			unless ( $freebsd->is_port_installed("ucspi-tcp") ) {
				$freebsd->port_install("ucspi-tcp", "sysutils", undef,  undef, "BATCH=yes", 1);
			};
		};

		# Then we install it with the SQL patch.
		$vals->{'targets'} = ["make", "make setup check"];
	}
	elsif ( $os eq "darwin"  )
	{
		my @targets = "echo '/opt/local' > conf-home";
#		$vals->{'patches'} = ["ucspi-tcp-0.88-mysql+rss-darwin.patch"];
		if ( $conf->{'install_mysql'} ) {
			if ( -d "/opt/local/include/mysql" ) {
				push @targets, "echo 'gcc -s -I/opt/local/include/mysql -L/opt/local/lib/mysql -lmysqlclient' > conf-ld";
				push @targets, "echo 'gcc -O2 -I/opt/local/include/mysql' > conf-cc";
			} else {
				push @targets, "echo 'gcc -s -I/usr/include/mysql -L/usr/lib/mysql -lmysqlclient' > conf-ld";
				push @targets, "echo 'gcc -O2 -I/usr/include/mysql' > conf-cc";
			};
		};
		push @targets, "make";
		push @targets, "make setup";
		$vals->{'targets'} = \@targets;
	}
	elsif ( $os eq "linux" )
	{
		$vals->{'targets'} = ["echo gcc -O2 -include /usr/include/errno.h > conf-cc", "make", "make setup check"];
#		Need to test MySQL patch on linux before enabling it.
#		$vals->{'patches'}    = ('ucspi-tcp-0.88-mysql+rss.patch', 'ucspi-tcp-0.88.errno.patch');
#		$vals->{'patch_args'} = "-p0";
	};

	# see if it's installed
	my $tcpserver = $utility->find_the_bin("tcpserver");
	if (-x $tcpserver) {                               # its installed
		unless ( $conf->{'install_mysql'} ) {          # done if we don't need mysql
			$self->_formatted("ucspi-tcp: already installed", "ok (exists)");
			return 2;
 		}
		if ( `strings $tcpserver | grep sql` ) {       # check if mysql libs are present
			$self->_formatted("ucspi-tcp: mysql support is already installed", "ok (exists)");
			return 1;
		} else {
			print "ucspi-tcp is installed but w/o mysql support, compiling from sources.\n";
		};
	};

	# save having to download it again
	if ( -e "/usr/ports/distfiles/ucspi-tcp-0.88.tar.gz" ) {
		copy("/usr/ports/distfiles/ucspi-tcp-0.88.tar.gz", "/usr/local/src/ucspi-tcp-0.88.tar.gz");
	};

	$utility->install_from_source($conf, $vals );

	print "should be all done!\n";
	-x $utility->find_the_bin("tcpserver") ? return 1 : return 0;

#	my $file = "db.c";
#	my @lines = $utility->file_read($file);
#	foreach my $line (@lines) {
#		if ( $line =~ /^#include <unistd.h>/ ) {
#			$line = '#include <sys/unistd.h>';
#		};
#	};
#	$utility->file_write($file, @lines);
};

sub ucspi_test
{
	my ($self, $conf) = @_;

	print "checking ucspi-tcp binaries...\n";
	foreach ( qw( tcprules tcpserver rblsmtpd tcpclient recordio ) ) {
		-x $utility->find_the_bin($_) ?
			$self->_formatted("\t$_", "ok") : $self->_formatted("\t$_", "FAILED");
	};

	my $tcpserver = $utility->find_the_bin("tcpserver");

	if ( $conf->{'install_mysql'} ) {
		if ( `strings $tcpserver | grep sql` ) {
			$self->_formatted("\ttcpserver mysql support", "ok");
		} else {
			$self->_formatted("\ttcpserver mysql support", "FAILED");
			return 0;
		};
	};

	return 1;
}

=head2 vpopmail


Vpopmail is great, but it has lots of options and remembering which option you used months or years ago to build a mail server isn't always easy. So, store all the settings in toaster-watcher.conf and this sub will install vpopmail for you honoring all your settings and passing the appropriate configure flags to vpopmail's configure.

	$setup->vpopmail($conf);

If you don't have toaster-watcher.conf installed, it'll ask you a series of questions and then install based on your answers.

=cut

sub vpopmail($)
{
	my ($self, $conf)  = @_;
	my ($ans, $ddom, $ddb, $cflags, $my_write, $conf_args, $mysql);

	my $debug   = $conf->{'debug'};
	my $version = $conf->{'install_vpopmail'}; $version ||= "5.4.5";

	if ( $os eq "freebsd" && ! $freebsd->is_port_installed("vpopmail") ) 
	{
		my @defs = "WITH_CLEAR_PASSWD=yes";
		push @defs, "WITH_LEARN_PASSWORDS=yes";
		push @defs, "WITH_MYSQL=yes";

		push @defs, "WITH_MYSQL_REPLICATION=yes" if ( $conf->{'vpopmail_mysql_replication'} );
		push @defs, "WITH_MYSQL_LIMITS=yes"      if ( $conf->{'vpopmail_mysql_limits'}      );
		push @defs, "WITH_IP_ALIAS=yes"          if ( $conf->{'vpopmail_ip_alias_domains'}  );
		push @defs, "WITH_QMAIL_EXT=yes"         if ( $conf->{'vpopmail_qmail_extensions'}  );
		push @defs, "WITH_DOMAIN_QUOTAS=yes"     if ( $conf->{'vpopmail_domain_quotas'}     );
		push @defs, "WITH_SINGLE_DOMAIN=yes"     if ( $conf->{'vpopmail_disable_many_domains'} );

		push @defs, 'WITH_MYSQL_SERVER="'      . $conf->{'vpopmail_mysql_repl_master'} . '"';
		push @defs, 'WITH_MYSQL_USER="'        . $conf->{'vpopmail_mysql_repl_user'} . '"';
		push @defs, 'WITH_MYSQL_PASSWD="'      . $conf->{'vpopmail_mysql_repl_pass'} . '"';
		push @defs, 'WITH_MYSQL_DB="'          . $conf->{'vpopmail_mysql_database'} . '"';
		push @defs, 'WITH_MYSQL_READ_SERVER="' . $conf->{'vpopmail_mysql_repl_slave'} . '"';

		push @defs, 'LOGLEVEL="p"';

		my $r = $freebsd->port_install("vpopmail", "mail", undef, undef, join(",", @defs), 1 );
		if ( $freebsd->is_port_installed("vpopmail") ) 
		{
			$freebsd->port_install ("p5-vpopmail", "mail", undef, undef, undef, 1);
			return 1 if $version eq "port";
		};
	};

	my $package    = "vpopmail-$version";
	my $site       = "http://" . $conf->{'toaster_sf_mirror'} . "/vpopmail";
	#my $site       = "http://www.inter7.com/devel";

	my $vpopdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";
	my $vpuser  = $conf->{'vpopmail_user'}     || "vpopmail";
	my $vpgroup = $conf->{'vpopmail_group'}    || "vchkpw";

	my $uid = getpwnam($vpuser);
	my $gid = getgrnam($vpgroup);

	unless ( $uid && $gid ) 
	{
		$perl->module_load( {module=>"Mail::Toaster::Passwd"} );
		my $passwd = Mail::Toaster::Passwd->new();

		$passwd->creategroup($vpgroup, "89" );
		$passwd->user_add( { user=>$vpuser, homedir=>$vpopdir, uid=>89, gid=>89 } );
	};

	# check installed version
	if ( -x "$vpopdir/bin/vpasswd" ) {
		$perl->module_load( {module=>"vpopmail"} ) if $conf->{'install_ezmlm_cgi'};
		my $installed = `$vpopdir/bin/vpasswd -v | head -1 | cut -f2 -d" "`;
		chop $installed;
		print "vpopmail version $installed currently installed.\n";
		if ( $installed eq $version ) {
			return 1 unless $utility->yes_or_no("Do you want to reinstall vpopmail with the same version?", 60);
		};
	} 
	else {
		print "vpopmail is not installed yet.\n";
	};
	$self->vpopmail_etc($conf);

	unless ( defined $conf->{'vpopmail_mysql'} && $conf->{'vpopmail_mysql'} == 0 ) 
	{
		$mysql = 1;

		if ( is_newer("5.3.30", $version) ) { $conf_args = "--enable-auth-module=mysql "; } 
		else                                { $conf_args = "--enable-mysql=y ";           };

		print "authentication module: mysql\n";
	} 
	else { print "authentication module: cdb\n"; };

	unless ( defined $conf->{'vpopmail_rebuild_tcpserver_file'} 
		&& $conf->{'vpopmail_rebuild_tcpserver_file'} == 1 ) 
	{
		$conf_args .= " --enable-rebuild-tcpserver-file=n";
		print "rebuild tcpserver file: no\n";
	};

	if ( defined $conf->{'vpopmail_ip_alias_domains'} )
	{
		$conf_args .= " --enable-ip-alias-domains=y";
	};

	unless ( is_newer("5.3.30", $version) ) {
		if ( defined $conf->{'vpopmail_default_quota'} ) 
		{
			$conf_args   .= " --enable-defaultquota=$conf->{'vpopmail_default_quota'}";
			print "default quota: $conf->{'vpopmail_default_quota'}\n";
		} 
		else {
			$conf_args   .= " --enable-defaultquota=100000000S,10000C";
			print "default quota: 100000000S,10000C\n";
		};
	};

	if ( defined $conf->{'vpopmail_roaming_users'} ) {
		if ( $conf->{'vpopmail_roaming_users'} ) {
			$conf_args .= " --enable-roaming-users=y"; print "roaming users: yes\n";

			my $min = $conf->{'vpopmail_relay_clear_minutes'};
			if ( $min && $min ne 180 ) {
				$conf_args .= " --enable-relay-clear-minutes=$min"; print "roaming user minutes: $min\n";
			};
		} 
		else {
			$conf_args .= " --enable-roaming-users=n"; print "roaming users: no\n";
		};
	} 
	else {
		$conf_args   .= " --enable-roaming-users=y"; print "roaming users: yes\n";
	};

	if ( $os eq "darwin" && ! -d "/usr/local/mysql" && -d "/opt/local/include/mysql")
	{
		$conf_args .= " --enable-incdir=/opt/local/include/mysql";
		$conf_args .= " --enable-libdir=/opt/local/lib/mysql";
	};

	my $tcprules = $utility->find_the_bin("tcprules");
	$conf_args .= " --enable-tcprules-prog=$tcprules";

	my $src = $conf->{'toaster_src_dir'}; $src ||= "/usr/local/src";

	$utility->chdir_source_dir("$src/mail");

	my $tarball = "$package.tar.gz";

	unless ( -e $tarball ) 
	{
		$utility->get_file("$site/$tarball");
		unless ( -e $tarball ) {
			carp "vpopmail FAILED: Couldn't fetch $tarball!\n";
			exit 0;
		} 
		else 
		{
			if ( `file $tarball | grep ASCII` ) 
			{
				print "vpopmail: oops, file is not binary, we had a problem downloading vpopmail!\n";
				unlink $tarball;
				$utility->get_file("$site/$tarball", 1);
				exit 0;
			};
		};
	};

	if ( -d $package )
	{
		unless ( $utility->source_warning($package, 1, $src) )
		{ 
			carp "vpopmail: OK then, skipping install.\n"; 
			return 0;
		};
	};

	unless ( $utility->archive_expand($tarball, $debug) ) { croak "Couldn't expand $tarball!\n"; };

	unless ( defined $conf->{'vpopmail_learn_passwords'} && $conf->{'vpopmail_learn_passwords'} == 0 ) {
		$conf_args    = $conf_args . " --enable-learn-passwords=y";
		print "learning passwords yes\n";
	} 
	else 
	{
		if ( $utility->yes_or_no("Do you want password learning? (y) ") ) {
			$conf_args    = $conf_args . " --enable-learn-passwords=y";
			print "password learning: yes\n";
		} else {
			print "password learning: no\n";
		};
	};

	unless ( defined $conf->{'vpopmail_logging'} ) {
		if ( $utility->yes_or_no("Do you want logging enabled? (y) ") )
		{
			if ( $utility->yes_or_no("Do you want verbose logging? (y) ") )
			{
				$conf_args    = $conf_args . " --enable-logging=v";
				print "logging: verbose\n";
			} else {
				$conf_args    = $conf_args . " --enable-logging=p";
				print "logging: verbose with failed passwords\n";
			};
		} else {
			$conf_args .= " --enable-logging=p";
		};
	} else {
		if ( $conf->{'vpopmail_logging'} == 1) {
			if ( $conf->{'vpopmail_logging_verbose'} == 1 ) {
				$conf_args .= " --enable-logging=v";
				print "logging: verbose with failed passwords\n";
			} else {
				$conf_args .= " --enable-logging=y";
				print "logging: everything\n";
			};
		};
	};

	unless ( defined $conf->{'vpopmail_default_domain'} ) {
		if ( $utility->yes_or_no("Do you want to use a default domain? ") )
		{
			$ddom = $utility->answer("your default domain");
	
			my @lines;
			if ( is_newer("5.3.22", $version) )
			{
				$utility->file_write("$vpopdir/etc/defaultdomain", ($ddom) );
				chown($uid, $gid, "$vpopdir/etc/defaultdomain") or carp "Couldn't chown $vpopdir/etc/defaultdomain to $uid: $!\n";
			} 
			else {
				$conf_args .= " --enable-default-domain=$ddom";
			}
			print "default domain: $ddom\n";
		};
	} else {
		if ( $conf->{'vpopmail_default_domain'} ne 0 ) {
			if ( is_newer("5.3.22", $version) )
			{
				$utility->file_write("$vpopdir/etc/defaultdomain", ($conf->{'vpopmail_default_domain'}) );
				chown($uid, $gid, "$vpopdir/etc/defaultdomain") or carp "Couldn't chown $vpopdir/etc/defaultdomain to $uid: $!\n";
			} else {
				$conf_args .= " --enable-default-domain=$conf->{'vpopmail_default_domain'}";
			};
			print "default domain: $conf->{'vpopmail_default_domain'}\n";
		} else {
			print "default domain: NONE SELECTED.\n";
		};
	};

	unless ( defined $conf->{'vpopmail_etc_passwd'} ) 
	{
		print "\t\t CAUTION!!  CAUTION!!

		The system users account is NOT compatible with qmail-smtpd-chkusr.
		If you selected that option in the qmail build, you should not answer
		yes here. If you are unsure, select (n).\n";

		if ( $utility->yes_or_no("Do system users (/etc/passwd) get mail? (n) ") ) {
			$conf_args  .= " --enable-passwd";
			print "system password accounts: yes\n";
		};
	} else {
		if ( $conf->{'vpopmail_etc_passwd'} ) {
			$conf_args  .= " --enable-passwd";
			print "system password accounts: yes\n";
		} else {
			print "system password accounts: no\n";
		};
	};
 	
	unless ( defined $conf->{'vpopmail_valias'} ) {
		if ( $utility->yes_or_no("Do you use valias processing? (n) ") ) { 
			$conf_args  .= " --enable-valias=y"; 
			print "valias processing: yes\n";
		};
	} else {
		if ( $conf->{'vpopmail_valias'} ) {
			$conf_args  .= " --enable-valias=y"; 
			print "valias processing: yes\n";
		};
	};
 	
	unless ( defined $conf->{'vpopmail_mysql_logging'} ) {
		if ( $utility->yes_or_no("Do you want mysql logging? (n) " ) ) { 
			$conf_args .= " --enable-mysql-logging=y"; 
			print "mysql logging: yes\n";
		};
	} else {
		if ( $conf->{'vpopmail_mysql_logging'} ) {
			$conf_args .= " --enable-mysql-logging=y"; 
			print "mysql logging: yes\n";
		};
	}

	unless ( defined $conf->{'vpopmail_qmail_extensions'} ) {
		if ( $utility->yes_or_no("Do you want qmail extensions? (n) ") ) { 
			$conf_args .= " --enable-qmail-ext=y"; 
			print "qmail extensions: yes\n";
		};
	} else {
		if ( $conf->{'vpopmail_qmail_extensions'} ) {
			$conf_args .= " --enable-qmail-ext=y"; 
			print "qmail extensions: yes\n";
		};
	};

	if ( $mysql ) 
	{
		my ($mysql_repl, $my_read, $my_user, $my_pass);

		unless ( defined $conf->{'vpopmail_mysql_limits'} ) {
			print "Qmailadmin supports limits via a .qmailadmin-limits file. It can\n";
			print "also get these limits from a MySQL table. ";

			if ( $utility->yes_or_no("Do you want mysql limits? (n) ") ) { 
				$conf_args .= " --enable-mysql-limits=y"; 
				print "mysql qmailadmin limits: yes\n";
			};
		} else {
			if ( $conf->{'vpopmail_mysql_limits'} ) {
				$conf_args .= " --enable-mysql-limits=y"; 
				print "mysql qmailadmin limits: yes\n";
			};
		};

		unless ( defined $conf->{'vpopmail_mysql_replication'} ) {
			$mysql_repl = $utility->yes_or_no("Do you want mysql replication enabled? (n) ");
			if ($mysql_repl) 
			{
				$conf_args .= " --enable-mysql-replication=y";
				if ($ddom) { $ddb = "db.$ddom"; } else { $ddb = "db"; };
				$my_write = $utility->answer("your MySQL master servers hostname", $ddb);
				$my_read  = $utility->answer("your MySQL read server hostname", "localhost");
				$my_user  = $utility->answer("your MySQL user name", "vpopmail");
				$my_pass  = $utility->answer("your MySQL password");
			};
		} else {
			if ( $conf->{'vpopmail_mysql_replication'} ) {
				$conf_args .= " --enable-mysql-replication=y";
				$mysql_repl = 1;
				$my_write = $conf->{'vpopmail_mysql_repl_master'};
				print "mysql replication: yes\n";
				print "mysql replication master: $conf->{'vpopmail_mysql_repl_master'}\n";
			} else { 
				$mysql_repl = 0; 
				print "mysql server: $conf->{'vpopmail_mysql_repl_slave'}\n";
			};
			$my_read  = $conf->{'vpopmail_mysql_repl_slave'};
			$my_user  = $conf->{'vpopmail_mysql_repl_user'};
			$my_pass  = $conf->{'vpopmail_mysql_repl_pass'};
		};

		if ( $conf->{'vpopmail_disable_many_domains'} ) {
			$conf_args .= " --disable-many-domains";
		};

		chdir($package);
		vpopmail_vmysql_h($conf, $mysql_repl, $my_write, $my_read, $my_user, $my_pass);
	};

	unless ( defined $conf->{'vpopmail_domain_quotas'} ) 
	{
		if ( $utility->yes_or_no("Do you want vpopmail's domain quotas? (n) ")) { 
			$conf_args  .= " --enable-domainquotas=y"; 
		};
	} else {
		if ($conf->{'vpopmail_domain_quotas'} ) {
			$conf_args  .= " --enable-domainquotas=y"; 
			print "domain quotas: yes\n";
		} else {
			print "domain quotas: no\n";
		};
	};

	chdir($package);
	print "running configure with $conf_args\n\n";
	$utility->syscmd( "./configure $conf_args");
	$utility->syscmd( "make");
	$utility->syscmd( "make install-strip");
	if ( -e "vlimits.h" ) {
		# this was needed due to a bug in vpopmail 5.4.?(1-2) installer
		$utility->syscmd( "cp vlimits.h $vpopdir/include/");
	};

	$self->vpopmail_mysql_privs($conf);

	if ($conf->{'install_ezmlm_cgi'} ) 
	{
		if ( $os eq "freebsd" ) {
			$freebsd->port_install ("p5-vpopmail", "mail", undef, undef, undef, 1);
		} else {
			$perl->module_load( {module=>"vpopmail"} );
		};
	};

	print "vpopmail: complete.\n";
};


=head2 vpopmail_etc

Builds the ~vpopmail/etc/tcp.smtp file with a mess of sample entries and user specified settings.

	$setup->vpopmail_etc($conf);

=cut

sub vpopmail_etc($)
{
	my ($self, $conf) = @_;

	my $vpopdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";
	my $vetc    = "$vpopdir/etc";
	my $qdir    = $conf->{'qmail_dir'};

	mkdir($vpopdir, 0775) unless ( -d $vpopdir );

	if ( -d $vetc ) { print "$vetc already exists, skipping.\n"; } 
	else 
	{
		print "creating $vetc\n";
		mkdir($vetc, 0775) or carp "failed to create $vetc: $!\n";
	};

	if ( -f "$vetc/tcp.smtp" ) {
		my @lines = $utility->file_read("$vetc/tcp.smtp");
		my $count = @lines;
		unless ( $count == 1) {
			return 0;
		};
		$utility->file_archive("$vetc/tcp.smtp");
	}

	my @lines = '# RELAYCLIENT="" means IP can relay';
	push @lines, '# RBLSMTPD=""    means DNSBLs are ignored for this IP';
	push @lines, '# QMAILQUEUE=""  is the qmail queue process, defaults to ' . $qdir . '/bin/qmail-queue';
	push @lines, '#';
	push @lines, '#    common QMAILQUEUE settings:';
	push @lines, '# QMAILQUEUE="'.$qdir.'/bin/qmail-queue"';
	push @lines, '# QMAILQUEUE="'.$qdir.'/bin/simscan"';
	push @lines, '# QMAILQUEUE="'.$qdir.'/bin/qmail-scanner-queue.pl\"';
	push @lines, '# ';
	push @lines, '#      handy test settings ';
	push @lines, '# 127.:allow,RELAYCLIENT="",RBLSMTPD="",QMAILQUEUE="'.$qdir.'/bin/simscan"';
	push @lines, '# 127.:allow,RELAYCLIENT="",RBLSMTPD="",QMAILQUEUE="'.$qdir.'/bin/qmail-scanner-queue.pl"';
	push @lines, '# 127.:allow,RELAYCLIENT="",RBLSMTPD="",QMAILQUEUE="'.$qdir.'/bin/qscanq/bin/qscanq"';
	push @lines, '127.0.0.1:allow,RELAYCLIENT="",RBLSMTPD=""';
	push @lines, "";
	my $block = 1;

	if ( $conf->{'vpopmail_enable_netblocks'} ) {
		if ( $utility->yes_or_no("Do you need to enable relay access for any netblocks? :

NOTE: If you are an ISP and have dialup pools, this is where you want
to enter those netblocks. If you have systems that should be able to 
relay through this host, enter their IP/netblocks here as well.\n\n") )
		{
			do
			{
				$block = $utility->answer("the netblock to add (empty to finish)");
				push @lines, "$block:allow" if $block;
			} 
			until (! $block);
		};
	};
	push @lines, "### BEGIN QMAIL SCANNER VIRUS ENTRIES ###";
	push @lines, "### END QMAIL SCANNER VIRUS ENTRIES ###";
	push @lines, '#';
	push @lines, '# Allow anyone with reverse DNS set up';
	push @lines, '#=:allow';
	push @lines, '#    soft block on no reverse DNS ';
	push @lines, '#:allow,RBLSMTPD="Blocked - Reverse DNS queries for your IP fail. Fix your DNS!"';
	push @lines, '#    hard block on no reverse DNS ';
	push @lines, '#:allow,RBLSMTPD="-Blocked - Reverse DNS queries for your IP fail. You cannot send me mail."';
	push @lines, '#    default allow ';
	push @lines, '#:allow,QMAILQUEUE="'.$qdir.'/bin/simscan"';
	push @lines, ":allow";

	$utility->file_write("$vetc/tcp.smtp", @lines);

	if ( -x "/var/qmail/bin/qmailctl" ) 
	{
		print " vpopmail_etc: rebuilding tcp.smtp.cdb\n";
		$utility->syscmd("/var/qmail/bin/qmailctl cdb");
	};
};


sub vpopmail_test
{
	my ($self, $conf) = @_;

	print "do vpopmail directories exist...\n";
	my $vpdir = $conf->{'vpopmail_home_dir'};
	foreach ( (
			"$vpdir",
			"$vpdir/bin",
			"$vpdir/domains",
			"$vpdir/etc/",
			"$vpdir/include",
			"$vpdir/lib",
		) )
	{
		-d $_ ?  $self->_formatted("\t$_", "ok") : $self->_formatted("\t$_", "FAILED");
	};

	print "checking vpopmail binaries...\n";
	foreach ( (
			"$vpdir/bin/clearopensmtp",
			"$vpdir/bin/vaddaliasdomain",
			"$vpdir/bin/vadddomain",
			"$vpdir/bin/vadduser",
			"$vpdir/bin/valias",
			"$vpdir/bin/vchangepw",
			"$vpdir/bin/vchkpw",
			"$vpdir/bin/vconvert",
			"$vpdir/bin/vdeldomain",
			"$vpdir/bin/vdelivermail",
			"$vpdir/bin/vdeloldusers",
			"$vpdir/bin/vdeluser",
			"$vpdir/bin/vdominfo",
			"$vpdir/bin/vipmap",
			"$vpdir/bin/vkill",
			"$vpdir/bin/vmkpasswd",
			"$vpdir/bin/vmoddomlimits",
			"$vpdir/bin/vmoduser",
			"$vpdir/bin/vpasswd",
			"$vpdir/bin/vpopbull",
			"$vpdir/bin/vqmaillocal",
			"$vpdir/bin/vsetuserquota",
			"$vpdir/bin/vuserinfo",
		) )
	{
		-x $_ ?  $self->_formatted("\t$_", "ok") : $self->_formatted("\t$_", "FAILED");
	};

	print "do vpopmail libs exist...\n";
	foreach ( ( "$vpdir/lib/libvpopmail.a",) )
	{
		-e $_ ?  $self->_formatted("\t$_", "ok") : $self->_formatted("\t$_", "FAILED");
	};

	print "do vpopmail includes exist...\n";
	foreach ( ( 
			"$vpdir/include/config.h",
			"$vpdir/include/vauth.h",
			"$vpdir/include/vlimits.h",
			"$vpdir/include/vpopmail.h",
			"$vpdir/include/vpopmail_config.h",
		) )
	{
		-e $_ ?  $self->_formatted("\t$_", "ok") : $self->_formatted("\t$_", "FAILED");
	};

	print "checking vpopmail etc files...\n";
	foreach ( ( 
			"$vpdir/etc/inc_deps",
			"$vpdir/etc/lib_deps",
			"$vpdir/etc/tcp.smtp",
			"$vpdir/etc/tcp.smtp.cdb",
			"$vpdir/etc/vlimits.default",
			"$vpdir/etc/vpopmail.mysql",
		) )
	{
		-e $_ && -s $_ ? $self->_formatted("\t$_", "ok") : $self->_formatted("\t$_", "FAILED");
	};
};


=head2 vpopmail_vmysql_h

	vpopmail_vmysql_h(replication, master, slave, user, pass);

Versions of vpopmail less than 5.2.26 (or thereabouts) required you to manually edit vmysql.h to set your mysql login parameters. This sub modifies that file for you.

=cut

sub vpopmail_vmysql_h 
{
	my ($conf, $mysql_repl, $my_write, $my_read, $my_user, $my_pass) = @_;

	my $vpopdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";

	copy("vmysql.h", "vmysql.h.orig");
	my @lines = $utility->file_read("vmysql.h");

	foreach my $line (@lines) 
	{
		chomp $line;
		if ( $line =~ /^#define MYSQL_UPDATE_SERVER/ ) {
			if ($mysql_repl) {
				$line = "#define MYSQL_UPDATE_SERVER \"$my_write\"";
			} else {
				$line = "#define MYSQL_UPDATE_SERVER \"$my_read\"";
			};
		} 
		elsif ( $line =~ /^#define MYSQL_UPDATE_USER/  ) { $line = "#define MYSQL_UPDATE_USER   \"$my_user\""; } 
		elsif ( $line =~ /^#define MYSQL_UPDATE_PASSWD/) { $line = "#define MYSQL_UPDATE_PASSWD \"$my_pass\""; } 
		elsif ( $line =~ /^#define MYSQL_READ_SERVER/  ) { $line = "#define MYSQL_READ_SERVER   \"$my_read\""; } 
		elsif ( $line =~ /^#define MYSQL_READ_USER/    ) { $line = "#define MYSQL_READ_USER     \"$my_user\""; } 
		elsif ( $line =~ /^#define MYSQL_READ_PASSWD/  ) { $line = "#define MYSQL_READ_PASSWD   \"$my_pass\""; };
	};
	$utility->file_write("vmysql.h", @lines);

	@lines = "$my_read|0|$my_user|$my_pass|vpopmail";
	if ($mysql_repl) {
		push @lines, "$my_write|0|$my_user|$my_pass|vpopmail";
	} else {
		push @lines, "$my_read|0|$my_user|$my_pass|vpopmail";
	};

	$utility->file_write("$vpopdir/etc/vpopmail.mysql", @lines);
};

=head2 vpopmail_mysql_privs

Connects to MySQL server, creates the vpopmail table if it doesn't exist, and sets up a vpopmail user and password as set in $conf. 

    $setup->vpopmail_mysql_privs($conf);

=cut

sub vpopmail_mysql_privs($)
{
	my ($self, $conf) = @_;

	if ( $conf->{'vpopmail_mysql'} )
	{
		my $db   = $conf->{'vpopmail_mysql_database'};
		my $user = $conf->{'vpopmail_mysql_repl_user'};
		my $pass = $conf->{'vpopmail_mysql_repl_pass'};
		my $host = $conf->{'vpopmail_mysql_repl_slave'};

		$perl->module_load( {module=>"Mail::Toaster::Mysql"} );
		my $mysql = Mail::Toaster::Mysql->new();
		my $dot = $mysql->parse_dot_file(".my.cnf", "[mysql]", 0);
		my ($dbh, $dsn, $drh) = $mysql->connect( $dot, 1);
		if ( $dbh )
		{
			my $query = "use vpopmail";
			my $sth = $mysql->query($dbh, $query, 1);
			if ( $sth->errstr ) 
			{
				print "vpopmail: oops, no vpopmail database.\n";
				print "vpopmail: creating MySQL vpopmail database.\n";
				$query = "CREATE DATABASE vpopmail";
				$sth = $mysql->query($dbh, $query);
				$query = "GRANT ALL PRIVILEGES ON $db.* TO $user\@'$host' IDENTIFIED BY '$pass'";
				$sth = $mysql->query($dbh, $query);
				$query = "CREATE TABLE vpopmail.relay ( ip_addr char(18) NOT NULL default '', timestamp char(12) default NULL, name char(64) default NULL, PRIMARY KEY (ip_addr)) TYPE=ISAM PACK_KEYS=1";
				$sth = $mysql->query ($dbh, $query);
				$sth->finish;
			} else {
				print "vpopmail: vpopmail database exists!\n";
				$sth->finish;
			};
		} 
		else
		{
			print <<EOMYSQLGRANT

WARNING: I couldn't connect to your database server!  If this is a new install, 
you will need to connect to your database server and run this command manually:

mysql -u root -h $host -p
CREATE DATABASE vpopmail;
GRANT ALL PRIVILEGES ON $db.* TO $user\@'$host' IDENTIFIED BY '$pass';
use vpopmail;
CREATE TABLE relay ( ip_addr char(18) NOT NULL default '',
  timestamp char(12) default NULL, name char(64) default NULL,
  PRIMARY KEY (ip_addr)) TYPE=ISAM PACK_KEYS=1;
quit;

If this is an upgrade and you already use MySQL authentication, 
then you can safely ignore this warning.

EOMYSQLGRANT
		};
	};
};


=head2 vqadmin

	$setup->vqadmin($conf, $debug);

Installs vqadmin from ports on FreeBSD and from sources on other platforms. It honors your cgi-bin and your htdocs directory as configured in toaster-watcher.conf.

=cut

sub vqadmin($;$)
{
	my ($self, $conf, $debug) = @_;

	my $cgi  = $conf->{'toaster_cgi-bin'}   || "/usr/local/www/cgi-bin";
	my $data = $conf->{'toaster_http_docs'} || "/usr/local/www/data";

	my @defs = 'CGIBINDIR="' . $cgi. '"';
	push @defs, 'WEBDATADIR="' . $data . '"';

	if ( $os eq "freebsd") 
	{
		$freebsd->port_install("vqadmin", "mail", undef, undef, join(",", @defs) );
	} 
	else 
	{
		print "not done for $os yet, trying to build from sources\n";
		$utility->install_from_source($conf, 
			{ 
				package=> "vqadmin", 
				site   => "http://vpopmail.sf.net", 
				url    => "/downloads", 
				targets=> ["./configure ", "gmake", "gmake install-strip"],
				source_sub_dir => 'mail',
			} 
		);
	};
};


sub _formatted
{
	my ($self, $mess, $result) = @_;

	my $dots;
	my $len = length($mess);
	if ($len < 65) { until ( $len == 65 ) { $dots .= "."; $len++ }; };
	print "$mess $dots $result\n";
}


1;
__END__


=head1 AUTHOR

Matt Simerson - matt@tnpi.biz

=head1 BUGS

None known. Report any to matt@cadillac.net.

=head1 TODO

Documentation. It's almost reasonable now.

=head1 SEE ALSO

The following are all man/perldoc pages: 

 Mail::Toaster 
 Mail::Toaster::Conf
 toaster.conf
 toaster-watcher.conf

 http://matt.simerson.net/computing/mail/toaster/

=head1 COPYRIGHT

Copyright (c) 2004-2005, The Network People, Inc.
All rights reserved.
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut
