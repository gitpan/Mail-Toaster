#!/usr/bin/perl
use strict;

#
# $Id: Qmail.pm,v 1.22 2004/02/14 21:40:46 matt Exp $
#

package Mail::Toaster::Qmail;

use Carp;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION = '1.28';

@ISA     = qw(Exporter);
@EXPORT  = qw(
		StopQmailSend
		StartQmailSend
		RestartQmailSmtpd
		CheckQmailControl 
		CheckQmailQueue 
		ProcessQmailQueue
		CheckRcpthosts
		ConfigQmail
		ConfigureQmailControl
		InstallQmailSuperviseRunFiles
		InstallQmailSuperviseLogRunFiles
		TestSmtpdConfigValues
		GetQmailScannerVirusSenderIPs
		UpdateVirusBlocks
	);
@EXPORT_OK = qw(
		GetListOfRWLs
		GetListOfRBLs
		TestEachRBL
		BuildSendRun
		BuildSmtpRun
		BuildSubmitRun
		BuildPOP3Run
		SetServiceDir
		InstallQmailServiceRun
		GetDomainsFromAssign
	);

use MATT::Utility;

=head1 NAME

Mail::Toaster:::Qmail - Common Qmail functions

=head1 SYNOPSIS

Mail::Toaster::Qmail is frequently used functions I've written for perl use with Qmail.

=head1 DESCRIPTION

This module has all sorts of goodies, the most useful of which are the Build????Run modules which build your qmail control files for you. 

=cut

sub GetQmailScannerVirusSenderIPs
{
	my ($conf, $debug) = @_;
	my @ips;

	my $block = $conf->{'qs_block_virus_senders'};
	my $clean = $conf->{'qs_quarantine_clean'};
	my $quarantine = $conf->{'qs_quarantine_dir'};

	unless (-d $quarantine)
	{
		if ( -d "/var/spool/qmailscan/quarantine" )
		{
			$quarantine = "/var/spool/qmailscan/quarantine";
		};
	};
	die "no quarantine dir!" unless (-d "$quarantine/new");

	my @files = MATT::Utility::GetDirFiles("$quarantine/new");

	foreach my $file (@files)
	{
		if ( $block ) {
			my $ipline = `head -n 10 $file | grep HELO`;
			chomp $ipline;

			next unless ($ipline);
			print " $ipline  - " if $debug;

			my @lines = split(/Received/, $ipline);
			foreach my $line (@lines)
			{
				print $line if $debug;

				# Received: from unknown (HELO netbible.org) (202.54.63.141)
				my ($ip) = $line =~ /([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/;

				if ( $ip =~ /\s+/ or ! $ip )
				{
					print "$line\n" if $debug;
				}
				else { push @ips, $ip; };
				print "\t$ip" if $debug;
			};
			print "\n" if $debug;
		};
		unlink $file if ($clean);
	};

	my (%hash, @sorted);
	foreach my $ip (@ips) { $hash{$ip} = "1"; };
	foreach my $key ( keys %hash ) { push @sorted, $key; delete $hash{$key} };
	return @sorted;
};

sub UpdateVirusBlocks
{
	my ($conf, @ips) = @_;

	my $time  = $conf->{'qs_block_virus_senders_time'};
	my $relay = $conf->{'smtpd_relay_database'};
	my $vpdir = $conf->{'vpopmail_home_dir'};
	unless ($vpdir) { $vpdir = "/usr/local/vpopmail"; };

	if ( $relay =~ /^vpopmail_home_dir\/(.*)\.cdb$/ ) { $relay = "$vpdir/$1" };
	unless ( -r $relay ) { die "$relay selected but not readable!\n" };

	my @lines;

	my $debug = 0;
	my $in = 0;
	my $done = 0;
	my $now = time;
	my $expire = time + ($time * 3600);

	print "now: $now   expire: $expire\n" if $debug;

	my @userlines = ReadFile($relay);
	USERLINES: foreach my $line (@userlines)
	{
		unless ($in) { push @lines, $line };
		if ($line eq "### BEGIN QMAIL SCANNER VIRUS ENTRIES ###")
		{
			$in = 1;

			foreach my $ip (@ips)
			{
				push @lines, "$ip:allow,RBLSMTPD=\"-VIRUS SOURCE: Block will be automatically removed in $time hours: ($expire)\"\n";
			};
			$done++;
			next USERLINES;
		};

		if ($line eq "### END QMAIL SCANNER VIRUS ENTRIES ###")
		{
			$in = 0;
			push @lines, $line;
			next USERLINES;
		};

		if ($in) 
		{
			my ($timestamp) = $line =~ /\(([0-9]+)\)"$/;
			unless ($timestamp) { print "ERROR: malformed line: $line\n" if $debug; };

			if ($now > $timestamp ) {
				print "removing $timestamp\t" if $debug;
			} else {
				print "leaving $timestamp\t" if $debug;
				push @lines, $line;
			};
		};
	};

	if ($done)
	{
		if ($debug) {
			foreach my $line (@lines) { print "$line\n"; };
		};
		WriteFile($relay, @lines);
	} 
	else { print "FAILURE: Couldn't find QS section in $relay\n"; };
};

sub GetListOfRWLs
{

=head2 GetListOfRWLs

	use Mail::Toaster::Qmail
	my $list = GetListOfRWLs($conf, $debug);

Here we collect a list of the RWLs from the configuration file that get's passed to us. We return an arrayref with a list of the enabled ones.

=cut

	my ($hash, $debug) = @_;
	my @list;

	foreach my $key ( keys %$hash )
	{		
		if ( $key =~ /^rwl/ && $hash->{$key} == 1 ) 
		{
			next if ( $key =~ /^rwl_enable/ );
			$key =~ /^rwl_([a-zA-Z_\.\-]*)\s*$/;

			print "good key: $1 \n" if $debug;
			push @list, $1;
		};
	};
	return \@list;
};

sub TestEachRBL
{

=head2 TestEachRBL

	use Mail::Toaster::Qmail
	my $list = TestEachRBL($arrayref, $debug);

We get a list of RBL's in an arrayref and we run some tests on them to determine if they are working correctly. We return a list of the correctly functioning RBLs.

=cut

	my ($rbls, $debug) = @_;
	my @list;

	use Mail::Toaster::DNS;
	foreach my $rbl (@$rbls)
	{
		print "testing $rbl.... " if $debug;
		my $r = Mail::Toaster::DNS::RblTest($rbl, $debug);
		if ( $r ) { push @list, $rbl };
		print "$r \n" if $debug;
	};
	return \@list;
};


sub GetListOfRBLs
{

=head2 GetListOfRBLs

	use Mail::Toaster::Qmail
	my $list = GetListOfRBLs($arrayref, $debug);

We get passwd a configuration file (toaster-watcher.conf) and from it we extract all the RBL's the user has selected and return them as an array ref.

=cut

	my ($hash, $debug) = @_;
	my @list;

	foreach my $key ( keys %$hash )
	{		
		#print "checking $key \n" if $debug;
		if ( $key =~ /^rbl/ && $hash->{$key} == 1 ) 
		{
			next if ( $key =~ /^rbl_enable/ );
			next if ( $key =~ /^rbl_reverse_dns/ );
			$key =~ /^rbl_([a-zA-Z_\.\-]*)\s*$/;

			print "good key: $1 \n" if $debug;
			push @list, $1;
		};
	};
	return \@list;
};

sub BuildSendRun
{

=head2 BuildSendRun

	use Mail::Toaster::Qmail;
	if ( BuildSendRun($conf, $file, $debug) ) { print "success"};

BuildSendRun generates a supervise run file for qmail-send. $file is the location of the file it's going to generate. $conf is a list of configuration variables pulled from a config file (see ParseConfigfile). I typically use it like this:

	my $file = "/tmp/toaster-watcher-send-runfile";
	if ( BuildSendRun($conf, $file ) )
	{
		InstallQmailServiceRun($file, "$supervise/send/run");
	};

If it succeeds in building the file, it will install it. You can optionally restart qmail after installing a new run file.

=cut

	my ($conf, $file, $debug) = @_;
	my ($mem);

	my   @lines = "#!/bin/sh\n";
	push @lines, "PATH=$conf->{'qmail_dir'}/bin:/usr/local/bin:/usr/bin:/bin";
	push @lines, "export PATH\n";

	my $qsupervise = $conf->{'qmail_supervise'};
	unless ( $qsupervise )
	{
		print "BuildSendRun: WARNING: qmail_supervise not set in toaster-watcher.conf!\n";
	};
	unless ( -d $qsupervise )
	{
		SysCmd("mkdir -p $qsupervise");
	};

	my $mailbox = $conf->{'send_mailbox_string'};
	unless ($mailbox) { $mailbox = "./Maildir/"; };

	my $send_log = $conf->{'send_log_method'};
	unless ($send_log) { $send_log = "syslog"; };

	if ($send_log eq "syslog") 
	{
		push @lines, "# This uses splogger to send logging through syslog";
		push @lines, "# Change this in /usr/local/etc/toaster-watcher.conf";
		push @lines, "exec qmail-start $mailbox splogger qmail";
	} else {
		push @lines, "# This sends the output to multilog as directed in log/run";
		push @lines, "# make changes in /usr/local/etc/toaster-watcher.conf";
		push @lines, "exec qmail-start $mailbox 2>&1";
	};
	push @lines, "\n";

	if ( WriteFile($file, @lines) ) { return 1 } 
	else { print "error writing file $file\n"; return 0; };
};

sub BuildPOP3Run
{

=head2 BuildPOP3Run

	use Mail::Toaster::Qmail;
	if ( BuildPOP3Run($conf, $file, $debug) ) { print "success"};

Generate a supervise run file for qmail-pop3d. $file is the location of the file it's going to generate. $conf is a list of configuration variables pulled from a config file (see ParseConfigfile). I typically use it like this:

	my $file = "/tmp/toaster-watcher-pop3-runfile";
	if ( BuildPOP3Run($conf, $file ) )
	{
		InstallQmailServiceRun($file, "$supervise/pop3/run");
	};

If it succeeds in building the file, it will install it. You can optionally restart the service after installing a new run file.

=cut


	my ($conf, $file, $debug) = @_;
	my ($mem);

	my $vdir  = $conf->{'vpopmail_home_dir'};
	unless ( $vdir) { $vdir = "/usr/local/vpopmail"; };

	my $qctrl = $conf->{'qmail_dir'} . "/control";

	my $qsupervise = $conf->{'qmail_supervise'};
	unless ( -d $qsupervise )
	{
		print "BuildPOP3Run: FAILURE: supervise dir $qsupervise doesn't exist!\n";
		return 0;
	};

	my   @lines = "#!/bin/sh\n";
	push @lines, "PATH=$conf->{'qmail_dir'}/bin:$vdir/bin:/usr/local/bin:/usr/bin:/bin";
	push @lines, "export PATH\n";

	if ( $conf->{'pop3_hostname'} eq "qmail" ) {
		push @lines, "LOCAL=\`head -1 $qctrl/me\`";
		push @lines, "if [ -z \"\$LOCAL\" ]; then";
		push @lines, "\techo LOCAL is unset in $qsupervise/smtp/run";
		push @lines, "\texit 1";
		push @lines, "fi\n";
	};

#exec softlimit -m 2000000 tcpserver -v -R -H -c50 0 pop3 

	if ( $conf->{'pop3_max_memory_per_connection'} > 0 ) {
		$mem  = $conf->{'pop3_max_memory_per_connection'} * 1024000; } 
	else { $mem = "3000000" };

	my $exec = "exec softlimit -m $mem tcpserver ";

	if ( $conf->{'pop3_lookup_tcpremotehost'}  == 0 ) { $exec .= "-H " };
	if ( $conf->{'pop3_lookup_tcpremoteinfo'}  == 0 ) { $exec .= "-R " };
	if ( $conf->{'pop3_dns_paranoia'}          == 1 ) { $exec .= "-p " };
	if ( $conf->{'pop3_max_connections'} != 40      ) { 
		$exec .= "-c$conf->{'pop3_max_connections'} ";
	};

	if ( $conf->{'pop3_dns_lookup_timeout'} != 26 ) {
		$exec .= "-t$conf->{'pop3_dns_lookup_timeout'} ";
	};

	if ( $conf->{'pop3_listen_on_address'} && $conf->{'pop3_listen_on_address'} ne "all" ) 
	{
		$exec .= "$conf->{'pop3_listen_on_address'} ";
	} 
	else {  $exec .= "0 " };

	if ( $conf->{'pop3_listen_on_port'} && $conf->{'pop3_listen_on_port'} ne "pop3" ) 
	{
		$exec .= "$conf->{'pop3_listen_on_port'} ";
	} 
	else {  $exec .= "pop3 " };

#qmail-popup mail.cadillac.net /usr/local/vpopmail/bin/vchkpw 
#qmail-pop3d Maildir 2>&1

	$exec .= "qmail-popup "; 

	if    ( $conf->{'pop3_hostname'} eq "qmail" ) 
	{
		$exec .= "\"\$LOCAL\" ";
	} 
	elsif ( $conf->{'pop3_hostname'} eq "system" ) 
	{
		use Sys::Hostname;
		$exec .= hostname() . " ";
	}
	else { $exec .= $conf->{'pop3_hostname'} . " " };
	
	my $chkpass = $conf->{'pop3_checkpasswd_bin'};
	unless ($chkpass) { 
		print "WARNING: pop3_checkpasswd_bin is not set in toaster-watcher.conf!\n";
		$chkpass = "$vdir/bin/vchkpw"; 
	};
	if ( $chkpass =~ /^vpopmail_home_dir\/(.*)$/ ) { $chkpass = "$vdir/$1" };
	unless ( -x $chkpass ) {
		warn "WARNING: chkpasss $chkpass selected but not executable!\n" 
	};
	$exec .= "$chkpass qmail-pop3d Maildir ";

	if ( $conf->{'pop3_log_method'} eq "syslog" )
	{
		$exec .= "splogger qmail ";
	}
	else { $exec .= "2>&1 " };

	push @lines, $exec;

	if ( WriteFile($file, @lines) ) { return 1 } 
	else { print "error writing file $file\n"; return 0; };
};

sub TestSmtpdConfigValues
{

=head2 TestSmtpdConfigValues

=cut

	my ($conf, $debug) = @_;

	my $file = "/usr/local/etc/toaster.conf";

	die "FAILURE: qmail_dir does not exist as configured in $file\n" 
		unless ( -d $conf->{'qmail_dir'} );

	die "FAILURE: vpopmail_home_dir does not exist as configured in $file!\n"  
		unless ( -d $conf->{'vpopmail_home_dir'} );

	die "FAILURE: qmail_supervise is not a directory!\n"
		unless ( -d $conf->{'qmail_supervise'} );

	die "FAILURE: smtpd_hostname is not set in $file.\n"
		unless ( $conf->{'smtpd_hostname'} );
};

sub SetServiceDir
{

=head2 SetServiceDir

This is necessary because things such as service directories are now in /var by default but older versions of my toaster installed them in /. This will detect and adjust for that.

=cut

	my ($conf, $prot) = @_;

	my $servicedir = $conf->{'qmail_service'};
	unless ($servicedir) { $servicedir = "/var/service"; };

	if ( ! -d $servicedir and $servicedir eq "/var/service" )
	{
		if ( -d "/service" )  { $servicedir = "/service" };
	};

	if ( $prot eq "smtp" ) 
	{
		my $dir = $conf->{'qmail_service_smtp'};
		unless ($dir) 
		{ 
			warn "WARNING: qmail_service_smtp is not set correctly in toaster-watcher.conf!\n";
			$dir = "$servicedir/smtp"; 
		};
		return $dir;
	} 
	elsif ( $prot eq "pop3" ) 
	{
		my $dir = $conf->{'qmail_service_pop3'};
		unless ($dir) 
		{ 
			warn "WARNING: qmail_service_pop3 is not set correctly in toaster-watcher.conf!\n";
			$dir = "$servicedir/pop3"; 
		};
		return $dir;
	} 
	elsif ( $prot eq "send" ) 
	{
		my $dir   = $conf->{'qmail_service_send'};

		unless ($dir) 
		{ 
			warn "WARNING: qmail_service_send is not set correctly in toaster-watcher.conf!\n";
			$dir = "$servicedir/send"; 
		};
		return $dir;
	}
	elsif ( $prot eq "submit" ) 
	{
		my $dir = $conf->{'qmail_service_submit'};
		unless ($dir) 
		{ 
			warn "WARNING: qmail_service_submit is not set correctly in toaster-watcher.conf!\n";
			$dir = "$servicedir/submit"; 
		};
		return $dir;
	};
};

sub BuildSmtpRun
{

=head2 BuildSmtpRun

	use Mail::Toaster::Qmail;
	if ( BuildSmtpRun($conf, $file, $debug) ) { print "success"};

Generate a supervise run file for qmail-smtpd. $file is the location of the file it's going to generate. $conf is a list of configuration variables pulled from a config file (see ParseConfigfile). I typically use it like this:

	my $file = "/tmp/toaster-watcher-smtpd-runfile";
	if ( BuildSmtpRun($conf, $file ) )
	{
		InstallQmailServiceRun($file, "$supervise/smtp/run");
	};

If it succeeds in building the file, it will install it. You can optionally restart the service after installing a new run file.

=cut

	my ($conf, $file, $debug) = @_;
	my ($mem);

	TestSmtpdConfigValues($conf, $debug);

	my $vdir = $conf->{'vpopmail_home_dir'};

	my   @lines = "#!/bin/sh\n";
	push @lines, "PATH=$conf->{'qmail_dir'}/bin:$vdir/bin:/usr/local/bin:/usr/bin:/bin";
	push @lines, "export PATH\n";

	if ( $conf->{'filtering_qmailscanner_method'} eq "smtp" )
	{
		my $queue = $conf->{'smtpd_qmail_queue'};
		unless ( -x $queue ) { 
			warn "WARNING: $queue is not executable by uid $>\n";
			return 0;
		};
		push @lines, "QMAILQUEUE=\"$queue\"";
		push @lines, "export QMAILQUEUE\n";
	};

	my $qctrl = $conf->{'qmail_dir'} . "/control";
	unless ( -d $qctrl ) {
		warn "WARNING: BuildSmtpRun failed. $qctrl is not a directory";
		return 0;
	};

	my $qsupervise = $conf->{'qmail_supervise'};
	return 0 unless ( -d $qsupervise );

	if ( $conf->{'smtpd_hostname'} eq "qmail" ) {
		push @lines, "LOCAL=\`head -1 $qctrl/me\`";
		push @lines, "if [ -z \"\$LOCAL\" ]; then";
		push @lines, "\techo LOCAL is unset in $qsupervise/smtp/run";
		push @lines, "\texit 1";
		push @lines, "fi\n";
	};

	push @lines, "if [ ! -f $qctrl/rcpthosts ]; then";
	push @lines, "\techo \"No $qctrl/rcpthosts!\"";
	push @lines, "\techo \"Refusing to start SMTP listener because it'll create an open relay\"";
	push @lines, "\texit 1";
	push @lines, "fi\n";

	if ( $conf->{'smtpd_max_memory_per_connection'} > 0 ) {
		$mem  = $conf->{'smtpd_max_memory_per_connection'} * 1024000; } 
	else { $mem = "8000000" };

	my $exec = "exec softlimit -m $mem tcpserver ";

	if ( $conf->{'smtpd_use_mysql_relay_table'} == 1 ) { $exec .= "-S " };
	if ( $conf->{'smtpd_lookup_tcpremotehost'}  == 0 ) { $exec .= "-H " };
	if ( $conf->{'smtpd_lookup_tcpremoteinfo'}  == 0 ) { $exec .= "-R " };
	if ( $conf->{'smtpd_dns_paranoia'}          == 1 ) { $exec .= "-p " };
	if ( $conf->{'smtpd_max_connections'} != 40      ) { 
		$exec .= "-c$conf->{'smtpd_max_connections'} ";
	};

	if ( $conf->{'smtpd_dns_lookup_timeout'} != 26      ) {
		$exec .= "-t$conf->{'smtpd_dns_lookup_timeout'} ";
	};

	my $cdb  = $conf->{'smtpd_relay_database'};
	print "smtpd relay db: $cdb\n" if $debug;
	if ( $cdb =~ /^vpopmail_home_dir\/(.*)$/ ) { $cdb = "$vdir/$1" };
	if ( -r $cdb ) { $exec .= "-x $cdb " } else { die "$cdb selected but not readable!\n" };

	my $uid = getpwnam( $conf->{'smtpd_run_as_user'}  );
	my $gid = getgrnam( $conf->{'smtpd_run_as_group'} );

	unless ( $uid && $gid ) { print "WARNING: uid and gid not found!\n"; return 0 };
	$exec .= "-u $uid -g $gid ";

	if ( $conf->{'smtpd_listen_on_address'} && $conf->{'smtpd_listen_on_address'} ne "all" ) 
	{
		$exec .= "$conf->{'smtpd_listen_on_address'} ";
	} 
	else {  $exec .= "0 " };

	if ( $conf->{'smtpd_listen_on_port'} && $conf->{'smtpd_listen_on_port'} ne "smtp" ) 
	{
		$exec .= "$conf->{'smtpd_listen_on_port'} ";
	} 
	else {  $exec .= "smtp " };

	if ( ( $conf->{'rwl_enable'} && $conf->{'rwl_enable'} > 0 ) 
	or   ( $conf->{'rbl_enable'} && $conf->{'rbl_enable'} > 0 )  )
	{
		$exec .= "rblsmtpd ";

		my $timeout = $conf->{'rbl_timeout'}; unless ($timeout) { $timeout = 60; };
		if ( $timeout != 60 ) { $exec .= "-t $timeout "; };

		if ( $conf->{'rbl_enable_fail_closed'} ) { $exec .= "-c "; };

		unless ( $conf->{'rbl_enable_soft_failure'} ) { $exec .= "-b "; };

		if ( $conf->{'rwl_enable'} && $conf->{'rwl_enable'} > 0 )
		{
			print "testing RWLs...." if $debug;
			my $list  = GetListOfRWLs($conf, $debug);
#			my $rwls  = test_each_rwl( $list, $debug);
#			foreach my $rwl ( @$rwls ) { $exec = $exec . "-a $rwl " };
			foreach my $rwl ( @$list ) { $exec = $exec . "-a $rwl " };
			print "done.\n" if $debug;
		} 
		else { print "no RWL's selected\n" if $debug };

		if ( $conf->{'rbl_enable'} && $conf->{'rbl_enable'} > 0 )
		{
			print "testing RBLs...." if $debug;
			my $list  = GetListOfRBLs($conf, $debug);
			my $rbls  = TestEachRBL( $list, $debug);
			foreach my $rbl ( @$rbls ) { $exec = $exec . "-r $rbl " };
			print "done.\n" if $debug;
		} 
		else { print "no RBL's selected\n" if $debug };
	};

	$exec .= "qmail-smtpd "; 

	if ( $conf->{'smtpd_auth_enable'} == 1 ) 
	{
		if    ( $conf->{'smtpd_hostname'} eq "qmail" ) 
		{
			$exec .= "\"\$LOCAL\" ";
		} 
		elsif ( $conf->{'smtpd_hostname'} eq "system" ) 
		{
			use Sys::Hostname;
			$exec .= hostname() . " ";
		}
		else { $exec .= $conf->{'smtpd_hostname'} . " " };
	
		my $chkpass = $conf->{'smtpd_checkpasswd_bin'};
		if ( $chkpass =~ /^vpopmail_home_dir\/(.*)$/ ) { $chkpass = "$vdir/$1" };
		die "$chkpass selected but not executable!\n" unless ( -x $chkpass );

		$exec .= "$chkpass /usr/bin/true ";
	};

	if ( $conf->{'smtpd_log_method'} eq "syslog" )
	{
		$exec = $exec . "splogger qmail ";
	}
	else { $exec = $exec . "2>&1 " };

	push @lines, $exec;

	if ( WriteFile($file, @lines) ) { return 1 } 
	else { print "error writing file $file\n"; return 0; };
};

sub BuildSubmitRun
{

=head2 BuildSubmitRun

	use Mail::Toaster::Qmail;
	if ( BuildSubmitRun($conf, $file, $debug) ) { print "success"};

Generate a supervise run file for qmail-smtpd running on submit. $file is the location of the file it's going to generate. $conf is a list of configuration variables pulled from a config file (see ParseConfigfile). I typically use it like this:

	my $file = "/tmp/toaster-watcher-smtpd-runfile";
	if ( BuildSubmitRun($conf, $file ) )
	{
		InstallQmailServiceRun($file, "$supervise/submit/run");
	};

If it succeeds in building the file, it will install it. You can optionally restart the service after installing a new run file.

=cut

	my ($conf, $file, $debug) = @_;
	my ($mem);

	TestSmtpdConfigValues($conf, $debug);

	my $vdir = $conf->{'vpopmail_home_dir'};

	my   @lines = "#!/bin/sh\n";
	push @lines, "PATH=$conf->{'qmail_dir'}/bin:$vdir/bin:/usr/local/bin:/usr/bin:/bin";
	push @lines, "export PATH\n";

	if ( $conf->{'filtering_qmailscanner_method'} eq "smtp" )
	{
		my $queue = $conf->{'smtpd_qmail_queue'};
		unless ( -x $queue ) { 
			warn "WARNING: $queue is not executable by uid $>\n";
			return 0;
		};
		push @lines, "QMAILQUEUE=\"$queue\"";
		push @lines, "export QMAILQUEUE\n";
	};

	my $qctrl = $conf->{'qmail_dir'} . "/control";
	unless ( -d $qctrl ) {
		warn "WARNING: BuildSubmitRun failed. $qctrl is not a directory";
		return 0;
	};

	my $qsupervise = $conf->{'qmail_supervise'};
	return 0 unless ( -d $qsupervise );

	if ( $conf->{'smtpd_hostname'} eq "qmail" ) {
		push @lines, "LOCAL=\`head -1 $qctrl/me\`";
		push @lines, "if [ -z \"\$LOCAL\" ]; then";
		push @lines, "\techo LOCAL is unset in $qsupervise/smtp/run";
		push @lines, "\texit 1";
		push @lines, "fi\n";
	};

	push @lines, "if [ ! -f $qctrl/rcpthosts ]; then";
	push @lines, "\techo \"No $qctrl/rcpthosts!\"";
	push @lines, "\techo \"Refusing to start SMTP listener because it'll create an open relay\"";
	push @lines, "\texit 1";
	push @lines, "fi\n";

	if ( $conf->{'smtpd_max_memory_per_connection'} > 0 ) {
		$mem  = $conf->{'smtpd_max_memory_per_connection'} * 1024000; } 
	else { $mem = "8000000" };

	my $exec = "exec softlimit -m $mem tcpserver ";

	if ( $conf->{'smtpd_lookup_tcpremotehost'}  == 0 ) { $exec .= "-H " };
	if ( $conf->{'smtpd_lookup_tcpremoteinfo'}  == 0 ) { $exec .= "-R " };
	if ( $conf->{'smtpd_dns_paranoia'}          == 1 ) { $exec .= "-p " };
	if ( $conf->{'smtpd_max_connections'} != 40      ) { 
		$exec .= "-c$conf->{'smtpd_max_connections'} ";
	};

	if ( $conf->{'smtpd_dns_lookup_timeout'} != 26      ) {
		$exec .= "-t$conf->{'smtpd_dns_lookup_timeout'} ";
	};

	my $uid = getpwnam( $conf->{'smtpd_run_as_user'}  );
	my $gid = getgrnam( $conf->{'smtpd_run_as_group'} );

	unless ( $uid && $gid ) { print "WARNING: uid and gid not found!\n"; return 0 };
	$exec .= "-u $uid -g $gid ";

	if ( $conf->{'smtpd_listen_on_address'} && $conf->{'smtpd_listen_on_address'} ne "all" ) 
	{
		$exec .= "$conf->{'smtpd_listen_on_address'} ";
	} 
	else {  $exec .= "0 " };

	if ( $conf->{'submit_listen_on_port'} && $conf->{'submit_listen_on_port'} ne "submit" ) 
	{
		$exec .= "$conf->{'submit_listen_on_port'} ";
	} 
	else {  $exec .= "submit " };

	$exec .= "qmail-smtpd "; 

	if ( $conf->{'smtpd_auth_enable'} == 1 ) 
	{
		if    ( $conf->{'smtpd_hostname'} eq "qmail" ) 
		{
			$exec .= "\"\$LOCAL\" ";
		} 
		elsif ( $conf->{'smtpd_hostname'} eq "system" ) 
		{
			use Sys::Hostname;
			$exec .= hostname() . " ";
		}
		else { $exec .= $conf->{'smtpd_hostname'} . " " };
	
		my $chkpass = $conf->{'smtpd_checkpasswd_bin'};
		if ( $chkpass =~ /^vpopmail_home_dir\/(.*)$/ ) { $chkpass = "$vdir/$1" };
		die "$chkpass selected but not executable!\n" unless ( -x $chkpass );

		$exec .= "$chkpass /usr/bin/true ";
	};

	if ( $conf->{'smtpd_log_method'} eq "maillogs" )
	{
		$exec = $exec . "2>&1 ";
	}
	else 
	{ 
		$exec = $exec . "splogger qmail ";
	};

	push @lines, $exec;

	if ( WriteFile($file, @lines) ) { return 1 } 
	else { print "error writing file $file\n"; return 0; };
};

sub InstallQmailServiceRun
{

=head2 InstallQmailServiceRun

	use Mail::Toaster::Qmail;

	my $file = "/tmp/toaster-watcher-smtpd-runfile";
	if ( BuildSmtpRun($conf, $file ) )
	{
		InstallQmailServiceRun($file, "$supervise/smtp/run");
	};

The code says it as well as I can. 

=cut

	my ($tmpfile, $file, $debug) = @_;

	unless ( -e $file ) {
		print "InstallQmailServiceRun: installing $file..." if $debug;
	} else {
		print "InstallQmailServiceRun: updating $file..." if $debug;
	};

#	unless ( files_diff($tmpfile, $file, "text") ) {
#		print "done. (same)\n";
#		return 1;
#	};

	if ( $> == 0 ) 
	{
		chmod(00755, "$tmpfile") or die "couldn't chmod $tmpfile: $!\n";
		SysCmd("mv $file $file.bak") if ( -e $file);
		SysCmd("mv $tmpfile $file");
	} 
	else 
	{
		if ( FindTheBin("sudo") ) 
		{
			chmod(00755, "$tmpfile") or die "couldn't chmod $tmpfile: $!\n";
			SysCmd("sudo mv $file $file.bak") if ($file);
			SysCmd("sudo mv $tmpfile $file");
		} 
		else 
		{
			die "FAILED: you aren't root, sudo isn't installed, and you don't have permission to control the qmail daemon. Sorry, I can't go on!\n";
		};
	};
	print "done\n" if $debug;
};


sub RestartQmailSmtpd
{

=head2 RestartQmailSmtpd

	RestartQmailSmtpd($dir, $debug)

Use RestartQmailSmtpd to restart the qmail-smtpd process. It will send qmail-smtpd the TERM signal causing it to exit. It will restart immediately (supervise). 

=cut

	my ($dir, $debug) = @_;

	unless ( -d $dir || -l $dir ) { 
		carp "RestartQmailSmtpd: no such dir: $dir!\n"; 
		return 0;
	};

	print "restarting qmail smtpd..." if $debug;

	my $svc = MATT::Utility::FindTheBin("svc");
	SysCmd( "$svc -t $dir");

	print "done.\n" if $debug;
}

sub StopQmailSend
{

=head2 StopQmailSend

	StopQmailSend

Use StopQmailSend to quit the qmail-send process. It will send qmail-send the TERM signal and then wait until it's shut down before returning. If qmail-send fails to shut down within 100 seconds, then we force kill it, causing it to abort any outbound SMTP sessions that are active. This is safe, as qmail will attempt to deliver them again, and again until it succeeds.

=cut


	my $svc    = MATT::Utility::FindTheBin("svc");
	my $svstat = MATT::Utility::FindTheBin("svstat");

	# send qmail-send a TERM signal
	my $qcontrol = "/service/send";
	system "$svc -d $qcontrol";

	# loop up to a thousand seconds waiting for qmail-send to die
	foreach my $i ( 1..1000 ) {
		my $r = `$svstat $qcontrol`;
		chomp $r;
		if ( $r =~ /^.*:\sdown\s[0-9]*\sseconds/ ) {
			print "Yay, we're down!\n";
			return 0;
		} else {
			# if more than 100 seconds passes, lets kill off the qmail-remote
			# processes that are forcing us to wait.
			
			if ($i > 100) {
				system "killall qmail-remote";
			};
			print "$r\n";
		};
		sleep 1;
	};
	return 1;
};

sub StartQmailSend
{

=head2 StartQmailSend

	StartQmailSend - Start up the qmail-send process.

After starting up qmail-send, we verify that it's running before returning.

=cut

	my $svc    = MATT::Utility::FindTheBin("svc");
	my $svstat = MATT::Utility::FindTheBin("svstat");
	my $qcontrol = "/service/send";

	# Start the qmail-send (and related programs)
	system "$svc -u $qcontrol";

	# loop until it's up and running.
	foreach my $i ( 1..100 ) {
		my $r = `$svstat $qcontrol`;
		chomp $r;
		if ( $r =~ /^.*:\sup\s\(pid [0-9]*\)\s[0-9]*\sseconds$/ ) {
			print "Yay, we're up!\n";
			return 0;
		};
		sleep 1;
	};
	return 1;
};

sub CheckQmailControl
{
	my $dir = shift;
	my $qcontrol = "/service/send";
	
	if ( ! -d $dir )
	{
		print "HEY! The control directory for qmail-send is not
		in $dir where I expected. Please edit this script
		and set $qcontrol to the appropriate directory!\n";
	};
};

sub CheckQmailQueue
{
	my $dir = shift;
	my $qdir     = "/var/qmail/queue";
	
	if ( ! -d $dir )
	{
		print "HEY! The queue directory for qmail is not
		$dir where I expect. Please edit this script
		and set $qdir to the appropriate directory!\n";
	};
};

sub ProcessQmailQueue
{

=head2 ProcessQmailQueue
	
ProcessQmailQueue - Tell qmail to process the queue immediately

=cut

	my $svc    = MATT::Utility::FindTheBin("svc");
	my $qcontrol = "/service/send";

	print "\nSending ALRM signal to qmail-send.\n";
	system "$svc -a $qcontrol";
};

sub CheckRcpthosts
{

=head2 CheckRcpthosts

	use Mail::Toaster::Qmail;
	CheckRcpthosts($qmaildir);

Checks the rcpthosts file and compare it to users/assign. Any zones that are in users/assign but not in control/rcpthosts or control/morercpthosts will be presented as a list and you'll be expected to add them to morercpthosts.

=cut

	my ($qmaildir) = @_;
	unless ($qmaildir) { $qmaildir="/var/qmail" };

	my $assign = "$qmaildir/users/assign";
	my @domains = GetDomainsFromAssign($assign);

	my $rcpt   = "$qmaildir/control/rcpthosts";
	my $mrcpt  = "$qmaildir/control/morercpthosts";


	my (@f2, %rcpthosts, $domains);
	my @f1      = ReadFile( $rcpt  );

	@f2 = ReadFile( $mrcpt ) if ( -e "$qmaildir/control/morercpthosts" );

	foreach my $f (@f1, @f2)
	{
		chomp $f;
		$rcpthosts{$f} = 1;
	};

	foreach my $v (@domains)
	{
		my $domain = $v->{'dom'};
		if ( ! $rcpthosts{$domain} )
		{
			print "$domain\n";
		};
		$domains++;
	};

	if ( $domains > 50 ) 
	{
		print "\nDomains listed above should be added to the file 
	$mrcpt. Don't forget to do this afterwards:

	$qmaildir/bin/qmail-newmrh
\n";
	}
	else 
	{
		print "\nDomains listed above should be added to the file $rcpt. \n";
	};
};

sub ConfigQmail 
{

=head2 ConfigQmail

	use Mail::Toaster::Qmail;
	ConfigQmail($qmaildir, $host, $postmaster, $conf);

Qmail is fantastic because it's so easy to configure. Just edit files and put the right values in them. However, many find that a problem because it's not so easy to always know the sytax for what goes in every file, and exactly where that file might be. This sub takes your values from toaster-watcher.conf and puts them where they need to be. It modifies the following files:

 /var/qmail/control/concurrencyremote
 /var/qmail/control/me
 /var/qmail/control/tarpitcount
 /var/qmail/control/tarpitdelay
 /var/qmail/control/sql
 /var/qmail/alias/.qmail-postmaster
 /var/qmail/alias/.qmail-root
 /var/qmail/alias/.qmail-mailer-daemon

=cut

	my ($conf) = @_;

	my $qmaildir = $conf->{'qmail_dir'};
	unless ($qmaildir) { $qmaildir = "/var/qmail"; };

	my $control = "$qmaildir/control";

	my $host = $conf->{'toaster_hostname'};
	if ( $host)
	{
		if    ( $host eq "qmail" ) { $host = `hostname`; } 
		elsif ( $host eq "system") { $host = `hostname`; } 
		elsif ( $host eq "mail.example.com" ) {
			$host = MATT::Utility::GetAnswer("the hostname for this mail server");
		};
	} 
	else {
		$host = MATT::Utility::GetAnswer("the hostname for this mail server");
	};

	my $dbhost = $conf->{'vpopmail_mysql_repl_slave'};
	unless ( $dbhost ) 
	{
		$dbhost = MATT::Utility::GetAnswer("the hostname for your database server (localhost)");
	};
	$dbhost = "localhost" unless ($dbhost);

	my $postmaster = $conf->{'toaster_admin_email'};
	unless ( $postmaster ) 
	{
		$postmaster = MATT::Utility::GetAnswer("the email address you use for administrator mail");
	};

	my $password = $conf->{'vpopmail_mysql_repl_pass'};
	unless ($password) {
		$password = MATT::Utility::GetAnswer("the SQL password for user vpopmail"); 
	};

	unless ( -e "$control/concurrencyremote" ) 
	{
		MATT::Utility::WriteFile("$control/concurrencyremote", "255");
		chmod(00644, "$control/concurrencyremote");
	};

	unless ( -e "$control/me" ) 
	{
		MATT::Utility::WriteFile("$control/me", $host);
	};

	unless ( -e "$control/tarpitcount" ) 
	{
		MATT::Utility::WriteFile("$control/tarpitcount", "50");
	};

	unless ( -e "$control/tarpitdelay" ) 
	{
		MATT::Utility::WriteFile("$control/tarpitdelay", "5");
	};

	unless ( -e "$qmaildir/alias/.qmail-postmaster" ) 
	{
		MATT::Utility::WriteFile("$qmaildir/alias/.qmail-postmaster",    $postmaster);
	};

	unless ( -e "$qmaildir/alias/.qmail-root" ) 
	{
		MATT::Utility::WriteFile("$qmaildir/alias/.qmail-root",          $postmaster);
	};

	unless ( -e "$qmaildir/alias/.qmail-mailer-daemon" ) 
	{
		MATT::Utility::WriteFile("$qmaildir/alias/.qmail-mailer-daemon", $postmaster);
	};

	unless ( -e "$control/sql" ) 
	{
		my @lines  = "server $dbhost";
		push @lines, "port 3306";
		push @lines, "database vpopmail";
		push @lines, "table relay";
		push @lines, "user vpopmail";
		push @lines, "pass $password";
		push @lines, "time 1800";

		MATT::Utility::WriteFile("$control/sql", @lines);

		my $uid = getpwnam("vpopmail");
		my $gid = getgrnam("vchkpw");
		chown( $uid, $gid, "$control/sql"); 
		chown( $uid, $gid, "$control/servercert.pem"); 
		chmod(00640, "$control/sql");
		chmod(00640, "$control/servercert.pem");
		chmod(00640, "$control/clientcert.pem");
	};

	unless ( -e "$control/locals" ) 
	{
		MATT::Utility::WriteFile("$control/locals", "\n");
	};
};

sub ConfigureQmailControl($)
{

=head2 ConfigureQmailControl

	use Mail::Toaster::Qmail;
	ConfigureQmailControl($conf);

Installs the qmail control script as well as the startup (services.sh) script.

=cut

	my ($conf) = @_;

	my $dl_site = $conf->{'toaster_dl_site'};
	unless ($dl_site) { $dl_site = "http://www.tnpi.biz"; };

	my $toaster   = "$dl_site/internet/mail/toaster";

	my $qmaildir = $conf->{'qmail_dir'};
	unless ($qmaildir) { $qmaildir = "/var/qmail"; };

	my $confdir = $conf->{'system_config_dir'};
	unless ($confdir) { $confdir = "/usr/local/etc"; };

	my $qmailctl  = "/usr/local/sbin/qmail";
	if ( -e $qmailctl ) 
	{
		print "ConfigureQmailControl: $qmailctl already exists.\n";
	}
	else 
	{
		MATT::Utility::FetchFile("$toaster/start/qmail.txt");
		use File::Copy;
		move("qmail.txt", $qmailctl) or die "couldn't move: $!";
		chmod(00751, $qmailctl);
		MATT::Utility::SysCmd("$qmailctl cdb");
	};

	if ( -e "$qmaildir/rc" ) 
	{
		print "ConfigureQmailControl: $qmaildir/rc already exists.\n";
	}
	else 
	{
		my $file = "/tmp/toaster-watcher-send-runfile";
		if ( BuildSendRun($conf, $file ) )
		{
			InstallQmailServiceRun($file, "$qmaildir/rc");
		};
	};

	if ( -e "$confdir/rc.d/qmail.sh" ) 
	{
		unlink("$confdir/rc.d/qmail.sh") 
			or die "couldn't delete $confdir/rc.d/qmail.sh: $!";
	};
};

sub InstallQmailSuperviseRunFiles($;$)
{

=head2 InstallQmailSuperviseRunFiles

	use Mail::Toaster::Qmail;
	InstallQmailSuperviseRunFiles($conf, $supervise);

$conf is a hashref of values pulled from toaster-watcher.conf. $supervise is your qmail supervise directory. 

Generates the qmail/supervise/*/run files based on your settings.

=cut

	my ($conf, $supervise) = @_;

	unless ($supervise) { $supervise = "/var/qmail/supervise"; };

	foreach my $prot ( qw/ smtp send pop3 submit / )
	{
		my $run_f = "$supervise/$prot/run";
		
		unless ( -e  $run_f )
		{
			if ($prot eq "smtp")
			{
				my $file = "/tmp/toaster-watcher-smtpd-runfile";
				if ( BuildSmtpRun($conf, $file ) )
				{
					InstallQmailServiceRun($file, $run_f);
				};
			}
			elsif ($prot eq "send")
			{
				#my @lines = "#!/bin/sh\n";
				#push @lines, "exec /var/qmail/rc";
				#print "InstallQmailSuperviseRunFiles: writing $run_f\n";
				#MATT::Utility::WriteFile($run_f, @lines);
				#chmod(00751, $run_f);

				my $file = "/tmp/toaster-watcher-send-runfile";
				if ( BuildSendRun($conf, $file ) )
				{
					InstallQmailServiceRun($file, $run_f);
				};
			}
			elsif ($prot eq "pop3")
			{
				my $file = "/tmp/toaster-watcher-pop3-runfile";
				if ( BuildPOP3Run($conf, $file ) )
				{
					InstallQmailServiceRun($file, $run_f);
				};
			}
			elsif ($prot eq "submit")
			{
				my $file = "/tmp/toaster-watcher-submit-runfile";
				if ( BuildSubmitRun($conf, $file ) )
				{
					InstallQmailServiceRun($file, $run_f);
				};
			};
		}
		else { print "InstallQmailSuperviseRunFiles: $run_f already exists!\n"; };
	};
};

sub InstallQmailSuperviseLogRunFiles($)
{

=head2 InstallQmailSuperviseLogRunFiles

	use Mail::Toaster::Qmail;
	InstallQmailSuperviseLogRunFiles($conf);

$conf is a hash of values. See ParseConfigFile or toaster-watcher.conf for config values.

Installs the files the control your supervised processes logging. Typically this consists of qmail-smtpd, qmail-send, and qmail-pop3d. The generated files are:
                
 $supervise/pop3/log/run
 $supervise/smtp/log/run
 $supervise/send/log/run

=cut

	my ($conf) = @_;
	my (@lines);

	my $supervise = $conf->{'qmail_supervise'};
	unless ($supervise) { $supervise = "/var/qmail/supervise"; };

	my $log = $conf->{'qmail_log_base'};
	unless ($log) { 
		print "NOTICE: qmail_log_base is not set in toaster-watcher.conf!\n";
		$log = "/var/log/mail" 
	};

	# Create log/run files
	foreach my $serv ( qw/ smtp send pop3 submit / )
	{
		my $run_f   = "$supervise/$serv/log/run";

		unless ( -s $run_f ) 
		{
			print "InstallQmailSuperviseLogRun: creating file $run_f\n";

			     @lines= "#!/bin/sh\n";
			push @lines, "PATH=/var/qmail/bin:/usr/local/bin:/usr/bin:/bin";
			push @lines, "export PATH\n";

			my $runline = "exec setuidgid qmaill multilog t ";

			if ($serv eq "smtp") 
			{
				if ( $conf->{'smtpd_log_postprocessor'} eq "maillogs" ) {
					$runline .= "!./smtplog ";
				};
				$runline .= "s100000 $log/smtp";
			} 
			elsif ( $serv eq "send") 
			{
				if ( $conf->{'send_log_postprocessor'} eq "maillogs" ) {
					$runline .= "!./sendlog ";
				};

				if ( $conf->{'send_log_isoqlog'} ) {
					$runline .= "n288 ";
				};
				$runline .= "s100000 $log/send";
			} 
			elsif ( $serv eq "pop3") 
			{
				if ( $conf->{'pop3_log_postprocessor'} eq "maillogs" ) {
					$runline .= "!./pop3log ";
				};
				$runline .= "s100000 $log/pop3";
			} 
			elsif ( $serv eq "submit") 
			{
				if ( $conf->{'submit_log_postprocessor'} eq "maillogs" ) {
					$runline .= "!./submitlog ";
				};
				$runline .= "s100000 $log/submit";
			};

			push @lines, $runline;
			
			MATT::Utility::WriteFile($run_f, @lines);
			chmod(00751, $run_f);
		} 
		else 
		{
			print "InstallQmailSuperviseLogRun: $run_f already exists.\n";
		};
	};
};

sub GetDomainsFromAssign
{

=head2 GetDomainsFromAssign

Fetch a list of domains from the qmaildir/users/assign file.

	use Mail::Toaster::Qmail;
	GetDomainsFromAssign($assign, $debug, $match, $value);

 $assign is the path to the assign file.
 $debug is optional
 $match is an optional field to match (dom, uid, dir)
 $value is the pattern to  match

=cut

    my ($assign, $debug, $match, $value) = @_;

	unless ($assign) { $assign = "/var/qmail/users/assign"; };

    my @domains;
    my @lines = MATT::Utility::ReadFile($assign);
    print "Parsing through the file $assign..." if $debug;
    foreach my $line (@lines)
	{
        chomp $line;
        my @fields = split(":", $line);
        if ($fields[0] ne "" && $fields[0] ne ".") {
            my %domain = (
                stat => "$fields[0]",
                dom  => "$fields[1]",
                uid  => "$fields[2]",
                gid  => "$fields[3]",
                dir  => "$fields[4]"
            );

            unless ($match) { push @domains, \%domain; } 
			else 
			{
                if    ( $match eq "dom" && $value eq "$fields[1]" ) {
                    push @domains, \%domain;
                } 
				elsif ( $match eq "uid" && $value eq "$fields[2]" ) {
                    push @domains, \%domain;
                } 
				elsif ( $match eq "dir" && $value eq "$fields[4]" ) {
                    push @domains, \%domain;
                };
            };
        };
    };
    print "done.\n\n" if $debug;;
    return @domains;
}


1;
__END__


=head1 AUTHOR

	Matt Simerson <matt@cadillac.net>

=head1 BUGS

	None known. Report any to author.

=head1 TODO

=head1 SEE ALSO

http://www.tnpi.biz/computing/
http://www.tnpi.biz/internet/mail/toaster/

Mail::Toaster::CGI, Mail::Toaster::DNS, Mail::Toaster::Logs,
Mail::Toaster::Qmail, Mail::Toaster::Setup


=head1 COPYRIGHT

Copyright 2003, The Network People, Inc. All Rights Reserved.

=cut
