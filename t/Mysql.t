#!/usr/bin/perl
use strict;
use warnings;

use Cwd;
use English qw( -no_match_vars );
use Test::More 'no_plan';

use lib "inc";
use lib "lib";

BEGIN { use_ok('Mail::Toaster::Mysql'); }
require_ok('Mail::Toaster::Mysql');


my $mysql = Mail::Toaster::Mysql->new;
ok($mysql, 'mysql object');

ok( $mysql->db_vars(), 'db_vars');

