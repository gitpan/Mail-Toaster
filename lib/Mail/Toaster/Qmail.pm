#!/usr/bin/perl
use strict;

#
# $Id: Qmail.pm,v 4.1 2004/11/16 21:20:01 matt Exp $
#

package Mail::Toaster::Qmail;

use Carp;
my $os = $^O;
use vars qw($VERSION);
$VERSION = '4.00';

use lib "lib";
use lib "../..";
require Mail::Toaster::Utility; my $utility = Mail::Toaster::Utility->new();
require Mail::Toaster::Perl;    my $perl    = Mail::Toaster::Perl->new();

=head1 NAME

Mail::Toaster:::Qmail - Common Qmail functions

=head1 SYNOPSIS

Mail::Toaster::Qmail is frequently used functions I've written for perl use with Qmail.

=head1 DESCRIPTION

This module has all sorts of goodies, the most useful of which are the build_????_run modules which build your qmail control files for you. 

=head1 METHODS

=head2 new

To use any of the methods following, you need to create a qmail object:

	use Mail::Toaster::Qmail;
	my $qmail = Mail::Toaster::Qmail->new();

=cut

sub new
{
	my ($class, $name) = @_;
	my $self = { name => $name };
	bless ($self, $class);
	return $self;
};

=head2 netqmail_virgin

Builds and installs a pristine net-qmail. This is necessary to resolve a chicken and egg problem. You can't apply the toaster patches (specifically chkuser) against NetQmail until vpopmail is installed, and you can't install vpopmail without qmail being installed. After installing this, and then vpopmail, you can rebuild NetQmail with the toaster patches.

	$qmail->netqmail_virgin($conf, $package);

$conf is a hash of values from toaster-watcher.conf used to determine how to configure qmail.

$package is the name of the program. It defaults to "qmail-1.03"

=cut

sub netqmail_virgin($;$)
{
	my ($self, $conf, $package) = @_;
	my ($chkusr);

	my $ver = $conf->{'install_netqmail'}; $ver ||= "1.05";

	$package ||= "netqmail-$ver";

	my $src      = $conf->{'toaster_src_dir'};  $src ||= "/usr/local/src";
	my $qmaildir = $conf->{'qmail_dir'};        $qmaildir ||= "/var/qmail";

	$self->install_qmail_groups_users($conf);

	my $mysql      = $conf->{'qmail_mysql_include'}; $mysql ||= "/usr/local/lib/mysql/libmysqlclient.a";
	my $qmailgroup = $conf->{'qmail_log_group'};     $qmailgroup ||= "qnofiles";

	$utility->chdir_source_dir("$src/mail");

	if ( -e $package ) 
	{
		my $r = $utility->source_warning($package, 1, $src);
		unless ($r) 
		{ 
			carp "\nnetqmail: OK then, skipping install.\n\n"; 
			return 0;
		};
	};

	my $site  = "http://www.qmail.org";

	unless ( -e "$package.tar.gz" ) 
	{
		if ( -e "/usr/ports/distfiles/$package.tar.gz" ) 
		{
			use File::Copy;
			copy("/usr/ports/distfiles/$package.tar.gz", "$src/mail/$package.tar.gz");  
		} 
		else 
		{ 
			$utility->get_file("$site/$package.tar.gz"); 
			unless ( -e "$package.tar.gz" ) {
				croak "netqmail FAILED: couldn't fetch $package.tar.gz!\n";
			};
		};
	};

	my $tar      = $utility->find_the_bin("tar");
	my $gunzip   = $utility->find_the_bin("gunzip");
	unless ( $tar && $gunzip ) { croak "couldn't find tar or gunzip!\n"; };

	$utility->syscmd( "$gunzip -c $package.tar.gz | $tar -xf -");
	chdir("$src/mail/$package") or croak "netqmail: cd $src/mail/$package failed: $!\n";
	$utility->syscmd("./collate.sh");
	chdir("$src/mail/$package/$package") or croak "netqmail: cd $src/mail/$package/$package failed: $!\n";

	print "netqmail: fixing up conf-qmail\n";
	$utility->file_write("conf-qmail",    $qmaildir) or croak "couldn't write to conf-qmail: $!";

	print "netqmail: fixing up conf-mysql\n";
	$utility->file_write("conf-mysql",    $mysql)  or croak "couldn't write to conf-mysql: $!";

	if ( $os eq "darwin" ) 
	{
		print "netqmail: fixing up conf-ld\n";
		$utility->file_write("conf-ld",    "cc -Xlinker -x")  or croak "couldn't write to conf-ld: $!";

		print "netqmail: fixing up dns.c for Darwin\n";
		my @lines = $utility->file_read("dns.c");
		foreach my $line ( @lines )
		{ 
			if ( $line =~ /#include <netinet\/in.h>/ ) 
			{
				$line = "#include <netinet/in.h>\n#include <nameser8_compat.h>";
			};
		};
		$utility->file_write("dns.c", @lines);

		print "netqmail: fixing up strerr_sys.c for Darwin\n";
		@lines = $utility->file_read("strerr_sys.c");
		foreach my $line ( @lines )
		{ 
			if ( $line =~ /struct strerr strerr_sys/ ) 
			{
				$line = "struct strerr strerr_sys = {0,0,0,0};";
			};
		};
		$utility->file_write("strerr_sys.c", @lines);

		move("INSTALL", "INSTALL.txt");
		print "netqmail: fixing up hier.c for Darwin\n";
		@lines = $utility->file_read("hier.c");
		foreach my $line (@lines)
		{
			if ( $line =~ /c\(auto_qmail,"doc","INSTALL",auto_uido,auto_gidq,0644\)/ )
			{
				$line = 'c(auto_qmail,"doc","INSTALL.txt",auto_uido,auto_gidq,0644);';
			};
		};
		$utility->file_write("hier.c", @lines);

		move("SENDMAIL", "SENDMAIL.txt");
	};

	print "netqmail: fixing up conf-cc\n";
	$utility->file_write("conf-cc", "cc -O2")  or croak "couldn't write to conf-cc: $!";

	print "netqmail: fixing up conf-groups\n";
	my @groups = "qmail"; push @groups, $qmailgroup;
	$utility->file_write("conf-groups",    @groups) or croak "couldn't write to conf-groups: $!";

	my $servicectl = "/usr/local/sbin/services";
	if (-x $servicectl)
	{
		print "Stopping Qmail!\n";
		$self->send_stop($conf);
		$utility->syscmd("$servicectl stop");
	};

	my $make = $utility->find_the_bin("gmake");
	unless ($make) { $make = $utility->find_the_bin("make") };
	$utility->syscmd("$make setup");

	unless ( -e "/usr/share/skel/Maildir" ) 
	{
		$utility->syscmd( "$qmaildir/bin/maildirmake /usr/share/skel/Maildir");
	};

	$self->config($conf);

	if (-x $servicectl)
	{
		print "Stopping Qmail & supervised services!\n";
		$utility->syscmd("$servicectl start") 
	};
};

sub rebuild_ssl_temp_keys($)
{
	my ($self, $conf) = @_;

	my $debug   = $conf->{'debug'};
	my $openssl = $utility->find_the_bin("openssl");
	die "no openssl!\n" unless ( -x $openssl);

	my $qmdir = $conf->{'qmail_dir'};         $qmdir ||= "/var/qmail";
	my $user  = $conf->{'smtpd_run_as_user'}; $user  ||= "vpopmail";
	my $group = $conf->{'qmail_group'};       $group ||= "qmail";
	my $uid   = getpwnam($user);
	my $gid   = getgrnam($group);
	my $cert  = "$qmdir/control/rsa512.pem";

	if ( -M $cert >= 1 || ! -e $cert )
	{
		print "rebuild_ssl_temp_keys: rebuilding RSA key\n" if $debug;
		$utility->syscmd("$openssl genrsa -out $cert.new 512 2>/dev/null");
		chmod(0660, "$cert.new") or die "chmod $cert.new failed: $!\n";
		chown($uid, $gid, "$cert.new") or carp "chown $cert.new failed: $!\n";
		move("$cert.new", $cert);
	};

	$cert = "$qmdir/control/dh512.pem";
	if ( -M $cert >= 1 || ! -e $cert )
	{
		print "rebuild_ssl_temp_keys: rebuilding DSA 512 key\n" if $debug;
		$utility->syscmd("$openssl dhparam -2 -out $cert.new 512 2>/dev/null");
		chmod(0660, "$cert.new") or die "chmod $cert.new failed: $!\n";
		chown($uid, $gid, "$cert.new") or carp "chown $cert.new failed: $!\n";
		move("$cert.new", $cert);
	};

	$cert = "$qmdir/control/dh1024.pem";
	if ( -M $cert >= 1 || ! -e $cert )
	{
		print "rebuild_ssl_temp_keys: rebuilding DSA 1024 key\n" if $debug;
		$utility->syscmd("$openssl dhparam -2 -out $cert.new 1024 2>/dev/null");
		chmod(0660, "$cert.new") or die "chmod $cert.new failed: $!\n";
		chown($uid, $gid, "$cert.new") or carp "chown $cert.new failed: $!\n";
		move("$cert.new", $cert);
	};
};


=head2 set_supervise_dir

	my $dir = $qmail->set_supervise_dir($conf, "smtp", $debug);

This sub just sets the supervise directory used by the various qmail
services (qmail-smtpd, qmail-send, qmail-pop3d, qmail-submit). It sets
the values according to your preferences in toaster-watcher.conf. If
any settings are missing from the config, it chooses reasonable defaults.

This is used primarily to allow you to set your mail system up in ways
that are a different than mine, like a LWQ install.

=cut

sub set_supervise_dir($$)
{
	my ($self, $conf, $prot) = @_;

	my $debug        = $conf->{'debug'};
	my $supervisedir = $conf->{'qmail_supervise'}; $supervisedir ||= "/var/qmail/supervise";

	if ( ! -d $supervisedir and $supervisedir eq "/var/supervise" )
	{
		if ( -d "/supervise" )  { $supervisedir = "/supervise" };
	};

	if ( $prot eq "smtp" ) 
	{
		my $dir = $conf->{'qmail_supervise_smtp'};
		unless ($dir) 
		{ 
			carp "WARNING: qmail_supervise_smtp is not set correctly in toaster-watcher.conf!\n";
			$dir = "$supervisedir/smtp"; 
		} 
		else 
		{
			if ( $dir =~ /^qmail_supervise\/(.*)$/ ) 
			{
				$dir = "$supervisedir/$1";
			};
		};
		print "set_supervise_dir: using $dir for $prot \n" if $debug;
		return $dir;
	} 
	elsif ( $prot eq "pop3" ) 
	{
		my $dir = $conf->{'qmail_supervise_pop3'};
		unless ($dir) 
		{ 
			carp "WARNING: qmail_supervise_pop3 is not set correctly in toaster-watcher.conf!\n";
			$dir = "$supervisedir/pop3"; 
		} 
		else 
		{
			if ( $dir =~ /^qmail_supervise\/(.*)$/ ) 
			{
				$dir = "$supervisedir/$1";
			};
		};
		print "set_supervise_dir: using $dir for $prot \n" if $debug;
		return $dir;
	} 
	elsif ( $prot eq "send" ) 
	{
		my $dir   = $conf->{'qmail_supervise_send'};

		unless ($dir) 
		{ 
			carp "WARNING: qmail_supervise_send is not set correctly in toaster-watcher.conf!\n";
			$dir = "$supervisedir/send"; 
		} 
		else 
		{
			if ( $dir =~ /^qmail_supervise\/(.*)$/ ) 
			{
				$dir = "$supervisedir/$1";
			};
		};
		print "set_supervise_dir: using $dir for $prot \n" if $debug;
		return $dir;
	}
	elsif ( $prot eq "submit" ) 
	{
		my $dir = $conf->{'qmail_supervise_submit'};
		unless ($dir) 
		{ 
			carp "WARNING: qmail_supervise_submit is not set correctly in toaster-watcher.conf!\n";
			$dir = "$supervisedir/submit"; 
		} 
		else 
		{
			if ( $dir =~ /^qmail_supervise\/(.*)$/ ) 
			{
				$dir = "$supervisedir/$1";
			};
		};
		print "set_supervise_dir: using $dir for $prot \n" if $debug;
		return $dir;
	}
	else
	{
		print "set_supervise_dir: FAILURE: please read perldoc Mail::Toaster::Qmail to see how to use this subroutine.\n";
	};
};

sub install_qmail_groups_users($)
{
	my ($self, $conf) = @_;

	my $qmaildir = $conf->{'qmail_dir'};
	unless ($qmaildir) { $qmaildir = "/var/qmail"; };

	my $errmsg = "ERROR: You need to update your toaster-watcher.conf file!\n";

	my $alias   = $conf->{'qmail_user_alias'};  croak $errmsg unless $alias;
	my $qmaild  = $conf->{'qmail_user_daemon'}; croak $errmsg unless $qmaild;
	my $qmailp  = $conf->{'qmail_user_passwd'}; croak $errmsg unless $qmailp;
	my $qmailq  = $conf->{'qmail_user_queue'};  croak $errmsg unless $qmailq;
	my $qmailr  = $conf->{'qmail_user_remote'}; croak $errmsg unless $qmailr;
	my $qmails  = $conf->{'qmail_user_send'};   croak $errmsg unless $qmails;
	my $qmailg  = $conf->{'qmail_group'};       croak $errmsg unless $qmailg;
	my $nofiles = $conf->{'qmail_log_group'};   croak $errmsg unless $nofiles;

	$perl->module_load( { module=>"Mail::Toaster::Passwd"} );
	my $passwd = Mail::Toaster::Passwd->new;

	$passwd->creategroup("qmail", "82");
	$passwd->creategroup("qnofiles", "81");

	unless ( $passwd->exist($alias) ) {
		$passwd->user_add( {user=>$alias,homedir=>$qmaildir,uid=>81,gid=>81} );
	};

	unless ( $passwd->exist($qmaild) ) {
		$passwd->user_add( {user=>$qmaild,homedir=>$qmaildir,uid=>82,gid=>81} );
	};

	unless ( $passwd->exist($qmailp) ) {
		$passwd->user_add( {user=>$qmailp,homedir=>$qmaildir,uid=>84,gid=>81} );
	};

	unless ( $passwd->exist($qmailq) ) {
		$passwd->user_add( {user=>$qmailq,homedir=>$qmaildir,uid=>85,gid=>82} );
	};

	unless ( $passwd->exist($qmailr) ) {
		$passwd->user_add( {user=>$qmailr,homedir=>$qmaildir,uid=>86,gid=>82} );
	};

	unless ( $passwd->exist($qmails) ) {
		$passwd->user_add( {user=>$qmails,homedir=>$qmaildir,uid=>87,gid=>82} );
	};
};

=head2 netqmail

Builds net-qmail with patches (based on your settings in toaster-watcher.conf), installs the SSL certs, adjusts the permissions of several files that need it.

	$qmail->netqmail($conf, $package);

$conf is a hash of values from toaster-watcher.conf

$package is the name of the program. It defaults to "qmail-1.03"

Patch info is here: http://www.tnpi.biz/internet/mail/toaster/patches/

=cut

sub netqmail($;$)
{
	my ($self, $conf, $package) = @_;
	my ($chkusr);

	my $ver      = $conf->{'install_netqmail'}; $ver ||= "1.05";
	my $src      = $conf->{'toaster_src_dir'};  $src ||= "/usr/local/src";
	my $qmaildir = $conf->{'qmail_dir'};        $qmaildir ||= "/var/qmail";

	$package ||= "netqmail-$ver";
	$self->install_qmail_groups_users($conf);

	my $vpopdir    = $conf->{'vpopmail_home_dir'};   $vpopdir ||= "/usr/local/vpopmail";
	my $mysql      = $conf->{'qmail_mysql_include'}; $mysql   ||= "/usr/local/lib/mysql/libmysqlclient.a";
	my $qmailgroup = $conf->{'qmail_log_group'};     $qmailgroup ||= "qnofiles";
	my $dl_site    = $conf->{'toaster_dl_site'};     $dl_site ||= "http://www.tnpi.biz";
	my $toaster    = "$dl_site/internet/mail/toaster";
	my $vhome      = $conf->{'vpopmail_home_dir'};   $vhome   ||= "/usr/local/vpopmail";

	$utility->chdir_source_dir("$src/mail");

	if ( -e $package ) 
	{
		my $r = $utility->source_warning($package, 1, $src);
		unless ($r) 
		{ 
			carp "\nnetqmail: OK then, skipping install.\n\n"; 
			return 0;
		};
	};

	if ( defined $conf->{'qmail_chk_usr_patch'} ) {
		if ( $conf->{'qmail_chk_usr_patch'} ) {
			$chkusr = 1;
			print "chk-usr patch: yes\n";
		} 
		else { print "chk-usr patch: no\n" };
	};

	my $patch    = "$package-toaster-2.9.patch";
	my $chkpatch = "$package-chkusr-2.9.patch";

	print "netqmail: using patch $patch\n";

	my $site  = "http://www.qmail.org";

	unless ( -e "$package.tar.gz" ) 
	{
		if ( -e "/usr/ports/distfiles/$package.tar.gz" ) 
		{
			use File::Copy;
			copy("/usr/ports/distfiles/$package.tar.gz", "$src/mail/$package.tar.gz");  
		} 
		else 
		{ 
			$utility->get_file("$site/$package.tar.gz"); 
			unless ( -e "$package.tar.gz" ) {
				croak "netqmail FAILED: couldn't fetch $package.tar.gz!\n";
			};
		};
	};

	unless ( -e $patch )
	{
		$utility->get_file("$toaster/patches/$patch");
		unless ( -e $patch )  { croak "\n\nfailed to fetch patch $patch!\n\n"; };
	};

	unless ( -e $chkpatch )
	{
		$utility->get_file("$toaster/patches/$chkpatch");
		unless ( -e $chkpatch )  { croak "\n\nfailed to fetch patch $chkpatch!\n\n"; };
	};

	my $tar      = $utility->find_the_bin("tar");
	my $gunzip   = $utility->find_the_bin("gunzip");
	my $patchbin = $utility->find_the_bin("patch");
	unless ( $tar && $patchbin && $gunzip ) { croak "couldn't find tar, gunzip, or patch!\n"; };

	$utility->syscmd( "$gunzip -c $package.tar.gz | $tar -xf -");
	chdir("$src/mail/$package") or croak "netqmail: cd $src/mail/$package failed: $!\n";
	$utility->syscmd("./collate.sh");
	chdir("$src/mail/$package/$package") or croak "netqmail: cd $src/mail/$package/$package failed: $!\n";
	$utility->syscmd("$patchbin < $src/mail/$patch");
	if ($chkusr) { $utility->syscmd("$patchbin < $src/mail/$chkpatch"); };

	print "netqmail: fixing up conf-qmail\n";
	$utility->file_write("conf-qmail",    $qmaildir) or croak "couldn't write to conf-qmail: $!";

	print "netqmail: fixing up conf-vpopmail\n";
	$utility->file_write("conf-vpopmail", $vpopdir) or croak "couldn't write to conf-vpopmail: $!";

	print "netqmail: fixing up conf-mysql\n";
	$utility->file_write("conf-mysql",    $mysql)  or croak "couldn't write to conf-mysql: $!";

	if ( $os eq "darwin" ) 
	{
		print "netqmail: fixing up conf-ld\n";
		$utility->file_write("conf-ld",    "cc -Xlinker -x")  or croak "couldn't write to conf-ld: $!";

		print "netqmail: fixing up dns.c for Darwin\n";
		my @lines = $utility->file_read("dns.c");
		foreach my $line ( @lines )
		{ 
			if ( $line =~ /#include <netinet\/in.h>/ ) 
			{
				$line = "#include <netinet/in.h>\n#include <nameser8_compat.h>";
			};
		};
		$utility->file_write("dns.c", @lines);

		print "netqmail: fixing up strerr_sys.c for Darwin\n";
		@lines = $utility->file_read("strerr_sys.c");
		foreach my $line ( @lines )
		{ 
			if ( $line =~ /struct strerr strerr_sys/ ) 
			{
				$line = "struct strerr strerr_sys = {0,0,0,0};";
			};
		};
		$utility->file_write("strerr_sys.c", @lines);

		move("INSTALL", "INSTALL.txt");
		print "netqmail: fixing up hier.c for Darwin\n";
		@lines = $utility->file_read("hier.c");
		foreach my $line (@lines)
		{
			if ( $line =~ /c\(auto_qmail,"doc","INSTALL",auto_uido,auto_gidq,0644\)/ )
			{
				$line = 'c(auto_qmail,"doc","INSTALL.txt",auto_uido,auto_gidq,0644);';
			};
		};
		$utility->file_write("hier.c", @lines);

		move("SENDMAIL", "SENDMAIL.txt");
	};

	print "netqmail: fixing up conf-cc\n";
	if ( -d "/usr/local/include/openssl" ) 
	{
		print "netqmail: I have detected the OpenSSL port is installed. I will build against it.\n";
		$utility->file_write("conf-cc", "cc -O2 -DTLS=20040120 -I/usr/local/include/openssl")  or croak "couldn't write to conf-cc: $!";
	} 
	elsif ( -d "/usr/include/openssl" ) 
	{
		print "netqmail: using system supplied OpenSSL libraries.\n";
		$utility->file_write("conf-cc", "cc -O2 -DTLS=20040120 -I/usr/include/openssl")  or croak "couldn't write to conf-cc: $!";
	} 
	else 
	{
		print "netqmail: WARNING: I couldn't find your OpenSSL libraries. This might cause problems!\n";
		$utility->file_write("conf-cc", "cc -O2 -DTLS=20040120")  or croak "couldn't write to conf-cc: $!";
	};

	print "netqmail: fixing up conf-groups\n";
	my @groups = "qmail"; push @groups, $qmailgroup;
	$utility->file_write("conf-groups",    @groups) or croak "couldn't write to conf-groups: $!";

	my $servicectl = "/usr/local/sbin/services";
	if (-x $servicectl)
	{
		print "Stopping Qmail!\n";
		$self->send_stop($conf);
		$utility->syscmd("$servicectl stop");
	};

	my $make = $utility->find_the_bin("gmake");
	unless ($make) { $make = $utility->find_the_bin("make") };

	$utility->syscmd("$make setup");
	unless ( -f "$qmaildir/control/servercert.pem" ) 
	{
		print "netqmail: installing SSL certificates \n";
		$utility->syscmd("$make cert");
	};
	unless ( -f "$qmaildir/control/rsa512.pem" ) {
		print "netqmail: install temp SSL \n";
		$utility->syscmd( "$make tmprsadh");
	};

	if ($chkusr) 
	{
		my $uid = getpwnam("vpopmail");
		my $gid = getgrnam("vchkpw");

		chown($uid, $gid, "$qmaildir/bin/qmail-smtpd") 
			or carp "chown $qmaildir/bin/qmail-smtpd failed: $!\n";

		$utility->syscmd("chmod 6555 $qmaildir/bin/qmail-smtpd");
	};

	unless ( -e "/usr/share/skel/Maildir" ) 
	{
		$utility->syscmd( "$qmaildir/bin/maildirmake /usr/share/skel/Maildir");
	};

	$self->config($conf);

	if (-x $servicectl)
	{
		print "Stopping Qmail & supervised services!\n";
		$utility->syscmd("$servicectl start") 
	};
};

sub install_qmail($;$)
{

=head2 install_qmail

Builds qmail and installs qmail with patches (based on your settings in toaster-watcher.conf), installs the SSL certs, adjusts the permissions of several files that need it.

	$qmail->install_qmail($conf, $package);

$conf is a hash of values from toaster-watcher.conf

$package is the name of the program. It defaults to "qmail-1.03"

Patch info is here: http://www.tnpi.biz/internet/mail/toaster/patches/

=cut

	my ($self, $conf, $package) = @_;
	my ($patch, $chkusr);

	if ( $conf->{'install_netqmail'} )
	{
		$self->netqmail($conf);
		exit;
	};

	$self->install_qmail_groups_users($conf);

	my $ver = $conf->{'install_qmail'};
	unless ($ver) { $ver = "1.03"; };

	$package ||= "qmail-$ver";

	my $src      = $conf->{'toaster_src_dir'};     $src      ||= "/usr/local/src";
	my $qmaildir = $conf->{'qmail_dir'};           $qmaildir ||= "/var/qmail";
	my $vpopdir  = $conf->{'vpopmail_home_dir'};   $vpopdir  ||= "/usr/local/vpopmail";
	my $mysql    = $conf->{'qmail_mysql_include'}; $mysql    ||= "/usr/local/lib/mysql/libmysqlclient.a";
	my $dl_site  = $conf->{'toaster_dl_site'};     $dl_site  ||= "http://www.tnpi.biz";
	my $toaster  = "$dl_site/internet/mail/toaster";

	$utility->chdir_source_dir("$src/mail");

	if ( -e $package ) 
	{
		my $r = $utility->source_warning($package, 1, $src);
		unless ($r) 
		{ 
			carp "install_qmail: sorry, I can't continue.\n"; 
			return 0;
		};
	};

	unless ( defined $conf->{'qmail_chk_usr_patch'} ) {
		print "\nCheckUser support causes the qmail-smtpd daemon to verify that
a user exists locally before accepting the message, during the SMTP conversation.
This prevents your mail server from accepting messages to email addresses that
don't exist in vpopmail. It is not compatible with system user mailboxes. \n\n";

		$chkusr = $utility->yes_or_no("Do you want qmail-smtpd-chkusr support enabled?");
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
			$utility->get_file("$site/$package.tar.gz"); 
			unless ( -e "$package.tar.gz" ) {
				croak "install_qmail FAILED: couldn't fetch $package.tar.gz!\n";
			};
		};
	};

	unless ( -e $patch ) 
	{
		$utility->get_file("$toaster/patches/$patch");
		unless ( -e $patch )  { croak "\n\nfailed to fetch patch $patch!\n\n"; };
	};

	my $tar      = $utility->find_the_bin("tar");
	my $patchbin = $utility->find_the_bin("patch");
	unless ( $tar && $patchbin ) { croak "couldn't find tar or patch!\n"; };

	$utility->syscmd( "$tar -xzf $package.tar.gz");
	chdir("$src/mail/$package") or croak "install_qmail: cd $src/mail/$package failed: $!\n";
	$utility->syscmd("$patchbin < $src/mail/$patch");

	$utility->file_write("conf-qmail",    $qmaildir) or croak "couldn't write to conf-qmail: $!";
	$utility->file_write("conf-vpopmail", $vpopdir) or croak "couldn't write to conf-vpopmail: $!";
	$utility->file_write("conf-mysql",    $mysql) or croak "couldn't write to conf-mysql: $!";

	my $servicectl = "/usr/local/sbin/services";
	if (-x $servicectl)
	{
		print "Stopping Qmail!\n";
		$utility->syscmd("$servicectl stop");
		$self->send_stop($conf);
	};

	$utility->syscmd( "make setup");

	unless ( -f "$qmaildir/control/servercert.pem" ) { 
		$utility->syscmd( "gmake cert") 
	};

	if ($chkusr) 
	{
		my $uid = getpwnam("vpopmail");
		my $gid = getgrnam("vchkpw");

		chown($uid, $gid, "$qmaildir/bin/qmail-smtpd") 
			or carp "chown $qmaildir/bin/qmail-smtpd failed: $!\n";

		$utility->syscmd("chmod 6555 $qmaildir/bin/qmail-smtpd");
	};

	unless ( -e "/usr/share/skel/Maildir" ) 
	{
		$utility->syscmd( "$qmaildir/bin/maildirmake /usr/share/skel/Maildir");
	};

#  system - will set to the systems hostname
#  qmail  - will set to contents of qmail/control/me

	$self->config($conf);

	if (-x $servicectl)
	{
		print "Stopping Qmail & supervised services!\n";
		$utility->syscmd("$servicectl start")
	};
};

sub smtp_memory_explanation($)
{
	my ($self, $conf) = @_;
	my ($sysmb, $maxsmtpd, $memorymsg, $perconnection, $connectmsg, $connections);

	if ( $os eq "freebsd" ) {
		$sysmb =  int(substr(`/sbin/sysctl hw.physmem`,12)/1024/1024);
		$memorymsg = "Your system has $sysmb MB of physical RAM.  ";
	} else {
		$sysmb = 1024;
		$memorymsg = "This example assumes a system with $sysmb MB of physical RAM.";
	}

	$maxsmtpd = int($sysmb * 0.75);

	if ($conf->{'install_mail_filtering'}) 
	{
		$perconnection=40;
		$connectmsg = "This is a reasonable value for systems which run filtering.";
	} else { 
		$perconnection = 15;
		$connectmsg = "This is a reasonable value for systems which do not run filtering.";
	}

	$connections = int ($maxsmtpd / $perconnection);
	$maxsmtpd = $connections * $perconnection;

	carp <<EOMAXMEM

These settings control the concurrent connection limit set by tcpserver,
and the per-connection RAM limit set by softlimit. 

Here are some suggestions for how to set these options:

$memorymsg

smtpd_max_memory = $maxsmtpd # approximately 75% of RAM

smtpd_max_memory_per_connection = $perconnection
   # $connectmsg

smtpd_max_connections = $connections

If you want to allow more than $connections simultaneous SMTP connections,
you'll either need to lower smtpd_max_memory_per_connection, or raise 
smtpd_max_memory.

smtpd_max_memory_per_connection is a VERY important setting, because
softlimit/qmail will start soft-bouncing mail if the smtpd processes
exceed this value, and the number needs to be sufficient to allow for
any virus scanning, filtering, or other processing you have configured
on your toaster. 

If you raise smtpd_max_memory over $sysmb MB to allow for more than
$connections incoming SMTP connections, be prepared that in some
situations your smtp processes might use more than $sysmb MB of memory. 
In this case, your system will use swap space (virtual memory) to
provide the necessary amount of RAM, and this slows your system down. In
extreme cases, this can result in a denial of service-- your server can
become unusable until the services are stopped.

EOMAXMEM

};

sub get_qmailscanner_virus_sender_ips($)
{
	my ($self, $conf) = @_;
	my @ips;

	my $debug   = $conf->{'debug'};
	my $block   = $conf->{'qs_block_virus_senders'};
	my $clean   = $conf->{'qs_quarantine_clean'};
	my $quarantine = $conf->{'qs_quarantine_dir'};

	unless (-d $quarantine)
	{
		if ( -d "/var/spool/qmailscan/quarantine" )
		{
			$quarantine = "/var/spool/qmailscan/quarantine";
		};
	};

	unless (-d "$quarantine/new")
	{
		carp "no quarantine dir!";
		return;
	};

	my @files = $utility->get_dir_files("$quarantine/new");

	foreach my $file (@files)
	{
		if ( $block ) 
		{
			my $ipline = `head -n 10 $file | grep HELO`;
			chomp $ipline;

			next unless ($ipline);
			print " $ipline  - " if $debug;

			my @lines = split(/Received/, $ipline);
			foreach my $line (@lines)
			{
				print $line if $debug;

				# Received: from unknown (HELO netbible.org) (202.54.63.141)
				my ($ip) = $line =~ /([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/;

				# we need to check the message and verify that it's
				# a virus that was blocked, not an admin testing
				# (Matt 4/3/2004)

				if ( $ip =~ /\s+/ or ! $ip )
				{
					print "$line\n" if $debug;
				}
				else { push @ips, $ip; };
				print "\t$ip" if $debug;
			};
			print "\n" if $debug;
		};
		unlink $file if ($clean);
	};

	my (%hash, @sorted);
	foreach my $ip (@ips) { $hash{$ip} = "1"; };
	foreach my $key ( keys %hash ) { push @sorted, $key; delete $hash{$key} };
	return @sorted;
};

sub UpdateVirusBlocks($;@)
{
	my ($self, $conf, @ips) = @_;

	my $time  = $conf->{'qs_block_virus_senders_time'};
	my $relay = $conf->{'smtpd_relay_database'};
	my $vpdir = $conf->{'vpopmail_home_dir'};
	unless ($vpdir) { $vpdir = "/usr/local/vpopmail"; };

	if ( $relay =~ /^vpopmail_home_dir\/(.*)\.cdb$/ ) { 
		$relay = "$vpdir/$1" 
	} else {
		if ( $relay =~ /^(.*)\.cdb$/ ) { $relay = $1; };
	};
	unless ( -r $relay ) { die "$relay selected but not readable!\n" };

	my @lines;

	my $debug = 0;
	my $in = 0;
	my $done = 0;
	my $now = time;
	my $expire = time + ($time * 3600);

	print "now: $now   expire: $expire\n" if $debug;

	my @userlines = $utility->file_read($relay);
	USERLINES: foreach my $line (@userlines)
	{
		unless ($in) { push @lines, $line };
		if ($line =~ /^### BEGIN QMAIL SCANNER VIRUS ENTRIES ###/)
		{
			$in = 1;

			for (@ips) {
				push @lines, "$_:allow,RBLSMTPD=\"-VIRUS SOURCE: Block will be automatically removed in $time hours: ($expire)\"\n";
			};
			$done++;
			next USERLINES;
		};

		if ($line =~ /^### END QMAIL SCANNER VIRUS ENTRIES ###/ )
		{
			$in = 0;
			push @lines, $line;
			next USERLINES;
		};

		if ($in) 
		{
			my ($timestamp) = $line =~ /\(([0-9]+)\)"$/;
			unless ($timestamp) { print "ERROR: malformed line: $line\n" if $debug; };

			if ($now > $timestamp ) {
				print "removing $timestamp\t" if $debug;
			} else {
				print "leaving $timestamp\t" if $debug;
				push @lines, $line;
			};
		};
	};

	if ($done)
	{
		if ($debug) {
			foreach my $line (@lines) { print "$line\n"; };
		};
		$utility->file_write($relay, @lines);
	} 
	else 
	{ 
		print "FAILURE: Couldn't find QS section in $relay\n You need to add the following lines as documented in the toaster-watcher.conf and FAQ:

### BEGIN QMAIL SCANNER VIRUS ENTRIES ###
### END QMAIL SCANNER VIRUS ENTRIES ###

"; 
	};

	my $tcprules = $utility->find_the_bin("tcprules");
	$utility->syscmd("$tcprules $vpdir/etc/tcp.smtp.cdb $vpdir/etc/tcp.smtp.tmp < $vpdir/etc/tcp.smtp");
	chmod(0644, "$vpdir/etc/tcp.smtp*");
};


=head2 get_list_of_rwls

	my $selected = $qmail->get_list_of_rwls($conf, $debug);

Here we collect a list of the RWLs from the configuration file that get's passed to us. 

returns an arrayref with a list of the enabled list from your config file.

=cut

sub get_list_of_rwls($;$)
{
	my ($self, $hash, $debug) = @_;
	my @list;

	foreach my $key ( keys %$hash )
	{		
		if ( $key =~ /^rwl/ && $hash->{$key} == 1 ) 
		{
			next if ( $key =~ /^rwl_enable/ );
			$key =~ /^rwl_([a-zA-Z_\.\-]*)\s*$/;

			print "good key: $1 \n" if $debug;
			push @list, $1;
		};
	};
	return \@list;
};

sub test_each_rbl($;$)
{

=head2 test_each_rbl

	my $available = $qmail->test_each_rbl($selected, $debug);

We get a list of RBL's in an arrayref and we run some tests on them to determine if they are working correctly. 

returns a list of the correctly functioning RBLs.

=cut

	my ($self, $rbls, $debug) = @_;
	my @list;

	use Mail::Toaster::DNS;
	my $t_dns = Mail::Toaster::DNS->new();

	foreach my $rbl (@$rbls)
	{
		print "testing $rbl.... " if $debug;
		my $r = $t_dns->rbl_test($rbl, $debug);
		if ( $r ) { push @list, $rbl };
		print "$r \n" if $debug;
	};
	return \@list;
};

sub get_list_of_rbls($;$)
{

=head2 get_list_of_rbls

	my $selected = $qmail->get_list_of_rbls($arrayref, $debug);

We get passed a configuration file (toaster-watcher.conf) and from it we extract all the RBL's the user has selected.

returns an array ref.

=cut

	my ($self, $hash, $debug) = @_;
	my @list;

	foreach my $key ( keys %$hash )
	{		
		#print "checking $key \n" if $debug;
		if ( $key =~ /^rbl/ && $hash->{$key} == 1 ) 
		{
			next if ( $key =~ /^rbl_enable/ );
			next if ( $key =~ /^rbl_reverse_dns/ );
			$key =~ /^rbl_([a-zA-Z_\.\-]*)\s*$/;

			print "good key: $1 \n" if $debug;
			push @list, $1;
		};
	};
	return \@list;
};

sub build_send_run($$;$)
{

=head2 build_send_run

	$qmail->build_send_run($conf, $file, $debug) ? print "success";

build_send_run generates a supervise run file for qmail-send. $file is the location of the file it's going to generate. $conf is a list of configuration variables pulled from toaster-watcher.conf. I typically use it like this:

	my $file = "/tmp/toaster-watcher-send-runfile";
	if ( $qmail->build_send_run($conf, $file ) )
	{
		$qmail->install_qmail_service_run( {file=>$file, service=>"send"}, $conf);
		$qmail->restart($conf, $debug);
	};

If it succeeds in building the file, it will install it. You can optionally restart qmail after installing a new run file.

=cut

	my ($self, $conf, $file, $debug) = @_;
	my ($mem);

	my   @lines = "#!/bin/sh\n";
	push @lines, "#    NOTICE: This file is generated automatically by toaster-watcher.pl. Do NOT hand";
	push @lines, "#      edit this file. Edit toaster-watcher.conf instead and then run toaster-watcher.pl";
	push @lines, "#      to make your settings active.\n";
	push @lines, "#    See perldoc toaster-watcher.conf for additional details. \n";
	push @lines, "PATH=$conf->{'qmail_dir'}/bin:/usr/local/bin:/usr/bin:/bin";
	push @lines, "export PATH\n";

	my $qsupervise = $conf->{'qmail_supervise'};
	unless ( $qsupervise )
	{
		print "build_send_run: WARNING: qmail_supervise not set in toaster-watcher.conf!\n";
	};
	unless ( -d $qsupervise )
	{
		$utility->syscmd("mkdir -p $qsupervise");
	};

	my $mailbox  = $conf->{'send_mailbox_string'}; $mailbox  ||= "./Maildir/";
	my $send_log = $conf->{'send_log_method'};     $send_log ||= "syslog";

	if ($send_log eq "syslog") 
	{
		push @lines, "# This uses splogger to send logging through syslog";
		push @lines, "# Change this in /usr/local/etc/toaster-watcher.conf";
		push @lines, "exec qmail-start $mailbox splogger qmail";
	} else {
		push @lines, "# This sends the output to multilog as directed in log/run";
		push @lines, "# make changes in /usr/local/etc/toaster-watcher.conf";
		push @lines, "exec qmail-start $mailbox 2>&1";
	};
	push @lines, "\n";

	if ( $utility->file_write($file, @lines) ) { return 1 } 
	else { print "error writing file $file\n"; return 0; };
};

sub build_pop3_run
{

=head2 build_pop3_run

	$qmail->build_pop3_run($conf, $file, $debug) ? print "success";

Generate a supervise run file for qmail-pop3d. $file is the location of the file it's going to generate. $conf is a list of configuration variables pulled from a config file (see ParseConfigfile). I typically use it like this:

	my $file = "/tmp/toaster-watcher-pop3-runfile";
	if ( $qmail->build_pop3_run($conf, $file ) )
	{
		$qmail->install_qmail_service_run( {file=>$file, service=>"pop3"}, $conf);
	};

If it succeeds in building the file, it will install it. You can optionally restart the service after installing a new run file.

=cut


	my ($self, $conf, $file, $debug) = @_;
	my ($mem);

	my $vdir       = $conf->{'vpopmail_home_dir'}; $vdir ||= "/usr/local/vpopmail";
	my $qctrl      = $conf->{'qmail_dir'} . "/control";
	my $qsupervise = $conf->{'qmail_supervise'};

	unless ( -d $qsupervise )
	{
		print "build_pop3_run: FAILURE: supervise dir $qsupervise doesn't exist!\n";
		return 0;
	};

	my   @lines = "#!/bin/sh\n";
	push @lines, "#    NOTICE: This file is generated automatically by toaster-watcher.pl. Do NOT hand";
	push @lines, "#      edit this file. Edit toaster-watcher.conf instead and then run toaster-watcher.pl";
	push @lines, "#      to make your settings active. See perldoc toaster-watcher.conf\n";
	push @lines, "PATH=$conf->{'qmail_dir'}/bin:$vdir/bin:/usr/local/bin:/usr/bin:/bin";
	push @lines, "export PATH\n";

	if ( $conf->{'pop3_hostname'} eq "qmail" ) {
		push @lines, "LOCAL=\`head -1 $qctrl/me\`";
		push @lines, "if [ -z \"\$LOCAL\" ]; then";
		push @lines, "\techo LOCAL is unset in $file";
		push @lines, "\texit 1";
		push @lines, "fi\n";
	};

	#exec softlimit -m 2000000 tcpserver -v -R -H -c50 0 pop3 

	if ( $conf->{'pop3_max_memory_per_connection'} > 0 ) {
		$mem  = $conf->{'pop3_max_memory_per_connection'} * 1024000; } 
	else { $mem = "3000000" };

	my $exec = "exec softlimit -m $mem tcpserver ";

	if ( $conf->{'pop3_lookup_tcpremotehost'}  == 0 ) { $exec .= "-H " };
	if ( $conf->{'pop3_lookup_tcpremoteinfo'}  == 0 ) { $exec .= "-R " };
	if ( $conf->{'pop3_dns_paranoia'}          == 1 ) { $exec .= "-p " };
	if ( $conf->{'pop3_max_connections'} != 40      ) { 
		$exec .= "-c".$conf->{'pop3_max_connections'}." ";
	};

	if ( $conf->{'pop3_dns_lookup_timeout'} != 26 ) {
		$exec .= "-t$conf->{'pop3_dns_lookup_timeout'} ";
	};

	if ( $conf->{'pop3_listen_on_address'} && $conf->{'pop3_listen_on_address'} ne "all" ) 
	{
		$exec .= "$conf->{'pop3_listen_on_address'} ";
	} 
	else {  $exec .= "0 " };

	if ( $conf->{'pop3_listen_on_port'} && $conf->{'pop3_listen_on_port'} ne "pop3" ) 
	{
		$exec .= "$conf->{'pop3_listen_on_port'} ";
	} 
	else {  $exec .= "pop3 " };

#qmail-popup mail.cadillac.net /usr/local/vpopmail/bin/vchkpw 
#qmail-pop3d Maildir 2>&1

	$exec .= "qmail-popup "; 

	if    ( $conf->{'pop3_hostname'} eq "qmail" ) 
	{
		$exec .= "\"\$LOCAL\" ";
	} 
	elsif ( $conf->{'pop3_hostname'} eq "system" ) 
	{
		use Sys::Hostname;
		$exec .= hostname() . " ";
	}
	else { $exec .= "$conf->{'pop3_hostname'} " };

	my $chkpass = $conf->{'pop3_checkpasswd_bin'};
	unless ($chkpass) { 
		print "WARNING: pop3_checkpasswd_bin is not set in toaster-watcher.conf!\n";
		$chkpass = "$vdir/bin/vchkpw"; 
	};
	if ( $chkpass =~ /^vpopmail_home_dir\/(.*)$/ ) { $chkpass = "$vdir/$1" };
	unless ( -x $chkpass ) {
		carp "WARNING: chkpasss $chkpass selected but not executable!\n" 
	};
	$exec .= "$chkpass qmail-pop3d Maildir ";

	if ( $conf->{'pop3_log_method'} eq "syslog" )
	{
		$exec .= "splogger qmail ";
	}
	else { $exec .= "2>&1 " };

	push @lines, $exec;

	if ( $utility->file_write($file, @lines) ) { return 1 } 
	else { print "error writing file $file\n"; return 0; };
};

sub test_smtpd_config_values($;$)
{

=head2 test_smtpd_config_values

Runs the following tests:

  make sure qmail_dir exists
  make sure vpopmail home dir exists
  make sure qmail_supervise is not a directory

=cut

	my ($self, $conf, $debug) = @_;

	my $file = "/usr/local/etc/toaster.conf";

	die "FAILURE: qmail_dir does not exist as configured in $file\n" 
		unless ( -d $conf->{'qmail_dir'} );

	if ( $conf->{'install_vpopmail'} ) {
		die "FAILURE: vpopmail_home_dir does not exist as configured in $file!\n"  
			unless ( -d $conf->{'vpopmail_home_dir'} );
	};

	croak "FAILURE: qmail_supervise is not a directory!\n"
		unless ( -d $conf->{'qmail_supervise'} );

#  This is no longer necessary with vpopmail > 5.4.0 and 0.4.2 SMTP-AUTH patch
#	croak "FAILURE: smtpd_hostname is not set in $file.\n"
#		unless ( $conf->{'smtpd_hostname'} );
};

sub set_service_dir($$)
{

=head2 set_service_dir

This is necessary because things such as service directories are now in /var by default but older versions of my toaster installed them in /. This will detect and adjust for that.

  $qmail->set_service_dir($conf, $prot);

$prot is the protocol (smtp, pop3, submit, send).

returned is the directory

=cut

	my ($self, $conf, $prot) = @_;

	my $debug      = $conf->{'debug'};
	my $servicedir = $conf->{'qmail_service'}; $servicedir ||= "/var/service";

	if ( ! -d $servicedir and $servicedir eq "/var/service" )
	{
		if ( -d "/service" )  { $servicedir = "/service" };
	};
	print "set_service_dir: service dir is $servicedir \n" if $debug;

	if ( $prot eq "smtp" ) 
	{
		my $dir = $conf->{'qmail_service_smtp'};
		unless ($dir) 
		{ 
			carp "WARNING: qmail_service_smtp is not set correctly in toaster-watcher.conf!\n";
			$dir = "$servicedir/smtp"; 
		} else {
			if ( $dir =~ /^qmail_service\/(.*)$/ ) { $dir = "$servicedir/$1"; };
		};
		print "set_service_dir: using $dir for $prot \n" if $debug;
		return $dir;
	} 
	elsif ( $prot eq "pop3" ) 
	{
		my $dir = $conf->{'qmail_service_pop3'};
		unless ($dir) 
		{ 
			carp "WARNING: qmail_service_pop3 is not set correctly in toaster-watcher.conf!\n";
			$dir = "$servicedir/pop3"; 
		} else {
			if ( $dir =~ /^qmail_service\/(.*)$/ ) { $dir = "$servicedir/$1"; };
		};
		print "set_service_dir: using $dir for $prot \n" if $debug;
		return $dir;
	} 
	elsif ( $prot eq "send" ) 
	{
		my $dir   = $conf->{'qmail_service_send'};

		unless ($dir) 
		{ 
			carp "WARNING: qmail_service_send is not set correctly in toaster-watcher.conf!\n";
			$dir = "$servicedir/send"; 
		} else {
			if ( $dir =~ /^qmail_service\/(.*)$/ ) { $dir = "$servicedir/$1"; };
		};
		print "set_service_dir: using $dir for $prot \n" if $debug;
		return $dir;
	}
	elsif ( $prot eq "submit" ) 
	{
		my $dir = $conf->{'qmail_service_submit'};
		unless ($dir) 
		{ 
			carp "WARNING: qmail_service_submit is not set correctly in toaster-watcher.conf!\n";
			$dir = "$servicedir/submit"; 
		} else {
			if ( $dir =~ /^qmail_service\/(.*)$/ ) { $dir = "$servicedir/$1"; };
		};
		print "set_service_dir: using $dir for $prot \n" if $debug;
		return $dir;
	};
};

sub build_smtp_run($$;$)
{

=head2 build_smtp_run

	if ( $qmail->build_smtp_run($conf, $file, $debug) ) { print "success" };

Generate a supervise run file for qmail-smtpd. $file is the location of the file it's going to generate. $conf is a list of configuration variables pulled from a config file (see ParseConfigfile). I typically use it like this:

	my $file = "/tmp/toaster-watcher-smtpd-runfile";
	if ( $qmail->build_smtp_run($conf, $file ) )
	{
		$qmail->install_qmail_service_run( {file=>$file, service=>"smtp"}, $conf);
	};

If it succeeds in building the file, it will install it. You can optionally restart the service after installing a new run file.

=cut

	my ($self, $conf, $file, $debug) = @_;
	my ($mem);

	$self->test_smtpd_config_values($conf, $debug);

	my $vdir = $conf->{'vpopmail_home_dir'};

	my   @lines = "#!/bin/sh\n";
	push @lines, "#    NOTICE: This file is generated automatically by toaster-watcher.pl. Do NOT hand";
	push @lines, "#      edit this file. Edit toaster-watcher.conf instead and then run toaster-watcher.pl";
	push @lines, "#      to make your settings active. See perldoc toaster-watcher.conf\n";
	push @lines, "PATH=$conf->{'qmail_dir'}/bin:$vdir/bin:/usr/local/bin:/usr/bin:/bin";
	push @lines, "export PATH\n";

	if ( $conf->{'filtering_method'} eq "smtp" )
	{
		my $queue = $conf->{'smtpd_qmail_queue'};
		unless ( -x $queue ) 
		{
			if ( -x "/var/qmail/bin/qmail-queue" ) 
			{
				carp "WARNING: $queue is not executable! I'm falling back to 
/var/qmail/bin/qmail-queue. You need to either (re)install $queue or update your
toaster-watcher.conf file to point to it's correct installed location.\n
You will continue to get this notice every 5 minutes until you fix this.\n";
				$queue = "/var/qmail/bin/qmail-queue";
			} else {
				carp "WARNING: $queue is not executable by uid $>.\n";
				return 0;
			};
		};
		push @lines, "QMAILQUEUE=\"$queue\"";
		push @lines, "export QMAILQUEUE\n";
		print "build_smtp_run: using $queue for QMAILQUEUE\n" if $debug;
	};

	my $qctrl = $conf->{'qmail_dir'} . "/control";
	unless ( -d $qctrl ) {
		carp "WARNING: build_smtp_run failed. $qctrl is not a directory";
		return 0;
	};

	my $qsupervise = $conf->{'qmail_supervise'};
	return 0 unless ( -d $qsupervise );

	if ( $conf->{'smtpd_hostname'} eq "qmail" ) 
	{
		push @lines, "LOCAL=\`head -1 $qctrl/me\`";
		push @lines, "if [ -z \"\$LOCAL\" ]; then";
		push @lines, "\techo LOCAL is unset in $qctrl/me";
		push @lines, "\texit 1";
		push @lines, "fi\n";
		print "build_smtp_run: qmail-smtpd hostname is set in $qctrl/me\n" if $debug;
	};

	push @lines, "if [ ! -f $qctrl/rcpthosts ]; then";
	push @lines, "\techo \"No $qctrl/rcpthosts!\"";
	push @lines, "\techo \"Refusing to start SMTP listener because it'll create an open relay\"";
	push @lines, "\texit 1";
	push @lines, "fi\n";

	if ( $conf->{'smtpd_max_memory_per_connection'} > 0 ) {
		$mem  = $conf->{'smtpd_max_memory_per_connection'} * 1024000; } 
	else { $mem = "8000000" };

	my $exec = "exec softlimit -m $mem tcpserver ";

	if ( $conf->{'smtpd_use_mysql_relay_table'} == 1 ) 
	{ 
		$exec .= "-S ";
		print "build_smtp_run: using MySQL based relay table\n" if $debug;
	};
	if ( $conf->{'smtpd_lookup_tcpremotehost'}  == 0 ) { $exec .= "-H " };
	if ( $conf->{'smtpd_lookup_tcpremoteinfo'}  == 0 ) { $exec .= "-R " };
	if ( $conf->{'smtpd_dns_paranoia'}          == 1 ) { $exec .= "-p " };

	my $maxcon;
	if ( $conf->{'smtpd_max_connections'} ) {
		$maxcon = $conf->{'smtpd_max_connections'};
	} else { $maxcon = 40; };

	if ( $conf->{'smtpd_max_memory'} ) {
		if ( ($mem / 1024000) * $maxcon > $conf->{'smtpd_max_memory'} ) {
			use POSIX;
			$maxcon = floor( $conf->{'smtpd_max_memory'} / ($mem / 1024000) );
			carp "\nbuild_smtp_run: your smtpd_max_memory_per_connection and smtpd_max_connections settings in toaster-watcher.conf have exceeded your smtpd_max_memory setting. I am reducing the connections to $maxcon to compensate. You should fix your settings.\n\n";
			$self->smtp_memory_explanation($conf);
		};
		$exec .= "-c$maxcon ";
	} else {
		if ( $conf->{'smtpd_max_connections'} != 40 ) { 
			$exec .= "-c$maxcon ";
		};
	};

	if ( $conf->{'smtpd_dns_lookup_timeout'} != 26      ) {
		$exec .= "-t$conf->{'smtpd_dns_lookup_timeout'} ";
		print "build_smtp_run: using custom dns timeout value: ". $conf->{'smtpd_dns_lookup_timeout'} . "\n" if $debug;
	};

	my $cdb  = $conf->{'smtpd_relay_database'};
	print "smtpd relay db: $cdb\n" if $debug;
	if ( $cdb =~ /^vpopmail_home_dir\/(.*)$/ ) { $cdb = "$vdir/$1" };
	if ( -r $cdb ) { $exec .= "-x $cdb " } else { croak "$cdb selected but not readable!\n" };

	my $uid = getpwnam( $conf->{'smtpd_run_as_user'}  );
	my $gid = getgrnam( $conf->{'smtpd_run_as_group'} );

	unless ( $uid && $gid ) 
	{
		print "WARNING: uid and gid not set!\n You need to edit toaster_watcher.conf 
and make sure smtpd_run_as_user and smtpd_run_as_group are set to valid usernames on your system.\n"; 
		return 0;
	};
	$exec .= "-u $uid -g $gid ";

	if ( $conf->{'smtpd_listen_on_address'} && $conf->{'smtpd_listen_on_address'} ne "all" ) 
	{
		$exec .= "$conf->{'smtpd_listen_on_address'} ";
		print "build_smtp_run: binding to IP " . $conf->{'smtpd_listen_on_address'} . "\n" if $debug;
	} 
	else {  $exec .= "0 " };

	if ( $conf->{'smtpd_listen_on_port'} && $conf->{'smtpd_listen_on_port'} ne "smtp" ) 
	{
		$exec .= "$conf->{'smtpd_listen_on_port'} ";
		print "build_smtp_run: listening on port: " . $conf->{'smtpd_listen_on_port'} . "\n" if $debug;
	} 
	else {  $exec .= "smtp " };

	if ( ( $conf->{'rwl_enable'} && $conf->{'rwl_enable'} > 0 ) 
	or   ( $conf->{'rbl_enable'} && $conf->{'rbl_enable'} > 0 )  )
	{
		$exec .= "rblsmtpd ";

		print "build_smtp_run: using rblsmtpd\n" if $debug;

		my $timeout = $conf->{'rbl_timeout'}; unless ($timeout) { $timeout = 60; };
		if ( $timeout != 60 ) { $exec .= "-t $timeout "; };

		if ( $conf->{'rbl_enable_fail_closed'} ) { $exec .= "-c "; };

		unless ( $conf->{'rbl_enable_soft_failure'} ) { $exec .= "-b "; };

		if ( $conf->{'rwl_enable'} && $conf->{'rwl_enable'} > 0 )
		{
			print "testing RWLs...." if $debug;
			my $list  = $self->get_list_of_rwls($conf, $debug);
#			my $rwls  = $self->test_each_rwl( $list, $debug);
#			foreach my $rwl ( @$rwls ) { $exec = $exec . "-a $rwl " };
			foreach my $rwl ( @$list ) { $exec = $exec . "-a $rwl " };
			print "done.\n" if $debug;
		} 
		else { print "no RWL's selected\n" if $debug };

		if ( $conf->{'rbl_enable'} && $conf->{'rbl_enable'} > 0 )
		{
			print "testing RBLs...." if $debug;
			my $list  = $self->get_list_of_rbls($conf, $debug);
			my $rbls  = $self->test_each_rbl( $list, $debug);
			foreach my $rbl ( @$rbls ) { $exec = $exec . "-r $rbl " };
			print "done.\n" if $debug;
		} 
		else { print "no RBL's selected\n" if $debug };
	};

	$exec .= "qmail-smtpd "; 

	if ( $conf->{'smtpd_auth_enable'} ) 
	{
		print "build_smtp_run: enabling SMTP-AUTH\n" if $debug;

		if ( $conf->{'smtpd_hostname'} && $conf->{'qmail_smtpd_auth_0.31'} ) {
			if    ( $conf->{'smtpd_hostname'} eq "qmail" ) 
			{
				$exec .= "\"\$LOCAL\" ";
			} 
			elsif ( $conf->{'smtpd_hostname'} eq "system" ) 
			{
				use Sys::Hostname;
				$exec .= hostname() . " ";
			}
			else { $exec .= $conf->{'smtpd_hostname'} . " " };
		};
	
		my $chkpass = $conf->{'smtpd_checkpasswd_bin'};
		if ( $chkpass =~ /^vpopmail_home_dir\/(.*)$/ ) { $chkpass = "$vdir/$1" };
		croak "$chkpass selected but not executable!\n" unless ( -x $chkpass );

		$exec .= "$chkpass /usr/bin/true ";
	};

	if ( $conf->{'smtpd_log_method'} eq "syslog" )
	{
		$exec = $exec . "splogger qmail ";
	}
	else { $exec = $exec . "2>&1 " };
	print "build_smtp_run: logging to ". $conf->{'smtpd_log_method'} . "\n" if $debug;

	push @lines, $exec;

	if ( $utility->file_write($file, @lines) ) { return 1 } 
	else { print "error writing file $file\n"; return 0; };
};

sub build_submit_run($$;$)
{

=head2 build_submit_run

	if ( $qmail->build_submit_run($conf, $file, $debug) ) { print "success"};

Generate a supervise run file for qmail-smtpd running on submit. $file is the location of the file it's going to generate. $conf is a list of configuration variables pulled from a config file (see ParseConfigfile). I typically use it like this:

	my $file = "/tmp/toaster-watcher-smtpd-runfile";
	if ( $qmail->build_submit_run($conf, $file ) )
	{
		$qmail->install_qmail_service_run( {file=>$file, service=>"submit"}, $conf);
	};

If it succeeds in building the file, it will install it. You can optionally restart the service after installing a new run file.

=cut

	my ($self, $conf, $file, $debug) = @_;
	my ($mem);

	$self->test_smtpd_config_values($conf, $debug);

	my $vdir = $conf->{'vpopmail_home_dir'};

	my   @lines = "#!/bin/sh\n";
	push @lines, "#    NOTICE: This file is generated automatically by toaster-watcher.pl. Do NOT hand";
	push @lines, "#      edit this file. Edit toaster-watcher.conf instead and then run toaster-watcher.pl";
	push @lines, "#      to make your settings active. See perldoc toaster-watcher.conf\n";
	push @lines, "PATH=$conf->{'qmail_dir'}/bin:$vdir/bin:/usr/local/bin:/usr/bin:/bin";
	push @lines, "export PATH\n";

	if ( $conf->{'filtering_method'} eq "smtp" )
	{
		my $queue = $conf->{'smtpd_qmail_queue'};
		unless ( -x $queue ) { 
			carp "WARNING: $queue is not executable by uid $>\n";
			return 0;
		};
		push @lines, "QMAILQUEUE=\"$queue\"";
		push @lines, "export QMAILQUEUE\n";
	};

	my $qctrl = $conf->{'qmail_dir'} . "/control";
	unless ( -d $qctrl ) {
		carp "WARNING: build_submit_run failed. $qctrl is not a directory";
		return 0;
	};

	my $qsupervise = $conf->{'qmail_supervise'};
	return 0 unless ( -d $qsupervise );

	my $qsuper_submit = $conf->{'qmail_supervise_submit'};
	unless ( $qsuper_submit ) {
		$qsuper_submit = "$qsupervise/submit";
	} else {
		if ( $qsuper_submit =~ /^supervise\/(.*)$/ ) 
		{
			$qsuper_submit = "$qsupervise/$1";
		};
	};
	print "build_submit_run: qmail-submit supervise dir is $qsuper_submit\n" if $debug;

	if ( $conf->{'submit_hostname'} eq "qmail" ) {
		push @lines, "LOCAL=\`head -1 $qctrl/me\`";
		push @lines, "if [ -z \"\$LOCAL\" ]; then";
		push @lines, "\techo LOCAL is unset in $qsuper_submit/run";
		push @lines, "\texit 1";
		push @lines, "fi\n";
	};

	push @lines, "if [ ! -f $qctrl/rcpthosts ]; then";
	push @lines, "\techo \"No $qctrl/rcpthosts!\"";
	push @lines, "\techo \"Refusing to start SMTP listener because it'll create an open relay\"";
	push @lines, "\texit 1";
	push @lines, "fi\n";

	if ( $conf->{'submit_max_memory_per_connection'} > 0 ) {
		$mem  = $conf->{'submit_max_memory_per_connection'} * 1024000; } 
	else { $mem = "8000000" };

	my $exec = "exec softlimit -m $mem tcpserver ";

	if ( $conf->{'submit_lookup_tcpremotehost'}  == 0 ) { $exec .= "-H " };
	if ( $conf->{'submit_lookup_tcpremoteinfo'}  == 0 ) { $exec .= "-R " };
	if ( $conf->{'submit_dns_paranoia'}          == 1 ) { $exec .= "-p " };
	if ( $conf->{'submit_max_connections'} != 40      ) { 
		$exec .= "-c$conf->{'submit_max_connections'} ";
	};

	if ( $conf->{'submit_dns_lookup_timeout'} != 26      ) {
		$exec .= "-t$conf->{'submit_dns_lookup_timeout'} ";
	};

	my $uid = getpwnam( $conf->{'submit_run_as_user'}  );
	my $gid = getgrnam( $conf->{'submit_run_as_group'} );

	unless ( $uid && $gid ) { print "WARNING: uid and gid not found!\n"; return 0 };
	$exec .= "-u $uid -g $gid ";

	if ( $conf->{'submit_listen_on_address'} && $conf->{'submit_listen_on_address'} ne "all" ) 
	{
		$exec .= "$conf->{'submit_listen_on_address'} ";
	} 
	else {  $exec .= "0 " };

	if ( $conf->{'submit_listen_on_port'} && $conf->{'submit_listen_on_port'} ne "submit" ) 
	{
		$exec .= "$conf->{'submit_listen_on_port'} ";
	} 
	else {  $exec .= "submit " };

	$exec .= "qmail-smtpd "; 

	if ( $conf->{'submit_auth_enable'} ) 
	{
		if ( $conf->{'submit_hostname'} && $conf->{'qmail_smtpd_auth_0.31'} )
		{
			if    ( $conf->{'submit_hostname'} eq "qmail" ) 
			{
				$exec .= "\"\$LOCAL\" ";
			} 
			elsif ( $conf->{'submit_hostname'} eq "system" ) 
			{
				use Sys::Hostname;
				$exec .= hostname() . " ";
			}
			else { $exec .= $conf->{'submit_hostname'} . " " };
		};
	
		my $chkpass = $conf->{'submit_checkpasswd_bin'};
		if ( $chkpass =~ /^vpopmail_home_dir\/(.*)$/ ) { $chkpass = "$vdir/$1" };
		croak "$chkpass selected but not executable!\n" unless ( -x $chkpass );

		$exec .= "$chkpass /usr/bin/true ";
	};

	if ( $conf->{'submit_log_method'} eq "syslog" )
	{
		$exec .= "splogger qmail ";
	}
	else 
	{ 
		$exec .= "2>&1 ";
	};

	push @lines, $exec;

	if ( $utility->file_write($file, @lines) ) { return 1 } 
	else { print "error writing file $file\n"; return 0; };
};

sub install_qmail_service_run($$)
{

=head2 install_qmail_service_run

Installs a new supervise/run file for a supervised service.

	my $file = "/tmp/toaster-watcher-smtpd-runfile";

	if ( $qmail->build_smtp_run($conf, $file, $debug ) )
	{
		$qmail->install_qmail_service_run( {file=>$file, service=>"smtp"}, $debug);
	};

Input is a hashref with these values:

  file    - new file that was created (typically /tmp/something) 
  service - one of (smtp, send, pop3, submit)

returns 1 on success, 0 on error

=cut

	my ($self, $vals, $conf) = @_;
	my $file;

	my $tmpfile = $vals->{'file'};

	if ( $vals->{'destination'} ) {
		$file    = $vals->{'destination'};
	} else {
		my $dir  = $self->set_supervise_dir($conf, $vals->{'service'});
		$file  ||= "$dir/run";
	}

	my $debug = $vals->{'debug'};

	unless ( -e $tmpfile ) {
		print "FATAL: the file to install ($tmpfile) is missing!\n";
		return 0;
	};

	unless ( -e $file ) 
	{
		print "install_qmail_service_run: installing $file..." if $debug;
	} 
	else 
	{
		print "install_qmail_service_run: updating $file..." if $debug;
	};

	my $diff = $utility->files_diff($tmpfile, $file, "text", $debug);
	unless ( $diff ) {
		print "done. (same)\n" if $debug;
		return 0;
	};
	print "done. (diff):\n$diff\n" if $debug;

	chmod(00755, $tmpfile) or die "couldn't chmod $tmpfile: $!\n";

	# email diffs to admin
	if ($conf->{'supervise_rebuilt_notice'} ) 
	{
		my $diff = $utility->find_the_bin("diff");

		$perl->module_load( {module=>"Mail::Send", ports_name=>"p5-Mail-Tools", ports_group=>"mail"} );
		require Mail::Send;
		my $msg = new Mail::Send;
		$msg->subject("$file updated");
		$msg->to($conf->{'toaster_admin_email'});
		my $fh = $msg->open;

		print $fh "This message is being sent to you because you have supervise_rebuilt_notice set in toaster-watcher.conf. I am notifitying you that $file has been altered. The difference between the new file and the old one is:\n\n";

		my $diffie = `$diff $tmpfile $file`;
		print $fh $diffie;
		$fh->close;
	};

	if ( $> == 0 ) 
	{
		# we're root
		use File::Copy;
		copy($file, "$file.bak") if (-e $file);
		move($tmpfile, $file)    if (-e $tmpfile);
	} 
	else 
	{
		my $sudo = $utility->find_the_bin("sudo");
		unless ( -x $sudo ) 
		{
			warn "FAILED: you aren't root, sudo isn't installed, and you don't have permission to control the qmail daemon. Sorry, I can't go on!\n";
			return 0;
		};

		$utility->syscmd("$sudo cp $file $file.bak") if (-e $file);
		$utility->syscmd("$sudo mv $tmpfile $file") if (-e $tmpfile);
	};

	print "done\n" if $debug;

	#if ( $conf->{''} ) { };
	return 1;
};


sub smtpd_restart($$;$)
{

=head2 smtpd_restart

	$qmail->smtpd_restart($conf, "smtp", $debug)

Use smtpd_restart to restart the qmail-smtpd process. It will send qmail-smtpd the TERM signal causing it to exit. It will restart immediately because it's supervised. 

=cut

	my ($self, $conf, $proto, $debug) = @_;

	my $dir = $self->set_service_dir($conf, $proto);

	unless ( -d $dir || -l $dir ) { 
		carp "smtpd_restart: no such dir: $dir!\n"; 
		return 0;
	};

	print "restarting qmail smtpd..." if $debug;

	my $svc = $utility->find_the_bin("svc");
	$utility->syscmd( "$svc -t $dir");

	print "done.\n" if $debug;
}

sub restart(;$)
{

=head2 restart

	$qmail->restart()

Use to restart the qmail-send process. It will send qmail-send the TERM signal and then return.

=cut

	my ($self, $conf) = @_;

	my $svc      = $utility->find_the_bin("svc");
	my $qcontrol = $self->find_qmail_send_control_dir($conf);

	# send qmail-send a TERM signal
	system "$svc -t $qcontrol";

	return 1;
};

sub send_stop(;$)
{

=head2 send_stop

	$qmail->send_stop()

Use send_stop to quit the qmail-send process. It will send qmail-send the TERM signal and then wait until it's shut down before returning. If qmail-send fails to shut down within 100 seconds, then we force kill it, causing it to abort any outbound SMTP sessions that are active. This is safe, as qmail will attempt to deliver them again, and again until it succeeds.

=cut

	my ($self, $conf) = @_;

	my $svc      = $utility->find_the_bin("svc");
	my $svstat   = $utility->find_the_bin("svstat");
	my $qcontrol = $self->find_qmail_send_control_dir($conf);

	# send qmail-send a TERM signal
	system "$svc -d $qcontrol";

	# loop up to a thousand seconds waiting for qmail-send to die
	foreach my $i ( 1..1000 ) 
	{
		my $r = `$svstat $qcontrol`;
		chomp $r;
		if ( $r =~ /^.*:\sdown\s[0-9]*\sseconds/ ) {
			print "Yay, we're down!\n";
			return 0;
		} elsif ( $r =~ /supervise not running/ ) {
			print "Yay, we're down!\n";
			return 0;
		} else {
			# if more than 100 seconds passes, lets kill off the qmail-remote
			# processes that are forcing us to wait.
			
			if ($i > 100) {
				$utility->syscmd("killall qmail-remote");
			};
			print "$r\n";
		};
		sleep 1;
	};
	return 1;
};

sub find_qmail_send_control_dir
{
	my ($self, $conf) = @_;

	my $qcontrol = $conf->{'qmail_service_send'} if ( defined $conf);
	unless ( -d $qcontrol ) 
	{ 
		if ( -d "/var/service/send" ) {
			$qcontrol = "/var/service/send";
		} elsif ( -d "/service/send" ) {
			$qcontrol = "/service/send";
		} elsif ( -d "/service/qmail-send" ) {
			$qcontrol = "/service/qmail-send";
		} else {
			carp "send_stop: FAILED! Couldn't find your qmail control dir!\n";
			return 0;
		};
	};

	return $qcontrol;
};

sub send_start()
{

=head2 send_start

	$qmail->send_start() - Start up the qmail-send process.

After starting up qmail-send, we verify that it's running before returning.

=cut

	my $svc    = $utility->find_the_bin("svc");
	my $svstat = $utility->find_the_bin("svstat");
	my $qcontrol = "/service/send";

	# Start the qmail-send (and related programs)
	system "$svc -u $qcontrol";

	# loop until it's up and running.
	foreach my $i ( 1..100 ) {
		my $r = `$svstat $qcontrol`;
		chomp $r;
		if ( $r =~ /^.*:\sup\s\(pid [0-9]*\)\s[0-9]*\sseconds$/ ) {
			print "Yay, we're up!\n";
			return 0;
		};
		sleep 1;
	};
	return 1;
};

sub check_control($;$)
{
	my ($self, $dir, $debug) = @_;
	my $qcontrol = "/service/send";

	print "check_control: checking $qcontrol/$dir..." if $debug;

	unless ( -d $dir )
	{
		print "FAILED.\n" if $debug;
		print "HEY! The control directory for qmail-send is not
		in $dir where I expected. Please edit this script
		and set $qcontrol to the appropriate directory!\n";
		return 0;
	} else {
		print "ok.\n" if $debug;
		return 1;
	};
};

sub queue_check($;$)
{
	my ($self, $dir, $debug) = @_;
	my $qdir     = "/var/qmail/queue";
	
	print "queue_check: checking $qdir/$dir..." if $debug;
	
	unless ( -d $dir )
	{
		print "FAILED.\n" if $debug;
		print "HEY! The queue directory for qmail is not
		$dir where I expect. Please edit this script
		and set $qdir to the appropriate directory!\n";
		return 0;
	} else {
		print "ok.\n" if $debug;
		return 1;
	};
};

sub queue_process()
{

=head2 queue_process
	
queue_process - Tell qmail to process the queue immediately

=cut

	my $svc    = $utility->find_the_bin("svc");
	my $qcontrol = "/service/send";

	print "\nSending ALRM signal to qmail-send.\n";
	system "$svc -a $qcontrol";
};

sub check_rcpthosts
{

=head2 check_rcpthosts

	$qmail->check_rcpthosts($qmaildir);

Checks the rcpthosts file and compare it to users/assign. Any zones that are in users/assign but not in control/rcpthosts or control/morercpthosts will be presented as a list and you'll be expected to add them to morercpthosts.

=cut

	my ($self, $qmaildir) = @_;
	$qmaildir ||= "/var/qmail";

	my $assign  = "$qmaildir/users/assign";
	my @domains = $self->get_domains_from_assign($assign);
	my $rcpt    = "$qmaildir/control/rcpthosts";
	my $mrcpt   = "$qmaildir/control/morercpthosts";

	my (@f2, %rcpthosts, $domains, $count);
	my @f1      = $utility->file_read( $rcpt  );

	@f2 = $utility->file_read( $mrcpt ) if ( -e "$qmaildir/control/morercpthosts" );

	foreach my $f (@f1, @f2)
	{
		chomp $f;
		$rcpthosts{$f} = 1;
	};

	foreach my $v (@domains)
	{
		my $domain = $v->{'dom'};
		unless ( $rcpthosts{$domain} )
		{
			print "$domain\n";
			$count++;
		};
		$domains++;
	};

	if ($count == 0) {
		print "Congrats, your rcpthosts is correct!\n";
		return 1;
	};

	if ( $domains > 50 ) 
	{
		print "\nDomains listed above should be added to the file 
	$mrcpt. Don't forget to do this afterwards:

	$qmaildir/bin/qmail-newmrh
\n";
	}
	else 
	{
		print "\nDomains listed above should be added to the file $rcpt. \n";
	};
};

sub config 
{

=head2 config

	$qmail->config($conf);

Qmail is fantastic because it's so easy to configure. Just edit files and put the right values in them. However, many find that a problem because it's not so easy to always know the sytax for what goes in every file, and exactly where that file might be. This sub takes your values from toaster-watcher.conf and puts them where they need to be. It modifies the following files:

   /var/qmail/control/concurrencyremote
   /var/qmail/control/me
   /var/qmail/control/tarpitcount
   /var/qmail/control/tarpitdelay
   /var/qmail/control/sql
   /var/qmail/alias/.qmail-postmaster
   /var/qmail/alias/.qmail-root
   /var/qmail/alias/.qmail-mailer-daemon

If you don't have toaster-watcher installed, it prompts you for each value.

=cut

	my ($self, $conf) = @_;

	my $qmaildir = $conf->{'qmail_dir'}; $qmaildir ||= "/var/qmail";
	my $control  = "$qmaildir/control";
	my $host     = $conf->{'toaster_hostname'};

	if ( $host)
	{
		if    ( $host eq "qmail" ) { $host = `hostname`; } 
		elsif ( $host eq "system") { $host = `hostname`; } 
		elsif ( $host eq "mail.example.com" ) {
			$host = $utility->answer("the hostname for this mail server");
		};
	} 
	else {
		$host = $utility->answer("the hostname for this mail server");
	};

	my $dbhost = $conf->{'vpopmail_mysql_repl_slave'};
	unless ( $dbhost ) 
	{
		$dbhost = $utility->answer("the hostname for your database server (localhost)");
	};
	$dbhost = "localhost" unless ($dbhost);

	my $postmaster = $conf->{'toaster_admin_email'};
	unless ( $postmaster ) 
	{
		$postmaster = $utility->answer("the email address you use for administrator mail");
	};

	my $password = $conf->{'vpopmail_mysql_repl_pass'};
	unless ($password) {
		$password = $utility->answer("the SQL password for user vpopmail"); 
	};

	unless ( -e "$control/concurrencyremote" ) 
	{
		my $ccr = $conf->{'qmail_concurrencyremote'};
		unless ($ccr) { $ccr = "255"};

		print "config: setting concurrencyremote to $ccr\n";
		$utility->file_write("$control/concurrencyremote", $ccr);
		chmod(00644, "$control/concurrencyremote");
	};

	unless ( -e "$control/me" ) 
	{
		print "config: setting qmail hostname to $host\n";
		$utility->file_write("$control/me", $host);
	};

	unless ( -e "$control/tarpitcount" ) 
	{
		print "config: setting tarpitcount to 50\n";
		$utility->file_write("$control/tarpitcount", "50");
	};

	unless ( -e "$control/tarpitdelay" ) 
	{
		print "config: setting tarpitdelay to 5\n";
		$utility->file_write("$control/tarpitdelay", "5");
	};

	unless ( -e "$control/mfcheck" ) 
	{
		print "config: setting mfcheck \n";
		if ($conf->{'qmail_mfcheck_enable'}) {
			$utility->file_write("$control/mfcheck", "1");
		} else {
			$utility->file_write("$control/mfcheck", "0");
		};
	};

	unless ( -s "$qmaildir/alias/.qmail-postmaster" ) 
	{
		print "config: setting postmaster\@localdomains to $postmaster\n";
		$utility->file_write("$qmaildir/alias/.qmail-postmaster",    $postmaster);
	};

	unless ( -s "$qmaildir/alias/.qmail-root" ) 
	{
		print "config: setting root\@localdomains to $postmaster\n";
		$utility->file_write("$qmaildir/alias/.qmail-root",          $postmaster);
	};

	unless ( -s "$qmaildir/alias/.qmail-mailer-daemon" ) 
	{
		print "config: setting mailer-daemon\@localdomains to $postmaster\n";
		$utility->file_write("$qmaildir/alias/.qmail-mailer-daemon", $postmaster);
	};

	unless ( -s "$control/sql" ) 
	{
		my @lines  = "server $dbhost";
		push @lines, "port 3306";
		push @lines, "database vpopmail";
		push @lines, "table relay";
		push @lines, "user vpopmail";
		push @lines, "pass $password";
		push @lines, "time 1800";

		print "config: adding MySQL config file for tcpserver -S\n";
		$utility->file_write("$control/sql", @lines);

		my $uid = getpwnam("vpopmail");
		my $gid = getgrnam("vchkpw");
		chown( $uid, $gid, "$control/sql"); 
		chown( $uid, $gid, "$control/servercert.pem"); 
		chmod(00640, "$control/sql");
		chmod(00640, "$control/servercert.pem");
		chmod(00640, "$control/clientcert.pem");
	};

	unless ( -e "$control/locals" ) 
	{
		print "config: touching $control/locals\n";
		$utility->file_write("$control/locals", "\n");
	};

    my $manpath = "/etc/manpath.config";
	if (-e $manpath)
	{
		unless ( `grep "/var/qmail/man" $manpath | grep -v grep` )
		{
			print "config: appending /var/qmail/man to MANPATH\n";
			$utility->file_append($manpath, ["OPTIONAL_MANPATH\t\t/var/qmail/man"]);
		};
	};
};

=head2 configure_qmail_control

	$qmail->configure_qmail_control($conf);

Installs the qmail control script as well as the startup (services.sh) script.

=cut

sub configure_qmail_control($)
{
	my ($self, $conf) = @_;

	my $dl_site  = $conf->{'toaster_dl_site'};   $dl_site  ||= "http://www.tnpi.biz";
	my $toaster  = "$dl_site/internet/mail/toaster";
	my $qmaildir = $conf->{'qmail_dir'};         $qmaildir ||= "/var/qmail";
	my $confdir  = $conf->{'system_config_dir'}; $confdir  ||= "/usr/local/etc";

	my $qmailctl  = "/var/qmail/bin/qmailctl";
	if ( -e $qmailctl ) 
	{
		print "configure_qmail_control: $qmailctl already exists.\n";
	}
	else 
	{
		print "configure_qmail_control: installing $qmailctl\n";
		$self->control_write($qmailctl);
		chmod(00751, $qmailctl);
		$utility->syscmd("$qmailctl cdb");
	};

	$qmailctl  = "/usr/local/sbin/qmail";
	unless ( -e $qmailctl ) {
		print "configure_qmail_control: adding symlink $qmailctl\n";
		symlink("/var/qmail/bin/qmailctl", $qmailctl) or carp "couldn't link $qmailctl: $!";
	};

	$qmailctl  = "/usr/local/sbin/qmailctl";
	unless ( -e $qmailctl ) {
		print "configure_qmail_control: adding symlink $qmailctl\n";
		symlink("/var/qmail/bin/qmailctl", $qmailctl) or carp "couldn't link $qmailctl: $!";
	};

	if ( -e "$qmaildir/rc" ) 
	{
		print "configure_qmail_control: $qmaildir/rc already exists.\n";
	}
	else 
	{
		my $file = "/tmp/toaster-watcher-send-runfile";
		if ( $self->build_send_run($conf, $file ) )
		{
			$self->install_qmail_service_run( {file=>$file, destination=>"$qmaildir/rc"});
		};
		print "configure_qmail_control: creating $qmaildir/rc.\n";
	};

	if ( -e "$confdir/rc.d/qmail.sh" ) 
	{
		unlink("$confdir/rc.d/qmail.sh") 
			or die "couldn't delete $confdir/rc.d/qmail.sh: $!";
		print "configure_qmail_control: removing $confdir/rc.d/qmail.sh\n";
	};
};

sub install_supervise_run($)
{

=head2 install_supervise_run

	$qmail->install_supervise_run($conf);

$conf is a hashref of values pulled from toaster-watcher.conf.

Generates the qmail/supervise/*/run files based on your settings.

=cut

	my ($self, $conf) = @_;

	my $debug     = $conf->{'debug'};
	my $supervise = $conf->{'qmail_supervise'}; $supervise ||= "/var/qmail/supervise";

	foreach my $prot ( qw/ smtp send pop3 submit / )
	{
		my $supervisedir = $self->set_supervise_dir($conf, $prot);
		my $run_f = "$supervisedir/run";

		unless ( -e  $run_f )
		{
			if ($prot eq "smtp")
			{
				my $file = "/tmp/toaster-watcher-smtpd-runfile";
				if ( $self->build_smtp_run($conf, $file, $debug ) )
				{
					print "install_supervise_run: installing $run_f\n" if $debug;
					$self->install_qmail_service_run( {file=>$file, destination=>$run_f} );
				};
			}
			elsif ($prot eq "send")
			{
				my $file = "/tmp/toaster-watcher-send-runfile";
				if ( $self->build_send_run($conf, $file, $debug ) )
				{
					print "install_supervise_run: installing $run_f\n" if $debug;
					$self->install_qmail_service_run( {file=>$file, destination=>$run_f} );
				};
			}
			elsif ($prot eq "pop3")
			{
				my $file = "/tmp/toaster-watcher-pop3-runfile";
				if ( $self->build_pop3_run($conf, $file, $debug ) )
				{
					print "install_supervise_run: installing $run_f\n" if $debug;
					$self->install_qmail_service_run( {file=>$file, destination=>$run_f} );
				};
			}
			elsif ($prot eq "submit")
			{
				my $file = "/tmp/toaster-watcher-submit-runfile";
				if ( $self->build_submit_run($conf, $file, $debug ) )
				{
					print "install_supervise_run: installing $run_f\n" if $debug;
					$self->install_qmail_service_run( {file=>$file, destination=>$run_f} );
				};
			};
		} 
		else
		{
			print "install_supervise_run: $run_f already exists!\n";
		};
	};
};

sub install_supervise_log_run($)
{

=head2 install_supervise_log_run

	$qmail->install_supervise_log_run($conf);

$conf is a hash of values. See $utility->parse_config or toaster-watcher.conf for config values.

Installs the files the control your supervised processes logging. Typically this consists of qmail-smtpd, qmail-send, and qmail-pop3d. The generated files are:
                
 qmail_supervise/pop3/log/run
 qmail_supervise/smtp/log/run
 qmail_supervise/send/log/run
 qmail_supervise/submit/log/run

=cut

	my ($self, $conf) = @_;
	my (@lines);

	my $debug     = $conf->{'debug'};
	my $supervise = $conf->{'qmail_supervise'}; $supervise ||= "/var/qmail/supervise";

	my $log = $conf->{'qmail_log_base'};
	unless ($log) { 
		print "NOTICE: qmail_log_base is not set in toaster-watcher.conf!\n";
		$log = "/var/log/mail" 
	};

	# Create log/run files
	foreach my $serv ( qw/ smtp send pop3 submit / )
	{
		my $supervisedir = $self->set_supervise_dir($conf, $serv);
		my $run_f = "$supervisedir/log/run";

		unless ( -s $run_f ) 
		{
			print "install_supervise_log_run: creating file $run_f\n";

			     @lines= "#!/bin/sh\n";
			push @lines, "#    NOTICE: This file is generated automatically by toaster-watcher.pl. Do NOT hand";
			push @lines, "#      edit this file. Edit toaster-watcher.conf instead and then run toaster-watcher.pl";
			push @lines, "#      to make your settings active. See perldoc toaster-watcher.conf\n";
			push @lines, "PATH=/var/qmail/bin:/usr/local/bin:/usr/bin:/bin";
			push @lines, "export PATH\n";

			my $runline = "exec setuidgid qmaill multilog t ";

			if ($serv eq "smtp") 
			{
				if ( $conf->{'smtpd_log_postprocessor'} eq "maillogs" ) {
					$runline .= "!./smtplog ";
				};

				my $maxbytes = $conf->{'smtp_log_maxsize_bytes'};
				unless ($maxbytes) { $maxbytes = "100000"; };

				if      ( $conf->{'smtpd_log_method'} eq "stats" ) 
				{
					$runline .= "-* +stats s$maxbytes $log/smtp";
				} 
				elsif ( $conf->{'smtpd_log_method'} eq "disabled" ) 
				{
					$runline .= "-* ";
				} 
				else { $runline .= "s$maxbytes $log/smtp"; };
			} 
			elsif ( $serv eq "send") 
			{
				if ( $conf->{'send_log_postprocessor'} eq "maillogs" ) {
					$runline .= "!./sendlog ";
				};

				my $maxbytes = $conf->{'send_log_maxsize_bytes'};
				unless ($maxbytes) { $maxbytes = "100000"; };

				if      ( $conf->{'send_log_method'} eq "stats" ) 
				{
					$runline .= "-* +stats s$maxbytes $log/send ";
				} 
				elsif ( $conf->{'send_log_method'} eq "disabled" ) 
				{
					$runline .= "-* ";
				}
				else 
				{
					if ( $conf->{'send_log_isoqlog'} ) 
					{
						$runline .= "n288 s100000 $log/send "; 
					} else {
						$runline .= "s100000 $log/send "; 
					};
				};
			} 
			elsif ( $serv eq "pop3") 
			{
				if ( $conf->{'pop3_log_postprocessor'} eq "maillogs" ) {
					$runline .= "!./pop3log ";
				};

				my $maxbytes = $conf->{'pop3_log_maxsize_bytes'};
				unless ($maxbytes) { $maxbytes = "100000"; };

				if      ( $conf->{'pop3_log_method'} eq "stats" ) 
				{
					$runline .= "-* +stats s$maxbytes $log/pop3 ";
				} 
				elsif ( $conf->{'pop3_log_method'} eq "disabled" ) 
				{
					$runline .= "-* ";
				}
				else { $runline .= "s$maxbytes $log/pop3 "; };
			} 
			elsif ( $serv eq "submit") 
			{
				if ( $conf->{'submit_log_postprocessor'} eq "maillogs" ) {
					$runline .= "!./submitlog ";
				};

				my $maxbytes = $conf->{'submit_log_maxsize_bytes'};
				unless ($maxbytes) { $maxbytes = "100000"; };

				if      ( $conf->{'submit_log_method'} eq "stats" ) 
				{
					$runline .= "-* +stats s$maxbytes $log/submit";
				} 
				elsif ( $conf->{'submit_log_method'} eq "disabled" ) 
				{
					$runline .= "-* ";
				} 
				else { $runline .= "s$maxbytes $log/submit"; };
			};

			push @lines, $runline;
			
			$utility->file_write($run_f, @lines);
			chmod(00751, $run_f);
		} 
		else 
		{
			print "install_supervise_log_run: $run_f already exists.\n";
		};
	};
};

sub get_domains_from_assign(;$$$$)
{

=head2 get_domains_from_assign

Fetch a list of domains from the qmaildir/users/assign file.

	$qmail->get_domains_from_assign($assign, $debug, $match, $value);

 $assign is the path to the assign file.
 $debug is optional
 $match is an optional field to match (dom, uid, dir)
 $value is the pattern to  match

returns an array

=cut


	my ($self, $assign, $debug, $match, $value) = @_;

	unless ($assign) { $assign = "/var/qmail/users/assign"; };

	my @domains;
	my @lines = $utility->file_read($assign);
	print "Parsing through the file $assign..." if $debug;

	foreach my $line (@lines)
	{
		chomp $line;
		my @fields = split(":", $line);
		if ($fields[0] ne "" && $fields[0] ne ".") 
		{
			my %domain = (
				stat => "$fields[0]",
				dom  => "$fields[1]",
				uid  => "$fields[2]",
				gid  => "$fields[3]",
				dir  => "$fields[4]"
			);

			unless ($match) { push @domains, \%domain; } 
			else 
			{
				if    ( $match eq "dom" && $value eq "$fields[1]" ) {
					push @domains, \%domain;
				} 
				elsif ( $match eq "uid" && $value eq "$fields[2]" ) {
					push @domains, \%domain;
				} 
				elsif ( $match eq "dir" && $value eq "$fields[4]" ) {
					push @domains, \%domain;
				};
			};
		};
	};
	print "done.\n\n" if $debug;;
	return @domains;
}

sub control_write($)
{
	my ($self, $file) = @_;
	open FILE, ">$file" or carp "control_write: FAILED to open $file: $!\n";

	print FILE <<EOQMAILCTL
#!/bin/sh

PATH=/var/qmail/bin:/usr/local/bin:/usr/bin:/bin
export PATH

case "\$1" in
	stat)
		cd /var/qmail/supervise
		svstat * */log
	;;
	doqueue|alrm|flush)
		echo "Sending ALRM signal to qmail-send."
		svc -a /var/qmail/supervise/send
	;;
	queue)
		qmail-qstat
		qmail-qread
	;;
	reload|hup)
		echo "Sending HUP signal to qmail-send."
		svc -h /var/qmail/supervise/send
	;;
	pause)
		echo "Pausing qmail-send"
		svc -p /var/qmail/supervise/send
		echo "Pausing qmail-smtpd"
		svc -p /var/qmail/supervise/smtp
	;;
	cont)
		echo "Continuing qmail-send"
		svc -c /var/qmail/supervise/send
		echo "Continuing qmail-smtpd"
		svc -c /var/qmail/supervise/smtp
	;;
	restart)
		echo "Restarting qmail:"
		echo "* Stopping qmail-smtpd."
		svc -d /var/qmail/supervise/smtp
		echo "* Sending qmail-send SIGTERM and restarting."
		svc -t /var/qmail/supervise/send
		echo "* Restarting qmail-smtpd."
		svc -u /var/qmail/supervise/smtp
	;;
	cdb)
		if [ -s ~vpopmail/etc/tcp.smtp ]
		then
			tcprules ~vpopmail/etc/tcp.smtp.cdb ~vpopmail/etc/tcp.smtp.tmp < ~vpopmail/etc/tcp.smtp
			chmod 644 ~vpopmail/etc/tcp.smtp*
			echo "Reloaded ~vpopmail/etc/tcp.smtp."
		fi 
                
		if [ -s /etc/tcp.smtp ]
		then
			tcprules /etc/tcp.smtp.cdb /etc/tcp.smtp.tmp < /etc/tcp.smtp
			chmod 644 /etc/tcp.smtp*
			echo "Reloaded /etc/tcp.smtp."
		fi

		if [ -s /var/qmail/control/simcontrol ]
		then
			if [ -x /var/qmail/bin/simscanmk ]
			then
				/var/qmail/bin/simscanmk
				echo "Reloaded /var/qmail/control/simcontrol."
			fi
		fi

		if [ -s /var/qmail/users/assign ]
		then
			if [ -x /var/qmail/bin/qmail-newu ]
			then
				echo "Reloaded /var/qmail/users/assign."
			fi
		fi

		if [ -s /var/qmail/control/morercpthosts ]
		then
			if [ -x /var/qmail/bin/qmail-newmrh ]
			then
				/var/qmail/bin/qmail-newmrh
				echo "Reloaded /var/qmail/control/morercpthosts"
			fi
		fi
	;;
	help)
		cat <<HELP
		pause -- temporarily stops mail service (connections accepted, nothing leaves)
		cont -- continues paused mail service
		stat -- displays status of mail service
		cdb -- rebuild the cdb files (tcp.smtp, users, simcontrol)
		restart -- stops and restarts smtp, sends qmail-send a TERM & restarts it
		doqueue -- sends qmail-send ALRM, scheduling queued messages for delivery
		reload -- sends qmail-send HUP, rereading locals and virtualdomains
		queue -- shows status of queue
		alrm -- same as doqueue
		hup -- same as reload
HELP
	;;
	*)
		echo "Usage: \$0 {restart|doqueue|flush|reload|stat|pause|cont|cdb|queue|help}"
		exit 1
	;;
esac

exit 0

EOQMAILCTL
;

	close FILE;
};


1;
__END__


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>

=head1 BUGS

None known. Report any to author.

=head1 TODO

=head1 SEE ALSO

 http://www.tnpi.biz/computing/
 http://www.tnpi.biz/internet/mail/toaster/

Mail::Toaster::CGI, Mail::Toaster::DNS, Mail::Toaster::Logs,
Mail::Toaster::Qmail, Mail::Toaster::Setup


=head1 COPYRIGHT

Copyright (c) 2004, The Network People, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut
