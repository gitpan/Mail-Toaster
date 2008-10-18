#!perl
use strict;
use warnings;

use English qw( -no_match_vars );
use Test::More 'no_plan';

use lib "lib";

BEGIN { use_ok('Mail::Toaster::Passwd'); }
require_ok('Mail::Toaster::Passwd');

my $passwd = Mail::Toaster::Passwd->new();
ok($passwd, 'passwd object');

ok( $passwd->user_sanity("test"), 'user sanity');

ok( $passwd->sanity("testing", "test"), 'sanity');

ok( $passwd->show( {user=>"int-testing", debug=>0} ), 'show');

if ( $OSNAME !~ /cygwin/ ) {
    ok( $passwd->exist("nobody"), 'exist');
};

my $mod = "Crypt::PasswdMD5";
if (eval "require $mod")
{
	ok( $passwd->encrypt("secret"), 'encrypt');
}

