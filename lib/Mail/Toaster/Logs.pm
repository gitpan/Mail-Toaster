#!/usr/bin/perl
use strict;

#
# $Id: Logs.pm,v 4.7 2005/03/21 16:20:52 matt Exp $
#

package Mail::Toaster::Logs;

use Carp;
use Getopt::Std;
use POSIX;   # needed for floor()

use vars qw( $VERSION);
$VERSION = "4.5";

use lib "lib";
use lib "../..";
use Mail::Toaster::Utility; my $utility = Mail::Toaster::Utility->new;
use Mail::Toaster::Perl;    my $perl    = Mail::Toaster::Perl->new;
use vars qw/ %spam /;

use File::Path;
#use POSIX;

my $os = $^O;

=head1 NAME

Mail::Toaster::Logs

=head1 SYNOPSIS

Perl modules related to mail logging. These modules are used primarily in maillogs but may be used in toaster-watcher.pl and toaster_setup.pl as well.

=head1 METHODS

=head2 new

Create a new Mail::Toaster::Logs object.

    use Mail::Toaster::Logs;
    $logs = Mail::Toaster::Logs->new;

=cut

sub new
{
	my ($class) = @_;
	my $self = { class=>$class };
	bless ($self, $class);
	return $self;
};


=head2 ReportYesterday

email a report of yesterdays email traffic.

=cut

sub ReportYesterday($)
{
	my ($conf) = @_;

	my $debug   = $conf->{'debug'};
	my $qmadir  = $conf->{'qmailanalog_bin'};     $qmadir  ||= "/usr/local/qmailanalog/bin";
	my $email   = $conf->{'toaster_admin_email'}; $email   ||= "postmaster";
	my $logbase = $conf->{'logs_base'};           $logbase ||= $conf->{'qmail_log_base'};
	$logbase ||= "/var/log/mail";

	my ($dd, $mm, $yy) = SetupDateVariables();
	my $file = "sendlog";
	my $log  = "$logbase/$yy/$mm/$dd/$file";
	print "ReportYesterday: updating todays symlink for sendlogs\n" if $debug;
	unlink("$logbase/sendlog") if ( -l "$logbase/sendlog" );
	symlink($log, "$logbase/sendlog");

	($dd, $mm, $yy) = SetupDateVariables(-86400);

	$file = "sendlog.gz";
	$log  = "$logbase/$yy/$mm/$dd/$file";
	print "ReportYesterday: updating yesterdays symlink for sendlogs\n" if $debug;
	unlink ("$logbase/sendlog.0.gz") if ( -l "$logbase/sendlog.0.gz");
	symlink($log, "$logbase/sendlog.0.gz");

	print "processing log: $log\n" if $debug;
	my $gzcat = $utility->find_the_bin("gzcat");

	print "calculating overall stats with:\n" if $debug;
	print "`$gzcat $log | $qmadir/matchup 5>/dev/null | $qmadir/zoverall`\n" if $debug;
	my $overall   = `$gzcat $log | $qmadir/matchup 5>/dev/null | $qmadir/zoverall`;
	print "calculating failure stats with:\n" if $debug;
	print "`$gzcat $log | $qmadir/matchup 5>/dev/null | $qmadir/zfailures`\n" if $debug;
	my $failures  = `$gzcat $log | $qmadir/matchup 5>/dev/null | $qmadir/zfailures`;
	print "calculating deferral stats\n" if $debug;
	print "`$gzcat $log | $qmadir/matchup 5>/dev/null | $qmadir/zdeferrals`\n" if $debug;
	my $deferrals = `$gzcat $log | $qmadir/matchup 5>/dev/null | $qmadir/zdeferrals`;

	my $date = "$yy.$mm.$dd";
	print "date: $yy.$mm.$dd\n" if $debug;

	open EMAIL, "| /var/qmail/bin/qmail-inject";
	print EMAIL "To: $email\n";
	print EMAIL "From: postmaster\n";
	print EMAIL "Subject: Daily Mail Toaster Report for $date\n";
	print EMAIL "\n";
	print EMAIL "           OVERALL MESSAGE DELIVERY STATISTICS\n\n";
	print EMAIL $overall;
	print EMAIL "\n\n\n            MESSAGE FAILURE REPORT\n\n";
	print EMAIL $failures;
	print EMAIL "\n\n\n            MESSAGE DEFERRAL REPORT  \n\n";
	print EMAIL $deferrals;
	close EMAIL;

	print "all done!\n";
};

