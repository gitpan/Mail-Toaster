#!/usr/bin/perl
use strict;

#
# $Id: toaster-watcher.pl,v 4.7 2005/04/14 21:07:37 matt Exp $
# 

use vars qw/$VERSION/;

$VERSION = "4.06";

=head1 NAME

toaster-watcher.pl - monitors and configure various aspects of a qmail toaster

=head1 SYNOPSIS

toaster-watcher does several unique and important things. First, it includes a configuration file that stores settings about your mail system. You configure it to suit your needs and it goes about making sure all the settings on your system are as you selected. Various other scripts (like toaster_setup.pl) and programs use this configuration file to determine how to configure themselves and other parts of the mail toaster solution.

The really cool part about toaster-watcher.pl is that it dynamically builds the run files for your qmail daemons (qmail-smtpd, qmail-send, and qmail-pop3). You choose all your settings in toaster-watcher.conf and toaster-watcher.pl builds your run files for you, on the fly. It tests the RBL's you've selected to use, and builds a control file based on your settings and dynamic information such as the availability of the RBLs you want to use.


=head1 DESCRIPTION

=over

=cut

use Mail::Toaster 4;             my $toaster = Mail::Toaster->new();
use Mail::Toaster::Utility 4;    my $utility = Mail::Toaster::Utility->new();
use Mail::Toaster::DNS 4;
use Mail::Toaster::Qmail 4;      my $qmail   = Mail::Toaster::Qmail->new();

use vars qw/ $opt_d $opt_v $file $verbose /;
use Getopt::Std;
getopts('dv');

$|++;

my $pidfile = "/var/run/toaster-watcher.pid";
exit 500 unless $utility->check_pidfile($pidfile);

my $conf    = $utility->parse_config( {file=>"toaster-watcher.conf", debug=>$opt_d} );
my $debug   = $conf->{'toaster_debug'}; $debug ||= $opt_d; 
if ($opt_v) { $verbose = 1; print "$0 v$VERSION\n"; };

my $logfile   = $conf->{'toaster_watcher_log'};
if ($logfile ) {
	$utility->logfile_append($logfile, ["watcher", "Starting up"]);
	$utility->logfile_append($logfile, ["watcher", "Running toaster_check"]);
}

$toaster->toaster_check($conf, $verbose);


=item build_smtp_run

We first build a new $service/smtp/run file based on your settings in 
toaster-watcher.conf. There are a ton of configuration options, be sure
to check out the docs for toaster-watcher.conf. 

If the new generated file is different than the installed version, we 
install the updated run file and restart the daemon.

=cut

print "generating smtp/run..." if $verbose;
$utility->logfile_append($logfile, ["watcher", "Building smtp/run"]) if $logfile;

$file = "/tmp/toaster-watcher-smtpd-runfile";

my $vals = {
	file    => $file,
    debug   => $debug,
    verbose => $verbose,
    service => "smtp",
};

if ( $qmail->build_smtp_run($conf, $file, $debug ) )
{
	print "success.\n" if $verbose;
	if ( $qmail->install_qmail_service_run( $vals, $conf) ) 
	{
		$qmail->smtpd_restart($conf, "smtp", $debug);
	};
} 
else { print "FAILED.\n" if $verbose; };	

=item build_send_run

We first build a new $service/send/run file based on your settings in 
toaster-watcher.conf. There are a ton of configuration options, be sure
to check out the docs for toaster-watcher.conf. 

If the new generated file is different than the installed version, we 
install the updated run file and restart the daemon.

=cut


$utility->logfile_append($logfile, ["watcher", "Building send/run"]) if $logfile;
print "generating send/run..." if $verbose;

$file = "/tmp/toaster-watcher-send-runfile";
if ( $qmail->build_send_run($conf, $file, $debug ) )
{
	print "success.\n" if $verbose;
	$vals->{'service'} = "send";
	$vals->{'file'} = $file;
	if ( $qmail->install_qmail_service_run($vals, $conf) ) 
	{
		$qmail->restart($conf, $debug);
	};
}
else { print "FAILED.\n" if $verbose; };	


=item build_pop3_run

We first build a new $service/pop3/run file based on your settings in 
toaster-watcher.conf. There are a ton of configuration options, be sure
to check out the docs for toaster-watcher.conf. 

If the new generated file is different than the installed version, we 
install the updated run file and restart the daemon.

=cut

if ( $conf->{'pop3_daemon'} eq "qpop3d" )
{
	$utility->logfile_append($logfile, ["watcher", "Building pop3/run"]) if $logfile;

	$file = "/tmp/toaster-watcher-pop3-runfile";
	print "generating pop3/run..." if $verbose;
	if ( $qmail->build_pop3_run($conf, $file, $debug ) )
	{
		print "success.\n" if $verbose;
		$vals->{'service'} = "pop3";
		$vals->{'file'} = $file;
		$qmail->install_qmail_service_run($vals, $conf);
	}
	else { print "FAILED.\n" if $verbose; };	
};


=item build_submit_run

We first build a new $service/submit/run file based on your settings in 
toaster-watcher.conf. There are a ton of configuration options, be sure
to check out the docs for toaster-watcher.conf. 

If the new generated file is different than the installed version, we 
install the updated run file and restart the daemon.

=cut

if ( $conf->{'submit_enable'} ) 
{
	$utility->logfile_append($logfile, ["watcher", "Building submit/run"]) if $logfile;
	print "generating submit/run..." if $verbose;

	$file = "/tmp/toaster-watcher-submit-runfile";
	if ( $qmail->build_submit_run($conf, $file, $debug ) )
	{
		print "success.\n" if $verbose;
		$vals->{'file'} = $file; $vals->{'service'} = "submit";
		if ( $qmail->install_qmail_service_run($vals, $conf) )
		{
			$qmail->smtpd_restart($conf, "submit", $debug);
		};
	}
	else { print "FAILED.\n" if $verbose; };	
};


=item Qmail-Scanner Quarantine Processing

Qmail-Scanner quarantines any files that fail certain tests, such as banned attachments, Virus laden messages, etc. The messages get left laying around in the quarantine until someone does something about it. If you enable this feature, toaster-watcher.pl will go through the quarantine and deal with messages as you see fit.

I have mine configured to block the IP (for 24 hours) of anyone that's sent me a virus and delete the quarantined message. I run toaster-watcher.pl from cron every 5 minutes so this usually keeps virus infected hosts from sending me another virus laden message for at least 24 hours, after which we hope the owner of the system has cleaned up his computer.

=cut

if ( $conf->{'install_qmailscanner'} && $conf->{'qs_quarantine_process'} )
{
	print "checking qmail-scanner quarantine.\n" if $verbose;
	$utility->logfile_append($logfile, ["watcher", "Processing the qmail-scanner quarantine"]) if $logfile;

	my $qs_debug = $conf->{'qs_quarantine_verbose'};
	if ($verbose && ! $qs_debug ) { $qs_debug++ };

	my @list = $qmail->get_qmailscanner_virus_sender_ips($conf, $qs_debug);

	my $count = @list;
	if ($count && $qs_debug )
	{
		print "\nfound $count infected files\n\n"; 
	};

	if ($conf->{'qs_block_virus_senders'}) 
	{
		$qmail->UpdateVirusBlocks($conf, @list);
	};

	#    Contributors
	# Randy Ricker - Paid $50
	# Anton Zavrin $20
	# Randy Jordan - Paid $25
	# Arie Gerszt  $20
	# Joe Kletch   (Backpack, much better than $40 pledge)
	# Marius Kirschner $20
};

=item Maildir Processing

Many times its useful to have a script that cleans up old mail messages on your mail system and enforces policy. Now toaster-watcher.pl does that. You tell it how often to run (I use every 7 days), what mail folders to clean (Inbox, Read, Unread, Sent, Trash, Spam), and then how old the messaged need to be before you remove them. 

I have my system set to remove messages in Sent folders more than 180 days old and messages in Trash and Spam folders that are over 14 days old. I have also instructed toaster-watcher to feed any messages in my Spam and Read folders that are more than 1 day old through sa-learn. That way I train SpamAssassin by merely moving my messages into appropriate folders.

=back

=cut

if ($conf->{'maildir_clean_interval'} )
{
	print "cleaning mailbox messages..." if ($verbose);
	$utility->logfile_append($logfile, ["watcher","Cleaning mailbox messages"]) if $logfile;

	$toaster->clean_mailboxes($conf, $debug);
	print "done.\n"	if ($verbose);
}

if ($conf->{'maildir_learn_interval'} )
{
	print "learning mailbox messages..." if ($verbose);
	$utility->logfile_append($logfile, ["watcher","learning mailbox messages"]) if $logfile;

	$toaster->learn_mailboxes($conf, $debug);
	print "done.\n"	if ($verbose);
}


$utility->logfile_append($logfile, ["watcher","rebuilding SSL temp keys"]) if $logfile;
$qmail->rebuild_ssl_temp_keys($conf, $verbose);

unlink $pidfile;

$utility->logfile_append($logfile, ["watcher","Exiting\n"]) if $logfile;

if ( -x "/var/qmail/bin/simscanmk" ) { 
	# this needs to be done, but quietly
#	$utility->syscmd("/var/qmail/bin/simscanmk");
#	$utility->syscmd("/var/qmail/bin/simscanmk -g");
};

exit 0;

__END__


=head1 TODO

Optionally send an email notification to an admin if a file gets updated. Make this
configurable on a per service basis. I can imagine wanting to know if pop3/run or send/run ever
changed but I don't care to get emailed every time a RBL fails a DNS check.

Feature request by David Chaplin-Leobell: check for low disk space on the queue and
mail delivery partitions.  If low disk is detected, it could either just
notify the administrator, or it could do some cleanup of things like the
qmail-scanner quarantine folder.


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>


=head1 DEPENDENCIES

This module requires these other modules and libraries:

Net::DNS


=head1 SEE ALSO

http://www.tnpi.biz/internet/mail/toaster/


=head1 COPYRIGHT

Copyright (c) 2004-2005, The Network People, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

