# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#
# $Id: Provision.t,v 4.0 2004/11/16 20:57:31 matt Exp $
#

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..3\n"; }
END {print "not ok 1\n" unless $loaded;}
use lib "lib";
use Mail::Toaster::Provision;
$loaded = 1;
print "ok 1 - Mail::Toaster::Provision\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

my $prov = Mail::Toaster::Provision->new();
$prov ? print "ok 2 - new\n" : print "not ok 2 - new\n";

my $r = $prov->what_am_i;
$r ? print "ok 3 - what_am_i ($r)\n" : print "not ok 3 - what_am_i\n";


