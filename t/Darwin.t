#!/usr/bin/perl
use strict;
use warnings;

use English qw( -no_match_vars );
use Test::More;

Test::More::plan(
    skip_all => "skipping Darwin tests on $OSNAME"
) if $OSNAME ne "darwin";

use lib "inc";
use lib "lib";

plan 'no_plan';

BEGIN { use_ok('Mail::Toaster::Darwin'); }
require_ok('Mail::Toaster::Darwin');

ok( Mail::Toaster::Darwin->new, 'new darwin object' );


