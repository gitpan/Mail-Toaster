#!/usr/bin/perl
use strict;

#
# $Id: Toaster.pm,v 4.22 2006/03/18 03:32:53 matt Exp $
#

package Mail::Toaster;

use Carp;
use vars qw($VERSION);

#$VERSION = sprintf "%d.%02d", q$Revision: 4.22 $ =~ /(\d+)/g;
# this has problems being detected with perl 5.6.

$VERSION  = '4.10';

use Mail::Toaster::Utility; my $utility = new Mail::Toaster::Utility;
use Mail::Toaster::Perl;    my $perl    = new Mail::Toaster::Perl;

=head1 NAME

Mail::Toaster

=head1 SYNOPSIS

Everything you need to build a industrial strength mail system.

=head1 DESCRIPTION

A collection of perl scripts and modules that are terribly useful for building and maintaining a mail system. Written for FreeBSD, Mac OS X, and Linux. It's become quite useful on other platforms and will grow to support other MTA's (think postfix) in the future. 

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

=head2 toaster_check

    $toaster->toaster_check($conf);

Runs a series of tests to keep your toaster ship shape:

 check for processes that should be running.
 make sure watcher.log is less than 1MB
 make sure ~alias/.qmail-* exist and are not empty
 verify multilog log directories are working

=cut

sub toaster_check
{
	my ($self, $conf, $debug) = @_;

	# Do other sanity tests here

	# check for running processes
	if ($debug) {
		print "checking running processes...";
		$self->test_processes($conf);
	} else {
		$self->test_processes($conf, 1);
	}

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
	# UPDATE: this is now handled by qmail->config
#	my $qdir = $conf->{'qmail_dir'}; $qdir ||= "/var/qmail";
#	foreach ( qw/ .qmail-postmaster .qmail-root .qmail-mailer-daemon / ) #	{
#		unless ( -s "$qdir/alias/$_" ) #		{
#			print "\n\nWARNING: your administrative email address needs to be in $_!\n\n";
#			sleep 3;
#		};
#	};

	# make sure the supervised processes are configured correctly.

	$self->supervised_dir_test($conf, "smtp", $debug);
	$self->supervised_dir_test($conf, "send", $debug);
	$self->supervised_dir_test($conf, "pop3", $debug);
	$self->supervised_dir_test($conf, "submit", $debug);
};


=head2 learn_mailboxes

This sub trawls through a mail system finding mail messages that have arrived since the last time it ran and passing them through sa-learn to train SpamAssassin what you think is spam versus ham. It make decisions based on settings defined in toaster-watcher.conf.

=cut

sub learn_mailboxes
{
	my ($self, $conf, $debug) = @_;
	
	my $days = $conf->{'maildir_learn_interval'};
	unless ($days) {
		warn "maildir_learn_interval not set in \$conf!";
		return 0;
	};

	my $log = $conf->{'qmail_log_base'};
	unless ($log) {
		print "NOTICE: qmail_log_base is not set in toaster-watcher.conf! Using default /var/log/mail. \n";
		$log = "/var/log/mail";
	};
	print "learn_mailboxes: qmail log base is: $log\n" if $debug;
	$log  = "$log/learn.log";

	# create the log file if it does not exist
	unless ( -e $log ) 
	{ 
		$utility->logfile_append($log, ["toaster-watcher.pl", "created file"]); 
		croak unless (-e $log);
	};

	unless ( -M $log > $days )
	{
		print "learn_mailboxes: skipping, $log is less than $days old\n" if $debug;
		return 0;
	} 
	else 
	{
		$utility->logfile_append($log, ["toaster-watcher.pl", "learn_mailboxes running."] ); 
		print "learn_mailboxes: checks passed, getting ready to clean\n" if $debug;
	};

	my $tmp      = $conf->{'toaster_tmp_dir'}    ||= "/tmp";
	my $spamlist = "$tmp/toaster-spam-learn-me"; unlink $spamlist if ( -e $spamlist);
	my $hamlist  = "$tmp/toaster-ham-learn-me";  unlink $hamlist  if ( -e $hamlist );

	my @paths = $self->get_maildir_paths($conf, $debug);

	foreach my $path (@paths)
	{
		if ( $path && -d $path ) 
		{
			print "learn_mailboxes: processing in $path\n" if $debug;

			$self->maildir_learn_ham  ($conf, $path, $debug) if ($conf->{'maildir_learn_Read'  });
			$self->maildir_learn_spam ($conf, $path, $debug) if ($conf->{'maildir_learn_Spam'  });
		}
		else
		{
			print "learn_mailboxes: $path does not exist, skipping!\n";
		};
	}

	my $nice    = $utility->find_the_bin("nice");
	my $salearn = $utility->find_the_bin("sa-learn");

	$utility->syscmd("$nice $salearn --ham  -f $hamlist");   unlink $hamlist;
	$utility->syscmd("$nice $salearn --spam -f $spamlist");  unlink $spamlist;
};

