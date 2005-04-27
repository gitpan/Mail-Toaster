#!/usr/bin/perl
use strict;
#use warnings;

#
# $Id: Apache.pm,v 4.10 2005/04/14 21:07:37 matt Exp $
#

package Mail::Toaster::Apache;

use Carp;
use vars qw($VERSION); 
$VERSION  = '4.07';

my $os = $^O;

sub new;
sub vhost_show($$);
sub vhost_enable($$);
sub vhost_disable($$);
sub vhost_delete($$);
sub vhosts_get_match;
sub vhosts_get_file;
sub vhost_create($$);
sub restart($);
sub vhost_exists;
sub install_apache2;
sub install_apache1($;$);
sub conf_patch(;$);
sub RemoveOldApacheSources;
sub install_ssl_certs(;$);
sub OpenSSLConfigNote;
sub InstallDSACert;
sub InstallRSACert;

use lib "lib";
use lib "../..";

use Mail::Toaster::Perl 1;    my $perl    = Mail::Toaster::Perl->new;
use Mail::Toaster::Utility 1; my $utility = Mail::Toaster::Utility->new;

=head1 NAME

Mail::Toaster::Apache

=head1 SYNOPSIS

Install Apache 1 or 2 based on settings in toaster-watcher.conf

=head1 DESCRIPTION 

Perl methods for working with Apache.

Install section builds a high performance statically compiled web server with SSL, PHP, and Perl support.

=head1 METHODS

=head2 new

   use Mail::Toaster::Apache
   my $apache = Mail::Toaster::Apache->new();

use this function to create a new apache object. From there you can use all the functions
included in this document.

Each method expect to recieve one or two hashrefs. The first hashref must have a value set for <i>vhost</i> and optional values set for the following: ip, serveralias serveradmin, documentroot, redirect, ssl, sslcert, sslkey, cgi, customlog, customerror.

The second hashref is key/value pairs from sysadmin.conf. See that file for details of what options you can set there to influence the behavior of these methods..

=cut


sub new()
{
	my $class = shift;
	my $self = {};
	bless ($self, $class);
	return $self;
}


=head2 InstallApache1

	use Mail::Toaster::Apache;
	my $apache = new Mail::Toaster::Apache;

	$apache->install_apache1("/usr/local/src")

Builds Apache from sources with DSO for all but mod_perl which must be compiled statically in order to work at all.

Will build Apache in the directory as shown. After compile, the script will show you a few options for testing and completing the installation.

Also installs mod_php4 and mod_ssl.

=cut

sub install_apache1($;$) 
{
	my ($self, $src, $conf) = @_;
	if ( $os eq "darwin" ) 
	{
		print "\n\nNOTICE: Darwin comes with Apache pre-installed! Simply open
System Preferences->Sharing and enable Web Sharing. If for some crazy reason you
still want Apache1, simply follow the instructions here: \n";
		print "http://www.macdevcenter.com/pub/a/mac/2002/12/18/apache_modssl.html\n";

		return 0;
	};

	use File::Copy;

	my $apache   = "apache_1.3.31";
	my $mod_perl = "mod_perl-1.29";
	my $mod_ssl  = "mod_ssl-2.8.19-1.3.31";
	my $layout   = "FreeBSD.layout";

	if ( $os eq "freebsd" ) 
	{
		use Mail::Toaster::FreeBSD;
		my $freebsd = Mail::Toaster::FreeBSD->new();

		if ( $conf->{'package_install_method'} eq "packages" ) 
		{
			$freebsd->package_install("mm");
			$freebsd->package_install("gettext");
			$freebsd->package_install("libtool");
			$freebsd->package_install("apache");
			$freebsd->package_install("p5-libwww");
		} else {
			$freebsd->port_install("mm",        "devel");
			$freebsd->port_install("gettext",   "textproc");
			$freebsd->port_install("libtool",   "devel");
			$freebsd->port_install("apache",    "www", "apache13");
			$freebsd->port_install("p5-libwww", "www");
		};
		$freebsd->port_install   ("cronolog", "sysutils");

		my $log = "/var/log/apache";
		unless ( -d $log) 
		{
			mkdir($log, 0755) or croak "Couldn't create $log: $!\n";
			my $uid = getpwnam("www");
			my $gid = getgrnam("www");
			chown($uid, $gid, $log);
		};

		unless ( $freebsd->is_port_installed("apache") ) {
			# get it registered in the ports db
			$freebsd->package_install("apache");
		};

		$freebsd->rc_dot_conf_check("apache_enable", "apache_enable=\"YES\"");
	};

	$utility->chdir_source_dir("$src/www", $src);

	unless ( -e "$apache.tar.gz" ) {
		$utility->get_file("http://www.apache.org/dist/httpd/$apache.tar.gz");
	};

	unless ( -e "$mod_perl.tar.gz" ) {
		$utility->get_file("http://perl.apache.org/dist/$mod_perl.tar.gz");
	};

	unless ( -e "$mod_ssl.tar.gz" ) {
		$utility->get_file("http://www.modssl.org/source/$mod_ssl.tar.gz");
	};

	unless ( -e $layout ) 
	{
		$utility->get_file("http://www.tnpi.biz/internet/www/apache.layout");
		move("apache.layout", $layout);
	};

	RemoveOldApacheSources($apache);

	foreach my $package ($apache, $mod_perl, $mod_ssl) 
	{
		if ( -d $package )
		{
			my $r = $utility->source_warning($package, 1);
			unless ($r) { croak "sorry, I can't continue.\n" };
		};
		$utility->archive_expand("$package.tar.gz");
	};

	chdir($mod_ssl);
	if ( $os eq "darwin") { $utility->syscmd("./configure --with-apache=../$apache") } 
	else {
		$utility->syscmd("./configure --with-apache=../$apache --with-ssl=/usr --enable-shared=ssl --with-mm=/usr/local");
	};
	chdir("../$mod_perl");
	if ( $os eq "darwin") {
		$utility->syscmd( "perl Makefile.PL APACHE_SRC=../$apache NO_HTTPD=1 USE_APACI=1 PREP_HTTPD=1 EVERYTHING=1");
	} else {
		$utility->syscmd( "perl Makefile.PL DO_HTTPD=1 USE_APACI=1 APACHE_PREFIX=/usr/local EVERYTHING=1 APACI_ARGS='--server-uid=www, --server-gid=www, --enable-module=so --enable-module=most, --enable-shared=max --disable-shared=perl, --enable-module=perl, --with-layout=../$layout:FreeBSD, --without-confadjust'");
	};
	$utility->syscmd("make");

	if ( $os eq "darwin") {
		$utility->syscmd("make install");
		chdir("../$apache");
		$utility->syscmd( "./configure --with-layout=Darwin --enable-module=so --enable-module=ssl --enable-shared=ssl --activate-module=src/modules/perl/libperl.a --disable-shared=perl --without-execstrip");
		$utility->syscmd("make");
		$utility->syscmd("make install");
	};

	if (-e "../$apache/src/httpd") 
	{
		print <<EOM

Apache build successful, now you must install as follows:

For new installs:

     cd $src/www/$mod_perl
     make test
     cd ../$apache; make certificate TYPE=custom
     rm /usr/local/etc/apache/httpd.conf
     cd ../$mod_perl; make install
     cd /usr/ports/www/mod_php4; make install clean (optional)
     apachectl stop; apachectl startssl

For re-installs:

     cd $src/www/$mod_perl;\n\tmake test
     make install
     cd /usr/ports/www/mod_php4; make install clean (optional)
     apachectl stop; apachectl startssl
EOM
;
	};

	return 1;
};



