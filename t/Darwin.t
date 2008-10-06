#!/usr/bin/perl
use strict;
use warnings;

use English qw( -no_match_vars );
use Test::More;

if ( lc( $OSNAME ) ne "darwin" ) {
        plan skip_all => "Darwin tests skipped on " . $OSNAME;
}
else {
        plan 'no_plan';
};

use lib "inc";
use lib "lib";

require_ok('Mail::Toaster::Darwin');

ok( Mail::Toaster::Darwin->new, 'new darwin object' );