=head2 clean_mailboxes

This sub trawls through a mail system cleaning out old mail messages that exceed some pre-configured threshhold as defined in toaster-watcher.conf.

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

	# create the log file if it does not exist
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

	my @paths = $self->get_maildir_paths($conf, $debug);

	foreach my $path (@paths)
	{
		if ( $path && -d $path ) 
		{
			print "clean_mailboxes: processing in $path\n" if $debug;

			$self->maildir_clean_ham  ($conf, $path, $debug) if ($conf->{'maildir_clean_Read'  });
			$self->maildir_clean_new  ($conf, $path, $debug) if ($conf->{'maidir_clean_Unread' });
			$self->maildir_clean_sent ($conf, $path, $debug) if ($conf->{'maidir_clean_Sent'   });
			$self->maildir_clean_trash($conf, $path, $debug) if ($conf->{'maidir_clean_Trash'  });
			$self->maildir_clean_spam ($conf, $path, $debug) if ($conf->{'maildir_clean_Spam'  });
		}
		else
		{
			print "clean_mailboxes: $path does not exist, skipping!\n";
		};
	}

	print "done.\n" if $debug;
}

sub maildir_clean_spam
{
	my ($self, $conf, $path, $debug) = @_;

	my $find = $utility->find_the_bin("find");

	my $days = $conf->{'maildir_clean_Spam'};
	
	print "clean_spam: cleaning spam messages older than $days\n" if $debug;

	if ( -d "$path/Maildir/.Spam" ) 
	{
		$utility->syscmd("$find $path/Maildir/.Spam/cur -type f -mtime +$days -exec rm {} \\;");
		$utility->syscmd("$find $path/Maildir/.Spam/new -type f -mtime +$days -exec rm {} \\;");
	} 
	else {
		print "clean_spam: skipped cleaning because $path/Maildir/.Spam does not exist.\n" if $debug;
	};
}

sub get_maildir_paths
{
	my ($self, $conf, $debug) = @_;

	my @paths;
	my $vpdir    = $conf->{'vpopmail_home_dir'};

	# this method requires a MySQL queries for each email address
#	foreach ( `$vpdir/bin/vpopbull -n -V` ) {
#		my $path = `$vpdir/bin/vuserinfo -d $_`;
#		push @paths, $path;
#	};
#	chomp @paths;
#	return @paths;

	# this method requires a SQL query for each domain
	use Mail::Toaster::Qmail;
	my $qmail = Mail::Toaster::Qmail->new();

	my $qmaildir = $conf->{'qmail_dir'} ||= "/var/qmail";
	my @domains  = $qmail->get_domains_from_assign("$qmaildir/users/assign",$debug);

	my $count = @domains;
	print "get_maildir_paths: found $count domains.\n" if $debug;

	foreach (@domains)
	{
		my $domain = $_->{'dom'};

		print "get_maildir_paths: processing $domain mailboxes.\n" if $debug;

		my @list = `$vpdir/bin/vuserinfo -d -D $domain`;
		chomp @list;
		push @paths, @list;
	};

	chomp @paths;

	$count = @paths; 
	print "found $count mailboxes.\n";

	return @paths;
}

sub maildir_learn_spam
{
	my ($self, $conf, $path, $debug) = @_;

	unless ( -d "$path/Maildir/.Spam" ) {
		print "learn_spam: skipped spam learning because $path/Maildir/.Spam does not exist.\n" if $debug;
		return 0;
	};

	my $find = $utility->find_the_bin("find");
	my $tmp  = $conf->{'toaster_tmp_dir'};
	my $list = "$tmp/toaster-spam-learn-me";

#	my $salearn = $utility->find_the_bin("sa-learn");
#	unless ( -x $salearn) {
#		carp "No sa-learn found!\n";
#		return 0;
#	};

	print "maildir_learn_spam: finding new messages to learn from.\n" if $debug;

	# how often do we process spam?  It's not efficient (or useful) to feed spam 
	# through sa-learn if we've already learned from them.

	my $interval = $conf->{'maildir_learn_interval'} || 7;   # default 7 days
	$interval = $interval + 2;

	my @files = `$find $path/Maildir/.Spam/cur -type f -mtime +1 -mtime -$interval;`;
	chomp @files;
	$utility->file_append($list, \@files);

	@files = `$find $path/Maildir/.Spam/new -type f -mtime +1 -mtime -$interval;`;
	chomp @files;
	$utility->file_append($list, \@files);

#	$utility->syscmd("$salearn --spam $path/Maildir/.Spam/cur");
#	$utility->syscmd("$salearn --spam $path/Maildir/.Spam/new");
};

