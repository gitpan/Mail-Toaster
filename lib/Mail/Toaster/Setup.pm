#!/usr/bin/perl
use strict;

#
# $Id: Setup.pm,v 1.33 2004/02/16 16:57:59 matt Exp $
#

package Mail::Toaster::Setup;

use Carp;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION  = '3.33';

@ISA = qw(Exporter);
@EXPORT = qw( 
	InstallApache
	InstallFilter 
	InstallClamAV
	InstallCourier 
	InstallEzmlm 
	InstallMATTBundle
	InstallMaildropFiles
	InstallMailLogs 
	InstallMysqld
	InstallPhpMyAdminW
	InstallPorts
	InstallQmail
	InstallQmailadmin
	InstallQmailScanner
	InstallQmailScannerStats
	InstallRRDutil
	InstallSources
	InstallSquirrelmail 
	InstallSqwebmail 
	InstallSocklog 
	InstallSupervise 
	InstallToasterDependencies 
	InstallUCSPI
	InstallVpopmail 
	InstallVqadmin
	ConfigIsoqlog
	ConfigVpopmailEtc
);
@EXPORT_OK = qw(
	ApacheConfPatch
);


=head1 NAME

Mail::Toaster::Setup

=head1 DESCRIPTION

The meat and potatoes of toaster_setup.pl. This is where the majority of the work gets done. Big chunks of the code got moved here, mainly because toaster_setup.pl was getting rather unwieldly. The biggest benefit requiring me to clean up the code considerably. It's now in nice tidy little subroutines that are pretty easy to read and understand.

=cut 

use MATT::Utility 1.20;
use MATT::Perl 1.00;


sub ConfigIsoqlog
{
	my ($conf) = @_;

	my $file = "/usr/local/etc/isoqlog.conf";
	if ( -e $file) { print "ConfigIsoqlog: skipping (already done).\n"; return 1; };

	my @lines;

	my $htdocs = $conf->{'toaster_http_docs'};
	my $hostn  = $conf->{'toaster_hostname'};
	unless ($htdocs) { $htdocs = "/usr/local/www/data"; };
	unless ($hostn ) { $hostn  = `hostname`; };

	push @lines, "#isoqlog Configuration file";
	push @lines, "";
	push @lines, 'logtype = "qmail-multilog"';
	push @lines, 'logstore = "/var/log/mail/send"';
	push @lines, 'domainsfile = "/var/qmail/control/rcpthosts"';
	push @lines, 'outputdir = "' . $htdocs . '/isoqlog"';
	push @lines, 'htmldir = "/usr/local/share/isoqlog/htmltemp"';
	push @lines, 'langfile = "/usr/local/share/isoqlog/lang/english"';
	push @lines, 'hostname = "' . $hostn . '"';
	push @lines, "";
	push @lines, "maxsender   = 100";
	push @lines, "maxreceiver = 100";
	push @lines, "maxtotal    = 100";
	push @lines, "maxbyte     = 100";

	MATT::Utility::WriteFile($file, @lines);

	SysCmd("/usr/local/bin/isoqlog");

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
		SysCmd("cp -r /usr/local/share/isoqlog/htmltemp/images $htdocs/isoqlog/images");
	};
};

sub InstallPhpMyAdminW
{

=head2 InstallPhpMyAdminW

	use Mail::Toaster::Setup;
	InstallPhpMyAdminW($conf);

Installs PhpMyAdmin for you, based on your settings in toaster-watcher.conf. The actual code that does the work is in MATT::Mysql (part of MATT::Bundle) so read the man page for MATT::Mysql for more info.

=cut

	my ($conf) = @_;

	use MATT::Mysql;
	MATT::Mysql::InstallPhpMyAdmin();
};

sub InstallVqadmin
{

=head2 InstallVqadmin

	use Mail::Toaster::Setup;
	InstallVqadmin($conf);

Installs vqadmin from FreeBSD ports. It honors your cgi-bin and your htdocs directory as configured in toaster-watcher.conf.

=cut

	my ($conf) = @_;

	my @defs = 'CGIBINDIR="/usr/local/www/cgi-bin"';
	push @defs, 'WEBDATADIR="/usr/local/www/data"';
	use MATT::FreeBSD 1.10;
	MATT::FreeBSD::InstallPort("vqadmin", "mail", undef, undef, join(",", @defs) );
};

sub InstallMysqld
{

=head2 InstallMysqld

	use Mail::Toaster::Setup;
	InstallMysqld($conf);

Installs mysql server for you, based on your settings in toaster-watcher.conf. The actual code that does the work is in MATT::Mysql (part of MATT::Bundle) so read the man page for MATT::Mysql for more info.

=cut

	my ($conf) = @_;

	use MATT::Mysql;
	MATT::Mysql::InstallMysql(undef,undef,$conf->{'install_mysql'}, $conf);
};

sub InstallSources
{

=head2 InstallSources

	use Mail::Toaster::Setup;
	InstallSources($conf, $toaster);

Update your FreeBSD source tree (/usr/src). Uses cvsup_fastest to pick the fastest server in your country (configure in toaster-watcher.conf) and then updates from there. Updates based on any cvsup settings in /etc/cvsup-stable). Configure that file to suit your preferences. If that file doesn't exist, it will be created for you.

=cut

	my ($conf, $toaster) = @_;

	use MATT::FreeBSD 1;
	unless ($toaster) { $toaster = "http://www.tnpi.biz/internet/mail/toaster"; };

	MATT::FreeBSD::UpdateSrcTree($toaster, $conf->{'cvsup_server_preferred'}, 
		$conf->{'cvsup_server_country'});
};


sub ApacheConfPatch
{

=head2 ApacheConfPatch

 # moved to MATT::Apache
 # delete this sub at some point

	use MATT::Apache;   
	ApacheConfPatch;    

=cut

	unless ( -e "contrib/httpd.conf-2.0.patch") 
	{
		print "FAILURE: you must run this while in the Mail::Toaster directory!\n";
		return 1;
	};

	my $httpd = "/usr/local/etc/apache2/httpd.conf";

	if ( -e $httpd )
	{
		SysCmd("patch $httpd contrib/httpd.conf-2.0.patch");
	} else {
		print "FAILURE: I couldn't find your httpd.conf!\n";
		return 1;
	};
	return 0;
};

sub InstallMATTBundle
{

=head2 InstallMATTBundle

	use Mail::Toaster::Setup;
	InstallMATTBundle;

Downloads and installs the latest version of MATT::Bundle.

=cut

	my $src = "/usr/local/src";
	unless ( -d $src) {
		SysCmd("mkdir -p /usr/local/src") or croak "InstallMATTBundle: couldn't create $src: $!\n";
	};
	chdir($src) or croak "InstallMATTBundle: couldn't cd to $src!\n";
	SysCmd("rm -rf MATT-Bundle-*");   # nuke any old versions
	MATT::Utility::FetchFile("http://www.tnpi.biz/computing/perl/MATT-Bundle/MATT-Bundle.tar.gz");
	if ( -e "MATT-Bundle.tar.gz" ) {
		SysCmd("tar -xzf MATT-Bundle.tar.gz");
	} else {
		croak "InstallMATTBundle FAILED: couldn't fetch MATT-Bundle.tar.gz!\n";
	};
	
	foreach my $file ( GetDirFiles($src) ) 
	{
		if ( $file =~ /MATT-Bundle-/ ) {
			chdir($file);
			SysCmd("perl Makefile.PL");
			SysCmd("make install");
			last;
		};
	};
};

sub InstallRRDutil
{

=head2 InstallRRDutil

	use Mail::Toaster::Setup;
	InstallRRDutil;

Checks for and installs any missing programs upon which RRDutil depends (rrdtool, net-snmp, Net::SNMP, Time::Date) and then downloads and installs the latest version of RRDutil. 

If upgrading, it is wise to check for differences in your installed rrdutil.conf and the latest rrdutil.conf-dist included in the RRDutil distribution.

=cut

	my ($conf) = @_;

	use MATT::FreeBSD 1.20 qw/ InstallPort /;

	InstallPort("rrdtool",     "net",  undef, undef, undef, 1 );
	InstallPort("net-snmp",    "net",  undef, undef, undef, 1 );
	InstallPort("p5-Net-SNMP", "net",  undef, undef, undef, 1 );
	InstallPort("p5-TimeDate", "devel",undef, undef, undef, 1 );

	my $src = $conf->{'toaster_src_dir'};
	unless ($src) { $src = "/usr/local/src"; };

	unless ( -d $src) {
		SysCmd("mkdir -p $src") or croak "InstallRRDutil: couldn't create $src: $!\n";
	};
	chdir($src) or croak "InstallRRDutil: couldn't cd to $src!\n";
	SysCmd("rm -rf RRDutil-*");   # nuke any old versions
	MATT::Utility::FetchFile("http://www.tnpi.biz/internet/manage/rrdutil/RRDutil.tar.gz");
	unless ( -e "RRDutil.tar.gz" ) {
		croak "InstallRRDutil FAILED: couldn't fetch RRDutil.tar.gz!\n";
	};
	SysCmd("tar -xzf RRDutil.tar.gz");
	
	foreach my $file ( GetDirFiles($src) ) 
	{
		if ( $file =~ /RRDutil-/ ) 
		{
			chdir($file);

			SysCmd("perl Makefile.PL");
			SysCmd("make install");

			if ( -e "/usr/local/etc/rrdutil.conf") {
				SysCmd("make conf");
			} else {
				SysCmd("make newconf");
			};

			if ( -e "/usr/local/www/cgi-bin") {
				SysCmd("make freebsd");
			};

			if ( -e "/Library/WebServer/CGI-Executables") {
				SysCmd("make darwin");
			};

			unless ( -e "/usr/local/share/snmpd/snmpd.conf" ) {
				SysCmd("cp contrib/snmpd.conf /usr/local/share/snmp");
			};

			if ( `grep snmpd_enable /etc/rc.conf` ) {
				SysCmd("/usr/local/etc/rc.d/snmpd.sh restart");
			} else {
				CheckRcDotConf("snmpd_enable", "snmpd_enable=\"YES\"");
				print "\n\nNOTICE:  I added snmpd_enable=\"YES\" to /etc/rc.conf!\n\n";
				SysCmd("/usr/local/etc/rc.d/snmpd.sh restart");
			};
			chdir("..");
			SysCmd("rm -rf $file");
			last;
		};
	};
};

