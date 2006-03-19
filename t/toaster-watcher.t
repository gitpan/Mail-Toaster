# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..21\n"; }
END {print "not ok 1\n" unless $loaded;}
use lib ".";
use lib "lib";
$loaded = 1;

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

use Mail::Toaster 4;             my $toaster = Mail::Toaster->new();
$toaster ? print "ok 1 - new toaster\n" : print "not ok 1\n";

use Mail::Toaster::Utility 4;    my $utility = Mail::Toaster::Utility->new();
$utility ? print "ok 2 - new utility\n" : print "not ok 2\n";

use Mail::Toaster::Qmail 4;      my $qmail   = Mail::Toaster::Qmail->new();
$qmail ? print "ok 3 - new qmail\n" : print "not ok 3\n";

use Mail::Toaster::DNS 4;
print "ok 4 - loaded dns\n";

my $conf    = $utility->parse_config( {file=>"toaster-watcher.conf", debug=>0} );
print "ok 5 - loaded \$conf\n";

my $clean = 1;

# build a pop3/run file in /tmp
$file = "/tmp/pop3.txt";
if ($qmail->build_pop3_run($conf, $file, 0) ) {
	print "ok 6 - created pop3/run\n";
	if ( $qmail->install_supervise_run({service=>"pop3", file=>$file}, $conf) ) {
		print "ok 7 - installed pop3/run file\n";
	};
}

# build a submit/run file in /tmp
$file = "/tmp/submit.txt";
if ( $qmail->build_submit_run($conf, $file, 0) ) 
{
	print "ok 8 - created submit/run\n";
	if ( $qmail->install_supervise_run({service=>"submit", file=>$file}, $conf) ) {
		print "ok 9 - installed submit/run file\n";
	};
}

# build a send/run file in /tmp
$file = "/tmp/send.txt";
if ( $qmail->build_send_run($conf, $file, 1) ) 
{
	print "ok 10 - created send/run\n";
	if ( $qmail->install_supervise_run({service=>"send", file=>$file}, $conf) ) {
		print "ok 11 - installed send/run file\n";
	};
}

# build a smtp/run file in /tmp
$file = "/tmp/smtp.txt";
if ( $qmail->build_smtp_run($conf, $file, 0) ) 
{
	print "ok 12 - created smtp/run\n";
	if ( $qmail->install_supervise_run({service=>"smtp", file=>$file}, $conf) ) {
		print "ok 13 - installed smtp/run file\n";
	};
}

# build a * /log/run file in /tmp
$qmail->install_qmail_control_log_files($conf, undef, 0);
print "ok 14 - created supervise/*/log/run\n";

use Mail::Toaster::Setup 4;  my $setup = Mail::Toaster::Setup->new();
$setup ? print "ok 15 - new setup\n" : print "not ok 15\n";

# test the supervised directories
$toaster->supervised_dir_test($conf, "smtp", 0) ? print "ok 16 dir supervise/smtp\n" : print "not ok 16\n";
$toaster->supervised_dir_test($conf, "send", 0) ? print "ok 17 dir supervise/send\n" : print "not ok 17\n";
$toaster->supervised_dir_test($conf, "pop3", 0) ? print "ok 18 dir supervise/pop3\n" : print "not ok 18\n";
$toaster->supervised_dir_test($conf, "submit", 0) ? print "ok 19 dir supervise/submit\n" : print "not ok 19\n";


$setup->startup_script($conf, 0) ? print "ok 20 startup script\n" : print "not ok 20\n";
$setup->service_symlinks($conf, 0) ? print "ok 21 service symlinks\n" : print "not ok 21\n";

