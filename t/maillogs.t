#!/usr/bin/perl
#
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'
#
#
# $Id: Utility.t,v 4.3 2006/06/09 19:26:18 matt Exp $
#
use strict;
use warnings;
use English qw( -no_match_vars );

use Test::More 'no_plan';

use lib "lib";

my $mod = "Date::Parse";
unless (eval "require $mod" && -w "/var/log/mail")
{
	exit;
}

BEGIN { use_ok( 'Mail::Toaster::Utility' ); };
require_ok( 'Mail::Toaster::Utility' );

# basic OO mechanism
	my $utility = Mail::Toaster::Utility->new;                       # create an object
	ok ( defined $utility, 'get Mail::Toaster::Utility object' );    # check it
	ok ( $utility->isa('Mail::Toaster::Utility'), 'check object class' );

my $maillogs_location = "bin/maillogs";

ok( -e $maillogs_location, 'found maillogs');
ok( -x $maillogs_location, 'is executable');

unless ( -d "/var/log/mail/counters" &&
         -s "/var/log/mail/counters/webmail.txt" ) {
    exit;
};


my @log_types = qw( smtp send rbl imap pop3 webmail spamassassin );

foreach my $type (@log_types) {
    if ( $UID == 0 ) {
        ok( $utility->syscmd(
                command => "$maillogs_location $type",
                fatal   => 0,
                debug   => 0,
            ), "maillogs $type",
        );
    }
    else {
        ok( ! $utility->syscmd(
                command => "$maillogs_location -a list -s matt -h From ",
                fatal => 0,
                debug => 0,
            ), "maillogs $type",
        );
    }
}
