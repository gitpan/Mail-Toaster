# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..3\n"; }
END {print "not ok 1\n" unless $loaded;}
use lib ".";
$loaded = 1;

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

system "./index.cgi";
print "ok 1 - index.cgi\n";

use Mail::Toaster::CGI;
print "ok 2 - Mail::Toaster::CGI\n";

my $cgi = Mail::Toaster::CGI->new();
print "ok 3 - new CGI\n";

