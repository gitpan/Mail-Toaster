#!/usr/bin/perl
use strict;

#
# $Id: Logs.pm,v 1.9 2004/01/31 19:11:27 matt Exp $
#

package Mail::Toaster::Logs;

use Carp;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION = "2.66";

@ISA     = qw(Exporter);
@EXPORT  = qw(
	CheckForFlags
	CheckSetup
	RollSendLogs
	RollRblLogs
	RollPOP3Logs
	SetSyslog
	WhatAmI
);

@EXPORT_OK = qw(
	CheckLogFiles 
	CountIMAP 
	CountQMS
	CountRblLine
	CountRBL
	CountSendLine
	CountSend
	CountSMTP
	CountSpamA
	CountPOP3
	CountWebMail
	CompressYesterdaysLogfile
	ProcessPOP3Logs
	ProcessRblLogs
	ProcessSendLogs
	PurgeLastMonthLogs 
	ReadCounters
	RotateMailLogs 
	SetupDateVariables
	WriteCounters
);

use MATT::Utility;
use MATT::Perl;

use File::Path;
use Getopt::Std;
use POSIX;
#use Date::Parse;

=head1 NAME

Mail::Toaster::Logs

=head1 SYNOPSIS

Perl modules related to mail logging. These modules are used primarily in maillogs but will be used in ttoaster-watcher.pl and toaster_setup.pl as well.

=cut


sub CheckSetup($)
{

=head2 CheckSetup

	use Mail::Toaster::Logs;
	CheckSetup($conf);

=cut

	my ($conf) = @_;

	my $logbase  = $conf->{'logs_base'};
	my $counters = $conf->{'logs_counters'};
	unless ($logbase)  { $logbase = "/var/log/mail"; };
	unless ($counters) { $counters = "counters"; };

	my $user  = $conf->{'logs_user'};  unless ($user)  { $user  = "qmaill"   };
	my $group = $conf->{'logs_group'}; unless ($group) { $group = "qnofiles" };

	my $uid = getpwnam($user);
	my $gid = getgrnam($group);

	unless ( -e $logbase ) 
	{
		mkpath($logbase, 0, 0755) or warn "Couldn't create $logbase: $!\n";
		chown($uid, $gid, $logbase) or warn "Couldn't chown $logbase to $uid: $!\n";
	} 
	else 
	{
		chown($uid, $gid, $logbase) or warn "Couldn't chown $logbase to $uid: $!\n";
	};

	my $dir = "$logbase/$counters";

	unless ( -e $dir ) 
	{
		mkpath($dir, 0, 0755) or warn "Couldn't create $dir: $!\n";
		chown($uid, $gid, $dir) or warn "Couldn't chown $dir to $uid: $!\n";
	} 
	else 
	{
		unless ( -d $dir ) 
		{
			warn "Please remove $dir. It needs to be a directory!\n";
		};
	};

	my $script = "/usr/local/sbin/maillogs";

	unless ( -e $script ) { print "WARNING: $script must be installed!\n"; } 
	else 
	{
		print "WARNING: $script must be executable!\n" unless (-x $script);
	};
};

sub CheckForFlags($$;$)
{

=head2 CheckForFlags

	use Mail::Toaster::Logs;
	CheckForFlags($conf, $prot, $debug);

$conf is a hashref of configuration values, assumed to be pulled from toaster-watcher.conf.$prot is the protocol we're supposed to work on. Do the appropriate things based on what argument is passed on the command line.

=cut

	my ($conf, $prot, $debug) = @_;

	my $syslog  = SetSyslog();

	print "CheckForFlags: prot is $prot\n" if $debug;

	if ($prot) 
	{
		print "working on protocol: $prot\n" if $debug;
		if    ( $prot eq "smtp"         ) { CountSMTP  ( $conf, $syslog, $debug ) }
		elsif ( $prot eq "rbl"          ) { CountRBL   ( $conf, $debug  ) }
		elsif ( $prot eq "send"         ) { CountSend  ( $conf, $debug  ) }
		elsif ( $prot eq "pop3"         ) { CountPOP3  ( $conf, $syslog, $debug ) } 
		elsif ( $prot eq "imap"         ) { CountIMAP  ( $conf, $syslog, $debug ) } 
		elsif ( $prot eq "spamassassin" ) { CountSpamA ( $conf, $syslog, $debug ) }
		elsif ( $prot eq "qmailscanner" ) { CountQMS   ( $conf, $syslog, $debug ) }
		elsif ( $prot eq "webmail"      ) { CountWebMail($conf, $syslog, $debug ) }; 
	}
	else
	{
		print "Mail::Logs by Matt Simerson v$VERSION\n\n";
		print "\nI need you to pass me a command like this:\n\n";
		die "maillog <protocol> [-r] [-v]

<protocol> is one of: smtp, rbl, send, pop3, imap, spamassassin, qmailscanner, webmail\n\n";
	};
};

sub CountRBL($;$)
{

=head2 CountRBL

	use Mail::Toaster::Logs;
	CountRBL($conf, $debug);

Count the number of connections we've blocked (via rblsmtpd) for each RBL that we use.

=cut

	my ($conf, $debug) = @_;

	my $logbase   = $conf->{'logs_base'};
	my $counters  = $conf->{'logs_counters'};
	my $rbl_log   = $conf->{'logs_rbl_count'};
	my $supervise = $conf->{'logs_supervise'};

	unless ($logbase)   { $logbase   = "/var/log/mail"; };
	unless ($counters)  { $counters  = "counters"; };
	unless ($rbl_log)   { $rbl_log   = "smtp_rbl.txt"; };
	unless ($supervise) { $supervise = "/var/qmail/supervise"; };

	my $countfile = "$logbase/$counters/$rbl_log";
	my %spam      = ReadCounters($countfile, $debug);

	ProcessRblLogs(\%spam, $conf, "0", $debug, CheckLogFiles("$logbase/smtp/current") );

	print "      Spam Counts\n\n" if $debug;

	my $i = 0;
	foreach my $key (sort keys %spam) 
	{
		print ":" if ( $i > 0 );
		print "$key:$spam{$key}";
		$i++;
	};
	print "\n";

	RotateMailLogs( "$supervise/smtp/log" );
	CompressYesterdaysLogfile( $conf, "smtplog" );
};

sub CountSMTP($$;$)
{

=head2 CountSMTP

	use Mail::Toaster::Logs;
	CountSMTP($conf, $syslog, $debug);

Count the number of times users authenticate via SMTP-AUTH to our qmail-smtpd daemon.

=cut

	my ($conf, $syslog, $debug) = @_;

	my $logbase   = $conf->{'logs_base'};
	my $counters  = $conf->{'logs_counters'};
	my $smtp_log  = $conf->{'logs_smtp_count'};
	my $supervise = $conf->{'logs_supervise'};

	unless ($logbase)   { $logbase   = "/var/log/mail"; };
	unless ($counters)  { $counters  = "counters"; };
	unless ($smtp_log)  { $smtp_log  = "smtp_rbl.txt"; };
	unless ($supervise) { $supervise = "/var/qmail/supervise"; };

	my $countfile = "$logbase/$counters/$smtp_log";
	my %count     = ReadCounters($countfile, $debug);

	print "      SMTP Counts\n\n" if ($debug);
	
	my @logfiles = CheckLogFiles( $syslog );

	if ( $logfiles[0] eq "" ) 
	{
		warn "\nCountSMTP: Ack, no logfiles!\n\n";
	} 
	else 
	{
		my $success   = `grep "vchkpw-smtp:" @logfiles | grep success | wc -l`;
		my $connect   = `grep "vchkpw-smtp:" @logfiles | wc -l`;

		$success   = $success * 1;
		$connect   = $connect * 1;

		if ( $success >= $count{'success_last'} ) 
		{
		 	$count{'success'} = $count{'success'} + ( $success - $count{'success_last'} ) 
		}
		else  { $count{'success'} = $count{'success'} + $success };

		if ( $connect >= $count{'connect_last'} )
		{
			$count{'connect'} = $count{'connect'} + ( $connect - $count{'connect_last'} ) 
		}
		else  { $count{'connect'} = $count{'connect'} + $connect };

		$count{'success_last'} = $success;
		$count{'connect_last'} = $connect;
	};

	print "smtp_auth_connect:$count{'connect'}:smtp_auth_success:$count{'success'}\n";

	WriteCounters($countfile, %count);	
};

sub CountSend($;$)
{

=head2 CountSend

	use Mail::Toaster::Logs;
	CountSend($conf, $debug);

Count the number of messages we deliver, and a whole mess of stats from qmail-send.

=cut

	my ($conf, $debug) = @_;

	my $logbase   = $conf->{'logs_base'};
	my $counters  = $conf->{'logs_counters'};
	my $send_log  = $conf->{'logs_send_count'};
	my $isoqlog   = $conf->{'logs_isoqlog'};
	my $supervise = $conf->{'logs_supervise'};

	unless ($counters)  { $counters= "counters"; };
	unless ($logbase)   { $logbase = "/var/log/mail"; };
	unless ($send_log)  { $send_log = "send.txt"; };
	unless ($isoqlog)   { $isoqlog = 1; };
	unless ($supervise) { $supervise = "/var/qmail/supervise"; };

	my $countfile = "$logbase/$counters/$send_log";
	my %count     = ReadCounters($countfile, $debug);

	ProcessSendLogs(0, $conf, \%count, $debug, CheckLogFiles("$logbase/send/current") );

	if ( $count{'status_remotep'} && $count{'status'} ) {
		$count{'concurrencyremote'} = ( $count{'status_remotep'} / $count{'status'}) * 100;
	};

	print "      Counts\n\n" if $debug;

	my $i = 0;
	foreach my $key (sort keys %count) 
	{
		print ":" if ( $i > 0 );
		print "$key:$count{$key}";
		$i++;
	};
	print "\n";

	RotateMailLogs( "$supervise/send/log" );
	if ( $isoqlog ) 
	{
		my $isoqlogbin = FindTheBin("isoqlog");
		SysCmd($isoqlogbin) if ( -x $isoqlogbin );
	};

	CompressYesterdaysLogfile( $conf, "sendlog" );
	PurgeLastMonthLogs();
};

sub CountIMAP($$;$)
{

=head2 CountIMAP

	use Mail::Toaster::Logs;
	CountIMAP($conf, $syslog, $debug);

Count the number of connections and successful authentications via IMAP and IMAP-SSL.

=cut

	my ($conf, $syslog, $debug) = @_;

	my ($imap_success, $imap_connect, $imap_ssl_success, $imap_ssl_connect);
	my @logfiles = CheckLogFiles( $syslog );

	my $logbase   = $conf->{'logs_base'};
	my $counters  = $conf->{'logs_counters'};
	my $imap_log  = $conf->{'logs_imap_count'};

	unless ($logbase)   { $logbase = "/var/log/mail"; };
	unless ($counters)  { $counters= "counters"; };
	unless ($imap_log)  { $imap_log = "imap.txt"; };

	my $countfile = "$logbase/$counters/$imap_log";
	my %count     = ReadCounters($countfile, $debug);

	if ( $logfiles[0] eq "" ) 
	{
		warn "\n   CountIMAP ERROR: no logfiles!\n\n";
	} 
	else 
	{
		$imap_success      = `grep "imapd: LOGIN" @logfiles | wc -l`;
		$imap_connect      = `grep "imapd: Connection" @logfiles | wc -l`;
		$imap_ssl_success  = `grep "imapd-ssl: LOGIN" @logfiles | wc -l`;
		$imap_ssl_connect  = `grep "imapd-ssl: Connection" @logfiles | wc -l`;
		chomp ($imap_success, $imap_connect, $imap_ssl_success, $imap_ssl_connect);

		if ( $imap_success >= $count{'imap_success_last'} ) { 
			$count{'imap_success'} = $count{'imap_success'} + 
			( $imap_success - $count{'imap_success_last'} ) }
		else  { $count{'imap_success'} = $count{'imap_success'} + $imap_success };

		if ( $imap_ssl_success >= $count{'imap_ssl_success_last'} ) { 
			$count{'imap_ssl_success'} = $count{'imap_ssl_success'} + 
			( $imap_ssl_success - $count{'imap_ssl_success_last'} ) }
		else  { $count{'imap_ssl_success'} = $count{'imap_ssl_success'} + $imap_ssl_success };

		if ( $imap_connect >= $count{'imap_connect_last'} ) { 
			$count{'imap_connect'} = $count{'imap_connect'} + 
			( $imap_connect - $count{'imap_connect_last'} ) }
		else  { $count{'imap_connect'} = $count{'imap_connect'} + $imap_connect };

		if ( $imap_ssl_connect >= $count{'imap_ssl_connect_last'} ) { 
			$count{'imap_ssl_connect'} = $count{'imap_ssl_connect'} + 
			( $imap_ssl_connect - $count{'imap_ssl_connect_last'} ) }
		else  { $count{'imap_ssl_connect'} = $count{'imap_ssl_connect'} + $imap_ssl_connect };

		$count{'imap_success_last'}     = $imap_success;
		$count{'imap_connect_last'}     = $imap_connect;
		$count{'imap_ssl_success_last'} = $imap_ssl_success;
		$count{'imap_ssl_connect_last'} = $imap_ssl_connect;
	};

	print "connect_imap:$count{'imap_connect'}:connect_imap_ssl:$count{'imap_ssl_connect'}:" .
		"imap_connect_success:$count{'imap_success'}:imap_ssl_success:$count{'imap_ssl_success'}\n";

	WriteCounters($countfile, %count);
};

