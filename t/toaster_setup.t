#!/usr/bin/perl
use strict;
use warnings;

use Cwd;
use English qw( -no_match_vars );
use Test::More 'no_plan';

use lib "inc";
use lib "lib";

BEGIN { use_ok( 'Mail::Toaster::Utility' ); };
require_ok( 'Mail::Toaster::Utility' );

my $utility = Mail::Toaster::Utility->new;    # create an object

my $setup_location = "bin/toaster_setup.pl";

ok( -e $setup_location, 'found toaster_setup.pl');
ok( -x $setup_location, 'is executable');

#my $wd = cwd; print "wd: $wd\n";
#ok (system "$setup_location -s test2", 'test2');

ok( $utility->syscmd(
        command => "$setup_location -s test2",
        fatal   => 0,
        debug   => 0,
    ), 
    'toaster_setup.pl',
);