=head2	install_apache2

	use Mail::Toaster::Apache;
	my $apache = new Mail::Toaster::Apache;

	$apache->install_apache2($conf);

Builds Apache from sources with DSO for all modules. Also installs mod_perl2 and mod_php4.

Currently tested on FreeBSD and Mac OS X. On FreeBSD, the php is installed. It installs both the PHP cli and mod_php Apache module. This is done because the SpamAssassin + SQL module requires pear-DB and the pear-DB port thinks it needs the lang/php port installed. There are other ports which also have this requirement so it's best to just have it installed.

This script also builds default SSL certificates, based on your preferences in openssl.cnf (usually in /etc/ssl) and makes a few tweaks to your httpd.conf (for using PHP & perl scripts). 

Values in $conf are set in toaster-watcher.conf. Please refer to that file to see how you can influence your Apache build.

=cut

sub install_apache2
{
	my ($self, $conf) = @_;

	if ( $os eq "freebsd" ) 
	{
		use Mail::Toaster::FreeBSD 1;
		my $freebsd = Mail::Toaster::FreeBSD->new();

		print "\n";
		if ( $] < 5.006 ) 
		{
			$freebsd->port_install("perl5", "lang", "", "perl-5");
			$utility->syscmd("/usr/local/bin/use.perl port");
		};

		if ( $conf->{'package_install_method'} eq "packages" ) 
		{
			$freebsd->package_install("apache2", "apache-2");
			$freebsd->package_install("p5-libwww");
		};

		my $options = "WITH_OPENSSL_PORT";
		$options .= ",WITH_PROXY_MODULES=yes" if $conf->{'install_apache_proxy'};
		if ( $conf->{'install_apache_suexec'} ) {
			$options .= ",WITH_SUEXEC=yes";
			$options .= ",SUEXEC_DOCROOT=$conf->{'apache_suexec_docroot'}" if $conf->{'apache_suexec_docroot'};
			$options .= ",SUEXEC_USERDIR=$conf->{'apache_suexec_userdir'}" if $conf->{'apache_suexec_userdir'};
			$options .= ",SUEXEC_SAFEPATH=$conf->{'apache_suexec_safepath'}" if $conf->{'apache_suexec_safepath'};
			$options .= ",SUEXEC_LOGFILE=$conf->{'apache_suexec_logfile'}" if $conf->{'apache_suexec_logfile'};
			$options .= ",SUEXEC_UIDMIN=$conf->{'apache_suexec_uidmin'}" if $conf->{'apache_suexec_uidmin'};
			$options .= ",SUEXEC_GIDMIN=$conf->{'apache_suexec_gidmin'}" if $conf->{'apache_suexec_gidmin'};
			$options .= ",SUEXEC_CALLER=$conf->{'apache_suexec_caller'}" if $conf->{'apache_suexec_caller'};
			$options .= ",SUEXEC_UMASK=$conf->{'apache_suexec_umask'}" if $conf->{'apache_suexec_umask'};
		};

		$freebsd->port_install ("apache2", "www", undef, "apache", $options);
		$freebsd->port_install ("p5-libwww", "www");
		$freebsd->port_install ("cronolog", "sysutils");

		if ( $conf->{'package_install_method'} eq "packages" ) {
			$freebsd->package_install("bison") or  $freebsd->port_install ("bison", "devel");
			$freebsd->package_install("gd")    or  $freebsd->port_install ("gd", "graphics");
		} else {
			$freebsd->port_install ("bison", "devel");
			$freebsd->port_install ("gd", "graphics");
		};

		if ( $conf->{'install_php'} == "5" ) {
			$freebsd->port_install ("php5", "lang", undef, undef, "WITH_APACHE2");
		} else {
			$freebsd->port_install ("php4", "lang", undef, undef, "WITH_APACHE2");
		};

		if ( $conf->{'install_apache2_modperl'} ) {
			$freebsd->port_install ("mod_perl2", "www");
		};

		$freebsd->rc_dot_conf_check("apache2_enable", "apache2_enable=\"YES\"");
		$freebsd->rc_dot_conf_check("apache2ssl_enable", "apache2ssl_enable=\"YES\"");

		$self->install_ssl_certs();
		$self->conf_patch($conf);
	}
	elsif ( $os eq "darwin" )
	{
		print "\nInstalling Apache 2 on Darwin (MacOS X)?\n\n";

		if ( -d "/usr/dports/dports" ) {
			use Mail::Toaster::Darwin;
			my $darwin = Mail::Toaster::Darwin->new();

			$darwin->port_install("apache2");
			$darwin->port_install("php4", "+apache2");
		} 
		else 
		{
			print "Yikes, I can't find DarwinPorts! Try following the instructions here:  
http://www.tnpi.biz/internet/mail/toaster/darwin.shtml.\n";
		};
	}
	else
	{
		print "\nTrying to Apache 2 on $os from sources. \n\n";

		unless ( -d "/usr/local/src") { mkdir("/usr/local/src", 0755) };
		unless ( -d "/usr/local/src/www") { mkdir("/usr/local/src/www", 0755) };
		chdir("/usr/local/src/www");

		my $apache   = "httpd-2.0.52";
		my $mod_perl = "mod_perl-2.0.0-RC4";
		my $mod_php  = "php-4.3.10";

		unless ( -e "$apache.tar.gz" ) {
			$utility->get_file("http://www.apache.org/dist/httpd/$apache.tar.gz");
		};

		unless ( -e "$mod_perl.tar.gz" ) {
			$utility->get_file("http://perl.apache.org/dist/$mod_perl.tar.gz");
		};

		unless ( -e "$mod_php.tar.gz" ) {
			$utility->get_file("http://us2.php.net/distributions/$mod_php.tar.gz");
		};

		foreach my $package ( $apache, $mod_perl, $mod_php) 
		{
			if ( -d $package )
			{
				my $r = $utility->source_warning($package, 1);
				unless ($r) { croak "sorry, I can't continue.\n"; };
			};
			$utility->archive_expand("$package.tar.gz");
		};
	
		if ( -d $apache ) 
		{
			chdir($apache);
			$utility->syscmd("./configure --enable-layout=Darwin --enable-modules=all --enable-mods-shared=all --enable-so");
			$utility->syscmd("make");
			$utility->syscmd("make install");
		};

		if ( -d $mod_perl ) {
			chdir($mod_perl);
			$utility->syscmd("perl Makefile.PL");
			$utility->syscmd("make");
			$utility->syscmd("make install");
		};

		if ( -d $mod_php ) 
		{
			chdir($mod_php);
			$utility->syscmd("./configure");
			$utility->syscmd("make");
			$utility->syscmd("make install");
		};

		print "Don't forget to add this to httpd.conf:  

LoadModule perl_module modules/mod_perl.so

";
		print "sorry, not yet on $os \n";
	}
};


=head2 install_ssl_certs

Builds and installs SSL certificates in the locations that Apache expects to find them. This allows me to build a SSL enabled web server with a minimal amount of human interaction.


=cut

sub install_ssl_certs(;$)
{
	my ($self, $type) = @_;

	my $crtdir = "/usr/local/etc/apache2/ssl.crt";
	unless (-d $crtdir) { $utility->syscmd("mkdir -p $crtdir"); };

	my $keydir = "/usr/local/etc/apache2/ssl.key";
	unless (-d $keydir) { $utility->syscmd("mkdir -p $keydir"); };

	if ($type eq "rsa") 
	{
		unless ( -e "$crtdir/server.crt" ) 
		{
			OpenSSLConfigNote();
			InstallRSACert($crtdir, $keydir);
		} else {
			print "install_ssl_certs: $crtdir/server.crt is already installed!\n";
		};
	} 
	elsif ( $type eq "dsa" ) 
	{
		unless ( -e "$crtdir/server-dsa.crt" ) {
			#OpenSSLConfigNote();
			#InstallDSACert($crtdir, $keydir);
		} else {
			print "install_ssl_certs: $crtdir/server-dsa.crt is already installed!\n";
		};
	} 
	else {
		unless ( -e "$crtdir/server.crt" ) {
			OpenSSLConfigNote();
			InstallRSACert($crtdir, $keydir);
		} else {
			print "install_ssl_certs: $crtdir/server.crt is already installed!\n";
		};
		unless ( -e "$crtdir/server-dsa.crt" ) {
#			OpenSSLConfigNote();
#			InstallDSACert($crtdir, $keydir);
		} else {
			print "install_ssl_certs: $crtdir/server-dsa.crt is already installed!\n";
		};
	};
};


