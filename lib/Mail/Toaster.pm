#!/usr/bin/perl
use strict;

#
# $Id: Toaster.pm,v 1.15 2004/02/13 03:14:36 matt Exp $
#

package Mail::Toaster;

use Carp;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION  = '3.33';

@ISA = qw(Exporter);
@EXPORT = qw( CleanMailboxMessages );
@EXPORT_OK = qw();


sub CleanMailboxMessages
{
	my ($conf, $debug) = @_;

	my $log  = "/var/log/mail/clean.log";
	my $days = $conf->{'maildir_clean_interval'};

	unless ( -e $log ) 
	{ 
		use MATT::Utility;
		MATT::Utility::WriteFile($log, "created file"); 
		croak unless (-e $log);
	};

	unless ( -M $log > $days )
	{
		print "CleanMailboxMessages: skipping, $log is less than $days old\n" if $debug;
		return 0;
	} 
	else { MATT::Utility::LogFileAppend($log, "CleanMailboxMessages running."); };

	use Mail::Toaster::Qmail;
	my @domains = Mail::Toaster::Qmail::GetDomainsFromAssign();
	my $count = @domains;
	print "CleanMailboxMessages: found $count domains.\n" if $debug;

	foreach my $domain (@domains)
	{
		print "CleanMailboxMessages: processing $domain mailboxes..." if $debug;

		my @paths = `~vpopmail/bin/vuserinfo -d -D $domain`;

		foreach my $path (@paths)
		{
			if ( $path && -d $path ) 
			{
				if ($conf->{'maildir_clean_Read_learn'} ) 
				{
					my $salearn = MATT::Utility::FindTheBin("sa-learn");
					croak "No sa-learn found!\n" unless ( -x $salearn);

					$days = $conf->{'maildir_clean_Read_learn_days'};
					if ($days) 
					{
						SysCmd("find $path/Maildir/cur  -type f -mtime +$days -exec $salearn --ham -f {} \\;");
					} else {
						SysCmd("$salearn --ham -f $path/Maildir/cur");
					};
				};

				$days = $conf->{'maildir_clean_Read'};
				if ($days) 
				{
					SysCmd("find $path/Maildir/cur  -type f -mtime +$days -exec rm {} \\;");
				};

				$days = $conf->{'maildir_clean_Unread'};
				if ($days) 
				{
					SysCmd("find $path/Maildir/new  -type f -mtime +$days -exec rm {} \\;");
				};

				$days = $conf->{'maildir_clean_Sent'};
				if ($days) 
				{
					SysCmd("find $path/Maildir/.Sent -type f -mtime +$days -exec rm {} \\;");
				};

				$days = $conf->{'maildir_clean_Trash'};
				if ($days) 
				{
					SysCmd("find $path/Maildir/.Trash -type f -mtime +$days -exec rm {} \\;");
				};

				if ( $conf->{'maildir_clean_Spam_learn'} ) 
				{
					my $salearn = MATT::Utility::FindTheBin("sa-learn");
					croak "No sa-learn found!\n" unless ( -x $salearn);
					SysCmd("$salearn --spam -f $path/Maildir/.Spam");
				};

				$days = $conf->{'maildir_clean_Spam'};
				if ($days) 
				{
					SysCmd("find $path/Maildir/.Spam -type f -mtime +$days -exec rm {} \\;");
				};
			};
		};
		print "done." if $debug;
	};
}
	

1;
__END__

=head1 NAME

Mail::Toaster

=head1 SYNOPSIS

A collection of Perl programs and modules with oodles of code snippets that make working with mail systems much less work.

=head1 DESCRIPTION

A collection of perl scripts and modules that are terribly useful for building and maintaining a mail system. While it was ritten for FreeBSD and a vpopmail based system, it's become quite useful on other platforms and will grow to support other MTA's (think postfix) in the future. 


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>


=head1 BUGS

None known. Report any to matt@tnpi.biz.


=head1 TODO

 Start up daemons as they are installed.
 Dynamically generate the service/*/log/run files via toaster-watcher.conf
 update openssl & courier ssl .cnf files
 install an optional stub DNS resolver (dnscache)


=head1 SEE ALSO

Mail::Toaster::CGI, Mail::Toaster::DNS, 
Mail::Toaster::Logs, Mail::Toaster::Qmail, 
Mail::Toaster::Setup, Mail::Toaster::Watcher


=head1 COPYRIGHT

Copyright 2003, The Network People, Inc. All Rights Reserved.

=cut
