#!/usr/bin/perl
use strict;

#
# $Id: FreeBSD.pm,v 4.1 2004/11/16 21:20:01 matt Exp $
#

package Mail::Toaster::FreeBSD;

use Carp;
use vars qw($VERSION $utility $perl);
$VERSION = '4.00';

use lib "lib";
use lib "../..";
require Mail::Toaster::Utility; $utility = new Mail::Toaster::Utility;

eval { require Mail::Toaster::Perl };
unless ($@) { $perl = new Mail::Toaster::Perl; };

=head1 NAME

Mail::Toaster::FreeBSD

=head1 SYNOPSIS

FreeBSD scripting functions

=head1 DESCRIPTION

a group of frequently used functions for perl scripts running on FreeBSD systems.

Usage examples for each subroutine are included.

=head1 METHODS

=head2 new

	use Mail::Toaster::FreeBSD;
	my $fbsd = Mail::Toaster::FreeBSD->new;

=cut

sub new
{
	my ($class, $name) = @_;
	my $self = { name => $name };
	bless ($self, $class);
	return $self;
};

=head2 jail_delete

Delete a jail.

  $freebsd->jail_delete( {ip=>'10.0.1.160'} );

This script unmounts the proc and dev filesystems and then nukes the jail directory.

It would be a good idea to shut down any processes in the jail first.

=cut

sub jail_delete($)
{
	my ($self, $vals) = @_;

	my $ip       = $vals->{'ip'};
	   $ip     ||= $utility->answer("IP address", "10.0.1.160");
	my $debug    = $vals->{'debug'};
	my $dir      = $vals->{'jail_home'};
	   $dir    ||= $utility->answer("jail root directory", "/mnt/usr/jails");

	unless ( -d "$dir/$ip" ) { croak "The jail dir $dir/$ip doesn't exist!\n" };

	my $jexec = $utility->find_the_bin("jexec");
	if ( -x $jexec ) {
		my $jls = $utility->find_the_bin("jls");
		$utility->syscmd("jls");

		my $ans = $utility->answer("\nWhich jail do you want to delete?", undef, 60);
		if ( $ans > 0 ) {
			$utility->syscmd("$jexec $ans kill -TERM -1");
		};
	};

	my $mounts = $utility->drives_get_mounted($debug);

	if ( $mounts->{"$dir/$ip/dev"} ) 
	{
		print "unmounting $dir/ip/dev\n";
		$utility->syscmd("umount $dir/$ip/dev");
	};

	if ( $mounts->{"$dir/$ip/proc"} ) 
	{
		print "unmounting $dir/ip/proc\n";
		$utility->syscmd("umount $dir/$ip/proc");
	};

	$mounts = $utility->drives_get_mounted($debug);

	if ( $mounts->{"$dir/$ip/dev"} ) 
	{
		print "NOTICE: force unmounting $dir/ip/dev\n";
		$utility->syscmd("umount -f $dir/$ip/dev");
	};

	if ( $mounts->{"$dir/$ip/proc"} ) 
	{
		print "NOTICE: force unmounting $dir/ip/proc\n";
		$utility->syscmd("umount -f $dir/$ip/proc");
	};

	print "nuking jail: $dir/$ip\n";
	my $rm      = $utility->find_the_bin("rm");
	my $chflags = $utility->find_the_bin("chflags");

	$utility->syscmd("$rm -rf $dir/$ip");
	$utility->syscmd("$chflags -R noschg $dir/$ip");
	$utility->syscmd("$rm -rf $dir/$ip");
};


=head2 jail_start

Starts up a FreeBSD jail.

	$fbsd->jail_start($input);

$input is a hashref as follows:

    input = { 
        ip        => 10.0.1.1,
        hostname  => jail36.example.com,
        jail_home => /home/jail,
        debug     => 1
    };

hostname is optional, If not passed and reverse DNS is set up, it will
looked up. Otherwise, the hostname defaults to "jail".

jail_home is optional, it defaults to "/home/jail".

Here's an example of how I use it:

    perl -e 'use Mail::Toaster::FreeBSD; 
      my $fbsd = new Mail::Toaster::FreeBSD; 
      $fbsd->jail_start( {ip=>"10.0.1.175"})';

=cut

