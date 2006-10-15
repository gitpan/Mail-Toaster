#!/usr/bin/perl
use strict;
use warnings;

use lib "inc";
use lib "lib";

use Test::More tests => 1;

BEGIN {
use_ok( 'Mail::Toaster' );
}

diag( "Testing Mail::Toaster $Mail::Toaster::VERSION" );