sub CountPOP3($$;$)
{

=head2 CountPOP3

	use Mail::Toaster::Logs;
	CountPOP3($conf, $syslog, $debug);

Count the number of connections and successful authentications via POP3 and POP3-SSL.

=cut

	my ($conf, $syslog, $debug) = @_;

	my @logfiles = CheckLogFiles( $syslog );
	my ($pop3_success, $pop3_connect, $pop3_ssl_success, $pop3_ssl_connect);

	my $logbase   = $conf->{'logs_base'};
	my $counters  = $conf->{'logs_counters'};
	my $qpop_log  = $conf->{'logs_pop3_count'};
	my $supervise = $conf->{'logs_supervise'};
	my $pop3_logs = $conf->{'logs_pop3d'};

	unless ($logbase)  { $logbase = "/var/log/mail"; };
	unless ($counters) { $counters = "counters"; };
	unless ($qpop_log) { $qpop_log = "pop3.txt"; };
	unless ($supervise) { $supervise = "/var/qmail/supervise"; };
	unless ($pop3_logs) { $pop3_logs = "courier" };

	my $countfile = "$logbase/$counters/$qpop_log";
	my %count     = ReadCounters($countfile, $debug);

	if ( $logfiles[0] eq "" ) 
	{
		warn "    ERROR: no logfiles!\n\n";
	} 
	else 
	{
		print "checking files @logfiles.\n" if $debug;

		if ( $pop3_logs eq "qpop3d" ) 
		{
			$pop3_success = `grep vchkpw-pop3 @logfiles | grep success | wc -l`;
			$pop3_connect = `grep vchkpw-pop3 @logfiles | wc -l`;       
		} 
		elsif ( $pop3_logs eq "courier" ) 
		{
			$pop3_success = `grep "pop3d: LOGIN" @logfiles | wc -l`;
			$pop3_connect = `grep "pop3d: Connection" @logfiles | wc -l`;
		};

		$pop3_ssl_success  = `grep "pop3d-ssl: LOGIN" @logfiles | wc -l`;
		$pop3_ssl_connect  = `grep "pop3d-ssl: Connection" @logfiles | wc -l`;
		chomp( $pop3_success, $pop3_connect, $pop3_ssl_success, $pop3_ssl_connect);

		if ( $pop3_success >= $count{'pop3_success_last'} ) { 
			$count{'pop3_success'} = $count{'pop3_success'} + 
			( $pop3_success - $count{'pop3_success_last'} ) }
		else  { $count{'pop3_success'} = $count{'pop3_success'} + $pop3_success };

		if ( $pop3_connect >= $count{'pop3_connect_last'} ) { 
			$count{'pop3_connect'} = $count{'pop3_connect'} + 
			( $pop3_connect - $count{'pop3_connect_last'} ) }
		else  { $count{'pop3_connect'} = $count{'pop3_connect'} + $pop3_connect };

		if ( $pop3_ssl_success >= $count{'pop3_ssl_success_last'} ) { 
			$count{'pop3_ssl_success'} = $count{'pop3_ssl_success'} + 
			( $pop3_ssl_success - $count{'pop3_ssl_success_last'} ) }
		else  { $count{'pop3_ssl_success'} = $count{'pop3_ssl_success'} + $pop3_ssl_success };

		if ( $pop3_ssl_connect >= $count{'pop3_ssl_connect_last'} ) { 
			$count{'pop3_ssl_connect'} = $count{'pop3_ssl_connect'} + 
			( $pop3_ssl_connect - $count{'pop3_ssl_connect_last'} ) }
		else  { $count{'pop3_ssl_connect'} = $count{'pop3_ssl_connect'} + $pop3_ssl_connect };

		$count{'pop3_success_last'}     = $pop3_success;
		$count{'pop3_connect_last'}     = $pop3_connect;
		$count{'pop3_ssl_success_last'} = $pop3_ssl_success;
		$count{'pop3_ssl_connect_last'} = $pop3_ssl_connect;
	};

	print "pop3_connect:$count{'pop3_connect'}:pop3_ssl_connect:$count{'pop3_ssl_connect'}:pop3_success:$count{'pop3_success'}:pop3_ssl_success:$count{'pop3_ssl_success'}\n";

	WriteCounters($countfile, %count);

	if ( $pop3_logs eq "qpop3d" ) 
	{
		RotateMailLogs( "$supervise/pop3/log" );
		CompressYesterdaysLogfile( $conf, "pop3log" );
	};
};

sub CountWebMail($$;$)
{

=head2 CountWebMail

	use Mail::Toaster::Logs;
	CountWebMail($conf, $syslog, $debug);

Count the number of webmail authentications.

=cut

	my ($conf, $syslog, $debug) = @_;
	my ($success, $connect);

	my @logfiles = CheckLogFiles( $syslog );

	my $logbase   = $conf->{'logs_base'};
	my $counters  = $conf->{'logs_counters'};
	my $web_log   = $conf->{'logs_web_count'};
	#my $supervise = $conf->{'logs_supervise'};

	unless ($logbase)  { $logbase  = "/var/log/mail"; };
	unless ($counters) { $counters = "counters"; };
	unless ($web_log)  { $web_log  = "webmail.txt"; };

	my $countfile = "$logbase/$counters/$web_log";
	my %count     = ReadCounters($countfile, $debug);

	if ( $logfiles[0] eq "" ) 
	{
		warn "\n    ERROR: no logfiles!\n\n";
	} 
	else 
	{
		$success   = `grep "Successful webmail login" @logfiles | wc -l`;
		$connect   = `grep "Successful webmail login" @logfiles | wc -l`;
		$success   = $success * 1;
		$connect   = $connect * 1;

		if ( $success >= $count{'success_last'} ) {
	 		$count{'success'} = $count{'success'} + ( $success - $count{'success_last'} ) }
		else  { $count{'success'} = $count{'success'} + $success };

		if ( $connect >= $count{'connect_last'} ) { 
			$count{'connect'} = $count{'connect'} + ( $connect - $count{'connect_last'} ) }
		else  { $count{'connect'} = $count{'connect'} + $connect };

		$count{'success_last'} = $success;
		$count{'connect_last'} = $connect;
	};

	print "connect:$count{'connect'}:success:$count{'success'}\n";

	WriteCounters($countfile, %count);
};

