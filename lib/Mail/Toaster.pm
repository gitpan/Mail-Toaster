#!/usr/bin/perl
use strict;

#
# $Id: Toaster.pm,v 4.1 2004/11/16 21:20:01 matt Exp $
#

package Mail::Toaster;

use Carp;
use vars qw($VERSION);

#$VERSION = sprintf "%d.%02d", q$Revision: 4.1 $ =~ /(\d+)/g;
# this has problems being detected with perl 5.6.

$VERSION  = '4.00';

use Mail::Toaster::Utility; my $utility = new Mail::Toaster::Utility;

=head1 NAME

Mail::Toaster

=head1 SYNOPSIS

A collection of Perl programs and modules with oodles of code snippets that make working with mail systems much less work. Everything you need to build a industrial strength mail system.

=head1 DESCRIPTION

A collection of perl scripts and modules that are terribly useful for building and maintaining a mail system. Written for FreeBSD and Mac OS X. It's become quite useful on other platforms and will grow to support other MTA's (think postfix) in the future. 

=head1 METHODS

=head2 new

    use Mail::Toaster;
	my $toaster = Mail::Toaster->new;

=cut

sub new
{
	my ($class, $name) = @_;
	my $self = { name => $name };
	bless ($self, $class);
	return $self;
};

=head2 email_send

Email test routines for testing a mail toaster installation.

   $toaster->email_send($conf, "clean");
   $toaster->email_send($conf, "spam");
   $toaster->email_send($conf, "attach");
   $toaster->email_send($conf, "virus");

This sends 4 test emails of various types to the email address configured in toaster-watcher.conf.

=cut

sub email_send($$)
{
	my ($self, $conf, $type) = @_;

	my $email = $conf->{'toaster_admin_email'} or croak "Hey, where's \$conf?\n";

	my $qdir = $conf->{'qmail_dir'} || "/var/qmail";
	return 0 unless -x "$qdir/bin/qmail-inject";

	open (INJECT, "| $qdir/bin/qmail-inject -a -f \"\" $email") or warn "couldn't send to qmail-inject!\n";

	if    ( $type eq "clean" )  {
		print "sending a clean message.\n";
		print INJECT 'From: Mail Toaster testing <' . $email . '>
To: Email Administrator <'. $email .'>
Subject: Email test ('.$type.' message)

This is a clean test message. It should arrive unaltered and should also pass any virus or spam checks.
';
	}
	elsif ( $type eq "spam" )   {
		print "sending a sample spam message\n";
		print INJECT 'Return-Path: sb55sb55@yahoo.com
Delivery-Date: Mon, 19 Feb 2001 13:57:29 +0000
Return-Path: <sb55sb55@yahoo.com>
Delivered-To: jm@netnoteinc.com
Received: from webnote.net (mail.webnote.net [193.120.211.219])
   by mail.netnoteinc.com (Postfix) with ESMTP id 09C18114095
   for <jm7@netnoteinc.com>; Mon, 19 Feb 2001 13:57:29 +0000 (GMT)
Received: from netsvr.Internet (USR-157-050.dr.cgocable.ca [24.226.157.50] (may be forged))
   by webnote.net (8.9.3/8.9.3) with ESMTP id IAA29903
   for <jm7@netnoteinc.com>; Sun, 18 Feb 2001 08:28:16 GMT
From: sb55sb55@yahoo.com
Received: from R00UqS18S (max1-45.losangeles.corecomm.net [216.214.106.173]) by netsvr.Internet with S
MTP (Microsoft Exchange Internet Mail Service Version 5.5.2653.13)
   id 1429NTL5; Sun, 18 Feb 2001 03:26:12 -0500
DATE: 18 Feb 01 12:29:13 AM
Message-ID: <9PS291LhupY>
Subject: anti-spam test: checking SpamAssassin [if present] (There yours for FREE!)
To: undisclosed-recipients:;

Congratulations! You have been selected to receive 2 FREE 2 Day VIP Passes to Universal Studios!

Click here http://209.61.190.180

As an added bonus you will also be registered to receive vacations discounted 25%-75%!


@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
This mailing is done by an independent marketing co.
We apologize if this message has reached you in error.
Save the Planet, Save the Trees! Advertise via E mail.
No wasted paper! Delete with one simple keystroke!
Less refuse in our Dumps! This is the new way of the new millennium
To be removed please reply back with the word "remove" in the subject line.
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

';
	}
	elsif ( $type eq "virus" )  {
		print "Sending a real virus laden message.\n";
		print INJECT 'From: Mail Toaster testing <' . $email . '>
To: Email Administrator <'. $email .'>
Subject: Email test ('.$type.' message)
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="gKMricLos+KVdGMg"
Content-Disposition: inline

--gKMricLos+KVdGMg
Content-Type: text/plain; charset=us-ascii
Content-Disposition: inline

This is an example email containing a virus. It should trigger qmail-scanner
if it is configured properly. Simscan will not catch it as it is not a real
virus.

If it is caught by AV software, it will not be delivered to its intended 
recipient. The Qmail-Scanner administrator should receive an Email alerting 
him/her to the presence of the test virus. All other software should block 
the message.


--gKMricLos+KVdGMg
Content-Type: text/plain; charset=us-ascii
Content-Disposition: attachment; filename="sneaky.txt"

X5O!P%@AP[4\PZX54(P^)7CC)7}\$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!\$H+H*

--gKMricLos+KVdGMg--

';
	}
	elsif ( $type eq "attach" ) {
		print "Sending eicar test virus attachment - should be caught.\n";
		print INJECT 'From: Mail Toaster Testing <' . $email . '>
To: Email Administrator <'. $email .'>
Subject: Email test ('.$type.' message)
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="gKMricLos+KVdGMg"
Content-Disposition: inline

--gKMricLos+KVdGMg
Content-Type: text/plain; charset=us-ascii
Content-Disposition: inline

This is an example of an Email message containing a virus. It should
trigger the virus scanner, and not be delivered.

If you are using qmail-scanner, the server admin should get a notification.

--gKMricLos+KVdGMg
Content-Type: text/plain; charset=us-ascii
Content-Disposition: attachment; filename="Eicar.com"

00000000000000000000000000000000000000000000000000000000000000000000

--gKMricLos+KVdGMg--

';
	}
	else { print "man Mail::Toaster to figure out how to use this!\n" };

	close INJECT;

	return 1;
};

=head2 toaster_check

    $toaster->toaster_check($conf);

Runs a series of tests to keep your toaster ship shape:

  make sure watcher.log is less than 1MB
  make sure ~alias/.qmail-* exist and are not empty
  verify multilog down files are removed if maillogs is used

=cut