sub InstallPorts
{

=head2 InstallPorts

	use Mail::Toaster::Setup;
	InstallPorts($conf, $toaster);

Install the FreeBSD ports tree and update it with cvsup. Optionally uses cvsup_fastest to choose the fastest cvsup server to mirror from. Configure toaster-watch.conf to adjust it's behaviour.

Installs the portupgrade port to use for updating your legacy installed ports. Portupgrade is very useful, but be very careful about using portupgrade -a. I always use portupgrade -ai and skip the toastser related ports such as qmail since we have customized version(s) of them installed.

=cut

	my ($conf, $toaster) = @_;

	use MATT::FreeBSD 1;
	unless ($toaster) { $toaster = "http://www.tnpi.biz/internet/mail/toaster"; };

	MATT::FreeBSD::UpdatePortsTree($toaster, $conf->{'cvsup_server_preferred'}, 
		$conf->{'cvsup_server_country'});


	if ( $conf->{'install_portupgrade'} ) 
	{
		my $package = $conf->{'package_install_method'};
		unless ($package) { $package = "packages"; };

		if ( $package eq "port" ) 
		{
			MATT::FreeBSD::InstallPort("ruby", "lang");
			MATT::FreeBSD::InstallPort("ruby-gdbm", "databases");
		}
		else
		{
			MATT::FreeBSD::InstallPackage("ruby");
			MATT::FreeBSD::InstallPackage("ruby-gdbm");
		};

		MATT::FreeBSD::InstallPort   ("portupgrade",   "sysutils");
		print "\n\n
\tAt this point I recommend that you run pkgdb -F, and then 
\tportupgrade -ai, upgrading everything except XFree86 and 
\tother non-mail related items.\n
\tIf you have problems upgrading a particular port, then I recommend
\tremoving it (pkg_delete port_name-1.2) and then proceeding.\n\n";
	};
};

sub InstallApache
{

=head2 InstallApache

	use Mail::Toaster::Setup;
	InstallApache($conf, $version);

Calls MATT::Apache::InstallApache[1|2] which then builds and install Apache for you based on how it was called. See MATT::Apache:InstallApache (part of MATT::Bundle) for more details.

=cut

	my ($conf, $ver) = @_;

	my $src = $conf->{'toaster_src_dir'};
	unless ($src) { $src = "/usr/local/src"; };
	unless ($ver) { $ver = $conf->{'install_apache'}; };

	use MATT::Apache 1;

	if    ( lc($ver) eq "apache" or lc($ver) eq "apache1" or $ver == 1) 
	{ 
		MATT::Apache::InstallApache1($src); 
	} 
	elsif ( $ver eq "ssl" )
	{
		MATT::Apache::InstallApacheSSLCerts("rsa");
	}
	else 
	{
		MATT::Apache::InstallApache2(); 
	};

	unless ( IsProcessRunning("httpd") )
	{
		if ( -x "/usr/local/etc/rc.d/apache.sh" ) 
		{
			SysCmd("/usr/local/etc/rc.d/apache.sh startssl");
		};
	};
};

