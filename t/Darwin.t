# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..2\n"; }
END {print "not ok 1\n" unless $loaded;}
my $os = $^O;
unless ( $os eq "darwin" ) { print "ok 1\nok 2\n"; $loaded = 1; exit 0; };
use lib "lib";
use Mail::Toaster::Darwin;
$loaded = 1;
print "ok 1 - Mail::Toaster::Darwin\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

my $darwin = new Mail::Toaster::Darwin;
$darwin ? print "ok 2 - new\n" : print "not ok 3 - new\n";

