#!/usr/bin/perl
use strict;

#
# $Id: Qmail.pm,v 4.34 2006/03/18 03:32:53 matt Exp $
#

package Mail::Toaster::Qmail;

use Carp;
use POSIX;
my $os = $^O;
use vars qw($VERSION);
$VERSION = '4.18';

use lib "lib";
use lib "../..";
require Mail::Toaster;          my $toaster = Mail::Toaster->new();
require Mail::Toaster::Utility; my $utility = Mail::Toaster::Utility->new();
require Mail::Toaster::Perl;    my $perl    = Mail::Toaster::Perl->new();

=head1 NAME

Mail::Toaster:::Qmail - Common Qmail functions

=head1 SYNOPSIS

Mail::Toaster::Qmail is a module of Mail::Toaster. It contains features for use with qmail, like starting and stopping the deamons, installing qmail, checking the contents of config files, etc.

See http://www.tnpi.biz/internet/mail/toaster for details.

=head1 DESCRIPTION

This module has all sorts of goodies, the most useful of which are the build_????_run modules which build your qmail control files for you. 

=head1 METHODS

=head2 new

To use any of the methods following, you need to create a qmail object:

	use Mail::Toaster::Qmail;
	my $qmail = Mail::Toaster::Qmail->new();

=cut

sub new
{
	my ($class, $name) = @_;
	my $self = { name => $name };
	bless ($self, $class);
	return $self;
};


=head2 build_pop3_run

	$qmail->build_pop3_run($conf, $file, $debug) ? print "success" : print "failed";

Generate a supervise run file for qmail-pop3d. $file is the location of the file it's going to generate. $conf is a list of configuration variables pulled from a config file (see $utility->parse_config). I typically use it like this:

  my $file = "/tmp/toaster-watcher-pop3-runfile";
  if ( $qmail->build_pop3_run($conf, $file ) )
  {
    $qmail->install_supervise_run( {file=>$file, service=>"pop3"}, $conf);
  };

If it succeeds in building the file, it will install it. You should restart the service after installing a new run file.

=cut

sub build_pop3_run
{
	my ($self, $conf, $file, $debug) = @_;

	unless ($utility->is_hashref($conf) ) {
		print "FATAL: build_pop3_run subroutine called incorrectly!\n";
		return 0;
	};

	my $vdir       = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";
	my $qctrl      = $conf->{'qmail_dir'} . "/control";
	my $qsupervise = $conf->{'qmail_supervise'};

	return 0 unless $self->_supervise_dir_exist($qsupervise, "build_pop3_run");

	my @lines = $toaster->supervised_do_not_edit_notice($conf, $vdir); 
	push @lines, $self->supervised_hostname_qmail( $conf, "pop3", $debug ) 
		if ( $conf->{'pop3_hostname'} eq "qmail" );

	#exec softlimit -m 2000000 tcpserver -v -R -H -c50 0 pop3 

	my $exec = $toaster->supervised_tcpserver($conf, "pop3", $debug);
	return 0 unless $exec;

	#qmail-popup mail.cadillac.net /usr/local/vpopmail/bin/vchkpw qmail-pop3d Maildir 2>&1

	$exec .= "qmail-popup "; 
	$exec .= $toaster->supervised_hostname  ($conf, "pop3", $debug);
	my $chkpass = $self->_set_checkpasswd_bin ($conf, "pop3", $debug);
	$chkpass ? $exec .= $chkpass : return 0;
	$exec .= "qmail-pop3d Maildir ";
	$exec .= $toaster->supervised_log_method($conf, "pop3", $debug);

	push @lines, $exec;

	return 1 if ( $utility->file_write($file, @lines) );
	print "error writing file $file\n"; 
	return 0; 
};


=head2 build_send_run

  $qmail->build_send_run($conf, $file, $debug) ? print "success";

build_send_run generates a supervise run file for qmail-send. $file is the location of the file it's going to generate. $conf is a list of configuration variables pulled from toaster-watcher.conf. I typically use it like this:

  my $file = "/tmp/toaster-watcher-send-runfile";
  if ( $qmail->build_send_run($conf, $file ) )
  {
    $qmail->install_supervise_run( {file=>$file, service=>"send"}, $conf);
    $qmail->restart($conf, $debug);
  };

If it succeeds in building the file, it will install it. You can optionally restart qmail after installing a new run file.

=cut

sub build_send_run($$;$)
{
	my ($self, $conf, $file, $debug) = @_;
	my ($mem);

	unless ($utility->is_hashref($conf) ) {
		print "FATAL: build_send_run subroutine called incorrectly!\n";
		return 0;
	};

	my @lines = $toaster->supervised_do_not_edit_notice($conf);

	my $qsupervise = $conf->{'qmail_supervise'};
	print "build_send_run: WARNING: qmail_supervise not set in toaster-watcher.conf!\n" unless ($qsupervise);

	unless ( -d $qsupervise ) { $utility->syscmd("mkdir -p $qsupervise"); };

	my $mailbox  = $conf->{'send_mailbox_string'} || "./Maildir/";
	my $send_log = $conf->{'send_log_method'}     || "syslog";

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

	return 1 if ( $utility->file_write($file, @lines) );
	print "error writing file $file\n"; 
	return 0;
};


=head2 build_smtp_run

  if ( $qmail->build_smtp_run($conf, $file, $debug) ) { print "success" };

Generate a supervise run file for qmail-smtpd. $file is the location of the file it's going to generate. $conf is a list of configuration variables pulled from a config file (see ParseConfigfile). I typically use it like this:

  my $file = "/tmp/toaster-watcher-smtpd-runfile";
  if ( $qmail->build_smtp_run($conf, $file ) )
  {
    $qmail->install_supervise_run( {file=>$file, service=>"smtp"}, $conf);
  };

If it succeeds in building the file, it will install it. You can optionally restart the service after installing a new run file.

=cut

sub build_smtp_run($$;$)
{
	my ($self, $conf, $file, $debug) = @_;
	my ($mem);

	unless ($utility->is_hashref($conf) ) {
		print "FATAL: build_smtp_run subroutine called incorrectly!\n";
		return 0;
	};

	$self->_test_smtpd_config_values($conf, $debug);

	#use Data::Dumper; print Dumper($conf);
	my @lines = $toaster->supervised_do_not_edit_notice($conf, $conf->{'vpopmail_home_dir'});

	my $qdir  = $conf->{'qmail_dir'};
	if ( $conf->{'filtering_method'} eq "smtp" )
	{
		my $queue = $conf->{'smtpd_qmail_queue'};
		unless ( -x $queue ) 
		{
			if ( -x "$qdir/bin/qmail-queue" ) 
			{
				carp "WARNING: $queue is not executable! I'm falling back to 
$qdir/bin/qmail-queue. You need to either (re)install $queue or update your
toaster-watcher.conf file to point to it's correct installed location.\n
You will continue to get this notice every 5 minutes until you fix this.\n";
				$queue = "$qdir/bin/qmail-queue";
			} else {
				carp "WARNING: $queue is not executable by uid $>.\n";
				return 0;
			};
		};
		push @lines, "QMAILQUEUE=\"$queue\"";
		push @lines, "export QMAILQUEUE\n";
		print "build_smtp_run: using $queue for QMAILQUEUE\n" if $debug;
	};

	my $qctrl = "$qdir/control";
	unless ( -d $qctrl ) {
		carp "WARNING: build_smtp_run failed. $qctrl is not a directory";
		return 0;
	};

	my $qsupervise = $conf->{'qmail_supervise'};
	return 0 unless $self->_supervise_dir_exist($qsupervise, "build_smtp_run");

	my $qsuper_smtp = $conf->{'qmail_supervise_smtp'} || "$qsupervise/smtp";
	   $qsuper_smtp = "$qsupervise/$1" if ( $qsuper_smtp =~ /^supervise\/(.*)$/ );

	print "build_smtp_run: qmail-smtp supervise dir is $qsuper_smtp\n" if $debug;

	push @lines, $self->supervised_hostname_qmail( $conf, "smtpd", $debug )
		if ( $conf->{'smtpd_hostname'} eq "qmail" );
	push @lines, $self->_smtp_sanity_tests($conf);

	my $exec = $toaster->supervised_tcpserver($conf, "smtpd", $debug);
	return 0 unless $exec;

	if ( ( $conf->{'rwl_enable'} && $conf->{'rwl_enable'} > 0 ) 
	or   ( $conf->{'rbl_enable'} && $conf->{'rbl_enable'} > 0 )  )
	{
		my $rblsmtpd = $utility->find_the_bin("rblsmtpd");
		$exec .= "$rblsmtpd ";

		print "build_smtp_run: using rblsmtpd\n" if $debug;

		my $timeout = $conf->{'rbl_timeout'}; unless ($timeout) { $timeout = 60; };
		if ( $timeout != 60 ) { $exec .= "-t $timeout "; };

		$exec .= "-c " if     $conf->{'rbl_enable_fail_closed'};
		$exec .= "-b " unless $conf->{'rbl_enable_soft_failure'};

		if ( $conf->{'rwl_enable'} && $conf->{'rwl_enable'} > 0 )
		{
			print "testing RWLs...." if $debug;
			my $list  = $self->get_list_of_rwls($conf, $debug);
#			my $rwls  = $self->test_each_rwl($conf, $list, $debug);
#			foreach my $rwl ( @$rwls ) { $exec = $exec . "-a $rwl " };
			foreach my $rwl ( @$list ) { $exec = $exec . "-a $rwl " };
			print "done.\n" if $debug;
		} 
		else { print "no RWL's selected\n" if $debug };

		if ( $conf->{'rbl_enable'} && $conf->{'rbl_enable'} > 0 )
		{
			print "testing RBLs...." if $debug;
			my $list  = $self->get_list_of_rbls($conf, $debug);
			my $rbls  = $self->test_each_rbl($conf, $list, $debug);
			foreach ( @$rbls ) {
				my $mess = $conf->{"rbl_${_}_message"};
				if ( $mess ) {
					print "adding $_:'$mess'\n" if $debug;
					$exec = $exec . "-r $_:'$mess' ";
				} else {
					print "adding $_ \n" if $debug;
					$exec = $exec . "-r $_ ";
				};
			};
			print "done.\n" if $debug;
		} 
		else { print "no RBL's selected\n" if $debug };
	};

	$exec .= "recordio " if $conf->{'smtpd_recordio'};
	$exec .= "fixcrio " if $conf->{'smtpd_fixcrio'};
	$exec .= "qmail-smtpd "; 

	if ( $conf->{'smtpd_auth_enable'} ) 
	{
		print "build_smtp_run: enabling SMTP-AUTH\n" if $debug;

		if ( $conf->{'smtpd_hostname'} && $conf->{'qmail_smtpd_auth_0.31'} ) {
			print "build_smtp_run: configuring smtpd hostname\n" if $debug;
			$exec .= $toaster->supervised_hostname($conf, "smtpd", $debug);
		};

		my $chkpass = $self->_set_checkpasswd_bin ($conf, "smtpd", $debug);
		$chkpass ? $exec .= $chkpass : return 0;

		$exec .= "/usr/bin/true ";
	};

	$exec .= $toaster->supervised_log_method($conf, "smtpd", $debug);

	push @lines, $exec;

	if ( $utility->file_write($file, @lines) ) { return 1 } 
	else { print "error writing file $file\n"; return 0; };
};


=head2 build_submit_run

  if ( $qmail->build_submit_run($conf, $file, $debug) ) { print "success"};

Generate a supervise run file for qmail-smtpd running on submit. $file is the location of the file it's going to generate. $conf is a list of configuration variables pulled from a config file (see ParseConfigfile). I typically use it like this:

  my $file = "/tmp/toaster-watcher-smtpd-runfile";
  if ( $qmail->build_submit_run($conf, $file ) )
  {
    $qmail->install_supervise_run( {file=>$file, service=>"submit"}, $conf);
  };

If it succeeds in building the file, it will install it. You can optionally restart the service after installing a new run file.

=cut

sub build_submit_run($$;$)
{
	my ($self, $conf, $file, $debug) = @_;
	my ($mem);

	unless ( $utility->is_hashref($conf) ) 
	{
		my ($package, $filename, $line) = caller;
		carp "FATAL: $filename:$line passed build_submit_run an invalid argument.\n";
		return 0;
	};
	
	$self->_test_smtpd_config_values($conf, $debug);

	my $vdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";

	my @lines = $toaster->supervised_do_not_edit_notice($conf, $vdir);

	if ( $conf->{'filtering_method'} eq "smtp" )
	{
		my $queue = $conf->{'submit_qmail_queue'};
		unless ( -x $queue ) { 
			carp "WARNING: $queue is not executable by uid $>\n";
			return 0;
		};
		push @lines, "QMAILQUEUE=\"$queue\"";
		push @lines, "export QMAILQUEUE\n";
	};

	my $qctrl = $conf->{'qmail_dir'} . "/control";
	unless ( -d $qctrl ) {
		carp "WARNING: build_submit_run failed. $qctrl is not a directory";
		return 0;
	};

	my $qsupervise = $conf->{'qmail_supervise'};
	return 0 unless $self->_supervise_dir_exist($qsupervise, "build_submit_run");

	my $qsuper_submit = $conf->{'qmail_supervise_submit'} || "$qsupervise/submit";
	   $qsuper_submit = "$qsupervise/$1" if ( $qsuper_submit =~ /^supervise\/(.*)$/ );

	print "build_submit_run: qmail-submit supervise dir is $qsuper_submit\n" if $debug;

	push @lines, $self->supervised_hostname_qmail( $conf, "submit", $debug)
		if ( $conf->{'submit_hostname'} eq "qmail" );
	push @lines, $self->_smtp_sanity_tests($conf);

	my $exec = $toaster->supervised_tcpserver($conf, "submit", $debug);
	return 0 unless $exec;

	$exec .= "qmail-smtpd "; 

	if ( $conf->{'submit_auth_enable'} ) 
	{
		if ( $conf->{'submit_hostname'} && $conf->{'qmail_smtpd_auth_0.31'} )
		{
			$exec .= $toaster->supervised_hostname($conf, "submit", $debug);
		};

		my $chkpass = $self->_set_checkpasswd_bin ($conf, "submit", $debug);
		$chkpass ? $exec .= $chkpass : return 0;

		$exec .= "/usr/bin/true ";
	};

	$exec .= $toaster->supervised_log_method($conf, "submit", $debug);

	push @lines, $exec;

	return 1 if ( $utility->file_write($file, @lines) );
	print "error writing file $file\n"; 
	return 0;
};

=head2 check_control

Verify the existence of the qmail control directory (typically /var/qmail/control). 

=cut

sub check_control($;$)
{
	my ($self, $dir, $debug) = @_;

	my $qcontrol = $self->service_dir_get(undef, "send");

	print "check_control: checking $qcontrol/$dir..." if $debug;

	unless ( -d $dir )
	{
		print "FAILED.\n" if $debug;
		print "HEY! The control directory for qmail-send is not
		in $dir where I expected. Please edit this script
		and set $qcontrol to the appropriate directory!\n";
		return 0;
	} else {
		print "ok.\n" if $debug;
		return 1;
	};
};


=head2 check_rcpthosts

  $qmail->check_rcpthosts($qmaildir);

Checks the control/rcpthosts file and compares it's contents to users/assign. Any zones that are in users/assign but not in control/rcpthosts or control/morercpthosts will be presented as a list and you'll be expected to add them to morercpthosts.

=cut

sub check_rcpthosts
{
	my ($self, $qmaildir) = @_;
	$qmaildir ||= "/var/qmail";

	my $assign  = "$qmaildir/users/assign";
	my @domains = $self->get_domains_from_assign($assign);
	my $rcpt    = "$qmaildir/control/rcpthosts";
	my $mrcpt   = "$qmaildir/control/morercpthosts";

	print "check_rcpthosts: checking your rcpthost files.\n.";
	my (@f2, %rcpthosts, $domains, $count);
	my @f1 = $utility->file_read( $rcpt  );
	   @f2 = $utility->file_read( $mrcpt ) if ( -e "$qmaildir/control/morercpthosts" );

	foreach (@f1, @f2) { chomp $_; $rcpthosts{$_} = 1; };

	foreach (@domains)
	{
		my $domain = $_->{'dom'};
		unless ( $rcpthosts{$domain} )
		{
			print "\t$domain\n";
			$count++;
		};
		$domains++;
	};

	if ($count == 0) {
		print "Congrats, your rcpthosts is correct!\n";
		return 1;
	};

	if ( $domains > 50 ) 
	{
		print "\nDomains listed above should be added to $mrcpt. Don't forget to run 'qmail cdb' afterwards.\n";
	}
	else {
		print "\nDomains listed above should be added to $rcpt. \n";
	};
};

=head2 config

   $qmail->config($conf);

Qmail is fantastic because it's so easy to configure. Just edit files and put the right values in them. However, many find that a problem because it's not so easy to always know the syntax for what goes in every file, and exactly where that file might be. This sub takes your values from toaster-watcher.conf and puts them where they need to be. It modifies the following files:

   /var/qmail/control/concurrencyremote
   /var/qmail/control/me
   /var/qmail/control/spfbehavior
   /var/qmail/control/tarpitcount
   /var/qmail/control/tarpitdelay
   /var/qmail/control/sql
   /var/qmail/alias/.qmail-postmaster
   /var/qmail/alias/.qmail-root
   /var/qmail/alias/.qmail-mailer-daemon

You should not manually edit these files. Instead, make changes in toaster-watcher.conf and allow it to keep the updated.

=cut


sub config 
{
	my ($self, $conf, $debug) = @_;
	
	my $qmaildir = $conf->{'qmail_dir'}       || "/var/qmail";
	my $tmp      = $conf->{'toaster_tmp_dir'} || "/tmp";
	my $control  = "$qmaildir/control";
	my $host     = $conf->{'toaster_hostname'};

	if ( $host) {
		if    ( $host eq "qmail" ) { $host = `hostname`; } 
		elsif ( $host eq "system") { $host = `hostname`; } 
		elsif ( $host eq "mail.example.com" ) {
			$host = $utility->answer("the hostname for this mail server");
		};
	} 
	else {
		$host = $utility->answer("the hostname for this mail server");
	};

	# update control/me
	$utility->file_write("$tmp/me", $host);
	my $r = $utility->install_if_changed("$tmp/me", "$control/me", {clean=>1, notify=>1});
	if ($r) { if ( $r == 1) { $r = "ok"} else {$r = "ok (same)"} } else { $r = "FAILED"; };
	$self->_formatted("config: setting me to $host", $r) if $debug;

	$utility->file_write("$tmp/concurrencyremote", $conf->{'qmail_concurrencyremote'});
	$r = $utility->install_if_changed("$tmp/concurrencyremote", "$control/concurrencyremote", {clean=>1, notify=>1,mode=>00644});
	if ($r) { if ( $r == 1) { $r = "ok"} else {$r = "ok (same)"} } else { $r = "FAILED"; };
	$self->_formatted("config: setting concurrencyremote to ".$conf->{'qmail_concurrencyremote'}, $r) if $debug;

	$utility->file_write("$tmp/mfcheck", $conf->{'qmail_mfcheck_enable'});
	$r = $utility->install_if_changed("$tmp/mfcheck", "$control/mfcheck", {notify=>1,clean=>1});
	if ($r) { if ( $r == 1) { $r = "ok"} else {$r = "ok (same)"} } else { $r = "FAILED"; };
	$self->_formatted("config: setting mfcheck to ".$conf->{'qmail_mfcheck_enable'}, $r) if $debug;

	$utility->file_write("$tmp/tarpitcount", $conf->{'qmail_tarpit_count'});
	$r = $utility->install_if_changed("$tmp/tarpitcount", "$control/tarpitcount", {clean=>1, notify=>1});
	if ($r) { if ( $r == 1) { $r = "ok"} else {$r = "ok (same)"} } else { $r = "FAILED"; };
	$self->_formatted("config: setting tarpitcount to ".$conf->{'qmail_tarpit_count'}, $r) if $debug;

	$utility->file_write("$tmp/tarpitdelay", $conf->{'qmail_tarpit_delay'});
	$r = $utility->install_if_changed("$tmp/tarpitdelay", "$control/tarpitdelay", {clean=>1, notify=>1});
	if ($r) { if ( $r == 1) { $r = "ok"} else {$r = "ok (same)"} } else { $r = "FAILED"; };
	$self->_formatted("config: setting tarpitdelay to ".$conf->{'qmail_tarpit_delay'}, $r) if $debug;

	$utility->file_write("$tmp/spfbehavior", $conf->{'qmail_spf_behavior'});
	$r = $utility->install_if_changed("$tmp/spfbehavior", "$control/spfbehavior", {clean=>1, nofity=>1});
	if ($r) { if ( $r == 1) { $r = "ok"} else {$r = "ok (same)"} } else { $r = "FAILED"; };
	$self->_formatted("config: setting spfbehavior to ".$conf->{'qmail_spf_behavior'}, $r) if $debug;

	my $postmaster = $conf->{'toaster_admin_email'};
	$postmaster ||= $utility->answer("the email address you use for administrator mail");

	$utility->file_write("$tmp/.qmail-postmaster", $postmaster);
	$r = $utility->install_if_changed("$tmp/.qmail-postmaster", "$qmaildir/alias/.qmail-postmaster", {clean=>1,notify=>1});
	if ($r) { if ( $r == 1) { $r = "ok"} else {$r = "ok (same)"} } else { $r = "FAILED"; };
	$self->_formatted("config: setting postmaster\@local to $postmaster", $r) if $debug;

	$utility->file_write("$tmp/.qmail-root", $postmaster);
	$r = $utility->install_if_changed("$tmp/.qmail-root", "$qmaildir/alias/.qmail-root", {clean=>1,notify=>1});
	if ($r) { if ( $r == 1) { $r = "ok"} else {$r = "ok (same)"} } else { $r = "FAILED"; };
	$self->_formatted("config: setting root\@local to $postmaster", $r) if $debug;

	$utility->file_write("$tmp/.qmail-mailer-daemon", $postmaster);
	$r = $utility->install_if_changed("$tmp/.qmail-mailer-daemon", "$qmaildir/alias/.qmail-mailer-daemon", {clean=>1,notify=>1});
	if ($r) { if ( $r == 1) { $r = "ok"} else {$r = "ok (same)"} } else { $r = "FAILED"; };
	$self->_formatted("config: setting mailer-daemon\@local to $postmaster", $r) if $debug;

	my $dbhost = $conf->{'vpopmail_mysql_repl_slave'};
	$dbhost ||= $utility->answer("the hostname for your database server (localhost)");
	$dbhost ||= "localhost";

	my $password = $conf->{'vpopmail_mysql_repl_pass'};
	$password ||= $utility->answer("the SQL password for user vpopmail"); 

	my $uid = getpwnam("vpopmail");
	my $gid = getgrnam("vchkpw");
	if ( $conf->{'install_mysql'} ) {
		my @lines  = "server $dbhost";
		push @lines, "port 3306";
		push @lines, "database vpopmail";
		push @lines, "table relay";
		push @lines, "user vpopmail";
		push @lines, "pass $password";
		push @lines, "time 1800";

		$utility->file_write("$tmp/sql", @lines);
		$r = $utility->install_if_changed("$tmp/sql", "$control/sql", {uid=>$uid, gid=>$gid, mode=>00640, clean=>1});
		if ($r) { if ( $r == 1) { $r = "ok"} else {$r = "ok (same)"} } else { $r = "FAILED"; };
		$self->_formatted("config: setting up mysql relay settings (tcpserver -S)", $r) if $debug;
	};

	chown( $uid, $gid, "$control/servercert.pem"); 
	chmod 00640, "$control/servercert.pem";
	chmod 00640, "$control/clientcert.pem";

	unless ( -e "$control/locals" ) 
	{
		$utility->file_write("$control/locals", "\n");
		$self->_formatted("config: touching $control/locals", "ok") if $debug;
	};

    my $manpath = "/etc/manpath.config";
	if (-e $manpath)
	{
		unless ( `grep "/var/qmail/man" $manpath | grep -v grep` )
		{
			$utility->file_append($manpath, ["OPTIONAL_MANPATH\t\t/var/qmail/man"]);
			$self->_formatted("config: appending /var/qmail/man to MANPATH", "ok") if $debug;
		};
	};

	if ($os eq "freebsd") 
	{
		# disable sendmail
		require Mail::Toaster::FreeBSD;
		my $freebsd = Mail::Toaster::FreeBSD->new;
		my $sendmail = `grep sendmail_enable /etc/rc.conf`;
		$freebsd->rc_dot_conf_check("sendmail_enable", "sendmail_enable=\"NONE\"") unless $sendmail;
		unless ($sendmail && $sendmail =~ /NONE/) {
			my @lines = $utility->file_read("/etc/rc.conf");
			foreach ( @lines ) {
				if ( $_ =~ /^sendmail_enable/ ) { $_ = 'sendmail_enable="NONE"'; };
			};
			$utility->file_write("/etc/rc.conf", @lines);
		};

		# don't install sendmail when we rebuild the world
		my $make_conf = `grep NO_SENDMAIL /etc/make.conf`;
		unless ($make_conf) {
			$utility->file_append("/etc/make.conf", ["NO_SENDMAIL=true"]);
		};

		# make sure mailer.conf is set up for qmail
		my $tmp  = $conf->{'toaster_tmp_dir'} || "/tmp";
		my $file = "$tmp/mailer.conf";
		if ( open FILE, ">$file" ) {
			print FILE <<EOMAILER
# \$FreeBSD: src/etc/mail/mailer.conf,v 1.3 2002/04/05 04:25:12 gshapiro Exp \$
#
sendmail        /var/qmail/bin/sendmail
send-mail       /var/qmail/bin/sendmail
mailq  /usr/local/sbin/maillogs yesterday
#mailq          /var/qmail/bin/qmail-qread
newaliases      /var/qmail/bin/newaliases
hoststat        /var/qmail/bin/qmail-tcpto
purgestat       /var/qmail/bin/qmail-tcpok
#
# Execute the "real" sendmail program, named /usr/libexec/sendmail/sendmail
#
#sendmail        /usr/libexec/sendmail/sendmail
#send-mail       /usr/libexec/sendmail/sendmail
#mailq           /usr/libexec/sendmail/sendmail
#newaliases      /usr/libexec/sendmail/sendmail
#hoststat        /usr/libexec/sendmail/sendmail
#purgestat       /usr/libexec/sendmail/sendmail

EOMAILER
;
			$utility->install_if_changed($file, "/etc/mail/mailer.conf", {notify=>1,clean=>1});
		} else {
			carp "control_write: FAILED to open $file: $!\n";
		};
	}

};


=head2 control_create

  $qmail->control_create($conf);

Installs the qmail control script as well as the startup (services.sh) script.

=cut

sub control_create($;$)
{
	my ($self, $conf, $debug) = @_;

	my $dl_site  = $conf->{'toaster_dl_site'}        || "http://www.tnpi.biz";
	my $toaster  = "$dl_site/internet/mail/toaster";
	my $qmaildir = $conf->{'qmail_dir'}              || "/var/qmail";
	my $confdir  = $conf->{'system_config_dir'}      || "/usr/local/etc";
	my $tmp      = $conf->{'toaster_tmp_dir'}        || "/tmp";
	my $prefix   = $conf->{'toaster_prefix'}         || "/usr/local";

	my $qmailctl = "$qmaildir/bin/qmailctl";
		
	$self->control_write($conf, "$tmp/qmailctl");
	my $r = $utility->install_if_changed("$tmp/qmailctl", $qmailctl, {mode=>00755, notify=>1, clean=>1}, $debug);
	if ($r) { if ( $r == 1) { $r = "ok"} else {$r = "ok (same)"} } else { $r = "FAILED"; };
	$self->_formatted("control_create: installing $qmaildir/bin/qmailctl", $r);
	$utility->syscmd("$qmailctl cdb");

	foreach my $qmailctl ( "$prefix/sbin/qmail", "$prefix/sbin/qmailctl" ) 
	{
		if ( -e $qmailctl ) {
			unless ( -l $qmailctl ) {
				print "updating $qmailctl.\n" if $debug;
				unlink($qmailctl);
				symlink("$qmaildir/bin/qmailctl", $qmailctl);
			}
		}
		else {
			print "control_create: adding symlink $qmailctl\n" if $debug;
			symlink("$qmaildir/bin/qmailctl", $qmailctl) or carp "couldn't link $qmailctl: $!";
		};
	}

	if ( -e "$qmaildir/rc" ) 
	{
		print "control_create: $qmaildir/rc already exists.\n" if $debug;
	}
	else 
	{
		print "control_create: creating $qmaildir/rc.\n" if $debug;
		my $file = "/tmp/toaster-watcher-send-runfile";
		if ( $self->build_send_run($conf, $file ) )
		{
			$self->install_supervise_run( {file=>$file, destination=>"$qmaildir/rc"} );
			print "success.\n";
		}
		else { print "FAILED.\n" };
	};

	if ( -e "$confdir/rc.d/qmail.sh" ) 
	{
		unlink("$confdir/rc.d/qmail.sh") or croak "couldn't delete $confdir/rc.d/qmail.sh: $!";
		print "control_create: removing $confdir/rc.d/qmail.sh\n";
	};
};


sub control_write($$)
{
	my ($self, $conf, $file) = @_;

	unless ( open FILE, ">$file" ) {
		carp "control_write: FAILED to open $file: $!\n";
		return 0;
	};

	my $qdir     = $conf->{'qmail_dir'} || "/var/qmail";
	my $prefix   = $conf->{'toaster_prefix'} || "/usr/local";
	my $tcprules = $utility->find_the_bin("tcprules");
	my $svc      = $utility->find_the_bin("svc");

	unless ( -x $tcprules && -x $svc ) {
		carp "control_write: FAILED to find tcprules or svc.\n";
		return 0;
	};

	print FILE <<EOQMAILCTL
#!/bin/sh

PATH=$qdir/bin:$prefix/bin:/usr/bin:/bin
export PATH

case "\$1" in
	stat)
		cd $qdir/supervise
		svstat * */log
	;;
	doqueue|alrm|flush)
		echo "Sending ALRM signal to qmail-send."
		$svc -a $qdir/supervise/send
	;;
	queue)
		qmail-qstat
		qmail-qread
	;;
	reload|hup)
		echo "Sending HUP signal to qmail-send."
		$svc -h $qdir/supervise/send
	;;
	pause)
		echo "Pausing qmail-send"
		$svc -p $qdir/supervise/send
		echo "Pausing qmail-smtpd"
		$svc -p $qdir/supervise/smtp
	;;
	cont)
		echo "Continuing qmail-send"
		$svc -c $qdir/supervise/send
		echo "Continuing qmail-smtpd"
		$svc -c $qdir/supervise/smtp
	;;
	restart)
		echo "Restarting qmail:"
		echo "* Stopping qmail-smtpd."
		$svc -d $qdir/supervise/smtp
		echo "* Sending qmail-send SIGTERM and restarting."
		$svc -t $qdir/supervise/send
		echo "* Restarting qmail-smtpd."
		$svc -u $qdir/supervise/smtp
	;;
	cdb)
		if [ -s ~vpopmail/etc/tcp.smtp ]
		then
			$tcprules ~vpopmail/etc/tcp.smtp.cdb ~vpopmail/etc/tcp.smtp.tmp < ~vpopmail/etc/tcp.smtp
			chmod 644 ~vpopmail/etc/tcp.smtp*
			echo "Reloaded ~vpopmail/etc/tcp.smtp."
		fi 
                
		if [ -s /etc/tcp.smtp ]
		then
			$tcprules /etc/tcp.smtp.cdb /etc/tcp.smtp.tmp < /etc/tcp.smtp
			chmod 644 /etc/tcp.smtp*
			echo "Reloaded /etc/tcp.smtp."
		fi

		if [ -s $qdir/control/simcontrol ]
		then
			if [ -x $qdir/bin/simscanmk ]
			then
				$qdir/bin/simscanmk
				echo "Reloaded $qdir/control/simcontrol."
				$qdir/bin/simscanmk -g
				echo "Reloaded $qdir/control/simversions."
			fi
		fi

		if [ -s $qdir/users/assign ]
		then
			if [ -x $qdir/bin/qmail-newu ]
			then
				echo "Reloaded $qdir/users/assign."
			fi
		fi

		if [ -s $qdir/control/morercpthosts ]
		then
			if [ -x $qdir/bin/qmail-newmrh ]
			then
				$qdir/bin/qmail-newmrh
				echo "Reloaded $qdir/control/morercpthosts"
			fi
		fi

		if [ -s $qdir/control/spamt ]
		then
			if [ -x $qdir/bin/qmail-newst ]
			then
				$qdir/bin/qmail-newst
				echo "Reloaded $qdir/control/spamt"
			fi
		fi
	;;
	help)
		cat <<HELP
		pause -- temporarily stops mail service (connections accepted, nothing leaves)
		cont -- continues paused mail service
		stat -- displays status of mail service
		cdb -- rebuild the cdb files (tcp.smtp, users, simcontrol)
		restart -- stops and restarts smtp, sends qmail-send a TERM & restarts it
		doqueue -- sends qmail-send ALRM, scheduling queued messages for delivery
		reload -- sends qmail-send HUP, rereading locals and virtualdomains
		queue -- shows status of queue
		alrm -- same as doqueue
		hup -- same as reload
HELP
	;;
	*)
		echo "Usage: \$0 {restart|doqueue|flush|reload|stat|pause|cont|cdb|queue|help}"
		exit 1
	;;
esac

exit 0

EOQMAILCTL
;

	close FILE;
};


=head2 get_domains_from_assign

Fetch a list of domains from the qmaildir/users/assign file.

  $qmail->get_domains_from_assign($assign, $debug, $match, $value);

 $assign is the path to the assign file.
 $debug is optional
 $match is an optional field to match (dom, uid, dir)
 $value is the pattern to  match

returns an array

=cut

sub get_domains_from_assign(;$$$$)
{
	my ($self, $assign, $debug, $match, $value) = @_;

	$assign ||= "/var/qmail/users/assign";

	my @domains;
	my @lines = $utility->file_read($assign);
	print "Parsing through the file $assign..." if $debug;

	foreach my $line (@lines)
	{
		chomp $line;
		my @fields = split(":", $line);
		if ($fields[0] ne "" && $fields[0] ne ".") 
		{
			my %domain = (
				stat => $fields[0],
				dom  => $fields[1],
				uid  => $fields[2],
				gid  => $fields[3],
				dir  => $fields[4]
			);

			unless ($match) { push @domains, \%domain; } 
			else 
			{
				if    ( $match eq "dom" && $value eq "$fields[1]" ) { push @domains, \%domain } 
				elsif ( $match eq "uid" && $value eq "$fields[2]" ) { push @domains, \%domain } 
				elsif ( $match eq "dir" && $value eq "$fields[4]" ) { push @domains, \%domain };
			}
		};
	};
	print "done.\n\n" if $debug;;
	return @domains;
}



=head2 get_list_of_rbls

  my $selected = $qmail->get_list_of_rbls($arrayref, $debug);

We get passed a configuration file (toaster-watcher.conf) and from it we extract all the RBL's the user has selected.

returns an array ref.

=cut

sub get_list_of_rbls($;$)
{
	my ($self, $conf, $debug) = @_;

	my (@sorted, @unsorted);
	my (@list, %sort_keys, $sort);

	unless ( $utility->is_hashref($conf) ) 
	{
		my ($package, $filename, $line) = caller;
		carp "FATAL: $filename:$line passed get_list_of_rbls an invalid argument.\n";
		return 0;
	};

	foreach my $key ( keys %$conf )
	{
		#print "checking $key \n" if $debug;

		next if ( $key =~ /^rbl_enable/   );
		next if ( $key =~ /^rbl_reverse_dns/ );
		next if ( $key =~ /^rbl_timeout/  );
		next if ( $key =~ /_message$/     );

		next unless ( $key =~ /^rbl/ && $conf->{$key} > 0 );

		$key =~ /^rbl_([a-zA-Z\.\-]*)\s*$/;
		#$key =~ /^rbl_([a-zA-Z_\.\-]*)\s*$/;

		print "good key: $1 " if $debug;

		if ( $conf->{$key} > 1 ) {         # test for custom sort
			print "\t  sorted value $conf->{$key}\n" if $debug;
			@sorted[$conf->{$key} - 2] = $1;
		}
		else { 
			print "\t  unsorted\n" if $debug;
			push @unsorted, $1; 
		};
	};

	push @sorted, @unsorted;  # add the unsorted values to the sorted list

	print "\nsorted order:\n\t" . join("\n\t", @sorted) . "\n" if $debug;

	return \@sorted;          # and return them
};

=head2 get_list_of_rwls

  my $selected = $qmail->get_list_of_rwls($conf, $debug);

Here we collect a list of the RWLs from the configuration file that get's passed to us. 

returns an arrayref with a list of the enabled list from your config file.

=cut

sub get_list_of_rwls($;$)
{
	my ($self, $conf, $debug) = @_;
	my @list;

	unless ( $utility->is_hashref($conf) ) 
	{
		my ($package, $filename, $line) = caller;
		carp "FATAL: $filename:$line passed get_list_of_rwls an invalid argument.\n";
		return 0;
	}

	foreach my $key ( keys %$conf )
	{		
		if ( $key =~ /^rwl/ && $conf->{$key} == 1 ) 
		{
			next if ( $key =~ /^rwl_enable/ );
			$key =~ /^rwl_([a-zA-Z_\.\-]*)\s*$/;

			print "good key: $1 \n" if $debug;
			push @list, $1;
		};
	};
	return \@list;
};


sub get_qmailscanner_virus_sender_ips($)
{
	my ($self, $conf) = @_;
	my @ips;

	my $debug   = $conf->{'debug'};
	my $block   = $conf->{'qs_block_virus_senders'};
	my $clean   = $conf->{'qs_quarantine_clean'};
	my $quarantine = $conf->{'qs_quarantine_dir'};

	unless (-d $quarantine) {
		$quarantine = "/var/spool/qmailscan/quarantine" if (-d "/var/spool/qmailscan/quarantine");
	};

	unless (-d "$quarantine/new")
	{
		carp "no quarantine dir!";
		return;
	};

	my @files = $utility->get_dir_files("$quarantine/new");

	foreach my $file (@files)
	{
		if ( $block ) 
		{
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

				# we need to check the message and verify that it's
				# a virus that was blocked, not an admin testing
				# (Matt 4/3/2004)

				if ( $ip =~ /\s+/ or ! $ip ) { print "$line\n" if $debug; }
				else                         { push @ips, $ip;            };
				print "\t$ip" if $debug;
			};
			print "\n" if $debug;
		};
		unlink $file if $clean;
	};

	my (%hash, @sorted);
	foreach (@ips) { $hash{$_} = "1"; };
	foreach (keys %hash) { push @sorted, $_; delete $hash{$_} };
	return @sorted;
};


sub install_qmail($;$$)
{

=head2 install_qmail

Builds qmail and installs qmail with patches (based on your settings in toaster-watcher.conf), installs the SSL certs, adjusts the permissions of several files that need it.

  $qmail->install_qmail($conf, $package, $debug);

$conf is a hash of values from toaster-watcher.conf

$package is the name of the program. It defaults to "qmail-1.03"

Patch info is here: http://www.tnpi.biz/internet/mail/toaster/patches/

=cut

	my ($self, $conf, $package, $debug) = @_;
	my ($patch, $chkusr);

	unless ( $utility->is_hashref($conf) ) 
	{
		my ($package, $filename, $line) = caller;
		carp "FATAL: $filename:$line passed install_qmail an invalid argument.\n";
		return 0;
	}

	if ( $conf->{'install_netqmail'} )
	{
		$self->netqmail($conf);
		exit;
	};

	$self->install_qmail_groups_users($conf);

	my $ver = $conf->{'install_qmail'} || "1.03";

	$package ||= "qmail-$ver";

	my $src      = $conf->{'toaster_src_dir'}      || "/usr/local/src";
	my $qmaildir = $conf->{'qmail_dir'}            || "/var/qmail";
	my $vpopdir  = $conf->{'vpopmail_home_dir'}    || "/usr/local/vpopmail";
	my $mysql    = $conf->{'qmail_mysql_include'}  || "/usr/local/lib/mysql/libmysqlclient.a";
	my $dl_site  = $conf->{'toaster_dl_site'}      || "http://www.tnpi.biz";
	my $toaster  = "$dl_site/internet/mail/toaster";

	$utility->chdir_source_dir("$src/mail");

	if ( -e $package ) 
	{
		unless ( $utility->source_warning($package, 1, $src) )
		{
			carp "install_qmail: FATAL: sorry, I can't continue.\n"; 
			return 0;
		};
	};

	unless ( defined $conf->{'qmail_chk_usr_patch'} ) {
		print "\nCheckUser support causes the qmail-smtpd daemon to verify that
a user exists locally before accepting the message, during the SMTP conversation.
This prevents your mail server from accepting messages to email addresses that
don't exist in vpopmail. It is not compatible with system user mailboxes. \n\n";

		$chkusr = $utility->yes_or_no("Do you want qmail-smtpd-chkusr support enabled?");
	} 
	else 
	{
		if ( $conf->{'qmail_chk_usr_patch'} ) {
			$chkusr = 1;
			print "chk-usr patch: yes\n";
		};
	};

	if ($chkusr) { $patch = "$package-toaster-2.8.patch"; } 
	else         { $patch = "$package-toaster-2.6.patch"; };

	my $site  = "http://cr.yp.to/software";

	unless ( -e "$package.tar.gz" ) 
	{
		if ( -e "/usr/ports/distfiles/$package.tar.gz" ) 
		{
			use File::Copy;
			copy("/usr/ports/distfiles/$package.tar.gz", "$src/mail/$package.tar.gz");  
		} 
		else 
		{ 
			$utility->get_file("$site/$package.tar.gz"); 
			unless ( -e "$package.tar.gz" ) {
				croak "install_qmail FAILED: couldn't fetch $package.tar.gz!\n";
			};
		};
	};

	unless ( -e $patch ) 
	{
		$utility->get_file("$toaster/patches/$patch");
		unless ( -e $patch )  { croak "\n\nfailed to fetch patch $patch!\n\n"; };
	};

	my $tar      = $utility->find_the_bin("tar");
	my $patchbin = $utility->find_the_bin("patch");
	unless ( $tar && $patchbin ) { croak "couldn't find tar or patch!\n"; };

	$utility->syscmd( "$tar -xzf $package.tar.gz");
	chdir("$src/mail/$package") or croak "install_qmail: cd $src/mail/$package failed: $!\n";
	$utility->syscmd("$patchbin < $src/mail/$patch");

	$utility->file_write("conf-qmail",    $qmaildir) or croak "couldn't write to conf-qmail: $!";
	$utility->file_write("conf-vpopmail", $vpopdir) or croak "couldn't write to conf-vpopmail: $!";
	$utility->file_write("conf-mysql",    $mysql) or croak "couldn't write to conf-mysql: $!";

	my $servicectl = "/usr/local/sbin/services";
	if (-x $servicectl)
	{
		print "Stopping Qmail!\n";
		$utility->syscmd("$servicectl stop");
		$self->send_stop($conf);
	};

	$utility->syscmd( "make setup");

	unless ( -f "$qmaildir/control/servercert.pem" ) { 
		$utility->syscmd( "gmake cert") 
	};

	if ($chkusr) 
	{
		my $uid = getpwnam("vpopmail");
		my $gid = getgrnam("vchkpw");

		chown($uid, $gid, "$qmaildir/bin/qmail-smtpd") 
			or carp "chown $qmaildir/bin/qmail-smtpd failed: $!\n";

		$utility->syscmd("chmod 6555 $qmaildir/bin/qmail-smtpd");
	};

	unless ( -e "/usr/share/skel/Maildir" ) 
	{
		$utility->syscmd( "$qmaildir/bin/maildirmake /usr/share/skel/Maildir");
	};

	$self->config($conf, 1);

	if (-x $servicectl)
	{
		print "Stopping Qmail & supervised services!\n";
		$utility->syscmd("$servicectl start")
	};
};


=head2 install_qmail_control_files

  $qmail->install_qmail_control_files($conf, $debug);

$conf is a hashref of values pulled from toaster-watcher.conf.

