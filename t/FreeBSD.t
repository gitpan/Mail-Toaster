# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#
# $Id: FreeBSD.t,v 4.0 2004/11/16 20:57:31 matt Exp $
#

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..7\n"; }
END {print "not ok 1\n" unless $loaded;}
my $os = $^O;
unless ( $os eq "freebsd" ) { exit 0; };
use lib "lib";
use Mail::Toaster::FreeBSD;
$loaded = 1;
print "ok 1 - Mail::Toaster::FreeBSD\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

my $freebsd = Mail::Toaster::FreeBSD->new();
$freebsd ? print "ok 2 - new \n" : print "not ok 2\n";

my $r = $freebsd->is_port_installed("perl");
$r ? print "ok 3 - is_port_installed\n" : print "not ok 3 - \n";

$r = $freebsd->rc_dot_conf_check("hostname", "hostname=\"host.example.com\"");
$r ? print "ok 4 - rc_dot_conf_check\n" : print "not ok 4 - rc_dot_conf_check\n";

$r = $freebsd->port_install("perl", "lang");
$r ? print "ok 5 - port_install\n" : print "not ok 5 - port_install\n";

$r = $freebsd->ports_check_age("30");
$r ? print "ok 6 - ports_check_age\n" : print "not ok 6 - ports_check_age\n";

$r = $freebsd->package_install("perl");
$r ? print "ok 7 - package_install\n" : print "not ok 7 - \n";