sub toaster_check
{
	my ($self, $conf, $debug) = @_;

	# Do other sanity tests here

	# check that we can't SMTP AUTH with random user names and passwords

	# make sure watcher.log isn't larger than 1MB
	my $logfile = $conf->{'toaster_watcher_log'};
	if ( $logfile && -e $logfile ) {
		my $size = (stat($logfile))[7];
		if ( $size > 999999  ) {
			print "toaster_check: compressing $logfile! ($size)\n" if $debug;
			my $gzip = $utility->find_the_bin("gzip");
			$utility->syscmd("$gzip -f $logfile");
		};
	};

	# make sure the qmail alias files exist and are not empty
	my $qdir = $conf->{'qmail_dir'}; $qdir ||= "/var/qmail";

	foreach ( qw/ .qmail-postmaster .qmail-root .qmail-mailer-daemon / )
	{
		unless ( -s "$qdir/alias/$_" )
		{
			print "\n\nWARNING: your administrative email address needs to be in $_!\n\n";
			sleep 3;
		};
	};

	# if maillogs is the logging type, make sure down files aren't in service/log dir

	my $servicedir = $conf->{'qmail_service'}; $servicedir ||= "/var/service";

	if ( $conf->{'smtpd_log_method'} eq "multilog" )
	{
		my $svc_dir_smtp = $conf->{'qmail_service_smtp'};
		$svc_dir_smtp ||= "/var/service/smtp";

		if ( $svc_dir_smtp =~ /^qmail_service\/(.*)$/ ) { $svc_dir_smtp = "$servicedir/$1"; };

		if ( -d "$svc_dir_smtp/log" ) 
		{
			if ( -e "$svc_dir_smtp/log/down" ) 
			{
				print "\nWARNING: you have multilogs set as your log post-processor in toaster-watcher.conf but multilog post-processing is currently disabled because of the existing file $svc_dir_smtp/log/down. You need to either delete that file (if you want multilog processing) or edit toaster-watcher.conf and set the smtpd_log_method to another value.\n\n";
			};
		} 
		else {
			print "WARNING: $svc_dir_smtp/log does not exist\n";
		};
	};

	if ( $conf->{'send_log_method'} eq "multilog" )
	{
		my $svc_dir_send = $conf->{'qmail_service_send'};
		$svc_dir_send ||= "/var/service/send";

		if ( $svc_dir_send =~ /^qmail_service\/(.*)$/ ) { $svc_dir_send = "$servicedir/$1"; };

		if ( -d "$svc_dir_send/log" ) 
		{
			if ( -e "$svc_dir_send/log/down" ) 
			{
				print "\nWARNING: you have multilogs set as your log post-processor in toaster-watcher.conf but multilog post-processing is currently disabled because of the existing file $svc_dir_send/log/down. You need to either delete that file (if you want multilog processing) or edit toaster-watcher.conf and set the send_log_method to another value.\n\n";
			};
		} 
		else {
			print "WARNING: $svc_dir_send/log does not exist\n";
		};
	};

	if ( $conf->{'pop3_log_method'} eq "multilog" )
	{
		my $svc_dir_pop3 = $conf->{'qmail_service_pop3'};
		$svc_dir_pop3 ||= "/var/service/pop3";

		if ( $svc_dir_pop3 =~ /^qmail_service\/(.*)$/ ) { $svc_dir_pop3 = "$servicedir/$1"; };

		if ( -d "$svc_dir_pop3/log" ) 
		{
			if ( -e "$svc_dir_pop3/log/down" ) 
			{
				print "\nWARNING: you have multilogs set as your log post-processor in toaster-watcher.conf but multilog post-processing is currently disabled because of the existing file $svc_dir_pop3/log/down. You need to either delete that file (if you want multilog processing) or edit toaster-watcher.conf and set the pop3_log_method to another value.\n\n";
			};
		} 
		else {
			print "WARNING: $svc_dir_pop3/log does not exist\n";
		};
	};

	if ( $conf->{'submit_log_method'} eq "multilog" )
	{
		my $svc_dir_submit = $conf->{'qmail_service_submit'};
		$svc_dir_submit  ||= "/var/service/submit";

		if ( $svc_dir_submit =~ /^qmail_service\/(.*)$/ ) { $svc_dir_submit = "$servicedir/$1"; };

		if ( -d "$svc_dir_submit/log" ) 
		{
			if ( -e "$svc_dir_submit/log/down" ) 
			{
				print "\nWARNING: you have multilogs set as your log post-processor in toaster-watcher.conf but multilog post-processing is currently disabled because of the existing file $svc_dir_submit/log/down. You need to either delete that file (if you want multilog processing) or edit toaster-watcher.conf and set the submit_log_method to another value.\n\n";
			};
		} 
		else {
			print "WARNING: $svc_dir_submit/log does not exist\n";
		};
	};
};


=head2 clean_mailboxes

This sub does all sorts of fun things. The most important function is to trawl through a mail system cleaning out old mail messages that exceed some pre-configured threshhold as defined in toaster-watcher.conf.

Peter Brezny suggests adding another option which is good. Set a window during which the cleaning script can run so that it's not running during the highest load times.

=cut

sub clean_mailboxes($;$)
{
	my ($self, $conf, $debug) = @_;

	my $days = $conf->{'maildir_clean_interval'};
	unless ($days) {
		warn "maildir_clean_interval not set in \$conf!";
		return 0;
	};

	my $log = $conf->{'qmail_log_base'};
	unless ($log) {
		print "NOTICE: qmail_log_base is not set in toaster-watcher.conf! Using default /var/log/mail. \n";
		$log = "/var/log/mail";
	};
	print "clean_mailboxes: qmail log base is: $log\n" if $debug;
	$log  = "$log/clean.log";

	unless ( -e $log ) 
	{ 
		$utility->file_write($log, "created file"); 
		croak unless (-e $log);
	};

	unless ( -M $log > $days )
	{
		print "clean_mailboxes: skipping, $log is less than $days old\n" if $debug;
		return 0;
	} 
	else 
	{
		$utility->logfile_append($log, ["toaster-watcher", "clean_mailboxes running."] ); 
		print "clean_mailboxes: checks passed, getting ready to clean\n" if $debug;
	};

	use Mail::Toaster::Qmail;
	my $qmail = Mail::Toaster::Qmail->new();

	my $qmaildir = $conf->{'qmail_dir'}; $qmaildir ||= "/var/qmail";

	my @domains = $qmail->get_domains_from_assign("$qmaildir/users/assign",$debug);
	my $count = @domains;
	print "clean_mailboxes: found $count domains.\n" if $debug;

	my $find    = $utility->find_the_bin("find");
	my $salearn = $utility->find_the_bin("sa-learn");

	foreach my $hash (@domains)
	{
		my $domain = $hash->{'dom'};

		print "clean_mailboxes: processing $domain mailboxes.\n" if $debug;

		my $vpdir = $conf->{'vpopmail_home_dir'};
		my @paths = `$vpdir/bin/vuserinfo -d -D $domain`;
		chomp @paths;

		foreach my $path (@paths)
		{
			if ( $path && -d $path ) 
			{
				print "clean_mailboxes: processing in $path\n" if $debug;

				if ($conf->{'maildir_clean_Read_learn'} ) 
				{
					carp "No sa-learn found!\n" unless ( -x $salearn);
					if ( -d "$path/Maildir/cur") {
						print "clean_mailboxes: training SpamAsassin from ham (read) messages\n" if $debug;

						$days = $conf->{'maildir_clean_Read_learn_days'};
						if ($days) 
						{
							print "clean_mailboxes: removing read messages older than $days days.\n" if $debug;
							$utility->syscmd("$find $path/Maildir/cur  -type f -mtime +$days -exec $salearn --ham --no-rebuild {} \\;");
						} 
						else 
						{
							$utility->syscmd("$salearn --ham $path/Maildir/cur");
							if ( -d "$path/Maildir/.read" ) {
								$utility->syscmd("$salearn --ham $path/Maildir/.read/cur");
							};
							if ( -d "$path/Maildir/.Read" ) {
								$utility->syscmd("$salearn --ham $path/Maildir/.Read/cur");
							};
						};
					} 	
					else 
					{
						print "clean_mailboxes: ERROR, $path/Maildir/cur does not exist!\n" if $debug;
					};
				};

				$days = $conf->{'maildir_clean_Read'};
				if ($days) 
				{
					print "clean_mailboxes: cleaning read messages older than $days days\n" if $debug;
					if ( -d "$path/Maildir/cur" ) {
						$utility->syscmd("$find $path/Maildir/cur  -type f -mtime +$days -exec rm {} \\;");
					} else {
						print "clean_mailboxes: FAILED because $path/Maildir/cur does not exist.\n" if $debug;
					};
				};

				$days = $conf->{'maildir_clean_Unread'};
				if ($days) 
				{
					print "clean_mailboxes: cleaning unread messages older than $days days\n" if $debug;
					if ( -d "$path/Maildir/new" ) {
						$utility->syscmd("$find $path/Maildir/new  -type f -mtime +$days -exec rm {} \\;");
					} else {
						print "clean_mailboxes: FAILED because $path/Maildir/new does not exist.\n" if $debug;
					};
				};

				$days = $conf->{'maildir_clean_Sent'};
				if ($days) 
				{
					print "clean_mailboxes: cleaning sent messages older than $days days\n" if $debug;
					if ( -d "$path/Maildir/.Sent" ) {
						$utility->syscmd("$find $path/Maildir/.Sent/new -type f -mtime +$days -exec rm {} \\;");
						$utility->syscmd("$find $path/Maildir/.Sent/cur -type f -mtime +$days -exec rm {} \\;");
					} else {
						print "clean_mailboxes: skipped cleaning because $path/Maildir/.Sent does not exist.\n" if $debug;
					};
				};

				$days = $conf->{'maildir_clean_Trash'};
				if ($days) 
				{
					print "clean_mailboxes: cleaning deleted messages older than $days days\n" if $debug;
					if ( -d "$path/Maildir/.Trash" ) {
						$utility->syscmd("$find $path/Maildir/.Trash/new -type f -mtime +$days -exec rm {} \\;");
						$utility->syscmd("$find $path/Maildir/.Trash/cur -type f -mtime +$days -exec rm {} \\;");
					} else {
						print "clean_mailboxes: skipped cleaning because $path/Maildir/.Trash does not exist.\n" if $debug;
					};
				};

				if ( $conf->{'maildir_clean_Spam_learn'} ) 
				{
					print "clean_mailboxes: training SpamAsassin from spam messages\n" if $debug;
					if ( -d "$path/Maildir/.Spam" ) {
						carp "No sa-learn found!\n" unless ( -x $salearn);
						$utility->syscmd("$salearn --spam $path/Maildir/.Spam/cur");
						$utility->syscmd("$salearn --spam $path/Maildir/.Spam/new");
					} else {
						print "clean_mailboxes: skipped training because $path/Maildir/.Spam does not exist.\n" if $debug;
					};
				};

				$days = $conf->{'maildir_clean_Spam'};
				if ($days) 
				{
					print "clean_mailboxes: cleaning spam messages older than $days\n" if $debug;
					if ( -d "$path/Maildir/.Spam" ) {
						$utility->syscmd("$find $path/Maildir/.Spam/cur -type f -mtime +$days -exec rm {} \\;");
						$utility->syscmd("$find $path/Maildir/.Spam/new -type f -mtime +$days -exec rm {} \\;");
					} else {
						print "clean_mailboxes: skipped cleaning because $path/Maildir/.Spam does not exist.\n" if $debug;
					};
				};
			}
			else
			{
				print "clean_mailboxes: $path does not exist, skipping!\n";
			};
		}
		print "done.\n" if $debug;
	};
}
	

1;
__END__


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>

=head1 BUGS

None known. Report any to matt@tnpi.biz.

=head1 TODO

 Add support for Darwin (MacOS X) and Linux
 Update openssl & courier ssl .cnf files
 Install an optional stub DNS resolver (dnscache)

=head1 SEE ALSO

Mail::Toaster::CGI, Mail::Toaster::DNS, Mail::Toaster::Logs, Mail::Toaster::Qmail, 
Mail::Toaster::Setup, Mail::Toaster::Watcher, Mail::Toaster::Utility,
toaster-watcher.conf, toaster.conf

=head1 COPYRIGHT

Copyright (c) 2004, The Network People, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
