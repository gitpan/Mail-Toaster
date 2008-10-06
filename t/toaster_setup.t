#!/usr/bin/perl
use strict;
use warnings;

use lib "inc";
use lib "lib";

use Config;
use Cwd;
use English qw( -no_match_vars );
use Test::More 'no_plan';

BEGIN { use_ok( 'Mail::Toaster::Utility' ); };
require_ok( 'Mail::Toaster::Utility' );

my $util = Mail::Toaster::Utility->new;    # create an object

my $setup_location = "bin/toaster_setup.pl";

ok( -e $setup_location, 'found toaster_setup.pl');
ok( -x $setup_location, 'is executable');

#my $wd = cwd; print "wd: $wd\n";
#ok (system "$setup_location -s test2", 'test2');

my $this_perl = $EXECUTABLE_NAME;
if ($OSNAME ne 'VMS')
    {$this_perl .= $Config{_exe}
        unless $this_perl =~ m/$Config{_exe}$/i;}

ok( $util->syscmd(
        command => "$this_perl $setup_location -s test2",
        fatal   => 0,
        debug   => 0,
    ), 
    'toaster_setup.pl',
);
