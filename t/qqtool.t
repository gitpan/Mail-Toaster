#!/usr/bin/perl
#
use strict;
use warnings;
use English qw( -no_match_vars );


use Test::More 'no_plan';
#use Smart::Comments;

use lib "lib";

BEGIN { use_ok( 'Mail::Toaster::Utility' ); };
require_ok( 'Mail::Toaster::Utility' );

# basic OO mechanism
	my $utility = Mail::Toaster::Utility->new;
	ok ( defined $utility, 'get Mail::Toaster::Utility object' );
	ok ( $utility->isa('Mail::Toaster::Utility'), 'check object class' );

my $conf = $utility->parse_config( file => "toaster-watcher.conf", debug => 0 );

my $qqtool_location = "bin/qqtool.pl";

ok( -e $qqtool_location, 'found qqtool.pl');
ok( -x $qqtool_location, 'is executable');

my $queue = $conf->{'qmail_dir'} . "/queue";

### $queue
### require: -d $queue
### require: -r $queue

ok( $utility->syscmd(
        command => "$qqtool_location -a list -s matt -h From ",
        fatal   => 0,
        debug   => 0,
    ), 'qqtool.pl' );
