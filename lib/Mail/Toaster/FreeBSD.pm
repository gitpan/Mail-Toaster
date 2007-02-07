#!/usr/bin/perl
use strict;
use warnings;

#
# $Id: FreeBSD.pm,v 4.18 2006/06/09 19:26:18 matt Exp $
#

package Mail::Toaster::FreeBSD;

use Cwd;
use Carp;
use Params::Validate qw( :all );;

use vars qw($VERSION $err);
$VERSION = '5.05';

use lib "lib";

require Mail::Toaster::Utility; my $utility = Mail::Toaster::Utility->new;
require Mail::Toaster::Perl;    my $perl    = Mail::Toaster::Perl->new;

1;

sub new {

    my ( $class, $name ) = @_;
    my $self = { name => $name };
    bless( $self, $class );
    return $self;
}

sub cvsup_select_host {

    my $self = shift;
    
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $fatal, $debug )
        = ( $p{'conf'}, $p{'fatal'}, $p{'debug'} );

    my $cvshost      = $conf->{'cvsup_server_preferred'} || "fastest";
    my $country_code = $conf->{'cvsup_server_country'}   || "us";

    print "cvsup_select_host: in country $country_code: $cvshost\n" if $debug;

    # if this is set, use it
    if ( $cvshost && $cvshost ne "fastest" ) { return $cvshost; }

    # host is set to "fastest"
    my $fastest = $utility->find_the_bin(
        bin   => "fastest_cvsup",
        debug => $debug,
        fatal => 0,
    );

    # are we testing?
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    # if fastest_cvsup is not installed, install it
    if ( ! $fastest || !-x $fastest ) {
        if ( -d "/usr/ports/sysutils/fastest_cvsup" ) {
            
            # we are probably here to update the ports tree, so we'll create
            # a loop if we try installing a port, which will send us right back
            # to here since fastest_cvsup is selected but not installed.
            # the no_update flag helps us circumvent that problem.
            
            $self->port_install(
                port  => "fastest_cvsup",
                base  => "sysutils",
                fatal => 0,
                debug => $debug,
                no_update => 1,
            );
            $fastest =
              $utility->find_the_bin( bin => "fastest_cvsup", fatal => 0,debug=>0 );
        }
        else {
            print "ERROR: fastest_cvsup port is not available to install from ports.\n";
        }
    }

    # if it installed correctly
    if ( !$fastest || !-x $fastest ) {
        print "ERROR: fastest_cvsup is selected but not available.\n";
        croak if $fatal;
        return;
    };

    $country_code ||=
      $utility->answer( q => "what's your two digit country code?" );
    $cvshost = `$fastest -Q -c $country_code`;
    chomp $cvshost;
    return $cvshost;
}