=head2 restart

Restarts Apache. 

On FreeBSD, we use the rc.d script if it's available because it's smarter than apachectl. Under some instances, sending apache a restart signal will cause it to crash and not restart. The control script sends it a TERM, waits until it has done so, then starts it back up.

    $apache->restart($vals);

=cut

sub restart($)
{
	my ($self, $vals) = @_;

	# restart apache

	print "restarting apache.\n" if $vals->{'debug'};

	my $sudo = $utility->sudo();

	if    ( -x "/usr/local/etc/rc.d/apache2.sh" ) {
		$utility->syscmd("$sudo /usr/local/etc/rc.d/apache2.sh stop");
		$utility->syscmd("$sudo /usr/local/etc/rc.d/apache2.sh start");
	}
	elsif ( -x "/usr/local/etc/rc.d/apache.sh" ) {
		$utility->syscmd("$sudo /usr/local/etc/rc.d/apache.sh stop");
		$utility->syscmd("$sudo /usr/local/etc/rc.d/apache.sh start");
	}
	else { 
		my $apachectl = $utility->find_the_bin("apachectl");
		if ( -x $apachectl ) {
			$utility->syscmd("$sudo $apachectl graceful");
		} else {
			warn "WARNING: couldn't restart Apache!\n " 
		}
	};
};

=head2 vhost_create

Create an Apache vhost container like this:

  <VirtualHost *:80 >
    ServerName blockads.com
    ServerAlias ads.blockads.com
    DocumentRoot /usr/home/blockads.com/ads
    ServerAdmin admin@blockads.com
    CustomLog "| /usr/local/sbin/cronolog /usr/home/example.com/logs/access.log" combined
    ErrorDocument 404 "blockads.com
  </VirtualHost>

	my $apache->vhost_create($vals, $conf);

	Required values:

         ip  - an ip address
       name  - vhost name (ServerName)
     docroot - Apache DocumentRoot

    Optional values

 serveralias - Apache ServerAlias names (comma seperated)
 serveradmin - Server Admin (email address)
         cgi - CGI directory
   customlog - obvious
 customerror - obvious
      sslkey - SSL certificate key
     sslcert - SSL certificate
 
=cut

sub vhost_create($$)
{
	my ($self, $vals, $conf) = @_;

	if ( $self->vhost_exists($vals, $conf) ) {
		return { error_code=>400, error_desc=>"Sorry, that virtual host already exists!"};
	};

	# test all the values and make sure we've got enough to form a vhost
	# minimum needed: vhost servername, ip[:port], documentroot

	my $ip      = $vals->{'ip'} || '*:80';    # a default value
	my $name    = lc($vals->{'vhost'});
	my $docroot = $vals->{'documentroot'};
	my $home    = $vals->{'admin_home'} || "/home";

	unless ( $docroot ) {
		if ( -d "$home/$name" ) { $docroot = "$home/$name" };
		return { error_code=>400, error_desc=>"documentroot was not set and could not be determined!"} unless -d $docroot;
	};

	if ($vals->{'debug'}) { use Data::Dumper; print Dumper($vals); };

	# define the vhost
	my @lines = "\n<VirtualHost $ip>";
	push @lines, "	ServerName $name";
	push @lines, "	DocumentRoot $docroot";
	push @lines, "	ServerAdmin "  . $vals->{'serveradmin'}  if $vals->{'serveradmin'};
	push @lines, "	ServerAlias "  . $vals->{'serveralias'}  if $vals->{'serveralias'};
	if ( $vals->{'cgi'} ) {
		if    ( $vals->{'cgi'} eq "basic"    ) { push @lines, "	ScriptAlias /cgi-bin/ \"/usr/local/www/cgi-bin.basic/"; }
		elsif ( $vals->{'cgi'} eq "advanced" ) { push @lines, "	ScriptAlias /cgi-bin/ \"/usr/local/www/cgi-bin.advanced/\""; }
		elsif ( $vals->{'cgi'} eq "custom"   ) { push @lines, "	ScriptAlias /cgi-bin/ \"" . $vals->{'documentroot'} . "/cgi-bin/\""; }
		else  {  push @lines, "	ScriptAlias "  .  $vals->{'cgi'} };
		
	};
	# options needs some directory logic included if it's going to be used
	# I won't be using this initially, but maybe eventually...
	#push @lines, "	Options "      . $vals->{'options'}      if $vals->{'options'};

	push @lines, "	CustomLog "    . $vals->{'customlog'}    if $vals->{'customlog'};
	push @lines, "	CustomError "  . $vals->{'customerror'}  if $vals->{'customerror'};
	if ( $vals->{'ssl'} ) {
		if ( $vals->{'sslkey'} && $vals->{'sslcert'} && -f $vals->{'sslkey'} && $vals->{'sslcert'} ) {
			push @lines, "	SSLEngine on";
			push @lines, "	SSLCertificateKey "  . $vals->{'sslkey'}  if $vals->{'sslkey'};
			push @lines, "	SSLCertificateFile " . $vals->{'sslcert'} if $vals->{'sslcert'};
		} else {
			return { error_code=>400, error_desc=>"FATAL: ssl is enabled but either the key or cert is missing!"};
		};
	};
	push @lines, "</VirtualHost>\n";

	print join ("\n", @lines) if $vals->{'debug'};

	# write vhost definition to a file
	my ($vhosts_conf) = $self->vhosts_get_file($vals, $conf);

	if ( -f $vhosts_conf ) {
		print "appending to file: $vhosts_conf\n" if $vals->{'debug'};
		$utility->file_append($vhosts_conf, \@lines);
	} else {
		print "writing to file: $vhosts_conf\n" if $vals->{'debug'};
		$utility->file_write($vhosts_conf, @lines);
	};

	$self->restart($vals);

	print "returning success or error\n" if $vals->{'debug'};
	return { error_code=>200, error_desc=>"vhost creation successful"};
};

