# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#
# $Id: Qmail.t,v 4.2 2005/05/18 14:46:38 matt Exp $
#

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..6\n"; }
END {print "not ok 1\n" unless $loaded;}
use lib "lib";
use Mail::Toaster::Qmail;
$loaded = 1;
print "ok 1 - Mail::Toaster::Qmail\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

my $qmail = Mail::Toaster::Qmail->new();
$qmail ? print "ok 2 - new\n" : print "not ok 2 - new\n";

my $r = $qmail->get_list_of_rwls( { 'rwl_qmail.bondedsender.org'=> 1} );
@$r[0] ? print "ok 3 - get_list_of_rwls\n" : print "not ok 3 - get_list_of_rwls\n";

$r = $qmail->test_each_rbl(undef, $r);
@$r[0] ? print "ok 4 - test_each_rbl\n" : print "not ok 4 - test_each_rbl\n";

$r = $qmail->get_list_of_rbls( { 'rbl_sbl-xbl.spamhaus.org'=> 1} );
@$r[0] ? print "ok 5 - get_list_of_rbls\n" : print "not ok 5 - get_list_of_rbls\n";

$r = $qmail->service_dir_get( {qmail_service_smtp=>'/var/service/smtp'}, "smtp");
$r ? print "ok 6 - service_dir_get\n" : print "not ok 6 - service_dir_get\n";

