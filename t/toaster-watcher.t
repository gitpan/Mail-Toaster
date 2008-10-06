#!/usr/bin/perl
#
# Before `make install' is performed this script is runnable with `make test'.
#
use strict;
use warnings;
use Cwd;
use English qw( -no_match_vars );
use Test::More 'no_plan';

use lib "inc";
use lib "lib";

my $network++;
my $deprecated = 0;    # run the deprecated tests.
my $r;
my $initial_working_directory = cwd;

BEGIN {
    use_ok('Mail::Toaster');
    use_ok('Mail::Toaster::Utility');
    use_ok('Mail::Toaster::Qmail');
    use_ok('Mail::Toaster::DNS');
    use_ok('Mail::Toaster::Setup');

}
require_ok('Mail::Toaster');
require_ok('Mail::Toaster::Utility');
require_ok('Mail::Toaster::Qmail');

# let the testing begin

# basic OO mechanism
my $toaster = Mail::Toaster->new;    # create an object
ok( defined $toaster, 'get Mail::Toaster object' );    # check it
ok( $toaster->isa('Mail::Toaster'), 'check object class' );    # is it the right

my $util = Mail::Toaster::Utility->new;
my $qmail   = Mail::Toaster::Qmail->new;

my $conf = $util->parse_config( file => "toaster-watcher.conf", debug => 0 );
ok( $conf, 'parse_config' );

my $setup   = Mail::Toaster::Setup->new(conf=>$conf);

my $clean = 1;

# only run these tests on installed toasters
if (   !-w "/tmp"
    || !-d $conf->{'qmail_dir'}
    || !-d $conf->{'qmail_supervise'} )
{
    exit 0;
}

# build a pop3/run file in /tmp
my $file = "/tmp/pop3.txt";
$r = $qmail->build_pop3_run( file => $file, debug => 0 );
if ($r) {
    ok( $r, 'build_pop3_run' );
    ok(
        $qmail->install_supervise_run(
            tmpfile => $file,
            prot    => "pop3",
            test_ok => 1,
        ),
        'install pop3/run'
    );
}

# build a submit/run file in /tmp
$file = "/tmp/submit.txt";
$r = $qmail->build_submit_run( file => $file, debug => 0, fatal=>0 );
if ($r) {
    ok( $r, 'build_submit_run' );
    ok(
        $qmail->install_supervise_run(
            tmpfile => $file,
            prot    => "submit",
            test_ok => 1,
        ),
        'install submit/run'
    );
}

# build a send/run file in /tmp
$file = "/tmp/send.txt";
$r = $qmail->build_send_run( file => $file, debug => 0, fatal=>0 );
if ($r) {
    ok( $r, 'build_send_run' );
    ok(
        $qmail->install_supervise_run(
            tmpfile => $file,
            prot    => "send",
            fatal   => 0,
            debug   => 0,
            test_ok => 1,
        ),
        'install send/run'
    );
}

# build a smtp/run file in /tmp
$file = "/tmp/smtp.txt";
$r = $qmail->build_smtp_run( file => $file, debug => 0, fatal=>0 );
if ($r) {
    ok( $r, 'build_smtp_run' );
    ok(
        $qmail->install_supervise_run(
            tmpfile => $file,
            prot    => "smtp",
            fatal   => 0,
            debug   => 0,
            test_ok => 1,
        ),
        'installed smtp/run'
    );
}

# build a * /log/run file in /tmp
ok(
    $qmail->install_qmail_control_log_files(
        debug   => 0,
        test_ok => 1,
    ),
    'created supervise/*/log/run'
);

# test the supervised directories
if ( $toaster->supervised_dir_test( prot => "smtp", debug => 0 ) ) {
    ok(
        $toaster->supervised_dir_test( prot => "smtp", debug => 0 ),
        'dir supervise/smtp'
    );
    ok(
        $toaster->supervised_dir_test( prot => "send", debug => 0 ),
        'dir supervise/send'
    );
    ok(
        $toaster->supervised_dir_test( prot => "pop3", debug => 0 ),
        'dir supervise/pop3'
    );
    ok(
        $toaster->supervised_dir_test( prot  => "submit", debug => 0,),
        'dir supervise/submit'
    );
};

ok( $setup->startup_script( debug => 0, test_ok=>1 ), 'startup_script' );

ok( $toaster->service_symlinks( debug=>0 ), 'service_symlinks' );

ok( chdir($initial_working_directory), 'reset working directory' );