sub CountSpamA($$;$)
{

=head2 CountSpamA

	use Mail::Toaster::Logs;
	CountSpamA($conf, $syslog, $debug);

Count statistics logged by SpamAssassin.

=cut

	my ($conf, $syslog, $debug) = @_;
	my ($sa_clean, $sa_spam, $sa_clean_score, $sa_spam_score, $sa_threshhold);

	my $logbase   = $conf->{'logs_base'};
	my $counters  = $conf->{'logs_counters'};
	my $spam_log  = $conf->{'logs_spam_count'};

	unless ($logbase)  { $logbase   = "/var/log/mail"; };
	unless ($counters) { $counters  = "counters"; };
	unless ($spam_log) { $spam_log  = "spam.txt"; };

	my $countfile = "$logbase/$counters/$spam_log";
	my @logfiles  = CheckLogFiles( $syslog );
	my %count     = ReadCounters($countfile, $debug);

	if ( $logfiles[0] eq "" ) 
	{
		warn "\n   CountSpamAssassin ERROR: no logfiles!\n\n";
	} 
	else 
	{
		$sa_clean  = `grep spamd @logfiles | grep clean | wc -l`;
		$sa_clean  = $sa_clean * 1;
		$sa_spam   = `grep spamd @logfiles | grep "identified spam" | wc -l`;
		$sa_spam   = $sa_spam  * 1;

		if ( $sa_clean >= $count{'sa_clean_last'} ) {
	 		$count{'sa_clean'} = $count{'sa_clean'} + ( $sa_clean - $count{'sa_clean_last'} ) }
		else  { $count{'sa_clean'} = $count{'sa_clean'} + $sa_clean };
	
		if ( $sa_spam >= $count{'sa_spam_last'} ) { 
			$count{'sa_spam'} = $count{'sa_spam'} + ( $sa_spam - $count{'sa_spam_last'} ) }
		else  { $count{'sa_spam'} = $count{'sa_spam'} + $sa_spam };

		my $i;
		my @lines = `grep spamd @logfiles | grep "identified spam" | cut -d"(" -f2 | cut -d"/" -f1`;
		foreach my $line (@lines) { $sa_spam_score = $sa_spam_score + $line; $i++ };
		$sa_spam_score = floor($sa_spam_score / $i) if ($sa_spam_score);
		$count{'sa_spam_score'}  = $sa_spam_score;

		$i = 0;
		@lines = `grep spamd @logfiles | grep "clean" | cut -d"(" -f2 | cut -d"/" -f1`;
		foreach my $line (@lines) { $sa_clean_score = $sa_clean_score + $line; $i++ };
		$sa_clean_score = ($sa_clean_score / $i) if $sa_clean_score;
		$count{'sa_clean_score'} = $sa_clean_score;

		@lines = `grep spamd @logfiles | grep "identified spam" | cut -d"(" -f2 | cut -d"/" -f2 | cut -d ")" -f1`;
		chomp @lines;
		$sa_threshhold = $lines[0];
		$count{'sa_threshhold'}  = $sa_threshhold;

		$count{'sa_clean_last'}  = $sa_clean;
		$count{'sa_spam_last'}   = $sa_spam;
	};

	print "sa_spam:$count{'sa_spam'}:sa_clean:$count{'sa_clean'}:sa_spam_score:$sa_spam_score:sa_clean_score:$sa_clean_score:sa_threshhold:$sa_threshhold\n";

	WriteCounters($countfile, %count);
};

sub CountQMS($$;$)
{

=head2 CountQMS

	use Mail::Toaster::Logs;
	CountQMS($conf, $syslog, $debug);

Count statistics logged by qmail scanner.

=cut

	my ($conf, $syslog, $debug) = @_;
	my ($qs_clean, $qs_virus, $qs_all);

	my $logbase    = $conf->{'logs_base'};
	my $counters   = $conf->{'logs_counters'};
	my $virus_log  = $conf->{'logs_virus_count'};

	unless ($logbase)   { $logbase = "/var/log/mail"; };
	unless ($counters)  { $counters = "counters" };
	unless ($virus_log) { $virus_log = "virus.txt" };

	#my $supervise = $conf->{'logs_supervise'};

	my $countfile = "$logbase/$counters/$virus_log";
	my @logfiles  = CheckLogFiles( $syslog );
	my %count     = ReadCounters($countfile, $debug);

	if ( $logfiles[0] eq "" ) 
	{
		warn "\n    ERROR: no logfiles!\n\n";
	} 
	else 
	{
		$qs_clean  = `grep " qmail-scanner" @logfiles | grep "Clear:" | wc -l`;
		$qs_clean  = $qs_clean  * 1;
		$qs_all    = `grep " qmail-scanner" @logfiles | wc -l`;
		$qs_virus  = $qs_all - $qs_clean;

		if ( $qs_clean >= $count{'qs_clean_last'} ) { 
			$count{'qs_clean'} = $count{'qs_clean'} + ( $qs_clean - $count{'qs_clean_last'} ) }
		else  { $count{'qs_clean'} = $count{'qs_clean'} + $qs_clean };

		if ( $qs_virus >= $count{'qs_virus_last'} ) { 
			$count{'qs_virus'} = $count{'qs_virus'} + ( $qs_virus - $count{'qs_virus_last'} ) }
		else  { $count{'qs_virus'} = $count{'qs_virus'} + $qs_virus };

		$count{'qs_clean_last'} = $qs_clean;
		$count{'qs_virus_last'} = $qs_virus;
	};

	print "qs_clean:$qs_clean:qs_virii:$qs_virus\n";

	WriteCounters($countfile, %count);
};

