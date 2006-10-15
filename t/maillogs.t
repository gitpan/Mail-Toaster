#!/usr/bin/perl
#
# $Id: $
#
use strict;
use warnings;
use English qw( -no_match_vars );

use Test::More;

use lib "inc";
use lib "lib";

my $mod = "Date::Parse";
unless (eval "require $mod" && -w "/var/log/mail")
{
	Test::More::plan( skip_all => "skipping tests, maillogs not installed yet");
}
plan 'no_plan';

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