=head2 CheckSetup

Does some checks to make sure things are set up correctly.

    $logs->CheckSetup($conf);

tests: 

  logs base directory exists
  logs based owned by qmaill
  counters directory exists
  maillogs is installed

=cut

sub CheckSetup($)
{
	my ($self, $conf) = @_;

	my $logbase  = $conf->{'logs_base'};     $logbase  ||= $conf->{'qmail_log_base'};
	my $counters = $conf->{'logs_counters'}; $counters ||= "counters";
	$logbase  ||= "/var/log/mail";

	my $user  = $conf->{'logs_user'};     $user  ||= "qmaill"  ;
	my $group = $conf->{'logs_group'};    $group ||= "qnofiles";
	my $uid   = getpwnam($user);
	my $gid   = getgrnam($group);

	unless ( -e $logbase ) 
	{
		mkpath($logbase, 0, 0755) or carp "Couldn't create $logbase: $!\n";
		chown($uid, $gid, $logbase) or carp "Couldn't chown $logbase to $uid: $!\n";
	} 
	else 
	{
		if ( $uid && -w $logbase ) {
			chown($uid, $gid, $logbase) or carp "Couldn't chown $logbase to $uid: $!\n";
		};
	};

	my $dir = "$logbase/$counters";

	unless ( -e $dir ) 
	{
		mkpath($dir, 0, 0755) or carp "Couldn't create $dir: $!\n";
		chown($uid, $gid, $dir) or carp "Couldn't chown $dir to $uid: $!\n";
	} 
	else 
	{
		unless ( -d $dir ) 
		{
			carp "Please remove $dir. It needs to be a directory!\n";
		};
	};

	my $script = "/usr/local/sbin/maillogs";

	unless ( -e $script ) { print "WARNING: $script must be installed!\n"; } 
	else 
	{
		print "WARNING: $script must be executable!\n" unless (-x $script);
	};
};

=head2 CheckForFlags

Do the appropriate things based on what argument is passed on the command line.

	$logs->CheckForFlags($conf, $prot, $debug);

$conf is a hashref of configuration values, assumed to be pulled from toaster-watcher.conf.

$prot is the protocol we're supposed to work on. 

=cut

sub CheckForFlags($$;$)
{
	my ($self, $conf, $prot, $debug) = @_;

	my $syslog  = $self->syslog_locate($debug);

	print "CheckForFlags: prot is $prot\n" if $debug;

	if ($debug) { $conf->{'debug'} = 1 };

	if ($prot) 
	{
		print "working on protocol: $prot\n" if $debug;
		if    ( $prot eq "smtp"         ) { $self->smtp_count  ( $conf, $syslog ) }
		elsif ( $prot eq "rbl"          ) { $self->rbl_count   ( $conf          ) }
		elsif ( $prot eq "send"         ) { $self->send_count  ( $conf          ) }
		elsif ( $prot eq "pop3"         ) { $self->pop3_count  ( $conf, $syslog ) } 
		elsif ( $prot eq "imap"         ) { $self->imap_count  ( $conf, $syslog ) } 
		elsif ( $prot eq "spamassassin" ) { $self->spama_count ( $conf, $syslog ) }
		elsif ( $prot eq "qmailscanner" ) { $self->qms_count   ( $conf, $syslog ) }
		elsif ( $prot eq "webmail"      ) { $self->webmail_count($conf, $syslog ) }
		elsif ( $prot eq "yesterday"    ) { ReportYesterday ($conf      ) };
	}
	else
	{
		print "Mail::Logs by Matt Simerson v$VERSION\n\n";
		print "\nI need you to pass me a command like this:\n\n";
		croak "maillog <protocol> [-r] [-v]

<protocol> is one of: 

          smtp - report SMTP AUTH attempts and successes
           rbl - report RBL blocks
          send - report qmail-send counters
          pop3 - report pop3 counters
          imap - report imap counters
  spamassassin - report spamassassin counters
  qmailscanner - report qmailscanner counters
       webmail - count webmail authentications

     yesterday - mail an activity report to the admin\n\n";
	};
};

sub rbl_count($)
{

=head2 rbl_count

Count the number of connections we've blocked (via rblsmtpd) for each RBL that we use.

	$logs->rbl_count($conf, $debug);

=cut

	my ($self, $conf) = @_;

	my $debug     = $conf->{'debug'};
	my $logbase   = $conf->{'logs_base'};      $logbase   ||= "/var/log/mail";
	my $counters  = $conf->{'logs_counters'};  $counters  ||= "counters";
	my $rbl_log   = $conf->{'logs_rbl_count'}; $rbl_log   ||= "smtp_rbl.txt";
	my $supervise = $conf->{'logs_supervise'}; $supervise ||= "/var/qmail/supervise";

	my $countfile = "$logbase/$counters/$rbl_log";
	   %spam      = $self->counter_read($countfile, $debug);

	ProcessRblLogs($conf, "0", $debug, CheckLogFiles("$logbase/smtp/current") );

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

	$self->counter_write($countfile, %spam);
};

sub smtp_count($$)
{

=head2 smtp_count

	$logs->smtp_count($conf, $syslog);

Count the number of times users authenticate via SMTP-AUTH to our qmail-smtpd daemon.

=cut

	my ($self, $conf, $syslog) = @_;

	my $debug     = $conf->{'debug'};
	my $logbase   = $conf->{'logs_base'};       $logbase   ||= "/var/log/mail";
	my $counters  = $conf->{'logs_counters'};   $counters  ||= "counters";
	my $smtp_log  = $conf->{'logs_smtp_count'}; $smtp_log  ||= "smtp_rbl.txt";
	my $supervise = $conf->{'logs_supervise'};  $supervise ||= "/var/qmail/supervise";

	my $countfile = "$logbase/$counters/$smtp_log";
	my %count     = $self->counter_read($countfile, $debug);

	print "      SMTP Counts\n\n" if ($debug);

	my @logfiles = CheckLogFiles( $syslog );

	if ( $logfiles[0] eq "" ) 
	{
		carp "\nsmtp_count: Ack, no logfiles!\n\n";
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

	$self->counter_write($countfile, %count);	
};

sub send_count($)
{

=head2 send_count

	$logs->send_count($conf);

Count the number of messages we deliver, and a whole mess of stats from qmail-send.

=cut

	my ($self, $conf) = @_;

	my $debug     = $conf->{'debug'};
	my $logbase   = $conf->{'logs_base'};       $logbase  ||= "/var/log/mail";
	my $counters  = $conf->{'logs_counters'};   $counters ||= "counters";
	my $send_log  = $conf->{'logs_send_count'}; $send_log ||= "send.txt";
	my $isoqlog   = $conf->{'logs_isoqlog'};
	my $supervise = $conf->{'logs_supervise'};  $supervise = "/var/qmail/supervise";

	my $countfile = "$logbase/$counters/$send_log";
	my %count     = $self->counter_read($countfile, $debug);

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
		my $isoqlogbin = $utility->find_the_bin("isoqlog");
		$utility->syscmd($isoqlogbin) if ( -x $isoqlogbin );
	};

	CompressYesterdaysLogfile( $conf, "sendlog" );
	PurgeLastMonthLogs();
};