sub maildir_clean_trash
{
	my ($self, $conf, $path, $debug) = @_;

	unless ( -d "$path/Maildir/.Trash" ) {
		print "clean_trash: skipped cleaning because $path/Maildir/.Trash does not exist.\n" if $debug;
		return 0;
	};

	my $find = $utility->find_the_bin("find");
	my $days = $conf->{'maildir_clean_Trash'};

	print "clean_trash: cleaning deleted messages older than $days days\n" if $debug;

	$utility->syscmd("$find $path/Maildir/.Trash/new -type f -mtime +$days -exec rm {} \\;");
	$utility->syscmd("$find $path/Maildir/.Trash/cur -type f -mtime +$days -exec rm {} \\;");
}

sub maidir_clean_sent
{
	my ($self, $conf, $path, $debug) = @_;

	unless ( -d "$path/Maildir/.Sent" ) {
		print "clean_sent: skipped cleaning because $path/Maildir/.Sent does not exist.\n" if $debug;
		return 0;
	};

	my $find = $utility->find_the_bin("find");
	my $days = $conf->{'maildir_clean_Sent'};

	print "clean_sent: cleaning sent messages older than $days days\n" if $debug;

	$utility->syscmd("$find $path/Maildir/.Sent/new -type f -mtime +$days -exec rm {} \\;");
	$utility->syscmd("$find $path/Maildir/.Sent/cur -type f -mtime +$days -exec rm {} \\;");
};

sub maildir_clean_new
{
	my ($self, $conf, $path, $debug) = @_;

	unless ( -d "$path/Maildir/new" ) {
		print "clean_new: FAILED because $path/Maildir/new does not exist.\n" if $debug;
	};

	my $find = $utility->find_the_bin("find");
	my $days = $conf->{'maildir_clean_Unread'};

	print "clean_new: cleaning unread messages older than $days days\n" if $debug;
	$utility->syscmd("$find $path/Maildir/new  -type f -mtime +$days -exec rm {} \\;");
};

sub maildir_clean_ham
{
	my ($self, $conf, $path, $debug) = @_;

	unless ( -d "$path/Maildir/cur" ) {
		print "clean_ham: FAILED because $path/Maildir/cur does not exist.\n" if $debug;
	};

	my $find = $utility->find_the_bin("find");
	my $days = $conf->{'maildir_clean_Read'};

	print "clean_ham: cleaning read messages older than $days days\n" if $debug;
	$utility->syscmd("$find $path/Maildir/cur  -type f -mtime +$days -exec rm {} \\;");
}
	
sub maildir_learn_ham
{
	my ($self, $conf, $path, $debug) = @_;

	unless ( -d "$path/Maildir/cur") {
		print "learn_ham: ERROR, $path/Maildir/cur does not exist!\n" if $debug;
		return 0;
	};

	my $tmp  = $conf->{'toaster_tmp_dir'};
	my $list = "$tmp/toaster-ham-learn-me";

	my $find = $utility->find_the_bin("find");

	print "learn_ham: training SpamAsassin from ham (read) messages\n" if $debug;

	my $interval = $conf->{'maildir_learn_interval'} || 7;
	$interval = $interval + 2;

	my $days = $conf->{'maildir_learn_Read_days'};
	if ($days) 
	{
		print "learn_ham: learning read messages older than $days days.\n" if $debug;
		my @files = `$find $path/Maildir/cur -type f -mtime +$days -mtime -$interval;`;
		chomp @files;
		$utility->file_append($list, \@files);
	} 
	else 
	{
		if ( -d "$path/Maildir/.read" ) {
			#$utility->syscmd("$salearn --ham $path/Maildir/cur");
			my @files = `$find $path/Maildir/.read/cur -type f`;
			chomp @files;
			$utility->file_append($list, \@files);
		};

		if ( -d "$path/Maildir/.Read" ) {
			#$utility->syscmd("$salearn --ham $path/Maildir/.Read/cur");
			my @files = `$find $path/Maildir/.Read/cur -type f`;
			chomp @files;
			$utility->file_append($list, \@files);
		};
	};
}


=head2 service_dir_create

Create the supervised services directory (if it doesn't exist).

	$setup->service_dir_create($conf);

Also sets the permissions to 775.

=cut

sub service_dir_create($;$)
{
	my ($self, $conf, $debug) = @_;

	my $service = $conf->{'qmail_service'} || "/var/service";

	if ( -d $service ) {
		print "service_dir_create: $service already exists.\n";
	} 
	else {
		mkdir($service, 0775) or croak "service_dir_create: failed to create $service: $!\n";
	};

	unless ( -l "/service" ) 
	{
		if ( -d "/service" ) { $utility->syscmd("rm -rf /service"); };
		symlink("/var/service", "/service");
	};
};


=head2 service_dir_test

Makes sure the service directory is set up properly

	$setup->service_dir_test($conf);

Also sets the permissions to 775.

=cut

sub service_dir_test($;$)
{
	my ($self, $conf, $debug) = @_;

	my $service = $conf->{'qmail_service'} || "/var/service";

	unless ( -d $service ) {
		print "service_dir_test: $service is missing!\n";
		return 0;
	} 

	print "service_dir_test: $service already exists.\n" if $debug;

	unless ( -l "/service" && -e "/service" ) 
	{
		print "/service symlink is missing!\n";
		return 0;
	};

	print "service_dir_test: /service symlink exists.\n" if $debug;

	return 1;
};


=head2 supervise_dirs_create

Creates the qmail supervise directories.

	$setup->supervise_dirs_create($conf, $debug);

The default directories created are:

  $supervise/smtp
  $supervise/submit
  $supervise/send
  $supervise/pop3

unless otherwise specified in $conf

=cut

sub supervise_dirs_create($;$)
{
	my ($self, $conf, $debug) = @_;

	my $supervise = $conf->{'qmail_supervise'} || "/var/qmail/supervise";


	if ( -d $supervise ) 
	{
		$self->_formatted("supervise_dirs_create: $supervise", "ok (exists)");
	} 
	else 
	{
		mkdir($supervise, 0775) or croak "failed to create $supervise: $!\n";
		$self->_formatted("supervise_dirs_create: $supervise", "ok") if $debug;
	};

	chdir($supervise);

	$perl->module_load( {module=>"Mail::Toaster::Qmail"} );
	my $qmail = Mail::Toaster::Qmail->new;

	foreach my $prot ( qw/ smtp send pop3 submit / )
	{
		my $dir = $prot;
		$dir = $qmail->supervise_dir_get($conf, $prot) if $conf;

		if ( -d $dir )
		{
			$self->_formatted("supervise_dirs_create: $dir", "ok (exists)");
			next;
		}

		mkdir($dir, 0775) or croak "failed to create $dir: $!\n";
		$self->_formatted("supervise_dirs_create: creating $dir", "ok");
		mkdir("$dir/log", 0775) or croak "failed to create $dir/log: $!\n";
		$self->_formatted("supervise_dirs_create: creating $dir/log", "ok");
		$utility->syscmd("chmod +t $dir");

		symlink($dir, $prot) unless ( -e $prot );
	};
};


sub supervised_dir_test($$;$)
{
	my ($self, $conf, $prot, $debug) = @_;

	$perl->module_load( {module=>"Mail::Toaster::Qmail"} );
	my $qmail = Mail::Toaster::Qmail->new();

	# set the directory based on config settings
	my $dir = $qmail->supervise_dir_get($conf, $prot);

	my $r;
	# make sure the directory exists
	if ($debug) {
		if (-d $dir) { $r = "ok" } else { $r = "FAILED" };
		$self->_formatted("svc_dir_test: exists $dir", $r);
	};
	return 0 unless (-d $dir || -l $dir);

	# make sure the supervise/run file exists
	if ($debug) {
		if (-f "$dir/run") { $r = "ok" } else { $r = "FAILED" };
		$self->_formatted("svc_dir_test: exists $dir/run", $r);
	};
	return 0 unless -f "$dir/run";

	# check the run file permissions
	if ($debug) {
		if (-x "$dir/run") { $r = "ok" } else { $r = "FAILED" };
		$self->_formatted("svc_dir_test: perms $dir/run", $r);
	};
	return 0 unless -x "$dir/run";

	# make sure the supervise/down file does not exist
	if ($debug) {
		unless (-f "$dir/down") { $r = "ok" } else { $r = "FAILED" };
		$self->_formatted("svc_dir_test: !exist $dir/down", $r);
	};
	return 0 if -f "$dir/down";

	my $log = $conf->{$prot.'_log_method'} || $conf->{$prot.'d_log_method'} || "multilog";

	return 1 if ( $log eq "syslog" || $log eq "disabled" );

	# make sure the log directory exists
	if ($debug) {
		if (-d "$dir/log") { $r = "ok" } else { $r = "FAILED" };
		$self->_formatted("svc_dir_test: exists $dir/log", $r);
	};
	return 0 unless (-d "$dir/log");

	# make sure the supervise/log/run file exists
	if ($debug) {
		if (-f "$dir/log/run") { $r = "ok" } else { $r = "FAILED" };
		$self->_formatted("svc_dir_test: exists $dir/log/run", $r);
	};
	return 0 unless -f "$dir/log/run";

	# check the log/run file permissions
	if ($debug) {
		if (-x "$dir/log/run") { $r = "ok" } else { $r = "FAILED" };
		$self->_formatted("svc_dir_test: perms  $dir/log/run", $r);
	};
	return 0 unless -x "$dir/log/run";

	# make sure the supervise/down file does not exist
	if ($debug) {
		unless (-f "$dir/log/down") { $r = "ok" } else { $r = "FAILED" };
		$self->_formatted("svc_dir_test: !exist $dir/log/down", $r);
	};
	return 0 if -f "$dir/log/down";

	return 1;
}


sub test_processes
{
	my ($self, $conf, $quiet) = @_;

	print "checking for running processes\n" unless $quiet;

	my @processes = qw( svscan qmail-send );

	push @processes, "httpd"              if  $conf->{'install_apache'};
	push @processes, "mysqld"             if  $conf->{'install_mysql'};
	push @processes, "snmpd"              if  $conf->{'install_snmp'};
	push @processes, "clamd", "freshclam" if  $conf->{'install_clamav'};
	push @processes, "sqwebmaild"         if  $conf->{'install_sqwebmail'};
	push @processes, "imapd-ssl", "imapd", "pop3d-ssl" if $conf->{'install_courier-imap'};
	push @processes, "authdaemond"        if ($conf->{'install_courier_imap'} eq "port" || $conf->{'install_courier_imap'} gt 4);

	push @processes, "sendlog" if ( $conf->{'send_log_method'} eq "multilog" && $conf->{'send_log_postprocessor'} eq "maillogs");
	push @processes, "smtplog" if ( $conf->{'smtpd_log_method'} eq "multilog" && $conf->{'smtpd_log_postprocessor'} eq "maillogs");

	foreach ( @processes )
	{
		if ( $quiet ) {
			# if quiet is set, only report failures.
			print "\t$_ is not running, FAILED!\n" unless $utility->is_process_running($_);
		} else {
			$utility->is_process_running($_) ? $self->_formatted("\t$_", "ok") : $self->_formatted("\t$_", "FAILED");
		}
	}
}


=head2 email_send

Email test routines for testing a mail toaster installation.

   $toaster->email_send($conf, "clean" );
   $toaster->email_send($conf, "spam"  );
   $toaster->email_send($conf, "attach");
   $toaster->email_send($conf, "virus" );
   $toaster->email_send($conf, "clam"  );

This sends a test email of a specified type to the email address configured in toaster-watcher.conf.

=cut

sub email_send($$)
{
	my ($self, $conf, $type) = @_;

	unless ( $utility->is_hashref($conf) ) {
		print "email_send: FATAL, \$conf wasn't passed!\n";
		return 0;
	};

	my $email = $conf->{'toaster_admin_email'} || "root";

	my $qdir = $conf->{'qmail_dir'} || "/var/qmail";
	return 0 unless -x "$qdir/bin/qmail-inject";

	unless ( open (INJECT, "| $qdir/bin/qmail-inject -a -f \"\" $email") ) {
		warn "FATAL: couldn't send using qmail-inject!\n";
		return 0;
	};

	if    ( $type eq "clean" )  { $self->email_send_clean ($email) }
	elsif ( $type eq "spam"  )  { $self->email_send_spam  ($email) }
	elsif ( $type eq "virus" )  { $self->email_send_eicar ($email) }
	elsif ( $type eq "attach")  { $self->email_send_attach($email) }
	elsif ( $type eq "clam"  )  { $self->email_send_clam  ($email) }
	else { print "man Mail::Toaster to figure out how to use this!\n" };

	close INJECT;

	return 1;
};


sub email_send_attach
{
	my ($self, $email) = @_;

	print "\n\t\tSending .com test attachment - should fail.\n";
	print INJECT <<EOATTACH
From: Mail Toaster Testing <$email>
To: Email Administrator <$email>
Subject: Email test (blocked attachment message)
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

EOATTACH
;

}

sub email_send_clam
{
	my ($self, $email) = @_;

	print "\n\t\tSending ClamAV test virus - should fail.\n";
	print INJECT <<EOCLAM
From: Mail Toaster testing <$email>
To: Email Administrator <$email>
Subject: Email test (clean message)

This is a viral message containing the clam.zip test virus pattern. It should be blocked by any scanning software using ClamAV. 


--Apple-Mail-7-468588064
Content-Transfer-Encoding: base64
Content-Type: application/zip;
        x-unix-mode=0644;
        name="clam.zip"
Content-Disposition: attachment;
        filename=clam.zip

UEsDBBQAAAAIALwMJjH9PAfvAAEAACACAAAIABUAY2xhbS5leGVVVAkAA1SjO0El6E1BVXgEAOgD
6APzjQpgYGJgYGBh4Gf4/5+BYQeQrQjEDgxSDAQBIwPD7kIBBwbjAwEB3Z+DgwM2aDoYsKStqfy5
y5ChgndtwP+0Aj75fYYML5/+38J5VnGLz1nFJB4uRqaCMnEmOT8eFv1bZwRQjTwA5Degid0C8r+g
icGAt2uQn6uPsZGei48PA4NrRWZJQFF+cmpxMUNosGsQVNzZx9EXKJSYnuqUX+HI8Axqlj0QBLgy
MPgwMjIkOic6wcx8wNDXyM3IJAkMFAYGNoiYA0iPAChcwDwwGxRwjFA9zAxcEIYCODDBgAlMCkDE
QDTUXmSvtID8izeQaQOiQWHiGBbLAPUXsl+QwAEAUEsBAhcDFAAAAAgAvAwmMf08B+8AAQAAIAIA
AAgADQAAAAAAAAAAAKSBAAAAAGNsYW0uZXhlVVQFAANUoztBVXgAAFBLBQYAAAAAAQABAEMAAAA7
AQAAAAA=

--Apple-Mail-7-468588064


EOCLAM
;

}




sub email_send_clean
{
	my ($self, $email) = @_;

	print "\n\t\tsending a clean message - should arrive unaltered\n";
	print INJECT <<EOCLEAN
From: Mail Toaster testing <$email>
To: Email Administrator <$email>
Subject: Email test (clean message)

This is a clean test message. It should arrive unaltered and should also pass any virus or spam checks.

EOCLEAN
;

};

sub email_send_eicar
{
	my ($self, $email) = @_;

# http://eicar.org/anti_virus_test_file.htm
# X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*

	print "\n\t\tSending the EICAR test virus - should fail.\n";
	print INJECT <<EOVIRUS 
From: Mail Toaster testing <$email'>
To: Email Administrator <$email>
Subject: Email test (eicar virus test message)
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="gKMricLos+KVdGMg"
Content-Disposition: inline

--gKMricLos+KVdGMg
Content-Type: text/plain; charset=us-ascii
Content-Disposition: inline

This is an example email containing a virus. It should trigger any good virus
scanner.

If it is caught by AV software, it will not be delivered to its intended 
recipient (the email admin). The Qmail-Scanner administrator should receive 
an Email alerting him/her to the presence of the test virus. All other 
software should block the message.

--gKMricLos+KVdGMg
Content-Type: text/plain; charset=us-ascii
Content-Disposition: attachment; filename="sneaky.txt"

X5O!P%\@AP[4\\PZX54(P^)7CC)7}\$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!\$H+H*

--gKMricLos+KVdGMg--

EOVIRUS
;

};