Generates the qmail/supervise/*/run files based on your settings.

=cut

sub install_qmail_control_files($;$)
{
	my ($self, $conf, $debug) = @_;

	unless ( $utility->is_hashref($conf) ) 
	{
		my ($package, $filename, $line) = caller;
		carp "FATAL: $filename:$line passed install_qmail_control_files an invalid argument.\n";
		return 0;
	}

	$debug = $conf->{'debug'} if $conf->{'debug'};
	my $supervise = $conf->{'qmail_supervise'} || "/var/qmail/supervise";

	foreach my $prot ( qw/ smtp send pop3 submit / )
	{
		my $supervisedir = $self->supervise_dir_get($conf, $prot);
		my $run_f = "$supervisedir/run";

		unless ( -e $run_f )
		{
			my $file = "/tmp/toaster-watcher-$prot-runfile";

			if ($prot eq "smtp")
			{
				#$file = "/tmp/toaster-watcher-smtpd-runfile";
				if ( $self->build_smtp_run($conf, $file, $debug ) )
				{
					print "install_qmail_control_files: installing $run_f\n" if $debug;
					$self->install_supervise_run( {file=>$file, destination=>$run_f} );
				};
			}
			elsif ($prot eq "send")
			{
				if ( $self->build_send_run($conf, $file, $debug ) )
				{
					print "install_qmail_control_files: installing $run_f\n" if $debug;
					$self->install_supervise_run( {file=>$file, destination=>$run_f} );
				};
			}
			elsif ($prot eq "pop3")
			{
				if ( $self->build_pop3_run($conf, $file, $debug ) )
				{
					print "install_qmail_control_files: installing $run_f\n" if $debug;
					$self->install_supervise_run( {file=>$file, destination=>$run_f} );
				};
			}
			elsif ($prot eq "submit")
			{
				if ( $self->build_submit_run($conf, $file, $debug ) )
				{
					print "install_qmail_control_files: installing $run_f\n" if $debug;
					$self->install_supervise_run( {file=>$file, destination=>$run_f} );
				};
			};
		} 
		else
		{
			print "install_qmail_control_files: $run_f already exists!\n";
		};
	};
};


sub install_qmail_groups_users($)
{
	my ($self, $conf) = @_;

	unless ( $utility->is_hashref($conf) ) 
	{
		my ($package, $filename, $line) = caller;
		carp "FATAL: $filename:$line passed install_qmail_groups_users an invalid argument.\n";
		return 0;
	}
	
	my $qmaildir = $conf->{'qmail_dir'};
	unless ($qmaildir) { $qmaildir = "/var/qmail"; };

	my $errmsg = "ERROR: You need to update your toaster-watcher.conf file!\n";

	my $alias   = $conf->{'qmail_user_alias'}  || croak "$errmsg (alias)";
	my $qmaild  = $conf->{'qmail_user_daemon'} || croak "$errmsg (qmaild)";
	my $qmailp  = $conf->{'qmail_user_passwd'} || croak "$errmsg (qmailp)";
	my $qmailq  = $conf->{'qmail_user_queue'}  || croak "$errmsg (qmailq)";
	my $qmailr  = $conf->{'qmail_user_remote'} || croak "$errmsg (qmailr)";
	my $qmails  = $conf->{'qmail_user_send'}   || croak "$errmsg (qmails)";
	my $qmaill  = $conf->{'qmail_user_log'}    || croak "$errmsg (qmaill)";
	my $qmailg  = $conf->{'qmail_group'}       || croak "$errmsg (qmailg)";
	my $nofiles = $conf->{'qmail_log_group'}   || croak "$errmsg (nofiles)";

	$perl->module_load( { module=>"Mail::Toaster::Passwd"} );
	my $passwd = Mail::Toaster::Passwd->new;

	$passwd->creategroup("qmail", "82");
	$passwd->creategroup("qnofiles", "81");

	unless ( $passwd->exist($alias) ) {
		$passwd->user_add( {user=>$alias,homedir=>$qmaildir,uid=>81,gid=>81} );
	};

	unless ( $passwd->exist($qmaild) ) {
		$passwd->user_add( {user=>$qmaild,homedir=>$qmaildir,uid=>82,gid=>81} );
	};

	unless ( $passwd->exist($qmaill) ) {
		$passwd->user_add( {user=>$qmaill,homedir=>$qmaildir,uid=>83,gid=>81} );
	};

	unless ( $passwd->exist($qmailp) ) {
		$passwd->user_add( {user=>$qmailp,homedir=>$qmaildir,uid=>84,gid=>81} );
	};

	unless ( $passwd->exist($qmailq) ) {
		$passwd->user_add( {user=>$qmailq,homedir=>$qmaildir,uid=>85,gid=>82} );
	};

	unless ( $passwd->exist($qmailr) ) {
		$passwd->user_add( {user=>$qmailr,homedir=>$qmaildir,uid=>86,gid=>82} );
	};

	unless ( $passwd->exist($qmails) ) {
		$passwd->user_add( {user=>$qmails,homedir=>$qmaildir,uid=>87,gid=>82} );
	};
};


=head2 install_supervise_run

Installs a new supervise/run file for a supervised service. It first builds a new file, then compares it to the existing one and installs the new file if it's changed. It optionally notifies the admin.

  my $file = "/tmp/toaster-watcher-smtpd-runfile";

  if ( $qmail->build_smtp_run($conf, $file, $debug ) )
  {
    $qmail->install_supervise_run( {file=>$file, service=>"smtp"}, $debug);
  };

Input is a hashref with these values:

  file    - new file that was created (typically /tmp/something) 
  service - one of (smtp, send, pop3, submit)

returns 1 on success, 0 on error

=cut

sub install_supervise_run($$)
{
	my ($self, $vals, $conf) = @_;

	my $tmpfile = $vals->{'file'};

	my $dir = $conf->{'qmail_dir'} || "/var/qmail";
	my $file = "$dir/rc";

	if ( $vals->{'destination'} ) { $file = $vals->{'destination'} } 
	else 
	{
		if ( $vals->{'service'} ) {
			$dir  = $self->supervise_dir_get($conf, $vals->{'service'});
			$file = "$dir/run" if $dir;
		};
	}

	my $debug = $vals->{'debug'};
	$debug = $conf->{'toaster_debug'} if ($conf->{'toaster_debug'});

	unless ( -e $tmpfile ) {
		print "FATAL: the file to install ($tmpfile) is missing!\n";
		return 0;
	};

	unless ( chmod 00755, $tmpfile ) {
		carp "FATAL: couldn't chmod $tmpfile: $!\n";
		return 0;
	};

	unless ( -e $file ) 
	{
		print "install_supervise_run: installing $file..." if $debug;
	} 
	else 
	{
		print "install_supervise_run: updating $file..." if $debug;
	};

	my $r = ( $utility->install_if_changed($tmpfile, $file, {
			mode=>00755,
			notify=>$conf->{'supervise_rebuild_notice'},
			email=>$conf->{'toaster_admin_email'},
			clean=>1,
		}, $debug ) 
	);

	print "done\n" if $debug;

	return $r;
};



=head2 install_qmail_control_log_files

	$qmail->install_qmail_control_log_files($conf, $progs, $debug);

$conf is a hash of values. See $utility->parse_config or toaster-watcher.conf for config values.

Installs the files the control your supervised processes logging. Typically this consists of qmail-smtpd, qmail-send, and qmail-pop3d. The generated files are:
                
 qmail_supervise/pop3/log/run
 qmail_supervise/smtp/log/run
 qmail_supervise/send/log/run
 qmail_supervise/submit/log/run

=cut

sub install_qmail_control_log_files($$$)
{
	my ($self, $conf, $progs, $debug) = @_;
	my (@lines);

	unless ( $utility->is_hashref($conf) ) 
	{
		my ($package, $filename, $line) = caller;
		carp "FATAL: $filename:$line passed install_qmail_control_log_files an invalid argument.\n";
		return 0;
	}
	
	$debug        = $conf->{'debug'} if $conf->{'debug'};
	my $supervise = $conf->{'qmail_supervise'} || "/var/qmail/supervise";

	unless ( $progs && $progs->[0] ) { $progs = ["smtp", "send", "pop3", "submit"]  };

	# Create log/run files
	foreach my $serv ( @$progs )
	{
		my $supervisedir = $self->supervise_dir_get($conf, $serv);
		my $run_f = "$supervisedir/log/run";

		$self->_formatted("install_qmail_control_log_files: preparing $run_f") if $debug;

		@lines = $toaster->supervised_do_not_edit_notice($conf, undef );

		my $runline = $toaster->supervised_multilog($conf, $serv, $debug);
		push @lines, $runline;

		my $tmpfile = "/tmp/supervise_".$serv."_log_run";
		$utility->file_write($tmpfile, @lines);

		$self->_formatted("install_qmail_control_log_files: comparing $run_f") if $debug;

		if (-s $tmpfile) 
		{
			return 0 unless ( $utility->install_if_changed($tmpfile, $run_f, {
					mode  => 00755,
					notify=> $conf->{'supervise_rebuild_notice'},
					email => $conf->{'toaster_admin_email'},
					clean => 1,
				}, $debug ) 
			);
			$self->_formatted("install_supervise_run: updating $run_f...", "ok");
		};
	}

	$toaster->supervised_dir_test($conf, "smtp", $debug);
	$toaster->supervised_dir_test($conf, "send", $debug);
	$toaster->supervised_dir_test($conf, "pop3", $debug);
	$toaster->supervised_dir_test($conf, "submit", $debug);
};


=head2 netqmail

Builds net-qmail with patches (based on your settings in toaster-watcher.conf), installs the SSL certs, adjusts the permissions of several files that need it.

  $qmail->netqmail($conf, $package);

$conf is a hash of values from toaster-watcher.conf

$package is the name of the program. It defaults to "qmail-1.03"

Patch info is here: http://www.tnpi.biz/internet/mail/toaster/patches/

=cut

sub netqmail($;$)
{
	my ($self, $conf, $package) = @_;
	my ($smtp_reject);

	if ( $conf && ! $utility->is_hashref($conf) ) 
	{
		my ($package, $filename, $line) = caller;
		$self->_formatted("netqmail: $filename:$line passed an invalid argument!", "FAILED");
		return 0;
	}
	
	my $ver      = $conf->{'install_netqmail'} || "1.05";
	my $src      = $conf->{'toaster_src_dir'}  || "/usr/local/src";
	my $qmaildir = $conf->{'qmail_dir'}        || "/var/qmail";

	$package ||= "netqmail-$ver";
	$self->install_qmail_groups_users($conf);

	my $vpopdir    = $conf->{'vpopmail_home_dir'}   || "/usr/local/vpopmail";
	my $mysql      = $conf->{'qmail_mysql_include'} || "/usr/local/lib/mysql/libmysqlclient.a";
	my $qmailgroup = $conf->{'qmail_log_group'}     || "qnofiles";
	my $dl_site    = $conf->{'toaster_dl_site'}     || "http://www.tnpi.biz";
	my $toaster    = "$dl_site/internet/mail/toaster";
	my $vhome      = $conf->{'vpopmail_home_dir'}   || "/usr/local/vpopmail";

	$utility->chdir_source_dir("$src/mail");

	if ( -e $package ) 
	{
		my $r = $utility->source_warning($package, 1, $src);
		unless ($r) 
		{ 
			carp "\nnetqmail: OK then, skipping install.\n\n"; 
			return 0;
		};
	};

	if ( defined $conf->{'qmail_smtp_reject_patch'} ) {
		if ( $conf->{'qmail_smtp_reject_patch'} ) {
			$smtp_reject= 1;
			print "smtp_reject patch: yes\n";
		} 
		else { print "smtp_reject patch: no\n" };
	};

	my $patch    = "$package-toaster-3.1.patch";

	print "netqmail: using patch $patch\n";

	my $site  = "http://www.qmail.org";

	unless ( -e "$package.tar.gz" ) 
	{
		if ( -e "/usr/ports/distfiles/$package.tar.gz" ) 
		{
			use File::Copy;
			copy("/usr/ports/distfiles/$package.tar.gz", "$src/mail/$package.tar.gz");  
		} 
		else 
		{ 
			$utility->get_file("$site/$package.tar.gz"); 
			unless ( -e "$package.tar.gz" ) {
				croak "netqmail FAILED: couldn't fetch $package.tar.gz!\n";
			};
		};
	};

	unless ( -e $patch )
	{
		$utility->get_file("$toaster/patches/$patch");
		unless ( -e $patch )  { croak "\n\nfailed to fetch patch $patch!\n\n"; };
	};

	my $smtp_rej_patch = "$package-smtp_reject-3.0.patch";

	unless ( -e $smtp_rej_patch )
	{
		$utility->get_file("$toaster/patches/$smtp_rej_patch");
		unless ( -e $smtp_rej_patch )  { croak "\n\nfailed to fetch patch $smtp_rej_patch!\n\n"; };
	};

	unless ( $utility->archive_expand("$package.tar.gz") ) { 
		croak "couldn't expand $package.tar.gz!\n"; 
	};

	chdir("$src/mail/$package") or croak "netqmail: cd $src/mail/$package failed: $!\n";
	$utility->syscmd("./collate.sh");
	chdir("$src/mail/$package/$package") or croak "netqmail: cd $src/mail/$package/$package failed: $!\n";

	my $patchbin = $utility->find_the_bin("patch");
	croak "couldn't find tar or patch!\n" unless ($patchbin);

	print "netqmail: applying $patch\n";
	$utility->syscmd("$patchbin < $src/mail/$patch");
	$utility->syscmd("$patchbin < $src/mail/$smtp_rej_patch") if $smtp_reject;

	print "netqmail: fixing up conf-qmail\n";
	$utility->file_write("conf-qmail",    $qmaildir) or croak "couldn't write to conf-qmail: $!";

	print "netqmail: fixing up conf-vpopmail\n";
	$utility->file_write("conf-vpopmail", $vpopdir) or croak "couldn't write to conf-vpopmail: $!";

	print "netqmail: fixing up conf-mysql\n";
	$utility->file_write("conf-mysql",    $mysql)  or croak "couldn't write to conf-mysql: $!";

	my $prefix = $conf->{'toaster_prefix'} || "/usr/local/";
	my $ssl_lib = "$prefix/lib";
	if ( ! -e "$ssl_lib/libcrypto.a" ) {
		if    ( -e "/opt/local/lib/libcrypto.a" ) { $ssl_lib = "/opt/local/lib"; }
		elsif ( -e "/usr/local/lib/libcrypto.a" ) { $ssl_lib = "/usr/local/lib"; }
		elsif ( -e "/opt/lib/libcrypto.a"       ) { $ssl_lib = "/opt/lib";       }
		elsif ( -e "/usr/lib/libcrypto.a"       ) { $ssl_lib = "/usr/lib";       };
	};

	my @lines = $utility->file_read("Makefile");
	foreach my $line ( @lines )
	{
		if ( $vpopdir ne "/home/vpopmail" ) {          # fix up vpopmail home dir
			if ( $line =~ /^VPOPMAIL_HOME/ ) {
				$line =   'VPOPMAIL_HOME='.$vpopdir;
			}
		};

		if ( $line =~ /tls.o ssl_timeoutio.o -L\/usr\/local\/ssl\/lib -lssl -lcrypto/ ) {
			$line = '	tls.o ssl_timeoutio.o -L'.$ssl_lib.' -lssl -lcrypto \\';
		};

		if ( $line =~ /constmap.o tls.o ssl_timeoutio.o ndelay.a -L\/usr\/local\/ssl\/lib -lssl -lcrypto \\/ ) {
			$line = '	constmap.o tls.o ssl_timeoutio.o ndelay.a -L'.$ssl_lib.' -lssl -lcrypto \\';
		};
	}
	$utility->file_write("Makefile", @lines);

	if ( $conf->{'qmail_queue_extra'} ) 
	{
		print "netqmail: enabling QUEUE_EXTRA...\n";
		my $success = 0;
		my @lines = $utility->file_read("extra.h");
		foreach my $line ( @lines )
		{
			if ( $line =~ /#define QUEUE_EXTRA ""/ ) {
				$line =   '#define QUEUE_EXTRA "Tlog\0"';
				$success++;
			}

			if ( $line =~ /#define QUEUE_EXTRALEN 0/ ) {
				$line  =  '#define QUEUE_EXTRALEN 5';
				$success++;
			};
		};

		if ( $success == 2 ) {
			print "success.\n";
			$utility->file_write("extra.h", @lines);
		} else {
			print "FAILED.\n";
		}
	};

	if ( $os eq "darwin" ) 
	{
		$self->netqmail_darwin_fixups();
		move("INSTALL", "INSTALL.txt");   # fix due to case sensitive file system
	};

	print "netqmail: fixing up conf-cc\n";
	my $cmd = "cc -O2 -DTLS=20060104 -I$vpopdir/include";

	if ( -d "/opt/local/include/openssl" ) 
	{
		print "netqmail: building against /opt/local/include/openssl.\n";
		$cmd .= " -I/opt/local/include/openssl";
	}
	elsif ( -d "/usr/local/include/openssl" && $conf->{'install_openssl_port'} ) 
	{
		print "netqmail: building against /usr/local/include/openssl from ports.\n";
		$cmd .= " -I/usr/local/include/openssl";
	} 
	elsif ( -d "/usr/include/openssl" ) 
	{
		print "netqmail: using system supplied OpenSSL libraries.\n";
		$cmd .= " -I/usr/include/openssl";
	} 
	else 
	{
		if ( -d "/usr/local/include/openssl" ) 
		{
			print "netqmail: building against /usr/local/include/openssl.\n";
			$cmd .= " -I/usr/local/include/openssl";
		} else {
			print "netqmail: WARNING: I couldn't find your OpenSSL libraries. This might cause problems!\n";
		};
	};
	$utility->file_write("conf-cc", $cmd)  or croak "couldn't write to conf-cc: $!";

	print "netqmail: fixing up conf-groups\n";
	$utility->file_write("conf-groups", ("qmail", $qmailgroup) ) or croak "couldn't write to conf-groups: $!";

	my $servicectl = "/usr/local/sbin/services";
	if (-x $servicectl)
	{
		print "Stopping Qmail!\n";
		$self->send_stop($conf);
		$utility->syscmd("$servicectl stop");
	};

	my $make = $utility->find_the_bin("gmake") || $utility->find_the_bin("make");

	$utility->syscmd("$make setup");
	unless ( -f "$qmaildir/control/servercert.pem" ) 
	{
		print "netqmail: installing SSL certificates \n";
		$utility->syscmd("$make cert");
	};
	unless ( -f "$qmaildir/control/rsa512.pem" ) {
		print "netqmail: install temp SSL \n";
		$utility->syscmd( "$make tmprsadh");
	};

#	if ($chkusr) {
		my $uid = getpwnam("vpopmail");
		my $gid = getgrnam("vchkpw");

		chown($uid, $gid, "$qmaildir/bin/qmail-smtpd") 
			or carp "chown $qmaildir/bin/qmail-smtpd failed: $!\n";

		$utility->syscmd("chmod 06555 $qmaildir/bin/qmail-smtpd");
#	};

	my $skel = "/usr/share/skel";
	unless ( -d $skel ) {
		$skel = "/etc/skel" if ( -d "/etc/skel" );   # linux
	};

	$utility->syscmd( "$qmaildir/bin/maildirmake $skel/Maildir") unless (-e "$skel/Maildir");

	$self->config($conf);

	if (-x $servicectl)
	{
		print "Stopping Qmail & supervised services!\n";
		$utility->syscmd("$servicectl start") 
	};
};


sub netqmail_darwin_fixups
{
	print "netqmail: fixing up conf-ld\n";
	$utility->file_write("conf-ld",    "cc -Xlinker -x")  or croak "couldn't write to conf-ld: $!";

	print "netqmail: fixing up dns.c for Darwin\n";
	my @lines = $utility->file_read("dns.c");
	foreach my $line ( @lines )
	{ 
		if ( $line =~ /#include <netinet\/in.h>/ ) 
		{
			$line = "#include <netinet/in.h>\n#include <nameser8_compat.h>";
		};
	};
	$utility->file_write("dns.c", @lines);

	print "netqmail: fixing up strerr_sys.c for Darwin\n";
	@lines = $utility->file_read("strerr_sys.c");
	foreach my $line ( @lines )
	{ 
		if ( $line =~ /struct strerr strerr_sys/ ) 
		{
			$line = "struct strerr strerr_sys = {0,0,0,0};";
		};
	};
	$utility->file_write("strerr_sys.c", @lines);

	move("INSTALL", "INSTALL.txt");
	print "netqmail: fixing up hier.c for Darwin\n";
	@lines = $utility->file_read("hier.c");
	foreach my $line (@lines)
	{
		if ( $line =~ /c\(auto_qmail,"doc","INSTALL",auto_uido,auto_gidq,0644\)/ )
		{
			$line = 'c(auto_qmail,"doc","INSTALL.txt",auto_uido,auto_gidq,0644);';
		};
	};
	$utility->file_write("hier.c", @lines);

	move("SENDMAIL", "SENDMAIL.txt");
};



=head2 netqmail_virgin

Builds and installs a pristine net-qmail. This is necessary to resolve a chicken and egg problem. You can't apply the toaster patches (specifically chkuser) against NetQmail until vpopmail is installed, and you can't install vpopmail without qmail being installed. After installing this, and then vpopmail, you can rebuild NetQmail with the toaster patches.

  $qmail->netqmail_virgin($conf, $package);

$conf is a hash of values from toaster-watcher.conf used to determine how to configure qmail.

$package is the name of the program. It defaults to "qmail-1.03"

=cut

sub netqmail_virgin($;$)
{
	my ($self, $conf, $package) = @_;
	my ($chkusr);

	if ( $conf && ! $utility->is_hashref($conf) ) 
	{
		my ($package, $filename, $line) = caller;
		carp "FATAL: $filename:$line passed netqmail_virgin an invalid argument.\n";
		return 0;
	}
	
	my $ver = $conf->{'install_netqmail'} || "1.05";

	$package ||= "netqmail-$ver";

	my $src      = $conf->{'toaster_src_dir'} || "/usr/local/src";
	my $qmaildir = $conf->{'qmail_dir'}       || "/var/qmail";

	$self->install_qmail_groups_users($conf);

	my $mysql      = $conf->{'qmail_mysql_include'} || "/usr/local/lib/mysql/libmysqlclient.a";
	my $qmailgroup = $conf->{'qmail_log_group'}     || "qnofiles";

	$utility->chdir_source_dir("$src/mail");

	if ( -e $package ) 
	{
		unless ( $utility->source_warning($package, 1, $src) ) 
		{ 
			carp "\nnetqmail: OK then, skipping install.\n\n"; 
			return 0;
		};
	};

	my $site  = "http://www.qmail.org";

	unless ( -e "$package.tar.gz" ) 
	{
		if ( -e "/usr/ports/distfiles/$package.tar.gz" ) 
		{
			use File::Copy;
			copy("/usr/ports/distfiles/$package.tar.gz", "$src/mail/$package.tar.gz");  
		} 
		else 
		{ 
			$utility->get_file("$site/$package.tar.gz"); 
			unless ( -e "$package.tar.gz" ) {
				croak "netqmail FAILED: couldn't fetch $package.tar.gz!\n";
			};
		};
	};

	unless ($utility->archive_expand("$package.tar.gz") ) { croak "couldn't expand $package.tar.gz\n"; };

	chdir("$src/mail/$package") or croak "netqmail: cd $src/mail/$package failed: $!\n";
	$utility->syscmd("./collate.sh");
	chdir("$src/mail/$package/$package") or croak "netqmail: cd $src/mail/$package/$package failed: $!\n";

	print "netqmail: fixing up conf-qmail\n";
	$utility->file_write("conf-qmail",    $qmaildir) or croak "couldn't write to conf-qmail: $!";

	print "netqmail: fixing up conf-mysql\n";
	$utility->file_write("conf-mysql",    $mysql)  or croak "couldn't write to conf-mysql: $!";

	if ( $os eq "darwin" ) 
	{
		$self->netqmail_darwin_fixups();
	};

	print "netqmail: fixing up conf-cc\n";
	$utility->file_write("conf-cc", "cc -O2")  or croak "couldn't write to conf-cc: $!";

	print "netqmail: fixing up conf-groups\n";
	$utility->file_write("conf-groups", ("qmail", $qmailgroup) ) or croak "couldn't write to conf-groups: $!";

	my $servicectl = "/usr/local/sbin/services";
	if (-x $servicectl)
	{
		print "Stopping Qmail!\n";
		$self->send_stop($conf);
		$utility->syscmd("$servicectl stop");
	};

	my $make = $utility->find_the_bin("gmake") || $utility->find_the_bin("make");
	$utility->syscmd("$make setup");
	$utility->syscmd("$qmaildir/bin/maildirmake /usr/share/skel/Maildir") unless (-e "/usr/share/skel/Maildir");

	$self->config($conf);

	if (-x $servicectl)
	{
		print "Stopping Qmail & supervised services!\n";
		$utility->syscmd("$servicectl start") 
	};
}

sub queue_check($;$)
{
	my ($self, $dir, $debug) = @_;
	my $qdir     = "/var/qmail/queue";
	
	print "queue_check: checking $qdir/$dir..." if $debug;
	
	unless ( -d $dir )
	{
		print "FAILED.\n" if $debug;
		print "HEY! The queue directory for qmail is not
		$dir where I expect. Please edit this script
		and set $qdir to the appropriate directory!\n";
		return 0;
	} else {
		print "ok.\n" if $debug;
		return 1;
	};
};


=head2 queue_process
	
queue_process - Tell qmail to process the queue immediately

=cut

sub queue_process()
{
	my $svc    = $utility->find_the_bin("svc");
	unless ( -x $svc ) {
		print "FAILED: unable to find svc! Is daemontools installed?\n";
		return 0;
	};
	my $qcontrol = "/service/send";

	print "\nSending ALRM signal to qmail-send.\n";
	system "$svc -a $qcontrol";
};

sub rebuild_ssl_temp_keys($)
{
	my ($self, $conf) = @_;

	if ( $conf && ! $utility->is_hashref($conf) ) 
	{
		my ($package, $filename, $line) = caller;
		carp "FATAL: $filename:$line passed rebuild_ssl_temp_keys an invalid argument.\n";
		return 0;
	}
	
	my $debug   = $conf->{'debug'};
	my $openssl = $utility->find_the_bin("openssl");
	croak "no openssl!\n" unless ( -x $openssl);

	my $qmdir = $conf->{'qmail_dir'}          || "/var/qmail";
	my $user  = $conf->{'smtpd_run_as_user'}  || "vpopmail";
	my $group = $conf->{'qmail_group'}        || "qmail";
	my $uid   = getpwnam($user);
	my $gid   = getgrnam($group);
	my $cert  = "$qmdir/control/rsa512.pem";

	if ( -M $cert >= 1 || ! -e $cert )
	{
		print "rebuild_ssl_temp_keys: rebuilding RSA key\n" if $debug;
		$utility->syscmd("$openssl genrsa -out $cert.new 512 2>/dev/null");
		chmod 00660, "$cert.new" or croak "chmod $cert.new failed: $!\n";
		chown($uid, $gid, "$cert.new") or carp "chown $cert.new failed: $!\n";
		move("$cert.new", $cert);
	};

	$cert = "$qmdir/control/dh512.pem";
	if ( -M $cert >= 1 || ! -e $cert )
	{
		print "rebuild_ssl_temp_keys: rebuilding DSA 512 key\n" if $debug;
		$utility->syscmd("$openssl dhparam -2 -out $cert.new 512 2>/dev/null");
		chmod 00660, "$cert.new" or croak "chmod $cert.new failed: $!\n";
		chown($uid, $gid, "$cert.new") or carp "chown $cert.new failed: $!\n";
		move("$cert.new", $cert);
	};

	$cert = "$qmdir/control/dh1024.pem";
	if ( -M $cert >= 1 || ! -e $cert )
	{
		print "rebuild_ssl_temp_keys: rebuilding DSA 1024 key\n" if $debug;
		$utility->syscmd("$openssl dhparam -2 -out $cert.new 1024 2>/dev/null");
		chmod 00660, "$cert.new" or croak "chmod $cert.new failed: $!\n";
		chown($uid, $gid, "$cert.new") or carp "chown $cert.new failed: $!\n";
		move("$cert.new", $cert);
	};
};


=head2 restart

  $qmail->restart()

Use to restart the qmail-send process. It will send qmail-send the TERM signal and then return.

=cut


sub restart($)
{
	my ($self, $conf) = @_;

	my $svc      = $utility->find_the_bin("svc");
	my $svok     = $utility->find_the_bin("svok");
	my $qcontrol = $self->service_dir_get($conf, "send");

	unless ( -x $svc ) {
		print "FAILED: unable to find svc! Is daemontools installed?\n";
		return 0;
	};

	return $toaster->supervise_restart($qcontrol);
};


sub send_start()
{

=head2 send_start

	$qmail->send_start() - Start up the qmail-send process.

After starting up qmail-send, we verify that it's running before returning.

=cut

	my $svc    = $utility->find_the_bin("svc");
	my $svstat = $utility->find_the_bin("svstat");
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


sub send_stop(;$)
{

=head2 send_stop

  $qmail->send_stop()

Use send_stop to quit the qmail-send process. It will send qmail-send the TERM signal and then wait until it's shut down before returning. If qmail-send fails to shut down within 100 seconds, then we force kill it, causing it to abort any outbound SMTP sessions that are active. This is safe, as qmail will attempt to deliver them again, and again until it succeeds.

=cut

	my ($self, $conf) = @_;

	if ( $conf && ! $utility->is_hashref($conf) ) 
	{
		my ($package, $filename, $line) = caller;
		carp "FATAL: $filename:$line passed send_stop an invalid argument.\n";
		return 0;
	}
	
	my $svc      = $utility->find_the_bin("svc");
	my $svstat   = $utility->find_the_bin("svstat");
	my $qcontrol = $self->service_dir_get($conf, "send");

	unless ( $qcontrol ) {
		print "Qmail doesn't appear to have a supervised process yet, which likely means it's not running.\n";
		return 0;
	};

	# send qmail-send a TERM signal
	system "$svc -d $qcontrol";

	# loop up to a thousand seconds waiting for qmail-send to exit
	foreach my $i ( 1..1000 ) 
	{
		my $r = `$svstat $qcontrol`;
		chomp $r;
		if ( $r =~ /^.*:\sdown\s[0-9]*\sseconds/ ) {
			print "Yay, we're down!\n";
			return 0;
		} elsif ( $r =~ /supervise not running/ ) {
			print "Yay, we're down!\n";
			return 0;
		} else {
			# if more than 100 seconds passes, lets kill off the qmail-remote
			# processes that are forcing us to wait.
			
			if ($i > 100) {
				$utility->syscmd("killall qmail-remote");
			};
			print "$r\n";
		};
		sleep 1;
	};
	return 1;
};



=head2 service_dir_get

This is necessary because things such as service directories are now in /var/service by default but older versions of my toaster installed them in /service. This will detect and adjust for that.

  $qmail->service_dir_get($conf, $prot);

$prot is the protocol (smtp, pop3, submit, send).

returned is the directory

=cut

sub service_dir_get($$)
{
	my ($self, $conf, $prot) = @_;

	my ($package, $filename, $line) = caller;

	if ( $conf && ! $utility->is_hashref($conf) ) 
	{
		carp "FATAL: $filename:$line passed service_dir_get an invalid argument.\n";
		return 0;
	}
	
	unless ( $prot ) {
		carp "FATAL: $filename:$line passed service_dir_get an invalid argument.\n";
		return 0;
	};
	
	my $debug      = $conf->{'debug'};
	my $servicedir = $conf->{'qmail_service'} || "/var/service";

	if ( ! -d $servicedir and $servicedir eq "/var/service" )
	{
		if ( -d "/service" )  { $servicedir = "/service" };
	};

	print "service_dir_get: service dir is $servicedir \n" if $debug;
	
	my $dir;
	if    ( $prot eq "smtp"   ) { $dir = $conf->{'qmail_service_smtp'}   }
	elsif ( $prot eq "smtpd"  ) { $dir = $conf->{'qmail_service_smtp'}   }
	elsif ( $prot eq "pop3"   ) { $dir = $conf->{'qmail_service_pop3'}   }
	elsif ( $prot eq "send"   ) { $dir = $conf->{'qmail_service_send'}   }
	elsif ( $prot eq "submit" ) { $dir = $conf->{'qmail_service_submit'} };

	unless ($dir) {
		carp "WARNING: qmail_service_".$prot." is not set correctly in toaster-watcher.conf!\n";
		$dir = "$servicedir/$prot"; 
	};
	print "service_dir_get: $prot is $dir \n" if $debug;

	if ( $dir =~ /^qmail_service\/(.*)$/ )
	{
		$dir = "$servicedir/$1";
		print "service_dir_get: expanded to: $dir \n" if $debug;
	};

	print "service_dir_get: using $dir for $prot \n" if $debug;
	return $dir;
};


=head2 supervise_dir_get

  my $dir = $qmail->supervise_dir_get($conf, "smtp", $debug);

This sub just sets the supervise directory used by the various qmail
services (qmail-smtpd, qmail-send, qmail-pop3d, qmail-submit). It sets
the values according to your preferences in toaster-watcher.conf. If
any settings are missing from the config, it chooses reasonable defaults.

This is used primarily to allow you to set your mail system up in ways
that are a different than mine, like a LWQ install.

=cut

sub supervise_dir_get($$)
{
	my ($self, $conf, $prot) = @_;

	my ($package, $filename, $line) = caller;

	if ( $conf && ! $utility->is_hashref($conf) ) 
	{
		carp "FATAL: $filename:$line passed supervise_dir_get an invalid argument.\n";
		return 0;
	}
	
	unless ( $prot ) {
		carp "FATAL: $filename:$line passed supervise_dir_get an invalid argument.\n";
		return 0;
	};
	
	my $debug        = $conf->{'debug'};
	my $supervisedir = $conf->{'qmail_supervise'} || "/var/qmail/supervise";

	if ( ! -d $supervisedir and $supervisedir eq "/var/supervise" )
	{
		if ( -d "/supervise" )  { $supervisedir = "/supervise" };
	};

	my $dir;
	if    ( $prot eq "smtp"   ) { $dir = $conf->{'qmail_supervise_smtp'};  }
	elsif ( $prot eq "pop3"   ) { $dir = $conf->{'qmail_supervise_pop3'};  }
	elsif ( $prot eq "send"   ) { $dir = $conf->{'qmail_supervise_send'};  }
	elsif ( $prot eq "submit" ) { $dir = $conf->{'qmail_supervise_submit'};}
	else {
		print "supervise_dir_get: FAILURE: please read perldoc Mail::Toaster::Qmail to see how to use this subroutine.\n";
		return 0;
	};

	if ($dir) { 
		$dir = "$supervisedir/$1" if ( $dir =~ /^qmail_supervise\/(.*)$/ );
	} 
	else {
		carp "WARNING: qmail_supervise_smtp is not set correctly in toaster-watcher.conf!\n";
		$dir = "$supervisedir/$prot"; 
	};
	print "supervise_dir_get: using $dir for $prot \n" if $debug;
	return $dir;
};



=head2 smtpd_restart

  $qmail->smtpd_restart($conf, "smtp", $debug)

Use smtpd_restart to restart the qmail-smtpd process. It will send qmail-smtpd the TERM signal causing it to exit. It will restart immediately because it's supervised. 

=cut

sub smtpd_restart($$;$)
{
	my ($self, $conf, $prot, $debug) = @_;
	my ($package, $filename, $line) = caller;

	if ( $conf && ! $utility->is_hashref($conf) ) 
	{
		carp "FATAL: $filename:$line passed smtpd_restart an invalid argument.\n";
		return 0;
	}
	
	unless ( $prot ) {
		carp "FATAL: $filename:$line passed smtpd_restart an invalid argument.\n";
		return 0;
	};
	
	my $dir = $self->service_dir_get($conf, $prot);

	unless ( -d $dir || -l $dir ) { 
		carp "smtpd_restart: no such dir: $dir!\n"; 
		return 0;
	};

	print "restarting qmail smtpd..." if $debug;
	$toaster->supervise_restart($dir);
	print "done.\n" if $debug;
}



=head2 test_each_rbl

	my $available = $qmail->test_each_rbl($selected, $debug);

We get a list of RBL's in an arrayref and we run some tests on them to determine if they are working correctly. 

returns a list of the correctly functioning RBLs.

=cut

sub test_each_rbl($;$)
{
	my ($self, $conf, $rbls, $debug) = @_;
	my @list;

	use Mail::Toaster::DNS;
	my $t_dns = Mail::Toaster::DNS->new();

	foreach my $rbl (@$rbls)
	{
		print "testing $rbl.... " if $debug;
		my $r = $t_dns->rbl_test($conf, $rbl, $debug);
		if ( $r ) { push @list, $rbl };
		print "$r \n" if $debug;
	};
	return \@list;
};


sub UpdateVirusBlocks($;@)
{
	my ($self, $conf, @ips) = @_;

	unless ( $utility->is_hashref($conf) ) 
	{
		my ($package, $filename, $line) = caller;
		carp "FATAL: $filename:$line passed UpdateVirusBlocks an invalid argument.\n";
		return 0;
	}
	
	my $time  = $conf->{'qs_block_virus_senders_time'};
	my $relay = $conf->{'smtpd_relay_database'};
	my $vpdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";

	if ( $relay =~ /^vpopmail_home_dir\/(.*)\.cdb$/ ) { 
		$relay = "$vpdir/$1" 
	} else {
		if ( $relay =~ /^(.*)\.cdb$/ ) { $relay = $1; };
	};
	unless ( -r $relay ) { croak "$relay selected but not readable!\n" };

	my @lines;

	my $debug = 0;
	my $in = 0;
	my $done = 0;
	my $now = time;
	my $expire = time + ($time * 3600);

	print "now: $now   expire: $expire\n" if $debug;

	my @userlines = $utility->file_read($relay);
	USERLINES: foreach my $line (@userlines)
	{
		unless ($in) { push @lines, $line };
		if ($line =~ /^### BEGIN QMAIL SCANNER VIRUS ENTRIES ###/)
		{
			$in = 1;

			for (@ips) {
				push @lines, "$_:allow,RBLSMTPD=\"-VIRUS SOURCE: Block will be automatically removed in $time hours: ($expire)\"\n";
			};
			$done++;
			next USERLINES;
		};

		if ($line =~ /^### END QMAIL SCANNER VIRUS ENTRIES ###/ )
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
		$utility->file_write($relay, @lines);
	} 
	else 
	{ 
		print "FAILURE: Couldn't find QS section in $relay\n You need to add the following lines as documented in the toaster-watcher.conf and FAQ:

### BEGIN QMAIL SCANNER VIRUS ENTRIES ###
### END QMAIL SCANNER VIRUS ENTRIES ###

"; 
	};

	my $tcprules = $utility->find_the_bin("tcprules");
	$utility->syscmd("$tcprules $vpdir/etc/tcp.smtp.cdb $vpdir/etc/tcp.smtp.tmp < $vpdir/etc/tcp.smtp");
	chmod 00644, "$vpdir/etc/tcp.smtp*";
};


sub _memory_explanation($)
{
	my ($self, $conf, $prot, $maxcon) = @_;
	my ($sysmb, $maxsmtpd, $memorymsg, $perconnection, $connectmsg, $connections);

	carp "\nbuild_".$prot."_run: your ".$prot."_max_memory_per_connection and ".$prot."_max_connections settings in toaster-watcher.conf have exceeded your ".$prot."_max_memory setting. I have reduced the maximum concurrent connections to $maxcon to compensate. You should fix your settings.\n\n";

	if ( $os eq "freebsd" ) {
		$sysmb =  int(substr(`/sbin/sysctl hw.physmem`,12)/1024/1024);
		$memorymsg = "Your system has $sysmb MB of physical RAM.  ";
	} else {
		$sysmb = 1024;
		$memorymsg = "This example assumes a system with $sysmb MB of physical RAM.";
	}

	$maxsmtpd = int($sysmb * 0.75);

	if ($conf->{'install_mail_filtering'}) 
	{
		$perconnection=40;
		$connectmsg = "This is a reasonable value for systems which run filtering.";
	} else { 
		$perconnection = 15;
		$connectmsg = "This is a reasonable value for systems which do not run filtering.";
	}

	$connections = int ($maxsmtpd / $perconnection);
	$maxsmtpd = $connections * $perconnection;

	carp <<EOMAXMEM

These settings control the concurrent connection limit set by tcpserver,
and the per-connection RAM limit set by softlimit. 

Here are some suggestions for how to set these options:

$memorymsg

smtpd_max_memory = $maxsmtpd # approximately 75% of RAM

smtpd_max_memory_per_connection = $perconnection
   # $connectmsg

smtpd_max_connections = $connections

If you want to allow more than $connections simultaneous SMTP connections,
you'll either need to lower smtpd_max_memory_per_connection, or raise 
smtpd_max_memory.

smtpd_max_memory_per_connection is a VERY important setting, because
softlimit/qmail will start soft-bouncing mail if the smtpd processes
exceed this value, and the number needs to be sufficient to allow for
any virus scanning, filtering, or other processing you have configured
on your toaster. 

If you raise smtpd_max_memory over $sysmb MB to allow for more than
$connections incoming SMTP connections, be prepared that in some
situations your smtp processes might use more than $sysmb MB of memory. 
In this case, your system will use swap space (virtual memory) to
provide the necessary amount of RAM, and this slows your system down. In
extreme cases, this can result in a denial of service-- your server can
become unusable until the services are stopped.

EOMAXMEM

};


=head2 _test_smtpd_config_values

Runs the following tests:

  make sure qmail_dir exists
  make sure vpopmail home dir exists
  make sure qmail_supervise is not a directory

=cut

sub _test_smtpd_config_values($;$)
{
	my ($self, $conf, $debug) = @_;

	my $file = "/usr/local/etc/toaster.conf";

	croak "FAILURE: qmail_dir does not exist as configured in $file\n" 
		unless ( -d $conf->{'qmail_dir'} );

	if ( $conf->{'install_vpopmail'} ) {
		croak "FAILURE: vpopmail_home_dir does not exist as configured in $file!\n"  
			unless ( -d $conf->{'vpopmail_home_dir'} );
	};

	croak "FAILURE: qmail_supervise is not a directory!\n"
		unless ( -d $conf->{'qmail_supervise'} );

#  This is no longer necessary with vpopmail > 5.4.0 and 0.4.2 SMTP-AUTH patch
#	croak "FAILURE: smtpd_hostname is not set in $file.\n"
#		unless ( $conf->{'smtpd_hostname'} );
};



sub _smtp_sanity_tests
{
	my ($self, $conf) = @_;

	my $qdir = $conf->{'qmail_dir'} || "/var/qmail";

	my @lines;
	push @lines, "if [ ! -f $qdir/control/rcpthosts ]; then";
	push @lines, "\techo \"No $qdir/control/rcpthosts!\"";
	push @lines, "\techo \"Refusing to start SMTP listener because it'll create an open relay\"";
	push @lines, "\texit 1";
	push @lines, "fi\n";

	return @lines;
};

sub _set_checkpasswd_bin
{
	my ($self, $conf, $prot, $debug) = @_;

	my ($package, $filename, $line) = caller;

	unless ( $utility->is_hashref($conf) ) 
	{
		carp "FATAL: $filename:$line passed _set_checkpasswd_bin an invalid argument.\n";
		return 0;
	}
	
	unless ( $prot ) {
		carp "FATAL: $filename:$line passed _set_checkpasswd_bin an invalid argument.\n";
		return 0;
	};

	my $vdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";

	my $prot_dir = $prot."_checkpasswd_bin";
	my $chkpass  = $conf->{$prot_dir};

	print "build_".$prot."_run: using $chkpass for checkpasswd\n" if $debug;

	unless ($chkpass) 
	{
		print "WARNING: pop3_checkpasswd_bin is not set in toaster-watcher.conf!\n";
		$chkpass = "$vdir/bin/vchkpw"; 
		print "build_".$prot."_run: using $chkpass\n" if $debug;
	};

	if ( $chkpass =~ /^vpopmail_home_dir\/(.*)$/ )
	{
		$chkpass = "$vdir/$1";
		print "build_".$prot."_run: expanded to $chkpass\n" if $debug;
	}

	unless (-x $chkpass) {
		carp "build_".$prot."_run: FATAL: chkpass program $chkpass selected but not executable!\n";
		return 0;
	};

	return "$chkpass ";
};


sub supervised_hostname_qmail
{
	my ($self, $conf, $prot, $debug) = @_;
	my ($package, $filename, $line) = caller;

	if ( $conf && ! $utility->is_hashref($conf) ) 
	{
		carp "FATAL: $filename:$line passed supervised_hostname_qmail an invalid argument.\n";
		return 0;
	}
	
	unless ( $prot ) {
		carp "WARNING: $filename:$line passed supervised_hostname_qmail an invalid argument.\n";
		return 0;
	};
	
	my $qsupervise = $conf->{'qmail_supervise'} || "/var/qmail/supervise";

	my $prot_val   = "qmail_supervise_".$prot;
	my $prot_dir   = $conf->{$prot_val} || "$qsupervise/$prot";

	print "build_".$prot."_run: supervise dir is $prot_dir\n" if $debug;

	if ( $prot_dir =~ /^qmail_supervise\/(.*)$/ ) 
	{
	   $prot_dir   = "$qsupervise/$1";
		print "build_".$prot."_run: expanded supervise dir to $prot_dir\n" if $debug;
	};

	my $me = $conf->{'qmail_dir'}."/control/me" || "/var/qmail/control/me";

	my @lines;
	push @lines, "LOCAL=\`head -1 $me\`";
	push @lines, "if [ -z \"\$LOCAL\" ]; then";
	push @lines, "\techo ERROR: $prot_dir/run tried reading your hostname from $me and failed!";
	push @lines, "\texit 1";
	push @lines, "fi\n";
	print "build_".$prot."_run: hostname set to contents of $me\n" if $debug;

	return @lines;
};

=head2 _supervise_dir_exist



=cut


sub _supervise_dir_exist
{
	my ($self, $dir, $name) = @_;

	unless ( -d $dir )
	{
		$name ?  print "$name: " : print "";
		print "FAILURE: supervise dir $dir doesn't exist!\n";
		return 0;
	};

	return 1;
}

sub _formatted
{
	my ($self, $mess, $result) = @_;

	my $dots = ".";
	$result .= "\n";
	my $len = length($mess); 
	if ($len < 65) { until ( $len == 65 ) { $len++; $dots .= "."; }; };
	print "$mess $dots $result";
}

1;
__END__


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>

=head1 BUGS

None known. Report any to author.

=head1 TODO

=head1 SEE ALSO

The following are all man/perldoc pages: 

 Mail::Toaster 
 Mail::Toaster::Conf
 toaster.conf
 toaster-watcher.conf

 http://matt.simerson.net/computing/mail/toaster/


=head1 COPYRIGHT

Copyright (c) 2004-2005, The Network People, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
