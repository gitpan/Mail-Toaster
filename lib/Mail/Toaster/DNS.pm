#!/usr/bin/perl
use strict;

#
# $Id: DNS.pm,v 4.1 2004/11/16 21:20:01 matt Exp $
#

package Mail::Toaster::DNS;

use Carp;
use vars qw($VERSION);

$VERSION = '4.00';

use lib "lib";
use lib "../..";


=head1 NAME

Mail::Toaster::DNS

=head1 SYNOPSIS

Common DNS functions

=head1 DESCRIPTION

These functions are used by toaster-watcher to determine if RBL's are available when generating qmail's smtpd/run control file.

=head2 new

Create a new DNS method:

   use Mail::Toaster::DNS;
   my $dns = new Mail::Toaster::DNS;

=cut

sub new
{
	my $class = shift;
	my $self = { class=>$class };
	bless ($self, $class);
	return $self;
}


=head2 rbl_test

After the demise of osirusoft and the DDoS attacks currently under way against RBL operators, this little subroutine becomes one of necessity for using RBL's on mail servers. It is called by the toaster-watcher.pl script to test the RBLs before including them in the SMTP invocation.

	my $r = $dns->rbl_test("bl.example.com");
	if ($r) { print "bl tests good!" };

The routine expects to receive the zone of a blacklist to test as it's first argument and a possible debug value (set to a non-zero value) as it's second. 

It will then test to make sure that name servers are found for the zone and then run several test queries against the zone to verify that the answers it returns are sane. We want to detect if a RBL operator does something like whitelist or blacklist the entire planet.

If the blacklist fails any test, the sub willl return zero and you should not use that blacklist.

=cut

sub rbl_test
{
	my ($self, $zone, $debug) = @_;
	use Mail::Toaster::Perl; my $perl = Mail::Toaster::Perl->new;
	$perl->module_load( {module=>"Net::DNS", ports_name=>"p5-Net-DNS", ports_group=>"dns"} );

	my $res  = Net::DNS::Resolver->new;

	$res->tcp_timeout(5);   # really shouldn't matter
	$res->udp_timeout(5);

	# First we make sure their zone has active name servers

	my $ns    = 0;
	my $query = $res->query( $self->rbl_test_ns($zone), "NS");

	if ( $query )
	{
		foreach my $rr ( $query->answer ) 
		{
			next unless ($rr->type eq "NS");
			$ns++;
#			print "$zone ns: ", $rr->nsdname, "\n" if $debug;
		};
	} 
	else 
	{ 
		carp "ns query failed for $zone: ", $res->errorstring if $debug;
		return 0; 
	};

	return 0 unless ($ns > 0);
	print "good, we have $ns NS servers, we can go on.\n" if $debug;

	# then we test an IP that should always return an A record
	# for most RBL's this is 127.0.0.2, (2.0.0.127.bl.example.com)

	my $ip      = 0;
	my $test_ip = $self->rbl_test_positive_ip($zone);

	if ( $test_ip =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/ )
	{
		my $test = "$4.$3.$2.$1.$zone";

		print "querying $test..." if $debug;

		my $query = $res->query($test, "A" );
		if ( $query )
		{
			foreach my $rr ( $query->answer )
			{
				print "found: ", $rr->type, " = ", $rr->address if $debug;
				next unless $rr->type eq "A";
				next unless $rr->address =~ /127\.0\.0/;
				$ip++;
				# print " from ", $query->answerfrom if $debug;
				print " matched.\n" if $debug;
			};
		} 
		else 
		{ 
			carp "query failed for $zone: ", $res->errorstring if $debug;
			return 0;
		};
	} 
	else 
	{ 
		print "hrmmm, $test_ip didn't match an IP address format" if $debug;
		return 0;
	};

	return 0 unless ($ip > 0);
	print "good, we have $ip addresses, we can go on.\n" if $debug;


	# Now we test an IP that should always yield a negative response

	my $fip    = 0;
	$test_ip   = $self->rbl_test_negative_ip($zone);

	if ( $test_ip =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/ )
	{
		my $test = "$4.$3.$2.$1.$zone";

		print "querying $test..." if $debug;

		my $query = $res->query($test, "A" );
		return 1 unless $query;  # it's OK if this fails

		foreach my $rr ( $query->answer )
		{
			print "found: ", $rr->type, " = ", $rr->address if $debug;
			next unless $rr->type eq "A";
			next unless $rr->address =~ /127\.0\.0/;
			$ip++;
			# print " from ", $query->answerfrom if $debug;
			print " matched.\n" if $debug;
		};
	} 
	else 
	{ 
		carp "hrmmm, $test_ip didn't match an IP address format" if $debug;
		return 0;
	};

	if ( $fip > 0 ) { return 0 } else { return 1 };
};


=head2 rbl_test_ns

	$t_dns->rbl_test_ns($rbl);

$rbl is the reverse zone we use to test this rbl.

=cut

sub rbl_test_ns
{
	my ($self, $rbl) = @_;

	if    ( $rbl eq "korea.services.net"     ) { return "69.$rbl" } 
	elsif ( $rbl =~ /rbl\.cluecentral\.net$/ ) { return "rbl.cluecentral.net" } 
	else                                       { return $rbl };
};


=head2 rbl_test_positive_ip

	$t_dns->rbl_test_positive_ip($rbl);

$rbl is the reverse zone we use to test this rbl. Positive test is a test that should always return a RBL match. If it should and doesn't, then we assume that RBL has been disabled by it's operator.

Some RBLs have test IP's to verify they are working. For geographic RBLs (like korea.services.net) we can simply choose any IP within their allotted space. Most other RBLs use 127.0.0.2 as a positive test.

=cut

sub rbl_test_positive_ip
{
	my ($self, $rbl) = @_;

	if    ( $rbl eq "korea.services.net"     ) { return "61.96.1.1"    } 
	elsif ( $rbl eq "kr.rbl.cluecentral.net" ) { return "61.96.1.1"    }
	elsif ( $rbl eq "cn.rbl.cluecentral.net" ) { return "210.52.214.8" }
	else                                       { return "127.0.0.2"    };
};

sub rbl_test_negative_ip
{

=head2 rbl_test_negative_ip

	$t_dns->rbl_test_negative_ip($rbl);

This test is a little more difficult as RBL operators don't typically have an IP that's whitelisted. The DNS location based lists are very easy to test negatively. For the rest I'm listing my own IP as the default unless the RBL has a specific one. At the very least, my site won't get blacklisted that way. ;) I'm open to better suggestions.

=cut

	my ($self, $rbl) = @_;

	if    ( $rbl eq "korea.services.net"     ) { return "207.89.154.94"  } 
	elsif ( $rbl eq "kr.rbl.cluecentral.net" ) { return "207.89.154.94"  }
	elsif ( $rbl eq "cn.rbl.cluecentral.net" ) { return "207.89.154.94"  }
	elsif ( $rbl eq "us.rbl.cluecentral.net" ) { return "210.52.214.8"   }
	else                                       { return "207.89.154.94"  };
};


1;
__END__


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>


=head1 BUGS

None known. Report any to author.


=head1 TODO

=head1 SEE ALSO

http://www.tnpi.biz/computing/

  Mail::Toaster::CGI, Mail::Toaster::DNS, 
  Mail::Toaster::Logs, Mail::Toaster::Qmail, 
  Mail::Toaster::Setup


=head1 COPYRIGHT

Copyright (c) 2004, The Network People, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