sub jail_start($)
{
	my ($self, $vals) = @_;

	my $ip       = $vals->{'ip'};
	   $ip     ||= $utility->answer("IP address", "10.0.1.160");
	my $hostname = $vals->{'hostname'};
	my $debug    = $vals->{'debug'};
	my $dir      = $vals->{'jail_home'};
	   $dir    ||= $utility->answer("jail root directory", "/mnt/usr/jails");

	unless ( $hostname )
	{
		$perl->module_load( {module=>"Net::DNS", ports_name=>"p5-Net-DNS", ports_group=>"dns"} );

    	my $r     = Net::DNS::Resolver->new;
		my $query = $r->query( $ip, "PTR");

		if ( $query )
    	{
			foreach my $rr ( $query->answer )
			{
				next unless ($rr->type eq "PTR");
				$hostname = $rr->rdatastr;
				print "hostname: " . $rr->rdatastr . " \n";
			};
			if ($hostname =~ /.*\./) 
			{
				($hostname) = $hostname =~ /(.*)\./;
			};
		}
		else
		{
			carp "ns query failed for : ", $r->errorstring if $debug;
			$hostname = "jail";
		};
	};

	print "hostname: $hostname\n";

	$utility->chdir_source_dir("/usr/src");
	unless ( -d "$dir/$ip" ) { croak "The jail dir $dir/$ip doesn't exist!\n" };

	my $mounts = $utility->drives_get_mounted($debug);

	unless ( $mounts->{"$dir/$ip/dev"} ) 
	{
		print "mounting $dir/ip/dev\n";
		$utility->syscmd("mount_devfs devfs $dir/$ip/dev");
	};

	unless ( $mounts->{"$dir/$ip/proc"} ) 
	{
		print "mounting $dir/ip/proc\n";
		$utility->syscmd("mount -t procfs proc $dir/$ip/proc");
	};

	print "starting jail: jail $dir/$ip $hostname $ip /bin/tcsh\n";
	$utility->syscmd("jail $dir/$ip $hostname $ip /bin/tcsh");
};

sub rc_dot_conf_check($$)
{

=head2 rc_dot_conf_check

    $fbsd->rc_dot_conf_check("snmpd_enable", "snmpd_enable=\"YES\"");

The above example is for snmpd. This checks to verify that an snmpd_enable line exists in /etc/rc.conf. If it doesn't, then it will add it by appending the second argument to the file.

=cut

	my ($self, $check, $line) = @_;

	my $file = "/etc/rc.conf";

	return 1 if `grep $check $file | grep -v grep`;

	$utility->file_append($file, [$line]);

	return 1 if `grep $check $file | grep -v grep`;

	print "rc.conf_check: FAILED to add $line to $file: $!\n";
	print "\n\nNOTICE: It would be a good idea for you to manually add $line to $file.\n\n";
	return 0;
};

sub jail_create($;$$)
{

=head2 jail_create

    $fbsd->jail_create($input);

$input is a hashref as follows:

    input = { 
        ip        => 10.0.1.1,
        hostname  => jail36.example.com,
        jail_home => /home/jail,
        debug     => 1
    };

hostname is optional, If not passed and reverse DNS is set up, it will
looked up. Otherwise, the hostname defaults to "jail".

jail_home is optional, it defaults to "/home/jail".

Here's an example of how I use it:

    ifconfig fxp0 inet alias 10.0.1.175/32

    perl -e 'use Mail::Toaster::FreeBSD;  
         my $fbsd = new Mail::Toaster::FreeBSD; 
         $fbsd->jail_create( {ip=>"10.0.1.175"} )';

After running $bsd->jail_create, you need to set up the jail. 
At the very least, you need to:

    1. set root password
    2. create a user account
    3. get remote root 
        a) use sudo (pkg_add -r sudo; visudo)
        b) add user to wheel group (vi /etc/group)
        c) modify /etc/ssh/sshd_config to permit root login
    4. install perl (pkg_add -r perl)

Here's how I set up my jails:

    pw useradd -n matt -d /home/matt -s /bin/tcsh -m -h 0
    passwd root
    pkg_add -r sudo rsync
    rehash; visudo
    pkg_add -r perl5.8
    sh /etc/rc

Ssh into the jail from another terminal. Once successfully 
logged in with root privs, you can drop the initial shell 
and access the jail directly.

