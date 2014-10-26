#!/usr/bin/perl
#
# $Id: Logs.t,v 5.00 matt Exp $
#
use strict;
use warnings;
use Cwd;
use English qw( -no_match_vars );
use Test::More 'no_plan';

use lib "lib";

BEGIN {
    use_ok('Mail::Toaster::Logs');
    use_ok('Mail::Toaster::Utility');
}
require_ok('Mail::Toaster::Logs');

my $utility = Mail::Toaster::Utility->new;
my $conf = $utility->parse_config( file=>"toaster.conf", debug=>0 );

# basic OO mechanism
my $log = Mail::Toaster::Logs->new(conf=>$conf);    # create an object
ok( defined $log, 'get Mail::Toaster::Logs object' );
ok( $log->isa('Mail::Toaster::Logs'), 'check object class' );


# report_yesterdays_activity
    # only run the test if qmailanalog is installed
SKIP: {
    skip "report_yesterdays_activity: qmailanalog must be installed", 
        1 unless -d $conf->{'qmailanalog_bin'};
    ok( $log->report_yesterdays_activity(test_ok=>1), 
        'report_yesterdays_activity');
}

# verify_settings
    eval {
        # this will certainly fail before Mail::Toaster is installed
        $log->verify_settings;
    };
    if ( ! $EVAL_ERROR ) {
        ok( $log->verify_settings(), 'verify_settings');
    };


# parse_cmdline_flags
    ok( $log->parse_cmdline_flags(prot=>"test"), 'parse_cmdline_flags');


# set_countfile
    ok( $log->set_countfile(prot=>"imap"), 'set_countfile');
    cmp_ok( 
    $log->set_countfile(prot=>"imap"), 'eq', "/var/log/mail/counters/imap.txt", 
        'set_countfile imap');

# rbl_count
    #skip "rbl_count, needs root permissions", 1 if ( $UID != 0 );
    require Mail::Toaster::Perl;
    my $perl = Mail::Toaster::Perl->new();
    if ( $perl->has_module("Date::Format") ) {
        ok( $log->rbl_count(), 'rbl_count');
    };

# smtp_auth_count
    if ( $UID == 0 ) {
        ok( $log->smtp_auth_count(), 'smtp_auth_count');
    };


# send_count
    if ( $perl->has_module("Date::Format") ) {
        ok( $log->send_count(), 'send_count');
    };


# imap_count
    if ( $UID == 0 ) {
        ok( $log->imap_count(debug=>0), 'imap_count');


# pop3_count
        ok( $log->pop3_count(debug=>0), 'pop3_count');


# webmail_count
        ok( $log->webmail_count(), 'webmail_count');


# spama_count
        ok( $log->spama_count(), 'spama_count');
    };


# qms_count
    ok( $log->qms_count(), 'qms_count');


###### start of STDIN subs #######
# these subs expect to recieve log files via STDIN, so they will hang if
# called from this test script.
    # roll_send_logs
        #ok( $log->roll_send_logs(), 'roll_send_logs');

    # roll_rbl_logs
        #ok( $log->roll_rbl_logs(), 'roll_rbl_logs');

    # roll_pop3_logs
        #ok( $log->roll_pop3_logs(), 'roll_pop3_logs');
###### end of STDIN subs ########

# compress_yesterdays_logs
    if ( $perl->has_module("Date::Format") ) {
        ok( $log->compress_yesterdays_logs( file=>"sendlog" ), 'compress_yesterdays_logs');

# purge_last_months_logs
        ok( $log->purge_last_months_logs(), 'purge_last_months_logs');
    };

# rotate_supervised_logs
    if ( $UID != 0 ) {
        ok( ! $log->rotate_supervised_logs(), 'rotate_supervised_logs');
    } 
    else {
        ok( $log->rotate_supervised_logs(), 'rotate_supervised_logs');
    }

# check_log_files
    is_deeply( [], $log->check_log_files( [] ), 'check_log_files empty');

    if ( $OSNAME eq "darwin" ) {
        is_deeply ( 
            ["/var/log/system.log"], 
            $log->check_log_files( ["/var/log/system.log"] ),
            'check_log_files system'
        );

        is_deeply ( 
            ["/var/log/mail.log"],
            $log->check_log_files( ["/var/log/mail.log"] ), 
            'check_log_files mail',
        );
    }


# process_pop3_logs
    ok( $log->process_pop3_logs(), 'process_pop3_logs');

# process_rbl_logs
    ok( $log->process_rbl_logs(), 'process_rbl_logs');

# count_rbl_line
    ok( !$log->count_rbl_line(), 'count_rbl_line');
    ok( $log->count_rbl_line( 
        '@40000000450b2d2e1529cb14 rblsmtpd: 216.55.155.54 pid 93340: 451 '
        . 'http://www.spamhaus.org/query/bl?ip=216.55.155.54'
    ), 'count_rbl_line');

# process_send_logs
    ok( $log->process_send_logs(), 'process_send_logs');


# count_send_line
    ok( ! $log->count_send_line(), 'count_send_line');
    ok( $log->count_send_line('@40000000450c020b32315f74 new msg 71198'), 'count_send_line');


    my $countfile = $log->set_countfile(prot=>"pop3");
# counter_read
    my ( $path, $file ) = $utility->path_parse($countfile);
    if ( -w $path ) {
        ok( $log->counter_read(file=>$countfile, debug=>0), 'counter_read');
    }
    else {
        if ( -e $countfile ) {
            ok( $log->counter_read(file=>$countfile, debug=>0), 'counter_read');
        };
        $countfile = $log->set_countfile(prot=>"blop3");
        ok( ! $log->counter_read(file=>$countfile, debug=>0), 'counter_read');
    }


# counter_write
    $countfile = $log->set_countfile(prot=>"pop3");
    if ( -w $countfile ) {
        ok( $log->counter_write( 
            values=> {matt=>1,bob=>2}, 
            log   => $countfile, 
            fatal => 0,
        ), 'counter_write');
    };


ok( $log->what_am_i(), 'what_am_i' );
cmp_ok( $log->what_am_i(), "eq", "Logs.t", 'what_am_i' );

ok( $log->syslog_locate(), 'syslog_locate' );


1;

__END__;

