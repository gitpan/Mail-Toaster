#!perl

use strict;
#use warnings;

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
my $qmail = Mail::Toaster::Qmail->new;
ok ( defined $qmail, 'get Mail::Toaster::Qmail object' );
ok ( $qmail->isa('Mail::Toaster::Qmail'), 'check object class' );

# many of the subs expect this to be passed to them
my $toaster = Mail::Toaster->new;
my $util = Mail::Toaster::Utility->new;
my $conf = $util->parse_config( file=>"toaster-watcher.conf", debug=>0 );

my $r;
my $has_net_dns;


# get_list_of_rwls
    $qmail->_set_config( { 'rwl_list.dnswl.org'=> 1} );
	$r = $qmail->get_list_of_rwls(debug=>0 );
	ok ( @$r[0], 'get_list_of_rwls'); 
    $qmail->_set_config( $conf );

# test_each_rbl
    $r = $qmail->test_each_rbl( rbls=>$r, debug=>0, fatal=>0 );
    ok ( @$r[0], 'test_each_rbl'); 


# get_list_of_rbls
    $qmail->_set_config( {'rbl_sbl-xbl.spamhaus.org'=> 1} );
	$r = $qmail->get_list_of_rbls(debug=>0,fatal=>0 );
	cmp_ok ( $r, "eq", '\
		-r sbl-xbl.spamhaus.org ', 'get_list_of_rbls'); 

	# test one with a sort order
    $qmail->_set_config( {'rbl_sbl-xbl.spamhaus.org'=> 2} );
	$r = $qmail->get_list_of_rbls( debug=>0, fatal=>0 );
	cmp_ok ( $r, "eq", '\
		-r sbl-xbl.spamhaus.org ', 'get_list_of_rbls'); 

	# no enabled rbls!
    $qmail->_set_config( {'rbl_sbl-xbl.spamhaus.org'=> 0} );
	ok ( ! $qmail->get_list_of_rbls( debug=>0, fatal=>0 ), 
        'get_list_of_rbls nok');
	#cmp_ok ( $r, "eq", "", 'get_list_of_rbls nok');

	# ignore custom error messages
    $qmail->_set_config( {'rbl_sbl-xbl.spamhaus.org_message'=> 2} );
	$r = $qmail->get_list_of_rbls( debug=>0, fatal=>0 );
	ok ( ! $r, 'get_list_of_rbls nok');


# get_list_of_rwls
    $qmail->_set_config( {'rwl_list.dnswl.org'=> 1} );
	$r = $qmail->get_list_of_rwls( debug=>0 );
	ok ( @$r[0] eq "list.dnswl.org", 'get_list_of_rwls'); 

	# no enabled rwls!
    $qmail->_set_config( {'rwl_list.dnswl.org'=> 0} );
	$r = $qmail->get_list_of_rwls( debug=>0 );
	ok ( ! @$r[0], 'get_list_of_rwls nok');


# service_dir_get
	# a normal smtp invocation
    $qmail->_set_config( {qmail_service_smtp=>'/var/service/smtp'} );
	$r = $qmail->service_dir_get( prot=>"smtp", debug=>0 );
	ok ( $r eq "/var/service/smtp", 'service_dir_get smtp');

	# a normal invocation with a conf file shortcut
    $qmail->_set_config( {qmail_service_smtp=>'qmail_service/smtp'} );
	$r = $qmail->service_dir_get( prot=>"smtp", debug=>0 );
	ok ( $r eq "/var/service/smtp", 'service_dir_get smtp');

	# a deprecated invocation
    $qmail->_set_config( {qmail_service_smtp=>'qmail_service/smtp'} );
	$r = $qmail->service_dir_get( prot=>"smtpd", debug=>0 );
	ok ( $r eq "/var/service/smtp", 'service_dir_get smtp');

	# a normal send invocation
    $qmail->_set_config( {qmail_service_send=>'/var/service/send'} );
	my $send = $qmail->service_dir_get( prot=>"send", debug=>0 );
	ok ( $send eq "/var/service/send", 'service_dir_get send');

	# a normal pop3 invocation
    $qmail->_set_config( {qmail_service_pop3=>'/var/service/pop3'} );
	$r = $qmail->service_dir_get( prot=>"pop3", debug=>0 );
	ok ( $r eq "/var/service/pop3", 'service_dir_get pop3');

	# an invalid protocol
    $qmail->_set_config( {qmail_service_pop3=>'/var/service/invalid'} );
	$r = $qmail->service_dir_get( prot=>"invalid", fatal=>0, debug=>0 );
	ok ( ! $r , 'service_dir_get invalid');

$qmail->_set_config( $conf );