Read the jail man pages for more details. Read the perl code
to see what else it does.

=cut

	my ($self, $vals) = @_;

	my $ip       = $vals->{'ip'};
	   $ip     ||= $utility->answer("IP address", "10.0.1.160");
	my $hostname = $vals->{'hostname'};
	my $debug    = $vals->{'debug'};
	my $dir      = $vals->{'jail_home'};
	   $dir    ||= $utility->answer("jail root directory", "/mnt/usr/jails");

	unless ( $hostname )
	{
		$perl->module_load( {module=>"Net::DNS", ports_name=>"p5-Net-DNS", ports_group=>"dns"} );

    	my $r     = Net::DNS::Resolver->new;
		my $query = $r->query( $ip, "PTR");

		if ( $query )
    	{
			foreach my $rr ( $query->answer )
			{
				next unless ($rr->type eq "PTR");
				$hostname = $rr->rdatastr;
				print "hostname: " . $rr->rdatastr . " \n";
			};

			if ($hostname =~ /.*\./) 
			{
				($hostname) = $hostname =~ /(.*)\./;
			};
		}
		else
		{
			carp "ns query failed for : ", $r->errorstring if $debug;
			$hostname = "jail";
		};
	};

	# there's probably a better way to reliably do this
	unless ( `ifconfig | grep $ip` ) { 
		croak "Hey! That IP isn't available on any network interface!\n"; };

	unless ( -d "$dir/$ip" ) { $utility->syscmd("mkdir -p $dir/$ip"); };
	chdir("/usr/src");

	if ( $utility->yes_or_no("Do you have a fresh world built?") ) 
	{
		$utility->syscmd("make installworld DESTDIR=$dir/$ip");
	} else {
		print "In order to build a jail, you need a fresh world built. That typically means using cvsup to fetch the latest sources from the FreeBSD tree of your choice (I recommend -stable) and then building the world. You can find the instructions for doing this on www.FreeBSD.org. If you already have the FreeBSD source files on your system, you can achieve the desired result by issuing the following command: 

   make -DNOCLEAN world DESTDIR=$dir/$ip
\n";

		if ( $utility->yes_or_no("Would you like me to do so now?") ) {
			$utility->syscmd("make -DNOCLEAN world DESTDIR=$dir/$ip");
		} 
		else { print "Sorry, I cannot continue.\n"; croak; };
	};

	chdir("etc");
	$utility->syscmd("make distribution DESTDIR=$dir/$ip");
	$utility->syscmd("mount_devfs devfs $dir/$ip/dev");
	chdir("$dir/$ip");
	symlink("dev/null", "kernel");

	mkdir(0755, "$dir/$ip/stand");
	$utility->syscmd("cp /stand/sysinstall $dir/$ip/stand");

	$utility->file_write("$dir/$ip/etc/fstab", "");

	my @lines = 'rpcbind_enable="NO"';
	push @lines, 'network_interfaces=""';
	push @lines, 'sshd_enable="YES"';
	push @lines, 'sendmail_enable="NONE"';
	push @lines, 'inetd_enable="YES"';
	push @lines, 'inetd_flags="-wW -a ' . $ip . '"';
	$utility->file_write("$dir/$ip/etc/rc.conf", @lines);

	$utility->syscmd("cp /etc/localtime $dir/$ip/etc/localtime");
	$utility->syscmd("cp /etc/resolv.conf $dir/$ip/etc/resolv.conf");
	$utility->file_append("$dir/$ip/etc/hosts", ["$ip $hostname"]);
	$utility->syscmd("cp /root/.cshrc $dir/$ip/root/.cshrc");
	$utility->syscmd("cp /etc/ssl/openssl.cnf $dir/$ip/etc/ssl/openssl.cnf");

	@lines = $utility->file_read("$dir/$ip/etc/ssh/sshd_config");
	foreach my $line (@lines) {
		if ( $line =~ /#ListenAddress 0.0.0.0/ ) {
			$line = "ListenAddress $ip";
		};
	};
	$utility->file_write("$dir/$ip/etc/ssh/sshd_config", @lines);

	$utility->syscmd("mount -t procfs proc $dir/$ip/proc");

	if ( $utility->yes_or_no("Would you like ports installed?", 300) ) 
	{
		my $rsyncbin = $utility->find_the_bin("rsync");
		unless ($rsyncbin) {
			$self->package_install("rsync");
			$rsyncbin = $utility->find_the_bin("rsync");
		};

		my $limit = $utility->yes_or_no("\n\nTo speed up the process, we can limit the ports copy to just those required by Mail::Toaster. Shall I limit the ports tree to only what is required?", 60);

		print "Please be patient, this will take a few minutes (depending on the speed of your disk(s)). \n";

		unless ( -d "$dir/$ip/usr/ports") { mkdir(0755, "$dir/$ip/usr/ports") };

		if ($limit) {
			foreach ( $utility->get_dir_files("/usr/ports") ) 
			{
				next if /arabic$/;
				next if /astro$/;
				next if /audio$/;
				next if /biology$/;
				next if /cad$/;
				next if /chinese$/;
				next if /distfiles$/;
				next if /finance$/;
				next if /french$/;
				next if /german$/;
				next if /hebrew$/;
				next if /irc$/;
				next if /japanese$/;
				next if /korean$/;
				next if /palm$/;
				next if /picobsd$/;
				next if /portuguese$/;
				next if /polish$/;
				next if /russian$/;
				next if /science$/;
				next if /hungarian$/;
				next if /ukrainian$/;
				next if /vietnamese$/;
				print "rsync -aW $_ $dir/$ip/usr/ports/ \n";
				$utility->syscmd("rsync -aW $_ $dir/$ip/usr/ports/");
			}
		} 
		else {
			foreach ( $utility->get_dir_files("/usr/ports") ) 
			{
				print "rsync -aW $_ $dir/$ip/usr/ports/ \n";
				$utility->syscmd("rsync -aW $_ $dir/$ip/usr/ports/");
			}
		}
	};

	print "You now need to set up the jail. At the very least, you need to:

	1. set root password
	2. create a user account
	3. get remote root 
		a) use sudo (pkg_add -r sudo; visudo)
		b) add user to wheel group (vi /etc/group)
		c) modify /etc/ssh/sshd_config to permit root login
	4. install perl (pkg_add -r perl5.8)