sub imap_count($$)
{

=head2 imap_count

	$logs->imap_count($conf, $syslog);

Count the number of connections and successful authentications via IMAP and IMAP-SSL.

=cut

	my ($self, $conf, $syslog) = @_;

	my ($imap_success, $imap_connect, $imap_ssl_success, $imap_ssl_connect);
	my @logfiles = CheckLogFiles( $syslog );

	my $debug     = $conf->{'debug'};
	my $logbase   = $conf->{'logs_base'};       $logbase  ||= "/var/log/mail";
	my $counters  = $conf->{'logs_counters'};   $counters ||= "counters";
	my $imap_log  = $conf->{'logs_imap_count'}; $imap_log ||= "imap.txt";

	my $countfile = "$logbase/$counters/$imap_log";
	my %count     = $self->counter_read($countfile, $debug);

	if ( $logfiles[0] eq "" ) 
	{
		carp "\n   imap_count ERROR: no logfiles!\n\n";
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

	$self->counter_write($countfile, %count);
};

sub pop3_count($$)
{

=head2 pop3_count

	$logs->pop3_count($conf, $syslog);

Count the number of connections and successful authentications via POP3 and POP3-SSL.

=cut

	my ($self, $conf, $syslog) = @_;

	my @logfiles = CheckLogFiles( $syslog );
	my ($pop3_success, $pop3_connect, $pop3_ssl_success, $pop3_ssl_connect);

	my $debug     = $conf->{'debug'};
	my $logbase   = $conf->{'logs_base'};       $logbase   ||= "/var/log/mail";
	my $counters  = $conf->{'logs_counters'};   $counters  ||= "counters";
	my $qpop_log  = $conf->{'logs_pop3_count'}; $qpop_log  ||= "pop3.txt";
	my $supervise = $conf->{'logs_supervise'};  $supervise ||= "/var/qmail/supervise";
	my $pop3_logs = $conf->{'logs_pop3d'};      $pop3_logs ||= "courier";

	my $countfile = "$logbase/$counters/$qpop_log";
	my %count     = $self->counter_read($countfile, $debug);

	if ( $logfiles[0] eq "" ) 
	{
		carp "    ERROR: no logfiles!\n\n";
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

	$self->counter_write($countfile, %count);

	if ( $pop3_logs eq "qpop3d" ) 
	{
		RotateMailLogs( "$supervise/pop3/log" );
		CompressYesterdaysLogfile( $conf, "pop3log" );
	};
};

sub webmail_count($$)
{

=head2 webmail_count

	$logs->webmail_count($conf, $syslog);

Count the number of webmail authentications.

=cut

	my ($self, $conf, $syslog) = @_;

	my @logfiles = CheckLogFiles( $syslog );

	my $debug     = $conf->{'debug'};
	my $logbase   = $conf->{'logs_base'};      $logbase  ||= "/var/log/mail";
	my $counters  = $conf->{'logs_counters'};  $counters ||= "counters";
	my $web_log   = $conf->{'logs_web_count'}; $web_log  ||= "webmail.txt";
	#my $supervise = $conf->{'logs_supervise'};

	my $countfile = "$logbase/$counters/$web_log";
	my %count     = $self->counter_read($countfile, $debug);

	if ( $logfiles[0] eq "" ) 
	{
		carp "\n    ERROR: no logfiles!\n\n";
	} 
	else 
	{
		# older log style
		my $success   = `grep "Successful webmail login" @logfiles | wc -l`;
		my $connect   = `grep "Successful webmail login" @logfiles | wc -l`;

		# newer log entries
		# Feb 21 10:24:41 cadillac sqwebmaild: LOGIN, user=matt@cadillac.net, ip=[66.227.213.209]
		# Feb 21 10:27:00 cadillac sqwebmaild: LOGIN FAILED, user=matt@cadillac.net, ip=[66.227.213.209]
		my $failed    = `grep webmail @logfiles | grep "LOGIN FAILED" | wc -l`;
		my $connect2  = `grep webmail @logfiles | grep LOGIN | wc -l`;
		my $success2  = $connect2 - $failed;

		$success   = $success + $success2;
		$connect   = $connect + $connect2;

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

	$self->counter_write($countfile, %count);
};

sub spama_count($$)
{

=head2 spama_count

	$logs->spama_count($conf, $syslog);

Count statistics logged by SpamAssassin.

=cut

	my ($self, $conf, $syslog) = @_;
	my ($sa_clean, $sa_spam, $sa_clean_score, $sa_spam_score, $sa_threshhold);

	my $debug     = $conf->{'debug'};
	my $logbase   = $conf->{'logs_base'};       $logbase   ||= "/var/log/mail";
	my $counters  = $conf->{'logs_counters'};   $counters  ||= "counters";
	my $spam_log  = $conf->{'logs_spam_count'}; $spam_log  ||= "spam.txt";

	my $countfile = "$logbase/$counters/$spam_log";
	my @logfiles  = CheckLogFiles( $syslog );
	my %count     = $self->counter_read($countfile, $debug);

	if ( $logfiles[0] eq "" ) 
	{
		carp "\n   spamassassin_count ERROR: no logfiles!\n\n";
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

	$self->counter_write($countfile, %count);
};

sub qms_count($$)
{

=head2 qms_count

	$logs->qms_count($conf, $syslog);

Count statistics logged by qmail scanner.

=cut

	my ($self, $conf, $syslog) = @_;
	my ($qs_clean, $qs_virus, $qs_all);

	my $debug      = $conf->{'debug'};
	my $logbase    = $conf->{'logs_base'};        $logbase   ||= "/var/log/mail";
	my $counters   = $conf->{'logs_counters'};    $counters  ||= "counters";
	my $virus_log  = $conf->{'logs_virus_count'}; $virus_log ||= "virus.txt";
	#my $supervise = $conf->{'logs_supervise'};

	my $countfile = "$logbase/$counters/$virus_log";
	my @logfiles  = CheckLogFiles( $syslog );
	my %count     = $self->counter_read($countfile, $debug);

	if ( $logfiles[0] eq "" ) 
	{
		carp "\n    ERROR: no logfiles!\n\n";
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

	$self->counter_write($countfile, %count);
};

sub RollSendLogs($;$)
{

=head2 RollSendLogs

	$logs->RollSendLogs($conf, $debug);

Roll the qmail-send multilog logs. Update the maillogs counter.

=cut

	my ($self, $conf, $debug) = @_;

	my $logbase   = $conf->{'logs_base'};       $logbase  ||= "/var/log/mail";
	my $counters  = $conf->{'logs_counters'};   $counters ||= "counters";
	my $send_log  = $conf->{'logs_send_count'}; $send_log ||= "send.txt";

	my $countfile = "$logbase/$counters/$send_log";
	my %count     = $self->counter_read($countfile, $debug);

	ProcessSendLogs("1", $conf, \%count, $debug, CheckLogFiles("$logbase/send/current") );

	$self->counter_write($countfile, %count);
};

sub RollRblLogs($;$)
{

=head2 RollRblLogs

	$logs->RollRblLogs($conf, $debug);

Roll the qmail-smtpd logs (without 2>&1 output generated by rblsmtpd).

=cut

	my ($self, $conf, $debug) = @_;

	my $logbase   = $conf->{'logs_base'};      $logbase  ||= "/var/log/mail";
	my $counters  = $conf->{'logs_counters'};  $counters ||= "counters";
	my $rbl_log   = $conf->{'logs_rbl_count'}; $rbl_log  ||= "smtp_rbl.txt";

	my $cronolog  = $utility->find_the_bin("cronolog");
	my $countfile = "$logbase/$counters/$rbl_log";
	   %spam      = $self->counter_read($countfile, $debug);

	my $tai64nlocal;
	if ( $conf->{'logs_archive_untai'} ) {
		my $taibin = $utility->find_the_bin("tai64nlocal");
		if ( $taibin && -x $taibin ) { $tai64nlocal = $taibin; };
	};

	if ($tai64nlocal) {
		ProcessRblLogs($conf, "1", $debug, "| $tai64nlocal | $cronolog $logbase/\%Y/\%m/\%d/smtplog" );
	} else {
		ProcessRblLogs($conf, "1", $debug, "| $cronolog $logbase/\%Y/\%m/\%d/smtplog" );
	};

	$self->counter_write($countfile, %spam);
};

sub RollPOP3Logs($;$)
{

=head2 RollPOP3Logs

	$logs->RollPOP3Logs($conf);

These logs will only exist if tcpserver debugging is enabled. Rolling them is not likely to be necessary but the code is here should it ever prove necessary.

=cut

#	my $countfile = "$logbase/$counters/$qpop_log";
#	%count        = $self->counter_read($countfile, $debug);

	my ($self, $conf, $debug) = @_;

	my $logbase = $conf->{'logs_base'}; $logbase ||= "/var/log/mail";

	ProcessPOP3Logs($conf, "1", CheckLogFiles("$logbase/pop3/current") );

#	$self->counter_write($countfile, %count);
#	RotateMailLogs( "$supervise/pop3/log" );
	CompressYesterdaysLogfile( $conf, "pop3log" );
};

sub CompressYesterdaysLogfile($$;$)
{

=head2 CompressYesterdaysLogfile

	CompressYesterdaysLogfile($conf, $file, $debug);

You'll have to guess what this does. ;)

=cut

	my ($conf, $file, $debug) = @_;
	my ($dd, $mm, $yy) = SetupDateVariables(-86400);

	my $logbase = $conf->{'logs_base'}; $logbase ||= "/var/log/mail";

	my $log  = "$logbase/$yy/$mm/$dd/$file";
	my $gzip = $utility->find_the_bin("gzip");

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

	PurgeLastMonthLogs($conf, $protdir, $debug);

Keep guessing... 

=cut

	my ($conf, $protdir, $debug) = @_;

	my ($dd, $mm, $yy) = SetupDateVariables(-2592000);

	my $logbase = $conf->{'logs_base'}; $logbase ||= "/var/log/mail";

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

	RotateMailLogs(@dirs);

Tell multilog to rotate the maillogs for the array of dirs supplied.

=cut

	my (@dirs) = @_;

	my $svc = $utility->find_the_bin("svc");
	for ( @dirs ) { $utility->syscmd("$svc -a $_") };
};
 
sub SetupDateVariables($)
{

=head2 SetupDateVariables

	SetupDateVariables($offset);

=cut

	my ($offset) = @_;

	$offset = 0 unless ($offset);

	$perl->module_load( {module=>"Date::Format"} );

	my $dd = Date::Format::time2str( "%d", (time + $offset) );
	my $mm = Date::Format::time2str( "%m", (time + $offset) );
	my $yy = Date::Format::time2str( "%Y", (time + $offset) );

	return $dd, $mm, $yy;
};

sub CheckLogFiles(@)
{

=head2 CheckLogFiles

	CheckLogFiles(@check);

=cut

	my @check = @_;
	my @result;

	foreach my $logfile ( @check ) 
	{
		if ( -e $logfile ) { push @result, $logfile };
#		if ( -s $logfile ) { push @result, $logfile };
	};
	return @result;
};

sub ProcessPOP3Logs($$@)
{

=head2 ProcessPOP3Logs

=cut

	my ($conf, $roll, @files) = @_;
	my $cronolog   = $utility->find_the_bin("cronolog");

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

sub ProcessRblLogs($$$@)
{

=head2 ProcessRblLogs

=cut

#	ProcessRblLogs($conf, "0", $debug, CheckLogFiles("$logbase/smtp/current") );

	my ($conf, $roll, $debug, @files) = @_;

	if ($roll) 
	{
		open OUT, $files[0];
		while (<STDIN>) {
			chomp;
			CountRblLine($_, $debug);
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
			open(INFILE, $file) or carp "couldn't read $file: $!\n";
			while (<INFILE>) 
			{
				chomp;
				CountRblLine($_, $debug);
			};
			close(INFILE);
			print "done.\n" if $debug;
		}
	}
}
 
sub CountRblLine($$;$)
{

=head2 CountRblLine

=cut

	my ($line, $debug) = @_;

	if    ( $_ =~ /dsbl/ )       { $spam{'smtp_block_dsbl'}++;     } 
	elsif ( $_ =~ /spamhaus/ )   { $spam{'smtp_block_spamhaus'}++; } 
	elsif ( $_ =~ /spamcop/ )    { $spam{'smtp_block_spamcop'}++;  } 
	elsif ( $_ =~ /ORDB/ )       { $spam{'smtp_block_ordb'}++;     } 
	elsif ( $_ =~ /mail-abuse/ ) { $spam{'smtp_block_maps'}++;     } 
	elsif ( $_ =~ /Reverse/ )    { $spam{'smtp_block_dns'}++;      }
	else  { print $line if $debug; $spam{'smtp_block_other'}++;    };

	$spam{'smtp_block_count'}++;
};

sub ProcessSendLogs($$$$@)
{

=head2 ProcessSendLogs

=cut

	my ($roll, $conf, $count, $debug, @files) = @_;

	my $logbase  = $conf->{'logs_base'}; $logbase ||= "/var/log/mail";

	my $cronolog   = $utility->find_the_bin("cronolog");
	unless ( -x $cronolog ) { carp "Couldn't find cronolog!\n"; };

	my $tai64nlocal;
	if ( $conf->{'logs_archive_untai'} ) {
		my $taibin = $utility->find_the_bin("tai64nlocal");
		if ( $taibin && -x $taibin ) { $tai64nlocal = $taibin; };
	};

	if ($roll) 
	{
		if ( $tai64nlocal ) {
			open OUT, "| $tai64nlocal | $cronolog $logbase/\%Y/\%m/\%d/sendlog";
		} else {
			open OUT, "| $cronolog $logbase/\%Y/\%m/\%d/sendlog";
		};

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
			open(INFILE, $file) or carp "couldn't read $file: $!\n";
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

sub counter_read($;$)
{

=head2 counter_read

	$logs->counter_read($file, $debug);

$file is the file to read from. $debug is optional, it prints out verbose messages during the process. The sub returns a hashref full of key value pairs.

=cut

	my ($self, $file, $debug) = @_;
	my %hash;

	print "counter_read: fetching counters from $file..." if $debug;

	my @lines = $utility->file_read($file);
	unless ( $lines[0]) 
	{
		print "\n\nWARN: the file $file is empty! Creating...";

		my %hash = ( "created" => time() );
		$self->counter_write($file, %hash);

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

sub counter_write($%)
{

=head2 counter_write

	$logs->counter_write($file, %values);

$file is the logfile to write to.

%values is a hash of value=count style pairs.

returns 1 if writable, 0 if not.

=cut

	my ($self, $log, %hash) = @_;
	my @lines;

	if ( -d $log ) { print "FAILURE: counter_write $log is a directory!\n"; };

	return 0 unless $utility->file_check_writable($log);

	unless ( -e $log ) {
		print "WARNING: counter_write $log does not exist! Creating...";
	};

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

	my $r = $utility->file_write($log, @lines);
	$r ? return 1 : return 0;
};

sub what_am_i(;$)
{

=head2 what_am_i

	$logs->what_am_i(;$debug)

Determine what the filename of this program is. This is used in maillogs, as maillogs gets renamed in order to function as a log post-processor for multilog.

=cut

	my ($self, $debug) = @_;

	print "what_am_i: $0 \n" if $debug;
	$0 =~ /([a-zA-Z0-9\.]*)$/;
	print "what_am_i: returning $1\n" if $debug;
	return $1;
};

sub syslog_locate(;$)
{

=head2 syslog_locate

	$logs->syslog_locate($debug);

Determine where syslog.mail is logged to. Right now we just test based on the OS you're running on and assume you've left it in the default location. This is easy to expand later.

=cut

	my ($self, $debug) = @_;

	if    ( $os eq "freebsd" )
	{
		if ( -e "/var/log/maillog" ) {
			print "syslog_locate: FreeBSD detected...using /var/log/maillog\n" if $debug;
			return "/var/log/maillog"; 
		} else {
			croak "syslog_locate: can't find your syslog mail log\n";
		};
	}
	elsif ( $os eq "darwin"  ) 
	{ 
		if ( -e "/var/log/mail.log" ) {
			print "syslog_locate: Darwin detected...using /var/log/mail.log\n" if $debug;
			return "/var/log/mail.log";
		} else {
			croak "syslog_locate: can't find your syslog mail log\n";
		};
	}
	else  
	{ 
		if ( -e "/var/log/maillog" ) {
			print "syslog_locate: Darwin detected...using /var/log/mail.log\n" if $debug;
			return "/var/log/maillog";
		} else {
			croak "syslog_locate: can't find your syslog mail log\n";
		};
	};
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

The following are all man/perldoc pages: 

 Mail::Toaster 
 Mail::Toaster::Apache 
 Mail::Toaster::CGI  
 Mail::Toaster::DNS 
 Mail::Toaster::Darwin
 Mail::Toaster::Ezmlm
 Mail::Toaster::FreeBSD
 Mail::Toaster::Logs 
 Mail::Toaster::Mysql
 Mail::Toaster::Passwd
 Mail::Toaster::Perl
 Mail::Toaster::Provision
 Mail::Toaster::Qmail
 Mail::Toaster::Setup
 Mail::Toaster::Utility

 Mail::Toaster::Conf
 toaster.conf
 toaster-watcher.conf

 http://matt.simerson.net/computing/mail/toaster/
 http://matt.simerson.net/computing/mail/toaster/docs/


=head1 COPYRIGHT

Copyright (c) 2004-2005, The Network People, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