sub InstallVpopmail 
{

=head2 InstallVpopmail

	use Mail::Toaster::Setup;
	InstallVpopmail($conf);

Vpopmail is great, but it has lots of options and remembering which option you used months or years ago to build a mail server isn't always easy. So, store all the settings in toaster-watcher.conf and this sub will install vpopmail for you honoring all your settings and passing the appropriate configure flags to vpopmail's configure.

If you don't have toaster-watcher.conf installed, it'll ask you a series of questions and then install based on your answers.

=cut

	my ($conf)  = @_;
	my ($ans, $ddom, $ddb, $cflags, $my_write, $conf_args, $mysql);

	my $version = $conf->{'install_vpopmail'};
	unless ($version) { $version = "5.4.0"; };

	if ( $version eq "port" || $conf->{'install_vpopmail'} eq "port" ) {
		my @defs = "WITH_CLEAR_PASSWD";
		push @defs, "WITH_LEARN_PASSWORDS";
		push @defs, "WITH_MYSQL";
		if ( $conf->{'vpopmail_mysql_replication'} ) {
			push @defs, "WITH_MYSQL_REPLICATION";
		};

		if ( $conf->{'vpopmail_mysql_limits'} ) {
			push @defs, "WITH_MYSQL_LIMITS";
		};

		if ( $conf->{'vpopmail_ip_alias_domains'} ) {
			push @defs, "WITH_IP_ALIAS";
		};

		if ( $conf->{'vpopmail_qmail_extensions'} ) {
			push @defs, "WITH_QMAIL_EXT";
		};

		if ( $conf->{'vpopmail_qmail_extensions'} ) {
			push @defs, "WITH_QMAIL_EXT";
		};

		if ( $conf->{'vpopmail_domain_quotas'} ) {
			push @defs, "WITH_DOMAIN_QUOTAS";
		};

		push @defs, 'WITH_MYSQL_SERVER="' . $conf->{'vpopmail_mysql_repl_master'} . '"';
		push @defs, 'WITH_MYSQL_USER="'   . $conf->{'vpopmail_mysql_repl_user'} . '"';
		push @defs, 'WITH_MYSQL_PASSWD="' . $conf->{'vpopmail_mysql_repl_pass'} . '"';
		push @defs, 'WITH_MYSQL_DB="'     . $conf->{'vpopmail_mysql_database'} . '"';
		push @defs, 'WITH_MYSQL_READ_SERVER="' . $conf->{'vpopmail_mysql_repl_slave'} . '"';

		push @defs, 'LOGLEVEL="p"';

		MATT::FreeBSD::InstallPort("vpopmail", "port", undef, undef, join(",", @defs), 1 );
		return 1;
	};

	my $package    = "vpopmail-$version";
	my $site       = "http://aleron.dl.sourceforge.net/sourceforge/vpopmail";
	#my $site       = "http://www.inter7.com/devel";
	my $tar        = MATT::Utility::FindTheBin("tar");

	my $vpopdir = $conf->{'vpopmail_home_dir'};
	unless ($vpopdir) { $vpopdir = "/usr/local/vpopmail"; };

	use MATT::Passwd;
	MATT::Passwd::InstallGroup  ("vchkpw", "89");
	MATT::Passwd::InstallUser   ("vpopmail", "", $vpopdir);

	ConfigVpopmailEtc($conf);

	unless ( defined $conf->{'vpopmail_mysql'} && $conf->{'vpopmail_mysql'} == 0 ) {
		$mysql = 1;

		if ( is_newer("5.3.30", $version) )
		{
			$conf_args = "--enable-auth-module=mysql "; 
		} else {
			$conf_args = "--enable-mysql=y "; 
		};
		print "authentication module: mysql\n";
	} 
	else { print "authentication module: cdb\n"; };

	unless ( defined $conf->{'vpopmail_rebuild_tcpserver_file'} && $conf->{'vpopmail_rebuild_tcpserver_file'} == 1 ) 
	{
		$conf_args .= " --enable-rebuild-tcpserver-file=n";
		print "rebuild tcpserver file: no\n";
	};

	unless ( is_newer("5.3.30", $version) )
	{
		if ( defined $conf->{'vpopmail_default_quota'} ) {
			$conf_args   .= " --enable-defaultquota=$conf->{'vpopmail_default_quota'}";
			print "default quota: $conf->{'vpopmail_default_quota'}\n";
		} else {
			$conf_args   .= " --enable-defaultquota=100000000S,10000C";
			print "default quota: 100000000S,10000C\n";
		};
	};

	if ( defined $conf->{'vpopmail_roaming_users'} ) 
	{
		if ( $conf->{'vpopmail_roaming_users'} ) 
		{
			$conf_args .= " --enable-roaming-users=y";
			print "roaming users: yes\n";
		} 
		else 
		{
			$conf_args .= " --enable-roaming-users=n";
			print "roaming users: no\n";
		};
	} 
	else 
	{
		$conf_args   .= " --enable-roaming-users=y";
		print "roaming users: yes\n";
	};

	my $src = $conf->{'toaster_src_dir'};
	unless ($src) { $src = "/usr/local/src"; };

	MATT::Utility::CdSrcDir("$src/mail");

	if ( !-e "$package.tar.gz" ) {
		MATT::Utility::FetchFile("$site/$package.tar.gz");
		unless ( -e "$package.tar.gz" ) {
			carp "InstallVpopmail FAILED: Couldn't fetch $package.tar.gz!\n";
			exit 0;
		};
	};

	if ( -d $package )
	{
		my $r = SourceWarning($package, 1, $src);
		if (! $r) { croak "InstallVpopmail: sorry, I can't continue.\n"; };
	};
	MATT::Utility::SysCmd( "$tar -xzf $package.tar.gz");

	unless ( defined $conf->{'vpopmail_learn_passwords'} && $conf->{'vpopmail_learn_passwords'} == 0 ) {
		$conf_args    = $conf_args . " --enable-learn-passwords=y";
		print "learning passwords yes\n";
	} else {
		if ( MATT::Utility::YesOrNo("Do you want password learning? (y) ") ) {
			$conf_args    = $conf_args . " --enable-learn-passwords=y";
			print "password learning: yes\n";
		} else {
			print "password learning: no\n";
		};
	};

	unless ( defined $conf->{'vpopmail_logging'} ) {
		if ( MATT::Utility::YesOrNo("Do you want logging enabled? (y) ") )
		{
			if ( MATT::Utility::YesOrNo("Do you want verbose logging? (y) ") )
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
		if ( YesOrNo("Do you want to use a default domain? ") )
		{
			my $ddom = GetAnswer("your default domain");
	
			my @lines;
			if ( is_newer("5.3.22", $version) )
			{
				push @lines, $ddom;
				WriteFile("$vpopdir/etc/defaultdomain", @lines);
				chown();
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
				push my @lines, $conf->{'vpopmail_default_domain'};
				WriteFile("$vpopdir/etc/defaultdomain", @lines);
				chown();
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

		if ( YesOrNo("Do system users (/etc/passwd) get mail? (n) ") ) {
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
		if ( YesOrNo("Do you use valias processing? (n) ") ) { 
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
		if ( YesOrNo("Do you want mysql logging? (n) " ) ) { 
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
		if ( YesOrNo("Do you want qmail extensions? (n) ") ) { 
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

			if ( YesOrNo("Do you want mysql limits? (n) ") ) { 
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
			$mysql_repl = YesOrNo("Do you want mysql replication enabled? (n) ");
			if ($mysql_repl) 
			{
				$conf_args .= " --enable-mysql-replication=y";
				if ($ddom) { $ddb = "db.$ddom"; } else { $ddb = "db"; };
				$my_write = GetAnswer("your MySQL master servers hostname", $ddb);
				$my_read  = GetAnswer("your MySQL read server hostname", "localhost");
				$my_user  = GetAnswer("your MySQL user name", "vpopmail");
				$my_pass  = GetAnswer("your MySQL password");
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

		chdir($package);
		SetupVmysql($mysql_repl, $my_write, $my_read, $my_user, $my_pass);
	};

	unless ( defined $conf->{'vpopmail_domain_quotas'} ) {
		if ( YesOrNo("Do you want vpopmail's domain quotas? (n) ")) { 
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
	SysCmd( "./configure $conf_args");
	SysCmd( "make");
	SysCmd( "make install-strip");
	SysCmd( "cp vlimits.h $vpopdir/include/");
};

sub is_newer
{

=head2 is_newer

Checks a three place version string like 5.3.24 to see if the current version is newer than some value. Useful when you have various version of a program like vpopmail or mysql and the syntax you need to use for building it is different for differing version of the software.

=cut

	my ($min, $cur) = @_;

	$min =~ /^([0-9]+)\.([0-9]{1,})\.([0-9]{1,})$/;
	my @mins = ( $1, $2, $3 );
	$cur =~ /^([0-9]+)\.([0-9]{1,})\.([0-9]{1,})$/;
	my @curs = ( $1, $2, $3 );
        
	if ( $curs[0] > $mins[0] ) { return 1; };
	if ( $curs[1] > $mins[1] ) { return 1; };            
	if ( $curs[2] > $mins[2] ) { return 1; };
        
	return 0;
}       
        
sub SetupVmysql 
{

=head2 SetupVmysql

	use Mail::Toaster::Setup;
	SetupVmysql(replication, master, slave, user, pass);

Version of vpopmail less than 5.2.26 (or thereabouts) required you to manually edit vmysql.h to set your mysql login parameters. This sub modifies that file for you.

=cut

	my ($mysql_repl, $my_write, $my_read, $my_user, $my_pass) = @_;

	use File::Copy;
	copy("vmysql.h", "vmysql.h.orig");
	my @lines = ReadFile("vmysql.h");

	foreach my $line (@lines) {
		chomp $line;
		if      ( $line =~ /^#define MYSQL_UPDATE_SERVER/ ) {
			if ($mysql_repl) {
				$line = "#define MYSQL_UPDATE_SERVER \"$my_write\"";
			} else {
				$line = "#define MYSQL_UPDATE_SERVER \"$my_read\"";
			};
		} elsif ( $line =~ /^#define MYSQL_UPDATE_USER/ ) {
			$line = "#define MYSQL_UPDATE_USER   \"$my_user\"";
		} elsif ( $line =~ /^#define MYSQL_UPDATE_PASSWD/ ) {
			$line = "#define MYSQL_UPDATE_PASSWD \"$my_pass\"";
		} elsif ( $line =~ /^#define MYSQL_READ_SERVER/ ) {
			$line = "#define MYSQL_READ_SERVER   \"$my_read\"";
		} elsif ( $line =~ /^#define MYSQL_READ_USER/ ) {
			$line = "#define MYSQL_READ_USER     \"$my_user\"";
		} elsif ( $line =~ /^#define MYSQL_READ_PASSWD/ ) {
			$line = "#define MYSQL_READ_PASSWD   \"$my_pass\"";
		};
	};
	WriteFile("vmysql.h", @lines);

	@lines = "$my_read|0|$my_user|$my_pass|vpopmail";
	if ($mysql_repl) {
		push @lines, "$my_write|0|$my_user|$my_pass|vpopmail";
	} else {
		push @lines, "$my_read|0|$my_user|$my_pass|vpopmail";
	};

	WriteFile("/usr/local/vpopmail/etc/vpopmail.mysql", @lines);
};

sub InstallSquirrelmail 
{

=head2 InstallSquirrelmail

	Use Mail::Toaster::Setup;
	InstallSquirrelmail

Installs Squirrelmail using FreeBSD ports. Adjusts the FreeBSD port by passing along WITH_APACHE2 if you have Apache2 selected installed in your toaster-watcher.conf.

=cut

	my ($conf) = @_;

	if ($conf->{'install_apache'} == 2) 
	{
		MATT::FreeBSD::InstallPort("squirrelmail", "mail", undef, undef, "WITH_APACHE2", 1);
	} 
	else 
	{
		MATT::FreeBSD::InstallPort("squirrelmail", "mail", undef, undef, undef, 1);
	};

	if ( -d "/usr/local/www/squirrelmail" )
	{
		unless ( -e "/usr/local/www/squirrelmail/config/config.php")
		{
			my $dl_site = $conf->{'toaster_dl_site'};
			unless ($dl_site) { $dl_site = "http://www.tnpi.biz"; };

			print "InstallSquirrelmail: installing a default config.php";
			chdir("/usr/local/www/squirrelmail/config");
			MATT::Utility::FetchFile("$dl_site/internet/mail/toaster/etc/config.txt");
			MATT::Utility::SysCmd("cp config.txt config.php");
		};
	};
};

sub InstallMailLogs 
{

=head2 InstallMailLogs

	use Mail::Toaster::Setup;
	InstallMailLogs($conf);

Installs the maillogs script, creates the logging directories (/var/log/mail/*), creates the qmail supervise dirs, installs maillogs as a log post-process and then builds the corresponding service/log/run file to use the post-processor.

=cut

	my ($conf) = @_;

	use File::Copy;

	my $log = $conf->{'qmail_log_base'};
	unless ($log) { $log = "/var/log/mail"; };

	my $user = $conf->{'qmail_log_user'};
	unless ($user) { $user = "qmaill" };

	my $group = $conf->{'qmail_log_group'};
	unless ($group) { $group = "qnofiles"; };

	my $uid = getpwnam($user);
	my $gid = getgrnam($group);

	my $supervise = $conf->{'qmail_supervise'};
	unless ($supervise) { $supervise = "/var/qmail/supervise"; };

	if ( $conf->{'install_isoqlog'} )
	{
		InstallPort("isoqlog", "mail");
		ConfigIsoqlog($conf);
	};

	CreateSuperviseDirs($supervise);

	InstallQmailSuperviseLogRunFiles($conf);

	unless ( -d $log ) 
	{ 
		print "InstallMailLogs: creating $log\n";
		mkdir($log, 0755) or croak "InstallMailLogs: couldn't create $log: $!";
		chown($uid, $gid, $log) or croak "InstallMailLogs: couldn't chown $log: $!";
	};

	foreach my $prot ( qw/ send smtp pop3 submit / )
	{
		if ( ! -d "$log/$prot" ) 
		{
			print "InstallMailLogs: creating $log/$prot\n";
			mkdir("$log/$prot", 0755) or croak "InstallMailLogs: couldn't create: $!";
		} 
		else 
		{
			print "InstallMailLogs: $log/$prot exists\n";
		};
		chown($uid, $gid, "$log/$prot") or croak "InstallMailLogs: chown $log/$prot failed: $!";
	};

	my $maillogs = "/usr/local/sbin/maillogs";

	if ( ! -e $maillogs ) 
	{
		my $dl_site = $conf->{'toaster_dl_site'};
		unless ($dl_site) { $dl_site = "http://www.tnpi.biz"; };
		MATT::Utility::FetchFile("$dl_site/internet/mail/maillogs/maillogs");
		unless ( -e "maillogs" ) {
			croak "InstallMailLogs FAILED: couldn't fetch maillogs!\n";
		};
		move("maillogs", $maillogs);
		chmod(0755, $maillogs);
	};

	if ( ! -e "$log/send/sendlog" ) 
	{
		copy ($maillogs,  "$log/send/sendlog");
		chown($uid, $gid, "$log/send/sendlog");
		chmod(0755,       "$log/send/sendlog");
	};

	if ( ! -e "$log/smtp/smtplog" ) 
	{
		copy ($maillogs,  "$log/smtp/smtplog");
		chown($uid, $gid, "$log/smtp/smtplog");
		chmod(0755,       "$log/smtp/smtplog");
	};

	if ( ! -e "$log/pop3/pop3log" ) 
	{
		copy ($maillogs,  "$log/pop3/pop3log");
		chown($uid, $gid, "$log/pop3/pop3log");
		chmod(0755,       "$log/pop3/pop3log");
	};
};


sub InstallSocklog 
{

=head2 InstallSockLog

	use Mail::Toaster::Setup;
	InstallSockLog($conf, $ip);

If you need to use socklog, then you'll appreciate how nicely this configures it. :)  $ip is the IP address of the socklog master server.

=cut

	my ($conf, $ip) = @_;

	my $user = $conf->{'qmail_log_user'};
	unless ($user) { $user = "qmaill" };

	my $group = $conf->{'qmail_log_group'};
	unless ($group) { $group = "qnofiles"; };

	my $uid = getpwnam($user);
	my $gid = getgrnam($group);

	my $log = "/var/log/mail";

	InstallPort("socklog", "sysutils");
	InstallSocklogQmailControl("send", $ip, $user);
	InstallSocklogQmailControl("smtp", $ip, $user);
	InstallSocklogQmailControl("pop3", $ip, $user);

	unless ( -d $log ) 
	{ 
		mkdir($log, 0755) or croak "InstallSocklog: couldn't create $log: $!";
		chown($uid, $gid, $log) or croak "InstallSocklog: couldn't chown $log: $!";
	};

	foreach my $prot ( qw/ send smtp pop3 / )
	{
		unless ( -d "$log/$prot" ) {
			mkdir("$log/$prot", 0755) or croak "InstallSocklog: couldn't create $log/$prot: $!";
		};
		chown($uid, $gid, "$log/$prot") or croak "InstallSocklog: couldn't chown $log/$prot: $!";
	};
};

sub InstallSocklogQmailControl 
{

=head2 InstallSocklogQmailControl

	use Mail::Toaster::Setup;
	InstallSocklogQmailControl($service, $ip, $user, $supervisedir);

Builds a service/log/run file for use with socklog.

=cut

	my ($serv, $ip, $user, $supervise)  = @_;

	unless ($ip)   { $ip = "192.168.2.9"; };
	unless ($user) { $user = "qmaill"; };
	unless ($supervise) { $supervise = "/var/qmail/supervise"; };

	my $run_f   = "$supervise/$serv/log/run";

	if ( ! -s $run_f ) 
	{
		print "InstallSocklogQmailControl creating: $run_f...";
		open(RUN, ">$run_f") or croak "InstallSocklogQmailControl: couldn't open for write: $!";
		print RUN "#!/bin/sh\n";
		print RUN "LOGDIR=/var/log/mail\n";
		print RUN "LOGSERVERIP=$ip\n";
		print RUN "PORT=10116\n";
		print RUN "PATH=/var/qmail/bin:/usr/local/bin:/usr/bin:/bin\n";
		print RUN "export PATH\n";
		print RUN "exec setuidgid $user multilog t s4096 n20 \\\n";
		print RUN "  !\"tryto -pv tcpclient -v \$LOGSERVERIP \$PORT sh -c 'cat >&7'\" \\\n";
		print RUN "  \${LOGDIR}/$serv\n";
		close RUN;
		chmod(0755, $run_f) or croak "InstallSocklog: couldn't chmod $run_f: $!";
		print "done.\n";
	} else {
		print "InstallSocklogQmailControl skipping: $run_f exists!\n";
	};
};

sub InstallFilter 
{

=head2 InstallFilter

	use Mail::Toaster::Setup;
	InstallFilter($conf);

Installs SpamAssassin, ClamAV, QmailScanner, maildrop, procmail, and programs that support the aforementioned ones. See toaster-watcher.conf for options that allow you to customize the programs that are installed.

=cut

	my ($conf) = @_;

	my $toaster = "$conf->{'toaster_dl_site'}$conf->{'toaster_dl_url'}";
	unless ($toaster) { $toaster = "http://www.tnpi.biz/internet/mail/toaster"; };

	use MATT::FreeBSD 1.20;

	if ( $conf->{'install_maildrop'} ) {
		MATT::FreeBSD::InstallPort ("maildrop", "mail", undef, undef, "WITH_MAILDIRQUOTA", 1);
		InstallMaildropFiles($toaster);
	};

	if ( $conf->{'install_procmail'} ) {
		MATT::FreeBSD::InstallPort ("procmail", "mail");
	};

	MATT::FreeBSD::InstallPort ("p5-Time-HiRes", "devel" );

	if ( $conf->{'install_spamassassin'} ) 
	{
		MATT::FreeBSD::InstallPort ("p5-Mail-Audit", "mail" , undef, undef, undef, 1 );
		MATT::FreeBSD::InstallPort ("p5-Mail-SpamAssassin", "mail", undef, undef, undef, 1);

		unless ( -e "/usr/local/etc/rc.d/spamd.sh" ) {
			chdir("/usr/local/etc/rc.d");
			SysCmd("cp spamd.sh-dist spamd.sh");
		};

		CheckRcDotConf("spamd_enable", "spamd_enable=\"YES\"");
		my $flags = $conf->{'install_spamassassin_flags'};
		unless ($flags) { $flags = "-a -d -v -q -x -r /var/run/spamd.pid" };
		CheckRcDotConf("spamd_flags", "spamd_flags=\"$flags\"");

		unless ( IsProcessRunning("spamd") ) 
		{
			if ( -x "/usr/local/etc/rc.d/spamd.sh" ) 
			{
				print "Starting SpamAssassin...";
				SysCmd("/usr/local/etc/rc.d/spamd.sh restart");
				print "done.\n";
			} 
			else { print "WARN: couldn't start SpamAssassin's spamd.\n"; };
		};
	};

	if ( $conf->{'install_pyzor'} ) 
	{
		MATT::FreeBSD::InstallPort ("pyzor", "mail", undef, undef, undef, 1);
	};

	if ( $conf->{'install_razor'} ) 
	{
		MATT::FreeBSD::InstallPort ("razor-agents", "mail", undef, undef, undef, 1);
	};

	if ( $conf->{'install_bogofilter'} ) 
	{
		MATT::FreeBSD::InstallPort ("bogofilter", "mail");
	};

	if ( $conf->{'install_dcc'} ) 
	{
		MATT::FreeBSD::InstallPort ("dcc-dccd", "mail", undef, undef, undef, 1 );
	};

	if ( $conf->{'install_clamav'} ) { InstallClamAV($conf); };

	if ( $conf->{'install_qmailscanner'} ) 
	{
		MATT::FreeBSD::InstallPort ("tnef", "converters");
		MATT::FreeBSD::InstallPort ("unzip","archivers" );

		InstallQmailScanner($conf);
	};
};

sub InstallMaildropFiles
{

=head2 InstallMaildropFiles

	use Mail::Toaster::Setup;
	InstallMaildropFiles($toaster_site_url);

Installs a maildrop filter in /usr/local/etc/mail/mailfilter, a script for use with Courier-IMAP in /usr/local/sbin/subscribeIMAP.sh, and sets up a filter debugging file in /var/log/mail/maildrop.log.

=cut

	my ($toaster) = @_;
	unless ($toaster) { $toaster = "http://www.tnpi.biz/internet/mail/toaster"; };

	my $filterfile = "/usr/local/etc/mail/mailfilter";

	my $uid = getpwnam("vpopmail");
	my $gid = getgrnam("vchkpw");

	unless ( -d "/usr/local/etc/mail" ) 
	{
		mkdir("/usr/local/etc/mail", 0755);
	};

	unless ( -e $filterfile ) 
	{
		chdir("/usr/local/src/mail");
		MATT::Utility::FetchFile("$toaster/etc/mailfilter-site");
		unless ( -e "mailfilter-site" ) {
			croak "InstallMaildropFiles FAILED: couldn't fetch mailfilter-site!\n";
		};
		move("mailfilter-site", $filterfile);
		chmod(0600, $filterfile);
		chown($uid, $gid, $filterfile) or croak "InstallMaildropFiles: chown $filterfile failed!";
	};

	my $imap = "/usr/local/sbin/subscribeIMAP.sh";
	unless ( -e $imap )
	{
		MATT::Utility::FetchFile("$toaster/etc/subscribeIMAP.sh");
		if ( -e "subscribeIMAP.sh" ) {
			move("subscribeIMAP.sh", $imap);
			chmod(0555, $imap);
		} else {
			croak "InstallMaildropFiles FAILED: couldn't fetch subscribe-IMAP.sh!\n";
		};
	};

	unless ( -d "/var/log/mail" ) { SysCmd("mkdir -p /var/log/mail"); };

	my $logf = "/var/log/mail/maildrop.log";
	unless ( -e $logf ) 
	{
		WriteFile($logf, "begin");
		chown($uid, $gid, $logf) or croak "InstallMaildropFiles: chown $logf failed!";
	};
};

sub ConfigSpamAssassin
{

=head2 ConfigSpamAssassin

	use Mail::Toaster::Setup;
	ConfigSpamAssassin();

Shows this URL: http://www.yrex.com/spam/spamconfig.php

=cut

	print	"Visit http://www.yrex.com/spam/spamconfig.php ";

};

sub ConfigQmailScanner
{

=head2 ConfigQmailScanner

	use Mail::Toaster::Setup;
	ConfigQmailScanner;

prints out a note telling you how to enable qmail-scanner.

=cut

	my ($conf) = @_;

	my $service = $conf->{'qmail_service'};

	# We want qmailscanner to process emails so we add an ENV to the SMTP server:
	print "To enable qmail-scanner, add this to your $service/smtp/run file:
\n
QMAILQUEUE=\"/var/qmail/bin/qmail-scanner-queue.pl\"
 export QMAILQUEUE\n\n
";

};

sub InstallQmailScanner($)
{

=head2 InstallQmailScanner

	use Mail::Toaster::Setup;
	InstallQmailScanner($conf, $src);

=cut

	my ($conf) = @_;

	my $ver = $conf->{'install_qmailscanner_version'};
	my $src = $conf->{'toaster_src_dir'};
	unless ($ver) { $ver = "1.20"; };
	unless ($src) { $src = "/usr/local/src"; };

	my ($confcmd, $verb, $email, $clam, $spam, $fprot);

	my $package    = "qmail-scanner-$ver";
	my $site       = "http://download.sourceforge.net/qmail-scanner";
	#my $site       = "http://aleron.dl.sourceforge.net/sourceforge/qmail-scanner/";

	if ( -e "/var/qmail/bin/qmail-scanner-queue.pl") {
		print "QmailScanner is already Installed!\n";
		unless ( YesOrNo("Would you like to reinstall it?") ) { return };
	};

	if ( -d "$src/mail/filter" ) {
		CdSrcDir("$src/mail/filter");
	} else {
		SysCmd("mkdir -p $src/mail/filter");
		CdSrcDir("$src/mail/filter");
	};

	if ( ! -e "$package.tgz" ) 
	{
		MATT::Utility::FetchFile("$site/$package.tgz");
		unless ( -e "$package.tgz" ) {
			croak "InstallQmailScanner FAILED: couldn't fetch $package.tgz\n";
		};
	};

	if ( -d $package )
	{
		my $r = SourceWarning($package, 1, $src);
		if (! $r) { croak "InstallQmailScanner: sorry, I can't continue.\n"; };
	};

	my $tar = MATT::Utility::FindTheBin("tar");
	SysCmd("$tar -xzf $package.tgz");
	chdir($package);

	InstallGroup("qscand");
	InstallUser ("qscand");

	$confcmd = "./configure ";

	unless ( defined $conf->{'qmail_scanner_logging'} ) 
	{
		if ( YesOrNo("Do you want QS logging enabled?") )
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
		unless ( YesOrNo("Do you want QS debugging enabled?") )
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

	unless ( defined $conf->{'qmail_scanner_postmaster'} ) 
	{
		$email = GetAnswer("What is the email address for postmaster mail?");
	} 
	else 
	{
		$email = $conf->{'qmail_scanner_postmaster'};
	};

	my ($user, $dom) = $email =~ /^(.*)@(.*)$/;

	$confcmd .= "--admin $user --domain $dom ";

	unless ( defined $conf->{'qmail_scanner_clamav'} ) 
	{
		$clam = YesOrNo("Do you want ClamAV enabled?");
	} 
	else 
	{
		$clam = $conf->{'qmail_scanner_clamav'};
	};

	unless ( defined $conf->{'qmail_scanner_spamassassin'} ) 
	{
		$spam = YesOrNo("Do you want SpamAssassin enabled?");
	} else {
		$spam = $conf->{'qmail_scanner_spamassassin'};
	};

	if ( defined $conf->{'qmail_scanner_fprot'} ) 
	{
		$fprot = $conf->{'qmail_scanner_fprot'};
	};


	if ( $spam ) 
	{
		unless ( defined $conf->{'qmail_scanner_spamass_verbose'} ) 
		{
			$verb = YesOrNo("Do you want SA verbose logging (n)?");
		} else {
			$verb = $conf->{'qmail_scanner_spamass_verbose'};
		};
	};

	if ( $clam || $spam || $verb || $fprot ) 
	{
		my $first = 0;

		$confcmd .= "--scanners ";

		if ( $clam ) { 
			$confcmd .= "clamscan"; $first++; 
		};

		if ( $fprot ) { 
			if ( $first ) { $confcmd .= "," };
			$confcmd .= "fprot"; $first++; 
		};

		if ( $verb  ) { 
			if ( $first ) { $confcmd .= "," };
			$confcmd .= "verbose_spamassassin"; $first++
		};

		if ( $spam  ) { 
			if ( $first ) { $confcmd .= "," };
			$confcmd .= "fast_spamassassin"; 
		};
	} 
	else { croak "InstallQmailScanner: No scanners?"; };

	print "OK, running qmail-scanner configure to test options.\n";
	SysCmd( $confcmd );

	if ( YesOrNo("OK, ready to install it now?") ) 
		{ SysCmd( $confcmd . " --install" ); };

	ConfigQmailScanner($conf);

	if ( $conf->{'qmail_scanner_stats'} ) {
		InstallQmailScannerStats($conf);
	};
};

sub InstallQmailScannerStats($;$)
{
	my ($conf, $debug) = @_;

	my $ver = $conf->{'qmail_scanner_stats'};
	unless ($ver) { $ver = "2.0.2"; };

	my $package    = "qss-$ver";
	my $site       = "http://download.sourceforge.net/qss";

	my $htdocs     = $conf->{'toaster_http_docs'};
	unless ($htdocs) { $htdocs = "/usr/local/www/data"; };

	unless ( -d "$htdocs/qss" ) {
		mkdir("$htdocs/qss", 0755) or die "InstallQmailScannerStats: couldn't create $htdocs/qss: $!\n";
	};

	chdir "$htdocs/qss";
	if ( ! -e "$package.tar.gz" ) 
	{
		MATT::Utility::FetchFile("$site/$package.tar.gz");
		unless ( -e "$package.tar.gz" ) {
			croak "InstallQmailScannerStats: FAILED: couldn't fetch $package.tar.gz\n";
		};
	};

	my $tar = MATT::Utility::FindTheBin("tar");
	MATT::Utility::SysCmd("$tar -xzf $package.tar.gz");
	
	if ( -d "/var/spool/qmailscan") {
		chmod(0771, "/var/spool/qmailscan");
	} else { die "I can't find qmailscanner's quarantine!\n"; };

	if ( -e "/var/spool/qmailscan/quarantine.log" ) {
		chmod(0664, "/var/spool/qmailscan/quarantine.log")
	} else {
		MATT::Utility::WriteFile("/var/spool/qmailscan/quarantine.log", "created file");
		chmod(0664, "/var/spool/qmailscan/quarantine.log")
	};

	my $dos2unix = MATT::Utility::FindTheBin("dos2unix");
	unless ($dos2unix) {
		MATT::FreeBSD::InstallPort("unix2dos", "converters");
		$dos2unix = MATT::Utility::FindTheBin("dos2unix");
	};
	
	chdir "$htdocs/qss";
	MATT::Utility::SysCmd("$dos2unix \*.php");

	my @lines = MATT::Utility::ReadFile("config.php");
	foreach my $line ( @lines ) 
	{
		if ( $line =~ /logFile/ ) {
			$line = '$config["logFile"] = "/var/spool/qmailscan/quarantine.log";';
		};
		if ( $line =~ /startYear/ ) {
			$line = '$config["startYear"]  = 2004;';
		};
	};
	MATT::Utility::WriteFile("config.php", @lines);
};

sub InstallClamAV
{

=head2 InstallClamAV

	use Mail::Toaster::Setup;
	InstallClamAV($conf);

=cut

	my ($conf) = @_;

	my $confdir = $conf->{'system_config_dir'};
	unless ($confdir) { $confdir = "/usr/local/etc"; };

	use MATT::Passwd;
	use MATT::FreeBSD 1.20;

	InstallGroup("clamav");
	InstallUser ("clamav");
	MATT::FreeBSD::InstallPort ("clamav", "security", undef, undef, undef, 1 );

	my $run_f   = "$confdir/rc.d/clamav.sh";

	if ( !-s $run_f ) 
	{
		print "Creating $confdir/rc.d/clamav.sh startup file.\n";
		open(RUN, ">$run_f") or croak "InstallClamAV: couldn't open $run_f for write: $!";

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
		chmod(0755, "$confdir/rc.d/freshclam.sh");
	};

	my $uid = getpwnam("clamav");
	my $gid = getgrnam("clamav");

	my $logfile = "/var/log/freshclam.log";
	if ( !-e $logfile )
	{
		SysCmd("touch $logfile");
		chmod(0644, $logfile);
		chown($uid, $gid, $logfile);
	};

	my $freshclam = FindTheBin("freshclam");

	if ( -x $freshclam ) {
		SysCmd("$freshclam --verbose");
	} 
	else { print "couldn't find freshclam!\n"; };

	chown($uid, $gid, "/usr/local/share/clamav") or warn "FAILURE: $!";
	chown($uid, $gid, "/usr/local/share/clamav/viruses.db") or warn "FAILURE: $!";
	chown($uid, $gid, "/usr/local/share/clamav/viruses.db2") or warn "FAILURE: $!";

	CheckRcDotConf("clamav_clamd_enable", "clamav_clamd_enable=\"YES\"");

	if ( -x $run_f && ! IsProcessRunning("clamd") ) 
	{
		print "Starting ClamAV's clamd...";
		SysCmd("$run_f restart"); 
		print "done.\n";
	};

};

sub InstallToasterDependencies 
{

=head2 InstallToasterDependencies

	use Mail::Toaster::Setup;
	InstallToasterDependencies($conf);

Installs a bunch of programs that are needed by subsequent programs we'll be installing. You can install these yourself if you'd like, this doesn't do anything special beyond installing them:

ispell, gdbm, setquota, autoconf, automake, expect, gnupg, maildrop, mysql-client(3), autorespond, qmail, qmailanalog, daemontools, openldap-client, Compress::Zlib, Crypt::PasswdMD5, HTML::Template, Net::DNS, Crypt::OpenSSL-RSA, DBI, DBD::mysql, TimeDate.

=cut

	my ($conf) = @_;

	use MATT::FreeBSD 1.20;

	my $package = $conf->{'package_install_method'};
	unless ($package) { $package = "packages"; };

	if ( $package eq "port" ) 
	{
		MATT::FreeBSD::InstallPort("ispell",  "textproc",  undef, undef, undef, 1 );
		MATT::FreeBSD::InstallPort("gdbm",    "databases", undef, undef, undef, 1 );
		MATT::FreeBSD::InstallPort("setquota", "sysutils", undef, undef, undef, 1 );
		MATT::FreeBSD::InstallPort("autoconf", "devel",    undef, undef, undef, 1 );
		MATT::FreeBSD::InstallPort("automake", "devel",    undef, undef, undef, 1 );
		MATT::FreeBSD::InstallPort("gmake",    "devel",    undef, undef, undef, 1 );
		MATT::FreeBSD::InstallPort("expect",   "lang",     undef, undef, "WITHOUT_X11", 1 );
		MATT::FreeBSD::InstallPort("gnupg",    "security", undef, undef, undef, 1 );
		MATT::FreeBSD::InstallPort("maildrop", "mail",     undef, undef, undef, 1 );
	} 
	else 
	{ 
		unless ( MATT::FreeBSD::InstallPackage("ispell") ) {
			MATT::FreeBSD::InstallPort("ispell",  "textproc",  undef, undef, undef, 1 );
		};
		unless ( MATT::FreeBSD::InstallPackage("gdbm") )
		{
			MATT::FreeBSD::InstallPort("gdbm",    "databases", undef, undef, undef, 1 );
		};
		unless ( MATT::FreeBSD::InstallPackage("setquota") )
		{
			MATT::FreeBSD::InstallPort("setquota", "sysutils", undef, undef, undef, 1 );
		};
		unless ( MATT::FreeBSD::InstallPackage("autoconf") )
		{
			MATT::FreeBSD::InstallPort("autoconf", "devel",    undef, undef, undef, 1 );
		};
		unless ( MATT::FreeBSD::InstallPackage("automake") )
		{
			MATT::FreeBSD::InstallPort("automake", "devel",    undef, undef, undef, 1 );
		};
		unless ( MATT::FreeBSD::InstallPackage("gmake") )
		{
			MATT::FreeBSD::InstallPort("gmake",    "devel",    undef, undef, undef, 1 );
		};
		unless ( MATT::FreeBSD::InstallPackage("expect") )
		{
			MATT::FreeBSD::InstallPort("expect",   "lang",     undef, undef, "WITHOUT_X11", 1 );
		};
		unless ( MATT::FreeBSD::InstallPackage("gnupg") )
		{
			MATT::FreeBSD::InstallPort("gnupg",    "security", undef, undef, undef, 1 );
		};
		unless ( MATT::FreeBSD::InstallPackage("maildrop") )
		{
			MATT::FreeBSD::InstallPort("maildrop", "mail",     undef, undef, undef, 1 );
		};
	};

	if ( $conf->{'install_mysql'} == 4 ) 
	{
		MATT::FreeBSD::InstallPort ("mysql40-client", "databases", undef, "mysql-client-4", undef, 1);
	} else {
		MATT::FreeBSD::InstallPort ("mysql323-client", "databases", undef, "mysql-client-3", undef, 1);
	};

	MATT::FreeBSD::InstallPort ("autorespond",   "mail",     undef, undef, undef, 1);
	MATT::FreeBSD::InstallPort ("qmail",         "mail",     undef, undef, undef, 1);
	MATT::FreeBSD::InstallPort ("qmailanalog",   "mail",     undef, undef, undef, 1);
	MATT::FreeBSD::InstallPort ("daemontools",   "sysutils", undef, undef, undef, 1);

	unless ( ! $conf->{'install_openldap_client'} ) {
		MATT::FreeBSD::InstallPort   ("openldap-client",   "net", "openldap21-client");
	};
	MATT::FreeBSD::InstallPort   ("p5-Compress-Zlib", "archivers",   undef, undef, undef, 1);
	MATT::FreeBSD::InstallPort   ("p5-Crypt-PasswdMD5", "security",  undef, undef, undef, 1);
	MATT::FreeBSD::InstallPort   ("p5-HTML-Template",   "www",       undef, undef, undef, 1);
	MATT::FreeBSD::InstallPort   ("p5-Net-DNS",     "dns",           undef, undef, undef, 1);
	MATT::FreeBSD::InstallPort   ("p5-Crypt-OpenSSL-DSA", "security",undef, undef, undef, 1);
	MATT::FreeBSD::InstallPort   ("p5-Crypt-OpenSSL-RSA", "security",undef, undef, undef, 1);
	MATT::FreeBSD::InstallPort   ("p5-DBI",        "databases",      undef, undef, undef, 1);
	MATT::FreeBSD::InstallPort   ("p5-DBD-mysql",  "databases",      undef, undef, undef, 1);
	MATT::FreeBSD::InstallPort   ("p5-TimeDate",   "devel",          undef, undef, undef, 1);
};

sub InstallCourier($;$)
{

=head2 InstallCourier

	use Mail::Toaster::Setup;
	InstallCourier($conf, $package);

Installs courier imap based on your settings in toaster-watcher.conf.

=cut

	my ($conf, $package)  = @_;
	my $site   = "http://download.sourceforge.net/courier";

	my $ver    = $conf->{'install_courier_imap'};
	unless ($ver) { $ver = "1.7.0"; };

	unless ($package) { $package = "courier-imap-$ver"; };

	my $confdir = $conf->{'system_config_dir'};
	unless ($confdir) { $confdir = "/usr/local/etc"; };

	if ($package eq "port")
	{
		my @defs = "WITH_VPOPMAIL";
		push @defs, "WITHOUT_AUTHDAEMON";
		use MATT::FreeBSD 1.20;
		MATT::FreeBSD::InstallPort("courier-imap", "mail", undef, undef, join(",", @defs), 1 );
		ConfigCourier($conf, $confdir);
		return 1;
	};

	my $src = $conf->{'toaster_src_dir'};
	unless ($src) { $src = "/usr/local/src"; };

	CdSrcDir("$src/mail");

	if ( ! -e "$package.tar" ) 
	{
		MATT::Utility::FetchFile("$site/$package.tar.bz2");
		unless ( -e "$package.tar.bz2" ) {
			croak "InstallCourier: FAILED: couldn't fetch $package.tar.bz2\n";
		};
	};

	if ( -d $package )
	{
		my $r = SourceWarning($package, 1, $src);
		if (! $r) { croak "sorry, I can't continue.\n"; };
	};

	my $tar = MATT::Utility::FindTheBin("tar");

	MATT::Utility::SysCmd("bunzip2 $package.tar.bz2");
	MATT::Utility::SysCmd("$tar -xf $package.tar");

	chdir($package);
	$ENV{"HAVE_OPEN_SMTP_RELAY"} = 1;
	SysCmd( "./configure --prefix=/usr/local --exec-prefix=/usr/local --without-authldap --without-authshadow --with-authvchkpw --without-authcram --sysconfdir=/usr/local/etc/courier-imap --datadir=/usr/local/share/courier-imap --libexecdir=/usr/local/libexec/courier-imap --enable-workarounds-for-imap-client-bugs --disable-root-check --without-authdaemon");

	SysCmd( "make");
	SysCmd( "make install");
	ConfigCourier($conf, $confdir);
};

sub SourceWarning 
{

=head2 SourceWarning

	use Mail::Toaster::Setup;
	SourceWarning($package, $clean, $src);

=cut

	my ($package, $clean, $src) = @_;

	unless ( $src ) { $src = "/usr/local/src"; };

	print "\n$package sources are already present, indicating that you've already\n";
	print "installed $package. If you want to reinstall it, remove the existing\n";
	print "sources (rm -r $src/mail/$package) and re-run this script\n\n";

	if ($clean) 
	{
		if ( MATT::Utility::YesOrNo("\n\tWould you like me to remove the sources for you? ") ) 
		{
			use File::Path;
			print "Deleting $package...";
			rmtree "$src/mail/$package";
			print "done.\n";
			return 1;
		} else {
			return 0;
		};
	};
};

sub InstallSqwebmail($;$)
{

=head2 InstallSqwebmail

	use Mail::Toaster::Setup;
	InstallSqwebmail($conf, $package);

InstallSqwebmail based on your settings in toaster-watcher.conf.

=cut

	my ($conf, $package)  = @_;

	my $ver = $conf->{'install_sqwebmail'};
	unless ($ver) { $ver = "3.5.0"; };

	unless ($package) { $package = "sqwebmail-$ver"; };

	my $httpdir = $conf->{'toaster_http_base'};
	unless ($httpdir) { $httpdir = "/usr/local/www"; };

	my $src        = $conf->{'toaster_src_dir'};
	unless ($src) { $src = "/usr/local/src"; };

	my $site = "http://download.sourceforge.net/courier";
	my $cgi  = "$httpdir/cgi-bin";

	use File::Copy;

	CdSrcDir("$src/mail");

	if ( -d "$package" )
	{
		my $r = SourceWarning($package, 1, $src);
		if (! $r) { croak "sorry, I can't continue.\n"; };
	};

	my $tar = MATT::Utility::FindTheBin("tar");

	if ( !-e "$package.tar.bz2" ) {
		MATT::Utility::FetchFile("$site/$package.tar.bz2");
		if ( -e "$package.tar.bz2" ) 
		{
			SysCmd("$tar -xjf $package.tar.bz2");
		} 
		else 
		{
			if ( ! -e "$package.tar.gz" ) {
				MATT::Utility::FetchFile("$site/$package.tar.gz");
				if ( -e "$package.tar.gz" ) {
					SysCmd("$tar -xzf $package.tar.gz");
				} else {
					croak "InstallSqwebmail FAILED: coudn't fetch $package\n";
				};
			};
		};
	};

	chdir($package);

	my $datadir;
	if  ( -d "$httpdir/data/mail") 
	{
		$datadir = "$httpdir/data/mail";
	} else {
		$datadir = "$httpdir/data";
	};

	my $mime = "";

	if ( -e "/usr/local/etc/apache2/mime.types" ) {
		$mime = "--enable-mimetypes=/usr/local/etc/apache2/mime.types";
	} elsif ( -e "/usr/local/etc/apache/mime.types" ) {
		$mime = "--enable-mimetypes=/usr/local/etc/apache/mime.types";
	};
		
	SysCmd( "./configure --with-cachedir=/var/run/sqwebmail --enable-webpass=vpopmail --with-module=authvchkpw --enable-https --enable-logincache --enable-imagedir=$datadir/webmail --without-authdaemon $mime");
	SysCmd( "make configure-check");
	SysCmd( "make check");
	SysCmd( "make");

	my $share = "/usr/local/share/sqwebmail";
	if (-d $share) {
		SysCmd( "make install-exec");
		print "\n\nWARNING: I have only installed the $package binaries, thus\n";
		print "preserving any custom settings you might have in $share.\n";
		print "If you wish to do a full install, overwriting any customizations\n";
		print "you might have, then do this:\n\n";
		print "\tcd $src/mail/$package; make install\n";
	} else {
		SysCmd( "make install");
		chmod(0755, $share);
		chmod(0755, "$datadir/sqwebmail");
		copy("$share/ldapaddressbook.dist", "$share/ldapaddressbook") or croak "copy failed: $!";
	};

	my $var = "/var/run/sqwebmail";
	if (!-e $var) {
		my $uid = getpwnam("bin");
		my $gid = getgrnam("bin");
		mkdir($var, 0755);
		chown($uid, $gid, $var);
	};
};

sub InstallQmailadmin($;$)
{

=head2 InstallQmailadmin

	use Mail::Toaster::Setup;
	InstallQmailadmin($conf);

Install qmailadmin based on your settings in toaster-watcher.conf.

=cut

	my ($conf, $package)  = @_;
	my ($help, $helpdir, $conf_args);

	use MATT::FreeBSD 1.20;

	my $ver = $conf->{'install_qmailadmin'};
	unless ($ver) { $ver = "1.2.0"; };

	unless ($package) { $package = "qmailadmin-$ver"; };

	my $toaster = "$conf->{'toaster_dl_site'}$conf->{'toaster_dl_url'}";
	unless ($toaster) { $toaster = "http://www.tnpi.biz/internet/mail/toaster"; };

	my $src     = $conf->{'toaster_src_dir'};
	unless ($src) { $src = "/usr/local/src"; };

	my $httpdir = $conf->{'toaster_http_base'};
	unless ($httpdir) { $httpdir = "/usr/local/www"; };

	my $patch      = 0;
	#my $patch      = "$package-patch.txt";
	my $site       = "http://aleron.dl.sourceforge.net/sourceforge/qmailadmin";
	#my $site       = "http://www.inter7.com/devel";
	my $helpfile   = "qmailadmin-help-1.0.8";

	if ( $package eq "port" || $conf->{'install_qmailadmin'} eq "port" ) 
	{
		my @args;

		if ( $conf->{'qmailadmin_domain_autofill'} ) { 
			push @args, "WITH_DOMAIN_AUTOFILL"; 
		};

		if ( $conf->{'qmailadmin_modify_quotas'} ) {
			push @args, "WITH_MODIFY_QUOTA";
		};

		if ( $conf->{'qmailadmin_help_links'} ) {
			push @args, "WITH_HELP";
		};

		push @args, 'CGIBINSUBDIR=""';

		if ( $conf->{'qmailadmin_cgi-bin_dir'} ) {
			push @args, 'CGIBINDIR="'.$conf->{'qmailadmin_cgi-bin_dir'}.'"';
		} else {
			if ( -d "/usr/local/www/cgi-bin.mail") {
				push @args, 'CGIBINDIR="www/cgi-bin.mail"';
			} else {
				push @args, 'CGIBINDIR="www/cgi-bin"';
			};
		};

		if ( $conf->{'qmailadmin_http_docroot'} ) {
			push @args, 'WEBDATADIR="' . $conf->{'qmailadmin_http_docroot'} . '"';
		} else {
			if ( $conf->{'toaster_http_docs'} ) {
				push @args, 'WEBDATADIR="' . $conf->{'toaster_http_docs'} . '"';
			} else {
				push @args, 'WEBDATADIR="www/data"';
			};
		};
		
		if ( $conf->{'qmail_dir'} ne "/var/qmail" ) {
			push @args, 'QMAIL_DIR="' . $conf->{'qmail_dir'} . '"';
		};

		if ( $conf->{'qmailadmin_spam_option'} ) { 
			# not supported by the port as of 12/1/03
		};
		
		MATT::FreeBSD::InstallPort("qmailadmin", "mail", undef, undef, join(",", @args), 1);

		if ( $conf->{'qmailadmin_install_as_root'} ) { 
			my $gid = getgrnam("vchkpw");
			chown(0, $gid, "/usr/local/www/cgi-bin/qmailadmin");
		};
	} 
	else 
	{
		CdSrcDir("$src/mail");

		if ( !-e "$package.tar.gz" ) 
		{
			MATT::Utility::FetchFile("$site/$package.tar.gz");
			unless ( -e "$package.tar.gz" ) {
				print "InstallQmailadmin FAILED: Couldn't fetch $package.tar.gz!\n";
				exit 0;
			};
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
			if ( YesOrNo("\nDo you want spam options? ") ) 
			{ 
				$conf_args .= " --enable-modify-spam=Y" .
				" --enable-spam-command=\"| /usr/local/bin/maildrop /usr/local/etc/mail/mailfilter\"";
			};
		} else {
			if ( $conf->{'qmailadmin_spam_option'} ) {
				$conf_args .= " --enable-modify-spam=Y" .
				" --enable-spam-command=\"| /usr/local/bin/maildrop /usr/local/etc/mail/mailfilter\"";
				print "modify spam: yes\n";
			};
		};

		unless ( defined $conf->{'qmailadmin_modify_quotas'} ) {
			if ( YesOrNo("\nDo you want user quotas to be modifiable? ") ) 
			{ $conf_args .= " --enable-modify-quota=y"; };
		} else {
			if ( $conf->{'qmailadmin_modify_quotas'} ) {
				$conf_args .= " --enable-modify-quota=y";
				print "modify quotas: yes\n";
			};
		};
	
		unless ( defined $conf->{'qmailadmin_install_as_root'} ) 
		{
			if ( YesOrNo("\nShould qmailadmin be installed as root? ") ) 
			{ $conf_args .= " --enable-vpopuser=root"; };
		} else {
			if ( $conf->{'qmailadmin_install_as_root'} ) {
				$conf_args .= " --enable-vpopuser=root";
				print "install as root: yes\n";
			};
		};

		if ( $conf->{'qmailadmin_http_docroot'} ) {
			$conf_args .= " --enable-htmldir=" . $conf->{'qmailadmin_http_docroot'};
			$conf_args .= " --enable-imagedir=" . $conf->{'qmailadmin_http_docroot'}. "/images/qmailadmin";
		};

		if ( $conf->{'qmailadmin_cgi-bin_dir'} ) {
			$conf_args .= " --enable-cgibindir=" . $conf->{'qmailadmin_cgi-bin_dir'};
		} 
		else 
		{
			if ( -d "$httpdir/cgi-bin.mail") 
			{
				$conf_args .= " --enable-cgibindir=$httpdir/cgi-bin.mail";
			} else {
				$conf_args .= " --enable-cgibindir=$httpdir/cgi-bin";
			};
		};

		if ( $patch && !-e $patch ) { 
			MATT::Utility::FetchFile("$toaster/patches/$patch"); 
			unless ( -e $patch ) {
				croak "InstallQmailadmin FAILED: couldn't fetch $patch!\n";
			};
		};

		if ( -d "$package" )
		{
			my $r = SourceWarning($package, 1, $src);
			if (! $r) { croak "sorry, I can't continue.\n"; };
		};

		unless ( defined $conf->{'qmailadmin_help_links'} ) 
		{
			$help = YesOrNo("Would you like help links on the qmailadmin login page? ");
			if ($help) { $conf_args .= " --enable-help=y"; };
		} else {
			if ( $conf->{'qmailadmin_help_links'} ) {
				$conf_args .= " --enable-help=y"; $help = 1;
			};
		};

		my $tar = MATT::Utility::FindTheBin("tar");
		SysCmd("$tar -xzf $package.tar.gz");
		chdir($package);
		SysCmd("patch < ../$patch") if ($patch);
		print "running configure with $conf_args\n\n";
		SysCmd("./configure $conf_args");
		my $make = MATT::Utility::FindTheBin("gmake");
		unless ( -x $make ) { $make = MATT::Utility::FindTheBin("make"); };
		SysCmd($make);
		SysCmd("$make install-strip");

		if ($help) 
		{
			if ( $conf->{'qmailadmin_http_docroot'} ) {
				$helpdir = $conf->{'qmailadmin_http_docroot'} . "/images/qmailadmin/help";
			} else {
				if ( -d "$httpdir/data/mail" ) {
					$helpdir = "$httpdir/mail/images/qmailadmin/help";
				} else {
					$helpdir = "$httpdir/images/qmailadmin/help";
				};
			};

			if ( -d $helpdir ) 
			{
				print "InstallQmailadmin: help files already installed.\n";
			} 
			else 
			{
				MATT::Utility::FetchFile("$site/$helpfile.tar.gz");
				if ( -e "$helpfile.tar.gz" ) {
					SysCmd( "$tar -xzf $helpfile.tar.gz");
					move("$helpfile", "$helpdir") or warn "FAILED: Couldn't move $helpfile to $helpdir";
				} else {
					carp "InstallQmailadmin: FAILED: help files couldn't be downloaded!\n";
				};
			};
		};
	};

	return 1;
};

sub InstallUCSPI
{

=head2 InstallUCSPI

	use Mail::Toaster::Setup;
	InstallUCSPI($conf);

Installs ucspi-tcp with my (Matt Simerson) MySQL patch.

=cut

	my ($conf) = @_;

	my $package = "ucspi-tcp-0.88";
	my $patch   = "$package-mysql+rss.patch";
	#my $patch   = "$package-mysql2+rss.patch";
	my $site    = "http://cr.yp.to/ucspi-tcp";

	my $src = $conf->{'toaster_src_dir'};
	unless ($src) { $src = "/usr/local/src"; };

	my $toaster = "$conf->{'toaster_dl_site'}$conf->{'toaster_dl_url'}";
	unless ($toaster) { $toaster = "http://www.tnpi.biz/internet/mail/toaster"; };

	CdSrcDir("$src/mail");

	if ( !-e "$package.tar.gz" ) { 
		MATT::Utility::FetchFile("$site/$package.tar.gz"); 
		unless ( -e "$package.tar.gz" ) {
			croak "InstallUCSPI FAILED: couldn't fetch $package.tar.gz!\n";
		};
	};

	if ( !-e "$patch" ) { 
		MATT::Utility::FetchFile("$toaster/patches/$patch"); 
		unless ( -e $patch ) {
			croak "InstallUCSPI FAILED: couldn't fetch $patch!\n";
		};
	};

	if ( -d "$package" ) 
	{
		my $r = SourceWarning($package, 1, $src);
		if (! $r) { croak "sorry, I can't continue.\n"; };
	};

	my $tar = MATT::Utility::FindTheBin("tar");
	MATT::Utility::SysCmd("$tar -xzf $package.tar.gz");
	chdir($package);
	SysCmd( "patch -p1 < ../$patch");
	SysCmd( "make");
	SysCmd( "make setup check");
};

sub InstallEzmlm 
{

=head2 InstallEzmlm

	use Mail::Toaster::Setup;
	InstallEzmlm($conf);

Installs Ezmlm-idx. This also tweaks the port Makefile so that it'll build against MySQL 4.0 libraries as if you don't have MySQL 3 installed. It also copies the sample config files into place so that you have some default settings.

=cut

	my ($conf) = @_;

	my $confdir = $conf->{'system_config_dir'};
	unless ($confdir) { $confdir = "/usr/local/etc"; };

	use File::Copy;

	my $file = "/usr/ports/mail/ezmlm-idx/Makefile";

	my $mysql = $conf->{'install_mysql'};
	if ( $mysql == 4 ) {
		if ( `grep mysql323 $file` ) {
			my @lines = MATT::Utility::ReadFile($file);
			foreach my $line ( @lines ) {
				if ( $line =~ /^LIB_DEPENDS\+\=\s+mysqlclient.10/ ) {
					$line = "LIB_DEPENDS+=  mysqlclient.12:\${PORTSDIR}/databases/mysql40-client";
				};
			};
			MATT::Utility::WriteFile($file, @lines);
		};
	};

	my $r = MATT::FreeBSD::InstallPort("ezmlm-idx", "mail", undef,  undef, "WITH_MYSQL", 1);

	if ($r) 
	{
		chdir("$confdir/ezmlm");
		copy("ezmlmglrc.sample",  "ezmlmglrc" ) or croak "InstallEzmlm: copy ezmlmglrc failed: $!";
		copy("ezmlmrc.sample",    "ezmlmrc"   ) or croak "InstallEzmlm: copy ezmlmrc failed: $!";
		copy("ezmlmsubrc.sample", "ezmlmsubrc") or croak "InstallEzmlm: copy ezmlmsubrc failed: $!";
	};
};

sub ConfigCourier($$)
{

=head2 ConfigCourier

	use Mail::Toaster::Setup;
	ConfigCourier($confdir);

Does all the post-install configuration of Courier IMAP.

=cut

	my ($conf, $confdir) = @_;

	use File::Copy;

	chdir("$confdir/courier-imap");

	copy("pop3d.cnf.dist", "pop3d.cnf" ) if ( ! -e "pop3d.cnf" );
	copy("pop3d.dist",     "pop3d"     ) if ( ! -e "pop3d"     );
	copy("pop3d-ssl.dist", "pop3d-ssl" ) if ( ! -e "pop3d-ssl" );
	copy("imapd.cnf.dist", "imapd.cnf" ) if ( ! -e "imapd.cnf" );
	copy("imapd.dist",     "imapd"     ) if ( ! -e "imapd"     );
	copy("imapd-ssl.dist", "imapd-ssl" ) if ( ! -e "imapd-ssl" );
	copy("quotawarnmsg.example", "quotawarnmsg") if (!-e "quotawarnmsg");

	unless ( -e "$confdir/rc.d/imapd.sh" ) 
	{
		my $libe = "/usr/local/libexec/courier-imap";
		copy("$libe/imapd.rc",     "$confdir/rc.d/imapd.sh");
		chmod(00755, "$confdir/rc.d/imapd.sh");

		if ( $conf->{'pop3_daemon'} eq "courier" )
		{
			copy("$libe/pop3d.rc",     "$confdir/rc.d/pop3d.sh");
			chmod(00755, "$confdir/rc.d/pop3d.sh");
		};

		copy("$libe/imapd-ssl.rc", "$confdir/rc.d/imapd-ssl.sh");
		chmod(00755, "$confdir/rc.d/imapd-ssl.sh");
		copy("$libe/pop3d-ssl.rc", "$confdir/rc.d/pop3d-ssl.sh");
		chmod(00755, "$confdir/rc.d/pop3d-ssl.sh");
	};

	unless ( -e "/usr/local/sbin/imap" ) 
	{
		symlink("$confdir/rc.d/imapd.sh",     "/usr/local/sbin/imap");
		symlink("$confdir/rc.d/pop3d.sh",     "/usr/local/sbin/pop3");
		symlink("$confdir/rc.d/imapd-ssl.sh", "/usr/local/sbin/imapssl");
		symlink("$confdir/rc.d/pop3d-ssl.sh", "/usr/local/sbin/pop3ssl");
	};

	unless ( -e "/usr/local/share/courier-imap/pop3d.pem" ) 
	{
		chdir "/usr/local/share/courier-imap";
		SysCmd("./mkpop3dcert");
	};

	unless ( -e "/usr/local/share/courier-imap/imapd.pem" ) 
	{
		chdir "/usr/local/share/courier-imap";
		SysCmd("./mkimapdcert");
	};
};

sub ConfigVpopmailEtc 
{

=head2 ConfigVpopmailEtc

	use Mail::Toaster::Setup;
	ConfigVpopmailEtc($conf);

Builds the ~vpopmail/etc/tcp.smtp file.

=cut

	my ($conf) = @_;

	my $vpopdir = $conf->{'vpopmail_home_dir'};
	unless ($vpopdir) { $vpopdir = "/usr/local/vpopmail"; };

	my $vetc = "$vpopdir/etc";

	unless ( -d $vpopdir ) 
	{
		mkdir($vpopdir, 0775);
	};

	if ( -d $vetc ) { print "$vetc already exists, skipping.\n"; } 
	else 
	{
		print "creating $vetc\n";
		mkdir($vetc, 0775) or warn "failed to create $vetc: $!\n";
	};

	unless ( -f "$vetc/tcp.smtp" ) 
	{
		push my @lines, "127.0.0.1:allow,RELAYCLIENT=\"\"";
		my $block = 1;

		if ( YesOrNo("Do you need to enable relay access for any netblocks? :

NOTE: If you are an ISP and have dialup pools, this is where you want
to enter those netblocks. If you have systems that should be able to 
relay through this host, enter their IP/netblocks here as well.\n\n") )
		{
			do
			{
				$block = GetAnswer("the netblock to add (empty to finish)");
				push @lines, "$block:allow,RELAYCLIENT=\"\"" if $block;
			} 
			until (! $block);
		};
		push @lines, "### BEGIN QMAIL SCANNER VIRUS ENTRIES ###";
		push @lines, "### END QMAIL SCANNER VIRUS ENTRIES ###";
		push @lines, ":allow";

		WriteFile("$vetc/tcp.smtp", @lines);
	};

	if ( -x "/usr/local/sbin/qmail" ) 
	{
		print " ConfigVpopmailEtc: rebuilding tcp.smtp.cdb\n";
		MATT::Utility::SysCmd("/usr/local/sbin/qmail cdb");
	};
};

sub InstallSupervise 
{

=head2 InstallSupervise

	use Mail::Toaster::Setup;
	InstallSupervise($conf);

One stop shopping: calls the following subs:

 ConfigureQmailControl($conf);
 CreateServiceDir($conf);
 CreateSuperviseDirs($supervise);
 InstallQmailSuperviseRunFiles($conf, $supervise );
 InstallQmailSuperviseLogRunFiles($conf);
 ConfigureServices($conf, $supervise);

=cut

	my ($conf) = @_;

	my $supervise = $conf->{'qmail_supervise'};
	unless ($supervise) { $supervise = "/var/qmail/supervise"; };

	ConfigureQmailControl($conf);

	CreateServiceDir($conf);
	CreateSuperviseDirs($supervise);

	InstallQmailSuperviseRunFiles($conf, $supervise );
	InstallQmailSuperviseLogRunFiles($conf);

	ConfigureServices($conf, $supervise);
};

sub CreateServiceDir
{

=head2 CreateServiceDir

Create the supevised services directory (if it doesn't exist).

	use Mail::Toaster::Setup;
	InstallSupervise($conf);

Also sets the permissions of 775.

=cut

	my ($conf) = @_;

	my $service = $conf->{'qmail_service'};
	unless ($service) { $service = "/var/service"; };

	if ( -d $service ) 
	{
		print "CreateServiceDir: $service already exists.\n";
	} 
	else 
	{
		mkdir($service, 0775) or croak "CreateServiceDir: failed to create $service: $!\n";
	};
};

sub ConfigureServices
{

=head2 ConfigureServices

Sets up the supervised mail services for Mail::Toaster

	use Mail::Toaster::Setup;
	ConfigureServices($conf, $supervise);

This creates (if it doesn't exist) /var/service and populates it with symlinks to the supervise control directories (typicall /var/qmail/supervise). Creates and sets permissions on the following directories and files:

  /var/service
  /var/service/pop3
  /var/service/smtp
  /var/service/send
  /var/service/submit
  /usr/local/etc/rc.d/services.sh
  /usr/local/sbin/services

=cut

	my ($conf, $supervise) = @_;

	my $service = $conf->{'qmail_service'};
	unless ($service) { $service = "/var/service"; };

	my $confdir = $conf->{'system_config_dir'};
	unless ($confdir) { $confdir = "/usr/local/etc"; };

	my $dl_site = $conf->{'toaster_dl_site'};
	unless ($dl_site) { $dl_site = "http://www.tnpi.biz"; };
	my $toaster   = "$dl_site/internet/mail/toaster";

	if ( -e "$confdir/rc.d/services.sh" ) 
	{
		print "ConfigureServices: $confdir/rc.d/services.sh already exists.\n";
	}
	else
	{
		print "ConfigureServices: installing $confdir/rc.d/services.sh...\n";
		MATT::Utility::FetchFile("$toaster/start/services.txt");
		move("services.txt", "$confdir/rc.d/services.sh") or croak "couldn't move: $!";
		chmod(00751, "$confdir/rc.d/services.sh");
		if ( -x "$confdir/rc.d/services.sh" ) {
			print "done.\n";
		} 
		else { print "FAILED.\n"; };
	};

	my $sym = "/usr/local/sbin/services";
	if ( -e $sym ) 
	{
		print "ConfigureServices: $sym already exists.\n";
	}
	else
	{
		print "ConfigureServices: adding $sym...";
		symlink("$confdir/rc.d/services.sh", "/usr/local/sbin/services");
		if ( -e $sym ) { print "done.\n"; } else { print "FAILED.\n"; };
	};

	unless ( $conf->{'pop3_daemon'} eq "qpop3d" ) 
	{
		if ( -e "$service/pop3" ) {
			unlink("$service/pop3");
			print "Deleting $service/pop3 because we aren't using qpop3d!\n";
		} else {
			print "NOTICE: Not enabled due to configuration settings.\n";
		};
	}
	else
	{
		if ( -e "$service/pop3" ) 
		{
			print "ConfigureServices: $service/pop3 already exists.\n";
		} 
		else 
		{
			print "ConfigureServices: creating symlink from $supervise/pop3 to $service/pop3\n";
			symlink("$supervise/pop3", "$service/pop3") or croak "couldn't symlink: $!";
		};
	};

	foreach my $prot ("smtp", "send", "submit")
	{
		if ( -e "$service/$prot" ) 
		{
			print "ConfigureServices: $service/$prot already exists.\n";
		}
		else
		{
			print "ConfigureServices: creating symlink from $supervise/$prot to $service/$prot\n";
			symlink("$supervise/$prot", "$service/$prot") or croak "couldn't symlink: $!";
		};
	};
};

sub CreateSuperviseDirs
{

=head2 CreateSuperviseDirs

Creates the qmail supervise directories.

	use Mail::Toaster::Setup;
	CreateSuperviseDirs($supervise);

The directories created are:

  $supervise/smtp
  $supervise/submit
  $supervise/send
  $supervise/pop3

=cut

	my ($supervise) = @_;
	unless ($supervise) { $supervise = "/var/qmail/supervise"; };

	if ( -d $supervise ) 
	{
		print "CreateSuperviseDirs: $supervise already exists.\n";
	} 
	else 
	{
		mkdir($supervise, 0775) or croak "failed to create $supervise: $!\n";
	};

	chdir($supervise);

	foreach my $prot ( qw/ smtp send pop3 submit / )
	{
		if ( -d $prot )
		{
			print "CreateSuperviseDirs: $supervise/$prot already exists\n";
		}
		else
		{
			mkdir($prot, 0775) or croak "failed to create $supervise/$prot: $!\n";
			mkdir("$prot/log", 0775) or croak "failed to create $supervise/$prot/log: $!\n";
			SysCmd("chmod +t $prot");
		};
	};
};

sub InstallQmail
{

=head2 InstallQmail

Builds qmail and installs qmail with patches (based on your settings in toaster-watcher.conf), installs the SSL certs, adjusts the permissions of several files that need it.

	use Mail::Toaster::Setup;
	InstallQmail($conf, $package);

$conf is a hash of values from toaster-watcher.conf used to determine how to configured your qmail.

$package is the name of the program. It defaults to "qmail-1.03"

Patch info is here: http://www.tnpi.biz/internet/mail/toaster/patches/

=cut

	my ($conf, $package) = @_;
	my ($patch, $chkusr);

	my $ver = $conf->{'install_qmail'};
	unless ($ver) { $ver = "1.03"; };

	unless ($package) { $package = "qmail-$ver" };

	my $src = $conf->{'toaster_src_dir'};
	unless ( $src ) { $src = "/usr/local/src"; };

	my $qmaildir = $conf->{'qmail_dir'};
	unless ($qmaildir) { $qmaildir = "/var/qmail"; };

	my $vpopdir = $conf->{'vpopmail_home_dir'};
	unless ($vpopdir)  { $vpopdir  = "/usr/local/vpopmail"; };

	my $mysql = $conf->{'qmail_mysql_include'};
	unless ($mysql) { $mysql = "/usr/local/lib/mysql/libmysqlclient.a"; };

	my $dl_site = $conf->{'toaster_dl_site'};
	unless ($dl_site) { $dl_site = "http://www.tnpi.biz"; };
	my $toaster = "$dl_site/internet/mail/toaster";

	CdSrcDir("$src/mail");

	if ( -e $package ) 
	{
		my $r = SourceWarning($package, 1, $src);
		unless ($r) { croak "sorry, I can't continue.\n"; };
	};

	unless ( defined $conf->{'qmail_chk_usr_patch'} ) {
		print "\nCheckUser support causes the qmail-smtpd daemon to verify that
a user exists locally before accepting the message, during the SMTP conversation.
This prevents your mail server from accepting messages to email addresses that
don't exist in vpopmail. It is not compatible with system user mailboxes. \n\n";

		$chkusr = YesOrNo("Do you want qmail-smtpd-chkusr support enabled?");
	} 
	else 
	{
		if ( $conf->{'qmail_chk_usr_patch'} ) {
			$chkusr = 1;
			print "chk-usr patch: yes\n";
		};
	};

	if ($chkusr) { $patch = "$package-toaster-2.8.patch"; } 
	else         { $patch = "$package-toaster-2.6.patch"; };

	my $site  = "http://cr.yp.to/software";

	unless ( -e "$package.tar.gz" ) 
	{
		if ( -e "/usr/ports/distfiles/$package.tar.gz" ) 
		{
			use File::Copy;
			copy("/usr/ports/distfiles/$package.tar.gz", "$src/mail/$package.tar.gz");  
		} 
		else 
		{ 
			MATT::Utility::FetchFile("$site/$package.tar.gz"); 
			unless ( -e "$package.tar.gz" ) {
				croak "InstallQmail FAILED: couldn't fetch $package.tar.gz!\n";
			};
		};
	};

	unless ( -e $patch ) 
	{
		FetchFile("$toaster/patches/$patch");
		unless ( -e $patch )  { croak "\n\nfailed to fetch patch $patch!\n\n"; };
	};

	my $tar      = MATT::Utility::FindTheBin("tar");
	my $patchbin = MATT::Utility::FindTheBin("patch");
	unless ( $tar && $patchbin ) { croak "couldn't find tar or patch!\n"; };

	SysCmd( "$tar -xzf $package.tar.gz");
	chdir("$src/mail/$package") or croak "InstallQmail: cd $src/mail/$package failed: $!\n";
	SysCmd("$patchbin < $src/mail/$patch");

	WriteFile("conf-qmail",    $qmaildir) or croak "couldn't write to conf-qmail: $!";
	WriteFile("conf-vpopmail", $vpopdir) or croak "couldn't write to conf-vpopmail: $!";
	WriteFile("conf-mysql",    $mysql) or croak "couldn't write to conf-mysql: $!";
	SysCmd( "make setup");

	unless ( -f "$qmaildir/control/servercert.pem" ) { 
		SysCmd( "make cert") 
	};

	if ($chkusr) 
	{
		my $uid = getpwnam("vpopmail");
		my $gid = getgrnam("vchkpw");

		chown($uid, $gid, "$qmaildir/bin/qmail-smtpd") 
			or warn "chown $qmaildir/bin/qmail-smtpd failed: $!\n";

		SysCmd("chmod 6555 $qmaildir/bin/qmail-smtpd");
	};

	unless ( -e "/usr/share/skel/Maildir" ) 
	{
		SysCmd( "$qmaildir/bin/maildirmake /usr/share/skel/Maildir");
	};

#  system - will set to the systems hostname
#  qmail  - will set to contents of qmail/control/me

	use Mail::Toaster::Qmail;
	Mail::Toaster::Qmail::ConfigQmail($conf);
};


1;
__END__


=head1 AUTHOR

Matt Simerson - matt@tnpi.biz

=head1 BUGS

None known. Report any to matt@cadillac.net.

=head1 TODO

Documentation. Needs more documenation.

=head1 SEE ALSO

http://matt.simerson.net/computing/mail/toaster/

Mail::Toaster::CGI, Mail::Toaster::DNS, 
Mail::Toaster::Logs, Mail::Toaster::Qmail, 
Mail::Toaster::Setup


=head1 COPYRIGHT

Copyright 2001 - 2003, The Network People, Inc. All Right Reserved.

=cut
