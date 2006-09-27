#!/usr/bin/perl
#
# $Id: Qmail.t,v 4.2 2005/05/18 14:46:38 matt Exp $
#
use strict;
use warnings;
use English qw( -no_match_vars );

use Test::More 'no_plan';

use lib "lib";

BEGIN { 
    use_ok( 'Mail::Toaster::Qmail' );
    use_ok( 'Mail::Toaster::Utility' );
    use_ok( 'Mail::Toaster' );
};
require_ok( 'Mail::Toaster::Qmail' );
require_ok( 'Mail::Toaster::Utility' );
require_ok( 'Mail::Toaster' );

# let the testing begin

# basic OO mechanism
    my $qmail = Mail::Toaster::Qmail->new;                       # create an object
    ok ( defined $qmail, 'get Mail::Toaster::Qmail object' );    # check it
    ok ( $qmail->isa('Mail::Toaster::Qmail'), 'check object class' );   # is it the right class

# many of the subs expect this to be passed to them
my $toaster = Mail::Toaster->new;
my $utility = Mail::Toaster::Utility->new;
my $conf = $utility->parse_config( file=>"toaster-watcher.conf", debug=>0 );

my $r;
my $has_net_dns;


# get_list_of_rwls
	$r = $qmail->get_list_of_rwls( conf=>{ 'rwl_qmail.bondedsender.org'=> 1}, debug=>0 );
	ok ( @$r[0], 'get_list_of_rwls'); 


# test_each_rbl
    $r = $qmail->test_each_rbl( rbls=>$r, debug=>0, fatal=>0 );
    ok ( @$r[0], 'test_each_rbl'); 


# get_list_of_rbls
	$r = $qmail->get_list_of_rbls( conf=>{'rbl_sbl-xbl.spamhaus.org'=> 1}, debug=>0,fatal=>0 );
	cmp_ok ( $r, "eq", "-r sbl-xbl.spamhaus.org ", 'get_list_of_rbls'); 

	# test one with a sort order
	$r = $qmail->get_list_of_rbls( conf=>{'rbl_sbl-xbl.spamhaus.org'=> 2}, debug=>0, fatal=>0 );
	cmp_ok ( $r, "eq", "-r sbl-xbl.spamhaus.org ", 'get_list_of_rbls');

	# no enabled rbls!
	ok ( ! $qmail->get_list_of_rbls( conf=>{'rbl_sbl-xbl.spamhaus.org'=> 0}, debug=>0, fatal=>0 ), 
        'get_list_of_rbls nok');
	#cmp_ok ( $r, "eq", "", 'get_list_of_rbls nok');

	# ignore custom error messages
	$r = $qmail->get_list_of_rbls( conf=>{'rbl_sbl-xbl.spamhaus.org_message'=> 2}, debug=>0, fatal=>0 );
	ok ( ! $r, 'get_list_of_rbls nok');


# get_list_of_rwls
	$r = $qmail->get_list_of_rwls( conf=>{'rwl_qmail.bondedsender.org'=> 1}, debug=>0 );
	ok ( @$r[0] eq "qmail.bondedsender.org", 'get_list_of_rwls'); 

	# no enabled rwls!
	$r = $qmail->get_list_of_rwls( conf=>{'rwl_qmail.bondedsender.org'=> 0}, debug=>0 );
	ok ( ! @$r[0], 'get_list_of_rwls nok');


# service_dir_get
	# a normal smtp invocation
	$r = $qmail->service_dir_get( conf=>{qmail_service_smtp=>'/var/service/smtp'}, prot=>"smtp", debug=>0 );
	ok ( $r eq "/var/service/smtp", 'service_dir_get smtp');

	# a normal invocation with a conf file shortcut
	$r = $qmail->service_dir_get( conf=>{qmail_service_smtp=>'qmail_service/smtp'}, prot=>"smtp", debug=>0 );
	ok ( $r eq "/var/service/smtp", 'service_dir_get smtp');

	# a deprecated invocation
	$r = $qmail->service_dir_get( conf=>{qmail_service_smtp=>'qmail_service/smtp'}, prot=>"smtpd", debug=>0 );
	ok ( $r eq "/var/service/smtp", 'service_dir_get smtp');

	# a normal send invocation
	my $send = $qmail->service_dir_get( conf=>{qmail_service_send=>'/var/service/send'}, prot=>"send", debug=>0 );
	ok ( $send eq "/var/service/send", 'service_dir_get send');

	# a normal pop3 invocation
	$r = $qmail->service_dir_get( conf=>{qmail_service_pop3=>'/var/service/pop3'}, prot=>"pop3", debug=>0 );
	ok ( $r eq "/var/service/pop3", 'service_dir_get pop3');

	# an invalid protocol
	$r = $qmail->service_dir_get( conf=>{qmail_service_pop3=>'/var/service/invalid'}, prot=>"invalid", fatal=>0, debug=>0 );
	ok ( ! $r , 'service_dir_get invalid');

# _set_checkpasswd_bin
	# this test will only succeed on a fully installed toaster
	if ( -d $conf->{'vpopmail_home_dir'} ) {
		ok ( $qmail->_set_checkpasswd_bin( conf=>$conf, prot=>"pop3", debug=>0, fatal=>0 ), 
			'_set_checkpasswd_bin' );
	};


# supervised_hostname_qmail
	ok ( $qmail->supervised_hostname_qmail( prot=>'pop3',debug=>0 ), 
		'supervised_hostname_qmail' );

	# invalid type
#	ok ( ! $qmail->supervised_hostname_qmail( 
#			prot=>['invalid'],debug=>0,fatal=>0
#		), 'supervised_hostname_qmail' );


# _supervise_dir_exist
	ok ( $qmail->_supervise_dir_exist( dir=>'/tmp',name=>'' ), '_supervise_dir_exist' );
	ok ( ! $qmail->_supervise_dir_exist( dir=>'/var/thingymadowhakker',name=>'',debug=>0 ), '_supervise_dir_exist' );


# build_pop3_run
	if ( -d $conf->{'qmail_supervise'} && -d $conf->{'vpopmail_home_dir'} ) {

		ok ( $qmail->build_pop3_run( conf=>$conf, file=>"/tmp/mt-pop3-run", debug=>0), 
			'build_pop3_run');

		#ok ( ! $qmail->build_pop3_run( con=>$conf, file=>"/tmp/mt-pop3-run", debug=>0),
		#	'build_pop3_run');
		#ok ( ! $qmail->build_pop3_run( conf=>$conf, fil=>"/tmp/mt-pop3-run", debug=>0),
		#	'build_pop3_run');

# build_send_run
		ok ( $qmail->build_send_run( conf=>$conf, file=>"/tmp/mt-send-run", debug=>0),
			'build_send_run');

		# only run these tests if vpopmail is installed

# build_smtp_run
		ok ( $qmail->build_smtp_run( 
			conf=>$conf, file=>"/tmp/mt-smtp-run", debug=>0, fatal=>0
			), 'build_smtp_run');

# build_submit_run
		ok ( $qmail->build_submit_run( 
			conf=>$conf, file=>"/tmp/mt-submit-run", debug=>0, fatal=>0
			), 'build_submit_run');
	};

# check_control
	my $qmail_dir = $conf->{'qmail_dir'} || "/var/qmail";
	my $qmail_control_dir = $qmail_dir . "/control";

	if ( -d $qmail_control_dir ) {
		ok ( $qmail->check_control( dir=> $qmail_control_dir, debug=>0 ) , 'check_control' );
		ok ( ! $qmail->check_control( dir=>"/should-not-exist", debug=>0 ) , 'check_control' );
	};


# check_rcpthosts
	# only run the test if the files exist
	if ( -s "$qmail_control_dir/rcpthosts" && -s $qmail_dir . '/users/assign' ) {
		ok ( $qmail->check_rcpthosts, 'check_rcpthosts');
	};


# config
	# 
	ok ( $qmail->config( conf=>$conf,test_ok=>1 ), 'config' );
	ok ( ! $qmail->config( conf=>$conf,test_ok=>0 ), 'config' );


# control_create
	ok ( $qmail->control_create( conf=>$conf,test_ok=>1 ), 'control_create' );
	ok ( ! $qmail->control_create( conf=>$conf,test_ok=>0 ), 'control_create' );
	

# get_domains_from_assign
	ok ( $qmail->get_domains_from_assign( test_ok=>1 ), 'get_domains_from_assign');
	ok ( ! $qmail->get_domains_from_assign( test_ok=>0 ), 'get_domains_from_assign');


# install_qmail
	ok ( $qmail->install_qmail( conf=>$conf, test_ok=>1 ), 'install_qmail');
	ok ( ! $qmail->install_qmail( conf=>$conf, test_ok=>0 ), 'install_qmail');


