#!perl
use strict;
use warnings;

use lib "lib";
use Test::More 'no_plan';


BEGIN {
    use_ok('Mail::Toaster::CGI');
}
require_ok('Mail::Toaster::CGI');

ok( Mail::Toaster::CGI->new(), 'new' );