sub RollSendLogs($;$)
{

=head2 RollSendLogs

	use Mail::Toaster::Logs;
	RollSendLogs($conf, $debug);

Roll the qmail-send multilog logs. Update the maillogs counter.

=cut

	my ($conf, $debug) = @_;

	my $logbase   = $conf->{'logs_base'};
	my $counters  = $conf->{'logs_counters'};
	my $send_log  = $conf->{'logs_send_count'};

	unless ($logbase)  { $logbase = "/var/log/mail"; };
	unless ($counters) { $counters = "counters"; };
	unless ($send_log) { $send_log = "send.txt"; };

	my $countfile = "$logbase/$counters/$send_log";
	my %count     = ReadCounters($countfile, $debug);

	ProcessSendLogs("1", $conf, \%count, $debug, CheckLogFiles("$logbase/send/current") );

	WriteCounters($countfile, %count);
};

sub RollRblLogs($;$)
{

=head2 RollRblLogs

	use Mail::Toaster::Logs;
	RollRblLogs($conf, $debug);

Roll the qmail-smtpd logs (without 2>&1 output generated by rblsmtpd).

=cut

	my ($conf, $debug) = @_;

	my $logbase   = $conf->{'logs_base'};
	my $counters  = $conf->{'logs_counters'};
	my $rbl_log   = $conf->{'logs_rbl_count'};

	unless ($logbase)  { $logbase = "/var/log/mail"; };
	unless ($counters) { $counters = "counters"; };
	unless ($rbl_log)  { $rbl_log =  "smtp_rbl.txt" };

	my $cronolog  = FindTheBin("cronolog");
	my $countfile = "$logbase/$counters/$rbl_log";
	my %spam      = ReadCounters($countfile, $debug);

	ProcessRblLogs(\%spam, $conf, "1", $debug, "| $cronolog $logbase/\%Y/\%m/\%d/smtplog" );

	WriteCounters($countfile, %spam);
};

sub RollPOP3Logs($;$)
{

=head2 RollPOP3Logs

	use Mail::Toaster::Logs;
	RollPOP3Logs($conf);

These logs will only exist if tcpserver debugging is enabled. Rolling them is not likely to be necessary but the code is here should it ever prove necessary.

=cut

#	my $countfile = "$logbase/$counters/$qpop_log";
#	%count        = ReadCounters($countfile, $debug);

	my ($conf, $debug) = @_;

	my $logbase = $conf->{'logs_base'};
	unless ($logbase)  { $logbase = "/var/log/mail"; };

	ProcessPOP3Logs("1", CheckLogFiles("$logbase/pop3/current") );

#	WriteCounters($countfile, %count);
#	RotateMailLogs( "$supervise/pop3/log" );
	CompressYesterdaysLogfile( $conf, "pop3log" );
};

sub CompressYesterdaysLogfile($$;$)
{

=head2 CompressYesterdaysLogfile

	use Mail::Toaster::Logs;
	CompressYesterdaysLogfile($conf, $file, $debug);

You'll have to guess what this does. ;)

=cut

	my ($conf, $file, $debug) = @_;
	my ($dd, $mm, $yy) = SetupDateVariables(-86400);

	my $logbase = $conf->{'logs_base'};
	unless ($logbase)  { $logbase = "/var/log/mail"; };

	my $log  = "$logbase/$yy/$mm/$dd/$file";
	my $gzip = FindTheBin("gzip");

	if ( -s $log && ! -e "$log.gz") 
	{
		print "   Compressing the logfile $log..." if $debug;
		system "$gzip $log";
		print "done.\n\n" if $debug;
	} 
	elsif ( -s "${log}.gz" ) 
	{
		print "   $log is already compressed\n\n" if $debug;
	} 
	else { print "   $log does not exist.\n\n" if $debug; };
};

sub PurgeLastMonthLogs($$;$)
{

=head2 PurgeLastMonthLogs

	use Mail::Toaster::Logs;
	PurgeLastMonthLogs($conf, $protdir, $debug);

Keep guessing... 

=cut

	my ($conf, $protdir, $debug) = @_;

	my ($dd, $mm, $yy) = SetupDateVariables(-2592000);

	my $logbase = $conf->{'logs_base'};
	unless ($logbase)  { $logbase = "/var/log/mail"; };

	my $last_m_log = "$logbase/$yy/$mm";

	if ( -d $last_m_log ) 
	{
		print "\nI'm about to delete $last_m_log...." if $debug;
		rmtree($last_m_log);
		print "done.\n\n" if $debug;
	} 
	else 
	{
		print "\nLast months log dir $last_m_log doesn't exist.\n\n" if $debug;
	};
};

sub RotateMailLogs(@)
{

=head2 RotateMailLogs

	use Mail::Toaster::Logs;
	RotateMailLogs(@dirs);

Tell multilog to rotate the maillogs for the array of dirs supplied.

=cut

	my (@dirs) = @_;

	my $svc        = FindTheBin("svc");
	foreach my $dir ( @dirs ) { system "$svc -a $dir" };
};
 