# install_qmail_control_files
	ok ( $qmail->install_qmail_control_files( conf=>$conf, fatal=>0, debug=>0, test_ok=>1), 'install_qmail_control_files');
	ok ( ! $qmail->install_qmail_control_files( conf=>$conf, fatal=>0, debug=>0, test_ok=>0), 'install_qmail_control_files');


# install_qmail_groups_users
	ok ( $qmail->install_qmail_groups_users( conf=>$conf, test_ok=>1), 'install_qmail_groups_users');
	ok ( ! $qmail->install_qmail_groups_users( conf=>$conf, test_ok=>0), 'install_qmail_groups_users');


# install_supervise_run
	ok ( $qmail->install_supervise_run( tmpfile=>'/tmp/foo', test_ok=>1 ), 'install_supervise_run');
	ok ( ! $qmail->install_supervise_run( tmpfile=>'/tmp/foo', test_ok=>0 ), 'install_supervise_run');


# install_qmail_control_log_files
	ok ( $qmail->install_qmail_control_log_files( conf=>$conf, test_ok=>1 ), 'install_qmail_control_log_files');
	ok ( ! $qmail->install_qmail_control_log_files( conf=>$conf, test_ok=>0 ), 'install_qmail_control_log_files');


# netqmail
	ok ( $qmail->netqmail( conf=>$conf, debug=>0, test_ok=>1  ), 'netqmail');
	ok ( ! $qmail->netqmail( conf=>$conf, debug=>0, test_ok=>0 ), 'netqmail');


# netqmail_virgin
	ok ( $qmail->netqmail_virgin( conf=>$conf, debug=>0, test_ok=>1  ), 'netqmail_virgin');
	ok ( ! $qmail->netqmail_virgin( conf=>$conf, debug=>0, test_ok=>0 ), 'netqmail_virgin');

# queue_check
	if ( -d $qmail_dir ) {
		ok ( $qmail->queue_check( conf=>$conf, debug=>0 ), 'queue_check');
	};

# queue_process

# rebuild_ssl_temp_keys
	if ( -d $qmail_control_dir ) {
		ok ( $qmail->rebuild_ssl_temp_keys( conf=>$conf, debug=>0, fatal=>0, test_ok=>1 ), 'rebuild_ssl_temp_keys');
	}


# restart
	if ( -d $send ) {
		ok ( $qmail->restart( conf=>$conf, debug=>0, test_ok=>1 ), 'restart');
	};

# supervise_dir_get 
    my $qcontrol = $qmail->supervise_dir_get( conf=>$conf, prot=>"send", debug=>0 );
	ok ( $qcontrol, 'supervise_dir_get');
    

	if ( $toaster->supervised_dir_test( conf=>$conf, prot=>"send", debug=>0 ) ) {

# send_start
        ok ( $qmail->send_start( conf=>$conf, test_ok=>1, debug=>0, fatal=>0 ) , 'send_start');

# send_stop
        ok ( $qmail->send_stop( conf=>$conf, test_ok=>1, debug=>0, fatal=>0 ) , 'send_start');

	}
	

# smtpd_restart
	if ( $toaster->supervised_dir_test( conf=>$conf, prot=>"smtp", debug=>0 ) ) {
		ok ( $qmail->smtpd_restart( conf=>$conf, prot=>"smtp", fatal=>0 ), 'smtpd_restart');
	};


# smtp_set_qmailqueue
	if ( -d $qmail_dir ) {
		my $before = $conf->{'filtering_method'};
		$conf->{'filtering_method'} = "smtp";
		ok ( $qmail->smtp_set_qmailqueue( conf=>$conf, debug=>0 ), 'smtp_set_qmailqueue');
	
		$conf->{'filtering_method'} = "user";
		ok ( ! $qmail->smtp_set_qmailqueue( conf=>$conf, debug=>0 ), 'smtp_set_qmailqueue');

		$conf->{'filtering_method'} = $before;


# _test_smtpd_config_values
        if ( -d $conf->{'vpopmail_home_dir'} ) {
		    ok ( $qmail->_test_smtpd_config_values( conf=>$conf, debug=>0, fatal=>0, test_ok=>1 ), 
		    	'_test_smtpd_config_values');
        };
	};

# _smtp_sanity_tests
	ok ( $qmail->_smtp_sanity_tests( conf=>$conf ), '_smtp_sanity_tests');