sub drive_spin_down {

    my $self = shift;
    
    my %p = validate( @_, {
            'drive'   => { type=>SCALAR, },
            'kind'    => { type=>SCALAR,  optional=>1, },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $drive, $kind, $fatal, $debug )
        = ( $p{'drive'}, $p{'kind'}, $p{'fatal'}, $p{'debug'} );
	
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    # try atacontrol if IDE disk.

    # first, see if the drive exists!

    my $camcontrol = $utility->find_the_bin( bin => "camcontrol",debug=>0 );
    if ( -x $camcontrol ) {
        print "spinning down backup drive $drive...";
        $utility->syscmd( command => "$camcontrol stop $drive",debug=>0 );
        print "done.\n";
        return 1;
    }
    else {
        print "couldn't find camcontrol!\n";
        return 0;
    }
}

sub get_version {
    my $self = shift;
    my $debug = shift;

    my $uname = $utility->find_the_bin(bin=>"uname",debug=>0);
    print "found uname: $uname\n" if $debug;

    my $version = `$uname -r`;
    chomp $version;
    print "version is $version\n" if $debug;

    return $version;
};

sub is_port_installed {

    my $self = shift;
    
    # parameter validation
    my %p = validate( @_, {
            'port'    => { type=>SCALAR, },
            'alt'     => { type=>SCALAR|UNDEF, optional=>1},
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $package, $alt, $fatal, $debug )
        = ( $p{'port'}, $p{'alt'}, $p{'fatal'}, $p{'debug'} );

    my ($r, @args );
    
    print "is_port_installed: checking for $package\n" if $debug;

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $pkg_info = $utility->find_the_bin( debug => $debug, bin => "pkg_info", fatal=>$fatal );
    my $grep     = $utility->find_the_bin( debug => $debug, bin => "grep", fatal=>$fatal );

    return unless ( $pkg_info && $grep);

    # pkg_info gets a list of packages
    # grep the string we're looking for
    # cut strips off everything after the first space
    # and head gives us only the first line of output

    if ($alt) {
        $r =   `$pkg_info | $grep "^$alt-" | cut -d" " -f1 | head -n1`;
        $r ||= `$pkg_info | $grep "^$alt"  | cut -d" " -f1 | head -n1`;
    }
    else {
        $r =   `$pkg_info | $grep "^$package-" | cut -d" " -f1 | head -n1`;
        $r ||= `$pkg_info | $grep "^$package"  | cut -d" " -f1 | head -n1`;
    }
    chomp $r;

    return $r;
}

sub install_cvsup {

    my $self = shift;
    
    my %p = validate( @_, {
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $fatal, $debug ) = ( $p{'fatal'}, $p{'debug'} );

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $cvsupbin = $utility->find_the_bin( bin => "cvsup", debug=>$debug, fatal=>0 );
    if ( $cvsupbin && -x $cvsupbin) {
        return $cvsupbin 
    };

    # try installing it via a package (source compile takes a long time)
    $self->package_install( port => "cvsup-without-gui", debug=>$debug, fatal=>0 );

    # check for it again
    $cvsupbin = $utility->find_the_bin( bin => "cvsup", debug=>$debug, fatal=>0 );
    return $cvsupbin if ( $cvsupbin && -x $cvsupbin );

    # since package install failed, try installing via the port
    $self->port_install( 
        port  => "cvsup-without-gui", 
        base  => "net", 
        debug => $debug, 
        fatal => $fatal,
        no_update=>1, 
    );

    $cvsupbin = $utility->find_the_bin( 
        bin => "cvsup", 
        debug=>$debug, 
        fatal=>$fatal,
    );

    if ( !$cvsupbin || !-x $cvsupbin ) {
        $err = "install_cvsup: failed to install";
        carp $err;
        croak $err if $fatal;
        return;
    }

    return $cvsupbin;
}

sub install_portupgrade {

    my $self = shift;
    
    my %p = validate( @_, {
            conf  => { type=>HASHREF, optional=>1, },
            fatal => { type=>BOOLEAN, optional=>1, default=>1 },
            debug => { type=>BOOLEAN, optional=>1, default=>1 },
            test_ok=>{ type=>BOOLEAN, optional=>1 },
        },
    );

    my ( $conf, $fatal, $debug )
        = ( $p{'conf'}, $p{'fatal'}, $p{'debug'} );

    my $package = $conf->{'package_install_method'} || "packages";

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    # if we're running FreeBSD 6, try installing the package as it will do the
    # right thing. On older systems we want to install a (much newer) version
    # of portupgrade from ports

    if ( $self->get_version =~ m/\A6/ ) {
        $self->package_install(
            port => "portupgrade",
            debug => 0,
            fatal => 0,
        );
    } 

    if ( $package eq "packages" ) {
        $self->package_install( 
            port  => "ruby18_static", 
            alt   => "ruby-1.8", 
            debug => 0,
            fatal => 0,
        );
    }

    $self->port_install(
        port => "portupgrade",
        base => -d "/usr/ports/ports-mgmt" ? "ports-mgmt" : "sysutils",
        debug => 0,
        fatal => $fatal,
    );

    $self->is_port_installed(port=>"portupgrade", fatal=>$fatal, debug=>0) ? return 1 : return;
}

sub jail_create {

    my $self = shift;
    
    my %p = validate( @_, {
            'ip'        => { type=>SCALAR,  optional=>1, default=>"10.0.1.160" },
            'hostname'  => { type=>SCALAR,  optional=>1, },
            'jail_home' => { type=>SCALAR,  optional=>1, },
            'fatal'     => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'     => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $ip, $hostname, $dir, $fatal, $debug )
        = ( $p{'ip'}, $p{'hostname'}, $p{'jail_home'}, $p{'fatal'}, $p{'debug'} );

    if ( ! $ip || $ip eq "10.0.1.160" ) {
        $ip = $utility->answer(
            question => "ip address",
            default => $ip,
        );
    };

    $hostname ||= $self->jail_get_hostname( ip=>$ip, debug=>$debug );

    $dir ||=  $utility->answer(
          question => "jail root directory",
          default => "/usr/jails"
      );
     
    my $ifconfig = $utility->find_the_bin( bin=>'ifconfig',debug=>0 );
    unless (`$ifconfig | grep $ip`) {    # there's probably a better way
        croak "Hey! That IP isn't available on any network interface!\n";
    }

    unless ( -d "$dir/$ip" ) {
        $utility->syscmd( command => "mkdir -p $dir/$ip",debug=>0 );
    }

    $self->jail_install_world( dir=>$dir, ip=>$ip );
    $self->jail_postinstall_setup(dir=>$dir, ip=>$ip, hostname=>$hostname);

    print "\a";
    if ( $utility->yes_or_no(
            question => "Would you like ports installed?",
            timeout  => 300,
        )
      )
    {
        $self->jail_install_ports(dir=>$dir, ip=>$ip);
    };


    print "\a";
    if ( $utility->yes_or_no(
            question => "Install Matt tweaks",
            timeout  => 300,
        )
      )
    {
        my $home = "/home/matt";

        if ( -d $home ) {
            $utility->syscmd(
                command => "rsync -aW --exclude html $home $dir/$ip/usr/home",
                debug=>0,
            );
        }
        if ( -f "/usr/local/etc/sudoers" ) {
            $utility->syscmd( command => "mkdir -p $dir/$ip/usr/local/etc",debug=>0 );
            $utility->syscmd( 
                command =>"rsync -aW /usr/local/etc/sudoers $dir/$ip/usr/local/etc/sudoers", 
                debug=>0,
            );
        }

        $utility->syscmd( 
            command => "jail $dir/$ip $hostname $ip /usr/sbin/pkg_add -r sudo rsync perl" , 
            debug=>0,
        );
    }

    print "You now need to set up the jail. At the very least, you need to:

	1. set root password
	2. create a user account
	3. get remote root 
		a) use sudo (pkg_add -r sudo; visudo)
		b) add user to wheel group (vi /etc/group)
		c) modify /etc/ssh/sshd_config to permit root login
	4. install perl (pkg_add -r perl/perl5.8)

Here's how I set up my jail:

    pw useradd -n matt -d /home/matt -s /bin/tcsh -u 1000 -m -h 0
    passwd root
    pkg_add -r sudo rsync perl
    rehash; visudo
    sh /etc/rc

Ssh into the jail from another terminal. Once successfully logged in with root privs, you can drop the initial shell and manage the jail remotely.

Read the jail man pages for more details.\n\n";

    if ( $utility->yes_or_no(
            question => "Do you want to start a shell in the jail?",
            timeout  => 300, )
      )
    {
        print "starting: jail $dir/$ip $hostname $ip /bin/tcsh\n";
        $utility->syscmd( command => "jail $dir/$ip $hostname $ip /bin/tcsh" , debug=>0);
    }
    else {
        print "to run:\n\n\tjail $dir/$ip $hostname $ip /bin/tcsh\n\n";
    }
}

sub jail_delete {

    my $self = shift;
    
    my %p = validate( @_, {
            'ip'        => { type=>SCALAR,  optional=>1, },
            'jail_home' => { type=>SCALAR,  optional=>1, },
            'fatal'     => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'     => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $ip, $jail_home, $fatal, $debug )
        = ( $p{'ip'}, $p{'jail_home'}, $p{'fatal'}, $p{'debug'} );

    $ip ||= $utility->answer( q => "IP address", default => "10.0.1.160" );


    $jail_home ||= $utility->answer(
        q       => "jail root directory",
        default => "/usr/jails"
    );

    unless ( -d "$jail_home/$ip" ) { croak "The jail dir $jail_home/$ip doesn't exist!\n" }

    if ( -e "$jail_home/$ip/etc/rc.shutdown" ) {
        $utility->syscmd( command => "$jail_home/$ip/etc/rc.shutdown" , debug=>0);
    }

    my $jexec = $utility->find_the_bin( bin => "jexec" );
    if ( -x $jexec ) {
        my $jls = $utility->find_the_bin( bin => "jls" );
        $utility->syscmd( command => "jls" , debug=>0);

        my $ans = $utility->answer(
            q       => "\nWhich jail do you want to delete?",
            timeout => 60
        );
        if ( $ans > 0 ) {
            $utility->syscmd( command => "$jexec $ans kill -TERM -1" , debug=>0);
        }
    }

    my $mounts = $utility->drives_get_mounted( debug => $debug );

    if ( $mounts->{"$jail_home/$ip/dev"} ) {
        print "unmounting $jail_home/ip/dev\n";
        $utility->syscmd( command => "umount $jail_home/$ip/dev" , debug=>0);
    }

    if ( $mounts->{"$jail_home/$ip/proc"} ) {
        print "unmounting $jail_home/ip/proc\n";
        $utility->syscmd( command => "umount $jail_home/$ip/proc" , debug=>0);
    }

    $mounts = $utility->drives_get_mounted( debug => $debug );

    if ( $mounts->{"$jail_home/$ip/dev"} ) {
        print "NOTICE: force unmounting $jail_home/ip/dev\n";
        $utility->syscmd( command => "umount -f $jail_home/$ip/dev" , debug=>0);
    }

    if ( $mounts->{"$jail_home/$ip/proc"} ) {
        print "NOTICE: force unmounting $jail_home/ip/proc\n";
        $utility->syscmd( command => "umount -f $jail_home/$ip/proc" , debug=>0);
    }

    print "nuking jail: $jail_home/$ip\n";
    my $rm      = $utility->find_the_bin( bin => "rm" );
    my $chflags = $utility->find_the_bin( bin => "chflags" );

    $utility->syscmd( command => "$rm -rf $jail_home/$ip" , debug=>0);
    $utility->syscmd( command => "$chflags -R noschg $jail_home/$ip" , debug=>0);
    $utility->syscmd( command => "$rm -rf $jail_home/$ip" , debug=>0);
}

sub jail_get_hostname {
    
    my $self = shift;
    
    my %p = validate( @_, {
            'ip'        => { type=>SCALAR,  },
            'fatal'     => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'     => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $ip, $fatal, $debug ) = ( $p{'ip'}, $p{'fatal'}, $p{'debug'} );

    require Mail::Toaster::DNS;
    my $dns = Mail::Toaster::DNS->new();

    my $hostname = $dns->resolve(record=>$ip, type=>"PTR", debug=>$debug);

    # if ( $hostname =~ /.*\./ ) {
    if ( ! $hostname ) {
        $hostname = "jail";
    }

    return $hostname;
}

sub jail_install_ports {

    my $self = shift;
    
    my %p = validate( @_, {
            'ip'        => { type=>SCALAR, },
            'dir'       => { type=>SCALAR, },
            'fatal'     => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'     => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $ip, $dir, $fatal, $debug )
        = ( $p{'ip'}, $p{'dir'}, $p{'fatal'}, $p{'debug'} );


    my $rsyncbin = $utility->find_the_bin( bin => "rsync", debug=>0 );
    unless ($rsyncbin) {
        unless ( $self->package_install( port => "rsync", debug=>0 ) ) {
            $self->port_install( port => "rsync", base=>"net", debug=>0 );
        };
        $rsyncbin = $utility->find_the_bin( bin => "rsync", debug=>0 );
    }
    unless ( -x $rsyncbin ) {
        croak "sorry, rsync could not be found or installed!\n";
    }

    my $limit = $utility->yes_or_no(
        question => "\n\nTo speed up the process, we can copy only the ports \n"
            . "required by Mail::Toaster. Shall I limit the ports tree?",
        timeout=> 60,
    );

    print "Please be patient, this will take a few minutes (depending \n"
        . "on the speed of your disk(s)). \n";

    unless ( -d "$dir/$ip/usr/ports" ) { mkdir "$dir/$ip/usr/ports", oct('0755'); }

    if ($limit) {
        my @skip_array = qw{ arabic astro audio biology cad chinese comms
            deskutils distfiles emulators finance french ftp german hebrew
            irc japanese korean mbone news palm picobsd portuguese polish
            russian science hungarian ukrainian vietnamese x11-clocks
            x11-themes x11-wm };
        my %skip_hash = map { $_ => 1 } @skip_array;

        foreach ( $utility->get_dir_files( dir => "/usr/ports" ) ) {
            next if defined $skip_hash{$_};

            print "rsync -aW $_ $dir/$ip/usr/ports/ \n";

            $utility->syscmd(
                command => "rsync -aW $_ $dir/$ip/usr/ports/",
                debug  => 0,
            );
        }
    }
    else {
        foreach ( $utility->get_dir_files( dir => "/usr/ports" ) ) {
            print "rsync -aW $_ $dir/$ip/usr/ports/ \n";
            $utility->syscmd(
                command => "rsync -aW $_ $dir/$ip/usr/ports/",debug=>0 );
        }
    }
};

sub jail_install_world {

    my $self = shift;
    
    my %p = validate( @_, {
            'ip'        => { type=>SCALAR, },
            'dir'       => { type=>SCALAR, },
            'fatal'     => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'     => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $ip, $dir, $fatal, $debug )
        = ( $p{'ip'}, $p{'dir'}, $p{'fatal'}, $p{'debug'} );

    chdir("/usr/src")
      or croak
"Yikes, no /usr/src exists! You must have the FreeBSD sources downloaded to proceed!";

    if ( ! $utility->yes_or_no(question=>"Do you have a fresh world built?") ) 
    {
        print <<"EO_FRESH_WORLD";
   In order to build a jail, you need a fresh world built. That typically
   means using cvsup to fetch the latest sources from the FreeBSD branch 
   of your choice (I recommend -stable) and then building the world. You 
   can find the instructions for doing this on www.FreeBSD.org. 
   
   If you already have up-to-date FreeBSD sources on your system, you 
   can achieve the desired result by issuing the following command: 

   make -DNOCLEAN world DESTDIR=$dir/$ip

EO_FRESH_WORLD

        if ( ! $utility->yes_or_no(question=>"Would you like me to do so now?") ) {
            croak "Sorry, I cannot continue.\n"; 
        };

        $utility->syscmd(
             command => "make -DNOCLEAN world DESTDIR=$dir/$ip", 
             debug=>0,
        );
    }
    else {
        $utility->syscmd( 
            command => "make installworld DESTDIR=$dir/$ip", 
            debug   => 0,
        );
    };

    chdir("etc");
    $utility->syscmd( command => "make distribution DESTDIR=$dir/$ip", debug=>0 );
    $utility->syscmd( command => "mount_devfs devfs $dir/$ip/dev", debug=>0 );
}

sub jail_postinstall_setup {
    my $self = shift;

    my %p = validate(@_, { 
            ip    => SCALAR, 
            dir   => SCALAR,,
            hostname => { type=>SCALAR,  optional=>1, },
        } 
    );

    my $dir = $p{'dir'};
    my $ip  = $p{'ip'};

    chdir("$dir/$ip");
    symlink( "dev/null", "kernel" );

    mkdir "$dir/$ip/stand", oct('0755');
    $utility->file_chmod( file => "$dir/$ip/stand", mode => '0755' );

    $utility->file_write( file => "$dir/$ip/etc/fstab", lines => [""] );

    $utility->file_write( 
        file => "$dir/$ip/etc/rc.conf", 
        lines => [ 
                'rpcbind_enable="NO"',
                'network_interfaces=""',
                'sshd_enable="YES"',
                'sendmail_enable="NONE"',
                'inetd_enable="YES"',
                'inetd_flags="-wW -a ' . $ip . '"',
            ]
        );

    my $hostname = $p{'hostname'} || $self->jail_get_hostname( ip=>$ip, debug=>0 );
    $utility->file_write(
        file   => "$dir/$ip/etc/hosts",
        lines  => ["$ip $hostname"],
        append => 1
    );

    my @copies = ( 
        { source => "/etc/localtime",      dest=>"$dir/$ip/etc/localtime"      },
        { source => "/etc/resolv.conf",    dest=>"$dir/$ip/etc/resolv.conf"    },
        { source => "/stand/sysinstall",   dest=>"$dir/$ip/stand"              },
        { source => "/root/.cshrc",        dest=>"$dir/$ip/root/.cshrc"        },
        { source => "/etc/ssl/openssl.cnf",dest=>"$dir/$ip/etc/ssl/openssl.cnf"},
        { source => "/etc/my.cnf",         dest=>"$dir/$ip/etc/my.cnf"         },
    );

    foreach my $copy ( @copies ) { 
        $utility->syscmd( 
            command => "cp " .$copy->{'source'} . " " . $copy->{'dest'}, 
            debug   => 0,
        );
    };

    my @lines = $utility->file_read( file => "$dir/$ip/etc/ssh/sshd_config" );
    foreach my $line (@lines) {
        $line = "ListenAddress $ip" if ( $line =~ /#ListenAddress 0.0.0.0/ );
    }
    $utility->file_write(
        file  => "$dir/$ip/etc/ssh/sshd_config",
        lines => \@lines
    );

    $utility->syscmd( command => "mount -t procfs proc $dir/$ip/proc",debug=>0 );
};

sub jail_start {

    my $self = shift;
    
    my %p = validate( @_, {
            'ip'        => { type=>SCALAR,  optional=>1, default=>"10.0.1.160", },
            'hostname'  => { type=>SCALAR,  optional=>1, },
            'jail_home' => { type=>SCALAR,  optional=>1, },
            'fatal'     => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'     => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $ip, $hostname, $dir, $fatal, $debug )
        = ( $p{'ip'}, $p{'hostname'}, $p{'jail_home'}, $p{'fatal'}, $p{'debug'} );
 
    if ( ! $ip || $ip eq "10.0.1.160" ) {
        $ip = $utility->answer(
            question => "ip address",
            default => $ip,
        );
    };

    $dir ||= $utility->answer(
        q       => "jail root directory",
        default => "/usr/jails"
    );

    $hostname ||= $self->jail_get_hostname(ip=>$ip);
    
    print "hostname: $hostname\n";

    $utility->chdir_source_dir( dir => "/usr/src" );
    unless ( -d "$dir/$ip" ) { croak "The jail dir $dir/$ip doesn't exist!\n" }

    my $mounts = $utility->drives_get_mounted( debug => $debug );

    unless ( $mounts->{"$dir/$ip/dev"} ) {
        print "mounting $dir/ip/dev\n";
        $utility->syscmd( command => "mount_devfs devfs $dir/$ip/dev", debug=>0 );
    }

    unless ( $mounts->{"$dir/$ip/proc"} ) {
        print "mounting $dir/ip/proc\n";
        $utility->syscmd( command => "mount -t procfs proc $dir/$ip/proc", debug=>0 );
    }

    print "starting jail: jail $dir/$ip $hostname $ip /bin/tcsh\n";
    $utility->syscmd( command => "jail $dir/$ip $hostname $ip /bin/tcsh", debug=>0 );
}

sub package_install {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'port'   => { type=>SCALAR, },
            'alt'    => { type=>SCALAR,  optional=>1, },
            'url'    => { type=>SCALAR,  optional=>1, },
            'fatal'  => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'  => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok'=> { type=>BOOLEAN, optional=>1 },
        },
    );

    my ( $package, $alt, $pkg_url, $fatal, $debug )
        = ( $p{'port'}, $p{'alt'}, $p{'url'}, $p{'fatal'}, $p{'debug'} );

    if ( !$package ) {
        $err = "package_install: sorry, but I really need a package name!\n";
        die $err if $fatal;
        carp $err;
        return;
    }

    $utility->_formatted("package_install: checking if $package is installed")
      if $debug;
     
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $r = $self->is_port_installed(
        port  => $package,
        alt   => $alt,
        debug => $debug,
        fatal => $fatal,
    );
    if ($r) {
        if ($debug) {
            printf "package_install: %-20s installed as (%s).\n", $package, $r;
        }
        return $r;
    }


    print "package_install: installing $package....\n" if $debug;
    $ENV{"PACKAGESITE"} = $pkg_url if $pkg_url;

    my $pkg_add = $utility->find_the_bin( bin => "pkg_add", debug=>$debug, fatal=>$fatal );
    if ( ! $pkg_add || ! -x $pkg_add ) {
        carp "couldn't find pkg_add, giving up.";
        return;
    };

    my $r2 = $utility->syscmd( command => "$pkg_add -r $package" , debug=>0);

    if   (!$r2) { print "\t pkg_add failed\t "; }
    else        { print "\t pkg_add success\t " if $debug }

    print "done.\n" if $debug;

    unless (
        $self->is_port_installed(
            port  => $package,
            alt   => $alt,
            debug => $debug,
            fatal => $fatal,
        )
      )
    {
        print "package_install: Failed #1, trying alternate package site.\n";
        $ENV{"PACKAGEROOT"} = "ftp://ftp2.freebsd.org";
        $utility->syscmd( command => "$pkg_add -r $package" , debug=>0);

        unless (
            $self->is_port_installed(
                port  => $package,
                alt   => $alt,
                debug => $debug,
                fatal => $fatal,
            )
          )
        {
            print
              "package_install: Failed #2, trying alternate package site.\n";
            $ENV{"PACKAGEROOT"} = "ftp://ftp3.freebsd.org";
            $utility->syscmd( command => "$pkg_add -r $package" , debug=>0);

            unless (
                $self->is_port_installed(
                    port  => $package,
                    alt   => $alt,
                    debug => $debug,
                    fatal => $fatal,
                )
              )
            {
                print
"package_install: Failed #3, trying alternate package site.\n";
                $ENV{"PACKAGEROOT"} = "ftp://ftp4.freebsd.org";
                $utility->syscmd( command => "$pkg_add -r $package" , debug=>0);
            }
        }
    }

    unless (
        $self->is_port_installed(
            port  => $package,
            alt   => $alt,
            debug => $debug,
            fatal => $fatal,
        )
      )
    {
        carp
"package_install: Failed again! Sorry, I can't install the package $package!\n";
        return;
    }

    return $r;
}

sub port_install {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'port'     => { type=>SCALAR,  optional=>0, },
            'base'     => { type=>SCALAR,  optional=>0, },
            'dir'      => { type=>SCALAR,  optional=>1, },
            'check'    => { type=>SCALAR,  optional=>1, },
            'flags'    => { type=>SCALAR,  optional=>1, },
            'no_update'=> { type=>BOOLEAN, optional=>1, default=>0 },
            'options'  => { type=>SCALAR,  optional=>1, },
            'fatal'    => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'    => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok'  => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $port, $base, $dir, $check, $flags, $no_update, $options, $fatal, $debug )
        = ( $p{'port'}, $p{'base'}, $p{'dir'}, $p{'check'}, $p{'flags'}, 
            $p{'no_update'}, $p{'options'}, $p{'fatal'}, $p{'debug'} );

    my $make_defines = "";
    my @defs;

    $check ||= $port;

    if   ($dir) { $dir = "/usr/ports/$base/$dir" }
    else        { $dir = "/usr/ports/$base/$port" }

    # this will detect if you have a ports tree that hasn't been updated
    # since net-mgmt was split from net
    if ( $base eq "net-mgmt" && !-d "/usr/ports/net-mgmt" ) {
        $base = "net";
    }

    # used for package tests
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    unless ( -d $dir ) {
        $utility->_formatted( "port_install: $dir does not exist for $port",
            "FAILED" );
        croak if $fatal;
        return;
    }

    my $registered_as = $self->is_port_installed( 
            port  => $check, 
            debug => 0, 
            fatal => $fatal,
        );
    if ( $registered_as  ) {
        $utility->_formatted( "port_install: $port", "ok ($registered_as)" );
        #$utility->_formatted( "port_install: $port", "ok ($registered_as)" ) if $debug;
        return 1;
    }

    unless ( $no_update ) {
        $self->ports_check_age( days => "30", debug => $debug );
    }

    # these are the "make -DWITH_OPTION" flags
    if ($flags) {    
        @defs = split( /,/, $flags );
        foreach my $def (@defs) {
            # if provided in the DEFINE=VALUE format, use it as is
            if   ( $def =~ /=/ ) { $make_defines .= " $def " }
            # otherwise, we need to prepend the -D flag
            else                 { $make_defines .= " -D$def " }
        }
    }

    my $old_directory = Cwd::cwd();
    print "port_install: installing $port...\n" if $debug;
    chdir($dir) or croak "couldn't cd to $dir: $!\n";

    if ( $options ) {
        $self->port_options(
            port  => $port,
            opts  => $options,
            debug => $debug,
            fatal => $fatal,
        );
    };

    if ( $port eq "qmail" ) {

        $utility->syscmd( command => "make install; make clean", debug=>$debug );

        #$utility->syscmd( command=>"make install; make enable-qmail; make clean" );

        # remove that pesky qmail startup file
        # we run qmail under daemontools
        if ( -e "/usr/local/etc/rc.d/qmail.sh" ) {
            use File::Copy;
            move(
                "/usr/local/etc/rc.d/qmail.sh",
                "/usr/local/etc/rc.d/qmail.sh-dist"
            ) or croak "$!";
        }
    }
    elsif ( $port eq "ezmlm-idx" ) {
        $utility->syscmd( command => "make $make_defines install", debug=>$debug, fatal=>$fatal );
        copy( "work/ezmlm-0.53/ezmlmrc", "/usr/local/bin" );
        $utility->syscmd( command => "make clean", debug=>$debug, fatal=>$fatal );
    }
    elsif ( $port eq "sqwebmail" ) {
        print "running: make $make_defines install\n";
        $utility->syscmd( command => "make $make_defines install", debug=>$debug, fatal=>$fatal );
        chdir("$dir/work");
        my @list = $utility->get_dir_files( dir => "." );
        chdir( $list[0] );
        $utility->syscmd( command => "make install-configure", debug=>$debug, fatal=>$fatal );
        chdir($dir);
        $utility->syscmd( command => "make clean", debug=>$debug, fatal=>$fatal );
    }
    elsif ( $port eq "fastest_cvsup" ) {
        print "running: make; make install clean\n";
        $utility->syscmd( command => "make", fatal=>0, debug=>$debug, fatal=>$fatal );
        $utility->syscmd( command => "make install clean", debug=>$debug, fatal=>$fatal );
    }
    else {
        # reset our PATH, to make sure we use our system supplied tools
        $ENV{PATH} = "/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin";

        # the vast majority of ports work great this way
        print "running: make $make_defines install clean\n";
        system "make clean";
        system "make $make_defines";
        system "make $make_defines install";
        system "make clean";
    }
    print "done.\n" if $debug;

    # return to our original working directory
    chdir($old_directory);

    $registered_as = $self->is_port_installed( 
            port  => $check, 
            debug => $debug, 
            fatal=>$fatal 
        );

    if ($registered_as) {
        $utility->_formatted( "port_install: $port install", "ok ($registered_as)" );
        return 1;
    }

    $utility->_formatted( "port_install: $port install", "FAILED" );
    print <<"EO_PORT_TRY_MANUAL";

    Automatic installation of port $port failed! You can try to install $port manually
using the following commands:

        cd $dir
        make
        make install clean

    If that does not work, make sure your ports tree is up to date and try again. You
can also check out the "Dealing With Broken Ports" article on the FreeBSD web site:

        http://www.freebsd.org/doc/en_US.ISO8859-1/books/handbook/ports-broken.html

If none of those options work out, there may be something "unique" about your system
that is the source of the  problem, or the port my just be broken. You have several
choices for proceeding. You can:

    a. Wait until the port is fixed
    b. Try fixing it yourself
    c. Get someone else to fix it (cash usually helps)

EO_PORT_TRY_MANUAL

    if ( $port =~ /\Ap5\-(.*)\z/ ) {
        my $p_name = $1;
        $p_name =~ s/\-/::/g;

        print <<"EO_PERL_MODULE_MANUAL";
Since it was a perl module that failed to install,  you could also try
manually installing via CPAN. Try something like this:

       perl -MCPAN -e shell
       > install $p_name
       > quit

EO_PERL_MODULE_MANUAL
    };

    croak "FATAL FAILURE: Install of $port failed. Please fix and try again.\n"
      if $fatal;
    return 0;
}

sub port_options {

    my $self = shift;

    my %p = validate(@_, {
            'port' => SCALAR,
            'opts' => SCALAR,
            'debug' => { type=>BOOLEAN, optional=>1, default=>1, },
            'fatal' => { type=>BOOLEAN, optional=>1, default=>1, },
            test_ok => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ($port, $opts, $fatal) = ( $p{'port'}, $p{'opts'}, $p{'fatal'} );

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    if ( !-d "/var/db/ports/$port" ) {
        $utility->mkdir_system(dir=>"/var/db/ports/$port", debug=>0, fatal=>$fatal);
    };

    $utility->file_write(file=>"/var/db/ports/$port/options", lines=>[$opts], debug=>0, fatal=>$fatal);
};

sub portsdb_Uu {
    my $self = shift;

    my %p = validate(@_, {
            debug => { type=>BOOLEAN, optional=>1, default=>1 },
            fatal => { type=>BOOLEAN, optional=>1, default=>1 },
            test_ok => { type=>BOOLEAN, optional=>1, },
        },
    );

    my $debug = $p{'debug'};
    my $fatal = $p{'fatal'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    print "ports_update: according to the FreeBSD portsdb man page: \n\n
    Note that INDEX file is updated every few hours on official site, it is 
    recommended that you run ``portsdb -Fu'' after every CVSup of the ports 
    tree in order to keep them always up-to-date and in sync with the ports tree.\n";

    print("\a");
    sleep 2;

    if ( !
        $utility->yes_or_no(
            question => "\n\nWould you like me to run portsdb -Fu",
            timeout  => 60,
        )
      )
    {
        return 1;
    }

    my $portsdb = $utility->find_the_bin( bin => "portsdb", debug=>0,fatal=>0 );
    unless ( $portsdb && -x $portsdb ) {
        print "\a";  # bell
        print "
        ATTENTION: I could not find portsdb, which means that portugprade
        is not installed.\n";

        if ( ! $utility->yes_or_no( 
                question=>"Would you like me to install it now",
            )
        ) {
            return 1;
        };

        $self->install_portupgrade(debug=>$debug, fatal=>$fatal);
    };

    $portsdb = $utility->find_the_bin( bin => "portsdb", debug=>0 );
    $utility->syscmd( command => "$portsdb -Fu", debug=>$debug );
};

sub ports_check_age {

    my $self = shift;

    # parameter validation here
    my %p = validate( @_, {
            'days'    => { type=>SCALAR, },
            'url'     => { type=>SCALAR, optional=>1, default=>"http://mail-toaster.org"},
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $days, $url, $fatal, $debug, $test_ok )
        = ( $p{'days'}, $p{'url'}, $p{'fatal'}, $p{'debug'}, $p{'test_ok'} );


    if ( defined $test_ok ) { return $test_ok; }

    if ( -M "/usr/ports" > $days ) {
        return $self->ports_update( debug=>$debug );
    }
    else {
        print "ports_check_age: Ports file is current (enough).\n" if $debug;
        return 1;
    }
}

sub ports_update {

    my $self = shift;
    
    my %p = validate( @_, {
            conf    => { type=>HASHREF, optional=>1, },
            fatal   => { type=>BOOLEAN, optional=>1, default=>1 },
            debug   => { type=>BOOLEAN, optional=>1, default=>1 },
            test_ok => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $fatal, $debug )
        = ( $p{'conf'}, $p{'fatal'}, $p{'debug'} );

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    if ( ! -w "/usr/ports" ) {
        carp "you do not have write permission on /usr/ports, I cannot update your ports tree.";
        return;
    };

    my $days_old = int( (-M "/usr/ports") + 0.5);
    print "\n\nports_update: Your ports tree has not been updated in $days_old days.";
    unless (
        $utility->yes_or_no(
            timeout  => 60,
            question => "\nWould you like me to update it for you?:"
        )
      )
    {
        $utility->_formatted( "ports_update: updating FreeBSD ports tree",
            "skipped" );
        return;
    }

    my $supfile = $conf->{'cvsup_supfile_ports'} || "portsnap";

    if ( $supfile eq "portsnap" ) {
        return $self->portsnap(debug=>$debug, fatal=>$fatal);
    };

    # if we got here, these are set
    $supfile  = $conf->{'system_config_dir'}   || "/usr/local/etc";
    $supfile .= $conf->{'cvsup_supfile_ports'} || "cvsup-ports";

    my $toaster = $conf->{'toaster_dl_site'} || "http://www.tnpi.net";
    $toaster   .= $conf->{'toaster_dl_url'}  || "/internet/mail/toaster";

    my $cvsupbin = $self->install_cvsup( debug=>$debug, fatal=>$fatal );

    unless ( -e $supfile ) {
        $utility->file_get( url => "$toaster/etc/cvsup-ports", debug=>$debug );
        move( "cvsup-ports", $supfile ) or croak "$!";
    }

    my $cvshost = $self->cvsup_select_host(conf=>$conf, debug=>$debug);

    my $cmd = "$cvsupbin -g ";
    $cmd .= "-h $cvshost " if $cvshost;
    $cmd .= "$supfile";

    print "selecting the fastest cvsup host...\n";
    $utility->syscmd( command => $cmd, debug=>0 , fatal=>$fatal );

    # download the latest index file
    #chdir("/usr/ports")
    $utility->syscmd( command => "cd /usr/ports; make fetchindex", debug => 0, fatal=>$fatal);

    # install portupgrade
    if ( $conf->{'install_portupgrade'} ) {
        $self->install_portupgrade(conf=>$conf, debug=>$debug, fatal=>$fatal);
    }

    # optionally run portsdb
    $self->portsdb_Uu(debug=>$debug, fatal=>$fatal);

    print "\n

	Now that your ports tree is updated, I recommend that you run pkgdb -F.
	Then run portupgrade -ai, upgrading everything except XFree86, qmail, and 
	vpopmail. Upgrading other non-mail related items is optional.

	If you have problems upgrading a particular port, then I recommend
	removing it (pkg_delete port_name-1.2) and then proceeding.

	If you upgrade perl (yikes), make sure to also rebuild all the perl
	modules you have installed or run perl-after-upgrade with perl 5.8.7+.
	See the toaster FAQ or /usr/ports/UPDATING for more details.\n
";

    return 1;
}

sub portsnap {

    my $self = shift;
    
    my %p = validate( @_, {
#            'conf'    => { type=>HASHREF, optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $fatal, $debug )
        = ( $p{'conf'}, $p{'fatal'}, $p{'debug'} );

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    # should be installed already on FreeBSD 5.5 and 6.x
    my $portsnap = $utility->find_the_bin(bin=>"portsnap", fatal=>0, debug=>$debug);
    my $ps_conf  = "/usr/local/etc/portsnap.conf";

    unless ( $portsnap && -x $portsnap ) {
        # try installing from ports
        $self->port_install(
            'port'  => "portsnap",
            'base'  => "sysutils",
            'debug' => $debug,
            'fatal' => $fatal,
            'no_update' => 1,
        );

        if ( ! -e  $ps_conf ) {
            if ( -e "$ps_conf.sample" ) {
                copy("$ps_conf.sample", $ps_conf);
            } else {
                    warn "WARNING: portsnap configuration file is missing!\n";
            };
        };

        $portsnap = $utility->find_the_bin(bin=>"portsnap", fatal=>0, debug=>$debug);
        unless ( $portsnap && -x $portsnap ) {
            $err = "portsnap is not installed (correctly). I cannot go on!";
            croak $err if $fatal;
            carp $err;
            return;
        };
    };

    if ( !-e $ps_conf ) {
         $portsnap .= " -s portsnap.freebsd.org";
    };

    # grabs the latest updates from the portsnap servers
    $utility->syscmd( cmd=>"portsnap fetch", debug=>0, fatal=>$fatal );

    if ( ! -e "/usr/ports/.portsnap.INDEX" ) {
        print "\a
    COFFEE BREAK TIME: this step will take a while, dependent on how fast your
    disks are. After this initial extract, portsnap updates are much quicker than
    doing a cvsup and require less bandwidth (good for you, and the FreeBSD 
    servers). So, please be patient.\n\n";
        sleep 2;
        $utility->syscmd( cmd=>"$portsnap extract", debug=>0, fatal=>$fatal );
    }
    else {
        $utility->syscmd( cmd=>"$portsnap update", debug=>0, fatal=>$fatal );
    };

    $self->portsdb_Uu(debug=>$debug, fatal=>$fatal);

    return 1;
}

sub rc_dot_conf_check {

    my $self = shift;
    
    my %p = validate( @_, {
            'check'   => { type=>SCALAR, },
            'line'    => { type=>SCALAR,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            test_ok   => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $check, $line, $fatal, $debug )
        = ( $p{'check'}, $p{'line'}, $p{'fatal'}, $p{'debug'} );

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $file = "/etc/rc.conf";
    return 1 if `grep $check $file`;

    $utility->file_write( 
        file   => $file, 
        lines  => [$line], 
        append => 1, 
        debug  => $debug,
        fatal  => $fatal,
    );

    return 1 if `grep $check $file`;

    print "rc.conf_check: FAILED to add $line to $file: $!\n";
    carp "
    NOTICE: It would be a good idea for you to manually add:
         $line 
    to $file.         ";
    croak if $fatal;
    return;
}

sub source_update {

    my $self = shift;
    
    my %p = validate( @_, {
	        'conf'                   => { type=>HASHREF, optional=>1, },
	        'cvsup_server_preferred' => { type=>SCALAR,  optional=>1, default=>'fastest'},
	        'cvsup_server_country'   => { type=>SCALAR,  optional=>1, default=>'us'},
	        'cvsup_supfile_sources'  => { type=>SCALAR,  optional=>1, },
            'fatal'                  => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'                  => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok'                => { type=>BOOLEAN, optional=>1, },
        },
    );

	my ($conf, $cvshost, $country_code, $supfile, $fatal, $debug) 
	    = ($p{'conf'}, $p{'cvsup_server_preferred'}, $p{'cvsup_server_country'}, 
            $p{'cvsup_supfile_sources'}, $p{'fatal'}, $p{'debug'} );

    my $toaster = $conf->{'toaster_dl_site'} . $conf->{'toaster_dl_url'}
      || "http://www.tnpi.net/internet/mail/toaster";

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    print "\n\nsource_update: Getting ready to update your sources!\n\n";

    my $cvsupbin = $utility->find_the_bin( bin => "cvsup",debug=>0,fatal=>0 );
    unless ( $cvsupbin && -x $cvsupbin ) {
        
        print "source_update: cvsup isn't installed. I'll fix that.\n";

        # because of cvsup's build dependence on ezm3, we want to install it
        # as a package if possible.
        $self->package_install( port => "cvsup-without-gui", debug=>$debug, fatal=>$fatal );

        if ( -d "/usr/ports/net/cvsup-without-gui" )
        {
            $self->port_install( port => "cvsup-without-gui", base => "net", debug=>$debug, fatal=>$fatal );
        }
        $cvsupbin = $utility->find_the_bin( bin => "cvsup", debug=>$debug, fatal=>$fatal );
    }

    my $etcdir = $conf->{'system_config_dir'}     || "/usr/local/etc";
    $supfile ||= $conf->{'cvsup_supfile_sources'} || "cvsup-sources";
    print "source_update: using $supfile.\n";

    my $releng;
    if ( ! -e "$etcdir/$supfile" ) {
        print "source_update: your cvsup config file ($etcdir/$supfile) is missing!\n";
    };

    my $os_version = $self->get_version();

    # get_version returns something like this: 6.1-RELEASE-p6
    print "OS version is: " . $os_version. "\n"  if $debug;

    # if it is set properly, use it.
    if ( defined $conf->{'toaster_os_release'} ) {
        my $ver = $conf->{'toaster_os_release'};
        if ( $ver && $ver eq uc($ver) && $ver =~ /RELENG/ ) {
            $releng = $ver;
        } 
    }
    else {
        # otherwise try to determine it.
        if ( $os_version =~ /\A ([\d]) \. ([\d]) \- (\w+) /xms ) {
            $releng = "RELENG_$1.$2";
        }
        else {
            print "
I need to figure out which cvsup tag to use for your installation. Please 
edit toaster-watcher.conf and set toaster_os_release in the following format: 

    toaster_os_release = RELENG_6_1\n ";
            return;
        }
    }

    print "FreeBSD cvs tag: $releng\n" if $debug;

    my $tmp = $conf->{'toaster_tmp_dir'} || "/tmp";

    $cvshost = $self->cvsup_select_host(conf=>$conf);

    my @lines = "*default host=$cvshost\n"
              . "*default base=/usr\n"
              . "*default prefix=/usr\n"
              . "*default release=cvs tag=$releng\n"
              . "*default delete use-rel-suffix\n"
              . "src-all\n";

    $utility->file_write(
        file => "$tmp/sources",
        lines => \@lines,
        debug => $debug,
        fatal => $fatal,
    );

    $utility->install_if_changed(
        newfile  => "$tmp/sources",
        existing => "$etcdir/$supfile",
        debug    => $debug,
        fatal    => $fatal,
    );

    print "source_update: using $supfile\n";

    my $cmd  = "$cvsupbin -g ";
       $cmd .= "-h $cvshost " if $cvshost;
       $cmd .= "$etcdir/$supfile";
    
    $utility->syscmd( command => $cmd, debug=>$debug, fatal=>$fatal );

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

    return 1;
}

1;
__END__


=head1 NAME

Mail::Toaster::FreeBSD - FreeBSD specific Mail::Toaster functions.


=head1 SYNOPSIS

Primarily functions for working with FreeBSD ports (updating, installing, configuring with custom options, etc) but also includes a suite of methods for FreeBSD managing jails.


=head1 DESCRIPTION

Usage examples for each subroutine are included.


=head1 SUBROUTINES

=over

=item new

	use Mail::Toaster::FreeBSD;
	my $fbsd = Mail::Toaster::FreeBSD->new;


=item cvsup_select_host

Selects a host to cvsup port updates from. If you pass $conf to it, it will detect your country automatically. If fastest_cvsup is installed, it will detect it and use it to pick the fastest host in your country. If it is not installed and the hostname is set to "fastest", it will try to install fastest_cvsup from ports.

 arguments optional:
    conf

 result:
    a hostname to grab cvsup sources from


=item is_port_installed

Checks to see if a port is installed. 

    $fbsd->is_port_installed( port=>"p5-CGI" );

 arguments required
   port - the name of the port/package

 arguments optional:
   alt - alternate package name. This can help as ports evolve and register themselves differently in the ports database.

 result:
   0 - not installed
   1 - if installed 


=item jail_create

    $fbsd->jail_create( );

 arguments required:
    ip        - 10.0.1.1
    
 arguments optional:
    hostname  - jail36.example.com,
    jail_home - /home/jail,
    debug

If hostname is not passed and reverse DNS is set up, it will
be looked up. Otherwise, the hostname defaults to "jail".

jail_home defaults to "/home/jail".

Here's an example of how I use it:

    ifconfig fxp0 inet alias 10.0.1.175/32

    perl -e 'use Mail::Toaster::FreeBSD;  
         my $fbsd = Mail::Toaster::FreeBSD->new; 
         $fbsd->jail_create( ip=>"10.0.1.175" )';

After running $fbsd->jail_create, you need to set up the jail. 
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
    pkg_add -r sudo rsync perl5.8
    rehash; visudo
    sh /etc/rc

Ssh into the jail from another terminal. Once successfully 
logged in with root privs, you can drop the initial shell 
and access the jail directly.

Read the jail man pages for more details. Read the perl code
to see what else it does.


=item jail_delete

Delete a jail.

  $freebsd->jail_delete( ip=>'10.0.1.160' );

This script unmounts the proc and dev filesystems and then nukes the jail directory.

It would be a good idea to shut down any processes in the jail first.


=item jail_start

Starts up a FreeBSD jail.

	$fbsd->jail_start( ip=>'10.0.1.1', hostname=>'jail03.example.com' );


 arguments required:
    ip        - 10.0.1.1,

 arguments optional:
    hostname  - jail36.example.com,
    jail_home - /home/jail,
    debug

If hostname is not passed and reverse DNS is set up, it will be
looked up. Otherwise, the hostname defaults to "jail".

jail_home defaults to "/home/jail".

Here's an example of how I use it:

    perl -e 'use Mail::Toaster::FreeBSD; 
      $fbsd = Mail::Toaster::FreeBSD->new;
      $fbsd->jail_start( ip=>"10.0.1.175" )';


    
=item port_install

    $fbsd->port_install( port=>"openldap2", base=>"net" );

That's it. Really. Well, OK, sometimes it can get a little more complex. port_install checks first to determine if a port is already installed and if so, skips right on by. It is very intelligent that way. However, sometimes port maintainers do goofy things and we need to override settings that would normally work. A good example of this is currently openldap2. 

If you want to install OpenLDAP 2, then you can install from any of:

		/usr/ports/net/openldap2
		/usr/ports/net/openldap20
		/usr/ports/net/openldap21
		/usr/ports/net/openldap22

So, a full complement of settings could look like:
  
    $freebsd->port_install(
		port  => "openldap2", 
		base  => "net",
		dir   => "openldap22",
		check => "openldap-2.2",
		flags => "NOPORTDOCS=true", 
		fatal => 0,
		debug => 1,
	);

 arguments required:
   port - the name of the directory in which the port resides
   base - the base or category the port is in (security, net, lang, etc.)

 arguments optional:
   dir   - overrides 'port' for the build directory
   check - what to test for to determine if the port is installed (see note #1)
   flags - comma separated list of arguments to pass when building
   fatal
   debug

 NOTES:   

#1 - On rare occasion, a port will get installed as a name other than the ports name. Of course, that wreaks all sorts of havoc so when one of them nasties is found, you can optionally pass along a fourth parameter which can be used as the port installation name to check with.


=item package_install

	$fbsd->package_install( port=>"ispell" );

Suggested usage: 

	unless ( $fbsd->package_install( port=>"ispell" ) ) {
		$fbsd->port_install( port=>"ispell", base=>"textproc" );
	};

Installs the selected package from FreeBSD packages. If the first install fails, it will try again using an alternate FTP site (ftp2.freebsd.org). If that fails, it returns 0 (failure) so you know it failed and can try something else, like installing via ports.

If the package is registered in FreeBSD's package registry as another name and you want to check against that name (so it doesn't try installing a package that's already installed), instead, pass it along as alt.

 arguments required:
    port - the name of the package to install

 arguments optional:
    alt  - a name the package is registered in the ports tree as
    url  - a URL to fetch the package from

See the pkg_add man page for more details on using an alternate URL.


=item ports_check_age

Checks how long it's been since you've updated your ports tree. Since the ports tree can be a roaming target, by making sure it's current before installing ports we can increase the liklihood of success. 

	$fbsd->ports_check_age( days=>"20" );

That'll update the ports tree if it's been more than 20 days since it was last updated.

 arguments required:
   days - how many days old it must be to trigger an update

 arguments optional:
   url - where to fetch the cvsup-ports file.


=item ports_update

Updates the FreeBSD ports tree (/usr/ports/).

    $fbsd->ports_update(conf=>$conf);

 arguments required:
   conf - a hashref
 
See the docs for toaster-watcher.conf for complete details.


=item rc_dot_conf_check

    $fbsd->rc_dot_conf_check(check=>"snmpd_enable", line=>"snmpd_enable=\"YES\"");

The above example is for snmpd. This checks to verify that an snmpd_enable line exists in /etc/rc.conf. If it doesn't, then it will add it by appending the second argument to the file.


=item source_update

Updates the FreeBSD sources (/usr/src/) in preparation for building a fresh FreeBSD world.

    $fbsd->source_update( conf=>$conf);

 arguments required:
     conf 

 arguments optional:
     cvsup_server_preferred - 'fastest',
     cvsup_server_country   - 'us',
     cvsup_supfile_sources  - '/etc/cvsup-stable',
     fatal
     debug

See the docs for toaster-watcher.conf for complete details.


=back

=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>

=head1 BUGS

None known. Report any to author.

=head1 TODO

Needs more documentation.

=head1 SEE ALSO

The following are all man/perldoc pages: 

 Mail::Toaster 
 Mail::Toaster::Conf
 toaster.conf
 toaster-watcher.conf

 http://mail-toaster.org/
 http://www.tnpi.biz/computing/freebsd/


=head1 COPYRIGHT

Copyright 2003-2006, The Network People, Inc. All Rights Reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