sub email_send_spam
{
	print "\n\t\tSending a sample spam message - should fail\n";
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
Received: from R00UqS18S (max1-45.losangeles.corecomm.net [216.214.106.173]) by netsvr.Internet with SMTP (Microsoft Exchange Internet Mail Service Version 5.5.2653.13)
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
};


sub supervised_do_not_edit_notice($$)
{
	my ($self, $conf, $vdir) = @_;

	if ( $conf && ! $utility->is_hashref($conf) ) 
	{
		my ($package, $filename, $line) = caller;
		carp "WARNING: $filename:$line passed _do_not_edit_notice an invalid argument.\n";
	}
	
	my $qdir   = $conf->{'qmail_dir'} || "/var/qmail";
	my $prefix = $conf->{'toaster_prefix'} || "/usr/local";

	#use Data::Dumper; print Dumper($conf);

	my   @lines = "#!/bin/sh\n";
	push @lines,  "#    NOTICE: This file is generated automatically by toaster-watcher.pl.";
	push @lines,  "#";
	push @lines,  "#    Please DO NOT hand edit this file. Instead, edit toaster-watcher.conf";
	push @lines,  "#      and then run toaster-watcher.pl to make your settings active. ";
	push @lines,  "#      Run: perldoc toaster-watcher.conf  for more detailed info.\n";
	if ( $vdir ) {
		push @lines,  "PATH=$qdir/bin:$vdir/bin:$prefix/bin:/usr/bin:/bin";
	} else {
		push @lines,  "PATH=$qdir/bin:$prefix/bin:/usr/bin:/bin";
	}
	push @lines,  "export PATH\n";
	return @lines;
}


sub supervised_hostname($$;$)
{
	my ($self, $conf, $prot, $debug) = @_;
	my ($package, $filename, $line) = caller;

	unless ($utility->is_hashref($conf) ) {
		carp "FATAL: $filename:$line called supervised_hostname with an invalid argument!\n";
		return 0;
	};
	
	unless ( $prot ) {
		carp "FATAL: $filename:$line passed supervised_hostname an invalid argument.\n";
		return 0;
	};

	my $prot_val   = $prot."_hostname";

	if    ( $conf->{$prot_val} eq "qmail" ) 
	{
		print "build_".$prot."_run: using qmail hostname.\n" if $debug;
		return "\"\$LOCAL\" ";
	} 
	elsif ( $conf->{$prot_val} eq "system" ) 
	{
		use Sys::Hostname;
		print "build_".$prot."_run: using system hostname (". hostname() .")\n" if $debug;
		return hostname() . " ";
	}
	else 
	{ 
		print "build_".$prot."_run: using conf defined hostname (".$conf->{$prot_val}.").\n" if $debug;
		return "$conf->{$prot_val} ";
	}
}


sub supervised_multilog($$;$)
{
	my ($self, $conf, $prot, $debug) = @_;

	my ($package, $filename, $line) = caller;
	unless ( $utility->is_hashref($conf) ) 
	{
		carp "FATAL: $filename:$line passed supervised_multilog an invalid argument.\n";
		return 0;
	}
	
	unless ( $prot ) {
		carp "FATAL: $filename:$line passed supervised_multilog an invalid argument.\n";
		return 0;
	};

	my $setuidgid = $utility->find_the_bin("setuidgid") || "setuidgid";
	my $multilog  = $utility->find_the_bin("multilog")  || "multilog";
	my $loguser   = $conf->{'qmail_log_user'}  || "qmaill";

	my $log = $conf->{'qmail_log_base'} || $conf->{'log_base'};
	unless ($log) { 
		print "NOTICE: qmail_log_base is not set in toaster-watcher.conf!\n";
		$log = "/var/log/mail" 
	};

	my $runline = "exec $setuidgid $loguser $multilog t ";
	my $logprot = $prot; $logprot = "smtpd" if ( $prot eq "smtp");

	if ( $conf->{$logprot.'_log_postprocessor'} eq "maillogs" ) {
		print "install_qmail_control_log_files: using maillogs processing for $prot\n" if $debug;
		$runline .= "!./".$prot."log ";
	};

	my $maxbytes = $conf->{$logprot.'_log_maxsize_bytes'} || "100000";
	
	my $method = $conf->{$logprot.'_log_method'};
	if    ( $method eq "stats" )    { $runline .= "-* +stats s$maxbytes "; }
	elsif ( $method eq "disabled" ) { $runline .= "-* ";    } 
	else                            { $runline .= "s$maxbytes "; };
	print "install_qmail_control_log_files: log method for $prot is $method\n" if $debug;

	if ($prot eq "send" && $conf->{'send_log_isoqlog'} ) 
	{
		 $runline .= "n288 ";   # keep a days worth of logs around
	};

	$runline .= "$log/$prot";

	return $runline;
};


sub supervised_log_method($$;$)
{

	my ($self, $conf, $prot, $debug) = @_;
	my ($package, $filename, $line) = caller;

	unless ( $utility->is_hashref($conf) ) 
	{
		carp "FATAL: $filename:$line passed supervised_log_method an invalid argument.\n";
		return 0;
	}
	
	unless ( $prot ) {
		my ($package, $filename, $line) = caller;
		carp "FATAL: $filename:$line passed supervised_log_method an invalid argument.\n";
		return 0;
	};
	
	my $prot_val = $prot."_hostname";

	if ( $conf->{$prot_val} eq "syslog" )
	{
		print "build_".$prot."_run: using syslog logging.\n" if $debug;
		return "splogger qmail ";
	}
	else
	{
		print "build_".$prot."_run: using multilog logging.\n" if $debug;
		return "2>&1 ";
	};
};

sub supervise_restart($)
{
	my ($self, $dir) = @_;

	my $svc  = $utility->find_the_bin("svc");
	my $svok = $utility->find_the_bin("svok");

	unless ( -x $svc ) {
		$self->_formatted("supervise_restart: unable to find svc! Is daemontools installed?", "FAILED");
		return 0;
	};

	unless ( -d $dir) {
		$self->_formatted("supervise_restart: unable to use $dir! as a supervised dir", "FAILED");
		return 0;
	};

	unless ( $utility->syscmd("$svok $dir", undef, 1) )
	{
		# send qmail-send a TERM signal
		$utility->syscmd("$svc -t $dir", undef, 1);
		return 1;
	}
	else {
		$self->_formatted("supervise_restart: sorry, $dir isn't supervised!", "FAILED");
		return 0;
	}
};


