
use strict;
use warnings;

use English qw( -no_match_vars );
use Test::More;

use lib "lib";
use lib "inc";

if ( $OSNAME ne "freebsd" ) {
    plan skip_all => "FreeBSD tests skipped on " . $OSNAME;
}
else {
    plan 'no_plan';
};

require_ok( 'Mail::Toaster::FreeBSD' );
require_ok( 'Mail::Toaster::Utility' );


# basic OO mechanism
my $freebsd = Mail::Toaster::FreeBSD->new;                       # create an object
ok ( defined $freebsd, 'get Mail::Toaster::FreeBSD object' );    # check it
ok ( $freebsd->isa('Mail::Toaster::FreeBSD'), 'check object class' );


# most subs expect $conf to be passed to them
my $util = Mail::Toaster::Utility->new;
my $conf = $util->parse_config( file=>"toaster-watcher.conf", debug=>0 );

# cvsup_select_host
	ok ( $freebsd->cvsup_select_host( conf=>$conf, test_ok=>1,debug=>0 ), 'cvsup_select_host');

    # test the return value if set to a hostname 
	$conf->{'cvsup_server_preferred'} = "cvsup8.us.freebsd.org";
	cmp_ok ( "cvsup8.us.freebsd.org",
             "eq",
             $freebsd->cvsup_select_host( conf=>$conf, debug=>0, fatal=>0 ), 
            'cvsup_select_host static');

	$conf->{'cvsup_server_preferred'} = "fastest";
	cmp_ok ( 1,
             "eq",
             $freebsd->cvsup_select_host( conf=>$conf, test_ok=>1, debug=>0, fatal=>0 ), 
            'cvsup_select_host fastest');

# drive_spin_down
	# how exactly do I test this? 
		# a) check for SCSI disks, 
		# b) see if there is more than one
    ok ( $freebsd->drive_spin_down( drive=>"0:1:0", test_ok=>1, debug=>0), 'drive_spin_down');
    ok ( ! $freebsd->drive_spin_down( drive=>"0:1:0", test_ok=>0, debug=>0), 'drive_spin_down');


# get_version
    ok ( $freebsd->get_version(), 'get_version');
    my $os_ver = `/usr/bin/uname -r`; chomp $os_ver;
    cmp_ok ( $os_ver, "eq", $freebsd->get_version(0), 'get_version');


# install_cvsup
    ok ( $freebsd->install_cvsup( test_ok=>1 ), 'install_cvsup');

# is_port_installed
	ok ( $freebsd->is_port_installed( 
            port  => "perl", 
            debug => 0, 
            fatal => 0,
            test_ok=> 1,
        ), 'is_port_installed');


# install_portupgrade
    ok ( $freebsd->install_portupgrade( test_ok=>1, fatal=>0 ), 'install_portupgrade');


# package_install
	ok ( $freebsd->package_install( 
            port=>"perl", 
            debug=>0,
            fatal=>0,
            test_ok=>1,
       ), 'package_install');


# port_install
	ok ( $freebsd->port_install( 
	    port  => "perl", 
	    base  => "lang", 
	    dir   => 'perl5.8', 
	    debug => 0, 
        fatal => 0,
	    test_ok=> 1, 
	), 'port_install');


# port_options
    ok ( $freebsd->port_options(
        port => 'p5-Tar-Diff',
        opts => 'blah,test,deleteme\n',
        test_ok=>1,
    ), 'port_options');


# portsdb_Uu
    ok ( $freebsd->portsdb_Uu(test_ok=>1), 'portsdb update');


# ports_check_age
	ok ( $freebsd->ports_check_age( days=>"30", debug=>0, test_ok=>1 ), 'ports_check_age');
	ok ( ! $freebsd->ports_check_age( days=>"30", debug=>0, test_ok=>0 ), 'ports_check_age');


# ports_update
    ok ( $freebsd->ports_update(
            debug=>0,
            fatal=>0,
            test_ok=>1,
        ), 'ports_update');


# portsnap
    ok ( $freebsd->portsnap(
            debug=>0,
            fatal=>0,
            test_ok=>1,
        ), 'portsnap');


# rc_dot_conf_check
	ok ( $freebsd->rc_dot_conf_check(
	    check => "hostname", 
	    line  => "hostname='mail.example.com'",
        fatal => 0,
        test_ok => 1,
	), 'rc_dot_conf_check' );

# source_update
    ok ( $freebsd->source_update(
            conf  => $conf,
            debug => 0,
            fatal => 0,
            test_ok=>1,
    ), 'source_update');


__END__;

jail_create
jail_delete
jail_get_hostname
jail_install_world
jail_start
