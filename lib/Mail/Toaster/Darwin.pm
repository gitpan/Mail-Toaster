#!/usr/bin/perl
use strict;

#
# $Id: Darwin.pm,v 4.1 2004/11/16 21:20:01 matt Exp $
#

package Mail::Toaster::Darwin;

use Carp;
use vars qw($VERSION);
$VERSION = '4.0';

use lib "lib";
use lib "../..";
use Mail::Toaster::Utility; my $utility = Mail::Toaster::Utility->new();

=head1 NAME

Mail::Toaster::Darwin

=head1 SYNOPSIS

Mac OS X (Darwin) scripting functions

=head1 DESCRIPTION

functions I've written for perl scripts running on MacOS X (Darwin) systems.

Usage examples for each subroutine are included.

=head2 new

    use Mail::Toaster::Darwin;
	my $darwin = new Mail::Toaster::Darwin;

=cut

sub new
{
	my $class = shift;
	my $self = { class=>$class };
	bless ($self, $class);
	return $self;
}

=head2 ports_update

Updates the Darwin Ports tree (/usr/ports/dports/*).

	$darwin->ports_update();

=cut

sub ports_update
{
	print "\n\nports_update: You might want to update your ports tree!\n\n";

	if( $utility->yes_or_no( "\n\nWould you like me to do it for you?:") )
	{   
		my $cvsbin = $utility->find_the_bin("cvs");

		print "Updating Darwin ports...\n";
		if ( -d "/usr/ports/dports" ) 
		{
			chdir("/usr/ports/dports");
			if ( -x "/opt/local/bin/portindex") 
			{
				$utility->syscmd("/opt/local/bin/portindex");
			} 
			elsif ( -x "/usr/local/bin/portindex" ) 
			{
				$utility->syscmd("/usr/local/bin/portindex");
			};
			$utility->syscmd("$cvsbin -z3 update -dP");
		} 
		else {
			print "FAILED! I expect to find your dports dir in /usr/ports/dports. Please install it there or add a symlink there pointing to where you have your Darwin ports installed.\n";
		};
	};
};

sub port_install($)
{

=head2 port_install

	$darwin->port_install("openldap2");

That's it. Really. Honest. Nothing more. 

=cut

	my ($self, $name) = @_;

#	$self->ports_check_age("30");

	print "port_install: installing $name...";

	my $port = $utility->find_the_bin("port");

	unless ( -x $port )
	{
		print "FAILED: please install DarwinPorts!\n";
		return 0;
	};

	my $r = $utility->syscmd( "$port install $name");
#	$utility->syscmd( "port clean $name");
	return $r;
};

sub ports_check_age($;$)
{
	my ($self, $age, $url) = @_;

	$url |= "http://www.tnpi.biz/internet/mail/toaster";

	if ( -M "/usr/ports" > $age )
	{
		$self->ports_update();
	}
	else
	{
		print "ports_check_age: Ports file is current (enough).\n";
	};
};


1;
__END__


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>

=head1 BUGS

None known. Report any to author.

=head1 TODO

Needs more documentation.

=head1 SEE ALSO

 http://www.tnpi.biz/internet/mail/toaster
 http://www.tnpi.biz/internet/mail/toaster/docs/

Mail::Toaster::Apache, Mail::Toaster::DNS, Mail::Toaster::FreeBSD, Mail::Toaster::Mysql,
Mail::Toaster::Passwd, Mail::Toaster::Perl, Mail::Toaster::Quota, Mail::Toaster::Utility


=head1 COPYRIGHT

Copyright (c) 2003-2004, The Network People, Inc. All Rights Reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut
