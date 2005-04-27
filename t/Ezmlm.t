# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#
# $Id: Ezmlm.t,v 4.1 2005/03/24 03:38:35 matt Exp $
#

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)


BEGIN { $| = 1; print "1..5\n"; }
END {print "not ok 1\n" unless $loaded;}
use lib "lib";
use Mail::Toaster::Ezmlm;
$loaded = 1;
print "ok 1 - Mail::Toaster::Ezmlm\n";


######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

my $ezmlm = new Mail::Toaster::Ezmlm;
$ezmlm ? print "ok 2 - new\n" : print "not ok 2 - new\n";

$r = $ezmlm->process_shell();
! $r ? print "ok 3 - process_shell\n" : print "not ok 3 - process_shell\n";

$r = $ezmlm->logo();
$r ? print "ok 4 - logo\n" : print "not ok 4 - logo\n";

$r = $ezmlm->dir_check("/tmp");
$r ? print "ok 5 - dir_check\n" : print "not ok 5 - dir_check\n";

print "r: $r\n";

