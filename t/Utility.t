# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#
# $Id: Utility.t,v 4.2 2005/05/10 02:28:44 matt Exp $
#

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..27\n"; }
END {print "not ok 1\n" unless $loaded;}
use lib "lib";
use Mail::Toaster::Utility;
$loaded = 1;
print "ok 1 - Mail::Toaster::Utility\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

my $utility = Mail::Toaster::Utility->new();
$utility ? print "ok 2 - new utility\n" : print "not ok 2\n";

$r = $utility->yes_or_no("test", 5);
$r ? print "ok 3 - yes_or_no\n" : print "not ok 3 (yes_or_no)\n";

$r = $utility->file_check_readable("/etc/hosts", 1);
$r ? print "ok 4 - file_check_readable\n" : print "not ok 4 (file_check_readable)\n";

$r = $utility->file_check_writable("/tmp/test.pid");
$r ? print "ok 5 - file_check_writable\n" : print "not ok 5 (file_check_writable)\n";

if ( $r ) {
	$r = $utility->file_write("/tmp/test.pid", "junk");
	$r ? print "ok 6 - file_write\n" : print "not ok 6 (file_write)\n";

	($r) = $utility->file_read("/tmp/test.pid");
	$r ? print "ok 7 - file_read\n" : print "not ok 7 (file_read)\n";

	$r = $utility->file_append("/tmp/test.pid", ["more junk"]);
	$r ? print "ok 8 - file_append\n" : print "not ok 8 (file_append)\n";

	$r = $utility->file_delete("/tmp/test.pid");
	$r ? print "ok 9 - file_delete\n" : print "not ok 9 (file_delete)\n";
}

$r = $utility->check_pidfile("/tmp/test.pid");
-e $r ? print "ok 10 - check_pidfile\n" : print "not ok 10 (check_pidfile)\n";

$r = $utility->file_delete($r);
$r ? print "ok 11 - file_delete\n" : print "not ok 11 (file_delete)\n";

$r = $utility->is_process_running("init");
$r ? print "ok 12 - is_process_running\n" : print "not ok 12 (is_process_running)\n";

my $rm = $utility->find_the_bin("rm");
-x $rm ? print "ok 13 - find_the_bin\n" : print "not ok 13 (find_the_bin)\n";

$r = $utility->chdir_source_dir("/tmp");
$r ? print "ok 14 - chdir_source_dir\n" : print "not ok 14 (chdir_source_dir)\n";

$r = $utility->file_get("http://www.tnpi.biz/internet/mail/toaster/etc/maildrop-qmail-domain");
$r ? print "ok 15 - file_get\n" : print "not ok 15 (file_get)\n";

$r = $utility->syscmd("$rm /tmp/maildrop-qmail-domain");
$r ? print "not ok 16 - syscmd\n" : print "ok 16 - syscmd\n";

my @list = $utility->get_dir_files("/etc");
-e $list[0] ? print "ok 17 - get_dir_files\n" : print "not ok 17 (get_dir_files)\n";

$r = $utility->drives_get_mounted();
$r ? print "ok 18 - drives_get_mounted\n" : print "not ok 18 (drives_get_mounted)\n";

(@list) = $utility->get_the_date();
$list[0] ? print "ok 19 - get_the_date\n" : print "not ok 19 (get_the_date)\n";

$r = $utility->is_hashref( {test=>1} );  # should succeed
$r ? print "ok 20 - is_hashref\n" : print "not ok 20 (is_hashref)\n";

$r = $utility->is_hashref( );             # should fail
$r ? print "not ok 21 - is_hashref\n" : print "ok 21 (is_hashref)\n";

$r = $utility->install_from_source( "string", "string" );
$r ? print "not ok 22 - install_from_sources\n" : print "ok 22 (install_from_sources)\n";

$r = $utility->install_from_source( {int_test=>1}, "string" );
$r ? print "not ok 23 - install_from_sources\n" : print "ok 23 (install_from_sources)\n";

$r = $utility->install_from_source( "string", {int_test=>1} );
$r ? print "not ok 24 - install_from_sources\n" : print "ok 24 (install_from_sources)\n";

$r = $utility->install_from_source( {int_test=>1}, {int_test=>1} );
$r ? print "ok 25 - install_from_sources\n" : print "not ok 25 (install_from_sources)\n";

$r = $utility->is_arrayref( ['test'] );  # should succeed
$r ? print "ok 26 - is_arrayref\n" : print "not ok 26 (is_arrayref)\n";

$r = $utility->is_arrayref( );             # should fail
$r ? print "not ok 27 - is_arrayref\n" : print "ok 27 (is_arrayref)\n";

#$utility->install_if_changed("foo", "bar", undef, 1) ? print "ok 28 install_if_newer\n" : print "not ok 28\n";


__END__
print $r . "\n";
