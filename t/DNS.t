# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..6\n"; }
#BEGIN { $| = 1; print "1..2\n"; }
END {print "not ok 1\n" unless $loaded;}
use lib "lib";
use Mail::Toaster::DNS;
$loaded = 1;
print "ok 1 - Mail::Toaster::DNS\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

my $dns = new Mail::Toaster::DNS;
$dns ? print "ok 2 - new\n" : print "not ok 2 - new\n";

$r = $dns->rbl_test("sbl.spamhaus.org", 0);
$r ? print "ok 3 - rbl_test\n" : print "not ok 3 - rbl_test\n";

$r = $dns->rbl_test_ns("sbl.spamhaus.org", "NS");
$r ? print "ok 4 - rbl_test_ns\n" : print "not ok 4 - rbl_test_ns\n";

$r = $dns->rbl_test_positive_ip("sbl.spamhaus.org");
$r ? print "ok 5 - rbl_test_positive_ip\n" : print "not ok 5 - rbl_test_positive_ip\n";

$r = $dns->rbl_test_negative_ip("sbl.spamhaus.org");
$r ? print "ok 6 - rbl_test_negative_ip\n" : print "not ok 6 - rbl_test_negative_ip\n";