sub SetupDateVariables($)
{

=head2 SetupDateVariables

	use Mail::Toaster::Logs;
	SetupDateVariables($offset);

=cut

	my ($offset) = @_;

	$offset = 0 unless ($offset);

	MATT::Perl::LoadModule("Date::Format");

	my $dd = Date::Format::time2str( "%d", (time + $offset) );
	my $mm = Date::Format::time2str( "%m", (time + $offset) );
	my $yy = Date::Format::time2str( "%Y", (time + $offset) );

	return $dd, $mm, $yy;
};

sub CheckLogFiles(@)
{

=head2 CheckLogFiles

	use Mail::Toaster::Logs;
	CheckLogFiles(@check);

=cut

	my @check = @_;
	my @result;

	foreach my $logfile ( @check ) 
	{
		if ( -s $logfile ) { push @result, $logfile };
	};
	return @result;
};

sub ProcessPOP3Logs($$@)
{

=head2 ProcessPOP3Logs

=cut

	my ($conf, $roll, @files) = @_;
	my $cronolog   = FindTheBin("cronolog");

	if ($roll) 
	{
		my $logbase  = $conf->{'logs_base'};
		unless ($logbase)  { $logbase = "/var/log/mail"; };

		open OUT, "| $cronolog $logbase/\%Y/\%m/\%d/pop3log";
		while (<STDIN>) 
		{
			chomp;
			print "$_\n" if $conf->{'logs_taifiles'};
			print OUT "$_\n" if $conf->{'logs_archve'};
		};
		close OUT;
	}
};

sub ProcessRblLogs($$$$@)
{

=head2 ProcessRblLogs

=cut

	my ($spam, $conf, $roll, $debug, @files) = @_;

	if ($roll) 
	{
		open OUT, $files[0];
		while (<STDIN>) {
			chomp;
			CountRblLine($spam, $_, $debug);
			print "$_\n" if $conf->{'logs_taifiles'};
			print OUT "$_\n" if $conf->{'logs_archive'};
		};
		close OUT;
	}
	else 
	{
		foreach my $file (@files) 
		{
			print "ProcessRblLogs: reading file $file..." if $debug;
			open(INFILE, $file) or warn "couldn't read $file: $!\n";
			while (<INFILE>) 
			{
				chomp;
				CountRblLine($spam, $_, $debug);
			};
			close(INFILE);
			print "done.\n" if $debug;
		};
	};
};
 
sub CountRblLine($$;$)
{

=head2 CountRblLine

=cut

	my ($spam, $line, $debug) = @_;

	if    ( $_ =~ /dsbl/ )       { $spam->{'smtp_block_dsbl'}++;     } 
	elsif ( $_ =~ /spamhaus/ )   { $spam->{'smtp_block_spamhaus'}++; } 
	elsif ( $_ =~ /spamcop/ )    { $spam->{'smtp_block_spamcop'}++;  } 
	elsif ( $_ =~ /ORDB/ )       { $spam->{'smtp_block_ordb'}++;     } 
	elsif ( $_ =~ /mail-abuse/ ) { $spam->{'smtp_block_maps'}++;     } 
	elsif ( $_ =~ /Reverse/ )    { $spam->{'smtp_block_dns'}++;      }
	else  { print $line if $debug; $spam->{'smtp_block_other'}++;    };

	$spam->{'smtp_block_count'}++;
};

sub ProcessSendLogs($$$$@)
{

=head2 ProcessSendLogs

=cut

	my ($roll, $conf, $count, $debug, @files) = @_;

	my $logbase  = $conf->{'logs_base'};
	unless ($logbase) { $logbase = "/var/log/mail"; };

	my $cronolog   = FindTheBin("cronolog");
	unless ( -x $cronolog ) { carp "Couldn't find cronolog!\n"; };

	if ($roll) 
	{
		open OUT, "| $cronolog $logbase/\%Y/\%m/\%d/sendlog";
		while (<STDIN>) 
		{
			chomp;
			CountSendLine($count, $_);
			print "$_\n" if $conf->{'logs_taifiles'};
			print OUT "$_\n" if $conf->{'logs_archive'};
		};
		close OUT;
	}
	else 
	{
		foreach my $file (@files) 
		{
			print "ProcessSendLogs: reading file $file.\n" if ($debug);
			open(INFILE, $file) or warn "couldn't read $file: $!\n";
			while (<INFILE>) 
			{
				chomp;
				CountSendLine($count, $_);
			};
			close (INFILE);
		};
	};
};
 