=head2 vhost_enable

Enable a (previously) disabled virtual host. 

    $apache->vhost_enable($vals, $conf);

=cut

sub vhost_enable($$)
{
	my ($self, $vals, $conf) = @_;

	if ( $self->vhost_exists($vals, $conf) ) {
		return { error_code=>400, error_desc=>"Sorry, that virtual host is already enabled."};
	};

	print "enabling $vals->{'vhost'} \n";

	# get the file the disabled vhost would live in
	my ($vhosts_conf) = $self->vhosts_get_file ($vals, $conf);

	print "the disabled vhost should be in $vhosts_conf.disabled\n" if $vals->{'debug'};

	unless ( -s "$vhosts_conf.disabled" ) {
		return { error_code=>400, error_desc=>"That vhost is not disabled, I cannot enable it!"};
	};

	$vals->{'disabled'} = 1;

	# slit the file into two parts
	(undef, my $match, $vals)  = $self->vhosts_get_match($vals, $conf);

	print "enabling: \n", join ("\n", @$match), "\n";

	# write vhost definition to a file
	if ( -f $vhosts_conf ) {
		print "appending to file: $vhosts_conf\n" if $vals->{'debug'};
		$utility->file_append($vhosts_conf, $match);
	} else {
		print "writing to file: $vhosts_conf\n" if $vals->{'debug'};
		$utility->file_write($vhosts_conf, @$match);
	};

	$self->restart($vals);

	if ( $vals->{'documentroot'} ) 
	{ 
		print "docroot: $vals->{'documentroot'} \n";

		# chmod 755 the documentroot directory
		if ( $vals->{'documentroot'} && -d $vals->{'documentroot'} ) {
			my $sudo  = $utility->sudo();
			my $chmod = $utility->find_the_bin("chmod");
			$utility->syscmd("$sudo $chmod 755 $vals->{'documentroot'}");
		};
	};

	print "returning success or error\n" if $vals->{'debug'};
	return {error_code=>200, error_desc=>"vhost enabled successfully"};
};

=head2 vhost_disable

Disable a previously disabled vhost.

    $apache->vhost_disable($vals, $conf);

=cut

sub vhost_disable($$)
{
	my ($self, $vals, $conf) = @_;

	unless ( $self->vhost_exists($vals, $conf) ) {
		return { error_code => 400, error_desc => "Sorry, that virtual host does not exist." };
	};

	print "disabling $vals->{'vhost'}\n";

	# get the file the vhost lives in
	$vals->{'disabled'} = 0;
	my ($vhosts_conf) = $self->vhosts_get_file($vals, $conf);

	# split the file into two parts
	(my $new, my $match, $vals)  = $self->vhosts_get_match($vals, $conf);

	print "Disabling: \n" . join ("\n", @$match) . "\n";

	$utility->file_write("$vhosts_conf.new", @$new);

	# write out the .disabled file (append if existing)
	if ( -f "$vhosts_conf.disabled" ) 
	{
		# check to see if it's already in there
		$vals->{'disabled'} = 1;
		(undef, my $dis_match, $vals) = $self->vhosts_get_match($vals, $conf);

		if ( @$dis_match[1] ) {
			print "it's already in $vhosts_conf.disabled. skipping append.\n";
		} else {
			# if not, append it
			print "appending to file: $vhosts_conf.disabled\n" if $vals->{'debug'};
			$utility->file_append("$vhosts_conf.disabled", $match);
		};
	} 
	else {
		print "writing to file: $vhosts_conf.disabled\n" if $vals->{'debug'};
		$utility->file_write("$vhosts_conf.disabled", @$match);
	};

	my $sudo  = $utility->sudo();

	if ( (-s "$vhosts_conf.new") && (-s "$vhosts_conf.disabled") ) {
		print "Yay, success!\n" if $vals->{'debug'};
		if ( $< eq 0 ) {
			use File::Copy;    # this only works if we're root
			move("$vhosts_conf.new", $vhosts_conf);
		} else {
			my $mv = $utility->find_the_bin("move");
			$utility->syscmd("$sudo $mv $vhosts_conf.new $vhosts_conf");
		};
	} else {
		return { error_code => 500, error_desc => "Oops, the size of $vhosts_conf.new or $vhosts_conf.disabled is zero. This is a likely indication of an error. I have left the files for you to examine and correct" };
	};

	$self->restart($vals);

	# chmod 0 the HTML directory
	if ($vals->{'documentroot'} && -d $vals->{'documentroot'} ) {
		my $chmod = $utility->find_the_bin("chmod");
		$utility->syscmd("$sudo $chmod 0 $vals->{'documentroot'}") 
	};

	print "returning success or error\n" if $vals->{'debug'};
	return { error_code => 200, error_desc => "vhost disabled successfully" };
};

=head2 vhost_delete

Delete's an Apache vhost.

    $apache->vhost_delete();

=cut

sub vhost_delete($$)
{
	my ($self, $vals, $conf) = @_;

	unless ( $self->vhost_exists($vals, $conf) ) {
		return { error_code=>400, error_desc=>"Sorry, that virtual host does not exist." };
	};

	print "deleting vhost " . $vals->{'vhost'} . "\n";

	# this isn't going to be pretty.
	# basically, we need to parse through the config file, find the right vhost container, and then remove only that vhost
	# I'll do that by setting a counter that trips every time I enter a vhost and counts the lines (so if the servername declaration is on the 5th or 1st line, I'll still know where to nip the first line containing the virtualhost opening declaration)
	# 

	my ($vhosts_conf) = $self->vhosts_get_file ($vals, $conf);
	my ($new, $drop)  = $self->vhosts_get_match($vals, $conf);

	print "Dropping: \n" . join ("\n", @$drop) . "\n";

	if ( length @$new == 0 || length @$drop == 0 ) {
		return { error_code => 500, error_desc => "yikes, something went horribly wrong!" };
	};

	# now, just for fun, lets make sure things work out OK
	# we'll write out @new and @drop and compare them to make sure
	# the two total the same size as the original

	$utility->file_write("$vhosts_conf.new", @$new);
	$utility->file_write("$vhosts_conf.drop", @$drop);

	if ( ( (-s "$vhosts_conf.new") + (-s "$vhosts_conf.drop") ) == -s $vhosts_conf ) {
		print "Yay, success!\n";
		use File::Copy;
		move("$vhosts_conf.new", $vhosts_conf);
		unlink("$vhosts_conf.drop");
	} else {
		return { error_code => 500, error_desc => "Oops, the size of $vhosts_conf.new and $vhosts_conf.drop combined is not the same as $vhosts_conf. This is a likely indication of an error. I have left the files for you to examine and correct" };
	};

	$self->restart($vals);

	print "returning success or error\n" if $vals->{'debug'};
	return { error_code=>200, error_desc=>"vhost deletion successful" };
};

=head2 vhost_exists

Tests to see if a vhost definition already exists in your Apache config file(s).

=cut


sub vhost_exists
{
	my ($self, $vals, $conf) = @_;

	my $vhost       = lc($vals->{'vhost'});
	my $vhosts_conf = $conf->{'apache_dir_vhosts'};

	unless ( $vhosts_conf ) { croak "FATAL: you must set apache_dir_vhosts in sysadmin.conf\n"; };

	if ( -d $vhosts_conf ) 
	{
		# test to see if the vhosts exists
		# this almost implies some sort of unique naming mechanism for vhosts
		# For now, this requires that the file be the same as the domain name 
		# (example.com) for the domain AND any subdomains. This means subdomain
		# declarations live within the domain file.

		my ($vh_file_name) = $vhost =~ /([a-z0-9-]+\.[a-z0-9-]+)(\.)?$/;
		print "cleaned up vhost name: $vh_file_name\n" if $vals->{'debug'};

		print "searching for vhost $vhost in $vh_file_name\n" if $vals->{'debug'};
		my $vh_file_path   = "$vhosts_conf/$vh_file_name.conf";

		unless ( -f $vh_file_path ) {
			# file does not exist, return invalid
			return 0;
		};

		# OK, so the file exists that the virtual host should be in. Now we need
		# to determine if there our virtual is defined in it

		$perl->module_load( {module=>"Apache::ConfigFile", ports_name=>"p5-Apache-ConfigFile", ports_group=>"www"} );
		my $ac = Apache::ConfigFile->read(file => $vh_file_path, ignore_case => 1);

		for my $vh ($ac->cmd_context(VirtualHost => '*:80')) 
		{
			my $server_name = $vh->directive('ServerName');
			print "ServerName $server_name\n" if $vals->{'debug'};
			return 1 if ( $vhost eq $server_name);

			my $alias = 0;
			foreach my $server_alias ($vh->directive('ServerAlias')) {
				return 1 if ( $vhost eq $server_alias);
				if ($vals->{'debug'}) {
					print "\tServerAlias  " unless $alias;
					print "$server_alias ";
				};
				$alias++;
			};
			print "\n" if ($alias && $vals->{'debug'});
		}
		return 0;
	} 
	else 
	{
		print "parsing vhosts from file $vhosts_conf\n";
	
		$perl->module_load( {module=>"Apache::ConfigFile", ports_name=>"p5-Apache-ConfigFile", ports_group=>"www"} );
		my $ac = Apache::ConfigFile->read(file => $vhosts_conf, ignore_case => 1);

		for my $vh ($ac->cmd_context(VirtualHost => '*:80')) 
		{
			my $server_name = $vh->directive('ServerName');
			print "ServerName $server_name\n" if $vals->{'debug'};
			return 1 if ( $vhost eq $server_name);

			my $alias = 0;
			foreach my $server_alias ($vh->directive('ServerAlias')) {
				return 1 if ( $vhost eq $server_alias);
				if ($vals->{'debug'}) {
					print "\tServerAlias  " unless $alias;
					print "$server_alias ";
				};
				$alias++;
			};
			print "\n" if ($alias && $vals->{'debug'});
		};

		return 0;
	};
};


=head2 vhost_show

Shows the contents of a virtualhost block that matches the virtual domain name passed in the $vals hashref. 

	$apache->vhost_show($vals, $conf);

=cut

sub vhost_show($$)
{
	my ($self, $vals, $conf) = @_;

	unless ( $self->vhost_exists($vals, $conf) ) {
		return { error_code => 400, error_desc=>"Sorry, that virtual host does not exist."};
	};

	my ($vhosts_conf) = $self->vhosts_get_file($vals, $conf);

	(my $new, my $match, $vals)  = $self->vhosts_get_match($vals, $conf);
	print "showing: \n" . join ("\n", @$match) . "\n";

	return { error_code=>100, error_desc=>"exiting normally" };
};


=head2 vhosts_get_file

If vhosts are each in their own file, this determines the file name the vhost will live in and returns it. The general methods on my systems works like this:

   example.com would be stored in $apache/vhosts/example.com.conf

so would any subdomains of example.com.

thus, a return value for *.example.com will be "$apache/vhosts/example.com.conf".

$apache is looked up from the contents of $conf.

=cut

sub vhosts_get_file
{
	my ($self, $vals, $conf) = @_;

	# determine the path to the file the vhost is stored in
	my $vhosts_conf = $conf->{'apache_dir_vhosts'};
	if ( -d $vhosts_conf ) {
		my ($vh_file_name) = lc($vals->{'vhost'}) =~ /([a-z0-9-]+\.[a-z0-9-]+)(\.)?$/;
		$vhosts_conf .= "/$vh_file_name.conf";
	} else {
		$vhosts_conf .= ".conf";
	};
	
	return $vhosts_conf;
};

=head2 vhosts_get_match

Find a vhost declaration block in the Apache config file(s).

=cut

sub vhosts_get_match
{
	my ($self, $vals, $conf) = @_;

	my ($vhosts_conf) = $self->vhosts_get_file ($vals, $conf);
	if ($vals->{'disabled'}) { $vhosts_conf .= ".disabled" };

	print "reading in the vhosts file $vhosts_conf\n" if $vals->{'debug'};
	my @lines = $utility->file_read($vhosts_conf);

	my ($in, $match, @new, @drop);
	LINE: foreach my $line (@lines) 
	{
		if ( $match ) 
		{
			print "match: $line\n" if $vals->{'debug'};
			push @drop, $line;
			if ( $line =~ /documentroot[\s+]["]?(.*?)["]?[\s+]?$/i ) {
				print "setting documentroot to $1\n" if $vals->{'debug'};
				$vals->{'documentroot'} = $1; 
			};
		}
		else { push @new, $line }; 

		if ( $line =~ /^[\s+]?<\/virtualhost/i ) {
			$in = 0; 
			$match = 0; 
			next LINE;
		};

		$in++ if $in;

		if ( $line=~/^[\s+]?<virtualhost/i ) {
			$in=1; next LINE;
		};

		my ($servername) = $line =~ /([a-z0-9-\.]+)(:\d+)?(\s+)?$/i;
		if ($servername && $servername eq lc($vals->{'vhost'}) ) 
		{
			$match = 1;

			# determine how many lines are in @new
			my $length = @new;
			print "array length: $length\n" if $vals->{'debug'};

			# grab the lines from @new going back to the <virtualhost> declaration
			# and push them onto @drop
			for ( my $i = $in; $i > 0;   $i-- )
			{
				push @drop, @new[($length-$i)]; 
				unless ( $vals->{'documentroot'}) {
					if ( @new[($length-$i)] =~ /documentroot[\s+]["]?(.*?)["]?[\s+]?$/i ) {
						print "setting documentroot to $1\n" if $vals->{'debug'};
						$vals->{'documentroot'} = $1; 
					};
				};
			};
			# remove those lines from @new
			for ( my $i = 0;   $i < $in; $i++ ) { pop @new; };
		};
	};

	return \@new, \@drop, $vals;
};


=head2 conf_patch

	use Mail::Toaster::Apache;
	my $apache = Mail::Toaster::Apache->new();

	$apache->conf_patch($conf);

Patch apache's default httpd.conf file. See the patch in contrib of Mail::Toaster to see what changes are being made.

=cut

sub conf_patch(;$)
{
	my ($self, $conf) = @_;

	my $prefix = "/usr/local/etc/apache2";

	if ($conf->{'install_apache'} == 1 && $os eq "freebsd" ) { $prefix = "/usr/local/etc/apache" };
	if ($conf->{'install_apache'} == 2 && $os eq "darwin"  ) { $prefix = "/etc/httpd"; };

	(-d $prefix) ? chdir($prefix) : croak "$prefix doesn't exist!\n";

	unless ( -e "$prefix/httpd.conf-2.0.patch")
	{
		print "conf_patch FAILURE: patch not found!\n";
		return 1;
	};

	my $httpd = "$prefix/httpd.conf";

	if ( -e "$prefix/httpd.conf.orig" ) {
		print "NOTICE: skipping. It appears the patch is already applied!\n";
		return 0;
	};

	if ( -e $httpd )
	{
		if ( $utility->syscmd("patch $httpd $prefix/httpd.conf-2.0.patch") )
		{
			print "NOTICE: patch apply failed!\n";
			return 1;
		} else  {
			print "NOTICE: patch apply success!\n";
			return 0;
		};
	} 
	else 
	{
		print "FAILURE: I couldn't find your httpd.conf!\n";
		return 1;
	};
	return 0;
};

sub RemoveOldApacheSources
{
	my ($apache) = @_;

	my @list = <apache_1.*>;
	foreach my $dir (@list)
	{
		if ( $dir && $dir ne $apache && $dir !~ /\.tar\.gz$/ )
		{
			print "deleting: $dir... ";
			rmtree $dir or croak "couldn't delete $dir: $!\n";    
			print "done.";
		};       
	};
};


sub OpenSSLConfigNote
{
	print "ATTENTION! ATTENTION!

If you don't like the default values being offered to you, or you 
get tired of typing them in every time you mess with an SSL cert, 
edit your openssl.cnf file. On most platforms, it lives in 
/etc/ssl/openssl.cnf.\n\n";

	sleep 5;
};


=head2 InstallDSACert

Builds and installs a DSA Certificate.

=cut

sub InstallDSACert
{
	my ($crtdir, $keydir) = @_;

	chdir("/usr/local/etc/apache2");

	my $crt    = "server-dsa.crt";
	my $key    = "server-dsa.key";
	my $csr    = "server-dsa.csr";

	#$utility->syscmd("openssl gendsa 1024 > $keydir/$key");
	#$utility->syscmd("openssl req -new -key $keydir/$key -out $crtdir/$csr");
	#$utility->syscmd("openssl req -x509 -days 999 -key $keydir/$key -in $crtdir/$csr -out $crtdir/$crt");

#	use Mail::Toaster::Perl;
#	$perl->module_load( {module=>"Crypt::OpenSSL::DSA", ports_name=>"p5-Crypt-OpenSSL-DSA", ports_group=>"security"} );
#	require Crypt::OpenSSL::DSA;
#	my $dsa = Crypt::OpenSSL::DSA->generate_parameters( 1024 );
#	$dsa->generate_key;
#	unless ( -e "$crtdir/$crt" ) { $dsa->write_pub_key(  "$crtdir/$crt" ); };
#	unless ( -e "$keydir/$key" ) { $dsa->write_priv_key( "$keydir/$key" ); };
};


=head2 InstallRSACert

Builds and installs a RSA certificate.

	use Mail::Toaster::Apache;
	InstallRSACert($crtdir, $keydir);

=cut

sub InstallRSACert
{
	my ($crtdir, $keydir) = @_;

	chdir("/usr/local/etc/apache2");

	my $csr    = "server.csr";
	my $crt    = "server.crt";
	my $key    = "server.key";

	$utility->syscmd("openssl genrsa 1024 > $keydir/$key");
	$utility->syscmd("openssl req -new -key $keydir/$key -out $crtdir/$csr");
	$utility->syscmd("openssl req -x509 -days 999 -key $keydir/$key -in $crtdir/$csr -out $crtdir/$crt");
};

1;
__END__


=head2 DEPENDENCIES

Mail::Toaster - http://www.tnpi.biz/internet/mail/toaster/

=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>


=head1 BUGS

None known. Report any to author.


=head1 TODO

Don't export any of the symbols by default. Move all symbols to EXPORT_OK and explicitely pull in the required ones in programs that need them.


=head1 SEE ALSO

The following are all man/perldoc pages: 

 Mail::Toaster 
 Mail::Toaster::Apache 
 Mail::Toaster::CGI  
 Mail::Toaster::DNS 
 Mail::Toaster::Darwin
 Mail::Toaster::Ezmlm
 Mail::Toaster::FreeBSD
 Mail::Toaster::Logs 
 Mail::Toaster::Mysql
 Mail::Toaster::Passwd
 Mail::Toaster::Perl
 Mail::Toaster::Provision
 Mail::Toaster::Qmail
 Mail::Toaster::Setup
 Mail::Toaster::Utility

 Mail::Toaster::Conf
 toaster.conf
 toaster-watcher.conf

 http://matt.simerson.net/computing/mail/toaster/
 http://matt.simerson.net/computing/mail/toaster/docs/

=head1 COPYRIGHT

Copyright (c) 2003-2005, The Network People, Inc. All Rights Reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut


