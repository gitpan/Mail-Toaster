#!perl
use strict;
use warnings;

use Cwd;
use English qw( -no_match_vars );
use Test::More 'no_plan';

use lib 'lib';

BEGIN {
    use_ok('Mail::Toaster');
}
require_ok('Mail::Toaster');

my $toaster = Mail::Toaster->new(debug=>0);
ok( defined $toaster, 'get Mail::Toaster object' );
ok( $toaster->isa('Mail::Toaster'), 'check object class' );
my $conf = $toaster->get_config();
ok( ref $conf, 'get_config');

my $util = my $log = $toaster->get_util;

# audit
$log->dump_audit( quiet => 1);
$log->audit("line one");
#$toaster->dump_audit();
$log->audit("line two");
$log->audit("line three");
$log->dump_audit( quiet=>1);

# check
ok( $toaster->check( debug => 0, test_ok=> 1 ), 'check' );

if ( $UID == 0 ) {

# learn_mailboxes
    if ( -d $conf->{'qmail_log_base'} ) {
        ok( $toaster->learn_mailboxes( 
            fatal => 0,
            test_ok => 1, 
        ), 'learn_mailboxes +' );

# clean_mailboxes
        ok( $toaster->clean_mailboxes( test_ok=>1, fatal => 0 ),
            'clean_mailboxes +' );
    }
    else {
        # these should fail if the toaster logs are not set up yet
        ok( ! $toaster->clean_mailboxes( fatal => 0 ),
            'clean_mailboxes -' );

        ok( ! $toaster->learn_mailboxes( 
            fatal => 0,
            test_ok => 0, 
        ), 'learn_mailboxes -' );
    }
}

# maildir_clean_spam
ok( !$toaster->maildir_clean_spam( path => '/home/domains/fake.com/user' ),
    'maildir_clean_spam'
);

# get_maildir_paths
my $qdir   = $conf->{'qmail_dir'};
my $assign = "$qdir/users/assign";
my $assign_size = -s $assign;

my $r = $toaster->get_maildir_paths( fatal => 0 );
if ( -r $assign && $assign_size > 10 ) { ok( $r, 'get_maildir_paths' );  }
else                                   { ok( !$r, 'get_maildir_paths' ); };

# maildir_clean_trash
ok(
    !$toaster->maildir_clean_trash( path => '/home/example.com/user',),
    'maildir_clean_trash'
);

# maildir_clean_sent
ok(
    !$toaster->maildir_clean_sent( path => '/home/example.com/user',),
    'maildir_clean_sent'
);

# maildir_clean_new
ok(
    !$toaster->maildir_clean_new( path => '/home/example.com/user',),
    'maildir_clean_new'
);

# maildir_clean_ham
ok( !$toaster->maildir_clean_ham( path => '/home/example.com/user',),
        'maildir_clean_ham'
);

# service_dir_create
ok( $toaster->service_dir_create( fatal => 0, test_ok => 1 ),
    'service_dir_create' );

# service_dir_test
if ( -d "/var/service" ) {
    ok( $toaster->service_dir_test(), 'service_dir_test' );
}

# supervise_dir_get 
ok ( $toaster->supervise_dir_get( prot=>"send" ), 'supervise_dir_get');


# supervise_dirs_create
ok( $toaster->supervise_dirs_create( test_ok => 1 ), 'supervise_dirs_create' );

$log->dump_audit(quiet => 1);

# supervised_dir_test
ok(
    $toaster->supervised_dir_test( prot => 'smtp', test_ok => 1,),
    'supervised_dir_test smtp'
);

ok(
    $toaster->supervised_dir_test( prot => 'submit', test_ok => 1,),
    'supervised_dir_test submit'
);

ok(
    $toaster->supervised_dir_test( prot => 'send', test_ok => 1,),
    'supervised_dir_test send'
);

# check_processes
ok( $toaster->check_processes( test_ok=> 1), 'check_processes' );

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

$log->dump_audit(quiet=>1);
my $setuidgid = $util->find_bin( "setuidgid", fatal=>0, debug=>0 );
foreach ( qw/ smtpd pop3 submit / ) {

# supervised_hostname
    ok( $toaster->supervised_hostname( prot => $_ ), 
        "supervised_hostname $_" );

# supervised_multilog
    if ( $setuidgid ) {
        ok( $toaster->supervised_multilog( prot => $_, fatal=>0 ),
            "supervised_multilog $_"
        );
    };

# supervised_log_method
    ok( $toaster->supervised_log_method( prot => $_ ), 
        "supervised_log_method $_");
};


# supervise_restart
    # we do not want to try this during testing.

# supervised_tcpserver
    # this test would fail unless on a built toaster.