sub CountSendLine($$)
{

=head2 CountSendLine

=cut

	my ($count, $line) = @_;

	my ($date, $act) = $line =~ /^@([a-z0-9]*)\s(.*)$/;
		
	unless ( $act ) { $count->{'message_other'}++; return; };

	if    ( $act =~ /^new msg ([0-9]*)/ ) { $count->{'message_new'}++; } 
	elsif ( $act =~ /^info msg ([0-9]*): bytes ([0-9]*) from \<(.*)\> qp ([0-9]*)/ ) 
	{
		$count->{'message_bytes'} = $count->{'message_bytes'} + $2;
		$count->{'message_info'}++;
	} 
	elsif ( $act =~ /^starting delivery ([0-9]*): msg ([0-9]*) to ([a-z]*) / ) 
	{
		if    ($3 eq "remote") { $count->{'start_delivery_remote'}++  } 
		elsif ($3 eq "local" ) { $count->{'start_delivery_local' }++  };
		$count->{'start_delivery'}++;
	} 
	elsif ( $act =~ /^status: local ([0-9]*)\/([0-9]*) remote ([0-9]*)\/([0-9]*)/ ) 
	{
		$count->{'status_localp'}  = $count->{'status_localp'} + ( $1 / $2 );
		$count->{'status_remotep'} = $count->{'status_remotep'} + ( $3 / $4 );
		$count->{'status'}++;
	}
	elsif ( $act =~ /^end msg ([0-9]*)/ ) 
	{
		$count->{'local'}++ if ( $3 && $3 eq "local");
		$count->{'message_end'}++;
	} 
	elsif ( $act =~ /^delivery ([0-9]*): ([a-z]*):/ ) 
	{
		if    ( $2 eq "success"  ) { $count->{'delivery_success' }++  }
		elsif ( $2 eq "deferral" ) { $count->{'delivery_deferral'}++  }
		elsif ( $2 eq "failure"  ) { $count->{'delivery_failure' }++  }
		else                       { print $act . "\n"; };

		$count->{'delivery'}++;
	} 
	elsif ( $act =~ /^bounce msg ([0-9]*) [a-z]* ([0-9]*)/ ) 
	{
		$count->{'message_bounce'}++;
	} 
	else 
	{
		print "other: $act\n";
		$count->{'other'}++;
	};
};

sub ReadCounters($;$)
{

=head2 ReadCounters

	use Mail::Toster::Logs;
	ReadCounters($file, $debug);

$file is the file to read from. $debug is optional, it prints out verbose messages during the process. The sub returns a hashref full of key value pairs.

=cut

	my ($file, $debug) = @_;
	my %hash;

	print "ReadCounters: fetching counters from $file..." if $debug;

	my @lines = ReadFile($file);
	unless ( $lines[0]) 
	{
		print "\n\nWARN: the file $file is empty! Creating...";

		my %spam = ( "created" => time() );
		WriteCounters($file, %spam);

		print "done.\n";
		return 0;
	} 
	else 
	{
		foreach my $line (@lines)
		{
			my @f = split(":", $line);
			$hash{$f[0]} = $f[1];
		};
	};

	print "done.\n" if $debug;

	return %hash;
};

sub WriteCounters($%)
{

=head2 WriteCounters

	use Mail::Toster::Logs;
	WriteCounters($file, %values);

$file is the logfile to write to.

%values is a hash of value=count style pairs.

=cut

	my ($log, %hash) = @_;
	my @lines;

	if ( -d $log ) { print "FAILURE: WriteCounters $log is a directory!\n"; };

	unless ( -e $log ) {
		print "WARNING: WriteCounters $log does not exist! Creating...";
	};

	unless ( -w  $log) {
		print "FAILURE: WriteCounters $log is  not writable!\n";
	}

	# it might be necessary to wrap the counters at some point
	#
	# if so, the 32 and 64 bit limits are listed below. Just
	# check the number, and subtract the maximum value for it.
	# rrdtool will continue to Do The Right Thing. :)

	foreach my $key (sort keys %hash)
	{
		if ($key && $hash{$key} ) 
		{
			# 32 bit - 4294967295
			# 64 bit - 18446744073709551615
			push @lines, "$key:$hash{$key}";
		};
	};

	WriteFile($log, @lines);
};

sub WhatAmI(;$)
{

=head2 WhatAmI

	use Mail::Toaster::Logs;
	WhatAmI(;$debug)

Determine what the filename of this program is. This is used in maillogs, as maillogs gets renamed in order to function as a log post-processor for multilog.

=cut

	my ($debug) = @_;

	print "WhatAmI: $0 \n" if $debug;
	$0 =~ /([a-zA-Z0-9]*)$/;
	print "WhatAmI: returning $1\n" if $debug;
	return $1;
};

sub SetSyslog()
{

=head2 SetSyslog

	use Mail::Toaster::Logs;
	SetSyslog();

Determine where syslog.mail is logged to. Right now we just test based on the OS you're running on and assume you've left it in the default location. This is easy to expand later.

=cut

	if    ( (uname)[0] eq "FreeBSD" ) { return "/var/log/maillog"; }
	elsif ( (uname)[0] eq "Darwin"  ) { return "/var/log/mail.log" }
	else  { return "/var/log/maillog" };
};

1;
__END__

=head1	Design considerations

=over 4

=item * Counters will be polled via SNMP. Script must be able to return counts instantly, even when dealing with HUGE logs.

=item * Must work with multilog and syslog logging formats

=item * Outputs data in a format suitable for polling via SNMP

=item * Simple configuration

=item * Fail safe, errors must be noticed and reported but not fatal

=back

=cut


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>


=head1 BUGS

None known. Report any to author.


=head1 SEE ALSO

http://www.tnpi.biz/internet/mail/toaster/

Mail::Toaster::CGI, Mail::Toaster::DNS, Mail::Toaster::Logs,
Mail::Toaster::Qmail, Mail::Toaster::Setup


=head1 COPYRIGHT

Copyright 2003, The Network People, Inc.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
