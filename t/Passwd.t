# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..7\n"; }
END {print "not ok 1\n" unless $loaded;}
use lib "lib";
use Mail::Toaster::Passwd;
$loaded = 1;
print "ok 1 - Mail::Toaster::Passwd\n";

######################### End of black magic.


my $passwd = Mail::Toaster::Passwd->new();
$passwd ? print "ok 2 - new\n" : print "not ok 2 new\n";

my $r = $passwd->user_sanity("test");
$r->{'error_code'}==200 ? print "ok 3 - user sanity\n" : print "not ok 3 " . $r->{'error_desc'}."\n";


$r = $passwd->sanity("testing", "test");
$r->{'error_code'}==100 ? print "ok 4 - password sanity\n" : print "not ok 4 " . $r->{'error_desc'};

$r = $passwd->show( {user=>"root", debug=>0} );
$r->{'error_code'}==100 ? print "ok 5 - show\n" : print "not ok 5 " . $r->{'error_desc'};


$r = $passwd->exist("bin");
$r ? print "ok 6 - exist\n" : print "not ok 6 " . "exist\n";


$r = $passwd->encrypt("secret");
$r ? print "ok 7 - encrypt\n" : print "not ok 7 " . "encrypt\n";