# _set_checkpasswd_bin
	# this test will only succeed on a fully installed toaster
	if ( -d $conf->{'vpopmail_home_dir'} ) {
		ok ( $qmail->_set_checkpasswd_bin( prot=>"pop3", debug=>0, fatal=>0 ), 
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

		ok ( $qmail->build_pop3_run( file=>"/tmp/mt-pop3-run", debug=>0), 
			'build_pop3_run');

		#ok ( ! $qmail->build_pop3_run( file=>"/tmp/mt-pop3-run", debug=>0),
		#	'build_pop3_run');
		#ok ( ! $qmail->build_pop3_run( fil=>"/tmp/mt-pop3-run", debug=>0),
		#	'build_pop3_run');

# build_send_run
		ok ( $qmail->build_send_run( file=>"/tmp/mt-send-run", debug=>0),
			'build_send_run');

		# only run these tests if vpopmail is installed

# build_smtp_run
		ok ( $qmail->build_smtp_run( 
			file=>"/tmp/mt-smtp-run", debug=>0, fatal=>0
			), 'build_smtp_run');

# build_submit_run
		ok ( $qmail->build_submit_run( 
			file=>"/tmp/mt-submit-run", debug=>0, fatal=>0
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
	ok ( $qmail->config( test_ok=>1 ), 'config' );
	ok ( ! $qmail->config( test_ok=>0 ), 'config' );


# control_create
	ok ( $qmail->control_create( test_ok=>1 ), 'control_create' );
	ok ( ! $qmail->control_create( test_ok=>0 ), 'control_create' );
	

# get_domains_from_assign
	ok ( $qmail->get_domains_from_assign( test_ok=>1 ), 'get_domains_from_assign');
	ok ( ! $qmail->get_domains_from_assign( test_ok=>0 ), 'get_domains_from_assign');


# install_qmail
	ok ( $qmail->install_qmail( test_ok=>1 ), 'install_qmail');
	ok ( ! $qmail->install_qmail( test_ok=>0 ), 'install_qmail');


# install_qmail_control_files
	ok ( $qmail->install_qmail_control_files( fatal=>0, debug=>0, test_ok=>1), 'install_qmail_control_files');
	ok ( ! $qmail->install_qmail_control_files( fatal=>0, debug=>0, test_ok=>0), 'install_qmail_control_files');


# install_qmail_groups_users
	ok ( $qmail->install_qmail_groups_users( test_ok=>1), 'install_qmail_groups_users');
	ok ( ! $qmail->install_qmail_groups_users( test_ok=>0), 'install_qmail_groups_users');


# install_supervise_run
	ok ( $qmail->install_supervise_run( tmpfile=>'/tmp/foo', test_ok=>1 ), 'install_supervise_run');
	ok ( ! $qmail->install_supervise_run( tmpfile=>'/tmp/foo', test_ok=>0 ), 'install_supervise_run');


# install_qmail_control_log_files
	ok ( $qmail->install_qmail_control_log_files( test_ok=>1 ), 'install_qmail_control_log_files');
	ok ( ! $qmail->install_qmail_control_log_files( test_ok=>0 ), 'install_qmail_control_log_files');


# netqmail
	ok ( $qmail->netqmail( debug=>0, test_ok=>1  ), 'netqmail');
	ok ( ! $qmail->netqmail( debug=>0, test_ok=>0 ), 'netqmail');


# netqmail_virgin
	ok ( $qmail->netqmail_virgin( debug=>0, test_ok=>1  ), 'netqmail_virgin');
	ok ( ! $qmail->netqmail_virgin( debug=>0, test_ok=>0 ), 'netqmail_virgin');

# queue_check
	if ( -d $qmail_dir ) {
		ok ( $qmail->queue_check( debug=>0 ), 'queue_check');
	};

# queue_process

# rebuild_ssl_temp_keys
	if ( -d $qmail_control_dir ) {
		ok ( $qmail->rebuild_ssl_temp_keys( debug=>0, fatal=>0, test_ok=>1 ), 'rebuild_ssl_temp_keys');
	}


# restart
	if ( -d $send ) {
		ok ( $qmail->restart( debug=>0, test_ok=>1 ), 'restart');
	};

# supervise_dir_get 
    my $qcontrol = $qmail->supervise_dir_get( prot=>"send", debug=>0 );
	ok ( $qcontrol, 'supervise_dir_get');
    
	if ( $toaster->supervised_dir_test( prot=>"send", debug=>0 ) ) {

# send_start
        ok ( $qmail->send_start( test_ok=>1, debug=>0, fatal=>0 ) , 'send_start');

# send_stop
        ok ( $qmail->send_stop( test_ok=>1, debug=>0, fatal=>0 ) , 'send_start');

	}
	

# smtpd_restart
	if ( $toaster->supervised_dir_test( prot=>"smtp", debug=>0 ) ) {
		ok ( $qmail->smtpd_restart( prot=>"smtp", fatal=>0 ), 'smtpd_restart');
	};


# smtp_set_qmailqueue
	if ( -d $qmail_dir ) {

        $qmail->_set_config( { 'filtering_method' => 'smtp'} );
		ok ( $qmail->smtp_set_qmailqueue( debug=>0 ), 'smtp_set_qmailqueue');
	
        $qmail->_set_config( { 'filtering_method' => 'user'} );
		$conf->{'filtering_method'} = "user";
		ok ( ! $qmail->smtp_set_qmailqueue( debug=>0 ), 'smtp_set_qmailqueue');
        $qmail->_set_config( $conf );

# _test_smtpd_config_values
        if ( -d $conf->{'vpopmail_home_dir'} ) {
		    ok ( $qmail->_test_smtpd_config_values( debug=>0, fatal=>0, test_ok=>1 ), 
		    	'_test_smtpd_config_values');
        };
	};

# _smtp_sanity_tests
	ok ( $qmail->_smtp_sanity_tests(), '_smtp_sanity_tests');