sub supervised_tcpserver($$;$)
{
	my ($self, $conf, $prot, $debug) = @_;
	my ($package, $filename, $line) = caller;

	unless ( $utility->is_hashref($conf) ) 
	{
		carp "FATAL: $filename:$line passed supervised_tcpserver an invalid argument.\n";
		return 0;
	}
	
	unless ( $prot ) {
		carp "FATAL: $filename:$line passed supervised_tcpserver an invalid argument.\n";
		return 0;
	};
	
	my $mem = $conf->{$prot.'_max_memory_per_connection'};
	$mem ? $mem = "3000000" : $mem = $mem * 1024000; 
	print "build_".$prot."_run: memory limited to $mem bytes\n" if $debug;

	my $softlimit = $utility->find_the_bin("softlimit") || "softlimit";
	my $tcpserver = $utility->find_the_bin("tcpserver") || "tcpserver";

	my $exec = "exec $softlimit ";
	$exec .= "-m $mem " if $mem;
	$exec .= "$tcpserver ";

	if ($conf->{$prot.'_use_mysql_relay_table'} && $conf->{$prot.'_use_mysql_relay_table'} == 1) {
		unless ( `strings $tcpserver | grep sql` ) {   # make sure tcpserver mysql patch is installed
			print "It looks like the MySQL patch for ucspi-tcp (tcpserver) is not installed! Please re-install ucspi-tcp with the patch or disable the ".$prot."_use_mysql_relay_table setting.\n";
		} else {
			$exec .= "-S ";
			print "build_".$prot."_run: using MySQL based relay table\n" if $debug;
		};
	};

	$exec .= "-H "   if $conf->{$prot.'_lookup_tcpremotehost'}  == 0;
	$exec .= "-R "   if $conf->{$prot.'_lookup_tcpremoteinfo'}  == 0;
	$exec .= "-p "   if $conf->{$prot.'_dns_paranoia'}          == 1;

	my $maxcon = $conf->{$prot.'_max_connections'} || 40;
	my $maxmem = $conf->{$prot.'_max_memory'};
	if ($maxmem) {
		if ( ($mem / 1024000) * $maxcon > $maxmem) {
			use POSIX;
			$maxcon = floor( $maxmem / ($mem / 1024000) );
			use Mail::Toaster::Qmail;
			my $qmail = Mail::Toaster::Qmail->new();
			$qmail->_memory_explanation($conf, $prot, $maxcon);
		};
		$exec .= "-c$maxcon ";
	} else {
		$exec .= "-c$maxcon " if $maxcon != 40;
	};

	$exec .= "-t$conf->{$prot.'_dns_lookup_timeout'} "  if $conf->{$prot.'_dns_lookup_timeout'} != 26;

	my $cdb  = $conf->{$prot.'_relay_database'};
	if ($cdb) {
		my $vdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";
		print "build_".$prot."_run: relay db set to $cdb\n" if $debug;
		if ( $cdb =~ /^vpopmail_home_dir\/(.*)$/ ) { 
			$cdb = "$vdir/$1";
			print "build_".$prot."_run: expanded to $cdb\n" if $debug;
		};
		if (-r $cdb) { $exec .= "-x $cdb " } 
		else {
 			carp "build_".$prot."_run: FATAL: $cdb selected but not readable!\n";
			return 0;
		};
	};

	if ( $prot eq "smtpd" || $prot eq "submit") {
		my $uid = getpwnam( $conf->{$prot.'_run_as_user'}  );
		my $gid = getgrnam( $conf->{$prot.'_run_as_group'} );
		unless ( $uid && $gid ) 
		{
			print "FAILURE: uid and gid not set!\n You need to edit toaster_watcher.conf 
and make sure ".$prot."_run_as_user and ".$prot."_run_as_group are set to valid usernames on your system.\n"; 
			return 0;
		};
		$exec .= "-u $uid -g $gid ";
	};

	my $address = $conf->{$prot.'_listen_on_address'} || 0;  # default to 0 (all) if not selected
	if ($address eq "all") { $exec .= "0 " } else { $exec .= "$address " };
	print "build_".$prot."_run: listening on ip $address.\n" if $debug;

	my $port = $conf->{$prot.'_listen_on_port'};
	unless ( $port ) {
		if    ($prot eq "smtpd")      { $port = "smtp" }
		elsif ($prot eq "submission") { $port = "submission" }
		elsif ($prot eq "pop3")       { $port = "pop3" }
		else {
			croak "uh-oh, can't figure out what port $port should listen on!\n";
		}
	};
	$exec .= "$port ";
	print "build_".$prot."_run: listening on port $port.\n" if $debug;

	return $exec;
};


sub _formatted
{
    my ($self, $mess, $result) = @_;

    my $dots;
    my $len = length($mess);
    if ($len < 65) { until ( $len == 65 ) { $dots .= "."; $len++ }; };
    print "$mess $dots $result\n";
}


1;
__END__


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>

=head1 BUGS

None known. Report any to matt@tnpi.biz.

=head1 TODO

 Add support for Darwin (MacOS X) - done
 Add support for Linux - done
 Update openssl & courier ssl .cnf files
 Install an optional stub DNS resolver (dnscache)

=head1 SEE ALSO

The following are man (perldoc) pages: 

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
