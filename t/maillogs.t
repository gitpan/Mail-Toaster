# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..6\n"; }
END {print "not ok 1\n" unless $loaded;}
use lib ".";
$loaded = 1;

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

system "./maillogs smtp";
print "ok 1 - maillogs\n";
system "./maillogs send";
print "ok 2 - maillogs\n";
system "./maillogs imap";
print "ok 3 - maillogs\n";
system "./maillogs pop3";
print "ok 4 - maillogs\n";
system "./maillogs webmail";
print "ok 5 - maillogs\n";
system "./maillogs spam";
print "ok 6 - maillogs\n";

