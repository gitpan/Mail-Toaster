#!perl
use strict;
use warnings;

use Cwd;
use English qw( -no_match_vars );
use Test::More 'no_plan';

use lib "lib";

BEGIN {
    use_ok('Mail::Toaster');
    use_ok('Mail::Toaster::Utility');
}
require_ok('Mail::Toaster');
require_ok('Mail::Toaster::Utility');


# basic OO mechanism
my $toaster = Mail::Toaster->new;
ok( defined $toaster, 'get Mail::Toaster object' );
ok( $toaster->isa('Mail::Toaster'), 'check object class' );

my $util = Mail::Toaster::Utility->new;
ok( defined $util, 'get Mail::Toaster::Utility object' );
ok( $util->isa('Mail::Toaster::Utility'), 'check object class' );

# parse_config
my $conf = $util->parse_config( file => "toaster-watcher.conf", debug => 0 );
ok( $conf, 'parse_config' );

# toaster_check
ok( $toaster->toaster_check( debug => 0 ), 'toaster_check' );

if ( $UID == 0 ) {

# learn_mailboxes
    if ( -d $conf->{'qmail_log_base'} ) {
        ok( $toaster->learn_mailboxes( 
            fatal => 0,
            test_ok => 1, 
        ), 'learn_mailboxes' );

# clean_mailboxes
        ok( $toaster->clean_mailboxes( test_ok=>1, fatal => 0 ),
            'clean_mailboxes' );
    }
    else {
        # these should fail if the toaster logs are not set up yet
        ok( ! $toaster->clean_mailboxes( fatal => 0 ),
            'clean_mailboxes' );

        ok( ! $toaster->learn_mailboxes( 
            fatal => 0,
            test_ok => 0, 
        ), 'learn_mailboxes' );
    }
}

# maildir_clean_spam
ok(
    !$toaster->maildir_clean_spam(
        path  => '/home/domains/example.com/user',
        debug => 0,
    ),
    'maildir_clean_spam'
);

# get_maildir_paths
my $qdir   = $conf->{'qmail_dir'};
my $assign = "$qdir/users/assign";
my $assign_size = -s $assign;

if ( -r $assign && $assign_size > 10 ) {
    ok( $toaster->get_maildir_paths( fatal => 0 ),
        'get_maildir_paths' );
}
else {
    ok( !$toaster->get_maildir_paths( fatal => 0 , debug=>0 ),
        'get_maildir_paths' );
}

# maildir_learn_spam
ok(
    !$toaster->maildir_learn_spam(
        path  => '/home/example.com/user',
        debug => 0,
    ),
    'maildir_learn_spam'
);

# maildir_clean_trash
ok(
    !$toaster->maildir_clean_trash(
        path => '/home/example.com/user',
    ),
    'maildir_clean_trash'
);

# maidir_clean_sent
ok(
    !$toaster->maidir_clean_sent(
        path => '/home/example.com/user',
    ),
    'maidir_clean_sent'
);

# maildir_clean_new
ok(
    !$toaster->maildir_clean_new(
        path => '/home/example.com/user',
    ),
    'maildir_clean_new'
);

# maildir_clean_ham
ok(
    !$toaster->maildir_clean_ham(
        path => '/home/example.com/user',
    ),
    'maildir_clean_ham'
);

# maildir_learn_ham
ok(
    !$toaster->maildir_learn_ham(
        path => '/home/example.com/user',
    ),
    'maildir_learn_ham'
);

# service_dir_create
ok( $toaster->service_dir_create( fatal => 0, test_ok => 1 ),
    'service_dir_create' );

# service_dir_test
if ( -d "/var/service" ) {
    ok( $toaster->service_dir_test(), 'service_dir_test' );
}

# supervise_dirs_create
ok( $toaster->supervise_dirs_create( debug => 0, test_ok => 1 ),
    'supervise_dirs_create' );

# supervised_dir_test
ok(
    $toaster->supervised_dir_test(
        prot    => 'smtp',
        test_ok => 1,
        debug   => 0
    ),
    'supervised_dir_test smtp'
);

ok(
    $toaster->supervised_dir_test(
        prot    => 'submit',
        test_ok => 1,
        debug   => 0
    ),
    'supervised_dir_test submit'
);

ok(
    $toaster->supervised_dir_test(
        prot    => 'send',
        test_ok => 1,
        debug   => 0
    ),
    'supervised_dir_test send'
);

# test_processes
ok( $toaster->test_processes( debug => 0 ), 'test_processes' );

# email_send

# email_send_attach

# email_send_clam

# email_send_clean

# email_send_eicar

# email_send_spam

# get_toaster_htdocs
ok( $toaster->get_toaster_htdocs(), 'get_toaster_htdocs' );

# get_toaster_cgibin
ok( $toaster->get_toaster_cgibin(), 'get_toaster_cgibin' );

# supervised_do_not_edit_notice
ok( $toaster->supervised_do_not_edit_notice(),
    'supervised_do_not_edit_notice' );

# supervised_hostname
ok(
    $toaster->supervised_hostname( prot => "smtpd", debug => 0, fatal=>0 ),
    'supervised_hostname smtpd'
);
ok(
    $toaster->supervised_hostname( prot => "pop3", debug => 0, fatal=>0 ),
    'supervised_hostname pop3'
);
ok(
    $toaster->supervised_hostname(
        prot  => "submit",
        debug => 0
    ),
    'supervised_hostname submit'
);

# supervised_multilog
if ( $util->find_the_bin( bin => "setuidgid", debug=>0, fatal=>0 ) ) {
    ok(
        $toaster->supervised_multilog( prot => "smtpd", debug => 0, fatal=>0 ),
        'supervised_multilog smtpd'
    );
    ok(
        $toaster->supervised_multilog( prot => "pop3", debug => 0, fatal=>0 ),
        'supervised_multilog pop3'
    );
    ok(
        $toaster->supervised_multilog(
            prot  => "submit",
            debug => 0, 
            fatal => 0,
        ),
        'supervised_multilog submit'
    );
};

# supervised_log_method
ok(
    $toaster->supervised_log_method( prot => "smtpd", debug => 0 ),
    'supervised_log_method smtpd'
);
ok(
    $toaster->supervised_log_method( prot => "pop3", debug => 0 ),
    'supervised_log_method pop3'
);
ok(
    $toaster->supervised_log_method(
        prot  => "submit",
        debug => 0
    ),
    'supervised_log_method submit'
);


# supervise_restart
    # we do not want to try this during testing.

# supervised_tcpserver
    # this test would fail unless on a built toaster.
