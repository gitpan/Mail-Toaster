# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..3\n"; }
END {print "not ok 1\n" unless $loaded;}
use lib "lib";
use Mail::Toaster::Mysql;
$loaded = 1;
print "ok 1 - Mail::Toaster::Mysql\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

my $mysql = Mail::Toaster::Mysql->new;
$mysql ? print "ok 2 - new\n" : print "not ok 2 - new\n";


$r = $mysql->db_vars();
$r ? print "ok 3 - db_vars\n" : print "not ok 3 - db_vars\n";