Here's how I set up my jail:

    pw useradd -n matt -d /home/matt -s /bin/tcsh -m -h 0
    passwd root
    pkg_add -r sudo rsync
    rehash; visudo
    pkg_add -r perl5.8
    sh /etc/rc

Ssh into the jail from another terminal. Once successfully logged in with root privs, you can drop the initial shell and manage the jail remotely.

Read the jail man pages for more details.\n\n";

	if ( $utility->yes_or_no("Do you want to start a shell in the jail?", 300) ) 
	{
		print "starting: jail $dir/$ip $hostname $ip /bin/tcsh\n";
		$utility->syscmd("jail $dir/$ip $hostname $ip /bin/tcsh");
	} 
	else 
	{
		print "to run:\n\n\tjail $dir/$ip $hostname $ip /bin/tcsh\n\n";
	};
};


=head2 source_update

Updates the FreeBSD sources (/usr/src/*) in preparation for building a fresh FreeBSD world.

    $fbsd->source_update($conf);

$conf is a hashref. Optional settings to be passed are:

  $conf = {
      cvsup_server_preferred => 'fastest',
      cvsup_server_country   => 'us',
      toaster_dl_site        => 'http://www.tnpi.biz',
      toaster_dl_url         => '/internet/mail/toaster/',
      cvsup_supfile_sources  => '/etc/cvsup-stable',
   };

See the docs for toaster-watcher.conf for complete details.

=cut

sub source_update($)
{
	my ($self, $conf) = @_;

	my $cvshost = $conf->{'cvsup_server_preferred'};   $cvshost ||= "fastest";
	my $cc      = $conf->{'cvsup_server_country'};
	my $toaster = $conf->{'toaster_dl_site'} . $conf->{'toaster_dl_url'};
	$toaster  ||= "http://www.tnpi.biz/internet/mail/toaster";

	print "\n\nsource_update: Getting ready to update your sources!\n\n";

	my $cvsupbin = $utility->find_the_bin("cvsup");
	unless ( -x $cvsupbin ) 
	{
		print "source_update: cvsup isn't installed. I'll fix that.\n";
		if ( $conf->{'package_install_method'} eq "ports" && -d "/usr/ports/net/cvsup-without-gui" ) 
		{
			$self->port_install("cvsup-without-gui", "net");
		} else {
			$self->package_install("cvsup-without-gui");
		};
		$cvsupbin = $utility->find_the_bin("cvsup");
		unless ( -x $cvsupbin) { croak "Couldn't find or install cvsup!\n"; };
	};

	# some stupid ports think they require perl 5.6.1, this fools them
	# probably deprecated by now (11/07/2004) - mps
	unless ( -e "/usr/local/bin/perl5.6.1" ) {
		if ( -e "/usr/local/bin/perl" ) {
			print "source_update: adding a symlink for perl 5.6.1 so broken ports won't try installing it.\n";
			symlink("/usr/local/bin/perl", "/usr/local/bin/perl5.6.1");
		};
	};

	# some stupid ports think they require perl 5.6.1, this fools them
	# if we have 5.8.1-3 instead.
	# probably deprecated by now (11/07/2004) - mps
	unless ( -d "/usr/local/lib/perl5/site_per/5.6.1" ) {
		if ( -d "/usr/local/lib/perl5/site_perl/5.8.2" ) {
			print "source_update: creating symlinks in site_perl for perl 5.6.1 so broken ports won't try installing it.\n";
			symlink("/usr/local/lib/perl5/site_perl/5.8.2", "/usr/local/lib/perl5/site_per/5.6.1");
		};
		if ( -d "/usr/local/lib/perl5/site_perl/5.8.1" ) {
			symlink("/usr/local/lib/perl5/site_perl/5.8.1", "/usr/local/lib/perl5/site_per/5.6.1");
			print "source_update: creating symlinks in site_perl for perl 5.6.1 so broken ports won't try installing it.\n";
		};
		if ( -d "/usr/local/lib/perl5/site_perl/5.8.3" ) {
			symlink("/usr/local/lib/perl5/site_perl/5.8.3", "/usr/local/lib/perl5/site_per/5.6.1");
			print "source_update: creating symlinks in site_perl for perl 5.6.1 so broken ports won't try installing it.\n";
		};
	};

	my $supfile = $conf->{'cvsup_supfile_sources'};

	unless ( -e $supfile ) 
	{
		if    ( -e "/etc/cvsup-sources") { $supfile = "/etc/cvsup-sources"; }
		elsif ( -e "/etc/cvsup-stable" ) { $supfile = "/etc/cvsup-stable";  } 
		else  
		{ 
			$supfile = "/etc/cvsup-stable";
			$utility->get_file("$toaster/etc/cvsup-stable");
			move("cvsup-stable", $supfile);
		};
	};

	print "source_update: using $supfile\n";

	if ($cvshost eq "fastest" )
	{
		my $fastestbin = $utility->find_the_bin("fastest_cvsup");

		unless ( -x $fastestbin) 
		{
			if ( -d "/usr/ports/sysutils/fastest_cvsup" ) 
			{
				$self->port_install("fastest_cvsup", "sysutils");
				$fastestbin = $utility->find_the_bin("fastest_cvsup");
			} else {
				print "ERROR: fastest_cvsup port is not available (yet)\n";
			}
		}

		if (-x $fastestbin) 
		{
			$cc ||= $utility->answer("what's your two digit country code?");
			print "source_update: finding the fastest FreeBSD cvsup server... ";
			$cvshost = `$fastestbin -Q -c $cc`; chomp $cvshost;
			print $cvshost . "\n";
		} 
		else { print "ERROR: fastest_cvsup not installed or executable!\n" };
	}

	if ( $cvshost ) 
	{
		$utility->syscmd("$cvsupbin -g -h $cvshost $supfile");
	} else {
		$utility->syscmd("$cvsupbin -g $supfile");
	};

	print "\n\n
\tAt this point I recommend that you:

	a) read /usr/src/UPDATING
	b) make any kernel config options you need
	c)
		make buildworld
		make kernel
		reboot
		make installworld
		mergemaster
		reboot
\n";

};

sub ports_update(;$)
{

=head2 ports_update

Updates the FreeBSD ports tree (/usr/ports/*).

    $fbsd->ports_update($conf);

$conf is a hashref. Optional settings to be passed are:

   cvsup_server_preferred
   cvsup_server_country
   toaster_dl_site
   toaster_dl_url

See the docs for toaster-watcher.conf for complete details.

=cut

	my ($self, $conf) = @_;

	print "\n\nUpdatePorts: It's a good idea to keep your ports tree up to date.\n\n";

	unless ( $utility->yes_or_no( "\n\nWould you like me to do it for you?:") )
	{
		print "OK, skipping ports tree update\n";
		return 0;
	};

	my $cvshost = $conf->{'cvsup_server_preferred'};  $cvshost ||= "fastest";
	my $cc      = $conf->{'cvsup_server_country'};
	my $toaster = $conf->{'toaster_dl_site'} . $conf->{'toaster_dl_url'};
	$toaster  ||= "http://www.tnpi.biz/internet/mail/toaster";

	my $cvsupbin = $utility->find_the_bin("cvsup");

	unless ( $cvsupbin && -x $cvsupbin) 
	{
		$self->package_install("cvsup-without-gui");
		$cvsupbin = $utility->find_the_bin("cvsup");
	};

	my $supfile = $conf->{'cvsup_supfile_ports'}; $supfile ||= "/etc/cvsup-ports";

	unless ( -e $supfile )
	{
		$utility->get_file("$toaster/etc/cvsup-ports");
		move("cvsup-ports", $supfile);
	};

	if ($cvshost eq "fastest" )
	{
		my $fastestbin = $utility->find_the_bin("fastest_cvsup");

		unless ( $fastestbin) 
		{
			if ( -d "/usr/ports/sysutils/fastest_cvsup" ) 
			{
				$self->port_install("fastest_cvsup", "sysutils");
				$fastestbin = $utility->find_the_bin("fastest_cvsup");
			};
		};

		if ($fastestbin) 
		{
			$cc ||= $utility->answer("what's your two digit country code?");
			$cvshost = `$fastestbin -Q -c $cc`; chomp $cvshost;
		} 
		else 
		{ 
			print "ERROR: fastest_cvsup port is not available (yet)\n";
			$cvshost = undef;
		};
	}

	if ( $cvshost ) 
	{
		$utility->syscmd("$cvsupbin -g -h $cvshost $supfile");
	} else {
		$utility->syscmd("$cvsupbin -g $supfile");
	};

	print "ports_update: according to the FreeBSD portsdb man page: \n\n
   considering that the INDEX file often gets outdated because it is updated only 
   once a week or so in the official ports tree, it is recommended that you run
   ``portsdb -Uu'' after every CVSup of the ports tree in order to keep them
   always up-to-date and in sync with the ports tree.\n";

	sleep 2;

	if( $utility->yes_or_no( "\n\nWould you like me to run portsdb -Uu", 60) )
	{
		my $portsdb = $utility->find_the_bin("portsdb");
		$utility->syscmd("$portsdb -Uu");
	};

	if ( $conf->{'install_portupgrade'} )
	{
		my $package = $conf->{'package_install_method'}; $package ||= "packages";

		if ( $package eq "ports" )
		{
			$self->port_install("ruby18", "lang", undef, "ruby-1.8");
			$self->port_install("ruby-gdbm", "databases", undef, "ruby18-gdbm");
		}
		else
		{
			unless ( $self->package_install("ruby18_static", "ruby-1.8") )
			{
				$self->port_install("ruby18", "lang", undef, "ruby-1.8");
				$self->port_install("ruby-gdbm", "databases", undef, "ruby18-gdbm");
			};
		};

		$self->port_install   ("portupgrade", "sysutils");
		print "\n\n
\tAt this point I recommend that you run pkgdb -F, and then 
\tportupgrade -ai, upgrading everything except XFree86 and 
\tother non-mail related items.\n\n
\tIf you have problems upgrading a particular port, then I recommend
\tremoving it (pkg_delete port_name-1.2) and then proceeding.\n\n
\tIf you upgrade perl (yikes), make sure to also rebuild all the perl
\tmodules you have installed. See the FAQ for details.\n\n";
	};
};


sub port_install($$;$$$$$)
{

=head2 port_install

    $fbsd->port_install("openldap2", "net");

That's it. Really. Well, OK, sometimes it can get a little more complex. port_install checks first to determine if a port is already installed and if so, skips right on by. It's very intelligent that way. However, sometimes port maintainers do goofy things and we need to override the directory directory we install from. A good example of this is currently openldap2. 

If you want to install OpenLDAP 2, then you can install from any of:

		/usr/ports/net/openldap2
		/usr/ports/net/openldap20
		/usr/ports/net/openldap21
		/usr/ports/net/openldap22

BTW: The second argument ("net") is what determines where in FreeBSD's ports tree the script can find OpenLDAP. If you pass along a third argument, we'll use it instead of the port name as the port directory to install from.

On rare occasion, a port will get installed as a name other than the ports name. Of course, that wreaks all sorts of havoc so when one of them nasties is found, you can optionally pass along a fourth parameter which can be used as the port installation name to check with.

On yet other occassions, you'll want to pass make flags to the port. The fifth argument can be a comma separated list of make arguments.

The sixth optional flag is whether errors should be fatal or not. Binary values.

And the seventh is debugging. Setting will increase the amount of logging.

So, a full complement of settings could look like:

  
    $fbsd->port_install("openldap2", "net", "openldap22", "openldap-2.2", "NOPORTDOCS", 0, 1);

=cut

	my $self = shift;
	my ($name, $base, $booger, $check, $flags, $fatal, $debug) = @_;
	my ($dir, $makef, @defs);

	# this will detect if you have a ports tree that hasn't been updated
	# since net-mgmt was split from net
	if ($base eq "net-mgmt" && ! -d "/usr/ports/net-mgmt") {
		$base = "net";
	};

	if ($booger) { $dir = "/usr/ports/$base/$booger" } 
	else         { $dir = "/usr/ports/$base/$name"   };

	$self->ports_check_age("30");

	if ($flags) 
	{
		@defs = split(/,/, $flags);
		foreach my $def ( @defs ) 
		{ 
			if ( $def =~ /=/ ) { $makef .= " $def "   } 
			else               { $makef .= " -D$def " };
		};
	};

	$check ||= $name;

	my $r = $self->is_port_installed($check);
	if ( $r )
	{
		printf "port_install: %-20s installed as (%s).\n", $name, $r;
		return 1;
	}
	else
	{
		print "port_install: installing $name...\n" if $debug;
		chdir($dir) or croak "couldn't cd to $dir: $!\n";
		if ( $name eq "qmail" ) 
		{
			$utility->syscmd( "make enable-qmail clean");
			if ( -e "/usr/local/etc/rc.d/qmail.sh" ) 
			{
				use File::Copy;
				move("/usr/local/etc/rc.d/qmail.sh", "/usr/local/etc/rc.d/qmail.sh-dist") or croak "$!";
			};
		} 
		elsif ( $name eq "ezmlm-idx" )
		{
			$utility->syscmd( "make $makef install");
			copy("work/ezmlm-0.53/ezmlmrc", "/usr/local/bin");
			$utility->syscmd( "make clean");
		} 
		elsif ( $name eq "sqwebmail" )
		{
			print "running: make $makef install";
			$utility->syscmd( "make $makef install");
			chdir("$dir/work");
			my @list = $utility->get_dir_files(".");
			chdir ($list[0]);
			$utility->syscmd( "make install-configure");
			chdir($dir);
			$utility->syscmd( "make clean");
		} 
		else 
		{
			print "running: make $makef install clean";
			$utility->syscmd( "make $makef install clean");
		};
		print "done.\n" if $debug;
	};

	$r = $self->is_port_installed($check);
	if ( $r )
	{
		printf "port_install: %-20s installed as (%s).\n", $name, $r;
		return 1;
	} 
	else 
	{
		printf "port_install: %-20s FAILED\n", $name;
		if ($fatal) 
		{
			croak "FATAL FAILURE: Install of $name failed. Please fix and try again.\n";
		} 
		else { return 0; };
	};
};

sub ports_check_age($;$)
{
	my ($self, $age, $url) = @_;

=head2 ports_check_age

Checks how long it's been since you've updated your ports tree. Since the ports tree can be a roaming target, by making sure it's current before installing ports we can increase the liklihood of success. 

	$fbsd->ports_check_age("20");

That'll update the ports tree if it's been more than 20 days since it was last updated.

You can optionally pass along a URL as the second argument from where to fetch the cvsup-ports file. If you have a custom one for your site, pass along the URL (minus the file name).

=cut

	$url ||= "http://www.tnpi.biz/internet/mail/toaster";

	if ( -M "/usr/ports" > $age ) { $self->ports_update; }
	else
	{
		print "ports_check_age: Ports file is current (enough).\n";
	};
};

sub package_install($;$$$)
{   

=head2 package_install

	$fbsd->package_install("ispell");

Suggested usage: 

	unless ( $fbsd->package_install("ispell") ) {
		$fbsd->port_install("ispell", "textproc");
	};

Installs the selected package from FreeBSD packages. If the first install fails, it'll try again using an alternate FTP site (ftp2.freebsd.org). If that fails, it returns 0 (failure) so you know it failed and can try something else, like installing via ports.

If the package is registered in FreeBSD's package registry as another name and you want to check against that name (so it doesn't try installing a package that's already installed), instead, pass it along as the second argument.

If you want to retrieve packages from a package site other than FreeBSD's (the default), then pass along that URL as the third argument. See the pkg_add man page for more details.

=cut

	my ($self, $package, $alt, $pkg_url, $debug) = @_;

	my $pkg_add  = $utility->find_the_bin("pkg_add");

	my $r = $self->is_port_installed($package, $alt);
	if ( $r )
	{
		printf "package_install: %-20s installed as (%s).\n", $package, $r;
		return $r;
	}
	else
	{
		print "package_install: installing $package....\n" if $debug;
		$ENV{"PACKAGESITE"} = $pkg_url if $pkg_url;

		my $r2 = $utility->syscmd("$pkg_add -r $package");

		if ($r2) { print "\t pkg_add failed\t "; } 
		else     { print "\t pkg_add success\t " if $debug };

		print "done.\n" if $debug;

		unless ( $self->is_port_installed($package, $alt) ) 
		{
			print "package_install: Failed #1, trying alternate package site.\n";
			$ENV{"PACKAGEROOT"} = "ftp://ftp2.freebsd.org";
			$utility->syscmd("$pkg_add -r $package");

			unless ( $self->is_port_installed($package, $alt) ) 
			{
				print "package_install: Failed #2, trying alternate package site.\n";
				$ENV{"PACKAGEROOT"} = "ftp://ftp3.freebsd.org";
				$utility->syscmd("$pkg_add -r $package");

				unless ( $self->is_port_installed($package, $alt) ) 
				{
					print "package_install: Failed #3, trying alternate package site.\n";
					$ENV{"PACKAGEROOT"} = "ftp://ftp4.freebsd.org";
					$utility->syscmd("$pkg_add -r $package");
				};
			};
		};

		unless ( $self->is_port_installed($package, $alt) ) 
		{
			carp "package_install: Failed again! Sorry, I can't install the package $package!\n";
			return 0;
		};

		return $r;
	};
};

=head2 is_port_installed

Checks to see if a port is installed. 

    $fbsd->is_port_installed("p5-CGI");

Input is two strings, first is the package name, second is an alternate package name. This is necessary as some ports evolve and register themselves differently in the ports database.

returns 1 if installed, 0 if not

=cut

sub is_port_installed
{
	my ($self, $package, $alt) = @_;
	my $r;  

	my $pkg_info = $utility->find_the_bin("pkg_info");
	my $grep     = $utility->find_the_bin("grep");

	if ( $alt )
	{
		$r   = `$pkg_info | cut -d" " -f1 | $grep "^$alt-"`;
		$r ||= `$pkg_info | cut -d" " -f1 | $grep "^$alt"`;
	} 
	else {
		$r   = `$pkg_info | cut -d" " -f1 | $grep "^$package-"`;
		$r ||= `$pkg_info | cut -d" " -f1 | $grep "^$package"`;
	};
	chomp $r;

	return $r;
};


1;
__END__


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>

=head1 BUGS

None known. Report any to author.

=head1 TODO

Needs more documentation.

=head1 SEE ALSO

Mail::Toaster, Mail::Toaster::FreeBSD

	http://www.tnpi.biz/computing/freebsd/
	http://www.tnpi.biz/internet/
	http://www.tnpi.biz/internet/mail/toaster


=head1 COPYRIGHT

Copyright 2003-2004, The Network People, Inc. All Rights Reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut


