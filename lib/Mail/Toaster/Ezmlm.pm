#!/usr/bin/perl
use strict;

#
# $Id: Ezmlm.pm,v 4.9 2005/03/24 03:38:35 matt Exp $
#

package Mail::Toaster::Ezmlm;

#use Carp;
use vars qw($VERSION $perl $utility);

$VERSION = '4.6';

use lib "lib";
use lib "../..";
use Mail::Toaster::Utility;         $utility = Mail::Toaster::Utility->new;
eval {require Mail::Toaster::Perl}; $perl    = Mail::Toaster::Perl->new;

sub new;
sub authenticate;
sub process_cgi;
sub process_shell;
sub lists_get;
sub subs_add;
sub subs_list;
sub dir_check;
sub logo;
sub usage;
sub footer;

=head1 NAME

Mail::Toaster::Ezmlm

=head1 SYNOPSIS

Ezmlm perl methods.

=head1 DESCRIPTION

=head1 DEPENDENCIES

some functions depend on Mail::Ezmlm;
authentication depends on "vpopmail" (a perl extension)

If you run ezmlm.cgi suid, then hacks to Mail::Ezmlm are required for "list" to work in taint mode.

=head1 METHODS

=head2 new

Creates a new Mail::Toaster::Ezmlm object.

   use Mail::Toaster::Ezmlm;
   my $ez = Mail::Toaster::Ezmlm;

=cut

sub new
{
	my ($class, $name) = @_;
	my $self = { name => $name };
	bless ($self, $class);
	return $self;
}

=head2 Check_VpopAuth

Authenticates a HTTP user against vpopmail to verify the user has permission to do what they're asking.

=cut

sub authenticate($$;$)
{
	my ($self, $domain, $password, $debug) = @_;

	print "attempting to authenticate postmaster\@$domain..." if $debug;

	$perl->module_load( {module=>"vpopmail", ports_name=>'p5-vpopmail', ports_group=>'mail'} );
	require vpopmail;

	if ( vpopmail::vauth_user('postmaster', $domain, $password, undef) )
	{
		print "ok.<br>" if $debug;
		return 1;
	} else { 
		print "AUTHENTICATION FAILED! (dom: $domain, pass: $password)<br>";
		print "if you are certain the authentication information is correct, then
it's quite likely you can't authenticate because your web server is not running as
a user that has permission to run this script. You can:

  a: run this script suid vpopmail
  b: run the web server as user vpopmail

The easiest and most common methods is:

  chown vpopmail /path/to/ezmlm.cgi
  chmod 4755 /path/to/ezmlm.cgi

\n\n";

		return 0; 
	};
}

=head2 dir_check

Check a directory and see if it's a directory and readable.

    $ezmlm->dir_check($dir);

return 0 if not, return 1 if OK.

=cut

sub dir_check($$;$)
{
	my ($self, $dir, $br, $debug) = @_;

	print "dir_check: checking: $dir..." if $debug;

	unless ( -d $dir && -r $dir ) 
	{
		print "ERROR: No read permissions to $dir: $! $br";
		return 0;
	} else {
		print "ok.$br" if $debug;
		return 1;
	};
};

sub footer($)
{
	shift;  # $self
	my $VERSION = shift;

	print '<hr> <p align="center"><font size="-2">
		<a href="http://www.tnpi.biz/computing/mail/toaster">Mail::Toaster::Ezmlm</a> ', $VERSION, ' -
		&copy; <a href="http://www.tnpi.biz">The Network People, Inc.</a> 1999-2005 <br><br>
        <!--Donated to the toaster community by <a href="mailto:sam.mayes@sudhian.com">Sam Mayes</a>--></font>
     </p>
  </body>
</html>';
};


=head2 lists_get

Get a list of Ezmlm lists for a given mail directory. This is designed to work with vpopmail where all the list for example.com are in ~vpopmail/domains. 

    $ezmlm->lists_get("example.com");

=cut

sub lists_get($$;$)
{
	my ($self, $domain, $br, $debug) = @_;

	my %lists;

	$perl->module_load( {module=>"vpopmail", ports_name=>'p5-vpopmail', ports_group=>'mail'} );
	require vpopmail;

	my $dir = vpopmail::vgetdomaindir($domain);

	unless ( -d $dir ) {
		print "FAILED: invalid directory ($dir) returned from vgetdomaindir $br";
		return 0;
	};

	print "domain dir for $domain: $dir<br>" if $debug;

	print "now fetching a list of ezmlm lists..." if $debug;

	foreach my $all ( $utility->get_dir_files($dir) ) 
	{
		next unless ( -d $all );

		foreach my $second ( $utility->get_dir_files($all) ) 
		{
			next unless ( -d $second );	
			if ( $second =~ /subscribers$/ ) 
			{
				print "found one: $all, $second<br>" if $debug;
				my ($path, $dir) = $utility->path_parse($all);
				print "list name: $dir<br>" if $debug;
				$lists{$dir} = $all;
			} else {
				print "failed second match: $second<br>" if $debug;
			}
		}
	}

	print "done.<br>" if $debug;

	return \%lists;
};


=head2 logo

Put the logo on the HTML page. Sets the URL from $conf.

    $ezmlm->logo($conf);

$conf is values from toaster.conf.

Example: $ezmlm->logo( {
        web_logo_url => 'http://www.tnpi.biz/images/head.jpg',
        web_log_alt  => 'tnpi.biz logo',
    } );

=cut


sub logo
{
	my ($self, $conf) = @_;

	my $logo = $conf->{'web_logo_url'}; $logo ||= "http://www.tnpi.biz/images/head.jpg";
	my $text = $conf->{'web_logo_alt_text'}; $text ||= "tnpi.biz logo";

	return "<img src=\"$logo\" alt=\"$text\">";
};


=head2 process_cgi

Accepts input from HTTP requests, presents a HTML request form, and triggers actions based on input.

   $ez->process_cgi();

=cut

sub process_cgi($$;$)
{
	my ($self, $br, $debug, $list_dir) = @_;

	my ($mess, $ezlists, $authed);
	$br = "<br>";

	use CGI qw(:standard);
	use CGI::Carp qw( fatalsToBrowser );
	print header('text/html');
	#use Mail::Toaster::CGI;

	$perl->module_load( {module=>"HTML::Template", ports_name=>"p5-HTML-Template", ports_group=>"www"} );

	my $conf = $utility->parse_config( {file=>"toaster.conf", debug=>0} );
	#die "FAILURE: Could not find toaster.conf!\n" unless $conf;

	$debug = 0;

	my $cgi = new CGI;

	# get settings from HTML form submission
	my $domain    = param('domain');
	my $password  = param('password');
	my $list_sel  = param('list');
	my $action    = param('action');

	unless ( $list_sel ) { $mess .= " select a list from the menu" };
	unless ( $action   ) { $mess .= " select an action.<br>"      };

	# display create the HTML form
	my $template = HTML::Template->new(filename => 'ezmlm.tmpl');

	$template->param(logo     => $self->logo($conf) );
	$template->param(head     => 'Ezmlm Mailing List Import Tool' );
	$template->param(domain   => '<input name="domain"   type="text" value="' . $domain . '" size="20">');
	$template->param(password => '<input name="password" type="password" value="' . $password . '" size="20">');
	$template->param(action   => '<input name="action"   type="radio" value="list"> List <input name="action" type="radio" value="add">Add <input name="action" type="radio" value="remove"> Remove');

	my $list_of_lists = '<select name="list">';

	if ( $domain && $password )
	{
		print "we got a domain ($domain) & password ($password)<br>" if $debug;

		$authed = $self->authenticate($domain, $password, $debug);

		if ($authed) 
		{
			$ezlists = $self->lists_get($domain, $br, $debug);
			print "WARNING: couldn't retrieve list of ezmlm lists!<br>" unless $ezlists;

			foreach my $key ( keys %$ezlists ) {
				$list_of_lists .= '<option value="' . $key . '">' . $key . '</option>' if $key;
			};
		};
	} 
	else { $mess = "authentication information is missing!<br>"; };

	$list_of_lists .= '</select>';

	$template->param(instruct => $mess );
	$template->param(list     => $list_of_lists );

	print $template->output;

	if ( $action && $list_sel ) 
	{
		unless ($authed) {
			print "skipping processing because authentication failed!<br>";
			exit 0;
		};

		$perl->module_load( {module=>"vpopmail", ports_name=>'p5-vpopmail', ports_group=>'mail'} );
		print "running vpopmail v", vpopmail::vgetversion(), "<br>" if $debug;
#		print "selected list: $list_sel<br>" if $debug;

		$perl->module_load( {module=>"Mail::Ezmlm", ports_name=>"p5-Mail::Ezmlm", ports_group=>"mail"} );
		require Mail::Ezmlm;

		$list_dir = $ezlists->{$list_sel};
		return 0 unless $self->dir_check($list_dir, $br, $debug);
		my $list = new Mail::Ezmlm($list_dir);

		if ( $action eq "list" )
		{
			$self->subs_list($list, $list_dir, $br, $debug );
		}
		elsif ( $action eq "add" )
		{
			my @reqs = split("\n", param('addresses') );
			print "reqs: @reqs<br>" if $debug;
			my $requested = \@reqs;
			$self->subs_add($list, $list_dir, $requested, $br);
		}
		else
		{
			print "Sorry, action $action is not supported yet.<br>";
		}
	}
	else
	{
		print "missing auth, action, or lists<br>";
	};

	$self->footer($VERSION);
}

=head2 process_shell

Get input from the command line options and proceed accordingly.

=cut

sub process_shell()
{
	my ($self) = @_;
	use vars qw($opt_a $opt_d $opt_f $opt_v $list $debug);

	$perl->module_load( {module=>"Mail::Ezmlm", ports_name=>"p5-Mail::Ezmlm", ports_group=>"mail"} );
	require Mail::Ezmlm;

	use Getopt::Std;
	getopts('a:d:f:v');

	my $br = "\n";
	$opt_v ? $debug = 1 : $debug = 0;

	# set up based on command line options
	my $list_dir;
	$list_dir = $opt_d if $opt_d;

	# set a default list dir if not already set
	unless ( $list_dir ) {
		$list_dir = "/usr/local/vpopmail/domains/simerson.net/friends";
		print "You didn't set the list directory! Use the -d options!\n";
	};
	return 0 unless $self->dir_check($list_dir, $br, $debug);

	if ( $opt_a && $opt_a eq "list" )
	{
		$list = new Mail::Ezmlm($list_dir);
		$self->subs_list($list, $list_dir, $br, $debug );
		return 1;
	};

	unless ($opt_a && $opt_a eq "add") {
		usage(); return 0;
	};

	# since we're adding, fetch a list of email addresses
	my $requested;
	my $list_file = $opt_f; $list_file ||= "ezmlm.importme";

	unless ( -e $list_file ) 
	{
		print "FAILED: cannot find $list_file!\n Try specifying it with -f.\n";
		return 0;
	};

	if ( -r $list_file ) {
		my @lines = $utility->file_read($list_file);
		$requested = \@lines;
	} else {
		print "FAILED: $list_file not readable!\n";
		return 0;
	}

	$list = new Mail::Ezmlm($list_dir);
	#$list->setlist($list_dir);    # use this to switch lists

	$self->subs_add($list, $list_dir, $requested, $br);

	return 1;
};

=head2 subs_add

Subcribe a user (or list of users) to a mailing list.

   $ezmlm->subs_add($list_name, $list_dir, $address_list);

=cut

sub subs_add($$$$)
{
	my ($self, $list, $list_dir, $requested, $br) = @_;

	my ($duplicates, $success, $failed, @list_dups, @list_success, @list_fail);

	print "$br";

	unless ($requested && $requested->[0] ) {
		print "FAILURE: no list of addresses was supplied! $br";
		exit 0;
	};

	foreach my $addy ( @$requested ) 
	{
		$addy = lc($addy);                 # convert it to lower case
		chomp($addy);
		($addy) = $addy =~ /([a-z0-9\.\-\@]*)/;

		printf "adding %25s...", $addy;

		use Email::Valid;
		unless ( Email::Valid->address($addy) )
		{
			print "FAILED! (address fails $Email::Valid::Details check). $br";
			$failed++;
			next;
		};

		if ( $list->issub($addy) )
		{
			$duplicates++;
			push @list_dups, $addy;
			print "FAILED (duplicate). $br";
		} 
		else 
		{
			if ( $list->sub($addy) ) {
				print "ok. $br";
				$success++;
			} else {
				print "FAILED! $br";
				$failed++;
			};
		};
	};

	print " $br $br --- STATISTICS ---  $br $br";
	printf "duplicates...%5d  $br", $duplicates;
	printf "success......%5d  $br", $success;
	printf "failed.......%5d  $br", $failed;
};

=head2 subs_list

Print out a list of subscribers to an Ezmlm mailing list.

    $ezmlm->subs_list($list, $list_dir);

=cut

sub subs_list($$$;$)
{
	my ($self, $list, $list_dir, $br, $debug) = @_;

	print "subs_list: listing subs for list $list_dir $br" if $debug;

#	print "subscriber list: ";
#	$list->list;                 # list subscribers
#	#$list->list(\*STDERR);       # list subscribers
#	"\n";

	print "subs_list: getting list of subscribers...$br$br" if $debug;

	foreach my $sub ( $list->subscribers )
	{
		print "$sub $br";
	};

	print "$br done. $br";
};

sub usage
{
	print "\n$0 -a [ add | remove | list ]

     -a   action  - add, remove, list
     -d   dir     - ezmlm list directory
     -f   file    - file containing list of email addresses
     -v   verbose - print debugging options\n\n
";
};


1;
__END__


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>
Funded by Sam Mayes (sam.mayes@sudhian.com) and donated to the toaster community


=head1 BUGS

None known. Report any to author.


=head1 TODO

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


Mail::Toaster

=head1 COPYRIGHT

Copyright (c) 2005, The Network People, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

