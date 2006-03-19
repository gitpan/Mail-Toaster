#!/usr/bin/perl
use strict;

#
# $Id: DNS.pm,v 4.10 2006/03/18 20:13:21 matt Exp $
#

package Mail::Toaster::DNS;

use Carp;
use vars qw($VERSION);

$VERSION = '4.07';

use lib "lib";
use lib "../..";

use Mail::Toaster::Utility; my $utility = Mail::Toaster::Utility->new;
my $dig = $utility->find_the_bin("dig");

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

	my $r = $dns->rbl_test($conf, "bl.example.com");
	if ($r) { print "bl tests good!" };

The routine expects to receive the zone of a blacklist to test as it's first argument and a possible debug value (set to a non-zero value) as it's second. 

It will then test to make sure that name servers are found for the zone and then run several test queries against the zone to verify that the answers it returns are sane. We want to detect if a RBL operator does something like whitelist or blacklist the entire planet.

If the blacklist fails any test, the sub willl return zero and you should not use that blacklist.

=cut

sub rbl_test
{
	my ($self, $conf, $zone, $debug) = @_;

#	$net_dns->tcp_timeout(5);   # really shouldn't matter
#	$net_dns->udp_timeout(5);

	# First we make sure their zone has active name servers
	return 0 unless $self->rbl_test_ns($conf, $zone, $debug);

	# then we test an IP that should always return an A record
	# for most RBL's this is 127.0.0.2, (2.0.0.127.bl.example.com)
	return 0 unless $self->rbl_test_positive_ip($conf, $zone, $debug);

	# Now we test an IP that should always yield a negative response
	return 0 unless $self->rbl_test_negative_ip($conf, $zone, $debug);

	return 1;
};


=head2 rbl_test_ns

	my $count = $t_dns->rbl_test_ns($conf, $rbl, $debug);

$rbl is the reverse zone we use to test this rbl.

This script requires a zone name. It will then return a count of how many NS records exist for that zone. This sub is used by the rbl tests. Before we bother to look up addresses, we make sure valid nameservers are defined.

=cut

sub rbl_test_ns
{
	my ($self, $conf, $rbl, $debug) = @_;

	my $ns = 0;
	my $testns = $rbl;

	if    ( $rbl =~ /rbl\.cluecentral\.net$/ ) { $testns = "rbl.cluecentral.net" }
	elsif ( $rbl eq "spews.blackhole.us"     ) { $testns = "ls.spews.dnsbl.sorbs.net" }
	elsif ( $rbl =~ /\.dnsbl\.sorbs\.net$/   ) { $testns = "dnsbl.sorbs.net"     }

	if ( $conf && $conf->{'rbl_enable_lookup_using'} && $conf->{'rbl_enable_lookup_using'} eq "dig" && -x $dig )    # dig is installed
	{
		foreach (`$dig ns $testns +short`) { $ns++; print "rbl_test_ns: found $_\n" if $debug; };
	} 
	else 
	{
		require Mail::Toaster::Perl; my $perl = Mail::Toaster::Perl->new;
		$perl->module_load( {module=>"Net::DNS", ports_name=>"p5-Net-DNS", ports_group=>"dns"} );
		my $net_dns  = Net::DNS::Resolver->new;

		my $query = $net_dns->query( $testns, "NS");
		unless ( $query ) {
			carp "ns query failed for $rbl: ", $net_dns->errorstring if $debug;
			return 0;
		};

		foreach ( $query->answer )
		{
			next unless ($_->type eq "NS");
			$ns++;
			print "$rbl ns: ", $_->nsdname, "\n" if $debug;
		}
	}

	print "rbl_test_ns: found $ns NS servers.\n" if $debug;
	$ns > 0 ? return 1 : return 0;
};


=head2 rbl_test_positive_ip

	$t_dns->rbl_test_positive_ip($conf, $rbl);

$rbl is the reverse zone we use to test this rbl. Positive test is a test that should always return a RBL match. If it should and doesn't, then we assume that RBL has been disabled by it's operator.

Some RBLs have test IP's to verify they are working. For geographic RBLs (like korea.services.net) we can simply choose any IP within their allotted space. Most other RBLs use 127.0.0.2 as a positive test.

In the case of rfc-ignorant.org, they have no known test IPs and thus we have to skip testing them.

=cut

sub rbl_test_positive_ip
{
	my ($self, $conf, $rbl, $debug) = @_;

	my $ip      = 0;
	my $test_ip = $rbl;

	if    ( $rbl eq "korea.services.net"     ) { $test_ip = "61.96.1.1"    } 
	elsif ( $rbl eq "kr.rbl.cluecentral.net" ) { $test_ip = "61.96.1.1"    }
	elsif ( $rbl eq "cn-kr.blackholes.us"    ) { $test_ip = "61.96.1.1"    }
	elsif ( $rbl eq "cn.rbl.cluecentral.net" ) { $test_ip = "210.52.214.8" }
	elsif ( $rbl =~ /rfc-ignorant\.org$/     ) { return 1;                 } # no test ips!
	else                                       { $test_ip = "127.0.0.2"    };

	unless ( $test_ip =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/ )
	{
		print "hrmmm, $test_ip didn't match an IP address format" if $debug;
		return 0;
	};

	my $test = "$4.$3.$2.$1.$rbl";

	print "querying $test..." if $debug;

	if ( $conf && $conf->{'rbl_enable_lookup_using'} && $conf->{'rbl_enable_lookup_using'} eq "dig" && -x $dig )    # dig is installed
	{
		foreach (`$dig a $test +short`) { $ip++; print "rbl_test_pos: found $_\n" if $debug; };
	} 
	else 
	{
		require Mail::Toaster::Perl; my $perl = Mail::Toaster::Perl->new;
		$perl->module_load( {module=>"Net::DNS", ports_name=>"p5-Net-DNS", ports_group=>"dns"} );
		my $net_dns  = Net::DNS::Resolver->new;
		my $query = $net_dns->query($test, "A" );
		if ( $query )
		{
			foreach my $rr ( $query->answer )
			{
				print "found: ", $rr->type, " = ", $rr->address if $debug;
				next unless $rr->type eq "A";
				next unless $rr->address =~ /127\.[0-1]\.0/;
				$ip++;
				print " from ", $query->answerfrom if $debug;
				print " matched.\n" if $debug;
			};
		} 
		else 
		{ 
			carp "query failed for $rbl: ", $net_dns->errorstring if $debug;
			return 0;
		};
	}

	print "rbl_test_positive_ip: we have $ip addresses.\n" if $debug;
	$ip > 0 ? return $ip : return 0;
};


=head2 rbl_test_negative_ip

	$t_dns->rbl_test_negative_ip($conf, $rbl);

This test is a little more difficult as RBL operators don't typically have an IP that's whitelisted. The DNS location based lists are very easy to test negatively. For the rest I'm listing my own IP as the default unless the RBL has a specific one. At the very least, my site won't get blacklisted that way. ;) I'm open to better suggestions.

=cut

sub rbl_test_negative_ip
{
	my ($self, $conf, $rbl, $debug) = @_;

	my $test_ip = $rbl;

	if    ( $rbl eq "korea.services.net"     ) { $test_ip = "69.39.74.33"  } 
	elsif ( $rbl eq "kr.rbl.cluecentral.net" ) { $test_ip = "69.39.74.33"  }
	elsif ( $rbl eq "cn.rbl.cluecentral.net" ) { $test_ip = "69.39.74.33"  }
	elsif ( $rbl eq "us.rbl.cluecentral.net" ) { $test_ip = "210.52.214.8" }
	else                                       { $test_ip = "69.39.74.33"  };

	my $fip    = 0;

	unless ( $test_ip =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/ )
	{
		carp "hrmmm, $test_ip didn't match an IP address format" if $debug;
		return 0;
	};

	my $test = "$4.$3.$2.$1.$rbl";

	print "querying $test..." if $debug;

	if ( $conf && $conf->{'rbl_enable_lookup_using'} && $conf->{'rbl_enable_lookup_using'} eq "dig" && -x $dig )    # dig is installed
	{
		foreach (`dig a $test +short`) { $fip++; };
	} 
	else 
	{
		require Mail::Toaster::Perl; my $perl = Mail::Toaster::Perl->new;
		$perl->module_load( {module=>"Net::DNS", ports_name=>"p5-Net-DNS", ports_group=>"dns"} );
		my $net_dns  = Net::DNS::Resolver->new;

		my $query = $net_dns->query($test, "A" );
		return 1 unless $query;  # it's OK if this fails
	
		foreach my $rr ( $query->answer )
		{
			print "found: ", $rr->type, " = ", $rr->address if $debug;
			next unless $rr->type eq "A";
			next unless $rr->address =~ /127\.0\.0/;
			$fip++;
			# print " from ", $query->answerfrom if $debug;
			print " matched.\n" if $debug;
		};
	};

	$fip > 0 ? return 0 : return 1;
};


1;
__END__


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>


=head1 BUGS

None known. Report any to author.


=head1 TODO

=head1 SEE ALSO

The following man/perldoc pages: 

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

