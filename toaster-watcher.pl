#!/usr/bin/perl
use strict;

#
# $Id: toaster-watcher.pl,v 1.18 2004/02/13 02:11:59 matt Exp $
# 

use vars qw/$VERSION/;

$VERSION = "1.11";

=head1 NAME

toaster-watcher.pl - Mail::Toaster::Watcher - monitors aspects of a qmail toaster

=head1 SYNOPSIS

At the moment toaster-watcher is two things. First, it's a configuration file that stores settings about your mail system. Other scripts and programs use this configuration file to determine how to configure themselves and other parts of the mail toaster solution.

The second part is a script that builds the control (run) file for qmail-smtpd. It takes into consideration all your settings, tests the RBL's you've selected to use, and builds a control file accordingly. It will soon be much, much more.

=head1 DESCRIPTION

=cut

use MATT::Utility 1.21;
use MATT::DNS     1.0;
use Mail::Toaster 3.33;
use Mail::Toaster::Qmail 1.27 qw( SetServiceDir InstallQmailServiceRun 
	RestartQmailSmtpd BuildSmtpRun BuildSendRun BuildPOP3Run 
	BuildSubmitRun );

$|++;

my $conf      = ParseConfigFile("toaster-watcher.conf", 0);
my $debug     = $conf->{'toaster_debug'};
my $supervise = $conf->{'qmail_supervise'};
unless (-d $supervise) { $supervise = "/var/qmail/supervise" };

my $file = "/tmp/toaster-watcher-smtpd-runfile";
if ( BuildSmtpRun($conf, $file, $debug ) )
{
	InstallQmailServiceRun($file, "$supervise/smtp/run");

	my $smtpdir = SetServiceDir($conf, "smtp");
	RestartQmailSmtpd($smtpdir, $debug);
};

my $file = "/tmp/toaster-watcher-send-runfile";
if ( BuildSendRun($conf, $file, $debug ) )
{
	InstallQmailServiceRun($file, "$supervise/send/run");
};

my $file = "/tmp/toaster-watcher-pop3-runfile";
if ( BuildPOP3Run($conf, $file, $debug ) )
{
	InstallQmailServiceRun($file, "$supervise/pop3/run");
};

if ( $conf->{'submit_enable'} ) 
{
	my $file = "/tmp/toaster-watcher-submit-runfile";
	if ( BuildSubmitRun($conf, $file, $debug ) )
	{
		InstallQmailServiceRun($file, "$supervise/submit/run");

		my $dir = SetServiceDir($conf, "submit");
		RestartQmailSmtpd($dir, $debug);
	};
};

if ( $conf->{'qs_quarantine_process'} )
{
	use Mail::Toaster::Qmail;

	my $qs_debug = $conf->{'qs_quarantine_verbose'};

	my @list = GetQmailScannerVirusSenderIPs($conf, $qs_debug);

	my $count = @list;
	if ($count && $qs_debug )
	{
		print "\nfound $count infected files\n\n"; 
	};

	if ($conf->{'qs_block_virus_senders'}) 
	{
		UpdateVirusBlocks($conf, @list);
	};

	#   Contributors
	# Randy Ricker - Paid $50
	# Anton Zavrin $20
	# Randy Jordan - Paid $25
	# Arie Gerszt  $20
	# Joe Kletch   $40
	# Marius Kirschner $20
}

if ($conf->{'maildir_clean_interval'} )
{
	CleanMailboxMessages($conf, $debug);
};

exit 1;

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

MATT::Bundle  - http://www.tnpi.biz/computing/perl/MATT-Bundle/
Net::DNS


=head1 SEE ALSO

http://www.tnpi.biz/internet/mail/toaster/
http://www.tnpi.biz/computing/perl/MATT-Bundle/


=head1 COPYRIGHT

Copyright 2003, The Network People, Inc.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

