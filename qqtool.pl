#!/usr/bin/perl
use strict;

#
# $Id: qqtool.pl,v 4.4 2005/04/14 21:07:37 matt Exp $
#

=head1 NAME

qqtool.pl - A tool for viewing and purging messages from a qmail queue

=head1 SYNOPSIS

Qmail Queue Tool (qqtool.pl) 

This program will allow you to search and view messages in your qmail queue. It will also allow you to remove them, via expiration or deletion. It was written by Matt Simerson for the toaster users on mail-toaster@simerson.net

ChangeLog - http://www.tnpi.biz/internet/mail/qqtool/changelog.shtml

=head1 DESCRIPTION


=head1 INSTALL

Download Mail::Toaster from http://www.tnpi.biz/internet/mail/toaster/Mail-Toaster.tar.gz

   fetch Mail-Toaster.tar.gz
   tar -xzf Mail-Toaster.tar.gz
   cd Mail-Toaster-x.xx
   perl Makefile.PL
   make install
   rehash

Run the script without any parameters and it will show you a menu of options.

   qqtool.pl

=head2 Sample Output

 # qqtool.pl
          Qmail Queue Tool   v 1.6

   -a  action (delete, expire, list)
   -h  header to match (From, To, Subject, Date)
   -q  queue to search (local/remote)
   -s  search  (pattern to search for)
   -v  verbose

If no -h is specified, then the pattern is searched for in any header. If no -q is specified, then both queues are searched.

To list messages in queue from matt: 

   ./Mail-Toaster/qqtool.pl -a list -s matt -h From

To list messages in queue with string "foo" in the headers:

   ./Mail-Toaster/qqtool.pl -a list -s foo


=head2  User Preferences

There is one settings you can alter:

  $qdir is the path to your qmail queue

If you aren't using the default (/var/qmail/queue), edit qqtool.pl and adjust it.

=cut

my $qdir     = "/var/qmail/queue";


#######################################################################
#      System Settings! Don't muck with anything below this line      #
#######################################################################

my $author = "Matt Simerson";
my $email  = "matt\@tnpi.biz";
my $version = "1.6";

use Getopt::Std;
use vars qw/ $opt_a $opt_h $opt_q $opt_s $opt_v $remotes $locals/;
getopts('a:h:q:s:v');

use Mail::Toaster::Utility 4; my $utility = Mail::Toaster::Utility->new();
use Mail::Toaster::Qmail   4; my $qmail   = Mail::Toaster::Qmail->new();

print "           Qmail Queue Tool   v $version\n\n";

my $qcontrol = $qmail->find_qmail_send_control_dir();

# Make sure the qmail queue directory is set correctly
$qmail->queue_check($qdir, $opt_v);

unless ( $opt_a ) { PrintUsage(); die "\n"; };

if ( $opt_q ) 
{
	# if a queue is specified, only check it.
	if    ($opt_q eq "remote") { $remotes = messages_get("remote"); } 
	elsif ($opt_q eq "local" ) { $locals  = messages_get("local");  };
}
else
{
	# otherwise, check both queues
	$remotes = messages_get("remote");
	$locals  = messages_get("local");
	print "\n";
};

if    ($opt_a eq "list"  ) { messages_list  ($remotes, $locals) }
elsif ($opt_a eq "delete") { messages_delete($remotes, $locals) }
elsif ($opt_a eq "expire") { ExpireMessages($remotes, $locals) }
else                       { PrintUsage(); };

exit 1;

# -----------------------------------------------------------------------------
#       Subroutines. No user servicable parts below this line!                #
# -----------------------------------------------------------------------------

sub PrintUsage
{
	print "	
	-a  action (delete, expire, list)
	-h  header to match (From, To, Subject, Date)
	-q  queue to search (local/remote) 
	-s  search  (pattern to search for)
	-v  verbose
	
	If no -h is specified, then the pattern is searched for in any header.
	If no -q is specified, then both queues are searched.

	To list messages in queue from matt: 
	$0 -a list -s matt -h From

	To list messages in queue with string \"foo\" in the headers:
	$0 -a list -s foo	
";
};

sub message_delete
{
	my ($tree, $id) = @_;

	print "Deleting message $id...";

	# for each message id, check each of the queues and remove it.
	if ( -f "$qdir/local/$tree/$id" ) {
		print "\t deleting file $qdir/local/$tree/$id\n" if ($opt_v);
		unlink "$qdir/local/$tree/$id" or die "couldn't delete: $!";
	};

	if ( -f "$qdir/remote/$tree/$id" ) {
		print "\t deleting file $qdir/remote/$tree/$id\n" if ($opt_v);
		unlink "$qdir/remote/$tree/$id" or die "couldn't delete: $!";
	};

	if ( -f "$qdir/info/$tree/$id" ) {
		print "\t deleting file $qdir/info/$tree/$id\n" if ($opt_v);
		unlink "$qdir/info/$tree/$id" or die "couldn't delete: $!";
	};

	if ( -f "$qdir/mess/$tree/$id" ) {
		print "\t deleting file $qdir/mess/$tree/$id\n" if ($opt_v);
		unlink "$qdir/mess/$tree/$id" or die "couldn't delete: $!";
	};
	
	if ( -f "$qdir/bounce/$id" ) {
		print "\t deleting file $qdir/bounce/$id\n" if ($opt_v);
		unlink "$qdir/bounce/$id" or die "couldn't delete: $!";
	};

	print "done.\n";
};

sub messages_delete
{
	$qmail->check_control($qcontrol);
	
	my $r = $qmail->send_stop();
	die "qmail-send wouldn't die!\n" if ($r);

	# we'll get passed an array of the local, remote, or both queues
	foreach my $q (@_)
	{
		foreach my $hash (@$q)
		{
			my $header = headers_get($hash->{'tree'}, $hash->{'num'});
			
			unless ( $opt_s ) {
				message_delete($hash->{'tree'}, $hash->{'num'});
				next;
			};
			
			if ( $opt_h ) {
				if ($header->{$opt_h} =~ /$opt_s/) 
				{
					message_delete($hash->{'tree'}, $hash->{'num'});
				};
			} else {
				foreach my $key (keys %$header)
				{
					if ( $header->{$key} =~ /$opt_s/ ) 
					{
						message_delete($hash->{'tree'}, $hash->{'num'});
					};
				};
			};
		};
	};
	
	$qmail->send_start();
};

sub ExpireMessage
{
	my ($file) = @_;

	# set $ago to 8 days old.
	my $ago = time - 8 * 24  * 60 * 60;

	# alter the timestamp of the file to 8 days ago.
	utime $ago, $ago, $file;
	print "Expired $file\n";
};

sub ExpireMessages
{
	foreach my $q (@_)
	{
		foreach my $hash (@$q)
		{
			my $header = headers_get($hash->{'tree'}, $hash->{'num'});
			my $id = "$hash->{'tree'}/$hash->{'num'}";
			
			unless ( $opt_s ) 
			{
				ExpireMessage("$qdir/info/$id");
				next;
			};
			
			if ( $opt_h ) 
			{
				if ($header->{$opt_h} =~ /$opt_s/) 
				{
					ExpireMessage("$qdir/info/$id");
				};
			}
			else
			{
				foreach my $key (keys %$header)
				{
					if ( $header->{$key} =~ /$opt_s/ ) 
					{
						ExpireMessage("$qdir/info/$id");
					};
				};
			};
		};
	};
	
	$qmail->queue_process();	

	print "NOTICE: Expiring the messages does not remove them from the queue. 
	It merely alters their expiration time. The messages will be removed from
	the queue after qmail attempts to deliver them one more time. 
	
	I've already told qmail to start that process so be patient while qmail 
	is processing the queue. This might be a good time to check the value of 
	/var/qmail/control/concurrencyremote and verify it's value is reasonable
	for your site.\n\n";	

=head2	Message Expiration

Expiring messages does not remove them from the queue.  It merely alters their expiration time. The messages will be removed from the queue after qmail attempts to deliver them one last time.

=cut

}

sub messages_list
{
	foreach my $q (@_)
	{
		foreach my $hash (@$q)
		{			
			my $header = headers_get($hash->{'tree'}, $hash->{'num'});
			my $id = "$hash->{'tree'}/$hash->{'num'}";
			
			unless ( $opt_s) {
				PrintMessage($id, $header);
				next;
			};

			if ( $opt_h ) 
			{
				PrintMessage($id, $header) if ($header->{$opt_h} =~ /$opt_s/);
			} 
			else {
				foreach my $key (keys %$header)
				{
					if ( $header->{$key} =~ /$opt_s/ ) 
					{
						PrintMessage($id, $header);
						exit;
					};
				};
			};
		};
	};
};

sub PrintMessage
{
	my ($id, $header) = @_;

	print "message # $id ";
	print "to $header->{'To'}\n";
	print "From:     $header->{'From'}\n";
	print "Subject:  $header->{'Subject'}\n";

	if ($opt_v) 
	{
		if ($header->{'CC'}) {
			print "CC:        $header->{'CC'}\n";
		};
		print "Date:      $header->{'Date'}\n";
		my @lines = $utility->file_read("$qdir/info/$id");
		chop $lines[0];
		print "Return Path: $lines[0]\n";
	};
	
	print "\n";
};

sub headers_get
{
	my ($tree, $id) = @_;
	my %hash;

	foreach my $line ( $utility->file_read("$qdir/mess/$tree/$id") )
	{
		if ( $line =~ /^([a-zA-Z\-]*):\s(.*)$/ ) {
			print "header: $line\n" if $opt_v;
			$hash{$1} = $2;
		} else {
			print "body: $line\n" if $opt_v;
		};
	};
	return \%hash;
};

sub messages_get
{
	my ($qsubdir) = @_;
	my $queue = "$qdir/$qsubdir";
	my @messages;
	my ($up1dir, $id, $tree, $queu);
	
	foreach my $dir ( $utility->get_dir_files($queue)) 
	{
		foreach my $file ( $utility->get_dir_files($dir) )
		{
			($up1dir, $id)   = $utility->path_parse($file);
			($up1dir, $tree) = $utility->path_parse($up1dir);
			($up1dir, $queu) = $utility->path_parse($up1dir);

			print "messages_get: id: $id\n" if ($opt_v);

			my %hash = (
				num   => $id,
				file  => $file,
				tree  => $tree,
				queu  => $queu
			);
			push @messages, \%hash;

			print "messages_get: file   : $file\n" if ($opt_v);
		};
	};
	my $count = @messages;
	print "$qsubdir has $count messages\n";

	return \@messages;
};


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>

=head1 CREDITS

Idea based on mailRemove.py by Dru Nelson <dru@redwoodsoft.com>, ideas borrowed from qmHandle by Michele Beltrame <mick@io.com>

Community funding was contributed by the following mail-toaster@simerson.net mailing list subscribers:

 erik erik at microcontroller.nl (organizer)
 Rick Romero  rick at valeoinc.com
 Chris Eaton  Chris.Eaton at med.ge.com
 Marius Kirschner marius at agoron.com
 J. Vicente Carrasco carvay at teleline.es
 Chris Odell  chris at redstarnetworks.net
 Pat Hayes pat at pathayes.net
 Dixon Cole dixon at levee.net
 Randy Meyer rjmeyer at humbleguys.net
 kristian kristian at waveit.com
 Michael Andreasen michael at subwire.dk (beer)
 Nathan Nieblas nnieblas at microtosh.net
 Randy Jordan ctech at pcwarp.com

=head1 BUGS

Report any to author.

=head1 TODO

In list mode, when showing messages in the queue, show which addresses delivery has failed for, so you know exactly why a message is still in the queue (useful for mailing lists with many recipients)

Interactive mode - step through messages offering to delete/expire/skip each

Clean mode - Leave qmail down after stopping it, useful for multiple invocations

Write the messages into a "inactive" queue before deleting them.

Ability to restore messages from "inactive" to the real queue.

=head1 SEE ALSO

http://www.tnpi.biz/internet/mail/toaster/

=head1 COPYRIGHT

Copyright 2003-2005, The Network People, Inc. All Rights Reserved.

=cut
